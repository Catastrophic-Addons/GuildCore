-- /GuildCore/Modules/Invite/Realm.lua
-- Realm detection for Invite scanner.
-- Anchors WHO scans to the guild's registered realm and connected realms.
--
-- Fallback order for scan anchor:
--   1. Guild's registered/home realm (from guild roster header or GetGuildInfo)
--   2. Player's current realm from GetNormalizedRealmName / GetRealmName
--   3. Abort scan with a clear warning if neither resolves
--
-- Requires in-game testing:
--   - GetGuildInfo() availability and guild realm field accuracy varies by build.
--   - C_RealmList connected-realm enumeration may not be available on all builds.
--   - WHO r-"RealmName" filter syntax requires verification on Retail / Midnight.
--   - GetAutoCompleteRealms() is the most reliable connected-realm API on Retail;
--     verify it returns the guild's realm's connected realms, not just the player's.

local addonName, ns = ...
local GC = ns.GuildCore

GC.Modules.Invite       = GC.Modules.Invite       or {}
GC.Modules.Invite.Realm = GC.Modules.Invite.Realm or {}

local Realm = GC.Modules.Invite.Realm
local cachedGuildRealm = nil
local cachedGuildKey = nil

local DEFAULT_SCAN_CLASSES = {
    "Warrior",
    "Paladin",
    "Hunter",
    "Rogue",
    "Priest",
    "Death Knight",
    "Shaman",
    "Mage",
    "Warlock",
    "Monk",
    "Druid",
    "Demon Hunter",
    "Evoker",
}

local DEFAULT_LEVEL_BANDS = {
    { min = 75, max = 90 },
    { min = 50, max = 74 },
    { min = 25, max = 49 },
    { min = 1, max = 24 },
}

local MAIN_REALMS = {
    "Hellscream",
    "Gorefiend",
    "Spinebreaker",
    "Zangarmarsh",
    "Wildhammer",
    "Eredar",
}

local HELLSCREAM_CONNECTED_REALMS = {
    "Hellscream",
    "Gorefiend",
    "Spinebreaker",
    "Zangarmarsh",
    "Wildhammer",
    "Eredar",
}

local MAIN_REALM_SET = {}
for _, realm in ipairs(MAIN_REALMS) do
    MAIN_REALM_SET[realm:lower()] = realm
end

-- ── Internal helpers ───────────────────────────────────────────────────────

local function normalizeRealm(name)
    if not name or name == "" then return nil end
    -- Strip spaces; realm names in WHO queries use no spaces on some builds.
    -- Requires in-game testing: space handling in r-"Realm Name" filter.
    return tostring(name):match("^%s*(.-)%s*$")
end

local function canonicalMainRealm(name)
    local realm = normalizeRealm(name)
    if not realm then return nil end
    return MAIN_REALM_SET[realm:lower()]
end

local function settingRealmOverride(settings)
    local realm = canonicalMainRealm(settings and settings.guildRealmOverride)
    if realm then
        return realm
    end
    return nil
end

local function inviteSettings()
    local svc = GC.Services and GC.Services.Invite
    local storage = svc and svc.GetStorage and svc:GetStorage()
    return storage and storage.settings or {}
end

local function appendExtraFilter(query, extraFilter)
    extraFilter = extraFilter and GC.Utils.Trim(extraFilter) or ""
    if extraFilter == "" then
        return query
    end
    return query .. " " .. extraFilter
end

-- Requires in-game testing: all WHO realm query syntax is server interpreted
-- and may vary across Retail/Midnight builds.
local function realmQueryForMode(realm, mode)
    mode = tostring(mode or "safe")

    if mode == "safe" then
        return string.format('r-"%s"', realm), "r-quoted"
    end

    -- Unknown persisted values fall back to the conservative quoted realm form.
    return string.format('r-"%s"', realm), "r-quoted"
end

local function scanClasses(settings)
    if type(settings.scanClasses) == "table" and #settings.scanClasses > 0 then
        return settings.scanClasses
    end
    return DEFAULT_SCAN_CLASSES
end

local function scanLevels(settings)
    local apiMax = (GetMaxPlayerLevel and tonumber(GetMaxPlayerLevel())) or 90
    local minLevel = math.max(1, math.floor(tonumber(settings.scanLevelMin) or 1))
    local maxLevel = math.max(minLevel, math.floor(tonumber(settings.scanLevelMax) or apiMax))
    return minLevel, maxLevel
end

local function scanQueryMode(settings)
    local mode = tostring(settings.scanQueryMode or "adaptive-level-range")
    if mode == "adaptive-level-range" or mode == "class-level-local-realm" or mode == "level-band-local-realm" then
        return mode
    end
    return "adaptive-level-range"
end

local function scanLevelBands(settings)
    local apiMax = (GetMaxPlayerLevel and tonumber(GetMaxPlayerLevel())) or 90
    local source = type(settings.scanLevelBands) == "table" and settings.scanLevelBands or DEFAULT_LEVEL_BANDS
    local bands = {}
    local minLevel = nil
    local maxLevel = nil

    for _, band in ipairs(source) do
        if type(band) == "table" then
            local bandMin = math.max(1, math.floor(tonumber(band.min) or 1))
            local bandMax = math.max(bandMin, math.floor(tonumber(band.max) or apiMax))

            -- Do not hardcode 90 forever: when the saved/default final band is
            -- still the Midnight fallback, extend it to the live API max level.
            if tonumber(band.max) == 90 and apiMax > 90 then
                bandMax = apiMax
            end

            if bandMin <= bandMax then
                bands[#bands + 1] = { min = bandMin, max = bandMax }
                minLevel = minLevel and math.min(minLevel, bandMin) or bandMin
                maxLevel = maxLevel and math.max(maxLevel, bandMax) or bandMax
            end
        end
    end

    if #bands == 0 then
        bands[1] = { min = 1, max = apiMax }
        minLevel = 1
        maxLevel = apiMax
    end

    return bands, minLevel, maxLevel
end

local function currentGuildCacheKey()
    local guildName = GetGuildInfo and GetGuildInfo("player") or nil
    if not guildName or guildName == "" then
        return nil
    end
    return tostring(guildName)
end

local function cacheGuildRealm(realm)
    realm = normalizeRealm(realm)
    local key = currentGuildCacheKey()
    if realm and key then
        cachedGuildRealm = realm
        cachedGuildKey = key
    end
    return realm
end

-- ── GetGuildRealm ──────────────────────────────────────────────────────────
-- Returns the guild's registered home realm name, or nil.
-- Primary source: GetGuildInfo() which includes a realm field on cross-realm
-- capable builds. Falls back to extracting realm from guild master's full name
-- if available.
--
-- Requires in-game testing: GetGuildInfo() realm field presence on Retail/Midnight.
function Realm.GetGuildRealm()
    local cacheKey = currentGuildCacheKey()
    if cachedGuildRealm and cachedGuildKey and cacheKey == cachedGuildKey then
        GC:InviteDebug("debug", "Invite Realm: using cached guild realm:", cachedGuildRealm)
        return cachedGuildRealm
    end

    -- Attempt 1: GetGuildInfo() - field 4 on Retail is the realm.
    -- Requires in-game testing: field index varies; log all returned values.
    if GetGuildInfo then
        local f1, f2, f3, f4, f5, f6 = GetGuildInfo("player")
        GC:InviteDebug("debug", string.format(
            "Invite Realm: GetGuildInfo fields: [%s][%s][%s][%s][%s][%s]",
            tostring(f1), tostring(f2), tostring(f3),
            tostring(f4), tostring(f5), tostring(f6)
        ))
        -- Try each field that looks like a realm name (non-nil, non-numeric, not rank/index).
        for _, v in ipairs({ f4, f5, f6 }) do
            if type(v) == "string" and v ~= "" and not tonumber(v) then
                GC:InviteDebug("debug", "Invite Realm: guild realm from GetGuildInfo:", v)
                return cacheGuildRealm(v)
            end
        end
        if not f1 then
            GC:InviteDebug("debug", "Invite Realm: GetGuildInfo returned nil - player may not be in a guild.")
        else
            GC:InviteDebug("debug", "Invite Realm: GetGuildInfo returned no usable realm field.")
        end
    else
        GC:InviteDebug("debug", "Invite Realm: GetGuildInfo API is not available.")
    end

    -- Attempt 2: Scan guild roster for the guild master's full name realm suffix.
    -- Requires in-game testing: GuildRoster() may need to be called first to refresh.
    if GetNumGuildMembers then
        local total = GetNumGuildMembers()
        GC:InviteDebug("debug", "Invite Realm: checking guild roster for realm suffix. members=" .. tostring(total))
        for i = 1, math.min(total, 20) do
            local name, rankName, rankIndex = GetGuildRosterInfo(i)
            if name then
                local shortName, realm = name:match("^([^%-]+)%-(.+)$")
                local canonical = realm and canonicalMainRealm(realm) or nil
                if canonical then
                    GC:InviteDebug("debug", string.format(
                        "Invite Realm: found canonical realm suffix in member name [%s]: %s",
                        name, canonical
                    ))
                    return cacheGuildRealm(canonical)
                end
            end
        end
        GC:InviteDebug("debug", "Invite Realm: no member names had a realm suffix (cross-realm data may not be cached).")
    else
        GC:InviteDebug("debug", "Invite Realm: GetNumGuildMembers API is not available.")
    end

    GC:InviteDebug("debug", "Invite Realm: guild realm could not be determined.")
    return nil
end

function Realm.GetMainRealmOptions()
    local out = {}
    for _, realm in ipairs(MAIN_REALMS) do
        out[#out + 1] = realm
    end
    return out
end

function Realm.NormalizeMainRealm(name)
    return canonicalMainRealm(name)
end

-- ── GetPlayerRealm ─────────────────────────────────────────────────────────
-- Returns the player's current realm name. Used only as a fallback.
function Realm.GetPlayerRealm()
    local realm = (GetNormalizedRealmName and GetNormalizedRealmName())
               or (GetRealmName and GetRealmName())
               or nil
    return normalizeRealm(realm)
end

-- ── GetConnectedRealmsForGuildRealm ────────────────────────────────────────
-- Returns a list of realm name strings connected to the given guildRealm.
-- Includes guildRealm itself as the first entry.
--
-- Requires in-game testing:
--   - GetAutoCompleteRealms() returns connected realms for the PLAYER's realm.
--     If the guild is on a different realm, this list may not match.
--   - C_RealmList.GetRealmListInfo() is not available on all builds.
--   - On Midnight, connected realm APIs may differ significantly.
function Realm.GetConnectedRealmsForGuildRealm(guildRealm)
    if not guildRealm then return {} end

    local mainRealm = canonicalMainRealm(guildRealm)
    if mainRealm then
        local realms = {}
        for _, realm in ipairs(HELLSCREAM_CONNECTED_REALMS) do
            realms[#realms + 1] = realm
        end
        return realms
    end

    local realms = { guildRealm }
    local seen   = { [guildRealm:lower()] = true }

    -- GetAutoCompleteRealms: available on Retail, returns connected realm names.
    -- Requires in-game testing: whether this returns the guild realm's connected
    -- realms or only the player's realm's connected realms.
    if GetAutoCompleteRealms then
        local connected = GetAutoCompleteRealms()
        if type(connected) == "table" then
            for _, r in ipairs(connected) do
                local norm = normalizeRealm(r)
                if norm and not seen[norm:lower()] then
                    seen[norm:lower()] = true
                    realms[#realms + 1] = norm
                end
            end
        end
    end

    if #realms == 1 then
        GC:InviteDebug("debug", "Invite Realm: no connected realms found via GetAutoCompleteRealms.")
    else
        GC:InviteDebug("debug", string.format("Invite Realm: found %d connected realms for %s.", #realms, guildRealm))
    end

    return realms
end

-- ── GetScanRealms ──────────────────────────────────────────────────────────
-- Returns { guildRealm, playerRealm, scanRealms, warning }
-- scanRealms is the list of realms to actually scan.
-- warning is a non-nil string if fallbacks were used.
function Realm.GetScanRealms(settings)
    settings = settings or inviteSettings()

    local includeConnected    = settings.includeConnectedRealms ~= false
    local allowHomeFallback   = settings.allowHomeRealmFallback ~= false
    local neverScanAll        = settings.neverScanAllRealms     ~= false

    local overrideRealm = settingRealmOverride(settings)
    local guildRealm  = overrideRealm or Realm.GetGuildRealm()
    local playerRealm = Realm.GetPlayerRealm()
    local warning     = nil
    local anchor      = nil

    if guildRealm then
        anchor = guildRealm
        if overrideRealm then
            warning = nil
        end
    elseif allowHomeFallback and playerRealm then
        anchor  = playerRealm
        warning = "Guild realm could not be determined; falling back to player realm: " .. playerRealm
        GC:InviteDebug("debug", "Invite Realm:", warning)
    else
        return {
            guildRealm  = guildRealm,
            playerRealm = playerRealm,
            scanRealms  = {},
            warning     = "Realm detection failed. Cannot build scan queries safely.",
        }
    end

    local scanRealms
    if includeConnected then
        scanRealms = Realm.GetConnectedRealmsForGuildRealm(anchor)
    else
        scanRealms = { anchor }
    end

    -- Safety: never scan all realms (empty realm filter = global scan).
    -- Requires in-game testing: verify empty r-"" behaviour in WHO on current builds.
    if neverScanAll and #scanRealms == 0 then
        return {
            guildRealm  = guildRealm,
            playerRealm = playerRealm,
            scanRealms  = {},
            warning     = "No realms resolved; scan aborted to avoid global query.",
        }
    end

    return {
        guildRealm  = guildRealm,
        selected    = overrideRealm ~= nil,
        override    = overrideRealm,
        playerRealm = playerRealm,
        anchor      = anchor,
        scanRealms  = scanRealms,
        warning     = warning,
    }
end

-- ── BuildWhoQueries ────────────────────────────────────────────────────────
-- Returns { queries = {}, realmInfo = {...}, error = nil|string }
-- Each query string is ready to pass to GC.API.SendWho().
-- Optional extraFilter narrows results (e.g. "60-80" for levels).
--
-- Default WHO query format:
--   1-<max level>, then split saturated ranges in Scanner.lua.
-- Realm restriction is applied locally after results return because
-- Retail/Midnight realm-qualified WHO syntax has returned 0 results in tests.
--
-- Requires in-game testing:
--   - Level-band WHO syntax on Retail/Midnight.
--   - Whether WHO returns realm suffixes consistently for connected realms.
--   - Adaptive scanning must remain sequential and user-triggered unless the
--     existing safe auto-advance setting is enabled.
function Realm.BuildWhoQueries(settings, extraFilter)
    settings    = settings    or inviteSettings()
    extraFilter = extraFilter and GC.Utils.Trim(extraFilter) or ""

    local info = Realm.GetScanRealms(settings)

    if #info.scanRealms == 0 then
        return {
            queries   = {},
            realmInfo = info,
            error     = info.warning or "No scan realms available.",
        }
    end

    local mode = scanQueryMode(settings)
    local queries = {}

    if mode == "adaptive-level-range" then
        local minLevel, maxLevel = scanLevels(settings)
        local baseQuery = string.format("%d-%d", minLevel, maxLevel)
        local q = appendExtraFilter(baseQuery, extraFilter)
        queries[#queries + 1] = {
            query = q,
            format = "adaptive-level-range",
            label = baseQuery,
            levelBand = { min = minLevel, max = maxLevel },
            levelMin = minLevel,
            levelMax = maxLevel,
            scanLevelMin = minLevel,
            scanLevelMax = maxLevel,
            depth = 0,
            extraFilter = extraFilter,
            realmFilterMode = tostring(settings.realmFilterMode or "local"),
        }
    elseif mode == "class-level-local-realm" then
        local minLevel, maxLevel = scanLevels(settings)
        local classes = scanClasses(settings)
        for _, className in ipairs(classes) do
            if type(className) == "string" and className ~= "" then
                local baseQuery = string.format('%d-%d c-"%s"', minLevel, maxLevel, className)
                local q = appendExtraFilter(baseQuery, extraFilter)
                queries[#queries + 1] = {
                    query = q,
                    format = "class-level-local-realm",
                    label = string.format('%d-%d c-"%s"', minLevel, maxLevel, className),
                className = className,
                levelMin = minLevel,
                levelMax = maxLevel,
                extraFilter = extraFilter,
                realmFilterMode = tostring(settings.realmFilterMode or "local"),
            }
            end
        end
    else
        local bands, minLevel, maxLevel = scanLevelBands(settings)
        for _, band in ipairs(bands) do
            local baseQuery = string.format("%d-%d", band.min, band.max)
            local q = appendExtraFilter(baseQuery, extraFilter)
            queries[#queries + 1] = {
                query = q,
                format = "level-band-local-realm",
                label = baseQuery,
                levelBand = { min = band.min, max = band.max },
                levelMin = band.min,
                levelMax = band.max,
                scanLevelMin = minLevel,
                scanLevelMax = maxLevel,
                depth = 0,
                extraFilter = extraFilter,
                realmFilterMode = tostring(settings.realmFilterMode or "local"),
            }
        end
    end

    if #queries == 0 then
        return {
            queries   = {},
            realmInfo = info,
            mode      = mode,
            error     = "No level-band WHO queries could be built. Refusing to send a broad WHO query.",
        }
    end

    return {
        queries   = queries,
        realmInfo = info,
        mode      = mode,
        error     = nil,
    }
end

-- ── BuildRealmQueryFormatTests ────────────────────────────────────────────
-- Returns manual WHO query format candidates for /gc invitescan testrealm.
-- z-"RealmName" is included only here as a debug/manual syntax comparison.
-- Empty or broad WHO queries are intentionally never generated.
--
-- Requires in-game testing: these forms are accepted/rejected by the server,
-- not by the client API, so static validation cannot prove correctness.
function Realm.BuildRealmQueryFormatTests(settings)
    settings = settings or inviteSettings()

    local info = Realm.GetScanRealms(settings)
    local realm = info.anchor or info.guildRealm or info.playerRealm

    if not realm then
        return {
            queries   = {},
            realmInfo = info,
            error     = info.warning or "No realm resolved for query format testing.",
        }
    end

    local safeRealmQuery = realmQueryForMode(realm, settings.whoQueryMode)
    local queries = {
        {
            query = safeRealmQuery,
            format = "r-quoted",
            label = 'r-"RealmName"',
            debugOnly = false,
        },
        {
            query = string.format("r-%s", realm),
            format = "r-unquoted",
            label = "r-RealmName",
            debugOnly = false,
        },
        {
            query = string.format('"%s"', realm),
            format = "quoted-literal",
            label = '"RealmName"',
            debugOnly = false,
        },
        {
            query = string.format('z-"%s"', realm),
            format = "z-quoted-debug",
            label = 'z-"RealmName"',
            debugOnly = true,
        },
    }

    return {
        queries   = queries,
        realmInfo = info,
        error     = nil,
    }
end

function Realm.PrintQueryFormatTests(result)
    result = result or Realm.BuildRealmQueryFormatTests()
    local info = result.realmInfo or {}

    GC:Print("Invite Realm WHO Query Test:")
    GC:Print("  Detected guild realm:", tostring(info.guildRealm or "(not found)"))
    GC:Print("  Player realm:", tostring(info.playerRealm or "(not found)"))
    GC:Print("  Scan anchor:", tostring(info.anchor or "(none)"))

    if info.warning then
        GC:Print("  WARNING:", info.warning)
    end

    if type(info.scanRealms) == "table" and #info.scanRealms > 0 then
        GC:Print(string.format("  Connected realms (%d):", #info.scanRealms))
        for i, r in ipairs(info.scanRealms) do
            GC:Print(string.format("    %d. %s", i, r))
        end
    else
        GC:Print("  Connected realms: none resolved")
    end

    if result.error then
        GC:Print("  Error:", result.error)
        return
    end

    GC:Print("  Query formats to test manually:")
    for i, item in ipairs(result.queries or {}) do
        local suffix = item.debugOnly and " (debug/manual only)" or ""
        GC:Print(string.format("    %d. %s -> %s%s", i, item.label, item.query, suffix))
    end
    GC:Print("  One query is sent per command. Use /gc invitescan testrealm next to continue.")
end

-- ── PrintRealmDebug ────────────────────────────────────────────────────────
-- Prints a full diagnostic for /gc invitescan realm
function Realm.PrintRealmDebug(settings)
    settings = settings or inviteSettings()

    local guildName = GetGuildInfo and GetGuildInfo("player") or "unknown"
    local result    = Realm.BuildWhoQueries(settings)
    local info      = result.realmInfo

    GC:Print("Invite Realm Debug:")
    GC:Print("  Guild name:     ", tostring(guildName))
    GC:Print("  Guild realm:    ", tostring(info.guildRealm  or "(not found)"))
    GC:Print("  Player realm:   ", tostring(info.playerRealm or "(not found)"))
    GC:Print("  Scan anchor:    ", tostring(info.anchor      or "(none)"))

    if info.warning then
        GC:Print("  WARNING:        ", info.warning)
    end

    if #info.scanRealms > 0 then
        GC:Print(string.format("  Connected realms (%d):", #info.scanRealms))
        for i, r in ipairs(info.scanRealms) do
            GC:Print(string.format("    %d. %s", i, r))
        end
    else
        GC:Print("  Connected realms: none resolved")
    end

    if result.error then
        GC:Print("  Error:          ", result.error)
        GC:Print("  Planned queries: none (scan blocked)")
    else
        GC:Print(string.format("  Planned WHO queries (%d):", #result.queries))
        GC:Print("  Query mode:     ", tostring(result.mode or "level-band-local-realm"))
        for i, item in ipairs(result.queries) do
            local q = type(item) == "table" and item.query or item
            GC:Print(string.format("    %d. %s", i, q))
        end
    end
end

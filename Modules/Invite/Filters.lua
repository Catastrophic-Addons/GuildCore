-- /GuildCore/Modules/Invite/Filters.lua
-- Pure candidate eligibility filters for the Invite scanner.
local addonName, ns = ...
local GC = ns.GuildCore

GC.Modules.Invite = GC.Modules.Invite or {}

local Filters = {}

local function lower(value)
    return tostring(value or ""):lower()
end

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$") or ""
end

local function effectiveGuildlessOnly(settings)
    local guildlessOnly = true
    if settings and settings.guildlessOnly == false then
        guildlessOnly = false
    end
    return guildlessOnly
end

local function hasGuild(candidate)
    return trim(candidate and candidate.guild) ~= ""
end

local function normalizeName(value)
    if not value or value == "" then
        return nil
    end

    if GC.API and GC.API.NormalizePlayerName then
        return GC.API.NormalizePlayerName(value)
    end

    return tostring(value)
end

local function tableHasValues(values)
    if type(values) ~= "table" then
        return false
    end

    for _, enabled in pairs(values) do
        if enabled then
            return true
        end
    end
    return false
end

local function classMatches(values, candidate)
    if not tableHasValues(values) then
        return true
    end

    local className = lower(candidate and candidate.className)
    local classFile = lower(candidate and candidate.classFile)
    for classKey, enabled in pairs(values) do
        if enabled then
            local key = lower(classKey)
            if key == className or key == classFile then
                return true
            end
        end
    end
    return false
end

local function classExcluded(values, candidate)
    if not tableHasValues(values) then
        return false
    end

    local className = lower(candidate and candidate.className)
    local classFile = lower(candidate and candidate.classFile)
    for classKey, enabled in pairs(values) do
        if enabled then
            local key = lower(classKey)
            if key == className or key == classFile then
                return true
            end
        end
    end
    return false
end

local function zoneListHasValues(values)
    if type(values) ~= "table" then
        return false
    end

    for key, value in pairs(values) do
        if type(key) == "number" then
            if tostring(value or "") ~= "" then
                return true
            end
        elseif value then
            return true
        end
    end
    return false
end

local function zoneMatches(values, zone)
    if not zoneListHasValues(values) then
        return true
    end

    zone = lower(zone)
    if zone == "" then
        return false
    end

    for key, value in pairs(values) do
        local needle
        if type(key) == "number" then
            needle = value
        elseif value then
            needle = key
        end

        needle = lower(needle)
        if needle ~= "" and zone:find(needle, 1, true) then
            return true
        end
    end
    return false
end

local function zoneExcluded(values, zone)
    if not zoneListHasValues(values) then
        return false
    end

    zone = lower(zone)
    if zone == "" then
        return false
    end

    for key, value in pairs(values) do
        local needle
        if type(key) == "number" then
            needle = value
        elseif value then
            needle = key
        end

        needle = lower(needle)
        if needle ~= "" and zone:find(needle, 1, true) then
            return true
        end
    end
    return false
end

function Filters.IsGuildless(candidate, settings)
    if settings == nil then
        if GC and GC.Debug then
            GC:InviteDebug("debug", "Invite filters: settings missing; guildlessOnly defaults to true.")
        end
    elseif settings.guildlessOnly == nil then
        if GC and GC.Debug then
            GC:InviteDebug("debug", "Invite filters: guildlessOnly missing; defaulting to true.")
        end
    end

    if not effectiveGuildlessOnly(settings) then
        return true
    end

    return not hasGuild(candidate)
end

function Filters.EffectiveGuildlessOnly(settings)
    return effectiveGuildlessOnly(settings)
end

function Filters.MatchesLevelRange(candidate, settings)
    settings = settings or {}
    local level = candidate and tonumber(candidate.level)
    if not level then
        return false
    end

    local minLevel = math.max(1, math.floor(tonumber(settings.levelMin) or 1))
    local maxLevel = math.max(minLevel, math.floor(tonumber(settings.levelMax) or 90))
    return level >= minLevel and level <= maxLevel
end

function Filters.MatchesClass(candidate, settings)
    settings = settings or {}
    if classExcluded(settings.excludeClasses, candidate) then
        return false
    end

    return classMatches(settings.includeClasses, candidate)
end

function Filters.MatchesZone(candidate, settings)
    settings = settings or {}
    local zone = candidate and candidate.zone
    if zoneExcluded(settings.zoneExcludes, zone) then
        return false
    end

    return zoneMatches(settings.zoneIncludes, zone)
end

function Filters.IsIgnored(candidate, settings)
    settings = settings or {}
    local ignored = settings.ignored or settings.ignoredNames or settings.names or settings
    if type(ignored) == "table" and type(ignored.names) == "table" then
        ignored = ignored.names
    end

    local key = candidate and (candidate.key or normalizeName(candidate.fullName or candidate.name))
    if not key or type(ignored) ~= "table" then
        return false
    end

    return ignored[key] == true
        or ignored[candidate.fullName or ""] == true
        or ignored[candidate.name or ""] == true
end

function Filters.IsRecentlyInvited(candidate, history, settings)
    settings = settings or {}
    if settings.excludeRecentlyInvited == false then
        return false
    end

    history = history or {}
    local recent = history.recentInvites or history
    if type(recent) ~= "table" then
        return false
    end

    local key = candidate and (candidate.key or normalizeName(candidate.fullName or candidate.name))
    local entry = key and recent[key] or nil
    if type(entry) ~= "table" then
        return entry == true
    end

    local invitedAt = tonumber(entry.at or entry.invitedAt or entry.time)
    if not invitedAt then
        return false
    end

    local days = math.max(1, math.floor(tonumber(settings.recentInviteDays) or 30))
    return ((time and time() or 0) - invitedAt) < (days * 86400)
end

function Filters.IsRecentlyDeclined(candidate, history, settings)
    history = history or {}
    local recent = history.recentDeclines or history.declines or history.declinedInvites
    if type(recent) ~= "table" then
        recent = {}
    end

    local key = candidate and (candidate.key or normalizeName(candidate.fullName or candidate.name))
    local entry = key and recent[key] or nil
    if entry == nil and key and type(history.recentInvites) == "table" then
        entry = history.recentInvites[key]
    end
    if type(entry) ~= "table" then
        return entry == true
    end

    local outcome = lower(entry.outcome or entry.result or entry.status or "")
    local declined = outcome == "declined" or outcome == "invite_declined" or outcome == "declined_invite"
    local declinedAt = tonumber(entry.at or entry.declinedAt or entry.time)
    if not declinedAt then
        return declined
    end

    local days = math.max(1, math.floor(tonumber(settings and settings.recentInviteDays) or 30))
    return declined and (((time and time() or 0) - declinedAt) < (days * 86400))
end

function Filters.EvaluateCandidate(candidate, settings, history)
    if settings == nil then
        if GC and GC.Debug then
            GC:InviteDebug("debug", "Invite filters: EvaluateCandidate missing settings; using safe defaults.")
        end
        settings = {}
    elseif settings.guildlessOnly == nil then
        if GC and GC.Debug then
            GC:InviteDebug("debug", "Invite filters: EvaluateCandidate guildlessOnly missing; defaulting to true.")
        end
    end
    history = history or {}

    local reasons = {}

    if effectiveGuildlessOnly(settings) and hasGuild(candidate) then
        reasons[#reasons + 1] = "has_guild"
    end

    local level = candidate and tonumber(candidate.level)
    if not level then
        reasons[#reasons + 1] = "missing_level"
    else
        local minLevel = math.max(1, math.floor(tonumber(settings.levelMin) or 1))
        local maxLevel = math.max(minLevel, math.floor(tonumber(settings.levelMax) or 90))
        if level < minLevel then
            reasons[#reasons + 1] = "level_too_low"
        elseif level > maxLevel then
            reasons[#reasons + 1] = "level_too_high"
        end
    end

    if not Filters.MatchesClass(candidate, settings) then
        if classExcluded(settings.excludeClasses, candidate) then
            reasons[#reasons + 1] = "class_excluded"
        else
            reasons[#reasons + 1] = "class_not_included"
        end
    end

    if not Filters.MatchesZone(candidate, settings) then
        if zoneExcluded(settings.zoneExcludes, candidate and candidate.zone) then
            reasons[#reasons + 1] = "zone_excluded"
        else
            reasons[#reasons + 1] = "zone_not_included"
        end
    end

    if Filters.IsIgnored(candidate, history.ignored or settings) then
        reasons[#reasons + 1] = "ignored"
    end

    if GC.BanBook and GC.BanBook.IsBanned and GC.BanBook:IsBanned(candidate and (candidate.fullName or candidate.name or candidate.key), candidate and candidate.realm) then
        reasons[#reasons + 1] = "banned"
    end

    if Filters.IsRecentlyInvited(candidate, history, settings) then
        reasons[#reasons + 1] = "recently_invited"
    end

    if Filters.IsRecentlyDeclined(candidate, history, settings) then
        reasons[#reasons + 1] = "recently_declined"
    end

    return {
        eligible = #reasons == 0,
        reasons = reasons,
    }
end

GC.Modules.Invite.Filters = Filters

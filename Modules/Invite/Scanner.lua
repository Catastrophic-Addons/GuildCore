-- /GuildCore/Modules/Invite/Scanner.lua
-- Invite scanner: manual-step WHO query model.
--
-- C_FriendList.SendWho is hardware-event restricted on some WoW builds.
-- Follow-up queries MUST be user-triggered, never fired from timers or callbacks.
--
-- Flow:
--   /gc invitescan        -> build query list, send query 1, store rest as pending
--   /gc invitescan next   -> send the next pending query manually
--   /gc invitescan stop   -> clear pending queries and stop
--   WHO_LIST_UPDATE       -> collect results, mark query done, optionally auto advance
--   Timeout               -> mark query timed out, leave pending intact
local addonName, ns = ...
local GC = ns.GuildCore

GC.Modules.Invite = GC.Modules.Invite or {}

local Scanner = {}
Scanner.__index = Scanner

local TIMEOUT_SECONDS = 12
local PRINT_LIMIT     = 5
local RAW_PRINT_LIMIT = 3

local function trim(value)
    return GC.Utils.Trim(value or "")
end

local function now()
    return GC.Utils.Now()
end

local function printLine(...)
    GC:InviteDebug("debug", ...)
end

local function warnLine(...)
    GC:InviteDebug("warn", ...)
end

local function inviteStorage()
    if GC.Services.Invite and GC.Services.Invite.GetStorage then
        return GC.Services.Invite:GetStorage()
    end
    return nil
end

local function inviteSettings()
    local storage = inviteStorage()
    return storage and storage.settings or {}
end

local function inviteHistory()
    local storage = inviteStorage()
    return {
        ignored = storage and storage.ignored or {},
        recentInvites = storage and storage.recentInvites or {},
        recentDeclines = storage and storage.recentDeclines or {},
    }
end

local function runtime()
    if GC.Services.Invite and GC.Services.Invite.GetRuntimeState then
        return GC.Services.Invite:GetRuntimeState()
    end

    GC.State.invite = GC.State.invite or {}
    GC.State.invite.scan = GC.State.invite.scan or {}
    GC.State.invite.candidates = GC.State.invite.candidates or {}
    GC.State.invite.timers = GC.State.invite.timers or {}
    return GC.State.invite
end

local function splitFullName(fullName)
    if not fullName or fullName == "" then
        return nil, nil
    end

    local name, realm = tostring(fullName):match("^([^%-]+)%-(.+)$")
    if name and realm then
        return name, realm
    end

    return tostring(fullName), nil
end

local function trimString(value)
    if value == nil then
        return ""
    end
    return tostring(value):match("^%s*(.-)%s*$") or ""
end

local function firstNonEmptyString(...)
    for i = 1, select("#", ...) do
        local value = trimString(select(i, ...))
        if value ~= "" then
            return value
        end
    end
    return ""
end

local function hasReason(candidate, reason)
    for _, value in ipairs((candidate and candidate.ineligibleReasons) or {}) do
        if value == reason then
            return true
        end
    end
    return false
end

local function addReason(candidate, reason)
    candidate.ineligibleReasons = candidate.ineligibleReasons or {}
    if not hasReason(candidate, reason) then
        candidate.ineligibleReasons[#candidate.ineligibleReasons + 1] = reason
    end
end

local function hasGuild(candidate)
    return trimString(candidate and candidate.guild) ~= ""
end

local function effectiveGuildlessOnly(settings, filters)
    if filters and filters.EffectiveGuildlessOnly then
        return filters.EffectiveGuildlessOnly(settings)
    end
    return not (settings and settings.guildlessOnly == false)
end

local function normalizeRealmKey(realm)
    if not realm or realm == "" then
        return nil
    end
    return tostring(realm):gsub("%s+", ""):lower()
end

local function normalizeCandidate(info, sourceQuery, scannedAt)
    if type(info) ~= "table" then
        return nil
    end

    local fullName = info.name or info.fullName or info.Name
    if not fullName or fullName == "" then
        return nil
    end

    local name, realm = splitFullName(fullName)
    local key = info.normalizedName or GC.API.NormalizePlayerName(fullName)
    local guild = firstNonEmptyString(info.guild, info.Guild, info.fullGuildName)

    return {
        key = key,
        name = name,
        fullName = fullName,
        realm = realm,
        level = tonumber(info.level or info.Level),
        className = info.class or info.className or info.Class,
        classFile = info.classFileName or info.filename or info.NoLocaleClass,
        zone = info.zone or info.Zone,
        guild = guild ~= "" and guild or nil,
        isGuildless = guild == "",
        sourceQuery = sourceQuery,
        scannedAt = scannedAt,
        status = "found",
    }
end

local function printCandidates(candidates)
    printLine("Invite scan normalized candidates:", tostring(#candidates))

    local limit = math.min(#candidates, PRINT_LIMIT)
    for index = 1, limit do
        local candidate = candidates[index]
        local guildStatus = candidate.isGuildless and "guildless" or ("guild=" .. tostring(candidate.guild))
        printLine(string.format(
            "  %d. %s level=%s class=%s zone=%s %s",
            index,
            tostring(candidate.fullName or candidate.name or "unknown"),
            tostring(candidate.level or "?"),
            tostring(candidate.className or ""),
            tostring(candidate.zone or ""),
            guildStatus
        ))
    end
end

local function printEligibleCandidates(candidates)
    local printed = 0
    printLine("Invite scan first eligible candidates:")
    for _, candidate in ipairs(candidates or {}) do
        if candidate.eligible then
            printed = printed + 1
            printLine(string.format(
                "  %d. %s level=%s class=%s zone=%s",
                printed,
                tostring(candidate.fullName or candidate.name or "unknown"),
                tostring(candidate.level or "?"),
                tostring(candidate.className or ""),
                tostring(candidate.zone or "")
            ))
            if printed >= PRINT_LIMIT then
                break
            end
        end
    end

    if printed == 0 then
        printLine("  none")
    end
end

local function countRejectionReasons(candidates)
    local counts = {}
    local eligible = 0
    local ineligible = 0

    for _, candidate in ipairs(candidates or {}) do
        if candidate.eligible then
            eligible = eligible + 1
        else
            ineligible = ineligible + 1
            for _, reason in ipairs(candidate.ineligibleReasons or {}) do
                counts[reason] = (counts[reason] or 0) + 1
            end
        end
    end

    return counts, eligible, ineligible
end

local function sortedReasonRows(counts)
    local rows = {}
    for reason, count in pairs(counts or {}) do
        rows[#rows + 1] = { reason = reason, count = count }
    end
    table.sort(rows, function(a, b)
        if a.count == b.count then
            return a.reason < b.reason
        end
        return a.count > b.count
    end)
    return rows
end

local function printFilterSummary(candidates)
    local counts, eligible, ineligible = countRejectionReasons(candidates)
    printLine(string.format("Invite scan eligibility: total=%d eligible=%d ineligible=%d", #candidates, eligible, ineligible))

    local rows = sortedReasonRows(counts)
    if #rows == 0 then
        printLine("Invite scan rejection reasons: none")
        return
    end

    printLine("Invite scan rejection reasons:")
    for index = 1, math.min(#rows, PRINT_LIMIT) do
        printLine(string.format("  %s=%d", rows[index].reason, rows[index].count))
    end
end

local function printRejectedCandidates(candidates)
    local printed = 0
    printLine("Invite scan first rejected candidates:")
    for _, candidate in ipairs(candidates or {}) do
        if not candidate.eligible then
            printed = printed + 1
            printLine(string.format(
                "  %d. %s guild=%s reasons=%s",
                printed,
                tostring(candidate.fullName or candidate.name or "unknown"),
                tostring(candidate.guild or ""),
                table.concat(candidate.ineligibleReasons or {}, ",")
            ))
            if printed >= PRINT_LIMIT then
                break
            end
        end
    end

    if printed == 0 then
        printLine("  none")
    end
end

local function printEvaluatedCandidates(candidates)
    local printed = 0
    printLine("Invite scan evaluated candidates:")
    for _, candidate in ipairs(candidates or {}) do
        printed = printed + 1
        printLine(string.format(
            "  %d. %s guild=%s eligible=%s reasons=%s",
            printed,
            tostring(candidate.fullName or candidate.name or "unknown"),
            tostring(candidate.guild or ""),
            tostring(candidate.eligible == true),
            table.concat(candidate.ineligibleReasons or {}, ",")
        ))
        if printed >= PRINT_LIMIT then
            break
        end
    end

    if printed == 0 then
        printLine("  none")
    end
end

local function queryText(item)
    if type(item) == "table" then
        return item.query
    end
    return item
end

local function queryLabel(item)
    if type(item) == "table" then
        return item.label or item.format or item.query
    end
    return item
end

local function formatRawValue(value)
    if type(value) == "table" then
        return "<table>"
    end
    return tostring(value)
end

local function printRawWhoRows(shown)
    shown = tonumber(shown or 0) or 0
    if shown <= 0 then
        return
    end

    -- Requires in-game testing: WHO row field names can shift between builds.
    -- These raw rows help verify what C_FriendList.GetWhoInfo returns on Midnight.
    printLine("Invite scan raw WHO rows:")
    for i = 1, math.min(shown, RAW_PRINT_LIMIT) do
        local info = GC.API.GetWhoInfo(i)
        local raw = type(info) == "table" and info.raw or info
        if type(raw) == "table" then
            printLine(string.format(
                "  raw %d: fullName=%s name=%s guild=%s level=%s class=%s filename=%s area=%s",
                i,
                formatRawValue(raw.fullName),
                formatRawValue(raw.name or raw.Name),
                formatRawValue(raw.fullGuildName or raw.guild or raw.Guild),
                formatRawValue(raw.level or raw.Level),
                formatRawValue(raw.classStr or raw.class or raw.Class),
                formatRawValue(raw.filename or raw.NoLocaleClass or raw.classFileName),
                formatRawValue(raw.area or raw.zone or raw.Zone)
            ))
        else
            printLine(string.format("  raw %d: %s", i, tostring(raw)))
        end
    end
end

local function isQuotedRealmQueryZero(scan, query, rawTotal, shown, newThisQuery)
    if not query or tostring(query):match('^r%-".-"') == nil then
        return false
    end

    -- The r-"RealmName" form is the conservative default, but the observed
    -- Retail/Midnight behavior requires in-game testing before treating zero
    -- results as proof that no candidates exist.
    return (tonumber(rawTotal or 0) or 0) == 0
        and (tonumber(shown or 0) or 0) == 0
        and (tonumber(newThisQuery or 0) or 0) == 0
end

local function buildAllowedRealmSet(realmInfo)
    local allowed = {}
    local count = 0
    local function add(realm)
        local key = normalizeRealmKey(realm)
        if key and not allowed[key] then
            allowed[key] = true
            count = count + 1
        end
    end

    for _, realm in ipairs((realmInfo and realmInfo.scanRealms) or {}) do
        add(realm)
    end

    add(realmInfo and realmInfo.guildRealm)
    add(realmInfo and realmInfo.anchor)
    return allowed, count
end

local function assumeCandidateRealm(candidate, realmInfo)
    if not candidate or candidate.realm then
        return
    end

    -- Requires in-game testing: WHO often omits the realm suffix for same-realm
    -- players. Treat suffix-less rows as guild/player realm only when an anchor
    -- realm was safely detected; otherwise the row is filtered out.
    local assumed = realmInfo and (realmInfo.guildRealm or realmInfo.anchor or realmInfo.playerRealm)
    if assumed and assumed ~= "" then
        candidate.realm = assumed
        candidate.realmAssumed = true
        candidate.key = GC.API.NormalizePlayerName(candidate.fullName or candidate.name, assumed) or candidate.key
    end
end

local function passesLocalRealmFilter(candidate, realmInfo)
    if not candidate then
        return false
    end

    assumeCandidateRealm(candidate, realmInfo)
    local realmKey = normalizeRealmKey(candidate.realm)
    if not realmKey then
        return false
    end

    local allowed = buildAllowedRealmSet(realmInfo)
    return allowed[realmKey] == true
end

local function countEligible(candidates)
    local eligible = 0
    for _, candidate in ipairs(candidates or {}) do
        if candidate.eligible then
            eligible = eligible + 1
        end
    end
    return eligible
end

-- ── Internal helpers ──────────────────────────────────────────────────────

local function cancelTimeout(state)
    if state.timers and state.timers.inviteScanTimeout then
        state.timers.inviteScanTimeout:Cancel()
        state.timers.inviteScanTimeout = nil
    end
end

local function cancelAutoAdvance(state)
    if state.timers and state.timers.inviteScanAutoAdvance then
        state.timers.inviteScanAutoAdvance:Cancel()
        state.timers.inviteScanAutoAdvance = nil
    end
end

local function scanAdvanceDelay(settings)
    local delay = tonumber(settings and settings.scanAdvanceDelaySeconds) or 3
    return math.max(1, math.min(10, delay))
end

local function levelBandLabel(item)
    if type(item) == "table" and item.levelBand then
        return string.format(
            "%d-%d",
            tonumber(item.levelBand.min) or 0,
            tonumber(item.levelBand.max) or 0
        )
    end
    if type(item) == "table" and item.levelMin and item.levelMax then
        return string.format("%d-%d", tonumber(item.levelMin) or 0, tonumber(item.levelMax) or 0)
    end
    return nil
end

local function rangeFromItem(item)
    if type(item) ~= "table" then return nil, nil end
    if type(item.levelBand) == "table" then
        return tonumber(item.levelBand.min), tonumber(item.levelBand.max)
    end
    return tonumber(item.levelMin), tonumber(item.levelMax)
end

local function scanCapThreshold(settings)
    return math.max(1, math.floor(tonumber(settings and settings.whoCapThreshold) or 50))
end

local function scanMaxSplitDepth(settings)
    return math.max(0, math.floor(tonumber(settings and settings.maxSplitDepth) or 6))
end

local function isAdaptiveItem(item)
    return type(item) == "table" and item.format == "adaptive-level-range"
end

local function isSaturatedWhoResult(rawTotal, shown, threshold)
    rawTotal = tonumber(rawTotal) or 0
    shown = tonumber(shown) or 0
    threshold = tonumber(threshold) or 50
    return rawTotal >= threshold or shown >= threshold or rawTotal == 50 or shown == 50
end

local function adaptiveQuery(minLevel, maxLevel, depth, parent)
    local baseQuery = string.format("%d-%d", minLevel, maxLevel)
    local extraFilter = type(parent) == "table" and parent.extraFilter or nil
    local query = baseQuery
    if extraFilter and extraFilter ~= "" then
        query = query .. " " .. extraFilter
    end
    return {
        query = query,
        format = "adaptive-level-range",
        label = baseQuery,
        levelBand = { min = minLevel, max = maxLevel },
        levelMin = minLevel,
        levelMax = maxLevel,
        scanLevelMin = parent and parent.scanLevelMin or minLevel,
        scanLevelMax = parent and parent.scanLevelMax or maxLevel,
        depth = depth,
        extraFilter = extraFilter,
        realmFilterMode = parent and parent.realmFilterMode or "local",
    }
end

local function splitAdaptiveRange(item, settings)
    if not isAdaptiveItem(item) then return nil end
    local minLevel, maxLevel = rangeFromItem(item)
    if not minLevel or not maxLevel or minLevel >= maxLevel then return nil end
    local depth = math.max(0, math.floor(tonumber(item.depth) or 0))
    if depth >= scanMaxSplitDepth(settings) then return nil end

    local mid = math.floor((minLevel + maxLevel) / 2)
    if mid < minLevel or mid >= maxLevel then return nil end

    return adaptiveQuery(minLevel, mid, depth + 1, item),
        adaptiveQuery(mid + 1, maxLevel, depth + 1, item)
end

local function refreshInvitePanel()
    local panel = GC.UI and GC.UI.InvitePanel
    if panel and panel.UpdateStatus then
        panel:UpdateStatus()
    end
    if panel and panel._refreshCandidateList then
        panel:_refreshCandidateList()
    end
    if panel and panel._updateButtons then
        panel:_updateButtons()
    end
end

local function pauseAutoAdvance(scan, message)
    if not scan then return end
    scan.active = false
    scan.autoPaused = true
    scan.autoPauseReason = message or "Auto scan paused. Click Scan Next to continue."
    scan.statusLine = scan.autoPauseReason
    scan.autoAdvanceAttempting = false
    GC.API.SetWhoToUi(false)
    warnLine(scan.autoPauseReason)
    refreshInvitePanel()
end

local function scheduleAutoAdvance(scan)
    if not scan or scan.queryTest or scan.autoAdvanceEnabled == false then return end
    if scan.autoPaused or scan.active then return end
    if #(scan.pendingQueries or {}) == 0 then return end

    local state = runtime()
    state.timers = state.timers or {}
    cancelAutoAdvance(state)

    local delay = scanAdvanceDelay(inviteSettings())
    scan.statusLine = string.format(
        "Scanning levels %s complete. Next band in %ds...",
        tostring(scan.currentLevelBand or "?"),
        delay
    )
    refreshInvitePanel()

    -- Requires in-game testing: Retail/Midnight may reject timer-initiated WHO queries.
    -- If that happens, UI_ERROR_MESSAGE pauses auto scanning and the user can click Scan Next.
    state.timers.inviteScanAutoAdvance = C_Timer.NewTimer(delay, function()
        local svc = GC.Services and GC.Services.InviteScanner
        local cur = runtime()
        local curScan = cur.scan
        if not svc or not curScan or curScan.active or curScan.queryTest then return end
        if curScan.autoPaused or #(curScan.pendingQueries or {}) == 0 then return end

        local ok = svc:_advanceNextQuery(true)
        if ok then
            printLine("Invite scan auto-advance sent the next WHO query.")
        end
    end)
end

local function armTimeout(query)
    local state = runtime()
    state.timers = state.timers or {}
    cancelTimeout(state)
    cancelAutoAdvance(state)
    state.timers.inviteScanTimeout = C_Timer.NewTimer(TIMEOUT_SECONDS, function()
        local cur = runtime()
        if not cur.scan or not cur.scan.active then return end
        if cur.scan.query ~= query then return end
        -- Mark query timed out. Do NOT auto-advance. Leave pending queries intact.
        cancelTimeout(cur)
        cur.scan.active        = false
        cur.scan.timedOut      = true
        cur.scan.timedOutQuery = query
        cur.scan.statusLine    = "Auto scan paused. Click Scan Next to continue."
        cur.scan.autoPaused    = true
        cur.scan.autoAdvanceAttempting = false
        cur.scan.autoAdvanceItem = nil
        cur.scan.autoAdvancePrevious = nil
        GC.API.SetWhoToUi(false)
        local pending = cur.scan.pendingQueries or {}
        warnLine(string.format(
            "Invite scan: query timed out. [%s]  pending=%d",
            tostring(query), #pending
        ))
        if cur.scan.queryTest then
            printLine("WHO queries can be throttled. Run /gc invitescan testrealm next to continue.")
        else
            printLine("WHO queries can be throttled. Run /gc invitescan next to continue.")
        end
        refreshInvitePanel()
    end)
end

-- ── Public API ─────────────────────────────────────────────────────────────

-- IsScanning: true only while a WHO query has been sent and result not yet received.
function Scanner:IsScanning()
    return runtime().scan.active == true
end

-- HasPending: true if there are pending queries the user can advance with 'next'.
function Scanner:HasPending()
    local state = runtime()
    local pending = state.scan and state.scan.pendingQueries or {}
    return #pending > 0
end

function Scanner:GetCandidates()
    return runtime().candidates or {}
end

function Scanner:ClearCandidates()
    local state = runtime()
    state.candidates     = {}
    state.candidateByKey = {}
end

function Scanner:RemoveCandidate(candidateKey)
    if not candidateKey then return false end
    local state = runtime()
    local removed = false
    for i = #(state.candidates or {}), 1, -1 do
        if state.candidates[i].key == candidateKey then
            state.candidates[i].selected = false
            table.remove(state.candidates, i)
            removed = true
        end
    end
    if state.candidateByKey then
        state.candidateByKey[candidateKey] = nil
    end
    return removed
end

function Scanner:MarkCandidateStatus(candidateKey, status, result)
    if not candidateKey then return false end
    local state = runtime()
    local candidate = state.candidateByKey and state.candidateByKey[candidateKey]
    if not candidate then return false end
    candidate.status = status or candidate.status
    candidate.queueResult = result
    if status == "declined" then
        candidate.eligible = false
        addReason(candidate, "recently_declined")
    elseif status == "already_in_guild" then
        candidate.eligible = false
        candidate.isGuildless = false
        addReason(candidate, "has_guild")
    elseif status == "already_invited" or status == "invite_sent" or status == "sent" then
        addReason(candidate, "recently_invited")
    end
    if status then
        candidate.selected = false
    end
    return true
end

-- GetScanStatus: returns a summary table for UI and slash debug output.
function Scanner:GetScanStatus()
    local state   = runtime()
    local scan    = state.scan or {}
    local pending = scan.pendingQueries or {}
    local cands   = state.candidates or {}
    return {
        active        = scan.active == true,
        timedOut      = scan.timedOut == true,
        currentQuery  = scan.query,
        queryIndex    = scan.queryIndex or 0,
        totalQueries  = scan.totalQueries or 0,
        processedQueries = scan.processedQueries or 0,
        pendingCount  = #pending,
        candidateCount= #cands,
        eligibleCount = countEligible(cands),
        anchor        = scan.realmInfo and scan.realmInfo.anchor,
        warning       = scan.realmInfo and scan.realmInfo.warning,
        statusLine    = scan.statusLine,
        progressLine  = scan.progressLine,
        currentLevelBand = scan.currentLevelBand,
        currentRange  = scan.currentLevelBand,
        currentQueryLabel = scan.currentQueryLabel,
        autoPaused    = scan.autoPaused == true,
        autoPauseReason = scan.autoPauseReason,
        completedAt   = scan.completedAt,
    }
end

-- StopScan: cancel the current active query and discard pending queries.
-- Called by /gc invitescan stop, or on hard errors.
function Scanner:StopScan(reason)
    local state = runtime()
    cancelTimeout(state)
    cancelAutoAdvance(state)

    if state.scan and (state.scan.active or state.scan.timedOut) then
        printLine("Invite scan stopped:", reason or "stopped")
    end

    state.scan = {
        active    = false,
        stoppedAt = now(),
        reason    = reason,
    }

    -- Requires in-game testing: SetWhoToUi must be restored when scan ends.
    GC.API.SetWhoToUi(false)
end

-- ClearScan: stop scan and clear all accumulated candidates.
function Scanner:ClearScan()
    self:StopScan("cleared")
    self:ClearCandidates()
    printLine("Invite scan cleared. Candidates reset.")
end

-- StartScan: build WHO query list from guild realm, send query 1 directly.
-- MUST be called from a direct user action (slash command or button click).
-- Remaining queries stored in pendingQueries for manual NextQuery calls.
function Scanner:StartScan(extraFilter)
    if self:IsScanning() then
        return false, "Invite scan is already active. Wait for results or use /gc invitescan stop."
    end

    if GC.Services.InviteProbe and GC.Services.InviteProbe.activeWhoQuery then
        return false, "WHO debug probe is already active."
    end

    local Realm = GC.Modules.Invite and GC.Modules.Invite.Realm
    if not Realm then
        return false, "Invite Realm module is not loaded."
    end

    local settings = inviteSettings()
    local result   = Realm.BuildWhoQueries(settings, extraFilter)

    if result.error or #result.queries == 0 then
        return false, result.error or "No level-band WHO queries could be built. Check /gc invitescan realm."
    end

    local queries = result.queries
    local state   = runtime()
    -- Fresh StartScan always clears candidates.
    self:ClearCandidates()

    state.scan = {
        active         = true,
        query          = queryText(queries[1]),
        queryMeta      = type(queries[1]) == "table" and queries[1] or nil,
        queryIndex     = 1,
        totalQueries   = #queries,
        processedQueries = 0,
        pendingQueries = {},       -- queries 2..N stored here
        realmInfo      = result.realmInfo,
        startedAt      = now(),
        resultEventAt  = nil,
        timedOut       = false,
        autoAdvanceEnabled = settings.autoAdvanceScan ~= false,
        autoPaused     = false,
        statusLine     = "Preparing scan...",
    }

    for i = 2, #queries do
        state.scan.pendingQueries[#state.scan.pendingQueries + 1] = queries[i]
    end

    printLine(string.format(
        "Invite scan started. Realm: %s  Query mode: %s  Total queries: %d",
        tostring(result.realmInfo.anchor or "?"),
        tostring(result.mode or settings.whoQueryMode or "safe"),
        #queries
    ))
    printLine("  Guild realm:", tostring(result.realmInfo.guildRealm or "(not found)"))
    if type(result.realmInfo.scanRealms) == "table" and #result.realmInfo.scanRealms > 0 then
        printLine(string.format("  Connected/local realms (%d): %s",
            #result.realmInfo.scanRealms,
            table.concat(result.realmInfo.scanRealms, ", ")))
    else
        printLine("  Connected/local realms: none resolved")
    end
    if result.realmInfo.warning then
        warnLine("Invite scan warning:", result.realmInfo.warning)
    end

    GC.API.SetWhoToUi(true)
    return self:_sendQuery(queries[1], 1, #queries)
end

-- StartRealmQueryTest: compare same-realm WHO query syntax manually.
-- MUST be called from /gc invitescan testrealm. It sends exactly one query.
function Scanner:StartRealmQueryTest()
    if self:IsScanning() then
        return false, "Invite scan is already active. Wait for results or use /gc invitescan stop."
    end

    if GC.Services.InviteProbe and GC.Services.InviteProbe.activeWhoQuery then
        return false, "WHO debug probe is already active."
    end

    local Realm = GC.Modules.Invite and GC.Modules.Invite.Realm
    if not Realm or not Realm.BuildRealmQueryFormatTests then
        return false, "Invite Realm test builder is not loaded."
    end

    local result = Realm.BuildRealmQueryFormatTests(inviteSettings())
    if result.error or #result.queries == 0 then
        if Realm.PrintQueryFormatTests then
            Realm.PrintQueryFormatTests(result)
        end
        return false, result.error or "No realm query tests could be built."
    end

    local state = runtime()
    self:ClearCandidates()

    state.scan = {
        active         = true,
        query          = queryText(result.queries[1]),
        queryMeta      = result.queries[1],
        queryIndex     = 1,
        totalQueries   = #result.queries,
        pendingQueries = {},
        realmInfo      = result.realmInfo,
        startedAt      = now(),
        resultEventAt  = nil,
        timedOut       = false,
        queryTest      = true,
    }

    for i = 2, #result.queries do
        state.scan.pendingQueries[#state.scan.pendingQueries + 1] = result.queries[i]
    end

    if Realm.PrintQueryFormatTests then
        Realm.PrintQueryFormatTests(result)
    end

    GC.API.SetWhoToUi(true)
    return self:_sendQuery(result.queries[1], 1, #result.queries)
end

-- NextQuery: send the next pending query.
-- MUST be called from a direct user action (slash command or button click).
-- Never call this from a timer or event handler.
function Scanner:NextQuery()
    if self:IsScanning() then
        return false, "A WHO query is still active. Wait for results first."
    end

    local scan = runtime().scan
    if scan and scan.queryTest then
        return false, "Realm query tests use /gc invitescan testrealm next."
    end

    if not scan or #(scan.pendingQueries or {}) == 0 then
        if not scan or scan.totalQueries == 0 then
            return false, "No scan in progress. Run /gc invitescan first."
        end
        return false, "No pending queries. All realms have been scanned."
    end

    scan.autoPaused = false
    scan.autoPauseReason = nil
    return self:_advanceNextQuery(false)
end

function Scanner:_advanceNextQuery(isAuto)
    local state   = runtime()
    local scan    = state.scan
    local pending = scan and scan.pendingQueries or {}

    if not scan or #pending == 0 then
        return false, "No pending scan queries."
    end

    local nextItem = table.remove(pending, 1)
    local nextQuery = queryText(nextItem)
    local newIndex = (scan.queryIndex or 0) + 1
    local prevQuery = scan.query
    local prevMeta = scan.queryMeta
    local prevIndex = scan.queryIndex

    scan.active        = true
    scan.query         = nextQuery
    scan.queryMeta     = type(nextItem) == "table" and nextItem or nil
    scan.queryIndex    = newIndex
    scan.resultEventAt = nil
    scan.timedOut      = false
    scan.autoPaused    = false
    scan.autoPauseReason = nil
    scan.autoAdvanceAttempting = isAuto == true
    scan.autoAdvanceItem = isAuto == true and nextItem or nil
    scan.autoAdvancePrevious = isAuto == true and {
        query = prevQuery,
        queryMeta = prevMeta,
        queryIndex = prevIndex,
    } or nil

    GC.API.SetWhoToUi(true)
    local ok, err = self:_sendQuery(nextItem, newIndex, scan.totalQueries or newIndex, {
        auto = isAuto == true,
    })
    if not ok then
        table.insert(pending, 1, nextItem)
        scan.active = false
        scan.query = prevQuery
        scan.queryMeta = prevMeta
        scan.queryIndex = prevIndex
        scan.autoAdvanceAttempting = false
        scan.autoAdvanceItem = nil
        scan.autoAdvancePrevious = nil
        if isAuto then
            pauseAutoAdvance(scan, "Auto scan paused. Click Scan Next to continue.")
        end
        return false, err
    end

    return true
end

-- NextRealmQueryTest: send the next pending query-format candidate.
-- MUST be called from /gc invitescan testrealm next; never auto-advances.
function Scanner:NextRealmQueryTest()
    if self:IsScanning() then
        return false, "A WHO query is still active. Wait for results first."
    end

    local state   = runtime()
    local scan    = state.scan
    local pending = scan and scan.pendingQueries or {}

    if not scan or not scan.queryTest then
        return false, "No realm query test is active. Run /gc invitescan testrealm first."
    end

    if #pending == 0 then
        return false, "No pending realm query formats. Test is complete."
    end

    local nextItem  = table.remove(pending, 1)
    local nextQuery = queryText(nextItem)
    local newIndex  = (scan.queryIndex or 0) + 1

    scan.active        = true
    scan.query         = nextQuery
    scan.queryMeta     = nextItem
    scan.queryIndex    = newIndex
    scan.resultEventAt = nil
    scan.timedOut      = false

    GC.API.SetWhoToUi(true)
    return self:_sendQuery(nextItem, newIndex, scan.totalQueries or newIndex)
end

-- _sendQuery: internal, sends one WHO query and arms the timeout.
-- StartScan/NextQuery are user-triggered; auto advance is guarded and may pause
-- if Retail/Midnight rejects timer-initiated WHO requests.
function Scanner:_sendQuery(item, index, total, options)
    local query = queryText(item)
    local label = queryLabel(item)
    local state = runtime()
    local scan = state.scan or {}
    local band = levelBandLabel(item)

    scan.currentLevelBand = band
    scan.currentQueryLabel = query
    if band then
        scan.statusLine = string.format("Current WHO Query: %s  Scanning levels %s...", tostring(query), band)
    else
        scan.statusLine = string.format("Current WHO Query: %s  Scanning query %d...", tostring(query), tonumber(index) or 1)
    end
    scan.progressLine = string.format(
        "Scan Progress: processed %d / pending %d",
        tonumber(scan.processedQueries) or 0,
        #(scan.pendingQueries or {})
    )
    refreshInvitePanel()

    printLine(string.format(
        "Invite scan query %d/%d: %s",
        index, total, tostring(query)
    ))
    if label and label ~= query then
        printLine("  format:", tostring(label))
    end
    if type(item) == "table" and item.levelBand then
        printLine(string.format(
            "  current level band: %d-%d",
            tonumber(item.levelBand.min) or 0,
            tonumber(item.levelBand.max) or 0
        ))
    end
    if type(item) == "table" and item.className then
        printLine("  current class query:", tostring(item.className))
    end

    local ok, err = GC.API.SendWho(query)
    if not ok then
        scan.active = false
        local autoFailed = options and options.auto == true
        if autoFailed then
            scan.statusLine = "Auto scan paused. Click Scan Next to continue."
        else
            scan.statusLine = "WHO query failed. Click Scan Next to continue."
        end
        scan.autoPaused = autoFailed
        scan.autoAdvanceAttempting = false
        GC.API.SetWhoToUi(false)
        warnLine("WHO query failed:", tostring(err or "unknown error"))
        refreshInvitePanel()
        return false, err or "WHO query failed."
    end

    armTimeout(query)

    local pending = runtime().scan and runtime().scan.pendingQueries or {}
    if #pending > 0 then
        local scan = runtime().scan or {}
        if scan.queryTest then
            printLine(string.format(
                "  pending=%d  Run /gc invitescan testrealm next after results appear.",
                #pending
            ))
        else
            printLine(string.format(
                "  pending=%d  Run /gc invitescan next after results appear.",
                #pending
            ))
        end
    else
        printLine("  This is the last query.")
    end

    return true
end

-- HandleWhoListUpdate: called from Events.lua on WHO_LIST_UPDATE.
-- Collects results for the current query, then safely schedules the next query
-- when auto scan progression is enabled.
function Scanner:HandleWhoListUpdate()
    local state = runtime()
    if not state.scan or not state.scan.active then return end
    if state.scan.resultEventAt then return end  -- guard duplicate fires

    local query    = state.scan.query
    local index    = state.scan.queryIndex or 1
    local total    = state.scan.totalQueries or 1
    local pending  = state.scan.pendingQueries or {}

    state.scan.resultEventAt = now()
    cancelTimeout(state)

    printLine(string.format(
        "Invite scan WHO_LIST_UPDATE: query %d/%d done.",
        index, total
    ))

    -- Requires in-game testing: 0.2s delay for C_FriendList result population.
    C_Timer.After(0.2, function()
        local cur = runtime()
        if not cur.scan or cur.scan.query ~= query then return end

        local rawTotal, shown = GC.API.GetNumWhoResults()
        cur.scan.rawTotal = (cur.scan.rawTotal or 0) + (rawTotal or 0)
        cur.scan.rawShown = (cur.scan.rawShown or 0) + (shown or 0)
        printLine(string.format(
            "  WHO API counts: total=%d  shown=%d",
            rawTotal or 0,
            shown or 0
        ))
        printRawWhoRows(shown)

        local scannedAt      = now()
        local candidates     = cur.candidates     or {}
        local candidateByKey = cur.candidateByKey or {}
        local settings       = inviteSettings()
        local history        = inviteHistory()
        local filters        = GC.Modules.Invite and GC.Modules.Invite.Filters
        local effectiveGuildless = effectiveGuildlessOnly(settings, filters)
        local queryMeta      = cur.scan.queryMeta
        local threshold      = scanCapThreshold(settings)
        local saturated      = isSaturatedWhoResult(rawTotal, shown, threshold)

        printLine(string.format(
            "Invite filter settings: guildlessOnly=%s effectiveGuildlessOnly=%s",
            tostring(settings and settings.guildlessOnly),
            tostring(effectiveGuildless)
        ))

        local newThisQuery = 0
        local duplicateThisQuery = 0
        local realmFiltered = 0
        local guildFiltered = 0
        local hiddenIneligible = 0
        local evaluatedThisQuery = {}
        for i = 1, tonumber(shown or 0) do
            local candidate = normalizeCandidate(GC.API.GetWhoInfo(i), query, scannedAt)
            if candidate and candidate.key and not candidateByKey[candidate.key] then
                local realmAllowed = passesLocalRealmFilter(candidate, cur.scan.realmInfo)
                if filters and filters.EvaluateCandidate then
                    local res = filters.EvaluateCandidate(candidate, settings, history)
                    candidate.eligible          = res.eligible == true
                    candidate.ineligibleReasons = res.reasons or {}
                else
                    candidate.eligible          = false
                    candidate.ineligibleReasons = { "filters_unavailable" }
                end
                if not realmAllowed then
                    realmFiltered = realmFiltered + 1
                    candidate.eligible = false
                    candidate.selected = false
                    addReason(candidate, "wrong_realm")
                end
                if effectiveGuildless and hasGuild(candidate) then
                    candidate.eligible = false
                    addReason(candidate, "has_guild")
                    candidate.isGuildless = false
                end
                candidate.selected = candidate.eligible == true
                candidates[#candidates + 1]      = candidate
                candidateByKey[candidate.key]    = candidate
                newThisQuery = newThisQuery + 1
                evaluatedThisQuery[#evaluatedThisQuery + 1] = candidate
                if hasReason(candidate, "has_guild") then
                    guildFiltered = guildFiltered + 1
                end
                if candidate.eligible ~= true
                    and ((hasReason(candidate, "has_guild") and settings.showGuildedCandidates ~= true)
                        or (hasReason(candidate, "recently_invited") and settings.showRecentlyInvitedCandidates ~= true)
                        or (hasReason(candidate, "recently_declined") and settings.showRecentlyDeclinedCandidates ~= true)) then
                    hiddenIneligible = hiddenIneligible + 1
                end
            elseif candidate and candidate.key then
                duplicateThisQuery = duplicateThisQuery + 1
            end
        end

        cur.candidates     = candidates
        cur.candidateByKey = candidateByKey
        cur.scan.realmFiltered = (cur.scan.realmFiltered or 0) + realmFiltered
        cur.scan.guildFiltered = (cur.scan.guildFiltered or 0) + guildFiltered
        cur.scan.processedQueries = (cur.scan.processedQueries or 0) + 1

        local splitA, splitB
        if saturated and isAdaptiveItem(queryMeta) then
            splitA, splitB = splitAdaptiveRange(queryMeta, settings)
            if splitA and splitB then
                pending[#pending + 1] = splitA
                pending[#pending + 1] = splitB
                cur.scan.totalQueries = (cur.scan.totalQueries or 0) + 2
                cur.scan.lastSplitMessage = string.format(
                    "Range full, splitting into %s and %s.",
                    tostring(splitA.label or splitA.query),
                    tostring(splitB.label or splitB.query)
                )
                printLine(cur.scan.lastSplitMessage)
            else
                cur.scan.lastSplitMessage = "Range full, but max split depth or minimum range prevents further splitting."
                printLine(cur.scan.lastSplitMessage)
            end
        end

        -- Mark query complete. Adaptive scans may enqueue split ranges here, but
        -- the next WHO is still sent only by Scan/Scan Next unless safe
        -- auto-advance is enabled.
        cur.scan.active = false
        cur.scan.autoAdvanceAttempting = false
        cur.scan.autoAdvanceItem = nil
        cur.scan.autoAdvancePrevious = nil
        GC.API.SetWhoToUi(false)

        printLine(string.format(
            "  results: shown=%d  new=%d  total candidates=%d",
            shown or 0, newThisQuery, #candidates
        ))
        printLine(string.format(
            "  adaptive: threshold=%d saturated=%s duplicates=%d hiddenIneligible=%d pending=%d",
            threshold,
            tostring(saturated),
            duplicateThisQuery,
            hiddenIneligible,
            #pending
        ))
        printLine(string.format(
            "  local filters: removedByRealm=%d  removedByGuild=%d  eligible=%d",
            realmFiltered,
            guildFiltered,
            countEligible(candidates)
        ))
        printEvaluatedCandidates(evaluatedThisQuery)
        printRejectedCandidates(candidates)

        if isQuotedRealmQueryZero(cur.scan, query, rawTotal, shown, newThisQuery) then
            printLine('0 results for r-quoted realm query. Try /gc invitescan testrealm to compare query formats.')
        end

        if #pending > 0 then
            if cur.scan.queryTest then
                printLine(string.format(
                    "  pending=%d query format(s).  Run /gc invitescan testrealm next to continue.",
                    #pending
                ))
            elseif cur.scan.autoAdvanceEnabled ~= false and not cur.scan.autoPaused then
                local nextItem = pending[1]
                cur.scan.statusLine = string.format(
                    "%s Next query: %s",
                    tostring(cur.scan.lastSplitMessage or "Query complete."),
                    tostring(nextItem and (nextItem.label or nextItem.query) or "?")
                )
                cur.scan.progressLine = string.format(
                    "Scan Progress: processed %d / pending %d",
                    cur.scan.processedQueries or 0,
                    #pending
                )
                printLine(string.format(
                    "  pending=%d query(s). Auto scan will try the next band.",
                    #pending
                ))
                scheduleAutoAdvance(cur.scan)
            else
                printLine(string.format(
                    "  pending=%d query(s).  Run /gc invitescan next to continue.",
                    #pending
                ))
                local nextItem = pending[1]
                cur.scan.statusLine = string.format(
                    "%s Next query: %s",
                    tostring(cur.scan.lastSplitMessage or "Click Scan Next to continue."),
                    tostring(nextItem and (nextItem.label or nextItem.query) or "?")
                )
                cur.scan.progressLine = string.format(
                    "Scan Progress: processed %d / pending %d",
                    cur.scan.processedQueries or 0,
                    #pending
                )
                refreshInvitePanel()
            end
        else
            -- All queries done: print full summary.
            cur.scan.rejectionReasons = countRejectionReasons(candidates)
            cur.scan.completedAt      = scannedAt
            cur.scan.statusLine       = string.format(
                "Scan complete. Found: %d eligible candidates.",
                countEligible(candidates)
            )
            cur.scan.progressLine     = string.format(
                "Scan Progress: processed %d / pending 0",
                cur.scan.processedQueries or total
            )
            cur.scan.autoPaused       = false
            cancelAutoAdvance(cur)
            printCandidates(candidates)
            printEligibleCandidates(candidates)
            printFilterSummary(candidates)
            printLine(string.format(
                "Invite scan local filter totals: removedByRealm=%d removedByGuild=%d eligible=%d",
                cur.scan.realmFiltered or 0,
                cur.scan.guildFiltered or 0,
                countEligible(candidates)
            ))
            if cur.scan.queryTest then
                printLine("Invite realm query test complete. No guild invites sent.")
            else
                printLine("Invite scan complete. All queries scanned. No guild invites sent.")
            end
            refreshInvitePanel()
        end
    end)
end

function Scanner:HandleUIError(errorType, message)
    local text = tostring(message or errorType or "")
    if text == "" or not text:find("Interface action failed", 1, true) then return end

    local state = runtime()
    local scan = state.scan
    if not scan or not scan.autoAdvanceAttempting then return end

    cancelTimeout(state)
    cancelAutoAdvance(state)

    if scan.autoAdvanceItem then
        scan.pendingQueries = scan.pendingQueries or {}
        table.insert(scan.pendingQueries, 1, scan.autoAdvanceItem)
    end
    if scan.autoAdvancePrevious then
        scan.query = scan.autoAdvancePrevious.query
        scan.queryMeta = scan.autoAdvancePrevious.queryMeta
        scan.queryIndex = scan.autoAdvancePrevious.queryIndex
    end

    scan.autoAdvanceItem = nil
    scan.autoAdvancePrevious = nil
    pauseAutoAdvance(scan, "Auto scan paused. Click Scan Next to continue.")
end

GC.Modules.Invite.Scanner = setmetatable({}, Scanner)
GC:RegisterService("InviteScanner", GC.Modules.Invite.Scanner)

-- /GuildCore/Modules/Invite/Queue.lua
-- Invite queue service.
-- Dry run is available as an explicit safety mode. Live invites are only reached
-- from explicit user action after permission checks, and every queued item is
-- re-checked for guild/ineligible state before dispatch.
--
-- Queue item shape:
-- {
--   key         = candidate.key,
--   name        = candidate.name,
--   fullName    = candidate.fullName,
--   level       = candidate.level,
--   className   = candidate.className,
--   zone        = candidate.zone,
--   sourceQuery = candidate.sourceQuery,
--   status      = "queued",   -- "queued" | "dry_run_complete" | "skipped"
--   addedAt     = time(),
--   processedAt = nil,
--   result      = nil,        -- "would_invite" once processed
-- }
--
-- Requires in-game testing: real invite throttle, event payloads, and
-- permission behavior.

local addonName, ns = ...
local GC = ns.GuildCore

GC.Modules.Invite = GC.Modules.Invite or {}

local Queue = {}
Queue.__index = Queue

-- ── Constants ──────────────────────────────────────────────────────────────

local DELAY_MIN     = 3
local DELAY_MAX     = 30
local DELAY_DEFAULT = 3
local LIST_LIMIT    = 10
local markVisibleCandidate
local sessionStats
local refreshInvitePanel

-- ── Helpers ────────────────────────────────────────────────────────────────

local function now()
    return GC.Utils.Now()
end

local function printLine(...)
    GC:InviteDebug("debug", ...)
end

local function warnLine(...)
    GC:InviteDebug("warn", ...)
end

local function runtime()
    GC.State.invite         = GC.State.invite         or {}
    GC.State.invite.queue   = GC.State.invite.queue   or {}
    GC.State.invite.timers  = GC.State.invite.timers  or {}
    return GC.State.invite
end

local function scanner()
    return GC.Services and GC.Services.InviteScanner
end

local function inviteSettings()
    local svc = GC.Services and GC.Services.Invite
    local storage = svc and svc.GetStorage and svc:GetStorage()
    return storage and storage.settings or {}
end

local function getDelay()
    local settings = inviteSettings()
    local d = tonumber(settings.inviteDelaySeconds) or DELAY_DEFAULT
    return math.max(DELAY_MIN, math.min(DELAY_MAX, d))
end

local function getMaxPerSession()
    local settings = inviteSettings()
    return math.max(1, math.floor(tonumber(settings.maxPerSession) or 25))
end

local function rejectionReasons(candidate)
    if type(candidate) ~= "table" or type(candidate.ineligibleReasons) ~= "table" then
        return ""
    end
    return table.concat(candidate.ineligibleReasons, ",")
end

local function bannedEntryFor(candidate)
    if not (candidate and GC.BanBook and GC.BanBook.IsBanned) then
        return nil
    end
    local banned, entry = GC.BanBook:IsBanned(candidate.fullName or candidate.name or candidate.key, candidate.realm)
    return banned and entry or nil
end

local function markBannedSkipped(candidate)
    local entry = bannedEntryFor(candidate)
    if not entry then
        return false
    end
    if candidate then
        candidate.status = "skipped"
        candidate.result = "banned"
        candidate.processedAt = now()
        markVisibleCandidate(candidate, "skipped", "banned")
    end
    sessionStats().skipped = (sessionStats().skipped or 0) + 1
    warnLine("Skipped banned character:", tostring(entry.key or (candidate and (candidate.fullName or candidate.name or candidate.key))))
    refreshInvitePanel()
    return true, entry
end

local function hasGuild(candidate)
    return tostring((candidate and candidate.guild) or ""):match("^%s*(.-)%s*$") ~= ""
end

local function normalizeRealmKey(realm)
    if not realm or realm == "" then return nil end
    return tostring(realm):gsub("%s+", ""):lower()
end

local function realmAllowed(candidate)
    local realm = candidate and candidate.realm
    if (not realm or realm == "") and candidate and candidate.fullName then
        local _, parsedRealm = tostring(candidate.fullName):match("^([^%-]+)%-(.+)$")
        realm = parsedRealm
    end
    local candidateRealm = normalizeRealmKey(realm)
    if not candidateRealm then
        return true
    end

    local Realm = GC.Modules.Invite and GC.Modules.Invite.Realm
    local info = Realm and Realm.GetScanRealms and Realm.GetScanRealms(inviteSettings()) or nil
    if not info or type(info.scanRealms) ~= "table" then
        return false
    end

    for _, allowedRealm in ipairs(info.scanRealms) do
        if normalizeRealmKey(allowedRealm) == candidateRealm then
            return true
        end
    end
    return false
end

local function selectedEligibleCandidates(candidates)
    local selected = {}
    local total, selectedCount, eligibleSelected, skippedIneligible, skippedGuild = 0, 0, 0, 0, 0

    for _, candidate in ipairs(candidates or {}) do
        total = total + 1
        if candidate and candidate.selected == true then
            selectedCount = selectedCount + 1
            if hasGuild(candidate) then
                skippedGuild = skippedGuild + 1
                skippedIneligible = skippedIneligible + 1
            elseif candidate.eligible == true and realmAllowed(candidate) then
                eligibleSelected = eligibleSelected + 1
                selected[#selected + 1] = candidate
            else
                skippedIneligible = skippedIneligible + 1
            end
        end
    end

    return selected, {
        total = total,
        selected = selectedCount,
        eligibleSelected = eligibleSelected,
        skippedIneligible = skippedIneligible,
        skippedGuild = skippedGuild,
    }
end

sessionStats = function()
    local rt = runtime()
    rt.sessionStats = rt.sessionStats or {
        mode = "dry",
        sent = 0,
        declined = 0,
        failedApi = 0,
        noResponse = 0,
        skipped = 0,
        wouldInvite = 0,
    }
    return rt.sessionStats
end

local function pendingInviteCount()
    local history = GC.Services and GC.Services.InviteHistory
    if history and history.PendingCount then
        return history:PendingCount()
    end
    return 0
end

local function timeNow()
    if GetTime then
        return GetTime()
    end
    return now()
end

local function countQueuedItems()
    local count = 0
    for _, item in ipairs(runtime().queue or {}) do
        if item.status == "queued" or item.status == "sending" then
            count = count + 1
        end
    end
    return count
end

local function markRemainingSkipped(reason)
    for _, item in ipairs(runtime().queue or {}) do
        if item.status == "queued" or item.status == "sending" then
            item.status = "skipped"
            item.result = reason or "skipped"
            item.processedAt = now()
            markVisibleCandidate(item, "skipped", item.result)
        end
    end
end

local function removeVisibleCandidate(item)
    local svc = scanner()
    if svc and svc.RemoveCandidate then
        svc:RemoveCandidate(item.key)
    end
end

markVisibleCandidate = function(item, status, result)
    local svc = scanner()
    if svc and svc.MarkCandidateStatus then
        svc:MarkCandidateStatus(item.key, status, result)
    end
end

refreshInvitePanel = function()
    local panel = GC.UI and GC.UI.InvitePanel
    if panel and panel.Refresh then
        panel:Refresh()
    end
end

local function printSessionSummary()
    local stats = sessionStats()
    if stats.summaryPrinted then
        return
    end
    stats.summaryPrinted = true
    if stats.mode == "live" then
        GC:Print(string.format(
            "Invite session complete. Invites Sent: %d, Declined: %d, No Response Yet: %d, Skipped: %d.",
            stats.sent or 0,
            stats.declined or 0,
            stats.noResponse or 0,
            stats.skipped or 0
        ))
    else
        GC:Print(string.format(
            "Dry run complete. Would invite: %d, Skipped: %d.",
            stats.wouldInvite or 0,
            stats.skipped or 0
        ))
    end
end

local function maybePrintLiveSummary(queue)
    if queue and queue:GetStatus() == "running" then return end
    if pendingInviteCount() > 0 then
        if queue then queue:_setStatus("waiting") end
        refreshInvitePanel()
        return
    end
    if queue then queue:_setStatus("idle") end
    printSessionSummary()
    refreshInvitePanel()
end

-- ── Status accessors ───────────────────────────────────────────────────────

function Queue:GetItems()
    return runtime().queue
end

function Queue:GetStatus()
    return runtime().queueStatus or "idle"
end

function Queue:_setStatus(status)
    runtime().queueStatus = status
end

function Queue:IsRunning()
    return self:GetStatus() == "running"
end

function Queue:IsPaused()
    return self:GetStatus() == "paused"
end

-- ── Add candidates ─────────────────────────────────────────────────────────

-- Add a single candidate. Deduplicates by key. Returns ok, err.
function Queue:AddCandidate(candidate)
    if not candidate then
        return false, "Invalid candidate: missing key."
    end

    if candidate.eligible ~= true then
        local reasons = rejectionReasons(candidate)
        GC:InviteDebug("debug", 
            "Invite queue rejected ineligible:",
            tostring(candidate.fullName or candidate.name or candidate.key),
            reasons ~= "" and reasons or "no_reasons"
        )
        printLine(string.format(
            "Invite queue rejected ineligible: %s reasons=%s",
            tostring(candidate.fullName or candidate.name or candidate.key),
            reasons ~= "" and reasons or "no_reasons"
        ))
        return false, "ineligible"
    end

    if bannedEntryFor(candidate) then
        if candidate then
            candidate.eligible = false
            candidate.selected = false
            candidate.status = "skipped"
            candidate.result = "banned"
            markVisibleCandidate(candidate, "skipped", "banned")
        end
        warnLine("Skipped banned character:", tostring(candidate.fullName or candidate.name or candidate.key))
        return false, "banned"
    end

    if hasGuild(candidate) then
        printLine(string.format(
            "Invite queue rejected guilded candidate: %s guild=%s",
            tostring(candidate.fullName or candidate.name or candidate.key),
            tostring(candidate.guild or "")
        ))
        return false, "ineligible"
    end

    if not realmAllowed(candidate) then
        printLine(string.format(
            "Invite queue rejected wrong realm: %s realm=%s",
            tostring(candidate.fullName or candidate.name or candidate.key),
            tostring(candidate.realm or "")
        ))
        return false, "ineligible"
    end

    if not candidate.key then
        return false, "Invalid candidate: missing key."
    end

    local q = self:GetItems()
    for _, item in ipairs(q) do
        if item.key == candidate.key then
            return false, "duplicate"
        end
    end

    q[#q + 1] = {
        key         = candidate.key,
        name        = candidate.name,
        fullName    = candidate.fullName,
        level       = candidate.level,
        className   = candidate.className,
        zone        = candidate.zone,
        guild       = candidate.guild,
        eligible    = candidate.eligible == true,
        ineligibleReasons = candidate.ineligibleReasons,
        sourceQuery = candidate.sourceQuery,
        status      = "queued",
        addedAt     = now(),
        processedAt = nil,
        result      = nil,
    }
    candidate.status = "queued"
    candidate.selected = false
    markVisibleCandidate(candidate, "queued")
    return true
end

-- Add a list of candidates. Returns queued, duplicateSkipped, ineligibleSkipped.
function Queue:AddCandidates(candidates)
    local queued = 0
    local duplicates = 0
    local ineligible = 0
    for _, candidate in ipairs(candidates or {}) do
        local ok, err = self:AddCandidate(candidate)
        if ok then
            queued = queued + 1
        elseif err == "duplicate" then
            duplicates = duplicates + 1
            GC:InviteDebug("debug", "Invite queue skipped duplicate:", tostring(candidate and candidate.key))
        elseif err == "ineligible" or err == "banned" then
            ineligible = ineligible + 1
            GC:InviteDebug("debug", 
                "Invite queue skipped ineligible:",
                tostring(candidate and (candidate.fullName or candidate.name or candidate.key)),
                rejectionReasons(candidate)
            )
        else
            ineligible = ineligible + 1
            GC:InviteDebug("debug", "Invite queue skipped:", tostring(candidate and candidate.key), "-", tostring(err))
        end
    end
    return queued, duplicates, ineligible
end

-- ── Remove / clear ─────────────────────────────────────────────────────────

function Queue:Remove(candidateKey)
    local q = self:GetItems()
    for i = #q, 1, -1 do
        if q[i].key == candidateKey then
            table.remove(q, i)
            return true
        end
    end
    return false
end

function Queue:Clear()
    self:_cancelTimer()
    local rt = runtime()
    rt.queue         = {}
    rt.queueStatus   = "idle"
    rt.dryRunCount   = 0
    rt.sessionStats  = nil
    printLine("Invite queue cleared.")
end

-- ── Dry-run processing ─────────────────────────────────────────────────────

-- StartDryRun: process the queue one item at a time with throttled delays.
-- NEVER calls GC.API.GuildInvite or any real invite API.
-- Marks each item status = "dry_run_complete", result = "would_invite".
function Queue:StartDryRun()
    if self:IsRunning() then
        return false, "Dry run is already active."
    end

    local q = self:GetItems()
    if #q == 0 then
        return false, "Invite queue is empty."
    end

    -- Reset processed count for this run; preserve any already-completed items.
    local rt = runtime()
    rt.dryRunCount = 0
    rt.queueRunMode = "dry"
    rt.sessionStats = (rt.sessionStats and not rt.sessionStats.summaryPrinted and rt.sessionStats)
        or { mode = "dry", wouldInvite = 0, skipped = 0, failedApi = 0, noResponse = 0, sent = 0, declined = 0 }
    rt.sessionStats.mode = "dry"

    self:_setStatus("running")
    printLine(string.format("Invite dry run started. Queued: %d  Delay: %ds", #q, getDelay()))

    self:_scheduleDryRun(0)
    return true
end

function Queue:StartSelected(candidates, dryRun)
    local selected, stats = selectedEligibleCandidates(candidates)
    printLine(string.format(
        "Invite selected: total=%d selected=%d eligibleSelected=%d skippedIneligible=%d skippedHasGuild=%d dryRun=%s",
        stats.total,
        stats.selected,
        stats.eligibleSelected,
        stats.skippedIneligible,
        stats.skippedGuild,
        tostring(dryRun ~= false)
    ))

    self:Clear()
    runtime().sessionStats = {
        mode = dryRun ~= false and "dry" or "live",
        sent = 0,
        declined = 0,
        failedApi = 0,
        noResponse = 0,
        skipped = stats.skippedIneligible or 0,
        wouldInvite = 0,
    }
    local queued = self:AddCandidates(selected)
    if queued == 0 then
        return false, "No selected eligible candidates."
    end

    if dryRun ~= false then
        return self:StartDryRun()
    end

    return self:StartLiveRun()
end

function Queue:StartLiveRun()
    if self:IsRunning() then
        return false, "Invite queue is already running."
    end

    local canInvite, reason = GC.Permissions:CanInviteGuild()
    if not canInvite then
        return false, reason or "Guild invite permission is unavailable."
    end

    local q = self:GetItems()
    if #q == 0 then
        return false, "Invite queue is empty."
    end

    local rt = runtime()
    rt.liveInviteCount = 0
    rt.queueRunMode = "live"
    rt.sessionStats = (rt.sessionStats and not rt.sessionStats.summaryPrinted and rt.sessionStats)
        or { mode = "live", sent = 0, declined = 0, failedApi = 0, noResponse = 0, skipped = 0, wouldInvite = 0 }
    rt.sessionStats.mode = "live"
    self:_setStatus("running")
    printLine(string.format("Live invite run started. Queued: %d  Delay: %ds", #q, getDelay()))
    self:_scheduleLiveRun(0.1)
    return true
end

function Queue:InviteNow(candidate)
    if not candidate then
        return false, "No candidate selected."
    end

    local canInvite, reason = GC.Permissions:CanInviteGuild()
    if not canInvite then
        return false, reason or "Guild invite permission is unavailable."
    end

    local banned = bannedEntryFor(candidate)
    if banned then
        if candidate then
            candidate.eligible = false
            candidate.selected = false
            candidate.status = "skipped"
            candidate.result = "banned"
            candidate.processedAt = now()
            markVisibleCandidate(candidate, "skipped", "banned")
        end
        warnLine("Skipped banned character:", tostring(banned.key or candidate.fullName or candidate.name or candidate.key))
        refreshInvitePanel()
        return false, string.format("Cannot invite %s. Character is listed in Ban Book.", tostring(banned.key or candidate.fullName or candidate.name or candidate.key))
    end

    if hasGuild(candidate) then
        candidate.status = "skipped"
        candidate.result = "has_guild"
        candidate.processedAt = now()
        markVisibleCandidate(candidate, "skipped", "has_guild")
        refreshInvitePanel()
        return false, "Candidate is already in a guild."
    end

    if not realmAllowed(candidate) then
        candidate.status = "skipped"
        candidate.result = "wrong_realm"
        candidate.processedAt = now()
        markVisibleCandidate(candidate, "skipped", "wrong_realm")
        refreshInvitePanel()
        return false, "Candidate is outside the allowed invite realm."
    end

    if candidate.eligible ~= true then
        local reasonText = rejectionReasons(candidate)
        candidate.status = "skipped"
        candidate.result = reasonText ~= "" and reasonText or "ineligible"
        candidate.processedAt = now()
        markVisibleCandidate(candidate, "skipped", candidate.result)
        refreshInvitePanel()
        return false, "Candidate is not eligible."
    end

    candidate.status = "sending"
    candidate.result = nil
    markVisibleCandidate(candidate, "sending")

    local history = GC.Services and GC.Services.InviteHistory
    if history and history.TrackPending then
        history:TrackPending(candidate)
    end

    local target = candidate.fullName or candidate.name or candidate.key
    printLine("Direct invite dispatch:", tostring(target))

    local ok, err = GC.API.GuildInvite(target)
    candidate.processedAt = now()
    if ok then
        if candidate.status == "sending" then
            candidate.status = "pending"
            candidate.result = "pending_confirmation"
            markVisibleCandidate(candidate, "pending", "pending_confirmation")
        end
        printLine("Direct invite API call accepted:", tostring(target))
        refreshInvitePanel()
        return true
    end

    local resolved = false
    if history and history.Resolve then
        resolved = history:Resolve(candidate.key or target, "failed_api", err or "invite_failed")
    end
    if not resolved then
        self:ResolveInviteResult(candidate.key or target, "failed_api", err or "invite_failed", target)
    end
    warnLine("Direct invite failed:", tostring(target), tostring(err or "invite_failed"))
    refreshInvitePanel()
    return false, err or "invite_failed"
end

function Queue:ResolveInviteResult(candidateKey, status, message, fullName)
    if not candidateKey then return false, "missing_key" end

    local item
    for _, queued in ipairs(self:GetItems()) do
        if queued.key == candidateKey then
            item = queued
            break
        end
    end

    local stats = sessionStats()
    status = tostring(status or "unknown")

    if item then
        item.status = status
        item.result = status
        item.resultMessage = message
        item.processedAt = now()
    end

    if status == "invite_sent" or status == "sent" then
        if item and not item._sentCounted then
            stats.sent = (stats.sent or 0) + 1
            item._sentCounted = true
        elseif not item then
            stats.sent = (stats.sent or 0) + 1
        end
        removeVisibleCandidate(item or { key = candidateKey })
    elseif status == "declined" then
        if item and not item._declinedCounted then
            stats.declined = (stats.declined or 0) + 1
            item._declinedCounted = true
        elseif not item then
            stats.declined = (stats.declined or 0) + 1
        end
        markVisibleCandidate(item or { key = candidateKey }, "declined", status)
    elseif status == "no_response" then
        if item and item._sentCounted then
            printLine("Invite no-response ignored for already-sent invite:", tostring(fullName or item.fullName or candidateKey))
            return true
        elseif item and not item._noResponseCounted then
            stats.noResponse = (stats.noResponse or 0) + 1
            item._noResponseCounted = true
        elseif not item then
            stats.noResponse = (stats.noResponse or 0) + 1
        end
        markVisibleCandidate(item or { key = candidateKey }, "no_response", status)
    elseif status == "failed_api" then
        if item and not item._failedApiCounted then
            stats.failedApi = (stats.failedApi or 0) + 1
            stats.skipped = (stats.skipped or 0) + 1
            item._failedApiCounted = true
        elseif not item then
            stats.failedApi = (stats.failedApi or 0) + 1
            stats.skipped = (stats.skipped or 0) + 1
        end
        markVisibleCandidate(item or { key = candidateKey }, "failed_api", status)
    else
        if item and not item._failedApiCounted then
            stats.failedApi = (stats.failedApi or 0) + 1
            stats.skipped = (stats.skipped or 0) + 1
            item._failedApiCounted = true
        elseif not item then
            stats.failedApi = (stats.failedApi or 0) + 1
            stats.skipped = (stats.skipped or 0) + 1
        end
        markVisibleCandidate(item or { key = candidateKey }, status, status)
    end

    GC:InviteDebug(
        "debug",
        "Invite queue result:",
        tostring(fullName or (item and item.fullName) or candidateKey),
        tostring(status),
        tostring(message or "")
    )

    if self:GetStatus() == "waiting" or self:GetStatus() == "idle" then
        maybePrintLiveSummary(self)
    else
        refreshInvitePanel()
    end

    return true
end

function Queue:Pause()
    if not self:IsRunning() then return end
    self:_cancelTimer()
    self:_setStatus("paused")
    printLine("Invite queue paused.")
end

function Queue:Resume()
    if not self:IsPaused() then return end

    local q = self:GetItems()
    local pending = 0
    for _, item in ipairs(q) do
        if item.status == "queued" then
            pending = pending + 1
        end
    end

    if pending == 0 then
        self:_setStatus("idle")
        printLine("Invite queue: nothing left to resume.")
        return
    end

    self:_setStatus("running")
    printLine("Invite queue resumed.")
    if runtime().queueRunMode == "live" then
        self:_scheduleLiveRun(0.1)
    else
        self:_scheduleDryRun(0)
    end
end

function Queue:Cancel()
    self:_cancelTimer()
    self:_setStatus("idle")
    printLine("Invite queue cancelled.")
end

-- ── Internal scheduling ────────────────────────────────────────────────────

function Queue:_cancelTimer()
    local rt = runtime()
    if rt.timers and rt.timers.dryRun then
        rt.timers.dryRun:Cancel()
        rt.timers.dryRun = nil
    end
    if rt.timers and rt.timers.liveRun then
        rt.timers.liveRun:Cancel()
        rt.timers.liveRun = nil
    end
    rt.nextLiveDispatchAt = nil
end

function Queue:_scheduleDryRun(delay)
    local rt = runtime()
    if rt.timers and rt.timers.dryRun then
        rt.timers.dryRun:Cancel()
        rt.timers.dryRun = nil
    end
    rt.timers = rt.timers or {}
    local scheduledDelay = tonumber(delay)
    if scheduledDelay == nil then scheduledDelay = getDelay() end
    rt.timers.dryRun = C_Timer.NewTimer(scheduledDelay, function()
        runtime().timers.dryRun = nil
        Queue:_processDryRunNext()
    end)
end

function Queue:_scheduleLiveRun(delay)
    local rt = runtime()
    if rt.timers and rt.timers.liveRun then
        rt.timers.liveRun:Cancel()
        rt.timers.liveRun = nil
    end
    rt.timers = rt.timers or {}
    local scheduledDelay = tonumber(delay)
    if scheduledDelay == nil then scheduledDelay = getDelay() end
    rt.nextLiveDispatchAt = timeNow() + scheduledDelay
    printLine(string.format(
        "Live invite next dispatch scheduled in %.1fs. Remaining queued: %d",
        scheduledDelay,
        countQueuedItems()
    ))
    rt.timers.liveRun = C_Timer.NewTimer(scheduledDelay, function()
        local liveRt = runtime()
        liveRt.timers.liveRun = nil
        liveRt.nextLiveDispatchAt = nil
        Queue:_processLiveNext()
    end)
end

function Queue:_processLiveNext()
    if not self:IsRunning() then return end

    local maxPerSession = getMaxPerSession()
    local rt = runtime()
    if (rt.liveInviteCount or 0) >= maxPerSession then
        self:_setStatus("idle")
        local remaining = countQueuedItems()
        sessionStats().skipped = (sessionStats().skipped or 0) + remaining
        markRemainingSkipped("max_per_session")
        warnLine("Live invite run stopped: max per session reached.")
        maybePrintLiveSummary(self)
        return
    end

    local item = nil
    for _, candidate in ipairs(self:GetItems()) do
        if candidate.status == "queued" then
            item = candidate
            break
        end
    end

    if not item then
        printLine(string.format("Live invite run complete. Invites attempted: %d", rt.liveInviteCount or 0))
        if pendingInviteCount() > 0 then
            self:_setStatus("waiting")
            printLine(string.format("Waiting for %d pending invite result(s).", pendingInviteCount()))
            refreshInvitePanel()
        else
            self:_setStatus("idle")
            printSessionSummary()
            refreshInvitePanel()
        end
        return
    end

    if item.guild and tostring(item.guild):match("^%s*(.-)%s*$") ~= "" then
        item.status = "skipped"
        item.result = "has_guild"
        item.processedAt = now()
        sessionStats().skipped = (sessionStats().skipped or 0) + 1
        markVisibleCandidate(item, "skipped", "has_guild")
        warnLine("Live invite blocked guilded candidate:", tostring(item.fullName or item.name or item.key))
        self:_scheduleLiveRun(0.1)
        refreshInvitePanel()
        return
    end

    if markBannedSkipped(item) then
        self:_scheduleLiveRun(0.1)
        return
    end

    if not realmAllowed(item) then
        item.status = "skipped"
        item.result = "wrong_realm"
        item.processedAt = now()
        sessionStats().skipped = (sessionStats().skipped or 0) + 1
        markVisibleCandidate(item, "skipped", "wrong_realm")
        warnLine("Live invite blocked wrong-realm candidate:", tostring(item.fullName or item.name or item.key))
        self:_scheduleLiveRun(0.1)
        refreshInvitePanel()
        return
    end

    if item.eligible ~= true then
        item.status = "skipped"
        item.result = rejectionReasons(item) ~= "" and rejectionReasons(item) or "ineligible"
        item.processedAt = now()
        sessionStats().skipped = (sessionStats().skipped or 0) + 1
        markVisibleCandidate(item, "skipped", item.result)
        warnLine("Live invite blocked ineligible candidate:", tostring(item.fullName or item.name or item.key), tostring(item.result))
        self:_scheduleLiveRun(0.1)
        refreshInvitePanel()
        return
    end

    item.status = "sending"
    markVisibleCandidate(item, "sending")
    local history = GC.Services and GC.Services.InviteHistory
    if history and history.TrackPending then
        history:TrackPending(item)
    end
    printLine(string.format(
        "Live invite dispatch at %.3f: %s remaining=%d",
        timeNow(),
        tostring(item.fullName or item.name or item.key),
        math.max(0, countQueuedItems() - 1)
    ))
    local ok, err = GC.API.GuildInvite(item.fullName or item.name or item.key)
    item.processedAt = now()
    if ok then
        rt.liveInviteCount = (rt.liveInviteCount or 0) + 1
        -- GuildInvite may synchronously trigger the Blizzard success message
        -- before this call returns. Never overwrite invite_sent back to pending.
        if item.status ~= "invite_sent" and item.status ~= "sent" then
            local resolved = false
            if history and history.Resolve then
                resolved = history:Resolve(item.key, "invite_sent", "GuildInvite API accepted.")
            end
            if not resolved then
                self:ResolveInviteResult(item.key, "invite_sent", "GuildInvite API accepted.", item.fullName or item.name or item.key)
            end
        end
        printLine("Live invite API call accepted:", tostring(item.fullName or item.name or item.key))
    else
        local resolved = false
        if history and history.Resolve then
            resolved = history:Resolve(item.key, "failed_api", err or "invite_failed")
        end
        if not resolved then
            self:ResolveInviteResult(item.key, "failed_api", err or "invite_failed", item.fullName or item.name or item.key)
        end
        if item.status ~= "failed_api" then
            item.status = "failed_api"
            item.result = err or "invite_failed"
            markVisibleCandidate(item, "failed_api", item.result)
        end
        warnLine("Live invite failed:", tostring(item.fullName or item.name or item.key), tostring(item.result))
    end

    refreshInvitePanel()
    self:_scheduleLiveRun(getDelay())
end

function Queue:_processDryRunNext()
    if not self:IsRunning() then return end

    local q   = self:GetItems()
    local rt  = runtime()
    local item = nil

    if (rt.dryRunCount or 0) >= getMaxPerSession() then
        self:_setStatus("idle")
        local remaining = countQueuedItems()
        sessionStats().skipped = (sessionStats().skipped or 0) + remaining
        markRemainingSkipped("max_per_session")
        warnLine("Invite dry run stopped: max per session reached.")
        printSessionSummary()
        refreshInvitePanel()
        return
    end

    -- Find next unprocessed item.
    for _, candidate in ipairs(q) do
        if candidate.status == "queued" then
            item = candidate
            break
        end
    end

    if not item then
        self:_setStatus("idle")
        printLine(string.format(
            "Invite dry run complete. Would have invited: %d",
            rt.dryRunCount or 0
        ))
        printSessionSummary()
        refreshInvitePanel()
        return
    end

    -- DRY RUN ONLY — no real invite API call.
    -- Requires in-game testing before real invites are dispatched.
    item.status      = "dry_run_complete"
    item.result      = "would_invite"
    item.processedAt = now()
    rt.dryRunCount   = (rt.dryRunCount or 0) + 1
    sessionStats().wouldInvite = (sessionStats().wouldInvite or 0) + 1
    removeVisibleCandidate(item)

    printLine(string.format(
        "[DRY RUN] Would invite: %s  level=%s  class=%s  zone=%s",
        tostring(item.fullName or item.name or item.key),
        tostring(item.level or "?"),
        tostring(item.className or ""),
        tostring(item.zone or "")
    ))

    refreshInvitePanel()
    self:_scheduleDryRun(getDelay())
end

-- ── List / status summary ──────────────────────────────────────────────────

function Queue:PrintList()
    local q = self:GetItems()
    if #q == 0 then
        GC:Print("Invite queue is empty.")
        return
    end

    local queued, completed = 0, 0
    for _, item in ipairs(q) do
        if item.status == "queued" then
            queued = queued + 1
        else
            completed = completed + 1
        end
    end

    GC:Print(string.format(
        "Invite queue: status=%s  total=%d  queued=%d  completed=%d  delay=%ds",
        self:GetStatus(), #q, queued, completed, getDelay()
    ))

    local shown = 0
    for _, item in ipairs(q) do
        shown = shown + 1
        GC:Print(string.format(
            "  %d. [%s] %s  level=%s  class=%s",
            shown,
            tostring(item.status),
            tostring(item.fullName or item.name or item.key),
            tostring(item.level or "?"),
            tostring(item.className or "")
        ))
        if shown >= LIST_LIMIT then
            if #q > LIST_LIMIT then
                GC:Print("  ... and " .. tostring(#q - LIST_LIMIT) .. " more")
            end
            break
        end
    end
end

-- ── Registration ──────────────────────────────────────────────────────────

GC.Modules.Invite.Queue = setmetatable({}, Queue)
GC:RegisterService("InviteQueue", GC.Modules.Invite.Queue)

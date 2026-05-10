-- /GuildCore/Modules/Invite/History.lua
-- Runtime invite outcome tracker.
--
-- Blizzard exposes most guild-invite outcomes as localized system messages.
-- The English patterns below match observed Retail/Midnight text, but
-- localized parsing requires additional testing.

local addonName, ns = ...
local GC = ns.GuildCore

GC.Modules.Invite = GC.Modules.Invite or {}

local History = {}
History.__index = History

local function now()
    return GC.Utils.Now()
end

local function runtime()
    GC.State.invite = GC.State.invite or {}
    GC.State.invite.pendingInvites = GC.State.invite.pendingInvites or {}
    GC.State.invite.pendingInviteAliases = GC.State.invite.pendingInviteAliases or {}
    GC.State.invite.timers = GC.State.invite.timers or {}
    GC.State.invite.timers.pendingInviteTimeouts = GC.State.invite.timers.pendingInviteTimeouts or {}
    return GC.State.invite
end

local function settings()
    local svc = GC.Services and GC.Services.Invite
    local storage = svc and svc.GetStorage and svc:GetStorage()
    return storage and storage.settings or {}
end

local function normalizeName(name)
    if not name or name == "" then return nil end
    if GC.API and GC.API.NormalizePlayerName then
        return GC.API.NormalizePlayerName(name)
    end
    return tostring(name)
end

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$") or ""
end

local function lower(value)
    return trim(value):lower()
end

local function shortKey(value)
    local name = trim(value)
    local short = name:match("^([^%-]+)%-") or name
    return short ~= "" and short:lower() or nil
end

local function aliasKey(value)
    local text = lower(value)
    return text ~= "" and text or nil
end

local function addAlias(aliases, value)
    local alias = aliasKey(value)
    if alias then
        aliases[alias] = true
    end
    local short = shortKey(value)
    if short then
        aliases[short] = true
    end
end

local function findQueueKey(name)
    local rt = runtime()
    local wanted = aliasKey(name)
    local wantedShort = shortKey(name)
    if not wanted and not wantedShort then return nil end

    for _, item in ipairs(rt.queue or {}) do
        local itemKey = item and item.key
        local itemFull = item and item.fullName
        local itemName = item and item.name
        if itemKey and (
            aliasKey(itemKey) == wanted
            or aliasKey(itemFull) == wanted
            or aliasKey(itemName) == wanted
            or shortKey(itemKey) == wantedShort
            or shortKey(itemFull) == wantedShort
            or shortKey(itemName) == wantedShort
        ) then
            return itemKey
        end
    end

    return nil
end

local function timeoutSeconds()
    local value = tonumber(settings().inviteResponseTimeoutSeconds) or 20
    return math.max(5, math.min(120, value))
end

local function cancelTimeout(key)
    local rt = runtime()
    local timer = rt.timers.pendingInviteTimeouts[key]
    if timer and timer.Cancel then
        timer:Cancel()
    end
    rt.timers.pendingInviteTimeouts[key] = nil
end

local function recordStorage(status, fullName, message)
    local svc = GC.Services and GC.Services.Invite
    if not svc then return end

    if status == "invite_sent" or status == "sent" then
        svc:RecordRecentInvite(fullName, "sent")
    elseif status == "declined" then
        svc:RecordRecentDecline(fullName, "declined")
    elseif status == "already_in_guild" then
        svc:RecordRecentInvite(fullName, "already_in_guild")
    elseif status == "already_invited" then
        svc:RecordRecentInvite(fullName, "already_invited")
    elseif status == "offline" then
        svc:RecordRecentInvite(fullName, "offline")
    elseif status == "throttled"
        or status == "failed_api"
        or status == "failed"
        or status == "unknown"
        or status == "no_response"
        or status == "unknown_timeout" then
        svc:RecordRecentInvite(fullName, status)
    end

    if svc.AppendHistory then
        svc:AppendHistory("inviteResult", normalizeName(fullName) or fullName, {
            status = status,
            message = message,
        })
    end
end

local function refreshInvitePanel()
    local panel = GC.UI and GC.UI.InvitePanel
    if panel and panel.Refresh then
        panel:Refresh()
    end
end

function History:GetPending()
    return runtime().pendingInvites
end

function History:HasPending()
    for _ in pairs(runtime().pendingInvites or {}) do
        return true
    end
    return false
end

function History:PendingCount()
    local count = 0
    for _ in pairs(runtime().pendingInvites or {}) do
        count = count + 1
    end
    return count
end

function History:TrackPending(candidate)
    local fullName = candidate and (candidate.fullName or candidate.name or candidate.key)
    local key = candidate and (candidate.key or normalizeName(fullName))
    if not key or not fullName then
        return false, "missing_name"
    end

    local rt = runtime()
    local aliases = {}
    addAlias(aliases, key)
    addAlias(aliases, fullName)
    addAlias(aliases, candidate.name)
    addAlias(aliases, GC.API and GC.API.FormatNameForGuildInvite and GC.API.FormatNameForGuildInvite(fullName))

    rt.pendingInvites[key] = {
        key = key,
        fullName = fullName,
        sentAt = now(),
        status = "pending",
        aliases = aliases,
    }
    for alias in pairs(aliases) do
        rt.pendingInviteAliases[alias] = key
    end

    cancelTimeout(key)
    rt.timers.pendingInviteTimeouts[key] = C_Timer.NewTimer(timeoutSeconds(), function()
        local svc = GC.Services and GC.Services.InviteHistory
        if svc then
            svc:Resolve(key, "no_response", "Invite response timed out.")
        end
    end)

    GC:InviteDebug("debug", "Invite pending:", tostring(fullName), "timeout=", tostring(timeoutSeconds()))
    return true, key
end

function History:FindPendingKey(name)
    local rt = runtime()
    local pending = rt.pendingInvites
    local normalized = normalizeName(name)
    if normalized and pending[normalized] then
        return normalized
    end

    local alias = aliasKey(name)
    if alias and rt.pendingInviteAliases and rt.pendingInviteAliases[alias] then
        return rt.pendingInviteAliases[alias]
    end

    local normalizedAlias = aliasKey(normalized)
    if normalizedAlias and rt.pendingInviteAliases and rt.pendingInviteAliases[normalizedAlias] then
        return rt.pendingInviteAliases[normalizedAlias]
    end

    local wantedLower = lower(name)
    local wantedShort = shortKey(name)
    for key, entry in pairs(pending or {}) do
        if lower(entry.fullName) == wantedLower
            or lower(key) == wantedLower
            or shortKey(entry.fullName) == wantedShort
            or shortKey(key) == wantedShort then
            return key
        end
    end

    return normalized
end

local function clearPending(key, entry)
    local rt = runtime()
    rt.pendingInvites[key] = nil
    if entry and type(entry.aliases) == "table" then
        for alias in pairs(entry.aliases) do
            if rt.pendingInviteAliases then
                rt.pendingInviteAliases[alias] = nil
            end
        end
    end
    cancelTimeout(key)
end

function History:Resolve(keyOrName, status, message)
    local key = self:FindPendingKey(keyOrName) or keyOrName
    if not key then return false, "missing_key" end

    local pending = runtime().pendingInvites
    local entry = pending[key]
    if not entry then
        local queueKey = findQueueKey(keyOrName)
        if not queueKey then
            return false, "not_pending"
        end
        local pendingKey = self:FindPendingKey(queueKey)
        if pendingKey and pending[pendingKey] then
            key = pendingKey
            entry = pending[key]
        else
            key = queueKey
        end
    end
    local fullName = entry and entry.fullName or keyOrName

    if entry then
        entry.status = status
        entry.resolvedAt = now()
    end

    -- "You have invited X" is the reliable dispatch confirmation for queue
    -- accounting. Do not leave it pending, or it will timeout as a false failure.
    -- If Blizzard later emits a decline line, CaptureSystemMessage records that
    -- separately in recent decline history when possible.
    clearPending(key, entry)

    recordStorage(status, fullName, message)

    local queue = GC.Services and GC.Services.InviteQueue
    if queue and queue.ResolveInviteResult then
        queue:ResolveInviteResult(key, status, message, fullName)
    end

    GC:InviteDebug("debug", "Invite result:", tostring(fullName), tostring(status), tostring(message or ""))
    refreshInvitePanel()
    return true
end

local function parseSystemMessage(message)
    local text = trim(message)
    if text == "" then return nil end

    -- Localized parsing requires additional testing.
    local name = text:match("^You have invited%s+(.+)%s+to join your guild%.$")
    if name then return "invite_sent", name end

    name = text:match("^(.+)%s+has joined the guild%.$")
        or text:match("^(.+)%s+joined the guild%.$")
    if name then return "sent", name end

    name = text:match("^(.+)%s+declines your guild invitation%.$")
    if name then return "declined", name end

    name = text:match("^(.+)%s+is already in a guild%.$")
        or text:match("^(.+)%s+is already in your guild%.$")
    if name then return "already_in_guild", name end

    name = text:match("^(.+)%s+has already been invited to a guild%.$")
        or text:match("^(.+)%s+is already invited to a guild%.$")
        or text:match("^(.+)%s+has already been invited%.$")
    if name then return "already_invited", name end

    name = text:match("^Player not found:%s+(.+)%.$")
        or text:match("^No player named ['\"]?([^'\"]+)['\"]? is currently playing%.$")
    if name then return "offline", name end

    local low = text:lower()
    if low:find("too many", 1, true) or low:find("throttle", 1, true) or low:find("try again later", 1, true) then
        return "throttled", nil
    end

    if low:find("guild invitation", 1, true) and (low:find("failed", 1, true) or low:find("unable", 1, true)) then
        return "failed_api", nil
    end

    return nil
end

function History:CaptureSystemMessage(message)
    GC:InviteDebug("debug", "Invite system raw:", tostring(message or ""))

    local status, name = parseSystemMessage(message)
    if not status then return false end

    GC:InviteDebug("debug", "Invite system parsed:", tostring(status), tostring(name or "(no name)"))

    if status == "declined" and name then
        local pendingKey = self:FindPendingKey(name)
        if not (pendingKey and runtime().pendingInvites[pendingKey]) then
            recordStorage("declined", name, message)
            local queueKey = findQueueKey(name)
            local queue = GC.Services and GC.Services.InviteQueue
            if queueKey and queue and queue.ResolveInviteResult then
                queue:ResolveInviteResult(queueKey, "declined", message, name)
                refreshInvitePanel()
            end
            return true
        end
    end

    if name then
        return self:Resolve(name, status, message)
    end

    local pendingCount = self:PendingCount()
    if pendingCount == 1 then
        for key in pairs(self:GetPending()) do
            return self:Resolve(key, status, message)
        end
    end

    return false, "ambiguous_pending"
end

function History:CaptureUIError(errorType, message)
    local text = trim(message or errorType)
    if text == "" then return false end
    local low = text:lower()
    local status

    -- Localized parsing requires additional testing.
    if low:find("interface action failed because of an addon", 1, true) then
        -- Generic protected-action warnings can appear alongside a successful
        -- invite system message. They are not reliable invite failures.
        GC:InviteDebug("debug", "Invite UI error ignored:", tostring(text))
        return false
    elseif low:find("too many", 1, true) or low:find("throttle", 1, true) or low:find("try again later", 1, true) then
        status = "throttled"
    elseif low:find("offline", 1, true) or low:find("not found", 1, true) then
        status = "offline"
    elseif low:find("already", 1, true) and low:find("guild", 1, true) then
        status = "already_in_guild"
    elseif low:find("invite", 1, true) or low:find("guild", 1, true) then
        status = "failed_api"
    else
        return false
    end

    GC:InviteDebug("debug", "Invite UI error parsed:", tostring(status), tostring(text))

    if self:PendingCount() == 1 then
        for key in pairs(self:GetPending()) do
            return self:Resolve(key, status, text)
        end
    end

    return false, "ambiguous_pending"
end

GC.Modules.Invite.History = setmetatable({}, History)
GC:RegisterService("InviteHistory", GC.Modules.Invite.History)

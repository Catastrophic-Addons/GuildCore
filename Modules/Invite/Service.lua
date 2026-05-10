-- /GuildCore/Modules/Invite/Service.lua
-- Phase 2 storage/runtime service for the future Invite module.
local addonName, ns = ...
local GC = ns.GuildCore

GC.Modules.Invite = GC.Modules.Invite or {}
GC.State.invite = GC.State.invite or {
    scan = {},
    candidates = {},
    queue = {},
    pending = {},
    pendingInvites = {},
    timers = {},
}

local InviteService = {}
InviteService.__index = InviteService

local function now()
    return GC.Utils.Now()
end

local function guild()
    return GC.DB:GetGuild()
end

local function inviteState()
    local db = guild()
    return db and db.invite or nil
end

local function canonicalName(name)
    return GC.API.NormalizePlayerName(name)
end

function InviteService:IsEnabled()
    local settings = GC.DB:GetSettings()
    return not settings or settings.enableInviteModule ~= false
end

function InviteService:GetStorage()
    return inviteState()
end

function InviteService:GetSettings()
    local state = inviteState()
    return state and state.settings or nil
end

function InviteService:SetSetting(key, value)
    local settings = self:GetSettings()
    if not settings or not key then
        return false, "Invite settings are unavailable."
    end

    settings[key] = value
    return true
end

function InviteService:GetRuntimeState()
    GC.State.invite = GC.State.invite or {}
    GC.State.invite.scan = GC.State.invite.scan or {}
    GC.State.invite.candidates = GC.State.invite.candidates or {}
    GC.State.invite.queue = GC.State.invite.queue or {}
    GC.State.invite.pending = GC.State.invite.pending or {}
    GC.State.invite.pendingInvites = GC.State.invite.pendingInvites or {}
    GC.State.invite.timers = GC.State.invite.timers or {}
    return GC.State.invite
end

function InviteService:ResetRuntimeState()
    local runtime = self:GetRuntimeState()
    runtime.scan = {}
    runtime.candidates = {}
    runtime.queue = {}
    runtime.pending = {}
    runtime.pendingInvites = {}
    for _, timer in pairs(runtime.timers or {}) do
        if timer and timer.Cancel then
            timer:Cancel()
        end
    end
    runtime.timers = {}
end

function InviteService:GetIgnored()
    local state = inviteState()
    return state and state.ignored or nil
end

function InviteService:IsIgnored(name)
    local ignored = self:GetIgnored()
    local key = canonicalName(name)
    return ignored and key and ignored.names[key] == true
end

function InviteService:SetIgnored(name, reason)
    local ignored = self:GetIgnored()
    local key = canonicalName(name)
    if not ignored or not key then
        return false, "Player name is unavailable."
    end

    ignored.names[key] = true
    ignored.reasons[key] = tostring(reason or "")
    self:AppendHistory("ignored", key, { reason = ignored.reasons[key] })
    return true
end

function InviteService:ClearIgnored(name)
    local ignored = self:GetIgnored()
    local key = canonicalName(name)
    if not ignored or not key then
        return false, "Player name is unavailable."
    end

    ignored.names[key] = nil
    ignored.reasons[key] = nil
    self:AppendHistory("unignored", key)
    return true
end

function InviteService:RecordRecentInvite(name, outcome)
    local state = inviteState()
    local key = canonicalName(name)
    if not state or not key then
        return false, "Player name is unavailable."
    end

    state.recentInvites[key] = {
        at = now(),
        outcome = tostring(outcome or "attempted"),
    }
    self:AppendHistory("recentInvite", key, { outcome = outcome or "attempted" })
    return true
end

-- Requires in-game testing: Blizzard's exact declined-invite event payloads
-- can vary. This placeholder stores only confirmed decline outcomes when a
-- future event handler can identify the target safely.
function InviteService:RecordRecentDecline(name, outcome)
    local state = inviteState()
    local key = canonicalName(name)
    if not state or not key then
        return false, "Player name is unavailable."
    end

    state.recentDeclines = state.recentDeclines or {}
    state.recentDeclines[key] = {
        at = now(),
        outcome = tostring(outcome or "declined"),
    }
    self:AppendHistory("recentDecline", key, { outcome = outcome or "declined" })
    return true
end

function InviteService:WasRecentlyDeclined(name)
    local state = inviteState()
    local settings = self:GetSettings()
    local key = canonicalName(name)
    if not state or not settings or not key then
        return false
    end

    local entry = state.recentDeclines and state.recentDeclines[key]
    if type(entry) ~= "table" or not tonumber(entry.at) then
        return false
    end

    local window = math.max(1, tonumber(settings.recentInviteDays) or 30) * 86400
    return (now() - entry.at) < window
end

function InviteService:WasRecentlyInvited(name)
    local state = inviteState()
    local settings = self:GetSettings()
    local key = canonicalName(name)
    if not state or not settings or not key then
        return false
    end

    local entry = state.recentInvites[key]
    if type(entry) ~= "table" or not tonumber(entry.at) then
        return false
    end

    local window = math.max(1, tonumber(settings.recentInviteDays) or 30) * 86400
    return (now() - entry.at) < window
end

function InviteService:AppendHistory(kind, name, details)
    local state = inviteState()
    if not state then
        return false
    end

    state.history = state.history or {}
    state.history[#state.history + 1] = {
        kind = tostring(kind or "event"),
        name = name,
        at = now(),
        details = type(details) == "table" and details or nil,
    }

    while #state.history > 500 do
        table.remove(state.history, 1)
    end

    return true
end

function InviteService:PruneHistory()
    local state = inviteState()
    local settings = self:GetSettings()
    if not state or not settings then
        return 0
    end

    local cutoff = now() - (math.max(1, tonumber(settings.recentInviteDays) or 30) * 86400)
    local removed = 0
    for name, entry in pairs(state.recentInvites or {}) do
        if type(entry) ~= "table" or not tonumber(entry.at) or entry.at < cutoff then
            state.recentInvites[name] = nil
            removed = removed + 1
        end
    end
    for name, entry in pairs(state.recentDeclines or {}) do
        if type(entry) ~= "table" or not tonumber(entry.at) or entry.at < cutoff then
            state.recentDeclines[name] = nil
            removed = removed + 1
        end
    end
    state.meta = state.meta or {}
    state.meta.lastPrunedAt = now()
    return removed
end

GC:RegisterService("Invite", setmetatable({}, InviteService))

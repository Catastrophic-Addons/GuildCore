-- /GuildCore/Core/Init.lua
local addonName, ns = ...

ns.GuildCore = ns.GuildCore or {}
local GC = ns.GuildCore

GC.Name = "Guild Core"
GC.AddonName = addonName
GC.Version = C_AddOns and C_AddOns.GetAddOnMetadata(addonName, "Version") or "dev"

GC.Modules = GC.Modules or {}
GC.Services = GC.Services or {}
GC.UI = GC.UI or {}
GC.State = GC.State or {
    initialized     = false,
    rosterTicker    = nil,
    pendingScanReason = nil,   -- set when GuildRoster() is requested proactively
    actionMacroOwner = nil,
    actionMacroExecuted = false,
    actionMacroOwnerExecuted = nil,
    actionMacroExecutedAt = nil,
}

function GC:Print(...)
    print("|cff4fd1c5Guild Core:|r", ...)
end

function GC:Debug(...)
    local settings = self.DB and self.DB.GetSettings and self.DB:GetSettings()
    if settings and settings.debugMode then
        self:Print(...)
    end
end

local INVITE_WARNING_LEVELS = {
    warn = true,
    warning = true,
    error = true,
}

function GC:IsInviteDebugEnabled()
    local service = self.Services and self.Services.Invite
    local settings = service and service.GetSettings and service:GetSettings() or nil
    return settings and settings.debugEnabled == true
end

function GC:InviteDebug(level, ...)
    if not INVITE_WARNING_LEVELS[level] then
        if select("#", ...) == 0 then
            return self:InviteDebug("debug", level)
        end
        if not self:IsInviteDebugEnabled() then
            return
        end
        self:Print(...)
        return
    end

    self:Print(...)
end

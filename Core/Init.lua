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

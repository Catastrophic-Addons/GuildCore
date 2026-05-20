-- /GuildCore/UI/SettingsPanel.lua
-- Compatibility shim: MainFrame still talks to GC.UI.SettingsPanel while the
-- implementation now lives in UI/Settings/*.
local addonName, ns = ...
local GC = ns.GuildCore

GC.UI = GC.UI or {}
GC.UI.SettingsPanel = GC.UI.SettingsPanel or {}
local SP = GC.UI.SettingsPanel

function SP:Create(parent)
    if not GC.Settings or not GC.Settings.Create then return end
    GC.Settings:Create(parent)
    self.frame = GC.Settings.frame
end

function SP:Refresh()
    if GC.Settings and GC.Settings.Refresh then
        GC.Settings:Refresh()
    end
end

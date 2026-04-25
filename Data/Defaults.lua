-- /GuildCore/Data/Defaults.lua
local addonName, ns = ...

ns.Defaults = {
    meta = {
        dbVersion = 6,
    },
    settings = {
        autoScanIntervalMinutes = 60,
        enableRosterModule      = true,
        enableGuildBankModule   = true,
        enableMessagingModule   = true,
        enablePointsModule      = true,
        enableSyncModule        = false,
        enableClassificationPrompts = true,
        officerRankThreshold    = 4,
        debugMode               = false,
        themePreset             = "guildcore",
    },
    ui = {
        lastPanel = "dashboard",  -- panel key to restore on next open
        windowX   = nil,          -- saved frame left position
        windowY   = nil,          -- saved frame top  position
        windowWidth = nil,        -- saved frame width
        windowHeight = nil,       -- saved frame height
        minimapButtonAngle = 225, -- minimap button position around the minimap
    },
    guilds = {},
}

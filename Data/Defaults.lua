-- /GuildCore/Data/Defaults.lua
local addonName, ns = ...

ns.Defaults = {
    meta = {
        dbVersion = 18,
    },
    settings = {
        autoScanIntervalMinutes = 60,
        enableRosterModule      = true,
        enableGuildBankModule   = true,
        enableMessagingModule   = true,
        enableInviteModule         = true,
        includeConnectedRealms     = true,
        allowHomeRealmFallback     = true,
        neverScanAllRealms         = true,
        enablePointsModule      = true,
        enableSyncModule        = false,
        enableClassificationPrompts = true,
        officerRankThreshold    = 4,
        debugMode               = false,
        themePreset             = "guildcore",
        fontTheme               = "wowDefault",
        inviteHotkey            = "CTRL-SHIFT-I",
        inviteScanHotkey        = "CTRL-SHIFT-S",
        enableWelcomeBatch      = true,
        welcomeBatchWindowSeconds = 180,
        welcomeMessageTemplate  = "Welcome to the guild, {names}! Glad to have you aboard!",
    },
    ui = {
        lastPanel = "dashboard",  -- panel key to restore on next open
        windowX   = nil,          -- saved frame left position
        windowY   = nil,          -- saved frame top  position
        windowWidth = nil,        -- saved frame width
        windowHeight = nil,       -- saved frame height
        minimized = false,        -- show compact mini-frame instead of full window
        miniX = nil,              -- saved mini-frame left position
        miniY = nil,              -- saved mini-frame top position
        minimapButtonAngle = 225, -- minimap button position around the minimap
    },
    invite = {
        meta = {
            schemaVersion = 1,
            lastPrunedAt = nil,
        },
        settings = {
            enabled = false,
            levelMin = 1,
            levelMax = (GetMaxPlayerLevel and GetMaxPlayerLevel()) or 90,
            guildlessOnly = true,
            includeConnectedRealms = true,
            guildRealmOverride = nil,
            debugEnabled = false,
            requireOnline = true,
            includeClasses = {},
            excludeClasses = {},
            zoneIncludes = {},
            zoneExcludes = {},
            recentInviteDays = 30,
            excludeRecentlyInvited = true,
            whoQueryMode = "safe",
            autoAdvanceScan = false,
            scanAdvanceDelaySeconds = 3,
            scanLevelMin = 1,
            scanLevelMax = (GetMaxPlayerLevel and GetMaxPlayerLevel()) or 90,
            scanQueryMode = "adaptive-level-range",
            whoCapThreshold = 50,
            maxSplitDepth = 6,
            scanLevelBands = {
                { min = 75, max = (GetMaxPlayerLevel and GetMaxPlayerLevel()) or 90 },
                { min = 50, max = 74 },
                { min = 25, max = 49 },
                { min = 1, max = 24 },
            },
            scanClasses = {
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
            },
            realmFilterMode = "local",
            inviteDelaySeconds = 3,
            inviteResponseTimeoutSeconds = 20,
            maxPerSession = 25,
            confirmMassInvite = true,
            dryRun = false,
            showGuildedCandidates = false,
            showRecentlyInvitedCandidates = false,
            showRecentlyDeclinedCandidates = false,
            whisperMode = "none",
            selectedMessageId = nil,
        },
        ignored = {
            names = {},
            reasons = {},
        },
        recentInvites = {},
        recentDeclines = {},
        cooldowns = {},
        history = {},
        ui = {
            selectedFilterId = nil,
            showIgnored = false,
        },
    },
    guilds = {},
}

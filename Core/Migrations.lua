-- /GuildCore/Core/Migrations.lua
local addonName, ns = ...
local GC = ns.GuildCore

GC.Migrations = {}

local function trim(value)
    return GC.Utils.Trim(value or "")
end

local function currentPlayerName()
    local name = UnitName and UnitName("player") or nil
    name = trim(name)
    if name == "" then
        return nil
    end
    return name
end

local function normalizeTargetChannel(channelId)
    channelId = tostring(channelId or "GUILD"):upper()
    if channelId == "INSTANCE" then
        channelId = "INSTANCE_CHAT"
    end

    local supported = {
        GUILD = true,
        OFFICER = true,
        WHISPER = true,
        SAY = true,
        YELL = true,
        PARTY = true,
        RAID = true,
        INSTANCE_CHAT = true,
    }
    return supported[channelId] and channelId or "GUILD"
end

local function maxPlayerLevel()
    return (GetMaxPlayerLevel and tonumber(GetMaxPlayerLevel())) or 90
end

local function ensureMessagesState(guild)
    if type(guild.messageHistory) ~= "table" then
        guild.messageHistory = {}
    end
    guild.messages = guild.messages or {}
    guild.messages.meta = guild.messages.meta or {}
    guild.messages.meta.nextMessageId = tonumber(guild.messages.meta.nextMessageId) or 1
    guild.messages.meta.nextCategoryId = tonumber(guild.messages.meta.nextCategoryId) or 1
    guild.messages.meta.selectedCategoryId = guild.messages.meta.selectedCategoryId or "general"
    guild.messages.meta.selectedMessageId = guild.messages.meta.selectedMessageId or nil
    guild.messages.meta.automationEnabled = guild.messages.meta.automationEnabled == true
    guild.messages.meta.autoSendDelaySeconds = tonumber(guild.messages.meta.autoSendDelaySeconds) or 2
    guild.messages.meta.maxQueueSize = tonumber(guild.messages.meta.maxQueueSize) or 25
    guild.messages.meta.previewTargetName = tostring(guild.messages.meta.previewTargetName or "")
    guild.messages.meta.dailyTargetHour = tonumber(guild.messages.meta.dailyTargetHour) or 18
    guild.messages.meta.dailyTargetMinute = tonumber(guild.messages.meta.dailyTargetMinute) or 0
    guild.messages.meta.lastJoinedName = guild.messages.meta.lastJoinedName or nil
    guild.messages.categories = guild.messages.categories or {}
    guild.messages.categoryOrder = guild.messages.categoryOrder or {}
    guild.messages.messages = guild.messages.messages or {}
    guild.messages.messageOrderByCategory = guild.messages.messageOrderByCategory or {}

    if type(guild.messages.categories.general) ~= "table" then
        guild.messages.categories.general = {
            id = "general",
            name = "General",
            createdAt = time(),
            updatedAt = time(),
            archived = false,
            collapsed = false,
            color = nil,
            icon = nil,
        }
    else
        guild.messages.categories.general.id = "general"
        guild.messages.categories.general.name = guild.messages.categories.general.name or "General"
        guild.messages.categories.general.createdAt = guild.messages.categories.general.createdAt or time()
        guild.messages.categories.general.updatedAt = guild.messages.categories.general.updatedAt or guild.messages.categories.general.createdAt
    end

    for categoryId, category in pairs(guild.messages.categories or {}) do
        if type(category) == "table" then
            category.id = category.id or categoryId
            category.archived = category.archived == true
            category.collapsed = category.collapsed == true
            if category.color ~= nil and type(category.color) ~= "table" and type(category.color) ~= "string" then
                category.color = nil
            end
            if category.icon ~= nil and type(category.icon) ~= "string" then
                category.icon = nil
            end
        end
    end

    if not GC.Utils.ArrayContains(guild.messages.categoryOrder, "general") then
        table.insert(guild.messages.categoryOrder, 1, "general")
    end

    guild.messages.messageOrderByCategory.general = guild.messages.messageOrderByCategory.general or {}

    local actor = currentPlayerName()
    for messageId, message in pairs(guild.messages.messages or {}) do
        if type(message) == "table" then
            message.id = tostring(message.id or messageId)
            message.lastUsedAt = tonumber(message.lastUsedAt) or nil
            message.notes = tostring(message.notes or "")
            message.body = tostring(message.body or "")
            message.targetChannel = normalizeTargetChannel(message.targetChannel)
            if type(message.tags) ~= "table" then
                message.tags = {}
            end
            message.usageCount = math.max(0, math.floor(tonumber(message.usageCount) or 0))
            if message.createdBy == nil or tostring(message.createdBy) == "" then
                message.createdBy = actor
            else
                message.createdBy = tostring(message.createdBy)
            end
            if message.updatedBy == nil or tostring(message.updatedBy) == "" then
                message.updatedBy = message.createdBy or actor
            else
                message.updatedBy = tostring(message.updatedBy)
            end
            message.favorite = message.favorite == true
            message.archived = message.archived == true
        end
    end

    while #guild.messageHistory > 250 do
        table.remove(guild.messageHistory, 1)
    end
end

local function ensureMessagingCampaignsState(guild)
    if type(guild.messagingCampaigns) ~= "table" then
        guild.messagingCampaigns = {}
    end

    guild.messagingCampaigns.meta = guild.messagingCampaigns.meta or {}
    guild.messagingCampaigns.meta.nextCampaignId = math.max(1, math.floor(tonumber(guild.messagingCampaigns.meta.nextCampaignId) or 1))
    guild.messagingCampaigns.meta.nextStepId = math.max(1, math.floor(tonumber(guild.messagingCampaigns.meta.nextStepId) or 1))
    if type(guild.messagingCampaigns.campaigns) ~= "table" then
        guild.messagingCampaigns.campaigns = {}
    end
    if type(guild.messagingCampaigns.steps) ~= "table" then
        guild.messagingCampaigns.steps = {}
    end
end

local function ensurePurgeState(guild)
    guild.purge = guild.purge or {}
    guild.purge.queue = type(guild.purge.queue) == "table" and guild.purge.queue or {}
    guild.purge.candidates = type(guild.purge.candidates) == "table" and guild.purge.candidates or {}
    guild.purge.protected = type(guild.purge.protected) == "table" and guild.purge.protected or {}
    guild.purge.log = type(guild.purge.log) == "table" and guild.purge.log or {}
    guild.purge.meta = type(guild.purge.meta) == "table" and guild.purge.meta or {}
    guild.purge.meta.daysOffline = math.max(3, math.floor(tonumber(guild.purge.meta.daysOffline) or 3))
    guild.purge.meta.safeTags = type(guild.purge.meta.safeTags) == "table"
        and guild.purge.meta.safeTags
        or { "PROTECTED", "LEAVE", "OFFICER ALT", "DO NOT KICK" }
    guild.purge.meta.includeRanks = type(guild.purge.meta.includeRanks) == "table"
        and guild.purge.meta.includeRanks
        or { "Initiate", "Member" }
    if guild.purge.meta.includeAllRanks == nil then
        guild.purge.meta.includeAllRanks = true
    end
    if guild.purge.meta.exemptLinkedCharacters == nil then
        guild.purge.meta.exemptLinkedCharacters = true
    end
end

local function ensureInviteState(guild)
    local inviteDefaults = ns.Defaults and ns.Defaults.invite or {}

    guild.invite = type(guild.invite) == "table" and guild.invite or {}

    guild.invite.meta = type(guild.invite.meta) == "table" and guild.invite.meta or {}
    GC.Utils.MergeDefaults(guild.invite.meta, inviteDefaults.meta or {})

    guild.invite.settings = type(guild.invite.settings) == "table" and guild.invite.settings or {}
    local settings = guild.invite.settings
    GC.Utils.MergeDefaults(settings, inviteDefaults.settings or {})
    local maxLevel = maxPlayerLevel()
    if settings.levelMax == nil or tonumber(settings.levelMax) == 80 then
        settings.levelMax = maxLevel
    end
    if settings.scanLevelMax == nil or tonumber(settings.scanLevelMax) == 80 then
        settings.scanLevelMax = maxLevel
    end
    if type(settings.scanLevelBands) ~= "table" or #settings.scanLevelBands == 0 then
        settings.scanLevelBands = {
            { min = 75, max = maxLevel },
            { min = 50, max = 74 },
            { min = 25, max = 49 },
            { min = 1, max = 24 },
        }
    end
    if type(settings.scanLevelBands) == "table" then
        for _, band in ipairs(settings.scanLevelBands) do
            if type(band) == "table" and tonumber(band.max) == 80 then
                band.max = maxLevel
            end
        end
    end
    if settings.guildRealmOverride == "" then
        settings.guildRealmOverride = nil
    end
    if settings.debugEnabled == nil then
        settings.debugEnabled = false
    end
    if settings.showGuildedCandidates == nil then
        settings.showGuildedCandidates = false
    end
    if settings.showRecentlyInvitedCandidates == nil then
        settings.showRecentlyInvitedCandidates = false
    end
    if settings.showRecentlyDeclinedCandidates == nil then
        settings.showRecentlyDeclinedCandidates = false
    end
    if settings.autoAdvanceScan == nil then
        settings.autoAdvanceScan = false
    end
    if settings.scanAdvanceDelaySeconds == nil then
        settings.scanAdvanceDelaySeconds = 3
    end
    if settings.whoCapThreshold == nil then
        settings.whoCapThreshold = 50
    end
    if settings.maxSplitDepth == nil then
        settings.maxSplitDepth = 6
    end
    if settings.inviteDelaySeconds == nil or tonumber(settings.inviteDelaySeconds) == 8 then
        settings.inviteDelaySeconds = 3
    end
    if settings.inviteResponseTimeoutSeconds == nil then
        settings.inviteResponseTimeoutSeconds = 20
    end

    guild.invite.ignored = type(guild.invite.ignored) == "table" and guild.invite.ignored or {}
    GC.Utils.MergeDefaults(guild.invite.ignored, inviteDefaults.ignored or {})
    guild.invite.recentInvites = type(guild.invite.recentInvites) == "table" and guild.invite.recentInvites or {}
    guild.invite.recentDeclines = type(guild.invite.recentDeclines) == "table" and guild.invite.recentDeclines or {}
    guild.invite.cooldowns = type(guild.invite.cooldowns) == "table" and guild.invite.cooldowns or {}
    guild.invite.history = type(guild.invite.history) == "table" and guild.invite.history or {}
    guild.invite.ui = type(guild.invite.ui) == "table" and guild.invite.ui or {}
    GC.Utils.MergeDefaults(guild.invite.ui, inviteDefaults.ui or {})

    while #guild.invite.history > 500 do
        table.remove(guild.invite.history, 1)
    end
end

local function ensureBanBookState(root)
    if type(root.banBook) ~= "table" then
        root.banBook = {}
    end
end

local function ensureDashboardState(root)
    root.settings = type(root.settings) == "table" and root.settings or {}
    root.settings.dashboard = type(root.settings.dashboard) == "table" and root.settings.dashboard or {}
    local dashboard = root.settings.dashboard
    if dashboard.compactMode == nil then dashboard.compactMode = false end
    if dashboard.showHealth == nil then dashboard.showHealth = true end
    if dashboard.showTrends == nil then dashboard.showTrends = true end
    if dashboard.showIcons == nil then dashboard.showIcons = true end
    if dashboard.showQuickActions == nil then dashboard.showQuickActions = true end
    dashboard.hiddenCards = type(dashboard.hiddenCards) == "table" and dashboard.hiddenCards or {}
    dashboard.snapshotThrottleSeconds = tonumber(dashboard.snapshotThrottleSeconds) or 900
    root.dashboardSnapshots = type(root.dashboardSnapshots) == "table" and root.dashboardSnapshots or {}
end

local function ensureSyncSettings(root)
    root.settings = type(root.settings) == "table" and root.settings or {}
    root.settings.sync = type(root.settings.sync) == "table" and root.settings.sync or {}
    local sync = root.settings.sync
    if sync.enabled == nil then sync.enabled = root.settings.enableSyncModule == true end
    if sync.autoOnLogin == nil then sync.autoOnLogin = false end
    if sync.autoOnPeerDetected == nil then sync.autoOnPeerDetected = false end
    if sync.showMessages == nil then sync.showMessages = true end
    if sync.debug == nil then sync.debug = false end
end

local function ensureRosterSettings(root)
    root.settings = type(root.settings) == "table" and root.settings or {}
    root.settings.roster = type(root.settings.roster) == "table" and root.settings.roster or {}
    local roster = root.settings.roster
    if roster.onlineOnly == nil then roster.onlineOnly = false end
    if roster.groupAlts == nil then roster.groupAlts = false end
    if roster.lastLetterFilter == "" then roster.lastLetterFilter = nil end
end

local function migrateGuild(guild)
    guild.settings = guild.settings or {}
    guild.players = guild.players or {}
    guild.logs = guild.logs or {}
    guild.bank = guild.bank or {}
    guild.bank.entries = guild.bank.entries or {}
    guild.bank.seenKeys = guild.bank.seenKeys or {}
    guild.bank.lastCapturedAt = guild.bank.lastCapturedAt or nil
    guild.snapshots = guild.snapshots or {}
    guild.sync = guild.sync or {}
    guild.sync.outboundQueue = guild.sync.outboundQueue or {}
    guild.scans = guild.scans or {}
    guild.scans.history = guild.scans.history or {}
    guild.prompts = guild.prompts or {}
    ensurePurgeState(guild)
    guild.messageQueue = guild.messageQueue or {}
    if type(guild.messageHistory) ~= "table" then
        guild.messageHistory = {}
    end
    ensureMessagesState(guild)
    ensureMessagingCampaignsState(guild)
    ensureInviteState(guild)

    for key, player in pairs(guild.players) do
        player.key = player.key or key
        player.name = player.name or key:match("^([^%-]+)")
        player.realm = player.realm or key:match("-(.+)$") or GetRealmName() or "UnknownRealm"
        player.status = player.status or "active"
        player.points = player.points or { balance = 0, lifetime = 0, transactions = {} }
        player.points.transactions = player.points.transactions or {}
        player.notes = player.notes or { custom = "", tags = {} }
        player.notes.tags = player.notes.tags or {}
        player.syncMeta = player.syncMeta or {
            joinedAt = 0,
            promotedAt = 0,
            main = 0,
            customNote = 0,
        }
        player.alts = player.alts or {}
        player.classification = player.classification or (player.main and "alt") or (#player.alts > 0 and "main") or "unknown"
        player.firstSeenAt = player.firstSeenAt or player.joinedAt or player.lastRosterSeenAt or time()
        player.promptState = player.promptState or {}
        player.officerData = player.officerData or {
            joinDate = nil,
            discordVerified = nil,
            discordName = nil,
            noteLastParsedAt = nil,
        }
        player.lastScanReason = player.lastScanReason or nil
    end
end

function GC.Migrations:Run()
    local root = GC.DB:GetRoot()
    local currentVersion = root.meta.dbVersion or 1
    ensureBanBookState(root)
    ensureDashboardState(root)
    ensureSyncSettings(root)
    ensureRosterSettings(root)

    if currentVersion < 2 then
        root.settings = root.settings or {}
        if root.settings.enableClassificationPrompts == nil then
            root.settings.enableClassificationPrompts = true
        end

        for _, guild in pairs(root.guilds or {}) do
            migrateGuild(guild)
        end

        currentVersion = 2
    end

    if currentVersion < 3 then
        root.settings = root.settings or {}
        if root.settings.themePreset == nil then
            root.settings.themePreset = "guildcore"
        end
        currentVersion = 3
    end

    if currentVersion < 4 then
        root.settings = root.settings or {}
        if root.settings.enableGuildBankModule == nil then
            root.settings.enableGuildBankModule = true
        end
        currentVersion = 4
    end

    if currentVersion < 5 then
        for _, guild in pairs(root.guilds or {}) do
            ensureMessagesState(guild)
        end
        currentVersion = 5
    end

    if currentVersion < 6 then
        for _, guild in pairs(root.guilds or {}) do
            ensureMessagesState(guild)
        end
        currentVersion = 6
    end

    if currentVersion < 7 then
        for _, guild in pairs(root.guilds or {}) do
            ensureMessagesState(guild)
        end
        currentVersion = 7
    end

    if currentVersion < 8 then
        for _, guild in pairs(root.guilds or {}) do
            ensureMessagingCampaignsState(guild)
        end
        currentVersion = 8
    end

    if currentVersion < 9 then
        root.settings = root.settings or {}
        if root.settings.fontTheme == nil then
            root.settings.fontTheme = "wowDefault"
        end
        currentVersion = 9
    end

    if currentVersion < 10 then
        for _, guild in pairs(root.guilds or {}) do
            ensurePurgeState(guild)
        end
        currentVersion = 10
    end

    if currentVersion < 11 then
        root.settings = root.settings or {}
        if root.settings.enableInviteModule == nil then
            root.settings.enableInviteModule = true
        end
        for _, guild in pairs(root.guilds or {}) do
            ensureInviteState(guild)
        end
        currentVersion = 11
    end

    if currentVersion < 12 then
        for _, guild in pairs(root.guilds or {}) do
            ensureInviteState(guild)
        end
        currentVersion = 12
    end

    if currentVersion < 13 then
        for _, guild in pairs(root.guilds or {}) do
            ensureInviteState(guild)
        end
        currentVersion = 13
    end

    if currentVersion < 14 then
        root.settings = root.settings or {}
        -- The Invite tab is officer-gated by invite permissions and dry-run safety,
        -- not by a hidden General setting. Older development builds seeded this as
        -- false without exposing a UI control, which made the Invite page look disabled.
        if root.settings.enableInviteModule == nil or root.settings.enableInviteModule == false then
            root.settings.enableInviteModule = true
        end
        for _, guild in pairs(root.guilds or {}) do
            ensureInviteState(guild)
        end
        currentVersion = 14
    end

    if currentVersion < 15 then
        for _, guild in pairs(root.guilds or {}) do
            ensureInviteState(guild)
            guild.invite = guild.invite or {}
            guild.invite.settings = guild.invite.settings or {}
            local settings = guild.invite.settings
            local maxLevel = (GetMaxPlayerLevel and tonumber(GetMaxPlayerLevel())) or 90

            -- Timer-initiated WHO queries can return unreliable empty results in
            -- Retail/Midnight testing. Use one explicit user click per band.
            settings.autoAdvanceScan = false
            settings.scanLevelBands = {
                { min = 75, max = maxLevel },
                { min = 50, max = 74 },
                { min = 25, max = 49 },
                { min = 1, max = 24 },
            }
            settings.scanLevelMin = 1
            settings.scanLevelMax = maxLevel
            settings.scanQueryMode = "level-band-local-realm"
        end
        currentVersion = 15
    end

    if currentVersion < 16 then
        for _, guild in pairs(root.guilds or {}) do
            ensureInviteState(guild)
            guild.invite = guild.invite or {}
            guild.invite.settings = guild.invite.settings or {}
            local settings = guild.invite.settings
            local maxLevel = (GetMaxPlayerLevel and tonumber(GetMaxPlayerLevel())) or 90

            settings.scanQueryMode = "adaptive-level-range"
            settings.scanLevelMin = 1
            settings.scanLevelMax = maxLevel
            settings.whoCapThreshold = tonumber(settings.whoCapThreshold) or 50
            settings.maxSplitDepth = tonumber(settings.maxSplitDepth) or 6
        end
        currentVersion = 16
    end

    if currentVersion < 17 then
        root.settings = root.settings or {}
        if root.settings.inviteHotkey == nil then
            root.settings.inviteHotkey = "CTRL-SHIFT-I"
        end
        if root.settings.inviteScanHotkey == nil then
            root.settings.inviteScanHotkey = "CTRL-SHIFT-S"
        end
        currentVersion = 17
    end

    if currentVersion < 18 then
        root.settings = root.settings or {}
        if root.settings.enableWelcomeBatch == nil then
            root.settings.enableWelcomeBatch = true
        end
        if root.settings.welcomeBatchWindowSeconds == nil then
            root.settings.welcomeBatchWindowSeconds = 180
        end
        if root.settings.welcomeMessageTemplate == nil then
            root.settings.welcomeMessageTemplate = "Welcome to the guild, {names}! Glad to have you aboard!"
        end
        for _, guild in pairs(root.guilds or {}) do
            guild.welcomeBatch = guild.welcomeBatch or {}
            guild.welcomeBatch.recentWelcomed = guild.welcomeBatch.recentWelcomed or {}
            guild.welcomeBatch.lastSentAt = guild.welcomeBatch.lastSentAt or nil
        end
        currentVersion = 18
    end

    if currentVersion < 19 then
        ensureBanBookState(root)
        currentVersion = 19
    end

    if currentVersion < 20 then
        ensureDashboardState(root)
        ensureSyncSettings(root)
        currentVersion = 20
    end

    if currentVersion < 21 then
        ensureSyncSettings(root)
        ensureRosterSettings(root)
        currentVersion = 21
    end

    for _, guild in pairs(root.guilds or {}) do
        migrateGuild(guild)
    end
    ensureBanBookState(root)
    ensureDashboardState(root)
    ensureSyncSettings(root)
    ensureRosterSettings(root)

    root.meta.dbVersion = currentVersion
end

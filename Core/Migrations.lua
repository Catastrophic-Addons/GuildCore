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
    guild.messageQueue = guild.messageQueue or {}
    if type(guild.messageHistory) ~= "table" then
        guild.messageHistory = {}
    end
    ensureMessagesState(guild)
    ensureMessagingCampaignsState(guild)

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

    for _, guild in pairs(root.guilds or {}) do
        migrateGuild(guild)
    end

    root.meta.dbVersion = currentVersion
end

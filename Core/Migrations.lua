-- /GuildCore/Core/Migrations.lua
local addonName, ns = ...
local GC = ns.GuildCore

GC.Migrations = {}

local function ensureMessagesState(guild)
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
        }
    else
        guild.messages.categories.general.id = "general"
        guild.messages.categories.general.name = guild.messages.categories.general.name or "General"
        guild.messages.categories.general.createdAt = guild.messages.categories.general.createdAt or time()
        guild.messages.categories.general.updatedAt = guild.messages.categories.general.updatedAt or guild.messages.categories.general.createdAt
    end

    if not GC.Utils.ArrayContains(guild.messages.categoryOrder, "general") then
        table.insert(guild.messages.categoryOrder, 1, "general")
    end

    guild.messages.messageOrderByCategory.general = guild.messages.messageOrderByCategory.general or {}

    for messageId, message in pairs(guild.messages.messages or {}) do
        if type(message) == "table" then
            message.id = tostring(message.id or messageId)
            message.lastUsedAt = tonumber(message.lastUsedAt) or nil
            message.notes = tostring(message.notes or "")
            message.body = tostring(message.body or "")
        end
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
    ensureMessagesState(guild)

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

    for _, guild in pairs(root.guilds or {}) do
        migrateGuild(guild)
    end

    root.meta.dbVersion = currentVersion
end

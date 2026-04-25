local addonName, ns = ...
local GC = ns.GuildCore

local MessagesService = {}
MessagesService.__index = MessagesService

local DEFAULT_CATEGORY_ID = "general"
local DEFAULT_AUTO_SEND_DELAY = 2
local DEFAULT_MAX_QUEUE_SIZE = 25
local SEND_COOLDOWN_SECONDS = 1.2
local MESSAGE_HISTORY_LIMIT = 250

local DEFAULT_CATEGORY_SEEDS = {
    { id = DEFAULT_CATEGORY_ID, name = "General" },
    { id = "recruitment", name = "Recruitment" },
    { id = "welcome-onboarding", name = "Welcome / Onboarding" },
    { id = "discord-verification", name = "Discord Verification" },
    { id = "raid", name = "Raid" },
    { id = "mythic-plus", name = "Mythic+" },
    { id = "events", name = "Events" },
    { id = "officer-notes", name = "Officer Notes" },
    { id = "guild-rules", name = "Guild Rules" },
    { id = "follow-ups", name = "Follow-Ups" },
}

local SUPPORTED_CHANNELS = {
    GUILD = { key = "GUILD", id = "GUILD", label = "Guild", chatPrefix = "/g ", slashPrefix = "/g ", requiresRecipient = false, risky = false },
    OFFICER = { key = "OFFICER", id = "OFFICER", label = "Officer", chatPrefix = "/o ", slashPrefix = "/o ", requiresRecipient = false, risky = true },
    WHISPER = { key = "WHISPER", id = "WHISPER", label = "Whisper", chatPrefix = "/w ", slashPrefix = "/w ", requiresRecipient = true, risky = false },
    SAY = { key = "SAY", id = "SAY", label = "Say", chatPrefix = "/s ", slashPrefix = "/s ", requiresRecipient = false, risky = false },
    YELL = { key = "YELL", id = "YELL", label = "Yell", chatPrefix = "/y ", slashPrefix = "/y ", requiresRecipient = false, risky = true },
    PARTY = { key = "PARTY", id = "PARTY", label = "Party", chatPrefix = "/p ", slashPrefix = "/p ", requiresRecipient = false, risky = false },
    RAID = { key = "RAID", id = "RAID", label = "Raid", chatPrefix = "/raid ", slashPrefix = "/raid ", requiresRecipient = false, risky = true },
    INSTANCE_CHAT = { key = "INSTANCE_CHAT", id = "INSTANCE_CHAT", label = "Instance", chatPrefix = "/i ", slashPrefix = "/i ", requiresRecipient = false, risky = true },
}

local CHANNEL_ALIASES = {
    INSTANCE = "INSTANCE_CHAT",
}

local function trim(value)
    return GC.Utils.Trim(value or "")
end

local function now()
    return GC.Utils.Now and GC.Utils.Now() or time()
end

local function copyTable(source)
    local result = {}
    for key, value in pairs(source or {}) do
        result[key] = value
    end
    return result
end

local function currentPlayerName()
    local name = UnitName and UnitName("player") or nil
    name = trim(name)
    if name == "" then
        return nil
    end
    return name
end

local function normalizeTags(tags)
    if type(tags) ~= "table" then
        return {}
    end

    local normalized = {}
    for _, tag in ipairs(tags) do
        tag = trim(tag)
        if tag ~= "" then
            normalized[#normalized + 1] = tag
        end
    end
    return normalized
end

local function normalizeChannelId(channelId)
    channelId = tostring(channelId or "GUILD"):upper()
    return CHANNEL_ALIASES[channelId] or channelId
end

local function lowerText(value)
    return trim(value):lower()
end

local function ensureMessagingCampaignsState(guild)
    if not guild then
        return nil
    end

    if type(guild.messagingCampaigns) ~= "table" then
        guild.messagingCampaigns = {}
    end

    local campaigns = guild.messagingCampaigns
    campaigns.meta = campaigns.meta or {}
    campaigns.meta.nextCampaignId = math.max(1, math.floor(tonumber(campaigns.meta.nextCampaignId) or 1))
    campaigns.meta.nextStepId = math.max(1, math.floor(tonumber(campaigns.meta.nextStepId) or 1))
    if type(campaigns.campaigns) ~= "table" then
        campaigns.campaigns = {}
    end
    if type(campaigns.steps) ~= "table" then
        campaigns.steps = {}
    end

    return campaigns
end

local function textMatchesSearch(value, searchText)
    return tostring(value or ""):lower():find(searchText, 1, true) ~= nil
end

local function tagsMatchSearch(tags, searchText)
    if type(tags) ~= "table" then
        return false
    end
    for _, tag in ipairs(tags) do
        if textMatchesSearch(tag, searchText) then
            return true
        end
    end
    return false
end

function MessagesService:IsEnabled()
    local settings = GC.DB:GetSettings()
    return not settings or settings.enableMessagingModule ~= false
end

function MessagesService:GetStorage()
    local guild = GC.DB:GetGuild()
    if not guild then
        return nil
    end

    ensureMessagingCampaignsState(guild)
    guild.messageQueue = guild.messageQueue or {}
    if type(guild.messageHistory) ~= "table" then
        guild.messageHistory = {}
    end
    while #guild.messageHistory > MESSAGE_HISTORY_LIMIT do
        table.remove(guild.messageHistory, 1)
    end
    guild.messages = guild.messages or {}
    local storage = guild.messages

    storage.meta = storage.meta or {}
    storage.meta.nextMessageId = tonumber(storage.meta.nextMessageId) or 1
    storage.meta.nextCategoryId = tonumber(storage.meta.nextCategoryId) or 1
    storage.meta.selectedCategoryId = storage.meta.selectedCategoryId or DEFAULT_CATEGORY_ID
    storage.meta.selectedMessageId = storage.meta.selectedMessageId or nil
    storage.meta.automationEnabled = storage.meta.automationEnabled == true
    storage.meta.autoSendDelaySeconds = tonumber(storage.meta.autoSendDelaySeconds) or DEFAULT_AUTO_SEND_DELAY
    storage.meta.maxQueueSize = tonumber(storage.meta.maxQueueSize) or DEFAULT_MAX_QUEUE_SIZE
    storage.meta.previewTargetName = tostring(storage.meta.previewTargetName or "")
    storage.meta.dailyTargetHour = tonumber(storage.meta.dailyTargetHour) or 18
    storage.meta.dailyTargetMinute = tonumber(storage.meta.dailyTargetMinute) or 0
    storage.meta.lastJoinedName = storage.meta.lastJoinedName or nil
    storage.categories = storage.categories or {}
    storage.categoryOrder = storage.categoryOrder or {}
    storage.messages = storage.messages or {}
    storage.messageOrderByCategory = storage.messageOrderByCategory or {}

    local stamp = now()
    storage.categories[DEFAULT_CATEGORY_ID] = storage.categories[DEFAULT_CATEGORY_ID] or {
        id = DEFAULT_CATEGORY_ID,
        name = "General",
        createdAt = stamp,
        updatedAt = stamp,
    }

    if not GC.Utils.ArrayContains(storage.categoryOrder, DEFAULT_CATEGORY_ID) then
        table.insert(storage.categoryOrder, 1, DEFAULT_CATEGORY_ID)
    end

    storage.messageOrderByCategory[DEFAULT_CATEGORY_ID] = storage.messageOrderByCategory[DEFAULT_CATEGORY_ID] or {}

    self:ValidateStorage(storage)
    return storage
end

function MessagesService:GetCampaignStorage()
    local guild = GC.DB:GetGuild()
    return ensureMessagingCampaignsState(guild)
end

function MessagesService:SeedDefaultCategories(storage)
    if not storage then
        return
    end

    local stamp = now()
    local names = {}
    for _, category in pairs(storage.categories or {}) do
        if type(category) == "table" then
            names[lowerText(category.name)] = true
        end
    end

    for _, seed in ipairs(DEFAULT_CATEGORY_SEEDS) do
        local seedId = seed.id
        local seedName = seed.name
        if not storage.categories[seedId] and not names[lowerText(seedName)] then
            storage.categories[seedId] = {
                id = seedId,
                name = seedName,
                createdAt = stamp,
                updatedAt = stamp,
                archived = false,
                collapsed = false,
                color = nil,
                icon = nil,
            }
            storage.messageOrderByCategory[seedId] = storage.messageOrderByCategory[seedId] or {}
            storage.categoryOrder[#storage.categoryOrder + 1] = seedId
            names[lowerText(seedName)] = true
        end
    end
end

function MessagesService:ValidateStorage(storage)
    if not storage then
        return
    end

    storage.meta = storage.meta or {}
    storage.meta.automationEnabled = storage.meta.automationEnabled == true
    storage.meta.autoSendDelaySeconds = math.max(0.5, tonumber(storage.meta.autoSendDelaySeconds) or DEFAULT_AUTO_SEND_DELAY)
    storage.meta.maxQueueSize = math.max(1, math.floor(tonumber(storage.meta.maxQueueSize) or DEFAULT_MAX_QUEUE_SIZE))
    storage.meta.previewTargetName = tostring(storage.meta.previewTargetName or "")
    storage.meta.dailyTargetHour = math.max(0, math.min(23, tonumber(storage.meta.dailyTargetHour) or 18))
    storage.meta.dailyTargetMinute = math.max(0, math.min(59, tonumber(storage.meta.dailyTargetMinute) or 0))
    storage.categories = storage.categories or {}
    storage.categoryOrder = storage.categoryOrder or {}
    storage.messages = storage.messages or {}
    storage.messageOrderByCategory = storage.messageOrderByCategory or {}

    self:SeedDefaultCategories(storage)

    local validCategoryIds = {}
    local normalizedCategoryOrder = {}

    for _, categoryId in ipairs(storage.categoryOrder or {}) do
        if type(categoryId) == "string" and type(storage.categories[categoryId]) == "table" and not validCategoryIds[categoryId] then
            validCategoryIds[categoryId] = true
            normalizedCategoryOrder[#normalizedCategoryOrder + 1] = categoryId
        end
    end

    for categoryId, category in pairs(storage.categories or {}) do
        if type(category) == "table" then
            category.id = categoryId
            category.name = trim(category.name or categoryId)
            if category.name == "" then
                category.name = categoryId == DEFAULT_CATEGORY_ID and "General" or "Category"
            end
            category.createdAt = tonumber(category.createdAt) or now()
            category.updatedAt = tonumber(category.updatedAt) or category.createdAt
            category.archived = category.archived == true
            category.collapsed = category.collapsed == true
            if category.color ~= nil and type(category.color) ~= "table" and type(category.color) ~= "string" then
                category.color = nil
            end
            if category.icon ~= nil and type(category.icon) ~= "string" then
                category.icon = nil
            end
            storage.messageOrderByCategory[categoryId] = storage.messageOrderByCategory[categoryId] or {}
            if not validCategoryIds[categoryId] then
                normalizedCategoryOrder[#normalizedCategoryOrder + 1] = categoryId
                validCategoryIds[categoryId] = true
            end
        else
            storage.categories[categoryId] = nil
        end
    end

    if not validCategoryIds[DEFAULT_CATEGORY_ID] then
        normalizedCategoryOrder[#normalizedCategoryOrder + 1] = DEFAULT_CATEGORY_ID
    end
    storage.categoryOrder = normalizedCategoryOrder

    local validMessageIds = {}
    for messageId, message in pairs(storage.messages or {}) do
        if type(message) ~= "table" then
            storage.messages[messageId] = nil
        else
            message.id = tostring(message.id or messageId)
            message.title = trim(message.title)
            if message.title == "" then
                message.title = "Untitled Message"
            end
            message.body = tostring(message.body or "")
            message.notes = tostring(message.notes or "")
            message.lastUsedAt = tonumber(message.lastUsedAt) or nil
            message.targetChannel = self:NormalizeTargetChannel(message.targetChannel)
            if type(message.tags) ~= "table" then
                message.tags = {}
            end
            message.usageCount = math.max(0, math.floor(tonumber(message.usageCount) or 0))
            local actor = currentPlayerName()
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
            local categoryId = tostring(message.categoryId or DEFAULT_CATEGORY_ID)
            if not storage.categories[categoryId] then
                categoryId = DEFAULT_CATEGORY_ID
            end
            message.categoryId = categoryId
            message.createdAt = tonumber(message.createdAt) or now()
            message.updatedAt = tonumber(message.updatedAt) or message.createdAt
            validMessageIds[message.id] = true
        end
    end

    for categoryId, order in pairs(storage.messageOrderByCategory or {}) do
        if type(order) ~= "table" then
            storage.messageOrderByCategory[categoryId] = {}
            order = storage.messageOrderByCategory[categoryId]
        end

        local normalized = {}
        local seen = {}
        for _, messageId in ipairs(order) do
            if validMessageIds[messageId] and storage.messages[messageId] and storage.messages[messageId].categoryId == categoryId and not seen[messageId] then
                normalized[#normalized + 1] = messageId
                seen[messageId] = true
            end
        end

        for messageId, message in pairs(storage.messages) do
            if message.categoryId == categoryId and not seen[messageId] then
                normalized[#normalized + 1] = messageId
            end
        end

        storage.messageOrderByCategory[categoryId] = normalized
    end

    for messageId, message in pairs(storage.messages) do
        local categoryId = message.categoryId or DEFAULT_CATEGORY_ID
        storage.messageOrderByCategory[categoryId] = storage.messageOrderByCategory[categoryId] or {}
        if not GC.Utils.ArrayContains(storage.messageOrderByCategory[categoryId], messageId) then
            table.insert(storage.messageOrderByCategory[categoryId], messageId)
        end
    end

    if not storage.categories[storage.meta.selectedCategoryId] then
        storage.meta.selectedCategoryId = DEFAULT_CATEGORY_ID
    end

    if storage.meta.selectedMessageId and not storage.messages[storage.meta.selectedMessageId] then
        storage.meta.selectedMessageId = nil
    end
end

function MessagesService:GetSupportedChannels()
    local channels = {
        SUPPORTED_CHANNELS.GUILD,
        SUPPORTED_CHANNELS.OFFICER,
        SUPPORTED_CHANNELS.WHISPER,
        SUPPORTED_CHANNELS.SAY,
        SUPPORTED_CHANNELS.YELL,
        SUPPORTED_CHANNELS.PARTY,
        SUPPORTED_CHANNELS.RAID,
        SUPPORTED_CHANNELS.INSTANCE_CHAT,
    }

    local rows = {}
    for _, channel in ipairs(channels) do
        rows[#rows + 1] = copyTable(channel)
    end
    return rows
end

function MessagesService:GetChannelInfo(channelKey)
    local channel = SUPPORTED_CHANNELS[normalizeChannelId(channelKey)]
    return channel and copyTable(channel) or nil
end

function MessagesService:GetSupportedChannel(channelId)
    return self:GetChannelInfo(channelId)
end

function MessagesService:IsSupportedChannel(channelKey)
    return SUPPORTED_CHANNELS[normalizeChannelId(channelKey)] ~= nil
end

function MessagesService:NormalizeChannel(channelKey)
    local normalized = normalizeChannelId(channelKey)
    return SUPPORTED_CHANNELS[normalized] and normalized or "GUILD"
end

function MessagesService:NormalizeTargetChannel(channelId)
    return self:NormalizeChannel(channelId)
end

function MessagesService:ValidateChannelOptions(options)
    if type(options) == "string" then
        options = { channel = options }
    end
    options = options or {}
    local normalized = normalizeChannelId(options.channel or options.target or options.channelKey or "GUILD")
    local channel = SUPPORTED_CHANNELS[normalized]
    if not channel then
        return false, "Unsupported target channel."
    end

    local recipient = trim(options.recipient)
    if channel.requiresRecipient and recipient == "" then
        return false, "Whisper recipient is required."
    end

    local normalizedOptions = {
        target = channel.key,
        recipient = recipient ~= "" and recipient or nil,
    }

    return true, nil, copyTable(channel), normalizedOptions
end

function MessagesService:ValidateTargetChannel(channelId, recipient)
    return self:ValidateChannelOptions({
        target = channelId,
        recipient = recipient,
    })
end

function MessagesService:GetHistory()
    local guild = GC.DB:GetGuild()
    if not guild then
        return nil
    end

    if type(guild.messageHistory) ~= "table" then
        guild.messageHistory = {}
    end
    while #guild.messageHistory > MESSAGE_HISTORY_LIMIT do
        table.remove(guild.messageHistory, 1)
    end
    return guild.messageHistory
end

function MessagesService:TrimHistory()
    local history = self:GetHistory()
    if not history then
        return false
    end

    while #history > MESSAGE_HISTORY_LIMIT do
        table.remove(history, 1)
    end

    return true
end

function MessagesService:AddHistoryEntry(entry)
    local history = self:GetHistory()
    if not history then
        return false
    end

    entry = entry or {}
    history[#history + 1] = {
        templateId = entry.templateId,
        title = entry.title,
        target = self:NormalizeTargetChannel(entry.target or "GUILD"),
        recipient = trim(entry.recipient) ~= "" and trim(entry.recipient) or nil,
        sentBy = entry.sentBy or currentPlayerName() or "Unknown",
        sentAt = tonumber(entry.sentAt) or now(),
        chunkCount = math.max(1, math.floor(tonumber(entry.chunkCount) or 1)),
    }

    self:TrimHistory()
    return true
end

function MessagesService:GetMessageHistory()
    return self:GetHistory()
end

function MessagesService:AppendMessageHistory(entry)
    return self:AddHistoryEntry(entry)
end

function MessagesService:ListHistory(limit)
    local history = self:GetHistory() or {}
    local rows = {}
    limit = math.max(1, math.floor(tonumber(limit) or 8))

    for index = #history, 1, -1 do
        local entry = history[index]
        if type(entry) == "table" then
            rows[#rows + 1] = {
                key = tostring(index),
                templateId = entry.templateId,
                title = entry.title,
                target = entry.target or "GUILD",
                recipient = entry.recipient,
                sentBy = entry.sentBy,
                sentAt = entry.sentAt,
                sentLabel = entry.sentAt and date("%m-%d %H:%M", entry.sentAt) or "",
                chunkCount = tonumber(entry.chunkCount) or 1,
            }
            if #rows >= limit then
                break
            end
        end
    end

    return rows
end

function MessagesService:GetSelectedCategoryId()
    local storage = self:GetStorage()
    return storage and storage.meta.selectedCategoryId or DEFAULT_CATEGORY_ID
end

function MessagesService:SetSelectedCategory(categoryId)
    local storage = self:GetStorage()
    if storage and storage.categories[categoryId] then
        storage.meta.selectedCategoryId = categoryId
    end
end

function MessagesService:GetSelectedMessageId()
    local storage = self:GetStorage()
    return storage and storage.meta.selectedMessageId or nil
end

function MessagesService:SetSelectedMessage(messageId)
    local storage = self:GetStorage()
    if storage then
        storage.meta.selectedMessageId = storage.messages[messageId] and messageId or nil
    end
end

function MessagesService:GetAutomationEnabled()
    local storage = self:GetStorage()
    return storage and storage.meta.automationEnabled == true or false
end

function MessagesService:SetAutomationEnabled(enabled)
    local storage = self:GetStorage()
    if not storage then
        return false, "Storage not available."
    end

    storage.meta.automationEnabled = enabled == true
    if not storage.meta.automationEnabled then
        self:StopAutoSend("manual")
    end
    return true
end

function MessagesService:GetAutoSendDelaySeconds()
    local storage = self:GetStorage()
    return storage and storage.meta.autoSendDelaySeconds or DEFAULT_AUTO_SEND_DELAY
end

function MessagesService:SetAutoSendDelaySeconds(seconds)
    local storage = self:GetStorage()
    if not storage then
        return false, "Storage not available."
    end

    seconds = tonumber(seconds)
    if not seconds or seconds < 0.5 then
        return false, "Auto-send delay must be at least 0.5 seconds."
    end

    storage.meta.autoSendDelaySeconds = seconds
    return true
end

function MessagesService:GetMaxQueueSize()
    local storage = self:GetStorage()
    return storage and storage.meta.maxQueueSize or DEFAULT_MAX_QUEUE_SIZE
end

function MessagesService:GetPreviewTargetName()
    local storage = self:GetStorage()
    return storage and storage.meta.previewTargetName or ""
end

function MessagesService:SetPreviewTargetName(name)
    local storage = self:GetStorage()
    if not storage then
        return false, "Storage not available."
    end
    storage.meta.previewTargetName = trim(name)
    return true
end

function MessagesService:GetDailyTargetTime()
    local storage = self:GetStorage()
    return {
        hour = storage and storage.meta.dailyTargetHour or 18,
        minute = storage and storage.meta.dailyTargetMinute or 0,
    }
end

function MessagesService:SetDailyTargetTime(hour, minute)
    local storage = self:GetStorage()
    if not storage then
        return false, "Storage not available."
    end

    if type(hour) == "string" and minute == nil then
        local parsedHour, parsedMinute = hour:match("^(%d%d?):(%d%d)$")
        hour = tonumber(parsedHour)
        minute = tonumber(parsedMinute)
    end

    hour = tonumber(hour)
    minute = tonumber(minute)
    if not hour or not minute or hour < 0 or hour > 23 or minute < 0 or minute > 59 then
        return false, "Time must use HH:MM in 24-hour format."
    end

    storage.meta.dailyTargetHour = hour
    storage.meta.dailyTargetMinute = minute
    return true
end

function MessagesService:GetResolveContext(options)
    local storage = self:GetStorage()
    options = options or {}
    return {
        targetName = trim(options.targetName ~= nil and options.targetName or (storage and storage.meta.previewTargetName or "")),
        newMemberName = trim(options.newMemberName ~= nil and options.newMemberName or (storage and storage.meta.lastJoinedName or "")),
        recipient = trim(options.recipient or ""),
        rankName = trim(options.rankName or ""),
        discordName = trim(options.discordName or ""),
        dailyTargetHour = options.dailyTargetHour ~= nil and options.dailyTargetHour or (storage and storage.meta.dailyTargetHour or 18),
        dailyTargetMinute = options.dailyTargetMinute ~= nil and options.dailyTargetMinute or (storage and storage.meta.dailyTargetMinute or 0),
    }
end

function MessagesService:ResolvePlaceholderResult(text, options)
    local placeholderService = GC.Services.MessagePlaceholders
    if not placeholderService or not placeholderService.Resolve then
        return {
            text = tostring(text or ""),
            warnings = {},
            fallbackUsed = false,
            unknown = {},
        }
    end

    return placeholderService:Resolve(text, self:GetResolveContext(options))
end

function MessagesService:ResolvePlaceholders(text, options)
    local result = self:ResolvePlaceholderResult(text, options)
    return result.text or ""
end

function MessagesService:GetAvailablePlaceholders(options)
    local placeholderService = GC.Services.MessagePlaceholders
    if not placeholderService or not placeholderService.GetAvailablePlaceholders then
        return {}
    end
    return placeholderService:GetAvailablePlaceholders(self:GetResolveContext(options))
end

function MessagesService:FindUnknownPlaceholders(text)
    local placeholderService = GC.Services.MessagePlaceholders
    if not placeholderService or not placeholderService.FindUnknownPlaceholders then
        return {}
    end
    return placeholderService:FindUnknownPlaceholders(text)
end

function MessagesService:CaptureSystemMessage(message)
    local storage = self:GetStorage()
    local placeholderService = GC.Services.MessagePlaceholders
    if not storage or not placeholderService or not placeholderService.CaptureSystemMessage then
        return nil
    end

    local joinedName = placeholderService:CaptureSystemMessage(message)
    if joinedName and joinedName ~= "" then
        storage.meta.lastJoinedName = joinedName
    end
    return joinedName
end

function MessagesService:ListCategories(options)
    local storage = self:GetStorage()
    if not storage then
        return {}
    end

    options = options or {}
    local showArchived = options.showArchived == true
    local rows = {}
    for _, categoryId in ipairs(storage.categoryOrder) do
        local category = storage.categories[categoryId]
        if category and (showArchived or category.archived ~= true) then
            rows[#rows + 1] = {
                id = category.id,
                key = category.id,
                name = category.name,
                count = #(storage.messageOrderByCategory[categoryId] or {}),
                isDefault = category.id == DEFAULT_CATEGORY_ID,
                createdAt = category.createdAt,
                updatedAt = category.updatedAt,
                archived = category.archived == true,
                collapsed = category.collapsed == true,
                color = category.color,
                icon = category.icon,
            }
        end
    end
    return rows
end

function MessagesService:GetCategory(categoryId)
    local storage = self:GetStorage()
    local category = storage and storage.categories[categoryId] or nil
    return category and copyTable(category) or nil
end

function MessagesService:GetCategoryIndex(categoryId)
    local storage = self:GetStorage()
    if not storage then
        return nil
    end
    for index, currentId in ipairs(storage.categoryOrder or {}) do
        if currentId == categoryId then
            return index
        end
    end
    return nil
end

function MessagesService:MoveCategoryToIndex(categoryId, desiredIndex)
    local storage = self:GetStorage()
    if not storage then
        return false, "Storage not available."
    end
    if not storage.categories[categoryId] then
        return false, "Category not found."
    end

    local order = storage.categoryOrder or {}
    local currentIndex
    for index, currentId in ipairs(order) do
        if currentId == categoryId then
            currentIndex = index
            break
        end
    end
    if not currentIndex then
        return false, "Category order could not be updated."
    end

    desiredIndex = math.max(1, math.min(#order, tonumber(desiredIndex) or currentIndex))
    if desiredIndex == currentIndex then
        return true
    end

    table.remove(order, currentIndex)
    table.insert(order, desiredIndex, categoryId)
    storage.categories[categoryId].updatedAt = now()
    return true
end

function MessagesService:MoveCategoryUp(categoryId)
    return self:MoveCategoryToIndex(categoryId, (self:GetCategoryIndex(categoryId) or 1) - 1)
end

function MessagesService:MoveCategoryDown(categoryId)
    return self:MoveCategoryToIndex(categoryId, (self:GetCategoryIndex(categoryId) or 1) + 1)
end

function MessagesService:SetCategoryCollapsed(categoryId, collapsed)
    local storage = self:GetStorage()
    if not storage then
        return false, "Storage not available."
    end
    local category = storage.categories[categoryId]
    if not category then
        return false, "Category not found."
    end
    category.collapsed = collapsed == true
    category.updatedAt = now()
    return true
end

function MessagesService:ToggleCategoryCollapsed(categoryId)
    local category = self:GetCategory(categoryId)
    if not category then
        return false, "Category not found."
    end
    return self:SetCategoryCollapsed(categoryId, not category.collapsed)
end

function MessagesService:SetCategoryArchived(categoryId, archived)
    local storage = self:GetStorage()
    if not storage then
        return false, "Storage not available."
    end
    local category = storage.categories[categoryId]
    if not category then
        return false, "Category not found."
    end
    if categoryId == DEFAULT_CATEGORY_ID and archived == true then
        return false, "The default category cannot be archived."
    end
    category.archived = archived == true
    category.updatedAt = now()
    if category.archived and storage.meta.selectedCategoryId == categoryId then
        storage.meta.selectedCategoryId = DEFAULT_CATEGORY_ID
        storage.meta.selectedMessageId = nil
    end
    return true
end

function MessagesService:ArchiveCategory(categoryId)
    return self:SetCategoryArchived(categoryId, true)
end

function MessagesService:UnarchiveCategory(categoryId)
    return self:SetCategoryArchived(categoryId, false)
end

function MessagesService:CreateCategory(name)
    local storage = self:GetStorage()
    if not storage then
        return nil, "No guild data available."
    end

    name = trim(name)
    if name == "" then
        return nil, "Category name is required."
    end

    local wanted = name:lower()
    for _, category in pairs(storage.categories) do
        if trim(category.name):lower() == wanted then
            return nil, "A category with that name already exists."
        end
    end

    local categoryId = "cat-" .. tostring(storage.meta.nextCategoryId)
    storage.meta.nextCategoryId = storage.meta.nextCategoryId + 1
    local stamp = now()
    storage.categories[categoryId] = {
        id = categoryId,
        name = name,
        createdAt = stamp,
        updatedAt = stamp,
        archived = false,
        collapsed = false,
        color = nil,
        icon = nil,
    }
    storage.categoryOrder[#storage.categoryOrder + 1] = categoryId
    storage.messageOrderByCategory[categoryId] = {}
    storage.meta.selectedCategoryId = categoryId
    return self:GetCategory(categoryId)
end

function MessagesService:RenameCategory(categoryId, name)
    local storage = self:GetStorage()
    if not storage then
        return false, "Storage not available."
    end
    local category = storage.categories[categoryId]
    if not category then
        return false, "Category not found."
    end

    name = trim(name)
    if name == "" then
        return false, "Category name is required."
    end

    for otherId, other in pairs(storage.categories) do
        if otherId ~= categoryId and trim(other.name):lower() == name:lower() then
            return false, "A category with that name already exists."
        end
    end

    category.name = name
    category.updatedAt = now()
    return true
end

function MessagesService:DeleteCategory(categoryId, targetCategoryId)
    local storage = self:GetStorage()
    if not storage then
        return false, "Storage not available."
    end
    local category = storage.categories[categoryId]
    if not category then
        return false, "Category not found."
    end
    if categoryId == DEFAULT_CATEGORY_ID then
        return false, "The default category cannot be deleted."
    end

    targetCategoryId = targetCategoryId or DEFAULT_CATEGORY_ID
    if not storage.categories[targetCategoryId] then
        targetCategoryId = DEFAULT_CATEGORY_ID
    end
    storage.messageOrderByCategory[targetCategoryId] = storage.messageOrderByCategory[targetCategoryId] or {}

    for _, messageId in ipairs(storage.messageOrderByCategory[categoryId] or {}) do
        local message = storage.messages[messageId]
        if message then
            message.categoryId = targetCategoryId
            storage.messageOrderByCategory[targetCategoryId][#storage.messageOrderByCategory[targetCategoryId] + 1] = messageId
        end
    end

    storage.messageOrderByCategory[categoryId] = nil
    storage.categories[categoryId] = nil
    GC.Utils.RemoveArrayValue(storage.categoryOrder, categoryId)

    if storage.meta.selectedCategoryId == categoryId then
        storage.meta.selectedCategoryId = targetCategoryId
    end

    self:ValidateStorage(storage)
    return true
end

function MessagesService:GetMessage(messageId)
    local storage = self:GetStorage()
    local message = storage and storage.messages[messageId] or nil
    return message and copyTable(message) or nil
end

function MessagesService:GetMessageOrder(categoryId)
    local storage = self:GetStorage()
    if not storage then
        return {}
    end
    return storage.messageOrderByCategory[categoryId or storage.meta.selectedCategoryId or DEFAULT_CATEGORY_ID] or {}
end

function MessagesService:ListMessages(categoryId, options)
    local storage = self:GetStorage()
    if not storage then
        return {}
    end

    options = options or {}
    local showArchived = options.showArchived == true
    local favoritesOnly = options.favoritesOnly == true
    local searchText = lowerText(options.search or "")
    categoryId = categoryId or storage.meta.selectedCategoryId or DEFAULT_CATEGORY_ID
    local category = storage.categories[categoryId]
    if category and category.collapsed == true and searchText == "" then
        return {}
    end
    local rows = {}
    for index, messageId in ipairs(storage.messageOrderByCategory[categoryId] or {}) do
        local message = storage.messages[messageId]
        local messageCategory = message and storage.categories[message.categoryId or categoryId] or nil
        local categoryArchived = messageCategory and messageCategory.archived == true
        local include = message ~= nil
            and (showArchived or (message.archived ~= true and not categoryArchived))
            and (not favoritesOnly or message.favorite == true)
        if include and searchText ~= "" then
            include = textMatchesSearch(message.title, searchText)
                or textMatchesSearch(message.notes, searchText)
                or textMatchesSearch(message.body, searchText)
                or tagsMatchSearch(message.tags, searchText)
        end
        if include then
            rows[#rows + 1] = {
                id = message.id,
                key = message.id,
                title = message.title,
                notes = message.notes,
                body = message.body,
                categoryId = message.categoryId,
                position = index,
                updatedAt = message.updatedAt,
                updatedLabel = date("%Y-%m-%d", message.updatedAt or now()),
                lastUsedAt = message.lastUsedAt,
                lastUsedLabel = message.lastUsedAt and date("%Y-%m-%d", message.lastUsedAt) or nil,
                targetChannel = message.targetChannel or "GUILD",
                tags = copyTable(message.tags),
                usageCount = tonumber(message.usageCount) or 0,
                createdBy = message.createdBy,
                updatedBy = message.updatedBy,
                favorite = message.favorite == true,
                archived = message.archived == true,
            }
        end
    end
    return rows
end

function MessagesService:CreateMessage(fields)
    local storage = self:GetStorage()
    if not storage then
        return nil, "No guild data available."
    end

    fields = fields or {}
    local title = trim(fields.title)
    if title == "" then
        title = "New Message"
    end

    local categoryId = tostring(fields.categoryId or storage.meta.selectedCategoryId or DEFAULT_CATEGORY_ID)
    if not storage.categories[categoryId] then
        categoryId = DEFAULT_CATEGORY_ID
    end

    local messageId = "msg-" .. tostring(storage.meta.nextMessageId)
    storage.meta.nextMessageId = storage.meta.nextMessageId + 1
    local stamp = now()
    local actor = currentPlayerName()
    storage.messages[messageId] = {
        id = messageId,
        title = title,
        categoryId = categoryId,
        body = tostring(fields.body or ""),
        notes = tostring(fields.notes or ""),
        targetChannel = self:NormalizeTargetChannel(fields.targetChannel or fields.target or "GUILD"),
        tags = normalizeTags(fields.tags),
        usageCount = 0,
        createdBy = actor,
        updatedBy = actor,
        favorite = fields.favorite == true,
        archived = fields.archived == true,
        createdAt = stamp,
        updatedAt = stamp,
        lastUsedAt = nil,
    }

    storage.messageOrderByCategory[categoryId] = storage.messageOrderByCategory[categoryId] or {}
    storage.messageOrderByCategory[categoryId][#storage.messageOrderByCategory[categoryId] + 1] = messageId
    storage.meta.selectedCategoryId = categoryId
    storage.meta.selectedMessageId = messageId
    return self:GetMessage(messageId)
end

function MessagesService:UpdateMessage(messageId, fields)
    local storage = self:GetStorage()
    if not storage then
        return false, "Storage not available."
    end
    local message = storage.messages[messageId]
    if not message then
        return false, "Message not found."
    end

    fields = fields or {}
    local oldCategoryId = message.categoryId
    local targetCategoryId = tostring(fields.categoryId or message.categoryId or DEFAULT_CATEGORY_ID)
    if not storage.categories[targetCategoryId] then
        targetCategoryId = DEFAULT_CATEGORY_ID
    end

    local title = trim(fields.title ~= nil and fields.title or message.title)
    if title == "" then
        return false, "Message title is required."
    end

    message.title = title
    message.body = tostring(fields.body ~= nil and fields.body or message.body or "")
    message.notes = tostring(fields.notes ~= nil and fields.notes or message.notes or "")
    if fields.targetChannel ~= nil or fields.target ~= nil then
        message.targetChannel = self:NormalizeTargetChannel(fields.targetChannel or fields.target)
    end
    if fields.tags ~= nil then
        message.tags = normalizeTags(fields.tags)
    end
    if fields.favorite ~= nil then
        message.favorite = fields.favorite == true
    end
    if fields.archived ~= nil then
        message.archived = fields.archived == true
    end
    message.updatedAt = now()
    message.updatedBy = currentPlayerName() or message.updatedBy or message.createdBy

    if targetCategoryId ~= oldCategoryId then
        self:MoveMessageToCategory(messageId, targetCategoryId)
        message = storage.messages[messageId]
        if not message then
            return false, "Message not found after category move."
        end
    end

    message.categoryId = targetCategoryId
    storage.meta.selectedCategoryId = targetCategoryId
    storage.meta.selectedMessageId = messageId
    return true
end

function MessagesService:DeleteMessage(messageId)
    local storage = self:GetStorage()
    if not storage then
        return false, "Storage not available."
    end
    local message = storage.messages[messageId]
    if not message then
        return false, "Message not found."
    end

    GC.Utils.RemoveArrayValue(storage.messageOrderByCategory[message.categoryId] or {}, messageId)
    storage.messages[messageId] = nil

    if storage.meta.selectedMessageId == messageId then
        storage.meta.selectedMessageId = nil
    end
    if storage.meta.selectedCategoryId == nil or not storage.categories[storage.meta.selectedCategoryId] then
        storage.meta.selectedCategoryId = DEFAULT_CATEGORY_ID
    end

    return true
end

function MessagesService:SetMessageArchived(messageId, archived)
    local storage = self:GetStorage()
    if not storage then
        return false, "Storage not available."
    end
    local message = storage.messages[messageId]
    if not message then
        return false, "Message not found."
    end
    message.archived = archived == true
    message.updatedAt = now()
    message.updatedBy = currentPlayerName() or message.updatedBy or message.createdBy
    if message.archived and storage.meta.selectedMessageId == messageId then
        storage.meta.selectedMessageId = nil
    end
    return true
end

function MessagesService:ArchiveMessage(messageId)
    return self:SetMessageArchived(messageId, true)
end

function MessagesService:UnarchiveMessage(messageId)
    return self:SetMessageArchived(messageId, false)
end

function MessagesService:SetMessageFavorite(messageId, favorite)
    local storage = self:GetStorage()
    if not storage then
        return false, "Storage not available."
    end
    local message = storage.messages[messageId]
    if not message then
        return false, "Message not found."
    end
    message.favorite = favorite == true
    message.updatedAt = now()
    message.updatedBy = currentPlayerName() or message.updatedBy or message.createdBy
    return true
end

function MessagesService:ToggleMessageFavorite(messageId)
    local message = self:GetMessage(messageId)
    if not message then
        return false, "Message not found."
    end
    return self:SetMessageFavorite(messageId, not message.favorite)
end

function MessagesService:DuplicateMessage(messageId)
    local storage = self:GetStorage()
    if not storage then
        return nil, "Storage not available."
    end
    local source = storage.messages[messageId]
    if not source then
        return nil, "Message not found."
    end

    local baseTitle = trim(source.title)
    if baseTitle == "" then
        baseTitle = "Untitled Message"
    end
    local wanted = baseTitle .. " Copy"
    local title = wanted
    local suffix = 2
    local taken = {}
    for _, message in pairs(storage.messages) do
        taken[lowerText(message.title)] = true
    end
    while taken[lowerText(title)] do
        title = wanted .. " " .. tostring(suffix)
        suffix = suffix + 1
    end

    local messageIdNew = "msg-" .. tostring(storage.meta.nextMessageId)
    storage.meta.nextMessageId = storage.meta.nextMessageId + 1
    local stamp = now()
    local actor = currentPlayerName()
    local categoryId = storage.categories[source.categoryId] and source.categoryId or DEFAULT_CATEGORY_ID

    storage.messages[messageIdNew] = {
        id = messageIdNew,
        title = title,
        categoryId = categoryId,
        body = tostring(source.body or ""),
        notes = tostring(source.notes or ""),
        targetChannel = self:NormalizeTargetChannel(source.targetChannel or "GUILD"),
        tags = normalizeTags(source.tags),
        usageCount = 0,
        createdBy = actor,
        updatedBy = actor,
        favorite = false,
        archived = false,
        createdAt = stamp,
        updatedAt = stamp,
        lastUsedAt = nil,
    }

    storage.messageOrderByCategory[categoryId] = storage.messageOrderByCategory[categoryId] or {}
    local sourceIndex = self:GetMessageIndex(messageId) or #storage.messageOrderByCategory[categoryId]
    table.insert(storage.messageOrderByCategory[categoryId], sourceIndex + 1, messageIdNew)
    storage.meta.selectedCategoryId = categoryId
    storage.meta.selectedMessageId = messageIdNew
    return self:GetMessage(messageIdNew)
end

function MessagesService:RecordMessageUsage(messageId, output)
    local storage = self:GetStorage()
    if not storage or not messageId then
        return false, "Storage not available."
    end
    local message = storage.messages[messageId]
    if not message then
        return false, "Message not found."
    end

    output = output or {}
    local stamp = tonumber(output.sentAt) or now()
    local target = self:NormalizeTargetChannel(output.target or message.targetChannel or "GUILD")
    message.usageCount = math.max(0, math.floor(tonumber(message.usageCount) or 0)) + 1
    message.lastUsedAt = stamp

    self:AddHistoryEntry({
        templateId = message.id,
        title = message.title,
        target = target,
        recipient = output.recipient,
        sentBy = output.sentBy or currentPlayerName() or "Unknown",
        sentAt = stamp,
        chunkCount = output.chunkCount or 1,
    })
    return true
end

function MessagesService:MoveMessageUp(messageId)
    local message = self:GetMessage(messageId)
    if not message then
        return false, "Message not found."
    end
    return self:MoveMessageToIndex(messageId, (self:GetMessageIndex(messageId) or 1) - 1)
end

function MessagesService:MoveMessageDown(messageId)
    local message = self:GetMessage(messageId)
    if not message then
        return false, "Message not found."
    end
    return self:MoveMessageToIndex(messageId, (self:GetMessageIndex(messageId) or 1) + 1)
end

function MessagesService:GetMessageIndex(messageId)
    local storage = self:GetStorage()
    if not storage then
        return nil
    end

    local message = storage.messages[messageId]
    if not message then
        return nil
    end

    for index, currentId in ipairs(storage.messageOrderByCategory[message.categoryId] or {}) do
        if currentId == messageId then
            return index
        end
    end
    return nil
end

function MessagesService:MoveMessageToIndex(messageId, desiredIndex)
    local storage = self:GetStorage()
    if not storage then
        return false, "Storage not available."
    end
    local message = storage.messages[messageId]
    if not message then
        return false, "Message not found."
    end

    local order = storage.messageOrderByCategory[message.categoryId] or {}
    local currentIndex
    for index, currentId in ipairs(order) do
        if currentId == messageId then
            currentIndex = index
            break
        end
    end

    if not currentIndex then
        return false, "Message order could not be updated."
    end

    desiredIndex = math.max(1, math.min(#order, tonumber(desiredIndex) or currentIndex))
    if desiredIndex == currentIndex then
        return true
    end

    table.remove(order, currentIndex)
    table.insert(order, desiredIndex, messageId)
    return true
end

function MessagesService:MoveMessageToCategory(messageId, categoryId)
    local storage = self:GetStorage()
    if not storage then
        return false, "Storage not available."
    end
    local message = storage.messages[messageId]
    if not message then
        return false, "Message not found."
    end

    if not storage.categories[categoryId] then
        return false, "Target category not found."
    end

    local oldCategoryId = message.categoryId or DEFAULT_CATEGORY_ID
    if oldCategoryId == categoryId then
        return true
    end

    GC.Utils.RemoveArrayValue(storage.messageOrderByCategory[oldCategoryId] or {}, messageId)
    storage.messageOrderByCategory[categoryId] = storage.messageOrderByCategory[categoryId] or {}
    storage.messageOrderByCategory[categoryId][#storage.messageOrderByCategory[categoryId] + 1] = messageId

    message.categoryId = categoryId
    message.updatedAt = now()
    storage.meta.selectedCategoryId = categoryId
    storage.meta.selectedMessageId = messageId
    return true
end

function MessagesService:BuildPreview(body, options)
    local chunker = GC.Services.MessageChunker
    if not chunker then
        return {}
    end

    options = options or {}
    options.limit = math.max(20, math.min(255, tonumber(options.limit) or 240))

    local resolvedResult = self:ResolvePlaceholderResult(body, options)
    local resolved = resolvedResult.text or ""
    local preview = chunker:Preview(resolved, options)
    for _, row in ipairs(preview) do
        row.categoryId = nil
        row.resolvedText = resolved
        row.placeholderWarnings = copyTable(resolvedResult.warnings or {})
        row.placeholderFallbackUsed = resolvedResult.fallbackUsed == true
    end
    preview.placeholderWarnings = copyTable(resolvedResult.warnings or {})
    preview.placeholderFallbackUsed = resolvedResult.fallbackUsed == true
    preview.unknownPlaceholders = copyTable(resolvedResult.unknown or {})
    preview.resolvedBody = resolved
    return preview
end

function MessagesService:GetQueue()
    local guild = GC.DB:GetGuild()
    if not guild then
        return {}
    end

    guild.messageQueue = guild.messageQueue or {}
    if type(guild.messageQueue) ~= "table" then
        return {}
    end
    local rows = {}
    for index, entry in ipairs(guild.messageQueue) do
        local queueEntry = type(entry) == "table" and entry or { text = entry, target = "GUILD" }
        rows[#rows + 1] = {
            key = tostring(index),
            index = index,
            text = tostring(queueEntry.text or ""),
            target = tostring(queueEntry.target or "GUILD"),
            recipient = queueEntry.recipient,
            sourceMessageId = queueEntry.sourceMessageId,
            queuedAt = queueEntry.queuedAt,
        }
    end
    return rows
end

function MessagesService:GetQueueSize()
    return #self:GetQueue()
end

function MessagesService:ValidateQueueEntry(entry)
    local text = ""
    local target = "GUILD"
    local recipient
    local channelOptions

    if type(entry) == "table" then
        text = trim(entry.text or "")
        local ok, err, _, normalizedOptions = self:ValidateChannelOptions({
            target = entry.target or "GUILD",
            recipient = entry.recipient,
        })
        if not ok then
            return false, err or "Queued message has an invalid target channel."
        end
        channelOptions = normalizedOptions
        target = normalizedOptions.target
        recipient = normalizedOptions.recipient
    else
        text = trim(entry or "")
        local ok, err, _, normalizedOptions = self:ValidateChannelOptions({ target = "GUILD" })
        if not ok then
            return false, err or "Queued message has an invalid target channel."
        end
        channelOptions = normalizedOptions
    end

    if text == "" then
        return false, "Queued message was empty."
    end

    return true, nil, {
        text = text,
        target = target,
        recipient = recipient,
        channelOptions = channelOptions,
    }
end

function MessagesService:ValidateQueue()
    local guild = GC.DB:GetGuild()
    local queue = guild and guild.messageQueue or {}
    if type(queue) ~= "table" then
        return {
            ok = false,
            total = 1,
            validCount = 0,
            invalidCount = 1,
            invalidEntries = {
                {
                    index = 1,
                    error = "Message queue storage is malformed.",
                },
            },
        }
    end

    local invalid = {}
    local validCount = 0

    for index, entry in ipairs(queue) do
        local ok, err = self:ValidateQueueEntry(entry)
        if ok then
            validCount = validCount + 1
        else
            invalid[#invalid + 1] = {
                index = index,
                error = err or "Queued message is malformed.",
            }
        end
    end

    return {
        ok = #invalid == 0,
        total = #queue,
        validCount = validCount,
        invalidCount = #invalid,
        invalidEntries = invalid,
    }
end

function MessagesService:RepairQueue(options)
    local report = self:ValidateQueue()
    if not options or options.removeInvalid ~= true then
        return report
    end

    local guild = GC.DB:GetGuild()
    if not guild then
        report.removedCount = 0
        return report
    end
    if type(guild.messageQueue) ~= "table" then
        guild.messageQueue = {}
        self:StopAutoSend("queue-repaired")
        report.removedCount = report.invalidCount or 1
        report.remainingCount = 0
        return report
    end

    local repaired = {}
    local removed = 0
    for _, entry in ipairs(guild.messageQueue) do
        local ok = self:ValidateQueueEntry(entry)
        if ok then
            repaired[#repaired + 1] = entry
        else
            removed = removed + 1
        end
    end

    guild.messageQueue = repaired
    if removed > 0 then
        self:StopAutoSend("queue-repaired")
    end

    report.removedCount = removed
    report.remainingCount = #repaired
    return report
end

function MessagesService:QueueChunks(chunks, options)
    if not self:IsEnabled() then
        return false, "Messaging module is disabled."
    end

    local guild = GC.DB:GetGuild()
    if not guild then
        return false, "No guild data available."
    end

    guild.messageQueue = guild.messageQueue or {}
    if type(guild.messageQueue) ~= "table" then
        return false, "Message queue storage is malformed. Clear Queue or repair the queue before adding more chunks."
    end
    options = options or {}
    local ok, err, _, channelOptions = self:ValidateChannelOptions(options)
    if not ok then
        return false, err
    end

    local target = channelOptions.target
    local recipient = channelOptions.recipient
    local pending = {}
    for _, chunk in ipairs(chunks or {}) do
        local text = type(chunk) == "table" and chunk.text or chunk
        text = trim(text)
        if text ~= "" then
            pending[#pending + 1] = {
                text = text,
                target = target,
                recipient = recipient,
                sourceMessageId = options.sourceMessageId,
                queuedAt = now(),
            }
        end
    end

    if #pending == 0 then
        return false, "Nothing to queue."
    end

    local maxQueueSize = self:GetMaxQueueSize()
    if (#guild.messageQueue + #pending) > maxQueueSize then
        return false, string.format("Queue limit reached (%d). Clear or send queued chunks first.", maxQueueSize)
    end

    local batchId = tostring(now()) .. "-" .. tostring(#guild.messageQueue + 1)
    for index, entry in ipairs(pending) do
        entry.batchId = batchId
        entry.batchIndex = index
        entry.chunkCount = #pending
    end

    for _, entry in ipairs(pending) do
        guild.messageQueue[#guild.messageQueue + 1] = entry
    end

    return true
end

function MessagesService:BuildMessagePreview(messageId, options)
    local message = self:GetMessage(messageId)
    if not message then
        return nil, "Message not found."
    end

    options = options or {}
    local preview = self:BuildPreview(message.body, options)
    return {
        message = message,
        preview = preview,
        resolvedBody = preview.resolvedBody or (preview[1] and preview[1].resolvedText) or self:ResolvePlaceholders(message.body, options),
        placeholderWarnings = copyTable(preview.placeholderWarnings or {}),
    }
end

function MessagesService:DirectSendMessage(messageId, options)
    local payload, err = self:BuildMessagePreview(messageId, options)
    if not payload then
        return false, err
    end

    local ok, queueErr = self:QueueChunks(payload.preview, {
        target = options and options.target or "GUILD",
        recipient = options and options.recipient or nil,
        sourceMessageId = messageId,
    })
    if not ok then
        return false, queueErr
    end

    local autoStarted = false
    if self:GetAutomationEnabled() then
        local started = self:StartAutoSend()
        autoStarted = started == true or self:IsAutoSending()
    end

    return true, nil, {
        preview = payload.preview,
        resolvedBody = payload.resolvedBody,
        autoStarted = autoStarted,
    }
end

function MessagesService:QueueMessagePreview(messageId, options)
    local payload, err = self:BuildMessagePreview(messageId, options)
    if not payload then
        return false, err
    end

    return self:QueueChunks(payload.preview, {
        target = options and options.target or "GUILD",
        recipient = options and options.recipient or nil,
        sourceMessageId = messageId,
    })
end

function MessagesService:LoadChunkIntoChat(text, target, recipient)
    text = trim(text)
    if text == "" then
        return false, "Chunk is empty."
    end

    local options
    if type(target) == "table" then
        options = target
    else
        options = {
            target = target or "GUILD",
            recipient = recipient,
        }
    end

    local ok, err, channel, channelOptions = self:ValidateChannelOptions(options)
    if not ok then
        return false, err
    end

    local prefix = channel.chatPrefix or channel.slashPrefix or "/g "
    if channelOptions.recipient then
        prefix = prefix .. channelOptions.recipient .. " "
    end

    if ChatFrame_OpenChat then
        ChatFrame_OpenChat(prefix .. text)
        return true
    end

    return false, "Chat input is unavailable."
end

function MessagesService:IsAutoSending()
    return self._autoSendActive == true
end

function MessagesService:GetAutoSendStatus()
    local queueSize = self:GetQueueSize()
    if self:IsAutoSending() then
        local remaining = self:GetSendCooldownRemaining()
        if remaining > 0 then
            return string.format("Auto running - waiting %.1fs - %d queued", remaining, queueSize)
        end
        return string.format("Auto running - %d queued", queueSize)
    end
    if self:GetAutomationEnabled() then
        return string.format("Auto Mode enabled - %d queued", queueSize)
    end
    return string.format("Manual Mode - %d queued", queueSize)
end

function MessagesService:GetSendCooldownRemaining()
    local currentTime = GetTime and GetTime() or 0
    if not self._lastSendAt or currentTime <= 0 then
        return 0
    end

    return math.max(0, SEND_COOLDOWN_SECONDS - (currentTime - self._lastSendAt))
end

function MessagesService:_ScheduleAutoSendTick(delay)
    local token = self._autoSendToken
    if self._autoSendTimer and self._autoSendTimer.Cancel then
        self._autoSendTimer:Cancel()
    end

    self._autoSendTimer = C_Timer.NewTimer(delay, function()
        if not self._autoSendActive or self._autoSendToken ~= token then
            return
        end

        if not self:IsEnabled() then
            self:StopAutoSend("disabled")
            return
        end

        local ok, err = self:SendNextQueuedMessage()
        if ok then
            if self:GetQueueSize() == 0 then
                self:StopAutoSend("complete")
            else
                self:_ScheduleAutoSendTick(self:GetAutoSendDelaySeconds())
            end
            return
        end

        if err == "Queue is empty." then
            self:StopAutoSend("complete")
            return
        end

        if err and err:find("Please wait", 1, true) then
            self:_ScheduleAutoSendTick(math.max(self:GetAutoSendDelaySeconds(), SEND_COOLDOWN_SECONDS))
            return
        end

        self:StopAutoSend("error")
    end)
end

function MessagesService:StartAutoSend()
    if not self:IsEnabled() then
        return false, "Messaging module is disabled."
    end
    if not self:GetAutomationEnabled() then
        return false, "Auto Mode is disabled."
    end
    if self:GetQueueSize() == 0 then
        return false, "Queue is empty."
    end
    if self:IsAutoSending() then
        return false, "Auto-send is already running."
    end

    self._autoSendToken = (self._autoSendToken or 0) + 1
    self._autoSendActive = true
    self:_ScheduleAutoSendTick(0)
    return true
end

function MessagesService:StopAutoSend(reason)
    if self._autoSendTimer and self._autoSendTimer.Cancel then
        self._autoSendTimer:Cancel()
    end
    self._autoSendTimer = nil
    self._autoSendActive = false
    self._autoSendStopReason = reason or "manual"
    return true
end

function MessagesService:SendNextQueuedMessage()
    if not self:IsEnabled() then
        self:StopAutoSend("disabled")
        return false, "Messaging module is disabled."
    end

    local guild = GC.DB:GetGuild()
    if not guild or not guild.messageQueue then
        return false, "Queue is empty."
    end
    if type(guild.messageQueue) ~= "table" then
        return false, "Message queue storage is malformed. Clear Queue or repair the queue."
    end
    if #guild.messageQueue == 0 then
        return false, "Queue is empty."
    end

    local currentTime = GetTime and GetTime() or 0
    if self._lastSendAt and currentTime > 0 and (currentTime - self._lastSendAt) < SEND_COOLDOWN_SECONDS then
        return false, string.format("Please wait %.1f seconds before sending again.", self:GetSendCooldownRemaining())
    end

    local nextEntry = guild.messageQueue[1]
    local valid, validationErr, normalized = self:ValidateQueueEntry(nextEntry)
    if not valid then
        return false, (validationErr or "Queued message is malformed.") .. " Clear Queue or repair the queue."
    end

    SendChatMessage(normalized.text, normalized.target, nil, normalized.recipient)
    table.remove(guild.messageQueue, 1)
    self._lastSendAt = currentTime > 0 and currentTime or nil
    if type(nextEntry) == "table" and nextEntry.sourceMessageId and (tonumber(nextEntry.batchIndex) or 1) == 1 then
        self:RecordMessageUsage(nextEntry.sourceMessageId, {
            target = normalized.target,
            recipient = normalized.recipient,
            sentAt = now(),
            chunkCount = tonumber(nextEntry.chunkCount) or 1,
        })
    end
    return true
end

function MessagesService:ClearQueue()
    local guild = GC.DB:GetGuild()
    if not guild then
        return false
    end
    guild.messageQueue = {}
    self:StopAutoSend("cleared")
    return true
end

local messagesInstance = setmetatable({}, MessagesService)
GC:RegisterService("Messages", messagesInstance)
GC:RegisterService("Messaging", messagesInstance)

local addonName, ns = ...
local GC = ns.GuildCore

-- Shared constants and helpers exposed to all messaging sub-modules via ns.MessagesHelpers.
ns.MessagesHelpers = ns.MessagesHelpers or {}
local H = ns.MessagesHelpers

H.DEFAULT_CATEGORY_ID      = "general"
H.DEFAULT_AUTO_SEND_DELAY  = 2
H.DEFAULT_MAX_QUEUE_SIZE   = 25
H.SEND_COOLDOWN_SECONDS    = 1.2
H.MESSAGE_HISTORY_LIMIT    = 250

H.DEFAULT_CATEGORY_SEEDS = {
    { id = "general",              name = "General" },
    { id = "recruitment",          name = "Recruitment" },
    { id = "welcome-onboarding",   name = "Welcome / Onboarding" },
    { id = "discord-verification", name = "Discord Verification" },
    { id = "raid",                 name = "Raid" },
    { id = "mythic-plus",          name = "Mythic+" },
    { id = "events",               name = "Events" },
    { id = "officer-notes",        name = "Officer Notes" },
    { id = "guild-rules",          name = "Guild Rules" },
    { id = "follow-ups",           name = "Follow-Ups" },
}

function H.trim(value)
    -- Safe fallback if GC.Utils is not yet loaded
    if GC.Utils and GC.Utils.Trim then
        return GC.Utils.Trim(value or "")
    end
    value = tostring(value or "")
    return (value:match("^%s*(.-)%s*$"))
end

function H.now()
    return GC.Utils and GC.Utils.Now and GC.Utils.Now() or time()
end

function H.arrayContains(array, value)
    -- Fallback if GC.Utils is not yet available
    if GC.Utils and GC.Utils.ArrayContains then
        return GC.Utils.ArrayContains(array, value)
    end
    for _, v in ipairs(array or {}) do
        if v == value then return true end
    end
    return false
end

function H.removeArrayValue(array, value)
    -- Fallback if GC.Utils is not yet available
    if GC.Utils and GC.Utils.RemoveArrayValue then
        GC.Utils.RemoveArrayValue(array, value)
        return
    end
    for i = #(array or {}), 1, -1 do
        if array[i] == value then table.remove(array, i) end
    end
end

function H.getGuild()
    return GC.DB and GC.DB.GetGuild and GC.DB:GetGuild() or nil
end

function H.getSettings()
    return GC.DB and GC.DB.GetSettings and GC.DB:GetSettings() or nil
end

function H.copyTable(source)
    local result = {}
    for key, value in pairs(source or {}) do
        result[key] = value
    end
    return result
end

function H.currentPlayerName()
    local name = UnitName and UnitName("player") or nil
    name = H.trim(name)
    if name == "" then return nil end
    return name
end

function H.normalizeTags(tags)
    if type(tags) ~= "table" then return {} end
    local normalized = {}
    for _, tag in ipairs(tags) do
        tag = H.trim(tag)
        if tag ~= "" then
            normalized[#normalized + 1] = tag
        end
    end
    return normalized
end

function H.lowerText(value)
    return H.trim(value):lower()
end

function H.textMatchesSearch(value, searchText)
    return tostring(value or ""):lower():find(searchText, 1, true) ~= nil
end

function H.tagsMatchSearch(tags, searchText)
    if type(tags) ~= "table" then return false end
    for _, tag in ipairs(tags) do
        if H.textMatchesSearch(tag, searchText) then return true end
    end
    return false
end

function H.ensureMessagingCampaignsState(guild)
    if not guild then return nil end
    if type(guild.messagingCampaigns) ~= "table" then
        guild.messagingCampaigns = {}
    end
    local campaigns = guild.messagingCampaigns
    campaigns.meta = campaigns.meta or {}
    campaigns.meta.nextCampaignId = math.max(1, math.floor(tonumber(campaigns.meta.nextCampaignId) or 1))
    campaigns.meta.nextStepId     = math.max(1, math.floor(tonumber(campaigns.meta.nextStepId) or 1))
    if type(campaigns.campaigns) ~= "table" then campaigns.campaigns = {} end
    if type(campaigns.steps) ~= "table" then campaigns.steps = {} end
    return campaigns
end

-- Shared proto table; each sub-module adds its methods here before Service.lua registers the singleton.
ns.MessagesImpl = ns.MessagesImpl or {}
local I = ns.MessagesImpl

-- Local aliases used within this file
local DEFAULT_CATEGORY_ID    = H.DEFAULT_CATEGORY_ID
local DEFAULT_AUTO_SEND_DELAY = H.DEFAULT_AUTO_SEND_DELAY
local DEFAULT_MAX_QUEUE_SIZE  = H.DEFAULT_MAX_QUEUE_SIZE
local MESSAGE_HISTORY_LIMIT   = H.MESSAGE_HISTORY_LIMIT
local trim           = H.trim
local now            = H.now
local arrayContains  = H.arrayContains
local removeArrayValue = H.removeArrayValue
local getGuild       = H.getGuild
local getSettings    = H.getSettings
local lowerText      = H.lowerText
local ensureMessagingCampaignsState = H.ensureMessagingCampaignsState

function I:IsEnabled()
    local settings = getSettings()
    return not settings or settings.enableMessagingModule ~= false
end

function I:GetStorage()
    local guild = getGuild()
    if not guild then return nil end

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
    storage.meta.nextMessageId        = tonumber(storage.meta.nextMessageId) or 1
    storage.meta.nextCategoryId       = tonumber(storage.meta.nextCategoryId) or 1
    storage.meta.selectedCategoryId   = storage.meta.selectedCategoryId or DEFAULT_CATEGORY_ID
    storage.meta.selectedMessageId    = storage.meta.selectedMessageId or nil
    storage.meta.automationEnabled    = storage.meta.automationEnabled == true
    storage.meta.autoSendDelaySeconds = tonumber(storage.meta.autoSendDelaySeconds) or DEFAULT_AUTO_SEND_DELAY
    storage.meta.maxQueueSize         = tonumber(storage.meta.maxQueueSize) or DEFAULT_MAX_QUEUE_SIZE
    storage.meta.previewTargetName    = tostring(storage.meta.previewTargetName or "")
    storage.meta.dailyTargetHour      = tonumber(storage.meta.dailyTargetHour) or 18
    storage.meta.dailyTargetMinute    = tonumber(storage.meta.dailyTargetMinute) or 0
    storage.meta.lastJoinedName       = storage.meta.lastJoinedName or nil
    storage.categories              = storage.categories or {}
    storage.categoryOrder           = storage.categoryOrder or {}
    storage.messages                = storage.messages or {}
    storage.messageOrderByCategory  = storage.messageOrderByCategory or {}

    local stamp = now()
    storage.categories[DEFAULT_CATEGORY_ID] = storage.categories[DEFAULT_CATEGORY_ID] or {
        id = DEFAULT_CATEGORY_ID, name = "General", createdAt = stamp, updatedAt = stamp,
    }

    if not arrayContains(storage.categoryOrder, DEFAULT_CATEGORY_ID) then
        table.insert(storage.categoryOrder, 1, DEFAULT_CATEGORY_ID)
    end

    storage.messageOrderByCategory[DEFAULT_CATEGORY_ID] = storage.messageOrderByCategory[DEFAULT_CATEGORY_ID] or {}

    self:ValidateStorage(storage)
    return storage
end

function I:GetCampaignStorage()
    local guild = getGuild()
    return ensureMessagingCampaignsState(guild)
end

function I:SeedDefaultCategories(storage)
    if not storage then return end
    local stamp = now()
    local names = {}
    for _, category in pairs(storage.categories or {}) do
        if type(category) == "table" then
            names[lowerText(category.name)] = true
        end
    end
    for _, seed in ipairs(H.DEFAULT_CATEGORY_SEEDS) do
        local seedId   = seed.id
        local seedName = seed.name
        if not storage.categories[seedId] and not names[lowerText(seedName)] then
            storage.categories[seedId] = {
                id = seedId, name = seedName,
                createdAt = stamp, updatedAt = stamp,
                archived = false, collapsed = false, color = nil, icon = nil,
            }
            storage.messageOrderByCategory[seedId] = storage.messageOrderByCategory[seedId] or {}
            storage.categoryOrder[#storage.categoryOrder + 1] = seedId
            names[lowerText(seedName)] = true
        end
    end
end

function I:ValidateStorage(storage)
    if not storage then return end

    storage.meta = storage.meta or {}
    storage.meta.automationEnabled    = storage.meta.automationEnabled == true
    storage.meta.autoSendDelaySeconds = math.max(0.5, tonumber(storage.meta.autoSendDelaySeconds) or DEFAULT_AUTO_SEND_DELAY)
    storage.meta.maxQueueSize         = math.max(1, math.floor(tonumber(storage.meta.maxQueueSize) or DEFAULT_MAX_QUEUE_SIZE))
    storage.meta.previewTargetName    = tostring(storage.meta.previewTargetName or "")
    storage.meta.dailyTargetHour      = math.max(0, math.min(23, tonumber(storage.meta.dailyTargetHour) or 18))
    storage.meta.dailyTargetMinute    = math.max(0, math.min(59, tonumber(storage.meta.dailyTargetMinute) or 0))
    storage.categories             = storage.categories or {}
    storage.categoryOrder          = storage.categoryOrder or {}
    storage.messages               = storage.messages or {}
    storage.messageOrderByCategory = storage.messageOrderByCategory or {}

    self:SeedDefaultCategories(storage)

    local validCategoryIds        = {}
    local normalizedCategoryOrder = {}

    for _, categoryId in ipairs(storage.categoryOrder or {}) do
        if type(categoryId) == "string" and type(storage.categories[categoryId]) == "table" and not validCategoryIds[categoryId] then
            validCategoryIds[categoryId] = true
            normalizedCategoryOrder[#normalizedCategoryOrder + 1] = categoryId
        end
    end

    for categoryId, category in pairs(storage.categories or {}) do
        if type(category) == "table" then
            category.id   = categoryId
            category.name = trim(category.name or categoryId)
            if category.name == "" then
                category.name = categoryId == DEFAULT_CATEGORY_ID and "General" or "Category"
            end
            category.createdAt = tonumber(category.createdAt) or now()
            category.updatedAt = tonumber(category.updatedAt) or category.createdAt
            category.archived  = category.archived == true
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
            message.id    = tostring(message.id or messageId)
            message.title = trim(message.title)
            if message.title == "" then message.title = "Untitled Message" end
            message.body       = tostring(message.body or "")
            message.notes      = tostring(message.notes or "")
            message.lastUsedAt = tonumber(message.lastUsedAt) or nil
            -- NormalizeTargetChannel is defined in Service.lua; safe because ValidateStorage is only called at runtime
            message.targetChannel = self:NormalizeTargetChannel(message.targetChannel)
            if type(message.tags) ~= "table" then message.tags = {} end
            message.usageCount = math.max(0, math.floor(tonumber(message.usageCount) or 0))
            local actor = H.currentPlayerName()
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
            if not storage.categories[categoryId] then categoryId = DEFAULT_CATEGORY_ID end
            message.categoryId = categoryId
            message.createdAt  = tonumber(message.createdAt) or now()
            message.updatedAt  = tonumber(message.updatedAt) or message.createdAt
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
            if validMessageIds[messageId] and storage.messages[messageId]
                and storage.messages[messageId].categoryId == categoryId and not seen[messageId] then
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
        if not arrayContains(storage.messageOrderByCategory[categoryId], messageId) then
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

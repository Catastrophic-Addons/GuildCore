local addonName, ns = ...
local GC = ns.GuildCore

local H = ns.MessagesHelpers
local I = ns.MessagesImpl

local DEFAULT_CATEGORY_ID = H.DEFAULT_CATEGORY_ID
local trim             = H.trim
local now              = H.now
local copyTable        = H.copyTable
local removeArrayValue = H.removeArrayValue
local normalizeTags    = H.normalizeTags
local lowerText        = H.lowerText
local textMatchesSearch = H.textMatchesSearch
local tagsMatchSearch   = H.tagsMatchSearch
local currentPlayerName = H.currentPlayerName

function I:GetSelectedMessageId()
    local storage = self:GetStorage()
    return storage and storage.meta.selectedMessageId or nil
end

function I:SetSelectedMessage(messageId)
    local storage = self:GetStorage()
    if storage then
        storage.meta.selectedMessageId = storage.messages[messageId] and messageId or nil
    end
end

function I:GetMessage(messageId)
    local storage = self:GetStorage()
    local message = storage and storage.messages[messageId] or nil
    return message and copyTable(message) or nil
end

function I:GetMessageOrder(categoryId)
    local storage = self:GetStorage()
    if not storage then return {} end
    return storage.messageOrderByCategory[categoryId or storage.meta.selectedCategoryId or DEFAULT_CATEGORY_ID] or {}
end

function I:ListMessages(categoryId, options)
    local storage = self:GetStorage()
    if not storage then return {} end

    options = options or {}
    local showArchived  = options.showArchived == true
    local favoritesOnly = options.favoritesOnly == true
    local searchText    = lowerText(options.search or "")
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
                id           = message.id,
                key          = message.id,
                title        = message.title,
                notes        = message.notes,
                body         = message.body,
                categoryId   = message.categoryId,
                position     = index,
                updatedAt    = message.updatedAt,
                updatedLabel = date("%Y-%m-%d", message.updatedAt or now()),
                lastUsedAt   = message.lastUsedAt,
                lastUsedLabel = message.lastUsedAt and date("%Y-%m-%d", message.lastUsedAt) or nil,
                targetChannel = message.targetChannel or "GUILD",
                tags         = copyTable(message.tags),
                usageCount   = tonumber(message.usageCount) or 0,
                createdBy    = message.createdBy,
                updatedBy    = message.updatedBy,
                favorite     = message.favorite == true,
                archived     = message.archived == true,
            }
        end
    end
    return rows
end

function I:CreateMessage(fields)
    local storage = self:GetStorage()
    if not storage then return nil, "No guild data available." end

    fields = fields or {}
    local title = trim(fields.title)
    if title == "" then title = "New Message" end

    local categoryId = tostring(fields.categoryId or storage.meta.selectedCategoryId or DEFAULT_CATEGORY_ID)
    if not storage.categories[categoryId] then categoryId = DEFAULT_CATEGORY_ID end

    local messageId = "msg-" .. tostring(storage.meta.nextMessageId)
    storage.meta.nextMessageId = storage.meta.nextMessageId + 1
    local stamp = now()
    local actor = currentPlayerName()
    storage.messages[messageId] = {
        id            = messageId,
        title         = title,
        categoryId    = categoryId,
        body          = tostring(fields.body or ""),
        notes         = tostring(fields.notes or ""),
        -- NormalizeTargetChannel is added by Service.lua, resolved at call time
        targetChannel = self:NormalizeTargetChannel(fields.targetChannel or fields.target or "GUILD"),
        tags          = normalizeTags(fields.tags),
        usageCount    = 0,
        createdBy     = actor,
        updatedBy     = actor,
        favorite      = fields.favorite == true,
        archived      = fields.archived == true,
        createdAt     = stamp,
        updatedAt     = stamp,
        lastUsedAt    = nil,
    }

    storage.messageOrderByCategory[categoryId] = storage.messageOrderByCategory[categoryId] or {}
    storage.messageOrderByCategory[categoryId][#storage.messageOrderByCategory[categoryId] + 1] = messageId
    storage.meta.selectedCategoryId = categoryId
    storage.meta.selectedMessageId  = messageId
    return self:GetMessage(messageId)
end

function I:UpdateMessage(messageId, fields)
    local storage = self:GetStorage()
    if not storage then return false, "Storage not available." end
    local message = storage.messages[messageId]
    if not message then return false, "Message not found." end

    fields = fields or {}
    local oldCategoryId    = message.categoryId
    local targetCategoryId = tostring(fields.categoryId or message.categoryId or DEFAULT_CATEGORY_ID)
    if not storage.categories[targetCategoryId] then targetCategoryId = DEFAULT_CATEGORY_ID end

    local title = trim(fields.title ~= nil and fields.title or message.title)
    if title == "" then return false, "Message title is required." end

    message.title = title
    message.body  = tostring(fields.body  ~= nil and fields.body  or message.body  or "")
    message.notes = tostring(fields.notes ~= nil and fields.notes or message.notes or "")
    if fields.targetChannel ~= nil or fields.target ~= nil then
        message.targetChannel = self:NormalizeTargetChannel(fields.targetChannel or fields.target)
    end
    if fields.tags     ~= nil then message.tags     = normalizeTags(fields.tags) end
    if fields.favorite ~= nil then message.favorite = fields.favorite == true end
    if fields.archived ~= nil then message.archived = fields.archived == true end
    message.updatedAt = now()
    message.updatedBy = currentPlayerName() or message.updatedBy or message.createdBy

    if targetCategoryId ~= oldCategoryId then
        self:MoveMessageToCategory(messageId, targetCategoryId)
        message = storage.messages[messageId]
        if not message then return false, "Message not found after category move." end
    end

    message.categoryId = targetCategoryId
    storage.meta.selectedCategoryId = targetCategoryId
    storage.meta.selectedMessageId  = messageId
    return true
end

function I:DeleteMessage(messageId)
    local storage = self:GetStorage()
    if not storage then return false, "Storage not available." end
    local message = storage.messages[messageId]
    if not message then return false, "Message not found." end

    removeArrayValue(storage.messageOrderByCategory[message.categoryId] or {}, messageId)
    storage.messages[messageId] = nil

    if storage.meta.selectedMessageId == messageId then
        storage.meta.selectedMessageId = nil
    end
    if storage.meta.selectedCategoryId == nil or not storage.categories[storage.meta.selectedCategoryId] then
        storage.meta.selectedCategoryId = DEFAULT_CATEGORY_ID
    end
    return true
end

function I:SetMessageArchived(messageId, archived)
    local storage = self:GetStorage()
    if not storage then return false, "Storage not available." end
    local message = storage.messages[messageId]
    if not message then return false, "Message not found." end
    message.archived  = archived == true
    message.updatedAt = now()
    message.updatedBy = currentPlayerName() or message.updatedBy or message.createdBy
    if message.archived and storage.meta.selectedMessageId == messageId then
        storage.meta.selectedMessageId = nil
    end
    return true
end

function I:ArchiveMessage(messageId)
    return self:SetMessageArchived(messageId, true)
end

function I:UnarchiveMessage(messageId)
    return self:SetMessageArchived(messageId, false)
end

function I:SetMessageFavorite(messageId, favorite)
    local storage = self:GetStorage()
    if not storage then return false, "Storage not available." end
    local message = storage.messages[messageId]
    if not message then return false, "Message not found." end
    message.favorite  = favorite == true
    message.updatedAt = now()
    message.updatedBy = currentPlayerName() or message.updatedBy or message.createdBy
    return true
end

function I:ToggleMessageFavorite(messageId)
    local message = self:GetMessage(messageId)
    if not message then return false, "Message not found." end
    return self:SetMessageFavorite(messageId, not message.favorite)
end

function I:DuplicateMessage(messageId)
    local storage = self:GetStorage()
    if not storage then return nil, "Storage not available." end
    local source = storage.messages[messageId]
    if not source then return nil, "Message not found." end

    local baseTitle = trim(source.title)
    if baseTitle == "" then baseTitle = "Untitled Message" end
    local wanted = baseTitle .. " Copy"
    local title  = wanted
    local suffix = 2
    local taken  = {}
    for _, message in pairs(storage.messages) do
        taken[lowerText(message.title)] = true
    end
    while taken[lowerText(title)] do
        title  = wanted .. " " .. tostring(suffix)
        suffix = suffix + 1
    end

    local messageIdNew = "msg-" .. tostring(storage.meta.nextMessageId)
    storage.meta.nextMessageId = storage.meta.nextMessageId + 1
    local stamp      = now()
    local actor      = currentPlayerName()
    local categoryId = storage.categories[source.categoryId] and source.categoryId or DEFAULT_CATEGORY_ID

    storage.messages[messageIdNew] = {
        id            = messageIdNew,
        title         = title,
        categoryId    = categoryId,
        body          = tostring(source.body or ""),
        notes         = tostring(source.notes or ""),
        targetChannel = self:NormalizeTargetChannel(source.targetChannel or "GUILD"),
        tags          = normalizeTags(source.tags),
        usageCount    = 0,
        createdBy     = actor,
        updatedBy     = actor,
        favorite      = false,
        archived      = false,
        createdAt     = stamp,
        updatedAt     = stamp,
        lastUsedAt    = nil,
    }

    storage.messageOrderByCategory[categoryId] = storage.messageOrderByCategory[categoryId] or {}
    local sourceIndex = self:GetMessageIndex(messageId) or #storage.messageOrderByCategory[categoryId]
    table.insert(storage.messageOrderByCategory[categoryId], sourceIndex + 1, messageIdNew)
    storage.meta.selectedCategoryId = categoryId
    storage.meta.selectedMessageId  = messageIdNew
    return self:GetMessage(messageIdNew)
end

function I:RecordMessageUsage(messageId, output)
    local storage = self:GetStorage()
    if not storage or not messageId then return false, "Storage not available." end
    local message = storage.messages[messageId]
    if not message then return false, "Message not found." end

    output = output or {}
    local stamp  = tonumber(output.sentAt) or now()
    local target = self:NormalizeTargetChannel(output.target or message.targetChannel or "GUILD")
    message.usageCount = math.max(0, math.floor(tonumber(message.usageCount) or 0)) + 1
    message.lastUsedAt = stamp

    self:AddHistoryEntry({
        templateId = message.id,
        title      = message.title,
        target     = target,
        recipient  = output.recipient,
        sentBy     = output.sentBy or currentPlayerName() or "Unknown",
        sentAt     = stamp,
        chunkCount = output.chunkCount or 1,
    })
    return true
end

function I:MoveMessageUp(messageId)
    local message = self:GetMessage(messageId)
    if not message then return false, "Message not found." end
    return self:MoveMessageToIndex(messageId, (self:GetMessageIndex(messageId) or 1) - 1)
end

function I:MoveMessageDown(messageId)
    local message = self:GetMessage(messageId)
    if not message then return false, "Message not found." end
    return self:MoveMessageToIndex(messageId, (self:GetMessageIndex(messageId) or 1) + 1)
end

function I:GetMessageIndex(messageId)
    local storage = self:GetStorage()
    if not storage then return nil end
    local message = storage.messages[messageId]
    if not message then return nil end
    for index, currentId in ipairs(storage.messageOrderByCategory[message.categoryId] or {}) do
        if currentId == messageId then return index end
    end
    return nil
end

function I:MoveMessageToIndex(messageId, desiredIndex)
    local storage = self:GetStorage()
    if not storage then return false, "Storage not available." end
    local message = storage.messages[messageId]
    if not message then return false, "Message not found." end

    local order = storage.messageOrderByCategory[message.categoryId] or {}
    local currentIndex
    for index, currentId in ipairs(order) do
        if currentId == messageId then
            currentIndex = index
            break
        end
    end
    if not currentIndex then return false, "Message order could not be updated." end

    desiredIndex = math.max(1, math.min(#order, tonumber(desiredIndex) or currentIndex))
    if desiredIndex == currentIndex then return true end

    table.remove(order, currentIndex)
    table.insert(order, desiredIndex, messageId)
    return true
end

function I:MoveMessageToCategory(messageId, categoryId)
    local storage = self:GetStorage()
    if not storage then return false, "Storage not available." end
    local message = storage.messages[messageId]
    if not message then return false, "Message not found." end
    if not storage.categories[categoryId] then return false, "Target category not found." end

    local oldCategoryId = message.categoryId or DEFAULT_CATEGORY_ID
    if oldCategoryId == categoryId then return true end

    removeArrayValue(storage.messageOrderByCategory[oldCategoryId] or {}, messageId)
    storage.messageOrderByCategory[categoryId] = storage.messageOrderByCategory[categoryId] or {}
    storage.messageOrderByCategory[categoryId][#storage.messageOrderByCategory[categoryId] + 1] = messageId

    message.categoryId = categoryId
    message.updatedAt  = now()
    storage.meta.selectedCategoryId = categoryId
    storage.meta.selectedMessageId  = messageId
    return true
end

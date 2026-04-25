local addonName, ns = ...
local GC = ns.GuildCore

local MessagesService = {}
MessagesService.__index = MessagesService

local DEFAULT_CATEGORY_ID = "general"
local DEFAULT_AUTO_SEND_DELAY = 2
local DEFAULT_MAX_QUEUE_SIZE = 25
local SEND_COOLDOWN_SECONDS = 1.2

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

function MessagesService:IsEnabled()
    local settings = GC.DB:GetSettings()
    return not settings or settings.enableMessagingModule ~= false
end

function MessagesService:GetStorage()
    local guild = GC.DB:GetGuild()
    if not guild then
        return nil
    end

    guild.messageQueue = guild.messageQueue or {}
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
        dailyTargetHour = options.dailyTargetHour ~= nil and options.dailyTargetHour or (storage and storage.meta.dailyTargetHour or 18),
        dailyTargetMinute = options.dailyTargetMinute ~= nil and options.dailyTargetMinute or (storage and storage.meta.dailyTargetMinute or 0),
    }
end

function MessagesService:ResolvePlaceholders(text, options)
    local placeholderService = GC.Services.MessagePlaceholders
    if not placeholderService then
        return tostring(text or "")
    end

    return placeholderService:ResolveText(text, self:GetResolveContext(options))
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

function MessagesService:ListCategories()
    local storage = self:GetStorage()
    if not storage then
        return {}
    end

    local rows = {}
    for _, categoryId in ipairs(storage.categoryOrder) do
        local category = storage.categories[categoryId]
        if category then
            rows[#rows + 1] = {
                id = category.id,
                key = category.id,
                name = category.name,
                count = #(storage.messageOrderByCategory[categoryId] or {}),
                isDefault = category.id == DEFAULT_CATEGORY_ID,
                createdAt = category.createdAt,
                updatedAt = category.updatedAt,
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

function MessagesService:ListMessages(categoryId)
    local storage = self:GetStorage()
    if not storage then
        return {}
    end

    categoryId = categoryId or storage.meta.selectedCategoryId or DEFAULT_CATEGORY_ID
    local rows = {}
    for index, messageId in ipairs(storage.messageOrderByCategory[categoryId] or {}) do
        local message = storage.messages[messageId]
        if message then
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
    storage.messages[messageId] = {
        id = messageId,
        title = title,
        categoryId = categoryId,
        body = tostring(fields.body or ""),
        notes = tostring(fields.notes or ""),
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
    message.updatedAt = now()

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

    local resolved = self:ResolvePlaceholders(body, options)
    local preview = chunker:Preview(resolved, options)
    for _, row in ipairs(preview) do
        row.categoryId = nil
        row.resolvedText = resolved
    end
    return preview
end

function MessagesService:GetQueue()
    local guild = GC.DB:GetGuild()
    if not guild then
        return {}
    end

    guild.messageQueue = guild.messageQueue or {}
    local rows = {}
    for index, entry in ipairs(guild.messageQueue) do
        local queueEntry = type(entry) == "table" and entry or { text = entry, target = "GUILD" }
        rows[#rows + 1] = {
            key = tostring(index),
            index = index,
            text = tostring(queueEntry.text or ""),
            target = tostring(queueEntry.target or "GUILD"),
            sourceMessageId = queueEntry.sourceMessageId,
            queuedAt = queueEntry.queuedAt,
        }
    end
    return rows
end

function MessagesService:GetQueueSize()
    return #self:GetQueue()
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
    options = options or {}
    local target = options.target or "GUILD"
    local pending = {}
    for _, chunk in ipairs(chunks or {}) do
        local text = type(chunk) == "table" and chunk.text or chunk
        text = trim(text)
        if text ~= "" then
            pending[#pending + 1] = {
                text = text,
                target = target,
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
        resolvedBody = self:ResolvePlaceholders(message.body, options),
    }
end

function MessagesService:DirectSendMessage(messageId, options)
    local payload, err = self:BuildMessagePreview(messageId, options)
    if not payload then
        return false, err
    end

    local ok, queueErr = self:QueueChunks(payload.preview, {
        target = options and options.target or "GUILD",
        sourceMessageId = messageId,
    })
    if not ok then
        return false, queueErr
    end

    local storage = self:GetStorage()
    if storage and storage.messages[messageId] then
        storage.messages[messageId].lastUsedAt = now()
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
        sourceMessageId = messageId,
    })
end

function MessagesService:LoadChunkIntoChat(text, target)
    text = trim(text)
    if text == "" then
        return false, "Chunk is empty."
    end

    target = target or "GUILD"
    local prefixMap = {
        GUILD = "/g ",
        OFFICER = "/o ",
        WHISPER = "/w ",
    }
    local prefix = prefixMap[target] or "/g "

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
    if self:IsAutoSending() then
        return "Auto sending active"
    end
    if self:GetAutomationEnabled() then
        return "Auto Mode enabled"
    end
    return "Manual Mode"
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
    if not guild or not guild.messageQueue or #guild.messageQueue == 0 then
        return false, "Queue is empty."
    end

    local currentTime = GetTime and GetTime() or 0
    if self._lastSendAt and currentTime > 0 and (currentTime - self._lastSendAt) < SEND_COOLDOWN_SECONDS then
        return false, string.format("Please wait %.1f seconds before sending again.", SEND_COOLDOWN_SECONDS)
    end

    local nextEntry = table.remove(guild.messageQueue, 1)
    local target = "GUILD"
    local text = ""
    if type(nextEntry) == "table" then
        target = tostring(nextEntry.target or "GUILD")
        text = trim(nextEntry.text or "")
    else
        text = trim(nextEntry or "")
    end

    if text == "" then
        return false, "Queued message was empty."
    end

    SendChatMessage(text, target)
    self._lastSendAt = currentTime > 0 and currentTime or nil
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

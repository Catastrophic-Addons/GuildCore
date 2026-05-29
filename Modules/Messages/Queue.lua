local addonName, ns = ...
local GC = ns.GuildCore

local H = ns.MessagesHelpers
local I = ns.MessagesImpl

local trim     = H.trim
local now      = H.now
local copyTable = H.copyTable
local getGuild  = H.getGuild

local GUILD_MESSAGE_DELAY = H.DEFAULT_AUTO_SEND_DELAY or 2

local function queueStorage()
    local guild = getGuild()
    if not guild then return nil, "No guild data available." end
    guild.messageQueue = guild.messageQueue or {}
    if type(guild.messageQueue) ~= "table" then
        return nil, "Message queue storage is malformed. Clear Queue or repair the queue before adding more chunks."
    end
    return guild.messageQueue
end

function I:BuildPreview(body, options)
    local chunker = GC.Services.MessageChunker
    if not chunker then return {} end

    options = options or {}
    options.limit = math.max(20, math.min(255, tonumber(options.limit) or 255))
    options.includeNumbers = false

    local resolvedResult = self:ResolvePlaceholderResult(body, options)
    local resolved = resolvedResult.text or ""
    local preview  = chunker:Preview(resolved, options)
    for _, row in ipairs(preview) do
        row.categoryId              = nil
        row.resolvedText            = resolved
        row.placeholderWarnings     = copyTable(resolvedResult.warnings or {})
        row.placeholderFallbackUsed = resolvedResult.fallbackUsed == true
    end
    preview.placeholderWarnings     = copyTable(resolvedResult.warnings or {})
    preview.placeholderFallbackUsed = resolvedResult.fallbackUsed == true
    preview.unknownPlaceholders     = copyTable(resolvedResult.unknown or {})
    preview.resolvedBody            = resolved
    return preview
end

function I:SplitMessage(message, maxLength)
    local chunker = GC.Services.MessageChunker
    if not chunker or not chunker.Split then return {} end
    return chunker:Split(message, { limit = maxLength or 255, includeNumbers = false })
end

function I:GetQueue()
    local guild = getGuild()
    if not guild then return {} end

    guild.messageQueue = guild.messageQueue or {}
    if type(guild.messageQueue) ~= "table" then return {} end

    local rows = {}
    for index, entry in ipairs(guild.messageQueue) do
        local queueEntry = type(entry) == "table" and entry or { text = entry, target = "GUILD" }
        rows[#rows + 1] = {
            key             = tostring(index),
            index           = index,
            text            = tostring(queueEntry.text or ""),
            target          = tostring(queueEntry.target or "GUILD"),
            recipient       = queueEntry.recipient,
            sourceMessageId = queueEntry.sourceMessageId,
            queuedAt        = queueEntry.queuedAt,
        }
    end
    return rows
end

function I:GetQueueSize()
    return #self:GetQueue()
end

function I:GetQueueHealth()
    local guild = getGuild()
    if not guild then
        return { status = "unavailable", queueSize = 0, healthy = false, message = "Guild data unavailable." }
    end
    if type(guild.messageQueue) ~= "table" then
        return { status = "malformed", queueSize = 0, healthy = false, message = "Queue storage is not a table." }
    end
    local size = #guild.messageQueue
    if size == 0 then
        return { status = "empty", queueSize = 0, healthy = true, message = "Queue is empty." }
    end
    local firstOk, firstErr = self:ValidateQueueEntry(guild.messageQueue[1])
    if not firstOk then
        -- First entry blocks send; report specifically so UI can surface it
        return { status = "blocked", queueSize = size, healthy = false, message = firstErr or "First queue entry is malformed." }
    end
    local report = self:ValidateQueue()
    if not report.ok then
        return { status = "partial", queueSize = size, healthy = false,
                 message = string.format("%d of %d entries are malformed.", report.invalidCount, size) }
    end
    return { status = "healthy", queueSize = size, healthy = true, message = string.format("%d queued.", size) }
end

function I:ValidateQueueEntry(entry)
    local text
    local target = "GUILD"
    local recipient
    local channelOptions

    if type(entry) == "table" then
        text = trim(entry.text or "")
        local ok, err, _, normalizedOptions = self:ValidateChannelOptions({
            target    = entry.target or "GUILD",
            recipient = entry.recipient,
        })
        if not ok then
            return false, err or "Queued message has an invalid target channel."
        end
        channelOptions = normalizedOptions
        target    = normalizedOptions.target
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
        text          = text,
        target        = target,
        recipient     = recipient,
        channelOptions = channelOptions,
    }
end

function I:ValidateQueue()
    local guild = getGuild()
    local queue = guild and guild.messageQueue or {}
    if type(queue) ~= "table" then
        return {
            ok = false, total = 1, validCount = 0, invalidCount = 1,
            invalidEntries = { { index = 1, error = "Message queue storage is malformed." } },
        }
    end

    local invalid    = {}
    local validCount = 0
    for index, entry in ipairs(queue) do
        local ok, err = self:ValidateQueueEntry(entry)
        if ok then
            validCount = validCount + 1
        else
            invalid[#invalid + 1] = { index = index, error = err or "Queued message is malformed." }
        end
    end

    return {
        ok           = #invalid == 0,
        total        = #queue,
        validCount   = validCount,
        invalidCount = #invalid,
        invalidEntries = invalid,
    }
end

function I:RepairQueue(options)
    local report = self:ValidateQueue()
    if not options or options.removeInvalid ~= true then
        return report
    end

    local guild = getGuild()
    if not guild then
        report.removedCount = 0
        return report
    end
    if type(guild.messageQueue) ~= "table" then
        guild.messageQueue = {}
        self:StopAutoSend("queue-repaired")
        report.removedCount   = report.invalidCount or 1
        report.remainingCount = 0
        return report
    end

    local repaired = {}
    local removed  = 0
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
    report.removedCount   = removed
    report.remainingCount = #repaired
    return report
end

function I:QueueChunks(chunks, options)
    if not self:IsEnabled() then
        return false, "Messaging module is disabled."
    end

    local queue, queueErr = queueStorage()
    if not queue then return false, queueErr end

    options = options or {}
    local ok, err, _, channelOptions = self:ValidateChannelOptions(options)
    if not ok then return false, err end

    local target    = channelOptions.target
    local recipient = channelOptions.recipient
    local pending   = {}
    for _, chunk in ipairs(chunks or {}) do
        local text = type(chunk) == "table" and chunk.text or chunk
        text = trim(text)
        if text ~= "" then
            local parts = { text }
            if target == "GUILD" and #text > 255 then
                parts = self:SplitMessage(text, 255)
            end
            for _, part in ipairs(parts) do
                part = trim(part)
                if part ~= "" then
                    pending[#pending + 1] = {
                        text            = part,
                        target          = target,
                        recipient       = recipient,
                        sourceMessageId = options.sourceMessageId,
                        queuedAt        = now(),
                    }
                end
            end
        end
    end

    if #pending == 0 then return false, "Nothing to queue." end

    local maxQueueSize = self:GetMaxQueueSize()
    if (#queue + #pending) > maxQueueSize then
        return false, string.format("Queue limit reached (%d). Clear or send queued chunks first.", maxQueueSize)
    end

    local batchId = tostring(now()) .. "-" .. tostring(#queue + 1)
    for index, entry in ipairs(pending) do
        entry.batchId    = batchId
        entry.batchIndex = index
        entry.chunkCount = #pending
    end
    for _, entry in ipairs(pending) do
        queue[#queue + 1] = entry
    end
    return true
end

-- Guild chat has one outbound path: split once, enqueue ordered chunks, then let
-- ProcessQueue send each chunk through SendGuildChunk with timer spacing.
function I:QueueGuildMessage(message, options)
    if not self:IsEnabled() then
        return false, "Messaging module is disabled."
    end

    message = trim(message)
    if message == "" then return false, "Guild message is empty." end

    options = options or {}
    local resolved = options.resolvePlaceholders ~= false and self:ResolvePlaceholders(message, options) or message
    local parts = self:SplitMessage(resolved, 255)
    local ok, err = self:QueueChunks(parts, {
        target          = "GUILD",
        sourceMessageId = options.sourceMessageId,
    })
    if not ok then return false, err end

    if options.autoSend ~= false then
        self:ProcessQueue()
    end

    return true, nil, { chunkCount = #parts, chunks = parts }
end

function I:DebugSplitMessage(message, maxLength)
    local chunks = self:SplitMessage(message, maxLength or 255)
    local out = GC.Print and function(...)
        GC:Print("Messages:", ...)
    end or print

    out(string.format("split test: %d chunk%s", #chunks, #chunks == 1 and "" or "s"))
    for index, chunk in ipairs(chunks) do
        out(string.format("[%d] len=%d %s", index, #chunk, chunk))
    end
    return chunks
end

function I:BuildMessagePreview(messageId, options)
    local message = self:GetMessage(messageId)
    if not message then return nil, "Message not found." end

    options = options or {}
    local preview = self:BuildPreview(message.body, options)
    return {
        message             = message,
        preview             = preview,
        resolvedBody        = preview.resolvedBody or (preview[1] and preview[1].resolvedText) or self:ResolvePlaceholders(message.body, options),
        placeholderWarnings = copyTable(preview.placeholderWarnings or {}),
    }
end

function I:DirectSendMessage(messageId, options)
    local payload, err = self:BuildMessagePreview(messageId, options)
    if not payload then return false, err end

    local ok, queueErr = self:QueueChunks(payload.preview, {
        target          = options and options.target or "GUILD",
        recipient       = options and options.recipient or nil,
        sourceMessageId = messageId,
    })
    if not ok then return false, queueErr end

    local autoStarted = false
    if self:GetAutomationEnabled() then
        local started = self:StartAutoSend()
        autoStarted = started == true or self:IsAutoSending()
    end

    return true, nil, {
        preview      = payload.preview,
        resolvedBody = payload.resolvedBody,
        autoStarted  = autoStarted,
    }
end

function I:QueueMessagePreview(messageId, options)
    local payload, err = self:BuildMessagePreview(messageId, options)
    if not payload then return false, err end

    return self:QueueChunks(payload.preview, {
        target          = options and options.target or "GUILD",
        recipient       = options and options.recipient or nil,
        sourceMessageId = messageId,
    })
end

function I:LoadChunkIntoChat(text, target, recipient)
    text = trim(text)
    if text == "" then return false, "Chunk is empty." end

    local options
    if type(target) == "table" then
        options = target
    else
        options = { target = target or "GUILD", recipient = recipient }
    end

    local ok, err, channel, channelOptions = self:ValidateChannelOptions(options)
    if not ok then return false, err end

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

function I:SendNextQueuedMessage()
    if not self:IsEnabled() then
        self:StopAutoSend("disabled")
        return false, "Messaging module is disabled."
    end

    local guild = getGuild()
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
    local COOLDOWN    = H.SEND_COOLDOWN_SECONDS
    if self._lastSendAt and currentTime > 0 and (currentTime - self._lastSendAt) < COOLDOWN then
        return false, string.format("Please wait %.1f seconds before sending again.", self:GetSendCooldownRemaining())
    end

    local nextEntry = guild.messageQueue[1]
    local valid, validationErr, normalized = self:ValidateQueueEntry(nextEntry)
    if not valid then
        return false, (validationErr or "Queued message is malformed.") .. " Clear Queue or repair the queue."
    end

    local ok, err
    if normalized.target == "GUILD" then
        ok, err = self:SendGuildChunk(normalized.text)
    else
        ok, err = pcall(SendChatMessage, normalized.text, normalized.target, nil, normalized.recipient)
    end
    if not ok then
        return false, tostring(err or "Unable to send queued message.")
    end

    table.remove(guild.messageQueue, 1)
    self._lastSendAt = currentTime > 0 and currentTime or nil
    if type(nextEntry) == "table" and nextEntry.sourceMessageId and (tonumber(nextEntry.batchIndex) or 1) == 1 then
        self:RecordMessageUsage(nextEntry.sourceMessageId, {
            target     = normalized.target,
            recipient  = normalized.recipient,
            sentAt     = now(),
            chunkCount = tonumber(nextEntry.chunkCount) or 1,
        })
    end
    return true
end

function I:SendGuildChunk(chunk)
    chunk = trim(chunk)
    if chunk == "" then return false, "Guild message chunk is empty." end
    if #chunk > 255 then return false, "Guild message chunk exceeds 255 characters." end
    if not SendChatMessage then return false, "SendChatMessage is unavailable." end

    local ok, err = pcall(SendChatMessage, chunk, "GUILD")
    if not ok then return false, tostring(err) end
    return true
end

function I:ProcessQueue()
    if self._processingQueue then return true end
    self._processingQueue = true

    local function step()
        local queue = self:GetQueue()
        if #queue == 0 then
            self._processingQueue = false
            self:StopAutoSend("complete")
            return
        end

        local ok, err = self:SendNextQueuedMessage()
        if not ok then
            if err and err:find("Please wait", 1, true) and C_Timer and C_Timer.After then
                local delay = self.GetAutoSendDelaySeconds and self:GetAutoSendDelaySeconds() or GUILD_MESSAGE_DELAY
                C_Timer.After(math.max(delay, H.SEND_COOLDOWN_SECONDS or 1.2), step)
                return
            end
            self._processingQueue = false
            self:StopAutoSend("error")
            if GC.Debug then
                GC:Debug("Messages:", err or "Unable to send queued guild message.")
            elseif GC.Print then
                GC:Print(err or "Unable to send queued guild message.")
            end
            return
        end

        if self:GetQueueSize() == 0 then
            self._processingQueue = false
            self:StopAutoSend("complete")
            return
        end

        if C_Timer and C_Timer.After then
            local delay = self.GetAutoSendDelaySeconds and self:GetAutoSendDelaySeconds() or GUILD_MESSAGE_DELAY
            C_Timer.After(delay, step)
        else
            self._processingQueue = false
        end
    end

    step()
    return true
end

function I:ClearQueue()
    local guild = getGuild()
    if not guild then return false end
    guild.messageQueue = {}
    self:StopAutoSend("cleared")
    return true
end

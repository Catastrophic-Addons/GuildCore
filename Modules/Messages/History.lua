local addonName, ns = ...
local GC = ns.GuildCore

local H = ns.MessagesHelpers
local I = ns.MessagesImpl

local MESSAGE_HISTORY_LIMIT = H.MESSAGE_HISTORY_LIMIT
local trim            = H.trim
local now             = H.now
local getGuild        = H.getGuild
local currentPlayerName = H.currentPlayerName

function I:GetHistory()
    local guild = getGuild()
    if not guild then return nil end

    if type(guild.messageHistory) ~= "table" then
        guild.messageHistory = {}
    end
    while #guild.messageHistory > MESSAGE_HISTORY_LIMIT do
        table.remove(guild.messageHistory, 1)
    end
    return guild.messageHistory
end

function I:TrimHistory()
    local history = self:GetHistory()
    if not history then return false end

    while #history > MESSAGE_HISTORY_LIMIT do
        table.remove(history, 1)
    end
    return true
end

function I:AddHistoryEntry(entry)
    local history = self:GetHistory()
    if not history then return false end

    entry = entry or {}
    history[#history + 1] = {
        templateId = entry.templateId,
        title      = entry.title,
        -- NormalizeTargetChannel is added by Service.lua, resolved at call time
        target     = self:NormalizeTargetChannel(entry.target or "GUILD"),
        recipient  = trim(entry.recipient) ~= "" and trim(entry.recipient) or nil,
        sentBy     = entry.sentBy or currentPlayerName() or "Unknown",
        sentAt     = tonumber(entry.sentAt) or now(),
        chunkCount = math.max(1, math.floor(tonumber(entry.chunkCount) or 1)),
    }

    self:TrimHistory()
    return true
end

function I:GetMessageHistory()
    return self:GetHistory()
end

function I:AppendMessageHistory(entry)
    return self:AddHistoryEntry(entry)
end

function I:ListHistory(limit)
    local history = self:GetHistory() or {}
    local rows = {}
    limit = math.max(1, math.floor(tonumber(limit) or 8))

    for index = #history, 1, -1 do
        local entry = history[index]
        if type(entry) == "table" then
            rows[#rows + 1] = {
                key        = tostring(index),
                templateId = entry.templateId,
                title      = entry.title,
                target     = entry.target or "GUILD",
                recipient  = entry.recipient,
                sentBy     = entry.sentBy,
                sentAt     = entry.sentAt,
                sentLabel  = entry.sentAt and date("%m-%d %H:%M", entry.sentAt) or "",
                chunkCount = tonumber(entry.chunkCount) or 1,
            }
            if #rows >= limit then break end
        end
    end

    return rows
end

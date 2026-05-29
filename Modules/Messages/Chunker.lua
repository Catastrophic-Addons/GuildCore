local addonName, ns = ...
local GC = ns.GuildCore

local Chunker = {}
Chunker.__index = Chunker

Chunker.MAX_MESSAGE_LENGTH = 255

local function trim(value)
    -- Safe fallback if GC.Utils is not yet loaded
    if GC.Utils and GC.Utils.Trim then
        return GC.Utils.Trim(value or "")
    end
    value = tostring(value or "")
    return (value:match("^%s*(.-)%s*$"))
end

local function normalizeText(text)
    text = tostring(text or "")
    text = text:gsub("\r\n", "\n")
    text = text:gsub("\r", "\n")
    return text
end

local function findBestBreak(text, limit)
    local punctuation = { ".", "!", "?", ";", "," }
    for _, mark in ipairs(punctuation) do
        for i = limit, 1, -1 do
            if text:sub(i, i) == mark then
                local nextChar = text:sub(i + 1, i + 1)
                if nextChar == "" or nextChar:match("%s") then
                    return i
                end
            end
        end
    end

    for i = limit, 1, -1 do
        if text:sub(i, i):match("%s") then
            return i
        end
    end

    return limit
end

local function splitParagraph(text, limit, chunks)
    text = trim(text)
    while #text > 0 do
        if #text <= limit then
            chunks[#chunks + 1] = text
            return
        end

        local breakAt = findBestBreak(text, limit)
        local piece = trim(text:sub(1, breakAt))
        if piece == "" then
            piece = text:sub(1, limit)
            breakAt = limit
        end

        chunks[#chunks + 1] = piece
        text = trim(text:sub(breakAt + 1))
    end
end

local function splitRaw(text, limit)
    local chunks = {}
    text = normalizeText(text)
    limit = math.max(20, math.min(Chunker.MAX_MESSAGE_LENGTH, tonumber(limit) or Chunker.MAX_MESSAGE_LENGTH))

    for paragraph in (text .. "\n"):gmatch("([^\n]*)\n") do
        paragraph = trim(paragraph)
        if paragraph ~= "" then
            splitParagraph(paragraph, limit, chunks)
        end
    end

    return chunks
end

function Chunker:Split(text, options)
    options = options or {}
    local limit = math.max(20, math.min(self.MAX_MESSAGE_LENGTH, tonumber(options.limit) or self.MAX_MESSAGE_LENGTH))
    local normalized = normalizeText(text)
    if trim(normalized) == "" then
        return {}
    end
    return splitRaw(normalized, limit)
end

function Chunker:Preview(text, options)
    local chunks = self:Split(text, options)
    local preview = {}
    for index, chunk in ipairs(chunks) do
        preview[#preview + 1] = {
            key = tostring(index),
            index = index,
            text = chunk,
            length = #chunk,
        }
    end
    return preview
end

GC:RegisterService("MessageChunker", setmetatable({}, Chunker))

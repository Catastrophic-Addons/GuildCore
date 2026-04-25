local addonName, ns = ...
local GC = ns.GuildCore

local Chunker = {}
Chunker.__index = Chunker

local function trim(value)
    return GC.Utils.Trim(value or "")
end

local function normalizeText(text)
    text = tostring(text or "")
    text = text:gsub("\r\n", "\n")
    text = text:gsub("\r", "\n")
    return text
end

local function splitRaw(text, limit)
    local chunks = {}
    text = normalizeText(text)
    limit = math.max(20, math.min(255, tonumber(limit) or 240))

    while #text > 0 do
        if #text <= limit then
            chunks[#chunks + 1] = trim(text)
            break
        end

        local breakAt

        for i = limit - 1, 2, -1 do
            if text:sub(i - 1, i) == "\n\n" then
                breakAt = i
                break
            end
        end

        if not breakAt then
            for i = limit - 1, 1, -1 do
                local current = text:sub(i, i)
                local nextChar = text:sub(i + 1, i + 1)
                if current:match("[%.%!%?;:]") and nextChar:match("[%s\n]") then
                    breakAt = i
                    break
                end
            end
        end

        if not breakAt then
            for i = limit, 1, -1 do
                if text:sub(i, i) == "\n" then
                    breakAt = i
                    break
                end
            end
        end

        if not breakAt then
            for i = limit, 1, -1 do
                if text:sub(i, i):match("%s") then
                    breakAt = i
                    break
                end
            end
        end

        if not breakAt or breakAt < 1 then
            breakAt = limit
        end

        local piece = trim(text:sub(1, breakAt))
        if piece == "" then
            piece = text:sub(1, limit)
            breakAt = limit
        end

        chunks[#chunks + 1] = piece
        text = text:sub(breakAt + 1):gsub("^%s+", "")
    end

    if #chunks == 0 then
        chunks[1] = ""
    end

    return chunks
end

function Chunker:Split(text, options)
    options = options or {}
    local limit = math.max(20, math.min(255, tonumber(options.limit) or 240))
    local includeNumbers = options.includeNumbers ~= false
    local normalized = normalizeText(text)
    if trim(normalized) == "" then
        return {}
    end
    local raw = splitRaw(normalized, limit)

    if not includeNumbers or #raw <= 1 then
        return raw
    end

    local count = #raw
    for _ = 1, 3 do
        local suffix = string.format("(%d/%d) ", count, count)
        local reducedLimit = math.max(20, limit - #suffix)
        local adjusted = splitRaw(normalized, reducedLimit)
        if #adjusted == count then
            raw = adjusted
            break
        end
        raw = adjusted
        count = #adjusted
    end

    local numbered = {}
    count = #raw
    for index, chunk in ipairs(raw) do
        numbered[index] = string.format("(%d/%d) %s", index, count, chunk)
    end

    return numbered
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

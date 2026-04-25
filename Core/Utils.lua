-- /GuildCore/Core/Utils.lua
local addonName, ns = ...
local GC = ns.GuildCore

GC.Utils = {}

function GC.Utils.Trim(value)
    return (value or ""):match("^%s*(.-)%s*$")
end

function GC.Utils.LowerTrim(value)
    return GC.Utils.Trim(value):lower()
end

function GC.Utils.DeepCopy(source)
    if type(source) ~= "table" then
        return source
    end

    local copy = {}
    for key, value in pairs(source) do
        copy[key] = GC.Utils.DeepCopy(value)
    end
    return copy
end

function GC.Utils.MergeDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            target[key] = target[key] or {}
            GC.Utils.MergeDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
end

function GC.Utils.Now()
    return time()
end

function GC.Utils.NormalizePlayerKey(name, realm)
    if not name or name == "" then
        return nil
    end

    realm = realm or GetRealmName() or "UnknownRealm"
    realm = realm:gsub("%s+", "")
    return string.format("%s-%s", name, realm)
end

function GC.Utils.SplitGuildName(fullName)
    if not fullName then
        return nil, nil
    end

    local name, realm = strsplit("-", fullName)
    return name, realm
end

function GC.Utils.NormalizeRankName(rankName)
    return GC.Utils.LowerTrim(rankName):gsub("%s+", " ")
end

function GC.Utils.IsTrackedRank(rankName)
    local normalized = GC.Utils.NormalizeRankName(rankName)
    return normalized == "member" or normalized == "initiate"
end

function GC.Utils.IsTrackedRankIndex(rankIndex, totalRanks)
    rankIndex = tonumber(rankIndex)
    totalRanks = tonumber(totalRanks)
    if not rankIndex or not totalRanks or totalRanks <= 0 then
        return false
    end

    -- WoW rankIndex is 0 = highest. Fallback to the lowest two ranks when
    -- the guild uses custom rank names instead of literal "Member"/"Initiate".
    return rankIndex >= math.max(0, totalRanks - 2)
end

local function buildTimestamp(year, month, day)
    year = tonumber(year)
    month = tonumber(month)
    day = tonumber(day)
    if not year or not month or not day then
        return nil
    end
    if month < 1 or month > 12 or day < 1 or day > 31 then
        return nil
    end
    return time({ year = year, month = month, day = day, hour = 12, min = 0, sec = 0 })
end

function GC.Utils.ParseFlexibleDate(text)
    text = GC.Utils.Trim(text)
    if text == "" then
        return nil
    end

    local year, month, day = text:match("(%d%d%d%d)[%./%-](%d%d?)[%./%-](%d%d?)")
    if year then
        return buildTimestamp(year, month, day)
    end

    month, day, year = text:match("(%d%d?)[/%.-](%d%d?)[/%.-](%d%d%d%d)")
    if year then
        return buildTimestamp(year, month, day)
    end

    return nil
end

local function parseDiscordFlag(noteLower)
    if noteLower:find("discord%s*[:=]%s*(no|false|n)") or noteLower:find("discord%s*unverified") then
        return false
    end
    if noteLower:find("discord%s*[:=]%s*(yes|true|y|ok)") or noteLower:find("discord%s*verified") or noteLower:find("verified%s*discord") then
        return true
    end
    return nil
end

local function parseDiscordName(note)
    local candidates = {
        note:match("[Dd]iscord%s*[:=]%s*([^,;|]+)"),
        note:match("[Dd][Cc]%s*[:=]%s*([^,;|]+)"),
        note:match("@([%w%._%-]+)"),
    }

    for _, candidate in ipairs(candidates) do
        local value = GC.Utils.Trim(candidate)
        if value ~= "" then
            return value
        end
    end

    return nil
end

function GC.Utils.ParseOfficerNote(note)
    note = GC.Utils.Trim(note)
    if note == "" then
        return {
            joinDate = nil,
            discordVerified = nil,
            discordName = nil,
        }
    end

    local noteLower = note:lower()
    local joinDate = GC.Utils.ParseFlexibleDate(note)
    local discordName = parseDiscordName(note)
    local discordVerified = parseDiscordFlag(noteLower)

    if discordVerified == nil and discordName then
        discordVerified = true
    end

    return {
        joinDate = joinDate,
        discordVerified = discordVerified,
        discordName = discordName,
    }
end

function GC.Utils.ArrayContains(values, needle)
    if type(values) ~= "table" then
        return false
    end

    for _, value in ipairs(values) do
        if value == needle then
            return true
        end
    end

    return false
end

function GC.Utils.RemoveArrayValue(values, needle)
    if type(values) ~= "table" then
        return false
    end

    for index = #values, 1, -1 do
        if values[index] == needle then
            table.remove(values, index)
            return true
        end
    end

    return false
end

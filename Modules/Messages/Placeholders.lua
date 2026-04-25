local addonName, ns = ...
local GC = ns.GuildCore

local Placeholders = {}
Placeholders.__index = Placeholders

local function trim(value)
    return GC.Utils.Trim(value or "")
end

local function getServerTimestamp()
    if GetServerTime then
        local serverTime = GetServerTime()
        if type(serverTime) == "number" and serverTime > 0 then
            return serverTime
        end
    end

    return time()
end

local function stripChatDecorators(text)
    text = tostring(text or "")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    text = text:gsub("|H.-|h(.-)|h", "%1")
    return trim(text)
end

local function makeLocalizedPattern(formatString)
    if type(formatString) ~= "string" or formatString == "" then
        return nil
    end

    local escaped = formatString:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    escaped = escaped:gsub("%%%%s", "(.+)")
    return "^" .. escaped .. "$"
end

local GUILD_JOIN_PATTERNS = {
    makeLocalizedPattern(ERR_GUILD_JOIN_S),
    "^(.+) has joined the guild%.$",
}

local function formatTimeLeft(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)

    if hours > 0 and minutes > 0 then
        return string.format("%dh %dm", hours, minutes)
    end
    if hours > 0 then
        return string.format("%dh", hours)
    end
    return string.format("%dm", minutes)
end

function Placeholders:CaptureSystemMessage(message)
    message = stripChatDecorators(message)
    if message == "" then
        return nil
    end

    for _, pattern in ipairs(GUILD_JOIN_PATTERNS) do
        if pattern then
            local joinedName = trim(message:match(pattern))
            if joinedName ~= "" then
                return joinedName
            end
        end
    end

    return nil
end

function Placeholders:GetTimeLeft(hour, minute)
    hour = tonumber(hour) or 18
    minute = tonumber(minute) or 0
    hour = math.max(0, math.min(23, hour))
    minute = math.max(0, math.min(59, minute))

    local currentTimestamp = getServerTimestamp()
    local current = date("*t", currentTimestamp)
    if not current then
        return "0m"
    end

    local target = {
        year = current.year,
        month = current.month,
        day = current.day,
        hour = hour,
        min = minute,
        sec = 0,
    }
    local targetTimestamp = time(target)
    if targetTimestamp <= currentTimestamp then
        target.day = target.day + 1
        targetTimestamp = time(target)
    end

    return formatTimeLeft(targetTimestamp - currentTimestamp)
end

function Placeholders:BuildContext(options)
    options = options or {}
    local playerName = UnitName and UnitName("player") or nil
    local guildName = GetGuildInfo and GetGuildInfo("player") or nil
    local realmName = GetRealmName and GetRealmName() or nil
    local targetName = trim(options.targetName)
    local newMemberName = trim(options.newMemberName)

    if targetName == "" then
        targetName = "member"
    end
    if newMemberName == "" then
        newMemberName = "new member"
    end

    return {
        ["@player.name"] = trim(playerName) ~= "" and trim(playerName) or "player",
        ["@guild.name"] = trim(guildName) ~= "" and trim(guildName) or "guild",
        ["@realm.name"] = trim(realmName) ~= "" and trim(realmName) or "realm",
        ["@target.name"] = targetName,
        ["@new.member"] = newMemberName,
        ["@time.left"] = self:GetTimeLeft(options.dailyTargetHour, options.dailyTargetMinute),
    }
end

function Placeholders:ResolveText(text, options)
    text = tostring(text or "")
    if text == "" then
        return ""
    end

    local values = self:BuildContext(options)
    return (text:gsub("@[%a_]+[%w_%.]*", function(token)
        return values[token] or token
    end))
end

GC:RegisterService("MessagePlaceholders", setmetatable({}, Placeholders))

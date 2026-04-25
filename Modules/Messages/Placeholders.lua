local addonName, ns = ...
local GC = ns.GuildCore

local Placeholders = {}
Placeholders.__index = Placeholders

local function trim(value)
    return GC.Utils.Trim(value or "")
end

local function firstNonEmpty(...)
    for index = 1, select("#", ...) do
        local value = trim(select(index, ...))
        if value ~= "" then
            return value
        end
    end
    return nil
end

local function optionalText(value)
    return type(value) == "string" and value or nil
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

local FALLBACKS = {
    ["@player.name"] = "player",
    ["@guild.name"] = "your guild",
    ["@realm.name"] = "your realm",
    ["@target.name"] = "member",
    ["@new.member"] = "new member",
    ["@rank.name"] = "unknown rank",
    ["@discord.name"] = "Unknown Discord",
    ["@character.name"] = "character",
    ["@main.name"] = "main character",
    ["@team.name"] = "team",
    ["@role.name"] = "role",
    ["@event.name"] = "event",
    ["@event.date"] = "event date",
    ["@event.time"] = "event time",
}

local PLACEHOLDER_DEFS = {
    { token = "@player.name", group = "Player", label = "Player Name", description = "Your current character name." },
    { token = "@guild.name", group = "Guild", label = "Guild Name", description = "Current guild name." },
    { token = "@realm.name", group = "Guild", label = "Realm Name", description = "Current realm name." },
    { token = "@target.name", group = "Target", label = "Target Name", description = "Selected target/member name." },
    { token = "@new.member", group = "Target", label = "New Member", description = "Most recently detected guild join." },
    { token = "@rank.name", group = "Target", label = "Rank Name", description = "Target member rank when roster data is available." },
    { token = "@discord.name", group = "Target", label = "Discord Name", description = "Target Discord name when stored in officer data." },
    { token = "@character.name", group = "Player", label = "Character Name", description = "Current in-game character name." },
    { token = "@main.name", group = "Target", label = "Main Name", description = "Target member main character when stored." },
    { token = "@team.name", group = "Target", label = "Team Name", description = "Team name when supplied by a future workflow." },
    { token = "@role.name", group = "Target", label = "Role Name", description = "Target role/rank when stored or supplied." },
    { token = "@event.name", group = "Event", label = "Event Name", description = "Future event name; resolves only when supplied.", available = false },
    { token = "@event.date", group = "Event", label = "Event Date", description = "Future event date; resolves only when supplied.", available = false },
    { token = "@event.time", group = "Event", label = "Event Time", description = "Future event time; resolves only when supplied.", available = false },
    { token = "@date.today", group = "Time", label = "Today", description = "Current server date." },
    { token = "@time.now", group = "Time", label = "Current Time", description = "Current server time." },
    { token = "@time.left", group = "Time", label = "Time Left", description = "Time remaining until the configured daily target time." },
}

local PLACEHOLDER_INDEX = {}
for _, def in ipairs(PLACEHOLDER_DEFS) do
    PLACEHOLDER_INDEX[def.token] = def
end

local function addUnique(list, seen, value)
    value = trim(value)
    if value ~= "" and not seen[value] then
        list[#list + 1] = value
        seen[value] = true
    end
end

local function copyDef(def)
    return {
        key = def.token,
        token = def.token,
        group = def.group,
        label = def.label,
        description = def.description,
        available = def.available ~= false,
    }
end

local function findPlayerByName(name)
    name = trim(name)
    if name == "" then
        return nil
    end

    local guildService = GC.Services and GC.Services.GuildService
    if guildService and guildService.ResolvePlayerKey and guildService.GetPlayerByKey then
        local key = guildService:ResolvePlayerKey(name)
        local player = key and guildService:GetPlayerByKey(key) or nil
        if player then
            return player
        end
    end

    local dataStore = GC.Services and GC.Services.DataStore
    local players = dataStore and dataStore.GetPlayers and dataStore:GetPlayers() or nil
    if type(players) ~= "table" then
        return nil
    end

    local normalized = GC.Utils.NormalizePlayerKey and GC.Utils.NormalizePlayerKey(name) or nil
    if normalized and players[normalized] then
        return players[normalized]
    end

    local lowerName = name:lower()
    for _, player in pairs(players) do
        if type(player) == "table" then
            if trim(player.name):lower() == lowerName or trim(player.key):lower() == lowerName then
                return player
            end
        end
    end

    return nil
end

local function buildRosterContext(options)
    local targetName = firstNonEmpty(options.targetName, options.recipient, options.newMemberName)
    local player = findPlayerByName(targetName)
    if not player then
        return {}
    end

    local officerData = player.officerData or {}
    local mainName = firstNonEmpty(optionalText(player.mainName), optionalText(player.main))
    if mainName and mainName:find("-") then
        mainName = mainName:match("^([^%-]+)") or mainName
    end

    return {
        targetName = firstNonEmpty(player.name, targetName),
        rankName = firstNonEmpty(player.rankName),
        roleName = firstNonEmpty(optionalText(player.roleName), optionalText(player.role), optionalText(player.rankName)),
        mainName = firstNonEmpty(mainName),
        teamName = firstNonEmpty(optionalText(player.teamName), optionalText(player.team)),
        discordName = firstNonEmpty(officerData.discordName),
        discordVerified = officerData.discordVerified,
        joinDate = player.joinedAt or officerData.joinDate,
    }
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
    local serverTimestamp = getServerTimestamp()
    local roster = buildRosterContext(options)
    local targetName = firstNonEmpty(options.targetName, roster.targetName)
    local newMemberName = firstNonEmpty(options.newMemberName)

    return {
        ["@player.name"] = firstNonEmpty(playerName) or FALLBACKS["@player.name"],
        ["@guild.name"] = firstNonEmpty(guildName) or FALLBACKS["@guild.name"],
        ["@realm.name"] = firstNonEmpty(realmName) or FALLBACKS["@realm.name"],
        ["@target.name"] = targetName or FALLBACKS["@target.name"],
        ["@new.member"] = newMemberName or FALLBACKS["@new.member"],
        ["@rank.name"] = firstNonEmpty(options.rankName, roster.rankName) or FALLBACKS["@rank.name"],
        ["@discord.name"] = firstNonEmpty(options.discordName, roster.discordName) or FALLBACKS["@discord.name"],
        ["@character.name"] = firstNonEmpty(options.characterName, playerName) or FALLBACKS["@character.name"],
        ["@main.name"] = firstNonEmpty(options.mainName, roster.mainName) or FALLBACKS["@main.name"],
        ["@team.name"] = firstNonEmpty(options.teamName, roster.teamName) or FALLBACKS["@team.name"],
        ["@role.name"] = firstNonEmpty(options.roleName, roster.roleName, options.rankName, roster.rankName) or FALLBACKS["@role.name"],
        ["@event.name"] = firstNonEmpty(options.eventName) or FALLBACKS["@event.name"],
        ["@event.date"] = firstNonEmpty(options.eventDate) or FALLBACKS["@event.date"],
        ["@event.time"] = firstNonEmpty(options.eventTime) or FALLBACKS["@event.time"],
        ["@date.today"] = date("%Y-%m-%d", serverTimestamp),
        ["@time.now"] = date("%H:%M", serverTimestamp),
        ["@time.left"] = self:GetTimeLeft(options.dailyTargetHour, options.dailyTargetMinute),
    }
end

function Placeholders:FindUnknownPlaceholders(text)
    text = tostring(text or "")
    local unknown = {}
    local seen = {}
    for token in text:gmatch("@[%a_]+[%w_%.]*") do
        if not PLACEHOLDER_INDEX[token] then
            addUnique(unknown, seen, token)
        end
    end
    return unknown
end

function Placeholders:GetAvailablePlaceholders()
    local rows = {}
    for _, def in ipairs(PLACEHOLDER_DEFS) do
        if def.available ~= false then
            rows[#rows + 1] = copyDef(def)
        end
    end
    return rows
end

function Placeholders:Resolve(text, options)
    text = tostring(text or "")
    local warnings = {}
    local fallbackUsed = false
    local warningSeen = {}
    local values = self:BuildContext(options)

    local resolved = text:gsub("@[%a_]+[%w_%.]*", function(token)
        if PLACEHOLDER_INDEX[token] then
            local value = values[token]
            if value == FALLBACKS[token] then
                fallbackUsed = true
            end
            return value or FALLBACKS[token] or token
        end

        addUnique(warnings, warningSeen, "Unknown placeholder: " .. token)
        return token
    end)

    if fallbackUsed then
        addUnique(warnings, warningSeen, "Some placeholders used fallback values")
    end

    return {
        text = resolved,
        warnings = warnings,
        fallbackUsed = fallbackUsed,
        unknown = self:FindUnknownPlaceholders(text),
    }
end

function Placeholders:ResolveText(text, options)
    local result = self:Resolve(text, options)
    return result.text or ""
end

GC:RegisterService("MessagePlaceholders", setmetatable({}, Placeholders))

-- Modules/WelcomeBatch/Service.lua
-- Batches newly joined guild members into one warm guild chat welcome.
local addonName, ns = ...
local GC = ns.GuildCore

GC.Services = GC.Services or {}
GC.Services.WelcomeBatch = {}

local WB = GC.Services.WelcomeBatch

local RECENT_TTL_SECONDS = 7 * 24 * 60 * 60
local MAX_GUILD_MESSAGE_LENGTH = 255

local function trim(value)
    return GC.Utils and GC.Utils.Trim and GC.Utils.Trim(value or "") or tostring(value or ""):match("^%s*(.-)%s*$")
end

local function now()
    return (GetServerTime and GetServerTime()) or time()
end

local function settings()
    return GC.DB and GC.DB.GetSettings and GC.DB:GetSettings() or {}
end

local function guildState()
    local guild = GC.DB and GC.DB.GetGuild and GC.DB:GetGuild() or nil
    if not guild then return nil end

    guild.welcomeBatch = guild.welcomeBatch or {}
    guild.welcomeBatch.recentWelcomed = guild.welcomeBatch.recentWelcomed or {}
    return guild.welcomeBatch
end

local function normalizeName(name)
    name = trim(name)
    if name == "" then return nil end

    if GC.API and GC.API.NormalizePlayerName then
        return GC.API.NormalizePlayerName(name)
    end
    return GC.Utils and GC.Utils.NormalizePlayerKey and GC.Utils.NormalizePlayerKey(name) or name
end

local function displayName(name)
    name = trim(name)
    local shortName = name:match("^([^%-]+)%-") or name
    return shortName
end

local function stripChatDecorators(text)
    text = tostring(text or "")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    text = text:gsub("|H.-|h(.-)|h", "%1")
    return trim(text)
end

local function localizedPattern(formatString)
    if type(formatString) ~= "string" or formatString == "" then return nil end

    local escaped = formatString:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    escaped = escaped:gsub("%%%%s", "(.+)")
    return "^" .. escaped .. "$"
end

local JOIN_PATTERNS = {
    localizedPattern(ERR_GUILD_JOIN_S),
    "^(.+) has joined the guild%.$",
}

local function formatNames(names)
    if #names == 0 then return "" end
    if #names == 1 then return names[1] end
    if #names == 2 then return names[1] .. " and " .. names[2] end

    local parts = {}
    for index = 1, #names - 1 do
        parts[#parts + 1] = names[index]
    end
    return table.concat(parts, ", ") .. ", and " .. names[#names]
end

local function formatNamesWithOverflow(names)
    if #names == 0 then return "" end
    if #names == 1 then return names[1] .. " and others" end
    return table.concat(names, ", ") .. ", and others"
end

local function debugLog(...)
    if GC.Debug then
        GC:Debug("WelcomeBatch:", ...)
    end
end

-- Establish runtime state. Existing roster members are used as a baseline, so
-- login and /reload do not accidentally welcome the whole guild.
function WB:Initialize()
    self.knownRoster = self.knownRoster or {}
    self.queue = self.queue or {}
    self.queuedKeys = self.queuedKeys or {}
    self.timer = nil
    self.hasBaseline = false
    self:PruneRecent()
end

function WB:IsEnabled()
    return settings().enableWelcomeBatch == true
end

function WB:GetWindowSeconds()
    return math.max(15, math.floor(tonumber(settings().welcomeBatchWindowSeconds) or 180))
end

-- Keep only recent sent keys so the saved duplicate guard stays small.
function WB:PruneRecent()
    local state = guildState()
    if not state or type(state.recentWelcomed) ~= "table" then return end

    local cutoff = now() - RECENT_TTL_SECONDS
    for key, timestamp in pairs(state.recentWelcomed) do
        if (tonumber(timestamp) or 0) < cutoff then
            state.recentWelcomed[key] = nil
        end
    end
end

function WB:WasRecentlyWelcomed(key)
    local state = guildState()
    return state and state.recentWelcomed and state.recentWelcomed[key] ~= nil
end

function WB:MarkWelcomed(entry)
    local state = guildState()
    if not state or not entry or not entry.key then return end

    state.recentWelcomed[entry.key] = now()
    state.lastSentAt = now()
end

-- Read WoW's current guild roster without forcing a fresh GuildRoster() call.
function WB:BuildRosterSnapshot()
    local roster = {}
    local total = GC.API and GC.API.GetNumGuildMembers and GC.API.GetNumGuildMembers() or (GetNumGuildMembers and GetNumGuildMembers()) or 0

    for index = 1, tonumber(total) or 0 do
        local fullName = GC.API and GC.API.GetGuildRosterInfo and GC.API.GetGuildRosterInfo(index) or nil
        local key = normalizeName(fullName)
        if key then
            roster[key] = {
                key = key,
                name = fullName,
            }
        end
    end

    return roster
end

-- Roster diff is the reliable fallback when direct system text varies by locale
-- or arrives before other modules have finished processing the invite.
function WB:OnRosterUpdated(reason)
    if not IsInGuild or not IsInGuild() then
        self.knownRoster = {}
        self.hasBaseline = false
        return
    end

    local roster = self:BuildRosterSnapshot()
    if not self.hasBaseline then
        self.knownRoster = roster
        self.hasBaseline = true
        debugLog("roster baseline captured", reason or "event")
        return
    end

    for key, entry in pairs(roster) do
        if not self.knownRoster[key] then
            debugLog("new member detected from roster", entry.name or key)
            self:QueueJoin(entry.name or key, "roster")
        end
    end

    self.knownRoster = roster
end

function WB:OnGuildChanged()
    self.knownRoster = {}
    self.hasBaseline = false
    self.queue = {}
    self.queuedKeys = {}
    if self.timer then
        self.timer:Cancel()
        self.timer = nil
    end
    debugLog("guild changed; welcome state reset")
end

function WB:ExtractJoinedName(message)
    message = stripChatDecorators(message)
    if message == "" then return nil end

    for _, pattern in ipairs(JOIN_PATTERNS) do
        if pattern then
            local name = trim(message:match(pattern))
            if name ~= "" then
                return name
            end
        end
    end

    return nil
end

function WB:CaptureSystemMessage(message)
    local joinedName = self:ExtractJoinedName(message)
    if not joinedName then return end

    debugLog("new member detected from system message", joinedName)
    self:QueueJoin(joinedName, "system")
end

function WB:QueueJoin(name, source)
    if not self:IsEnabled() then
        debugLog("skip queue; disabled")
        return false
    end

    local key = normalizeName(name)
    if not key then return false end
    if self.queuedKeys[key] then
        debugLog("skip queue; already queued", name)
        return false
    end
    if self:WasRecentlyWelcomed(key) then
        debugLog("skip queue; recently welcomed", name)
        return false
    end

    local entry = {
        key = key,
        name = displayName(name),
        source = source or "unknown",
        queuedAt = now(),
    }
    self.queue[#self.queue + 1] = entry
    self.queuedKeys[key] = true
    debugLog("added to welcome queue", entry.name, entry.source)
    self:StartTimer()
    return true
end

-- The timer starts with the first queued member, then sends the whole batch at
-- the end of the configured window. Later joins join the same pending batch.
function WB:StartTimer()
    if self.timer then
        debugLog("batch timer already running")
        return
    end

    local delay = self:GetWindowSeconds()
    debugLog("batch timer started", tostring(delay) .. "s")
    self.timer = C_Timer.NewTimer(delay, function()
        self.timer = nil
        self:SendBatch()
    end)
end

function WB:BuildMessage(namesText)
    local template = trim(settings().welcomeMessageTemplate)
    if template == "" then
        template = "Welcome to the guild, {names}! Glad to have you aboard!"
    end

    if template:find("{names}", 1, true) then
        return (template:gsub("{names}", namesText))
    end

    return template .. " " .. namesText
end

function WB:BuildBoundedMessage(names)
    local namesText = formatNames(names)
    local message = self:BuildMessage(namesText)
    if #message <= MAX_GUILD_MESSAGE_LENGTH then
        return message
    end

    local kept = {}
    for index, name in ipairs(names) do
        kept[#kept + 1] = name
        local candidateNames = index < #names and formatNamesWithOverflow(kept) or formatNames(kept)
        if #self:BuildMessage(candidateNames) > MAX_GUILD_MESSAGE_LENGTH then
            table.remove(kept)
            break
        end
    end

    if #kept == 0 then
        message = self:BuildMessage("new members")
    elseif #kept < #names then
        message = self:BuildMessage(formatNamesWithOverflow(kept))
    else
        message = self:BuildMessage(formatNames(kept))
    end

    if #message > MAX_GUILD_MESSAGE_LENGTH then
        message = message:sub(1, MAX_GUILD_MESSAGE_LENGTH - 3) .. "..."
    end
    return message
end

function WB:CanSend()
    if not self:IsEnabled() then
        return false, "disabled"
    end
    if settings().enableMessagingModule == false then
        return false, "messaging module disabled"
    end
    if not IsInGuild or not IsInGuild() then
        return false, "not in guild"
    end
    if GC.API and GC.API.CanSpeakInGuildChat and not GC.API.CanSpeakInGuildChat() then
        return false, "no guild chat permission"
    end
    if InCombatLockdown and InCombatLockdown() then
        return false, "combat lockdown"
    end
    return true
end

function WB:RescheduleAfterSkip(reason)
    if #self.queue == 0 or self.timer then return end
    if reason == "combat lockdown" then
        debugLog("rescheduling welcome batch after combat skip")
        self.timer = C_Timer.NewTimer(15, function()
            self.timer = nil
            self:SendBatch()
        end)
    end
end

function WB:SendBatch()
    if #self.queue == 0 then
        debugLog("skip send; queue empty")
        return false
    end

    local canSend, reason = self:CanSend()
    if not canSend then
        debugLog("skip send;", reason)
        self:RescheduleAfterSkip(reason)
        return false
    end

    local batch = self.queue
    self.queue = {}
    self.queuedKeys = {}

    local names = {}
    for _, entry in ipairs(batch) do
        names[#names + 1] = entry.name
    end

    local message = self:BuildBoundedMessage(names)
    local ok, err
    if GC.API and GC.API.SendGuildMessage then
        ok, err = GC.API.SendGuildMessage(message)
    else
        ok, err = false, "guild chat API unavailable"
    end
    if not ok then
        debugLog("welcome send failed", err or "unknown error")
        for _, entry in ipairs(batch) do
            self.queue[#self.queue + 1] = entry
            self.queuedKeys[entry.key] = true
        end
        return false
    end

    for _, entry in ipairs(batch) do
        self:MarkWelcomed(entry)
    end
    self:PruneRecent()
    debugLog("welcome message sent", message)
    return true
end

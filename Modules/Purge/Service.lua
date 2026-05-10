-- /GuildCore/Modules/Purge/Service.lua
-- Safe guild purge queue. Guild removal is prepared as /gremove macro text and
-- must be executed manually by an officer.
local addonName, ns = ...
local GC = ns.GuildCore

local PurgeService = {}
PurgeService.__index = PurgeService

local MACRO_NAME = "GuildCore_Action"
local MACRO_ICON = "INV_Misc_Note_01"
local MACRO_LIMIT = 255
local RESET_LINE = "/run GuildCore_ResetActionMacro()"
local DEFAULT_HOTKEY = "CTRL-SHIFT-K"

local DEFAULT_SAFE_TAGS = {
    "PROTECTED",
    "LEAVE",
    "OFFICER ALT",
    "DO NOT KICK",
}

local DEFAULT_RANKS = {
    initiate = true,
    member = true,
}

local MIN_DAYS_OFFLINE = 3

local function now()
    return GC.Utils.Now and GC.Utils.Now() or time()
end

local function getHotkey()
    local settings = GC.DB and GC.DB.GetSettings and GC.DB:GetSettings()
    return settings and settings.guildActionHotkey or DEFAULT_HOTKEY
end

local function trim(value)
    return GC.Utils.Trim(value or "")
end

local function normalizeName(value)
    value = trim(value)
    if value == "" then
        return nil
    end
    return value:match("^([^%-]+)") or value
end

local function normalizeRank(value)
    return GC.Utils.NormalizeRankName(value or "")
end

local function guild()
    return GC.DB:GetGuild()
end

local function validateDaysOffline(value, fallback)
    local days
    if value == nil and fallback ~= nil then
        days = tonumber(fallback)
    else
        days = tonumber(value)
    end
    days = math.floor(days or MIN_DAYS_OFFLINE)
    if days < MIN_DAYS_OFFLINE then
        days = MIN_DAYS_OFFLINE
    end
    return days
end

local function ensureState()
    local db = guild()
    if not db then return nil end
    db.purge = db.purge or {}
    db.purge.queue = db.purge.queue or {}
    db.purge.candidates = db.purge.candidates or {}
    db.purge.protected = db.purge.protected or {}
    db.purge.log = db.purge.log or {}
    db.purge.meta = db.purge.meta or {
        daysOffline = 30,
        safeTags = DEFAULT_SAFE_TAGS,
        includeRanks = { "Initiate", "Member" },
        includeAllRanks = true,
        exemptLinkedCharacters = true,
    }
    -- Purge days offline is clamped to a minimum of 3 so dashboard offsets
    -- and purge comparisons cannot become negative or invalid.
    db.purge.meta.daysOffline = validateDaysOffline(db.purge.meta.daysOffline)
    db.purge.meta.safeTags = db.purge.meta.safeTags or DEFAULT_SAFE_TAGS
    db.purge.meta.includeRanks = db.purge.meta.includeRanks or { "Initiate", "Member" }
    if db.purge.meta.includeAllRanks == nil then
        db.purge.meta.includeAllRanks = true
    end
    if db.purge.meta.exemptLinkedCharacters == nil then
        db.purge.meta.exemptLinkedCharacters = true
    end
    return db.purge
end

local function appendLocalLog(entry)
    local state = ensureState()
    if not state then return end
    entry.timestamp = entry.timestamp or now()
    state.log[#state.log + 1] = entry
    while #state.log > 500 do
        table.remove(state.log, 1)
    end

    if GC.Services and GC.Services.DataStore then
        GC.Services.DataStore:AppendLog({
            timestamp = entry.timestamp,
            event = "PURGE",
            playerKey = entry.key,
            oldValue = entry.status,
            newValue = entry.name,
            reason = entry.reason,
        })
    end
end

local function actorName()
    local name, realm
    if UnitFullName then
        name, realm = UnitFullName("player")
    else
        name = UnitName("player")
    end
    if name and realm and realm ~= "" then
        return name .. "-" .. realm
    end
    return name or UnitName("player")
end

local function getMacroIndex()
    if GetMacroIndexByName then
        local index = GetMacroIndexByName(MACRO_NAME)
        if index and index > 0 then
            return index
        end
    end
    return nil
end

local function canCreateMacro()
    if not GetNumMacros then return false end
    local accountMacros = GetNumMacros()
    if type(accountMacros) == "table" then
        accountMacros = accountMacros.global or accountMacros.numGlobalMacros or 0
    end
    return (accountMacros or 0) < (MAX_ACCOUNT_MACROS or 120)
end

local function clearMacro()
    local index = getMacroIndex()
    if index and EditMacro then
        EditMacro(index, MACRO_NAME, MACRO_ICON, "")
    end
end

local function localizedSystemFormatMatches(message, formatText)
    if type(message) ~= "string" or type(formatText) ~= "string" or formatText == "" then
        return false
    end
    local marker = "\001"
    local pattern = string.lower(formatText):gsub("%%s", marker):gsub("%%d", marker)
    pattern = pattern:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
    pattern = pattern:gsub(marker, ".+")
    return string.find(string.lower(message), pattern) ~= nil
end

local function notesContainSafeTag(player, safeTags)
    local notes = {
        player and player.publicNote or "",
        player and player.officerNote or "",
        player and player.notes and player.notes.custom or "",
        player and player.notes and type(player.notes.tags) == "table" and table.concat(player.notes.tags, " ") or "",
    }
    local haystack = string.lower(table.concat(notes, "\n"))
    for _, tag in ipairs(safeTags or DEFAULT_SAFE_TAGS) do
        local text = trim(tag)
        if text ~= "" and string.find(haystack, string.lower(text), 1, true) then
            return true, text
        end
    end
    return false, nil
end

local function rankIncluded(player, includeRanks)
    local included = {}
    if type(includeRanks) == "table" and #includeRanks > 0 then
        for _, rank in ipairs(includeRanks) do
            included[normalizeRank(rank)] = true
        end
    elseif type(includeRanks) == "table" then
        return true
    else
        included = DEFAULT_RANKS
    end
    return included[normalizeRank(player and player.rankName)] == true
end

local function daysOffline(player)
    local rosterDays = tonumber(player and player.offlineDays)
    if rosterDays and rosterDays >= 0 then
        return math.floor(rosterDays)
    end

    local rosterHours = tonumber(player and player.offlineHours)
    if rosterHours and rosterHours >= 0 then
        return math.floor(rosterHours / 24)
    end

    local lastSeen = tonumber(player and player.lastSeenAt) or 0
    if lastSeen <= 0 then
        return math.huge
    end
    return math.floor(math.max(0, (now() - lastSeen) / 86400))
end

local function iterRosterCandidates()
    local byKey = {}
    local rows = {}
    local snapshot = GC.Services.DataStore:GetLastSnapshot()

    local function add(member)
        if not member or not member.key or byKey[member.key] then
            return
        end
        local stored = GC.Services.DataStore:GetPlayer(member.key) or {}
        local row = {}
        for key, value in pairs(stored) do
            row[key] = value
        end
        for key, value in pairs(member) do
            row[key] = value
        end
        row.status = member.capturedAt and "active" or (stored.status or "active")
        row.lastSeenAt = stored.lastSeenAt
        if member.offlineDays ~= nil then
            row.offlineDays = member.offlineDays
        end
        if member.offlineHours ~= nil then
            row.offlineHours = member.offlineHours
        end
        byKey[member.key] = true
        rows[#rows + 1] = row
    end

    if IsInGuild and IsInGuild() then
        GC.API.SetGuildRosterShowOffline(true)
        GC.API.GuildRoster()

        local totalMembers = GetNumGuildMembers and GetNumGuildMembers() or 0
        for index = 1, totalMembers do
            local fullName, rankName, rankIndex, level, classDisplayName, zone, publicNote, officerNote, isOnline, status, classFileName = GC.API.GetGuildRosterInfo(index)
            if fullName then
                local name, realm = GC.Utils.SplitGuildName(fullName)
                local key = GC.Utils.NormalizePlayerKey(name, realm)
                local yearsOffline, monthsOffline, offlineDays, hoursOffline = 0, 0, 0, 0
                if not isOnline and GC.API.GetGuildRosterLastOnline then
                    yearsOffline, monthsOffline, offlineDays, hoursOffline = GC.API.GetGuildRosterLastOnline(index)
                end
                yearsOffline = tonumber(yearsOffline) or 0
                monthsOffline = tonumber(monthsOffline) or 0
                offlineDays = tonumber(offlineDays) or 0
                hoursOffline = tonumber(hoursOffline) or 0

                add({
                    key = key,
                    name = name,
                    realm = realm or GetRealmName(),
                    rankName = rankName,
                    rankIndex = rankIndex,
                    level = level,
                    classDisplayName = classDisplayName,
                    classFileName = classFileName,
                    zone = zone,
                    publicNote = publicNote,
                    officerNote = officerNote,
                    isOnline = isOnline and true or false,
                    capturedAt = now(),
                    offlineHours = isOnline and 0 or ((yearsOffline * 365 * 24) + (monthsOffline * 30 * 24) + (offlineDays * 24) + hoursOffline),
                    offlineDays = isOnline and 0 or math.floor(((yearsOffline * 365 * 24) + (monthsOffline * 30 * 24) + (offlineDays * 24) + hoursOffline) / 24),
                })
            end
        end
    end

    if snapshot then
        for _, member in pairs(snapshot.members or {}) do
            add(member)
        end
        for _, member in pairs(snapshot.excluded or {}) do
            add(member)
        end
    end

    for _, player in pairs(GC.Services.DataStore:GetPlayers() or {}) do
        if player.key and not byKey[player.key] then
            rows[#rows + 1] = player
        end
    end

    return rows
end

local function getPlayerByName(name)
    local target = normalizeName(name)
    if not target then return nil end
    local lower = string.lower(target)
    local players = GC.Services.DataStore:GetPlayers() or {}
    for _, player in pairs(players) do
        if player.name and string.lower(player.name) == lower then
            return player
        end
    end
    return nil
end

local function linkedCharacterActive(player, thresholdDays)
    if not player then return false end
    local players = GC.Services.DataStore:GetPlayers() or {}
    local keys = {}
    if player.main then
        keys[player.main] = true
    end
    for _, key in ipairs(player.alts or {}) do
        keys[key] = true
    end
    for key, candidate in pairs(players) do
        if candidate.main and candidate.main == player.key then
            keys[key] = true
        end
    end

    for key in pairs(keys) do
        local linked = players[key]
        if linked and linked.status == "active" and daysOffline(linked) < thresholdDays then
            return true, linked.name or key
        end
    end
    return false, nil
end

function PurgeService:GetState()
    return ensureState()
end

function PurgeService:GetQueue()
    local state = ensureState()
    return state and state.queue or {}
end

function PurgeService:GetCandidates()
    local state = ensureState()
    return state and state.candidates or {}
end

function PurgeService:GetProtected()
    local state = ensureState()
    return state and state.protected or {}
end

function PurgeService:GetLog()
    local state = ensureState()
    return state and state.log or {}
end

function PurgeService:GetRules()
    local state = ensureState()
    return state and state.meta or {}
end

function PurgeService:ValidateDaysOffline(value, fallback)
    return validateDaysOffline(value, fallback)
end

function PurgeService:GetPurgeDaysOffline()
    local state = ensureState()
    return state and validateDaysOffline(state.meta.daysOffline) or 30
end

function PurgeService:GetDashboardInactiveDays()
    -- Ready for Purge uses the purge tab days offline rule directly.
    -- Dashboard Inactive uses purge days offline minus 3.
    -- The purge rule itself is clamped to a minimum of 3.
    return math.max(0, self:GetPurgeDaysOffline() - 3)
end

function PurgeService:GetPlayerDaysOffline(player)
    return daysOffline(player)
end

function PurgeService:UpdateRules(rules)
    local state = ensureState()
    if not state then return false, "Guild data unavailable." end
    rules = rules or {}

    if rules.daysOffline ~= nil then
        state.meta.daysOffline = validateDaysOffline(rules.daysOffline)
    end
    if type(rules.safeTags) == "table" then
        state.meta.safeTags = rules.safeTags
    end
    if type(rules.includeRanks) == "table" then
        state.meta.includeRanks = rules.includeRanks
    end
    if rules.includeAllRanks ~= nil then
        state.meta.includeAllRanks = rules.includeAllRanks and true or false
    end
    if rules.exemptLinkedCharacters ~= nil then
        state.meta.exemptLinkedCharacters = rules.exemptLinkedCharacters and true or false
    end
    return true
end

function PurgeService:HasPreparedMacro()
    local state = ensureState()
    return getMacroIndex() ~= nil
        and state
        and state.meta
        and type(state.meta.preparedNames) == "table"
        and #state.meta.preparedNames > 0
        and GC.State.actionMacroOwner == "purge"
end

function PurgeService:HasSafeTag(player)
    local state = ensureState()
    local tags = state and state.meta and state.meta.safeTags or DEFAULT_SAFE_TAGS
    return notesContainSafeTag(player, tags)
end

function PurgeService:CanQueue(player)
    if not player then
        return false, "No player selected."
    end
    local ok, reason = GC.Permissions:CanKickRankIndex(player.rankIndex)
    if not ok then
        return false, reason
    end
    local protected, tag = self:HasSafeTag(player)
    if protected then
        return false, "Safe tag found: " .. tostring(tag)
    end
    return true
end

function PurgeService:IsQueued(name)
    local target = normalizeName(name)
    if not target then return false end
    local lower = string.lower(target)
    for _, entry in ipairs(self:GetQueue()) do
        if string.lower(entry.name or "") == lower and entry.status ~= "removed" then
            return true
        end
    end
    return false
end

function PurgeService:QueuePlayer(player, reason, source)
    local ok, err = self:CanQueue(player)
    if not ok then
        return false, err
    end

    local name = normalizeName(player.name)
    if not name then
        return false, "Player name unavailable."
    end
    if self:IsQueued(name) then
        return true, "Purge already queued. Build and execute the macro to remove this member."
    end

    local state = ensureState()
    state.queue[#state.queue + 1] = {
        key = player.key,
        name = name,
        command = "/gremove",
        reason = reason,
        source = source or "manual",
        queuedAt = now(),
        queuedBy = actorName(),
        status = "queued",
    }
    return true, "Purge queued. Build and execute the macro to remove this member."
end

function PurgeService:QueueManual(player, reason)
    return self:QueuePlayer(player, reason, "manual")
end

function PurgeService:QueueCandidate(candidate)
    if not candidate then return false, "No candidate selected." end
    local player = candidate.key and GC.Services.DataStore:GetPlayer(candidate.key) or getPlayerByName(candidate.name)
    if not player then
        player = candidate
    end
    return self:QueuePlayer(player, candidate.reason, "rule")
end

function PurgeService:QueueAllCandidates()
    local queued, skipped = 0, 0
    for _, candidate in ipairs(self:GetCandidates()) do
        local ok = self:QueueCandidate(candidate)
        if ok then queued = queued + 1 else skipped = skipped + 1 end
    end
    return queued, skipped
end

function PurgeService:RemoveQueued(name)
    local target = normalizeName(name)
    if not target then return false end
    local lower = string.lower(target)
    local queue = self:GetQueue()
    for i = #queue, 1, -1 do
        if string.lower(queue[i].name or "") == lower then
            table.remove(queue, i)
            return true
        end
    end
    return false
end

function PurgeService:ClearQueue()
    local state = ensureState()
    if not state then return end
    state.queue = {}
    state.meta.preparedNames = {}
    if GC.State.actionMacroOwner == "purge" then
        GC.State.actionMacroOwner = nil
    end
    clearMacro()
end

function PurgeService:ScanCandidates(options)
    local state = ensureState()
    if not state then return 0, 0 end
    options = options or {}

    local thresholdDays = validateDaysOffline(options.daysOffline == nil and state.meta.daysOffline or options.daysOffline)
    local includeAllRanks = options.includeAllRanks
    if includeAllRanks == nil then
        includeAllRanks = state.meta.includeAllRanks
    end
    local includeRanks = includeAllRanks and {} or (options.includeRanks or state.meta.includeRanks)
    local safeTags = options.safeTags or state.meta.safeTags
    local exemptLinked = options.exemptLinkedCharacters
    if exemptLinked == nil then
        exemptLinked = state.meta.exemptLinkedCharacters
    end

    state.meta.daysOffline = thresholdDays
    state.meta.includeAllRanks = includeAllRanks and true or false
    state.meta.includeRanks = includeRanks
    state.meta.safeTags = safeTags
    state.meta.exemptLinkedCharacters = exemptLinked and true or false
    state.candidates = {}
    state.protected = {}

    local scanned = 0
    local inactive = 0

    for _, player in ipairs(iterRosterCandidates()) do
        if (player.status == "active" or player.capturedAt ~= nil) then
            scanned = scanned + 1
            local offline = daysOffline(player)
            if offline >= thresholdDays then
                inactive = inactive + 1
            end

            if not rankIncluded(player, includeRanks) then
                if offline >= thresholdDays then
                    state.protected[#state.protected + 1] = {
                        key = player.key,
                        name = player.name,
                        rankName = player.rankName,
                        daysOffline = offline,
                        reason = "Rank not included by current purge rule.",
                    }
                end
            else
            local ok, permissionReason = GC.Permissions:CanKickRankIndex(player.rankIndex)
            if ok and offline >= thresholdDays then
                local protected, tag = notesContainSafeTag(player, safeTags)
                if protected then
                    state.protected[#state.protected + 1] = {
                        key = player.key,
                        name = player.name,
                        rankName = player.rankName,
                        daysOffline = offline,
                        reason = "Safe tag: " .. tostring(tag),
                    }
                elseif exemptLinked then
                    local activeLinked, linkedName = linkedCharacterActive(player, thresholdDays)
                    if activeLinked then
                        state.protected[#state.protected + 1] = {
                            key = player.key,
                            name = player.name,
                            rankName = player.rankName,
                            daysOffline = offline,
                            reason = "Main/alt exemption: active link " .. tostring(linkedName),
                        }
                    else
                        state.candidates[#state.candidates + 1] = {
                            key = player.key,
                            name = player.name,
                            rankName = player.rankName,
                            daysOffline = offline,
                            reason = string.format("Rule: %s offline %d+ days", player.rankName or "rank", thresholdDays),
                            source = "rule",
                        }
                    end
                else
                    state.candidates[#state.candidates + 1] = {
                        key = player.key,
                        name = player.name,
                        rankName = player.rankName,
                        daysOffline = offline,
                        reason = string.format("Rule: %s offline %d+ days", player.rankName or "rank", thresholdDays),
                        source = "rule",
                    }
                end
            elseif permissionReason and offline >= thresholdDays then
                state.protected[#state.protected + 1] = {
                    key = player.key,
                    name = player.name,
                    rankName = player.rankName,
                    daysOffline = offline,
                    reason = permissionReason,
                }
            end
            end
        end
    end

    state.meta.lastScanTotal = scanned
    state.meta.lastScanInactive = inactive

    table.sort(state.candidates, function(a, b)
        if (a.daysOffline or 0) ~= (b.daysOffline or 0) then
            return (a.daysOffline or 0) > (b.daysOffline or 0)
        end
        return (a.name or "") < (b.name or "")
    end)
    table.sort(state.protected, function(a, b)
        return (a.name or "") < (b.name or "")
    end)

    return #state.candidates, #state.protected
end

function PurgeService:BuildMacro()
    local state = ensureState()
    if not state then return false, "Guild data unavailable." end
    if InCombatLockdown and InCombatLockdown() then
        return false, "Cannot create or edit guild action macros while in combat."
    end

    local macroText = ""
    local preparedNames = {}
    for _, entry in ipairs(state.queue) do
        if entry.status == "queued" and entry.name and entry.command == "/gremove" then
            local line = string.format("/gremove %s", entry.name)
            local candidate = macroText == "" and line or (macroText .. "\n" .. line)
            if #candidate > MACRO_LIMIT then
                break
            end
            macroText = candidate
            preparedNames[#preparedNames + 1] = entry.name
        end
    end

    if #preparedNames == 0 then
        clearMacro()
        return false, "No queued purge entries fit in the macro."
    end

    local withReset = macroText .. "\n" .. RESET_LINE
    if #withReset <= MACRO_LIMIT then
        macroText = withReset
    end

    local index = getMacroIndex()
    if index then
        EditMacro(index, MACRO_NAME, MACRO_ICON, macroText)
    else
        if not canCreateMacro() then
            return false, "No account macro slots are available."
        end
        CreateMacro(MACRO_NAME, MACRO_ICON, macroText, nil)
    end

    state.meta.preparedNames = preparedNames
    state.meta.lastMacroBuiltAt = now()
    GC.State.actionMacroOwner = "purge"
    local hotkey = getHotkey()
    if SetBindingMacro then
        SetBindingMacro(hotkey, MACRO_NAME)
        if SaveBindings and GetCurrentBindingSet then
            SaveBindings(GetCurrentBindingSet())
        end
    end
    GC:Debug("purge macro index", tostring(getMacroIndex()))
    GC:Debug("purge macro body before execution:")
    GC:Debug(macroText)
    GC:Debug("purge bound hotkey", tostring(hotkey))
    return true, string.format("Press %s 1 time to complete all actions. Batch size: %d.", hotkey, #preparedNames)
end

function PurgeService:OnMacroExecuted()
    local state = ensureState()
    if not state then return end
    local prepared = state.meta.preparedNames or {}
    local preparedLookup = {}
    for _, name in ipairs(prepared) do
        preparedLookup[string.lower(name)] = true
    end

    state.meta.lastMacroStartedAt = now()
    clearMacro()

    for _, entry in ipairs(state.queue) do
        if preparedLookup[string.lower(entry.name or "")] and entry.status == "queued" then
            entry.status = "awaitingVerification"
            entry.macroStartedAt = state.meta.lastMacroStartedAt
        end
    end

    if GC.UI and GC.UI.PurgePanel and GC.UI.PurgePanel.Refresh then
        GC.UI.PurgePanel:Refresh()
    end

    if GC.Services and GC.Services.GuildService then
        C_Timer.After(1.5, function()
            GC.Services.GuildService:TriggerScan()
        end)
    end
end

local function markVerifiedRemoved(name, officer, source)
    local state = ensureState()
    if not state then return false end
    local target = normalizeName(name)
    if not target then return false end
    local lower = string.lower(target)

    for i = #state.queue, 1, -1 do
        local entry = state.queue[i]
        if string.lower(entry.name or "") == lower then
            appendLocalLog({
                key = entry.key,
                name = entry.name,
                officer = officer or entry.queuedBy or actorName(),
                reason = entry.reason,
                source = entry.source or source,
                verified = true,
                status = "removed",
            })
            table.remove(state.queue, i)
            return true
        end
    end
    return false
end

function PurgeService:CaptureSystemMessage(message)
    if type(message) ~= "string" then return end
    local lower = string.lower(message)
    if not (string.find(lower, "has been kicked", 1, true)
        or string.find(lower, "removed from the guild", 1, true)
        or string.find(lower, "has kicked", 1, true)
        or localizedSystemFormatMatches(message, ERR_GUILD_REMOVE_SS)) then
        return
    end

    for _, entry in ipairs(self:GetQueue()) do
        if entry.name and string.find(lower, string.lower(entry.name), 1, true) then
            if markVerifiedRemoved(entry.name, nil, "system") then
                if GC.UI and GC.UI.MainFrame then
                    GC.UI.MainFrame:SetStatus(entry.name .. " removal verified by system message.", "textSuccess")
                end
                break
            end
        end
    end

    if GC.UI and GC.UI.PurgePanel and GC.UI.PurgePanel.Refresh then
        GC.UI.PurgePanel:Refresh()
    end
end

function PurgeService:OnRosterUpdated()
    local players = GC.Services.DataStore:GetPlayers() or {}
    local activeNames = {}
    for _, player in pairs(players) do
        if player.status == "active" and player.name then
            activeNames[string.lower(player.name)] = true
        end
    end

    local changed = false
    local queue = self:GetQueue()
    for i = #queue, 1, -1 do
        local entry = queue[i]
        if entry.status == "awaitingVerification" and entry.name and not activeNames[string.lower(entry.name)] then
            if markVerifiedRemoved(entry.name, entry.queuedBy, "roster") then
                changed = true
            end
        end
    end

    if changed and GC.UI and GC.UI.PurgePanel and GC.UI.PurgePanel.Refresh then
        GC.UI.PurgePanel:Refresh()
    end
end

GC:RegisterService("Purge", setmetatable({}, PurgeService))

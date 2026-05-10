-- Services/GuildService.lua
-- High-level facade used by UI panels. Aggregates roster, alts, and points
-- into ready-to-display view models so panels stay thin.
local addonName, ns = ...
local GC = ns.GuildCore

GC.Services              = GC.Services or {}
GC.Services.GuildService = {}
local GS                 = GC.Services.GuildService

local function getActivePlayers()
    local players = GC.Services.DataStore:GetPlayers()
    if not players then
        return {}
    end

    local active = {}
    for _, player in pairs(players) do
        if player.status == "active" then
            table.insert(active, player)
        end
    end

    return active
end

local function getInactivityDays(player, now)
    local purge = GC.Services and GC.Services.Purge
    if purge and purge.GetPlayerDaysOffline then
        return purge:GetPlayerDaysOffline(player)
    end

    local rosterDays = tonumber(player and player.offlineDays)
    if rosterDays and rosterDays >= 0 then
        return math.floor(rosterDays)
    end

    local rosterHours = tonumber(player and player.offlineHours)
    if rosterHours and rosterHours >= 0 then
        return math.floor(rosterHours / 24)
    end

    local lastSeen = player and player.lastSeenAt or 0
    if lastSeen <= 0 then
        return math.huge
    end
    return math.floor(math.max(0, ((now or time()) - lastSeen) / 86400))
end

local function getLiveGuildCounts()
    if not GetNumGuildMembers then
        return nil, nil
    end

    local total, online = GetNumGuildMembers()
    return tonumber(total), tonumber(online)
end

local function getPurgeService()
    return GC.Services and GC.Services.Purge or nil
end

local function getPurgeDaysOffline()
    local purge = getPurgeService()
    if purge and purge.GetPurgeDaysOffline then
        return purge:GetPurgeDaysOffline()
    end
    return 30
end

local function getDashboardInactiveDays()
    local purge = getPurgeService()
    if purge and purge.GetDashboardInactiveDays then
        return purge:GetDashboardInactiveDays()
    end
    -- Ready for Purge uses the purge rule directly; Dashboard Inactive uses
    -- that same purge days offline rule minus 3, clamped at 0.
    return math.max(0, getPurgeDaysOffline() - 3)
end

local function isMissingDiscordName(player)
    local discordName = player and player.officerData and player.officerData.discordName
    return GC.Utils.Trim(discordName or "") == ""
end

local function countsForDiscordDashboard(player)
    local rankIndex = tonumber(player and player.rankIndex)
    if not rankIndex or rankIndex < 0 or rankIndex > 3 then
        return false
    end
    if (player.classification or "unknown") == "alt" then
        return false
    end
    return true
end

-- Return sorted player list with derived display fields.
-- Each entry adds: statusLabel, classColor, joinedDisplay, lastSeenDisplay
function GS:GetRosterList()
    local DS      = GC.Services.DataStore
    local players = DS:GetPlayers()
    if not players then return {} end

    local T   = GC.UI and GC.UI.Theme
    local now = time()
    local list = {}
    local purgeDays = getPurgeDaysOffline()
    local seenWarnDays = math.floor(purgeDays / 2)
    local seenDangerDays = seenWarnDays + 1

    for _, p in pairs(players) do
        if p.status == "active" then
            local entry = {}
            for k, v in pairs(p) do entry[k] = v end

            -- Status is current roster presence; Seen carries age/urgency.
            if p.isOnline then
                entry.statusLabel = "Online"
                entry.statusKey   = "statusActive"
            else
                entry.statusLabel = "Offline"
                entry.statusKey   = "textDimmed"
            end

            local daysSince = getInactivityDays(p, now)
            if daysSince <= 7 then
                entry.seenColorKey = "statusActive"
            elseif daysSince <= seenWarnDays then
                entry.seenColorKey = "statusWarn"
            elseif daysSince >= seenDangerDays then
                entry.seenColorKey = "statusInact"
            else
                entry.seenColorKey = "textSecond"
            end

            -- Class color: use canonical class key (classFileName stored as p.class)
            local classKey = p.class or p.classFileName
            entry.classRGB = (T and classKey and T.classColor[classKey]) or {1, 1, 1}

            -- Date strings
            entry.joinedDisplay       = p.joinedAt and date("%Y-%m-%d", p.joinedAt) or "—"
            entry.firstSeenDisplay    = p.firstSeenAt and date("%Y-%m-%d", p.firstSeenAt) or "—"
            entry.lastSeenDisplay     = p.lastSeenAt and date("%Y-%m-%d", p.lastSeenAt) or "—"
            entry.lastRosterDisplay   = p.lastRosterSeenAt and date("%Y-%m-%d", p.lastRosterSeenAt) or "—"
            entry.locationDisplay     = p.zone or "—"

            -- Rank display (shorten long names)
            entry.rankShort = p.rankName and (p.rankName:sub(1, 14)) or "—"
            entry.classification = p.classification or "unknown"
            entry.classificationLabel = ({
                main = "Main",
                alt = "Alt",
                unknown = "Unknown",
            })[entry.classification] or "Unknown"
            entry.classificationBadge = ({
                main = "[M]",
                alt = "[A]",
                unknown = "[?]",
            })[entry.classification] or "[?]"
            entry.mainDisplay = p.main and p.main:match("^([^%-]+)") or "—"
            entry.discordVerified = p.officerData and p.officerData.discordVerified or nil
            entry.discordName = p.officerData and p.officerData.discordName or nil
            entry.specDisplay = p.specialization or nil
            entry.classSpecDisplay = entry.specDisplay and (entry.classDisplayName .. " / " .. entry.specDisplay) or entry.classDisplayName
            entry.needsPrompt = entry.classification == "unknown"
                and p.isTrackedRank ~= false
                and not (p.promptState and (p.promptState.dismissedAt or p.promptState.bootstrapSuppressed))

            table.insert(list, entry)
        end
    end

    -- Sort: prompt-needed first, then mains, then name
    table.sort(list, function(a, b)
        if a.needsPrompt ~= b.needsPrompt then
            return a.needsPrompt
        end
        if a.classification ~= b.classification then
            if a.classification == "main" then return true end
            if b.classification == "main" then return false end
        end
        if a.name and b.name then return a.name < b.name end
        return false
    end)

    return list
end

function GS:InviteToParty(key)
    local player = self:GetPlayerByKey(key)
    if not player then
        return false, "Player not found."
    end

    GC.API.InviteUnit(player.name or key)
    return true
end

function GS:GetWhisperTargetName(key)
    local player = self:GetPlayerByKey(key)
    if not player then
        return nil
    end

    if player.realm and player.realm ~= "" then
        local currentRealm = (GetRealmName() or ""):gsub("%s+", "")
        local targetRealm = tostring(player.realm):gsub("%s+", "")
        if targetRealm ~= "" and targetRealm ~= currentRealm then
            return string.format("%s-%s", player.name or key, targetRealm)
        end
    end

    return player.name or key
end

function GS:OpenWhisper(key)
    local player = self:GetPlayerByKey(key)
    if not player then
        return false, "Player not found."
    end
    if not player.isOnline then
        return false, "That member is offline."
    end

    local target = self:GetWhisperTargetName(key)
    if not target or target == "" then
        return false, "Unable to resolve whisper target."
    end

    if ChatFrame_SendTell then
        ChatFrame_SendTell(target)
        return true
    end

    if ChatFrame_OpenChat then
        ChatFrame_OpenChat("/w " .. target .. " ")
        return true
    end

    return false, "Whisper is unavailable in this UI state."
end

-- Dashboard summary stats
function GS:GetStats()
    local activePlayers = getActivePlayers()
    local DS        = GC.Services.DataStore
    local logs      = DS:GetLogs()
    local snapshot  = DS:GetLastSnapshot()
    local liveTotal, liveOnline = getLiveGuildCounts()

    local now    = time()
    local inactiveThresholdDays = getDashboardInactiveDays()
    local total, active, inactive, idle, withAlts, totalPoints = 0, 0, 0, 0, 0, 0

    for _, p in ipairs(activePlayers) do
        total = total + 1
        local days = getInactivityDays(p, now)
        if days <= 7 then active = active + 1
        elseif days <= 30 then idle = idle + 1
        end
        if days >= inactiveThresholdDays then inactive = inactive + 1 end

        if p.alts and #p.alts > 0 then withAlts = withAlts + 1 end
        totalPoints = totalPoints + (p.points and p.points.balance or 0)
    end

    local snapshotTotal = snapshot and snapshot.summary and snapshot.summary.totalMembers or nil
    local displayTotal = liveTotal or snapshotTotal or total

    -- Prefer the same live guild count used by the footer. The snapshot
    -- fallback keeps the dashboard useful when the WoW API is unavailable.
    local online = liveOnline
    if online == nil and snapshot then
        online = 0
        for _, m in pairs(snapshot.members or {}) do
            if m.isOnline then online = online + 1 end
        end
        for _, m in pairs(snapshot.excluded or {}) do
            if m.isOnline then online = online + 1 end
        end
    end
    online = online or 0

    -- Count events in the last 7 days
    local recentJoins, recentLeaves, recentRanks = 0, 0, 0
    if logs then
        local cutoff = now - 604800  -- 7 days
        for i = #logs, math.max(1, #logs - 500), -1 do
            local e = logs[i]
            if not e or (e.timestamp and e.timestamp < cutoff) then break end
            if e.event == "JOINED" then recentJoins = recentJoins + 1
            elseif e.event == "LEFT" then recentLeaves = recentLeaves + 1
            elseif e.event == "PROMOTED" or e.event == "DEMOTED" then recentRanks = recentRanks + 1
            end
        end
    end

    return {
        total            = displayTotal,
        active           = active,
        idle             = idle,
        inactive         = inactive,
        online           = online,
        withAlts         = withAlts,
        totalPoints      = totalPoints,
        logCount         = logs and #logs or 0,
        lastScanAt       = snapshot and snapshot.takenAt or nil,
        recentJoins      = recentJoins,
        recentLeaves     = recentLeaves,
        recentRankChanges = recentRanks,
    }
end

function GS:GetInactivityThresholdDays()
    return getDashboardInactiveDays()
end

function GS:GetPurgeThresholdDays()
    return getPurgeDaysOffline()
end

function GS:GetGuildInsights()
    local now = time()
    local thresholdDays = self:GetInactivityThresholdDays()
    local purgeThresholdDays = self:GetPurgeThresholdDays()
    local counts = {
        initiatesNeedingReview = 0,
        missingDiscordVerification = 0,
        unlinkedCharacters = 0,
        inactiveMembers = 0,
    }

    for _, player in ipairs(getActivePlayers()) do
        local normalizedRank = GC.Utils.NormalizeRankName(player.rankName)
        if normalizedRank == "initiate" then
            counts.initiatesNeedingReview = counts.initiatesNeedingReview + 1
        end
        if countsForDiscordDashboard(player) and isMissingDiscordName(player) then
            counts.missingDiscordVerification = counts.missingDiscordVerification + 1
        end
        if (player.classification or "unknown") == "unknown" then
            counts.unlinkedCharacters = counts.unlinkedCharacters + 1
        end
        if getInactivityDays(player, now) >= purgeThresholdDays then
            counts.inactiveMembers = counts.inactiveMembers + 1
        end
    end

    return counts
end

function GS:GetNeedsAttention(limit)
    local now = time()
    local thresholdDays = self:GetInactivityThresholdDays()
    local purgeThresholdDays = self:GetPurgeThresholdDays()
    local rows = {}
    local seen = {}

    local function addRow(player, issue, action, priority, colorKey, panel)
        if not player or seen[player.key] then
            return
        end
        seen[player.key] = true
        rows[#rows + 1] = {
            key = player.key,
            character = player.name or player.key or "Unknown",
            issue = issue,
            action = action,
            priority = priority,
            colorKey = colorKey or "textAccent",
            panel = panel or "roster",
        }
    end

    local activePlayers = getActivePlayers()

    for _, player in ipairs(activePlayers) do
        if (player.classification or "unknown") == "unknown" then
            addRow(player, "Unknown main/alt status", "Set Main / Link Alt", 1, "textAccent", "roster")
        end
    end

    for _, player in ipairs(activePlayers) do
        if countsForDiscordDashboard(player) and isMissingDiscordName(player) then
            addRow(player, "Missing Discord verification", "Verify Discord", 2, "textWarn", "roster")
        end
    end

    for _, player in ipairs(activePlayers) do
        if GC.Utils.NormalizeRankName(player.rankName) == "initiate" then
            addRow(player, "Initiate needs review", "Review Initiate", 3, "textAccent", "roster")
        end
    end

    for _, player in ipairs(activePlayers) do
        local inactiveDays = getInactivityDays(player, now)
        if inactiveDays >= thresholdDays then
            addRow(
                player,
                string.format("Inactive %d+ days", inactiveDays),
                inactiveDays >= purgeThresholdDays and "Ready for Purge" or "Review Soon",
                4,
                "textWarn",
                "roster"
            )
        end
    end

    table.sort(rows, function(a, b)
        if a.priority ~= b.priority then
            return a.priority < b.priority
        end
        return (a.character or "") < (b.character or "")
    end)

    if not limit then
        return rows
    end

    local trimmed = {}
    for i = 1, math.min(limit, #rows) do
        trimmed[#trimmed + 1] = rows[i]
    end
    return trimmed
end

function GS:GetNeedsAttentionExportText()
    local rows = self:GetNeedsAttention()
    if #rows == 0 then
        return "Guild Insights\n\nNo urgent guild issues found."
    end

    local lines = {
        "Guild Insights",
        "Dashboard Inactive Threshold: " .. tostring(self:GetInactivityThresholdDays()) .. " days",
        "Ready for Purge Threshold: " .. tostring(self:GetPurgeThresholdDays()) .. " days",
        "",
        "Character | Issue | Suggested Action",
    }

    for _, row in ipairs(rows) do
        lines[#lines + 1] = string.format("%s | %s | %s", row.character, row.issue, row.action)
    end

    return table.concat(lines, "\n")
end

-- Trigger a manual roster scan via the two-phase flow (request → GUILD_ROSTER_UPDATE → capture).
function GS:TriggerScan()
    if not IsInGuild() then
        return false, "You are not in a guild."
    end
    GC.API.SetGuildRosterShowOffline(true)
    GC.API.GuildRoster()
    GC.State.pendingScanReason = "manual"
    return true
end

-- Return the N most recent log entries, newest first
function GS:GetRecentLogs(n)
    local DS   = GC.Services.DataStore
    local logs = DS:GetLogs()
    if not logs or #logs == 0 then return {} end
    n = n or 100
    local result = {}
    for i = #logs, math.max(1, #logs - n + 1), -1 do
        table.insert(result, logs[i])
    end
    return result
end

function GS:GetPlayerByKey(key)
    return GC.Services.DataStore:GetPlayer(key)
end

function GS:ResolvePlayerKey(input)
    input = GC.Utils.Trim(input)
    if input == "" then
        return nil
    end

    local players = GC.Services.DataStore:GetPlayers()
    if not players then
        return nil
    end

    if players[input] then
        return input
    end

    local normalized = GC.Utils.NormalizePlayerKey(input)
    if normalized and players[normalized] then
        return normalized
    end

    local lowerInput = input:lower()
    for key, player in pairs(players) do
        if player.name and player.name:lower() == lowerInput then
            return key
        end
    end

    return nil
end

function GS:GetPendingClassificationPrompt()
    local settings = GC.Services.DataStore:GetSettings()
    if settings and settings.enableClassificationPrompts == false then
        return nil
    end

    local players = GC.Services.DataStore:GetPlayers()
    if not players then
        return nil
    end

    local chosen = nil
    for _, player in pairs(players) do
        local promptState = player.promptState or {}
        if player.status == "active"
            and player.classification == "unknown"
            and player.isTrackedRank ~= false
            and not promptState.dismissedAt
            and not promptState.bootstrapSuppressed then
            if not chosen or (player.firstSeenAt or math.huge) < (chosen.firstSeenAt or math.huge) then
                chosen = player
            end
        end
    end

    return chosen
end

function GS:GetRosterEntry(key)
    local player = self:GetPlayerByKey(key)
    if not player or player.status ~= "active" then
        return nil
    end

    for _, entry in ipairs(self:GetRosterList()) do
        if entry.key == key then
            return entry
        end
    end

    return nil
end

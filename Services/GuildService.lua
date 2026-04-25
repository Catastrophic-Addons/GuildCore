-- Services/GuildService.lua
-- High-level facade used by UI panels. Aggregates roster, alts, and points
-- into ready-to-display view models so panels stay thin.
local addonName, ns = ...
local GC = ns.GuildCore

GC.Services              = GC.Services or {}
GC.Services.GuildService = {}
local GS                 = GC.Services.GuildService
local INACTIVITY_THRESHOLD_DAYS = 7

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
    local lastSeen = player and player.lastSeenAt or 0
    return math.floor(math.max(0, (now - lastSeen) / 86400))
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

    for _, p in pairs(players) do
        if p.status == "active" then
            local entry = {}
            for k, v in pairs(p) do entry[k] = v end

            -- Status label
            local lastSeen = p.lastSeenAt or 0
            local daysSince = (now - lastSeen) / 86400
            if daysSince <= 7 then
                entry.statusLabel = "Active"
                entry.statusKey   = "statusActive"
            elseif daysSince <= 30 then
                entry.statusLabel = "Idle"
                entry.statusKey   = "statusWarn"
            else
                entry.statusLabel = "Inactive"
                entry.statusKey   = "statusInact"
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
    if #activePlayers == 0 then
        return {total=0, active=0, inactive=0, idle=0, withAlts=0, totalPoints=0}
    end

    local now    = time()
    local total, active, inactive, idle, withAlts, totalPoints = 0, 0, 0, 0, 0, 0

    for _, p in ipairs(activePlayers) do
        total = total + 1
        local last = p.lastSeenAt or 0
        local days = (now - last) / 86400
        if days <= 7 then active = active + 1
        elseif days <= 30 then idle = idle + 1
        else inactive = inactive + 1 end

        if p.alts and #p.alts > 0 then withAlts = withAlts + 1 end
        totalPoints = totalPoints + (p.points and p.points.balance or 0)
    end

    local DS      = GC.Services.DataStore
    local logs     = DS:GetLogs()
    local snapshot  = DS:GetLastSnapshot()

    -- Count members online in latest snapshot
    local online = 0
    if snapshot and snapshot.members then
        for _, m in pairs(snapshot.members) do
            if m.isOnline then online = online + 1 end
        end
    end

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
        total            = total,
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
    return INACTIVITY_THRESHOLD_DAYS
end

function GS:GetGuildInsights()
    local now = time()
    local thresholdDays = self:GetInactivityThresholdDays()
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
        if not (player.officerData and player.officerData.discordVerified == true) then
            counts.missingDiscordVerification = counts.missingDiscordVerification + 1
        end
        if (player.classification or "unknown") == "unknown" then
            counts.unlinkedCharacters = counts.unlinkedCharacters + 1
        end
        if getInactivityDays(player, now) >= thresholdDays then
            counts.inactiveMembers = counts.inactiveMembers + 1
        end
    end

    return counts
end

function GS:GetNeedsAttention(limit)
    local now = time()
    local thresholdDays = self:GetInactivityThresholdDays()
    local rows = {}
    local seen = {}

    local function addRow(player, issue, action, priority, colorKey)
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
        }
    end

    local activePlayers = getActivePlayers()

    for _, player in ipairs(activePlayers) do
        if (player.classification or "unknown") == "unknown" then
            addRow(player, "Unknown main/alt status", "Set Main / Link Alt", 1, "textAccent")
        end
    end

    for _, player in ipairs(activePlayers) do
        if not (player.officerData and player.officerData.discordVerified == true) then
            addRow(player, "Missing Discord verification", "Verify Discord", 2, "textWarn")
        end
    end

    for _, player in ipairs(activePlayers) do
        if GC.Utils.NormalizeRankName(player.rankName) == "initiate" then
            addRow(player, "Initiate needs review", "Review Initiate", 3, "textAccent")
        end
    end

    for _, player in ipairs(activePlayers) do
        local inactiveDays = getInactivityDays(player, now)
        if inactiveDays >= thresholdDays then
            addRow(
                player,
                string.format("Inactive %d+ days", inactiveDays),
                "Review",
                4,
                "textWarn"
            )
        end
    end

    table.sort(rows, function(a, b)
        if a.priority ~= b.priority then
            return a.priority < b.priority
        end
        return (a.character or "") < (b.character or "")
    end)

    limit = limit or 10
    local trimmed = {}
    for i = 1, math.min(limit, #rows) do
        trimmed[#trimmed + 1] = rows[i]
    end
    return trimmed
end

function GS:GetNeedsAttentionExportText()
    local rows = self:GetNeedsAttention(10)
    if #rows == 0 then
        return "Guild Insights\n\nNo urgent guild issues found."
    end

    local lines = {
        "Guild Insights",
        "Inactivity Threshold: " .. tostring(self:GetInactivityThresholdDays()) .. " days",
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

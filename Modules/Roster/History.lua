-- /GuildCore/Modules/Roster/History.lua
local addonName, ns = ...
local GC = ns.GuildCore

GC.Modules.RosterHistory = {}

local function ensurePromptState(record)
    record.promptState = record.promptState or {}
    return record.promptState
end

local function forEachSnapshotMember(snapshot, callback)
    for _, member in pairs((snapshot and snapshot.members) or {}) do
        callback(member)
    end
    for _, member in pairs((snapshot and snapshot.excluded) or {}) do
        callback(member)
    end
end

local function buildSnapshotMemberKeys(snapshot)
    local keys = {}
    forEachSnapshotMember(snapshot, function(member)
        if member and member.key then
            keys[member.key] = true
        end
    end)
    return keys
end

-- Build or return the existing player record for a snapshot member.
local function ensurePlayerRecord(member)
    local players = GC.DB:GetPlayers()
    if not players then return nil end

    if not players[member.key] then
        players[member.key] = {
            key          = member.key,
            name         = member.name,
            realm        = member.realm,
            rankName     = member.rankName,
            rankIndex    = member.rankIndex,
            class        = member.classFileName,     -- canonical: uppercase e.g. "WARRIOR"
            classDisplayName = member.classDisplayName,
            classFileName    = member.classFileName,
            firstSeenAt      = member.capturedAt,
            joinedAt         = member.officerData and member.officerData.joinDate or nil,
            joinedAtSource   = member.officerData and member.officerData.joinDate and "officerNote" or nil,
            promotedAt       = nil,
            lastRosterSeenAt = member.capturedAt,    -- any scan
            lastSeenAt       = member.isOnline and member.capturedAt or (member.offlineHours and member.offlineHours > 0 and (member.capturedAt - (member.offlineHours * 3600)) or nil),
            status  = "active",
            classification = "unknown",
            main    = nil,
            alts    = {},
            points  = { balance = 0, lifetime = 0, transactions = {} },
            notes   = { custom = "", tags = {} },
            promptState = {},
            officerData = {
                joinDate = member.officerData and member.officerData.joinDate or nil,
                discordVerified = member.officerData and member.officerData.discordVerified or nil,
                discordName = member.officerData and member.officerData.discordName or nil,
                noteLastParsedAt = member.capturedAt,
            },
            isTrackedRank = member.isTrackedRank and true or false,
            lastScanReason = nil,
            syncMeta = {
                joinedAt   = member.capturedAt,
                promotedAt = 0,
                main       = 0,
                customNote = 0,
            },
        }
    end

    local record = players[member.key]
    record.promptState = record.promptState or {}
    record.officerData = record.officerData or {
        joinDate = nil,
        discordVerified = nil,
        discordName = nil,
        noteLastParsedAt = nil,
    }
    record.classification = record.classification or "unknown"
    record.firstSeenAt = record.firstSeenAt or member.capturedAt
    record.alts = record.alts or {}

    return players[member.key]
end

-- Append a structured log entry. Uses 'event' as the type field.
local function appendLog(eventType, playerKey, oldValue, newValue, reason)
    local logs = GC.DB:GetLogs()
    if not logs then return end

    logs[#logs + 1] = {
        timestamp = GC.Utils.Now(),
        event     = eventType,   -- canonical field name used by all UI panels
        playerKey = playerKey,
        oldValue  = oldValue,
        newValue  = newValue,
        reason    = reason,
    }
end

local function applyParsedOfficerData(record, member)
    local officerData = member.officerData or {}
    record.officerData = record.officerData or {}
    record.officerData.joinDate = officerData.joinDate
    record.officerData.discordVerified = officerData.discordVerified
    record.officerData.discordName = officerData.discordName
    record.officerData.noteLastParsedAt = member.capturedAt

    if officerData.joinDate then
        if record.joinedAtSource ~= "manual" or not record.joinedAt then
            record.joinedAt = officerData.joinDate
            record.joinedAtSource = "officerNote"
        end
    elseif record.joinedAtSource == "officerNote" then
        record.joinedAt = nil
        record.joinedAtSource = nil
    end
end

local function updateMemberRecord(record, member, reason)
    record.rankName         = member.rankName
    record.rankIndex        = member.rankIndex
    record.level            = member.level
    record.class            = member.classFileName
    record.classDisplayName = member.classDisplayName
    record.classFileName    = member.classFileName
    record.zone             = member.zone
    record.publicNote       = member.publicNote
    record.officerNote      = member.officerNote
    record.isOnline         = member.isOnline
    record.offlineHours     = member.offlineHours
    record.offlineDays      = member.offlineDays
    record.lastRosterSeenAt = member.capturedAt
    record.lastScanReason   = reason
    record.isTrackedRank    = member.isTrackedRank and true or false
    if member.isOnline then
        record.lastSeenAt = member.capturedAt
    elseif member.offlineHours and member.offlineHours > 0 then
        record.lastSeenAt = member.capturedAt - (member.offlineHours * 3600)
    end
    record.status = "active"
    applyParsedOfficerData(record, member)
end

local function countPendingPrompts(players)
    local pending = 0
    for _, player in pairs(players or {}) do
        local promptState = player.promptState or {}
        if player.status == "active"
            and player.classification == "unknown"
            and player.isTrackedRank ~= false
            and not promptState.dismissedAt
            and not promptState.bootstrapSuppressed then
            pending = pending + 1
        end
    end
    return pending
end

-- Public: append a one-off custom log entry (called from UI panels).
function GC.Modules.RosterHistory:AppendCustomLog(eventType, playerKey, oldValue, newValue, reason)
    appendLog(eventType, playerKey, oldValue, newValue, reason)
end

-- Bootstrap: first-ever scan. Populate player records from the live snapshot
-- without emitting JOINED log entries for any member.
function GC.Modules.RosterHistory:Bootstrap(snapshot)
    local players = GC.DB:GetPlayers()
    if not players then return end

    forEachSnapshotMember(snapshot, function(member)
        local record = ensurePlayerRecord(member)
        if record then
            updateMemberRecord(record, member, "bootstrap")
            local promptState = ensurePromptState(record)
            if not promptState.completedAt and not promptState.dismissedAt then
                promptState.bootstrapSuppressed = true
            end
        end
    end)

    local summary = {
        timestamp = snapshot.takenAt,
        reason = "bootstrap",
        trackedMembers = snapshot.summary and snapshot.summary.trackedMembers or 0,
        trackedOnline = snapshot.summary and snapshot.summary.trackedOnline or 0,
        excludedMembers = snapshot.summary and snapshot.summary.excludedMembers or 0,
        totalMembers = snapshot.summary and snapshot.summary.totalMembers or 0,
        changes = 0,
        pendingPrompts = countPendingPrompts(players),
    }

    GC.Services.DataStore:AppendScanSummary(summary)
    return summary
end

-- ApplyChanges: normal scan path. Updates records and appends change events.
function GC.Modules.RosterHistory:ApplyChanges(snapshot, changes, reason)
    local players = GC.DB:GetPlayers()
    if not players then return end

    local currentKeys = buildSnapshotMemberKeys(snapshot)

    -- Update every guild member present in the snapshot, including officers
    -- and other ranks outside the tracked intelligence scope.
    forEachSnapshotMember(snapshot, function(member)
        local record = ensurePlayerRecord(member)
        if record then
            updateMemberRecord(record, member, reason)
        end
    end)

    -- Process structural changes (joins, leaves, promotions, note edits).
    for _, change in ipairs(changes) do
        local record = players[change.playerKey]

        if change.type == "JOINED" then
            local member = snapshot.members[change.playerKey]
            if member then
                record = ensurePlayerRecord(member)
                if record then
                    record.status = "active"
                    local promptState = ensurePromptState(record)
                    promptState.dismissedAt = nil
                    promptState.bootstrapSuppressed = nil
                end
            end
        elseif change.type == "PROMOTED" or change.type == "DEMOTED" then
            if record then record.promotedAt = snapshot.takenAt end
        elseif change.type == "LEFT" then
            if record then record.status = "left" end
        elseif change.type == "UNTRACKED" then
            local member = snapshot.excluded and snapshot.excluded[change.playerKey]
            if record and member then
                record.rankName = member.rankName
                record.rankIndex = member.rankIndex
                record.status = "active"
                record.isTrackedRank = false
                record.lastRosterSeenAt = snapshot.takenAt
                record.lastScanReason = reason
            end
        end

        appendLog(change.type, change.playerKey, change.oldValue, change.newValue, reason)
    end

    for key, record in pairs(players) do
        if record.status == "active" and not currentKeys[key] then
            record.status = "left"
            record.lastScanReason = reason
        end
    end

    local summary = {
        timestamp = snapshot.takenAt,
        reason = reason,
        trackedMembers = snapshot.summary and snapshot.summary.trackedMembers or 0,
        trackedOnline = snapshot.summary and snapshot.summary.trackedOnline or 0,
        excludedMembers = snapshot.summary and snapshot.summary.excludedMembers or 0,
        totalMembers = snapshot.summary and snapshot.summary.totalMembers or 0,
        changes = #changes,
        pendingPrompts = countPendingPrompts(players),
    }

    GC.Services.DataStore:AppendScanSummary(summary)
    return summary
end

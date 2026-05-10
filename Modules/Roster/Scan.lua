-- /GuildCore/Modules/Roster/Scan.lua
local addonName, ns = ...
local GC = ns.GuildCore

GC.Modules.RosterScan = {}

function GC.Modules.RosterScan:Capture()
    local snapshot = {
        takenAt = GC.Utils.Now(),
        members = {},
        excluded = {},
        summary = {
            totalMembers = 0,
            trackedMembers = 0,
            trackedOnline = 0,
            excludedMembers = 0,
        },
        usedRankFallback = false,
    }

    GC.API.SetGuildRosterShowOffline(true)

    local totalMembers = GetNumGuildMembers()
    local totalRanks = GetNumGuildRanks and GetNumGuildRanks() or nil
    for index = 1, totalMembers do
        local fullName, rankName, rankIndex, level, classDisplayName, zone, publicNote, officerNote, isOnline, status, classFileName, achievementPoints, achievementRank, isMobile, canSoR, reputation, yearsOffline, monthsOffline, daysOffline, hoursOffline = GC.API.GetGuildRosterInfo(index)

        if fullName then
            local name, realm = GC.Utils.SplitGuildName(fullName)
            local key = GC.Utils.NormalizePlayerKey(name, realm)
            local parsedOfficerNote = GC.Utils.ParseOfficerNote(officerNote)
            local trackedByName = GC.Utils.IsTrackedRank(rankName)
            local trackedByIndex = GC.Utils.IsTrackedRankIndex(rankIndex, totalRanks)
            yearsOffline = tonumber(yearsOffline) or 0
            monthsOffline = tonumber(monthsOffline) or 0
            daysOffline = tonumber(daysOffline) or 0
            hoursOffline = tonumber(hoursOffline) or 0
            if not isOnline and yearsOffline == 0 and monthsOffline == 0 and daysOffline == 0 and hoursOffline == 0 and GC.API.GetGuildRosterLastOnline then
                local y, m, d, h = GC.API.GetGuildRosterLastOnline(index)
                yearsOffline = tonumber(y) or yearsOffline
                monthsOffline = tonumber(m) or monthsOffline
                daysOffline = tonumber(d) or daysOffline
                hoursOffline = tonumber(h) or hoursOffline
            end
            local offlineHours = isOnline and 0 or ((yearsOffline * 365 * 24) + (monthsOffline * 30 * 24) + (daysOffline * 24) + hoursOffline)
            local member = {
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
                officerData = parsedOfficerNote,
                isOnline = isOnline and true or false,
                capturedAt = snapshot.takenAt,
                isTrackedRank = trackedByName or trackedByIndex,
                yearsOffline = yearsOffline,
                monthsOffline = monthsOffline,
                daysOffline = daysOffline,
                hoursOffline = hoursOffline,
                offlineHours = offlineHours,
                offlineDays = math.floor(offlineHours / 24),
            }

            snapshot.summary.totalMembers = snapshot.summary.totalMembers + 1
            if member.isTrackedRank then
                snapshot.members[key] = member
                snapshot.summary.trackedMembers = snapshot.summary.trackedMembers + 1
                if member.isOnline then
                    snapshot.summary.trackedOnline = snapshot.summary.trackedOnline + 1
                end
            else
                snapshot.excluded[key] = member
                snapshot.summary.excludedMembers = snapshot.summary.excludedMembers + 1
            end
        end
    end

    -- Safety fallback: if the guild has members but none matched the target
    -- ranks, keep the addon usable by treating the live roster as tracked for
    -- this scan. This avoids an empty roster UI for guilds with custom or
    -- officer-only rank setups on a given client.
    if snapshot.summary.totalMembers > 0 and snapshot.summary.trackedMembers == 0 and snapshot.summary.excludedMembers > 0 then
        snapshot.members = snapshot.excluded
        snapshot.excluded = {}
        snapshot.summary.trackedMembers = snapshot.summary.totalMembers
        snapshot.summary.trackedOnline = 0
        snapshot.summary.excludedMembers = 0
        snapshot.usedRankFallback = true

        for _, member in pairs(snapshot.members) do
            if member.isOnline then
                snapshot.summary.trackedOnline = snapshot.summary.trackedOnline + 1
            end
            member.isTrackedRank = true
        end
    end

    return snapshot
end

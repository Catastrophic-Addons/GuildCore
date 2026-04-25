-- /GuildCore/Modules/Roster/Diff.lua
local addonName, ns = ...
local GC = ns.GuildCore

GC.Modules.RosterDiff = {}

function GC.Modules.RosterDiff:GetPreviousSnapshot()
    local guild = GC.DB:GetGuild()
    return guild and guild.snapshots.latest or nil
end

function GC.Modules.RosterDiff:StoreSnapshot(snapshot)
    local guild = GC.DB:GetGuild()
    if not guild then
        return
    end

    guild.snapshots.latest = snapshot
end

function GC.Modules.RosterDiff:Compare(newSnapshot)
    local oldSnapshot = self:GetPreviousSnapshot() or { members = {}, excluded = {} }
    local changes = {}

    for key, member in pairs(newSnapshot.members) do
        local oldMember = oldSnapshot.members[key]

        if not oldMember then
            changes[#changes + 1] = {
                type = "JOINED",
                playerKey = key,
                newValue = member.rankName,
            }
        else
            if oldMember.rankIndex ~= member.rankIndex then
                changes[#changes + 1] = {
                    type = member.rankIndex < oldMember.rankIndex and "PROMOTED" or "DEMOTED",
                    playerKey = key,
                    oldValue = oldMember.rankName,
                    newValue = member.rankName,
                }
            end

            if oldMember.publicNote ~= member.publicNote then
                changes[#changes + 1] = {
                    type = "PUBLIC_NOTE_CHANGED",
                    playerKey = key,
                }
            end

            if oldMember.officerNote ~= member.officerNote then
                changes[#changes + 1] = {
                    type = "OFFICER_NOTE_CHANGED",
                    playerKey = key,
                }
            end
        end
    end

    for key, oldMember in pairs(oldSnapshot.members) do
        if not newSnapshot.members[key] then
            local excludedMember = newSnapshot.excluded and newSnapshot.excluded[key]
            if excludedMember then
                if oldMember.rankIndex ~= excludedMember.rankIndex then
                    changes[#changes + 1] = {
                        type = excludedMember.rankIndex < oldMember.rankIndex and "PROMOTED" or "DEMOTED",
                        playerKey = key,
                        oldValue = oldMember.rankName,
                        newValue = excludedMember.rankName,
                    }
                end

                changes[#changes + 1] = {
                    type = "UNTRACKED",
                    playerKey = key,
                    oldValue = oldMember.rankName,
                    newValue = excludedMember.rankName,
                }
            else
                changes[#changes + 1] = {
                    type = "LEFT",
                    playerKey = key,
                    oldValue = oldMember.rankName,
                }
            end
        end
    end

    return changes
end

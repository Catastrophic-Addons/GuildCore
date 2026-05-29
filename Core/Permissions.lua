-- /GuildCore/Core/Permissions.lua
local addonName, ns = ...
local GC = ns.GuildCore

GC.Permissions = {}

function GC.Permissions:GetPlayerGuildRankIndex()
    local guildRankIndex = self:GetPlayerGuildRankInfo()
    return guildRankIndex
end

function GC.Permissions:GetPlayerGuildRankInfo()
    local guildName, guildRankName, guildRankIndex = GetGuildInfo("player")
    if not guildName then
        return nil
    end
    return guildRankIndex, guildRankName
end

function GC.Permissions:IsOfficerOrBetter()
    local settings = GC.DB:GetSettings()
    local threshold = settings.officerRankThreshold or 4
    local rankIndex = self:GetPlayerGuildRankIndex()
    return rankIndex ~= nil and rankIndex <= threshold
end

function GC.Permissions:CanInviteGuild()
    if not IsInGuild or not IsInGuild() then
        return false, "You are not in a guild."
    end

    if CanGuildInvite then
        local ok, allowed = pcall(CanGuildInvite)
        if ok then
            if allowed then
                return true
            end
            return false, "Your current guild permissions do not allow guild invites."
        end
    end

    if C_GuildInfo and C_GuildInfo.Invite then
        -- Modern clients may expose the invite call without a matching reliable
        -- permission predicate. The server is still authoritative, so the first
        -- real invite attempt must treat errors as permission/API feedback.
        return true, "Invite API is available, but permission requires server validation."
    end

    return false, "No guild invite API is available."
end

function GC.Permissions:CanManageRankIndex(targetRankIndex)
    if not self:IsOfficerOrBetter() then
        return false, "Officer rank required."
    end

    local actorRankIndex = self:GetPlayerGuildRankIndex()
    targetRankIndex = tonumber(targetRankIndex)
    if actorRankIndex == nil or targetRankIndex == nil then
        return false, "Guild rank data unavailable."
    end

    if targetRankIndex <= actorRankIndex then
        return false, "You may only manage members below your rank."
    end

    return true
end

function GC.Permissions:GetNoteEditAvailability(target)
    if not self:IsOfficerOrBetter() then
        return {
            enabled = false,
            protected = false,
            reason = "Officer permission required.",
        }
    end

    local actorRankIndex, actorRankName = self:GetPlayerGuildRankInfo()
    local targetRankIndex = tonumber(target and target.rankIndex)
    local targetRankName = target and target.rankName
    if (targetRankIndex == nil or targetRankName == nil) and target and GC.API and GC.API.FindGuildRosterIndex and GC.API.GetGuildRosterInfo then
        local rosterIndex = GC.API.FindGuildRosterIndex(target.key or target.name)
        if rosterIndex then
            local _, rosterRankName, rosterRankIndex = GC.API.GetGuildRosterInfo(rosterIndex)
            targetRankIndex = targetRankIndex or tonumber(rosterRankIndex)
            targetRankName = targetRankName or rosterRankName
        end
    end
    if actorRankIndex == nil or targetRankIndex == nil then
        return {
            enabled = true,
            protected = false,
            actorRankName = actorRankName,
            targetRankName = targetRankName,
            reason = "Guild rank data unavailable; Blizzard will validate note permissions when saving.",
        }
    end

    -- WoW rankIndex is 0 = Guild Master/highest. Note editing is checked
    -- independently from promote/demote permissions; same-rank or higher-rank
    -- targets may be protected by Blizzard even when other officer actions exist.
    local protected = targetRankIndex <= actorRankIndex
    return {
        enabled = not protected,
        protected = protected,
        actorRankIndex = actorRankIndex,
        actorRankName = actorRankName,
        targetRankIndex = targetRankIndex,
        targetRankName = targetRankName,
        reason = protected and "Your guild rank may not have permission to edit notes for members at this rank or higher." or nil,
    }
end

function GC.Permissions:CanPromoteRankIndex(targetRankIndex)
    local ok, err = self:CanManageRankIndex(targetRankIndex)
    if not ok then
        return false, err
    end

    local actorRankIndex = self:GetPlayerGuildRankIndex()
    targetRankIndex = tonumber(targetRankIndex)
    if actorRankIndex == nil or targetRankIndex == nil then
        return false, "Guild rank data unavailable."
    end

    if (targetRankIndex - 1) <= actorRankIndex then
        return false, "Promotion would place that member at or above your rank."
    end

    return true
end

function GC.Permissions:CanDemoteRankIndex(targetRankIndex)
    return self:CanManageRankIndex(targetRankIndex)
end

function GC.Permissions:CanKickRankIndex(targetRankIndex)
    if not (GC.API and GC.API.CanGuildRemove and GC.API.CanGuildRemove()) then
        return false, "Your current guild permissions do not allow removals."
    end

    return self:CanManageRankIndex(targetRankIndex)
end

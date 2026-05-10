-- /GuildCore/Core/Permissions.lua
local addonName, ns = ...
local GC = ns.GuildCore

GC.Permissions = {}

function GC.Permissions:GetPlayerGuildRankIndex()
    local guildName, guildRankName, guildRankIndex = GetGuildInfo("player")
    if not guildName then
        return nil
    end
    return guildRankIndex
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

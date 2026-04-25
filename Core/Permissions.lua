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
    return self:CanManageRankIndex(targetRankIndex)
end

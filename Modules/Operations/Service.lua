-- /GuildCore/Modules/Operations/Service.lua
local addonName, ns = ...
local GC = ns.GuildCore

local OperationsService = {}
OperationsService.__index = OperationsService

function OperationsService:SetGuildMOTD(message)
    if not GC.Permissions:IsOfficerOrBetter() then
        return false, "Insufficient permission"
    end

    GuildSetMOTD(message)
    return true
end

function OperationsService:BuildPromoteMacro(targetName)
    return string.format("/gpromote %s", targetName or "")
end

function OperationsService:BuildDemoteMacro(targetName)
    return string.format("/gdemote %s", targetName or "")
end

function OperationsService:BuildRemoveMacro(targetName)
    return string.format("/gremove %s", targetName or "")
end

function OperationsService:GetActionAvailability(player)
    if not player then
        return {
            isOfficer = false,
            promote = { enabled = false, reason = "No player selected." },
            demote = { enabled = false, reason = "No player selected." },
            kick = { enabled = false, reason = "No player selected." },
        }
    end

    local rankIndex = tonumber(player.rankIndex)
    local promoteOk, promoteReason = GC.Permissions:CanPromoteRankIndex(rankIndex)
    local demoteOk, demoteReason = GC.Permissions:CanDemoteRankIndex(rankIndex)
    local kickOk, kickReason = GC.Permissions:CanKickRankIndex(rankIndex)

    return {
        isOfficer = GC.Permissions:IsOfficerOrBetter(),
        promote = { enabled = promoteOk, reason = promoteReason },
        demote = { enabled = demoteOk, reason = demoteReason },
        kick = { enabled = kickOk, reason = kickReason },
    }
end

local function targetName(player)
    if not player then
        return nil
    end
    return player.name
end

function OperationsService:Promote(player)
    local availability = self:GetActionAvailability(player)
    if not availability.promote.enabled then
        return false, availability.promote.reason or "Promotion not allowed."
    end

    GC.API.GuildPromote(targetName(player))
    return true
end

function OperationsService:Demote(player)
    local availability = self:GetActionAvailability(player)
    if not availability.demote.enabled then
        return false, availability.demote.reason or "Demotion not allowed."
    end

    GC.API.GuildDemote(targetName(player))
    return true
end

function OperationsService:Kick(player)
    local availability = self:GetActionAvailability(player)
    if not availability.kick.enabled then
        return false, availability.kick.reason or "Removal not allowed."
    end

    GC.API.GuildUninvite(targetName(player))
    return true
end

GC:RegisterService("Operations", setmetatable({}, OperationsService))

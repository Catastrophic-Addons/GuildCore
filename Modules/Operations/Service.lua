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

local function debugRankOrder(...)
    GC:Debug(...)
end

local function normalizeNameForCompare(name)
    if not name or name == "" then
        return nil
    end
    local shortName = tostring(name):match("^([^%-]+)") or tostring(name)
    return string.lower(shortName)
end

local function extractRosterGuidFromTable(info)
    if type(info) ~= "table" then
        return nil
    end

    return info.guid
        or info.GUID
        or info.playerGUID
        or info.memberGUID
        or info.guildMemberGUID
        or info.clubMemberGUID
end

local function debugRosterInfoShape(index, info)
    if type(info) ~= "table" then
        debugRankOrder("C_GuildInfo.GetGuildRosterInfo shape:", tostring(index), type(info), tostring(info))
        return
    end

    local keys = {}
    for key, value in pairs(info) do
        keys[#keys + 1] = tostring(key) .. "=" .. tostring(value)
    end
    table.sort(keys)
    debugRankOrder("C_GuildInfo.GetGuildRosterInfo shape:", tostring(index), table.concat(keys, ", "))
end

local function findRosterGuid(player)
    if not player then
        return nil
    end

    local directGuid = player.guid or player.GUID or player.playerGUID or player.memberGUID
    if directGuid and directGuid ~= "" then
        return directGuid
    end

    if not GetNumGuildMembers then
        return nil
    end

    local target = normalizeNameForCompare(player.name)
    if not target then
        return nil
    end

    for index = 1, GetNumGuildMembers() do
        if C_GuildInfo and C_GuildInfo.GetGuildRosterInfo then
            local info = C_GuildInfo.GetGuildRosterInfo(index)
            if type(info) == "table" then
                local rosterName = info.name
                if normalizeNameForCompare(rosterName) == target then
                    debugRosterInfoShape(index, info)
                    local guid = extractRosterGuidFromTable(info)
                    if guid then
                        return guid
                    end
                end
            end
        end

        if GetGuildRosterInfo then
            local fullName, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, guid = GetGuildRosterInfo(index)
            if normalizeNameForCompare(fullName) == target then
                debugRankOrder("legacy GetGuildRosterInfo match:", tostring(index), tostring(fullName), "guid:", tostring(guid))
                if guid and guid ~= "" then
                    return guid
                end
            end
        end
    end

    return nil
end

local function trySetGuildRankOrder(player, direction, fallbackCommand)
    local guildInfo = C_GuildInfo
    local name = targetName(player) or "Unknown"
    local guid = findRosterGuid(player)
    local called = false

    debugRankOrder("target name:", name)
    debugRankOrder("target GUID:", tostring(guid))

    if not guildInfo
        or not guildInfo.GetGuildRankOrder
        or not guildInfo.IsGuildRankAssignmentAllowed
        or not guildInfo.SetGuildRankOrder then
        debugRankOrder("SetGuildRankOrder path unavailable; falling back to macro.")
        return false, "Rank order API unavailable."
    end

    if not guid then
        debugRankOrder("No roster GUID found; falling back to macro.")
        return false, "Target GUID unavailable."
    end

    local okCurrent, currentRankOrder = pcall(guildInfo.GetGuildRankOrder, guid)
    if not okCurrent then
        debugRankOrder("GetGuildRankOrder error:", tostring(currentRankOrder))
        return false, "Unable to read current guild rank order."
    end

    currentRankOrder = tonumber(currentRankOrder)
    local requestedRankOrder = currentRankOrder and (currentRankOrder + direction) or nil
    debugRankOrder("current rank order:", tostring(currentRankOrder))
    debugRankOrder("requested rank order:", tostring(requestedRankOrder))

    if not requestedRankOrder then
        return false, "Current guild rank order unavailable."
    end

    local okAllowed, allowed = pcall(guildInfo.IsGuildRankAssignmentAllowed, guid, requestedRankOrder)
    debugRankOrder("IsGuildRankAssignmentAllowed result:", tostring(okAllowed and allowed), okAllowed and "" or tostring(allowed))
    if not okAllowed or not allowed then
        debugRankOrder("SetGuildRankOrder called:", tostring(called))
        return false, "Guild rank assignment is not allowed."
    end

    local okSet, setResult = pcall(guildInfo.SetGuildRankOrder, guid, requestedRankOrder)
    called = okSet
    debugRankOrder("SetGuildRankOrder called:", tostring(called))
    if not okSet then
        debugRankOrder("SetGuildRankOrder error:", tostring(setResult))
        return false, "Guild rank assignment API was blocked."
    end

    if GC.Services and GC.Services.GuildService then
        C_Timer.After(1.5, function()
            GC.Services.GuildService:TriggerScan()
        end)
    end

    C_Timer.After(3, function()
        if not C_GuildInfo or not C_GuildInfo.GetGuildRankOrder then
            return
        end

        local okVerify, verifiedRankOrder = pcall(C_GuildInfo.GetGuildRankOrder, guid)
        verifiedRankOrder = tonumber(verifiedRankOrder)
        debugRankOrder("verified rank order after SetGuildRankOrder:", okVerify and tostring(verifiedRankOrder) or tostring(verifiedRankOrder))
        if okVerify and verifiedRankOrder == requestedRankOrder then
            debugRankOrder("SetGuildRankOrder verified:", name)
            return
        end

        debugRankOrder("SetGuildRankOrder not verified; falling back to macro:", tostring(fallbackCommand))
        if fallbackCommand and GC.Services and GC.Services.OperationsMacro then
            GC.Services.OperationsMacro:QueueRankAction(player, fallbackCommand, 1)
        end
    end)

    return true, string.format("Rank assignment API called for %s. Watching roster for confirmation.", name)
end

function OperationsService:Promote(player)
    local availability = self:GetActionAvailability(player)
    if not availability.promote.enabled then
        return false, availability.promote.reason or "Promotion not allowed."
    end

    -- Direct GuildPromote() calls are blocked by Blizzard restrictions in
    -- modern WoW. Queue a /gpromote macro line instead; the user must click the
    -- generated macro for the rank change to happen.
    return GC.Services.OperationsMacro:QueueRankAction(player, "/gpromote", 1)
end

function OperationsService:Demote(player)
    local availability = self:GetActionAvailability(player)
    if not availability.demote.enabled then
        return false, availability.demote.reason or "Demotion not allowed."
    end

    -- See Promote(): /gdemote has to be executed by a user-clicked macro.
    return GC.Services.OperationsMacro:QueueRankAction(player, "/gdemote", 1)
end

function OperationsService:Kick(player)
    local availability = self:GetActionAvailability(player)
    if not availability.kick.enabled then
        return false, availability.kick.reason or "Removal not allowed."
    end

    if not (GC.Services and GC.Services.Purge) then
        return false, "Purge service is unavailable."
    end

    return GC.Services.Purge:QueueManual(player, "Manual purge queued from player panel.")
end

GC:RegisterService("Operations", setmetatable({}, OperationsService))

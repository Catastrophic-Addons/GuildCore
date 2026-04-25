-- /GuildCore/Modules/Points/Service.lua
local addonName, ns = ...
local GC = ns.GuildCore

local PointsService = {}
PointsService.__index = PointsService

function PointsService:AddPoints(playerKey, amount, reason)
    local settings = GC.DB:GetSettings()
    if settings and settings.enablePointsModule == false then
        return false, "Points module is disabled"
    end

    local players = GC.DB:GetPlayers()
    local player = players and players[playerKey]
    if not player then
        return false, "Player not found"
    end

    amount = tonumber(amount)
    if not amount then
        return false, "Invalid amount"
    end

    player.points = player.points or {
        balance = 0,
        lifetime = 0,
        transactions = {},
    }

    player.points.balance  = player.points.balance  + amount
    player.points.lifetime = player.points.lifetime + math.max(amount, 0)

    table.insert(player.points.transactions, {
        timestamp = GC.Utils.Now(),
        amount    = amount,
        reason    = reason or "Manual adjustment",
    })

    local logs = GC.DB:GetLogs()
    if logs then
        logs[#logs + 1] = {
            timestamp = GC.Utils.Now(),
            event     = amount >= 0 and "POINTS_ADDED" or "POINTS_REMOVED",
            playerKey = playerKey,
            newValue  = amount,
            reason    = reason,
        }
    end

    return true
end

GC:RegisterService("Points", setmetatable({}, PointsService))

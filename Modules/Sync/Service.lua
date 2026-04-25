-- /GuildCore/Modules/Sync/Service.lua
local addonName, ns = ...
local GC = ns.GuildCore

local SyncService = {}
SyncService.__index = SyncService

function SyncService:IsEnabled()
    return GC.DB:GetSettings().enableSyncModule == true
end

function SyncService:QueueOutboundChange(payload)
    local guild = GC.DB:GetGuild()
    if not guild then
        return false
    end

    guild.sync.outboundQueue = guild.sync.outboundQueue or {}
    table.insert(guild.sync.outboundQueue, payload)
    return true
end

GC:RegisterService("Sync", setmetatable({}, SyncService))

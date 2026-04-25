-- /GuildCore/Core/Database.lua
local addonName, ns = ...
local GC = ns.GuildCore

GC.DB = {}

function GC.DB:Initialize()
    GuildCoreDB = GuildCoreDB or {}
    GC.Utils.MergeDefaults(GuildCoreDB, ns.Defaults)
    self.Root = GuildCoreDB
end

function GC.DB:GetRoot()
    return self.Root
end

function GC.DB:GetSettings()
    return self.Root.settings
end

function GC.DB:GetCurrentGuildKey()
    local guildName = GetGuildInfo("player")
    if not guildName then
        return nil
    end

    local realm = GetRealmName() or "UnknownRealm"
    realm = realm:gsub("%s+", "")
    return string.format("%s-%s", guildName, realm)
end

function GC.DB:GetGuild()
    local guildKey = self:GetCurrentGuildKey()
    if not guildKey then
        return nil
    end

    self.Root.guilds[guildKey] = self.Root.guilds[guildKey] or {
        settings = {},
        players = {},
        logs = {},
        bank = {
            entries = {},
            seenKeys = {},
            lastCapturedAt = nil,
        },
        snapshots = {},
        sync = {},
        scans = { history = {} },
        prompts = {},
        messageQueue = {},
        messages = {
            meta = {
                nextMessageId = 1,
                nextCategoryId = 1,
                selectedCategoryId = "general",
                selectedMessageId = nil,
                automationEnabled = false,
                autoSendDelaySeconds = 2,
                maxQueueSize = 25,
                previewTargetName = "",
                dailyTargetHour = 18,
                dailyTargetMinute = 0,
                lastJoinedName = nil,
            },
            categories = {},
            categoryOrder = {},
            messages = {},
            messageOrderByCategory = {},
        },
    }

    return self.Root.guilds[guildKey]
end

function GC.DB:GetPlayers()
    local guild = self:GetGuild()
    return guild and guild.players or nil
end

function GC.DB:GetLogs()
    local guild = self:GetGuild()
    return guild and guild.logs or nil
end

-- Returns the persisted UI state table (position, last panel, etc.)
-- Safe to call after Initialize(); never returns nil.
function GC.DB:GetUIState()
    if not self.Root then return {} end
    self.Root.ui = self.Root.ui or {}
    return self.Root.ui
end

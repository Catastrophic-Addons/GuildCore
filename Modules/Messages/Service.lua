local addonName, ns = ...
local GC = ns.GuildCore

-- All storage/history/category/template/queue/automation methods are defined in their
-- respective sub-modules (Storage, History, Categories, Templates, Queue, Automation),
-- which each add methods to ns.MessagesImpl before this file loads.
local MessagesService = ns.MessagesImpl
MessagesService.__index = MessagesService

local SUPPORTED_CHANNELS = {
    GUILD         = { key = "GUILD",          id = "GUILD",          label = "Guild",     chatPrefix = "/g ",    slashPrefix = "/g ",    requiresRecipient = false, risky = false },
    OFFICER       = { key = "OFFICER",        id = "OFFICER",        label = "Officer",   chatPrefix = "/o ",    slashPrefix = "/o ",    requiresRecipient = false, risky = true  },
    WHISPER       = { key = "WHISPER",        id = "WHISPER",        label = "Whisper",   chatPrefix = "/w ",    slashPrefix = "/w ",    requiresRecipient = true,  risky = false },
    SAY           = { key = "SAY",            id = "SAY",            label = "Say",       chatPrefix = "/s ",    slashPrefix = "/s ",    requiresRecipient = false, risky = false },
    YELL          = { key = "YELL",           id = "YELL",           label = "Yell",      chatPrefix = "/y ",    slashPrefix = "/y ",    requiresRecipient = false, risky = true  },
    PARTY         = { key = "PARTY",          id = "PARTY",          label = "Party",     chatPrefix = "/p ",    slashPrefix = "/p ",    requiresRecipient = false, risky = false },
    RAID          = { key = "RAID",           id = "RAID",           label = "Raid",      chatPrefix = "/raid ", slashPrefix = "/raid ", requiresRecipient = false, risky = true  },
    INSTANCE_CHAT = { key = "INSTANCE_CHAT",  id = "INSTANCE_CHAT",  label = "Instance",  chatPrefix = "/i ",    slashPrefix = "/i ",    requiresRecipient = false, risky = true  },
}

local CHANNEL_ALIASES = {
    INSTANCE = "INSTANCE_CHAT",
}

-- Shared helpers from Storage.lua
local trim      = ns.MessagesHelpers.trim
local copyTable = ns.MessagesHelpers.copyTable

local function normalizeChannelId(channelId)
    channelId = tostring(channelId or "GUILD"):upper()
    return CHANNEL_ALIASES[channelId] or channelId
end

-- Channel methods

function MessagesService:GetSupportedChannels()
    local channels = {
        SUPPORTED_CHANNELS.GUILD,
        SUPPORTED_CHANNELS.OFFICER,
        SUPPORTED_CHANNELS.WHISPER,
        SUPPORTED_CHANNELS.SAY,
        SUPPORTED_CHANNELS.YELL,
        SUPPORTED_CHANNELS.PARTY,
        SUPPORTED_CHANNELS.RAID,
        SUPPORTED_CHANNELS.INSTANCE_CHAT,
    }
    local rows = {}
    for _, channel in ipairs(channels) do
        rows[#rows + 1] = copyTable(channel)
    end
    return rows
end

function MessagesService:GetChannelInfo(channelKey)
    local channel = SUPPORTED_CHANNELS[normalizeChannelId(channelKey)]
    return channel and copyTable(channel) or nil
end

function MessagesService:GetSupportedChannel(channelId)
    return self:GetChannelInfo(channelId)
end

function MessagesService:IsSupportedChannel(channelKey)
    return SUPPORTED_CHANNELS[normalizeChannelId(channelKey)] ~= nil
end

function MessagesService:NormalizeChannel(channelKey)
    local normalized = normalizeChannelId(channelKey)
    return SUPPORTED_CHANNELS[normalized] and normalized or "GUILD"
end

function MessagesService:NormalizeTargetChannel(channelId)
    return self:NormalizeChannel(channelId)
end

function MessagesService:ValidateChannelOptions(options)
    if type(options) == "string" then
        options = { channel = options }
    end
    options = options or {}
    local normalized = normalizeChannelId(options.channel or options.target or options.channelKey or "GUILD")
    local channel = SUPPORTED_CHANNELS[normalized]
    if not channel then
        return false, "Unsupported target channel."
    end

    local recipient = trim(options.recipient)
    if channel.requiresRecipient and recipient == "" then
        return false, "Whisper recipient is required."
    end

    local normalizedOptions = {
        target    = channel.key,
        recipient = recipient ~= "" and recipient or nil,
    }
    return true, nil, copyTable(channel), normalizedOptions
end

function MessagesService:ValidateTargetChannel(channelId, recipient)
    return self:ValidateChannelOptions({
        target    = channelId,
        recipient = recipient,
    })
end

-- Placeholder delegation

function MessagesService:GetResolveContext(options)
    local storage = self:GetStorage()
    options = options or {}
    return {
        targetName       = trim(options.targetName    ~= nil and options.targetName    or (storage and storage.meta.previewTargetName or "")),
        newMemberName    = trim(options.newMemberName ~= nil and options.newMemberName or (storage and storage.meta.lastJoinedName   or "")),
        recipient        = trim(options.recipient or ""),
        rankName         = trim(options.rankName or ""),
        discordName      = trim(options.discordName or ""),
        dailyTargetHour   = options.dailyTargetHour   ~= nil and options.dailyTargetHour   or (storage and storage.meta.dailyTargetHour   or 18),
        dailyTargetMinute = options.dailyTargetMinute ~= nil and options.dailyTargetMinute or (storage and storage.meta.dailyTargetMinute or 0),
    }
end

function MessagesService:ResolvePlaceholderResult(text, options)
    local placeholderService = GC.Services.MessagePlaceholders
    if not placeholderService or not placeholderService.Resolve then
        return {
            text          = tostring(text or ""),
            warnings      = {},
            fallbackUsed  = false,
            unknown       = {},
        }
    end
    return placeholderService:Resolve(text, self:GetResolveContext(options))
end

function MessagesService:ResolvePlaceholders(text, options)
    local result = self:ResolvePlaceholderResult(text, options)
    return result.text or ""
end

function MessagesService:GetAvailablePlaceholders(options)
    local placeholderService = GC.Services.MessagePlaceholders
    if not placeholderService or not placeholderService.GetAvailablePlaceholders then
        return {}
    end
    return placeholderService:GetAvailablePlaceholders(self:GetResolveContext(options))
end

function MessagesService:FindUnknownPlaceholders(text)
    local placeholderService = GC.Services.MessagePlaceholders
    if not placeholderService or not placeholderService.FindUnknownPlaceholders then
        return {}
    end
    return placeholderService:FindUnknownPlaceholders(text)
end

function MessagesService:CaptureSystemMessage(message)
    local storage = self:GetStorage()
    local placeholderService = GC.Services.MessagePlaceholders
    if not storage or not placeholderService or not placeholderService.CaptureSystemMessage then
        return nil
    end
    local joinedName = placeholderService:CaptureSystemMessage(message)
    if joinedName and joinedName ~= "" then
        storage.meta.lastJoinedName = joinedName
    end
    return joinedName
end

-- Register singleton
local messagesInstance = setmetatable({}, MessagesService)
GC:RegisterService("Messages", messagesInstance)
GC:RegisterService("Messaging", messagesInstance)

local addonName, ns = ...
local GC = ns.GuildCore

local MessagesModule = {
    key = "messages",
    panelKey = "messaging",
    title = "Messages",
    settingKey = "enableMessagingModule",
}

function MessagesModule:IsEnabled()
    local settings = GC.DB and GC.DB.GetSettings and GC.DB:GetSettings()
    return not settings or settings.enableMessagingModule ~= false
end

GC:RegisterModule("Messages", MessagesModule)

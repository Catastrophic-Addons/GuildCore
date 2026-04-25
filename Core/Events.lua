-- /GuildCore/Core/Events.lua
local addonName, ns = ...
local GC = ns.GuildCore

GC.Events = CreateFrame("Frame")

-- Debounce flag: prevents a burst of GUILD_ROSTER_UPDATE events from triggering
-- multiple captures within 0.5 seconds.
local rosterUpdatePending = false
local loginScanRequested = false

-- Start the periodic auto-scan ticker, respecting the settings interval.
-- Only starts if enableRosterModule is not explicitly false.
local function startRosterTicker()
    local settings = GC.DB:GetSettings()
    if not settings then return end
    if settings.enableRosterModule == false then return end

    local minutes = settings.autoScanIntervalMinutes or 60
    local seconds = math.max(60, minutes * 60)

    if GC.State.rosterTicker then
        GC.State.rosterTicker:Cancel()
        GC.State.rosterTicker = nil
    end

    GC.State.rosterTicker = C_Timer.NewTicker(seconds, function()
        if IsInGuild() and GC.Services.Roster then
            -- Request a data refresh; capture will happen when GUILD_ROSTER_UPDATE fires.
            GC.API.SetGuildRosterShowOffline(true)
            GC.API.GuildRoster()
            GC.State.pendingScanReason = "ticker"
        end
    end)
end

local function requestLoginScan(reason)
    if loginScanRequested or not IsInGuild() then
        return
    end

    loginScanRequested = true
    GC.API.SetGuildRosterShowOffline(true)
    GC.API.GuildRoster()
    GC.State.pendingScanReason = reason or "login"
end

GC.Events:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == "Blizzard_GuildBankUI" then
            if GC.Services.GuildBank then
                GC.Services.GuildBank:EnsureHooks()
            end
            return
        end
        if loadedAddon == "Blizzard_Communities" or loadedAddon == "Blizzard_GuildUI" then
            if GC.UI and GC.UI.CommunityTab then
                GC.UI.CommunityTab:Initialize()
            end
            return
        end
        if loadedAddon ~= addonName then return end

        GC.DB:Initialize()
        GC.Migrations:Run()
        if GC.UI and GC.UI.Theme and GC.UI.Theme.ApplyConfiguredPreset then
            GC.UI.Theme:ApplyConfiguredPreset()
        end
        if GC.Services.GuildBank then
            GC.Services.GuildBank:EnsureHooks()
        end
        if GC.UI and GC.UI.MinimapButton then
            GC.UI.MinimapButton:Initialize()
        end
        if GC.UI and GC.UI.CommunityTab then
            GC.UI.CommunityTab:Initialize()
        end
        GC.State.initialized = true
        GC:Print("Loaded v" .. tostring(GC.Version))

    elseif event == "PLAYER_LOGIN" then
        if GC.UI and GC.UI.MinimapButton then
            GC.UI.MinimapButton:Initialize()
        end
        if GC.UI and GC.UI.CommunityTab then
            GC.UI.CommunityTab:Initialize()
        end
        C_Timer.After(1, function()
            requestLoginScan("login")
        end)
        startRosterTicker()
        -- MainFrame is NOT created here. It is created lazily on first Toggle().

    elseif event == "PLAYER_GUILD_UPDATE" then
        if IsInGuild() then
            requestLoginScan("guild-update")
            startRosterTicker()
        end

    elseif event == "GUILDBANKFRAME_OPENED" then
        if GC.Services.GuildBank then
            GC.Services.GuildBank:OnGuildBankOpened()
        end

    elseif event == "GUILDBANKFRAME_CLOSED" then
        if GC.Services.GuildBank then
            GC.Services.GuildBank:OnGuildBankClosed()
        end

    elseif event == "GUILDBANKLOG_UPDATE" then
        if GC.Services.GuildBank then
            GC.Services.GuildBank:OnGuildBankLogUpdate()
        end

    elseif event == "GUILD_ROSTER_UPDATE" then
        if not IsInGuild() or not GC.Services.Roster then
            GC.State.pendingScanReason = nil
            return
        end

        if not rosterUpdatePending then
            -- Consume and latch the pending reason immediately so a second
            -- GUILD_ROSTER_UPDATE within the debounce window does not clobber it.
            local reason = GC.State.pendingScanReason or "event"
            GC.State.pendingScanReason = nil

            rosterUpdatePending = true
            C_Timer.After(0.5, function()
                rosterUpdatePending = false
                if IsInGuild() and GC.Services.Roster then
                    GC.Services.Roster:RunScan(reason)
                end
            end)
        else
            -- Already inside the debounce window; discard stale pending reason.
            GC.State.pendingScanReason = nil
        end
    elseif event == "CHAT_MSG_SYSTEM" then
        local message = ...
        if GC.Services.Messages and GC.Services.Messages.CaptureSystemMessage then
            GC.Services.Messages:CaptureSystemMessage(message)
        end
    end
end)

GC.Events:RegisterEvent("ADDON_LOADED")
GC.Events:RegisterEvent("PLAYER_LOGIN")
GC.Events:RegisterEvent("PLAYER_GUILD_UPDATE")
GC.Events:RegisterEvent("GUILD_ROSTER_UPDATE")
GC.Events:RegisterEvent("GUILDBANKFRAME_OPENED")
GC.Events:RegisterEvent("GUILDBANKFRAME_CLOSED")
GC.Events:RegisterEvent("GUILDBANKLOG_UPDATE")
GC.Events:RegisterEvent("CHAT_MSG_SYSTEM")

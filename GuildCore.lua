-- /GuildCore/GuildCore.lua
local addonName, ns = ...

local GC = ns.GuildCore
if not GC then
    return
end

SLASH_GUILDCORE1 = "/guildcore"
SLASH_GUILDCORE2 = "/gc"

SlashCmdList["GUILDCORE"] = function(msg)
    msg = GC.Utils.Trim(msg or "")

    local fontCmd = msg == "font" and "" or msg:match("^font%s+(.+)$")
    if fontCmd ~= nil then
        local Th = GC.UI and GC.UI.Theme
        if not Th or not Th.GetFontThemeKeys then
            print("|cff4fd1c5Guild Core:|r Font themes are unavailable.")
            return
        end

        fontCmd = GC.Utils.Trim(fontCmd)
        if fontCmd == "" then
            print("|cff4fd1c5Guild Core:|r Current font theme:", Th.GetFontThemeName())
            print("|cff4fd1c5Guild Core:|r Available font themes:", table.concat(Th.GetFontThemeKeys(), ", "))
            return
        end

        local applied = Th.SetFontTheme(fontCmd)
        if GC.UI.MainFrame and GC.UI.MainFrame.ApplyTheme then
            GC.UI.MainFrame:ApplyTheme()
        end
        print("|cff4fd1c5Guild Core:|r Font theme set to " .. applied .. ".")
        return
    end

    if msg == "scan" then
        local ok, err = GC.Services.GuildService:TriggerScan()
        print("|cff4fd1c5Guild Core:|r " .. (ok and "Roster scan requested." or (err or "Unable to request scan.")))
        return
    end

    if msg == "debug" then
        local guildKey = GC.DB:GetCurrentGuildKey()
        print("|cff4fd1c5Guild Core:|r Guild key:", guildKey or "none")
        local s = GC.DB:GetSettings()
        print("|cff4fd1c5Guild Core:|r Debug mode:", s and s.debugMode and "on" or "off")
        return
    end

    -- Panel shortcuts: /gc roster, /gc log, /gc settings, /gc messages
    local panelMap = {
        roster = "roster",
        log = "log",
        settings = "settings",
        dashboard = "dashboard",
        messaging = "messaging",
        messages = "messaging",
    }
    if panelMap[msg] then
        GC.UI:Show()
        GC.UI:SetActivePanel(panelMap[msg])
        return
    end

    GC.UI:Toggle()
end

local addonName, ns = ...
local GC = ns.GuildCore

GC.Settings:RegisterCategory({
    id = "advanced",
    label = "Advanced",
    keywords = "sync experimental performance cache rebuild reset settings",
    build = function(S, parent, y)
        y = select(2, S:CreateSection(parent, "Officer Data Sync", y))
        _, y = S:CreateToggle(parent, y, { key = "sync.enabled", label = "Enable Officer Data Sync", description = "Allow compatible online Guild Core users to exchange approved moderation/member metadata.", default = false, onChange = function(value)
            GC.Services.DataStore:SetSetting("enableSyncModule", value == true)
        end })
        _, y = S:CreateToggle(parent, y, { key = "sync.autoOnLogin", label = "Auto-sync On Login", description = "Broadcast a sync discovery request shortly after login.", default = false })
        _, y = S:CreateToggle(parent, y, { key = "sync.autoOnPeerDetected", label = "Auto-sync On Peer Detection", description = "Start sync when another compatible Guild Core user is detected.", default = false })
        _, y = S:CreateToggle(parent, y, { key = "sync.showMessages", label = "Show Sync Chat Messages", description = "Print clear chat status when sync starts, completes, fails, or is skipped.", default = true })
        _, y = S:CreateToggle(parent, y, { key = "sync.debug", label = "Debug Sync Messages", description = "Print protocol and merge details for sync troubleshooting.", default = false })
        _, y = S:CreateButton(parent, y, { label = "Manual Sync Now", description = "Broadcast discovery and sync with compatible online Guild Core users.", buttonText = "Sync Now", onClick = function()
            if GC.Sync and GC.Sync.SyncNow then
                GC.Sync:SyncNow("manual")
            elseif GC.UI.MainFrame then
                GC.UI.MainFrame:SetStatus("Sync service is unavailable.", "textDanger")
            end
        end })

        y = select(2, S:CreateSection(parent, "Advanced Systems", y))
        _, y = S:CreateButton(parent, y, { label = "Rebuild Alt/Main Cache", description = "Run the AltMain repair pass against current saved roster data.", buttonText = "Rebuild", onClick = function()
            local count = GC.AltMain and GC.AltMain.Repair and GC.AltMain:Repair() or 0
            if GC.UI.MainFrame then GC.UI.MainFrame:SetStatus("Alt/Main repair complete: " .. tostring(count) .. " change(s).", "textWarn") end
        end })
        _, y = S:CreateButton(parent, y, { label = "Reset All Settings", description = "Restore global Guild Core settings to defaults.", buttonText = "Reset", danger = true, onClick = function()
            local settings = GC.Services.DataStore:GetSettings()
            for k, v in pairs(ns.Defaults.settings or {}) do settings[k] = v end
            if GC.UI and GC.UI.Theme then
                if settings.themePreset then GC.UI.Theme:ApplyPresetLive(settings.themePreset) end
                if settings.fontTheme then GC.UI.Theme.SetFontTheme(settings.fontTheme) end
            end
            if GC.UI and GC.UI.ApplyInviteHotkeys then GC.UI.ApplyInviteHotkeys() end
            if GC.UI and GC.UI.MainFrame and GC.UI.MainFrame.ApplyTheme then GC.UI.MainFrame:ApplyTheme() end
            if GC.UI.MainFrame then GC.UI.MainFrame:SetStatus("Settings reset to defaults.", "textWarn") end
            S:Refresh()
        end })
        return y
    end,
})

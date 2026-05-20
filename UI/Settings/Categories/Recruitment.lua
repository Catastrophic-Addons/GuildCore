local addonName, ns = ...
local GC = ns.GuildCore

GC.Settings:RegisterCategory({
    id = "recruitment",
    label = "Recruitment",
    keywords = "invite recruitment scan queue dry run ban book hotkey",
    build = function(S, parent, y)
        y = select(2, S:CreateSection(parent, "Invite Hotkeys", y))
        local applyHotkeys = function()
            if GC.UI and GC.UI.ApplyInviteHotkeys then GC.UI.ApplyInviteHotkeys() end
        end
        _, y = S:CreateInput(parent, y, { key = "inviteHotkey", label = "Invite Next Hotkey", description = "Key combination for Invite Next.", default = "CTRL-SHIFT-I", onChange = applyHotkeys })
        _, y = S:CreateInput(parent, y, { key = "inviteScanHotkey", label = "Invite Scan Hotkey", description = "Key combination for starting invite scans.", default = "CTRL-SHIFT-S", onChange = applyHotkeys })
        y = select(2, S:CreateSection(parent, "Recruitment Systems", y))
        _, y = S:CreateToggle(parent, y, { key = "enableInviteModule", label = "Enable Invite Module", description = "Enable invite scanning, queues, and recruitment workflows.", default = true })
        _, y = S:CreateToggle(parent, y, { key = "includeConnectedRealms", label = "Include Connected Realms", description = "Allow recruitment tools to include connected realms.", default = true })
        _, y = S:CreateToggle(parent, y, { key = "neverScanAllRealms", label = "Avoid All-Realm Scans", description = "Prefer safe targeted scans over expensive all-realm scans.", default = true })
        _, y = S:CreateToggle(parent, y, { key = "allowHomeRealmFallback", label = "Allow Home Realm Fallback", description = "Use the guild home realm when realm data is incomplete.", default = true })
        return y
    end,
})

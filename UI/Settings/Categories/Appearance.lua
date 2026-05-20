local addonName, ns = ...
local GC = ns.GuildCore
local function T() return GC.UI.Theme end

GC.Settings:RegisterCategory({
    id = "appearance",
    label = "Appearance",
    keywords = "theme font scale compact roster row height accent preview",
    build = function(S, parent, y)
        y = select(2, S:CreateSection(parent, "Theme", y))
        local themeOptions = {}
        for _, key in ipairs(T().GetPresetKeys and T():GetPresetKeys() or {}) do
            themeOptions[#themeOptions + 1] = { key = key, label = T():GetPresetLabel(key) }
        end
        _, y = S:CreateDropdown(parent, y, {
            key = "themePreset", label = "Theme", description = "Swap the Guild Core color palette.",
            options = themeOptions, default = "guildcore", onChange = function(value)
                T():ApplyPresetLive(value)
                if GC.UI.MainFrame and GC.UI.MainFrame.ApplyTheme then GC.UI.MainFrame:ApplyTheme() end
            end
        })
        local fontOptions = {}
        for _, key in ipairs(T().GetFontThemeKeys()) do
            fontOptions[#fontOptions + 1] = { key = key, label = key }
        end
        _, y = S:CreateDropdown(parent, y, {
            key = "fontTheme", label = "Font Theme", description = "Choose the typography set used across the addon.",
            options = fontOptions, default = "wowDefault", onChange = function(value)
                T().SetFontTheme(value)
                if GC.UI.MainFrame and GC.UI.MainFrame.ApplyTheme then GC.UI.MainFrame:ApplyTheme() end
            end
        })
        _, y = S:CreateToggle(parent, y, { key = "compactMode", label = "Compact UI", description = "Reserved for denser future layouts.", default = false })
        _, y = S:CreateInput(parent, y, { key = "uiScale", label = "UI Scale", description = "Preferred scale for future frame sizing controls.", numeric = true, min = 0.75, max = 1.4, default = 1 })
        _, y = S:CreateInput(parent, y, { key = "rosterRowHeight", label = "Roster Row Height", description = "Preferred roster row height for future roster density options.", numeric = true, min = 28, max = 48, default = 36 })
        y = select(2, S:CreateSection(parent, "Live Preview", y))
        local preview = CreateFrame("Frame", nil, parent)
        preview:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
        preview:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, y)
        preview:SetHeight(116)
        T().Bg(preview, T().c.panelAlt, T().c.border)
        T().Fs(preview, "subheader", "Guild Core", "textAccent"):SetPoint("TOPLEFT", 14, -14)
        T().Fs(preview, "body", "Readable officer tools with live theme and font styling.", "textSecond"):SetPoint("TOPLEFT", 14, -42)
        T().Fs(preview, "small", "Small detail text remains legible in dense panels.", "textDimmed"):SetPoint("TOPLEFT", 14, -68)
        return y - 130
    end,
})

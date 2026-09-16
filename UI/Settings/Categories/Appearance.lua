local addonName, ns = ...
local GC = ns.GuildCore
local function T() return GC.UI.Theme end

GC.Settings:RegisterCategory({
    id = "appearance",
    label = "Appearance",
    keywords = "theme font text size accessibility readable large scale compact roster row height accent preview vision",
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
            fontOptions[#fontOptions + 1] = { key = key, label = T().GetFontThemeLabel and T().GetFontThemeLabel(key) or key }
        end
        _, y = S:CreateDropdown(parent, y, {
            key = "fontTheme", label = "Font Theme", description = "Choose the typography set used across the addon.",
            options = fontOptions, default = "wowDefault", onChange = function(value)
                T().SetFontTheme(value)
                if GC.UI.MainFrame and GC.UI.MainFrame.ApplyTheme then GC.UI.MainFrame:ApplyTheme() end
            end
        })
        _, y = S:CreateDropdown(parent, y, {
            key = "textScale", label = "Text Size", description = "Increase text throughout Guild Core without enlarging the entire window.",
            options = {
                { key = 1, label = "Default" },
                { key = 1.15, label = "Large" },
                { key = 1.3, label = "Extra Large" },
            },
            default = 1,
            onChange = function(value)
                T().SetTextScale(value)
                if GC.UI.MainFrame and GC.UI.MainFrame.ApplyTheme then GC.UI.MainFrame:ApplyTheme() end
            end,
        })
        _, y = S:CreateInput(parent, y, {
            key = "uiScale", label = "UI Scale", description = "Scale the Guild Core window while preserving its layout.",
            numeric = true, min = 0.75, max = 1.25, default = 1, onChange = function()
                if GC.UI.MainFrame and GC.UI.MainFrame.ApplyScale then GC.UI.MainFrame:ApplyScale() end
            end,
        })
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

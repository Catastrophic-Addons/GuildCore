local addonName, ns = ...
local GC = ns.GuildCore
local function T() return GC.UI.Theme end

local function diagnosticsText()
    local settings = GC.Services and GC.Services.DataStore and GC.Services.DataStore:GetSettings() or {}
    local lines = {
        "Guild Core Diagnostics",
        "Version: " .. tostring(GC.Version or "dev"),
        "DB Version: " .. tostring(GuildCoreDB and GuildCoreDB.meta and GuildCoreDB.meta.dbVersion or "unknown"),
        "Theme: " .. tostring(settings.themePreset or "guildcore"),
        "Font: " .. tostring(settings.fontTheme or "wowDefault"),
        "Roster: " .. tostring(settings.enableRosterModule ~= false),
        "Invite: " .. tostring(settings.enableInviteModule ~= false),
        "Debug: " .. tostring(settings.debugMode == true),
    }
    return table.concat(lines, " | ")
end

GC.Settings:RegisterCategory({
    id = "about",
    label = "About",
    keywords = "about version credits author diagnostics export community discord",
    build = function(S, parent, y)
        local Th = T()
        y = select(2, S:CreateSection(parent, "Guild Core", y))

        local card = S:CreateCard(parent, y, "Guild Core", "Modern guild management suite for World of Warcraft.", 118)
        local version = Th.Fs(card, "body", "Version " .. tostring(GC.Version or "dev"), "textAccent")
        version:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -54)
        local credits = Th.Fs(card, "small", "Author: Catastrophie", "textDimmed")
        credits:SetPoint("TOPLEFT", version, "BOTTOMLEFT", 0, -8)
        y = y - 126

        y = select(2, S:CreateSection(parent, "Diagnostics", y))
        _, y = S:CreateButton(parent, y, {
            label = "Export Diagnostics",
            description = "Open a chat line with a compact diagnostics summary for support or bug reports.",
            buttonText = "Export",
            onClick = function()
                if ChatFrame_OpenChat then
                    ChatFrame_OpenChat(diagnosticsText())
                elseif GC.Print then
                    GC:Print(diagnosticsText())
                end
            end,
        })
        return y
    end,
})

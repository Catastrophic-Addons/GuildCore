local addonName, ns = ...
local GC = ns.GuildCore

GC.Settings:RegisterCategory({
    id = "roster",
    label = "Roster",
    keywords = "roster scan profile portrait connected count first seen",
    build = function(S, parent, y)
        y = select(2, S:CreateSection(parent, "Roster Tracking", y))
        _, y = S:CreateToggle(parent, y, { key = "enableRosterModule", label = "Enable Roster Tracking", description = "Track guild joins, leaves, ranks, and roster profile data.", default = true })
        _, y = S:CreateInput(parent, y, { key = "autoScanIntervalMinutes", label = "Auto-scan Interval", description = "Minutes between automatic roster scans.", numeric = true, min = 5, max = 720, default = 60 })
        _, y = S:CreateToggle(parent, y, { key = "enableClassificationPrompts", label = "First-seen Classification Prompts", description = "Prompt officers to classify newly detected members.", default = true })
        y = select(2, S:CreateSection(parent, "Profile Display", y))
        _, y = S:CreateToggle(parent, y, { key = "profilePortraits", label = "Profile Portraits", description = "Show 2D portraits or class fallback icons in the roster profile.", default = true })
        _, y = S:CreateInput(parent, y, { key = "rosterFontSize", label = "Roster Font Size", description = "Preferred roster table font size for future readability controls.", numeric = true, min = 10, max = 18, default = 13 })
        _, y = S:CreateToggle(parent, y, { key = "showConnectedCharacterCount", label = "Connected Character Count", description = "Show a compact connected-character count in roster profiles.", default = true })
        return y
    end,
})

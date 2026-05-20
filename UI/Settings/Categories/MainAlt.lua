local addonName, ns = ...
local GC = ns.GuildCore

GC.Settings:RegisterCategory({
    id = "mainalt",
    label = "Main / Alt",
    keywords = "main alt linked characters classification prompts cross main detection",
    build = function(S, parent, y)
        y = select(2, S:CreateSection(parent, "Main / Alt Tracking", y))
        _, y = S:CreateToggle(parent, y, { key = "enableAltTracking", label = "Enable Alt Tracking", description = "Enable main/alt relationship tools and connected character groups.", default = true })
        _, y = S:CreateToggle(parent, y, { key = "enableClassificationPrompts", label = "Classification Prompts", description = "Prompt officers to classify first-seen tracked members.", default = true })
        _, y = S:CreateToggle(parent, y, { key = "mainAltCrossMainDetection", label = "Cross-main Detection", description = "Warn when linked characters appear split across multiple mains.", default = true })
        _, y = S:CreateToggle(parent, y, { key = "mainAltEnforceSingleMain", label = "Prefer One Main Per Group", description = "Use the shared AltMain resolver to normalize linked groups around one main.", default = true })
        return y
    end,
})

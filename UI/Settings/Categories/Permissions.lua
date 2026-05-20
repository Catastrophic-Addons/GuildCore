local addonName, ns = ...
local GC = ns.GuildCore

GC.Settings:RegisterCategory({
    id = "permissions",
    label = "Permissions",
    keywords = "officer threshold permissions restricted actions",
    build = function(S, parent, y)
        y = select(2, S:CreateSection(parent, "Officer Permissions", y))
        _, y = S:CreateInput(parent, y, { key = "officerRankThreshold", label = "Officer Rank Threshold", description = "Members at or above this rank index are treated as officers. Rank 0 is Guild Master.", numeric = true, min = 0, max = 9, default = 4 })
        _, y = S:CreateToggle(parent, y, { key = "restrictDangerActions", label = "Restrict Dangerous Actions", description = "Require officer permission checks for destructive workflows.", default = true })
        return y
    end,
})

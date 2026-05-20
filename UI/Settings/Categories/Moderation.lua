local addonName, ns = ...
local GC = ns.GuildCore

GC.Settings:RegisterCategory({
    id = "moderation",
    label = "Moderation",
    keywords = "compliance public officer note join date discord verification rank main alt ban book",
    build = function(S, parent, y)
        y = select(2, S:CreateSection(parent, "Compliance Checks", y))
        _, y = S:CreateToggle(parent, y, { key = "complianceCheckPublicNote", label = "Public Notes", description = "Flag active members missing public notes.", default = true })
        _, y = S:CreateToggle(parent, y, { key = "complianceCheckOfficerNote", label = "Officer Notes", description = "Flag active members missing officer notes.", default = true })
        _, y = S:CreateToggle(parent, y, { key = "complianceCheckJoinDate", label = "Join Dates", description = "Flag active members missing join dates.", default = true })
        _, y = S:CreateToggle(parent, y, { key = "complianceCheckDiscordName", label = "Discord Names", description = "Flag active members missing Discord names.", default = true })
        _, y = S:CreateToggle(parent, y, { key = "complianceCheckDiscordVerification", label = "Discord Verification", description = "Flag active members not marked as Discord verified.", default = true })
        _, y = S:CreateToggle(parent, y, { key = "complianceCheckRank", label = "Linked-character Ranks", description = "Flag linked groups where alts have different guild ranks.", default = true })
        _, y = S:CreateToggle(parent, y, { key = "complianceCheckMainAlt", label = "Main/Alt Structure", description = "Flag split linked groups with multiple mains.", default = true })
        return y
    end,
})

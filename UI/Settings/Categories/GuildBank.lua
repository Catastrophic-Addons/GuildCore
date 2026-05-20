local addonName, ns = ...
local GC = ns.GuildCore

GC.Settings:RegisterCategory({
    id = "guildbank",
    label = "Guild Bank",
    keywords = "guild bank donation logging capture",
    build = function(S, parent, y)
        y = select(2, S:CreateSection(parent, "Guild Bank", y))
        _, y = S:CreateToggle(parent, y, { key = "enableGuildBankModule", label = "Guild Bank Log Capture", description = "Capture visible guild bank item and money logs.", default = true })
        _, y = S:CreateToggle(parent, y, { key = "guildBankDonationTracking", label = "Donation Tracking", description = "Reserved for future bank donation workflows.", default = false })
        return y
    end,
})

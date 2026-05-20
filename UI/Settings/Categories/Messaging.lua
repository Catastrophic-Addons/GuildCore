local addonName, ns = ...
local GC = ns.GuildCore

GC.Settings:RegisterCategory({
    id = "messaging",
    label = "Messaging",
    keywords = "messaging welcome batch template chat",
    build = function(S, parent, y)
        y = select(2, S:CreateSection(parent, "Messaging", y))
        _, y = S:CreateToggle(parent, y, { key = "enableMessagingModule", label = "Enable Messaging System", description = "Enable queued guild-wide messaging tools.", default = true })
        _, y = S:CreateToggle(parent, y, { key = "enableWelcomeBatch", label = "Batched Welcome Messages", description = "Collect new guild joins and send one welcome after the batch window.", default = true })
        _, y = S:CreateInput(parent, y, { key = "welcomeBatchWindowSeconds", label = "Welcome Batch Window", description = "Seconds to collect new joins before sending the welcome.", numeric = true, min = 15, default = 180 })
        _, y = S:CreateInput(parent, y, { key = "welcomeMessageTemplate", label = "Welcome Template", description = "Use {names} where new member names should appear.", width = 300, default = "Welcome to the guild, {names}! Glad to have you aboard!" })
        return y
    end,
})

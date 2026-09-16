local addonName, ns = ...
local GC = ns.GuildCore

GC.Settings:RegisterCategory({
    id = "messaging",
    label = "Messaging",
    keywords = "messaging welcome batch template chat",
    build = function(S, parent, y)
        y = select(2, S:CreateSection(parent, "Messaging", y))
        _, y = S:CreateToggle(parent, y, { key = "enableMessagingModule", label = "Enable Messaging System", description = "Enable saved messages and guild communication tools.", default = true })
        _, y = S:CreateToggle(parent, y, { key = "enableWelcomeBatch", label = "Automatic Member Welcome", description = "Send one welcome when a new member joins.", default = true })
        _, y = S:CreateDropdown(parent, y, {
            key = "welcomeMessageChannel", label = "Welcome Destination", description = "Choose whether each welcome appears in guild chat or is sent privately.",
            options = {
                { key = "GUILD", label = "Guild Chat" },
                { key = "WHISPER", label = "Private Whisper" },
            },
            default = "GUILD", width = 170,
        })
        _, y = S:CreateInput(parent, y, { key = "welcomeIndividualDelaySeconds", label = "Welcome Delay", description = "Seconds to wait for the guild roster to settle before welcoming the member.", numeric = true, min = 1, default = 3 })
        _, y = S:CreateInput(parent, y, { key = "welcomeMessageTemplate", label = "Welcome Message", description = "Use {name} where the new member's name should appear.", width = 300, default = "Welcome to the guild, {name}! Glad to have you with us!" })
        return y
    end,
})

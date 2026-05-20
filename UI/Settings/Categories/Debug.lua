local addonName, ns = ...
local GC = ns.GuildCore

GC.Settings:RegisterCategory({
    id = "debug",
    label = "Debug",
    keywords = "debug verbose logging events tracing overlays diagnostics",
    build = function(S, parent, y)
        y = select(2, S:CreateSection(parent, "Logging", y))
        _, y = S:CreateToggle(parent, y, { key = "debugMode", label = "Debug Mode", description = "Print Guild Core debug messages when modules emit diagnostic output.", default = false })
        _, y = S:CreateToggle(parent, y, { key = "verboseLogging", label = "Verbose Logging", description = "Include additional details in debug output for deeper troubleshooting.", default = false })
        _, y = S:CreateToggle(parent, y, { key = "eventTracing", label = "Event Tracing", description = "Trace important WoW and Guild Core events as they are handled.", default = false })
        y = select(2, S:CreateSection(parent, "Visual Debugging", y))
        _, y = S:CreateToggle(parent, y, { key = "debugOverlays", label = "Debug Overlays", description = "Reserved for frame boundary and layout overlays during UI development.", default = false })
        return y
    end,
})

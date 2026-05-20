local addonName, ns = ...
local GC = ns.GuildCore

GC.Settings:RegisterCategory({
    id = "points",
    label = "Points",
    keywords = "points dkp attendance",
    build = function(S, parent, y)
        y = select(2, S:CreateSection(parent, "Points", y))
        _, y = S:CreateToggle(parent, y, { key = "enablePointsModule", label = "Enable Points System", description = "Allow officers to award and deduct points.", default = true })
        _, y = S:CreateInput(parent, y, { key = "defaultAttendancePoints", label = "Default Attendance Points", description = "Reserved default value for attendance-style awards.", numeric = true, default = 0 })
        return y
    end,
})

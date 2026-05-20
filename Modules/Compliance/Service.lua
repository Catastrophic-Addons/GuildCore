-- /GuildCore/Modules/Compliance/Service.lua
-- Officer-configurable roster hygiene checks.
local addonName, ns = ...
local GC = ns.GuildCore

GC.Services = GC.Services or {}

local Compliance = {}
Compliance.__index = Compliance

local CHECKS = {
    publicNote = "Public note",
    officerNote = "Officer note",
    joinDate = "Join date",
    discordName = "Discord name",
    discordVerified = "Discord verification",
    rank = "Rank consistency",
    mainAlt = "Main/Alt structure",
}

local SETTING_KEYS = {
    publicNote = "complianceCheckPublicNote",
    officerNote = "complianceCheckOfficerNote",
    joinDate = "complianceCheckJoinDate",
    discordName = "complianceCheckDiscordName",
    discordVerified = "complianceCheckDiscordVerification",
    rank = "complianceCheckRank",
    mainAlt = "complianceCheckMainAlt",
}

local function trim(value)
    return GC.Utils and GC.Utils.Trim and GC.Utils.Trim(value or "") or tostring(value or ""):match("^%s*(.-)%s*$")
end

local function enabled(settings, check)
    local key = SETTING_KEYS[check]
    return settings and settings[key] ~= false
end

local function addIssue(issues, player, check, message)
    issues[#issues + 1] = {
        key = player and player.key,
        name = player and (player.key or player.name) or "-",
        check = CHECKS[check] or check,
        message = message,
    }
end

local function activePlayers()
    local players = GC.Services.DataStore:GetPlayers() or {}
    local list = {}
    for _, player in pairs(players) do
        if player.status == "active" then
            list[#list + 1] = player
        end
    end
    table.sort(list, function(a, b) return tostring(a.key or a.name) < tostring(b.key or b.name) end)
    return list
end

local function groupSignature(group)
    local members = {}
    for _, key in ipairs(group and group.members or {}) do
        members[#members + 1] = key
    end
    table.sort(members)
    return table.concat(members, "|")
end

function Compliance:Run()
    if GC.AltMain and GC.AltMain.Repair then
        GC.AltMain:Repair()
    end

    local settings = GC.Services.DataStore:GetSettings() or {}
    local issues = {}
    local players = activePlayers()
    local groups = {}

    for _, player in ipairs(players) do
        if enabled(settings, "publicNote") and trim(player.publicNote) == "" then
            addIssue(issues, player, "publicNote", "Public note is missing.")
        end
        if enabled(settings, "officerNote") and trim(player.officerNote) == "" then
            addIssue(issues, player, "officerNote", "Officer note is missing.")
        end
        if enabled(settings, "joinDate") and not (player.joinedAt or (player.officerData and player.officerData.joinDate)) then
            addIssue(issues, player, "joinDate", "Join date is missing.")
        end
        if enabled(settings, "discordName") and trim(player.officerData and player.officerData.discordName) == "" then
            addIssue(issues, player, "discordName", "Discord name is missing.")
        end
        if enabled(settings, "discordVerified") and not (player.officerData and player.officerData.discordVerified == true) then
            addIssue(issues, player, "discordVerified", "Discord verification is missing.")
        end

        if GC.AltMain and GC.AltMain.GetGroup then
            local group = GC.AltMain:GetGroup(player.key)
            local signature = groupSignature(group)
            if signature ~= "" and not groups[signature] then
                groups[signature] = group
            end
        end
    end

    for _, group in pairs(groups) do
        local members = group.members or {}
        if #members > 1 then
            if enabled(settings, "rank") then
                local rankIndex, rankName
                for _, key in ipairs(members) do
                    local player = GC.Services.DataStore:GetPlayer(key)
                    if player then
                        rankIndex = rankIndex or player.rankIndex
                        rankName = rankName or player.rankName
                        if player.rankIndex ~= rankIndex or player.rankName ~= rankName then
                            addIssue(issues, player, "rank", "Linked group has mixed guild ranks.")
                            break
                        end
                    end
                end
            end

            if enabled(settings, "mainAlt") then
                local mains = {}
                for _, key in ipairs(members) do
                    local player = GC.Services.DataStore:GetPlayer(key)
                    if player and ((player.classification == "main") or (player.alts and #player.alts > 0)) then
                        mains[#mains + 1] = key
                    end
                end
                if #mains > 1 then
                    addIssue(issues, GC.Services.DataStore:GetPlayer(group.selectedKey or group.mainKey), "mainAlt",
                        "Linked group has multiple mains: " .. table.concat(mains, ", "))
                end
            end
        end
    end

    local lines = {
        "Guild Core Compliance Check",
        date("%Y-%m-%d %H:%M"),
        "",
        "Checks enabled:",
    }
    for check, label in pairs(CHECKS) do
        if enabled(settings, check) then
            lines[#lines + 1] = "- " .. label
        end
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Findings: " .. tostring(#issues)
    lines[#lines + 1] = ""
    for _, issue in ipairs(issues) do
        lines[#lines + 1] = string.format("%s | %s | %s", issue.name or "-", issue.check or "-", issue.message or "-")
    end
    if #issues == 0 then
        lines[#lines + 1] = "No compliance issues found."
    end

    return {
        issues = issues,
        text = table.concat(lines, "\n"),
        count = #issues,
    }
end

GC:RegisterService("Compliance", setmetatable({}, Compliance))

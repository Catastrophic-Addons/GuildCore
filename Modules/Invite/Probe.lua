-- /GuildCore/Modules/Invite/Probe.lua
-- Temporary Phase 1 probe for Midnight/Retail guild invite and WHO API behavior.
local addonName, ns = ...
local GC = ns.GuildCore

GC.Modules.Invite = GC.Modules.Invite or {}

local Probe = {}
Probe.__index = Probe

local function available(value)
    return value and "|cff7CFC00yes|r" or "|cffff6666no|r"
end

local function safeText(value)
    local ok, text = pcall(tostring, value)
    if ok then
        return text
    end
    return "<unprintable message>"
end

local function printLine(...)
    GC:Print(...)
end

local function debugLine(...)
    GC:InviteDebug("debug", ...)
end

local function warnLine(...)
    GC:InviteDebug("warn", ...)
end

function Probe:PrintInviteDebug(name)
    self:ArmInviteEventWindow()

    local normalized = GC.API.NormalizePlayerName(name or UnitName("player") or "")
    local apiName = GC.API.FormatNameForGuildInvite(normalized or name or "")
    local canInvite, inviteReason = GC.Permissions:CanInviteGuild()

    printLine("Invite debug:")
    printLine("  C_GuildInfo.Invite:", available(C_GuildInfo and C_GuildInfo.Invite))
    printLine("  GuildInvite:", available(GuildInvite))
    printLine("  CanGuildInvite:", available(CanGuildInvite))
    printLine("  IsInGuild:", available(IsInGuild and IsInGuild()))
    printLine("  Permission:", canInvite and "allowed/unknown" or "blocked", inviteReason or "")
    printLine("  Canonical name:", normalized or "n/a")
    printLine("  API-call name:", apiName or "n/a")
    printLine("  No invite was sent. This command only reports API availability.")
end

function Probe:PrintWhoDebug()
    printLine("WHO debug:")
    printLine("  C_FriendList.SendWho:", available(C_FriendList and C_FriendList.SendWho))
    printLine("  C_FriendList.GetWhoInfo:", available(C_FriendList and C_FriendList.GetWhoInfo))
    printLine("  C_FriendList.GetNumWhoResults:", available(C_FriendList and C_FriendList.GetNumWhoResults))
    printLine("  C_FriendList.SetWhoToUi:", available(C_FriendList and C_FriendList.SetWhoToUi))
    printLine("  WHO_LIST_UPDATE event:", available(true))
end

function Probe:StartWhoProbe(query)
    query = GC.Utils.Trim(query or "")
    if query == "" then
        local level = UnitLevel and UnitLevel("player") or 1
        local low = math.max(1, tonumber(level or 1) - 2)
        local high = math.max(low, tonumber(level or 1) + 2)
        query = tostring(low) .. "-" .. tostring(high)
    end

    if GC.Services.InviteScanner and GC.Services.InviteScanner.IsScanning and GC.Services.InviteScanner:IsScanning() then
        printLine("WHO probe refused: invite scanner is already active.")
        return false, "Invite scanner is already active."
    end

    self:PrintWhoDebug()

    if self.whoTimer then
        self.whoTimer:Cancel()
        self.whoTimer = nil
    end

    self.activeWhoQuery = query
    self.lastWhoStartedAt = GetTime and GetTime() or 0

    -- Force WHO_LIST_UPDATE for the probe so results are observable through the
    -- event path. This may briefly involve Blizzard's Who UI; reset afterward.
    GC.API.SetWhoToUi(true)
    local ok, err = GC.API.SendWho(query)
    if not ok then
        self.activeWhoQuery = nil
        printLine("WHO probe failed:", err or "unknown error")
        return false, err
    end

    printLine("WHO probe sent:", query)
    local probe = self
    self.whoTimer = C_Timer.NewTimer(12, function()
        if probe.activeWhoQuery == query then
            probe.activeWhoQuery = nil
            probe.whoTimer = nil
            GC.API.SetWhoToUi(false)
            printLine("WHO probe timed out. This can happen when the server throttles WHO queries.")
        end
    end)

    return true
end

function Probe:OnWhoListUpdate()
    local query = self.activeWhoQuery
    if not query then
        return
    end

    if self.whoTimer then
        self.whoTimer:Cancel()
        self.whoTimer = nil
    end
    self.activeWhoQuery = nil
    GC.API.SetWhoToUi(false)

    C_Timer.After(0.2, function()
        local total, shown = GC.API.GetNumWhoResults()
        printLine(string.format("WHO probe result for '%s': total=%d shown=%d", query, total or 0, shown or 0))

        local limit = math.min(tonumber(shown) or 0, 5)
        for index = 1, limit do
            local info = GC.API.GetWhoInfo(index)
            if type(info) == "table" then
                printLine(string.format(
                    "  %d. %s lvl %s %s zone=%s guild=%s",
                    index,
                    safeText(info.name or "unknown"),
                    safeText(info.level or "?"),
                    safeText(info.class or ""),
                    safeText(info.zone or ""),
                    safeText(info.guild or "")
                ))
            else
                printLine("  " .. tostring(index) .. ". " .. safeText(info))
            end
        end
    end)
end

function Probe:CaptureSystemMessage(message)
    if not self.lastInviteDebugAt then
        return
    end

    if (GetTime and GetTime() or 0) - self.lastInviteDebugAt > 20 then
        self.lastInviteDebugAt = nil
        return
    end

    debugLine("Invite/system event:", safeText(message))
end

function Probe:CaptureUIError(errorType, message)
    if self.activeWhoQuery then
        warnLine("WHO UI error:", safeText(errorType), safeText(message))
        return
    end

    if not self.lastInviteDebugAt then
        return
    end

    if (GetTime and GetTime() or 0) - self.lastInviteDebugAt > 20 then
        self.lastInviteDebugAt = nil
        return
    end

    warnLine("Invite UI error:", safeText(errorType), safeText(message))
end

function Probe:ArmInviteEventWindow()
    self.lastInviteDebugAt = GetTime and GetTime() or 0
end

GC.Modules.Invite.Probe = setmetatable({}, Probe)
GC:RegisterService("InviteProbe", GC.Modules.Invite.Probe)

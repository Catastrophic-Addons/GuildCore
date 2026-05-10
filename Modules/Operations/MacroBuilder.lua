-- /GuildCore/Modules/Operations/MacroBuilder.lua
-- Builds user-executed guild action macros.
--
-- Blizzard locked direct GuildPromote()/GuildDemote() execution behind protected
-- user actions in Patch 7.3+. The supported addon path is to write slash
-- commands into a macro, then let the player click that macro.
local addonName, ns = ...
local GC = ns.GuildCore

local MacroBuilder = {}
MacroBuilder.__index = MacroBuilder
local MacroBuilderInstance

local MACRO_NAME = "GuildCore_Action"
local MACRO_ICON = "INV_Misc_Note_01"
local MACRO_LIMIT = 255
local DEFAULT_HOTKEY = "CTRL-SHIFT-K"

local function debugPrint(...)
    GC:Debug(...)
end

local function shortName(name)
    if not name then
        return nil
    end
    return tostring(name):match("^([^%-]+)") or tostring(name)
end

local function printableName(playerOrName)
    if type(playerOrName) == "table" then
        local name = playerOrName.name
        if name and not string.find(name, "-", 1, true) then
            local realm = playerOrName.realm or GetRealmName()
            if realm and realm ~= "" then
                name = name .. "-" .. realm:gsub("%s+", "")
            end
        end
        return name
    end
    return playerOrName
end

local function expectedRankIndex(playerOrName, command, jumps)
    if type(playerOrName) ~= "table" then
        return nil
    end

    local rankIndex = tonumber(playerOrName.rankIndex)
    if not rankIndex then
        return nil
    end

    if command == "/gpromote" then
        return rankIndex - jumps
    elseif command == "/gdemote" then
        return rankIndex + jumps
    end
    return nil
end

local function copyQueue(queue)
    local result = {}
    for i = 1, #queue do
        local item = queue[i]
        result[i] = {
            name = item.name,
            command = item.command,
            jumps = item.jumps,
            key = item.key,
            expectedRankIndex = item.expectedRankIndex,
        }
    end
    return result
end

local function getMacroIndex()
    if GetMacroIndexByName then
        local index = GetMacroIndexByName(MACRO_NAME)
        if index and index > 0 then
            return index
        end
    end
    return nil
end

local function getMacroBody()
    if not GetMacroBody then
        return nil
    end

    local index = getMacroIndex()
    if index then
        return GetMacroBody(index)
    end

    return GetMacroBody(MACRO_NAME)
end

local function debugList(label, list)
    local parts = {}
    for i = 1, #(list or {}) do
        local item = list[i]
        if type(item) == "table" then
            parts[#parts + 1] = string.format("%d:%s %s x%s", i, tostring(item.command), tostring(item.name), tostring(item.jumps or 1))
        else
            parts[#parts + 1] = string.format("%d:%s", i, tostring(item))
        end
    end
    debugPrint(label, #parts > 0 and table.concat(parts, " | ") or "(empty)")
end

local function canCreateMacro()
    if not GetNumMacros then
        return false
    end

    local accountMacros = GetNumMacros()
    if type(accountMacros) == "table" then
        accountMacros = accountMacros.global or accountMacros.numGlobalMacros or 0
    end
    return (accountMacros or 0) < (MAX_ACCOUNT_MACROS or 120)
end

local function expandedLines(queue)
    local lines = {}
    for i = 1, #queue do
        local item = queue[i]
        for _ = 1, item.jumps do
            lines[#lines + 1] = string.format("%s %s", item.command, item.name)
        end
    end
    return lines
end

function MacroBuilder:Initialize()
    self.queue = self.queue or {}
    self.preparedLines = self.preparedLines or {}
    self.awaitingConfirmation = self.awaitingConfirmation or {}
    self.lastSystemMessage = nil
end

function MacroBuilder:GetMacroName()
    return MACRO_NAME
end

function MacroBuilder:GetHotkey()
    local settings = GC.DB and GC.DB.GetSettings and GC.DB:GetSettings()
    return settings and settings.guildActionHotkey or DEFAULT_HOTKEY
end

function MacroBuilder:GetQueuedActions()
    self:Initialize()
    return copyQueue(self.queue)
end

function MacroBuilder:GetQueuedLineCount()
    self:Initialize()
    local count = 0
    for i = 1, #self.queue do
        count = count + self.queue[i].jumps
    end
    return count
end

function MacroBuilder:GetQueuedNames()
    self:Initialize()
    local seen = {}
    local names = {}
    for i = 1, #self.queue do
        local name = self.queue[i].name
        if name and not seen[name] then
            seen[name] = true
            names[#names + 1] = name
        end
    end
    return names
end

function MacroBuilder:HasPreparedMacro()
    return getMacroIndex() ~= nil and #self.preparedLines > 0 and GC.State.actionMacroOwner == "operations"
end

function MacroBuilder:ClearPreparedMacro()
    self.preparedLines = {}
    if GC.State.actionMacroOwner == "operations" then
        GC.State.actionMacroOwner = nil
    end
end

function MacroBuilder:ClearQueue()
    self.queue = {}
    self:ClearPreparedMacro()
end

function MacroBuilder:QueueRankAction(playerOrName, command, jumps)
    self:Initialize()

    local name = printableName(playerOrName)
    if not name or name == "" then
        return false, "No player selected."
    end

    if command ~= "/gpromote" and command ~= "/gdemote" then
        return false, "Unsupported guild action."
    end

    jumps = math.max(1, tonumber(jumps) or 1)
    self.queue[#self.queue + 1] = {
        name = name,
        command = command,
        jumps = jumps,
        key = type(playerOrName) == "table" and playerOrName.key or nil,
        expectedRankIndex = expectedRankIndex(playerOrName, command, jumps),
    }

    local ok, message = self:BuildMacro()
    if not ok then
        table.remove(self.queue)
    end
    return ok, message
end

function MacroBuilder:BuildMacro()
    self:Initialize()

    if InCombatLockdown and InCombatLockdown() then
        return false, "Cannot create or edit guild action macros while in combat."
    end

    local lines = expandedLines(self.queue)
    if #lines == 0 then
        self:ClearPreparedMacro()
        return false, "No guild actions queued."
    end

    local macroText = ""
    local prepared = {}
    for i = 1, #lines do
        local candidate = macroText == "" and lines[i] or (macroText .. "\n" .. lines[i])
        if #candidate > MACRO_LIMIT then
            break
        end
        macroText = candidate
        prepared[#prepared + 1] = lines[i]
    end

    if #prepared == 0 then
        return false, "The first queued action is too long for a WoW macro."
    end

    local index = getMacroIndex()
    if index then
        EditMacro(index, MACRO_NAME, MACRO_ICON, macroText)
    else
        if not canCreateMacro() then
            return false, "No account macro slots are available."
        end
        CreateMacro(MACRO_NAME, MACRO_ICON, macroText, nil)
    end

    self.preparedLines = prepared
    GC.State.actionMacroOwner = "operations"
    local hotkey = self:GetHotkey()
    if SetBindingMacro then
        SetBindingMacro(hotkey, MACRO_NAME)
        if SaveBindings and GetCurrentBindingSet then
            SaveBindings(GetCurrentBindingSet())
        end
    end
    debugPrint("macro index", tostring(getMacroIndex()))
    debugPrint("macro body before execution:")
    debugPrint(macroText)
    debugPrint("bound hotkey", tostring(hotkey))
    debugList("prepared lines", self.preparedLines)
    debugList("queue after build", self.queue)
    return true, string.format("Press %s 1 time to complete all actions.", hotkey)
end

local function removeOneQueuedCommand(self, command, name)
    local lowerName = string.lower(shortName(name) or "")
    for i = 1, #self.queue do
        local item = self.queue[i]
        if item.command == command and string.lower(shortName(item.name) or "") == lowerName then
            item.jumps = math.max(0, (item.jumps or 1) - 1)
            if item.jumps == 0 then
                table.remove(self.queue, i)
            end
            return true
        end
    end
    return false
end

local function removeOneAwaitingLine(self, command, name)
    local target = string.format("%s %s", command, name or "")
    for i = 1, #self.awaitingConfirmation do
        if self.awaitingConfirmation[i] == target then
            table.remove(self.awaitingConfirmation, i)
            return true
        end
    end
    return false
end

local function removeAwaitingByLine(self, line)
    for i = 1, #self.awaitingConfirmation do
        if self.awaitingConfirmation[i] == line then
            table.remove(self.awaitingConfirmation, i)
            return true
        end
    end
    return false
end

local function parseConfirmedRankChange(message)
    local lower = string.lower(message or "")
    local command
    if string.find(lower, "has promoted", 1, true) then
        command = "/gpromote"
    elseif string.find(lower, "has demoted", 1, true) then
        command = "/gdemote"
    else
        return nil
    end

    if not MacroBuilderInstance then
        return command, nil
    end

    for i = 1, #MacroBuilderInstance.queue do
        local item = MacroBuilderInstance.queue[i]
        local name = item.name
        if name and string.find(lower, string.lower(shortName(name)), 1, true) then
            return command, name
        end
    end

    return command, nil
end

local function copyPreparedLines(self)
    local result = {}
    for i = 1, #self.preparedLines do
        local line = self.preparedLines[i]
        for q = 1, #self.queue do
            local item = self.queue[q]
            if line == string.format("%s %s", item.command, item.name) then
                result[#result + 1] = line
                break
            end
        end
    end
    return result
end

function MacroBuilder:VerifyAwaitingRankChanges()
    self:Initialize()

    local roster = GC.Services and GC.Services.GuildService
    if not roster or not roster.GetRosterEntry then
        debugPrint("validation result:", "skipped - roster service unavailable")
        return
    end

    local verified = 0
    for i = #self.queue, 1, -1 do
        local item = self.queue[i]
        if item.expectedRankIndex and item.key then
            local live = roster:GetRosterEntry(item.key)
            local liveRank = live and tonumber(live.rankIndex)
            local changed = liveRank and (
                (item.command == "/gpromote" and liveRank <= item.expectedRankIndex)
                or (item.command == "/gdemote" and liveRank >= item.expectedRankIndex)
            )
            if changed then
                debugPrint("roster verified rank change:", item.command, item.name, "rank", tostring(liveRank))
                removeAwaitingByLine(self, string.format("%s %s", item.command, item.name))
                table.remove(self.queue, i)
                verified = verified + 1
            end
        end
    end

    debugPrint("validation result:", tostring(verified), "confirmed,", tostring(self:GetQueuedLineCount()), "queued remaining")
    debugList("queue after roster verification", self.queue)
    debugList("awaiting confirmation after roster verification", self.awaitingConfirmation)
    if #self.awaitingConfirmation == 0 and self:GetQueuedLineCount() > 0 then
        self:BuildMacro()
    elseif #self.awaitingConfirmation == 0 and self:GetQueuedLineCount() == 0 then
        self:ClearPreparedMacro()
    end
end

function MacroBuilder:OnMacroExecuted()
    self:Initialize()

    -- Called after the macro body has had a chance to run /gpromote or
    -- /gdemote before reaching /run GuildCore_ResetActionMacro().
    -- Do not remove queue entries here; rank commands are only considered done
    -- after CHAT_MSG_SYSTEM or a later roster verification confirms them.
    self.awaitingConfirmation = copyPreparedLines(self)
    debugList("queue before delayed cleanup", self.queue)
    self:ClearPreparedMacro()
    debugList("queue after delayed cleanup", self.queue)
    if #self.awaitingConfirmation == 0 and self:GetQueuedLineCount() > 0 then
        self:BuildMacro()
    end

    if GC.Services and GC.Services.GuildService then
        C_Timer.After(1.5, function()
            GC.Services.GuildService:TriggerScan()
        end)
        C_Timer.After(3, function()
            if GC.Services and GC.Services.OperationsMacro then
                GC.Services.OperationsMacro:VerifyAwaitingRankChanges()
            end
        end)
    end

    C_Timer.After(8, function()
        if GC.State and GC.State.actionMacroOwnerExecuted == "operations" then
            GC.State.actionMacroExecuted = false
            GC.State.actionMacroOwnerExecuted = nil
            GC.State.actionMacroExecutedAt = nil
        end
    end)
end

function MacroBuilder:ValidateRosterUpdate()
    self:VerifyAwaitingRankChanges()
end

function MacroBuilder:CaptureSystemMessage(message)
    if type(message) ~= "string" then
        return
    end

    local lower = string.lower(message)
    debugPrint("CHAT_MSG_SYSTEM message:", message)

    if string.find(lower, "has promoted", 1, true) or string.find(lower, "has demoted", 1, true) then
        debugPrint("CHAT_MSG_SYSTEM rank change:", message)
        self.lastSystemMessage = message
        local command, name = parseConfirmedRankChange(message)
        if command and name then
            removeOneQueuedCommand(self, command, name)
            removeOneAwaitingLine(self, command, name)
            debugList("queue after CHAT_MSG_SYSTEM confirmation", self.queue)
            debugList("awaiting confirmation after CHAT_MSG_SYSTEM", self.awaitingConfirmation)
            if #self.awaitingConfirmation == 0 and self:GetQueuedLineCount() > 0 then
                self:BuildMacro()
            elseif #self.awaitingConfirmation == 0 and self:GetQueuedLineCount() == 0 then
                self:ClearPreparedMacro()
            end
        end
        if GC.UI and GC.UI.PlayerPanel and GC.UI.PlayerPanel.SetActionFeedback then
            GC.UI.PlayerPanel:SetActionFeedback(message, "textSuccess")
        end
    end
end

local service = setmetatable({}, MacroBuilder)
MacroBuilderInstance = service
service:Initialize()
GC:RegisterService("OperationsMacro", service)

function GuildCore_RunMacro()
    GuildCore_ResetActionMacro()
end

function GuildCore_ResetActionMacro()
    if GC and GC.State then
        local owner = GC.State.actionMacroOwner
        GC.State.actionMacroExecuted = true
        GC.State.actionMacroOwnerExecuted = owner
        GC.State.actionMacroExecutedAt = time()

        debugPrint("reset marker owner", tostring(owner), "at", tostring(GC.State.actionMacroExecutedAt))
        debugPrint("macro index", tostring(getMacroIndex()))
        debugPrint("macro body at reset marker:")
        debugPrint(getMacroBody() or "(nil)")
        if GC.Services and GC.Services.OperationsMacro then
            debugList("prepared lines at reset", GC.Services.OperationsMacro.preparedLines)
            debugList("queue before reset", GC.Services.OperationsMacro.queue)
        end

        C_Timer.After(0.25, function()
            if owner == "purge" and GC.Services and GC.Services.Purge then
                GC.Services.Purge:OnMacroExecuted()
            elseif owner == "operations" and GC.Services and GC.Services.OperationsMacro then
                GC.Services.OperationsMacro:OnMacroExecuted()
            end
        end)
    end
end

-- UI/PurgePanel.lua
-- Review-first purge UI. Builds /gremove macros; never removes directly.
local addonName, ns = ...
local GC = ns.GuildCore

GC.UI.PurgePanel = {}
local PP = GC.UI.PurgePanel

local function T() return GC.UI.Theme end
local function PS() return GC.Services.Purge end

local function shortText(value, maxLen)
    value = tostring(value or "")
    if maxLen and #value > maxLen then
        return value:sub(1, maxLen - 1) .. "."
    end
    return value
end

local function setCell(cell, text, color)
    cell:SetText(text or "")
    if color then
        cell:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    end
end

local function buildPurgeRow(row, item)
    local Th = T()
    if not row._cells then
        row._cells = {}

        local name = Th.Fs(row, "data", "", "textPrimary")
        name:SetPoint("LEFT", 10, 0)
        name:SetWidth(100)
        name:SetJustifyH("LEFT")
        name:SetWordWrap(false)
        row._cells.name = name

        local rank = Th.Fs(row, "data", "", "textSecond")
        rank:SetPoint("LEFT", 118, 0)
        rank:SetWidth(72)
        rank:SetJustifyH("LEFT")
        rank:SetWordWrap(false)
        row._cells.rank = rank

        local days = Th.Fs(row, "data", "", "textWarn")
        days:SetPoint("LEFT", 194, 0)
        days:SetWidth(46)
        days:SetJustifyH("RIGHT")
        days:SetWordWrap(false)
        row._cells.days = days

        local reason = Th.Fs(row, "data", "", "textSecond")
        reason:SetPoint("LEFT", 252, 0)
        reason:SetPoint("RIGHT", row, "RIGHT", -10, 0)
        reason:SetJustifyH("LEFT")
        reason:SetWordWrap(false)
        row._cells.reason = reason
    end

    local nameColor = item.status == "awaitingVerification" and Th.c.textWarn or Th.c.textPrimary
    setCell(row._cells.name, shortText(item.name or "Unknown", 13), nameColor)
    setCell(row._cells.rank, shortText(item.rankName or item.source or "-", 10), Th.c.textSecond)
    setCell(row._cells.days, item.daysOffline and (tostring(item.daysOffline) .. "d") or "-", Th.c.textWarn)
    setCell(row._cells.reason, shortText(item.reason or item.status or "", 30), Th.c.textSecond)
end

local function setStatus(self, message, colorKey)
    if self.statusText then
        local color = T().c[colorKey or "textDimmed"] or T().c.textDimmed
        self.statusText:SetTextColor(color[1], color[2], color[3], color[4] or 1)
        self.statusText:SetText(message or "")
    end
    if GC.UI.MainFrame then
        GC.UI.MainFrame:SetStatus(message, colorKey)
    end
end

local function splitList(text)
    local result = {}
    for part in string.gmatch(tostring(text or ""), "([^,]+)") do
        local value = GC.Utils.Trim(part)
        if value ~= "" then
            result[#result + 1] = value
        end
    end
    return result
end

local function joinList(values)
    return table.concat(values or {}, ", ")
end

local function setEditBoxEnabled(box, enabled)
    if not box then return end
    if enabled then
        if box.Enable then box:Enable() end
        box:EnableMouse(true)
        box:SetTextColor(1, 1, 1, 1)
    else
        if box.Disable then box:Disable() end
        box:EnableMouse(false)
        box:SetTextColor(0.45, 0.45, 0.5, 1)
        box:ClearFocus()
    end
end

local function makeToggle(parent, label, x, y, onChange)
    local Th = T()
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    row:SetSize(220, 24)

    local btn = CreateFrame("Button", nil, row)
    btn:SetSize(34, 18)
    btn:SetPoint("LEFT", 0, 0)
    local track = btn:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    local knob = btn:CreateTexture(nil, "OVERLAY")
    knob:SetSize(14, 14)

    local text = Th.Fs(row, "data", label, "textSecond")
    text:SetPoint("LEFT", btn, "RIGHT", 8, 0)

    local state = false
    local function refresh()
        knob:ClearAllPoints()
        if state then
            local ac = T().c.accent
            track:SetColorTexture(ac[1] * 0.35, ac[2] * 0.35, ac[3] * 0.35, 1)
            knob:SetColorTexture(ac[1], ac[2], ac[3], 1)
            knob:SetPoint("RIGHT", btn, "RIGHT", -2, 0)
        else
            local dc = T().c.btnDisabled
            track:SetColorTexture(dc[1], dc[2], dc[3], dc[4] or 1)
            knob:SetColorTexture(0.45, 0.45, 0.5, 1)
            knob:SetPoint("LEFT", btn, "LEFT", 2, 0)
        end
    end

    btn:SetScript("OnClick", function()
        state = not state
        refresh()
        if onChange then onChange(state) end
    end)

    refresh()
    return {
        set = function(value)
            state = value and true or false
            refresh()
        end,
        get = function()
            return state
        end,
    }
end

local function section(parent, title, x, y, w, h)
    local Th = T()
    local label = Th.Fs(parent, "tiny", title, "textAccent")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)

    local nameHdr = Th.Fs(parent, "tiny", "NAME", "textDimmed")
    nameHdr:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 10, y - 16)
    nameHdr:SetWidth(100)
    nameHdr:SetJustifyH("LEFT")
    local rankHdr = Th.Fs(parent, "tiny", "RANK", "textDimmed")
    rankHdr:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 118, y - 16)
    rankHdr:SetWidth(72)
    rankHdr:SetJustifyH("LEFT")
    local daysHdr = Th.Fs(parent, "tiny", "DAYS", "textDimmed")
    daysHdr:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 194, y - 16)
    daysHdr:SetWidth(46)
    daysHdr:SetJustifyH("RIGHT")
    local reasonHdr = Th.Fs(parent, "tiny", "REASON", "textDimmed")
    reasonHdr:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 252, y - 16)
    reasonHdr:SetWidth(math.max(80, w - 262))
    reasonHdr:SetJustifyH("LEFT")

    local outer = CreateFrame("Frame", nil, parent)
    outer:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 32)
    outer:SetSize(w, h - 14)
    Th.Bg(outer, Th.c.panelAlt, Th.c.border)

    local inner = CreateFrame("Frame", nil, outer)
    inner:SetPoint("TOPLEFT", outer, "TOPLEFT", 4, -8)
    inner:SetPoint("BOTTOMRIGHT", outer, "BOTTOMRIGHT", -4, 4)
    return inner
end

function PP:Create(parent)
    if self.frame then return end
    local Th = T()
    local P = Th.padding

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    frame:Hide()
    self.frame = frame
    Th.Bg(frame, Th.c.bg)

    local hdr = Th.Fs(frame, "header", "Purge", "textPrimary")
    hdr:SetPoint("TOPLEFT", P, -P)

    local note = Th.Fs(frame, "small", "Review candidates first. GuildCore only writes /gremove macro lines; the officer must manually click GuildCore_Action.", "textWarn")
    note:SetPoint("TOPLEFT", P, -(P + 28))
    note:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -P, -(P + 28))
    note:SetWordWrap(true)

    local rulesY = -(P + 58)
    local rulesLabel = Th.Fs(frame, "tiny", "RULES", "textAccent")
    rulesLabel:SetPoint("TOPLEFT", P, rulesY)

    local toolbarY = -(P + 180)
    local scanX = P
    local queueX = scanX + 108 + 8
    local buildX = queueX + 138 + 8
    local executeX = buildX + 110 + 8
    local pickupX = executeX + 122 + 8
    local clearX = pickupX + 104 + 8

    local daysBox = GC.UI.Panel.Input(frame, 56, Th.inputH)
    daysBox:SetPoint("TOPLEFT", P, rulesY - 22)
    daysBox:SetMaxLetters(4)
    if daysBox.SetTextInsets then
        daysBox:SetTextInsets(14, 4, 0, 0)
    end
    daysBox:SetScript("OnEditFocusLost", function()
        PP:SaveRulesFromUI()
    end)
    self.daysBox = daysBox

    local daysLabel = Th.Fs(frame, "small", "days offline", "textSecond")
    daysLabel:SetPoint("LEFT", daysBox, "RIGHT", 10, 0)
    daysLabel:SetWidth(110)

    local allRanksToggle
    allRanksToggle = makeToggle(frame, "All lower ranks", P + 230, rulesY - 22, function()
        PP:SaveRulesFromUI()
    end)
    self.allRanksToggle = allRanksToggle

    local linkedToggle
    linkedToggle = makeToggle(frame, "Protect linked mains/alts", P + 480, rulesY - 22, function()
        PP:SaveRulesFromUI()
    end)
    self.linkedToggle = linkedToggle

    local ranksY = rulesY - 54
    local ranksLabel = Th.Fs(frame, "tiny", "INCLUDED RANKS", "textDimmed")
    ranksLabel:SetPoint("TOPLEFT", P, ranksY)
    local ranksBox = GC.UI.Panel.Input(frame, 430, Th.inputH)
    ranksBox:SetPoint("TOPLEFT", P, ranksY - 22)
    ranksBox:SetMaxLetters(120)
    ranksBox:SetScript("OnEditFocusLost", function()
        PP:SaveRulesFromUI()
    end)
    self.ranksBox = ranksBox

    local tagsLabel = Th.Fs(frame, "tiny", "SAFE TAGS", "textDimmed")
    tagsLabel:SetPoint("TOPLEFT", P + 454, ranksY)
    local tagsBox = GC.UI.Panel.Input(frame, 650, Th.inputH)
    tagsBox:SetPoint("TOPLEFT", P + 454, ranksY - 22)
    tagsBox:SetMaxLetters(180)
    tagsBox:SetScript("OnEditFocusLost", function()
        PP:SaveRulesFromUI()
    end)
    self.tagsBox = tagsBox

    local scanBtn = GC.UI.Button.Create(frame, "Scan Rules", "primary", 108, Th.btnH)
    scanBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", scanX, toolbarY)
    scanBtn:SetScript("OnClick", function()
        PP:SaveRulesFromUI()
        local rules = PS():GetRules()
        local candidates, protected = PS():ScanCandidates({
            daysOffline = rules.daysOffline,
            includeAllRanks = rules.includeAllRanks,
            includeRanks = rules.includeRanks,
            safeTags = rules.safeTags,
            exemptLinkedCharacters = rules.exemptLinkedCharacters,
        })
        local state = PS():GetState()
        local total = state and state.meta and state.meta.lastScanTotal or 0
        local inactive = state and state.meta and state.meta.lastScanInactive or 0
        setStatus(PP, string.format("Rule scan complete: %d scanned, %d inactive. %d candidate%s, %d protected/skipped.", total, inactive, candidates, candidates == 1 and "" or "s", protected), "textWarn")
        PP:Refresh()
    end)

    local queueAllBtn = GC.UI.Button.Create(frame, "Queue Candidates", "danger", 138, Th.btnH)
    queueAllBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", queueX, toolbarY)
    queueAllBtn:SetScript("OnClick", function()
        local queued, skipped = PS():QueueAllCandidates()
        setStatus(PP, string.format("%d purge candidate%s queued. Build and execute the macro to remove members.", queued, queued == 1 and "" or "s"), skipped > 0 and "textWarn" or "textSuccess")
        PP:Refresh()
    end)

    local buildBtn = GC.UI.Button.Create(frame, "Build Macro", "primary", 110, Th.btnH)
    buildBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", buildX, toolbarY)
    buildBtn:SetScript("OnClick", function()
        local ok, message = PS():BuildMacro()
        setStatus(PP, message, ok and "textSuccess" or "textDanger")
        PP:Refresh()
    end)

    local executeBtn = GC.UI.Button.Create(frame, "Confirm", "success", 122, Th.btnH)
    executeBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", executeX, toolbarY)
    executeBtn:SetScript("OnClick", function()
        local ok, message = PS():BuildMacro()
        setStatus(PP, message, ok and "textSuccess" or "textDanger")
        PP:Refresh()
    end)
    self.executeBtn = executeBtn

    local pickupBtn = GC.UI.Button.Create(frame, "Place Macro", "secondary", 104, Th.btnH)
    pickupBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", pickupX, toolbarY)
    pickupBtn:SetScript("OnClick", function()
        if PickupMacro then
            PickupMacro("GuildCore_Action")
            setStatus(PP, "GuildCore_Action picked up. Place it on an action bar, then click it to execute.", "textSuccess")
        end
    end)
    self.pickupBtn = pickupBtn

    local clearBtn = GC.UI.Button.Create(frame, "Clear Queue", "secondary", 104, Th.btnH)
    clearBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", clearX, toolbarY)
    clearBtn:SetScript("OnClick", function()
        PS():ClearQueue()
        setStatus(PP, "Purge queue cleared.", "textWarn")
        PP:Refresh()
    end)

    local topY = toolbarY - 58
    local colW = math.floor((frame:GetWidth() > 0 and frame:GetWidth() or 1000) / 3) - P
    local listH = 428

    local candidatesFrame = section(frame, "CANDIDATES", P, topY, colW, listH)
    local candidatesCount = Th.Fs(frame, "tiny", "0 to purge", "textWarn")
    candidatesCount:SetPoint("TOPRIGHT", frame, "TOPLEFT", P + colW, topY)
    candidatesCount:SetJustifyH("RIGHT")
    self.candidatesCountLabel = candidatesCount

    self.candidatesList = GC.UI.List.Create(candidatesFrame, 26, buildPurgeRow, function(item)
        local ok, message = PS():QueueCandidate(item)
        setStatus(PP, message, ok and "textWarn" or "textDanger")
        PP:Refresh()
    end)
    self.candidatesList:SetEmptyText("Run a rule scan to find candidates.")

    local protectedFrame = section(frame, "PROTECTED / SKIPPED", P + colW + P, topY, colW, listH)
    self.protectedList = GC.UI.List.Create(protectedFrame, 26, buildPurgeRow)
    self.protectedList:SetEmptyText("Protected members appear here.")

    local queueFrame = section(frame, "QUEUED PURGES", P + (colW + P) * 2, topY, colW, listH)
    self.queueList = GC.UI.List.Create(queueFrame, 26, buildPurgeRow, nil, function(item)
        if item and item.status ~= "awaitingVerification" then
            PS():RemoveQueued(item.name)
            setStatus(PP, (item.name or "Member") .. " removed from purge queue.", "textWarn")
            PP:Refresh()
        end
    end)
    self.queueList:SetEmptyText("No purge entries queued.")

    local statusText = Th.Fs(frame, "data", "", "textDimmed")
    statusText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", P, P)
    statusText:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -P, P)
    statusText:SetWordWrap(true)
    self.statusText = statusText
end

function PP:SaveRulesFromUI()
    if not self.frame or not PS() then return end
    local includeAllRanks = self.allRanksToggle and self.allRanksToggle.get and self.allRanksToggle.get()
    local daysOffline = PS():ValidateDaysOffline(self.daysBox and self.daysBox:GetText() or nil)
    local rules = {
        daysOffline = daysOffline,
        includeAllRanks = includeAllRanks,
        includeRanks = self.ranksBox and splitList(self.ranksBox:GetText()) or nil,
        safeTags = self.tagsBox and splitList(self.tagsBox:GetText()) or nil,
        exemptLinkedCharacters = self.linkedToggle and self.linkedToggle.get and self.linkedToggle.get(),
    }
    PS():UpdateRules(rules)
    if self.daysBox then
        self.daysBox:SetText(tostring(PS():GetPurgeDaysOffline()))
    end
    if self.ranksBox then
        setEditBoxEnabled(self.ranksBox, not includeAllRanks)
    end
end

function PP:Refresh()
    if not self.frame then return end
    local state = PS():GetState()
    if self.daysBox and state and state.meta then
        self.daysBox:SetText(tostring(PS():GetPurgeDaysOffline()))
    end
    if state and state.meta then
        if self.allRanksToggle then
            self.allRanksToggle.set(state.meta.includeAllRanks)
        end
        if self.linkedToggle then
            self.linkedToggle.set(state.meta.exemptLinkedCharacters)
        end
        if self.ranksBox then
            self.ranksBox:SetText(joinList(state.meta.includeRanks))
            setEditBoxEnabled(self.ranksBox, not state.meta.includeAllRanks)
        end
        if self.tagsBox then
            self.tagsBox:SetText(joinList(state.meta.safeTags))
        end
    end
    local candidates = PS():GetCandidates()
    if self.candidatesCountLabel then
        local count = #candidates
        self.candidatesCountLabel:SetText(string.format("%d to purge", count))
    end
    if self.candidatesList then
        self.candidatesList:Refresh(candidates)
    end
    if self.protectedList then
        self.protectedList:Refresh(PS():GetProtected())
    end
    if self.queueList then
        self.queueList:Refresh(PS():GetQueue())
    end

    local hasPrepared = PS():HasPreparedMacro()
    if self.executeBtn then
        self.executeBtn:SetEnabled(hasPrepared or #PS():GetQueue() > 0)
    end
    if self.pickupBtn then
        self.pickupBtn:SetEnabled(hasPrepared and PickupMacro and true or false)
    end
end

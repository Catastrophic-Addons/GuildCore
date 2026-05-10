-- UI/Dashboard.lua
-- Command-center overview: guild header, stat tiles, and officer-focused guild insights.
local addonName, ns = ...
local GC = ns.GuildCore

GC.UI.Dashboard = {}
local DB = GC.UI.Dashboard

local function T()  return GC.UI.Theme  end
local function GS() return GC.Services.GuildService end

-- ─── helpers ──────────────────────────────────

-- Inline stat card: label on top, value below, accent stripe at top.
local function makeCard(parent, label)
    local Th = T()
    local f  = CreateFrame("Frame", nil, parent)
    Th.Bg(f, Th.c.panelAlt, Th.c.border)
    local stripe = f:CreateTexture(nil, "ARTWORK")
    stripe:SetPoint("TOPLEFT"); stripe:SetPoint("TOPRIGHT"); stripe:SetHeight(2)
    local a = Th.c.accent
    stripe:SetColorTexture(a[1], a[2], a[3], 0.65)
    local lblFs = Th.Fs(f, "data", label or "", "textDimmed")
    lblFs:SetPoint("TOPLEFT", 8, -12)
    lblFs:SetPoint("TOPRIGHT", -8, -12)
    lblFs:SetJustifyH("CENTER")
    lblFs:SetWordWrap(false)
    local valFs = Th.Fs(f, "dataLarge", "—", "textPrimary")
    valFs:SetPoint("CENTER", 0, -8)
    valFs:SetJustifyH("CENTER")
    return f, function(v) valFs:SetText(tostring(v or "—")) end,
              function(c) valFs:SetTextColor(c[1], c[2], c[3], c[4] or 1) end
end

local function makeInsightCard(parent, label)
    local frame, setVal, setColor = makeCard(parent, label)
    return frame, setVal, setColor
end

local function layoutRow(parent, defs, tileMap, topOffset, height, padding)
    local count = #defs
    if count == 0 then
        return
    end

    local gap = padding
    local liveWidth = parent:GetWidth()
    local fallbackWidth = T().width - T().navWidth - (padding * 2) - 8
    local totalWidth = ((liveWidth and liveWidth > 0) and liveWidth or fallbackWidth) - (padding * 2)
    local tileWidth = math.floor((totalWidth - gap * (count - 1)) / count)

    for i, def in ipairs(defs) do
        local tile = tileMap[def.key] and tileMap[def.key].frame
        if tile then
            tile:ClearAllPoints()
            tile:SetPoint("TOPLEFT", parent, "TOPLEFT", padding + (i - 1) * (tileWidth + gap), topOffset)
            tile:SetSize(tileWidth, height)
        end
    end
end

local function buildAttentionRow(row, item)
    local Th = T()
    if not row._built then
        local nameFs = Th.Fs(row, "small", "", "textPrimary")
        nameFs:SetPoint("LEFT", 10, 0)
        nameFs:SetWidth(150)
        local issueFs = Th.Fs(row, "small", "", "textSecond")
        issueFs:SetPoint("LEFT", 170, 0)
        issueFs:SetWidth(240)
        local actionFs = Th.Fs(row, "small", "", "textDimmed")
        actionFs:SetPoint("LEFT", 420, 0)
        actionFs:SetPoint("RIGHT", -10, 0)
        local navHint = Th.Fs(row, "tiny", "→ click to navigate", "textDimmed")
        navHint:SetPoint("RIGHT", -10, 0)
        navHint:SetAlpha(0)
        row._nameFs   = nameFs
        row._issueFs  = issueFs
        row._actionFs = actionFs
        row._navHint  = navHint
        row._built = true

        local prevEnter = row:GetScript("OnEnter")
        local prevLeave = row:GetScript("OnLeave")
        row:SetScript("OnEnter", function(self)
            if prevEnter then prevEnter(self) end
            if self._navHint then self._navHint:SetAlpha(0.7) end
            if self._actionFs then self._actionFs:SetAlpha(0) end
        end)
        row:SetScript("OnLeave", function(self)
            if prevLeave then prevLeave(self) end
            if self._navHint then self._navHint:SetAlpha(0) end
            if self._actionFs then self._actionFs:SetAlpha(1) end
        end)
    end

    local actionColor = Th.c[item.colorKey or "textAccent"] or Th.c.textAccent
    row._nameFs:SetText(item.character or "—")
    row._issueFs:SetText(item.issue or "—")
    row._actionFs:SetText(item.action or "—")
    row._actionFs:SetTextColor(actionColor[1], actionColor[2], actionColor[3], actionColor[4] or 1)
end

-- ─── Create ───────────────────────────────────

function DB:Create(parent)
    if self.frame then return end
    local Th = T()
    local P  = Th.padding

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    frame:Hide()
    self.frame = frame
    Th.Bg(frame, Th.c.bg)

    -- ── Guild header card ────────────────────────
    local guildCard = CreateFrame("Frame", nil, frame)
    guildCard:SetPoint("TOPLEFT",  frame, "TOPLEFT",  P, -P)
    guildCard:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -P, -P)
    guildCard:SetHeight(52)
    Th.Bg(guildCard, Th.c.chrome, Th.c.border)
    local guildStripe = guildCard:CreateTexture(nil, "ARTWORK")
    guildStripe:SetPoint("TOPLEFT"); guildStripe:SetPoint("BOTTOMLEFT"); guildStripe:SetWidth(3)
    local a = Th.c.accent
    guildStripe:SetColorTexture(a[1], a[2], a[3], 0.9)
    local guildNameFs = Th.Fs(guildCard, "subheader", "—", "textAccent")
    guildNameFs:SetPoint("LEFT", 14, 6)
    local guildSubFs  = Th.Fs(guildCard, "data", "No guild data", "textDimmed")
    guildSubFs:SetPoint("LEFT", 14, -12)
    self.guildNameFs  = guildNameFs
    self.guildSubFs   = guildSubFs

    local activityBtn = GC.UI.Button.Create(guildCard, "Activity Log", "secondary", 94, Th.btnH)
    activityBtn:SetPoint("RIGHT", guildCard, "RIGHT", -108, 0)
    activityBtn:SetScript("OnClick", function()
        GC.UI:SetActivePanel("log")
    end)

    local exportBtn = GC.UI.Button.Create(guildCard, "Export", "secondary", 74, Th.btnH)
    exportBtn:SetPoint("RIGHT", guildCard, "RIGHT", -18, 0)
    exportBtn:SetScript("OnClick", function()
        DB:ShowExport()
    end)

    -- ── Main stat tiles (4 across) ───────────────
    local tileTop = -(P + 52 + P)
    local tileH   = 72
    self.mainTiles = {}
    local mainTileDefs = {
        {key="total",    label="Members"},
        {key="online",   label="Online"},
        {key="active",   label="Active (7d)"},
        {key="inactive", label="Inactive"},
    }
    for i, td in ipairs(mainTileDefs) do
        local f, setVal, setColor = makeCard(frame, td.label)
        f:SetHeight(tileH)
        self.mainTiles[td.key] = {setVal = setVal, setColor = setColor, frame = f}
    end
    layoutRow(frame, mainTileDefs, self.mainTiles, tileTop, tileH, P)

    -- ── 7-day summary row ────────────────────────
    local summaryTop = tileTop - tileH - P
    local summaryH   = tileH
    local summaryDefs = {
        {key="recentJoins",      label="Joined (7d)"},
        {key="recentLeaves",     label="Left (7d)"},
        {key="recentRankChanges",label="Rank Changes (7d)"},
        {key="logCount",         label="Log Entries"},
    }
    self.summaryTiles = {}
    for i, td in ipairs(summaryDefs) do
        local f, setVal = makeCard(frame, td.label)
        f:SetHeight(summaryH)
        self.summaryTiles[td.key] = {setVal = setVal, frame = f}
    end
    layoutRow(frame, summaryDefs, self.summaryTiles, summaryTop, summaryH, P)

    -- ── Last scan line ───────────────────────────
    local scanLineTop = summaryTop - summaryH - P/2
    local scanFs = Th.Fs(frame, "data", "Last scan: —", "textDimmed")
    scanFs:SetPoint("TOPLEFT", frame, "TOPLEFT", P, scanLineTop)
    self.scanFs = scanFs

    Th.HSep(frame, scanLineTop - 20)

    -- ── Guild Insights ───────────────────────────
    local insightsTop = scanLineTop - 28
    local insightsHdr = Th.Fs(frame, "subheader", "Guild Insights", "textAccent")
    insightsHdr:SetPoint("TOPLEFT", frame, "TOPLEFT", P, insightsTop)

    local insightTop = insightsTop - 24
    local insightH = 68
    local insightDefs = {
        {key = "initiatesNeedingReview", label = "Initiates Needing Review"},
        {key = "missingDiscordVerification", label = "Missing Discord Verification"},
        {key = "unlinkedCharacters", label = "Unlinked / Unknown"},
        {key = "inactiveMembers", label = "Ready for Purge"},
    }
    self.insightTiles = {}
    for _, td in ipairs(insightDefs) do
        local card, setVal, setColor = makeInsightCard(frame, td.label)
        self.insightTiles[td.key] = { frame = card, setVal = setVal, setColor = setColor }
    end
    layoutRow(frame, insightDefs, self.insightTiles, insightTop, insightH, P)

    local attentionTop = insightTop - insightH - P - 2
    local attentionHdr = Th.Fs(frame, "subheader", "Needs Attention", "textAccent")
    attentionHdr:SetPoint("TOPLEFT", frame, "TOPLEFT", P, attentionTop)

    local attentionFrame = CreateFrame("Frame", nil, frame)
    attentionFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", P, attentionTop - 24)
    attentionFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -P, P)
    Th.Bg(attentionFrame, Th.c.panelAlt, Th.c.border)
    self.attentionFrame = attentionFrame

    local colBar = CreateFrame("Frame", nil, attentionFrame)
    colBar:SetPoint("TOPLEFT", attentionFrame, "TOPLEFT", 0, 0)
    colBar:SetPoint("TOPRIGHT", attentionFrame, "TOPRIGHT", 0, 0)
    colBar:SetHeight(Th.colBarH)
    Th.Bg(colBar, Th.c.chrome)

    local function colHdr(text, x, width)
        local fs = Th.Fs(colBar, "tiny", text, "textDimmed")
        fs:SetPoint("LEFT", x, 0)
        fs:SetWidth(width)
    end
    colHdr("Character", 10, 150)
    colHdr("Issue", 170, 240)
    colHdr("Suggested Action", 420, 180)

    local attentionListHost = CreateFrame("Frame", nil, attentionFrame)
    attentionListHost:SetPoint("TOPLEFT", attentionFrame, "TOPLEFT", 0, -Th.colBarH)
    attentionListHost:SetPoint("BOTTOMRIGHT", attentionFrame, "BOTTOMRIGHT", 0, 0)
    self.attentionList = GC.UI.List.Create(attentionListHost, 24, buildAttentionRow, function(item)
        if not item then return end
        GC.UI.MainFrame:SetActivePanel("roster")
        local function focusRosterTarget()
            local roster = GC.UI.RosterPanel
            if roster and roster.FocusCharacter then
                local ok, message = roster:FocusCharacter(item.key or item.character)
                if not ok and GC.Debug then
                    GC:Debug(message or "Needs Attention target was not found in the roster.")
                end
            end
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(0, focusRosterTarget)
        else
            focusRosterTarget()
        end
    end)
    self.attentionList:SetEmptyText("No urgent guild issues found.")

    local exportOverlay = CreateFrame("Frame", nil, frame)
    exportOverlay:SetPoint("TOPLEFT", frame, "TOPLEFT", P + 18, -(P + 96))
    exportOverlay:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -P - 18, -(P + 96))
    exportOverlay:SetHeight(250)
    if GC.UI.Layering then
        GC.UI.Layering:ApplyPopup(exportOverlay, GC.UI.MainFrame and GC.UI.MainFrame.frame, 35)
    else
        exportOverlay:SetFrameStrata("DIALOG")
    end
    Th.Bg(exportOverlay, Th.c.panel, Th.c.borderAccent)
    exportOverlay:Hide()
    self.exportOverlay = exportOverlay

    local exportHdr = Th.Fs(exportOverlay, "subheader", "Export Guild Insights", "textAccent")
    exportHdr:SetPoint("TOPLEFT", 12, -10)

    local exportClose = GC.UI.Button.Create(exportOverlay, "Close", "secondary", 70, Th.btnH)
    exportClose:SetPoint("TOPRIGHT", -12, -8)
    exportClose:SetScript("OnClick", function()
        exportOverlay:Hide()
    end)

    local exportScroll = CreateFrame("ScrollFrame", nil, exportOverlay)
    exportScroll:SetPoint("TOPLEFT", exportOverlay, "TOPLEFT", 12, -40)
    exportScroll:SetPoint("BOTTOMRIGHT", exportOverlay, "BOTTOMRIGHT", -12, 12)
    exportScroll:EnableMouseWheel(true)
    exportScroll:SetScript("OnMouseWheel", function(_, delta)
        exportScroll:SetVerticalScroll(math.max(0, exportScroll:GetVerticalScroll() - delta * 24))
    end)

    local exportEdit = CreateFrame("EditBox", nil, exportScroll)
    exportEdit:SetMultiLine(true)
    exportEdit:SetAutoFocus(true)
    exportEdit:SetFontObject("ChatFontNormal")
    exportEdit:SetWidth(700)
    exportEdit:SetScript("OnEscapePressed", function()
        exportOverlay:Hide()
    end)
    exportEdit:SetScript("OnTextChanged", function(self)
        self:SetHeight(math.max(210, self:GetStringHeight() + 24))
    end)
    exportScroll:SetScrollChild(exportEdit)
    self.exportEdit = exportEdit
end

-- ─── Refresh ──────────────────────────────────

function DB:Refresh()
    if not self.frame then return end
    local Th = T()
    local P  = Th.padding

    layoutRow(self.frame, {
        {key="total",    label="Members"},
        {key="online",   label="Online"},
        {key="active",   label="Active (7d)"},
        {key="inactive", label="Inactive"},
    }, self.mainTiles, -(P + 52 + P), 72, P)
    layoutRow(self.frame, {
        {key="recentJoins",      label="Joined (7d)"},
        {key="recentLeaves",     label="Left (7d)"},
        {key="recentRankChanges",label="Rank Changes (7d)"},
        {key="logCount",         label="Log Entries"},
    }, self.summaryTiles, -(P + 52 + P) - 72 - P, 72, P)
    layoutRow(self.frame, {
        {key = "initiatesNeedingReview", label = "Initiates Needing Review"},
        {key = "missingDiscordVerification", label = "Missing Discord Verification"},
        {key = "unlinkedCharacters", label = "Unlinked / Unknown"},
        {key = "inactiveMembers", label = "Ready for Purge"},
    }, self.insightTiles, -(P + 52 + P) - 72 - P - 72 - P - 22, 68, P)

    local stats = GS():GetStats()
    local insights = GS():GetGuildInsights()
    local attentionRows = GS():GetNeedsAttention()

    -- Guild header
    local guildName = GetGuildInfo and GetGuildInfo("player") or nil
    self.guildNameFs:SetText(guildName or "No Guild")
    if stats.lastScanAt then
        self.guildSubFs:SetText("Last scan: " .. date("%Y-%m-%d %H:%M", stats.lastScanAt))
    else
        self.guildSubFs:SetText("No scan data yet  —  open the window to scan")
    end

    -- Main tiles
    local c_ok   = Th.c.statusActive
    local c_warn = Th.c.textWarn
    local mainMap = {total="total", online="online", active="active", inactive="inactive"}
    for key, statKey in pairs(mainMap) do
        local td = self.mainTiles[key]
        if td then
            td.setVal(stats[statKey] or 0)
            if key == "online"   then td.setColor(c_ok) end
            if key == "inactive" then td.setColor(c_warn) end
        end
    end

    -- Summary tiles
    for key, _ in pairs({recentJoins=true,recentLeaves=true,recentRankChanges=true,logCount=true}) do
        local td = self.summaryTiles[key]
        if td then td.setVal(stats[key] or 0) end
    end

    local insightColors = {
        initiatesNeedingReview = Th.c.textAccent,
        missingDiscordVerification = Th.c.textWarn,
        unlinkedCharacters = Th.c.textAccent,
        inactiveMembers = Th.c.textWarn,
    }
    for key, value in pairs(insights) do
        local td = self.insightTiles[key]
        if td then
            td.setVal(value or 0)
            local color = insightColors[key] or Th.c.textPrimary
            td.setColor(color)
        end
    end

    -- Last scan timestamp
    if self.scanFs then
        if stats.lastScanAt then
            self.scanFs:SetText("Last scan: " .. date("%Y-%m-%d %H:%M", stats.lastScanAt))
        else
            self.scanFs:SetText("Last scan: not yet performed")
        end
    end

    if self.attentionList then
        self.attentionList:Refresh(attentionRows)
    end
end

function DB:ShowExport()
    if not self.exportOverlay or not self.exportEdit then
        return
    end
    self.exportEdit:SetText(GS():GetNeedsAttentionExportText())
    self.exportEdit:HighlightText()
    self.exportEdit:SetFocus()
    self.exportOverlay:Show()
end

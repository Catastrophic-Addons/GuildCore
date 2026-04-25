-- UI/RosterPanel.lua
-- Scrollable guild roster with search, online filter, column headers.
local addonName, ns = ...
local GC = ns.GuildCore

GC.UI.RosterPanel = {}
local RP = GC.UI.RosterPanel

local function T()  return GC.UI.Theme end
local function GS() return GC.Services.GuildService end

local function hideContextMenu()
    if RP.contextMenu then
        RP.contextMenu._item = nil
        RP.contextMenu:Hide()
    end
    RP.contextItemKey = nil
end

local function setCursorAnchor(frame)
    local scale = UIParent:GetEffectiveScale() or 1
    local x, y = GetCursorPosition()
    x = (x or 0) / scale
    y = (y or 0) / scale
    local offsetX, offsetY = 12, -12
    local width = frame:GetWidth() or 0
    local height = frame:GetHeight() or 0
    local screenWidth = UIParent:GetWidth() or 0
    local screenHeight = UIParent:GetHeight() or 0
    x = math.max(0, math.min(x + offsetX, math.max(0, screenWidth - width)))
    y = math.max(height, math.min(y + offsetY, screenHeight))
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
end

local function showContextMenu(item)
    local Th = T()
    if not RP.contextMenu then
        local menu = CreateFrame("Frame", nil, UIParent)
        menu:SetSize(148, 64)
        if GC.UI.Layering then
            GC.UI.Layering:ApplyPopup(menu, GC.UI.MainFrame and GC.UI.MainFrame.frame, 40)
        else
            menu:SetFrameStrata("DIALOG")
        end
        Th.Bg(menu, Th.c.panelAlt, Th.c.borderStrong)
        menu:Hide()
        menu:EnableMouse(true)

        local whisperBtn = GC.UI.Button.Create(menu, "Whisper", "secondary", 136, Th.btnH)
        whisperBtn:SetPoint("TOPLEFT", menu, "TOPLEFT", 6, -4)
        whisperBtn:SetScript("OnClick", function()
            local target = menu._item
            hideContextMenu()
            if not target then return end
            local ok, err = GS():OpenWhisper(target.key)
            local mf = GC.UI.MainFrame
            if mf then
                mf:SetStatus(ok and ("Opening whisper to " .. (target.name or "member") .. ".") or (err or "Unable to whisper member."), ok and "textSuccess" or "textDanger")
            end
        end)
        menu.whisperBtn = whisperBtn

        local inviteBtn = GC.UI.Button.Create(menu, "Invite to Party", "secondary", 136, Th.btnH)
        inviteBtn:SetPoint("TOPLEFT", menu, "TOPLEFT", 6, -34)
        inviteBtn:SetScript("OnClick", function()
            local target = menu._item
            hideContextMenu()
            if not target then return end
            local ok, err = GS():InviteToParty(target.key)
            local mf = GC.UI.MainFrame
            if mf then
                mf:SetStatus(ok and ("Party invite sent to " .. (target.name or "member") .. ".") or (err or "Unable to invite member."), ok and "textSuccess" or "textDanger")
            end
        end)

        RP.contextMenu = menu
    end

    if RP.contextMenu:IsShown() and RP.contextItemKey and item and RP.contextItemKey == item.key then
        hideContextMenu()
        return
    end

    local menu = RP.contextMenu
    menu._item = item
    RP.contextItemKey = item and item.key or nil
    if menu.whisperBtn then
        menu.whisperBtn:SetEnabled(item and item.isOnline)
    end
    setCursorAnchor(menu)
    menu:Show()
end

-- Column layout: {label, xOffset, width, field}
local COLS = {
    {label = "Name",      x = 6,   w = 118, field = "name"},
    {label = "Type",      x = 128, w = 46,  field = "classificationBadge"},
    {label = "Rank",      x = 178, w = 92,  field = "rankShort"},
    {label = "Class",     x = 274, w = 120, field = "classSpecDisplay"},
    {label = "Lvl",       x = 360, w = 30,  field = "level"},
    {label = "Status",    x = 394, w = 58,  field = "statusLabel"},
    {label = "Location",  x = 456, w = 116, field = "locationDisplay"},
    {label = "Seen",      x = 576, w = 72,  field = "lastSeenDisplay"},
}

local function buildRow(row, item)
    local Th = T()
    if not row._cols then
        row._cols = {}
        for i, col in ipairs(COLS) do
            local fs = Th.Fs(row, "small", "", "textSecond")
            fs:SetPoint("LEFT", col.x, 0)
            fs:SetWidth(col.w)
            fs:SetJustifyH("LEFT")
            fs:SetWordWrap(false)
            row._cols[i] = fs
        end
    end
    for i, col in ipairs(COLS) do
        local val = tostring(item[col.field] or "—")
        local fs  = row._cols[i]
        if col.field == "name" then
            local rgb = item.classRGB or {1, 1, 1}
            fs:SetTextColor(rgb[1], rgb[2], rgb[3], 1)
            fs:SetText(val)
        elseif col.field == "classificationBadge" then
            local badgeColor = item.classification == "main" and Th.c.textAccent
                or item.classification == "alt" and Th.c.textWarn
                or item.needsPrompt and Th.c.textDanger
                or Th.c.textDimmed
            fs:SetTextColor(badgeColor[1], badgeColor[2], badgeColor[3], badgeColor[4] or 1)
            fs:SetText(val)
        elseif col.field == "classSpecDisplay" then
            local rgb = item.classRGB or Th.c.textDimmed
            fs:SetTextColor(rgb[1] * 0.9, rgb[2] * 0.9, rgb[3] * 0.9, 1)
            fs:SetText(val)
        elseif col.field == "statusLabel" then
            local c = Th.c[item.statusKey] or Th.c.textSecond
            fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
            fs:SetText(val)
        else
            local sc = Th.c.textSecond
            fs:SetTextColor(sc[1], sc[2], sc[3], sc[4] or 1)
            fs:SetText(val)
        end
    end
end

-- ─── filter helpers ────────────────────────────

local function applyFilters(data, searchText, onlineOnly)
    if (not searchText or searchText == "") and not onlineOnly then
        return data
    end
    local q = searchText and searchText:lower() or ""
    local out = {}
    for _, item in ipairs(data) do
        local nameMatch = (q == "") or
            (item.name       and item.name:lower():find(q, 1, true)) or
            (item.rankName   and item.rankName:lower():find(q, 1, true)) or
            (item.classDisplayName and item.classDisplayName:lower():find(q, 1, true))
        local onlineMatch = (not onlineOnly) or item.isOnline
        if nameMatch and onlineMatch then
            out[#out + 1] = item
        end
    end
    return out
end

-- ─── Create ────────────────────────────────────

function RP:Create(parent)
    if self.frame then return end
    local Th = T()
    local P  = Th.padding

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    frame:Hide()
    self.frame = frame
    Th.Bg(frame, Th.c.bg)

    -- ── Page header ──────────────────────────────
    local hdr = Th.Fs(frame, "header", "Roster", "textPrimary")
    hdr:SetPoint("TOPLEFT", P, -P)

    local countFs = Th.Fs(frame, "small", "", "textDimmed")
    countFs:SetPoint("LEFT", hdr, "RIGHT", 10, -2)
    self.countLabel = countFs

    -- ── Toolbar row ──────────────────────────────
    local toolbarY = -(P + 40)

    -- Search box
    local searchBox = GC.UI.Panel.Input(frame, 180, Th.inputH)
    searchBox:SetPoint("TOPLEFT", frame, "TOPLEFT", P, toolbarY)
    searchBox:SetMaxLetters(40)
    -- Placeholder hint
    local hint = searchBox:CreateFontString(nil, "OVERLAY")
    Th.ApplyFont(hint, "small")
    if Th.RegisterRefresh then
        Th:RegisterRefresh(function()
            T().ApplyFont(hint, "small")
        end)
    end
    hint:SetTextColor(0.4, 0.4, 0.5, 1)
    hint:SetText("Search name, rank, class…")
    hint:SetPoint("LEFT", searchBox, "LEFT", 4, 0)
    hint:SetPoint("RIGHT", searchBox, "RIGHT", -4, 0)
    searchBox:SetScript("OnTextChanged", function(eb)
        hint:SetShown(eb:GetText() == "")
        RP:_applyFilter()
    end)
    searchBox:SetScript("OnEditFocusGained", function() hint:Hide() end)
    searchBox:SetScript("OnEditFocusLost",   function(eb) hint:SetShown(eb:GetText() == "") end)
    self.searchBox = searchBox

    -- Online filter button
    local onlineBtn = GC.UI.Button.Create(frame, "All Members", "secondary", 110, Th.btnH)
    onlineBtn:SetPoint("LEFT", searchBox, "RIGHT", P, 0)
    onlineBtn:SetTooltip("Toggle Online Filter", "Show only members who were online in the last scan.")
    self._onlineOnly = false
    onlineBtn:SetScript("OnClick", function()
        self._onlineOnly = not self._onlineOnly
        onlineBtn:SetLabel(self._onlineOnly and "Online Only" or "All Members")
        RP:_applyFilter()
    end)
    self.onlineBtn = onlineBtn

    -- Refresh button
    local refreshBtn = GC.UI.Button.Create(frame, "Refresh", "secondary", 92, Th.btnH)
    refreshBtn:SetPoint("LEFT", onlineBtn, "RIGHT", P/2, 0)
    refreshBtn:SetTooltip("Refresh Roster", "Request a live roster update from the server.")
    refreshBtn:SetScript("OnClick", function()
        local ok, err = GC.Services.GuildService:TriggerScan()
        local mf = GC.UI.MainFrame
        if mf then
            mf:SetStatus(ok and "Roster scan requested…" or (err or "Unable to scan."), ok and "textWarn" or "textDanger")
        end
    end)

    Th.HSep(frame, toolbarY - Th.btnH - 6)

    -- ── Column header bar ────────────────────────
    local colBarY = toolbarY - Th.btnH - 10
    local colBar  = CreateFrame("Frame", nil, frame)
    colBar:SetPoint("TOPLEFT",  frame, "TOPLEFT",  0, colBarY)
    colBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, colBarY)
    colBar:SetHeight(Th.colBarH)
    Th.Bg(colBar, Th.c.chrome)
    for _, col in ipairs(COLS) do
        local hf = Th.Fs(colBar, "tiny", col.label, "textDimmed")
        hf:SetPoint("LEFT", col.x + 4, 0)
        hf:SetWidth(col.w)
        hf:SetJustifyH("LEFT")
    end

    -- ── Scrollable list ──────────────────────────
    local listTop = colBarY - Th.colBarH
    local listFrame = CreateFrame("Frame", nil, frame)
    listFrame:SetPoint("TOPLEFT",     frame, "TOPLEFT",     0, listTop)
    listFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, P)
    self.listFrame = listFrame

    self.list = GC.UI.List.Create(listFrame, Th.rowH, buildRow, function(item)
        hideContextMenu()
        GC.UI.PlayerPanel:SetPlayer(item)
        GC.UI.PlayerPanel:Refresh()
        self.list:SetSelected(item.key)
    end, function(item)
        showContextMenu(item)
    end)
    self.list:SetEmptyText("No members match the current filter.")
end

-- ─── internal filter/refresh ──────────────────

function RP:_applyFilter()
    if not self._allData then return end
    local q = self.searchBox and self.searchBox:GetText() or ""
    local filtered = applyFilters(self._allData, q, self._onlineOnly)
    if self.countLabel then
        local total = #self._allData
        local shown = #filtered
        if shown == total then
            self.countLabel:SetText("(" .. total .. " members)")
        else
            self.countLabel:SetText("(" .. shown .. " / " .. total .. " shown)")
        end
    end
    self.list:Refresh(filtered)
end

-- ─── Refresh ──────────────────────────────────

function RP:Refresh()
    if not self.frame then return end
    self._allData = GS():GetRosterList()
    self:_applyFilter()
end

-- UI/LogPanel.lua
-- Activity log viewer: type-filter bar, timestamped rows, empty state.
local addonName, ns = ...
local GC = ns.GuildCore

GC.UI.LogPanel = {}
local LP = GC.UI.LogPanel
LP._clearConfirmTimer = nil
LP._clearConfirmArmed = false

local function T()  return GC.UI.Theme end
local function GS() return GC.Services.GuildService end

local function trim(value)
    return GC.Utils and GC.Utils.Trim and GC.Utils.Trim(value or "") or tostring(value or ""):match("^%s*(.-)%s*$")
end

local function lower(value)
    return tostring(value or ""):lower()
end

-- Event type → {shortLabel, colorKey}
local EVENT_META = {
    JOINED               = {"Joined",       "statusActive"},
    LEFT                 = {"Left",         "statusInact"},
    REJOINED             = {"Rejoined",     "statusWarn"},
    PROMOTED             = {"Promoted",     "textAccent"},
    DEMOTED              = {"Demoted",      "textWarn"},
    NOTE_CHANGED         = {"Note",         "textSecond"},
    PUBLIC_NOTE_CHANGED  = {"Public Note",  "textSecond"},
    OFFICER_NOTE_CHANGED = {"Officer Note", "textSecond"},
    ALT_LINKED           = {"Alt Linked",   "textAccent"},
    ALT_UNLINKED         = {"Alt Unlinked", "textWarn"},
    CLASSIFICATION_CHANGED = {"Classified", "textAccent"},
    PROMPT_DISMISSED     = {"Prompt",       "textDimmed"},
    UNTRACKED            = {"Untracked",    "textWarn"},
    POINTS_ADDED         = {"Points +",     "textSuccess"},
    POINTS_REMOVED       = {"Points -",     "textDanger"},
    JOIN_DATE_UPDATED    = {"Date",         "textSecond"},
    BANK_ITEM            = {"Bank Item",    "textAccent"},
    BANK_MONEY           = {"Bank Gold",    "textWarn"},
    CUSTOM               = {"Custom",       "textDimmed"},
}

-- category → set of event keys that belong to it
local FILTER_CATS = {
    {id = "all",    label = "All"},
    {id = "roster", label = "Roster",  events = {JOINED=1,LEFT=1,REJOINED=1,UNTRACKED=1}},
    {id = "ranks",  label = "Rank Changes", events = {PROMOTED=1,DEMOTED=1}},
    {id = "points", label = "Points",  events = {POINTS_ADDED=1,POINTS_REMOVED=1}},
    {id = "bank",   label = "Bank",    events = {BANK_ITEM=1,BANK_MONEY=1}},
    {id = "notes",  label = "Notes",   events = {NOTE_CHANGED=1,PUBLIC_NOTE_CHANGED=1,OFFICER_NOTE_CHANGED=1}},
    {id = "alts",   label = "Alts",    events = {ALT_LINKED=1,ALT_UNLINKED=1,CLASSIFICATION_CHANGED=1,PROMPT_DISMISSED=1}},
}

-- ─── row builder ───────────────────────────────

local SORT_MODES = {
    { id = "date",   label = "Date" },
    { id = "member", label = "Member" },
    { id = "type",   label = "Type" },
    { id = "detail", label = "Detail" },
}

local function eventLabel(event)
    local meta = event and EVENT_META[event] or nil
    return meta and meta[1] or tostring(event or "Event")
end

local function playerLabel(item)
    return item and item.playerKey and item.playerKey:match("^([^%-]+)") or (item and item.playerKey) or "—"
end

local function detailText(item, full)
    if not item then return "" end
    local detail = ""
    if item.newValue and item.oldValue then
        local oldValue = tostring(item.oldValue)
        local newValue = tostring(item.newValue)
        if full then
            detail = oldValue .. " -> " .. newValue
        else
            detail = oldValue:sub(1, 18) .. " -> " .. newValue:sub(1, 18)
        end
    elseif item.newValue then
        detail = tostring(item.newValue)
        if not full then
            detail = detail:sub(1, 64)
        end
    end
    return detail
end

local function matchesSearch(item, query)
    query = lower(trim(query))
    if query == "" then
        return true
    end

    local blob = table.concat({
        eventLabel(item and item.event),
        tostring(item and item.event or ""),
        playerLabel(item),
        detailText(item, true),
        tostring(item and item.reason or ""),
        tostring(item and item.bankKind or ""),
        tostring(item and item.bankTransactionType or ""),
        tostring(item and item.bankTab or ""),
        item and item.timestamp and date("%Y-%m-%d %H:%M", item.timestamp) or "",
    }, " "):lower()

    return blob:find(query, 1, true) ~= nil
end

local function sortLogs(logs, mode)
    table.sort(logs, function(a, b)
        if mode == "member" then
            local av, bv = lower(playerLabel(a)), lower(playerLabel(b))
            if av ~= bv then return av < bv end
        elseif mode == "type" then
            local av, bv = lower(eventLabel(a and a.event)), lower(eventLabel(b and b.event))
            if av ~= bv then return av < bv end
        elseif mode == "detail" then
            local av, bv = lower(detailText(a, true)), lower(detailText(b, true))
            if av ~= bv then return av < bv end
        end

        local at = tonumber(a and a.timestamp) or 0
        local bt = tonumber(b and b.timestamp) or 0
        if at ~= bt then return at > bt end
        return tostring(a and a.key or "") < tostring(b and b.key or "")
    end)
    return logs
end

local function buildBankEntryLookup()
    local entries = GC.Services and GC.Services.DataStore and GC.Services.DataStore.GetGuildBankEntries
        and GC.Services.DataStore:GetGuildBankEntries() or nil
    if type(entries) ~= "table" then
        return nil
    end

    local lookup = {}
    for _, entry in ipairs(entries) do
        local event = entry.kind == "money" and "BANK_MONEY" or "BANK_ITEM"
        local key = table.concat({
            tostring(event),
            tostring(entry.playerKey or entry.playerName or "Unknown"),
            tostring(entry.summary or ""),
        }, "|")
        lookup[key] = entry
    end
    return lookup
end

local function enrichBankActivityLog(entry, bankLookup)
    if not entry or entry.reason ~= "guild-bank" or not bankLookup then
        return entry
    end

    local key = table.concat({
        tostring(entry.event or ""),
        tostring(entry.playerKey or "Unknown"),
        tostring(entry.newValue or ""),
    }, "|")
    local bankEntry = bankLookup[key]
    if not bankEntry then
        return entry
    end

    -- Older mirrored Activity rows used the pull time. When the structured
    -- bank entry is still present, display/search/sort by the original bank
    -- log timestamp instead.
    entry.timestamp = bankEntry.occurredAt or entry.timestamp
    entry.bankKind = entry.bankKind or bankEntry.kind
    entry.bankTransactionType = entry.bankTransactionType or bankEntry.transactionType
    entry.bankTab = entry.bankTab or bankEntry.tabName or bankEntry.tab
    entry.bankCapturedAt = entry.bankCapturedAt or bankEntry.capturedAt
    return entry
end

local function buildLogRow(row, item)
    local Th = T()
    if not row._built then
        local timeFs   = Th.Fs(row, "data", "", "textDimmed")
        timeFs:SetPoint("LEFT", 6, 0); timeFs:SetWidth(104)
        local typeFs   = Th.Fs(row, "small", "", "textAccent")
        typeFs:SetPoint("LEFT", 114, 0); typeFs:SetWidth(90)
        local playerFs = Th.Fs(row, "small", "", "textSecond")
        playerFs:SetPoint("LEFT", 208, 0); playerFs:SetWidth(120)
        local detailFs = Th.Fs(row, "data", "", "textDimmed")
        detailFs:SetPoint("LEFT", 332, 0); detailFs:SetPoint("RIGHT", -6, 0)
        row._timeFs = timeFs; row._typeFs = typeFs
        row._playerFs = playerFs; row._detailFs = detailFs
        row._built = true
    end
    local meta = item.event and EVENT_META[item.event] or {"Event", "textDimmed"}
    local c    = T().c[meta[2]] or T().c.textDimmed
    row._typeFs:SetText(meta[1])
    row._typeFs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    row._timeFs:SetText(item.timestamp and date("%m-%d %H:%M", item.timestamp) or "—")
    row._playerFs:SetText(playerLabel(item))
    local detail = detailText(item, false)
    row._detailFs:SetText(detail)
    row._tooltipTitle = item.timestamp and date("%Y-%m-%d %H:%M", item.timestamp) or eventLabel(item.event)
    local tooltip = {
        "Type: " .. eventLabel(item.event),
        "Member: " .. playerLabel(item),
        "Details: " .. detailText(item, true),
    }
    if item.bankTransactionType then tooltip[#tooltip + 1] = "Bank entry: " .. tostring(item.bankTransactionType) end
    if item.bankTab then tooltip[#tooltip + 1] = "Tab: " .. tostring(item.bankTab) end
    if item.bankCapturedAt then tooltip[#tooltip + 1] = "Pulled: " .. date("%Y-%m-%d %H:%M", item.bankCapturedAt) end
    row._tooltipText = table.concat(tooltip, "\n")
end

-- ─── Create ────────────────────────────────────

function LP:Create(parent)
    if self.frame then return end
    local Th = T()
    local P  = Th.padding

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    frame:Hide()
    self.frame = frame
    Th.Bg(frame, Th.c.bg)

    -- ── Header ───────────────────────────────────
    local hdr = Th.Fs(frame, "header", "Activity Log", "textPrimary")
    hdr:SetPoint("TOPLEFT", P, -P)
    local countFs = Th.Fs(frame, "data", "", "textDimmed")
    countFs:SetPoint("LEFT", hdr, "RIGHT", 10, -2)
    self.countLabel = countFs

    local clearBtn = GC.UI.Button.Create(frame, "Clear Log", "danger", 84, Th.btnH)
    clearBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -P, -P + 2)
    clearBtn:SetTooltip("Clear Activity Log", "Removes all stored activity log entries for the current guild on this client.")
    self.clearBtn = clearBtn
    clearBtn:SetScript("OnClick", function()
        if not LP._clearConfirmArmed then
            LP._clearConfirmArmed = true
            clearBtn:SetLabel("Confirm")
            if GC.UI.MainFrame then
                GC.UI.MainFrame:SetStatus("Click Confirm to clear the activity log.", "textWarn")
            end
            if LP._clearConfirmTimer then
                LP._clearConfirmTimer:Cancel()
            end
            LP._clearConfirmTimer = C_Timer.NewTimer(4, function()
                LP._clearConfirmArmed = false
                if LP.clearBtn then
                    LP.clearBtn:SetLabel("Clear Log")
                end
            end)
            return
        end

        LP._clearConfirmArmed = false
        if LP._clearConfirmTimer then
            LP._clearConfirmTimer:Cancel()
            LP._clearConfirmTimer = nil
        end
        clearBtn:SetLabel("Clear Log")
        local ok = GC.Services.DataStore:ClearLogs()
        if GC.UI.MainFrame then
            GC.UI.MainFrame:SetStatus(ok and "Activity log cleared." or "Unable to clear activity log.", ok and "textWarn" or "textDanger")
        end
        LP:Refresh()
    end)

    -- ── Category filter bar ───────────────────────
    local filterY  = -(P + 40)
    local btnW     = 96
    local btnGap   = 4
    self._filterBtns   = {}
    self._activeFilter = "all"

    for i, cat in ipairs(FILTER_CATS) do
        local btn = GC.UI.Button.Create(frame, cat.label, "secondary", btnW, Th.btnH)
        btn:SetPoint("TOPLEFT", frame, "TOPLEFT", P + (i-1) * (btnW + btnGap), filterY)
        local catId = cat.id
        btn:SetScript("OnClick", function()
            LP._dashboardEventFilter = nil
            LP._characterFilter = nil
            LP._activeFilter = catId
            LP:_updateFilterButtons()
            LP:_applyFilter()
        end)
        self._filterBtns[catId] = btn
    end

    -- ── Search and organization controls ─────────
    local searchY = filterY - Th.btnH - 10
    self.searchBox = GC.UI.Panel.Input(frame, 260, Th.inputH)
    self.searchBox:SetPoint("TOPLEFT", frame, "TOPLEFT", P, searchY)
    self.searchBox:SetMaxLetters(80)
    self.searchHint = Th.Fs(frame, "input", "Search member, date, type, details...", "textDimmed")
    self.searchHint:SetPoint("LEFT", self.searchBox, "LEFT", 7, 0)
    self.searchBox:SetScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        if LP.searchHint then
            LP.searchHint:SetShown(text == "")
        end
        LP._searchText = text
        LP:_applyFilter()
    end)
    self.searchBox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)

    self._sortMode = self._sortMode or "date"
    self._sortBtns = {}
    local sortLabel = Th.Fs(frame, "tiny", "SORT", "textDimmed")
    sortLabel:SetPoint("LEFT", self.searchBox, "RIGHT", 14, 0)
    local sortX = P + 260 + 46
    for i, mode in ipairs(SORT_MODES) do
        local btn = GC.UI.Button.Create(frame, mode.label, "secondary", 70, Th.btnH)
        btn:SetPoint("TOPLEFT", frame, "TOPLEFT", sortX + ((i - 1) * 74), searchY)
        btn:SetScript("OnClick", function()
            LP._sortMode = mode.id
            LP:_updateSortButtons()
            LP:_applyFilter()
        end)
        self._sortBtns[mode.id] = btn
    end

    Th.HSep(frame, searchY - Th.btnH - 6)

    -- ── Column header bar ─────────────────────────
    local colBarY = searchY - Th.btnH - 10
    local colBar  = CreateFrame("Frame", nil, frame)
    colBar:SetPoint("TOPLEFT",  frame, "TOPLEFT",  0, colBarY)
    colBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, colBarY)
    colBar:SetHeight(Th.colBarH)
    Th.Bg(colBar, Th.c.chrome)
    local function colHdr(lbl, x, w)
        local fs = Th.Fs(colBar, "tiny", lbl, "textDimmed")
        fs:SetPoint("LEFT", x, 0); fs:SetWidth(w)
    end
    colHdr("Time",   6,   104)
    colHdr("Event",  114, 90)
    colHdr("Player", 208, 120)
    colHdr("Detail", 332, 200)

    -- ── Scrollable list ───────────────────────────
    local listTop = colBarY - Th.colBarH
    local listFrame = CreateFrame("Frame", nil, frame)
    listFrame:SetPoint("TOPLEFT",     frame, "TOPLEFT",     0, listTop)
    listFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, P)

    self.list = GC.UI.List.Create(listFrame, Th.rowH, buildLogRow, nil, function(item)
        if item and item.playerKey and GC.UI.CharacterContextMenu then
            GC.UI.CharacterContextMenu:Open({
                key = item.playerKey,
                fullName = item.playerKey,
                source = "Activity",
            })
        end
    end)
    self.list:SetEmptyText("No log entries for this filter.")

    self:_updateFilterButtons()
    self:_updateSortButtons()
end

-- ─── internal ─────────────────────────────────

function LP:_updateFilterButtons()
    local Th = T()
    for id, btn in pairs(self._filterBtns) do
        local active = (id == self._activeFilter)
        -- Swap between primary (active) and secondary (inactive) visuals
        if btn._bg then
            local c = active and Th.c.btnPrimary or Th.c.btnSecond
            btn._bg:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
        end
    end
end

function LP:_updateSortButtons()
    local Th = T()
    for id, btn in pairs(self._sortBtns or {}) do
        local active = id == (self._sortMode or "date")
        if btn._bg then
            local c = active and Th.c.btnPrimary or Th.c.btnSecond
            btn._bg:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
        end
    end
end

function LP:_applyFilter()
    if not self._allLogs then return end
    local cat = self._activeFilter
    local selectedLabel = "this filter"
    local filtered
    if cat == "all" then
        filtered = self._allLogs
    else
        local allowed = {}
        for _, c in ipairs(FILTER_CATS) do
            if c.id == cat and c.events then
                allowed = c.events
                selectedLabel = c.label
                break
            end
        end
        filtered = {}
        for _, e in ipairs(self._allLogs) do
            if allowed[e.event] then
                filtered[#filtered + 1] = e
            end
        end
    end
    if self._dashboardEventFilter then
        local eventFiltered = {}
        for _, e in ipairs(filtered) do
            if e.event == self._dashboardEventFilter then
                eventFiltered[#eventFiltered + 1] = e
            end
        end
        filtered = eventFiltered
        selectedLabel = self._dashboardEventFilter == "JOINED" and "joined events" or self._dashboardEventFilter == "LEFT" and "left events" or selectedLabel
    end
    if self._characterFilter then
        local target = tostring(self._characterFilter)
        local characterFiltered = {}
        for _, e in ipairs(filtered) do
            if e.playerKey == target then
                characterFiltered[#characterFiltered + 1] = e
            end
        end
        filtered = characterFiltered
        selectedLabel = "character " .. target
    end
    local searched = {}
    for _, e in ipairs(filtered) do
        if matchesSearch(e, self._searchText) then
            searched[#searched + 1] = e
        end
    end
    filtered = sortLogs(searched, self._sortMode or "date")
    if self.countLabel then
        local total = #self._allLogs
        local shown = #filtered
        if shown == total then
            self.countLabel:SetText("(" .. total .. " entries)")
        else
            self.countLabel:SetText("(" .. shown .. " / " .. total .. " shown)")
        end
    end
    if self.list then
        if cat == "ranks" then
            self.list:SetEmptyText("No promotions or demotions recorded since tracking began.")
        else
            self.list:SetEmptyText("No log entries for " .. selectedLabel .. ".")
        end
    end
    self.list:Refresh(filtered)
end

function LP:ApplyDashboardFilter(filterKey)
    local target = filterKey or "all"
    self._characterFilter = nil
    self._dashboardEventFilter = nil
    if target == "joined" then
        self._dashboardEventFilter = "JOINED"
        target = "roster"
    elseif target == "left" then
        self._dashboardEventFilter = "LEFT"
        target = "roster"
    elseif target == "rank_changes" then
        target = "ranks"
    elseif not self._filterBtns[target] then
        target = "all"
    end
    self._activeFilter = target
    self:_updateFilterButtons()
    self:_updateSortButtons()
    self:_applyFilter()
end

function LP:FocusCharacter(key)
    if not self.frame or not key then return false end
    self._dashboardEventFilter = nil
    self._activeFilter = "all"
    self._characterFilter = key
    self:_updateFilterButtons()
    self:_updateSortButtons()
    self:_applyFilter()
    return true
end

-- ─── Refresh ──────────────────────────────────

function LP:Refresh()
    if not self.frame then return end
    local logs = GS():GetRecentLogs(1000)
    local bankLookup = buildBankEntryLookup()
    for i, e in ipairs(logs) do
        enrichBankActivityLog(e, bankLookup)
        e.key = table.concat({
            tostring(e.timestamp or ""),
            tostring(e.event or ""),
            tostring(e.playerKey or ""),
            tostring(e.newValue or ""),
            tostring(i),
        }, "|")
    end
    self._allLogs = logs
    self:_applyFilter()
end

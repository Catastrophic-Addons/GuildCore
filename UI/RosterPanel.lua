-- UI/RosterPanel.lua
-- Scrollable guild roster with search, online filter, column headers.
local addonName, ns = ...
local GC = ns.GuildCore

GC.UI.RosterPanel = {}
local RP = GC.UI.RosterPanel
GC.UI.Roster = RP

local function T()  return GC.UI.Theme end
local function GS() return GC.Services.GuildService end

local function normalizeFocusName(value)
    value = GC.Utils.Trim(value or "")
    if value == "" then return "" end
    local name = value:match("^([^%-]+)") or value
    return name:lower()
end

local function hideContextMenu()
    if GC.UI and GC.UI.CharacterContextMenu then
        GC.UI.CharacterContextMenu:Close()
    end
    RP.contextItemKey = nil
end

local CLASSIFICATION_ORDER = {
    main = 1,
    alt = 2,
    unknown = 3,
}

local STATUS_ORDER = {
    Online = 1,
    Offline = 2,
}

local RANK_COLORS = {
    officer = "textAccent",
    veteran = "textSuccess",
    raider = "statusActive",
    ["mythic +"] = "textWarn",
    member = "textSecond",
    initiate = "textWarn",
}

local function lowerText(value)
    return tostring(value or ""):lower()
end

local function wipeTable(tbl)
    if wipe then return wipe(tbl) end
    for key in pairs(tbl) do tbl[key] = nil end
    return tbl
end

local function rosterSettings()
    local settings = GC.Services and GC.Services.DataStore and GC.Services.DataStore:GetSettings() or {}
    settings.roster = type(settings.roster) == "table" and settings.roster or {}
    if settings.roster.onlineOnly == nil then settings.roster.onlineOnly = false end
    if settings.roster.groupAlts == nil then settings.roster.groupAlts = false end
    return settings.roster
end

local function saveRosterSetting(key, value)
    local settings = rosterSettings()
    settings[key] = value
end

local function safeNumber(value, fallback)
    local n = tonumber(value)
    if not n or n ~= n then
        return fallback or 0
    end
    return n
end

local SORT_GETTERS = {
    name = function(item)
        return lowerText(item.name or item.key)
    end,
    classification = function(item)
        return CLASSIFICATION_ORDER[item.classification or "unknown"] or 99
    end,
    rankIndex = function(item)
        return safeNumber(item.rankIndex, 999)
    end,
    classDisplayName = function(item)
        return lowerText(item.classDisplayName or item.classFileName or item.classSpecDisplay)
    end,
    level = function(item)
        return safeNumber(item.level, -1)
    end,
    statusLabel = function(item)
        return STATUS_ORDER[item.statusLabel or ""] or 99
    end,
    locationDisplay = function(item)
        return lowerText(item.locationDisplay or item.zone)
    end,
    lastSeenAt = function(item)
        return safeNumber(item.lastSeenAt, 0)
    end,
}

-- Column layout: {label, xOffset, width, field, sortField, sortType}
-- sortField: key into SORT_GETTERS; sortType: "alpha" | "num" | "time"
local COLS = {
    {label = "Name",      x = 10,  w = 134, field = "name",              sortField = "name",            sortType = "alpha", role = "body"},
    {label = "Main/Alt",  x = 152, w = 58,  field = "classificationBadge", sortField = "classification",  sortType = "num", role = "body"},
    {label = "Rank",      x = 218, w = 104, field = "rankShort",          sortField = "rankIndex",       sortType = "num",  role = "body"},
    {label = "Class",     x = 330, w = 142, field = "classSpecDisplay",   sortField = "classDisplayName",sortType = "alpha", role = "body"},
    {label = "Lvl",       x = 458, w = 38,  field = "level",              sortField = "level",           sortType = "num",  role = "body"},
    {label = "Status",    x = 504, w = 74,  field = "statusLabel",        sortField = "statusLabel",     sortType = "num", role = "body"},
    {label = "Location",  x = 586, w = 142, field = "locationDisplay",    sortField = "locationDisplay", sortType = "alpha", role = "body"},
    {label = "Seen",      x = 736, w = 86,  field = "lastSeenDisplay",    sortField = "lastSeenAt",      sortType = "time",  role = "body"},
}

local function buildRow(row, item)
    local Th = T()
    row._tooltipTitle = nil
    row._tooltipText = nil
    if item.hasRelationshipIssue then
        row._tooltipTitle = "Roster Data Issue"
        local issueLines = {}
        for i, issue in ipairs(item.relationshipIssues or {}) do
            if i > 3 then break end
            issueLines[#issueLines + 1] = tostring(issue.message or "Review this character's Main / Alt links.")
        end
        local extra = (item.relationshipIssueCount or 0) - #issueLines
        if extra > 0 then
            issueLines[#issueLines + 1] = "+" .. tostring(extra) .. " more issue" .. (extra == 1 and "" or "s")
        end
        row._tooltipText = #issueLines > 0 and table.concat(issueLines, "\n") or "Review this character's Main / Alt links."
    end

    if not row._cols then
        row._cols = {}
        for i, col in ipairs(COLS) do
            local fs = Th.Fs(row, col.role or "small", "", "textSecond")
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
            fs:ClearAllPoints()
            fs:SetPoint("LEFT", (item._groupIndent and 24 or col.x), 0)
            fs:SetWidth(item._groupIndent and (col.w - 14) or col.w)
            local rgb = item.hasRelationshipIssue and Th.c.textDanger
                or item.isOnline and (item.classRGB or {1, 1, 1})
                or Th.c.textDimmed
            fs:SetTextColor(rgb[1], rgb[2], rgb[3], 1)
            fs:SetText((item.hasRelationshipIssue and "! " or "") .. val)
        elseif col.field == "classificationBadge" then
            local badgeColor = item.hasRelationshipIssue and Th.c.textDanger
                or item.classification == "main" and Th.c.statusActive
                or item.classification == "alt" and Th.c.textWarn
                or item.needsPrompt and Th.c.textDanger
                or Th.c.textDimmed
            fs:SetTextColor(badgeColor[1], badgeColor[2], badgeColor[3], badgeColor[4] or 1)
            fs:SetText(val)
        elseif col.field == "rankShort" then
            local rankKey = GC.Utils.NormalizeRankName(item.rankName or "")
            local c = Th.c[RANK_COLORS[rankKey] or "textSecond"] or Th.c.textSecond
            if not item.isOnline then c = Th.c.textDimmed end
            fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
            fs:SetText(val)
        elseif col.field == "classSpecDisplay" then
            local rgb = item.isOnline and (item.classRGB or Th.c.textDimmed) or Th.c.textDimmed
            fs:SetTextColor(rgb[1] * 0.9, rgb[2] * 0.9, rgb[3] * 0.9, 1)
            fs:SetText(val)
        elseif col.field == "statusLabel" then
            local c = Th.c[item.statusKey] or Th.c.textSecond
            fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
            fs:SetText(val)
        elseif col.field == "lastSeenDisplay" then
            local c = Th.c[item.seenColorKey] or Th.c.textSecond
            fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
            fs:SetText(val)
        else
            local sc = Th.c.textSecond
            fs:SetTextColor(sc[1], sc[2], sc[3], sc[4] or 1)
            fs:SetText(val)
        end
    end
end

-- ─── sort helpers ─────────────────────────────

local _sortPool      = {}  -- pooled entry tables; avoids N allocs per sort call
local _sortDecorated = {}  -- reused decorated array
local _filterRebuildCount = 0
local _groupRebuildCount  = 0

local function applySort(data, sortField, sortType, asc)
    if not sortField then return data end
    local getter = SORT_GETTERS[sortField]
    if not getter then return data end

    local count = 0
    for i = 1, #(data or {}) do
        local item = data[i] or {}
        local value = getter(item)
        if sortType == "num" or sortType == "time" then
            value = safeNumber(value, 0)
        else
            value = lowerText(value)
        end
        count = count + 1
        local e = _sortPool[count]
        if not e then
            e = {}
            _sortPool[count] = e
        end
        e.item  = item
        e.index = i
        e.value = value
        e.name  = lowerText(item.name or item.key)
        e.key   = lowerText(item.key)
        _sortDecorated[count] = e
    end
    for i = count + 1, #_sortDecorated do _sortDecorated[i] = nil end

    local function comesBefore(a, b)
        if not a then return false end
        if not b then return true end

        if a.value ~= b.value then
            return asc and (a.value < b.value) or (a.value > b.value)
        end

        if a.name ~= b.name then
            return a.name < b.name
        end

        if a.key ~= b.key then
            return a.key < b.key
        end

        return a.index < b.index
    end

    -- Avoid WoW's table.sort here. Large roster tables with repeated values
    -- were intermittently tripping "invalid order function" even with a
    -- strict comparator, so this stable insertion sort keeps header toggles
    -- deterministic and Lua-error free.
    for i = 2, count do
        local current = _sortDecorated[i]
        local j = i - 1
        while j >= 1 and comesBefore(current, _sortDecorated[j]) do
            _sortDecorated[j + 1] = _sortDecorated[j]
            j = j - 1
        end
        _sortDecorated[j + 1] = current
    end

    local sorted = {}
    for i = 1, count do
        sorted[i] = _sortDecorated[i].item
    end
    return sorted
end

-- ─── filter helpers ────────────────────────────

local function matchesDashboardFilter(item, filterKey)
    if not filterKey or filterKey == "" or filterKey == "all" then
        return true
    end
    if filterKey == "online" then
        return item.isOnline
    end
    if filterKey == "active" then
        return item.lastSeenAt and (time() - item.lastSeenAt) <= 604800
    end
    if filterKey == "inactive" then
        local threshold = GC.Services.GuildService and GC.Services.GuildService.GetInactivityThresholdDays
            and GC.Services.GuildService:GetInactivityThresholdDays() or 30
        return item.lastSeenAt and (time() - item.lastSeenAt) >= (threshold * 86400)
    end
    if filterKey == "unknown_main_alt" then
        return (item.classification or "unknown") == "unknown"
    end
    if filterKey == "relationship_issues" then
        return item.hasRelationshipIssue == true
    end
    if filterKey == "missing_discord" then
        local discordStatus = item.discordVerificationStatus
        if not discordStatus and GC.Utils and GC.Utils.GetDiscordVerificationStatus then
            discordStatus = GC.Utils.GetDiscordVerificationStatus(item)
        end
        local discordName = item.discordName or ""
        local trimDiscord = GC.Utils and GC.Utils.Trim and GC.Utils.Trim(discordName) or tostring(discordName):match("^%s*(.-)%s*$")
        return discordStatus ~= "skipped"
            and (discordStatus ~= "verified" or trimDiscord == "")
    end
    if filterKey == "initiates" then
        return GC.Utils.NormalizeRankName(item.rankName) == "initiate"
    end
    return true
end

local function itemMatchesSearch(item, query)
    local q = lowerText(query)
    if q == "" then return true end
    item._searchBlob = item._searchBlob or lowerText(
        tostring(item.name or "") .. " " ..
        tostring(item.key or "") .. " " ..
        tostring(item.rankName or "") .. " " ..
        tostring(item.classDisplayName or "") .. " " ..
        tostring(item.classSpecDisplay or "")
    )
    return item._searchBlob:find(q, 1, true)
end

local function itemMatchesLetter(item, letter)
    if not letter or letter == "" then return true end
    local first = tostring(item.name or item.key or ""):sub(1, 1):upper()
    return first == tostring(letter):upper()
end

local function itemMatchesNonTextFilters(item, filters)
    return ((not filters.onlineOnly) or item.isOnline)
        and matchesDashboardFilter(item, filters.dashboardFilter)
        and itemMatchesLetter(item, filters.letter)
end

local function applyFilters(data, filters, out)
    out = wipeTable(out or {})
    local q = filters.searchText or ""
    for _, item in ipairs(data or {}) do
        item._groupIndent = false
        if itemMatchesNonTextFilters(item, filters) and itemMatchesSearch(item, q) then
            out[#out + 1] = item
        end
    end
    return out
end

local function groupRosterRows(sortedData, filters, byKey, emitted, out)
    if not filters.groupAlts or not GC.AltMain or not GC.AltMain.GetGroup then
        return sortedData
    end
    _groupRebuildCount = _groupRebuildCount + 1

    -- Text search keeps the whole visible linked group for context. Online,
    -- dashboard, and letter filters remain row-level filters so they do not
    -- create confusing offline rows inside online-only results.
    byKey = wipeTable(byKey or {})
    emitted = wipeTable(emitted or {})
    out = wipeTable(out or {})
    local searchActive = (filters.searchText or "") ~= ""
    for _, item in ipairs(sortedData or {}) do
        if item.key then byKey[item.key] = item end
    end

    local function groupHasSearchMatch(group)
        local q = filters.searchText or ""
        if q == "" then return true end
        for _, key in ipairs(group.members or {}) do
            if byKey[key] and itemMatchesSearch(byKey[key], q) then
                return true
            end
        end
        return false
    end

    local function emitKey(key, indent)
        local item = byKey[key]
        if item and not emitted[key] and itemMatchesNonTextFilters(item, filters) then
            emitted[key] = true
            item._groupIndent = indent == true
            out[#out + 1] = item
        end
    end

    for _, item in ipairs(sortedData or {}) do
        if item.key and not emitted[item.key] then
            local group = GC.AltMain:GetGroup(item.key)
            if group and group.members and #group.members > 1 then
                if not groupHasSearchMatch(group) then
                    emitted[item.key] = true
                elseif byKey[group.mainKey] then
                    local mainKey = group.mainKey
                    emitKey(mainKey, false)
                    for _, altKey in ipairs(group.alts or {}) do
                        emitKey(altKey, true)
                    end
                else
                    -- Main is not in the currently loaded roster; keep matching
                    -- linked characters as normal rows rather than inventing data.
                    for _, memberKey in ipairs(group.members or {}) do
                        emitKey(memberKey, false)
                    end
                end
            elseif not searchActive or itemMatchesSearch(item, filters.searchText) then
                emitKey(item.key, false)
            else
                emitted[item.key] = true
            end
        end
    end

    return out
end

local function selectRosterItem(item, scrollToSelection)
    if not item then
        return false
    end
    hideContextMenu()
    GC.UI.PlayerPanel:SetPlayer(item)
    GC.UI.PlayerPanel:Refresh()
    if RP.list then
        RP.list:SetSelected(item.key, scrollToSelection)
    end
    return true
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

    local countFs = Th.Fs(frame, "data", "", "textDimmed")
    countFs:SetPoint("LEFT", hdr, "RIGHT", 10, -2)
    self.countLabel = countFs
    local savedFilters = rosterSettings()
    self.filters = {
        onlineOnly = savedFilters.onlineOnly == true,
        searchText = "",
        letter = savedFilters.lastLetterFilter,
        groupAlts = savedFilters.groupAlts == true,
        dashboardFilter = nil,
    }
    self._scratchFilter = {}
    self._scratchGroup = {}
    self._scratchSortSource = {}
    self._scratchGroupByKey = {}
    self._scratchGroupEmitted = {}

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
    hint:SetPoint("LEFT", searchBox, "LEFT", 6, 0)   -- match Panel.Input text insets
    hint:SetPoint("RIGHT", searchBox, "RIGHT", -6, 0)
    searchBox:SetScript("OnTextChanged", function(eb)
        hint:SetShown(eb:GetText() == "")
        RP.filters.searchText = eb:GetText() or ""
        RP:ScheduleApplyFilters("search")
    end)
    searchBox:SetScript("OnEditFocusGained", function() hint:Hide() end)
    searchBox:SetScript("OnEditFocusLost",   function(eb) hint:SetShown(eb:GetText() == "") end)
    self.searchBox = searchBox

    -- Online filter button
    local onlineBtn = GC.UI.Button.Create(frame, "Online Only", "secondary", 110, Th.btnH)
    onlineBtn:SetPoint("LEFT", searchBox, "RIGHT", P, 0)
    onlineBtn:SetTooltip("Toggle Online Filter", "Show only members who were online in the last scan.")
    onlineBtn:SetScript("OnClick", function()
        self.filters.onlineOnly = not self.filters.onlineOnly
        saveRosterSetting("onlineOnly", self.filters.onlineOnly)
        RP:ApplyFilters()
    end)
    self.onlineBtn = onlineBtn

    local groupBtn = GC.UI.Button.Create(frame, "Group Alts", "secondary", 92, Th.btnH)
    groupBtn:SetPoint("LEFT", onlineBtn, "RIGHT", P/2, 0)
    groupBtn:SetTooltip("Group Linked Characters", "Show linked main/alt characters together in the roster.")
    groupBtn:SetScript("OnClick", function()
        self.filters.groupAlts = not self.filters.groupAlts
        saveRosterSetting("groupAlts", self.filters.groupAlts)
        RP:ApplyFilters()
    end)
    self.groupBtn = groupBtn

    local clearBtn = GC.UI.Button.Create(frame, "Clear Filters", "secondary", 96, Th.btnH)
    clearBtn:SetPoint("LEFT", groupBtn, "RIGHT", P/2, 0)
    clearBtn:SetTooltip("Clear Filters", "Clear search, alphabet, online, and dashboard filters.")
    clearBtn:SetScript("OnClick", function()
        RP:ClearFilters()
    end)
    self.clearBtn = clearBtn

    -- Refresh button
    local refreshBtn = GC.UI.Button.Create(frame, "Refresh", "secondary", 92, Th.btnH)
    refreshBtn:SetPoint("LEFT", clearBtn, "RIGHT", P/2, 0)
    refreshBtn:SetTooltip("Refresh Roster", "Request a live roster update from the server.")
    refreshBtn:SetScript("OnClick", function()
        local ok, err = GC.Services.GuildService:TriggerScan()
        local mf = GC.UI.MainFrame
        if mf then
            mf:SetStatus(ok and "Roster scan requested…" or (err or "Unable to scan."), ok and "textWarn" or "textDanger")
        end
    end)

    local importBtn = GC.UI.Button.Create(frame, "Import GRM", "secondary", 96, Th.btnH)
    importBtn:SetPoint("LEFT", refreshBtn, "RIGHT", P/2, 0)
    importBtn:SetTooltip("Import GRM Export", "Paste a Guild Roster Manager export and preview safe local metadata updates.")
    importBtn:SetScript("OnClick", function()
        if GC.UI.GRMImportPopup then
            GC.UI.GRMImportPopup:Open()
        end
    end)

    -- Alphabet quick filter
    local alphaY = toolbarY - Th.btnH - 8
    local alphaRow = CreateFrame("Frame", nil, frame)
    alphaRow:SetPoint("TOPLEFT", frame, "TOPLEFT", P, alphaY)
    alphaRow:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -P, alphaY)
    alphaRow:SetHeight(22)
    self.alphaButtons = {}
    local letters = {"All", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z"}
    local x = 0
    for _, label in ipairs(letters) do
        local letterLabel = label
        local width = letterLabel == "All" and 34 or 22
        local btn = GC.UI.Button.Create(alphaRow, letterLabel, "secondary", width, 20)
        btn:SetPoint("LEFT", alphaRow, "LEFT", x, 0)
        btn:SetScript("OnClick", function()
            self.filters.letter = letterLabel == "All" and nil or letterLabel
            saveRosterSetting("lastLetterFilter", self.filters.letter)
            RP:ApplyFilters("letter")
        end)
        self.alphaButtons[letterLabel] = btn
        x = x + width + 3
    end

    Th.HSep(frame, alphaY - 26)

    -- ── Column header bar ────────────────────────
    local colBarY = alphaY - 30
    local colBar  = CreateFrame("Frame", nil, frame)
    colBar:SetPoint("TOPLEFT",  frame, "TOPLEFT",  0, colBarY)
    colBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, colBarY)
    colBar:SetHeight(Th.colBarH)
    Th.Bg(colBar, Th.c.chrome)

    self._sortKey = nil
    self._sortAsc = true
    self._headerLabels = {}

    for i, col in ipairs(COLS) do
        local btn = CreateFrame("Button", nil, colBar)
        btn:SetPoint("LEFT", col.x, 0)
        btn:SetSize(col.w, Th.colBarH)
        btn:EnableMouse(true)

        local hf = Th.Fs(colBar, "tiny", col.label, "textDimmed")
        hf:SetPoint("LEFT", btn, "LEFT", 0, 0)
        hf:SetWidth(col.w)
        hf:SetJustifyH("LEFT")
        self._headerLabels[i] = hf

        btn:SetScript("OnEnter", function()
            local c = T().c.textAccent
            hf:SetTextColor(c[1], c[2], c[3], 1)
        end)
        btn:SetScript("OnLeave", function()
            RP:_refreshHeaderLabels()
        end)
        btn:SetScript("OnClick", function()
            if RP._sortKey == col.sortField then
                RP._sortAsc = not RP._sortAsc
            else
                RP._sortKey = col.sortField
                RP._sortType = col.sortType
                RP._sortAsc  = true
            end
            RP:ApplyFilters()
        end)
    end

    -- ── Scrollable list ──────────────────────────
    local listTop = colBarY - Th.colBarH
    local listFrame = CreateFrame("Frame", nil, frame)
    listFrame:SetPoint("TOPLEFT",     frame, "TOPLEFT",     0, listTop)
    listFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, P)
    self.listFrame = listFrame

    self.list = GC.UI.List.Create(listFrame, 36, buildRow, function(item)
        selectRosterItem(item, false)
    end, function(item)
        if GC.UI.CharacterContextMenu then
            item.source = "Roster"
            GC.UI.CharacterContextMenu:Open(item)
        end
    end)
    self.list:SetEmptyText("No members match the current filter.")
    self:_refreshFilterControls()
end

function RP:ScheduleApplyFilters(reason)
    if not C_Timer then
        self:ApplyFilters(reason)
        return
    end
    if self._filterDebounceTimer and self._filterDebounceTimer.Cancel then
        self._filterDebounceTimer:Cancel()
    end
    self._filterDebounceToken = (self._filterDebounceToken or 0) + 1
    local token = self._filterDebounceToken
    local callback = function()
        RP._filterDebounceTimer = nil
        if RP._filterDebounceToken == token then
            RP:ApplyFilters(reason or "debounced")
        end
    end
    if C_Timer.NewTimer then
        self._filterDebounceTimer = C_Timer.NewTimer(0.18, callback)
    elseif C_Timer.After then
        C_Timer.After(0.18, callback)
    else
        self:ApplyFilters(reason)
    end
end

-- ─── internal filter/refresh ──────────────────

function RP:_refreshHeaderLabels()
    if not self._headerLabels then return end
    local Th = T()
    for i, col in ipairs(COLS) do
        local hf = self._headerLabels[i]
        if not hf then break end
        if col.sortField == self._sortKey then
            local c = Th.c.textAccent
            hf:SetTextColor(c[1], c[2], c[3], 1)
            hf:SetText(col.label .. (self._sortAsc and " ▲" or " ▼"))
        else
            local c = Th.c.textDimmed
            hf:SetTextColor(c[1], c[2], c[3], 1)
            hf:SetText(col.label)
        end
    end
end

function RP:_refreshFilterControls()
    local filters = self.filters or {}
    if self.onlineBtn then
        self.onlineBtn:SetLabel(filters.onlineOnly and "Show All" or "Online Only")
    end
    if self.groupBtn then
        self.groupBtn:SetLabel(filters.groupAlts and "Ungroup" or "Group Alts")
    end
    if self.alphaButtons then
        local Th = T()
        for label, btn in pairs(self.alphaButtons) do
            local active = (label == "All" and not filters.letter) or label == filters.letter
            if btn.SetButtonState then
                btn:SetButtonState(active and "PUSHED" or "NORMAL")
            end
            if btn.SetAlpha then
                btn:SetAlpha(active and 1 or 0.72)
            end
            if btn.SetBackdropBorderColor and Th.c then
                local c = active and Th.c.accent or Th.c.border
                btn:SetBackdropBorderColor(c[1], c[2], c[3], c[4] or 1)
            end
        end
    end
end

function RP:_filterStatusParts()
    local filters = self.filters or {}
    local parts = {}
    parts[#parts + 1] = filters.onlineOnly and "Online Only" or "Showing All"
    if filters.letter then parts[#parts + 1] = "Letter " .. filters.letter end
    if filters.searchText and filters.searchText ~= "" then parts[#parts + 1] = "Search \"" .. filters.searchText .. "\"" end
    if filters.groupAlts then parts[#parts + 1] = "Grouped" end
    if filters.dashboardFilter then
        local labels = {
            active = "Active",
            inactive = "Inactive",
            unknown_main_alt = "Unknown Main/Alt",
            missing_discord = "Missing Discord",
            initiates = "Initiates",
        }
        parts[#parts + 1] = labels[filters.dashboardFilter] or tostring(filters.dashboardFilter)
    end
    return table.concat(parts, " · ")
end

function RP:ApplyFilters(reason)
    if not self._allData then return end
    _filterRebuildCount = _filterRebuildCount + 1
    local memBefore = GC.Perf and GC.Perf:Snapshot("Roster ApplyFilters before")
    self.filters = self.filters or {}
    self.filters.searchText = self.searchBox and (self.searchBox:GetText() or "") or (self.filters.searchText or "")
    self.filters.dashboardFilter = self._dashboardFilter

    local sortSource
    if self.filters.groupAlts and self.filters.searchText ~= "" then
        -- Search in grouped mode should include linked context, so delay text
        -- filtering until group assembly can inspect the full linked set.
        sortSource = wipeTable(self._scratchSortSource or {})
        self._scratchSortSource = sortSource
        for _, item in ipairs(self._allData or {}) do
            item._groupIndent = false
            if itemMatchesNonTextFilters(item, self.filters) then
                sortSource[#sortSource + 1] = item
            end
        end
    else
        sortSource = applyFilters(self._allData, self.filters, self._scratchFilter)
        self._scratchFilter = sortSource
    end

    local filtered = applySort(sortSource, self._sortKey, self._sortType, self._sortAsc)
    filtered = groupRosterRows(filtered, self.filters, self._scratchGroupByKey, self._scratchGroupEmitted, self._scratchGroup)
    self._scratchGroup = filtered
    self._filteredData = filtered
    if self.countLabel then
        local total = #self._allData
        local shown = #filtered
        self.countLabel:SetText("(" .. shown .. " / " .. total .. " shown) · " .. self:_filterStatusParts())
    end
    self:_refreshFilterControls()
    self:_refreshHeaderLabels()
    self.list:Refresh(filtered)
    if GC.Perf then GC.Perf:Delta("Roster ApplyFilters after" .. (reason and (" (" .. tostring(reason) .. ")") or ""), memBefore) end
end

RP._applyFilter = RP.ApplyFilters

function RP:ClearFilters()
    self._dashboardFilter = nil
    self.filters = self.filters or {}
    self.filters.onlineOnly = false
    self.filters.letter = nil
    self.filters.searchText = ""
    if self.searchBox then self.searchBox:SetText("") end
    saveRosterSetting("onlineOnly", false)
    saveRosterSetting("lastLetterFilter", nil)
    self:ApplyFilters()
end

function RP:ApplyDashboardFilter(filterKey)
    self._dashboardFilter = filterKey ~= "all" and filterKey or nil
    self.filters = self.filters or {}
    self.filters.onlineOnly = filterKey == "online"
    self.filters.letter = nil
    self.filters.searchText = ""
    if self.searchBox then self.searchBox:SetText("") end
    saveRosterSetting("onlineOnly", self.filters.onlineOnly)
    saveRosterSetting("lastLetterFilter", nil)
    self:ApplyFilters()
end

-- ─── Refresh ──────────────────────────────────

function RP:Refresh()
    if not self.frame then return end
    local memBefore = GC.Perf and GC.Perf:Snapshot("Roster Refresh before")
    self._allData = GS():GetRosterList()
    self:ApplyFilters("refresh")
    if GC.Perf then GC.Perf:Delta("Roster Refresh after", memBefore) end
end

function RP:GetListStats()
    local stats = {}
    if self.list and self.list.GetStats then
        stats = self.list:GetStats()
    else
        stats.totalCreated = 0
        stats.pooledRows   = 0
        stats.visibleRows  = 0
    end
    stats.allDataCount       = #(self._allData or {})
    stats.filteredCount      = #(self._filteredData or {})
    stats.filterRebuildCount = _filterRebuildCount
    stats.groupRebuildCount  = _groupRebuildCount
    stats.sortPoolSize       = #_sortPool
    return stats
end

-- Fields that should never contain full player/member objects in display rows.
local _NESTED_FIELDS = {"member", "data", "group", "alts", "children"}

local function isMemberObject(v)
    -- A table is considered a "full member object" only if it has both .key
    -- and .name as strings (player record shape). String-key arrays like
    -- row.alts = {"Alt1-Realm"} are lightweight and intentionally allowed.
    if type(v) ~= "table" then return false end
    if type(v.key) == "string" and type(v.name) == "string" then return true end
    -- Array of member objects: first element is itself a member object
    if v[1] ~= nil and type(v[1]) == "table"
       and type(v[1].key) == "string" and type(v[1].name) == "string" then
        return true
    end
    return false
end

function RP:DumpStats()
    local allData     = self._allData or {}
    local filtered    = self._filteredData or {}
    local mainRows, altRows, unlinkedRows, indentedRows = 0, 0, 0, 0
    local nestedTableRows = 0

    for _, row in ipairs(filtered) do
        local cls = row.classification or "unknown"
        if cls == "main" then
            mainRows = mainRows + 1
        elseif cls == "alt" then
            altRows = altRows + 1
            if row._groupIndent then indentedRows = indentedRows + 1 end
        else
            unlinkedRows = unlinkedRows + 1
        end
        for _, f in ipairs(_NESTED_FIELDS) do
            if isMemberObject(row[f]) then
                nestedTableRows = nestedTableRows + 1
                break
            end
        end
    end

    local totalAltLinks = 0
    local players = GC.Services and GC.Services.DataStore and GC.Services.DataStore:GetPlayers() or {}
    for _, p in pairs(players) do
        if type(p.alts) == "table" then totalAltLinks = totalAltLinks + #p.alts end
    end

    local gs    = GC.AltMain and GC.AltMain.GetGroupCacheStats and GC.AltMain:GetGroupCacheStats() or {}
    local sPool = #_sortPool

    return {
        allDataCount      = #allData,
        filteredCount     = #filtered,
        mainRows          = mainRows,
        altRows           = altRows,
        unlinkedRows      = unlinkedRows,
        indentedRows      = indentedRows,
        nestedTableRows   = nestedTableRows,
        totalAltLinks     = totalAltLinks,
        filterRebuildCount = _filterRebuildCount,
        groupRebuildCount  = _groupRebuildCount,
        sortPoolSize       = sPool,
        groupCacheChars    = gs.cachedCharacters or 0,
        groupCacheGroups   = gs.cachedGroups     or 0,
        maxGroupSize       = gs.maxGroupSize     or 0,
        groupCacheValid    = gs.isCacheValid      or false,
        altDataVersion     = gs.altDataVersion   or 0,
        repairVersion      = gs.repairVersion    or 0,
    }
end

function RP:FocusCharacter(value)
    if not self.frame then
        return false, "Roster panel is unavailable."
    end

    if not self._allData then
        self._allData = GS():GetRosterList()
    end

    local target = GC.Utils.Trim(value or "")
    local targetName = normalizeFocusName(target)
    local found = nil

    for _, item in ipairs(self._allData or {}) do
        if item.key == target then
            found = item
            break
        end
    end

    if not found and targetName ~= "" then
        for _, item in ipairs(self._allData or {}) do
            if normalizeFocusName(item.name or item.key) == targetName then
                found = item
                break
            end
        end
    end

    if not found then
        return false, "Character not found in roster: " .. tostring(value or "")
    end

    local visible = false
    for _, item in ipairs(self._filteredData or {}) do
        if item.key == found.key then
            visible = true
            break
        end
    end

    if not visible then
        if self.searchBox then
            self.searchBox:SetText("")
        end
        self.filters = self.filters or {}
        if self.filters.onlineOnly then
            self.filters.onlineOnly = false
            saveRosterSetting("onlineOnly", false)
        end
        if self.filters.letter then
            self.filters.letter = nil
            saveRosterSetting("lastLetterFilter", nil)
        end
        self:ApplyFilters()
    end

    return selectRosterItem(found, true)
end

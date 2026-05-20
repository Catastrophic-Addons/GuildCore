-- /GuildCore/UI/BanBookPanel.lua
-- Officer moderation UI for the centralized invite ban database.
local addonName, ns = ...
local GC = ns.GuildCore

GC.UI.BanBookPanel = {}
local BP = GC.UI.BanBookPanel

local function T() return GC.UI.Theme end
local function BB() return GC.BanBook end

local function trim(value)
    return GC.Utils and GC.Utils.Trim and GC.Utils.Trim(value or "") or tostring(value or ""):match("^%s*(.-)%s*$")
end

local function fmtDate(ts)
    ts = tonumber(ts)
    if not ts then return "" end
    return date("%Y-%m-%d", ts)
end

local COLS = {
    { label = "Name-Realm", x = 10,  w = 190 },
    { label = "Reason",     x = 210, w = 270 },
    { label = "Date Added", x = 490, w = 92  },
    { label = "Added By",   x = 590, w = 150 },
    { label = "State",      x = 748, w = 70  },
}

local function status(parent, message, colorKey)
    if GC.UI and GC.UI.MainFrame and GC.UI.MainFrame.SetStatus then
        GC.UI.MainFrame:SetStatus(message, colorKey)
    end
end

local function makeLabel(parent, text)
    local fs = T().Fs(parent, "tiny", text, "textDimmed")
    fs:SetJustifyH("LEFT")
    return fs
end

local function buildEntryRow(row, item)
    local Th = T()
    if not row._built then
        row._name = Th.Fs(row, "small", "", "textPrimary")
        row._name:SetPoint("LEFT", COLS[1].x, 0)
        row._name:SetWidth(COLS[1].w)

        row._reason = Th.Fs(row, "small", "", "textSecond")
        row._reason:SetPoint("LEFT", COLS[2].x, 0)
        row._reason:SetWidth(COLS[2].w)

        row._date = Th.Fs(row, "data", "", "textDimmed")
        row._date:SetPoint("LEFT", COLS[3].x, 0)
        row._date:SetWidth(COLS[3].w)

        row._addedBy = Th.Fs(row, "data", "", "textDimmed")
        row._addedBy:SetPoint("LEFT", COLS[4].x, 0)
        row._addedBy:SetWidth(COLS[4].w)

        row._state = Th.Fs(row, "data", "", "textDimmed")
        row._state:SetPoint("LEFT", COLS[5].x, 0)
        row._state:SetWidth(COLS[5].w)
        row._built = true
    end

    row._name:SetText(item and item.key or "")
    row._reason:SetText(item and item.reason or "")
    row._date:SetText(fmtDate(item and item.addedAt))
    row._addedBy:SetText(item and item.addedBy or "")
    row._state:SetText(item and item.active == false and "Inactive" or "Active")
    local color = item and item.active == false and Th.c.textDimmed or Th.c.textPrimary
    row._name:SetTextColor(color[1], color[2], color[3], color[4] or 1)

    row:SetScript("OnEnter", function(self)
        local h = Th.c.rowHover
        self._hov:SetColorTexture(h[1], h[2], h[3], h[4])
        self._hov:SetAlpha(1)
        if item and trim(item.notes) ~= "" then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(item.key or "Ban Book Entry", 1, 1, 1, 1, true)
            GameTooltip:AddLine(item.notes, 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function(self)
        self._hov:SetAlpha(0)
        GameTooltip:Hide()
    end)
end

function BP:_clearForm()
    self.selectedKey = nil
    if self.nameBox then self.nameBox:SetText("") end
    if self.realmBox then self.realmBox:SetText((GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or "") end
    if self.reasonBox then self.reasonBox:SetText("") end
    if self.notesBox then self.notesBox:SetText("") end
    if self.activeBtn then
        self.activeBtn._inactive = false
        if self.activeBtn.SetLabel then self.activeBtn:SetLabel("Active: On") end
    end
    if self.entryList then self.entryList:SetSelected(nil) end
    self:_updateButtons()
end

function BP:_populateForm(entry)
    if not entry then return end
    self.selectedKey = entry.key
    self.nameBox:SetText(entry.name or "")
    self.realmBox:SetText(entry.realm or "")
    self.reasonBox:SetText(entry.reason or "")
    self.notesBox:SetText(entry.notes or "")
    if self.activeBtn then
        self.activeBtn._inactive = entry.active == false
        if self.activeBtn.SetLabel then
            self.activeBtn:SetLabel(entry.active == false and "Active: Off" or "Active: On")
        end
    end
    self:_updateButtons()
end

function BP:_formActive()
    return not (self.activeBtn and self.activeBtn._inactive == true)
end

function BP:_formData()
    return {
        name = self.nameBox and self.nameBox:GetText() or "",
        realm = self.realmBox and self.realmBox:GetText() or "",
        reason = self.reasonBox and self.reasonBox:GetText() or "",
        notes = self.notesBox and self.notesBox:GetText() or "",
        active = self:_formActive(),
    }
end

function BP:_addBan()
    local data = self:_formData()
    local ok, entry, updated = BB():Add(data.name, data.realm, data.reason, data.notes)
    if not ok then
        status(self.frame, entry or "Unable to add Ban Book entry.", "textDanger")
        return
    end
    BB():Update(entry.key, { active = data.active })
    entry.active = data.active
    self.selectedKey = entry.key
    self:_refreshList(true)
    status(self.frame, updated and "Ban Book entry updated." or "Ban Book entry added.", "textSuccess")
end

function BP:_editBan()
    if not self.selectedKey then
        status(self.frame, "Select a Ban Book entry first.", "textWarn")
        return
    end
    local data = self:_formData()
    local ok, entryOrErr = BB():Update(self.selectedKey, data)
    if not ok then
        status(self.frame, entryOrErr or "Unable to update Ban Book entry.", "textDanger")
        return
    end
    self.selectedKey = entryOrErr.key
    self:_refreshList(true)
    status(self.frame, "Ban Book entry updated.", "textSuccess")
end

function BP:_removeBan()
    if not self.selectedKey then
        status(self.frame, "Select a Ban Book entry first.", "textWarn")
        return
    end
    StaticPopupDialogs.GUILDCORE_REMOVE_BAN_BOOK = StaticPopupDialogs.GUILDCORE_REMOVE_BAN_BOOK or {
        text = "Remove this Ban Book entry?",
        button1 = "Remove",
        button2 = "Cancel",
        OnAccept = function(_, key)
            local ok, err = BB():Remove(key)
            if ok then
                BP:_clearForm()
                BP:_refreshList()
                status(BP.frame, "Ban Book entry removed.", "textWarn")
            else
                status(BP.frame, err or "Unable to remove Ban Book entry.", "textDanger")
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    StaticPopup_Show("GUILDCORE_REMOVE_BAN_BOOK", nil, nil, self.selectedKey)
end

function BP:_matchesFilter(entry)
    local search = self.searchBox and trim(self.searchBox:GetText() or ""):lower() or ""
    local realm = self.realmFilterBox and trim(self.realmFilterBox:GetText() or ""):lower() or ""
    if self.activeOnlyBtn and self.activeOnlyBtn._showActiveOnly == true and entry.active == false then
        return false
    end
    if realm ~= "" and tostring(entry.realm or ""):lower():find(realm, 1, true) == nil then
        return false
    end
    if search == "" then
        return true
    end
    local haystack = table.concat({
        entry.key or "",
        entry.reason or "",
        entry.notes or "",
        entry.addedBy or "",
    }, "\n"):lower()
    return haystack:find(search, 1, true) ~= nil
end

function BP:_filteredEntries()
    local rows = {}
    for _, entry in ipairs(BB():GetAll()) do
        if self:_matchesFilter(entry) then
            rows[#rows + 1] = entry
        end
    end
    return rows
end

function BP:_refreshList(scrollToSelection)
    if not self.entryList then return end
    local rows = self:_filteredEntries()
    self.entryList:Refresh(rows)
    self.entryList:SetSelected(self.selectedKey, scrollToSelection)
    if self.countFs then
        self.countFs:SetText(string.format("%d entries", #rows))
    end
    self:_updateButtons()
end

function BP:_updateButtons()
    local hasSelection = self.selectedKey ~= nil
    if self.editBtn then self.editBtn:SetEnabled(hasSelection) end
    if self.removeBtn then self.removeBtn:SetEnabled(hasSelection) end
end

function BP:Create(parent)
    if self.frame then return end
    local Th = T()
    local P = Th.padding or 10
    local btnH = Th.btnH or 24
    local inputH = Th.inputH or 22

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    frame:Hide()
    self.frame = frame
    Th.Bg(frame, Th.c.bg)

    local hdr = Th.Fs(frame, "subheader", "Ban Book", "textAccent")
    hdr:SetPoint("TOPLEFT", frame, "TOPLEFT", P, -P)
    hdr:SetHeight(20)

    local sub = Th.Fs(frame, "small", "Officer moderation list. Active entries are blocked from every Guild Core invite path.", "textDimmed")
    sub:SetPoint("LEFT", hdr, "RIGHT", 10, 0)
    sub:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -P, -P)
    sub:SetHeight(20)

    local form = CreateFrame("Frame", nil, frame)
    form:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", 0, -12)
    form:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -P, 0)
    form:SetHeight(126)
    Th.Bg(form, Th.c.panel, Th.c.border)

    local x, y = 10, -10
    local nameLbl = makeLabel(form, "Character Name")
    nameLbl:SetPoint("TOPLEFT", x, y)
    self.nameBox = GC.UI.Panel.Input(form, 170, inputH)
    self.nameBox:SetPoint("TOPLEFT", x, y - 16)
    self.nameBox:SetMaxLetters(32)

    local realmLbl = makeLabel(form, "Realm")
    realmLbl:SetPoint("TOPLEFT", self.nameBox, "TOPRIGHT", 10, 16)
    self.realmBox = GC.UI.Panel.Input(form, 150, inputH)
    self.realmBox:SetPoint("LEFT", self.nameBox, "RIGHT", 10, 0)
    self.realmBox:SetMaxLetters(32)

    local reasonLbl = makeLabel(form, "Reason Banned")
    reasonLbl:SetPoint("TOPLEFT", self.realmBox, "TOPRIGHT", 10, 16)
    self.reasonBox = GC.UI.Panel.Input(form, 330, inputH)
    self.reasonBox:SetPoint("LEFT", self.realmBox, "RIGHT", 10, 0)
    self.reasonBox:SetMaxLetters(120)

    local notesLbl = makeLabel(form, "Ban Notes")
    notesLbl:SetPoint("TOPLEFT", x, -62)
    self.notesBox = GC.UI.Panel.Input(form, 670, inputH)
    self.notesBox:SetPoint("TOPLEFT", x, -78)
    self.notesBox:SetMaxLetters(240)

    self.activeBtn = GC.UI.Button.Create(form, "Active: On", "secondary", 92, btnH)
    self.activeBtn:SetPoint("LEFT", self.notesBox, "RIGHT", 10, 0)
    self.activeBtn:SetScript("OnClick", function(btn)
        btn._inactive = not (btn._inactive == true)
        btn:SetLabel(btn._inactive and "Active: Off" or "Active: On")
    end)

    self.addBtn = GC.UI.Button.Create(form, "Add Ban", "primary", 82, btnH)
    self.addBtn:SetPoint("TOPRIGHT", form, "TOPRIGHT", -218, -22)
    self.addBtn:SetScript("OnClick", function() BP:_addBan() end)

    self.editBtn = GC.UI.Button.Create(form, "Edit Ban", "secondary", 82, btnH)
    self.editBtn:SetPoint("LEFT", self.addBtn, "RIGHT", 6, 0)
    self.editBtn:SetScript("OnClick", function() BP:_editBan() end)

    self.removeBtn = GC.UI.Button.Create(form, "Remove Ban", "danger", 96, btnH)
    self.removeBtn:SetPoint("TOPRIGHT", form, "TOPRIGHT", -218, -58)
    self.removeBtn:SetScript("OnClick", function() BP:_removeBan() end)

    self.clearBtn = GC.UI.Button.Create(form, "Clear Form", "secondary", 96, btnH)
    self.clearBtn:SetPoint("LEFT", self.removeBtn, "RIGHT", 6, 0)
    self.clearBtn:SetScript("OnClick", function() BP:_clearForm() end)

    local filterRow = CreateFrame("Frame", nil, frame)
    filterRow:SetPoint("TOPLEFT", form, "BOTTOMLEFT", 0, -10)
    filterRow:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -P, 0)
    filterRow:SetHeight(btnH)

    local searchLbl = makeLabel(filterRow, "Search")
    searchLbl:SetPoint("LEFT", filterRow, "LEFT", 0, 0)
    self.searchBox = GC.UI.Panel.Input(filterRow, 250, inputH)
    self.searchBox:SetPoint("LEFT", searchLbl, "RIGHT", 8, 0)
    self.searchBox:SetScript("OnTextChanged", function() BP:_refreshList() end)

    local realmFilterLbl = makeLabel(filterRow, "Realm")
    realmFilterLbl:SetPoint("LEFT", self.searchBox, "RIGHT", 18, 0)
    self.realmFilterBox = GC.UI.Panel.Input(filterRow, 170, inputH)
    self.realmFilterBox:SetPoint("LEFT", realmFilterLbl, "RIGHT", 8, 0)
    self.realmFilterBox:SetScript("OnTextChanged", function() BP:_refreshList() end)

    self.activeOnlyBtn = GC.UI.Button.Create(filterRow, "Active Only", "secondary", 96, btnH)
    self.activeOnlyBtn:SetPoint("LEFT", self.realmFilterBox, "RIGHT", 10, 0)
    self.activeOnlyBtn._showActiveOnly = false
    self.activeOnlyBtn:SetScript("OnClick", function(btn)
        btn._showActiveOnly = not (btn._showActiveOnly == true)
        btn:SetLabel(btn._showActiveOnly and "Active: Only" or "Active Only")
        BP:_refreshList()
    end)

    self.countFs = Th.Fs(filterRow, "data", "", "textDimmed")
    self.countFs:SetPoint("RIGHT", filterRow, "RIGHT", 0, 0)

    local colBar = CreateFrame("Frame", nil, frame)
    colBar:SetPoint("TOPLEFT", filterRow, "BOTTOMLEFT", 0, -8)
    colBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -P, 0)
    colBar:SetHeight(20)
    Th.Bg(colBar, Th.c.chrome)
    for _, col in ipairs(COLS) do
        local fs = Th.Fs(colBar, "tiny", col.label, "textDimmed")
        fs:SetPoint("LEFT", colBar, "LEFT", col.x, 0)
        fs:SetWidth(col.w)
    end

    local listHost = CreateFrame("Frame", nil, frame)
    listHost:SetPoint("TOPLEFT", colBar, "BOTTOMLEFT", 0, -2)
    listHost:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -P, P)
    self.entryList = GC.UI.List.Create(listHost, 28, buildEntryRow, function(item)
        BP:_populateForm(item)
    end)
    self.entryList:SetEmptyText("No Ban Book entries match the current filter.")

    self:_clearForm()
end

function BP:Refresh()
    if not self.frame then return end
    if BB() and BB().Init then BB():Init() end
    self:_refreshList()
end

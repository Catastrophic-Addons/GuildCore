-- /GuildCore/UI/RosterGRMImportPopup.lua
local addonName, ns = ...
local GC = ns.GuildCore

GC.UI.GRMImportPopup = {}
local Popup = GC.UI.GRMImportPopup

local function T() return GC.UI.Theme end

local OPTION_ROWS = {
    {"joinDate", "Join dates"},
    {"promoDate", "Promotion dates"},
    {"rankHistory", "Rank history snapshot"},
    {"publicNote", "Public notes"},
    {"officerNote", "Officer notes"},
    {"customNote", "Custom notes"},
    {"discord", "Discord from notes"},
    {"mainAlt", "Main/Alt status"},
    {"noteMainAltHints", "Main/Alt note hints"},
    {"altLinks", "Alt links"},
    {"birthday", "Birthday"},
    {"mythicScore", "Mythic+ score"},
    {"guildRep", "Guild rep"},
    {"referenceInfo", "Class/race/level/faction"},
    {"lastOnlineSnapshot", "Last-online snapshot"},
    {"autoMainStandalone", "Auto-mark standalone Main"},
}

local MODES = {
    { id = "fill", label = "Fill blanks only" },
    { id = "overwrite", label = "Overwrite existing" },
    { id = "skipExisting", label = "Skip existing" },
    { id = "preview", label = "Preview only" },
}

local function status(message, colorKey)
    if GC.UI and GC.UI.MainFrame then
        GC.UI.MainFrame:SetStatus(message, colorKey or "textDimmed")
    end
end

local function setEditBoxReadOnly(box)
    box:SetAutoFocus(false)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnCursorChanged", function(self)
        self:HighlightText(0, 0)
    end)
end

local function makeScrollEdit(parent, width, height, multiline)
    local Th = T()
    local shell = CreateFrame("Frame", nil, parent)
    shell:SetSize(width, height)
    Th.Bg(shell, Th.c.panelAlt, Th.c.borderStrong)

    local scroll = CreateFrame("ScrollFrame", nil, shell)
    scroll:SetPoint("TOPLEFT", shell, "TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", shell, "BOTTOMRIGHT", -6, 6)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local child = self:GetScrollChild()
        local maxScroll = math.max(0, (child and child:GetHeight() or 0) - self:GetHeight())
        self:SetVerticalScroll(math.min(maxScroll, math.max(0, self:GetVerticalScroll() - delta * 40)))
    end)

    local box = CreateFrame("EditBox", nil, scroll)
    box:SetMultiLine(multiline == true)
    box:SetAutoFocus(false)
    box:SetFontObject(ChatFontNormal)
    box:SetTextColor(0.92, 0.92, 0.95, 1)
    box:SetWidth(width - 16)
    box:SetHeight(height - 12)
    box:SetTextInsets(0, 0, 0, 0)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    if box.SetMaxLetters then box:SetMaxLetters(0) end
    scroll:SetScrollChild(box)
    shell.scroll = scroll
    shell.box = box
    return shell, box
end

local function summarizeFieldCounts(fieldCounts)
    local parts = {}
    for field, count in pairs(fieldCounts or {}) do
        parts[#parts + 1] = tostring(field) .. "=" .. tostring(count)
    end
    table.sort(parts)
    return #parts > 0 and table.concat(parts, ", ") or "None"
end

local function issueLines(validation)
    local lines = {}
    validation = validation or {}
    for _, issue in ipairs(validation.errors or {}) do
        lines[#lines + 1] = "BLOCKED: " .. tostring(issue.message or issue.code or "Validation error")
    end
    for _, issue in ipairs(validation.warnings or {}) do
        lines[#lines + 1] = "Warning: " .. tostring(issue.message or issue.code or "Validation warning")
    end
    return lines
end

local function previewLines(preview)
    local lines = {}
    if not preview then
        return "Paste a GRM export and click Parse / Preview."
    end
    local s = preview.summary or {}
    lines[#lines + 1] = "Summary"
    lines[#lines + 1] = string.format("Rows: %d total, %d valid, %d invalid", s.totalRows or 0, s.validRows or 0, s.invalidRows or 0)
    lines[#lines + 1] = string.format("Current guild: %d matched, %d not in current guild, %d ambiguous", s.membersMatched or 0, s.membersNotFound or 0, s.ambiguousMatches or 0)
    lines[#lines + 1] = string.format("Apply plan: %d row(s) ready, %d row(s) skipped, %d conflict(s), %d duplicate base name(s)", s.rowsToApply or 0, s.rowsSkipped or 0, s.conflicts or 0, s.duplicateNames or 0)
    lines[#lines + 1] = string.format("Staged field updates: %d", s.fieldsUpdated or 0)
    lines[#lines + 1] = string.format("Standalone characters auto-marked as Main: %d", s.autoMainStandalone or 0)
    lines[#lines + 1] = "Fields: " .. summarizeFieldCounts(s.fieldCounts)
    lines[#lines + 1] = "Rows for characters not currently in the guild will be skipped. This export may include members who left after the export was created."
    for _, line in ipairs(issueLines(preview.validation)) do
        lines[#lines + 1] = line
    end
    lines[#lines + 1] = ""

    local function addGroup(title, entries, limit, formatter)
        lines[#lines + 1] = title .. " (" .. tostring(#(entries or {})) .. ")"
        local shown = math.min(limit or 20, #(entries or {}))
        for i = 1, shown do
            lines[#lines + 1] = formatter(entries[i])
        end
        if #(entries or {}) > shown then
            lines[#lines + 1] = "  ... " .. tostring(#entries - shown) .. " more"
        end
        lines[#lines + 1] = ""
    end

    addGroup("Ready to import", preview.ready, 25, function(entry)
        local autoMain = false
        for _, change in ipairs(entry.changes or {}) do
            if change.group == "autoMainStandalone" then
                autoMain = true
                break
            end
        end
        local warning = entry.relationshipWarnings and entry.relationshipWarnings[1] and entry.relationshipWarnings[1].message
        return string.format("  %s: %d change(s)%s%s", tostring(entry.key or entry.row.name), #(entry.changes or {}), autoMain and " - auto Main standalone" or "", warning and (" - " .. warning) or "")
    end)
    addGroup("Conflicts", preview.conflicts, 20, function(entry)
        local conflict = entry.conflicts and entry.conflicts[1]
        return string.format("  %s: %s (%s -> %s)", tostring(entry.key or entry.row.name), tostring(conflict and conflict.field or "?"), tostring(conflict and conflict.existing or ""), tostring(conflict and conflict.incoming or ""))
    end)
    addGroup("Ambiguous matches", preview.ambiguous, 20, function(entry)
        return string.format("  line %d %s: %s", entry.row.line or 0, tostring(entry.row.name or ""), table.concat(entry.ambiguousKeys or {}, ", "))
    end)
    addGroup("Not in current guild", preview.notFound, 20, function(entry)
        return string.format("  line %d %s - %s", entry.row.line or 0, tostring(entry.row.name or ""), entry.skipReason or "Skipped because this character is not currently in the guild.")
    end)
    addGroup("Invalid rows", preview.invalid, 10, function(row)
        return string.format("  line %d: %s", row.line or 0, row.reason or "Invalid row")
    end)
    addGroup("Skipped rows", preview.skipped, 20, function(entry)
        return string.format("  line %d %s - %s", entry.row.line or 0, tostring(entry.row.name or ""), entry.skipReason or "Skipped")
    end)

    return table.concat(lines, "\n")
end

local function fit(value, width)
    value = tostring(value or "")
    if #value > width then
        return value:sub(1, math.max(1, width - 1)) .. "~"
    end
    return value .. string.rep(" ", math.max(0, width - #value))
end

local function dateText(ts, raw)
    if tonumber(ts) then
        return date("%Y-%m-%d", ts)
    end
    return raw or ""
end

local function validationLines(preview)
    if not preview then
        return "Paste a GRM export and click Validate Roster View."
    end

    local lines = {}
    local s = preview.summary or {}
    lines[#lines + 1] = "Roster View Validation"
    lines[#lines + 1] = string.format(
        "Rows: %d valid, %d invalid | Matched: %d | Conflicts: %d | Not in guild: %d | Ambiguous: %d | Ready: %d | Skipped: %d | Auto Main: %d",
        s.validRows or 0,
        s.invalidRows or 0,
        s.membersMatched or 0,
        s.conflicts or 0,
        s.membersNotFound or 0,
        s.ambiguousMatches or 0,
        s.rowsToApply or 0,
        s.rowsSkipped or 0,
        s.autoMainStandalone or 0
    )
    lines[#lines + 1] = "This is a display validation only. No data has been applied. Rows not in the current guild are expected and will be skipped."
    for _, line in ipairs(issueLines(preview.validation)) do
        lines[#lines + 1] = line
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = table.concat({
        fit("Status", 10),
        fit("Name", 24),
        fit("Main/Alt", 9),
        fit("Rank", 14),
        fit("Class", 14),
        fit("Lvl", 4),
        fit("Join", 10),
        fit("Discord", 18),
        "Notes"
    }, " | ")
    lines[#lines + 1] = string.rep("-", 132)

    local shown = 0
    for _, entry in ipairs(preview.entries or {}) do
        if shown >= 120 then break end
        local row = entry.row or {}
        local statusText = "Ready"
        if not entry.key then
            statusText = entry.matchType == "ambiguous" and "Ambig" or "NotGuild"
        elseif #(entry.conflicts or {}) > 0 then
            statusText = "Conflict"
        elseif #(entry.changes or {}) == 0 then
            statusText = "No-op"
        else
            for _, change in ipairs(entry.changes or {}) do
                if change.group == "autoMainStandalone" then
                    statusText = "AutoMain"
                    break
                end
            end
        end

        local note = (entry.relationshipWarnings and entry.relationshipWarnings[1] and entry.relationshipWarnings[1].message)
            or row.publicNote
            or row.customNote
            or row.officerNote
            or ""
        local discord = row.discordName or ""
        local role = row.mainAlt or (row.publicHint and row.publicHint.role) or ""
        local name = entry.key or row.name or ""
        lines[#lines + 1] = table.concat({
            fit(statusText, 10),
            fit(name, 24),
            fit(role, 9),
            fit(row.rank, 14),
            fit(row.class, 14),
            fit(row.level, 4),
            fit(dateText(row.joinDate, row.joinDateRaw), 10),
            fit(discord, 18),
            note
        }, " | ")
        shown = shown + 1
    end

    if #(preview.entries or {}) > shown then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "... " .. tostring(#preview.entries - shown) .. " more row(s) not shown in this validation view."
    end

    return table.concat(lines, "\n")
end

local function applyToggleVisual(btn)
    if not btn or not btn._bg then return end
    local Th = T()
    local colorKey
    if btn._toggleDisabled then
        colorKey = "btnDisabled"
    elseif btn._toggleSelected then
        colorKey = "btnPrimary"
    elseif btn._toggleHovered then
        colorKey = "btnSecHov"
    else
        colorKey = "btnSecond"
    end
    local c = Th.c[colorKey] or Th.c.btnSecond
    btn._bg:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
end

local function setupToggleButton(btn, onClick)
    if not btn then return end
    btn:SetScript("OnEnter", function(self)
        self._toggleHovered = true
        applyToggleVisual(self)
        if self._toggleTooltipTitle and GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self._toggleTooltipTitle, 1, 1, 1, 1, true)
            if self._toggleTooltipBody then
                GameTooltip:AddLine(self._toggleTooltipBody, 0.8, 0.8, 0.8, true)
            end
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function(self)
        self._toggleHovered = false
        self._togglePressed = false
        applyToggleVisual(self)
        if self._toggleTooltipTitle and GameTooltip then
            GameTooltip:Hide()
        end
    end)
    btn:SetScript("OnMouseDown", function(self)
        self._togglePressed = true
        applyToggleVisual(self)
    end)
    btn:SetScript("OnMouseUp", function(self)
        self._togglePressed = false
        applyToggleVisual(self)
    end)
    btn:SetScript("OnClick", function(self)
        if onClick then onClick(self) end
        applyToggleVisual(self)
    end)
end

local function applyButtonVisual(btn, active)
    if not btn or not btn._bg then return end
    btn._toggleSelected = active == true
    applyToggleVisual(btn)
end

function Popup:_collectOptions(extra)
    local options = GC.Modules.GRMImport.GetDefaultOptions()
    for key, state in pairs(self.optionState or {}) do
        options[key] = state == true
    end
    options.mode = self.mode or "fill"
    for k, v in pairs(extra or {}) do options[k] = v end
    return options
end

function Popup:_refreshControls()
    for key, btn in pairs(self.optionButtons or {}) do
        btn:SetLabel((self.optionState[key] and "[x] " or "[ ] ") .. (btn._optionLabel or key))
        applyButtonVisual(btn, self.optionState[key])
    end
    for mode, btn in pairs(self.modeButtons or {}) do
        applyButtonVisual(btn, self.mode == mode)
    end
    if self.applyBtn then
        local blocked = self.preview and self.preview.validation and self.preview.validation.blocked
        self.applyBtn:SetEnabled(self.preview ~= nil and not blocked and #(self.preview.ready or {}) > 0 and self.mode ~= "preview")
    end
end

function Popup:_parse(extraOptions)
    local raw = self.pasteBox and self.pasteBox:GetText() or ""
    local parsed = GC.Modules.GRMImport.Parse(raw)
    self.parsed = parsed
    if not parsed.validHeader then
        self.preview = nil
        self.previewBox:SetText("Header validation failed: " .. tostring(parsed.headerError or "Unknown error."))
        self.summaryLabel:SetText("No valid preview.")
        self:_refreshControls()
        status("GRM import header validation failed.", "textDanger")
        return nil
    end

    local players = GC.Services and GC.Services.DataStore and GC.Services.DataStore:GetPlayers() or {}
    self.preview = GC.Modules.GRMImport.BuildPreview(parsed, players, self:_collectOptions(extraOptions))
    self.previewBox:SetText(previewLines(self.preview))
    local s = self.preview.summary or {}
    self.summaryLabel:SetText(string.format(
        "%s delimiter. %d valid, %d invalid, %d matched, %d ready, %d skipped, %d conflicts.",
        parsed.delimiterName or "Unknown",
        s.validRows or 0,
        s.invalidRows or 0,
        s.membersMatched or 0,
        s.rowsToApply or 0,
        s.rowsSkipped or 0,
        s.conflicts or 0
    ))
    self:_refreshControls()
    if self.preview.validation and self.preview.validation.blocked then
        status("GRM import preview built, but apply is blocked by validation.", "textWarn")
    elseif self.preview.validation and #(self.preview.validation.warnings or {}) > 0 then
        status("GRM import preview built with validation warnings.", "textWarn")
    else
        status("GRM import preview built.", "textSuccess")
    end
    return self.preview
end

function Popup:_dryRun()
    local preview = self:_parse({ dryRun = true, mode = "dryRun" })
    if not preview then return end
    local summary = GC.Modules.GRMImport.Apply(preview, { dryRun = true, mode = "dryRun" })
    self.previewBox:SetText(previewLines(preview) .. "\nDry run\nWould apply " .. tostring(summary.appliedFields or 0) .. " field update(s) across " .. tostring(summary.appliedRows or 0) .. " row(s).\nRows for characters not currently in the guild would be skipped: " .. tostring(summary.skippedNotInGuild or 0))
    status("GRM dry run complete.", "textSuccess")
end

function Popup:_validateRosterView()
    local preview = self:_parse({ dryRun = true })
    if not preview then return end
    self.previewBox:SetText(validationLines(preview))
    status("GRM roster view validation built. No data applied.", "textSuccess")
end

function Popup:_apply()
    if not self.preview then
        self:_parse()
    end
    if not self.preview then return end
    local summary = GC.Modules.GRMImport.Apply(self.preview, self:_collectOptions())
    local lines = {
        previewLines(self.preview),
        "Applied",
        "Applied rows: " .. tostring(summary.appliedRows or 0),
        "Fields updated: " .. tostring(summary.appliedFields or 0),
        "Standalone characters auto-marked as Main: " .. tostring(summary.autoMainStandalone or 0),
        "Skipped because not currently in guild: " .. tostring(summary.skippedNotInGuild or 0),
        "Skipped because ambiguous: " .. tostring(summary.skippedAmbiguous or 0),
        "Skipped because invalid: " .. tostring(summary.skippedInvalid or 0),
        "Conflicts skipped: " .. tostring(summary.skippedConflicts or 0),
        "Rows for characters not currently in the guild were skipped.",
    }
    if #(summary.errors or {}) > 0 then
        lines[#lines + 1] = "Errors: " .. tostring(#summary.errors)
        for i = 1, math.min(5, #summary.errors) do
            lines[#lines + 1] = "  " .. tostring(summary.errors[i])
        end
    end
    self.previewBox:SetText(table.concat(lines, "\n"))
    if GC.UI.RosterPanel then GC.UI.RosterPanel:Refresh() end
    if GC.UI.PlayerPanel then GC.UI.PlayerPanel:Refresh() end
    if #(summary.errors or {}) > 0 then
        status("GRM import did not fully apply. Check the validation summary.", "textDanger")
    else
        status("GRM import applied: " .. tostring(summary.appliedFields or 0) .. " field update(s).", "textSuccess")
    end
end

function Popup:Create()
    if self.frame then return end
    local Th = T()
    local frame = CreateFrame("Frame", "GuildCoreGRMImportPopup", UIParent)
    frame:SetSize(780, 680)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)
    if GC.UI.FrameLayering then
        GC.UI.FrameLayering:PreparePopupFrame(frame, GC.UI.MainFrame and GC.UI.MainFrame.frame, 80)
    else
        frame:SetFrameStrata("DIALOG")
    end
    Th.Bg(frame, Th.c.panel, Th.c.borderAccent)
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()
    self.frame = frame

    local title = Th.Fs(frame, "subheader", "Import GRM Roster Export", "textAccent")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -12)

    local close = GC.UI.Button.Create(frame, "Cancel", "secondary", 76, Th.btnH)
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -10)
    close:SetScript("OnClick", function() Popup:Close() end)

    local pasteLabel = Th.Fs(frame, "tiny", "PASTE EXPORT TEXT", "textDimmed")
    pasteLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -48)
    local pasteShell, pasteBox = makeScrollEdit(frame, 450, 245, true)
    pasteShell:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -66)
    self.pasteBox = pasteBox

    local optionsLabel = Th.Fs(frame, "tiny", "IMPORT OPTIONS", "textDimmed")
    optionsLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 480, -48)
    self.optionButtons = {}
    self.optionState = GC.Modules.GRMImport.GetDefaultOptions()
    local y = -66
    for i, option in ipairs(OPTION_ROWS) do
        local key, label = option[1], option[2]
        local btn = GC.UI.Button.Create(frame, "", "secondary", 132, 20)
        local col = (i > 8) and 1 or 0
        local row = col == 0 and i or (i - 8)
        btn:SetPoint("TOPLEFT", frame, "TOPLEFT", 480 + (col * 140), y - ((row - 1) * 24))
        btn._optionLabel = label
        if key == "autoMainStandalone" then
            btn._toggleTooltipTitle = "Auto-mark Standalone Main"
            btn._toggleTooltipBody = "Characters with no linked alts or main relationship will be marked as Main."
        end
        setupToggleButton(btn, function()
            Popup.optionState[key] = not Popup.optionState[key]
            Popup:_refreshControls()
        end)
        self.optionButtons[key] = btn
    end

    local modeLabel = Th.Fs(frame, "tiny", "IMPORT MODE", "textDimmed")
    modeLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 480, -262)
    self.mode = "fill"
    self.modeButtons = {}
    for i, mode in ipairs(MODES) do
        local btn = GC.UI.Button.Create(frame, mode.label, "secondary", 132, 22)
        btn:SetPoint("TOPLEFT", frame, "TOPLEFT", 480 + (((i - 1) % 2) * 140), -280 - (math.floor((i - 1) / 2) * 28))
        setupToggleButton(btn, function()
            Popup.mode = mode.id
            Popup:_refreshControls()
        end)
        self.modeButtons[mode.id] = btn
    end

    local parseBtn = GC.UI.Button.Create(frame, "Parse / Preview", "primary", 128, Th.btnH)
    parseBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -332)
    parseBtn:SetScript("OnClick", function() Popup:_parse() end)

    local dryBtn = GC.UI.Button.Create(frame, "Dry Run", "secondary", 92, Th.btnH)
    dryBtn:SetPoint("LEFT", parseBtn, "RIGHT", 8, 0)
    dryBtn:SetScript("OnClick", function() Popup:_dryRun() end)

    local validateBtn = GC.UI.Button.Create(frame, "Validate View", "secondary", 112, Th.btnH)
    validateBtn:SetPoint("LEFT", dryBtn, "RIGHT", 8, 0)
    validateBtn:SetScript("OnClick", function() Popup:_validateRosterView() end)

    local applyBtn = GC.UI.Button.Create(frame, "Apply Import", "success", 112, Th.btnH)
    applyBtn:SetPoint("LEFT", validateBtn, "RIGHT", 8, 0)
    applyBtn:SetScript("OnClick", function() Popup:_apply() end)
    self.applyBtn = applyBtn

    self.summaryLabel = Th.Fs(frame, "data", "Paste a semicolon-delimited GRM export, then preview.", "textSecond")
    self.summaryLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -366)
    self.summaryLabel:SetPoint("RIGHT", frame, "RIGHT", -14, 0)
    self.summaryLabel:SetWordWrap(false)

    local previewLabel = Th.Fs(frame, "tiny", "PREVIEW", "textDimmed")
    previewLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -392)
    local previewShell, previewBox = makeScrollEdit(frame, 752, 250, true)
    previewShell:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -410)
    previewBox:SetText("Paste a GRM export and click Parse / Preview.")
    setEditBoxReadOnly(previewBox)
    self.previewBox = previewBox

    self:_refreshControls()
end

function Popup:Open()
    self:Create()
    self.preview = nil
    self.parsed = nil
    if self.summaryLabel then
        self.summaryLabel:SetText("Paste a semicolon-delimited GRM export, then preview.")
    end
    if self.previewBox then
        self.previewBox:SetText("Paste a GRM export and click Parse / Preview.")
    end
    self:_refreshControls()
    self.frame:Show()
end

function Popup:Close()
    if self.frame then self.frame:Hide() end
end

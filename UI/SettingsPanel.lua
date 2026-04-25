-- UI/SettingsPanel.lua
-- Settings organized into sections. All changes apply immediately to SavedVariables.
local addonName, ns = ...
local GC = ns.GuildCore

GC.UI.SettingsPanel = {}
local SP = GC.UI.SettingsPanel

local function T()  return GC.UI.Theme end
local function DS() return GC.Services.DataStore end

-- ──────────────────────────────────────────────
-- Widget helpers
-- ──────────────────────────────────────────────

-- Labeled toggle. onChange(newValue) is called each time the state flips.
-- Returns frame + getValue + setValue
local function makeToggle(parent, label, y, onChange)
    local Th = T()
    local P  = Th.padding

    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(28)
    row:SetPoint("TOPLEFT",  parent, "TOPLEFT",  0, y)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -P, y)

    -- Toggle button (left side)
    local btn = CreateFrame("Button", nil, row)
    btn:SetSize(40, 20)
    btn:SetPoint("LEFT", 0, 0)

    local trackBg = btn:CreateTexture(nil, "BACKGROUND", nil, -8)
    trackBg:SetAllPoints()

    local knob = btn:CreateTexture(nil, "OVERLAY")
    knob:SetSize(16, 16)

    local state = false
    local function updateVisual()
        local Th2 = T()
        if state then
            local ac = Th2.c.accent
            trackBg:SetColorTexture(ac[1]*0.4, ac[2]*0.4, ac[3]*0.4, 1)
            knob:SetColorTexture(ac[1], ac[2], ac[3], 1)
            knob:SetPoint("RIGHT", btn, "RIGHT", -2, 0)
        else
            local dc = Th2.c.btnDisabled
            trackBg:SetColorTexture(dc[1]+0.06, dc[2]+0.06, dc[3]+0.06, 1)
            knob:SetColorTexture(0.4, 0.4, 0.45, 1)
            knob:SetPoint("LEFT", btn, "LEFT", 2, 0)
        end
    end
    updateVisual()

    -- Label (right side)
    local lbl = Th.Fs(row, "body", label, "textSecond")
    lbl:SetPoint("LEFT", btn, "RIGHT", 10, 0)

    btn:SetScript("OnClick", function()
        state = not state
        updateVisual()
        if onChange then onChange(state) end
    end)

    local function getValue() return state end
    local function setValue(v)
        state = v and true or false
        updateVisual()
    end

    return row, getValue, setValue
end

-- Labeled number input: returns frame + getValue + setValue
local function makeNumInput(parent, label, y, minVal, maxVal)
    local Th = T()
    local P  = Th.padding

    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(28)
    row:SetPoint("TOPLEFT",  parent, "TOPLEFT",  0, y)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -P, y)

    local lbl = Th.Fs(row, "body", label, "textSecond")
    lbl:SetPoint("LEFT", 0, 0)
    lbl:SetWidth(200)

    local box = GC.UI.Panel.Input(row, 60, Th.inputH)
    box:SetPoint("LEFT", 210, 0)
    box:SetNumeric(false)

    local function getValue()
        local n = tonumber(box:GetText())
        if not n then return nil end
        if minVal then n = math.max(minVal, n) end
        if maxVal then n = math.min(maxVal, n) end
        return n
    end
    local function setValue(v)
        box:SetText(v ~= nil and tostring(v) or "")
    end

    return row, getValue, setValue
end

-- Compact custom dropdown. Options are { key = "...", label = "..." }.
local function makeDropdown(parent, label, y, width, options, onChange)
    local Th = T()
    local P  = Th.padding

    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(28)
    row:SetPoint("TOPLEFT",  parent, "TOPLEFT",  0, y)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -P, y)

    local lbl = Th.Fs(row, "body", label, "textSecond")
    lbl:SetPoint("LEFT", 0, 0)
    lbl:SetWidth(200)

    local btn = CreateFrame("Button", nil, row)
    btn:SetSize(width or 180, Th.btnH)
    btn:SetPoint("LEFT", 210, 0)
    Th.Bg(btn, Th.c.panelAlt, Th.c.borderStrong)

    local text = Th.Fs(btn, "body", "", "textPrimary")
    text:SetPoint("LEFT", 8, 0)
    text:SetPoint("RIGHT", btn, "RIGHT", -24, 0)
    text:SetJustifyH("LEFT")

    local arrow = Th.Fs(btn, "small", "v", "textAccent")
    arrow:SetPoint("RIGHT", -8, 0)

    local menu = CreateFrame("Frame", nil, btn)
    menu:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
    menu:SetPoint("TOPRIGHT", btn, "BOTTOMRIGHT", 0, -2)
    menu:SetHeight(#options * Th.btnH)
    menu:SetFrameStrata("DIALOG")
    menu:SetFrameLevel((btn:GetFrameLevel() or 1) + 20)
    Th.Bg(menu, Th.c.panel, Th.c.borderAccent)
    menu:Hide()

    local selectedKey
    local optionButtons = {}

    local function labelFor(key)
        for _, option in ipairs(options) do
            if option.key == key then return option.label end
        end
        return options[1] and options[1].label or ""
    end

    local function refreshOptions()
        for _, optBtn in ipairs(optionButtons) do
            local c = optBtn._key == selectedKey and T().c.navActive or T().c.panel
            optBtn._bg:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
        end
    end

    for index, option in ipairs(options) do
        local optBtn = CreateFrame("Button", nil, menu)
        optBtn:SetHeight(Th.btnH)
        optBtn:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, -((index - 1) * Th.btnH))
        optBtn:SetPoint("TOPRIGHT", menu, "TOPRIGHT", 0, -((index - 1) * Th.btnH))
        optBtn._key = option.key

        local bg = optBtn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        local pc = Th.c.panel
        bg:SetColorTexture(pc[1], pc[2], pc[3], pc[4] or 1)
        optBtn._bg = bg

        local optText = Th.Fs(optBtn, "body", option.label, "textSecond")
        optText:SetPoint("LEFT", 8, 0)

        optBtn:SetScript("OnEnter", function(self)
            local hc = T().c.navHover
            self._bg:SetColorTexture(hc[1], hc[2], hc[3], hc[4] or 1)
        end)
        optBtn:SetScript("OnLeave", function()
            refreshOptions()
        end)
        optBtn:SetScript("OnClick", function()
            selectedKey = option.key
            text:SetText(option.label)
            menu:Hide()
            arrow:SetText("v")
            refreshOptions()
            if onChange then onChange(option.key) end
        end)

        optionButtons[#optionButtons + 1] = optBtn
    end

    btn:SetScript("OnClick", function()
        if menu:IsShown() then
            menu:Hide()
            arrow:SetText("v")
        else
            refreshOptions()
            menu:Show()
            arrow:SetText("^")
        end
    end)

    btn:SetScript("OnHide", function()
        menu:Hide()
        arrow:SetText("v")
    end)

    if Th.RegisterRefresh then
        Th:RegisterRefresh(refreshOptions)
    end

    local function getValue() return selectedKey end
    local function setValue(value)
        selectedKey = value
        text:SetText(labelFor(value))
        refreshOptions()
    end

    return row, getValue, setValue
end

-- ──────────────────────────────────────────────
-- Build
-- ──────────────────────────────────────────────

function SP:Create(parent)
    if self.frame then return end
    local Th = T()
    local P  = Th.padding

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    frame:Hide()
    self.frame = frame
    Th.Bg(frame, Th.c.bg)

    -- Page header
    local hdr = Th.Fs(frame, "header", "Settings", "textPrimary")
    hdr:SetPoint("TOPLEFT", P, -P)
    local sub = Th.Fs(frame, "small", "Changes apply immediately and are saved automatically.", "textDimmed")
    sub:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", 0, -2)
    Th.HSep(frame, -(P + 38))

    -- Scroll area
    local scroll = CreateFrame("ScrollFrame", nil, frame)
    scroll:SetPoint("TOPLEFT",     frame, "TOPLEFT",     P, -(P + 46))
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -P, P)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta)
        scroll:SetVerticalScroll(math.max(0, scroll:GetVerticalScroll() - delta * 26))
    end)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(frame:GetWidth() - P * 2)
    scroll:SetScrollChild(content)

    -- ── Cursor / layout state ─────────────────────
    local y = -4
    self._setters = {}  -- settingKey → setValue fn

    -- Helper: advance cursor
    local function gap(n) y = y - (n or Th.sectionGap) end

    -- Helper: section heading
    local function secHdr(title)
        gap(8)
        local fs = Th.Fs(content, "subheader", title, "textAccent")
        fs:SetPoint("TOPLEFT", 2, y)
        gap(22)
        local sep = content:CreateTexture(nil, "ARTWORK"); sep:SetHeight(1)
        sep:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
        sep:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, y)
        local sc = Th.c.separator; sep:SetColorTexture(sc[1], sc[2], sc[3], sc[4])
        gap(10)
    end

    -- Helper: immediate-apply toggle row with helper text below
    local function addToggle(settingKey, label, helpText)
        local rowY = y
        local _, getV, setV = makeToggle(content, label, rowY, function(newVal)
            DS():SetSetting(settingKey, newVal)
            GC.UI.MainFrame:SetStatus(label .. ": " .. (newVal and "enabled" or "disabled"), "textSuccess")
        end)
        self._setters[settingKey] = setV
        if not self._getters then self._getters = {} end
        self._getters[settingKey] = getV
        gap(30)
        if helpText then
            local ht = Th.Fs(content, "small", helpText, "textDimmed")
            ht:SetPoint("TOPLEFT", content, "TOPLEFT", 50, y)
            ht:SetPoint("TOPRIGHT", content, "TOPRIGHT", -4, y)
            ht:SetWordWrap(true)
            gap(18)
        end
        gap(4)
    end

    -- Helper: number input row with inline Save button
    local function addNumInput(settingKey, label, helpText, minV, maxV)
        local _, getV, setV = makeNumInput(content, label, y, minV, maxV)
        self._setters[settingKey] = setV
        if not self._getters then self._getters = {} end
        self._getters[settingKey] = getV
        gap(32)
        if helpText then
            local ht = Th.Fs(content, "small", helpText, "textDimmed")
            ht:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
            ht:SetPoint("TOPRIGHT", content, "TOPRIGHT", -4, y)
            ht:SetWordWrap(true)
            gap(18)
        end
        local saveBtn = GC.UI.Button.Create(content, "Save", "primary", 80, Th.btnH)
        saveBtn:SetPoint("TOPLEFT", 0, y)
        gap(Th.btnH + 4)
        saveBtn:SetScript("OnClick", function()
            local v = getV()
            if not v then
                GC.UI.MainFrame:SetStatus("Invalid value for " .. label, "textDanger")
                return
            end
            DS():SetSetting(settingKey, v)
            GC.UI.MainFrame:SetStatus(label .. " saved.", "textSuccess")
        end)
    end

    -- ── GENERAL ──────────────────────────────────
    secHdr("Appearance")
    do
        local themeOptions = {}
        for _, key in ipairs(Th:GetPresetKeys()) do
            themeOptions[#themeOptions + 1] = {key = key, label = Th:GetPresetLabel(key)}
        end
        local _, getTheme, setTheme = makeDropdown(content, "Theme", y, 190, themeOptions, function(presetKey)
            local applied = T():ApplyPresetLive(presetKey)
            DS():SetSetting("themePreset", applied)
            if GC.UI.MainFrame and GC.UI.MainFrame.ApplyTheme then
                GC.UI.MainFrame:ApplyTheme()
            end
            GC.UI.MainFrame:SetStatus("Theme set to " .. T():GetPresetLabel(applied) .. ".", "textSuccess")
        end)
        self._setters.themePreset = setTheme
        if not self._getters then self._getters = {} end
        self._getters.themePreset = getTheme
        gap(30)

        local themeHelp = Th.Fs(content, "small",
            "Preset themes swap the addon color palette while preserving the current layout.",
            "textDimmed")
        themeHelp:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
        themeHelp:SetPoint("TOPRIGHT", content, "TOPRIGHT", -4, y)
        themeHelp:SetWordWrap(true)
        gap(28)

        local fontOptions = {}
        for _, key in ipairs(Th.GetFontThemeKeys()) do
            fontOptions[#fontOptions + 1] = {key = key, label = key}
        end
        local _, getFontTheme, setFontTheme = makeDropdown(content, "Font Theme", y, 190, fontOptions, function(fontTheme)
            local applied = T().SetFontTheme(fontTheme)
            if GC.UI.MainFrame and GC.UI.MainFrame.ApplyTheme then
                GC.UI.MainFrame:ApplyTheme()
            end
            GC.UI.MainFrame:SetStatus("Font theme set to " .. applied .. ".", "textSuccess")
        end)
        self._setters.fontTheme = setFontTheme
        self._getters.fontTheme = getFontTheme
        gap(34)

        local preview = CreateFrame("Frame", nil, content)
        preview:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
        preview:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, y)
        preview:SetHeight(156)
        Th.Bg(preview, Th.c.panelAlt, Th.c.border)
        local previewRows = {
            {"title", "Title Text"},
            {"header", "Header Text"},
            {"subheader", "Subheader Text"},
            {"body", "Body text shows normal reading density."},
            {"label", "Label Text"},
            {"small", "Small text"},
            {"tiny", "Tiny text"},
            {"status", "Status text"},
        }
        local py = -10
        for _, row in ipairs(previewRows) do
            local fs = Th.Fs(preview, row[1], row[2], row[1] == "status" and "textWarn" or "textSecond")
            fs:SetPoint("TOPLEFT", preview, "TOPLEFT", 14, py)
            py = py - 18
        end
        gap(166)
    end

    -- ── GENERAL ──────────────────────────────────
    secHdr("General")
    addToggle("debugMode",
        "Debug mode",
        "Enables verbose chat output and debug-only UI overlays. Disable during normal gameplay.")

    -- ── ROSTER ───────────────────────────────────
    secHdr("Roster")
    addToggle("enableRosterModule",
        "Enable roster tracking",
        "Tracks guild joins, leaves, and rank changes. Required for most other features.")
    addNumInput("autoScanIntervalMinutes",
        "Auto-scan interval (minutes)",
        "How often the roster is automatically refreshed. Range: 5–720 minutes.",
        5, 720)
    addToggle("enableClassificationPrompts",
        "Enable first-seen classification prompts",
        "Shows a compact prompt for newly detected tracked members until they are classified or dismissed.")

    -- ── POINTS ───────────────────────────────────
    secHdr("Guild Bank")
    addToggle("enableGuildBankModule",
        "Enable guild bank log capture",
        "Captures visible guild bank item and money logs when the guild bank is opened. Requires guild bank access and inherits Blizzard log limitations.")

    -- ── POINTS ───────────────────────────────────
    secHdr("Points")
    addToggle("enablePointsModule",
        "Enable points system",
        "Allows officers to award and deduct DKP / attendance points per member.")

    -- ── MESSAGING ────────────────────────────────
    secHdr("Messaging")
    addToggle("enableMessagingModule",
        "Enable messaging system",
        "Queues and sends guild-wide messages. Disable to suppress all automated chat output.")

    -- ── SYNC ─────────────────────────────────────
    secHdr("Sync")
    addToggle("enableSyncModule",
        "Enable sync (experimental)",
        "Synchronizes roster data between online officers via addon messages. Experimental — use with caution.")

    -- ── PERMISSIONS ──────────────────────────────
    secHdr("Permissions")
    addNumInput("officerRankThreshold",
        "Officer rank threshold (0–9)",
        "Members at or above this rank index are treated as officers. Rank 0 is the highest (Guild Master).",
        0, 9)

    -- ── DANGER ZONE ──────────────────────────────
    secHdr("Danger Zone")
    local note = Th.Fs(content, "small",
        "Resetting settings restores all defaults and applies appearance changes immediately.", "textDimmed")
    note:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    note:SetPoint("TOPRIGHT", content, "TOPRIGHT", -4, y)
    note:SetWordWrap(true)
    gap(24)
    local resetBtn = GC.UI.Button.Create(content, "Reset All Settings", "danger", 180, Th.btnH)
    resetBtn:SetPoint("TOPLEFT", 0, y); gap(Th.btnH + P)
    resetBtn:SetScript("OnClick", function()
        local settings = DS():GetSettings()
        if settings then
            local defaults = ns.Defaults and ns.Defaults.settings or {}
            for k, v in pairs(defaults) do settings[k] = v end
            if settings.themePreset then
                T():ApplyPresetLive(settings.themePreset)
                if GC.UI.MainFrame and GC.UI.MainFrame.ApplyTheme then
                    GC.UI.MainFrame:ApplyTheme()
                end
            end
            if settings.fontTheme then
                T().SetFontTheme(settings.fontTheme)
                if GC.UI.MainFrame and GC.UI.MainFrame.ApplyTheme then
                    GC.UI.MainFrame:ApplyTheme()
                end
            end
        end
        SP:Refresh()
        GC.UI.MainFrame:SetStatus("Settings reset to defaults.", "textWarn")
    end)

    content:SetHeight(math.abs(y) + P * 2)
end

-- ──────────────────────────────────────────────
-- Refresh: read live settings into widgets
-- ──────────────────────────────────────────────

function SP:Refresh()
    if not self.frame then return end
    local s = DS():GetSettings()
    if not s or not self._setters then return end
    for key, setV in pairs(self._setters) do
        if s[key] ~= nil then
            setV(s[key])
        end
    end
end

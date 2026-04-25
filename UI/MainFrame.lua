-- UI/MainFrame.lua
-- Main window: custom dark chrome, sidebar nav, content + detail layout.
-- No default WoW frame templates are used anywhere in this file.
local addonName, ns = ...
local GC = ns.GuildCore

GC.UI.MainFrame = {}
local MF = GC.UI.MainFrame

-- ──────────────────────────────────────────────
-- Helpers
-- ──────────────────────────────────────────────

local function T() return GC.UI.Theme end
local function GS() return GC.Services.GuildService end

-- panels keyed by id; each has {frame, hasDetail, refresh}
local panels      = {}
local navButtons  = {}
local activePanel = nil
local statusTimer = nil

-- Persist the current active panel key to SavedVariables.
local function saveUIState()
    if not GC.DB or not GC.DB.Root then return end
    local ui = GC.DB:GetUIState()
    ui.lastPanel = activePanel
    if MF.frame and MF.frame:IsShown() then
        ui.windowX = MF.frame:GetLeft()
        ui.windowY = MF.frame:GetTop()
    end
end

-- Show exactly one content panel; toggle the right-side detail column.
-- skipRefresh=true avoids refreshing while the main frame is hidden.
local function showPanel(id, skipRefresh)
    local Th = T()
    if not panels[id] then id = "dashboard" end

    for pid, p in pairs(panels) do
        if pid == id then
            p.frame:Show()
            if p.refresh and not skipRefresh then p.refresh() end
        else
            p.frame:Hide()
        end
    end

    -- Right detail column visibility (Roster only)
    if MF.detailCol then
        if panels[id] and panels[id].hasDetail then
            MF.detailCol:Show()
            MF.contentArea:SetPoint("TOPRIGHT", MF.detailCol, "TOPLEFT", -2, 0)
        else
            MF.detailCol:Hide()
            MF.contentArea:SetPoint("TOPRIGHT", MF.frame, "TOPRIGHT", -2, 0)
        end
    end

    -- Nav button active states
    for nid, btn in pairs(navButtons) do
        local c  = (nid == id) and Th.c.navActive or Th.c.navBg
        local tc = (nid == id) and Th.c.textAccent or Th.c.textSecond
        if btn._bg     then btn._bg:SetColorTexture(c[1], c[2], c[3], c[4]) end
        if btn._label  then btn._label:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1) end
        if btn._accent then btn._accent:SetAlpha(nid == id and 1 or 0) end
    end

    activePanel = id
    if not skipRefresh then saveUIState() end
    if not skipRefresh and MF.RefreshPrompt then
        MF:RefreshPrompt()
    end
end

-- ──────────────────────────────────────────────
-- Public API
-- ──────────────────────────────────────────────

-- Show a status message in the bottom bar (auto-clears after 4 s).
function MF:SetStatus(msg, colorKey)
    if not self.statusLabel then return end
    local Th = T()
    local c  = colorKey and Th.c[colorKey] or Th.c.textSecond
    self.statusLabel:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    self.statusLabel:SetText(msg or "")
    if statusTimer then statusTimer:Cancel() end
    statusTimer = C_Timer.NewTimer(4, function()
        if MF.statusLabel then MF.statusLabel:SetText("") end
    end)
end

-- Switch to a named panel programmatically.
function MF:SetActivePanel(id)
    if not self.frame then self:Create() end
    showPanel(id)
end

function MF:ShowPanel(id) showPanel(id) end

function MF:RefreshActive()
    if activePanel and panels[activePanel] and panels[activePanel].refresh then
        panels[activePanel].refresh()
    end
    self:RefreshPrompt()
end

function MF:ApplyTheme()
    local Th = T()
    if Th and Th.RefreshRegistered then
        Th:RefreshRegistered()
    end
    if activePanel then
        showPanel(activePanel, true)
    end
    self:RefreshActive()
end

function MF:RefreshPrompt()
    if not self.promptSlot or not self.panelHost then
        return
    end

    if activePanel ~= "dashboard" then
        self.promptSlot:SetHeight(0)
        self.promptFrame:Hide()
        self.promptTargetKey = nil
        self.panelHost:ClearAllPoints()
        self.panelHost:SetPoint("TOPLEFT", self.contentArea, "TOPLEFT", 0, 0)
        self.panelHost:SetPoint("TOPRIGHT", self.contentArea, "TOPRIGHT", 0, 0)
        self.panelHost:SetPoint("BOTTOMLEFT", self.contentArea, "BOTTOMLEFT", 0, 0)
        self.panelHost:SetPoint("BOTTOMRIGHT", self.contentArea, "BOTTOMRIGHT", 0, 0)
        return
    end

    local prompt = GS() and GS():GetPendingClassificationPrompt() or nil
    if not prompt then
        self.promptSlot:SetHeight(0)
        self.promptFrame:Hide()
        self.promptTargetKey = nil
        self.panelHost:ClearAllPoints()
        self.panelHost:SetPoint("TOPLEFT", self.contentArea, "TOPLEFT", 0, 0)
        self.panelHost:SetPoint("TOPRIGHT", self.contentArea, "TOPRIGHT", 0, 0)
        self.panelHost:SetPoint("BOTTOMLEFT", self.contentArea, "BOTTOMLEFT", 0, 0)
        self.panelHost:SetPoint("BOTTOMRIGHT", self.contentArea, "BOTTOMRIGHT", 0, 0)
        return
    end

    self.promptTargetKey = prompt.key
    self.promptSlot:SetHeight(72)
    self.promptFrame:Show()
    self.panelHost:ClearAllPoints()
    self.panelHost:SetPoint("TOPLEFT", self.contentArea, "TOPLEFT", 0, -72)
    self.panelHost:SetPoint("TOPRIGHT", self.contentArea, "TOPRIGHT", 0, -72)
    self.panelHost:SetPoint("BOTTOMLEFT", self.contentArea, "BOTTOMLEFT", 0, 0)
    self.panelHost:SetPoint("BOTTOMRIGHT", self.contentArea, "BOTTOMRIGHT", 0, 0)

    local promptName = prompt.name or (prompt.key and prompt.key:match("^([^%-]+)")) or "Unknown"
    local firstSeen = prompt.firstSeenAt and date("%Y-%m-%d", prompt.firstSeenAt) or "recently"
    self.promptLabel:SetText(string.format("%s was first detected on %s. Mark as Main or link as Alt.", promptName, firstSeen))
    self.promptInput:SetText(prompt.main or "")
end

-- ──────────────────────────────────────────────
-- Build
-- ──────────────────────────────────────────────

function MF:Create()
    if self.frame then return end
    local Th = T()

    -- ── Window ──────────────────────────────────
    local frame = CreateFrame("Frame", "GuildCoreMainFrame", UIParent)
    frame:SetSize(1280, 850)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    if GC.UI.Layering then
        GC.UI.Layering:ApplyMainFrame(frame)
    else
        frame:SetFrameStrata("DIALOG")
        frame:SetFrameLevel(80)
    end
    frame:SetClampedToScreen(true)
    frame:Hide()
    self.frame = frame
    if UISpecialFrames then
        local registered = false
        for _, name in ipairs(UISpecialFrames) do
            if name == "GuildCoreMainFrame" then
                registered = true
                break
            end
        end
        if not registered then
            table.insert(UISpecialFrames, "GuildCoreMainFrame")
        end
    end

    -- Restore saved position or center
    local uiState = GC.DB:GetUIState()
    if uiState.windowX and uiState.windowY then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", uiState.windowX, uiState.windowY)
    else
        frame:SetPoint("CENTER")
    end

    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop",  function(f)
        f:StopMovingOrSizing()
        saveUIState()
    end)

    -- Background + accent border
    Th.Bg(frame, Th.c.bg, Th.c.borderAccent)

    -- Outer shadow is parented to UIParent so it can sit just behind the main frame.
    local shadow = CreateFrame("Frame", nil, UIParent)
    shadow:SetPoint("TOPLEFT",     frame, "TOPLEFT",     -6, 6)
    shadow:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT",  6,-6)
    if GC.UI.Layering then
        GC.UI.Layering:ApplyShadow(shadow, frame)
    else
        shadow:SetFrameStrata("DIALOG")
        shadow:SetFrameLevel(math.max(1, (frame:GetFrameLevel() or 80) - 1))
    end
    shadow:Hide()
    Th.Bg(shadow, {0, 0, 0, 0.60})

    frame:SetScript("OnShow", function()
        shadow:Show()
        if MF.guildLabel then
            local gn = GetGuildInfo and GetGuildInfo("player") or ""
            MF.guildLabel:SetText(gn or "")
        end
        -- Update online/member count in status bar
        MF:UpdateMemberCount()
        MF:RefreshActive()
    end)
    frame:SetScript("OnHide", function()
        shadow:Hide()
        saveUIState()
    end)

    -- ── Title bar ───────────────────────────────
    local titleBar = CreateFrame("Frame", nil, frame)
    titleBar:SetPoint("TOPLEFT"); titleBar:SetPoint("TOPRIGHT")
    titleBar:SetHeight(Th.titleBarH)
    Th.Bg(titleBar, Th.c.chrome)

    local titleEdge = titleBar:CreateTexture(nil, "ARTWORK")
    titleEdge:SetPoint("BOTTOMLEFT"); titleEdge:SetPoint("BOTTOMRIGHT"); titleEdge:SetHeight(1)
    local ac = Th.c.accent
    titleEdge:SetColorTexture(ac[1], ac[2], ac[3], 0.45)

    local titleFs = Th.Fs(titleBar, "header", GC.Name or "Guild Core", "textAccent")
    titleFs:SetPoint("LEFT", 16, 5)

    local guildName = GetGuildInfo and GetGuildInfo("player") or ""
    local subFs = Th.Fs(titleBar, "small", guildName or "", "textDimmed")
    subFs:SetPoint("LEFT", 16, -13)
    self.guildLabel = subFs

    local verFs = Th.Fs(titleBar, "tiny", "v" .. (GC.Version or "0"), "textDimmed")
    verFs:SetPoint("RIGHT", -64, 0)

    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame)
    closeBtn:SetSize(30, 30)
    closeBtn:SetPoint("TOPRIGHT", -9, -9)
    local closeBg = closeBtn:CreateTexture(nil, "BACKGROUND")
    closeBg:SetAllPoints()
    closeBg:SetColorTexture(0.40, 0.07, 0.07, 0.90)
    local closeFs = closeBtn:CreateFontString(nil, "OVERLAY")
    Th.ApplyFont(closeFs, "subheader")
    if Th.RegisterRefresh then
        Th:RegisterRefresh(function()
            T().ApplyFont(closeFs, "subheader")
        end)
    end
    closeFs:SetAllPoints(); closeFs:SetJustifyH("CENTER"); closeFs:SetJustifyV("MIDDLE")
    closeFs:SetText("X"); closeFs:SetTextColor(1, 0.55, 0.55, 1)
    closeBtn:SetScript("OnEnter", function() closeBg:SetColorTexture(0.72, 0.12, 0.12, 1) end)
    closeBtn:SetScript("OnLeave", function() closeBg:SetColorTexture(0.40, 0.07, 0.07, 0.90) end)
    closeBtn:SetScript("OnClick", function() GC.UI:Hide() end)

    -- ── Status bar ──────────────────────────────
    local statusBar = CreateFrame("Frame", nil, frame)
    statusBar:SetPoint("BOTTOMLEFT"); statusBar:SetPoint("BOTTOMRIGHT")
    statusBar:SetHeight(Th.statusBarH)
    Th.Bg(statusBar, Th.c.chrome, Th.c.border)
    local statusEdge = statusBar:CreateTexture(nil, "ARTWORK")
    statusEdge:SetPoint("TOPLEFT"); statusEdge:SetPoint("TOPRIGHT"); statusEdge:SetHeight(1)
    statusEdge:SetColorTexture(ac[1], ac[2], ac[3], 0.18)
    local statusFs = Th.Fs(statusBar, "small", "", "textDimmed")
    statusFs:SetPoint("LEFT", 12, 0)
    self.statusLabel = statusFs

    local memberFs = Th.Fs(statusBar, "tiny", "", "textDimmed")
    memberFs:SetPoint("RIGHT", -12, 0)
    self.memberCountLabel = memberFs

    local footerFs = Th.Fs(statusBar, "tiny", "\194\169 2026 AddOns by Catastrophie", "textDimmed")
    footerFs:SetPoint("CENTER", statusBar, "CENTER", 0, 0)
    footerFs:SetTextColor(1, 0.55, 0.1, 1)

    -- ── Nav sidebar ─────────────────────────────
    local sidebar = CreateFrame("Frame", nil, frame)
    sidebar:SetPoint("TOPLEFT",    frame, "TOPLEFT",    0, -Th.titleBarH)
    sidebar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0,  Th.statusBarH)
    sidebar:SetWidth(Th.navWidth)
    Th.Bg(sidebar, Th.c.navBg)

    local sideEdge = sidebar:CreateTexture(nil, "ARTWORK")
    sideEdge:SetPoint("TOPRIGHT"); sideEdge:SetPoint("BOTTOMRIGHT"); sideEdge:SetWidth(1)
    local brd = Th.c.border
    sideEdge:SetColorTexture(brd[1], brd[2], brd[3], brd[4])

    local navItems = {
        {id = "dashboard",  label = "Dashboard"},
        {id = "roster",     label = "Roster"},
        {id = "log",        label = "Activity"},
        {id = "messaging",  label = "Messages"},
        {id = "settings",   label = "Settings"},
    }

    -- Scan button pinned at bottom of sidebar
    local scanBtn = GC.UI.Button.Create(sidebar, "Scan Now", "primary", Th.navWidth - 16, Th.btnH)
    scanBtn:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMLEFT", 8, 8)
    scanBtn:SetTooltip("Refresh Roster", "Requests a live guild roster update from the server.")
    scanBtn:SetScript("OnClick", function()
        local ok, err = GC.Services.GuildService:TriggerScan()
        MF:SetStatus(ok and "Requesting scan…" or (err or "Unable to scan."), ok and "textWarn" or "textDanger")
    end)

    local navItemH = 42
    for i, item in ipairs(navItems) do
        local btn = CreateFrame("Button", nil, sidebar)
        btn:SetHeight(navItemH)
        btn:SetPoint("TOPLEFT",  sidebar, "TOPLEFT",  0, -(i-1)*navItemH)
        btn:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", 0, -(i-1)*navItemH)

        local nc = Th.c.navBg
        local bg = btn:CreateTexture(nil, "BACKGROUND", nil, -8)
        bg:SetAllPoints(); bg:SetColorTexture(nc[1], nc[2], nc[3], nc[4])
        btn._bg = bg

        local accentBar = btn:CreateTexture(nil, "ARTWORK")
        accentBar:SetWidth(3); accentBar:SetPoint("TOPLEFT"); accentBar:SetPoint("BOTTOMLEFT")
        accentBar:SetColorTexture(ac[1], ac[2], ac[3], 1); accentBar:SetAlpha(0)
        btn._accent = accentBar

        local lbl = Th.Fs(btn, "nav", item.label, "textSecond")
        lbl:SetPoint("LEFT", 16, 0)
        btn._label = lbl

        btn:SetScript("OnEnter", function()
            if activePanel ~= item.id then
                local hc = Th.c.navHover
                bg:SetColorTexture(hc[1], hc[2], hc[3], hc[4])
            end
        end)
        btn:SetScript("OnLeave", function()
            if activePanel ~= item.id then
                bg:SetColorTexture(nc[1], nc[2], nc[3], nc[4])
            end
        end)
        btn:SetScript("OnClick", function() showPanel(item.id) end)
        navButtons[item.id] = btn

        local sep = sidebar:CreateTexture(nil, "ARTWORK")
        sep:SetHeight(1)
        sep:SetPoint("BOTTOMLEFT",  btn, "BOTTOMLEFT")
        sep:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT")
        local sp = Th.c.separator
        sep:SetColorTexture(sp[1], sp[2], sp[3], sp[4])
    end

    -- ── Right detail column ──────────────────────
    local detailCol = CreateFrame("Frame", nil, frame)
    detailCol:SetWidth(Th.detailWidth)
    detailCol:SetPoint("TOPRIGHT",    frame, "TOPRIGHT",    0, -Th.titleBarH)
    detailCol:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0,  Th.statusBarH)
    Th.Bg(detailCol, Th.c.panelAlt, Th.c.border)
    self.detailCol = detailCol

    -- ── Content area ─────────────────────────────
    local contentArea = CreateFrame("Frame", nil, frame)
    contentArea:SetPoint("TOPLEFT",  sidebar,    "TOPRIGHT",  0, 0)
    contentArea:SetPoint("TOPRIGHT", frame,      "TOPRIGHT",  0, 0)
    contentArea:SetPoint("BOTTOM",   frame,      "BOTTOM",    0, Th.statusBarH)
    Th.Bg(contentArea, Th.c.bg)
    self.contentArea = contentArea

    local bodyDivider = frame:CreateTexture(nil, "ARTWORK")
    bodyDivider:SetPoint("TOPLEFT", frame, "TOPLEFT", Th.navWidth, -Th.titleBarH)
    bodyDivider:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", Th.navWidth, Th.statusBarH)
    bodyDivider:SetWidth(1)
    bodyDivider:SetColorTexture(brd[1], brd[2], brd[3], brd[4])

    local promptSlot = CreateFrame("Frame", nil, contentArea)
    promptSlot:SetPoint("TOPLEFT", contentArea, "TOPLEFT", 0, 0)
    promptSlot:SetPoint("TOPRIGHT", contentArea, "TOPRIGHT", 0, 0)
    promptSlot:SetHeight(0)
    self.promptSlot = promptSlot

    local promptFrame = CreateFrame("Frame", nil, promptSlot)
    promptFrame:SetPoint("TOPLEFT", promptSlot, "TOPLEFT", 8, -8)
    promptFrame:SetPoint("TOPRIGHT", promptSlot, "TOPRIGHT", -8, -8)
    promptFrame:SetHeight(56)
    Th.Bg(promptFrame, Th.c.panelAlt, Th.c.borderAccent)
    promptFrame:Hide()
    self.promptFrame = promptFrame

    local promptTitle = Th.Fs(promptFrame, "tiny", "Classification Prompt", "textAccent")
    promptTitle:SetPoint("TOPLEFT", 10, -6)

    local promptLabel = Th.Fs(promptFrame, "small", "", "textSecond")
    promptLabel:SetPoint("TOPLEFT", 10, -20)
    promptLabel:SetPoint("TOPRIGHT", promptFrame, "TOPRIGHT", -390, -20)
    promptLabel:SetJustifyH("LEFT")
    self.promptLabel = promptLabel

    local promptInput = GC.UI.Panel.Input(promptFrame, 110, Th.inputH)
    promptInput:SetPoint("RIGHT", promptFrame, "RIGHT", -186, 0)
    promptInput:SetMaxLetters(40)
    self.promptInput = promptInput

    local promptDismissBtn = GC.UI.Button.Create(promptFrame, "Dismiss", "danger", 72, Th.btnH)
    promptDismissBtn:SetPoint("RIGHT", promptFrame, "RIGHT", -10, 0)
    promptDismissBtn:SetScript("OnClick", function()
        if not self.promptTargetKey then return end
        local ok, err = GC.Services.Alts:DismissPrompt(self.promptTargetKey, "prompt")
        self:SetStatus(ok and "Prompt dismissed." or err, ok and "textWarn" or "textDanger")
        self:RefreshActive()
    end)

    local promptViewBtn = GC.UI.Button.Create(promptFrame, "View", "secondary", 52, Th.btnH)
    promptViewBtn:SetPoint("RIGHT", promptDismissBtn, "LEFT", -6, 0)
    promptViewBtn:SetScript("OnClick", function()
        if not self.promptTargetKey then return end
        GC.UI:SetActivePanel("roster")
        GC.UI.PlayerPanel:ShowPlayerByKey(self.promptTargetKey)
    end)

    local promptAltBtn = GC.UI.Button.Create(promptFrame, "Alt", "secondary", 44, Th.btnH)
    promptAltBtn:SetPoint("RIGHT", promptViewBtn, "LEFT", -6, 0)
    promptAltBtn:SetScript("OnClick", function()
        if not self.promptTargetKey then return end
        local mainKey = GS():ResolvePlayerKey(promptInput:GetText() or "")
        if not mainKey then
            self:SetStatus("Enter a known main character name or key.", "textDanger")
            return
        end
        local ok, err = GC.Services.Alts:SetAlt(self.promptTargetKey, mainKey, "prompt")
        self:SetStatus(ok and "Alt link saved." or err, ok and "textSuccess" or "textDanger")
        self:RefreshActive()
    end)

    local promptMainBtn = GC.UI.Button.Create(promptFrame, "Main", "success", 52, Th.btnH)
    promptMainBtn:SetPoint("RIGHT", promptInput, "LEFT", -6, 0)
    promptMainBtn:SetScript("OnClick", function()
        if not self.promptTargetKey then return end
        local ok, err = GC.Services.Alts:SetMain(self.promptTargetKey, "prompt")
        self:SetStatus(ok and "Character marked as Main." or err, ok and "textSuccess" or "textDanger")
        self:RefreshActive()
    end)

    local panelHost = CreateFrame("Frame", nil, contentArea)
    panelHost:SetPoint("TOPLEFT", contentArea, "TOPLEFT", 0, 0)
    panelHost:SetPoint("TOPRIGHT", contentArea, "TOPRIGHT", 0, 0)
    panelHost:SetPoint("BOTTOMLEFT", contentArea, "BOTTOMLEFT", 0, 0)
    panelHost:SetPoint("BOTTOMRIGHT", contentArea, "BOTTOMRIGHT", 0, 0)
    self.panelHost = panelHost

    -- ── Create panels ─────────────────────────────
    GC.UI.Dashboard:Create(panelHost)
    GC.UI.RosterPanel:Create(panelHost)
    GC.UI.PlayerPanel:Create(detailCol)
    GC.UI.LogPanel:Create(panelHost)
    GC.UI.MessagingPanel:Create(panelHost)
    GC.UI.SettingsPanel:Create(panelHost)

    panels.dashboard  = {frame = GC.UI.Dashboard.frame,       refresh = function() GC.UI.Dashboard:Refresh()       end, hasDetail = false}
    panels.roster     = {frame = GC.UI.RosterPanel.frame,     refresh = function() GC.UI.RosterPanel:Refresh()     end, hasDetail = true}
    panels.log        = {frame = GC.UI.LogPanel.frame,        refresh = function() GC.UI.LogPanel:Refresh()        end, hasDetail = false}
    panels.messaging  = {frame = GC.UI.MessagingPanel.frame,  refresh = function() GC.UI.MessagingPanel:Refresh()  end, hasDetail = false}
    panels.settings   = {frame = GC.UI.SettingsPanel.frame,   refresh = function() GC.UI.SettingsPanel:Refresh()   end, hasDetail = false}

    -- Restore last panel (no refresh; frame is still hidden).
    local startPanel = (uiState.lastPanel and panels[uiState.lastPanel]) and uiState.lastPanel or "dashboard"
    showPanel(startPanel, true)
    self:RefreshPrompt()
end

-- Update the member count label in the status bar.
function MF:UpdateMemberCount()
    if not self.memberCountLabel then return end
    local total, online = GetNumGuildMembers()
    total  = total  or 0
    online = online or 0
    self.memberCountLabel:SetText(online .. " / " .. total .. " online")
end

-- ──────────────────────────────────────────────
-- GC.UI top-level API  (routes all entry points)
-- ──────────────────────────────────────────────

function GC.UI:Show()
    if not MF.frame then MF:Create() end
    if GC.UI.Layering then
        GC.UI.Layering:ApplyMainFrame(MF.frame)
    end
    MF.frame:Show()
end

function GC.UI:Hide()
    if MF.frame then MF.frame:Hide() end
end

function GC.UI:Toggle()
    if MF.frame and MF.frame:IsShown() then
        GC.UI:Hide()
    else
        GC.UI:Show()
    end
end

function GC.UI:SetActivePanel(id)
    MF:SetActivePanel(id)
end

function MF:Toggle()
    GC.UI:Toggle()
end

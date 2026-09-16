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

local function guildDisplayName()
    local guildName = GetGuildInfo and GetGuildInfo("player") or nil
    if not guildName or guildName == "" then
        return ""
    end

    local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or nil
    if realm and realm ~= "" then
        return string.format("%s - %s", guildName, realm)
    end

    return guildName
end

local function pendingClassificationCount()
    local settings = GC.Services and GC.Services.DataStore and GC.Services.DataStore:GetSettings() or nil
    if settings and settings.enableClassificationPrompts == false then return 0 end
    local players = GC.Services and GC.Services.DataStore and GC.Services.DataStore:GetPlayers() or nil
    local count = 0
    for _, player in pairs(players or {}) do
        local promptState = player.promptState or {}
        if player.status == "active"
            and player.classification == "unknown"
            and player.isTrackedRank ~= false
            and not promptState.dismissedAt
            and not promptState.bootstrapSuppressed then
            count = count + 1
        end
    end
    return count
end

local function getActionHotkey()
    local macro = GC.Services and GC.Services.OperationsMacro
    if macro and macro.GetHotkey then
        return macro:GetHotkey()
    end
    local settings = GC.DB and GC.DB.GetSettings and GC.DB:GetSettings()
    return settings and settings.guildActionHotkey or "CTRL-SHIFT-K"
end

local function getPreparedActionState()
    local owner = GC.State and GC.State.actionMacroOwner or nil
    local hotkey = getActionHotkey()
    if owner == "operations" then
        local macro = GC.Services and GC.Services.OperationsMacro
        if macro and macro.HasPreparedMacro and macro:HasPreparedMacro() then
            local lines = macro.preparedLines or {}
            local names = macro.GetQueuedNames and macro:GetQueuedNames() or {}
            local target = names[1] or "rank action"
            return {
                owner = "operations",
                text = string.format("Prepared: %s rank change (%s)", tostring(target), hotkey),
                tooltip = string.format("The guild action hotkey is armed with %d rank step%s.", #lines, #lines == 1 and "" or "s"),
            }
        end
    elseif owner == "purge" then
        local purge = GC.Services and GC.Services.Purge
        if purge and purge.HasPreparedMacro and purge:HasPreparedMacro() then
            local state = purge.GetState and purge:GetState() or nil
            local names = state and state.meta and state.meta.preparedNames or {}
            return {
                owner = "purge",
                text = string.format("Prepared: %d purge action%s (%s)", #names, #names == 1 and "" or "s", hotkey),
                tooltip = "The guild action hotkey is armed with queued purge removals.",
            }
        end
    end
    return nil
end

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
        ui.windowWidth = MF.frame:GetWidth()
        ui.windowHeight = MF.frame:GetHeight()
    end
end

function MF:ApplyScale()
    if not self.frame then return end
    local settings = GC.DB and GC.DB.GetSettings and GC.DB:GetSettings() or {}
    local requested = math.max(0.75, math.min(1.25, tonumber(settings.uiScale) or 1))
    local screenW = UIParent and UIParent:GetWidth() or 1400
    local screenH = UIParent and UIParent:GetHeight() or 865
    local scale = math.max(0.65, math.min(requested, (screenW - 48) / self.frame:GetWidth(), (screenH - 48) / self.frame:GetHeight()))
    self.frame:SetScale(scale)
    if self.miniFrame then self.miniFrame:SetScale(scale) end
    local maxW = math.max(1120, math.floor((screenW / scale) - 48))
    local maxH = math.max(680, math.floor((screenH / scale) - 48))
    if self.frame.SetResizeBounds then
        self.frame:SetResizeBounds(1120, 680, maxW, maxH)
    elseif self.frame.SetMaxResize then
        self.frame:SetMaxResize(maxW, maxH)
    end
end

local function saveMiniState()
    if not GC.DB or not GC.DB.Root then return end
    local ui = GC.DB:GetUIState()
    if MF.miniFrame and MF.miniFrame:IsShown() then
        ui.miniX = MF.miniFrame:GetLeft()
        ui.miniY = MF.miniFrame:GetTop()
    end
end

-- Show exactly one content panel; toggle the right-side detail column.
-- skipRefresh=true avoids refreshing while the main frame is hidden.
local function showPanel(id, skipRefresh)
    local Th = T()
    if not panels[id] then id = "dashboard" end
    local target = panels[id]
    if target and not target.frame and target.create then
        target.create()
    end

    for pid, p in pairs(panels) do
        if pid == id then
            if p.frame then p.frame:Show() end
            if p.refresh and not skipRefresh then p.refresh() end
        else
            if p.frame then p.frame:Hide() end
        end
    end

    -- Right detail column visibility (Roster only)
    if MF.detailCol then
        if panels[id] and panels[id].hasDetail then
            if GC.UI.PlayerPanel and not GC.UI.PlayerPanel.frame then
                GC.UI.PlayerPanel:Create(MF.detailCol)
            end
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
    if MF.RefreshPreparedActionStatus then
        MF:RefreshPreparedActionStatus()
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
    self:RefreshPreparedActionStatus()
end

function MF:RefreshPreparedActionStatus()
    if not self.preparedActionLabel then return end
    local state = getPreparedActionState()
    if not state then
        self.preparedActionLabel:Hide()
        if self.preparedActionClearBtn then self.preparedActionClearBtn:Hide() end
        if self.footerLabel then self.footerLabel:Show() end
        return
    end

    self.preparedActionLabel:SetText(state.text)
    self.preparedActionLabel._tooltipTitle = "Guild Action Prepared"
    self.preparedActionLabel._tooltipBody = state.tooltip .. " Clear it if you do not want the next hotkey press to run it."
    self.preparedActionLabel:Show()
    if self.footerLabel then self.footerLabel:Hide() end
    if self.preparedActionClearBtn then
        self.preparedActionClearBtn._owner = state.owner
        self.preparedActionClearBtn:Show()
    end
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
    self:RefreshPreparedActionStatus()
end

function MF:ApplyTheme()
    local Th = T()
    if Th and Th.RefreshRegistered then
        Th:RefreshRegistered()
    end
    if activePanel then
        showPanel(activePanel, true)
    end
    self:ApplyScale()
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
    self.promptSlot:SetHeight(78)
    self.promptFrame:Show()
    self.panelHost:ClearAllPoints()
    self.panelHost:SetPoint("TOPLEFT", self.contentArea, "TOPLEFT", 0, -78)
    self.panelHost:SetPoint("TOPRIGHT", self.contentArea, "TOPRIGHT", 0, -78)
    self.panelHost:SetPoint("BOTTOMLEFT", self.contentArea, "BOTTOMLEFT", 0, 0)
    self.panelHost:SetPoint("BOTTOMRIGHT", self.contentArea, "BOTTOMRIGHT", 0, 0)

    local promptName = prompt.name or (prompt.key and prompt.key:match("^([^%-]+)")) or "Unknown"
    local firstSeen = prompt.firstSeenAt and date("%Y-%m-%d", prompt.firstSeenAt) or "recently"
    local promptCount = pendingClassificationCount()
    if self.promptTitle then
        self.promptTitle:SetText(promptCount > 1 and ("Pending Classification (" .. tostring(promptCount) .. ")") or "Pending Classification")
    end
    self.promptLabel:SetText(string.format("%s | First detected: %s | Status: Unknown main/alt", promptName, firstSeen))
    self.promptInput:SetText(prompt.main or "")
end

function MF:UpdateMiniFrame()
    if not self.miniFrame then return end
    if self.miniGuildLabel then
        self.miniGuildLabel:SetText(guildDisplayName())
    end
    if self.miniCountLabel then
        local total, online = 0, 0
        if GC.API and GC.API.GetNumGuildMembers then
            total, online = GC.API.GetNumGuildMembers()
        end
        total = total or 0
        online = online or 0
        self.miniCountLabel:SetText(online .. " / " .. total)
    end
end

function MF:CreateMiniFrame()
    if self.miniFrame then return end
    local Th = T()
    local uiState = GC.DB:GetUIState()

    local mini = CreateFrame("Frame", "GuildCoreMiniFrame", UIParent)
    mini:SetSize(236, 54)
    if self.frame and self.frame.GetScale then mini:SetScale(self.frame:GetScale() or 1) end
    mini:SetMovable(true)
    mini:EnableMouse(true)
    mini:RegisterForDrag("LeftButton")
    mini:SetClampedToScreen(true)
    if GC.UI.FrameLayering then
        GC.UI.FrameLayering:PrepareMainFrame(mini)
    else
        mini:SetFrameStrata("HIGH")
        mini:SetFrameLevel(80)
    end
    if uiState.miniX and uiState.miniY then
        mini:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", uiState.miniX, uiState.miniY)
    else
        mini:SetPoint("CENTER", UIParent, "CENTER", 0, 260)
    end
    Th.Bg(mini, Th.c.chrome, Th.c.borderAccent)
    mini:Hide()
    self.miniFrame = mini

    mini:SetScript("OnDragStart", mini.StartMoving)
    mini:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        saveMiniState()
    end)
    mini:SetScript("OnShow", function()
        MF:UpdateMiniFrame()
    end)
    mini:SetScript("OnHide", function()
        saveMiniState()
    end)

    local accent = mini:CreateTexture(nil, "ARTWORK")
    accent:SetPoint("TOPLEFT"); accent:SetPoint("BOTTOMLEFT")
    accent:SetWidth(2)
    local ac = Th.c.accent
    accent:SetColorTexture(ac[1], ac[2], ac[3], 0.64)

    local guild = Th.Fs(mini, "header", "", "textAccent")
    guild:SetPoint("TOPLEFT", 12, -6)
    guild:SetPoint("TOPRIGHT", mini, "TOPRIGHT", -78, -6)
    guild:SetJustifyH("LEFT")
    guild:SetWordWrap(false)
    self.miniGuildLabel = guild

    local title = Th.Fs(mini, "tiny", GC.Name or "Guild Core", "textDimmed")
    title:SetPoint("TOPLEFT", 12, -31)

    local count = Th.Fs(mini, "data", "", "textSecond")
    count:SetPoint("RIGHT", mini, "RIGHT", -44, -10)
    self.miniCountLabel = count

    local restoreBtn = GC.UI.Button.Create(mini, "+", "secondary", 30, 30)
    restoreBtn:SetPoint("RIGHT", mini, "RIGHT", -8, 0)
    restoreBtn:SetTooltip("Restore Guild Core")
    restoreBtn:SetScript("OnClick", function()
        MF:Restore()
    end)

end

function MF:Minimize()
    if not self.frame then return end
    self:CreateMiniFrame()
    local ui = GC.DB:GetUIState()
    ui.minimized = true
    saveUIState()
    self.frame:Hide()
    self:UpdateMiniFrame()
    self.miniFrame:Show()
end

function MF:Restore()
    if not self.frame then self:Create() end
    self:CreateMiniFrame()
    local ui = GC.DB:GetUIState()
    ui.minimized = false
    if self.miniFrame then
        saveMiniState()
        self.miniFrame:Hide()
    end
    self.frame:Show()
end

-- ──────────────────────────────────────────────
-- Build
-- ──────────────────────────────────────────────

function MF:Create()
    if self.frame then return end
    local Th = T()

    -- ── Window ──────────────────────────────────
    local frame = CreateFrame("Frame", "GuildCoreMainFrame", UIParent)
    local uiState = GC.DB:GetUIState()
    local screenW = UIParent and UIParent:GetWidth() or 1400
    local screenH = UIParent and UIParent:GetHeight() or 865
    local settings = GC.DB and GC.DB.GetSettings and GC.DB:GetSettings() or {}
    local requestedScale = math.max(0.75, math.min(1.25, tonumber(settings.uiScale) or 1))
    local uiScale = math.max(0.65, math.min(requestedScale, (screenW - 48) / 1120, (screenH - 48) / 680))
    local maxW = math.max(1120, math.floor((screenW / uiScale) - 48))
    local maxH = math.max(680, math.floor((screenH / uiScale) - 48))
    local minW = 1120
    local minH = 680
    local initialW = math.max(minW, math.min(maxW, tonumber(uiState.windowWidth) or 1280))
    local initialH = math.max(minH, math.min(maxH, tonumber(uiState.windowHeight) or 780))
    frame:SetSize(initialW, initialH)
    frame:SetScale(uiScale)
    frame:SetMovable(true)
    if frame.SetResizable then frame:SetResizable(true) end
    if frame.SetResizeBounds then
        frame:SetResizeBounds(minW, minH, maxW, maxH)
    else
        if frame.SetMinResize then frame:SetMinResize(minW, minH) end
        if frame.SetMaxResize then frame:SetMaxResize(maxW, maxH) end
    end
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    if GC.UI.FrameLayering then
        GC.UI.FrameLayering:PrepareMainFrame(frame)
    else
        frame:SetFrameStrata("HIGH")
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
    frame:SetScript("OnSizeChanged", function()
        if MF._resizeRefreshPending or not frame:IsShown() then return end
        MF._resizeRefreshPending = true
        if C_Timer and C_Timer.After then
            C_Timer.After(0.08, function()
                MF._resizeRefreshPending = false
                saveUIState()
                MF:RefreshActive()
            end)
        else
            MF._resizeRefreshPending = false
        end
    end)

    local resizeGrip = CreateFrame("Button", nil, frame)
    resizeGrip:SetSize(22, 22)
    resizeGrip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -3, 3)
    resizeGrip:SetFrameLevel((frame:GetFrameLevel() or 80) + 10)
    local gripColor = Th.c.textDimmed
    for offset = 0, 2 do
        local mark = resizeGrip:CreateTexture(nil, "OVERLAY")
        mark:SetSize(2 + (offset * 4), 2)
        mark:SetPoint("BOTTOMRIGHT", resizeGrip, "BOTTOMRIGHT", -3, 4 + (offset * 4))
        mark:SetColorTexture(gripColor[1], gripColor[2], gripColor[3], 0.7)
    end
    resizeGrip:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" and frame.StartSizing then frame:StartSizing("BOTTOMRIGHT") end
    end)
    resizeGrip:SetScript("OnMouseUp", function()
        if frame.StopMovingOrSizing then frame:StopMovingOrSizing() end
        saveUIState()
    end)
    resizeGrip:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
            GameTooltip:SetText("Resize Guild Core", 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    resizeGrip:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    self.resizeGrip = resizeGrip

    -- Background + accent border
    Th.Bg(frame, Th.c.bg, Th.c.borderAccent)

    -- Outer shadow is parented to UIParent so it can sit just behind the main frame.
    local shadow = CreateFrame("Frame", nil, UIParent)
    shadow:SetPoint("TOPLEFT",     frame, "TOPLEFT",     -6, 6)
    shadow:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT",  6,-6)
    if GC.UI.FrameLayering then
        GC.UI.FrameLayering:PrepareShadowFrame(shadow, frame)
    else
        shadow:SetFrameStrata("HIGH")
        shadow:SetFrameLevel(math.max(1, (frame:GetFrameLevel() or 80) - 1))
    end
    shadow:Hide()
    Th.Bg(shadow, {0, 0, 0, 0.42})
    self.shadowFrame = shadow

    frame:SetScript("OnShow", function()
        shadow:Show()
        if MF.guildLabel then
            MF.guildLabel:SetText(guildDisplayName())
        end
        -- Update online/member count in status bar
        MF:UpdateMemberCount()
        MF:RefreshActive()
    end)
    frame:SetScript("OnHide", function()
        if GC.UI and GC.UI.CharacterContextMenu then
            GC.UI.CharacterContextMenu:Close()
        end
        if GC.UI and GC.UI.EditCharacterPopup and GC.UI.EditCharacterPopup.frame then
            GC.UI.EditCharacterPopup:Cancel()
        end
        shadow:Hide()
        saveUIState()
    end)

    -- ── Title bar ───────────────────────────────
    local titleBar = CreateFrame("Frame", nil, frame)
    titleBar:SetPoint("TOPLEFT"); titleBar:SetPoint("TOPRIGHT")
    titleBar:SetHeight(Th.titleBarH)
    Th.Bg(titleBar, Th.c.chrome, nil, {rounded = true})

    local titleEdge = titleBar:CreateTexture(nil, "ARTWORK")
    titleEdge:SetPoint("BOTTOMLEFT"); titleEdge:SetPoint("BOTTOMRIGHT"); titleEdge:SetHeight(1)
    local ac = Th.c.accent
    titleEdge:SetColorTexture(ac[1], ac[2], ac[3], 0.26)

    local guildFs = Th.Fs(titleBar, "header", guildDisplayName(), "textAccent")
    guildFs:SetPoint("LEFT", 16, 5)
    guildFs:SetPoint("RIGHT", titleBar, "RIGHT", -220, 5)
    guildFs:SetJustifyH("LEFT")
    guildFs:SetWordWrap(false)
    self.guildLabel = guildFs

    local titleFs = Th.Fs(titleBar, "tiny", GC.Name or "Guild Core", "textDimmed")
    titleFs:SetPoint("LEFT", 16, -17)

    local verFs = Th.Fs(titleBar, "data", "v" .. (GC.Version or "0"), "textDimmed")
    verFs:SetPoint("RIGHT", -100, 0)

    -- Minimize button
    local minBtn = GC.UI.Button.Create(frame, "-", "secondary", 30, 30)
    minBtn:SetPoint("TOPRIGHT", -45, -9)
    minBtn:SetTooltip("Minimize Guild Core", "Collapse into a small draggable frame.")
    minBtn:SetScript("OnClick", function()
        MF:Minimize()
    end)

    -- Close button
    local closeBtn = GC.UI.Button.Create(frame, "X", "danger", 30, 30)
    closeBtn:SetPoint("TOPRIGHT", -9, -9)
    closeBtn:SetTooltip("Close Guild Core")
    closeBtn:SetScript("OnClick", function() GC.UI:Hide() end)

    -- ── Status bar ──────────────────────────────
    local statusBar = CreateFrame("Frame", nil, frame)
    statusBar:SetPoint("BOTTOMLEFT"); statusBar:SetPoint("BOTTOMRIGHT")
    statusBar:SetHeight(Th.statusBarH)
    Th.Bg(statusBar, Th.c.chrome, Th.c.border)
    local statusEdge = statusBar:CreateTexture(nil, "ARTWORK")
    statusEdge:SetPoint("TOPLEFT"); statusEdge:SetPoint("TOPRIGHT"); statusEdge:SetHeight(1)
    statusEdge:SetColorTexture(ac[1], ac[2], ac[3], 0.18)
    local statusFs = Th.Fs(statusBar, "data", "", "textDimmed")
    statusFs:SetPoint("LEFT", 12, 0)
    self.statusLabel = statusFs

    local memberFs = Th.Fs(statusBar, "data", "", "textDimmed")
    memberFs:SetPoint("RIGHT", -12, 0)
    self.memberCountLabel = memberFs

    local footerFs = Th.Fs(statusBar, "data", "\194\169 2026 AddOns by Catastrophie", "textDimmed")
    footerFs:SetPoint("CENTER", statusBar, "CENTER", 0, 0)
    self.footerLabel = footerFs

    local preparedFs = Th.Fs(statusBar, "data", "", "textWarn")
    preparedFs:SetPoint("CENTER", statusBar, "CENTER", -34, 0)
    preparedFs:SetJustifyH("CENTER")
    preparedFs:Hide()
    self.preparedActionLabel = preparedFs

    local preparedClearBtn = GC.UI.Button.Create(statusBar, "Clear", "secondary", 54, Th.btnH - 4)
    preparedClearBtn:SetPoint("LEFT", preparedFs, "RIGHT", 8, 0)
    preparedClearBtn:SetTooltip("Clear Prepared Action", "Disarm the current guild action macro and empty its prepared queue.")
    preparedClearBtn:SetScript("OnClick", function()
        local owner = preparedClearBtn._owner or (GC.State and GC.State.actionMacroOwner)
        if owner == "operations" and GC.Services and GC.Services.OperationsMacro then
            GC.Services.OperationsMacro:ClearQueue()
            MF:SetStatus("Prepared rank action cleared.", "textWarn")
        elseif owner == "purge" and GC.Services and GC.Services.Purge then
            GC.Services.Purge:ClearQueue()
            MF:SetStatus("Prepared purge action cleared.", "textWarn")
            if GC.UI.PurgePanel and GC.UI.PurgePanel.Refresh then GC.UI.PurgePanel:Refresh() end
        else
            MF:SetStatus("No prepared guild action to clear.", "textDimmed")
        end
        MF:RefreshPreparedActionStatus()
    end)
    preparedClearBtn:Hide()
    self.preparedActionClearBtn = preparedClearBtn

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
        {id = "invite",     label = "Invite", gapBefore = true},
        {id = "messaging",  label = "Messages"},
        {id = "purge",      label = "Purge", gapBefore = true},
        {id = "banbook",    label = "Ban Book"},
        {id = "log",        label = "Activity"},
        {id = "settings",   label = "Settings", gapBefore = true},
        {id = "help",       label = "Help"},
    }

    local navItemH = 42
    local navY = 0
    for i, item in ipairs(navItems) do
        if item.gapBefore then navY = navY + 10 end
        local btn = CreateFrame("Button", nil, sidebar)
        btn:SetHeight(navItemH)
        btn:SetPoint("TOPLEFT",  sidebar, "TOPLEFT",  0, -navY)
        btn:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", 0, -navY)
        navY = navY + navItemH

        local nc = Th.c.navBg
        local bg = Th.RoundedSurface(btn, nc, nil, 6, "BACKGROUND", -8)
        btn._bg = bg

        local accentBar = btn:CreateTexture(nil, "ARTWORK")
        accentBar:SetWidth(2); accentBar:SetPoint("TOPLEFT"); accentBar:SetPoint("BOTTOMLEFT")
        accentBar:SetColorTexture(ac[1], ac[2], ac[3], 0.72); accentBar:SetAlpha(0)
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
    promptFrame:SetHeight(62)
    Th.Bg(promptFrame, Th.c.panelAlt, Th.c.borderAccent)
    promptFrame:Hide()
    self.promptFrame = promptFrame

    local promptTitle = Th.Fs(promptFrame, "tiny", "Pending Classification", "textAccent")
    promptTitle:SetPoint("TOPLEFT", 10, -6)
    self.promptTitle = promptTitle

    local promptLabel = Th.Fs(promptFrame, "data", "", "textSecond")
    promptLabel:SetPoint("TOPLEFT", 10, -22)
    promptLabel:SetPoint("TOPRIGHT", promptFrame, "TOPRIGHT", -430, -20)
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

    local promptAltBtn = GC.UI.Button.Create(promptFrame, "Link Alt", "secondary", 64, Th.btnH)
    promptAltBtn:SetPoint("RIGHT", promptViewBtn, "LEFT", -6, 0)
    promptAltBtn:SetScript("OnClick", function()
        if not self.promptTargetKey then return end
        local mainKey = GS():ResolvePlayerKey(promptInput:GetText() or "")
        if not mainKey then
            self:SetStatus("Enter a known main character name or key.", "textDanger")
            return
        end
        local ok, result = GC.Services.Alts:SetAlt(self.promptTargetKey, mainKey, "prompt")
        local message = ok
            and GC.Services.Alts:DescribeLinkResult(result, "Alt link saved.")
            or result
        self:SetStatus(message, ok and "textSuccess" or "textDanger")
        self:RefreshActive()
    end)

    local promptMainBtn = GC.UI.Button.Create(promptFrame, "Mark Main", "success", 78, Th.btnH)
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

    -- ── Lazy panel registry ───────────────────────
    -- Build panels only when opened. This avoids paying the UI object cost for
    -- Messages/Invite/Settings/etc. just because the main window was shown.
    panels.dashboard  = {hasDetail = false, create = function()
        GC.UI.Dashboard:Create(panelHost)
        panels.dashboard.frame = GC.UI.Dashboard.frame
    end, refresh = function() GC.UI.Dashboard:Refresh() end}
    panels.roster     = {hasDetail = true, create = function()
        GC.UI.RosterPanel:Create(panelHost)
        panels.roster.frame = GC.UI.RosterPanel.frame
    end, refresh = function() GC.UI.RosterPanel:Refresh() end}
    panels.purge      = {hasDetail = false, create = function()
        GC.UI.PurgePanel:Create(panelHost)
        panels.purge.frame = GC.UI.PurgePanel.frame
    end, refresh = function() GC.UI.PurgePanel:Refresh() end}
    panels.invite     = {hasDetail = false, create = function()
        GC.UI.InvitePanel:Create(panelHost)
        panels.invite.frame = GC.UI.InvitePanel.frame
    end, refresh = function() GC.UI.InvitePanel:Refresh() end}
    panels.banbook    = {hasDetail = false, create = function()
        GC.UI.BanBookPanel:Create(panelHost)
        panels.banbook.frame = GC.UI.BanBookPanel.frame
    end, refresh = function() GC.UI.BanBookPanel:Refresh() end}
    panels.log        = {hasDetail = false, create = function()
        GC.UI.LogPanel:Create(panelHost)
        panels.log.frame = GC.UI.LogPanel.frame
    end, refresh = function() GC.UI.LogPanel:Refresh() end}
    panels.messaging  = {hasDetail = false, create = function()
        GC.UI.MessagingPanel:Create(panelHost)
        panels.messaging.frame = GC.UI.MessagingPanel.frame
    end, refresh = function() GC.UI.MessagingPanel:Refresh() end}
    panels.settings   = {hasDetail = false, create = function()
        GC.UI.SettingsPanel:Create(panelHost)
        panels.settings.frame = GC.UI.SettingsPanel.frame
    end, refresh = function() GC.UI.SettingsPanel:Refresh() end}
    panels.help       = {hasDetail = false, create = function()
        GC.UI.HelpPanel:Create(panelHost)
        panels.help.frame = GC.UI.HelpPanel.frame
    end, refresh = function() GC.UI.HelpPanel:Refresh() end}

    -- Restore last panel (no refresh; frame is still hidden).
    local startPanel = (uiState.lastPanel and panels[uiState.lastPanel]) and uiState.lastPanel or "dashboard"
    showPanel(startPanel, true)
    self:RefreshPrompt()
    self:RefreshPreparedActionStatus()
end

-- Update the member count label in the status bar.
function MF:UpdateMemberCount()
    if not self.memberCountLabel then return end
    local total, online = 0, 0
    if GC.API and GC.API.GetNumGuildMembers then
        total, online = GC.API.GetNumGuildMembers()
    end
    total  = total  or 0
    online = online or 0
    self.memberCountLabel:SetText(online .. " / " .. total .. " online")
end

-- ──────────────────────────────────────────────
-- GC.UI top-level API  (routes all entry points)
-- ──────────────────────────────────────────────

function GC.UI:Show()
    if not MF.frame then MF:Create() end
    MF:CreateMiniFrame()
    if GC.UI.FrameLayering then
        GC.UI.FrameLayering:PrepareMainFrame(MF.frame)
        GC.UI.FrameLayering:PrepareMainFrame(MF.miniFrame)
    end
    local ui = GC.DB:GetUIState()
    if ui.minimized then
        MF.frame:Hide()
        MF:UpdateMiniFrame()
        MF.miniFrame:Show()
        return
    end
    if MF.miniFrame then MF.miniFrame:Hide() end
    MF.frame:Show()
    MF:RefreshActive()
end

function GC.UI:Hide()
    if MF.frame then MF.frame:Hide() end
    if MF.miniFrame then MF.miniFrame:Hide() end
end

function GC.UI:Toggle()
    if MF.frame and MF.frame:IsShown() then
        GC.UI:Hide()
    elseif MF.miniFrame and MF.miniFrame:IsShown() then
        MF:Restore()
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

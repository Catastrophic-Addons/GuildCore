-- UI/Dashboard.lua
-- Interactive guild operations center: health, metric shortcuts, and action queue.
local addonName, ns = ...
local GC = ns.GuildCore

GC.UI.Dashboard = GC.UI.Dashboard or {}
local DB = GC.UI.Dashboard

local function T()  return GC.UI.Theme  end
local function GS() return GC.Services.GuildService end

local SECTION_GAP = 10
local SNAPSHOT_KEYS = {
    total = "members",
    online = "online",
    active = "active7d",
    inactive = "inactive",
    recentJoins = "joined7d",
    recentLeaves = "left7d",
    recentRankChanges = "rankChanges7d",
    initiatesNeedingReview = "initiatesNeedingReview",
    missingDiscordVerification = "missingDiscord",
    unlinkedCharacters = "unknownMainAlt",
    rosterDataIssues = "rosterDataIssues",
    inactiveMembers = "readyForPurge",
    logCount = "logEntries",
}

local ICONS = {
    total = "Interface\\FriendsFrame\\FriendsFrameScrollIcon",
    online = "Interface\\FriendsFrame\\StatusIcon-Online",
    active = "Interface\\Calendar\\EventNotification",
    inactive = "Interface\\FriendsFrame\\StatusIcon-Away",
    recentJoins = "Interface\\Buttons\\UI-PlusButton-Up",
    recentLeaves = "Interface\\Buttons\\UI-MinusButton-Up",
    recentRankChanges = "Interface\\GuildFrame\\GuildLogo-NoLogo",
    logCount = "Interface\\Buttons\\UI-GuildButton-PublicNote-Up",
    initiatesNeedingReview = "Interface\\GuildFrame\\GuildFrame",
    missingDiscordVerification = "Interface\\FriendsFrame\\BroadcastIcon",
    unlinkedCharacters = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
    rosterDataIssues = "Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew",
    inactiveMembers = "Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew",
}

local METRIC_GROUPS = {
    {
        title = "Guild Overview",
        key = "overview",
        items = {
            {key = "total", label = "Members", target = "roster_all"},
            {key = "online", label = "Online", target = "roster_online"},
            {key = "active", label = "Active (7d)", target = "roster_active"},
            {key = "inactive", label = "Inactive", target = "roster_inactive"},
        },
    },
    {
        title = "Officer Work Queue",
        key = "work",
        items = {
            {key = "initiatesNeedingReview", label = "Initiates Needing Review", target = "roster_initiates"},
            {key = "missingDiscordVerification", label = "Missing Discord Verification", target = "roster_missing_discord"},
            {key = "unlinkedCharacters", label = "Unlinked / Unknown", target = "roster_unknown_main_alt"},
            {key = "rosterDataIssues", label = "Roster Data Issues", target = "roster_relationship_issues"},
            {key = "inactiveMembers", label = "Ready for Purge", target = "purge_ready"},
        },
    },
    {
        title = "Activity Snapshot",
        key = "activity",
        items = {
            {key = "recentJoins", label = "Joined (7d)", target = "activity_joined"},
            {key = "recentLeaves", label = "Left (7d)", target = "activity_left"},
            {key = "recentRankChanges", label = "Rank Changes (7d)", target = "activity_rank_changes"},
            {key = "logCount", label = "Log Entries", target = "activity_all"},
        },
    },
}

-- TODO: add per-officer dashboard widget visibility/order preferences once
-- Guild Core has a settings profile model for personalized layouts.
-- TODO: support dragging/reordering card groups when hiddenCards grows into a
-- full dashboard customization UI.

local function dashboardSettings()
    local settings = GC.Services and GC.Services.DataStore and GC.Services.DataStore:GetSettings() or {}
    settings.dashboard = type(settings.dashboard) == "table" and settings.dashboard or {}
    local dashboard = settings.dashboard
    if dashboard.compactMode == nil then dashboard.compactMode = false end
    if dashboard.showHealth == nil then dashboard.showHealth = true end
    if dashboard.showTrends == nil then dashboard.showTrends = true end
    if dashboard.showIcons == nil then dashboard.showIcons = true end
    if dashboard.showQuickActions == nil then dashboard.showQuickActions = true end
    dashboard.hiddenCards = type(dashboard.hiddenCards) == "table" and dashboard.hiddenCards or {}
    dashboard.snapshotThrottleSeconds = tonumber(dashboard.snapshotThrottleSeconds) or 900
    return dashboard
end

local function dashboardSnapshots()
    if not GuildCoreDB then return {} end
    GuildCoreDB.dashboardSnapshots = type(GuildCoreDB.dashboardSnapshots) == "table" and GuildCoreDB.dashboardSnapshots or {}
    return GuildCoreDB.dashboardSnapshots
end

local function debugLog(...)
    if GC.Debug then GC:Debug("Dashboard:", ...) end
end

local function colorForState(state)
    local Th = T()
    if state == "healthy" then return Th.c.statusActive or Th.c.textSuccess or Th.c.textAccent end
    if state == "warning" then return Th.c.textWarn or Th.c.statusWarn or Th.c.textAccent end
    if state == "danger" then return Th.c.textDanger or Th.c.statusInact or Th.c.textWarn end
    return Th.c.accent
end

local function showStatus(message, colorKey)
    if GC.UI and GC.UI.MainFrame then
        GC.UI.MainFrame:SetStatus(message, colorKey or "textSecond")
    end
end

local function buildRepairPreviewText(preview, result)
    preview = preview or {}
    local lines = {}
    local summary = preview.summary or {}
    local safeCount = summary.safeActions or #(preview.actions or {})
    local manualCount = summary.manualReview or #(preview.unsafe or {})
    lines[#lines + 1] = "Safe Alt Link Repair Preview"
    lines[#lines + 1] = ""
    if result then
        lines[#lines + 1] = string.format("Safe repairs applied: %d. Manual issues remaining: %d.", result.applied or 0, manualCount)
        if (result.skipped or 0) > 0 then
            lines[#lines + 1] = string.format("Skipped during apply because data changed: %d.", result.skipped or 0)
        end
    elseif safeCount == 0 and manualCount == 0 then
        lines[#lines + 1] = "No roster relationship issues found."
    elseif safeCount == 0 then
        lines[#lines + 1] = "No safe automatic repairs are available. Manual review is required."
    else
        lines[#lines + 1] = string.format("Safe repairs ready: %d. Manual review items: %d.", safeCount, manualCount)
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Safe repairs are non-destructive relationship cleanup only."
    lines[#lines + 1] = "Manual-review items are not fixed automatically; Guild Core will not guess a missing Main."
    lines[#lines + 1] = "This does not change notes, Discord, join dates, rank history, points, settings, or imported metadata."

    if preview.actions and #preview.actions > 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "Safe Repairs"
        for i, action in ipairs(preview.actions) do
            if i > 40 then
                lines[#lines + 1] = string.format("...and %d more", #preview.actions - 40)
                break
            end
            lines[#lines + 1] = string.format("- %s [%s]: %s", tostring(action.characterKey or "?"), tostring(action.action or "repair"), tostring(action.message or "Repair relationship data."))
        end
    end

    if preview.unsafe and #preview.unsafe > 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "Needs Manual Review"
        for i, issue in ipairs(preview.unsafe) do
            if i > 30 then
                lines[#lines + 1] = string.format("...and %d more", #preview.unsafe - 30)
                break
            end
            lines[#lines + 1] = string.format("- %s [%s]: %s", tostring(issue.characterKey or "?"), tostring(issue.code or "manual"), tostring(issue.message or "Review relationship data."))
        end
    end

    return table.concat(lines, "\n")
end

local function sectionHeader(parent, title, y)
    local Th = T()
    local fs = Th.Fs(parent, "subheader", title, "textAccent")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", Th.padding, y)
    local sep = parent:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("LEFT", fs, "RIGHT", 10, 0)
    sep:SetPoint("RIGHT", parent, "RIGHT", -Th.padding, 0)
    local c = Th.c.separator
    sep:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    return fs
end

local function decorateClickable(frame)
    frame:EnableMouse(true)
    frame:RegisterForClicks("LeftButtonUp")
    frame:SetScript("OnEnter", function(self)
        if self._hover then self._hover:SetAlpha(1) end
        if self._hint then self._hint:SetAlpha(0.9) end
    end)
    frame:SetScript("OnLeave", function(self)
        if self._hover then self._hover:SetAlpha(0) end
        if self._hint then self._hint:SetAlpha(0.45) end
    end)
end

local function createMetricCard(parent, def)
    local Th = T()
    local f = CreateFrame("Button", nil, parent)
    Th.Bg(f, Th.c.panelAlt, Th.c.border)

    local stripe = f:CreateTexture(nil, "ARTWORK")
    stripe:SetPoint("TOPLEFT"); stripe:SetPoint("TOPRIGHT"); stripe:SetHeight(3)
    local a = Th.c.accent
    stripe:SetColorTexture(a[1], a[2], a[3], 0.55)
    f._stripe = stripe

    local hover = f:CreateTexture(nil, "BACKGROUND", nil, -5)
    hover:SetAllPoints()
    local h = Th.c.rowHover
    hover:SetColorTexture(h[1], h[2], h[3], h[4] or 0.35)
    hover:SetAlpha(0)
    f._hover = hover

    local label = Th.Fs(f, "small", def.label or "", "textDimmed")
    label:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -10)
    label:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -10)
    label:SetJustifyH("CENTER")
    label:SetWordWrap(false)

    local value = Th.Fs(f, "dataLarge", "0", "textPrimary")
    value:SetPoint("CENTER", f, "CENTER", 0, -5)
    value:SetJustifyH("CENTER")
    f._value = value

    local trend = Th.Fs(f, "tiny", "", "textDimmed")
    trend:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 8, 5)
    f._trend = trend

    local iconTexture = DB:GetIcon(def.key)
    if iconTexture then
        local icon = f:CreateTexture(nil, "ARTWORK")
        icon:SetSize(16, 16)
        icon:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -8)
        local ok = icon:SetTexture(iconTexture)
        if ok == false then icon:Hide() end
        icon:SetAlpha(0.55)
        f._icon = icon
    end

    local hint = Th.Fs(f, "tiny", "open", "textDimmed")
    hint:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 5)
    hint:SetAlpha(def.target and 0.45 or 0)
    f._hint = hint

    decorateClickable(f)
    f:SetScript("OnClick", function()
        if def.target then DB:NavigateTo(def.target, def) end
    end)

    return f
end

local function buildActionQueueRow(row, item)
    local Th = T()
    if not row._built then
        local marker = row:CreateTexture(nil, "ARTWORK")
        marker:SetPoint("TOPLEFT"); marker:SetPoint("BOTTOMLEFT"); marker:SetWidth(3)
        row._marker = marker

        local nameFs = Th.Fs(row, "small", "", "textPrimary")
        nameFs:SetPoint("LEFT", 10, 0)
        nameFs:SetWidth(170)

        local issueFs = Th.Fs(row, "small", "", "textSecond")
        issueFs:SetPoint("LEFT", 188, 0)
        issueFs:SetWidth(250)

        local actionFs = Th.Fs(row, "small", "", "textAccent")
        actionFs:SetPoint("LEFT", 450, 0)
        actionFs:SetPoint("RIGHT", -96, 0)

        local reviewBtn = GC.UI.Button.Create(row, "Review", "secondary", 76, Th.btnH - 4)
        reviewBtn:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        reviewBtn:SetScript("OnClick", function()
            if row._item then
                DB:NavigateTo(row._item.target or row._item.panel or "roster", row._item)
            end
        end)

        row._nameFs = nameFs
        row._issueFs = issueFs
        row._actionFs = actionFs
        row._reviewBtn = reviewBtn
        row._built = true
    end

    row._item = item
    local color = colorForState(item and item.state or "neutral")
    row._marker:SetColorTexture(color[1], color[2], color[3], 0.9)
    row._nameFs:SetText(item and item.character or "-")
    row._issueFs:SetText(item and item.issue or "-")
    row._actionFs:SetText(item and item.action or "-")
    row._actionFs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
end

local function countPendingPrompts()
    local settings = GC.Services.DataStore:GetSettings()
    if settings and settings.enableClassificationPrompts == false then return 0 end
    local players = GC.Services.DataStore:GetPlayers()
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

function DB:GetIcon(metricKey)
    return ICONS[metricKey]
end

function DB:CreateEmptyState(parent, title, subtitle)
    local Th = T()
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    frame:EnableMouse(false)
    frame:Hide()

    local titleFs = Th.Fs(frame, "body", title or "No data", "textSecond")
    titleFs:SetPoint("CENTER", frame, "CENTER", 0, 10)
    titleFs:SetJustifyH("CENTER")
    frame.titleFs = titleFs

    local subFs = Th.Fs(frame, "small", subtitle or "", "textDimmed")
    subFs:SetPoint("TOP", titleFs, "BOTTOM", 0, -5)
    subFs:SetJustifyH("CENTER")
    frame.subtitleFs = subFs

    function frame:SetMessage(newTitle, newSubtitle)
        self.titleFs:SetText(newTitle or "")
        self.subtitleFs:SetText(newSubtitle or "")
    end

    return frame
end

function DB:CollectMetrics(stats, insights)
    return {
        total = stats.total or 0,
        online = stats.online or 0,
        active = stats.active or 0,
        inactive = stats.inactive or 0,
        recentJoins = stats.recentJoins or 0,
        recentLeaves = stats.recentLeaves or 0,
        recentRankChanges = stats.recentRankChanges or 0,
        logCount = stats.logCount or 0,
        initiatesNeedingReview = insights.initiatesNeedingReview or 0,
        missingDiscordVerification = insights.missingDiscordVerification or 0,
        unlinkedCharacters = insights.unlinkedCharacters or 0,
        rosterDataIssues = insights.rosterDataIssues or 0,
        inactiveMembers = insights.inactiveMembers or 0,
        lastScanAt = stats.lastScanAt,
    }
end

function DB:GetHealthState(metrics)
    local state = "stable"
    if (metrics.rosterDataIssues or 0) > 0 or (metrics.inactiveMembers or 0) > 0 or (metrics.unlinkedCharacters or 0) > 50 then
        state = "critical"
    elseif (metrics.missingDiscordVerification or 0) > 0
        or (metrics.inactive or 0) > 0
        or (metrics.unlinkedCharacters or 0) > 0
        or (metrics.recentLeaves or 0) > 0
        or (metrics.recentRankChanges or 0) > 0 then
        state = "attention"
    end
    local label = state == "critical" and "Critical Review Needed" or state == "attention" and "Attention Needed" or "Stable"
    debugLog("health state", state, "purge", tostring(metrics.inactiveMembers or 0), "unknown", tostring(metrics.unlinkedCharacters or 0))
    return state, label
end

function DB:GetHealthSummaryLines(metrics)
    return {
        string.format("%d tracked", metrics.total or 0),
        string.format("%d online", metrics.online or 0),
        string.format("%d main/alt review", metrics.unlinkedCharacters or 0),
        string.format("%d data issues", metrics.rosterDataIssues or 0),
    }
end

function DB:BuildHealthSummary(metrics)
    local state, label = self:GetHealthState(metrics)
    return {
        state = state,
        label = label,
        lines = self:GetHealthSummaryLines(metrics),
    }
end

function DB:SnapshotFromMetrics(metrics)
    return {
        timestamp = time(),
        members = metrics.total or 0,
        online = metrics.online or 0,
        active7d = metrics.active or 0,
        inactive = metrics.inactive or 0,
        joined7d = metrics.recentJoins or 0,
        left7d = metrics.recentLeaves or 0,
        rankChanges7d = metrics.recentRankChanges or 0,
        logEntries = metrics.logCount or 0,
        initiatesNeedingReview = metrics.initiatesNeedingReview or 0,
        missingDiscord = metrics.missingDiscordVerification or 0,
        unknownMainAlt = metrics.unlinkedCharacters or 0,
        rosterDataIssues = metrics.rosterDataIssues or 0,
        readyForPurge = metrics.inactiveMembers or 0,
    }
end

function DB:GetTrend(metricKey, currentValue)
    local settings = dashboardSettings()
    if settings.showTrends == false then return nil end
    local snapshots = dashboardSnapshots()
    local previous = snapshots.last
    local previousKey = SNAPSHOT_KEYS[metricKey]
    if type(previous) ~= "table" or not previousKey or previous[previousKey] == nil then
        return nil
    end

    local delta = (tonumber(currentValue) or 0) - (tonumber(previous[previousKey]) or 0)
    local direction = delta > 0 and "up" or delta < 0 and "down" or "same"
    local label = direction == "up" and ("^ " .. tostring(delta))
        or direction == "down" and ("v " .. tostring(math.abs(delta)))
        or "->"
    debugLog("trend", tostring(metricKey), tostring(direction), tostring(delta))
    return {
        direction = direction,
        delta = delta,
        label = label,
    }
end

function DB:SaveSnapshot(metrics)
    local settings = dashboardSettings()
    local snapshots = dashboardSnapshots()
    local now = time()
    local last = snapshots.last
    local throttle = math.max(60, tonumber(settings.snapshotThrottleSeconds) or 900)
    if type(last) == "table" and last.timestamp and (now - last.timestamp) < throttle then
        debugLog("snapshot throttled", tostring(now - last.timestamp), "seconds")
        return false
    end
    snapshots.last = self:SnapshotFromMetrics(metrics)
    debugLog("snapshot saved", tostring(snapshots.last.timestamp))
    return true
end

function DB:GetMetricState(metricKey, value)
    value = tonumber(value) or 0
    if metricKey == "online" or metricKey == "active" then
        return value > 0 and "healthy" or "neutral"
    end
    if metricKey == "inactiveMembers" or metricKey == "rosterDataIssues" then
        return value > 0 and "danger" or "healthy"
    end
    if metricKey == "inactive" or metricKey == "missingDiscordVerification" or metricKey == "unlinkedCharacters" or metricKey == "initiatesNeedingReview" then
        return value > 0 and "warning" or "healthy"
    end
    if metricKey == "recentLeaves" then
        return value > 0 and "warning" or "neutral"
    end
    return "neutral"
end

function DB:SetMetricState(card, state)
    if not card then return end
    local c = colorForState(state)
    if card._stripe then card._stripe:SetColorTexture(c[1], c[2], c[3], state == "neutral" and 0.45 or 0.85) end
    if card._value then card._value:SetTextColor(c[1], c[2], c[3], c[4] or 1) end
end

function DB:ApplyDashboardSettings(settings)
    settings = settings or dashboardSettings()
    if self.healthCard then self.healthCard:SetShown(settings.showHealth ~= false) end
    for _, btn in ipairs(self.quickButtons or {}) do
        btn:SetShown(settings.showQuickActions ~= false)
    end
    for key, card in pairs(self.metricCards or {}) do
        local hidden = settings.hiddenCards and settings.hiddenCards[key] == true
        card:SetShown(not hidden)
        if card._icon then card._icon:SetShown(settings.showIcons ~= false) end
        if card._trend then card._trend:SetShown(settings.showTrends ~= false) end
    end
end

function DB:NavigateTo(target, payload)
    local memBefore = GC.Perf and GC.Perf:Snapshot("Dashboard navigation before")
    local main = GC.UI.MainFrame
    local roster = GC.UI.RosterPanel
    local log = GC.UI.LogPanel

    debugLog("navigate", tostring(target))
    local function finish()
        if GC.Perf then GC.Perf:Delta("Dashboard navigation after " .. tostring(target or "unknown"), memBefore) end
    end

    if target == "roster_all" then
        main:SetActivePanel("roster")
        if roster and roster.ClearFilters then roster:ClearFilters() end
        finish()
        return
    elseif target == "roster_online" then
        main:SetActivePanel("roster")
        if roster and roster.ApplyDashboardFilter then roster:ApplyDashboardFilter("online") end
        finish()
        return
    elseif target == "roster_active" then
        main:SetActivePanel("roster")
        if roster and roster.ApplyDashboardFilter then roster:ApplyDashboardFilter("active") end
        finish()
        return
    elseif target == "roster_inactive" then
        main:SetActivePanel("roster")
        if roster and roster.ApplyDashboardFilter then roster:ApplyDashboardFilter("inactive") end
        finish()
        return
    elseif target == "roster_unknown_main_alt" then
        main:SetActivePanel("roster")
        if roster and roster.ApplyDashboardFilter then roster:ApplyDashboardFilter("unknown_main_alt") end
        finish()
        return
    elseif target == "roster_relationship_issues" then
        main:SetActivePanel("roster")
        if roster and roster.ApplyDashboardFilter then roster:ApplyDashboardFilter("relationship_issues") end
        finish()
        return
    elseif target == "roster_missing_discord" then
        main:SetActivePanel("roster")
        if roster and roster.ApplyDashboardFilter then roster:ApplyDashboardFilter("missing_discord") end
        finish()
        return
    elseif target == "roster_initiates" then
        main:SetActivePanel("roster")
        if roster and roster.ApplyDashboardFilter then roster:ApplyDashboardFilter("initiates") end
        finish()
        return
    elseif target == "purge_ready" then
        main:SetActivePanel("purge")
        if GC.Services.Purge and GC.Services.Purge.ScanCandidates then GC.Services.Purge:ScanCandidates({silent = true}) end
        showStatus("Opened purge review for ready members.", "textWarn")
        finish()
        return
    elseif target == "activity_joined" or target == "activity_left" or target == "activity_rank_changes" or target == "activity_all" then
        main:SetActivePanel("log")
        if log and log.ApplyDashboardFilter then
            local filter = ({
                activity_joined = "joined",
                activity_left = "left",
                activity_rank_changes = "rank_changes",
                activity_all = "all",
            })[target]
            log:ApplyDashboardFilter(filter)
        end
        finish()
        return
    elseif target == "ban_book" then
        main:SetActivePanel("banbook")
        finish()
        return
    elseif target == "relationship_repair" then
        self:ShowRelationshipRepairPreview()
        finish()
        return
    elseif target == "compliance" then
        self:RunCompliance()
        finish()
        return
    elseif target == "invite_scan" then
        main:SetActivePanel("invite")
        if GC.UI.InvitePanel and GC.UI.InvitePanel._doScan then
            GC.UI.InvitePanel:_doScan()
        else
            showStatus("Opened Invite tab. Scan action is unavailable from dashboard.", "textWarn")
        end
        finish()
        return
    elseif target == "roster_character" and payload and (payload.key or payload.character) then
        main:SetActivePanel("roster")
        local function focus()
            if roster and roster.FocusCharacter then roster:FocusCharacter(payload.key or payload.character) end
            finish()
        end
        if C_Timer and C_Timer.After then C_Timer.After(0, focus) else focus() end
        return
    end

    -- TODO: add deeper destination filters as more panels expose public filter APIs.
    main:SetActivePanel(payload and payload.panel or "roster")
    showStatus("Opened the closest workflow for this dashboard item.", "textWarn")
    finish()
end

function DB:Create(parent)
    if self.frame then return end
    local Th = T()
    local P = Th.padding

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    frame:Hide()
    self.frame = frame
    Th.Bg(frame, Th.c.bg)

    local guildCard = CreateFrame("Frame", nil, frame)
    guildCard:SetPoint("TOPLEFT", frame, "TOPLEFT", P, -P)
    guildCard:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -P, -P)
    guildCard:SetHeight(52)
    Th.Bg(guildCard, Th.c.chrome, Th.c.border)
    local guildStripe = guildCard:CreateTexture(nil, "ARTWORK")
    guildStripe:SetPoint("TOPLEFT"); guildStripe:SetPoint("BOTTOMLEFT"); guildStripe:SetWidth(3)
    local accent = Th.c.accent
    guildStripe:SetColorTexture(accent[1], accent[2], accent[3], 0.9)

    self.guildNameFs = Th.Fs(guildCard, "subheader", "-", "textAccent")
    self.guildNameFs:SetPoint("LEFT", 14, 6)
    self.guildSubFs = Th.Fs(guildCard, "data", "No guild data", "textDimmed")
    self.guildSubFs:SetPoint("LEFT", 14, -12)
    self.guildSubFs:SetPoint("RIGHT", guildCard, "RIGHT", -360, -12)
    self.guildSubFs:SetJustifyH("LEFT")

    local activityBtn = GC.UI.Button.Create(guildCard, "Activity Log", "secondary", 94, Th.btnH)
    activityBtn:SetPoint("RIGHT", guildCard, "RIGHT", -248, 0)
    activityBtn:SetScript("OnClick", function() self:NavigateTo("activity_all") end)

    local complianceBtn = GC.UI.Button.Create(guildCard, "Compliance", "secondary", 100, Th.btnH)
    complianceBtn:SetPoint("RIGHT", guildCard, "RIGHT", -128, 0)
    complianceBtn:SetScript("OnClick", function() self:NavigateTo("compliance") end)
    self.complianceBtn = complianceBtn

    local exportBtn = GC.UI.Button.Create(guildCard, "Export", "secondary", 74, Th.btnH)
    exportBtn:SetPoint("RIGHT", guildCard, "RIGHT", -18, 0)
    exportBtn:SetScript("OnClick", function() self:ShowExport() end)

    local health = CreateFrame("Frame", nil, frame)
    health:SetPoint("TOPLEFT", guildCard, "BOTTOMLEFT", 0, -P)
    health:SetPoint("TOPRIGHT", guildCard, "BOTTOMRIGHT", 0, -P)
    health:SetHeight(86)
    Th.Bg(health, Th.c.panelAlt, Th.c.border)
    self.healthCard = health
    self.healthStripe = health:CreateTexture(nil, "ARTWORK")
    self.healthStripe:SetPoint("TOPLEFT"); self.healthStripe:SetPoint("BOTTOMLEFT"); self.healthStripe:SetWidth(3)
    self.healthTitle = Th.Fs(health, "subheader", "Guild Health", "textAccent")
    self.healthTitle:SetPoint("TOPLEFT", 14, -10)
    self.healthSummary = Th.Fs(health, "data", "", "textSecond")
    self.healthSummary:SetPoint("TOPLEFT", 14, -34)
    self.healthSummary:SetPoint("RIGHT", health, "RIGHT", -660, 0)
    self.healthSummary:SetJustifyH("LEFT")
    self.healthSummary:SetWordWrap(false)

    self.quickButtons = {}
    local quickDefs = {
        {label = "Invite Scan", target = "invite_scan", width = 86},
        {label = "Review Unknowns", target = "roster_unknown_main_alt", width = 114},
        {label = "Repair Alt Links", target = "relationship_repair", width = 108},
        {label = "Compliance", target = "compliance", width = 94},
        {label = "Ban Book", target = "ban_book", width = 82},
        {label = "Activity", target = "activity_all", width = 78},
    }
    local right = -12
    for i = #quickDefs, 1, -1 do
        local def = quickDefs[i]
        local btn = GC.UI.Button.Create(health, def.label, "secondary", def.width, Th.btnH)
        btn:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", right, 10)
        right = right - def.width - 6
        btn:SetScript("OnClick", function()
            DB:NavigateTo(def.target)
        end)
        self.quickButtons[#self.quickButtons + 1] = btn
    end

    self.metricCards = {}
    self.groupHeaders = {}
    local y = -(P + 52 + P + 86 + P)
    local cardH = 58
    for _, group in ipairs(METRIC_GROUPS) do
        self.groupHeaders[group.key] = sectionHeader(frame, group.title, y)
        y = y - 24
        for _, def in ipairs(group.items) do
            local card = createMetricCard(frame, def)
            self.metricCards[def.key] = card
        end
        y = y - cardH - SECTION_GAP
    end

    self.actionHeader = sectionHeader(frame, "Action Queue", y)
    y = y - 24

    local actionFrame = CreateFrame("Frame", nil, frame)
    actionFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", P, y)
    actionFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -P, P)
    Th.Bg(actionFrame, Th.c.panelAlt, Th.c.border)
    self.attentionFrame = actionFrame

    local colBar = CreateFrame("Frame", nil, actionFrame)
    colBar:SetPoint("TOPLEFT", actionFrame, "TOPLEFT", 0, 0)
    colBar:SetPoint("TOPRIGHT", actionFrame, "TOPRIGHT", 0, 0)
    colBar:SetHeight(Th.colBarH)
    Th.Bg(colBar, Th.c.chrome)
    self.actionColBar = colBar
    local function colHdr(text, x, width)
        local fs = Th.Fs(colBar, "tiny", text, "textDimmed")
        fs:SetPoint("LEFT", x, 0)
        fs:SetWidth(width)
    end
    colHdr("Character", 10, 170)
    colHdr("Issue", 188, 250)
    colHdr("Suggested Action", 450, 200)

    local listHost = CreateFrame("Frame", nil, actionFrame)
    listHost:SetPoint("TOPLEFT", actionFrame, "TOPLEFT", 0, -Th.colBarH)
    listHost:SetPoint("BOTTOMRIGHT", actionFrame, "BOTTOMRIGHT", 0, 0)
    self.actionListHost = listHost
    self.attentionList = GC.UI.List.Create(listHost, 28, buildActionQueueRow, function(item)
        if not item then return end
        DB:NavigateTo("roster_character", item)
    end, function(item)
        if GC.UI.CharacterContextMenu then
            GC.UI.CharacterContextMenu:Open({
                key = item and item.key,
                name = item and item.character,
                fullName = item and item.key,
                source = "Dashboard",
            })
        end
    end)
    self.attentionList:SetEmptyText("No action items found.")
    self.actionEmpty = self:CreateEmptyState(actionFrame, "No action items found.", "Roster, compliance, and moderation checks are clear.")

    local exportOverlay = CreateFrame("Frame", nil, frame)
    exportOverlay:SetPoint("TOPLEFT", frame, "TOPLEFT", P + 18, -(P + 96))
    exportOverlay:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -P - 18, -(P + 96))
    exportOverlay:SetHeight(250)
    if GC.UI.FrameLayering then
        GC.UI.FrameLayering:PreparePopupFrame(exportOverlay, GC.UI.MainFrame and GC.UI.MainFrame.frame, 35)
    else
        exportOverlay:SetFrameStrata("DIALOG")
    end
    Th.Bg(exportOverlay, Th.c.panel, Th.c.borderAccent)
    exportOverlay:Hide()
    self.exportOverlay = exportOverlay

    self.exportHdr = Th.Fs(exportOverlay, "subheader", "Export Guild Insights", "textAccent")
    self.exportHdr:SetPoint("TOPLEFT", 12, -10)

    local exportClose = GC.UI.Button.Create(exportOverlay, "Close", "secondary", 70, Th.btnH)
    exportClose:SetPoint("TOPRIGHT", -12, -8)
    exportClose:SetScript("OnClick", function() exportOverlay:Hide() end)

    local repairApply = GC.UI.Button.Create(exportOverlay, "Apply Safe Repairs", "primary", 138, Th.btnH)
    repairApply:SetPoint("RIGHT", exportClose, "LEFT", -8, 0)
    repairApply:Hide()
    repairApply:SetScript("OnClick", function()
        if not self._relationshipRepairPreview or not GC.Modules.RosterRelationships then return end
        local result = GC.Modules.RosterRelationships:ApplyRepairPreview(self._relationshipRepairPreview)
        self._relationshipRepairResult = result
        local nextPreview = GC.Modules.RosterRelationships:BuildRepairPreview()
        self._relationshipRepairPreview = nextPreview
        if self.exportEdit then
            self.exportEdit:SetText(buildRepairPreviewText(nextPreview, result))
            self.exportEdit:HighlightText(0, 0)
            self.exportEdit:SetCursorPosition(0)
        end
        repairApply:SetEnabled((nextPreview.summary and nextPreview.summary.safeActions or #(nextPreview.actions or {})) > 0)
        showStatus(string.format("Safe repairs applied: %d. Manual issues remaining: %d.", result.applied or 0, nextPreview.summary and nextPreview.summary.manualReview or 0), (result.applied or 0) > 0 and "textSuccess" or "textWarn")
        if GC.UI.RosterPanel and GC.UI.RosterPanel.Refresh then GC.UI.RosterPanel:Refresh() end
        if GC.UI.PlayerPanel and GC.UI.PlayerPanel.Refresh then GC.UI.PlayerPanel:Refresh() end
        if GC.UI.Dashboard and GC.UI.Dashboard.Refresh then GC.UI.Dashboard:Refresh() end
    end)
    self.repairApplyBtn = repairApply

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
    exportEdit:SetScript("OnEscapePressed", function() exportOverlay:Hide() end)
    exportEdit:SetScript("OnTextChanged", function(selfEdit)
        local height
        if selfEdit.GetStringHeight then
            height = selfEdit:GetStringHeight()
        else
            local text = selfEdit:GetText() or ""
            local lines = 1
            for _ in text:gmatch("\n") do
                lines = lines + 1
            end
            height = lines * 14
        end
        selfEdit:SetHeight(math.max(210, height + 24))
    end)
    exportScroll:SetScrollChild(exportEdit)
    self.exportEdit = exportEdit
end

local function valueForMetric(key, stats, insights)
    if stats[key] ~= nil then return stats[key] end
    if insights[key] ~= nil then return insights[key] end
    return 0
end

function DB:Refresh()
    if not self.frame then return end
    local Th = T()
    local P = Th.padding
    local settings = dashboardSettings()

    local stats = GS():GetStats()
    local insights = GS():GetGuildInsights()
    local attentionRows = GS():GetNeedsAttention()
    local metrics = self:CollectMetrics(stats, insights)
    local noScan = not stats.lastScanAt

    local guildName = GetGuildInfo and GetGuildInfo("player") or nil
    self.guildNameFs:SetText(guildName or "No Guild")
    local allSettings = GC.Services.DataStore:GetSettings() or {}
    local hasCompliance = GC.Services and GC.Services.Compliance ~= nil
    local complianceEnabled = hasCompliance and (
        allSettings.complianceCheckPublicNote ~= false
        or allSettings.complianceCheckOfficerNote ~= false
        or allSettings.complianceCheckJoinDate ~= false
        or allSettings.complianceCheckDiscordVerification ~= false
        or allSettings.complianceCheckRank ~= false
        or allSettings.complianceCheckMainAlt ~= false
    )
    local readiness = {
        stats.lastScanAt and ("Last scan: " .. date("%Y-%m-%d %H:%M", stats.lastScanAt)) or "No roster scan data yet",
        allSettings.enableRosterModule ~= false and "Tracking enabled" or "Tracking disabled",
        not hasCompliance and "Compliance checks unavailable" or complianceEnabled and "Compliance checks enabled" or "Compliance checks disabled",
        allSettings.enableSyncModule and "Sync enabled" or "Sync disabled",
    }
    if allSettings.debugMode then readiness[#readiness + 1] = "Debug mode active" end
    self.guildSubFs:SetText(table.concat(readiness, "   |   "))

    local health = self:BuildHealthSummary(metrics)
    local healthColorKey = health.state == "critical" and "danger" or health.state == "attention" and "warning" or "healthy"
    local hc = colorForState(healthColorKey)
    self.healthStripe:SetColorTexture(hc[1], hc[2], hc[3], 0.9)
    self.healthTitle:SetText("Guild Health: " .. health.label)
    self.healthTitle:SetTextColor(hc[1], hc[2], hc[3], hc[4] or 1)
    self.healthSummary:SetText(noScan and "No roster scan data yet. Open Roster or Invite to scan." or table.concat(health.lines, "   |   "))

    local healthH = settings.showHealth ~= false and (settings.compactMode and 64 or 86) or 0
    local gap = settings.compactMode and 6 or P
    if self.healthCard then
        self.healthCard:ClearAllPoints()
        self.healthCard:SetPoint("TOPLEFT", self.frame, "TOPLEFT", P, -(P + 52 + P))
        self.healthCard:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -P, -(P + 52 + P))
        self.healthCard:SetHeight(healthH)
    end

    local y = -(P + 52 + P + healthH + gap)
    local cardH = settings.compactMode and 48 or 58
    local sectionOffset = settings.compactMode and 20 or 24
    local groupGap = settings.compactMode and 6 or SECTION_GAP
    for _, group in ipairs(METRIC_GROUPS) do
        if self.groupHeaders and self.groupHeaders[group.key] then
            self.groupHeaders[group.key]:ClearAllPoints()
            self.groupHeaders[group.key]:SetPoint("TOPLEFT", self.frame, "TOPLEFT", P, y)
        end
        y = y - sectionOffset
        local count = #group.items
        local visible = {}
        for _, def in ipairs(group.items) do
            if not (settings.hiddenCards and settings.hiddenCards[def.key]) then
                visible[#visible + 1] = def
            end
        end
        count = #visible
        local totalW = (self.frame:GetWidth() > 0 and self.frame:GetWidth() or 1100) - (P * 2)
        local cardW = count > 0 and math.floor((totalW - gap * (count - 1)) / count) or totalW
        for i, def in ipairs(visible) do
            local card = self.metricCards[def.key]
            if card then
                card:ClearAllPoints()
                card:SetPoint("TOPLEFT", self.frame, "TOPLEFT", P + (i - 1) * (cardW + gap), y)
                card:SetSize(cardW, cardH)
                local value = valueForMetric(def.key, metrics, metrics)
                card._value:SetText(tostring(value or 0))
                self:SetMetricState(card, self:GetMetricState(def.key, value))
                if card._trend then
                    local trend = self:GetTrend(def.key, value)
                    card._trend:SetText(trend and trend.label or "")
                    local trendColor = trend and trend.direction == "up" and Th.c.statusActive
                        or trend and trend.direction == "down" and Th.c.textWarn
                        or Th.c.textDimmed
                    card._trend:SetTextColor(trendColor[1], trendColor[2], trendColor[3], trendColor[4] or 1)
                end
            end
        end
        y = y - cardH - groupGap
    end

    if self.actionHeader then
        self.actionHeader:ClearAllPoints()
        self.actionHeader:SetPoint("TOPLEFT", self.frame, "TOPLEFT", P, y)
    end
    y = y - sectionOffset
    if self.attentionFrame then
        self.attentionFrame:ClearAllPoints()
        self.attentionFrame:SetPoint("TOPLEFT", self.frame, "TOPLEFT", P, y)
        self.attentionFrame:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -P, P)
    end

    for _, row in ipairs(attentionRows or {}) do
        if row.action == "Ready for Purge" then
            row.state = "danger"
            row.target = "purge_ready"
        elseif row.issue and row.action == "Review Main / Alt Links" then
            row.state = "danger"
            row.target = "roster_relationship_issues"
        elseif row.issue and row.issue:find("Discord", 1, true) then
            row.state = "warning"
            row.target = "roster_missing_discord"
        elseif row.issue and row.issue:find("Unknown", 1, true) then
            row.state = "warning"
            row.target = "roster_character"
        else
            row.state = "neutral"
            row.target = "roster_character"
        end
    end

    if self.attentionList then
        local hasRows = attentionRows and #attentionRows > 0
        if self.actionColBar then self.actionColBar:SetShown(hasRows) end
        if self.actionListHost then self.actionListHost:SetShown(hasRows) end
        if self.actionEmpty then
            if hasRows then
                self.actionEmpty:Hide()
            else
                self.actionEmpty:SetMessage(
                    noScan and "No roster scan data yet." or "No action items found.",
                    noScan and "Open Roster or Invite to scan when needed." or "Roster, compliance, and moderation checks are clear."
                )
                self.actionEmpty:Show()
                debugLog("empty state rendered", noScan and "no scan" or "clear")
            end
        end
        self.attentionList:Refresh(hasRows and attentionRows or {})
        self.attentionList:SetEmptyText(noScan and "No roster scan yet. Open Roster or Invite to scan when needed." or "No urgent action items. Guild looks tidy.")
    end

    if GC.UI.MainFrame and GC.UI.MainFrame.promptTitle then
        local count = countPendingPrompts()
        GC.UI.MainFrame.promptTitle:SetText(count > 1 and ("Pending Classification (" .. tostring(count) .. ")") or "Pending Classification")
    end

    self:ApplyDashboardSettings(settings)
    if noScan then
        debugLog("snapshot skipped", "no scan data")
    else
        self:SaveSnapshot(metrics)
    end
end

function DB:GetObjectStats()
    local cards = 0
    for _ in pairs(self.metricCards or {}) do cards = cards + 1 end
    return {
        metricCards = cards,
        quickButtons = #(self.quickButtons or {}),
    }
end

function DB:ShowExport()
    if not self.exportOverlay or not self.exportEdit then return end
    if self.repairApplyBtn then self.repairApplyBtn:Hide() end
    self._relationshipRepairPreview = nil
    if self.exportHdr then self.exportHdr:SetText("Export Guild Insights") end
    self.exportEdit:SetText(GS():GetNeedsAttentionExportText())
    self.exportEdit:HighlightText()
    self.exportEdit:SetFocus()
    self.exportOverlay:Show()
end

function DB:ShowRelationshipRepairPreview()
    if not self.exportOverlay or not self.exportEdit then return end
    local service = GC.Modules and GC.Modules.RosterRelationships
    if not service or not service.BuildRepairPreview then
        showStatus("Relationship repair service is unavailable.", "textDanger")
        return
    end
    local preview = service:BuildRepairPreview()
    self._relationshipRepairPreview = preview
    self._relationshipRepairResult = nil
    if self.exportHdr then self.exportHdr:SetText("Safe Alt Link Repair Preview") end
    self.exportEdit:SetText(buildRepairPreviewText(preview))
    self.exportEdit:HighlightText(0, 0)
    self.exportEdit:SetCursorPosition(0)
    self.exportEdit:SetFocus()
    if self.repairApplyBtn then
        self.repairApplyBtn:Show()
        self.repairApplyBtn:SetEnabled((preview.summary and preview.summary.safeActions or #(preview.actions or {})) > 0)
    end
    self.exportOverlay:Show()
    local safeCount = preview.summary and preview.summary.safeActions or #(preview.actions or {})
    local manualCount = preview.summary and preview.summary.manualReview or #(preview.unsafe or {})
    if safeCount == 0 and manualCount == 0 then
        showStatus("No roster relationship issues found.", "textSuccess")
    elseif safeCount == 0 then
        showStatus("No safe automatic repairs are available. Manual review is required.", "textWarn")
    else
        showStatus("Safe alt link repair preview is ready.", "textWarn")
    end
end

function DB:RunCompliance()
    local service = GC.Services and GC.Services.Compliance
    if not service or not service.Run then
        GC.UI.MainFrame:SetStatus("Compliance service is unavailable.", "textDanger")
        return
    end
    if self.repairApplyBtn then self.repairApplyBtn:Hide() end
    self._relationshipRepairPreview = nil
    local result = service:Run()
    if self.exportHdr then self.exportHdr:SetText("Compliance Check Results") end
    if self.exportEdit then
        self.exportEdit:SetText(result.text or "")
        self.exportEdit:HighlightText()
        self.exportEdit:SetFocus()
    end
    if self.exportOverlay then self.exportOverlay:Show() end
    GC.UI.MainFrame:SetStatus("Compliance check complete: " .. tostring(result.count or 0) .. " finding(s).", (result.count or 0) > 0 and "textWarn" or "textSuccess")
end

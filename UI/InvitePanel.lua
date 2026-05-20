-- UI/InvitePanel.lua
-- Phase 5: Invite panel UI. Uses GC.UI.List, GC.UI.Button, GC.UI.Panel,
-- and GC.UI.Theme. No AceGUI. No standalone frames.
--
-- Layout:
--   Header + subtitle
--   Control row: [Scan] [Select All] [Clear Selection] [Refresh Status] [Invite Selected] [Invite Next]
--   Status bar:  scan status | queue status | permission note
--   Column header bar
--   Candidate list (virtual, scrollable)
--   Permission/module-disabled overlay when needed
local addonName, ns = ...
local GC = ns.GuildCore

GC.UI.InvitePanel = {}
local IP = GC.UI.InvitePanel

local function T()  return GC.UI.Theme end
local function IQ() return GC.Services.InviteQueue  end
local function IS() return GC.Services.InviteScanner end
local function SVC() return GC.Services.Invite end

local function rootSettings()
    return GC.DB and GC.DB.GetSettings and GC.DB:GetSettings() or {}
end

local function applyInviteHotkeys()
    if not SetBindingClick then return end
    local settings = rootSettings()
    local inviteKey = settings.inviteHotkey or "CTRL-SHIFT-I"
    local scanKey = settings.inviteScanHotkey or "CTRL-SHIFT-S"
    local inviteCommand = "CLICK GuildCoreInviteNowHotkeyButton:LeftButton"
    local scanCommand = "CLICK GuildCoreInviteScanHotkeyButton:LeftButton"

    if GetBindingKey and SetBinding then
        local keys = { GetBindingKey(inviteCommand) }
        for _, key in ipairs(keys) do
            SetBinding(key)
        end
        keys = { GetBindingKey(scanCommand) }
        for _, key in ipairs(keys) do
            SetBinding(key)
        end
    end

    if inviteKey and inviteKey ~= "" then
        SetBindingClick(inviteKey, "GuildCoreInviteNowHotkeyButton", "LeftButton")
    end
    if scanKey and scanKey ~= "" then
        SetBindingClick(scanKey, "GuildCoreInviteScanHotkeyButton", "LeftButton")
    end
    if SaveBindings and GetCurrentBindingSet then
        SaveBindings(GetCurrentBindingSet())
    end
end

GC.UI.ApplyInviteHotkeys = applyInviteHotkeys

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$") or ""
end

local function hasGuild(candidate)
    return trim(candidate and candidate.guild) ~= ""
end

local function reasonsText(candidate)
    if not candidate then return "" end
    if candidate.eligible and not hasGuild(candidate) then return "eligible" end
    local labels = {}
    for _, reason in ipairs(candidate.ineligibleReasons or {}) do
        if reason == "level_too_low" or reason == "level_too_high" then
            reason = "level_out_of_range"
        end
        labels[reason] = true
    end
    local ordered = { "banned", "has_guild", "recently_invited", "recently_declined", "ignored", "wrong_realm", "level_out_of_range" }
    local out = {}
    for _, reason in ipairs(ordered) do
        if labels[reason] then out[#out + 1] = reason end
    end
    for reason in pairs(labels) do
        local known = false
        for _, expected in ipairs(ordered) do
            if reason == expected then known = true; break end
        end
        if not known then out[#out + 1] = reason end
    end
    return table.concat(out, ",")
end

local function addReason(candidate, reason)
    candidate.ineligibleReasons = candidate.ineligibleReasons or {}
    for _, existing in ipairs(candidate.ineligibleReasons) do
        if existing == reason then return end
    end
    candidate.ineligibleReasons[#candidate.ineligibleReasons + 1] = reason
end

local function hasReason(candidate, reason)
    for _, existing in ipairs((candidate and candidate.ineligibleReasons) or {}) do
        if existing == reason then return true end
    end
    return false
end

local function isLockedStatus(status)
    return status == "queued"
        or status == "sending"
        or status == "pending"
        or status == "failed"
        or status == "failed_api"
        or status == "skipped"
        or status == "sent"
        or status == "invite_sent"
        or status == "declined"
        or status == "already_in_guild"
        or status == "already_invited"
        or status == "offline"
        or status == "throttled"
        or status == "unknown"
        or status == "unknown_timeout"
        or status == "no_response"
        or status == "dry_run_complete"
end

local function isActionableCandidate(candidate)
    return candidate
        and candidate.eligible == true
        and not hasGuild(candidate)
        and not isLockedStatus(candidate.status)
end

local function candidateStorageKey(candidate)
    local name = candidate and (candidate.key or candidate.fullName or candidate.name)
    if not name or name == "" then return nil end
    if GC.API and GC.API.NormalizePlayerName then
        return GC.API.NormalizePlayerName(name)
    end
    return tostring(name)
end

local REALM_OPTIONS = {
    "Hellscream",
    "Gorefiend",
    "Spinebreaker",
    "Zangarmarsh",
    "Wildhammer",
    "Eredar",
}

local function maxPlayerLevel()
    return (GetMaxPlayerLevel and tonumber(GetMaxPlayerLevel())) or 90
end

local function mainRealmOptions()
    local Realm = GC.Modules.Invite and GC.Modules.Invite.Realm
    if Realm and Realm.GetMainRealmOptions then
        return Realm.GetMainRealmOptions()
    end
    local out = {}
    for _, realm in ipairs(REALM_OPTIONS) do
        out[#out + 1] = realm
    end
    return out
end

local function makeRealmDropdown(parent, width, onChange)
    local Th = T()
    local options = mainRealmOptions()
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(width or 150, Th.btnH or 24)
    Th.Bg(btn, Th.c.panelAlt, Th.c.borderStrong)

    local text = Th.Fs(btn, "body", "", "textPrimary")
    text:SetPoint("LEFT", 8, 0)
    text:SetPoint("RIGHT", btn, "RIGHT", -24, 0)
    text:SetJustifyH("LEFT")

    local arrow = Th.Fs(btn, "small", "v", "textAccent")
    arrow:SetPoint("RIGHT", -8, 0)

    local itemH = Th.btnH or 24
    local menu = CreateFrame("Frame", nil, UIParent)
    menu:SetSize(width or 150, #options * itemH)
    menu:SetFrameStrata("TOOLTIP")
    menu:SetFrameLevel(210)
    Th.Bg(menu, Th.c.panel, Th.c.borderAccent)
    menu:Hide()

    local selected
    local buttons = {}

    local function labelFor(value)
        return value or "Auto"
    end

    local function refreshOptions()
        for _, optBtn in ipairs(buttons) do
            local c = optBtn._key == selected and T().c.navActive or T().c.panel
            optBtn._bg:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
        end
    end

    local function repositionMenu()
        local scale = UIParent:GetEffectiveScale() or 1
        local bScale = btn:GetEffectiveScale() or 1
        local bx, by = btn:GetLeft(), btn:GetBottom()
        if not bx then return end
        bx = bx * bScale / scale
        by = by * bScale / scale
        menu:ClearAllPoints()
        menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", bx, by - 2)
        menu:SetWidth(btn:GetWidth() * bScale / scale)
    end

    for index, realm in ipairs(options) do
        local optBtn = CreateFrame("Button", nil, menu)
        optBtn:SetHeight(itemH)
        optBtn:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, -((index - 1) * itemH))
        optBtn:SetPoint("TOPRIGHT", menu, "TOPRIGHT", 0, -((index - 1) * itemH))
        optBtn._key = realm

        local bg = optBtn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        local pc = Th.c.panel
        bg:SetColorTexture(pc[1], pc[2], pc[3], pc[4] or 1)
        optBtn._bg = bg

        local fs = Th.Fs(optBtn, "body", realm, "textSecond")
        fs:SetPoint("LEFT", 8, 0)

        optBtn:SetScript("OnEnter", function(self)
            local hc = T().c.navHover
            self._bg:SetColorTexture(hc[1], hc[2], hc[3], hc[4] or 1)
        end)
        optBtn:SetScript("OnLeave", refreshOptions)
        optBtn:SetScript("OnClick", function()
            selected = realm
            text:SetText(labelFor(selected))
            menu:Hide()
            arrow:SetText("v")
            refreshOptions()
            if onChange then onChange(selected) end
        end)
        buttons[#buttons + 1] = optBtn
    end

    btn:SetScript("OnClick", function()
        if menu:IsShown() then
            menu:Hide()
            arrow:SetText("v")
        else
            repositionMenu()
            refreshOptions()
            menu:Show()
            arrow:SetText("^")
        end
    end)
    btn:SetScript("OnHide", function()
        menu:Hide()
        arrow:SetText("v")
    end)

    function btn:SetSelectedRealm(value)
        selected = value
        text:SetText(labelFor(value))
        refreshOptions()
    end

    return btn
end

-- ── Row builder ────────────────────────────────────────────────────────────

local COLS = {
    {label = "",           x = 6,   w = 24},
    {label = "Name",       x = 34,  w = 140},
    {label = "Lvl",        x = 178, w = 34},
    {label = "Class",      x = 216, w = 100},
    {label = "Zone",       x = 320, w = 140},
    {label = "Guild",      x = 464, w = 120},
    {label = "Status",     x = 588, w = 150},
}

local function buildCandidateRow(row, item)
    local Th = T()
    if not row._built then
        local check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        check:SetPoint("LEFT", COLS[1].x, 0)
        check:SetSize(22, 22)

        local nameFs = Th.Fs(row, "small", "", "textPrimary")
        nameFs:SetPoint("LEFT", COLS[2].x, 0); nameFs:SetWidth(COLS[2].w)

        local lvlFs = Th.Fs(row, "data", "", "textSecond")
        lvlFs:SetPoint("LEFT", COLS[3].x, 0); lvlFs:SetWidth(COLS[3].w)

        local classFs = Th.Fs(row, "small", "", "textSecond")
        classFs:SetPoint("LEFT", COLS[4].x, 0); classFs:SetWidth(COLS[4].w)

        local zoneFs = Th.Fs(row, "small", "", "textDimmed")
        zoneFs:SetPoint("LEFT", COLS[5].x, 0); zoneFs:SetWidth(COLS[5].w)

        local guildFs = Th.Fs(row, "small", "", "textDimmed")
        guildFs:SetPoint("LEFT", COLS[6].x, 0); guildFs:SetWidth(COLS[6].w)

        local statusFs = Th.Fs(row, "tiny", "", "textDimmed")
        statusFs:SetPoint("LEFT", COLS[7].x, 0); statusFs:SetWidth(COLS[7].w)

        row._check    = check
        row._nameFs   = nameFs
        row._lvlFs    = lvlFs
        row._classFs  = classFs
        row._zoneFs   = zoneFs
        row._guildFs  = guildFs
        row._statusFs = statusFs
        row._built    = true
    end

    local Th = T()
    if hasGuild(item) then
        item.eligible = false
        item.selected = false
        item.isGuildless = false
        addReason(item, "has_guild")
    end
    local eligible = isActionableCandidate(item)
    if not eligible then
        item.selected = false
    elseif item.selected == nil then
        item.selected = true
    end

    if row._check then
        row._check:SetChecked(item.selected == true)
        row._check:SetEnabled(eligible)
        row._check:SetScript("OnClick", function(self)
            if not eligible then
                self:SetChecked(false)
                item.selected = false
                return
            end
            item.selected = self:GetChecked() == true
        end)
    end

    local nameColor  = eligible and "textPrimary" or "textDimmed"
    local nc = Th.c[nameColor] or Th.c.textPrimary
    row._nameFs:SetText(item.fullName or item.name or item.key or "?")
    row._nameFs:SetTextColor(nc[1], nc[2], nc[3], 1)
    row._lvlFs:SetText(tostring(item.level or "?"))
    row._classFs:SetText(tostring(item.className or ""))
    row._zoneFs:SetText(tostring(item.zone or ""))
    row._guildFs:SetText(item.isGuildless and "" or tostring(item.guild or ""))

    if item.status == "queued" or item.status == "sending" or item.status == "pending" or item.status == "failed"
        or item.status == "failed_api" or item.status == "no_response"
        or item.status == "skipped" or item.status == "sent" or item.status == "invite_sent"
        or item.status == "declined" or item.status == "already_in_guild" or item.status == "already_invited"
        or item.status == "offline" or item.status == "throttled" or item.status == "unknown"
        or item.status == "unknown_timeout" or item.status == "dry_run_complete" then
        local isBad = item.status == "failed" or item.status == "failed_api" or item.status == "declined" or item.status == "already_in_guild"
            or item.status == "already_invited" or item.status == "offline" or item.status == "throttled"
            or item.status == "unknown" or item.status == "unknown_timeout"
        local wc = isBad and (Th.c.textDanger or Th.c.textWarn) or (Th.c.textWarn or Th.c.textDimmed)
        row._statusFs:SetText(item.status == "invite_sent" and "sent" or tostring(item.status))
        row._statusFs:SetTextColor(wc[1], wc[2], wc[3], 1)
    elseif eligible then
        local ac = Th.c.statusActive or Th.c.textAccent
        row._statusFs:SetText("eligible")
        row._statusFs:SetTextColor(ac[1], ac[2], ac[3], 1)
    elseif item.ineligibleReasons and #item.ineligibleReasons > 0 then
        local wc = Th.c.textWarn or Th.c.textDimmed
        row._statusFs:SetText(reasonsText(item))
        row._statusFs:SetTextColor(wc[1], wc[2], wc[3], 1)
    else
        row._statusFs:SetText("")
    end
end

-- ── Create ─────────────────────────────────────────────────────────────────

function IP:Create(parent)
    if self.frame then return end
    local Th = T()
    local P       = Th.padding  or 10
    local btnH    = Th.btnH     or 24
    local inputH  = Th.inputH   or 22
    local colBarH = Th.colBarH  or 20
    local rowGap  = 10

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    frame:Hide()
    self.frame = frame
    Th.Bg(frame, Th.c.bg)

    -- ── Page header ──────────────────────────────────────────────────────────
    local hdr = Th.Fs(frame, "subheader", "Invite", "textAccent")
    hdr:SetPoint("TOPLEFT", frame, "TOPLEFT", P, -P)
    hdr:SetHeight(20)
    self._hdr = hdr

    local sub = Th.Fs(frame, "small", "WHO-based candidate discovery. Invites require guild officer permissions.", "textDimmed")
    sub:SetPoint("LEFT",      hdr,   "RIGHT",       10,  0)
    sub:SetPoint("TOPRIGHT",  frame, "TOPRIGHT",    -P, -P)
    sub:SetHeight(20)

    -- ── Module-disabled notice (hidden by default) ───────────────────────────
    local noticeFrame = CreateFrame("Frame", nil, frame)
    noticeFrame:SetPoint("TOPLEFT",  hdr,   "BOTTOMLEFT",  0,  -rowGap)
    noticeFrame:SetPoint("TOPRIGHT", frame, "TOPRIGHT",   -P,  0)
    noticeFrame:SetHeight(24)
    Th.Bg(noticeFrame, Th.c.panelAlt or Th.c.chrome, Th.c.borderAccent or Th.c.border)
    noticeFrame:Hide()
    local noticeFs = Th.Fs(noticeFrame, "small", "", "textWarn")
    noticeFs:SetPoint("LEFT",  noticeFrame, "LEFT",  8, 0)
    noticeFs:SetPoint("RIGHT", noticeFrame, "RIGHT", -8, 0)
    noticeFs:SetJustifyH("LEFT")
    self.noticeFrame = noticeFrame
    self.noticeFs    = noticeFs

    -- ── Control row ──────────────────────────────────────────────────────────
    -- Anchored below header (notice is hidden by default; Refresh shows it)
    local ctrlRow = CreateFrame("Frame", nil, frame)
    ctrlRow:SetPoint("TOPLEFT",  hdr,   "BOTTOMLEFT",  0,  -rowGap)
    ctrlRow:SetPoint("TOPRIGHT", frame, "TOPRIGHT",   -P,  0)
    ctrlRow:SetHeight(btnH)
    self._ctrlRow = ctrlRow

    local scanBtn = GC.UI.Button.Create(ctrlRow, "Scan", "primary", 82, btnH)
    scanBtn:SetPoint("LEFT", ctrlRow, "LEFT", 0, 0)
    scanBtn:SetTooltip("Scan", "Runs one WHO query per click.")
    self.scanBtn = scanBtn

    -- stopScanBtn replaces Scan button during active scan (hidden by default)
    local stopScanBtn = GC.UI.Button.Create(ctrlRow, "Stop", "secondary", 52, btnH)
    stopScanBtn:SetPoint("LEFT", scanBtn, "RIGHT", 6, 0)
    stopScanBtn:SetTooltip("Stop Scan", "Cancels the active WHO scan.")
    self.stopScanBtn = stopScanBtn

    -- Queue control buttons — chained left-to-right after stopScanBtn
    local queueSelBtn = GC.UI.Button.Create(ctrlRow, "Select All", "secondary", 86, btnH)
    queueSelBtn:SetPoint("LEFT", stopScanBtn, "RIGHT", 10, 0)
    queueSelBtn:SetTooltip("Select All", "Selects all currently visible eligible invite candidates.")
    self.queueSelBtn = queueSelBtn

    local clearQueueBtn = GC.UI.Button.Create(ctrlRow, "Clear Selection", "secondary", 108, btnH)
    clearQueueBtn:SetPoint("LEFT", queueSelBtn, "RIGHT", 6, 0)
    clearQueueBtn:SetTooltip("Clear Selection", "Clears the current candidate selection.")
    self.clearQueueBtn = clearQueueBtn

    local refreshStatusBtn = GC.UI.Button.Create(ctrlRow, "Refresh Status", "secondary", 108, btnH)
    refreshStatusBtn:SetPoint("LEFT", clearQueueBtn, "RIGHT", 6, 0)
    refreshStatusBtn:SetTooltip("Refresh Status", "Updates candidate statuses from recent invite and decline history.")
    self.refreshStatusBtn = refreshStatusBtn

    local inviteSelectedBtn = GC.UI.Button.Create(ctrlRow, "Invite Selected", "secondary", 116, btnH)
    inviteSelectedBtn:SetPoint("LEFT", refreshStatusBtn, "RIGHT", 6, 0)
    inviteSelectedBtn:SetTooltip("Invite Selected", "Feature in progress. Batch invites are under development.")
    self.inviteSelectedBtn = inviteSelectedBtn

    local inviteNowBtn = GC.UI.Button.Create(ctrlRow, "INVITE NEXT", "success", 148, btnH + 8)
    inviteNowBtn:SetPoint("RIGHT", ctrlRow, "RIGHT", 0, 0)
    inviteNowBtn:SetTooltip("Invite Next", "Immediately sends one selected eligible guild invite. Hotkey can be changed in Settings.")
    self.inviteNowBtn = inviteNowBtn

    -- Overflow queue buttons (shown only when queue is running)
    local queueAllBtn = GC.UI.Button.Create(ctrlRow, "Queue Eligible", "secondary", 106, btnH)
    queueAllBtn:SetPoint("LEFT", queueSelBtn, "RIGHT", 6, 0)
    queueAllBtn:SetTooltip("Queue All Eligible", "Adds all eligible candidates to the invite queue.")
    self.queueAllBtn = queueAllBtn

    local startQueueBtn = GC.UI.Button.Create(ctrlRow, "Start Queue", "primary", 88, btnH)
    startQueueBtn:SetPoint("LEFT", queueAllBtn, "RIGHT", 10, 0)
    startQueueBtn:SetTooltip("Start Queue", "Begins dry-run processing.")
    self.startQueueBtn = startQueueBtn

    local pauseBtn = GC.UI.Button.Create(ctrlRow, "Pause", "secondary", 58, btnH)
    pauseBtn:SetPoint("LEFT", startQueueBtn, "RIGHT", 6, 0)
    pauseBtn:SetTooltip("Pause Queue", "Pauses the invite queue.")
    self.pauseBtn = pauseBtn

    local cancelQueueBtn = GC.UI.Button.Create(ctrlRow, "Cancel Queue", "danger", 94, btnH)
    cancelQueueBtn:SetPoint("LEFT", pauseBtn, "RIGHT", 6, 0)
    cancelQueueBtn:SetTooltip("Cancel Queue", "Stops and clears the invite queue.")
    self.cancelQueueBtn = cancelQueueBtn

    stopScanBtn:Hide()
    queueAllBtn:Hide()
    startQueueBtn:Hide()
    pauseBtn:Hide()
    cancelQueueBtn:Hide()

    local bottomControls = CreateFrame("Frame", nil, frame)
    bottomControls:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", P, P)
    bottomControls:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -P, P)
    bottomControls:SetHeight(btnH)
    self._bottomControls = bottomControls

    local dryRunBtn = GC.UI.Button.Create(bottomControls, "Dry Run: Off", "secondary", 100, btnH)
    dryRunBtn:SetPoint("LEFT", bottomControls, "LEFT", 0, 0)
    dryRunBtn:SetTooltip("Dry Run", "When ON, Invite Selected simulates invites only.")
    self.dryRunBtn = dryRunBtn

    local debugLabel = Th.Fs(bottomControls, "tiny", "Debug Logging", "textDimmed")
    debugLabel:SetPoint("LEFT", dryRunBtn, "RIGHT", 16, 0)
    debugLabel:SetWidth(86)
    debugLabel:SetHeight(btnH)
    debugLabel:SetJustifyV("MIDDLE")

    local debugBtn = GC.UI.Button.Create(bottomControls, "Off", "secondary", 52, btnH)
    debugBtn:SetPoint("LEFT", debugLabel, "RIGHT", 4, 0)
    debugBtn:SetTooltip("Debug Logging", "Shows detailed Invite scan, realm, filter, and queue logs.")
    self.debugBtn = debugBtn

    local showGuildedBtn = GC.UI.Button.Create(bottomControls, "Guilded: Off", "secondary", 92, btnH)
    showGuildedBtn:SetPoint("LEFT", debugBtn, "RIGHT", 10, 0)
    showGuildedBtn:SetTooltip("Show Guilded", "Shows guilded WHO results for review only.")
    self.showGuildedBtn = showGuildedBtn

    local showRecentBtn = GC.UI.Button.Create(bottomControls, "Invited: Off", "secondary", 92, btnH)
    showRecentBtn:SetPoint("LEFT", showGuildedBtn, "RIGHT", 6, 0)
    showRecentBtn:SetTooltip("Show Recently Invited", "Shows recently invited candidates for review only.")
    self.showRecentBtn = showRecentBtn

    local showDeclinedBtn = GC.UI.Button.Create(bottomControls, "Declined: Off", "secondary", 100, btnH)
    showDeclinedBtn:SetPoint("LEFT", showRecentBtn, "RIGHT", 6, 0)
    showDeclinedBtn:SetTooltip("Show Recently Declined", "Shows recently declined candidates for review only.")
    self.showDeclinedBtn = showDeclinedBtn

    -- ── Realm selector row ────────────────────────────────────────────────────
    -- Two sub-lines: [line1] controls  [line2] realm info text
    local line1H = btnH
    local line2H = 18
    local realmRow = CreateFrame("Frame", nil, frame)
    realmRow:SetPoint("TOPLEFT",  ctrlRow, "BOTTOMLEFT",  0, -rowGap)
    realmRow:SetPoint("TOPRIGHT", frame,   "TOPRIGHT",   -P, 0)
    realmRow:SetHeight(line1H + 6 + line2H)
    self._realmRow = realmRow

    -- Line 1: Guild Realm dropdown + toggle buttons, all vertically centred at top
    local realmLabel = Th.Fs(realmRow, "tiny", "Guild Realm", "textDimmed")
    realmLabel:SetPoint("TOPLEFT", realmRow, "TOPLEFT", 0, 0)
    realmLabel:SetHeight(line1H)
    realmLabel:SetWidth(74)
    realmLabel:SetJustifyV("MIDDLE")

    local realmSelect = makeRealmDropdown(realmRow, 150, function(realm)
        local svc = SVC()
        local settings = svc and svc:GetSettings()
        if settings then
            settings.guildRealmOverride = realm
        end
        local scanner = IS()
        if scanner and scanner.ClearCandidates then
            scanner:ClearCandidates()
        end
        local queue = IQ()
        if queue and queue.Clear then
            queue:Clear()
        end
        IP:_refreshRealmDisplay()
        IP:UpdateStatus()
    end)
    realmSelect:SetPoint("TOPLEFT", realmLabel, "TOPRIGHT", 6, 0)
    self.realmSelect = realmSelect

    -- Line 2: realm info text, sits 6px below line 1
    local realmInfoFs = Th.Fs(realmRow, "small", "", "textSecond")
    realmInfoFs:SetPoint("TOPLEFT",  realmRow, "TOPLEFT",  0, -(line1H + 6))
    realmInfoFs:SetPoint("TOPRIGHT", realmRow, "TOPRIGHT", -8, -(line1H + 6))
    realmInfoFs:SetHeight(line2H)
    realmInfoFs:SetJustifyH("LEFT")
    self.realmInfoFs = realmInfoFs

    -- ── Filter strip ─────────────────────────────────────────────────────────
    local filterRow = CreateFrame("Frame", nil, frame)
    filterRow:SetPoint("TOPLEFT",  realmRow, "BOTTOMLEFT",  0, -rowGap)
    filterRow:SetPoint("TOPRIGHT", frame,   "TOPRIGHT",   -P, 0)
    filterRow:SetHeight(inputH)
    self._filterRow = filterRow

    local lvlLabel = Th.Fs(filterRow, "tiny", "Level", "textDimmed")
    lvlLabel:SetPoint("LEFT", filterRow, "LEFT", 0, 0)
    lvlLabel:SetWidth(30)

    local lvlMinBox = GC.UI.Panel.Input(filterRow, 38, inputH)
    lvlMinBox:SetPoint("LEFT", lvlLabel, "RIGHT", 4, 0)
    lvlMinBox:SetMaxLetters(3)
    lvlMinBox:SetNumeric(true)
    self.lvlMinBox = lvlMinBox

    local lvlSep = Th.Fs(filterRow, "small", "-", "textDimmed")
    lvlSep:SetPoint("LEFT", lvlMinBox, "RIGHT", 3, 0)

    local lvlMaxBox = GC.UI.Panel.Input(filterRow, 38, inputH)
    lvlMaxBox:SetPoint("LEFT", lvlSep, "RIGHT", 3, 0)
    lvlMaxBox:SetMaxLetters(3)
    lvlMaxBox:SetNumeric(true)
    self.lvlMaxBox = lvlMaxBox

    local guildlessLabel = Th.Fs(filterRow, "tiny", "Guildless Only", "textDimmed")
    guildlessLabel:SetPoint("LEFT", lvlMaxBox, "RIGHT", 14, 0)

    local guildlessToggle = GC.UI.Button.Create(filterRow, "On", "secondary", 40, btnH)
    guildlessToggle:SetPoint("LEFT", guildlessLabel, "RIGHT", 4, 0)
    self.guildlessToggle = guildlessToggle

    local exclRecentLabel = Th.Fs(filterRow, "tiny", "Excl. Recent", "textDimmed")
    exclRecentLabel:SetPoint("LEFT", guildlessToggle, "RIGHT", 14, 0)

    local exclRecentToggle = GC.UI.Button.Create(filterRow, "On", "secondary", 40, btnH)
    exclRecentToggle:SetPoint("LEFT", exclRecentLabel, "RIGHT", 4, 0)
    self.exclRecentToggle = exclRecentToggle

    local zoneLabel = Th.Fs(filterRow, "tiny", "Zone Contains", "textDimmed")
    zoneLabel:SetPoint("LEFT", exclRecentToggle, "RIGHT", 14, 0)

    local zoneBox = GC.UI.Panel.Input(filterRow, 130, inputH)
    zoneBox:SetPoint("LEFT", zoneLabel, "RIGHT", 4, 0)
    zoneBox:SetMaxLetters(64)
    self.zoneBox = zoneBox

    local applyFiltersBtn = GC.UI.Button.Create(filterRow, "Apply Filters", "secondary", 96, btnH)
    applyFiltersBtn:SetPoint("LEFT", zoneBox, "RIGHT", 8, 0)
    self.applyFiltersBtn = applyFiltersBtn

    local connectedLabel = Th.Fs(filterRow, "tiny", "Connected Realms", "textDimmed")
    connectedLabel:SetPoint("LEFT", applyFiltersBtn, "RIGHT", 14, 0)

    local connectedToggle = GC.UI.Button.Create(filterRow, "On", "secondary", 40, btnH)
    connectedToggle:SetPoint("LEFT", connectedLabel, "RIGHT", 4, 0)
    self.connectedToggle = connectedToggle
    connectedToggle:SetTooltip("Include Connected Realms",
        "When ON, scans all realms connected to the guild's home realm. Turn OFF to scan home realm only.")
    connectedToggle:SetScript("OnClick", function()
        local svc = SVC()
        if not svc then return end
        local settings = svc:GetSettings()
        if settings then
            settings.includeConnectedRealms = not (settings.includeConnectedRealms ~= false)
        end
        IP:_refreshFilterDisplay()
    end)

    filterRow:Hide()

    -- ── Status strip ─────────────────────────────────────────────────────────
    local statusBar = CreateFrame("Frame", nil, frame)
    statusBar:SetPoint("TOPLEFT",  realmRow, "BOTTOMLEFT",  0, -rowGap)
    statusBar:SetPoint("TOPRIGHT", frame,    "TOPRIGHT",   -P, 0)
    statusBar:SetHeight(24)
    Th.Bg(statusBar, Th.c.chrome)

    local scanStatusFs = Th.Fs(statusBar, "data", "Scan: idle", "textDimmed")
    scanStatusFs:SetPoint("LEFT", statusBar, "LEFT", 8, 0)
    scanStatusFs:SetWidth(420)
    self.scanStatusFs = scanStatusFs

    local queueStatusFs = Th.Fs(statusBar, "data", "Queue: idle  queued=0  done=0", "textDimmed")
    queueStatusFs:SetPoint("LEFT", statusBar, "LEFT", 440, 0)
    queueStatusFs:SetWidth(220)
    self.queueStatusFs = queueStatusFs

    local permStatusFs = Th.Fs(statusBar, "data", "", "textDimmed")
    permStatusFs:SetPoint("RIGHT", statusBar, "RIGHT", -8, 0)
    permStatusFs:SetWidth(200)
    permStatusFs:SetJustifyH("RIGHT")
    self.permStatusFs = permStatusFs

    -- ── Column header bar ────────────────────────────────────────────────────
    local colBar = CreateFrame("Frame", nil, frame)
    colBar:SetPoint("TOPLEFT",  statusBar, "BOTTOMLEFT",  0, -6)
    colBar:SetPoint("TOPRIGHT", frame,     "TOPRIGHT",   -P, 0)
    colBar:SetHeight(colBarH)
    Th.Bg(colBar, Th.c.chrome)

    for _, col in ipairs(COLS) do
        local fs = Th.Fs(colBar, "tiny", col.label, "textDimmed")
        fs:SetPoint("LEFT", colBar, "LEFT", col.x, 0)
        fs:SetWidth(col.w)
    end

    -- ── Candidate list ───────────────────────────────────────────────────────
    local listHost = CreateFrame("Frame", nil, frame)
    listHost:SetPoint("TOPLEFT",     colBar, "BOTTOMLEFT",  0,  -2)
    listHost:SetPoint("BOTTOMRIGHT", bottomControls, "TOPRIGHT", 0, 8)
    self.listHost = listHost

    self.candidateList = GC.UI.List.Create(listHost, 26, buildCandidateRow, function(item)
        if isActionableCandidate(item) then
            item.selected = not (item.selected == true)
            self._selectedKey = item.key
        else
            if item then item.selected = false end
            self._selectedKey = nil
        end
        self:_refreshCandidateList()
        self:_updateButtons()
    end)
    self.candidateList:SetEmptyText("Run a scan to find invite candidates.")

    local hotkeyBtn = CreateFrame("Button", "GuildCoreInviteNowHotkeyButton", frame)
    hotkeyBtn:RegisterForClicks("AnyUp")
    hotkeyBtn:SetScript("OnClick", function()
        IP:_inviteNow()
    end)
    hotkeyBtn:SetSize(1, 1)
    hotkeyBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", -100, 100)
    hotkeyBtn:SetAlpha(0)
    self.inviteNowHotkeyBtn = hotkeyBtn

    local scanHotkeyBtn = CreateFrame("Button", "GuildCoreInviteScanHotkeyButton", frame)
    scanHotkeyBtn:RegisterForClicks("AnyUp")
    scanHotkeyBtn:SetScript("OnClick", function()
        IP:_doScan()
    end)
    scanHotkeyBtn:SetSize(1, 1)
    scanHotkeyBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", -102, 100)
    scanHotkeyBtn:SetAlpha(0)
    self.inviteScanHotkeyBtn = scanHotkeyBtn
    applyInviteHotkeys()

    -- ── Wire button callbacks ─────────────────────────────────────────────────
    -- Scan fires immediately using auto-detected guild realm.
    -- No manual realm entry; optional filter text in filterRow narrows results.
    scanBtn:SetScript("OnClick", function()
        IP:_doScan()
    end)

    queueSelBtn:SetScript("OnClick", function()
        IP:_selectAll()
    end)

    clearQueueBtn:SetScript("OnClick", function()
        IP:_clearSelection()
    end)

    refreshStatusBtn:SetScript("OnClick", function()
        IP:_refreshInviteStatuses()
    end)

    inviteNowBtn:SetScript("OnClick", function()
        IP:_inviteNow()
    end)

    inviteSelectedBtn:SetScript("OnClick", function()
        GC.UI.MainFrame:SetStatus("Invite Selected is under development. Use Invite Next for direct invites.", "textWarn")
    end)

    dryRunBtn:SetScript("OnClick", function()
        local svc = SVC()
        if not svc then return end
        local settings = svc:GetSettings()
        if settings then
            settings.dryRun = not (settings.dryRun ~= false)
        end
        IP:_refreshFilterDisplay()
    end)

    debugBtn:SetScript("OnClick", function()
        local svc = SVC()
        if not svc then return end
        local settings = svc:GetSettings()
        if settings then
            settings.debugEnabled = not (settings.debugEnabled == true)
            GC:Print("Invite debug logging:", settings.debugEnabled and "ON" or "OFF")
        end
        IP:_refreshFilterDisplay()
    end)

    local function toggleVisibilitySetting(key)
        local svc = SVC()
        if not svc then return end
        local settings = svc:GetSettings()
        if settings then
            settings[key] = not (settings[key] == true)
        end
        IP:_refreshFilterDisplay()
        IP:_refreshCandidateList()
        IP:_updateButtons()
    end

    showGuildedBtn:SetScript("OnClick", function()
        toggleVisibilitySetting("showGuildedCandidates")
    end)
    showRecentBtn:SetScript("OnClick", function()
        toggleVisibilitySetting("showRecentlyInvitedCandidates")
    end)
    showDeclinedBtn:SetScript("OnClick", function()
        toggleVisibilitySetting("showRecentlyDeclinedCandidates")
    end)
end

-- ── Scan submission ─────────────────────────────────────────────────────────

function IP:_doScan()
    local scanner = IS()
    if not scanner then
        GC.UI.MainFrame:SetStatus("Invite scanner is unavailable.", "textDanger")
        return
    end
    if scanner:IsScanning() then
        GC.UI.MainFrame:SetStatus("Scan already active.", "textWarn")
        return
    end
    self:_enforceSafeInviteSettings()

    local ok, err
    if scanner:HasPending() then
        ok, err = scanner:NextQuery()
    else
        ok, err = scanner:StartScan(nil)
    end
    if not ok then
        GC.UI.MainFrame:SetStatus(err or "Scan failed. Try /gc invitescan realm to diagnose.", "textDanger")
    end
    self:UpdateStatus()
end

-- ── Queue actions ───────────────────────────────────────────────────────────

function IP:_queueSelected()
    local q = IQ()
    if not q then return end
    local scanner = IS()
    local candidates = scanner and scanner:GetCandidates() or {}
    local selected = self:_selectedEligibleCandidates(candidates)
    local queued, duplicates, ineligible = q:AddCandidates(selected)
    local stats = self:_selectionStats(candidates)
    GC:Print(string.format(
        "Invite UI Queue Selected: total=%d selected=%d eligibleSelected=%d skippedIneligible=%d skippedHasGuild=%d dryRun=%s",
        stats.total, stats.selected, stats.eligibleSelected, stats.skippedIneligible, stats.skippedGuild, tostring(self:_isDryRun())
    ))
    GC.UI.MainFrame:SetStatus(
        string.format("Queued %d selected. Skipped %d duplicates, %d ineligible.", queued or 0, duplicates or 0, ineligible or 0),
        queued and queued > 0 and "textSuccess" or "textWarn"
    )
    self:UpdateStatus()
end

function IP:_inviteSelected()
    local q = IQ()
    local scanner = IS()
    if not q or not scanner then return end
    local candidates = scanner:GetCandidates()
    local ok, err = q:StartSelected(candidates, self:_isDryRun())
    GC.UI.MainFrame:SetStatus(ok and "Invite selected started." or (err or "Unable to invite selected."), ok and "textSuccess" or "textWarn")
    self:UpdateStatus()
end

function IP:_inviteNow()
    local q = IQ()
    local scanner = IS()
    if not q or not scanner then return end

    local candidates = scanner:GetCandidates()
    local selected = self:_selectedEligibleCandidates(candidates)
    local candidate = selected[1]
    if not candidate then
        GC.UI.MainFrame:SetStatus("Select one eligible invite candidate first.", "textWarn")
        self:UpdateStatus()
        return
    end

    local ok, err = q:InviteNow(candidate)
    GC.UI.MainFrame:SetStatus(
        ok and ("Invite sent for " .. tostring(candidate.fullName or candidate.name or candidate.key) .. ".")
            or (err or "Unable to send invite."),
        ok and "textSuccess" or "textWarn"
    )
    self:UpdateStatus()
end

function IP:_isDryRun()
    local svc = SVC()
    local settings = svc and svc:GetSettings() or {}
    return settings.dryRun ~= false
end

function IP:_enforceSafeInviteSettings()
    local svc = SVC()
    local settings = svc and svc:GetSettings()
    if not settings then return end
    settings.guildlessOnly = true
    settings.excludeRecentlyInvited = true
    settings.includeConnectedRealms = true
    if settings.levelMin == nil then settings.levelMin = 1 end
    if settings.levelMax == nil then settings.levelMax = maxPlayerLevel() end
    if settings.scanLevelMin == nil then settings.scanLevelMin = 1 end
    if settings.scanLevelMax == nil then settings.scanLevelMax = maxPlayerLevel() end
    if settings.debugEnabled == nil then settings.debugEnabled = false end
    if settings.showGuildedCandidates == nil then settings.showGuildedCandidates = false end
    if settings.showRecentlyInvitedCandidates == nil then settings.showRecentlyInvitedCandidates = false end
    if settings.showRecentlyDeclinedCandidates == nil then settings.showRecentlyDeclinedCandidates = false end
end

function IP:_selectionStats(candidates)
    local stats = { total = 0, selected = 0, eligibleSelected = 0, skippedIneligible = 0, skippedGuild = 0 }
    for _, c in ipairs(candidates or {}) do
        stats.total = stats.total + 1
        if c.selected == true then
            stats.selected = stats.selected + 1
            if hasGuild(c) then
                stats.skippedGuild = stats.skippedGuild + 1
                stats.skippedIneligible = stats.skippedIneligible + 1
            elseif isActionableCandidate(c) then
                stats.eligibleSelected = stats.eligibleSelected + 1
            else
                stats.skippedIneligible = stats.skippedIneligible + 1
            end
        end
    end
    return stats
end

function IP:_shouldShowCandidate(candidate)
    if not candidate then return false end
    local svc = SVC()
    local settings = svc and svc:GetSettings() or {}
    if candidate.status == "queued"
        or candidate.status == "sending"
        or candidate.status == "failed"
        or candidate.status == "failed_api"
        or candidate.status == "no_response"
        or candidate.status == "skipped" then
        return true
    end
    if isActionableCandidate(candidate) then
        return true
    end
    if hasReason(candidate, "has_guild") and settings.showGuildedCandidates ~= true then
        return false
    end
    if hasReason(candidate, "recently_invited") and settings.showRecentlyInvitedCandidates ~= true then
        return false
    end
    if hasReason(candidate, "recently_declined") and settings.showRecentlyDeclinedCandidates ~= true then
        return false
    end
    if hasReason(candidate, "banned") then
        return false
    end
    return hasReason(candidate, "has_guild")
        or hasReason(candidate, "recently_invited")
        or hasReason(candidate, "recently_declined")
end

function IP:_visibleCandidates(candidates)
    local visible = {}
    for _, candidate in ipairs(candidates or {}) do
        if self:_shouldShowCandidate(candidate) then
            visible[#visible + 1] = candidate
        end
    end
    return visible
end

function IP:_refreshCandidateList()
    if not self.candidateList then return end
    local scanner = IS()
    local candidates = scanner and scanner:GetCandidates() or {}
    self.candidateList:Refresh(self:_visibleCandidates(candidates))
end

function IP:_selectedEligibleCandidates(candidates)
    local selected = {}
    for _, c in ipairs(candidates or {}) do
        if c.selected == true and isActionableCandidate(c) then
            selected[#selected + 1] = c
        end
    end
    return selected
end

function IP:_selectAll()
    local scanner = IS()
    local candidates = scanner and scanner:GetCandidates() or {}
    local count = 0
    for _, c in ipairs(candidates) do
        if self:_shouldShowCandidate(c) and isActionableCandidate(c) then
            c.selected = true
            count = count + 1
        end
    end
    self:_refreshCandidateList()
    self:UpdateStatus()
    GC.UI.MainFrame:SetStatus(string.format("Selected %d eligible candidate%s.", count, count == 1 and "" or "s"), count > 0 and "textSuccess" or "textWarn")
end

function IP:_clearSelection()
    local scanner = IS()
    local candidates = scanner and scanner:GetCandidates() or {}
    for _, c in ipairs(candidates) do
        c.selected = false
    end
    self:_refreshCandidateList()
    self:UpdateStatus()
    GC.UI.MainFrame:SetStatus("Selection cleared.", "textDimmed")
end

function IP:_refreshInviteStatuses()
    local scanner = IS()
    local svc = SVC()
    local storage = svc and svc:GetStorage()
    local candidates = scanner and scanner:GetCandidates() or {}
    local recentInvites = storage and storage.recentInvites or {}
    local recentDeclines = storage and storage.recentDeclines or {}
    local updated = 0

    for _, c in ipairs(candidates) do
        local key = candidateStorageKey(c)
        local inviteEntry = key and recentInvites[key]
        local declineEntry = key and recentDeclines[key]
        if declineEntry then
            c.status = "declined"
            c.queueResult = "declined"
            c.selected = false
            c.eligible = false
            addReason(c, "recently_declined")
            updated = updated + 1
        elseif inviteEntry then
            c.status = tostring(inviteEntry.outcome or "invite_sent")
            c.queueResult = c.status
            c.selected = false
            addReason(c, "recently_invited")
            updated = updated + 1
        end
    end

    self:_refreshCandidateList()
    self:UpdateStatus()
    GC.UI.MainFrame:SetStatus(string.format("Refreshed invite status for %d candidate%s.", updated, updated == 1 and "" or "s"), "textSuccess")
end

function IP:_clearSelectedQueuedState()
    local scanner = IS()
    local candidates = scanner and scanner:GetCandidates() or {}
    for _, c in ipairs(candidates) do
        if isLockedStatus(c.status) then
            c.status = nil
            c.queueResult = nil
        end
        if isActionableCandidate(c) then
            c.selected = true
        else
            c.selected = false
        end
    end
    self:_refreshCandidateList()
end

function IP:_queueAllEligible()
    local q = IQ()
    if not q then return end
    local scanner = IS()
    local candidates = scanner and scanner:GetCandidates() or {}
    local eligible = {}
    for _, c in ipairs(candidates) do
        if c.eligible then
            eligible[#eligible + 1] = c
        end
    end
    if #eligible == 0 then
        GC.UI.MainFrame:SetStatus("No eligible candidates to queue.", "textWarn")
        return
    end
    local queued, skipped, ineligible = q:AddCandidates(eligible)
    local msg = string.format("Queued %d candidates.", queued)
    if skipped > 0 then
        msg = msg .. string.format(" Skipped %d duplicates.", skipped)
    end
    if ineligible and ineligible > 0 then
        msg = msg .. string.format(" Skipped %d ineligible.", ineligible)
    end
    GC.UI.MainFrame:SetStatus(msg, "textSuccess")
    self:UpdateStatus()
end

-- ── Filter helpers ──────────────────────────────────────────────────────────

function IP:_applyFilterInputs()
    local svc = SVC()
    if not svc then return end
    local settings = svc:GetSettings()
    if not settings then return end

    local minText = self.lvlMinBox and GC.Utils.Trim(self.lvlMinBox:GetText() or "") or ""
    local maxText = self.lvlMaxBox and GC.Utils.Trim(self.lvlMaxBox:GetText() or "") or ""
    local zoneText = self.zoneBox and GC.Utils.Trim(self.zoneBox:GetText() or "") or ""

    if minText ~= "" then
        settings.levelMin = math.max(1, tonumber(minText) or settings.levelMin or 1)
    end
    if maxText ~= "" then
        settings.levelMax = math.max(settings.levelMin or 1, tonumber(maxText) or settings.levelMax or maxPlayerLevel())
    end
    settings.zoneIncludes = zoneText ~= "" and {zoneText} or {}
end

function IP:_refreshFilterDisplay()
    self:_enforceSafeInviteSettings()
    local svc = SVC()
    local settings = svc and svc:GetSettings() or {}

    if self.guildlessToggle then
        local isOn = settings.guildlessOnly ~= false
        self.guildlessToggle:SetLabel(isOn and "On" or "Off")
    end
    if self.exclRecentToggle then
        local isOn = settings.excludeRecentlyInvited ~= false
        self.exclRecentToggle:SetLabel(isOn and "On" or "Off")
    end
    if self.connectedToggle then
        local isOn = settings.includeConnectedRealms ~= false
        self.connectedToggle:SetLabel(isOn and "On" or "Off")
    end
    if self.lvlMinBox then
        self.lvlMinBox:SetText(tostring(settings.levelMin or 1))
    end
    if self.lvlMaxBox then
        self.lvlMaxBox:SetText(tostring(settings.levelMax or maxPlayerLevel()))
    end
    if self.dryRunBtn then
        self.dryRunBtn:SetLabel((settings.dryRun ~= false) and "Dry Run: On" or "Dry Run: Off")
    end
    if self.debugBtn then
        self.debugBtn:SetLabel((settings.debugEnabled == true) and "On" or "Off")
    end
    if self.showGuildedBtn then
        self.showGuildedBtn:SetLabel((settings.showGuildedCandidates == true) and "Guilded: On" or "Guilded: Off")
    end
    if self.showRecentBtn then
        self.showRecentBtn:SetLabel((settings.showRecentlyInvitedCandidates == true) and "Invited: On" or "Invited: Off")
    end
    if self.showDeclinedBtn then
        self.showDeclinedBtn:SetLabel((settings.showRecentlyDeclinedCandidates == true) and "Declined: On" or "Declined: Off")
    end
    self:_refreshRealmDisplay()
end

function IP:_refreshRealmDisplay()
    local svc = SVC()
    local settings = svc and svc:GetSettings() or {}
    local Realm = GC.Modules.Invite and GC.Modules.Invite.Realm
    local override = Realm and Realm.NormalizeMainRealm and Realm.NormalizeMainRealm(settings.guildRealmOverride) or settings.guildRealmOverride

    if self.realmSelect and self.realmSelect.SetSelectedRealm then
        self.realmSelect:SetSelectedRealm(override)
    end

    if not self.realmInfoFs then return end

    local info = Realm and Realm.GetScanRealms and Realm.GetScanRealms(settings) or nil
    local guildRealm = info and info.anchor or override or "unknown"
    local suffix = override and " (selected)" or ""
    local realms = info and info.scanRealms or {}
    local connected = #realms > 0 and table.concat(realms, ", ") or "unknown"
    self.realmInfoFs:SetText(string.format(
        "Guild Realm: %s%s   Connected Realms: %s",
        tostring(guildRealm),
        suffix,
        connected
    ))
end

function IP:_refilterCandidates()
    local scanner = IS()
    if not scanner then return end
    local candidates = scanner:GetCandidates()
    local svc = SVC()
    local storage = svc and svc:GetStorage()
    local settings = storage and storage.settings or {}
    local history = {
        ignored       = storage and storage.ignored or {},
        recentInvites = storage and storage.recentInvites or {},
        recentDeclines = storage and storage.recentDeclines or {},
    }
    local filters = GC.Modules.Invite and GC.Modules.Invite.Filters
    for _, c in ipairs(candidates) do
        if filters and filters.EvaluateCandidate then
            local result = filters.EvaluateCandidate(c, settings, history)
            c.eligible           = result.eligible == true
            c.ineligibleReasons  = result.reasons or {}
        end
        if hasGuild(c) then
            c.eligible = false
            c.selected = false
            c.isGuildless = false
            c.ineligibleReasons = c.ineligibleReasons or {}
            local hasReason = false
            for _, reason in ipairs(c.ineligibleReasons) do
                if reason == "has_guild" then hasReason = true end
            end
            if not hasReason then
                c.ineligibleReasons[#c.ineligibleReasons + 1] = "has_guild"
            end
        elseif c.eligible == true and c.selected == nil then
            c.selected = true
        elseif c.eligible ~= true then
            c.selected = false
        end
    end
    self:_refreshCandidateList()
    self:_updateButtons()
end

-- ── Button state management ─────────────────────────────────────────────────

function IP:_updateButtons()
    local scanner   = IS()
    local queue     = IQ()
    local scanning  = scanner and scanner:IsScanning() or false
    local qStatus   = queue and queue:GetStatus() or "idle"
    local qLen      = queue and #queue:GetItems() or 0
    local candidates = scanner and scanner:GetCandidates() or {}
    local stats = self:_selectionStats(candidates)
    local hasSelectedEligible = stats.eligibleSelected > 0
    local visibleActionable = 0
    for _, c in ipairs(candidates) do
        if self:_shouldShowCandidate(c) and isActionableCandidate(c) then
            visibleActionable = visibleActionable + 1
        end
    end
    local scanStatus = scanner and scanner.GetScanStatus and scanner:GetScanStatus() or nil

    if self.scanBtn     then self.scanBtn:SetEnabled(not scanning)      end
    if self.scanBtn and self.scanBtn.SetLabel then
        if scanning then
            self.scanBtn:SetLabel("Scanning...")
        elseif scanner and scanner:HasPending() then
            self.scanBtn:SetLabel("Scan Next")
        elseif scanStatus and scanStatus.completedAt then
            self.scanBtn:SetLabel("Scan Again")
        else
            self.scanBtn:SetLabel("Scan")
        end
    end

    if self.queueSelBtn then
        self.queueSelBtn:SetEnabled(visibleActionable > 0 and qStatus ~= "running")
    end
    if self.queueAllBtn then
        self.queueAllBtn:SetEnabled(qStatus ~= "running")
    end

    if self.startQueueBtn then
        self.startQueueBtn:SetEnabled(qLen > 0 and qStatus ~= "running")
    end
    if self.pauseBtn then
        local canPauseResume = qStatus == "running" or qStatus == "paused"
        self.pauseBtn:SetEnabled(canPauseResume)
        if self.pauseBtn.SetLabel then
            self.pauseBtn:SetLabel(qStatus == "paused" and "Resume" or "Pause")
        end
    end
    if self.cancelQueueBtn then
        self.cancelQueueBtn:SetEnabled(qLen > 0 or qStatus ~= "idle")
    end
    if self.clearQueueBtn then
        self.clearQueueBtn:SetEnabled(stats.selected > 0 and qStatus ~= "running")
    end
    if self.refreshStatusBtn then
        self.refreshStatusBtn:SetEnabled(#candidates > 0)
    end
    if self.inviteNowBtn then
        self.inviteNowBtn:SetEnabled(hasSelectedEligible and qStatus ~= "running")
    end
    if self.inviteSelectedBtn then
        self.inviteSelectedBtn:SetEnabled(true)
    end
end

-- ── Status update ────────────────────────────────────────────────────────────

function IP:UpdateStatus()
    local scanner = IS()
    local queue   = IQ()

    -- Scan status: show realm anchor and progress
    if self.scanStatusFs then
        local rt = GC.State.invite
        local realmAnchor = rt and rt.scan and rt.scan.realmInfo and rt.scan.realmInfo.anchor
        local realmStr = realmAnchor and ("[" .. realmAnchor .. "]") or ""
        local scanStatus = scanner and scanner.GetScanStatus and scanner:GetScanStatus() or nil
        if scanStatus and scanStatus.statusLine then
            local progress = scanStatus.progressLine and ("  " .. scanStatus.progressLine) or ""
            self.scanStatusFs:SetText(scanStatus.statusLine .. progress)
        elseif scanner and scanner:IsScanning() then
            local qi = rt and rt.scan and rt.scan.queryIndex or 1
            local qt = rt and rt.scan and rt.scan.totalQueries or 1
            self.scanStatusFs:SetText(string.format(
                "Scan: running %s  (%d/%d)", realmStr, qi, qt
            ))
        else
            local count = rt and rt.candidates and #rt.candidates or 0
            if count > 0 then
                local scanStatus = scanner and scanner.GetScanStatus and scanner:GetScanStatus() or nil
                if scanStatus and (scanStatus.pendingCount or 0) > 0 then
                    self.scanStatusFs:SetText(string.format(
                        "Scan paused. Click Scan Next.  Scan Progress: processed %d / pending %d",
                        scanStatus.processedQueries or 0,
                        scanStatus.pendingCount or 0
                    ))
                else
                    self.scanStatusFs:SetText(string.format(
                        "Scan: %d candidates %s", count, realmStr
                    ))
                end
            else
                -- Show detected realm even when idle so user can see what will be scanned.
                local Realm = GC.Modules.Invite and GC.Modules.Invite.Realm
                if Realm and realmStr == "" then
                    local svc = SVC()
                    local settings = svc and svc:GetSettings() or {}
                    local info = Realm.GetScanRealms and Realm.GetScanRealms(settings) or nil
                    local gr = info and info.anchor or Realm.GetGuildRealm()
                    realmStr = gr and ("[" .. gr .. "]") or "[realm unknown]"
                end
                self.scanStatusFs:SetText("Scan: idle  " .. realmStr)
            end
        end
    end

    -- Queue status
    if self.queueStatusFs and queue then
        local items = queue:GetItems()
        local queued, done = 0, 0
        for _, item in ipairs(items) do
            if item.status == "queued" then queued = queued + 1
            else done = done + 1 end
        end
        self.queueStatusFs:SetText(string.format(
            "Queue: %s  queued=%d  done=%d",
            queue:GetStatus(), queued, done
        ))
    end

    -- Permission note
    if self.permStatusFs then
        local Th = T()
        local canInvite, reason = GC.Permissions:CanInviteGuild()
        if canInvite then
            local c = Th.c.statusActive or Th.c.textAccent
            self.permStatusFs:SetTextColor(c[1], c[2], c[3], 1)
            self.permStatusFs:SetText("Invite permission: ok")
        else
            local c = Th.c.textDanger or Th.c.textWarn
            self.permStatusFs:SetTextColor(c[1], c[2], c[3], 1)
            self.permStatusFs:SetText(reason or "No invite permission")
        end
    end

    self:_updateButtons()
end

-- ── Refresh (called by MainFrame on panel show) ───────────────────────────

function IP:Refresh()
    if not self.frame then return end
    local Th = T()
    local P  = Th.padding or 10

    self:_refreshFilterDisplay()
    self:UpdateStatus()

    -- Show/hide the module-disabled notice. This should normally stay hidden;
    -- older development saved variables may contain a hidden false value, and
    -- the v14 migration resets that to enabled.
    local settings = GC.DB:GetSettings()
    local enabled  = not settings or settings.enableInviteModule ~= false
    if self.noticeFrame and self._ctrlRow then
        local rowGap = 10
        if not enabled then
            self.noticeFs:SetText("Invite module is disabled. Enable it in Settings → General.")
            self.noticeFrame:Show()
            self._ctrlRow:ClearAllPoints()
            self._ctrlRow:SetPoint("TOPLEFT",  self.noticeFrame, "BOTTOMLEFT",  0,  -rowGap)
            self._ctrlRow:SetPoint("TOPRIGHT", self.frame,       "TOPRIGHT",   -P,  0)
        else
            self.noticeFrame:Hide()
            self._ctrlRow:ClearAllPoints()
            self._ctrlRow:SetPoint("TOPLEFT",  self._hdr, "BOTTOMLEFT",  0,  -rowGap)
            self._ctrlRow:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT",  -P,  0)
        end
    end

    -- Populate candidate list from runtime state.
    local scanner = IS()
    local candidates = scanner and scanner:GetCandidates() or {}
    self:_refreshCandidateList()
end

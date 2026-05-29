-- /GuildCore/UI/EditCharacterPopup.lua
-- Draft-based character management modal. Field and Main/Alt edits wait for
-- Save; explicit officer actions run from the Actions tab after confirmation.
local addonName, ns = ...
local GC = ns.GuildCore

GC.UI.EditCharacterPopup = {}
local ECP = GC.UI.EditCharacterPopup

local function T() return GC.UI.Theme end
local function DS() return GC.Services.DataStore end
local function GS() return GC.Services.GuildService end

local currentKey = nil
local draft = nil

local function trim(value)
    return GC.Utils and GC.Utils.Trim and GC.Utils.Trim(value or "") or tostring(value or ""):match("^%s*(.-)%s*$")
end

local function splitTags(text)
    local tags, seen = {}, {}
    for part in string.gmatch(tostring(text or ""), "([^,]+)") do
        local tag = trim(part)
        local key = tag:lower()
        if tag ~= "" and not seen[key] then
            tags[#tags + 1] = tag
            seen[key] = true
        end
    end
    return tags
end

local function joinTags(tags)
    return type(tags) == "table" and table.concat(tags, ", ") or ""
end

local function parseDate(text)
    text = trim(text)
    if text == "" then return nil, true end
    local ts = GC.Utils.ParseFlexibleDate and GC.Utils.ParseFlexibleDate(text) or nil
    return ts, ts ~= nil
end

local function dateText(ts)
    return tonumber(ts) and date("%Y-%m-%d", ts) or ""
end

local function status(message, colorKey)
    if GC.UI and GC.UI.MainFrame then
        GC.UI.MainFrame:SetStatus(message, colorKey)
    end
end

local function noteEditAvailability(player)
    if GC.Permissions and GC.Permissions.GetNoteEditAvailability then
        return GC.Permissions:GetNoteEditAvailability(player)
    end
    return {
        enabled = false,
        protected = false,
        reason = "Permission service is unavailable.",
    }
end

local function addTagToBox(box, tag)
    local tags = splitTags(box:GetText() or "")
    local wanted = tag:lower()
    for _, existing in ipairs(tags) do
        if existing:lower() == wanted then return end
    end
    tags[#tags + 1] = tag
    box:SetText(joinTags(tags))
end

local function showConfirm(key, text, callback)
    StaticPopupDialogs[key] = StaticPopupDialogs[key] or {
        text = text,
        button1 = "Confirm",
        button2 = "Cancel",
        OnAccept = function(_, cb) if cb then cb() end end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    StaticPopupDialogs[key].text = text
    if GC.UI.FrameLayering then
        GC.UI.FrameLayering:ShowStaticPopup(key, nil, nil, callback)
    else
        StaticPopup_Show(key, nil, nil, callback)
    end
end

local function ensureLivePlayer()
    if not currentKey then return nil end
    return DS():GetPlayer(currentKey)
end

local function roleLabel(player)
    local role = player and player.classification or "unknown"
    return ({
        main = "Main",
        alt = "Alt",
        unknown = "Unknown",
    })[role] or "Unknown"
end

local function activeRosterPlayer(key)
    local player = key and DS():GetPlayer(key) or nil
    if player and player.status == "active" then
        return player
    end
    return nil
end

local function copyText(text)
    text = tostring(text or "")
    if text == "" then return end
    if SetClipboard then
        SetClipboard(text)
        status("Copied " .. text, "textSuccess")
    elseif ChatFrame_OpenChat then
        ChatFrame_OpenChat(text)
        status("Opened chat with " .. text, "textSecond")
    end
end

local function clampScroll(scrollFrame, delta, step)
    if not scrollFrame then return end
    local child = scrollFrame.GetScrollChild and scrollFrame:GetScrollChild() or nil
    local childHeight = child and child.GetHeight and child:GetHeight() or 0
    local frameHeight = scrollFrame.GetHeight and scrollFrame:GetHeight() or 0
    local maxScroll = math.max(0, childHeight - frameHeight)
    local nextScroll = (scrollFrame:GetVerticalScroll() or 0) - ((delta or 0) * (step or 24))
    scrollFrame:SetVerticalScroll(math.min(maxScroll, math.max(0, nextScroll)))
end

local function playerClassColor(player)
    local classKey = player and (player.class or player.classFileName)
    local color = player and player.classRGB
    if not color and classKey and T().classColor then
        color = T().classColor[classKey]
    end
    return color or T().c.textSecond
end

local function arrayContains(values, needle)
    for _, value in ipairs(values or {}) do
        if value == needle then return true end
    end
    return false
end

local function addUnique(values, needle)
    if needle and not arrayContains(values, needle) then
        values[#values + 1] = needle
        return true
    end
    return false
end

local function markPendingAction(action, label)
    if not draft then return end
    draft.pendingAction = action
end

local function makeLabel(parent, text, x, y)
    local fs = T().Fs(parent, "tiny", text, "textDimmed")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    return fs
end

local function makeInput(parent, label, x, y, w)
    makeLabel(parent, label, x, y)
    local box = GC.UI.Panel.Input(parent, w or 250, T().inputH)
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 16)
    return box
end

local function makeSection(parent, title, y)
    local Th = T()
    local P = Th.padding
    local lbl = Th.Fs(parent, "subheader", title, "textAccent")
    lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", P, y)
    local sep = parent:CreateTexture(nil, "ARTWORK")
    sep:SetPoint("TOPLEFT", parent, "TOPLEFT", P, y - 24)
    sep:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -P, y - 24)
    sep:SetHeight(1)
    local c = Th.c.separator
    sep:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    return y - 38, lbl
end

function ECP:_setTab(tab)
    self.activeTab = tab
    for id, page in pairs(self.pages or {}) do
        page:SetShown(id == tab)
        local btn = self.tabButtons[id]
        if btn and btn._bg then
            local c = T().c[id == tab and "btnPrimary" or "btnSecond"]
            btn._bg:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
        end
    end
end

function ECP:_buildGeneralPage(page)
    local y = -10
    y = makeSection(page, "GENERAL", y)
    self.publicNoteBox = makeInput(page, "Public Note", 12, y, 500); y = y - 48
    self.officerNoteBox = makeInput(page, "Officer Note", 12, y, 500); y = y - 48
    self.noteEditWarning = T().Fs(page, "tiny", "", "textWarn")
    self.noteEditWarning:SetPoint("TOPLEFT", page, "TOPLEFT", 12, y + 2)
    self.noteEditWarning:SetPoint("RIGHT", page, "RIGHT", -12, 0)
    self.noteEditWarning:SetWordWrap(true)
    self.noteEditWarning:Hide()
    y = y - 22
    self.customNoteBox = makeInput(page, "Custom Note", 12, y, 500); y = y - 48
    self.discordBox = makeInput(page, "Discord Name", 12, y, 240)
    self.joinDateBox = makeInput(page, "Join Date", 272, y, 120); y = y - 48
    self.pointsBox = makeInput(page, "Points Adjustment", 12, y, 120)
    self.pointsReasonBox = makeInput(page, "Points Reason", 152, y, 360); y = y - 58
    page:SetHeight(math.abs(y) + 20)
end

function ECP:_refreshNoteEditWarning(live)
    if not self.noteEditWarning then return end
    local availability = noteEditAvailability(live)
    if availability.protected then
        self.noteEditWarning:SetText("Note edits may be blocked for " .. tostring(availability.targetRankName or (live and live.rankName) or "this rank") .. ". " .. tostring(availability.reason or "Your guild rank may not have permission to edit notes for members at this rank or higher."))
        self.noteEditWarning:Show()
    elseif availability.reason and availability.enabled then
        self.noteEditWarning:SetText(availability.reason)
        self.noteEditWarning:Show()
    else
        self.noteEditWarning:Hide()
    end
end

function ECP:_buildAltPage(page)
    self.altPageContent = page

    local y = -10
    y = makeSection(page, "CURRENT STATUS", y)
    self.altCurrentCharacter = T().Fs(page, "data", "Current Character: -", "textSecond")
    self.altCurrentCharacter:SetPoint("TOPLEFT", page, "TOPLEFT", 12, y)
    self.altCurrentRole = T().Fs(page, "data", "Current Role: Unknown", "textSecond")
    self.altCurrentRole:SetPoint("TOPLEFT", page, "TOPLEFT", 12, y - 20)
    self.altLinkedMain = T().Fs(page, "data", "Linked Main: -", "textSecond")
    self.altLinkedMain:SetPoint("TOPLEFT", page, "TOPLEFT", 260, y - 20)
    y = y - 40

    y, self.linkedAltSectionTitle = makeSection(page, "LINKED ALTS", y)
    local listFrame = CreateFrame("Frame", nil, page)
    listFrame:SetPoint("TOPLEFT", page, "TOPLEFT", 12, y)
    listFrame:SetSize(510, 112)
    T().Bg(listFrame, T().c.panelAlt, T().c.border)
    self.linkedAltListFrame = listFrame

    local altScroll = CreateFrame("ScrollFrame", nil, listFrame)
    altScroll:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 4, -4)
    altScroll:SetPoint("BOTTOMRIGHT", listFrame, "BOTTOMRIGHT", -4, 4)
    altScroll:EnableMouseWheel(true)
    altScroll:SetScript("OnMouseWheel", function(self, delta)
        clampScroll(self, delta, 22)
    end)
    local altContent = CreateFrame("Frame", nil, altScroll)
    altContent:SetWidth(500)
    altScroll:SetScrollChild(altContent)
    self.linkedAltScroll = altScroll
    self.linkedAltContent = altContent
    self.linkedAltRows = {}
    self.linkedAltEmpty = T().Fs(listFrame, "data", "No alts linked.", "textDimmed")
    self.linkedAltEmpty:SetPoint("CENTER", listFrame, "CENTER", 0, 0)
    y = y - 126

    y = makeSection(page, "ADD ALT", y)
    self.addAltBox = makeInput(page, "Add Alt", 12, y, 300)
    self.addAltHint = T().Fs(page, "input", "Type alt character name...", "textDimmed")
    self.addAltHint:SetPoint("LEFT", self.addAltBox, "LEFT", 7, 0)
    self.addAltBtn = GC.UI.Button.Create(page, "Add Alt", "secondary", 92, T().btnH)
    self.addAltBtn:SetPoint("TOPLEFT", page, "TOPLEFT", 324, y - 16)
    self.addAltBtn:SetEnabled(false)
    self.addAltBtn:SetScript("OnClick", function() ECP:_queueAddAlt() end)
    self.addAltValidation = T().Fs(page, "tiny", "", "textWarn")
    self.addAltValidation:SetPoint("TOPLEFT", page, "TOPLEFT", 12, y - 48)
    self.addAltTargetHint = T().Fs(page, "tiny", "", "textDimmed")
    self.addAltTargetHint:SetPoint("TOPLEFT", page, "TOPLEFT", 12, y - 56)

    self.addAltDropdown = CreateFrame("Frame", nil, page)
    self.addAltDropdown:SetPoint("TOPLEFT", self.addAltBox, "BOTTOMLEFT", 0, -4)
    self.addAltDropdown:SetSize(410, 240)
    if GC.UI.FrameLayering then
        GC.UI.FrameLayering:PrepareChildPopupFrame(self.addAltDropdown, page, 20)
    else
        self.addAltDropdown:SetFrameLevel(page:GetFrameLevel() + 20)
    end
    T().Bg(self.addAltDropdown, T().c.panel, T().c.borderAccent)
    self.addAltDropdown:Hide()
    self.addAltResults = {}
    for i = 1, 8 do
        local row = CreateFrame("Button", nil, self.addAltDropdown)
        row:SetSize(402, 26)
        row:SetPoint("TOPLEFT", self.addAltDropdown, "TOPLEFT", 4, -4 - ((i - 1) * 28))
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        local rc = T().c.panelAlt
        row.bg:SetColorTexture(rc[1], rc[2], rc[3], rc[4] or 1)
        row.text = T().Fs(row, "data", "", "textSecond")
        row.text:SetPoint("LEFT", row, "LEFT", 8, 0)
        row:SetScript("OnEnter", function(self)
            local hc = T().c.panelHover
            self.bg:SetColorTexture(hc[1], hc[2], hc[3], hc[4] or 1)
        end)
        row:SetScript("OnLeave", function(self)
            local nc = T().c.panelAlt
            self.bg:SetColorTexture(nc[1], nc[2], nc[3], nc[4] or 1)
        end)
        row:Hide()
        self.addAltResults[i] = row
    end
    self.addAltBox:SetScript("OnTextChanged", function()
        ECP:_refreshAltAutocomplete()
    end)
    self.addAltBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        ECP.addAltDropdown:Hide()
    end)
    y = y - 84

    y = makeSection(page, "ROLE ACTIONS", y)
    self.roleActionsY = y
    self.mainBtn = GC.UI.Button.Create(page, "Mark as Main", "secondary", 120, T().btnH)
    self.mainBtn:SetPoint("TOPLEFT", page, "TOPLEFT", 12, y)
    self.mainBtn:SetScript("OnClick", function() markPendingAction("main", "Mark as Main") end)
    self.altBtn = GC.UI.Button.Create(page, "Mark as Alt", "secondary", 120, T().btnH)
    self.altBtn:SetPoint("LEFT", self.mainBtn, "RIGHT", 8, 0)
    self.altBtn:SetTooltip("Mark as Alt", "Enter or select the target main in Add Alt, then click this button.")
    self.altBtn:SetScript("OnClick", function() ECP:_queueMarkCurrentAlt() end)
    self.unknownBtn = GC.UI.Button.Create(page, "Mark Unknown", "secondary", 120, T().btnH)
    self.unknownBtn:SetPoint("LEFT", self.altBtn, "RIGHT", 8, 0)
    self.unknownBtn:SetScript("OnClick", function() markPendingAction("unknown", "Mark as Unknown") end)
    self.unlinkCurrentBtn = GC.UI.Button.Create(page, "Remove Link", "danger", 112, T().btnH)
    self.unlinkCurrentBtn:SetPoint("LEFT", self.unknownBtn, "RIGHT", 8, 0)
    self.unlinkCurrentBtn:SetScript("OnClick", function()
        showConfirm("GUILDCORE_EDIT_CHARACTER_UNLINK_CURRENT", "Queue removal of the alt link for the current character?", function()
            markPendingAction("unlink", "Remove Current Alt Link")
        end)
    end)
    y = y - 40
    page:SetHeight(math.abs(y) + 20)
end

function ECP:_buildSecurityPage(page)
    local y = -10
    y = makeSection(page, "SECURITY / TAGS", y)
    self.securityTagsBox = makeInput(page, "Security Tags", 12, y, 500); y = y - 48
    local protectedBtn = GC.UI.Button.Create(page, "PROTECTED", "secondary", 98, T().btnH)
    protectedBtn:SetPoint("TOPLEFT", page, "TOPLEFT", 12, y)
    protectedBtn:SetScript("OnClick", function() addTagToBox(self.securityTagsBox, "PROTECTED") end)
    local leaveBtn = GC.UI.Button.Create(page, "LEAVE", "secondary", 74, T().btnH)
    leaveBtn:SetPoint("LEFT", protectedBtn, "RIGHT", 8, 0)
    leaveBtn:SetScript("OnClick", function() addTagToBox(self.securityTagsBox, "LEAVE") end)
    local officerAltBtn = GC.UI.Button.Create(page, "OFFICER ALT", "secondary", 112, T().btnH)
    officerAltBtn:SetPoint("LEFT", leaveBtn, "RIGHT", 8, 0)
    officerAltBtn:SetScript("OnClick", function() addTagToBox(self.securityTagsBox, "OFFICER ALT") end)
    local dnkBtn = GC.UI.Button.Create(page, "DO NOT KICK", "secondary", 122, T().btnH)
    dnkBtn:SetPoint("LEFT", officerAltBtn, "RIGHT", 8, 0)
    dnkBtn:SetScript("OnClick", function() addTagToBox(self.securityTagsBox, "DO NOT KICK") end)
    y = y - 48
    page:SetHeight(math.abs(y) + 20)
end

function ECP:_buildActionsPage(page)
    local y = -10
    y = makeSection(page, "RANK ACTIONS", y)
    self.promoteBtn = GC.UI.Button.Create(page, "Promote", "success", 138, T().btnH)
    self.promoteBtn:SetPoint("TOPLEFT", page, "TOPLEFT", 12, y)
    self.promoteBtn:SetScript("OnClick", function() ECP:_confirmRankAction("promote") end)
    self.demoteBtn = GC.UI.Button.Create(page, "Demote", "warning", 138, T().btnH)
    self.demoteBtn:SetPoint("LEFT", self.promoteBtn, "RIGHT", 8, 0)
    self.demoteBtn:SetScript("OnClick", function() ECP:_confirmRankAction("demote") end)
    -- Target-rank dropdowns need safe multi-step macro validation first; the
    -- operations service currently supports one protected rank jump at a time.
    y = y - 50

    y = makeSection(page, "DANGER ZONE", y)
    self.dangerHint = T().Fs(page, "tiny", "Danger actions prepare guild removal or moderation changes immediately after confirmation.", "textWarn")
    self.dangerHint:SetPoint("TOPLEFT", page, "TOPLEFT", 12, y)
    self.dangerHint:SetPoint("RIGHT", page, "RIGHT", -12, 0)
    self.dangerHint:SetWordWrap(true)
    y = y - 30
    self.kickBtn = GC.UI.Button.Create(page, "Kick", "danger", 138, T().btnH)
    self.kickBtn:SetPoint("TOPLEFT", page, "TOPLEFT", 12, y)
    self.kickBtn:SetScript("OnClick", function() ECP:_confirmKick() end)
    y = y - 58

    y = makeSection(page, "BAN BOOK", y)
    self.banReasonBox = makeInput(page, "Ban Book Reason", 12, y, 500); y = y - 48
    self.banNotesBox = makeInput(page, "Ban Book Notes", 12, y, 500); y = y - 54
    self.banBtn = GC.UI.Button.Create(page, "Add to Ban Book", "danger", 190, T().btnH)
    self.banBtn:SetPoint("TOPLEFT", page, "TOPLEFT", 12, y)
    self.banBtn:SetScript("OnClick", function() ECP:_confirmBanBookAdd() end)
    y = y - 54
    page:SetHeight(math.abs(y) + 20)
end

function ECP:_buildHistoryPage(page)
    local y = -10
    y = makeSection(page, "ACTIVITY / HISTORY", y)
    self.historySummary = T().Fs(page, "data", "No history entries found.", "textSecond")
    self.historySummary:SetPoint("TOPLEFT", page, "TOPLEFT", 12, y)
    self.historySummary:SetPoint("RIGHT", page, "RIGHT", -12, 0)
    self.historySummary:SetWordWrap(true)
    page:SetHeight(160)
end

local function setActionButtonState(button, availability, fallbackReason)
    if not button then return end
    availability = availability or {}
    local enabled = availability.enabled == true
    button:SetEnabled(enabled)
    if button.SetTooltip then
        button:SetTooltip(enabled and nil or "Action unavailable", enabled and nil or (availability.reason or fallbackReason))
    end
end

function ECP:_refreshOfficerActionViews(live)
    live = live or ensureLivePlayer()
    local operations = GC.Services and GC.Services.Operations
    local availability = operations and operations.GetActionAvailability and operations:GetActionAvailability(live) or {
        promote = { enabled = false, reason = "Operations service is unavailable." },
        demote = { enabled = false, reason = "Operations service is unavailable." },
        kick = { enabled = false, reason = "Operations service is unavailable." },
    }
    setActionButtonState(self.promoteBtn, availability.promote, "Promotion is unavailable.")
    setActionButtonState(self.demoteBtn, availability.demote, "Demotion is unavailable.")
    setActionButtonState(self.kickBtn, availability.kick, "Guild removal is unavailable.")

    local canModerate = GC.Permissions and GC.Permissions.IsOfficerOrBetter and GC.Permissions:IsOfficerOrBetter()
    setActionButtonState(self.banBtn, {
        enabled = canModerate and live ~= nil and GC.BanBook ~= nil,
        reason = not canModerate and "Officer permission required." or "Ban Book is unavailable.",
    }, "Ban Book is unavailable.")
end

function ECP:_refreshAfterOfficerAction(options)
    options = options or {}
    if options.scan and GS() and GS().TriggerScan then
        GS():TriggerScan()
    end
    if GC.UI and GC.UI.PlayerPanel and GC.UI.PlayerPanel.Refresh then
        GC.UI.PlayerPanel:Refresh()
    end
    if GC.UI and GC.UI.RosterPanel and GC.UI.RosterPanel.Refresh then
        GC.UI.RosterPanel:Refresh()
    end
    if GC.UI and GC.UI.Dashboard and GC.UI.Dashboard.Refresh then
        GC.UI.Dashboard:Refresh()
    end
    if GC.UI and GC.UI.LogPanel and GC.UI.LogPanel.Refresh then
        GC.UI.LogPanel:Refresh()
    end
    if GC.UI and GC.UI.BanBookPanel and GC.UI.BanBookPanel.Refresh then
        GC.UI.BanBookPanel:Refresh()
    end
    if GC.UI and GC.UI.PurgePanel and GC.UI.PurgePanel.Refresh then
        GC.UI.PurgePanel:Refresh()
    end
    self:_refreshOfficerActionViews(ensureLivePlayer())
    self:_refreshHistory(ensureLivePlayer())
end

function ECP:_confirmRankAction(action)
    local live = ensureLivePlayer()
    local operations = GC.Services and GC.Services.Operations
    if not live or not operations then
        status("Rank action is unavailable.", "textDanger")
        return
    end

    local isPromote = action == "promote"
    local verb = isPromote and "Promote" or "Demote"
    local availability = operations:GetActionAvailability(live)
    local allowed = availability and availability[action]
    if not allowed or not allowed.enabled then
        status((allowed and allowed.reason) or (verb .. " is unavailable."), "textDanger")
        self:_refreshOfficerActionViews(live)
        return
    end

    -- WoW's supported rank path is a protected one-step /gpromote or
    -- /gdemote macro. A target-rank dropdown needs safe multi-step macro
    -- validation before it can be offered here.
    showConfirm("GUILDCORE_EDIT_CHARACTER_RANK_ACTION", verb .. " " .. tostring(live.key or live.name) .. "?", function()
        local ok, message
        if isPromote then
            ok, message = operations:Promote(live)
        else
            ok, message = operations:Demote(live)
        end
        if ok then
            status(string.format("%s ready for %s. %s", verb, tostring(live.key or live.name), tostring(message or "Use the guild action hotkey to execute.")), "textWarn")
            ECP:_refreshAfterOfficerAction()
        else
            status(message or (verb .. " could not be prepared."), "textDanger")
            ECP:_refreshOfficerActionViews(live)
        end
    end)
end

function ECP:_confirmKick()
    local live = ensureLivePlayer()
    local operations = GC.Services and GC.Services.Operations
    if not live or not operations then
        status("Guild removal is unavailable.", "textDanger")
        return
    end

    local availability = operations:GetActionAvailability(live)
    if not availability or not availability.kick or not availability.kick.enabled then
        status((availability and availability.kick and availability.kick.reason) or "Guild removal is unavailable.", "textDanger")
        self:_refreshOfficerActionViews(live)
        return
    end

    showConfirm("GUILDCORE_EDIT_CHARACTER_KICK", "Kick " .. tostring(live.key or live.name) .. " from the guild?", function()
        local ok, message = operations:Kick(live)
        if ok then
            status("Kick queued for " .. tostring(live.key or live.name) .. ". " .. tostring(message or "Build and execute the guild removal action."), "textWarn")
            ECP:_refreshAfterOfficerAction()
        else
            status(message or "Unable to prepare guild removal.", "textDanger")
            ECP:_refreshOfficerActionViews(live)
        end
    end)
end

function ECP:_confirmBanBookAdd()
    local live = ensureLivePlayer()
    if not live or not GC.BanBook then
        status("Ban Book is unavailable.", "textDanger")
        return
    end
    if not (GC.Permissions and GC.Permissions.IsOfficerOrBetter and GC.Permissions:IsOfficerOrBetter()) then
        status("Officer permission required.", "textDanger")
        self:_refreshOfficerActionViews(live)
        return
    end

    local reason = trim(self.banReasonBox and self.banReasonBox:GetText() or "")
    local notes = self.banNotesBox and self.banNotesBox:GetText() or ""
    if reason == "" then
        status("Ban Book reason is required.", "textDanger")
        return
    end

    showConfirm("GUILDCORE_EDIT_CHARACTER_BAN", "Add " .. tostring(live.key or live.name) .. " to Ban Book?", function()
        local ok, entryOrError, updated = GC.BanBook:Add(live.name, live.realm, reason, notes)
        if not ok then
            status(entryOrError or "Unable to add Ban Book entry.", "textDanger")
            return
        end
        if DS() and DS().AppendLog then
            DS():AppendLog({
                timestamp = GC.Utils and GC.Utils.Now and GC.Utils.Now() or time(),
                event = "BAN_BOOK",
                playerKey = live.key,
                oldValue = updated and "existing" or nil,
                newValue = entryOrError and entryOrError.key or live.key,
                reason = reason,
            })
        end
        status((updated and "Ban Book entry updated for " or "Added to Ban Book: ") .. tostring(entryOrError.key or live.key or live.name), "textSuccess")
        ECP:_refreshAfterOfficerAction()
    end)
end

function ECP:_refreshHistory(live)
    if not self.historySummary then return end
    live = live or ensureLivePlayer()
    if not live or not GS() or not GS().GetRecentLogs then
        self.historySummary:SetText("No history entries found.")
        return
    end

    local lines = {}
    for _, entry in ipairs(GS():GetRecentLogs(250) or {}) do
        if entry and entry.playerKey == live.key then
            local when = tonumber(entry.timestamp) and date("%Y-%m-%d %H:%M", entry.timestamp) or "Unknown time"
            lines[#lines + 1] = string.format("%s  %s%s", when, tostring(entry.event or "EVENT"), entry.reason and ("  " .. tostring(entry.reason)) or "")
            if #lines >= 8 then break end
        end
    end
    self.historySummary:SetText(#lines > 0 and table.concat(lines, "\n") or "No history entries found.")
end

function ECP:_setAddAltValidation(message)
    if self.addAltValidation then
        self.addAltValidation:SetText(message or "")
    end
end

function ECP:_resolveAddAltKey(text)
    text = trim(text or "")
    if text == "" then return nil end
    if draft and draft.addAltKey and self.addAltBox and self.addAltBox:GetText() == (draft.addAltText or "") then
        return draft.addAltKey
    end
    local resolved = GS():ResolvePlayerKey(text)
    return activeRosterPlayer(resolved) and resolved or nil
end

function ECP:_altSearchMatches(player, query)
    if not player or query == "" then return false end
    local q = query:lower()
    local values = {
        player.name,
        player.key,
        player.realm,
        player.fullName,
    }
    for _, value in ipairs(values) do
        value = tostring(value or ""):lower()
        if value ~= "" and value:find(q, 1, true) then
            return true
        end
    end
    return false
end

function ECP:_getAltMatches(query)
    local matches = {}
    query = trim(query or "")
    if query == "" then return matches end

    for _, player in ipairs(self.altCandidateCache or GS():GetRosterList() or {}) do
        if player.key ~= currentKey and self:_altSearchMatches(player, query) then
            matches[#matches + 1] = player
            if #matches >= 8 then
                break
            end
        end
    end
    return matches
end

function ECP:_selectAddAlt(player)
    if not player or not player.key then return end
    draft.addAltKey = player.key
    draft.addAltText = player.key
    self.addAltBox:SetText(player.key)
    self.addAltBox:ClearFocus()
    self.addAltDropdown:Hide()
    self.addAltHint:Hide()
    self.addAltBtn:SetEnabled(true)
    self:_setAddAltValidation("")
end

function ECP:_collectRelationshipGroup(seedKey)
    local keys, mains, seen = {}, {}, {}

    local function visit(key)
        if not key or seen[key] then return end
        local player = activeRosterPlayer(key)
        if not player then return end
        seen[key] = true
        keys[#keys + 1] = key

        if player.classification == "main" or (player.alts and #player.alts > 0) then
            addUnique(mains, key)
        end
        if player.main then
            visit(player.main)
        end
        for _, altKey in ipairs(player.alts or {}) do
            visit(altKey)
        end
    end

    visit(currentKey)
    visit(seedKey)
    return keys, mains
end

function ECP:_showMainPicker(mainKeys, onPick)
    if not self.mainPicker then
        local frame = CreateFrame("Frame", "GuildCoreAltMainPicker", UIParent)
        frame:SetSize(360, 120)
        frame:SetPoint("CENTER")
        if GC.UI.FrameLayering then
            GC.UI.FrameLayering:PreparePopupFrame(frame, self.frame or (GC.UI.MainFrame and GC.UI.MainFrame.frame), 90)
        else
            frame:SetFrameStrata("DIALOG")
        end
        frame:EnableMouse(true)
        frame:SetClampedToScreen(true)
        T().Bg(frame, T().c.panel, T().c.borderAccent)
        frame.title = T().Fs(frame, "subheader", "Choose Actual Main", "textAccent")
        frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -12)
        frame.body = T().Fs(frame, "data", "Multiple linked characters are marked as Main.", "textSecond")
        frame.body:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -8)
        frame.body:SetPoint("RIGHT", frame, "RIGHT", -12, 0)
        frame.cancel = GC.UI.Button.Create(frame, "Cancel", "secondary", 72, T().btnH)
        frame.cancel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 12)
        frame.cancel:SetScript("OnClick", function() frame:Hide() end)
        frame.buttons = {}
        frame:Hide()
        self.mainPicker = frame
    end

    local frame = self.mainPicker
    for _, btn in ipairs(frame.buttons or {}) do
        btn:Hide()
    end

    frame:SetHeight(104 + (#mainKeys * 34))
    frame.body:SetText("Multiple linked characters are marked as Main. Pick the actual main for this group.")
    for i, key in ipairs(mainKeys or {}) do
        local btn = frame.buttons[i]
        if not btn then
            btn = GC.UI.Button.Create(frame, "", "secondary", 230, T().btnH)
            frame.buttons[i] = btn
        end
        btn:SetLabel(key)
        btn:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -58 - ((i - 1) * 34))
        btn:SetScript("OnClick", function()
            frame:Hide()
            onPick(key)
        end)
        btn:Show()
    end
    frame.cancel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 12)
    frame:Show()
end

function ECP:_queueAltGroup(mainKey, keys)
    if not draft then return end
    local queued = 0
    local previousMain = draft.mainOverride
    draft.addAltKeys = draft.addAltKeys or {}
    draft.addAltOrder = draft.addAltOrder or {}
    draft.mainOverride = mainKey or currentKey

    for _, key in ipairs(keys or {}) do
        if key ~= draft.mainOverride and not (draft.removeAltKeys and draft.removeAltKeys[key]) then
            if not draft.addAltKeys[key] then
                draft.addAltKeys[key] = true
                draft.addAltOrder[#draft.addAltOrder + 1] = key
                queued = queued + 1
            end
        end
    end

    if queued == 0 then
        draft.mainOverride = previousMain
        self:_setAddAltValidation("Those characters are already in the staged alt list.")
        return
    end

    draft.addAltKey = nil
    draft.addAltText = ""
    self.addAltBox:SetText("")
    self.addAltHint:Show()
    self.addAltDropdown:Hide()
    self.addAltBtn:SetEnabled(false)
    markPendingAction("addAlt", "Add " .. tostring(#draft.addAltOrder) .. " Alt" .. (#draft.addAltOrder == 1 and "" or "s"))
    self:_refreshAltDisplay(ensureLivePlayer())
    self:_setAddAltValidation("Queued " .. tostring(queued) .. " alt" .. (queued == 1 and "" or "s") .. ". Click Save to apply.")
end

function ECP:_refreshAltAutocomplete()
    if not self.addAltBox then return end
    local text = self.addAltBox:GetText() or ""
    if self.addAltHint then
        self.addAltHint:SetShown(trim(text) == "")
    end

    if draft then
        draft.addAltText = text
        if draft.addAltKey and text ~= draft.addAltKey then
            draft.addAltKey = nil
        end
    end

    local exact = self:_resolveAddAltKey(text)
    self.addAltBtn:SetEnabled(exact ~= nil)
    self:_setAddAltValidation(text ~= "" and not exact and "Choose a guild character from the list." or "")

    local matches = self:_getAltMatches(text)
    local showDropdown = #matches > 0 and self.addAltBox:HasFocus()
    self.addAltDropdown:SetShown(showDropdown)

    for i, row in ipairs(self.addAltResults or {}) do
        local player = matches[i]
        if player then
            local display = string.format(
                "%s  %s  %s  %s",
                player.key or player.name or "-",
                player.classDisplayName or player.class or "-",
                player.rankShort or player.rankName or "-",
                roleLabel(player)
            )
            row.text:SetText(display)
            local rgb = playerClassColor(player)
            row.text:SetTextColor(rgb[1], rgb[2], rgb[3], rgb[4] or 1)
            local selected = player
            row:SetScript("OnClick", function() ECP:_selectAddAlt(selected) end)
            row:Show()
        else
            row:Hide()
        end
    end
end

function ECP:_queueAddAlt()
    local live = ensureLivePlayer()
    if not live or not draft then return end

    local altKey = self:_resolveAddAltKey(self.addAltBox:GetText() or "")
    if not altKey then
        self:_setAddAltValidation("Pick a valid guild character before adding an alt.")
        return
    end
    if altKey == live.key then
        self:_setAddAltValidation("A character cannot be linked to itself.")
        return
    end

    local altPlayer = activeRosterPlayer(altKey)
    if not altPlayer then
        self:_setAddAltValidation("That character is not in the active roster cache.")
        return
    end
    if altPlayer.main == live.key or (draft.addAltKeys and draft.addAltKeys[altKey]) then
        self:_setAddAltValidation(altKey .. " is already linked to this main.")
        return
    end

    local keys, mains = self:_collectRelationshipGroup(altKey)
    if #mains > 1 then
        self:_showMainPicker(mains, function(chosenMain)
            ECP:_queueAltGroup(chosenMain, keys)
        end)
        return
    end

    self:_queueAltGroup(mains[1] or live.key, keys)
end

function ECP:_queueMarkCurrentAlt()
    local live = ensureLivePlayer()
    if not live or not draft then return end

    local mainKey = self:_resolveAddAltKey(self.addAltBox and self.addAltBox:GetText() or "")
    if not mainKey then
        self:_setAddAltValidation("Enter or select the target main in Add Alt before marking this character as Alt.")
        status("Choose a target main first.", "textWarn")
        return
    end
    if mainKey == live.key then
        self:_setAddAltValidation("A character cannot be its own main.")
        return
    end
    if not activeRosterPlayer(mainKey) then
        self:_setAddAltValidation("Target main is not in the active roster cache.")
        return
    end

    draft.mainOverride = mainKey
    markPendingAction("alt", "Mark as Alt")
    self:_setAddAltValidation("Queued current character as an Alt of " .. tostring(mainKey) .. ". Click Save to apply.")
    self:_refreshAltDisplay(live)
end

function ECP:_queueRemoveLinkedAlt(altKey)
    if not draft or not altKey then return end
    if draft.addAltKeys and draft.addAltKeys[altKey] then
        draft.addAltKeys[altKey] = nil
        for i = #draft.addAltOrder, 1, -1 do
            if draft.addAltOrder[i] == altKey then
                table.remove(draft.addAltOrder, i)
            end
        end
        if not self:_hasQueuedAltAdds() then
            draft.mainOverride = nil
            if draft.pendingAction == "addAlt" then
                markPendingAction(nil, nil)
            end
        else
            markPendingAction("addAlt", "Add " .. tostring(#draft.addAltOrder) .. " Alt" .. (#draft.addAltOrder == 1 and "" or "s"))
        end
        self:_refreshAltDisplay(ensureLivePlayer())
        status("Removed staged alt link.", "textWarn")
        return
    end

    draft.removeAltKeys = draft.removeAltKeys or {}
    draft.removeAltKeys[altKey] = true
    self:_refreshAltDisplay(ensureLivePlayer())
    status("Queued alt link removal. Click Save to apply.", "textWarn")
end

function ECP:_confirmQueueRemoveLinkedAlt(altKey)
    local live = ensureLivePlayer()
    local group = live and GC.AltMain and GC.AltMain:GetGroup(live.key) or nil
    local targetKey = altKey
    if group and altKey == group.mainKey and live and live.key ~= group.mainKey then
        targetKey = live.key
    end
    showConfirm("GUILDCORE_EDIT_CHARACTER_REMOVE_ALT_LINK", "Queue removal of the alt link for " .. tostring(targetKey) .. "?", function()
        ECP:_queueRemoveLinkedAlt(targetKey)
    end)
end

function ECP:_openLinkedAlt(altKey)
    local player = activeRosterPlayer(altKey)
    if not player then
        status("Character is not in the active roster cache.", "textWarn")
        return
    end
    if GC.UI and GC.UI.RosterPanel and GC.UI.RosterPanel.FocusCharacter then
        local ok, err = GC.UI.RosterPanel:FocusCharacter(altKey)
        if ok then return end
        if err then status(err, "textWarn") end
    end
    self:Open(player)
end

function ECP:_showLinkedAltMenu(altKey)
    if not self.linkedAltMenu then
        local menu = CreateFrame("Frame", "GuildCoreEditCharacterAltMenu", UIParent)
        menu:SetSize(170, 98)
        if GC.UI.FrameLayering then
            GC.UI.FrameLayering:PreparePopupFrame(menu, self.frame or (GC.UI.MainFrame and GC.UI.MainFrame.frame), 95)
        else
            menu:SetFrameStrata("DIALOG")
        end
        menu:SetClampedToScreen(true)
        T().Bg(menu, T().c.panel, T().c.borderAccent)
        menu.buttons = {}
        local labels = {"Open Character", "Copy Name-Realm", "Remove Alt Link"}
        for i, label in ipairs(labels) do
            local btn = GC.UI.Button.Create(menu, label, i == 3 and "danger" or "secondary", 150, 24)
            btn:SetPoint("TOPLEFT", menu, "TOPLEFT", 10, -8 - ((i - 1) * 29))
            menu.buttons[i] = btn
        end
        menu:Hide()
        self.linkedAltMenu = menu
    end

    local menu = self.linkedAltMenu
    menu.buttons[1]:SetScript("OnClick", function()
        menu:Hide()
        ECP:_openLinkedAlt(altKey)
    end)
    menu.buttons[2]:SetScript("OnClick", function()
        menu:Hide()
        copyText(altKey)
    end)
    menu.buttons[3]:SetScript("OnClick", function()
        menu:Hide()
        ECP:_confirmQueueRemoveLinkedAlt(altKey)
    end)
    local scale = UIParent:GetEffectiveScale()
    local x, y = GetCursorPosition()
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    menu:Show()
end

function ECP:_getLinkedAltRow(index)
    self.linkedAltRows = self.linkedAltRows or {}
    if self.linkedAltRows[index] then
        return self.linkedAltRows[index]
    end

    local row = CreateFrame("Button", nil, self.linkedAltContent)
    row:SetSize(246, 21)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    local c = T().c.panelAlt
    row.bg:SetColorTexture(c[1], c[2], c[3], 0.25)
    row.name = T().Fs(row, "data", "", "textSecond")
    row.name:SetPoint("LEFT", row, "LEFT", 8, 0)
    row.name:SetWidth(158)
    row.name:SetJustifyH("LEFT")
    row.meta = T().Fs(row, "tiny", "", "textDimmed")
    row.meta:SetPoint("LEFT", row.name, "RIGHT", 4, 0)
    row.meta:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.meta:SetJustifyH("LEFT")
    row:SetScript("OnEnter", function(self)
        local hc = T().c.panelHover
        self.bg:SetColorTexture(hc[1], hc[2], hc[3], hc[4] or 1)
    end)
    row:SetScript("OnLeave", function(self)
        local nc = T().c.panelAlt
        self.bg:SetColorTexture(nc[1], nc[2], nc[3], 0.25)
    end)
    row:SetScript("OnClick", function(self, button)
        local altKey = self._altKey
        if not altKey then return end
        if button == "RightButton" then
            local player = activeRosterPlayer(altKey)
            if GC.UI and GC.UI.CharacterContextMenu and player then
                player.source = "Edit Character Linked Alts"
                GC.UI.CharacterContextMenu:Open(player)
            else
                ECP:_showLinkedAltMenu(altKey)
            end
        else
            ECP:_openLinkedAlt(altKey)
        end
    end)
    self.linkedAltRows[index] = row
    return row
end

function ECP:_hasQueuedAltRemovals()
    if not draft or not draft.removeAltKeys then return false end
    for _, remove in pairs(draft.removeAltKeys) do
        if remove then return true end
    end
    return false
end

function ECP:_hasQueuedAltAdds()
    if not draft or not draft.addAltKeys then return false end
    for _, add in pairs(draft.addAltKeys) do
        if add then return true end
    end
    return false
end

function ECP:_refreshAltDisplay(live)
    if not live then return end
    local group = GC.AltMain and GC.AltMain:GetGroup(live.key) or {
        mainKey = live.main or live.key,
        role = roleLabel(live),
        members = {live.key},
        alts = live.alts or {},
    }
    self.altCurrentCharacter:SetText("Current Character: " .. tostring(live.key or live.name or "-"))
    local effectiveMain = draft and draft.mainOverride or group.mainKey or live.key
    local currentRole = effectiveMain == live.key and "Main" or (group.role or roleLabel(live))
    self.altCurrentRole:SetText("Current Role: " .. currentRole)
    self.altLinkedMain:SetShown(effectiveMain ~= live.key)
    self.altLinkedMain:SetText("Linked Main: " .. tostring(effectiveMain ~= live.key and effectiveMain or "-"))
    if self.linkedAltSectionTitle then
        self.linkedAltSectionTitle:SetText(effectiveMain == live.key and "LINKED ALTS" or "CONNECTED CHARACTERS")
    end
    if self.addAltTargetHint then
        self.addAltTargetHint:SetText("New alts will be linked to main: " .. tostring(effectiveMain))
    end

    local visible = 0
    local displayKeys = {}
    if effectiveMain == live.key then
        for _, altKey in ipairs(group.alts or {}) do
            addUnique(displayKeys, altKey)
        end
    else
        for _, memberKey in ipairs(group.members or {}) do
            if memberKey ~= live.key then
                addUnique(displayKeys, memberKey)
            end
        end
    end
    for _, altKey in ipairs((draft and draft.addAltOrder) or {}) do
        if altKey ~= live.key then
            addUnique(displayKeys, altKey)
        end
    end

    for _, altKey in ipairs(displayKeys) do
        if altKey ~= live.key and not (draft and draft.removeAltKeys and draft.removeAltKeys[altKey]) then
            visible = visible + 1
            local row = self:_getLinkedAltRow(visible)
            local player = activeRosterPlayer(altKey)
            local staged = draft and draft.addAltKeys and draft.addAltKeys[altKey]
            local color = staged and T().c.textSuccess or playerClassColor(player)
            local column = (visible - 1) % 2
            local rowIndex = math.floor((visible - 1) / 2)
            row._altKey = altKey
            row:SetPoint("TOPLEFT", self.linkedAltContent, "TOPLEFT", column * 250, -(rowIndex * 22))
            row.name:SetText((staged and "+ " or "") .. altKey)
            row.name:SetTextColor(color[1], color[2], color[3], color[4] or 1)
            row.meta:SetText(player and (player.rankShort or player.rankName or "-") or "-")
            row:Show()
        end
    end

    for i, row in ipairs(self.linkedAltRows or {}) do
        if i > visible then
            row._altKey = nil
            row:Hide()
        end
    end
    self.linkedAltEmpty:SetShown(visible == 0)
    if self.linkedAltContent then
        self.linkedAltContent:SetHeight(math.max(1, math.ceil(visible / 2) * 22))
    end
    if self.linkedAltScroll then
        clampScroll(self.linkedAltScroll, 0, 22)
    end

    if self.mainBtn then
        self.mainBtn:SetShown(true)
        self.mainBtn:SetEnabled(effectiveMain ~= live.key or live.classification ~= "main")
    end
    if self.altBtn then
        self.altBtn:SetShown(true)
        self.altBtn:SetEnabled(true)
    end
    if self.unknownBtn then
        self.unknownBtn:SetShown(true)
        self.unknownBtn:SetEnabled(live.classification ~= "unknown")
    end
    if self.unlinkCurrentBtn then
        self.unlinkCurrentBtn:SetShown(effectiveMain ~= live.key)
        self.unlinkCurrentBtn:ClearAllPoints()
        self.unlinkCurrentBtn:SetPoint("LEFT", self.unknownBtn, "RIGHT", 8, 0)
    end
end

function ECP:Create()
    if self.frame then return end
    local Th = T()
    local frame = CreateFrame("Frame", "GuildCoreEditCharacterPopup", UIParent)
    frame:SetSize(560, 620)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)
    if GC.UI.FrameLayering then
        GC.UI.FrameLayering:PreparePopupFrame(frame, GC.UI.MainFrame and GC.UI.MainFrame.frame, 70)
    else
        frame:SetFrameStrata("DIALOG")
    end
    Th.Bg(frame, Th.c.panel, Th.c.borderAccent)
    frame:Hide()
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    self.frame = frame

    local title = Th.Fs(frame, "subheader", "Edit Character", "textAccent")
    title:SetPoint("TOPLEFT", 14, -12)
    self.title = title

    self.tabButtons = {}
    self.pages = {}
    local tabs = {
        { id = "general", label = "General" },
        { id = "alts", label = "Main / Alt" },
        { id = "security", label = "Security" },
        { id = "actions", label = "Actions" },
        { id = "history", label = "History" },
    }
    for i, tab in ipairs(tabs) do
        local btn = GC.UI.Button.Create(frame, tab.label, i == 1 and "primary" or "secondary", 96, Th.btnH)
        btn:SetPoint("TOPLEFT", frame, "TOPLEFT", 12 + (i - 1) * 104, -50)
        btn:SetScript("OnClick", function() ECP:_setTab(tab.id) end)
        self.tabButtons[tab.id] = btn

        local page = CreateFrame("Frame", nil, frame)
        page:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -90)
        page:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 58)
        page:Hide()
        self.pages[tab.id] = page
    end

    self:_buildGeneralPage(self.pages.general)
    self:_buildAltPage(self.pages.alts)
    self:_buildSecurityPage(self.pages.security)
    self:_buildActionsPage(self.pages.actions)
    self:_buildHistoryPage(self.pages.history)

    local footer = CreateFrame("Frame", nil, frame)
    footer:SetPoint("BOTTOMLEFT")
    footer:SetPoint("BOTTOMRIGHT")
    footer:SetHeight(50)
    Th.Bg(footer, Th.c.chrome, Th.c.border)
    local save = GC.UI.Button.Create(footer, "Save", "primary", 92, Th.btnH)
    save:SetPoint("RIGHT", footer, "RIGHT", -96, 0)
    save:SetScript("OnClick", function() ECP:Save() end)
    local cancel = GC.UI.Button.Create(footer, "Cancel", "secondary", 78, Th.btnH)
    cancel:SetPoint("RIGHT", footer, "RIGHT", -12, 0)
    cancel:SetScript("OnClick", function() ECP:Cancel() end)

    self:_setTab("general")
end

function ECP:GetObjectStats()
    return {
        built            = self.frame ~= nil,
        linkedAltRows    = #(self.linkedAltRows or {}),
        autocompleteRows = #(self.addAltResults or {}),
        openCount        = self._openCount or 0,
        isOpen           = self.frame ~= nil and self.frame:IsShown() or false,
    }
end

function ECP:Open(player)
    self:Create()
    player = type(player) == "table" and player or nil
    if not player then return end
    self._openCount = (self._openCount or 0) + 1
    currentKey = player.key
    local live = DS():GetPlayer(currentKey) or player
    self.altCandidateCache = GS():GetRosterList() or {}
    draft = {
        publicNote = live.publicNote or "",
        officerNote = live.officerNote or "",
        customNote = live.notes and live.notes.custom or "",
        tags = joinTags(live.notes and live.notes.tags or {}),
        discordName = live.officerData and live.officerData.discordName or "",
        joinDate = dateText(live.joinedAt),
        points = "",
        pointsReason = "",
        pendingAction = nil,
        addAltKey = nil,
        addAltText = "",
        addAltKeys = {},
        addAltOrder = {},
        mainOverride = nil,
        reassignFrom = nil,
        removeAltKeys = {},
    }

    self.title:SetText("Edit Character: " .. tostring(live.key or live.name or "Unknown"))
    self.publicNoteBox:SetText(draft.publicNote)
    self.officerNoteBox:SetText(draft.officerNote)
    self.customNoteBox:SetText(draft.customNote)
    self.discordBox:SetText(draft.discordName)
    self.joinDateBox:SetText(draft.joinDate)
    self.pointsBox:SetText("")
    self.pointsReasonBox:SetText("")
    self.securityTagsBox:SetText(draft.tags)
    self.addAltBox:SetText("")
    self.addAltHint:Show()
    self.addAltDropdown:Hide()
    self.addAltBtn:SetEnabled(false)
    self:_setAddAltValidation("")
    self.banReasonBox:SetText("")
    self.banNotesBox:SetText("")
    markPendingAction(nil, nil)

    self:_refreshAltDisplay(live)
    self:_refreshHistory(live)
    self:_refreshOfficerActionViews(live)
    self:_refreshNoteEditWarning(live)

    self.frame:Show()
    self:_setTab("general")
end

function ECP:Cancel()
    if self.frame then self.frame:Hide() end
    currentKey = nil
    draft = nil
end

function ECP:_applySafeChanges(live)
    local fields = {}
    live.notes = live.notes or {}
    live.officerData = live.officerData or {}

    local publicNote = self.publicNoteBox:GetText() or ""
    local officerNote = self.officerNoteBox:GetText() or ""
    if publicNote ~= (live.publicNote or "") then
        local ok, err = GC.API.SetGuildMemberNote(live.key, publicNote, false)
        if not ok then return false, err end
    end
    if officerNote ~= (live.officerNote or "") then
        local ok, err = GC.API.SetGuildMemberNote(live.key, officerNote, true)
        if not ok then return false, err end
    end

    live.notes.custom = self.customNoteBox:GetText() or ""
    live.notes.tags = splitTags(self.securityTagsBox:GetText() or "")
    live.officerData.discordName = trim(self.discordBox:GetText() or "")
    fields.notes = live.notes
    fields.officerData = live.officerData

    local joinTs, joinOk = parseDate(self.joinDateBox:GetText() or "")
    if not joinOk then return false, "Invalid join date. Use YYYY-MM-DD." end
    if joinTs then
        fields.joinedAt = joinTs
        fields.joinedAtSource = "manual"
    end

    DS():SavePlayer(live.key, fields)

    local points = tonumber(trim(self.pointsBox:GetText() or ""))
    if points and points ~= 0 and GC.Services.Points then
        local ok, err = GC.Services.Points:AddPoints(live.key, points, self.pointsReasonBox:GetText() or "Edit Character")
        if not ok then return false, err end
    end

    return true
end

function ECP:_applyPendingAction(live)
    if draft and draft.removeAltKeys then
        for altKey, remove in pairs(draft.removeAltKeys) do
            if remove then
                local altPlayer = DS():GetPlayer(altKey)
                if altPlayer and altPlayer.main then
                    local ok, err = GC.Services.Alts:UnlinkAlt(altKey, "edit-character")
                    if not ok then return false, err end
                end
            end
        end
    end

    local action = draft and draft.pendingAction
    if not action then return true end
    if action == "main" then
        return GC.Services.Alts:SetMain(live.key, "edit-character")
    elseif action == "alt" then
        local mainKey = draft and draft.mainOverride
        if not mainKey then return false, "Choose a target main before marking this character as Alt." end
        return GC.Services.Alts:SetAlt(live.key, mainKey, "edit-character")
    elseif action == "unknown" then
        return GC.Services.Alts:SetUnknown(live.key, "edit-character")
    elseif action == "unlink" then
        return GC.Services.Alts:UnlinkAlt(live.key, "edit-character")
    elseif action == "addAlt" then
        local mainKey = draft.mainOverride or live.key
        local mainPlayer = activeRosterPlayer(mainKey)
        if not mainPlayer then return false, "Selected main character is not in the active roster cache." end

        local groupKeys = {}
        for _, altKey in ipairs(draft.addAltOrder or {}) do
            if altKey ~= mainKey then
                local altPlayer = activeRosterPlayer(altKey)
                if not altPlayer then
                    return false, tostring(altKey) .. " is not in the active roster cache."
                end
                groupKeys[#groupKeys + 1] = altKey
            end
        end

        return GC.Services.Alts:NormalizeGroup(mainKey, groupKeys, "edit-character")
    end
    return true
end

function ECP:Save()
    local live = ensureLivePlayer()
    if not live then
        status("Character not found.", "textDanger")
        return
    end

    local function applyAll()
        local ok, err = self:_applySafeChanges(live)
        if not ok then status(err or "Unable to save character.", "textDanger"); return end
        ok, err = self:_applyPendingAction(live)
        if not ok then status(err or "Unable to apply pending action.", "textDanger"); return end
        if GS() then GS():TriggerScan() end
        if GC.UI.PlayerPanel then GC.UI.PlayerPanel:Refresh() end
        if GC.UI.RosterPanel then GC.UI.RosterPanel:Refresh() end
        if GC.UI.BanBookPanel and GC.UI.BanBookPanel.Refresh then GC.UI.BanBookPanel:Refresh() end
        if GC.UI.Dashboard and GC.UI.Dashboard.Refresh then GC.UI.Dashboard:Refresh() end
        status("Character changes saved.", "textSuccess")
        self:Cancel()
    end

    local function continueWithActionConfirm()
        local action = draft and draft.pendingAction
        local hasAltRemovals = self:_hasQueuedAltRemovals()
        local hasAltAdds = self:_hasQueuedAltAdds()
        if action == "addAlt" then
            local mainKey = draft and draft.mainOverride or live.key
            local count = draft and draft.addAltOrder and #draft.addAltOrder or 0
            showConfirm("GUILDCORE_EDIT_CHARACTER_LINKS", "Link " .. tostring(count) .. " alt" .. (count == 1 and "" or "s") .. " under " .. tostring(mainKey) .. "?", applyAll)
            return
        end
        if action == "main" or action == "alt" or action == "unknown" or action == "unlink" or hasAltRemovals or hasAltAdds then
            showConfirm("GUILDCORE_EDIT_CHARACTER_LINKS", "Apply main/alt change for " .. tostring(live.key or live.name) .. "?", applyAll)
            return
        end
        applyAll()
    end

    local publicNote = self.publicNoteBox:GetText() or ""
    local officerNote = self.officerNoteBox:GetText() or ""
    local noteChanged = publicNote ~= (live.publicNote or "") or officerNote ~= (live.officerNote or "")
    local noteAvailability = noteEditAvailability(live)
    if noteChanged and noteAvailability.protected then
        -- This warning is separate from rank action permissions. Blizzard may
        -- silently reject note edits against same-rank or higher-rank members,
        -- so the save path verifies the note after attempting the write.
        showConfirm(
            "GUILDCORE_EDIT_CHARACTER_NOTE_PROTECTED",
            "This character is at your guild rank or higher. Note edits may not be allowed. Try to save anyway?",
            continueWithActionConfirm
        )
        return
    end

    continueWithActionConfirm()
end

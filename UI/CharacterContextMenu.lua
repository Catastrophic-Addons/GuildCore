-- /GuildCore/UI/CharacterContextMenu.lua
-- Shared right-click command menu for character names and roster rows.
local addonName, ns = ...
local GC = ns.GuildCore

GC.UI.CharacterContextMenu = {}
local CCM = GC.UI.CharacterContextMenu

local MENU_NAME = "GuildCoreCharacterContextMenu"
local CATCHER_NAME = "GuildCoreCharacterContextMenuCatcher"

local function T() return GC.UI.Theme end

local function trim(value)
    return GC.Utils and GC.Utils.Trim and GC.Utils.Trim(value or "") or tostring(value or ""):match("^%s*(.-)%s*$")
end

local function splitFullName(value)
    local name, realm = tostring(value or ""):match("^([^%-]+)%-(.+)$")
    return name, realm
end

local function normalizeCharacterData(data)
    data = type(data) == "table" and data or {}
    local key = trim(data.key or data.fullName or data.normalizedKey or "")
    local name = trim(data.name or "")
    local realm = trim(data.realm or "")
    if key ~= "" then
        local keyName, keyRealm = splitFullName(key)
        name = name ~= "" and name or trim(keyName)
        realm = realm ~= "" and realm or trim(keyRealm)
    end
    if name == "" then
        name = key ~= "" and (key:match("^([^%-]+)") or key) or "Unknown"
    end
    if realm == "" then
        realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or ""
        realm = tostring(realm):gsub("%s+", "")
    end
    if key == "" and name ~= "" then
        key = GC.BanBook and GC.BanBook.NormalizeKey and GC.BanBook:NormalizeKey(name, realm) or GC.Utils.NormalizePlayerKey(name, realm)
    end

    local live = key and GC.Services and GC.Services.DataStore and GC.Services.DataStore:GetPlayer(key) or nil
    if live then
        for k, v in pairs(live) do
            if data[k] == nil then data[k] = v end
        end
    end

    data.name = name
    data.realm = realm
    data.key = key
    data.fullName = key
    data.displayName = key or name
    data.source = data.source or "Guild Core"
    data.publicNote = data.publicNote or data.note
    data.officerNote = data.officerNote or data.officer
    return data
end

local function status(message, colorKey)
    if GC.UI and GC.UI.MainFrame and GC.UI.MainFrame.SetStatus then
        GC.UI.MainFrame:SetStatus(message, colorKey)
    else
        GC:Print(message)
    end
end

local function debugLine(...)
    if GC.Debug then
        GC:Debug(...)
    end
end

local function isCombatBlocked(data, action)
    if InCombatLockdown and InCombatLockdown() then
        GC:InviteDebug("warn", "Context action unavailable in combat:", tostring(data and data.displayName or "Unknown"))
        status(action .. " is unavailable during combat.", "textWarn")
        return true
    end
    return false
end

local function getAvailability(data)
    local ops = GC.Services and GC.Services.Operations
    if ops and ops.GetActionAvailability then
        return ops:GetActionAvailability(data)
    end
    return {
        promote = { enabled = false, reason = "Operations service is unavailable." },
        demote = { enabled = false, reason = "Operations service is unavailable." },
        kick = { enabled = false, reason = "Operations service is unavailable." },
    }
end

local function focusRoster(data)
    if not data or not data.key then
        return false, "Character is unavailable."
    end
    if GC.UI and GC.UI.SetActivePanel then
        GC.UI:SetActivePanel("roster")
    end
    local roster = GC.UI and GC.UI.RosterPanel
    if roster and roster.FocusCharacter then
        return roster:FocusCharacter(data.key)
    end
    return false, "Roster panel is unavailable."
end

local function appendActivity(event, data, oldValue, newValue, reason)
    local ds = GC.Services and GC.Services.DataStore
    if ds and ds.AppendLog then
        ds:AppendLog({
            timestamp = GC.Utils.Now(),
            event = event,
            playerKey = data and data.key,
            oldValue = oldValue,
            newValue = newValue,
            reason = reason or "context-menu",
        })
    end
end

local function openCopyText(text)
    text = tostring(text or "")
    if ChatFrame_OpenChat then
        ChatFrame_OpenChat(text)
        return
    end
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox then
        DEFAULT_CHAT_FRAME.editBox:SetText(text)
        DEFAULT_CHAT_FRAME.editBox:HighlightText()
        DEFAULT_CHAT_FRAME.editBox:Show()
        return
    end
    status(text, "textDimmed")
end

function CCM:Close()
    if self.menu then
        self.menu:Hide()
    end
    if self.catcher then
        self.catcher:Hide()
    end
    self.current = nil
end

local function anchorNearCursor(frame)
    local scale = UIParent:GetEffectiveScale() or 1
    local x, y = GetCursorPosition()
    x = (x or 0) / scale
    y = (y or 0) / scale
    local width = frame:GetWidth() or 220
    local height = frame:GetHeight() or 300
    local screenW = UIParent:GetWidth() or 0
    local screenH = UIParent:GetHeight() or 0
    x = math.max(4, math.min(x + 12, math.max(4, screenW - width - 4)))
    y = math.max(height + 4, math.min(y - 10, screenH - 4))
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
end

function CCM:_ensureFrames()
    if self.menu then return end
    local Th = T()

    local catcher = CreateFrame("Button", CATCHER_NAME, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:EnableMouse(true)
    catcher:SetFrameStrata("DIALOG")
    catcher:SetFrameLevel(180)
    catcher:SetAlpha(0)
    catcher:Hide()
    catcher:SetScript("OnClick", function() CCM:Close() end)
    self.catcher = catcher

    local menu = CreateFrame("Frame", MENU_NAME, UIParent)
    menu:SetSize(224, 320)
    if GC.UI.Layering then
        GC.UI.Layering:ApplyPopup(menu, GC.UI.MainFrame and GC.UI.MainFrame.frame, 60)
    else
        menu:SetFrameStrata("DIALOG")
        menu:SetFrameLevel(220)
    end
    menu:EnableMouse(true)
    menu:Hide()
    Th.Bg(menu, Th.c.panelAlt, Th.c.borderAccent)
    self.menu = menu
    if UISpecialFrames then
        table.insert(UISpecialFrames, MENU_NAME)
    end

    self.title = Th.Fs(menu, "small", "", "textAccent")
    self.title:SetPoint("TOPLEFT", 10, -8)
    self.title:SetPoint("TOPRIGHT", -10, -8)

    self.rows = {}
end

function CCM:_getRow(index)
    local row = self.rows[index]
    if row then return row end
    local Th = T()
    row = CreateFrame("Button", nil, self.menu)
    row:SetHeight(22)
    row:SetPoint("TOPLEFT", self.menu, "TOPLEFT", 6, -30 - ((index - 1) * 24))
    row:SetPoint("TOPRIGHT", self.menu, "TOPRIGHT", -6, -30 - ((index - 1) * 24))
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0)
    row._bg = bg
    row._label = Th.Fs(row, "small", "", "textSecond")
    row._label:SetPoint("LEFT", 8, 0)
    row._label:SetPoint("RIGHT", -8, 0)
    row:SetScript("OnEnter", function(self)
        if self._disabled then
            if self._reason and self._reason ~= "" then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(self._reason, 1, 0.82, 0.35, 1, true)
                GameTooltip:Show()
            end
            return
        end
        local h = T().c.rowHover
        self._bg:SetColorTexture(h[1], h[2], h[3], h[4])
    end)
    row:SetScript("OnLeave", function(self)
        self._bg:SetColorTexture(0, 0, 0, 0)
        GameTooltip:Hide()
    end)
    self.rows[index] = row
    return row
end

function CCM:_addSeparator(index)
    local row = self:_getRow(index)
    row._isSeparator = true
    row._disabled = true
    row._reason = nil
    row._label:SetText("")
    if not row._line then
        row._line = row:CreateTexture(nil, "ARTWORK")
        row._line:SetPoint("LEFT", 4, 0)
        row._line:SetPoint("RIGHT", -4, 0)
        row._line:SetHeight(1)
    end
    local c = T().c.separator or T().c.border
    row._line:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    row._line:Show()
    row:SetScript("OnClick", nil)
    row:Show()
end

function CCM:_addItem(index, item)
    local row = self:_getRow(index)
    local Th = T()
    row._isSeparator = false
    row._disabled = item.enabled == false
    row._reason = item.reason
    if row._line then row._line:Hide() end
    row._label:SetText(item.label or "")
    local color = item.danger and Th.c.textDanger or row._disabled and Th.c.textDimmed or Th.c.textSecond
    row._label:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    row:SetScript("OnClick", function()
        if row._disabled then
            debugLine("Context action blocked by permissions:", item.label, self.current and self.current.displayName)
            if item.reason then status(item.reason, "textWarn") end
            return
        end
        debugLine("Context action selected:", item.label, self.current and self.current.displayName)
        self:Close()
        if item.onClick then item.onClick() end
    end)
    row:Show()
end

local function confirm(actionKey, text, onAccept)
    StaticPopupDialogs[actionKey] = StaticPopupDialogs[actionKey] or {
        text = text,
        button1 = "Confirm",
        button2 = "Cancel",
        OnAccept = function(_, callback)
            if callback then callback() end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    StaticPopupDialogs[actionKey].text = text
    StaticPopup_Show(actionKey, nil, nil, onAccept)
end

function CCM:_showTextDialog(kind, data)
    self:_ensureFrames()
    local dialog = self.textDialog
    local Th = T()
    if not dialog then
        dialog = CreateFrame("Frame", "GuildCoreCharacterTextDialog", UIParent)
        dialog:SetSize(430, 132)
        if GC.UI.Layering then
            GC.UI.Layering:ApplyPopup(dialog, GC.UI.MainFrame and GC.UI.MainFrame.frame, 70)
        else
            dialog:SetFrameStrata("DIALOG")
        end
        Th.Bg(dialog, Th.c.panel, Th.c.borderAccent)
        dialog:Hide()
        dialog.title = Th.Fs(dialog, "subheader", "", "textAccent")
        dialog.title:SetPoint("TOPLEFT", 12, -10)
        dialog.input = GC.UI.Panel.Input(dialog, 400, Th.inputH)
        dialog.input:SetPoint("TOPLEFT", 12, -42)
        dialog.input:SetMaxLetters(240)
        dialog.save = GC.UI.Button.Create(dialog, "Save", "primary", 78, Th.btnH)
        dialog.save:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -96, 12)
        dialog.cancel = GC.UI.Button.Create(dialog, "Cancel", "secondary", 78, Th.btnH)
        dialog.cancel:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -12, 12)
        dialog.cancel:SetScript("OnClick", function() dialog:Hide() end)
        self.textDialog = dialog
    end

    local officer = kind == "officer"
    dialog.title:SetText((officer and "Edit Officer Note: " or "Edit Public Note: ") .. tostring(data.displayName or data.name))
    dialog.input:SetText(officer and (data.officerNote or "") or (data.publicNote or ""))
    dialog.input:SetFocus()
    dialog.input:HighlightText()
    dialog.save:SetScript("OnClick", function()
        local value = dialog.input:GetText() or ""
        local oldValue = officer and (data.officerNote or "") or (data.publicNote or "")
        local function saveNote()
            local ok, err = GC.API.SetGuildMemberNote(data.key or data.name, value, officer)
            if ok then
                appendActivity(officer and "OFFICER_NOTE_CHANGED" or "PUBLIC_NOTE_CHANGED", data, oldValue, value, "context-menu")
                if GC.Services and GC.Services.GuildService then GC.Services.GuildService:TriggerScan() end
                status(officer and "Officer note saved." or "Public note saved.", "textSuccess")
                dialog:Hide()
            else
                status(err or "Unable to save note.", "textDanger")
            end
        end
        if trim(oldValue) ~= "" and trim(value) == "" then
            confirm("GUILDCORE_CONTEXT_CLEAR_NOTE", "Clear this guild note for " .. tostring(data.displayName) .. "?", saveNote)
            return
        end
        saveNote()
    end)
    dialog:ClearAllPoints()
    dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    dialog:Show()
end

function CCM:_showBanDialog(data)
    local Th = T()
    local dialog = self.banDialog
    if not dialog then
        dialog = CreateFrame("Frame", "GuildCoreCharacterBanDialog", UIParent)
        dialog:SetSize(440, 166)
        if GC.UI.Layering then
            GC.UI.Layering:ApplyPopup(dialog, GC.UI.MainFrame and GC.UI.MainFrame.frame, 70)
        else
            dialog:SetFrameStrata("DIALOG")
        end
        Th.Bg(dialog, Th.c.panel, Th.c.borderAccent)
        dialog:Hide()
        dialog.title = Th.Fs(dialog, "subheader", "", "textAccent")
        dialog.title:SetPoint("TOPLEFT", 12, -10)
        dialog.reasonLabel = Th.Fs(dialog, "tiny", "Reason Banned", "textDimmed")
        dialog.reasonLabel:SetPoint("TOPLEFT", 12, -38)
        dialog.reason = GC.UI.Panel.Input(dialog, 410, Th.inputH)
        dialog.reason:SetPoint("TOPLEFT", 12, -54)
        dialog.reason:SetMaxLetters(120)
        dialog.notesLabel = Th.Fs(dialog, "tiny", "Ban Notes", "textDimmed")
        dialog.notesLabel:SetPoint("TOPLEFT", 12, -84)
        dialog.notes = GC.UI.Panel.Input(dialog, 410, Th.inputH)
        dialog.notes:SetPoint("TOPLEFT", 12, -100)
        dialog.notes:SetMaxLetters(240)
        dialog.save = GC.UI.Button.Create(dialog, "Save Ban", "danger", 92, Th.btnH)
        dialog.save:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -96, 12)
        dialog.cancel = GC.UI.Button.Create(dialog, "Cancel", "secondary", 78, Th.btnH)
        dialog.cancel:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -12, 12)
        dialog.cancel:SetScript("OnClick", function() dialog:Hide() end)
        self.banDialog = dialog
    end
    dialog.title:SetText("Add to Ban Book: " .. tostring(data.displayName or data.name))
    dialog.reason:SetText("")
    dialog.notes:SetText("")
    dialog.reason:SetFocus()
    dialog.save:SetScript("OnClick", function()
        local reason = trim(dialog.reason:GetText() or "")
        if reason == "" then
            status("Ban Book reason is required.", "textWarn")
            return
        end
        local ok, entryOrErr = GC.BanBook:Add(data.name, data.realm, reason, dialog.notes:GetText() or "")
        if ok then
            status("Ban Book entry added for " .. tostring(entryOrErr.key or data.displayName) .. ".", "textWarn")
            if GC.UI and GC.UI.BanBookPanel and GC.UI.BanBookPanel.Refresh then
                GC.UI.BanBookPanel:Refresh()
            end
            dialog:Hide()
        else
            status(entryOrErr or "Unable to add Ban Book entry.", "textDanger")
        end
    end)
    dialog:ClearAllPoints()
    dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    dialog:Show()
end

function CCM:_showMainDialog(data)
    local Th = T()
    local dialog = self.mainDialog
    if not dialog then
        dialog = CreateFrame("Frame", "GuildCoreCharacterMainDialog", UIParent)
        dialog:SetSize(360, 124)
        if GC.UI.Layering then
            GC.UI.Layering:ApplyPopup(dialog, GC.UI.MainFrame and GC.UI.MainFrame.frame, 70)
        else
            dialog:SetFrameStrata("DIALOG")
        end
        Th.Bg(dialog, Th.c.panel, Th.c.borderAccent)
        dialog:Hide()
        dialog.title = Th.Fs(dialog, "subheader", "Mark as Alt", "textAccent")
        dialog.title:SetPoint("TOPLEFT", 12, -10)
        dialog.label = Th.Fs(dialog, "tiny", "Main character name or key", "textDimmed")
        dialog.label:SetPoint("TOPLEFT", 12, -38)
        dialog.input = GC.UI.Panel.Input(dialog, 330, Th.inputH)
        dialog.input:SetPoint("TOPLEFT", 12, -54)
        dialog.save = GC.UI.Button.Create(dialog, "Save", "primary", 78, Th.btnH)
        dialog.save:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -96, 12)
        dialog.cancel = GC.UI.Button.Create(dialog, "Cancel", "secondary", 78, Th.btnH)
        dialog.cancel:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -12, 12)
        dialog.cancel:SetScript("OnClick", function() dialog:Hide() end)
        self.mainDialog = dialog
    end
    dialog.input:SetText("")
    dialog.input:SetFocus()
    dialog.save:SetScript("OnClick", function()
        local mainKey = GC.Services.GuildService:ResolvePlayerKey(dialog.input:GetText() or "")
        if not mainKey then
            status("Enter a known main character name or key.", "textDanger")
            return
        end
        local function saveAlt()
            local ok, err = GC.Services.Alts:SetAlt(data.key, mainKey, "context-menu")
            status(ok and "Alt link saved." or (err or "Unable to mark alt."), ok and "textSuccess" or "textDanger")
            if ok then dialog:Hide(); focusRoster(data) end
        end
        if data.main and data.main ~= mainKey then
            confirm("GUILDCORE_CONTEXT_ALT_OVERWRITE", "Change " .. tostring(data.displayName) .. "'s main character link?", saveAlt)
            return
        end
        if data.classification == "main" then
            confirm("GUILDCORE_CONTEXT_MAIN_TO_ALT", "Mark " .. tostring(data.displayName) .. " as an alt instead of a main?", saveAlt)
            return
        end
        saveAlt()
    end)
    dialog:ClearAllPoints()
    dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    dialog:Show()
end

local function safePlayerAction(data, action, fn)
    if isCombatBlocked(data, action) then return end
    local ok, err = fn()
    status(ok and (action .. " queued for " .. tostring(data.displayName) .. ".") or (err or ("Unable to " .. action .. ".")), ok and "textWarn" or "textDanger")
    if ok and GC.UI and GC.UI.PlayerPanel and GC.UI.PlayerPanel.Refresh then
        GC.UI.PlayerPanel:Refresh()
    end
end

function CCM:_buildItems(data)
    local items = {}
    local function item(def) items[#items + 1] = def end
    local function sep() items[#items + 1] = { separator = true } end

    local availability = getAvailability(data)
    local isOfficer = GC.Permissions and GC.Permissions.IsOfficerOrBetter and GC.Permissions:IsOfficerOrBetter()
    local banned, banEntry = GC.BanBook and GC.BanBook.IsBanned and GC.BanBook:IsBanned(data.name, data.realm)

    item({ label = "Whisper", enabled = data.isOnline == true, reason = "Character is offline.", onClick = function()
        local ok, err = GC.Services.GuildService:OpenWhisper(data.key)
        status(ok and ("Opening whisper to " .. data.name .. ".") or (err or "Unable to whisper."), ok and "textSuccess" or "textDanger")
    end })
    item({ label = "Edit Character", enabled = data.key ~= nil and GC.UI.EditCharacterPopup ~= nil, reason = "Character profile is unavailable.", onClick = function()
        local live = GC.Services.DataStore:GetPlayer(data.key) or data
        GC.UI.EditCharacterPopup:Open(live)
    end })
    item({ label = "Invite to Group", enabled = data.isOnline == true, reason = "Character is offline.", onClick = function()
        local ok, err = GC.Services.GuildService:InviteToParty(data.key)
        status(ok and ("Party invite sent to " .. data.name .. ".") or (err or "Unable to invite."), ok and "textSuccess" or "textDanger")
    end })
    item({ label = "Open Roster Entry", enabled = data.key ~= nil, onClick = function() local ok, err = focusRoster(data); if not ok then status(err, "textWarn") end end })
    item({ label = "Copy Name", onClick = function() openCopyText(data.name or "") end })
    item({ label = "Copy Name-Realm", onClick = function() openCopyText(data.displayName or data.name or "") end })
    local canInspect = InspectUnit ~= nil and UnitExists and UnitExists(data.name or "") and (not CanInspect or CanInspect(data.name or ""))
    item({ label = "Inspect", enabled = canInspect == true, reason = "Inspect requires an available nearby unit token.", onClick = function()
        if InspectUnit then InspectUnit(data.name) end
    end })
    sep()

    item({ label = "Edit Public Note", enabled = isOfficer, reason = "Officer permission required.", onClick = function() self:_showTextDialog("public", data) end })
    item({ label = "Edit Officer Note", enabled = isOfficer, reason = "Officer permission required.", onClick = function() self:_showTextDialog("officer", data) end })
    sep()

    item({ label = "Promote", enabled = availability.promote and availability.promote.enabled, reason = availability.promote and availability.promote.reason, onClick = function()
        confirm("GUILDCORE_CONTEXT_PROMOTE", "Promote " .. tostring(data.displayName) .. "?", function()
            safePlayerAction(data, "Promote", function() return GC.Services.Operations:Promote(data) end)
        end)
    end })
    item({ label = "Demote", enabled = availability.demote and availability.demote.enabled, reason = availability.demote and availability.demote.reason, onClick = function()
        confirm("GUILDCORE_CONTEXT_DEMOTE", "Demote " .. tostring(data.displayName) .. "?", function()
            safePlayerAction(data, "Demote", function() return GC.Services.Operations:Demote(data) end)
        end)
    end })
    item({ label = "Kick from Guild", danger = true, enabled = availability.kick and availability.kick.enabled, reason = availability.kick and availability.kick.reason, onClick = function()
        confirm("GUILDCORE_CONTEXT_KICK", "Are you sure you want to kick " .. tostring(data.displayName) .. " from the guild?", function()
            safePlayerAction(data, "Kick", function() return GC.Services.Operations:Kick(data) end)
            if GC.UI and GC.UI.PurgePanel and GC.UI.PurgePanel.Refresh then GC.UI.PurgePanel:Refresh() end
        end)
    end })
    sep()

    item({ label = "View Alts", enabled = data.key ~= nil, onClick = function()
        local ok, err = focusRoster(data)
        if ok and GC.UI and GC.UI.MainFrame then
            GC.UI.MainFrame:SetStatus("Alts are shown in the roster detail panel.", "textDimmed")
        elseif err then
            status(err, "textWarn")
        end
    end })
    item({ label = "Mark as Main", enabled = data.key ~= nil, onClick = function()
        confirm("GUILDCORE_CONTEXT_MAIN", "Mark " .. tostring(data.displayName) .. " as a main character?", function()
            local ok, err = GC.Services.Alts:SetMain(data.key, "context-menu")
            status(ok and "Character marked as Main." or (err or "Unable to mark Main."), ok and "textSuccess" or "textDanger")
            if ok then focusRoster(data) end
        end)
    end })
    item({ label = "Mark as Alt", enabled = data.key ~= nil, onClick = function() self:_showMainDialog(data) end })
    sep()

    if banned then
        item({ label = "Already in Ban Book", enabled = false, reason = "This character is already listed in Ban Book." })
        item({ label = "View Ban Entry", onClick = function()
            if GC.UI and GC.UI.SetActivePanel then GC.UI:SetActivePanel("banbook") end
            status("Ban Book entry: " .. tostring(banEntry and banEntry.key or data.displayName), "textWarn")
        end })
    else
        item({ label = "Add to Ban Book", danger = true, enabled = isOfficer, reason = "Officer permission required.", onClick = function() self:_showBanDialog(data) end })
    end
    item({ label = "Refresh Character", onClick = function()
        local ok, err = GC.Services.GuildService:TriggerScan()
        status(ok and "Roster refresh requested." or (err or "Unable to refresh roster."), ok and "textWarn" or "textDanger")
    end })
    item({ label = "Cancel", onClick = function() end })

    return items
end

function CCM:Open(data)
    self:_ensureFrames()
    data = normalizeCharacterData(data)
    self.current = data
    debugLine("Character context menu opened for", data.displayName or data.name)

    self.title:SetText(data.displayName or data.name or "Character")
    local items = self:_buildItems(data)
    local rowIndex = 0
    for _, def in ipairs(items) do
        rowIndex = rowIndex + 1
        if def.separator then
            self:_addSeparator(rowIndex)
        else
            self:_addItem(rowIndex, def)
        end
    end
    for i = rowIndex + 1, #self.rows do
        self.rows[i]:Hide()
    end
    self.menu:SetHeight(36 + (rowIndex * 24))
    anchorNearCursor(self.menu)
    self.catcher:Show()
    self.menu:Show()
end

function CCM:Attach(frame, characterDataProvider)
    if not frame then return false end
    frame:EnableMouse(true)
    local objectType = frame.GetObjectType and frame:GetObjectType() or ""
    local isButton = objectType == "Button" or objectType == "CheckButton"
    if isButton and frame.RegisterForClicks then
        frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    end
    local prevClick = isButton and frame:GetScript("OnClick") or nil
    local prevMouseUp = frame:GetScript("OnMouseUp")
    if isButton then
        frame:SetScript("OnClick", function(self, button, ...)
            if button == "RightButton" then
                local data = characterDataProvider and characterDataProvider(self) or nil
                CCM:Open(data)
                return
            end
            if prevClick then prevClick(self, button, ...) end
        end)
    end
    frame:SetScript("OnMouseUp", function(self, button, ...)
        if button == "RightButton" and not isButton then
            local data = characterDataProvider and characterDataProvider(self) or nil
            CCM:Open(data)
            return
        end
        if prevMouseUp then prevMouseUp(self, button, ...) end
    end)
    local prevHide = frame:GetScript("OnHide")
    frame:SetScript("OnHide", function(self, ...)
        CCM:Close()
        if prevHide then prevHide(self, ...) end
    end)
    return true
end

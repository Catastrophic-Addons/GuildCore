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

function CCM:NormalizeCharacterData(data)
    return normalizeCharacterData(data)
end

function CCM:ValidateCharacterData(data, actionId)
    data = normalizeCharacterData(data)
    if not data.key or data.key == "" then
        if GC.Debug then GC:Debug("Character context action blocked: missing character key", tostring(actionId or "unknown")) end
        return nil, "Character key is unavailable."
    end
    if not data.name or data.name == "" or data.name == "Unknown" then
        if GC.Debug then GC:Debug("Character context action blocked: missing character name", tostring(actionId or "unknown"), tostring(data.key)) end
        return nil, "Character name is unavailable."
    end
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
    if text == "" then return end
    local dialog = CCM.copyDialog
    local Th = T()
    if not dialog then
        dialog = CreateFrame("Frame", "GuildCoreCharacterCopyDialog", UIParent)
        dialog:SetSize(360, 108)
        if GC.UI.Layering then
            GC.UI.Layering:ApplyPopup(dialog, GC.UI.MainFrame and GC.UI.MainFrame.frame, 80)
        else
            dialog:SetFrameStrata("DIALOG")
        end
        dialog:SetClampedToScreen(true)
        Th.Bg(dialog, Th.c.panel, Th.c.borderAccent)
        dialog.title = Th.Fs(dialog, "subheader", "Copy Character Name", "textAccent")
        dialog.title:SetPoint("TOPLEFT", dialog, "TOPLEFT", 12, -10)
        dialog.input = GC.UI.Panel.Input(dialog, 334, Th.inputH)
        dialog.input:SetPoint("TOPLEFT", dialog, "TOPLEFT", 12, -42)
        dialog.input:SetAutoFocus(false)
        dialog.close = GC.UI.Button.Create(dialog, "Close", "secondary", 72, Th.btnH)
        dialog.close:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -12, 12)
        dialog.close:SetScript("OnClick", function() dialog:Hide() end)
        dialog:Hide()
        CCM.copyDialog = dialog
    end
    dialog.input:SetText(text)
    dialog.input:SetFocus()
    dialog.input:HighlightText()
    dialog:ClearAllPoints()
    dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    dialog:Show()
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
    catcher:SetFrameStrata("FULLSCREEN_DIALOG")
    catcher:SetFrameLevel(240)
    catcher:SetAlpha(0)
    catcher:Hide()
    catcher:SetScript("OnClick", function() CCM:Close() end)
    self.catcher = catcher

    local menu = CreateFrame("Frame", MENU_NAME, UIParent)
    menu:SetSize(224, 320)
    -- Keep this above the invisible dismiss catcher. The catcher used to sit
    -- over menu rows after the shared popup helper picked a lower frame level.
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetFrameLevel(260)
    menu:EnableMouse(true)
    menu:SetClampedToScreen(true)
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
    row:EnableMouse(true)
    row:RegisterForClicks("LeftButtonUp")
    row:SetFrameLevel((self.menu:GetFrameLevel() or 260) + 2)
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
        local current = self.current
        self:Close()
        if item.actionId then
            self:RunAction(item.actionId, current)
        elseif item.onClick then
            item.onClick()
        end
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
        confirm("GUILDCORE_CONTEXT_ADD_BAN", "Add " .. tostring(data.displayName) .. " to Ban Book?", function()
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

local function refreshCharacterViews()
    if GC.UI and GC.UI.PlayerPanel and GC.UI.PlayerPanel.Refresh then GC.UI.PlayerPanel:Refresh() end
    if GC.UI and GC.UI.RosterPanel and GC.UI.RosterPanel.Refresh then GC.UI.RosterPanel:Refresh() end
    if GC.UI and GC.UI.Dashboard and GC.UI.Dashboard.Refresh then GC.UI.Dashboard:Refresh() end
    if GC.UI and GC.UI.LogPanel and GC.UI.LogPanel.Refresh then GC.UI.LogPanel:Refresh() end
    if GC.UI and GC.UI.BanBookPanel and GC.UI.BanBookPanel.Refresh then GC.UI.BanBookPanel:Refresh() end
    if GC.UI and GC.UI.PurgePanel and GC.UI.PurgePanel.Refresh then GC.UI.PurgePanel:Refresh() end
end

local function openEditCharacterTab(data, tab)
    local popup = GC.UI and GC.UI.EditCharacterPopup
    local live = data and data.key and GC.Services.DataStore:GetPlayer(data.key) or data
    if not popup or not live then
        return false, "Edit Character is unavailable."
    end
    popup:Open(live)
    if tab and popup._setTab then
        popup:_setTab(tab)
    end
    return true
end

function CCM:RunAction(actionId, characterData)
    local data, err = self:ValidateCharacterData(characterData, actionId)
    if not data then
        status(err or "Character action is unavailable.", "textWarn")
        return false, err
    end

    local function rankAction(label, fn)
        confirm("GUILDCORE_CONTEXT_" .. string.upper(actionId), label .. " " .. tostring(data.displayName) .. "?", function()
            safePlayerAction(data, label, fn)
            refreshCharacterViews()
        end)
        return true
    end

    if actionId == "edit_character" then
        local ok, message = openEditCharacterTab(data)
        if not ok then status(message, "textWarn") end
        return ok, message
    elseif actionId == "open_roster_entry" then
        local ok, message = focusRoster(data)
        if not ok then status(message or "Roster entry unavailable.", "textWarn") end
        return ok, message
    elseif actionId == "whisper" then
        local ok, message = GC.Services.GuildService:OpenWhisper(data.key)
        status(ok and ("Opening whisper to " .. tostring(data.name) .. ".") or (message or "Unable to whisper."), ok and "textSuccess" or "textDanger")
        return ok, message
    elseif actionId == "invite_group" then
        local ok, message = GC.Services.GuildService:InviteToParty(data.key)
        status(ok and ("Party invite sent to " .. tostring(data.name) .. ".") or (message or "Unable to invite."), ok and "textSuccess" or "textDanger")
        return ok, message
    elseif actionId == "inspect" then
        if InspectUnit then InspectUnit(data.name) end
        return true
    elseif actionId == "copy_name" then
        openCopyText(data.name)
        return true
    elseif actionId == "copy_name_realm" then
        openCopyText(data.displayName or data.key)
        return true
    elseif actionId == "edit_public_note" then
        self:_showTextDialog("public", data)
        return true
    elseif actionId == "edit_officer_note" then
        self:_showTextDialog("officer", data)
        return true
    elseif actionId == "promote" then
        return rankAction("Promote", function() return GC.Services.Operations:Promote(data) end)
    elseif actionId == "demote" then
        return rankAction("Demote", function() return GC.Services.Operations:Demote(data) end)
    elseif actionId == "kick" then
        confirm("GUILDCORE_CONTEXT_KICK", "Kick " .. tostring(data.displayName) .. " from the guild?", function()
            safePlayerAction(data, "Kick", function() return GC.Services.Operations:Kick(data) end)
            refreshCharacterViews()
        end)
        return true
    elseif actionId == "add_to_ban_book" then
        self:_showBanDialog(data)
        return true
    elseif actionId == "view_ban_entry" then
        if GC.UI and GC.UI.SetActivePanel then GC.UI:SetActivePanel("banbook") end
        if GC.UI and GC.UI.BanBookPanel and GC.UI.BanBookPanel.FocusEntry then
            GC.UI.BanBookPanel:FocusEntry(data.key)
        end
        status("Ban Book entry: " .. tostring(data.displayName), "textWarn")
        return true
    elseif actionId == "remove_from_ban_book" then
        confirm("GUILDCORE_CONTEXT_REMOVE_BAN", "Remove " .. tostring(data.displayName) .. " from Ban Book?", function()
            local ok, message = GC.BanBook:Remove(data.key)
            status(ok and ("Removed from Ban Book: " .. tostring(data.displayName)) or (message or "Unable to remove Ban Book entry."), ok and "textWarn" or "textDanger")
            refreshCharacterViews()
        end)
        return true
    elseif actionId == "view_alts" or actionId == "mark_alt" then
        local ok, message = openEditCharacterTab(data, "alts")
        if not ok then status(message, "textWarn") end
        return ok, message
    elseif actionId == "mark_main" then
        confirm("GUILDCORE_CONTEXT_MAIN", "Mark " .. tostring(data.displayName) .. " as a main character?", function()
            local ok, message = GC.Services.Alts:SetMain(data.key, "context-menu")
            status(ok and "Character marked as Main." or (message or "Unable to mark Main."), ok and "textSuccess" or "textDanger")
            if ok then focusRoster(data); refreshCharacterViews() end
        end)
        return true
    elseif actionId == "mark_unknown" then
        confirm("GUILDCORE_CONTEXT_UNKNOWN", "Mark " .. tostring(data.displayName) .. " as Unknown and clear its current alt link if present?", function()
            local ok, message = GC.Services.Alts:SetUnknown(data.key, "context-menu")
            status(ok and "Character marked as Unknown." or (message or "Unable to mark Unknown."), ok and "textWarn" or "textDanger")
            if ok then focusRoster(data); refreshCharacterViews() end
        end)
        return true
    elseif actionId == "add_discord_verification" then
        local ok, message = openEditCharacterTab(data, "general")
        if ok then status("Discord fields are available in Edit Character.", "textDimmed") else status(message, "textWarn") end
        return ok, message
    elseif actionId == "remove_discord_verification" then
        confirm("GUILDCORE_CONTEXT_REMOVE_DISCORD", "Open Edit Character to remove Discord verification for " .. tostring(data.displayName) .. "?", function()
            local ok, message = openEditCharacterTab(data, "general")
            if ok then status("Update Discord verification in Edit Character.", "textWarn") else status(message, "textWarn") end
        end)
        return true
    elseif actionId == "view_activity_history" then
        if GC.UI and GC.UI.SetActivePanel then GC.UI:SetActivePanel("log") end
        if GC.UI and GC.UI.LogPanel and GC.UI.LogPanel.FocusCharacter then
            GC.UI.LogPanel:FocusCharacter(data.key)
            return true
        end
        status("Activity history is unavailable.", "textWarn")
        return false, "Activity history is unavailable."
    elseif actionId == "refresh_character" then
        local ok, message = GC.Services.GuildService:TriggerScan()
        status(ok and "Roster refresh requested." or (message or "Unable to refresh roster."), ok and "textWarn" or "textDanger")
        return ok, message
    elseif actionId == "cancel" then
        return true
    end

    debugLine("Context action unavailable:", tostring(actionId), tostring(data.displayName))
    status("Not implemented yet.", "textWarn")
    return false, "Not implemented yet."
end

function CCM:_buildItems(data)
    local items = {}
    local function item(def) items[#items + 1] = def end
    local function sep() items[#items + 1] = { separator = true } end

    local availability = getAvailability(data)
    local isOfficer = GC.Permissions and GC.Permissions.IsOfficerOrBetter and GC.Permissions:IsOfficerOrBetter()
    local banned, banEntry = GC.BanBook and GC.BanBook.IsBanned and GC.BanBook:IsBanned(data.name, data.realm)

    item({ label = "Whisper", actionId = "whisper", enabled = data.isOnline == true, reason = "Character is offline." })
    item({ label = "Edit Character", actionId = "edit_character", enabled = data.key ~= nil and GC.UI.EditCharacterPopup ~= nil, reason = "Character profile is unavailable." })
    item({ label = "Invite to Group", actionId = "invite_group", enabled = data.isOnline == true, reason = "Character is offline." })
    item({ label = "Open Roster Entry", actionId = "open_roster_entry", enabled = data.key ~= nil, reason = "Character key is unavailable." })
    item({ label = "Copy Name", actionId = "copy_name" })
    item({ label = "Copy Name-Realm", actionId = "copy_name_realm" })
    local canInspect = InspectUnit ~= nil and UnitExists and UnitExists(data.name or "") and (not CanInspect or CanInspect(data.name or ""))
    item({ label = "Inspect", actionId = "inspect", enabled = canInspect == true, reason = "Inspect requires the character to be nearby or targeted." })
    sep()

    item({ label = "Edit Public Note", actionId = "edit_public_note", enabled = isOfficer, reason = "Officer permission required." })
    item({ label = "Edit Officer Note", actionId = "edit_officer_note", enabled = isOfficer, reason = "Officer permission required." })
    sep()

    item({ label = "Promote", actionId = "promote", enabled = availability.promote and availability.promote.enabled, reason = availability.promote and availability.promote.reason })
    item({ label = "Demote", actionId = "demote", enabled = availability.demote and availability.demote.enabled, reason = availability.demote and availability.demote.reason })
    item({ label = "Kick from Guild", actionId = "kick", danger = true, enabled = availability.kick and availability.kick.enabled, reason = availability.kick and availability.kick.reason })
    sep()

    item({ label = "View Alts", actionId = "view_alts", enabled = data.key ~= nil, reason = "Character key is unavailable." })
    item({ label = "Mark as Main", actionId = "mark_main", enabled = data.key ~= nil, reason = "Character key is unavailable." })
    item({ label = "Mark as Alt", actionId = "mark_alt", enabled = data.key ~= nil, reason = "Character key is unavailable." })
    item({ label = "Mark Unknown", actionId = "mark_unknown", enabled = data.key ~= nil and data.classification ~= "unknown", reason = data.classification == "unknown" and "Character is already Unknown." or "Character key is unavailable." })
    item({ label = "View Activity History", actionId = "view_activity_history", enabled = data.key ~= nil, reason = "Character key is unavailable." })
    sep()

    if banned then
        item({ label = "Already in Ban Book", enabled = false, reason = "This character is already listed in Ban Book." })
        item({ label = "View Ban Entry", actionId = "view_ban_entry" })
        item({ label = "Remove from Ban Book", actionId = "remove_from_ban_book", danger = true, enabled = isOfficer, reason = "Officer permission required." })
    else
        item({ label = "Add to Ban Book", actionId = "add_to_ban_book", danger = true, enabled = isOfficer, reason = "Officer permission required." })
    end
    item({ label = "Refresh Character", actionId = "refresh_character" })
    item({ label = "Cancel", actionId = "cancel" })

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
    debugLine(
        "Character context menu frame:",
        tostring(self.menu:GetFrameStrata()),
        tostring(self.menu:GetFrameLevel()),
        "catcher:",
        tostring(self.catcher:GetFrameStrata()),
        tostring(self.catcher:GetFrameLevel()),
        "rows:",
        tostring(rowIndex)
    )
    self.catcher:Show()
    self.menu:Show()
end

function CCM:Attach(frame, characterDataProvider)
    if not frame then return false end
    frame._guildCoreCharacterContextProvider = characterDataProvider
    if frame._guildCoreCharacterContextAttached then
        return true
    end
    frame._guildCoreCharacterContextAttached = true
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
                local provider = self._guildCoreCharacterContextProvider
                local data = provider and provider(self) or nil
                CCM:Open(data)
                return
            end
            if prevClick then prevClick(self, button, ...) end
        end)
    end
    frame:SetScript("OnMouseUp", function(self, button, ...)
        if button == "RightButton" and not isButton then
            local provider = self._guildCoreCharacterContextProvider
            local data = provider and provider(self) or nil
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

-- UI/MessagingPanel.lua
-- Message template library: categories, reusable templates, placeholder preview,
-- safe queueing, optional auto-send, and drag-reorder support.
local addonName, ns = ...
local GC = ns.GuildCore

GC.UI.MessagingPanel = {}
local MP = GC.UI.MessagingPanel

local function T() return GC.UI.Theme end
local function MS() return GC.Services.Messages end
local function TB() return GC.Services.MessageTemplateBridge end
local function DS() return GC.Services.DataStore end

local MESSAGE_ROW_HEIGHT = 50
local PREVIEW_ROW_HEIGHT = 58
local HISTORY_ROW_HEIGHT = 40
local DEFAULT_CHUNK_LIMIT = 240
local MIN_CHUNK_LIMIT = 20
local MAX_CHUNK_LIMIT = 255

local function trim(value)
    return GC.Utils.Trim(value or "")
end

local function setEditBoxInteractive(editBox, enabled)
    if not editBox then
        return
    end

    if not enabled and editBox.ClearFocus then
        editBox:ClearFocus()
    end
    if editBox.EnableMouse then
        editBox:EnableMouse(enabled)
    end
    if editBox.SetTextColor then
        local c = enabled and T().c.textPrimary or T().c.textDimmed
        editBox:SetTextColor(c[1], c[2], c[3], 1)
    end
end

local function setFrameShown(frame, shown)
    if not frame then
        return
    end
    if shown then
        frame:Show()
    else
        frame:Hide()
    end
end

local function createMultilineInput(parent, height)
    local Th = T()

    local holder = CreateFrame("Frame", nil, parent)
    holder:SetHeight(height)
    Th.Bg(holder, Th.c.panelAlt, Th.c.borderStrong)

    local scroll = CreateFrame("ScrollFrame", nil, holder)
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -6, 6)

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    Th.ApplyFont(edit, "input")
    if Th.RegisterRefresh then
        Th:RegisterRefresh(function()
            T().ApplyFont(edit, "input")
        end)
    end
    edit:SetTextColor(Th.c.textPrimary[1], Th.c.textPrimary[2], Th.c.textPrimary[3], 1)
    edit:SetWidth(100)
    edit:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    edit:SetScript("OnCursorChanged", function(_, _, y, _, lineHeight)
        local offset = scroll:GetVerticalScroll()
        local visibleTop = offset
        local visibleBottom = offset + scroll:GetHeight()
        local cursorTop = y
        local cursorBottom = y + lineHeight
        if cursorBottom > visibleBottom then
            scroll:SetVerticalScroll(cursorBottom - scroll:GetHeight())
        elseif cursorTop < visibleTop then
            scroll:SetVerticalScroll(math.max(0, cursorTop))
        end
    end)
    edit:SetScript("OnTextChanged", function(self)
        self:SetWidth(math.max(120, scroll:GetWidth() - 4))
    end)
    edit:SetTextInsets(0, 0, 0, 0)
    scroll:SetScrollChild(edit)

    holder:EnableMouseWheel(true)
    holder:SetScript("OnMouseWheel", function(_, delta)
        scroll:SetVerticalScroll(math.max(0, scroll:GetVerticalScroll() - (delta * 24)))
    end)

    local function edge()
        local tex = holder:CreateTexture(nil, "BACKGROUND", nil, -7)
        local bc = Th.c.borderStrong
        tex:SetColorTexture(bc[1], bc[2], bc[3], bc[4])
        return tex
    end
    holder._top, holder._bot, holder._lft, holder._rgt = edge(), edge(), edge(), edge()
    holder._top:SetPoint("TOPLEFT")
    holder._top:SetPoint("TOPRIGHT")
    holder._top:SetHeight(1)
    holder._bot:SetPoint("BOTTOMLEFT")
    holder._bot:SetPoint("BOTTOMRIGHT")
    holder._bot:SetHeight(1)
    holder._lft:SetPoint("TOPLEFT")
    holder._lft:SetPoint("BOTTOMLEFT")
    holder._lft:SetWidth(1)
    holder._rgt:SetPoint("TOPRIGHT")
    holder._rgt:SetPoint("BOTTOMRIGHT")
    holder._rgt:SetWidth(1)

    holder:SetScript("OnSizeChanged", function(_, width, boxHeight)
        edit:SetWidth(math.max(120, width - 18))
        if boxHeight then
            edit:SetHeight(math.max(24, boxHeight - 12))
        end
    end)

    edit:SetScript("OnEditFocusGained", function()
        local ac = Th.c.borderAccent
        holder._top:SetColorTexture(ac[1], ac[2], ac[3], ac[4])
        holder._bot:SetColorTexture(ac[1], ac[2], ac[3], ac[4])
        holder._lft:SetColorTexture(ac[1], ac[2], ac[3], ac[4])
        holder._rgt:SetColorTexture(ac[1], ac[2], ac[3], ac[4])
    end)
    edit:SetScript("OnEditFocusLost", function()
        local bc = Th.c.borderStrong
        holder._top:SetColorTexture(bc[1], bc[2], bc[3], bc[4])
        holder._bot:SetColorTexture(bc[1], bc[2], bc[3], bc[4])
        holder._lft:SetColorTexture(bc[1], bc[2], bc[3], bc[4])
        holder._rgt:SetColorTexture(bc[1], bc[2], bc[3], bc[4])
    end)

    return holder, edit
end

local function buildCategoryRow(row, item)
    local Th = T()
    row._item = item

    if not row._name then
        local nameFs = Th.Fs(row, "data", "", "textPrimary")
        nameFs:SetPoint("LEFT", 8, 0)
        nameFs:SetPoint("RIGHT", row, "RIGHT", -48, 0)
        nameFs:SetJustifyH("LEFT")
        row._name = nameFs

        local countFs = Th.Fs(row, "data", "", "textDimmed")
        countFs:SetPoint("RIGHT", -8, 0)
        countFs:SetJustifyH("RIGHT")
        row._count = countFs
    end

    local prefix = item.collapsed and "[+] " or ""
    local suffix = item.isDefault and " *" or ""
    if item.archived then
        suffix = suffix .. " [Archived]"
    end
    row._name:SetText(prefix .. (item.name or "General") .. suffix)
    row._count:SetText(tostring(item.count or 0))
end

function MP:StartMessageDrag(messageId)
    local svc = MS()
    if not svc or not messageId or not self.visibleMessages or #self.visibleMessages == 0 then
        return
    end

    local originalIndex = svc:GetMessageIndex(messageId)
    if not originalIndex then
        return
    end

    self.dragState = {
        messageId = messageId,
        categoryId = svc:GetSelectedCategoryId(),
        originalIndex = originalIndex,
        dropIndex = originalIndex,
    }

    if self.dragOverlay then
        self.dragOverlay:Show()
    end
    if self.dropIndicator then
        self.dropIndicator:Show()
    end
    self:UpdateMessageDragIndicator()
end

function MP:GetMessageDropIndex()
    if not self.visibleMessages or #self.visibleMessages == 0 or not self.messageList or not self.messageList.content then
        return nil
    end

    local content = self.messageList.content
    local contentTop = content:GetTop()
    if not contentTop then
        return nil
    end

    local scale = content:GetEffectiveScale() or 1
    local _, cursorY = GetCursorPosition()
    cursorY = cursorY / scale
    local relativeY = contentTop - cursorY
    local index = math.floor((relativeY + (MESSAGE_ROW_HEIGHT * 0.5)) / MESSAGE_ROW_HEIGHT) + 1
    index = math.max(1, math.min(#self.visibleMessages + 1, index))
    return index
end

function MP:UpdateMessageDragIndicator()
    if not self.dragState or not self.dropIndicator or not self.messageList or not self.messageList.content then
        return
    end

    local dropIndex = self:GetMessageDropIndex()
    if not dropIndex then
        return
    end

    self.dragState.dropIndex = dropIndex
    self.dropIndicator:ClearAllPoints()
    self.dropIndicator:SetPoint("TOPLEFT", self.messageList.content, "TOPLEFT", 0, -((dropIndex - 1) * MESSAGE_ROW_HEIGHT))
    self.dropIndicator:SetPoint("TOPRIGHT", self.messageList.content, "TOPRIGHT", 0, -((dropIndex - 1) * MESSAGE_ROW_HEIGHT))
    self.dropIndicator:Show()
end

function MP:FinishMessageDrag(cancelled)
    local svc = MS()
    local dragState = self.dragState

    if self.dragOverlay then
        self.dragOverlay:Hide()
    end
    if self.dropIndicator then
        self.dropIndicator:Hide()
    end
    self.dragState = nil

    if cancelled or not dragState or not svc then
        return
    end

    local desiredIndex = dragState.dropIndex or dragState.originalIndex
    if desiredIndex > dragState.originalIndex then
        desiredIndex = desiredIndex - 1
    end

    if desiredIndex ~= dragState.originalIndex then
        local ok, err = svc:MoveMessageToIndex(dragState.messageId, desiredIndex)
        if not ok then
            GC.UI.MainFrame:SetStatus(err or "Unable to reorder message.", "textDanger")
        end
    end

    self:Refresh()
end

function MP:DirectSendTemplate(messageId)
    local svc = MS()
    if not svc then
        return
    end

    local ok, err = self:ApplyPlaceholderInputs()
    if not ok then
        GC.UI.MainFrame:SetStatus(err or "Invalid placeholder settings.", "textDanger")
        return
    end

    local message = svc:GetMessage(messageId)
    local fallbackChannel = message and message.targetChannel or "GUILD"
    if self.currentDraft and self.currentDraft.id ~= messageId then
        self:SetSelectedChannel(fallbackChannel, false)
    end

    local outputOptions, optionsErr = self:GetOutputOptions(fallbackChannel)
    if not outputOptions then
        GC.UI.MainFrame:SetStatus(optionsErr or "Invalid target channel.", "textDanger")
        return
    end

    local payload, previewErr = svc:BuildMessagePreview(messageId, self:GetResolveOptions())
    if not payload then
        GC.UI.MainFrame:SetStatus(previewErr or "Unable to preview message.", "textDanger")
        return
    end
    self:SetPlaceholderWarnings(payload.placeholderWarnings or {})

    local function runDirectSend()
        local success, sendErr, sendPayload = svc:DirectSendMessage(messageId, self:GetResolveOptions())
        if not success then
            GC.UI.MainFrame:SetStatus(sendErr or "Unable to queue message.", "textDanger")
            return
        end

        self.previewData = sendPayload and sendPayload.preview or payload.preview or {}
        self.selectedPreviewKey = self.previewData[1] and self.previewData[1].key or nil
        self:Refresh()

        if sendPayload and sendPayload.autoStarted then
            GC.UI.MainFrame:SetStatus("Template queued and auto-send started.", "textSuccess")
        else
            GC.UI.MainFrame:SetStatus("Template queued in Manual Mode.", "textSuccess")
        end
    end

    outputOptions.chunkCount = #(payload.preview or {})
    outputOptions.willAutoSend = svc:GetAutomationEnabled()
    outputOptions.actionLabel = "template send"
    outputOptions.callback = runDirectSend
    self:RunWithOutputConfirmation(outputOptions)
end

function MP:GetTemplateFilterOptions()
    return {
        showArchived = self.showArchived == true,
        favoritesOnly = self.favoritesOnly == true,
        search = self.searchInput and self.searchInput:GetText() or "",
    }
end

function MP:GetPlaceholderRows()
    local svc = MS()
    if svc and svc.GetAvailablePlaceholders then
        local rows = svc:GetAvailablePlaceholders(self:GetResolveOptions())
        if rows and #rows > 0 then
            return rows
        end
    end

    return {
        { token = "@player.name", label = "Player Name", group = "Player" },
        { token = "@guild.name", label = "Guild Name", group = "Guild" },
        { token = "@realm.name", label = "Realm Name", group = "Guild" },
        { token = "@target.name", label = "Target Name", group = "Target" },
        { token = "@new.member", label = "New Member", group = "Target" },
        { token = "@rank.name", label = "Rank Name", group = "Target" },
        { token = "@discord.name", label = "Discord Name", group = "Target" },
        { token = "@character.name", label = "Character Name", group = "Player" },
        { token = "@main.name", label = "Main Name", group = "Target" },
        { token = "@team.name", label = "Team Name", group = "Target" },
        { token = "@role.name", label = "Role Name", group = "Target" },
        { token = "@date.today", label = "Today", group = "Time" },
        { token = "@time.now", label = "Current Time", group = "Time" },
        { token = "@time.left", label = "Time Left", group = "Time" },
    }
end

function MP:GetSelectedPlaceholder()
    local rows = self:GetPlaceholderRows()
    if #rows == 0 then
        return nil
    end

    self.selectedPlaceholderIndex = math.max(1, math.min(#rows, tonumber(self.selectedPlaceholderIndex) or 1))
    return rows[self.selectedPlaceholderIndex]
end

function MP:RefreshPlaceholderPicker()
    local row = self:GetSelectedPlaceholder()
    if self.placeholderPickerBtn then
        self.placeholderPickerBtn:SetLabel(row and row.token or "Placeholder")
        if row and self.placeholderPickerBtn.SetTooltip then
            self.placeholderPickerBtn:SetTooltip(row.label or row.token, row.description or row.group or "")
        end
    end
end

function MP:CyclePlaceholder()
    local rows = self:GetPlaceholderRows()
    if #rows == 0 then
        return
    end

    self.selectedPlaceholderIndex = (tonumber(self.selectedPlaceholderIndex) or 1) + 1
    if self.selectedPlaceholderIndex > #rows then
        self.selectedPlaceholderIndex = 1
    end
    self:RefreshPlaceholderPicker()
end

function MP:InsertSelectedPlaceholder()
    local row = self:GetSelectedPlaceholder()
    if not row or not self.bodyInput then
        return
    end

    local token = row.token or row.key
    if self.bodyInput.Insert then
        self.bodyInput:SetFocus()
        self.bodyInput:Insert(token)
    else
        self.bodyInput:SetText((self.bodyInput:GetText() or "") .. token)
    end
    if self.currentDraft then
        self.currentDraft.dirty = true
    end
end

function MP:SetPlaceholderWarnings(warnings)
    self.placeholderWarnings = warnings or {}
    if not self.placeholderWarningLabel then
        return
    end

    if #self.placeholderWarnings == 0 then
        self.placeholderWarningLabel:SetText("")
        self.placeholderWarningLabel:Hide()
        return
    end

    local text = self.placeholderWarnings[1]
    if #self.placeholderWarnings > 1 then
        text = text .. string.format(" (+%d more)", #self.placeholderWarnings - 1)
    end
    self.placeholderWarningLabel:SetText(text)
    self.placeholderWarningLabel:Show()
end

function MP:ClearEditorInputs()
    if self.titleInput then
        self.titleInput:SetText("")
    end
    if self.notesInput then
        self.notesInput:SetText("")
    end
    if self.bodyInput then
        self.bodyInput:SetText("")
    end
    if self.bodyCountLabel then
        self.bodyCountLabel:SetText("0 chars")
    end
end

function MP:DuplicateSelectedMessage()
    local svc = MS()
    local draft = self:CollectDraft()
    if not svc or not draft.id then
        GC.UI.MainFrame:SetStatus("Select a saved message to duplicate.", "textWarn")
        return
    end

    local message, err = svc:DuplicateMessage(draft.id)
    if not message then
        GC.UI.MainFrame:SetStatus(err or "Unable to duplicate message.", "textDanger")
        return
    end

    self:LoadDraft(message)
    self:Refresh()
    GC.UI.MainFrame:SetStatus("Message duplicated.", "textSuccess")
end

function MP:ToggleSelectedFavorite()
    local svc = MS()
    local draft = self:CollectDraft()
    if not svc or not draft.id then
        GC.UI.MainFrame:SetStatus("Select a saved message first.", "textWarn")
        return
    end

    local ok, err = svc:ToggleMessageFavorite(draft.id)
    if not ok then
        GC.UI.MainFrame:SetStatus(err or "Unable to update favorite.", "textDanger")
        return
    end

    self:LoadDraft(svc:GetMessage(draft.id))
    self:Refresh()
end

function MP:ToggleSelectedArchive()
    local svc = MS()
    local draft = self:CollectDraft()
    if not svc or not draft.id then
        GC.UI.MainFrame:SetStatus("Select a saved message first.", "textWarn")
        return
    end

    local message = svc:GetMessage(draft.id)
    local ok, err
    if message and message.archived then
        ok, err = svc:UnarchiveMessage(draft.id)
    else
        ok, err = svc:ArchiveMessage(draft.id)
    end
    if not ok then
        GC.UI.MainFrame:SetStatus(err or "Unable to update archive state.", "textDanger")
        return
    end

    local updated = svc:GetMessage(draft.id)
    if updated and (self.showArchived or not updated.archived) then
        self:LoadDraft(updated)
    else
        self:ResetDraft(svc:GetSelectedCategoryId() or "general")
    end
    self:Refresh()
    GC.UI.MainFrame:SetStatus(updated and updated.archived and "Message archived." or "Message unarchived.", "textWarn")
end

function MP:PromptDeleteSelectedMessage()
    local draft = self:CollectDraft()
    if not draft.id then
        GC.UI.MainFrame:SetStatus("Select a saved message to delete.", "textWarn")
        return
    end
    self.pendingDeleteMessageId = draft.id
    StaticPopup_Show("GUILDCORE_MESSAGES_DELETE_TEMPLATE", nil, nil, self)
end

function MP:ConfirmDeleteMessage()
    local svc = MS()
    local messageId = self.pendingDeleteMessageId
    self.pendingDeleteMessageId = nil
    if not svc or not messageId then
        return
    end

    local ok, err = svc:DeleteMessage(messageId)
    if not ok then
        GC.UI.MainFrame:SetStatus(err or "Unable to delete message.", "textDanger")
        return
    end
    self:ResetDraft(svc:GetSelectedCategoryId() or "general")
    self:ClearEditorInputs()
    self.previewData = {}
    self.selectedPreviewKey = nil
    self:SetPlaceholderWarnings({})
    self:Refresh()
    GC.UI.MainFrame:SetStatus("Message deleted.", "textWarn")
end

function MP:ToggleSelectedCategoryCollapsed()
    local svc = MS()
    local categoryId = svc and svc:GetSelectedCategoryId()
    local ok, err
    if categoryId then
        ok, err = svc:ToggleCategoryCollapsed(categoryId)
    end
    if not ok then
        GC.UI.MainFrame:SetStatus(err or "Unable to collapse category.", "textWarn")
        return
    end
    self:Refresh()
end

function MP:ToggleSelectedCategoryArchived()
    local svc = MS()
    local categoryId = svc and svc:GetSelectedCategoryId()
    local category = categoryId and svc:GetCategory(categoryId)
    local ok, err
    if category and category.archived then
        ok, err = svc:UnarchiveCategory(categoryId)
    else
        ok, err = svc:ArchiveCategory(categoryId)
    end
    if not ok then
        GC.UI.MainFrame:SetStatus(err or "Unable to update category archive state.", "textDanger")
        return
    end
    if not self.showArchived and category and not category.archived then
        self:SelectCategory("general")
    else
        self:Refresh()
    end
end

function MP:EnsureTemplateBridgeDialog()
    if self.bridgeDialog then
        return self.bridgeDialog
    end

    local Th = T()
    local dialog = CreateFrame("Frame", nil, UIParent)
    dialog:SetSize(560, 420)
    dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    dialog:SetFrameStrata("DIALOG")
    dialog:SetFrameLevel(100)
    dialog:EnableMouse(true)
    dialog:SetMovable(true)
    dialog:RegisterForDrag("LeftButton")
    dialog:SetScript("OnDragStart", function(self) self:StartMoving() end)
    dialog:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
    dialog:Hide()
    Th.Bg(dialog, Th.c.panel, Th.c.borderStrong)

    local title = Th.Fs(dialog, "header", "Template Bridge", "textPrimary")
    title:SetPoint("TOPLEFT", 14, -14)
    dialog.title = title

    local info = Th.Fs(dialog, "data", "", "textDimmed")
    info:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    info:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -14, -42)
    info:SetJustifyH("LEFT")
    dialog.info = info

    local holder, edit = createMultilineInput(dialog, 260)
    holder:SetPoint("TOPLEFT", info, "BOTTOMLEFT", 0, -10)
    holder:SetPoint("RIGHT", dialog, "RIGHT", -14, 0)
    dialog.editHolder = holder
    dialog.edit = edit

    local summary = Th.Fs(dialog, "data", "", "textWarn")
    summary:SetPoint("TOPLEFT", holder, "BOTTOMLEFT", 0, -8)
    summary:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -14, 0)
    summary:SetJustifyH("LEFT")
    dialog.summary = summary

    local validateBtn = GC.UI.Button.Create(dialog, "Validate", "secondary", 76, Th.btnH)
    validateBtn:SetPoint("BOTTOMLEFT", dialog, "BOTTOMLEFT", 14, 14)
    validateBtn:SetScript("OnClick", function()
        self:ValidateTemplateImport()
    end)
    dialog.validateBtn = validateBtn

    local importBtn = GC.UI.Button.Create(dialog, "Import", "success", 64, Th.btnH)
    importBtn:SetPoint("LEFT", validateBtn, "RIGHT", 8, 0)
    importBtn:SetScript("OnClick", function()
        self:ConfirmTemplateImport()
    end)
    dialog.importBtn = importBtn

    local closeBtn = GC.UI.Button.Create(dialog, "Close", "secondary", 64, Th.btnH)
    closeBtn:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -14, 14)
    closeBtn:SetScript("OnClick", function()
        dialog:Hide()
    end)
    dialog.closeBtn = closeBtn

    self.bridgeDialog = dialog
    return dialog
end

function MP:ShowTemplateExport(messageIds)
    local bridge = TB()
    if not bridge then
        GC.UI.MainFrame:SetStatus("Template bridge is unavailable.", "textWarn")
        return
    end

    local text, err, count = bridge:ExportTemplates({ messageIds = messageIds })
    if not text then
        GC.UI.MainFrame:SetStatus(err or "Unable to export templates.", "textWarn")
        return
    end

    local dialog = self:EnsureTemplateBridgeDialog()
    dialog.mode = "export"
    dialog.title:SetText("Export Templates")
    dialog.info:SetText(string.format("%d template(s) exported. Select the text below and copy it manually.", count or 0))
    dialog.summary:SetText("Usage history and player-sensitive state are not included.")
    dialog.edit:SetText(text)
    dialog.edit:HighlightText()
    dialog.validateBtn:Hide()
    dialog.importBtn:Hide()
    dialog:Show()
end

function MP:ShowTemplateImport()
    local dialog = self:EnsureTemplateBridgeDialog()
    dialog.mode = "import"
    dialog.title:SetText("Import Templates")
    dialog.info:SetText("Paste a GuildCore template export below, validate it, then import. Existing templates are preserved; imports become local copies.")
    dialog.summary:SetText("")
    dialog.edit:SetText("")
    dialog.validateBtn:Show()
    dialog.importBtn:Show()
    dialog.importBtn:SetEnabled(false)
    dialog:Show()
    dialog.edit:SetFocus()
end

function MP:ValidateTemplateImport()
    local bridge = TB()
    local dialog = self:EnsureTemplateBridgeDialog()
    if not bridge then
        dialog.summary:SetText("Template bridge is unavailable.")
        dialog.importBtn:SetEnabled(false)
        return nil
    end

    local summary, err = bridge:PreviewTemplateImport(dialog.edit:GetText() or "")
    if not summary then
        dialog.summary:SetText(err or "Import could not be validated.")
        dialog.importBtn:SetEnabled(false)
        return nil
    end

    local text = string.format(
        "%d template(s), %d missing categor%s, %d duplicate title%s detected.",
        summary.templateCount or 0,
        summary.categoryCount or 0,
        (summary.categoryCount or 0) == 1 and "y" or "ies",
        summary.duplicateCount or 0,
        (summary.duplicateCount or 0) == 1 and "" or "s"
    )
    if (summary.duplicateCount or 0) > 0 then
        text = text .. " Duplicates will import as copies."
    end
    dialog.summary:SetText(text)
    dialog.importBtn:SetEnabled(true)
    return summary
end

function MP:ConfirmTemplateImport()
    local summary = self:ValidateTemplateImport()
    if not summary then
        return
    end

    local bridge = TB()
    local dialog = self:EnsureTemplateBridgeDialog()
    if not bridge then
        dialog.summary:SetText("Template bridge is unavailable.")
        return
    end

    local result, err = bridge:ImportTemplates(dialog.edit:GetText() or "")
    if not result then
        dialog.summary:SetText(err or "Import failed.")
        return
    end

    dialog.summary:SetText(string.format("Imported %d template(s).", result.importedCount or 0))
    dialog.importBtn:SetEnabled(false)
    self:Refresh()
    GC.UI.MainFrame:SetStatus("Templates imported.", "textSuccess")
end

local function buildMessageRow(row, item)
    local Th = T()
    row._item = item

    if not row._title then
        local dragBtn = CreateFrame("Button", nil, row)
        dragBtn:SetSize(18, 18)
        dragBtn:SetPoint("LEFT", 4, 0)
        local dragLabel = Th.Fs(dragBtn, "tiny", "|||", "textDimmed")
        dragLabel:SetAllPoints()
        dragLabel:SetJustifyH("CENTER")
        dragLabel:SetJustifyV("MIDDLE")
        dragBtn:SetScript("OnMouseDown", function(_, button)
            if button == "LeftButton" and row._item and row._item.id then
                MP:StartMessageDrag(row._item.id)
            end
        end)
        row._dragBtn = dragBtn

        local sendBtn = GC.UI.Button.Create(row, "Send", "primary", 42, 18)
        sendBtn:SetPoint("RIGHT", -8, 0)
        sendBtn:SetTooltip("Direct Send", "Queues this saved template immediately. In Auto Mode it also starts the auto-send loop.")
        sendBtn:SetScript("OnClick", function()
            if row._item and row._item.id then
                MP:DirectSendTemplate(row._item.id)
            end
        end)
        row._sendBtn = sendBtn

        local titleFs = Th.Fs(row, "data", "", "textPrimary")
        titleFs:SetPoint("TOPLEFT", 28, -5)
        titleFs:SetPoint("TOPRIGHT", -56, -5)
        titleFs:SetJustifyH("LEFT")
        row._title = titleFs

        local stampFs = Th.Fs(row, "data", "", "textDimmed")
        stampFs:SetPoint("BOTTOMLEFT", 28, 5)
        stampFs:SetJustifyH("LEFT")
        row._stamp = stampFs

        local subFs = Th.Fs(row, "data", "", "textSecond")
        subFs:SetPoint("BOTTOMLEFT", 128, 5)
        subFs:SetPoint("BOTTOMRIGHT", -56, 5)
        subFs:SetJustifyH("LEFT")
        row._sub = subFs
    end

    local title = item.title or "Untitled Message"
    if item.favorite then
        title = "[Fav] " .. title
    end
    if item.archived then
        title = title .. " [Archived]"
    end
    row._title:SetText(title)
    row._stamp:SetText(item.lastUsedLabel and ("Used " .. item.lastUsedLabel) or (item.updatedLabel and ("Updated " .. item.updatedLabel) or ""))

    local snippet = trim(item.notes ~= "" and item.notes or item.body or "")
    if #snippet > 40 then
        snippet = snippet:sub(1, 37) .. "..."
    end
    row._sub:SetText(snippet ~= "" and snippet or "No notes")
end

local function buildHistoryRow(row, item)
    local Th = T()
    row._item = item

    if not row._title then
        local titleFs = Th.Fs(row, "data", "", "textPrimary")
        titleFs:SetPoint("TOPLEFT", 6, -5)
        titleFs:SetPoint("TOPRIGHT", -6, -5)
        titleFs:SetJustifyH("LEFT")
        row._title = titleFs

        local metaFs = Th.Fs(row, "data", "", "textDimmed")
        metaFs:SetPoint("BOTTOMLEFT", 6, 5)
        metaFs:SetPoint("BOTTOMRIGHT", -6, 5)
        metaFs:SetJustifyH("LEFT")
        row._meta = metaFs
    end

    local title = trim(item.title or "")
    if title == "" then
        title = "Untitled Message"
    end
    if #title > 36 then
        title = title:sub(1, 33) .. "..."
    end
    row._title:SetText(title)

    local target = item.target or "GUILD"
    if item.recipient and item.recipient ~= "" then
        target = target .. " " .. item.recipient
    end
    row._meta:SetText(string.format("%s  %s  %d chunks", item.sentLabel or "", target, tonumber(item.chunkCount) or 1))
end

local function buildPreviewRow(row, item)
    local Th = T()
    row._item = item

    if not row._idx then
        local idxFs = Th.Fs(row, "data", "", "textAccent")
        idxFs:SetPoint("TOPLEFT", 8, -5)
        row._idx = idxFs

        local lenFs = Th.Fs(row, "data", "", "textDimmed")
        lenFs:SetPoint("TOPRIGHT", -8, -5)
        row._len = lenFs

        local textFs = Th.Fs(row, "data", "", "textSecond")
        textFs:SetPoint("TOPLEFT", 8, -18)
        textFs:SetPoint("TOPRIGHT", -8, -18)
        textFs:SetPoint("BOTTOMLEFT", 8, 5)
        textFs:SetPoint("BOTTOMRIGHT", -8, 5)
        textFs:SetJustifyH("LEFT")
        textFs:SetJustifyV("TOP")
        row._text = textFs
    end

    row._idx:SetText(string.format("Chunk %d", item.index or 1))
    row._len:SetText(string.format("%d chars", item.length or 0))

    local text = trim(item.text or "")
    if #text > 120 then
        text = text:sub(1, 117) .. "..."
    end
    row._text:SetText(text)
end

function MP:ClampChunkLimit(value)
    value = tonumber(value) or DEFAULT_CHUNK_LIMIT
    value = math.floor(value)
    if value < MIN_CHUNK_LIMIT then
        value = MIN_CHUNK_LIMIT
    elseif value > MAX_CHUNK_LIMIT then
        value = MAX_CHUNK_LIMIT
    end
    return value
end

function MP:GetChannelRows()
    local svc = MS()
    if not svc or not svc.GetSupportedChannels then
        return {
            { key = "GUILD", label = "Guild", chatPrefix = "/g ", requiresRecipient = false, risky = false },
        }
    end
    return svc:GetSupportedChannels()
end

function MP:GetSelectedChannelKey(fallback)
    local svc = MS()
    local key = self.selectedChannelKey or fallback or "GUILD"
    if svc and svc.NormalizeChannel then
        return svc:NormalizeChannel(key)
    end
    return key or "GUILD"
end

function MP:GetSelectedChannelInfo(fallback)
    local svc = MS()
    local key = self:GetSelectedChannelKey(fallback)
    return svc and svc:GetChannelInfo(key) or { key = key, label = key, chatPrefix = "/g ", requiresRecipient = false, risky = false }
end

function MP:SetSelectedChannel(channelKey, markDirty)
    local info = self:GetSelectedChannelInfo(channelKey)
    self.selectedChannelKey = info.key or "GUILD"
    if self.currentDraft then
        self.currentDraft.targetChannel = self.selectedChannelKey
        if markDirty then
            self.currentDraft.dirty = true
        end
    end
    if self.channelBtn then
        self.channelBtn:SetLabel(info.label or self.selectedChannelKey)
    end
    local needsRecipient = info.requiresRecipient == true
    setFrameShown(self.recipientLabel, needsRecipient)
    setFrameShown(self.recipientInput, needsRecipient)
    if self.recipientInput then
        setEditBoxInteractive(self.recipientInput, needsRecipient)
    end
end

function MP:CycleChannel()
    local rows = self:GetChannelRows()
    if #rows == 0 then
        self:SetSelectedChannel("GUILD", false)
        return
    end

    local current = self:GetSelectedChannelKey()
    local nextIndex = 1
    for index, row in ipairs(rows) do
        if row.key == current then
            nextIndex = index + 1
            break
        end
    end
    if nextIndex > #rows then
        nextIndex = 1
    end

    self:SetSelectedChannel(rows[nextIndex].key, true)
    self:Refresh()
end

function MP:GetOutputOptions(fallbackChannel)
    local svc = MS()
    if not svc then
        return nil, "Messaging service is unavailable."
    end

    local options = {
        target = self:GetSelectedChannelKey(fallbackChannel),
        recipient = trim(self.recipientInput and self.recipientInput:GetText() or ""),
    }
    local ok, err, channel, normalized = svc:ValidateChannelOptions(options)
    if not ok then
        return nil, err
    end
    if type(normalized) ~= "table" then
        return nil, "Target channel validation did not return output options."
    end
    normalized.channelInfo = channel
    return normalized
end

function MP:NeedsOutputConfirmation(options, chunkCount)
    local info = options and options.channelInfo
    return (chunkCount or 0) > 3 or (info and info.risky == true)
end

function MP:PromptConfirmOutput(options)
    self.pendingOutputConfirmation = options
    local channel = options.channelInfo or { label = options.target or "Guild" }
    local text = string.format(
        "Confirm %s to %s?\nChunks: %d\nMode: %s",
        options.actionLabel or "output",
        channel.label or options.target or "Guild",
        options.chunkCount or 0,
        options.willAutoSend and "queue and auto-send" or "queue only"
    )
    StaticPopup_Show("GUILDCORE_MESSAGES_CONFIRM_OUTPUT", text, nil, self)
end

function MP:ConfirmPendingOutput()
    local pending = self.pendingOutputConfirmation
    self.pendingOutputConfirmation = nil
    if pending and pending.callback then
        pending.callback()
    end
end

function MP:RunWithOutputConfirmation(options)
    if self:NeedsOutputConfirmation(options, options.chunkCount) then
        self:PromptConfirmOutput(options)
        return
    end
    if options.callback then
        options.callback()
    end
end

function MP:GetQueuedOutputSummary()
    local svc = MS()
    local queue = svc and svc:GetQueue() or {}
    local summary = {
        chunkCount = #queue,
        target = "GUILD",
        channelInfo = svc and svc:GetChannelInfo("GUILD") or { key = "GUILD", label = "Guild", risky = false },
    }

    for _, row in ipairs(queue) do
        local target = row.target or "GUILD"
        local info = svc and svc:GetChannelInfo(target)
        if info then
            summary.target = info.key
            summary.channelInfo = info
            if info.risky then
                return summary
            end
        end
    end

    return summary
end

function MP:ResetDraft(categoryId)
    local svc = MS()
    self.currentDraft = {
        id = nil,
        title = "",
        notes = "",
        body = "",
        categoryId = categoryId or (svc and svc:GetSelectedCategoryId()) or "general",
        targetChannel = "GUILD",
        dirty = false,
    }
    self:SetSelectedChannel("GUILD", false)
    self.previewData = {}
    self.selectedPreviewKey = nil
    self:SetPlaceholderWarnings({})
end

function MP:CollectDraft()
    local draft = self.currentDraft or {}
    draft.title = trim(self.titleInput and self.titleInput:GetText() or "")
    draft.notes = trim(self.notesInput and self.notesInput:GetText() or "")
    draft.body = self.bodyInput and self.bodyInput:GetText() or ""
    draft.categoryId = draft.categoryId or ((MS() and MS():GetSelectedCategoryId()) or "general")
    draft.targetChannel = self:GetSelectedChannelKey(draft.targetChannel or "GUILD")
    self.currentDraft = draft
    return draft
end

function MP:LoadDraft(message)
    local svc = MS()
    local categoryId = message and message.categoryId or (svc and svc:GetSelectedCategoryId()) or "general"

    self.currentDraft = {
        id = message and message.id or nil,
        title = message and message.title or "",
        notes = message and message.notes or "",
        body = message and message.body or "",
        categoryId = categoryId,
        targetChannel = message and message.targetChannel or "GUILD",
        dirty = false,
    }

    self.titleInput:SetText(self.currentDraft.title or "")
    self.notesInput:SetText(self.currentDraft.notes or "")
    self.bodyInput:SetText(self.currentDraft.body or "")
    self.bodyCountLabel:SetText(string.format("%d chars", #(self.currentDraft.body or "")))
    self:SetSelectedChannel(self.currentDraft.targetChannel, false)
    self.previewData = {}
    self.selectedPreviewKey = nil
    self:SetPlaceholderWarnings({})

    if svc then
        svc:SetSelectedCategory(categoryId)
        svc:SetSelectedMessage(message and message.id or nil)
    end
end

function MP:SelectCategory(categoryId)
    local svc = MS()
    if not svc or not categoryId then
        return
    end

    svc:SetSelectedCategory(categoryId)
    local selectedMessageId = svc:GetSelectedMessageId()
    local selectedMessage = selectedMessageId and svc:GetMessage(selectedMessageId) or nil
    if selectedMessage and selectedMessage.categoryId == categoryId then
        self:LoadDraft(selectedMessage)
    else
        self:ResetDraft(categoryId)
        self:ClearEditorInputs()
        svc:SetSelectedMessage(nil)
    end

    self:Refresh()
end

function MP:GetResolveOptions()
    local svc = MS()
    local targetTime = svc and svc:GetDailyTargetTime() or { hour = 18, minute = 0 }
    local outputOptions = self:GetOutputOptions()
    local limit = self:ClampChunkLimit(self.limitInput and self.limitInput:GetText() or DEFAULT_CHUNK_LIMIT)
    return {
        targetName = self.targetInput and self.targetInput:GetText() or "",
        dailyTargetHour = targetTime.hour,
        dailyTargetMinute = targetTime.minute,
        limit = limit,
        includeNumbers = true,
        target = outputOptions and outputOptions.target or self:GetSelectedChannelKey(),
        recipient = outputOptions and outputOptions.recipient or nil,
    }
end

function MP:ApplyPlaceholderInputs()
    local svc = MS()
    if not svc then
        return false, "Messaging service unavailable."
    end

    local ok, err = svc:SetPreviewTargetName(self.targetInput and self.targetInput:GetText() or "")
    if not ok then
        return false, err
    end

    ok, err = svc:SetDailyTargetTime(self.timeInput and self.timeInput:GetText() or "18:00")
    if not ok then
        return false, err
    end

    ok, err = svc:SetAutoSendDelaySeconds(self.delayInput and self.delayInput:GetText() or "2")
    if not ok then
        return false, err
    end

    return true
end

function MP:GetSelectedPreviewChunk()
    for _, row in ipairs(self.previewData or {}) do
        if row.key == self.selectedPreviewKey then
            return row
        end
    end
    return self.previewData and self.previewData[1] or nil
end

function MP:RefreshPreview()
    local svc = MS()
    if not svc then
        return false
    end

    local ok, err = self:ApplyPlaceholderInputs()
    if not ok then
        GC.UI.MainFrame:SetStatus(err or "Invalid placeholder settings.", "textDanger")
        return false
    end

    local limit = self:ClampChunkLimit(self.limitInput:GetText() or DEFAULT_CHUNK_LIMIT)
    self.limitInput:SetText(tostring(limit))

    local draft = self:CollectDraft()
    self.previewData = svc:BuildPreview(draft.body, self:GetResolveOptions())
    self.selectedPreviewKey = self.previewData[1] and self.previewData[1].key or nil
    self:SetPlaceholderWarnings(self.previewData.placeholderWarnings or {})
    self:Refresh()
    return true
end

function MP:PromptEnableAutoMode()
    StaticPopup_Show("GUILDCORE_MESSAGES_ENABLE_AUTO", nil, nil, self)
end

function MP:PromptStartAutoSend()
    local svc = MS()
    local summary = self:GetQueuedOutputSummary()

    summary.willAutoSend = true
    summary.actionLabel = "auto-send"
    summary.callback = function()
        self:ConfirmStartAutoSend()
    end

    if svc and svc:IsAutoSending() then
        GC.UI.MainFrame:SetStatus("Auto-send is already running.", "textWarn")
        return
    end

    if self:NeedsOutputConfirmation(summary, summary.chunkCount) then
        self:PromptConfirmOutput(summary)
        return
    end

    StaticPopup_Show("GUILDCORE_MESSAGES_START_AUTO", nil, nil, self)
end

function MP:ConfirmEnableAutoMode()
    local svc = MS()
    local ok, err = self:ApplyPlaceholderInputs()
    if not ok then
        GC.UI.MainFrame:SetStatus(err or "Invalid automation settings.", "textDanger")
        return
    end

    if svc then
        ok, err = svc:SetAutomationEnabled(true)
    else
        ok, err = false, "Messaging service is unavailable."
    end
    if not ok then
        GC.UI.MainFrame:SetStatus(err or "Unable to enable Auto Mode.", "textDanger")
        return
    end

    self:Refresh()
    GC.UI.MainFrame:SetStatus("Auto Mode enabled.", "textWarn")
end

function MP:ConfirmStartAutoSend()
    local svc = MS()
    local ok, err = self:ApplyPlaceholderInputs()
    if not ok then
        GC.UI.MainFrame:SetStatus(err or "Invalid automation settings.", "textDanger")
        return
    end

    if svc then
        ok, err = svc:StartAutoSend()
    else
        ok, err = false, "Messaging service is unavailable."
    end
    if not ok then
        GC.UI.MainFrame:SetStatus(err or "Unable to start auto-send.", "textDanger")
        return
    end

    self:Refresh()
    GC.UI.MainFrame:SetStatus("Auto-send started.", "textSuccess")
end

function MP:Create(parent)
    if self.frame then
        return
    end

    if not StaticPopupDialogs.GUILDCORE_MESSAGES_ENABLE_AUTO then
        StaticPopupDialogs.GUILDCORE_MESSAGES_ENABLE_AUTO = {
            text = "Enable Auto Mode? Queued chunks will be allowed to send automatically using the configured delay.",
            button1 = "Enable",
            button2 = "Cancel",
            OnAccept = function(_, data)
                if data and data.ConfirmEnableAutoMode then
                    data:ConfirmEnableAutoMode()
                end
            end,
            timeout = 0,
            whileDead = 1,
            hideOnEscape = 1,
            preferredIndex = STATICPOPUP_NUMDIALOGS,
        }
    end

    if not StaticPopupDialogs.GUILDCORE_MESSAGES_START_AUTO then
        StaticPopupDialogs.GUILDCORE_MESSAGES_START_AUTO = {
            text = "Start auto-sending the queued chunks now?",
            button1 = "Start",
            button2 = "Cancel",
            OnAccept = function(_, data)
                if data and data.ConfirmStartAutoSend then
                    data:ConfirmStartAutoSend()
                end
            end,
            timeout = 0,
            whileDead = 1,
            hideOnEscape = 1,
            preferredIndex = STATICPOPUP_NUMDIALOGS,
        }
    end

    if not StaticPopupDialogs.GUILDCORE_MESSAGES_CONFIRM_OUTPUT then
        StaticPopupDialogs.GUILDCORE_MESSAGES_CONFIRM_OUTPUT = {
            text = "%s",
            button1 = "Confirm",
            button2 = "Cancel",
            OnAccept = function(_, data)
                if data and data.ConfirmPendingOutput then
                    data:ConfirmPendingOutput()
                end
            end,
            timeout = 0,
            whileDead = 1,
            hideOnEscape = 1,
            preferredIndex = STATICPOPUP_NUMDIALOGS,
        }
    end

    if not StaticPopupDialogs.GUILDCORE_MESSAGES_DELETE_TEMPLATE then
        StaticPopupDialogs.GUILDCORE_MESSAGES_DELETE_TEMPLATE = {
            text = "Delete this saved message template? This cannot be undone.",
            button1 = "Delete",
            button2 = "Cancel",
            OnAccept = function(_, data)
                if data and data.ConfirmDeleteMessage then
                    data:ConfirmDeleteMessage()
                end
            end,
            timeout = 0,
            whileDead = 1,
            hideOnEscape = 1,
            preferredIndex = STATICPOPUP_NUMDIALOGS,
        }
    end

    local Th = T()
    local P = Th.padding

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    frame:Hide()
    Th.Bg(frame, Th.c.bg)
    self.frame = frame

    local titleFs = Th.Fs(frame, "header", "Messages", "textPrimary")
    titleFs:SetPoint("TOPLEFT", P, -P)

    local subtitleFs = Th.Fs(frame, "small", "Reusable templates, placeholders, queue safety, and optional automation.", "textDimmed")
    subtitleFs:SetPoint("LEFT", titleFs, "RIGHT", 10, -1)

    local disabledFs = Th.Fs(frame, "small", "Messaging module is disabled in Settings.", "textWarn")
    disabledFs:SetPoint("TOPLEFT", P, -(P + 26))
    disabledFs:Hide()
    self.disabledBanner = disabledFs

    local topOffset = -(P + 52)

    local categoriesCard, categoriesContent = GC.UI.Panel.Section(frame, "Categories")
    categoriesCard:SetPoint("TOPLEFT", frame, "TOPLEFT", P, topOffset)
    categoriesCard:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", P, P)
    categoriesCard:SetWidth(188)

    local categoryNameLabel = Th.Fs(categoriesContent, "tiny", "Category Name", "textDimmed")
    categoryNameLabel:SetPoint("TOPLEFT", 0, 0)

    local categoryInput = GC.UI.Panel.Input(categoriesContent, 156, Th.inputH)
    categoryInput:SetPoint("TOPLEFT", categoryNameLabel, "BOTTOMLEFT", 0, -6)
    self.categoryInput = categoryInput

    local categoryNewBtn = GC.UI.Button.Create(categoriesContent, "New", "primary", 48, Th.btnH)
    categoryNewBtn:SetPoint("TOPLEFT", categoryInput, "BOTTOMLEFT", 0, -8)
    categoryNewBtn:SetScript("OnClick", function()
        local svc = MS()
        local category, err
        if svc then
            category, err = svc:CreateCategory(self.categoryInput:GetText() or "")
        end
        if not category then
            GC.UI.MainFrame:SetStatus(err or "Unable to create category.", "textDanger")
            return
        end
        self.categoryInput:SetText(category.name or "")
        self:SelectCategory(category.id)
        GC.UI.MainFrame:SetStatus("Category created.", "textSuccess")
    end)
    self.categoryNewBtn = categoryNewBtn

    local categoryRenameBtn = GC.UI.Button.Create(categoriesContent, "Rename", "secondary", 58, Th.btnH)
    categoryRenameBtn:SetPoint("LEFT", categoryNewBtn, "RIGHT", 6, 0)
    categoryRenameBtn:SetScript("OnClick", function()
        local svc = MS()
        local ok, err
        if svc then
            ok, err = svc:RenameCategory(svc:GetSelectedCategoryId(), self.categoryInput:GetText() or "")
        end
        if not ok then
            GC.UI.MainFrame:SetStatus(err or "Unable to rename category.", "textDanger")
            return
        end
        self:Refresh()
        GC.UI.MainFrame:SetStatus("Category renamed.", "textSuccess")
    end)
    self.categoryRenameBtn = categoryRenameBtn

    local categoryDeleteBtn = GC.UI.Button.Create(categoriesContent, "Delete", "danger", 52, Th.btnH)
    categoryDeleteBtn:SetPoint("LEFT", categoryRenameBtn, "RIGHT", 6, 0)
    categoryDeleteBtn:SetScript("OnClick", function()
        local svc = MS()
        local ok, err
        if svc then
            ok, err = svc:DeleteCategory(svc:GetSelectedCategoryId(), "general")
        end
        if not ok then
            GC.UI.MainFrame:SetStatus(err or "Unable to delete category.", "textDanger")
            return
        end
        self.categoryInput:SetText("General")
        self:SelectCategory("general")
        GC.UI.MainFrame:SetStatus("Category deleted. Messages were reassigned to General.", "textWarn")
    end)
    self.categoryDeleteBtn = categoryDeleteBtn

    local categoryUpBtn = GC.UI.Button.Create(categoriesContent, "Up", "secondary", 36, Th.btnH)
    categoryUpBtn:SetPoint("TOPLEFT", categoryNewBtn, "BOTTOMLEFT", 0, -6)
    categoryUpBtn:SetScript("OnClick", function()
        local svc = MS()
        local ok, err
        if svc then
            ok, err = svc:MoveCategoryUp(svc:GetSelectedCategoryId())
        end
        if not ok then
            GC.UI.MainFrame:SetStatus(err or "Unable to move category.", "textWarn")
            return
        end
        self:Refresh()
    end)
    self.categoryUpBtn = categoryUpBtn

    local categoryDownBtn = GC.UI.Button.Create(categoriesContent, "Down", "secondary", 48, Th.btnH)
    categoryDownBtn:SetPoint("LEFT", categoryUpBtn, "RIGHT", 6, 0)
    categoryDownBtn:SetScript("OnClick", function()
        local svc = MS()
        local ok, err
        if svc then
            ok, err = svc:MoveCategoryDown(svc:GetSelectedCategoryId())
        end
        if not ok then
            GC.UI.MainFrame:SetStatus(err or "Unable to move category.", "textWarn")
            return
        end
        self:Refresh()
    end)
    self.categoryDownBtn = categoryDownBtn

    local categoryCollapseBtn = GC.UI.Button.Create(categoriesContent, "Collapse", "secondary", 68, Th.btnH)
    categoryCollapseBtn:SetPoint("LEFT", categoryDownBtn, "RIGHT", 6, 0)
    categoryCollapseBtn:SetScript("OnClick", function()
        self:ToggleSelectedCategoryCollapsed()
    end)
    self.categoryCollapseBtn = categoryCollapseBtn

    local categoryArchiveBtn = GC.UI.Button.Create(categoriesContent, "Archive", "secondary", 70, Th.btnH)
    categoryArchiveBtn:SetPoint("TOPLEFT", categoryUpBtn, "BOTTOMLEFT", 0, -6)
    categoryArchiveBtn:SetScript("OnClick", function()
        self:ToggleSelectedCategoryArchived()
    end)
    self.categoryArchiveBtn = categoryArchiveBtn

    local categoryListFrame = CreateFrame("Frame", nil, categoriesContent)
    categoryListFrame:SetPoint("TOPLEFT", categoryArchiveBtn, "BOTTOMLEFT", 0, -12)
    categoryListFrame:SetPoint("BOTTOMRIGHT", categoriesContent, "BOTTOMRIGHT", 0, 0)
    self.categoryList = GC.UI.List.Create(categoryListFrame, 28, buildCategoryRow, function(item)
        self.categoryInput:SetText(item.name or "")
        self:SelectCategory(item.id)
    end)
    self.categoryList:SetEmptyText("No categories yet.")

    local templatesCard, templatesContent = GC.UI.Panel.Section(frame, "Templates")
    templatesCard:SetPoint("TOPLEFT", categoriesCard, "TOPRIGHT", 10, 0)
    templatesCard:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 210, P)
    templatesCard:SetWidth(256)

    local messageNewBtn = GC.UI.Button.Create(templatesContent, "New", "primary", 46, Th.btnH)
    messageNewBtn:SetPoint("TOPLEFT", 0, -4)
    messageNewBtn:SetScript("OnClick", function()
        local svc = MS()
        self:ResetDraft(svc and svc:GetSelectedCategoryId() or "general")
        self:ClearEditorInputs()
        if svc then
            svc:SetSelectedMessage(nil)
        end
        self.previewData = {}
        self.selectedPreviewKey = nil
        self:SetPlaceholderWarnings({})
        self:Refresh()
    end)
    self.messageNewBtn = messageNewBtn

    local messageDeleteBtn = GC.UI.Button.Create(templatesContent, "Delete", "danger", 58, Th.btnH)
    messageDeleteBtn:SetPoint("LEFT", messageNewBtn, "RIGHT", 6, 0)
    messageDeleteBtn:SetScript("OnClick", function()
        self:PromptDeleteSelectedMessage()
    end)
    self.messageDeleteBtn = messageDeleteBtn

    local moveUpBtn = GC.UI.Button.Create(templatesContent, "Up", "secondary", 38, Th.btnH)
    moveUpBtn:SetPoint("LEFT", messageDeleteBtn, "RIGHT", 6, 0)
    moveUpBtn:SetScript("OnClick", function()
        local svc = MS()
        local draft = self:CollectDraft()
        local ok, err
        if draft.id and svc then
            ok, err = svc:MoveMessageUp(draft.id)
        end
        if not ok then
            GC.UI.MainFrame:SetStatus(err or "Unable to move message.", "textWarn")
            return
        end
        self:Refresh()
    end)
    self.moveUpBtn = moveUpBtn

    local moveDownBtn = GC.UI.Button.Create(templatesContent, "Down", "secondary", 48, Th.btnH)
    moveDownBtn:SetPoint("LEFT", moveUpBtn, "RIGHT", 6, 0)
    moveDownBtn:SetScript("OnClick", function()
        local svc = MS()
        local draft = self:CollectDraft()
        local ok, err
        if draft.id and svc then
            ok, err = svc:MoveMessageDown(draft.id)
        end
        if not ok then
            GC.UI.MainFrame:SetStatus(err or "Unable to move message.", "textWarn")
            return
        end
        self:Refresh()
    end)
    self.moveDownBtn = moveDownBtn

    local moveHereBtn = GC.UI.Button.Create(templatesContent, "Move Here", "secondary", 72, Th.btnH)
    moveHereBtn:SetPoint("TOPLEFT", messageNewBtn, "BOTTOMLEFT", 0, -8)
    moveHereBtn:SetScript("OnClick", function()
        local svc = MS()
        local draft = self:CollectDraft()
        if not draft.id then
            GC.UI.MainFrame:SetStatus("Select a saved message to move.", "textWarn")
            return
        end
        local ok, err
        if svc then
            ok, err = svc:MoveMessageToCategory(draft.id, svc:GetSelectedCategoryId())
        end
        if not ok then
            GC.UI.MainFrame:SetStatus(err or "Unable to move message.", "textDanger")
            return
        end
        self:LoadDraft(svc:GetMessage(draft.id))
        self:Refresh()
        GC.UI.MainFrame:SetStatus("Message moved to selected category.", "textSuccess")
    end)
    self.moveHereBtn = moveHereBtn

    local saveBtn = GC.UI.Button.Create(templatesContent, "Save", "success", 50, Th.btnH)
    saveBtn:SetPoint("LEFT", moveHereBtn, "RIGHT", 6, 0)
    saveBtn:SetScript("OnClick", function()
        local svc = MS()
        local draft = self:CollectDraft()
        if draft.title == "" then
            GC.UI.MainFrame:SetStatus("Message title is required.", "textDanger")
            return
        end
        if trim(draft.body) == "" then
            GC.UI.MainFrame:SetStatus("Message body is required.", "textDanger")
            return
        end

        local ok, err
        if draft.id then
            ok, err = svc:UpdateMessage(draft.id, draft)
            if not ok then
                GC.UI.MainFrame:SetStatus(err or "Unable to save message.", "textDanger")
                return
            end
        else
            local saved
            saved, err = svc:CreateMessage(draft)
            if not saved then
                GC.UI.MainFrame:SetStatus(err or "Unable to create message.", "textDanger")
                return
            end
            draft.id = saved.id
        end

        self:LoadDraft(svc:GetMessage(draft.id))
        self:Refresh()
        GC.UI.MainFrame:SetStatus("Message saved.", "textSuccess")
    end)
    self.saveBtn = saveBtn

    local duplicateBtn = GC.UI.Button.Create(templatesContent, "Duplicate", "secondary", 76, Th.btnH)
    duplicateBtn:SetPoint("TOPLEFT", moveHereBtn, "BOTTOMLEFT", 0, -8)
    duplicateBtn:SetScript("OnClick", function()
        self:DuplicateSelectedMessage()
    end)
    self.duplicateBtn = duplicateBtn

    local favoriteBtn = GC.UI.Button.Create(templatesContent, "Favorite", "secondary", 68, Th.btnH)
    favoriteBtn:SetPoint("LEFT", duplicateBtn, "RIGHT", 6, 0)
    favoriteBtn:SetScript("OnClick", function()
        self:ToggleSelectedFavorite()
    end)
    self.favoriteBtn = favoriteBtn

    local archiveBtn = GC.UI.Button.Create(templatesContent, "Archive", "secondary", 64, Th.btnH)
    archiveBtn:SetPoint("LEFT", favoriteBtn, "RIGHT", 6, 0)
    archiveBtn:SetScript("OnClick", function()
        self:ToggleSelectedArchive()
    end)
    self.archiveBtn = archiveBtn

    local searchLabel = Th.Fs(templatesContent, "tiny", "Search", "textDimmed")
    searchLabel:SetPoint("TOPLEFT", duplicateBtn, "BOTTOMLEFT", 0, -14)

    local searchInput = GC.UI.Panel.Input(templatesContent, 170, Th.inputH)
    searchInput:SetPoint("TOPLEFT", searchLabel, "BOTTOMLEFT", 0, -4)
    searchInput:SetScript("OnTextChanged", function()
        self:Refresh()
    end)
    self.searchInput = searchInput

    local showArchivedBtn = GC.UI.Button.Create(templatesContent, "Archived: Off", "secondary", 92, Th.btnH)
    showArchivedBtn:SetPoint("TOPLEFT", searchInput, "BOTTOMLEFT", 0, -8)
    showArchivedBtn:SetScript("OnClick", function()
        self.showArchived = not self.showArchived
        self:Refresh()
    end)
    self.showArchivedBtn = showArchivedBtn

    local favoritesOnlyBtn = GC.UI.Button.Create(templatesContent, "Favs: Off", "secondary", 76, Th.btnH)
    favoritesOnlyBtn:SetPoint("LEFT", showArchivedBtn, "RIGHT", 6, 0)
    favoritesOnlyBtn:SetScript("OnClick", function()
        self.favoritesOnly = not self.favoritesOnly
        self:Refresh()
    end)
    self.favoritesOnlyBtn = favoritesOnlyBtn

    local exportBtn = GC.UI.Button.Create(templatesContent, "Export", "secondary", 58, Th.btnH)
    exportBtn:SetPoint("TOPLEFT", showArchivedBtn, "BOTTOMLEFT", 0, -8)
    exportBtn:SetTooltip("Export Selected", "Shows a copyable export for the selected saved template.")
    exportBtn:SetScript("OnClick", function()
        local draft = self:CollectDraft()
        if not draft.id then
            GC.UI.MainFrame:SetStatus("Select a saved message to export.", "textWarn")
            return
        end
        self:ShowTemplateExport({ draft.id })
    end)
    self.exportBtn = exportBtn

    local exportAllBtn = GC.UI.Button.Create(templatesContent, "Export All", "secondary", 76, Th.btnH)
    exportAllBtn:SetPoint("LEFT", exportBtn, "RIGHT", 6, 0)
    exportAllBtn:SetTooltip("Export All", "Shows a copyable export for all saved templates in this guild.")
    exportAllBtn:SetScript("OnClick", function()
        self:ShowTemplateExport()
    end)
    self.exportAllBtn = exportAllBtn

    local importBtn = GC.UI.Button.Create(templatesContent, "Import", "secondary", 58, Th.btnH)
    importBtn:SetPoint("LEFT", exportAllBtn, "RIGHT", 6, 0)
    importBtn:SetTooltip("Import Templates", "Validates and imports pasted GuildCore template exports as new local templates.")
    importBtn:SetScript("OnClick", function()
        self:ShowTemplateImport()
    end)
    self.importBtn = importBtn

    local messageListFrame = CreateFrame("Frame", nil, templatesContent)
    messageListFrame:SetPoint("TOPLEFT", exportBtn, "BOTTOMLEFT", 0, -12)
    messageListFrame:SetPoint("BOTTOMRIGHT", templatesContent, "BOTTOMRIGHT", 0, 0)
    self.messageList = GC.UI.List.Create(messageListFrame, MESSAGE_ROW_HEIGHT, buildMessageRow, function(item)
        local svc = MS()
        local message = svc and svc:GetMessage(item.id) or nil
        if message then
            self:LoadDraft(message)
            self:Refresh()
        end
    end)
    self.messageList:SetEmptyText("No saved messages in this category.")

    self.dropIndicator = self.messageList.content:CreateTexture(nil, "ARTWORK")
    self.dropIndicator:SetHeight(2)
    self.dropIndicator:SetColorTexture(Th.c.accent[1], Th.c.accent[2], Th.c.accent[3], 1)
    self.dropIndicator:Hide()

    self.dragOverlay = CreateFrame("Frame", nil, frame)
    self.dragOverlay:SetAllPoints(frame)
    self.dragOverlay:EnableMouse(true)
    self.dragOverlay:SetFrameStrata("DIALOG")
    self.dragOverlay:Hide()
    self.dragOverlay:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then
            self:FinishMessageDrag(false)
        end
    end)
    self.dragOverlay:SetScript("OnUpdate", function()
        self:UpdateMessageDragIndicator()
    end)

    local previewCard, previewContent = GC.UI.Panel.Section(frame, "Chunk Preview & Output")
    previewCard:SetPoint("LEFT", templatesCard, "RIGHT", 10, 0)
    previewCard:SetPoint("RIGHT", frame, "RIGHT", -P, 0)
    previewCard:SetPoint("BOTTOM", frame, "BOTTOM", 0, P)
    previewCard:SetHeight(380)

    local editorCard, editorContent = GC.UI.Panel.Section(frame, "Editor")
    editorCard:SetPoint("TOPLEFT", templatesCard, "TOPRIGHT", 10, 0)
    editorCard:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -P, topOffset)
    editorCard:SetPoint("BOTTOMLEFT", previewCard, "TOPLEFT", 0, 10)
    editorCard:SetPoint("BOTTOMRIGHT", previewCard, "TOPRIGHT", 0, 10)

    local titleLabel = Th.Fs(editorContent, "tiny", "Title", "textDimmed")
    titleLabel:SetPoint("TOPLEFT", 0, 0)

    local categoryLabel = Th.Fs(editorContent, "tiny", "Assigned Category", "textDimmed")
    categoryLabel:SetPoint("TOPLEFT", 278, 0)

    local titleInput = GC.UI.Panel.Input(editorContent, 250, Th.inputH)
    titleInput:SetPoint("TOPLEFT", titleLabel, "BOTTOMLEFT", 0, -6)
    titleInput:SetScript("OnTextChanged", function()
        if self.currentDraft then
            self.currentDraft.dirty = true
        end
    end)
    self.titleInput = titleInput

    local assignedCategoryFs = Th.Fs(editorContent, "data", "General", "textAccent")
    assignedCategoryFs:SetPoint("TOPLEFT", categoryLabel, "BOTTOMLEFT", 0, -8)
    self.assignedCategoryLabel = assignedCategoryFs

    local assignSelectedBtn = GC.UI.Button.Create(editorContent, "Assign Selected Category", "secondary", 154, Th.btnH)
    assignSelectedBtn:SetPoint("TOPRIGHT", editorContent, "TOPRIGHT", 0, -18)
    assignSelectedBtn:SetTooltip("Assign Selected Category", "Applies the currently selected category to this draft without saving yet.")
    assignSelectedBtn:SetScript("OnClick", function()
        local svc = MS()
        local selectedCategoryId = svc and svc:GetSelectedCategoryId() or "general"
        local category = svc and svc:GetCategory(selectedCategoryId) or nil
        self:CollectDraft()
        self.currentDraft.categoryId = selectedCategoryId
        self.assignedCategoryLabel:SetText(category and category.name or "General")
        self.currentDraft.dirty = true
    end)
    self.assignSelectedBtn = assignSelectedBtn

    local notesLabel = Th.Fs(editorContent, "tiny", "Notes", "textDimmed")
    notesLabel:SetPoint("TOPLEFT", titleInput, "BOTTOMLEFT", 0, -12)

    local notesInput = GC.UI.Panel.Input(editorContent, 430, Th.inputH)
    notesInput:SetPoint("TOPLEFT", notesLabel, "BOTTOMLEFT", 0, -6)
    notesInput:SetPoint("TOPRIGHT", editorContent, "TOPRIGHT", 0, -46)
    notesInput:SetScript("OnTextChanged", function()
        if self.currentDraft then
            self.currentDraft.dirty = true
        end
    end)
    self.notesInput = notesInput

    local bodyLabel = Th.Fs(editorContent, "tiny", "Message Body", "textDimmed")
    bodyLabel:SetPoint("TOPLEFT", notesInput, "BOTTOMLEFT", 0, -14)

    local placeholderPickerBtn = GC.UI.Button.Create(editorContent, "@player.name", "secondary", 112, Th.btnH)
    placeholderPickerBtn:SetPoint("TOPLEFT", bodyLabel, "BOTTOMLEFT", 0, -6)
    placeholderPickerBtn:SetTooltip("Placeholder Picker", "Cycles through available placeholders.")
    placeholderPickerBtn:SetScript("OnClick", function()
        self:CyclePlaceholder()
    end)
    self.placeholderPickerBtn = placeholderPickerBtn

    local insertPlaceholderBtn = GC.UI.Button.Create(editorContent, "Insert", "secondary", 54, Th.btnH)
    insertPlaceholderBtn:SetPoint("LEFT", placeholderPickerBtn, "RIGHT", 6, 0)
    insertPlaceholderBtn:SetTooltip("Insert Placeholder", "Inserts the selected placeholder into the message body at the cursor.")
    insertPlaceholderBtn:SetScript("OnClick", function()
        self:InsertSelectedPlaceholder()
    end)
    self.insertPlaceholderBtn = insertPlaceholderBtn

    local bodyHolder, bodyInput = createMultilineInput(editorContent, 210)
    bodyHolder:SetPoint("TOPLEFT", placeholderPickerBtn, "BOTTOMLEFT", 0, -6)
    bodyHolder:SetPoint("BOTTOMRIGHT", editorContent, "BOTTOMRIGHT", 0, 0)
    bodyInput:SetScript("OnTextChanged", function(self)
        self:SetWidth(math.max(120, bodyHolder:GetWidth() - 18))
        self:SetHeight(math.max(24, bodyHolder:GetHeight() - 12))
        MP.bodyCountLabel:SetText(string.format("%d chars", #(self:GetText() or "")))
        if self == MP.bodyInput and MP.currentDraft then
            MP.currentDraft.dirty = true
        end
    end)
    self.bodyInput = bodyInput

    local bodyCountFs = Th.Fs(editorContent, "data", "0 chars", "textDimmed")
    bodyCountFs:SetPoint("RIGHT", editorContent, "RIGHT", 0, 0)
    bodyCountFs:SetPoint("TOP", bodyLabel, "TOP", 0, 0)
    self.bodyCountLabel = bodyCountFs

    local previewInfoFs = Th.Fs(previewContent, "small", "Placeholders resolve only during preview/send. Drag templates with the handle. Manual Mode stays safest.", "textDimmed")
    previewInfoFs:SetPoint("TOPLEFT", 0, 0)
    previewInfoFs:SetPoint("TOPRIGHT", previewContent, "TOPRIGHT", 0, 0)
    previewInfoFs:SetJustifyH("LEFT")
    previewInfoFs:SetWordWrap(true)

    local placeholderFs = Th.Fs(previewContent, "tiny", "@player.name  @guild.name  @target.name  @discord.name  @main.name  @role.name  @date.today  @time.now", "textDimmed")
    placeholderFs:SetPoint("TOPLEFT", previewInfoFs, "BOTTOMLEFT", 0, -8)
    placeholderFs:SetWidth(560)
    placeholderFs:SetWordWrap(false)
    self.placeholderHintLabel = placeholderFs

    local placeholderWarningFs = Th.Fs(previewContent, "tiny", "", "textWarn")
    placeholderWarningFs:SetPoint("TOPLEFT", placeholderFs, "BOTTOMLEFT", 0, -4)
    placeholderWarningFs:SetPoint("TOPRIGHT", previewContent, "TOPRIGHT", 0, 0)
    placeholderWarningFs:SetJustifyH("LEFT")
    placeholderWarningFs:Hide()
    self.placeholderWarningLabel = placeholderWarningFs

    local channelLabel = Th.Fs(previewContent, "tiny", "Channel", "textDimmed")
    channelLabel:SetPoint("TOPLEFT", placeholderWarningFs, "BOTTOMLEFT", 0, -8)

    local channelBtn = GC.UI.Button.Create(previewContent, "Guild", "secondary", 74, Th.btnH)
    channelBtn:SetPoint("TOPLEFT", channelLabel, "BOTTOMLEFT", 0, -4)
    channelBtn:SetTooltip("Target Channel", "Cycles the channel used when queueing, sending, or loading chunks.")
    channelBtn:SetScript("OnClick", function()
        self:CycleChannel()
    end)
    self.channelBtn = channelBtn

    local recipientLabel = Th.Fs(previewContent, "tiny", "Recipient", "textDimmed")
    recipientLabel:SetPoint("TOPLEFT", channelLabel, "TOPLEFT", 94, 0)
    self.recipientLabel = recipientLabel

    local recipientInput = GC.UI.Panel.Input(previewContent, 110, Th.inputH)
    recipientInput:SetPoint("TOPLEFT", recipientLabel, "BOTTOMLEFT", 0, -4)
    recipientInput:SetScript("OnTextChanged", function()
        if self.currentDraft then
            self.currentDraft.dirty = true
        end
    end)
    self.recipientInput = recipientInput

    local targetLabel = Th.Fs(previewContent, "tiny", "Target", "textDimmed")
    targetLabel:SetPoint("TOPLEFT", channelBtn, "BOTTOMLEFT", 0, -20)

    local targetInput = GC.UI.Panel.Input(previewContent, 108, Th.inputH)
    targetInput:SetPoint("LEFT", targetLabel, "RIGHT", 6, 0)
    self.targetInput = targetInput

    local timeLabel = Th.Fs(previewContent, "tiny", "Daily Time", "textDimmed")
    timeLabel:SetPoint("LEFT", targetInput, "RIGHT", 14, 0)

    local timeInput = GC.UI.Panel.Input(previewContent, 56, Th.inputH)
    timeInput:SetPoint("LEFT", timeLabel, "RIGHT", 6, 0)
    self.timeInput = timeInput

    local delayLabel = Th.Fs(previewContent, "tiny", "Delay", "textDimmed")
    delayLabel:SetPoint("LEFT", timeInput, "RIGHT", 14, 0)

    local delayInput = GC.UI.Panel.Input(previewContent, 42, Th.inputH)
    delayInput:SetPoint("LEFT", delayLabel, "RIGHT", 6, 0)
    self.delayInput = delayInput

    local limitLabel = Th.Fs(previewContent, "tiny", "Limit", "textDimmed")
    limitLabel:SetPoint("LEFT", delayInput, "RIGHT", 14, 0)

    local limitInput = GC.UI.Panel.Input(previewContent, 48, Th.inputH)
    limitInput:SetPoint("LEFT", limitLabel, "RIGHT", 6, 0)
    self.limitInput = limitInput

    local previewBtn = GC.UI.Button.Create(previewContent, "Preview", "primary", 62, Th.btnH)
    previewBtn:SetPoint("TOPLEFT", targetInput, "BOTTOMLEFT", 0, -8)
    previewBtn:SetScript("OnClick", function()
        self:RefreshPreview()
    end)
    self.previewBtn = previewBtn

    local queuePreviewBtn = GC.UI.Button.Create(previewContent, "Queue Preview", "secondary", 94, Th.btnH)
    queuePreviewBtn:SetPoint("LEFT", previewBtn, "RIGHT", 6, 0)
    queuePreviewBtn:SetTooltip("Queue Preview", "Queues the currently previewed chunks without sending them immediately.")
    queuePreviewBtn:SetScript("OnClick", function()
        local svc = MS()
        if not self:RefreshPreview() then
            return
        end
        if #(self.previewData or {}) == 0 then
            GC.UI.MainFrame:SetStatus("Nothing to queue. Add message text first.", "textWarn")
            return
        end
        local outputOptions, optionsErr = self:GetOutputOptions()
        if not outputOptions then
            GC.UI.MainFrame:SetStatus(optionsErr or "Invalid target channel.", "textDanger")
            return
        end

        local function queuePreview()
            local ok, err
            if svc then
                ok, err = svc:QueueChunks(self.previewData, {
                    target = outputOptions.target,
                    recipient = outputOptions.recipient,
                    sourceMessageId = self.currentDraft and self.currentDraft.id or nil,
                })
            else
                ok, err = false, "Messaging service is unavailable."
            end
            if not ok then
                GC.UI.MainFrame:SetStatus(err or "Unable to queue preview chunks.", "textDanger")
                return
            end
            self:Refresh()
            GC.UI.MainFrame:SetStatus("Preview queued.", "textSuccess")
        end

        outputOptions.chunkCount = #(self.previewData or {})
        outputOptions.willAutoSend = false
        outputOptions.actionLabel = "queue"
        outputOptions.callback = queuePreview
        self:RunWithOutputConfirmation(outputOptions)
    end)
    self.queuePreviewBtn = queuePreviewBtn

    local loadChunkBtn = GC.UI.Button.Create(previewContent, "Load Chunk", "secondary", 78, Th.btnH)
    loadChunkBtn:SetPoint("LEFT", queuePreviewBtn, "RIGHT", 6, 0)
    loadChunkBtn:SetTooltip("Load First/Selected Chunk", "Loads the selected chunk into the chat edit box instead of sending it immediately.")
    loadChunkBtn:SetScript("OnClick", function()
        local svc = MS()
        if not self:RefreshPreview() then
            return
        end
        local chunk = self:GetSelectedPreviewChunk()
        if not chunk then
            GC.UI.MainFrame:SetStatus("Preview a message first.", "textWarn")
            return
        end
        local outputOptions, optionsErr = self:GetOutputOptions()
        if not outputOptions then
            GC.UI.MainFrame:SetStatus(optionsErr or "Invalid target channel.", "textDanger")
            return
        end
        local ok, err
        if svc then
            ok, err = svc:LoadChunkIntoChat(chunk.text, outputOptions)
        else
            ok, err = false, "Messaging service is unavailable."
        end
        if not ok then
            GC.UI.MainFrame:SetStatus(err or "Unable to load chunk into chat.", "textDanger")
            return
        end
        if self.currentDraft and self.currentDraft.id and svc and svc.RecordMessageUsage then
            svc:RecordMessageUsage(self.currentDraft.id, {
                target = outputOptions.target,
                recipient = outputOptions.recipient,
                sentAt = time(),
                chunkCount = #(self.previewData or {}),
            })
        end
        self:Refresh()
        GC.UI.MainFrame:SetStatus("Chunk loaded into chat input.", "textSuccess")
    end)
    self.loadChunkBtn = loadChunkBtn

    local modeBtn = GC.UI.Button.Create(previewContent, "Mode: Manual", "secondary", 104, Th.btnH)
    modeBtn:SetPoint("LEFT", loadChunkBtn, "RIGHT", 6, 0)
    modeBtn:SetTooltip("Auto Mode Toggle", "Manual Mode only queues chunks. Auto Mode can send the queue automatically using the configured delay.")
    modeBtn:SetScript("OnClick", function()
        local svc = MS()
        if not svc then
            return
        end
        if svc:GetAutomationEnabled() then
            svc:SetAutomationEnabled(false)
            self:Refresh()
            GC.UI.MainFrame:SetStatus("Auto Mode disabled.", "textWarn")
        else
            self:PromptEnableAutoMode()
        end
    end)
    self.modeBtn = modeBtn

    local sendNextBtn = GC.UI.Button.Create(previewContent, "Send Next", "success", 74, Th.btnH)
    sendNextBtn:SetPoint("TOPLEFT", previewBtn, "BOTTOMLEFT", 0, -8)
    sendNextBtn:SetScript("OnClick", function()
        local svc = MS()
        local ok, err
        if svc then
            ok, err = svc:SendNextQueuedMessage()
        else
            ok, err = false, "Messaging service is unavailable."
        end
        if not ok then
            GC.UI.MainFrame:SetStatus(err or "Unable to send queued chunk.", "textWarn")
            return
        end
        self:Refresh()
        GC.UI.MainFrame:SetStatus("Queued chunk sent.", "textSuccess")
    end)
    self.sendNextBtn = sendNextBtn

    local startAutoBtn = GC.UI.Button.Create(previewContent, "Start Auto", "success", 84, Th.btnH)
    startAutoBtn:SetPoint("LEFT", sendNextBtn, "RIGHT", 6, 0)
    startAutoBtn:SetTooltip("Start Auto Send", "Starts automatically sending queued chunks using the configured delay.")
    startAutoBtn:SetScript("OnClick", function()
        local svc = MS()
        if not svc then
            return
        end
        if not svc:GetAutomationEnabled() then
            self:PromptEnableAutoMode()
            return
        end
        self:PromptStartAutoSend()
    end)
    self.startAutoBtn = startAutoBtn

    local stopAutoBtn = GC.UI.Button.Create(previewContent, "Stop Auto", "danger", 84, Th.btnH)
    stopAutoBtn:SetPoint("LEFT", startAutoBtn, "RIGHT", 6, 0)
    stopAutoBtn:SetTooltip("Stop Auto Send", "Cancels the active auto-send loop without clearing the queue.")
    stopAutoBtn:SetScript("OnClick", function()
        local svc = MS()
        if svc then
            svc:StopAutoSend("manual")
        end
        self:Refresh()
        GC.UI.MainFrame:SetStatus("Auto-send stopped.", "textWarn")
    end)
    self.stopAutoBtn = stopAutoBtn

    local clearQueueBtn = GC.UI.Button.Create(previewContent, "Clear Queue", "danger", 84, Th.btnH)
    clearQueueBtn:SetPoint("LEFT", stopAutoBtn, "RIGHT", 6, 0)
    clearQueueBtn:SetScript("OnClick", function()
        local svc = MS()
        if svc then
            svc:ClearQueue()
        end
        self.previewData = {}
        self.selectedPreviewKey = nil
        self:SetPlaceholderWarnings({})
        self:Refresh()
        GC.UI.MainFrame:SetStatus("Queue cleared.", "textWarn")
    end)
    self.clearQueueBtn = clearQueueBtn

    -- Status block: three stacked lines (mode / queue / chunks)
    local modeStatusFs = Th.Fs(previewContent, "data", "", "textAccent")
    modeStatusFs:SetPoint("TOPLEFT", sendNextBtn, "BOTTOMLEFT", 0, -8)
    modeStatusFs:SetWidth(360)
    self.modeStatusLabel = modeStatusFs

    local queueStatusFs = Th.Fs(previewContent, "data", "", "textDimmed")
    queueStatusFs:SetPoint("TOPLEFT", modeStatusFs, "BOTTOMLEFT", 0, -2)
    queueStatusFs:SetWidth(360)
    self.queueStatusLabel = queueStatusFs

    local chunksStatusFs = Th.Fs(previewContent, "data", "", "textDimmed")
    chunksStatusFs:SetPoint("TOPLEFT", queueStatusFs, "BOTTOMLEFT", 0, -2)
    chunksStatusFs:SetWidth(360)
    self.chunksStatusLabel = chunksStatusFs

    local previewListFrame = CreateFrame("Frame", nil, previewContent)
    previewListFrame:SetPoint("TOPLEFT", chunksStatusFs, "BOTTOMLEFT", 0, -8)
    previewListFrame:SetPoint("BOTTOMRIGHT", previewContent, "BOTTOMRIGHT", -210, 0)
    self.previewList = GC.UI.List.Create(previewListFrame, PREVIEW_ROW_HEIGHT, buildPreviewRow, function(item)
        self.selectedPreviewKey = item.key
    end)
    self.previewList:SetEmptyText("No preview yet. Enter or select a message and click Preview.")

    local historyLabel = Th.Fs(previewContent, "tiny", "Recent History", "textDimmed")
    historyLabel:SetPoint("TOPLEFT", previewListFrame, "TOPRIGHT", 12, 0)
    self.historyLabel = historyLabel

    local historyListFrame = CreateFrame("Frame", nil, previewContent)
    historyListFrame:SetPoint("TOPLEFT", historyLabel, "BOTTOMLEFT", 0, -6)
    historyListFrame:SetPoint("BOTTOMRIGHT", previewContent, "BOTTOMRIGHT", 0, 0)
    self.historyList = GC.UI.List.Create(historyListFrame, HISTORY_ROW_HEIGHT, buildHistoryRow)
    self.historyList:SetEmptyText("No history yet.")

    self:RefreshPlaceholderPicker()
    self:ResetDraft("general")
end

function MP:UpdateStatusDisplay()
    local svc = MS()
    local Th  = T()
    if not svc then
        if self.modeStatusLabel  then self.modeStatusLabel:SetText("") end
        if self.queueStatusLabel then
            local c = Th.c.textDanger
            self.queueStatusLabel:SetTextColor(c[1], c[2], c[3], c[4] or 1)
            self.queueStatusLabel:SetText("Service unavailable.")
        end
        if self.chunksStatusLabel then self.chunksStatusLabel:SetText("") end
        return
    end

    local autoSending = svc:IsAutoSending()
    local autoEnabled = svc:GetAutomationEnabled()
    local health      = svc:GetQueueHealth()
    local chunkCount  = #(self.previewData or {})

    -- Mode line
    local modeText
    if autoSending then
        local remaining = svc:GetSendCooldownRemaining()
        if remaining > 0 then
            modeText = string.format("Auto Mode: running (next in %.1fs)", remaining)
        else
            modeText = "Auto Mode: running"
        end
    elseif autoEnabled then
        modeText = "Auto Mode: idle"
    else
        modeText = "Manual Mode"
    end

    -- Queue status line (health-aware)
    local queueText, queueColorKey
    local st = health.status
    if st == "unavailable" or st == "malformed" then
        queueText     = "Queue error - clear required"
        queueColorKey = "textDanger"
    elseif st == "blocked" then
        queueText     = "Queue blocked - " .. (health.message or "first entry is invalid")
        queueColorKey = "textDanger"
    elseif st == "partial" then
        queueText     = "Queue: " .. (health.message or (health.queueSize .. " queued"))
        queueColorKey = "textWarn"
    elseif st == "healthy" then
        queueText     = string.format("Queue: %d queued", health.queueSize)
        queueColorKey = "textDimmed"
    else
        queueText     = "Queue: empty"
        queueColorKey = "textDimmed"
    end

    -- Chunks line
    local chunksText = chunkCount > 0
        and string.format("%d chunk%s prepared", chunkCount, chunkCount == 1 and "" or "s")
        or ""

    if self.modeStatusLabel then
        self.modeStatusLabel:SetText(modeText)
    end
    if self.queueStatusLabel then
        local c = Th.c[queueColorKey] or Th.c.textDimmed
        self.queueStatusLabel:SetTextColor(c[1], c[2], c[3], c[4] or 1)
        self.queueStatusLabel:SetText(queueText)
    end
    if self.chunksStatusLabel then
        self.chunksStatusLabel:SetText(chunksText)
    end
end

function MP:Refresh()
    if not self.frame then
        return
    end

    if self.dragState then
        self:FinishMessageDrag(true)
    end

    local svc = MS()
    if not svc then
        return
    end

    local settings = DS() and DS():GetSettings()
    local disabled = settings and settings.enableMessagingModule == false
    self.disabledBanner:SetShown(disabled)

    local selectedCategoryId = svc:GetSelectedCategoryId() or "general"
    local selectedCategory = svc:GetCategory(selectedCategoryId) or { name = "General" }
    if selectedCategory.archived and not self.showArchived then
        svc:SetSelectedCategory("general")
        svc:SetSelectedMessage(nil)
        selectedCategoryId = "general"
        selectedCategory = svc:GetCategory(selectedCategoryId) or { name = "General" }
    end
    local categories = svc:ListCategories({ showArchived = self.showArchived == true })
    self.categoryList:SetSelected(selectedCategoryId)
    self.categoryList:Refresh(categories)

    if not self.categoryInput:HasFocus() then
        self.categoryInput:SetText(selectedCategory.name or "General")
    end

    self.visibleMessages = svc:ListMessages(selectedCategoryId, self:GetTemplateFilterOptions())
    local selectedMessageId = self.currentDraft and self.currentDraft.id or svc:GetSelectedMessageId()
    self.messageList:SetSelected(selectedMessageId)
    self.messageList:Refresh(self.visibleMessages)

    local dailyTarget = svc:GetDailyTargetTime()
    if not self.targetInput:HasFocus() then
        self.targetInput:SetText(svc:GetPreviewTargetName() or "")
    end
    if not self.timeInput:HasFocus() then
        self.timeInput:SetText(string.format("%02d:%02d", dailyTarget.hour or 18, dailyTarget.minute or 0))
    end
    if not self.delayInput:HasFocus() then
        self.delayInput:SetText(string.format("%.1f", svc:GetAutoSendDelaySeconds()))
    end
    if not self.limitInput:HasFocus() then
        local currentLimit = self:ClampChunkLimit(self.limitInput:GetText() or DEFAULT_CHUNK_LIMIT)
        self.limitInput:SetText(tostring(currentLimit))
    end

    if self.currentDraft then
        local assignedCategory = svc:GetCategory(self.currentDraft.categoryId or selectedCategoryId) or selectedCategory
        self.assignedCategoryLabel:SetText(assignedCategory.name or "General")
    end

    self.previewList:SetSelected(self.selectedPreviewKey)
    self.previewList:Refresh(self.previewData or {})
    if self.historyList then
        self.historyList:Refresh(svc:ListHistory(6))
    end

    local queueSize = svc:GetQueueSize()
    local draft = self.currentDraft or {}
    local hasSavedMessage = draft.id ~= nil
    local hasPreview = #(self.previewData or {}) > 0
    local autoEnabled = svc:GetAutomationEnabled()
    local autoSending = svc:IsAutoSending()
    local selectedMessage = draft.id and svc:GetMessage(draft.id) or nil
    local queueHealth = svc:GetQueueHealth()

    self:UpdateStatusDisplay()
    self.modeBtn:SetLabel(autoEnabled and "Mode: Auto" or "Mode: Manual")
    self.showArchivedBtn:SetLabel(self.showArchived and "Archived: On" or "Archived: Off")
    self.favoritesOnlyBtn:SetLabel(self.favoritesOnly and "Favs: On" or "Favs: Off")
    self:RefreshPlaceholderPicker()
    self:SetPlaceholderWarnings(self.placeholderWarnings or {})
    if self.channelBtn then
        local info = self:GetSelectedChannelInfo()
        self.channelBtn:SetLabel(info.label or self:GetSelectedChannelKey())
        setFrameShown(self.recipientLabel, info.requiresRecipient == true)
        setFrameShown(self.recipientInput, info.requiresRecipient == true)
    end

    self.categoryNewBtn:SetEnabled(not disabled)
    self.categoryRenameBtn:SetEnabled(not disabled)
    self.categoryDeleteBtn:SetEnabled(not disabled and selectedCategoryId ~= "general")
    self.categoryUpBtn:SetEnabled(not disabled and selectedCategoryId ~= nil and #categories > 1)
    self.categoryDownBtn:SetEnabled(not disabled and selectedCategoryId ~= nil and #categories > 1)
    self.categoryCollapseBtn:SetEnabled(not disabled and selectedCategoryId ~= nil)
    self.categoryCollapseBtn:SetLabel(selectedCategory.collapsed and "Expand" or "Collapse")
    self.categoryArchiveBtn:SetEnabled(not disabled and selectedCategoryId ~= "general")
    self.categoryArchiveBtn:SetLabel(selectedCategory.archived and "Unarchive" or "Archive")
    self.messageNewBtn:SetEnabled(not disabled)
    self.messageDeleteBtn:SetEnabled(not disabled and hasSavedMessage)
    self.duplicateBtn:SetEnabled(not disabled and hasSavedMessage)
    self.favoriteBtn:SetEnabled(not disabled and hasSavedMessage)
    self.favoriteBtn:SetLabel((selectedMessage and selectedMessage.favorite) and "Unfavorite" or "Favorite")
    self.archiveBtn:SetEnabled(not disabled and hasSavedMessage)
    self.archiveBtn:SetLabel((selectedMessage and selectedMessage.archived) and "Unarchive" or "Archive")
    self.showArchivedBtn:SetEnabled(not disabled)
    self.favoritesOnlyBtn:SetEnabled(not disabled)
    self.exportBtn:SetEnabled(not disabled and hasSavedMessage)
    self.exportAllBtn:SetEnabled(not disabled)
    self.importBtn:SetEnabled(not disabled)
    self.moveUpBtn:SetEnabled(not disabled and hasSavedMessage and #self.visibleMessages > 1)
    self.moveDownBtn:SetEnabled(not disabled and hasSavedMessage and #self.visibleMessages > 1)
    self.moveHereBtn:SetEnabled(not disabled and hasSavedMessage)
    self.saveBtn:SetEnabled(not disabled)
    self.assignSelectedBtn:SetEnabled(not disabled)
    self.placeholderPickerBtn:SetEnabled(not disabled)
    self.insertPlaceholderBtn:SetEnabled(not disabled)
    self.previewBtn:SetEnabled(not disabled)
    self.queuePreviewBtn:SetEnabled(not disabled and hasPreview)
    self.loadChunkBtn:SetEnabled(not disabled and hasPreview)
    local queueSendable  = (queueHealth.status == "healthy" or queueHealth.status == "partial") and queueSize > 0
    local queueClearable = queueSize > 0 or queueHealth.status == "malformed"
    self.sendNextBtn:SetEnabled(not disabled and queueSendable)
    self.startAutoBtn:SetEnabled(not disabled and not autoSending and queueSendable)
    self.stopAutoBtn:SetEnabled(not disabled and autoSending)
    self.clearQueueBtn:SetEnabled(not disabled and queueClearable)
    self.modeBtn:SetEnabled(not disabled)
    self.channelBtn:SetEnabled(not disabled)

    setEditBoxInteractive(self.titleInput, not disabled)
    setEditBoxInteractive(self.notesInput, not disabled)
    setEditBoxInteractive(self.bodyInput, not disabled)
    setEditBoxInteractive(self.targetInput, not disabled)
    setEditBoxInteractive(self.timeInput, not disabled)
    setEditBoxInteractive(self.delayInput, not disabled)
    setEditBoxInteractive(self.limitInput, not disabled)
    setEditBoxInteractive(self.recipientInput, not disabled and self:GetSelectedChannelInfo().requiresRecipient == true)
    setEditBoxInteractive(self.searchInput, not disabled)
end

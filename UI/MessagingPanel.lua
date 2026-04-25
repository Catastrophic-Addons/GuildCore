-- UI/MessagingPanel.lua
-- Message template library: categories, reusable templates, placeholder preview,
-- safe queueing, optional auto-send, and drag-reorder support.
local addonName, ns = ...
local GC = ns.GuildCore

GC.UI.MessagingPanel = {}
local MP = GC.UI.MessagingPanel

local function T() return GC.UI.Theme end
local function MS() return GC.Services.Messages end
local function DS() return GC.Services.DataStore end

local MESSAGE_ROW_HEIGHT = 50
local PREVIEW_ROW_HEIGHT = 58

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
    edit:SetFont(Th.f.body[1], Th.f.body[2], Th.f.body[3])
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
            edit:SetHeight(math.max(boxHeight - 12, edit:GetStringHeight() + 24))
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
        local nameFs = Th.Fs(row, "small", "", "textPrimary")
        nameFs:SetPoint("LEFT", 8, 0)
        nameFs:SetPoint("RIGHT", row, "RIGHT", -48, 0)
        nameFs:SetJustifyH("LEFT")
        row._name = nameFs

        local countFs = Th.Fs(row, "tiny", "", "textDimmed")
        countFs:SetPoint("RIGHT", -8, 0)
        countFs:SetJustifyH("RIGHT")
        row._count = countFs
    end

    row._name:SetText((item.name or "General") .. (item.isDefault and " *" or ""))
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

    local success, sendErr, payload = svc:DirectSendMessage(messageId, self:GetResolveOptions())
    if not success then
        GC.UI.MainFrame:SetStatus(sendErr or "Unable to queue message.", "textDanger")
        return
    end

    self.previewData = payload and payload.preview or {}
    self.selectedPreviewKey = self.previewData[1] and self.previewData[1].key or nil
    self:Refresh()

    if payload and payload.autoStarted then
        GC.UI.MainFrame:SetStatus("Template queued and auto-send started.", "textSuccess")
    else
        GC.UI.MainFrame:SetStatus("Template queued in Manual Mode.", "textSuccess")
    end
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

        local titleFs = Th.Fs(row, "small", "", "textPrimary")
        titleFs:SetPoint("TOPLEFT", 28, -5)
        titleFs:SetPoint("TOPRIGHT", -56, -5)
        titleFs:SetJustifyH("LEFT")
        row._title = titleFs

        local stampFs = Th.Fs(row, "tiny", "", "textDimmed")
        stampFs:SetPoint("BOTTOMLEFT", 28, 5)
        stampFs:SetJustifyH("LEFT")
        row._stamp = stampFs

        local subFs = Th.Fs(row, "tiny", "", "textSecond")
        subFs:SetPoint("BOTTOMLEFT", 128, 5)
        subFs:SetPoint("BOTTOMRIGHT", -56, 5)
        subFs:SetJustifyH("LEFT")
        row._sub = subFs
    end

    row._title:SetText(item.title or "Untitled Message")
    row._stamp:SetText(item.lastUsedLabel and ("Used " .. item.lastUsedLabel) or (item.updatedLabel and ("Updated " .. item.updatedLabel) or ""))

    local snippet = trim(item.notes ~= "" and item.notes or item.body or "")
    if #snippet > 40 then
        snippet = snippet:sub(1, 37) .. "..."
    end
    row._sub:SetText(snippet ~= "" and snippet or "No notes")
end

local function buildPreviewRow(row, item)
    local Th = T()
    row._item = item

    if not row._idx then
        local idxFs = Th.Fs(row, "tiny", "", "textAccent")
        idxFs:SetPoint("TOPLEFT", 8, -5)
        row._idx = idxFs

        local lenFs = Th.Fs(row, "tiny", "", "textDimmed")
        lenFs:SetPoint("TOPRIGHT", -8, -5)
        row._len = lenFs

        local textFs = Th.Fs(row, "small", "", "textSecond")
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

function MP:ResetDraft(categoryId)
    local svc = MS()
    self.currentDraft = {
        id = nil,
        title = "",
        notes = "",
        body = "",
        categoryId = categoryId or (svc and svc:GetSelectedCategoryId()) or "general",
        dirty = false,
    }
    self.previewData = {}
    self.selectedPreviewKey = nil
end

function MP:CollectDraft()
    local draft = self.currentDraft or {}
    draft.title = trim(self.titleInput and self.titleInput:GetText() or "")
    draft.notes = trim(self.notesInput and self.notesInput:GetText() or "")
    draft.body = self.bodyInput and self.bodyInput:GetText() or ""
    draft.categoryId = draft.categoryId or ((MS() and MS():GetSelectedCategoryId()) or "general")
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
        dirty = false,
    }

    self.titleInput:SetText(self.currentDraft.title or "")
    self.notesInput:SetText(self.currentDraft.notes or "")
    self.bodyInput:SetText(self.currentDraft.body or "")
    self.bodyCountLabel:SetText(string.format("%d chars", #(self.currentDraft.body or "")))
    self.previewData = {}
    self.selectedPreviewKey = nil

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
        self.titleInput:SetText("")
        self.notesInput:SetText("")
        self.bodyInput:SetText("")
        self.bodyCountLabel:SetText("0 chars")
        svc:SetSelectedMessage(nil)
    end

    self:Refresh()
end

function MP:GetResolveOptions()
    local svc = MS()
    local targetTime = svc and svc:GetDailyTargetTime() or { hour = 18, minute = 0 }
    return {
        targetName = self.targetInput and self.targetInput:GetText() or "",
        dailyTargetHour = targetTime.hour,
        dailyTargetMinute = targetTime.minute,
        limit = tonumber(self.limitInput and self.limitInput:GetText() or "") or 240,
        includeNumbers = true,
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
        return
    end

    local ok, err = self:ApplyPlaceholderInputs()
    if not ok then
        GC.UI.MainFrame:SetStatus(err or "Invalid placeholder settings.", "textDanger")
        return
    end

    local limit = tonumber(self.limitInput:GetText() or "") or 240
    if limit < 20 then
        limit = 20
    end
    self.limitInput:SetText(tostring(limit))

    local draft = self:CollectDraft()
    self.previewData = svc:BuildPreview(draft.body, self:GetResolveOptions())
    self.selectedPreviewKey = self.previewData[1] and self.previewData[1].key or nil
    self:Refresh()
end

function MP:PromptEnableAutoMode()
    StaticPopup_Show("GUILDCORE_MESSAGES_ENABLE_AUTO", nil, nil, self)
end

function MP:PromptStartAutoSend()
    StaticPopup_Show("GUILDCORE_MESSAGES_START_AUTO", nil, nil, self)
end

function MP:ConfirmEnableAutoMode()
    local svc = MS()
    local ok, err = self:ApplyPlaceholderInputs()
    if not ok then
        GC.UI.MainFrame:SetStatus(err or "Invalid automation settings.", "textDanger")
        return
    end

    ok, err = svc and svc:SetAutomationEnabled(true)
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

    ok, err = svc and svc:StartAutoSend()
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
        local category, err = svc and svc:CreateCategory(self.categoryInput:GetText() or "")
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
        local ok, err = svc and svc:RenameCategory(svc:GetSelectedCategoryId(), self.categoryInput:GetText() or "")
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
        local ok, err = svc and svc:DeleteCategory(svc:GetSelectedCategoryId(), "general")
        if not ok then
            GC.UI.MainFrame:SetStatus(err or "Unable to delete category.", "textDanger")
            return
        end
        self.categoryInput:SetText("General")
        self:SelectCategory("general")
        GC.UI.MainFrame:SetStatus("Category deleted. Messages were reassigned to General.", "textWarn")
    end)
    self.categoryDeleteBtn = categoryDeleteBtn

    local categoryListFrame = CreateFrame("Frame", nil, categoriesContent)
    categoryListFrame:SetPoint("TOPLEFT", categoryNewBtn, "BOTTOMLEFT", 0, -12)
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
    messageNewBtn:SetPoint("TOPLEFT", 0, 0)
    messageNewBtn:SetScript("OnClick", function()
        local svc = MS()
        self:ResetDraft(svc and svc:GetSelectedCategoryId() or "general")
        self.titleInput:SetText("")
        self.notesInput:SetText("")
        self.bodyInput:SetText("")
        self.bodyCountLabel:SetText("0 chars")
        if svc then
            svc:SetSelectedMessage(nil)
        end
        self.previewData = {}
        self.selectedPreviewKey = nil
        self:Refresh()
    end)
    self.messageNewBtn = messageNewBtn

    local messageDeleteBtn = GC.UI.Button.Create(templatesContent, "Delete", "danger", 58, Th.btnH)
    messageDeleteBtn:SetPoint("LEFT", messageNewBtn, "RIGHT", 6, 0)
    messageDeleteBtn:SetScript("OnClick", function()
        local svc = MS()
        local draft = self:CollectDraft()
        if not draft.id then
            GC.UI.MainFrame:SetStatus("Select a saved message to delete.", "textWarn")
            return
        end
        local ok, err = svc and svc:DeleteMessage(draft.id)
        if not ok then
            GC.UI.MainFrame:SetStatus(err or "Unable to delete message.", "textDanger")
            return
        end
        self:ResetDraft(svc and svc:GetSelectedCategoryId() or "general")
        self.titleInput:SetText("")
        self.notesInput:SetText("")
        self.bodyInput:SetText("")
        self.bodyCountLabel:SetText("0 chars")
        self.previewData = {}
        self.selectedPreviewKey = nil
        self:Refresh()
        GC.UI.MainFrame:SetStatus("Message deleted.", "textWarn")
    end)
    self.messageDeleteBtn = messageDeleteBtn

    local moveUpBtn = GC.UI.Button.Create(templatesContent, "Up", "secondary", 38, Th.btnH)
    moveUpBtn:SetPoint("LEFT", messageDeleteBtn, "RIGHT", 6, 0)
    moveUpBtn:SetScript("OnClick", function()
        local svc = MS()
        local draft = self:CollectDraft()
        local ok, err = draft.id and svc and svc:MoveMessageUp(draft.id)
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
        local ok, err = draft.id and svc and svc:MoveMessageDown(draft.id)
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
        local ok, err = svc and svc:MoveMessageToCategory(draft.id, svc:GetSelectedCategoryId())
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

    local messageListFrame = CreateFrame("Frame", nil, templatesContent)
    messageListFrame:SetPoint("TOPLEFT", moveHereBtn, "BOTTOMLEFT", 0, -12)
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
    previewCard:SetHeight(272)

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

    local assignedCategoryFs = Th.Fs(editorContent, "small", "General", "textAccent")
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

    local bodyHolder, bodyInput = createMultilineInput(editorContent, 210)
    bodyHolder:SetPoint("TOPLEFT", bodyLabel, "BOTTOMLEFT", 0, -6)
    bodyHolder:SetPoint("BOTTOMRIGHT", editorContent, "BOTTOMRIGHT", 0, 0)
    bodyInput:SetScript("OnTextChanged", function(self)
        self:SetWidth(math.max(120, bodyHolder:GetWidth() - 18))
        self:SetHeight(math.max(bodyHolder:GetHeight() - 12, self:GetStringHeight() + 24))
        MP.bodyCountLabel:SetText(string.format("%d chars", #(self:GetText() or "")))
        if self == MP.bodyInput and MP.currentDraft then
            MP.currentDraft.dirty = true
        end
    end)
    self.bodyInput = bodyInput

    local bodyCountFs = Th.Fs(editorContent, "tiny", "0 chars", "textDimmed")
    bodyCountFs:SetPoint("RIGHT", editorContent, "RIGHT", 0, 0)
    bodyCountFs:SetPoint("TOP", bodyLabel, "TOP", 0, 0)
    self.bodyCountLabel = bodyCountFs

    local previewInfoFs = Th.Fs(previewContent, "small", "Placeholders resolve only during preview/send. Drag templates with the handle. Manual Mode stays safest.", "textDimmed")
    previewInfoFs:SetPoint("TOPLEFT", 0, 0)
    previewInfoFs:SetPoint("TOPRIGHT", previewContent, "TOPRIGHT", 0, 0)
    previewInfoFs:SetJustifyH("LEFT")

    local placeholderFs = Th.Fs(previewContent, "tiny", "@player.name  @guild.name  @realm.name  @target.name  @new.member  @time.left", "textDimmed")
    placeholderFs:SetPoint("TOPLEFT", previewInfoFs, "BOTTOMLEFT", 0, -6)

    local targetLabel = Th.Fs(previewContent, "tiny", "Target", "textDimmed")
    targetLabel:SetPoint("TOPLEFT", placeholderFs, "BOTTOMLEFT", 0, -10)

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
    previewBtn:SetPoint("TOPLEFT", targetLabel, "BOTTOMLEFT", 0, -10)
    previewBtn:SetScript("OnClick", function()
        self:RefreshPreview()
    end)
    self.previewBtn = previewBtn

    local queuePreviewBtn = GC.UI.Button.Create(previewContent, "Queue Preview", "secondary", 94, Th.btnH)
    queuePreviewBtn:SetPoint("LEFT", previewBtn, "RIGHT", 6, 0)
    queuePreviewBtn:SetTooltip("Queue Preview", "Queues the currently previewed chunks without sending them immediately.")
    queuePreviewBtn:SetScript("OnClick", function()
        local svc = MS()
        self:RefreshPreview()
        if #(self.previewData or {}) == 0 then
            GC.UI.MainFrame:SetStatus("Nothing to queue. Add message text first.", "textWarn")
            return
        end
        local ok, err = svc and svc:QueueChunks(self.previewData, {
            target = "GUILD",
            sourceMessageId = self.currentDraft and self.currentDraft.id or nil,
        })
        if not ok then
            GC.UI.MainFrame:SetStatus(err or "Unable to queue preview chunks.", "textDanger")
            return
        end
        self:Refresh()
        GC.UI.MainFrame:SetStatus("Preview queued.", "textSuccess")
    end)
    self.queuePreviewBtn = queuePreviewBtn

    local loadChunkBtn = GC.UI.Button.Create(previewContent, "Load Chunk", "secondary", 78, Th.btnH)
    loadChunkBtn:SetPoint("LEFT", queuePreviewBtn, "RIGHT", 6, 0)
    loadChunkBtn:SetTooltip("Load First/Selected Chunk", "Loads the selected chunk into the chat edit box instead of sending it immediately.")
    loadChunkBtn:SetScript("OnClick", function()
        local svc = MS()
        self:RefreshPreview()
        local chunk = self:GetSelectedPreviewChunk()
        if not chunk then
            GC.UI.MainFrame:SetStatus("Preview a message first.", "textWarn")
            return
        end
        local ok, err = svc and svc:LoadChunkIntoChat(chunk.text, "GUILD")
        if not ok then
            GC.UI.MainFrame:SetStatus(err or "Unable to load chunk into chat.", "textDanger")
            return
        end
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
        local ok, err = svc and svc:SendNextQueuedMessage()
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
        self:Refresh()
        GC.UI.MainFrame:SetStatus("Queue cleared.", "textWarn")
    end)
    self.clearQueueBtn = clearQueueBtn

    local autoStatusFs = Th.Fs(previewContent, "small", "", "textAccent")
    autoStatusFs:SetPoint("LEFT", clearQueueBtn, "RIGHT", 12, 0)
    self.autoStatusLabel = autoStatusFs

    local queueCountFs = Th.Fs(previewContent, "small", "", "textDimmed")
    queueCountFs:SetPoint("LEFT", autoStatusFs, "RIGHT", 12, 0)
    self.queueCountLabel = queueCountFs

    local previewCountFs = Th.Fs(previewContent, "small", "", "textAccent")
    previewCountFs:SetPoint("LEFT", queueCountFs, "RIGHT", 12, 0)
    self.previewCountLabel = previewCountFs

    local previewListFrame = CreateFrame("Frame", nil, previewContent)
    previewListFrame:SetPoint("TOPLEFT", sendNextBtn, "BOTTOMLEFT", 0, -10)
    previewListFrame:SetPoint("BOTTOMRIGHT", previewContent, "BOTTOMRIGHT", 0, 0)
    self.previewList = GC.UI.List.Create(previewListFrame, PREVIEW_ROW_HEIGHT, buildPreviewRow, function(item)
        self.selectedPreviewKey = item.key
    end)
    self.previewList:SetEmptyText("No preview yet. Enter or select a message and click Preview.")

    self:ResetDraft("general")
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
    local categories = svc:ListCategories()
    self.categoryList:SetSelected(selectedCategoryId)
    self.categoryList:Refresh(categories)

    local selectedCategory = svc:GetCategory(selectedCategoryId) or { name = "General" }
    if not self.categoryInput:HasFocus() then
        self.categoryInput:SetText(selectedCategory.name or "General")
    end

    self.visibleMessages = svc:ListMessages(selectedCategoryId)
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
        local currentLimit = tonumber(self.limitInput:GetText() or "") or 240
        self.limitInput:SetText(tostring(math.max(20, currentLimit)))
    end

    if self.currentDraft then
        local assignedCategory = svc:GetCategory(self.currentDraft.categoryId or selectedCategoryId) or selectedCategory
        self.assignedCategoryLabel:SetText(assignedCategory.name or "General")
    end

    self.previewList:SetSelected(self.selectedPreviewKey)
    self.previewList:Refresh(self.previewData or {})

    local queueSize = svc:GetQueueSize()
    local draft = self.currentDraft or {}
    local hasSavedMessage = draft.id ~= nil
    local hasPreview = #(self.previewData or {}) > 0
    local autoEnabled = svc:GetAutomationEnabled()
    local autoSending = svc:IsAutoSending()

    self.queueCountLabel:SetText(string.format("%d queued", queueSize))
    self.previewCountLabel:SetText(string.format("%d chunks", #(self.previewData or {})))
    self.autoStatusLabel:SetText(svc:GetAutoSendStatus())
    self.modeBtn:SetLabel(autoEnabled and "Mode: Auto" or "Mode: Manual")

    self.categoryNewBtn:SetEnabled(not disabled)
    self.categoryRenameBtn:SetEnabled(not disabled)
    self.categoryDeleteBtn:SetEnabled(not disabled and selectedCategoryId ~= "general")
    self.messageNewBtn:SetEnabled(not disabled)
    self.messageDeleteBtn:SetEnabled(not disabled and hasSavedMessage)
    self.moveUpBtn:SetEnabled(not disabled and hasSavedMessage and #self.visibleMessages > 1)
    self.moveDownBtn:SetEnabled(not disabled and hasSavedMessage and #self.visibleMessages > 1)
    self.moveHereBtn:SetEnabled(not disabled and hasSavedMessage)
    self.saveBtn:SetEnabled(not disabled)
    self.assignSelectedBtn:SetEnabled(not disabled)
    self.previewBtn:SetEnabled(not disabled)
    self.queuePreviewBtn:SetEnabled(not disabled and hasPreview)
    self.loadChunkBtn:SetEnabled(not disabled and hasPreview)
    self.sendNextBtn:SetEnabled(not disabled and queueSize > 0)
    self.startAutoBtn:SetEnabled(not disabled and not autoSending and queueSize > 0)
    self.stopAutoBtn:SetEnabled(not disabled and autoSending)
    self.clearQueueBtn:SetEnabled(not disabled and queueSize > 0)
    self.modeBtn:SetEnabled(not disabled)

    setEditBoxInteractive(self.titleInput, not disabled)
    setEditBoxInteractive(self.notesInput, not disabled)
    setEditBoxInteractive(self.bodyInput, not disabled)
    setEditBoxInteractive(self.targetInput, not disabled)
    setEditBoxInteractive(self.timeInput, not disabled)
    setEditBoxInteractive(self.delayInput, not disabled)
    setEditBoxInteractive(self.limitInput, not disabled)
end

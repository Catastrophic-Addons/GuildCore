-- UI/MessagingPanel.lua
-- Browse-first saved message manager. Editing and sending live in focused popups
-- so existing message/template storage stays compatible while the tab stays clean.
local addonName, ns = ...
local GC = ns.GuildCore

GC.UI.MessagingPanel = {}
local MP = GC.UI.MessagingPanel

local function T() return GC.UI.Theme end
local function MS() return GC.Services.Messages end
local function TB() return GC.Services.MessageTemplateBridge end
local function DS() return GC.Services.DataStore end

local CATEGORY_ROW_HEIGHT = 30
local MESSAGE_ROW_HEIGHT = 66

local function trim(value)
    return GC.Utils and GC.Utils.Trim and GC.Utils.Trim(value or "") or tostring(value or ""):match("^%s*(.-)%s*$")
end

local function status(message, colorKey)
    if GC.UI and GC.UI.MainFrame then
        GC.UI.MainFrame:SetStatus(message, colorKey)
    end
end

local function setFrameShown(frame, shown)
    if not frame then return end
    if shown then frame:Show() else frame:Hide() end
end

local function setControlEnabled(control, enabled)
    if control and control.SetEnabled then control:SetEnabled(enabled) end
end

local function createMultilineInput(parent, height)
    local Th = T()
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetHeight(height)
    holder:EnableMouse(true)
    Th.Bg(holder, Th.c.panelAlt, Th.c.borderStrong)

    local scroll = CreateFrame("ScrollFrame", nil, holder)
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -8, 8)
    scroll:EnableMouse(true)
    scroll:EnableMouseWheel(true)

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:EnableMouse(true)
    edit:SetTextInsets(2, 2, 2, 2)
    edit:SetWidth(400)
    edit:SetHeight(math.max(24, height - 16))
    Th.ApplyFont(edit, "input")
    if Th.RegisterRefresh then
        Th:RegisterRefresh(function() T().ApplyFont(edit, "input") end)
    end
    local pc = Th.c.textPrimary
    edit:SetTextColor(pc[1], pc[2], pc[3], 1)
    if edit.SetCursorColor then
        edit:SetCursorColor(pc[1], pc[2], pc[3], 1)
    end
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnCursorChanged", function(_, _, y, _, lineHeight)
        local offset = scroll:GetVerticalScroll()
        local visibleBottom = offset + scroll:GetHeight()
        local cursorBottom = y + lineHeight
        if cursorBottom > visibleBottom then
            scroll:SetVerticalScroll(math.max(0, cursorBottom - scroll:GetHeight()))
        elseif y < offset then
            scroll:SetVerticalScroll(math.max(0, y))
        end
    end)
    edit:SetScript("OnTextChanged", function(self)
        self:SetWidth(math.max(120, scroll:GetWidth() - 4))
        self:SetHeight(math.max(scroll:GetHeight(), self:GetStringHeight() + 18))
    end)
    scroll:SetScrollChild(edit)

    holder:SetScript("OnMouseDown", function()
        edit:SetFocus()
        if edit.SetCursorPosition then
            edit:SetCursorPosition(#(edit:GetText() or ""))
        end
    end)
    scroll:SetScript("OnMouseDown", function()
        edit:SetFocus()
    end)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local child = self:GetScrollChild()
        local maxScroll = math.max(0, (child and child:GetHeight() or 0) - self:GetHeight())
        self:SetVerticalScroll(math.min(maxScroll, math.max(0, self:GetVerticalScroll() - (delta * 28))))
    end)
    holder:SetScript("OnSizeChanged", function(_, width, boxHeight)
        edit:SetWidth(math.max(120, width - 20))
        edit:SetHeight(math.max(boxHeight - 16, edit:GetStringHeight() + 18))
    end)

    return holder, edit
end

function MP:GetFilterOptions()
    return {
        showArchived = self.showArchived == true,
        favoritesOnly = self.favoritesOnly == true,
        search = self.searchInput and self.searchInput:GetText() or "",
    }
end

function MP:GetSelectedMessageId()
    local svc = MS()
    return self.selectedMessageId or (svc and svc:GetSelectedMessageId()) or nil
end

function MP:GetSelectedMessage()
    local svc = MS()
    local id = self:GetSelectedMessageId()
    return svc and id and svc:GetMessage(id) or nil
end

function MP:OpenNewMessage()
    local svc = MS()
    if not svc then return end
    GC.UI.MessageEditorPopup:Open({
        mode = "new",
        categoryId = svc:GetSelectedCategoryId() or "general",
        onSave = function(message)
            self.selectedMessageId = message and message.id or nil
            self:Refresh()
        end,
    })
end

function MP:OpenEditMessage(messageId)
    local svc = MS()
    messageId = messageId or self:GetSelectedMessageId()
    local message = svc and messageId and svc:GetMessage(messageId) or nil
    if not message then
        status("Select a message to edit.", "textWarn")
        return
    end
    GC.UI.MessageEditorPopup:Open({
        mode = "edit",
        message = message,
        onSave = function(saved)
            self.selectedMessageId = saved and saved.id or messageId
            self:Refresh()
        end,
    })
end

function MP:OpenDuplicateMessage()
    local message = self:GetSelectedMessage()
    if not message then
        status("Select a message to duplicate.", "textWarn")
        return
    end
    GC.UI.MessageEditorPopup:Open({
        mode = "duplicate",
        message = message,
        onSave = function(saved)
            self.selectedMessageId = saved and saved.id or nil
            self:Refresh()
        end,
    })
end

function MP:SendMessageNow(messageId)
    local svc = MS()
    messageId = messageId or self:GetSelectedMessageId()
    local message = svc and messageId and svc:GetMessage(messageId) or nil
    if not message then
        status("Select a message to send.", "textWarn")
        return
    end

    local payload, previewErr = svc:BuildMessagePreview(messageId, {
        target = message.targetChannel or "GUILD",
        limit = 255,
    })
    if not payload then
        status(previewErr or "Unable to prepare message.", "textDanger")
        return
    end

    local ok, err = svc:QueueChunks(payload.preview, {
        target = message.targetChannel or "GUILD",
        sourceMessageId = messageId,
    })
    if not ok then
        status(err or "Unable to send message.", "textDanger")
        return
    end

    svc:ProcessQueue()
    self.selectedMessageId = messageId
    self:Refresh()
    status("Message sent.", "textSuccess")
end

function MP:SelectCategory(categoryId)
    local svc = MS()
    if not svc or not categoryId then return end
    svc:SetSelectedCategory(categoryId)
    svc:SetSelectedMessage(nil)
    self.selectedMessageId = nil
    self:Refresh()
end

function MP:SelectMessage(messageId)
    local svc = MS()
    if not svc or not messageId then return end
    svc:SetSelectedMessage(messageId)
    self.selectedMessageId = messageId
    self:Refresh()
end

function MP:PromptDeleteSelectedMessage()
    local id = self:GetSelectedMessageId()
    if not id then
        status("Select a message to delete.", "textWarn")
        return
    end
    self.pendingDeleteMessageId = id
    if GC.UI.FrameLayering then
        GC.UI.FrameLayering:ShowStaticPopup("GUILDCORE_MESSAGES_DELETE_MESSAGE", nil, nil, self)
    else
        StaticPopup_Show("GUILDCORE_MESSAGES_DELETE_MESSAGE", nil, nil, self)
    end
end

function MP:ConfirmDeleteMessage()
    local svc = MS()
    local id = self.pendingDeleteMessageId
    self.pendingDeleteMessageId = nil
    if not svc or not id then return end
    local ok, err = svc:DeleteMessage(id)
    if not ok then
        status(err or "Unable to delete message.", "textDanger")
        return
    end
    self.selectedMessageId = nil
    self:Refresh()
    status("Message deleted.", "textWarn")
end

function MP:ToggleSelectedFavorite()
    local svc = MS()
    local id = self:GetSelectedMessageId()
    if not svc or not id then
        status("Select a message first.", "textWarn")
        return
    end
    local ok, err = svc:ToggleMessageFavorite(id)
    if not ok then status(err or "Unable to update favorite.", "textDanger"); return end
    self:Refresh()
end

function MP:ToggleSelectedArchive()
    local svc = MS()
    local id = self:GetSelectedMessageId()
    local message = svc and id and svc:GetMessage(id) or nil
    if not message then
        status("Select a message first.", "textWarn")
        return
    end
    local ok, err
    if message.archived then ok, err = svc:UnarchiveMessage(id) else ok, err = svc:ArchiveMessage(id) end
    if not ok then status(err or "Unable to update archive state.", "textDanger"); return end
    if not self.showArchived and not message.archived then
        self.selectedMessageId = nil
    end
    self:Refresh()
end

function MP:MoveSelectedMessage(delta)
    local svc = MS()
    local id = self:GetSelectedMessageId()
    if not svc or not id then
        status("Select a message to move.", "textWarn")
        return
    end
    local ok, err
    if delta < 0 then ok, err = svc:MoveMessageUp(id) else ok, err = svc:MoveMessageDown(id) end
    if not ok then status(err or "Unable to move message.", "textWarn"); return end
    self:Refresh()
end

function MP:ToggleSelectedCategoryCollapsed()
    local svc = MS()
    local id = svc and svc:GetSelectedCategoryId()
    local ok, err
    if id then
        ok, err = svc:ToggleCategoryCollapsed(id)
    end
    if not ok then status(err or "Unable to collapse category.", "textWarn"); return end
    self:Refresh()
end

function MP:ToggleSelectedCategoryArchived()
    local svc = MS()
    local id = svc and svc:GetSelectedCategoryId()
    local category = id and svc:GetCategory(id)
    local ok, err
    if category and category.archived then ok, err = svc:UnarchiveCategory(id) else ok, err = svc:ArchiveCategory(id) end
    if not ok then status(err or "Unable to update category archive state.", "textDanger"); return end
    self:SelectCategory("general")
end

function MP:EnsureTemplateBridgeDialog()
    if self.bridgeDialog then return self.bridgeDialog end
    local Th = T()
    local dialog = CreateFrame("Frame", nil, UIParent)
    dialog:SetSize(560, 420)
    dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    if GC.UI.FrameLayering then
        GC.UI.FrameLayering:PreparePopupFrame(dialog, GC.UI.MainFrame and GC.UI.MainFrame.frame, 80)
    else
        dialog:SetFrameStrata("DIALOG")
        dialog:SetFrameLevel(100)
    end
    dialog:EnableMouse(true)
    dialog:SetMovable(true)
    dialog:RegisterForDrag("LeftButton")
    dialog:SetScript("OnDragStart", function(self) self:StartMoving() end)
    dialog:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
    dialog:Hide()
    Th.Bg(dialog, Th.c.panel, Th.c.borderStrong)

    local title = Th.Fs(dialog, "header", "Message Import / Export", "textPrimary")
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
    dialog.edit = edit

    local summary = Th.Fs(dialog, "data", "", "textWarn")
    summary:SetPoint("TOPLEFT", holder, "BOTTOMLEFT", 0, -8)
    summary:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -14, 0)
    dialog.summary = summary

    local validateBtn = GC.UI.Button.Create(dialog, "Validate", "secondary", 76, Th.btnH)
    validateBtn:SetPoint("BOTTOMLEFT", dialog, "BOTTOMLEFT", 14, 14)
    validateBtn:SetScript("OnClick", function() self:ValidateTemplateImport() end)
    dialog.validateBtn = validateBtn

    local importBtn = GC.UI.Button.Create(dialog, "Import", "success", 64, Th.btnH)
    importBtn:SetPoint("LEFT", validateBtn, "RIGHT", 8, 0)
    importBtn:SetScript("OnClick", function() self:ConfirmTemplateImport() end)
    dialog.importBtn = importBtn

    local closeBtn = GC.UI.Button.Create(dialog, "Close", "secondary", 64, Th.btnH)
    closeBtn:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -14, 14)
    closeBtn:SetScript("OnClick", function() dialog:Hide() end)
    dialog.closeBtn = closeBtn

    self.bridgeDialog = dialog
    return dialog
end

function MP:ShowTemplateExport(messageIds)
    local bridge = TB()
    if not bridge then status("Message bridge is unavailable.", "textWarn"); return end
    local text, err, count = bridge:ExportTemplates({ messageIds = messageIds })
    if not text then status(err or "Unable to export messages.", "textWarn"); return end
    local dialog = self:EnsureTemplateBridgeDialog()
    dialog.mode = "export"
    dialog.title:SetText("Export Messages")
    dialog.info:SetText(string.format("%d message(s) exported. Select the text below and copy it manually.", count or 0))
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
    dialog.title:SetText("Import Messages")
    dialog.info:SetText("Paste a GuildCore message export below, validate it, then import. Existing messages are preserved.")
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
        dialog.summary:SetText("Message bridge is unavailable.")
        dialog.importBtn:SetEnabled(false)
        return nil
    end
    local summary, err = bridge:PreviewTemplateImport(dialog.edit:GetText() or "")
    if not summary then
        dialog.summary:SetText(err or "Import could not be validated.")
        dialog.importBtn:SetEnabled(false)
        return nil
    end
    local text = string.format("%d message(s), %d missing categor%s, %d duplicate title%s detected.",
        summary.templateCount or 0,
        summary.categoryCount or 0,
        (summary.categoryCount or 0) == 1 and "y" or "ies",
        summary.duplicateCount or 0,
        (summary.duplicateCount or 0) == 1 and "" or "s")
    if (summary.duplicateCount or 0) > 0 then text = text .. " Duplicates will import as copies." end
    dialog.summary:SetText(text)
    dialog.importBtn:SetEnabled(true)
    return summary
end

function MP:ConfirmTemplateImport()
    if not self:ValidateTemplateImport() then return end
    local bridge = TB()
    local dialog = self:EnsureTemplateBridgeDialog()
    local result, err
    if bridge then
        result, err = bridge:ImportTemplates(dialog.edit:GetText() or "")
    end
    if not result then dialog.summary:SetText(err or "Import failed."); return end
    dialog.summary:SetText(string.format("Imported %d message(s).", result.importedCount or 0))
    dialog.importBtn:SetEnabled(false)
    self:Refresh()
    status("Messages imported.", "textSuccess")
end

local function buildCategoryRow(row, item)
    local Th = T()
    row._item = item
    if not row._name then
        row._name = Th.Fs(row, "data", "", "textPrimary")
        row._name:SetPoint("LEFT", 8, 0)
        row._name:SetPoint("RIGHT", row, "RIGHT", -48, 0)
        row._name:SetJustifyH("LEFT")
        row._count = Th.Fs(row, "data", "", "textDimmed")
        row._count:SetPoint("RIGHT", -8, 0)
    end
    local label = item.name or "General"
    if item.collapsed then label = "[+] " .. label end
    if item.archived then label = label .. " [Archived]" end
    row._name:SetText(label)
    row._count:SetText(tostring(item.count or 0))
end

local function buildMessageRow(row, item)
    local Th = T()
    row._item = item
    if not row._title then
        row._title = Th.Fs(row, "data", "", "textPrimary")
        row._title:SetPoint("TOPLEFT", 12, -7)
        row._title:SetPoint("TOPRIGHT", row, "TOPRIGHT", -82, -7)
        row._title:SetJustifyH("LEFT")

        row._snippet = Th.Fs(row, "small", "", "textSecond")
        row._snippet:SetPoint("TOPLEFT", row._title, "BOTTOMLEFT", 0, -4)
        row._snippet:SetPoint("RIGHT", row, "RIGHT", -82, 0)
        row._snippet:SetJustifyH("LEFT")

        row._meta = Th.Fs(row, "tiny", "", "textDimmed")
        row._meta:SetPoint("BOTTOMLEFT", 12, 7)
        row._meta:SetPoint("RIGHT", row, "RIGHT", -82, 0)
        row._meta:SetJustifyH("LEFT")

        row._sendBtn = GC.UI.Button.Create(row, "Send", "primary", 58, 24)
        row._sendBtn:SetPoint("RIGHT", row, "RIGHT", -12, 0)
        row._sendBtn:SetScript("OnClick", function()
            if row._item and row._item.id then MP:SendMessageNow(row._item.id) end
        end)
        row:SetScript("OnDoubleClick", function()
            if row._item and row._item.id then MP:OpenEditMessage(row._item.id) end
        end)
    end

    local title = item.title or "Untitled Message"
    if item.favorite then title = "* " .. title end
    if item.archived then title = title .. " [Archived]" end
    row._title:SetText(title)

    local snippet = trim(item.body ~= "" and item.body or item.notes or "")
    snippet = snippet:gsub("%s+", " ")
    if #snippet > 110 then snippet = snippet:sub(1, 107) .. "..." end
    row._snippet:SetText(snippet ~= "" and snippet or "No message body.")

    local used = item.lastUsedLabel and ("Used " .. item.lastUsedLabel) or "Not sent yet"
    local updated = item.updatedLabel and ("Updated " .. item.updatedLabel) or ""
    local flags = {}
    if item.favorite then flags[#flags + 1] = "Favorite" end
    if item.archived then flags[#flags + 1] = "Archived" end
    row._meta:SetText(table.concat({ used, updated, table.concat(flags, " / ") }, "   "))
end

function MP:Create(parent)
    if self.frame then return end

    StaticPopupDialogs.GUILDCORE_MESSAGES_DELETE_MESSAGE = StaticPopupDialogs.GUILDCORE_MESSAGES_DELETE_MESSAGE or {
        text = "Delete this saved message? This cannot be undone.",
        button1 = "Delete",
        button2 = "Cancel",
        OnAccept = function(_, data) if data and data.ConfirmDeleteMessage then data:ConfirmDeleteMessage() end end,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
        preferredIndex = STATICPOPUP_NUMDIALOGS,
    }

    local Th = T()
    local P = Th.padding
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    frame:Hide()
    Th.Bg(frame, Th.c.bg)
    self.frame = frame

    local titleFs = Th.Fs(frame, "header", "Messages", "textPrimary")
    titleFs:SetPoint("TOPLEFT", P, -P)
    local subtitleFs = Th.Fs(frame, "small", "Browse saved guild messages. Edit and sending open in focused popups.", "textDimmed")
    subtitleFs:SetPoint("LEFT", titleFs, "RIGHT", 10, -1)

    self.disabledBanner = Th.Fs(frame, "small", "Messaging module is disabled in Settings.", "textWarn")
    self.disabledBanner:SetPoint("TOPLEFT", P, -(P + 26))
    self.disabledBanner:Hide()

    local topOffset = -(P + 52)
    local categoriesCard, categoriesContent = GC.UI.Panel.Section(frame, "Categories")
    categoriesCard:SetPoint("TOPLEFT", frame, "TOPLEFT", P, topOffset)
    categoriesCard:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", P, P)
    categoriesCard:SetWidth(230)

    local categoryInput = GC.UI.Panel.Input(categoriesContent, 190, Th.inputH)
    categoryInput:SetPoint("TOPLEFT", 0, -2)
    self.categoryInput = categoryInput

    local categoryNewBtn = GC.UI.Button.Create(categoriesContent, "New Category", "primary", 104, Th.btnH)
    categoryNewBtn:SetPoint("TOPLEFT", categoryInput, "BOTTOMLEFT", 0, -8)
    categoryNewBtn:SetScript("OnClick", function()
        local svc = MS()
        local category, err
        if svc then
            category, err = svc:CreateCategory(categoryInput:GetText() or "")
        end
        if not category then status(err or "Unable to create category.", "textDanger"); return end
        self:SelectCategory(category.id)
        status("Category created.", "textSuccess")
    end)
    self.categoryNewBtn = categoryNewBtn

    local categoryRenameBtn = GC.UI.Button.Create(categoriesContent, "Rename", "secondary", 78, Th.btnH)
    categoryRenameBtn:SetPoint("LEFT", categoryNewBtn, "RIGHT", 8, 0)
    categoryRenameBtn:SetScript("OnClick", function()
        local svc = MS()
        local ok, err
        if svc then
            ok, err = svc:RenameCategory(svc:GetSelectedCategoryId(), categoryInput:GetText() or "")
        end
        if not ok then status(err or "Unable to rename category.", "textDanger"); return end
        self:Refresh()
        status("Category renamed.", "textSuccess")
    end)
    self.categoryRenameBtn = categoryRenameBtn

    local categoryDeleteBtn = GC.UI.Button.Create(categoriesContent, "Delete", "danger", 78, Th.btnH)
    categoryDeleteBtn:SetPoint("TOPLEFT", categoryNewBtn, "BOTTOMLEFT", 0, -8)
    categoryDeleteBtn:SetScript("OnClick", function()
        local svc = MS()
        local ok, err
        if svc then
            ok, err = svc:DeleteCategory(svc:GetSelectedCategoryId(), "general")
        end
        if not ok then status(err or "Unable to delete category.", "textDanger"); return end
        self:SelectCategory("general")
        status("Category deleted. Messages moved to General.", "textWarn")
    end)
    self.categoryDeleteBtn = categoryDeleteBtn

    local categoryUpBtn = GC.UI.Button.Create(categoriesContent, "Move Up", "secondary", 78, Th.btnH)
    categoryUpBtn:SetPoint("LEFT", categoryDeleteBtn, "RIGHT", 8, 0)
    categoryUpBtn:SetScript("OnClick", function()
        local svc = MS()
        local ok, err
        if svc then
            ok, err = svc:MoveCategoryUp(svc:GetSelectedCategoryId())
        end
        if not ok then status(err or "Unable to move category.", "textWarn"); return end
        self:Refresh()
    end)
    self.categoryUpBtn = categoryUpBtn

    local categoryDownBtn = GC.UI.Button.Create(categoriesContent, "Move Down", "secondary", 92, Th.btnH)
    categoryDownBtn:SetPoint("TOPLEFT", categoryDeleteBtn, "BOTTOMLEFT", 0, -8)
    categoryDownBtn:SetScript("OnClick", function()
        local svc = MS()
        local ok, err
        if svc then
            ok, err = svc:MoveCategoryDown(svc:GetSelectedCategoryId())
        end
        if not ok then status(err or "Unable to move category.", "textWarn"); return end
        self:Refresh()
    end)
    self.categoryDownBtn = categoryDownBtn

    local categoryCollapseBtn = GC.UI.Button.Create(categoriesContent, "Collapse", "secondary", 82, Th.btnH)
    categoryCollapseBtn:SetPoint("LEFT", categoryDownBtn, "RIGHT", 8, 0)
    categoryCollapseBtn:SetScript("OnClick", function() self:ToggleSelectedCategoryCollapsed() end)
    self.categoryCollapseBtn = categoryCollapseBtn

    local categoryArchiveBtn = GC.UI.Button.Create(categoriesContent, "Archive", "secondary", 82, Th.btnH)
    categoryArchiveBtn:SetPoint("TOPLEFT", categoryDownBtn, "BOTTOMLEFT", 0, -8)
    categoryArchiveBtn:SetScript("OnClick", function() self:ToggleSelectedCategoryArchived() end)
    self.categoryArchiveBtn = categoryArchiveBtn

    local categoryListFrame = CreateFrame("Frame", nil, categoriesContent)
    categoryListFrame:SetPoint("TOPLEFT", categoryArchiveBtn, "BOTTOMLEFT", 0, -12)
    categoryListFrame:SetPoint("BOTTOMRIGHT", categoriesContent, "BOTTOMRIGHT", 0, 0)
    self.categoryList = GC.UI.List.Create(categoryListFrame, CATEGORY_ROW_HEIGHT, buildCategoryRow, function(item)
        categoryInput:SetText(item.name or "")
        self:SelectCategory(item.id)
    end)
    self.categoryList:SetEmptyText("No categories.")

    local messagesCard, messagesContent = GC.UI.Panel.Section(frame, "Messages")
    messagesCard:SetPoint("TOPLEFT", categoriesCard, "TOPRIGHT", 12, 0)
    messagesCard:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -P, P)

    self.searchInput = GC.UI.Panel.Input(messagesContent, 260, Th.inputH)
    self.searchInput:SetPoint("TOPLEFT", 0, -2)
    self.searchInput:SetScript("OnTextChanged", function() self:Refresh() end)

    self.showArchivedBtn = GC.UI.Button.Create(messagesContent, "Archived: Off", "secondary", 104, Th.btnH)
    self.showArchivedBtn:SetPoint("LEFT", self.searchInput, "RIGHT", 10, 0)
    self.showArchivedBtn:SetScript("OnClick", function()
        self.showArchived = not self.showArchived
        self:Refresh()
    end)

    self.favoritesOnlyBtn = GC.UI.Button.Create(messagesContent, "Favorites: Off", "secondary", 112, Th.btnH)
    self.favoritesOnlyBtn:SetPoint("LEFT", self.showArchivedBtn, "RIGHT", 8, 0)
    self.favoritesOnlyBtn:SetScript("OnClick", function()
        self.favoritesOnly = not self.favoritesOnly
        self:Refresh()
    end)

    self.messageNewBtn = GC.UI.Button.Create(messagesContent, "New Message", "primary", 112, Th.btnH)
    self.messageNewBtn:SetPoint("TOPLEFT", self.searchInput, "BOTTOMLEFT", 0, -12)
    self.messageNewBtn:SetScript("OnClick", function() self:OpenNewMessage() end)

    self.messageEditBtn = GC.UI.Button.Create(messagesContent, "Edit", "secondary", 64, Th.btnH)
    self.messageEditBtn:SetPoint("LEFT", self.messageNewBtn, "RIGHT", 8, 0)
    self.messageEditBtn:SetScript("OnClick", function() self:OpenEditMessage() end)

    self.duplicateBtn = GC.UI.Button.Create(messagesContent, "Duplicate", "secondary", 86, Th.btnH)
    self.duplicateBtn:SetPoint("LEFT", self.messageEditBtn, "RIGHT", 8, 0)
    self.duplicateBtn:SetScript("OnClick", function() self:OpenDuplicateMessage() end)

    self.messageDeleteBtn = GC.UI.Button.Create(messagesContent, "Delete", "danger", 70, Th.btnH)
    self.messageDeleteBtn:SetPoint("LEFT", self.duplicateBtn, "RIGHT", 8, 0)
    self.messageDeleteBtn:SetScript("OnClick", function() self:PromptDeleteSelectedMessage() end)

    self.sendBtn = GC.UI.Button.Create(messagesContent, "Send", "success", 66, Th.btnH)
    self.sendBtn:SetPoint("LEFT", self.messageDeleteBtn, "RIGHT", 8, 0)
    self.sendBtn:SetScript("OnClick", function() self:SendMessageNow() end)

    self.favoriteBtn = GC.UI.Button.Create(messagesContent, "Favorite", "secondary", 78, Th.btnH)
    self.favoriteBtn:SetPoint("TOPLEFT", self.messageNewBtn, "BOTTOMLEFT", 0, -8)
    self.favoriteBtn:SetScript("OnClick", function() self:ToggleSelectedFavorite() end)

    self.archiveBtn = GC.UI.Button.Create(messagesContent, "Archive", "secondary", 76, Th.btnH)
    self.archiveBtn:SetPoint("LEFT", self.favoriteBtn, "RIGHT", 8, 0)
    self.archiveBtn:SetScript("OnClick", function() self:ToggleSelectedArchive() end)

    self.moveUpBtn = GC.UI.Button.Create(messagesContent, "Move Up", "secondary", 78, Th.btnH)
    self.moveUpBtn:SetPoint("LEFT", self.archiveBtn, "RIGHT", 8, 0)
    self.moveUpBtn:SetScript("OnClick", function() self:MoveSelectedMessage(-1) end)

    self.moveDownBtn = GC.UI.Button.Create(messagesContent, "Move Down", "secondary", 92, Th.btnH)
    self.moveDownBtn:SetPoint("LEFT", self.moveUpBtn, "RIGHT", 8, 0)
    self.moveDownBtn:SetScript("OnClick", function() self:MoveSelectedMessage(1) end)

    self.exportBtn = GC.UI.Button.Create(messagesContent, "Export", "secondary", 68, Th.btnH)
    self.exportBtn:SetPoint("LEFT", self.moveDownBtn, "RIGHT", 8, 0)
    self.exportBtn:SetScript("OnClick", function()
        local id = self:GetSelectedMessageId()
        if not id then status("Select a message to export.", "textWarn"); return end
        self:ShowTemplateExport({ id })
    end)

    self.exportAllBtn = GC.UI.Button.Create(messagesContent, "Export All", "secondary", 88, Th.btnH)
    self.exportAllBtn:SetPoint("LEFT", self.exportBtn, "RIGHT", 8, 0)
    self.exportAllBtn:SetScript("OnClick", function() self:ShowTemplateExport() end)

    self.importBtn = GC.UI.Button.Create(messagesContent, "Import", "secondary", 68, Th.btnH)
    self.importBtn:SetPoint("LEFT", self.exportAllBtn, "RIGHT", 8, 0)
    self.importBtn:SetScript("OnClick", function() self:ShowTemplateImport() end)

    local messageListFrame = CreateFrame("Frame", nil, messagesContent)
    messageListFrame:SetPoint("TOPLEFT", self.favoriteBtn, "BOTTOMLEFT", 0, -12)
    messageListFrame:SetPoint("BOTTOMRIGHT", messagesContent, "BOTTOMRIGHT", 0, 0)
    self.messageList = GC.UI.List.Create(messageListFrame, MESSAGE_ROW_HEIGHT, buildMessageRow, function(item)
        self:SelectMessage(item.id)
    end)
    self.messageList:SetEmptyText("No saved messages in this category.")

    self:Refresh()
end

function MP:Refresh()
    if not self.frame then return end
    local svc = MS()
    if not svc then return end

    local settings = DS() and DS():GetSettings()
    local disabled = settings and settings.enableMessagingModule == false
    setFrameShown(self.disabledBanner, disabled)

    local selectedCategoryId = svc:GetSelectedCategoryId() or "general"
    local selectedCategory = svc:GetCategory(selectedCategoryId) or { id = "general", name = "General" }
    if selectedCategory.archived and not self.showArchived then
        selectedCategoryId = "general"
        svc:SetSelectedCategory(selectedCategoryId)
        selectedCategory = svc:GetCategory(selectedCategoryId) or { id = "general", name = "General" }
    end

    local categories = svc:ListCategories({ showArchived = self.showArchived == true })
    self.categoryList:SetSelected(selectedCategoryId)
    self.categoryList:Refresh(categories)
    if self.categoryInput and not self.categoryInput:HasFocus() then
        self.categoryInput:SetText(selectedCategory.name or "General")
    end

    self.visibleMessages = svc:ListMessages(selectedCategoryId, self:GetFilterOptions())
    local selectedId = self.selectedMessageId or svc:GetSelectedMessageId()
    local selectedMessage = selectedId and svc:GetMessage(selectedId) or nil
    local selectedVisible = false
    for _, row in ipairs(self.visibleMessages or {}) do
        if row.id == selectedId then selectedVisible = true; break end
    end
    if not selectedMessage or not selectedVisible then
        selectedId = nil
        svc:SetSelectedMessage(nil)
    end
    self.selectedMessageId = selectedId
    self.messageList:SetSelected(selectedId)
    self.messageList:Refresh(self.visibleMessages)

    local hasMessage = selectedId ~= nil
    self.showArchivedBtn:SetLabel(self.showArchived and "Archived: On" or "Archived: Off")
    self.favoritesOnlyBtn:SetLabel(self.favoritesOnly and "Favorites: On" or "Favorites: Off")
    self.categoryCollapseBtn:SetLabel(selectedCategory.collapsed and "Expand" or "Collapse")
    self.categoryArchiveBtn:SetLabel(selectedCategory.archived and "Unarchive" or "Archive")
    self.favoriteBtn:SetLabel((selectedMessage and selectedMessage.favorite) and "Unfavorite" or "Favorite")
    self.archiveBtn:SetLabel((selectedMessage and selectedMessage.archived) and "Unarchive" or "Archive")

    setControlEnabled(self.categoryNewBtn, not disabled)
    setControlEnabled(self.categoryRenameBtn, not disabled)
    setControlEnabled(self.categoryDeleteBtn, not disabled and selectedCategoryId ~= "general")
    setControlEnabled(self.categoryUpBtn, not disabled and #categories > 1)
    setControlEnabled(self.categoryDownBtn, not disabled and #categories > 1)
    setControlEnabled(self.categoryCollapseBtn, not disabled)
    setControlEnabled(self.categoryArchiveBtn, not disabled and selectedCategoryId ~= "general")

    setControlEnabled(self.messageNewBtn, not disabled)
    setControlEnabled(self.messageEditBtn, not disabled and hasMessage)
    setControlEnabled(self.duplicateBtn, not disabled and hasMessage)
    setControlEnabled(self.messageDeleteBtn, not disabled and hasMessage)
    setControlEnabled(self.sendBtn, not disabled and hasMessage)
    setControlEnabled(self.favoriteBtn, not disabled and hasMessage)
    setControlEnabled(self.archiveBtn, not disabled and hasMessage)
    setControlEnabled(self.moveUpBtn, not disabled and hasMessage and #self.visibleMessages > 1)
    setControlEnabled(self.moveDownBtn, not disabled and hasMessage and #self.visibleMessages > 1)
    setControlEnabled(self.exportBtn, not disabled and hasMessage)
    setControlEnabled(self.exportAllBtn, not disabled)
    setControlEnabled(self.importBtn, not disabled)
end

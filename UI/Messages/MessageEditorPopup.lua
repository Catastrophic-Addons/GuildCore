-- UI/Messages/MessageEditorPopup.lua
-- Draft-based saved message editor. Save writes to storage; Cancel discards.
local addonName, ns = ...
local GC = ns.GuildCore

GC.UI.MessageEditorPopup = {}
local MEP = GC.UI.MessageEditorPopup

local draft = nil

local function T() return GC.UI.Theme end
local function MS() return GC.Services.Messages end

local function trim(value)
    return GC.Utils and GC.Utils.Trim and GC.Utils.Trim(value or "") or tostring(value or ""):match("^%s*(.-)%s*$")
end

local function status(message, colorKey)
    if GC.UI and GC.UI.MainFrame then
        GC.UI.MainFrame:SetStatus(message, colorKey)
    end
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
    edit:SetWidth(520)
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
        local bottom = offset + scroll:GetHeight()
        if y + lineHeight > bottom then
            scroll:SetVerticalScroll(math.max(0, y + lineHeight - scroll:GetHeight()))
        elseif y < offset then
            scroll:SetVerticalScroll(math.max(0, y))
        end
    end)
    edit:SetScript("OnTextChanged", function(self)
        self:SetWidth(math.max(160, scroll:GetWidth() - 4))
        self:SetHeight(math.max(scroll:GetHeight(), self:GetStringHeight() + 18))
        MEP:RefreshStats()
    end)
    scroll:SetScrollChild(edit)

    local function focusAtEnd()
        edit:SetFocus()
        if edit.SetCursorPosition then edit:SetCursorPosition(#(edit:GetText() or "")) end
    end
    holder:SetScript("OnMouseDown", focusAtEnd)
    scroll:SetScript("OnMouseDown", focusAtEnd)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local child = self:GetScrollChild()
        local maxScroll = math.max(0, (child and child:GetHeight() or 0) - self:GetHeight())
        self:SetVerticalScroll(math.min(maxScroll, math.max(0, self:GetVerticalScroll() - (delta * 28))))
    end)
    holder:SetScript("OnSizeChanged", function(_, width, boxHeight)
        edit:SetWidth(math.max(160, width - 20))
        edit:SetHeight(math.max(boxHeight - 16, edit:GetStringHeight() + 18))
    end)

    return holder, edit
end

local function makeLabel(parent, text, x, y)
    local fs = T().Fs(parent, "tiny", text, "textDimmed")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    return fs
end

local function makeInput(parent, label, x, y, w)
    makeLabel(parent, label, x, y)
    local box = GC.UI.Panel.Input(parent, w, T().inputH)
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 16)
    return box
end

function MEP:GetCategories()
    local svc = MS()
    return svc and svc:ListCategories({ showArchived = true }) or {}
end

function MEP:RefreshCategoryButton()
    if not self.categoryBtn or not draft then return end
    local svc = MS()
    local category = svc and svc:GetCategory(draft.categoryId or "general")
    self.categoryBtn:SetLabel(category and category.name or "General")
end

function MEP:CycleCategory()
    local categories = self:GetCategories()
    if #categories == 0 then return end
    local current = draft and draft.categoryId or "general"
    local nextIndex = 1
    for index, category in ipairs(categories) do
        if category.id == current then
            nextIndex = index + 1
            break
        end
    end
    if nextIndex > #categories then nextIndex = 1 end
    draft.categoryId = categories[nextIndex].id
    self:RefreshCategoryButton()
end

function MEP:GetPlaceholderRows()
    local svc = MS()
    if svc and svc.GetAvailablePlaceholders then
        return svc:GetAvailablePlaceholders({}) or {}
    end
    return {
        { token = "@player.name", label = "Player Name" },
        { token = "@guild.name", label = "Guild Name" },
        { token = "@new.member", label = "New Member" },
        { token = "@target.name", label = "Target Name" },
    }
end

function MEP:RefreshPlaceholderButton()
    local rows = self:GetPlaceholderRows()
    self.placeholderIndex = math.max(1, math.min(#rows, tonumber(self.placeholderIndex) or 1))
    local row = rows[self.placeholderIndex]
    if self.placeholderBtn then self.placeholderBtn:SetLabel(row and row.token or "Placeholder") end
end

function MEP:CyclePlaceholder()
    local rows = self:GetPlaceholderRows()
    if #rows == 0 then return end
    self.placeholderIndex = (tonumber(self.placeholderIndex) or 1) + 1
    if self.placeholderIndex > #rows then self.placeholderIndex = 1 end
    self:RefreshPlaceholderButton()
end

function MEP:InsertPlaceholder()
    local rows = self:GetPlaceholderRows()
    local row = rows[tonumber(self.placeholderIndex) or 1]
    if not row or not self.bodyInput then return end
    self.bodyInput:SetFocus()
    if self.bodyInput.Insert then
        self.bodyInput:Insert(row.token or row.key or "")
    else
        self.bodyInput:SetText((self.bodyInput:GetText() or "") .. tostring(row.token or row.key or ""))
    end
    self:RefreshStats()
end

function MEP:RefreshStats()
    if not self.statsLabel then return end
    local body = self.bodyInput and self.bodyInput:GetText() or ""
    local svc = MS()
    local chunks = svc and svc.SplitMessage and svc:SplitMessage(body, 255) or {}
    self.statsLabel:SetText(string.format("%d chars   %d chunk%s", #body, #chunks, #chunks == 1 and "" or "s"))
end

function MEP:Create()
    if self.frame then return end
    local Th = T()
    local frame = CreateFrame("Frame", "GuildCoreMessageEditorPopup", UIParent)
    frame:SetSize(640, 600)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)
    if GC.UI.FrameLayering then
        GC.UI.FrameLayering:PreparePopupFrame(frame, GC.UI.MainFrame and GC.UI.MainFrame.frame, 75)
    else
        frame:SetFrameStrata("DIALOG")
    end
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()
    Th.Bg(frame, Th.c.panel, Th.c.borderAccent)
    self.frame = frame

    self.title = Th.Fs(frame, "subheader", "Message Editor", "textAccent")
    self.title:SetPoint("TOPLEFT", 14, -12)

    self.titleInput = makeInput(frame, "Message Title", 14, -52, 292)
    makeLabel(frame, "Category", 326, -52)
    self.categoryBtn = GC.UI.Button.Create(frame, "General", "secondary", 180, Th.btnH)
    self.categoryBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 326, -68)
    self.categoryBtn:SetScript("OnClick", function() self:CycleCategory() end)

    self.notesInput = makeInput(frame, "Notes", 14, -104, 580)

    makeLabel(frame, "Message Body", 14, -156)
    local bodyHolder, bodyInput = createMultilineInput(frame, 260)
    bodyHolder:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -174)
    bodyHolder:SetPoint("RIGHT", frame, "RIGHT", -14, 0)
    self.bodyHolder = bodyHolder
    self.bodyInput = bodyInput

    self.placeholderBtn = GC.UI.Button.Create(frame, "Placeholder", "secondary", 150, Th.btnH)
    self.placeholderBtn:SetPoint("TOPLEFT", bodyHolder, "BOTTOMLEFT", 0, -12)
    self.placeholderBtn:SetScript("OnClick", function() self:CyclePlaceholder() end)

    self.insertPlaceholderBtn = GC.UI.Button.Create(frame, "Insert", "secondary", 72, Th.btnH)
    self.insertPlaceholderBtn:SetPoint("LEFT", self.placeholderBtn, "RIGHT", 8, 0)
    self.insertPlaceholderBtn:SetScript("OnClick", function() self:InsertPlaceholder() end)

    self.previewBtn = GC.UI.Button.Create(frame, "Preview Send", "secondary", 104, Th.btnH)
    self.previewBtn:SetPoint("LEFT", self.insertPlaceholderBtn, "RIGHT", 8, 0)
    self.previewBtn:SetScript("OnClick", function()
        self:SaveDraftFields()
        GC.UI.SendPreviewPopup:Open({
            title = draft.title,
            body = draft.body,
            targetChannel = draft.targetChannel,
        })
    end)

    self.statsLabel = Th.Fs(frame, "data", "", "textDimmed")
    self.statsLabel:SetPoint("LEFT", self.previewBtn, "RIGHT", 12, 0)

    local footer = CreateFrame("Frame", nil, frame)
    footer:SetPoint("BOTTOMLEFT")
    footer:SetPoint("BOTTOMRIGHT")
    footer:SetHeight(50)
    Th.Bg(footer, Th.c.chrome, Th.c.border)

    local save = GC.UI.Button.Create(footer, "Save", "primary", 92, Th.btnH)
    save:SetPoint("RIGHT", footer, "RIGHT", -96, 0)
    save:SetScript("OnClick", function() self:Save() end)
    local cancel = GC.UI.Button.Create(footer, "Cancel", "secondary", 78, Th.btnH)
    cancel:SetPoint("RIGHT", footer, "RIGHT", -12, 0)
    cancel:SetScript("OnClick", function() self:Cancel() end)
end

function MEP:SaveDraftFields()
    if not draft then return end
    draft.title = self.titleInput:GetText() or ""
    draft.notes = self.notesInput:GetText() or ""
    draft.body = self.bodyInput:GetText() or ""
end

function MEP:Open(options)
    self:Create()
    options = options or {}
    local message = options.message or {}
    local mode = options.mode or (message.id and "edit" or "new")
    draft = {
        mode = mode,
        id = mode == "edit" and message.id or nil,
        title = mode == "duplicate" and ((message.title or "Untitled Message") .. " Copy") or (message.title or ""),
        categoryId = message.categoryId or options.categoryId or "general",
        notes = message.notes or "",
        body = message.body or "",
        targetChannel = message.targetChannel or "GUILD",
        favorite = mode == "edit" and message.favorite == true or false,
        archived = mode == "edit" and message.archived == true or false,
        onSave = options.onSave,
    }

    self.title:SetText(mode == "new" and "New Message" or (mode == "duplicate" and "Duplicate Message" or "Edit Message"))
    self.titleInput:SetText(draft.title)
    self.notesInput:SetText(draft.notes)
    self.bodyInput:SetText(draft.body)
    self.bodyInput:ClearFocus()
    self.placeholderIndex = 1
    self:RefreshCategoryButton()
    self:RefreshPlaceholderButton()
    self:RefreshStats()
    self.frame:Show()
    self.titleInput:SetFocus()
end

function MEP:Save()
    if not draft then return end
    self:SaveDraftFields()
    local svc = MS()
    if not svc then status("Messaging service is unavailable.", "textDanger"); return end
    if trim(draft.title) == "" then status("Message title is required.", "textDanger"); return end
    if trim(draft.body) == "" then status("Message body is required.", "textDanger"); return end

    local fields = {
        title = draft.title,
        categoryId = draft.categoryId,
        notes = draft.notes,
        body = draft.body,
        targetChannel = draft.targetChannel or "GUILD",
        favorite = draft.favorite,
        archived = draft.archived,
    }
    local saved, ok, err
    if draft.mode == "edit" and draft.id then
        ok, err = svc:UpdateMessage(draft.id, fields)
        if ok then saved = svc:GetMessage(draft.id) end
    else
        saved, err = svc:CreateMessage(fields)
        ok = saved ~= nil
    end
    if not ok then status(err or "Unable to save message.", "textDanger"); return end

    local cb = draft.onSave
    self:Cancel()
    if cb then cb(saved) end
    status("Message saved.", "textSuccess")
end

function MEP:Cancel()
    if self.frame then self.frame:Hide() end
    draft = nil
end

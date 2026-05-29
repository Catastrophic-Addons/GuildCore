-- UI/Messages/SendPreviewPopup.lua
-- Focused send/queue preview for saved messages.
local addonName, ns = ...
local GC = ns.GuildCore

GC.UI.SendPreviewPopup = {}
local SPP = GC.UI.SendPreviewPopup

local currentMessage = nil
local currentPreview = {}
local onQueued = nil

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

local function createMultilineDisplay(parent)
    local Th = T()
    local holder = CreateFrame("Frame", nil, parent)
    Th.Bg(holder, Th.c.panelAlt, Th.c.borderStrong)

    local scroll = CreateFrame("ScrollFrame", nil, holder)
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -8, 8)
    scroll:EnableMouseWheel(true)

    local text = Th.Fs(scroll, "data", "", "textSecond")
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    text:SetWordWrap(true)
    text:SetWidth(500)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(500)
    content:SetHeight(1)
    text:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    scroll:SetScrollChild(content)

    scroll:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = math.max(0, content:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.min(maxScroll, math.max(0, self:GetVerticalScroll() - (delta * 30))))
    end)
    holder:SetScript("OnSizeChanged", function(_, width)
        content:SetWidth(math.max(100, width - 20))
        text:SetWidth(math.max(100, width - 20))
        content:SetHeight(math.max(1, text:GetStringHeight() + 8))
    end)

    holder.text = text
    holder.content = content
    return holder
end

function SPP:GetChannelRows()
    local svc = MS()
    return svc and svc.GetSupportedChannels and svc:GetSupportedChannels() or {
        { key = "GUILD", label = "Guild", requiresRecipient = false },
    }
end

function SPP:GetChannelInfo(channelKey)
    local svc = MS()
    return svc and svc:GetChannelInfo(channelKey or self.channelKey or "GUILD") or { key = "GUILD", label = "Guild", requiresRecipient = false }
end

function SPP:CycleChannel()
    local rows = self:GetChannelRows()
    if #rows == 0 then return end
    local current = self.channelKey or "GUILD"
    local nextIndex = 1
    for index, row in ipairs(rows) do
        if row.key == current then nextIndex = index + 1; break end
    end
    if nextIndex > #rows then nextIndex = 1 end
    self.channelKey = rows[nextIndex].key
    self:Refresh()
end

function SPP:GetOptions()
    local delay = tonumber(self.delayInput and self.delayInput:GetText() or "") or 2
    local limit = tonumber(self.limitInput and self.limitInput:GetText() or "") or 255
    limit = math.max(20, math.min(255, math.floor(limit)))
    return {
        target = self.channelKey or "GUILD",
        recipient = self.recipientInput and self.recipientInput:GetText() or "",
        targetName = self.targetInput and self.targetInput:GetText() or "",
        limit = limit,
        dailyTargetHour = 18,
        dailyTargetMinute = 0,
        delay = math.max(0.5, delay),
    }
end

function SPP:BuildPreview()
    local svc = MS()
    if not svc or not currentMessage then return {} end
    if currentMessage.id then
        local payload = svc:BuildMessagePreview(currentMessage.id, self:GetOptions())
        return payload and payload.preview or {}
    end
    return svc:BuildPreview(currentMessage.body or "", self:GetOptions())
end

function SPP:Refresh()
    if not self.frame or not currentMessage then return end
    local svc = MS()
    local options = self:GetOptions()
    local info = self:GetChannelInfo(options.target)
    self.channelBtn:SetLabel(info.label or options.target)
    self.recipientLabel:SetShown(info.requiresRecipient == true)
    self.recipientInput:SetShown(info.requiresRecipient == true)
    if self.modeBtn and svc then
        self.modeBtn:SetLabel(svc:GetAutomationEnabled() and "Mode: Auto" or "Mode: Manual")
    end
    if not self.delayInput:HasFocus() and svc then
        self.delayInput:SetText(string.format("%.1f", svc:GetAutoSendDelaySeconds()))
    end
    if not self.limitInput:HasFocus() then
        self.limitInput:SetText(tostring(options.limit))
    end

    currentPreview = self:BuildPreview()
    local lines = {}
    for index, chunk in ipairs(currentPreview or {}) do
        lines[#lines + 1] = string.format("[%d] %d chars  %s", index, tonumber(chunk.length) or #(chunk.text or ""), trim(chunk.text or ""))
    end
    if #lines == 0 then lines[1] = "No preview available." end
    self.previewBox.text:SetText(table.concat(lines, "\n\n"))
    self.previewBox.content:SetHeight(math.max(1, self.previewBox.text:GetStringHeight() + 8))
    self.summary:SetText(string.format("%d chunk%s prepared for %s", #currentPreview, #currentPreview == 1 and "" or "s", info.label or options.target))
end

function SPP:QueueSend()
    local svc = MS()
    if not svc or not currentMessage then return end
    local options = self:GetOptions()
    local ok, err = svc:SetAutoSendDelaySeconds(options.delay)
    if not ok then status(err or "Invalid send delay.", "textDanger"); return end
    currentPreview = self:BuildPreview()
    ok, err = svc:QueueChunks(currentPreview, {
        target = options.target,
        recipient = options.recipient,
        sourceMessageId = currentMessage.id,
    })
    if not ok then status(err or "Unable to queue message.", "textDanger"); return end
    if svc:GetAutomationEnabled() then
        svc:StartAutoSend()
    end
    if onQueued then onQueued() end
    status(svc:GetAutomationEnabled() and "Message queued and auto-send started." or "Message queued.", "textSuccess")
    self:Cancel()
end

function SPP:Create()
    if self.frame then return end
    local Th = T()
    local frame = CreateFrame("Frame", "GuildCoreSendPreviewPopup", UIParent)
    frame:SetSize(640, 560)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)
    if GC.UI.FrameLayering then
        GC.UI.FrameLayering:PreparePopupFrame(frame, GC.UI.MainFrame and GC.UI.MainFrame.frame, 76)
    else
        frame:SetFrameStrata("DIALOG")
    end
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()
    Th.Bg(frame, Th.c.panel, Th.c.borderAccent)
    self.frame = frame

    self.title = Th.Fs(frame, "subheader", "Send Preview", "textAccent")
    self.title:SetPoint("TOPLEFT", 14, -12)
    self.summary = Th.Fs(frame, "data", "", "textDimmed")
    self.summary:SetPoint("TOPLEFT", self.title, "BOTTOMLEFT", 0, -8)

    local channelLabel = Th.Fs(frame, "tiny", "Channel", "textDimmed")
    channelLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -70)
    self.channelBtn = GC.UI.Button.Create(frame, "Guild", "secondary", 110, Th.btnH)
    self.channelBtn:SetPoint("TOPLEFT", channelLabel, "BOTTOMLEFT", 0, -4)
    self.channelBtn:SetScript("OnClick", function() self:CycleChannel() end)

    self.recipientLabel = Th.Fs(frame, "tiny", "Target", "textDimmed")
    self.recipientLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 138, -70)
    self.recipientInput = GC.UI.Panel.Input(frame, 150, Th.inputH)
    self.recipientInput:SetPoint("TOPLEFT", self.recipientLabel, "BOTTOMLEFT", 0, -4)

    local targetLabel = Th.Fs(frame, "tiny", "Placeholder Target", "textDimmed")
    targetLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 304, -70)
    self.targetInput = GC.UI.Panel.Input(frame, 140, Th.inputH)
    self.targetInput:SetPoint("TOPLEFT", targetLabel, "BOTTOMLEFT", 0, -4)

    local delayLabel = Th.Fs(frame, "tiny", "Delay", "textDimmed")
    delayLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 460, -70)
    self.delayInput = GC.UI.Panel.Input(frame, 56, Th.inputH)
    self.delayInput:SetPoint("TOPLEFT", delayLabel, "BOTTOMLEFT", 0, -4)

    local limitLabel = Th.Fs(frame, "tiny", "Limit", "textDimmed")
    limitLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 530, -70)
    self.limitInput = GC.UI.Panel.Input(frame, 56, Th.inputH)
    self.limitInput:SetPoint("TOPLEFT", limitLabel, "BOTTOMLEFT", 0, -4)

    local refreshBtn = GC.UI.Button.Create(frame, "Preview", "secondary", 76, Th.btnH)
    refreshBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -108)
    refreshBtn:SetScript("OnClick", function() self:Refresh() end)
    self.refreshBtn = refreshBtn

    self.modeBtn = GC.UI.Button.Create(frame, "Mode: Manual", "secondary", 112, Th.btnH)
    self.modeBtn:SetPoint("LEFT", refreshBtn, "RIGHT", 8, 0)
    self.modeBtn:SetScript("OnClick", function()
        local svc = MS()
        if not svc then return end
        svc:SetAutomationEnabled(not svc:GetAutomationEnabled())
        self:Refresh()
    end)

    self.previewBox = createMultilineDisplay(frame)
    self.previewBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -148)
    self.previewBox:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 60)

    local footer = CreateFrame("Frame", nil, frame)
    footer:SetPoint("BOTTOMLEFT")
    footer:SetPoint("BOTTOMRIGHT")
    footer:SetHeight(50)
    Th.Bg(footer, Th.c.chrome, Th.c.border)

    local queueBtn = GC.UI.Button.Create(footer, "Queue Send", "primary", 104, Th.btnH)
    queueBtn:SetPoint("RIGHT", footer, "RIGHT", -96, 0)
    queueBtn:SetScript("OnClick", function() self:QueueSend() end)
    local cancel = GC.UI.Button.Create(footer, "Cancel", "secondary", 78, Th.btnH)
    cancel:SetPoint("RIGHT", footer, "RIGHT", -12, 0)
    cancel:SetScript("OnClick", function() self:Cancel() end)
end

function SPP:Open(message, options)
    self:Create()
    currentMessage = message
    onQueued = options and options.onQueued or nil
    self.channelKey = message and message.targetChannel or "GUILD"
    self.title:SetText("Send Preview: " .. tostring(message and message.title or "Message"))
    self.recipientInput:SetText("")
    self.targetInput:SetText("")
    if MS() then self.delayInput:SetText(string.format("%.1f", MS():GetAutoSendDelaySeconds())) end
    self.limitInput:SetText("255")
    self.frame:Show()
    self:Refresh()
end

function SPP:Cancel()
    if self.frame then self.frame:Hide() end
    currentMessage = nil
    currentPreview = {}
    onQueued = nil
end

-- UI/Components/Panel.lua
-- Factory for styled section panels, titled cards, and input fields.
local addonName, ns = ...
local GC = ns.GuildCore

GC.UI        = GC.UI or {}
GC.UI.Panel  = {}
local Panel  = GC.UI.Panel

local function T() return GC.UI.Theme end

-- Basic styled frame: dark background + border.
-- @param parent  Parent frame
-- @param bgKey   Color key in T.c (default "panel")
-- @param bdrKey  Border color key (default "border"), nil = no border
function Panel.Create(parent, bgKey, bdrKey)
    local Th = T()
    local f  = CreateFrame("Frame", nil, parent)
    if GC.Perf then GC.Perf:CountUI("frames", 1) end

    local c  = Th.c[bgKey  or "panel"]
    local b  = bdrKey and Th.c[bdrKey] or nil
    Th.Bg(f, c, b)

    return f
end

-- Titled section card: header label at top-left + separator + content area.
-- Returns: frame, contentFrame (inset below the header)
function Panel.Section(parent, title, h)
    local Th = T()
    local P  = Th.padding

    local frame = CreateFrame("Frame", nil, parent)
    if GC.Perf then GC.Perf:CountUI("frames", 1) end
    Th.Bg(frame, Th.c.panel, Th.c.border)

    -- Title bar background
    local titleBg = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
    titleBg:SetPoint("TOPLEFT"); titleBg:SetPoint("TOPRIGHT"); titleBg:SetHeight(28)
    local ac = Th.c.accentDim
    titleBg:SetColorTexture(ac[1], ac[2], ac[3], ac[4])

    -- Accent left-edge bar
    local accent = frame:CreateTexture(nil, "ARTWORK")
    accent:SetPoint("TOPLEFT"); accent:SetPoint("BOTTOMLEFT"); accent:SetWidth(1)
    local a = Th.c.accent
    accent:SetColorTexture(a[1], a[2], a[3], 0.48)

    -- Title text
    local lbl = Th.Fs(frame, "subheader", title, "textAccent")
    lbl:SetPoint("TOPLEFT", P, -7)

    -- Separator
    Th.HSep(frame, -28, 0.55)

    -- Inner content frame
    local content = CreateFrame("Frame", nil, frame)
    if GC.Perf then GC.Perf:CountUI("frames", 1) end
    content:SetPoint("TOPLEFT",  frame, "TOPLEFT",  P, -36)
    content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -P, P)

    return frame, content
end

-- Styled EditBox (single-line text input).
-- @param parent  Parent frame
-- @param w, h    Dimensions
function Panel.Input(parent, w, h)
    local Th = T()
    h = h or Th.inputH
    w = w or 180

    local eb = CreateFrame("EditBox", nil, parent)
    if GC.Perf then
        GC.Perf:CountUI("inputs", 1)
        GC.Perf:CountUI("textures", 9)
    end
    eb:SetSize(w, h)
    eb:SetAutoFocus(false)
    eb:SetTextInsets(6, 6, 0, 0) -- 6 px L/R breathing room inside the 1-px border

    Th.ApplyFont(eb, "input")
    if Th.RegisterRefresh then
        Th:RegisterRefresh(function()
            Th.ApplyFont(eb, "input")
        end)
    end

    local pc = Th.c.textPrimary
    eb:SetTextColor(pc[1], pc[2], pc[3], pc[4])

    local ic = Th.c.panelAlt
    local bc = Th.c.borderStrong
    local surface = Th.RoundedSurface(eb, ic, bc, 6, "BACKGROUND", -8)
    eb._surface = surface

    local function draw(focused)
        local Th2 = T()
        local fill = Th2.c.panelAlt
        local edge = focused and Th2.c.borderAccent or Th2.c.borderStrong
        surface:SetColorTexture(fill[1], fill[2], fill[3], fill[4] or 1)
        surface:SetBorderColor(edge[1], edge[2], edge[3], focused and 0.9 or 0.72)
        local text = Th2.c.textPrimary
        eb:SetTextColor(text[1], text[2], text[3], text[4] or 1)
    end

    -- Focused highlight
    eb:HookScript("OnEditFocusGained", function()
        draw(true)
    end)
    eb:HookScript("OnEditFocusLost", function()
        draw(false)
    end)

    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    if Th.RegisterRefresh then
        Th:RegisterRefresh(function() draw(eb:HasFocus()) end)
    end
    draw(false)

    return eb
end

-- Compact switch control used by settings and workflow filters.
-- Returns a Button frame with :SetChecked(value, silent), :GetChecked(),
-- :SetEnabled(value), and :SetOnChange(callback).
function Panel.Toggle(parent, w, h, onChange)
    local Th = T()
    local switch = CreateFrame("Button", nil, parent)
    if GC.Perf then
        GC.Perf:CountUI("buttons", 1)
        GC.Perf:CountUI("textures", 3)
    end
    switch:SetSize(w or 46, h or 22)

    local controlH = h or 22
    local track = Th.RoundedSurface(switch, Th.c.btnDisabled, Th.c.border, math.floor(controlH / 2), "BACKGROUND", -8)
    local knob = CreateFrame("Frame", nil, switch)
    knob:SetSize(math.max(10, controlH - 6), math.max(10, controlH - 6))
    local knobSurface = Th.RoundedSurface(knob, Th.c.textDimmed, nil, math.floor((controlH - 6) / 2), "OVERLAY", 1)

    local checked = false
    local enabled = true
    local changeCallback = onChange

    local function draw()
        local Th2 = T()
        local trackColor = checked and Th2.c.accentMid or Th2.c.btnDisabled
        local knobColor = checked and Th2.c.textPrimary or Th2.c.textDimmed

        track:SetColorTexture(trackColor[1], trackColor[2], trackColor[3], checked and 0.55 or 1)
        local border = Th2.c.border
        track:SetBorderColor(border[1], border[2], border[3], 0.5)
        knobSurface:SetColorTexture(knobColor[1], knobColor[2], knobColor[3], enabled and 1 or 0.45)
        knob:ClearAllPoints()
        knob:SetPoint(checked and "RIGHT" or "LEFT", switch, checked and "RIGHT" or "LEFT", checked and -2 or 2, 0)
        switch:SetAlpha(enabled and 1 or 0.55)
    end

    switch:SetScript("OnClick", function()
        if not enabled then return end
        checked = not checked
        draw()
        if changeCallback then changeCallback(checked) end
    end)

    function switch:SetChecked(value, silent)
        checked = value and true or false
        draw()
        if not silent and changeCallback then changeCallback(checked) end
    end

    function switch:GetChecked()
        return checked
    end

    function switch:SetEnabled(value)
        enabled = value and true or false
        self:EnableMouse(enabled)
        draw()
    end

    function switch:SetOnChange(callback)
        changeCallback = callback
    end

    if Th.RegisterRefresh then
        Th:RegisterRefresh(draw)
    end

    draw()
    return switch
end

-- Stat tile: a compact panel showing a number + label. Used in the dashboard.
-- Returns the frame and two setters: SetValue(n), SetLabel(str)
function Panel.StatTile(parent, label, value)
    local Th  = T()
    local f   = CreateFrame("Frame", nil, parent)
    if GC.Perf then GC.Perf:CountUI("frames", 1) end
    Th.Bg(f, Th.c.panelAlt, Th.c.border)

    -- Accent top stripe
    local stripe = f:CreateTexture(nil, "ARTWORK")
    stripe:SetPoint("TOPLEFT"); stripe:SetPoint("TOPRIGHT"); stripe:SetHeight(2)
    local a = Th.c.accent
    stripe:SetColorTexture(a[1], a[2], a[3], 0.42)

    local numFs = Th.Fs(f, "dataLarge", tostring(value or 0), "textPrimary")
    numFs:SetPoint("CENTER", 0, 8)
    numFs:SetJustifyH("CENTER")

    local lblFs = Th.Fs(f, "small", label or "", "textDimmed")
    lblFs:SetPoint("CENTER", 0, -12)
    lblFs:SetJustifyH("CENTER")

    return f,
        function(n) numFs:SetText(tostring(n or 0)) end,
        function(s) lblFs:SetText(s or "") end
end

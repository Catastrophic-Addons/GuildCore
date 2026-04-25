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
    Th.Bg(frame, Th.c.panel, Th.c.border)

    -- Title bar background
    local titleBg = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
    titleBg:SetPoint("TOPLEFT"); titleBg:SetPoint("TOPRIGHT"); titleBg:SetHeight(28)
    local ac = Th.c.accentDim
    titleBg:SetColorTexture(ac[1], ac[2], ac[3], ac[4])

    -- Accent left-edge bar
    local accent = frame:CreateTexture(nil, "ARTWORK")
    accent:SetPoint("TOPLEFT"); accent:SetPoint("BOTTOMLEFT"); accent:SetWidth(2)
    local a = Th.c.accent
    accent:SetColorTexture(a[1], a[2], a[3], 0.8)

    -- Title text
    local lbl = Th.Fs(frame, "subheader", title, "textAccent")
    lbl:SetPoint("TOPLEFT", P, -7)

    -- Separator
    Th.HSep(frame, -28)

    -- Inner content frame
    local content = CreateFrame("Frame", nil, frame)
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
    eb:SetSize(w, h)
    eb:SetAutoFocus(false)
    eb:SetFontObject("ChatFontNormal")

    Th.ApplyFont(eb, "input")
    if Th.RegisterRefresh then
        Th:RegisterRefresh(function()
            Th.ApplyFont(eb, "input")
        end)
    end

    local pc = Th.c.textPrimary
    eb:SetTextColor(pc[1], pc[2], pc[3], pc[4])

    -- Background
    local bg = eb:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetAllPoints()
    local ic = Th.c.panelAlt
    bg:SetColorTexture(ic[1], ic[2], ic[3], ic[4])

    -- Border
    local function edgeTex(sublevel)
        local e = eb:CreateTexture(nil, "BACKGROUND", nil, sublevel)
        local bc = Th.c.borderStrong
        e:SetColorTexture(bc[1], bc[2], bc[3], bc[4])
        return e
    end
    local top, bot, lft, rgt = edgeTex(-7), edgeTex(-7), edgeTex(-7), edgeTex(-7)
    top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(1)
    bot:SetPoint("BOTTOMLEFT"); bot:SetPoint("BOTTOMRIGHT"); bot:SetHeight(1)
    lft:SetPoint("TOPLEFT"); lft:SetPoint("BOTTOMLEFT"); lft:SetWidth(1)
    rgt:SetPoint("TOPRIGHT"); rgt:SetPoint("BOTTOMRIGHT"); rgt:SetWidth(1)

    -- Focused highlight
    eb:SetScript("OnEditFocusGained", function()
        local ac = Th.c.borderAccent
        top:SetColorTexture(ac[1], ac[2], ac[3], ac[4])
        bot:SetColorTexture(ac[1], ac[2], ac[3], ac[4])
        lft:SetColorTexture(ac[1], ac[2], ac[3], ac[4])
        rgt:SetColorTexture(ac[1], ac[2], ac[3], ac[4])
    end)
    eb:SetScript("OnEditFocusLost", function()
        local bc = Th.c.borderStrong
        top:SetColorTexture(bc[1], bc[2], bc[3], bc[4])
        bot:SetColorTexture(bc[1], bc[2], bc[3], bc[4])
        lft:SetColorTexture(bc[1], bc[2], bc[3], bc[4])
        rgt:SetColorTexture(bc[1], bc[2], bc[3], bc[4])
    end)

    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    return eb
end

-- Stat tile: a compact panel showing a number + label. Used in the dashboard.
-- Returns the frame and two setters: SetValue(n), SetLabel(str)
function Panel.StatTile(parent, label, value)
    local Th  = T()
    local f   = CreateFrame("Frame", nil, parent)
    Th.Bg(f, Th.c.panelAlt, Th.c.border)

    -- Accent top stripe
    local stripe = f:CreateTexture(nil, "ARTWORK")
    stripe:SetPoint("TOPLEFT"); stripe:SetPoint("TOPRIGHT"); stripe:SetHeight(2)
    local a = Th.c.accent
    stripe:SetColorTexture(a[1], a[2], a[3], 0.7)

    local numFs = Th.Fs(f, "title", tostring(value or 0), "textPrimary")
    numFs:SetPoint("CENTER", 0, 8)
    numFs:SetJustifyH("CENTER")

    local lblFs = Th.Fs(f, "small", label or "", "textDimmed")
    lblFs:SetPoint("CENTER", 0, -12)
    lblFs:SetJustifyH("CENTER")

    return f,
        function(n) numFs:SetText(tostring(n or 0)) end,
        function(s) lblFs:SetText(s or "") end
end

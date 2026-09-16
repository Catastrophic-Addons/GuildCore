-- UI/Components/Button.lua
-- Factory for styled, hoverable buttons. No default WoW templates used.
local addonName, ns = ...
local GC = ns.GuildCore

GC.UI         = GC.UI or {}
GC.UI.Button  = {}
local Btn     = GC.UI.Button
local T       -- resolved after Theme loads

-- Lazily grab the theme reference so load order doesn't matter
local function theme() T = T or GC.UI.Theme; return T end

-- colorKey pairs: normal/hover color keys from T.c
local TYPE_COLORS = {
    primary = {"btnPrimary", "btnPrimHov"},
    secondary = {"btnSecond", "btnSecHov"},
    warning = {"statusWarn", "statusWarn"},
    danger  = {"btnDanger",  "btnDanHov"},
    success = {"btnSuccess", "btnSucHov"},
}

-- Create a fully styled button.
-- @param parent  Parent frame
-- @param label   Button text
-- @param bType   "primary" | "secondary" | "warning" | "danger" | "success"
-- @param w, h    Dimensions (optional, defaults 120×24)
-- @returns button frame with :SetLabel(), :SetEnabled(), :SetActive()
local function createStyledButton(parent, label, bType, w, h, template)
    local T = theme()
    bType = bType or "secondary"
    w = w or 120
    h = h or T.btnH

    local keys = TYPE_COLORS[bType] or TYPE_COLORS.secondary
    local normalKey = keys[1]
    local hoverKey = keys[2]
    local cn   = T.c[normalKey]

    local btn = CreateFrame("Button", nil, parent, template)
    if GC.Perf then
        GC.Perf:CountUI("buttons", 1)
        GC.Perf:CountUI("textures", 4)
        GC.Perf:CountUI("fontStrings", 1)
    end
    btn:SetSize(w, h)

    -- Background surface (exposed as btn._bg for external active-state control)
    local bg = T.RoundedSurface(btn, cn, T.c.border, 6, "BACKGROUND", -8)
    btn._bg = bg

    -- Top-edge highlight (subtle 1px lighter strip)
    local shine = btn:CreateTexture(nil, "BORDER")
    shine:SetPoint("TOPLEFT", btn, "TOPLEFT", 6, 0)
    shine:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -6, 0)
    shine:SetHeight(1)
    shine:SetColorTexture(1, 1, 1, 0.035)

    -- Bottom-edge shadow
    local shadow = btn:CreateTexture(nil, "BORDER")
    shadow:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 6, 0)
    shadow:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -6, 0)
    shadow:SetHeight(1)
    shadow:SetColorTexture(0, 0, 0, 0.12)

    local bdr = bg

    -- Label
    local fs = btn:CreateFontString(nil, "OVERLAY")
    T.ApplyFont(fs, "body")
    fs:SetAllPoints()
    fs:SetJustifyH("CENTER"); fs:SetJustifyV("MIDDLE")
    fs:SetTextColor(1, 1, 1, 1)
    fs:SetText(label or "")

    -- State
    local enabled = true
    local hovered = false
    local active = false

    local function setBg(colorKey)
        local c = theme().c[colorKey]
        bg:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    end

    local function setType(nextType)
        bType = nextType or "secondary"
        keys = TYPE_COLORS[bType] or TYPE_COLORS.secondary
        normalKey = keys[1]
        hoverKey = keys[2]
    end

    local function refreshVisual()
        if enabled then
            if active then
                setBg("btnPrimary")
            else
                setBg(hovered and hoverKey or normalKey)
            end
            fs:SetTextColor(1, 1, 1, 1)
        else
            setBg("btnDisabled")
            fs:SetTextColor(0.35, 0.35, 0.38, 1)
        end
        local bc = theme().c.border
        if bdr.SetBorderColor then
            bdr:SetBorderColor(bc[1], bc[2], bc[3], 0.34)
        end
    end

    btn:SetScript("OnEnter", function()
        hovered = true
        refreshVisual()
    end)
    btn:SetScript("OnLeave", function()
        hovered = false
        refreshVisual()
    end)

    function btn:SetLabel(txt)  fs:SetText(txt or "") end

    function btn:SetVisualType(nextType)
        setType(nextType)
        refreshVisual()
    end

    function btn:SetActive(state)
        active = state and true or false
        refreshVisual()
    end

    function btn:SetEnabled(state)
        enabled = state
        refreshVisual()
        btn:EnableMouse(state and true or false)
    end

    function btn:RefreshTheme()
        theme().ApplyFont(fs, "body")
        refreshVisual()
    end

    -- Attach a GameTooltip shown on hover.  Pass nil to remove.
    function btn:SetTooltip(title, body)
        if title then
            btn:SetScript("OnEnter", function(self)
                hovered = true
                refreshVisual()
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(title, 1, 1, 1, 1, true)
                if body then GameTooltip:AddLine(body, 0.8, 0.8, 0.8, true) end
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function()
                hovered = false
                refreshVisual()
                GameTooltip:Hide()
            end)
        else
            btn:SetScript("OnEnter", function()
                hovered = true
                refreshVisual()
            end)
            btn:SetScript("OnLeave", function()
                hovered = false
                refreshVisual()
            end)
        end
    end

    if T.RegisterRefresh then
        T:RegisterRefresh(function()
            if btn.RefreshTheme then
                btn:RefreshTheme()
            end
        end)
    end

    return btn
end

function Btn.Create(parent, label, bType, w, h)
    return createStyledButton(parent, label, bType, w, h, nil)
end

function Btn.CreateSecure(parent, label, bType, w, h)
    return createStyledButton(parent, label, bType, w, h, "SecureActionButtonTemplate")
end

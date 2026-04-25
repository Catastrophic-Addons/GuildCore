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
    danger  = {"btnDanger",  "btnDanHov"},
    success = {"btnSuccess", "btnSucHov"},
}

-- Create a fully styled button.
-- @param parent  Parent frame
-- @param label   Button text
-- @param bType   "primary" | "secondary" | "danger" | "success"
-- @param w, h    Dimensions (optional, defaults 120×24)
-- @returns button frame with :SetLabel(), :SetEnabled()
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
    btn:SetSize(w, h)

    -- Background texture (exposed as btn._bg for external active-state control)
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(cn[1], cn[2], cn[3], cn[4] or 1)
    btn._bg = bg

    -- Top-edge highlight (subtle 1px lighter strip)
    local shine = btn:CreateTexture(nil, "BORDER")
    shine:SetPoint("TOPLEFT"); shine:SetPoint("TOPRIGHT"); shine:SetHeight(1)
    shine:SetColorTexture(1, 1, 1, 0.06)

    -- Bottom-edge shadow
    local shadow = btn:CreateTexture(nil, "BORDER")
    shadow:SetPoint("BOTTOMLEFT"); shadow:SetPoint("BOTTOMRIGHT"); shadow:SetHeight(1)
    shadow:SetColorTexture(0, 0, 0, 0.25)

    -- Border
    local bdr = btn:CreateTexture(nil, "BACKGROUND", nil, -7)
    bdr:SetPoint("TOPLEFT", -1, 1); bdr:SetPoint("BOTTOMRIGHT", 1, -1)
    local bc = T.c.border
    bdr:SetColorTexture(bc[1], bc[2], bc[3], 0.6)

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

    local function setBg(colorKey)
        local c = theme().c[colorKey]
        bg:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    end

    local function refreshVisual()
        if enabled then
            setBg(hovered and hoverKey or normalKey)
            fs:SetTextColor(1, 1, 1, 1)
        else
            setBg("btnDisabled")
            fs:SetTextColor(0.35, 0.35, 0.38, 1)
        end
        local bc = theme().c.border
        bdr:SetColorTexture(bc[1], bc[2], bc[3], 0.6)
    end

    btn:SetScript("OnEnter", function()
        hovered = true
        if enabled then setBg(hoverKey) end
    end)
    btn:SetScript("OnLeave", function()
        hovered = false
        if enabled then setBg(normalKey) end
    end)

    function btn:SetLabel(txt)  fs:SetText(txt or "") end

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
                if enabled then setBg(hoverKey) end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(title, 1, 1, 1, 1, true)
                if body then GameTooltip:AddLine(body, 0.8, 0.8, 0.8, true) end
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function()
                hovered = false
                if enabled then setBg(normalKey) end
                GameTooltip:Hide()
            end)
        else
            btn:SetScript("OnEnter", function()
                hovered = true
                if enabled then setBg(hoverKey) end
            end)
            btn:SetScript("OnLeave", function()
                hovered = false
                if enabled then setBg(normalKey) end
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

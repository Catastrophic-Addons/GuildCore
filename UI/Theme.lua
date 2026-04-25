-- /GuildCore/UI/Theme.lua
local addonName, ns = ...
local GC = ns.GuildCore

GC.UI = GC.UI or {}
GC.UI.Theme = {}
local T = GC.UI.Theme

-- Layout dimensions
T.width        = 960
T.height       = 660
T.minWidth     = 820
T.minHeight    = 520
T.navWidth     = 148
T.detailWidth  = 280
T.titleBarH    = 48
T.statusBarH   = 28
T.colBarH      = 24
T.padding      = 12
T.rowH         = 28
T.btnH         = 26
T.inputH       = 24
T.sectionGap   = 10

-- Color palette (arrays: {r, g, b, a})
T.c = {
    -- Window / chrome
    bg            = {0.060, 0.060, 0.080, 0.97},
    chrome        = {0.040, 0.040, 0.055, 1.00},
    panel         = {0.090, 0.090, 0.115, 1.00},
    panelAlt      = {0.068, 0.068, 0.092, 1.00},
    panelHover    = {0.130, 0.135, 0.180, 1.00},
    border        = {0.200, 0.200, 0.260, 1.00},
    borderStrong  = {0.260, 0.260, 0.340, 1.00},
    borderAccent  = {0.310, 0.820, 0.780, 0.65},
    separator     = {0.150, 0.150, 0.200, 1.00},
    -- Accent
    accent        = {0.310, 0.820, 0.780, 1.00},
    accentDim     = {0.310, 0.820, 0.780, 0.08},
    accentMid     = {0.310, 0.820, 0.780, 0.25},
    -- Text
    textPrimary   = {1.000, 1.000, 1.000, 1.00},
    textSecond    = {0.720, 0.720, 0.780, 1.00},
    textDimmed    = {0.450, 0.450, 0.520, 1.00},
    textAccent    = {0.310, 0.820, 0.780, 1.00},
    textWarn      = {0.940, 0.750, 0.100, 1.00},
    textDanger    = {0.920, 0.300, 0.260, 1.00},
    textSuccess   = {0.220, 0.820, 0.460, 1.00},
    -- Buttons
    btnPrimary    = {0.130, 0.400, 0.570, 1.00},
    btnPrimHov    = {0.180, 0.540, 0.740, 1.00},
    btnSecond     = {0.120, 0.120, 0.162, 1.00},
    btnSecHov     = {0.185, 0.185, 0.245, 1.00},
    btnDanger     = {0.520, 0.090, 0.090, 1.00},
    btnDanHov     = {0.700, 0.130, 0.130, 1.00},
    btnSuccess    = {0.090, 0.350, 0.180, 1.00},
    btnSucHov     = {0.130, 0.470, 0.240, 1.00},
    btnDisabled   = {0.075, 0.075, 0.098, 1.00},
    -- Nav sidebar
    navBg         = {0.065, 0.065, 0.088, 1.00},
    navActive     = {0.120, 0.120, 0.165, 1.00},
    navHover      = {0.095, 0.095, 0.132, 1.00},
    -- Status / indicators
    statusActive  = {0.220, 0.800, 0.440, 1.00},
    statusInact   = {0.800, 0.260, 0.200, 1.00},
    statusWarn    = {0.920, 0.720, 0.100, 1.00},
    -- Roster rows
    rowOdd        = {0.068, 0.068, 0.092, 1.00},
    rowEven       = {0.090, 0.090, 0.115, 1.00},
    rowHover      = {0.135, 0.170, 0.220, 1.00},
    rowSelected   = {0.110, 0.240, 0.310, 1.00},
}

-- Font registry {path, size, flags}
T.f = {
    title     = {"Fonts\\FRIZQT__.TTF", 22, ""},
    header    = {"Fonts\\FRIZQT__.TTF", 15, ""},
    subheader = {"Fonts\\FRIZQT__.TTF", 13, ""},
    nav       = {"Fonts\\ARIALN.TTF",   13, ""},
    body      = {"Fonts\\ARIALN.TTF",   12, ""},
    label     = {"Fonts\\ARIALN.TTF",   12, ""},
    small     = {"Fonts\\ARIALN.TTF",   11, ""},
    tiny      = {"Fonts\\ARIALN.TTF",   10, ""},
    status    = {"Fonts\\ARIALN.TTF",   11, "OUTLINE"},
}

-- Class colors for roster display
T.classColor = {
    WARRIOR     = {0.78, 0.61, 0.43},
    PALADIN     = {0.96, 0.55, 0.73},
    HUNTER      = {0.67, 0.83, 0.45},
    ROGUE       = {1.00, 0.96, 0.41},
    PRIEST      = {1.00, 1.00, 1.00},
    DEATHKNIGHT = {0.77, 0.12, 0.23},
    SHAMAN      = {0.00, 0.44, 0.87},
    MAGE        = {0.41, 0.80, 0.94},
    WARLOCK     = {0.58, 0.51, 0.79},
    MONK        = {0.00, 1.00, 0.60},
    DRUID       = {1.00, 0.49, 0.04},
    DEMONHUNTER = {0.64, 0.19, 0.79},
    EVOKER      = {0.20, 0.58, 0.50},
}

local BASE_COLORS = GC.Utils and GC.Utils.DeepCopy and GC.Utils.DeepCopy(T.c) or {
    bg = T.c.bg,
    chrome = T.c.chrome,
    panel = T.c.panel,
    panelAlt = T.c.panelAlt,
    panelHover = T.c.panelHover,
    border = T.c.border,
    borderStrong = T.c.borderStrong,
    borderAccent = T.c.borderAccent,
    separator = T.c.separator,
    accent = T.c.accent,
    accentDim = T.c.accentDim,
    accentMid = T.c.accentMid,
    textPrimary = T.c.textPrimary,
    textSecond = T.c.textSecond,
    textDimmed = T.c.textDimmed,
    textAccent = T.c.textAccent,
    textWarn = T.c.textWarn,
    textDanger = T.c.textDanger,
    textSuccess = T.c.textSuccess,
    btnPrimary = T.c.btnPrimary,
    btnPrimHov = T.c.btnPrimHov,
    btnSecond = T.c.btnSecond,
    btnSecHov = T.c.btnSecHov,
    btnDanger = T.c.btnDanger,
    btnDanHov = T.c.btnDanHov,
    btnSuccess = T.c.btnSuccess,
    btnSucHov = T.c.btnSucHov,
    btnDisabled = T.c.btnDisabled,
    navBg = T.c.navBg,
    navActive = T.c.navActive,
    navHover = T.c.navHover,
    statusActive = T.c.statusActive,
    statusInact = T.c.statusInact,
    statusWarn = T.c.statusWarn,
    rowOdd = T.c.rowOdd,
    rowEven = T.c.rowEven,
    rowHover = T.c.rowHover,
    rowSelected = T.c.rowSelected,
}

local PRESETS = {
    guildcore = {
        label = "GuildCore",
        colors = {},
    },
    ember = {
        label = "Emberwatch",
        colors = {
            bg = {0.080, 0.055, 0.060, 0.97},
            chrome = {0.060, 0.040, 0.045, 1.00},
            panel = {0.110, 0.080, 0.088, 1.00},
            panelAlt = {0.088, 0.065, 0.074, 1.00},
            borderAccent = {0.960, 0.520, 0.300, 0.70},
            accent = {0.960, 0.520, 0.300, 1.00},
            accentDim = {0.960, 0.520, 0.300, 0.08},
            accentMid = {0.960, 0.520, 0.300, 0.25},
            textAccent = {0.960, 0.620, 0.360, 1.00},
            btnPrimary = {0.420, 0.260, 0.140, 1.00},
            btnPrimHov = {0.580, 0.340, 0.180, 1.00},
            navActive = {0.180, 0.120, 0.115, 1.00},
            navHover = {0.145, 0.095, 0.100, 1.00},
            rowSelected = {0.290, 0.180, 0.130, 1.00},
        },
    },
    tideglass = {
        label = "Tideglass",
        colors = {
            bg = {0.045, 0.060, 0.080, 0.97},
            chrome = {0.035, 0.050, 0.070, 1.00},
            panel = {0.065, 0.090, 0.118, 1.00},
            panelAlt = {0.055, 0.078, 0.102, 1.00},
            borderAccent = {0.380, 0.700, 0.980, 0.68},
            accent = {0.380, 0.700, 0.980, 1.00},
            accentDim = {0.380, 0.700, 0.980, 0.08},
            accentMid = {0.380, 0.700, 0.980, 0.25},
            textAccent = {0.460, 0.790, 1.000, 1.00},
            btnPrimary = {0.120, 0.330, 0.520, 1.00},
            btnPrimHov = {0.180, 0.450, 0.700, 1.00},
            navActive = {0.090, 0.130, 0.180, 1.00},
            navHover = {0.078, 0.112, 0.155, 1.00},
            rowSelected = {0.090, 0.210, 0.320, 1.00},
        },
    },
}

local PRESET_ORDER = {"guildcore", "ember", "tideglass"}
local themedTextures = {}
local themedFontStrings = {}
local refreshCallbacks = {}

local function copyColorTable(source)
    local copy = {}
    for key, value in pairs(source or {}) do
        if type(value) == "table" then
            copy[key] = {unpack(value)}
        else
            copy[key] = value
        end
    end
    return copy
end

local function colorKeyFor(value)
    if type(value) ~= "table" then return nil end
    for key, color in pairs(T.c or {}) do
        if color == value then
            return key
        end
    end
    return nil
end

local function applyTextureColor(texture, colorKey, alphaOverride)
    local c = colorKey and T.c[colorKey]
    if texture and c then
        texture:SetColorTexture(c[1], c[2], c[3], alphaOverride or c[4] or 1)
    end
end

local function trackTexture(texture, colorKey, alphaOverride)
    if texture and colorKey then
        themedTextures[#themedTextures + 1] = {texture = texture, colorKey = colorKey, alpha = alphaOverride}
    end
end

local function applyFontStringColor(fontString, colorKey)
    local c = colorKey and T.c[colorKey]
    if fontString and c then
        fontString:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    end
end

function T:ApplyPreset(name)
    local presetKey = PRESETS[name] and name or "guildcore"
    local preset = PRESETS[presetKey]
    self.c = copyColorTable(BASE_COLORS)
    for key, value in pairs(preset.colors or {}) do
        self.c[key] = {unpack(value)}
    end
    self.activePreset = presetKey
    return presetKey
end

function T:RegisterRefresh(callback)
    if type(callback) == "function" then
        refreshCallbacks[#refreshCallbacks + 1] = callback
    end
end

function T:RefreshRegistered()
    for _, item in ipairs(themedTextures) do
        applyTextureColor(item.texture, item.colorKey, item.alpha)
    end
    for _, item in ipairs(themedFontStrings) do
        applyFontStringColor(item.fontString, item.colorKey)
    end
    for _, callback in ipairs(refreshCallbacks) do
        pcall(callback)
    end
end

function T:ApplyPresetLive(name)
    local presetKey = self:ApplyPreset(name)
    self:RefreshRegistered()
    return presetKey
end

function T:GetPresetKeys()
    return PRESET_ORDER
end

function T:GetPresetLabel(name)
    local preset = PRESETS[name]
    return preset and preset.label or PRESETS.guildcore.label
end

function T:GetNextPresetKey(current)
    current = current or self.activePreset or "guildcore"
    for index, key in ipairs(PRESET_ORDER) do
        if key == current then
            return PRESET_ORDER[index + 1] or PRESET_ORDER[1]
        end
    end
    return PRESET_ORDER[1]
end

function T:ApplyConfiguredPreset()
    local settings = GC.DB and GC.DB.GetSettings and GC.DB:GetSettings()
    local preset = settings and settings.themePreset or "guildcore"
    return self:ApplyPreset(preset)
end

T:ApplyPreset("guildcore")

-- Show a standard GameTooltip anchored to a frame.
-- Call T.Tooltip(frame, title, body) to attach; tooltip hides on OnLeave automatically.
function T.Tooltip(frame, title, body)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if title then GameTooltip:SetText(title, 1, 1, 1, 1, true) end
        if body  then GameTooltip:AddLine(body, 0.8, 0.8, 0.8, true) end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

-- Apply solid color background to a frame. border (optional) draws 1px edges.
function T.Bg(frame, c, border)
    local bgKey = colorKeyFor(c)
    local borderKey = colorKeyFor(border)
    local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetAllPoints()
    bg:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    trackTexture(bg, bgKey)
    frame._bg = bg
    if border then
        local b = border
        local function edge()
            local e = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
            e:SetColorTexture(b[1], b[2], b[3], b[4] or 1)
            trackTexture(e, borderKey)
            return e
        end
        local top, bot, lft, rgt = edge(), edge(), edge(), edge()
        top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(1)
        bot:SetPoint("BOTTOMLEFT"); bot:SetPoint("BOTTOMRIGHT"); bot:SetHeight(1)
        lft:SetPoint("TOPLEFT"); lft:SetPoint("BOTTOMLEFT"); lft:SetWidth(1)
        rgt:SetPoint("TOPRIGHT"); rgt:SetPoint("BOTTOMRIGHT"); rgt:SetWidth(1)
    end
    return bg
end

-- Create a 1px horizontal separator line inside a parent frame
function T.HSep(parent, yOffset, alpha)
    local line = parent:CreateTexture(nil, "ARTWORK")
    local sc = T.c.separator
    line:SetColorTexture(sc[1], sc[2], sc[3], alpha or sc[4])
    trackTexture(line, "separator", alpha)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT",  parent, "TOPLEFT",  0, yOffset or 0)
    line:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, yOffset or 0)
    return line
end

-- Create a FontString using the theme font registry
function T.Fs(parent, fontKey, text, colorKey)
    local fd = T.f[fontKey] or T.f.body
    local c  = colorKey and T.c[colorKey] or T.c.textPrimary
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(fd[1], fd[2], fd[3])
    fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    themedFontStrings[#themedFontStrings + 1] = {fontString = fs, colorKey = colorKey or "textPrimary"}
    if text then fs:SetText(text) end
    return fs
end

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
T.colBarH      = 28
T.padding      = 14
T.rowH         = 32
T.btnH         = 30
T.inputH       = 28
T.sectionGap   = 12
T.cornerRadius  = 8

-- Color palette (arrays: {r, g, b, a})
T.c = {
    -- Window / chrome
    bg            = {0.046, 0.049, 0.061, 0.97},
    chrome        = {0.038, 0.041, 0.052, 1.00},
    panel         = {0.074, 0.079, 0.098, 1.00},
    panelAlt      = {0.088, 0.094, 0.116, 1.00},
    panelHover    = {0.112, 0.126, 0.154, 1.00},
    border        = {0.135, 0.145, 0.180, 0.82},
    borderStrong  = {0.185, 0.200, 0.245, 0.88},
    borderAccent  = {0.310, 0.720, 0.660, 0.34},
    separator     = {0.110, 0.120, 0.150, 0.78},
    -- Accent
    accent        = {0.310, 0.720, 0.660, 1.00},
    accentDim     = {0.310, 0.720, 0.660, 0.045},
    accentMid     = {0.310, 0.720, 0.660, 0.145},
    -- Text
    textPrimary   = {1.000, 1.000, 1.000, 1.00},
    textSecond    = {0.740, 0.755, 0.805, 1.00},
    textDimmed    = {0.500, 0.515, 0.575, 1.00},
    textAccent    = {0.430, 0.820, 0.760, 1.00},
    textWarn      = {0.860, 0.650, 0.180, 1.00},
    textDanger    = {0.900, 0.340, 0.340, 1.00},
    textSuccess   = {0.300, 0.780, 0.480, 1.00},
    -- Buttons
    btnPrimary    = {0.115, 0.420, 0.500, 1.00},
    btnPrimHov    = {0.155, 0.520, 0.610, 1.00},
    btnSecond     = {0.100, 0.108, 0.134, 1.00},
    btnSecHov     = {0.140, 0.154, 0.190, 1.00},
    btnDanger     = {0.500, 0.120, 0.120, 1.00},
    btnDanHov     = {0.650, 0.175, 0.175, 1.00},
    btnSuccess    = {0.110, 0.360, 0.220, 1.00},
    btnSucHov     = {0.160, 0.470, 0.300, 1.00},
    btnDisabled   = {0.068, 0.072, 0.088, 1.00},
    -- Nav sidebar
    navBg         = {0.055, 0.060, 0.076, 1.00},
    navActive     = {0.092, 0.108, 0.136, 1.00},
    navHover      = {0.078, 0.088, 0.112, 1.00},
    -- Status / indicators
    statusActive  = {0.220, 0.800, 0.440, 1.00},
    statusInact   = {0.800, 0.260, 0.200, 1.00},
    statusWarn    = {0.920, 0.720, 0.100, 1.00},
    -- Roster rows
    rowOdd        = {0.070, 0.074, 0.092, 1.00},
    rowEven       = {0.086, 0.091, 0.112, 1.00},
    rowHover      = {0.120, 0.145, 0.180, 1.00},
    rowSelected   = {0.095, 0.190, 0.230, 1.00},
}

local ADDON_FONT_PATH = "Interface\\AddOns\\GuildCore\\Assets\\fonts\\"
local ADDON_UI_PATH = "Interface\\AddOns\\GuildCore\\Assets\\ui\\"
local FALLBACK_FONT = "Fonts\\ARIALN.TTF"
local ROUNDED_CORNERS = {
    tl = ADDON_UI_PATH .. "rounded-tl.tga",
    tr = ADDON_UI_PATH .. "rounded-tr.tga",
    bl = ADDON_UI_PATH .. "rounded-bl.tga",
    br = ADDON_UI_PATH .. "rounded-br.tga",
}
local ROUNDED_BORDER_CORNERS = {
    tl = ADDON_UI_PATH .. "rounded-border-tl.tga",
    tr = ADDON_UI_PATH .. "rounded-border-tr.tga",
    bl = ADDON_UI_PATH .. "rounded-border-bl.tga",
    br = ADDON_UI_PATH .. "rounded-border-br.tga",
}

local function addonFont(fileName)
    return ADDON_FONT_PATH .. fileName
end

-- Font theme registry. Add or remove complete font presets here; every theme
-- should provide all roles so the UI can switch typography without layout code
-- needing to know which font family is active.
T.fontThemes = {
    wowDefault = {
        title     = {"Fonts\\FRIZQT__.TTF", 26, ""},
        header    = {"Fonts\\FRIZQT__.TTF", 17, ""},
        subheader = {"Fonts\\FRIZQT__.TTF", 15, ""},
        nav       = {"Fonts\\ARIALN.TTF",   14, ""},
        body      = {"Fonts\\ARIALN.TTF",   13, ""},
        label     = {"Fonts\\ARIALN.TTF",   13, ""},
        input     = {"Fonts\\ARIALN.TTF",   13, ""},
        data      = {"Fonts\\ARIALN.TTF",   12, ""},
        dataLarge = {"Fonts\\ARIALN.TTF",   17, ""},
        small     = {"Fonts\\ARIALN.TTF",   12, ""},
        tiny      = {"Fonts\\ARIALN.TTF",   11, ""},
        status    = {"Fonts\\ARIALN.TTF",   12, "OUTLINE"},
    },
    magenta = {
        title     = {addonFont("MagentaBold.ttf"),    26, ""},
        header    = {addonFont("MagentaBold.ttf"),    17, ""},
        subheader = {addonFont("MagentaReguler.ttf"), 15, ""},
        nav       = {addonFont("MagentaReguler.ttf"), 14, ""},
        body      = {addonFont("MagentaReguler.ttf"), 13, ""},
        label     = {addonFont("MagentaReguler.ttf"), 13, ""},
        input     = {addonFont("MagentaReguler.ttf"), 13, ""},
        data      = {"Fonts\\ARIALN.TTF",              12, ""},
        dataLarge = {"Fonts\\ARIALN.TTF",              17, ""},
        small     = {addonFont("MagentaReguler.ttf"), 12, ""},
        tiny      = {addonFont("MagentaReguler.ttf"), 11, ""},
        status    = {addonFont("MagentaBold.ttf"),    12, "OUTLINE"},
    },
    frescito = {
        title     = {addonFont("FrescitoBold.ttf"),    26, ""},
        header    = {addonFont("FrescitoBold.ttf"),    17, ""},
        subheader = {addonFont("FrescitoRegular.ttf"), 15, ""},
        nav       = {addonFont("FrescitoRegular.ttf"), 14, ""},
        body      = {addonFont("FrescitoRegular.ttf"), 13, ""},
        label     = {addonFont("FrescitoRegular.ttf"), 13, ""},
        input     = {"Fonts\\ARIALN.TTF",              13, ""},
        data      = {"Fonts\\ARIALN.TTF",              12, ""},
        dataLarge = {"Fonts\\ARIALN.TTF",              17, ""},
        small     = {"Fonts\\ARIALN.TTF",              12, ""},  -- ARIALN: digits in row data render safely
        tiny      = {addonFont("FrescitoRegular.ttf"), 11, ""},
        status    = {addonFont("FrescitoBold.ttf"),    12, "OUTLINE"},
    },
    highLegibility = {
        title     = {addonFont("FrescitoBold.ttf"),    26, ""},
        header    = {addonFont("FrescitoBold.ttf"),    17, ""},
        subheader = {addonFont("FrescitoBold.ttf"),    15, ""},
        nav       = {addonFont("FrescitoRegular.ttf"), 14, ""},
        body      = {addonFont("FrescitoRegular.ttf"), 13, ""},
        label     = {addonFont("FrescitoRegular.ttf"), 13, ""},
        input     = {addonFont("FrescitoRegular.ttf"), 13, ""},
        data      = {addonFont("FrescitoRegular.ttf"), 12, ""},
        dataLarge = {addonFont("FrescitoBold.ttf"),    17, ""},
        small     = {addonFont("FrescitoRegular.ttf"), 12, ""},
        tiny      = {addonFont("FrescitoRegular.ttf"), 11, ""},
        status    = {addonFont("FrescitoBold.ttf"),    12, "OUTLINE"},
    },
}

local FONT_THEME_ORDER = {"wowDefault", "highLegibility", "magenta", "frescito"}
local FONT_THEME_LABELS = {
    wowDefault = "WoW Default",
    highLegibility = "High Legibility",
    magenta = "Magenta",
    frescito = "Frescito",
}
T.f = T.fontThemes.wowDefault

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
    voidsteel = {
        label = "Voidsteel",
        colors = {
            bg = {0.035, 0.035, 0.050, 0.97},
            chrome = {0.025, 0.025, 0.040, 1.00},
            panel = {0.055, 0.055, 0.080, 1.00},
            panelAlt = {0.045, 0.045, 0.070, 1.00},
            borderAccent = {0.620, 0.480, 1.000, 0.65},
            accent = {0.620, 0.480, 1.000, 1.00},
            accentDim = {0.620, 0.480, 1.000, 0.08},
            accentMid = {0.620, 0.480, 1.000, 0.25},
            textAccent = {0.720, 0.600, 1.000, 1.00},
            btnPrimary = {0.200, 0.160, 0.350, 1.00},
            btnPrimHov = {0.300, 0.240, 0.500, 1.00},
            navActive = {0.090, 0.085, 0.140, 1.00},
            navHover = {0.070, 0.070, 0.120, 1.00},
            rowSelected = {0.180, 0.140, 0.300, 1.00},
        },
    },
    verdant = {
        label = "Verdant",
        colors = {
            bg = {0.050, 0.070, 0.055, 0.97},
            chrome = {0.040, 0.060, 0.045, 1.00},
            panel = {0.070, 0.095, 0.075, 1.00},
            panelAlt = {0.060, 0.085, 0.068, 1.00},
            borderAccent = {0.400, 0.850, 0.550, 0.65},
            accent = {0.400, 0.850, 0.550, 1.00},
            accentDim = {0.400, 0.850, 0.550, 0.08},
            accentMid = {0.400, 0.850, 0.550, 0.25},
            textAccent = {0.500, 0.950, 0.650, 1.00},
            btnPrimary = {0.150, 0.350, 0.220, 1.00},
            btnPrimHov = {0.220, 0.480, 0.300, 1.00},
            navActive = {0.090, 0.140, 0.100, 1.00},
            navHover = {0.075, 0.120, 0.090, 1.00},
            rowSelected = {0.120, 0.300, 0.180, 1.00},
        },
    },
    stormforge = {
        label = "Stormforge",
        colors = {
            bg = {0.040, 0.050, 0.065, 0.97},
            chrome = {0.030, 0.040, 0.055, 1.00},
            panel = {0.060, 0.075, 0.095, 1.00},
            panelAlt = {0.050, 0.065, 0.085, 1.00},
            borderAccent = {0.300, 0.650, 1.000, 0.70},
            accent = {0.300, 0.650, 1.000, 1.00},
            accentDim = {0.300, 0.650, 1.000, 0.08},
            accentMid = {0.300, 0.650, 1.000, 0.25},
            textAccent = {0.450, 0.800, 1.000, 1.00},
            btnPrimary = {0.120, 0.260, 0.420, 1.00},
            btnPrimHov = {0.180, 0.380, 0.600, 1.00},
            navActive = {0.085, 0.115, 0.155, 1.00},
            navHover = {0.070, 0.095, 0.135, 1.00},
            rowSelected = {0.090, 0.200, 0.320, 1.00},
        },
    },
    bloodwake = {
        label = "Bloodwake",
        colors = {
            bg = {0.070, 0.035, 0.040, 0.97},
            chrome = {0.055, 0.025, 0.030, 1.00},
            panel = {0.095, 0.050, 0.055, 1.00},
            panelAlt = {0.080, 0.040, 0.045, 1.00},
            borderAccent = {0.850, 0.200, 0.250, 0.70},
            accent = {0.850, 0.200, 0.250, 1.00},
            accentDim = {0.850, 0.200, 0.250, 0.08},
            accentMid = {0.850, 0.200, 0.250, 0.25},
            textAccent = {0.950, 0.350, 0.400, 1.00},
            btnPrimary = {0.350, 0.100, 0.120, 1.00},
            btnPrimHov = {0.520, 0.160, 0.180, 1.00},
            navActive = {0.160, 0.070, 0.080, 1.00},
            navHover = {0.135, 0.060, 0.070, 1.00},
            rowSelected = {0.320, 0.120, 0.140, 1.00},
        },
    },
    gilded = {
        label = "Gilded",
        colors = {
            bg = {0.060, 0.055, 0.040, 0.97},
            chrome = {0.050, 0.045, 0.030, 1.00},
            panel = {0.085, 0.075, 0.050, 1.00},
            panelAlt = {0.072, 0.065, 0.045, 1.00},
            borderAccent = {1.000, 0.820, 0.320, 0.70},
            accent = {1.000, 0.820, 0.320, 1.00},
            accentDim = {1.000, 0.820, 0.320, 0.08},
            accentMid = {1.000, 0.820, 0.320, 0.25},
            textAccent = {1.000, 0.900, 0.500, 1.00},
            btnPrimary = {0.420, 0.320, 0.120, 1.00},
            btnPrimHov = {0.600, 0.450, 0.180, 1.00},
            navActive = {0.140, 0.120, 0.080, 1.00},
            navHover = {0.120, 0.100, 0.070, 1.00},
            rowSelected = {0.320, 0.250, 0.100, 1.00},
        },
    },
    cupertino = {
        label = "Cupertino",
        colors = {
            bg = {0.940, 0.940, 0.950, 0.97},
            chrome = {0.900, 0.900, 0.920, 1.00},
            panel = {0.970, 0.970, 0.980, 1.00},
            panelAlt = {0.955, 0.955, 0.970, 1.00},
            panelHover = {0.900, 0.920, 0.965, 1.00},
            border = {0.730, 0.730, 0.780, 1.00},
            borderStrong = {0.620, 0.640, 0.700, 1.00},
            borderAccent = {0.350, 0.550, 0.950, 0.45},
            separator = {0.760, 0.770, 0.820, 1.00},
            accent = {0.250, 0.500, 0.950, 1.00},
            accentDim = {0.250, 0.500, 0.950, 0.08},
            accentMid = {0.250, 0.500, 0.950, 0.22},
            textPrimary = {0.080, 0.085, 0.105, 1.00},
            textSecond = {0.220, 0.230, 0.270, 1.00},
            textDimmed = {0.430, 0.440, 0.500, 1.00},
            textAccent = {0.200, 0.450, 0.900, 1.00},
            btnPrimary = {0.250, 0.500, 0.950, 1.00},
            btnPrimHov = {0.350, 0.600, 1.000, 1.00},
            btnSecond = {0.860, 0.865, 0.900, 1.00},
            btnSecHov = {0.800, 0.820, 0.880, 1.00},
            btnDisabled = {0.820, 0.825, 0.850, 1.00},
            navBg = {0.900, 0.900, 0.920, 1.00},
            navActive = {0.880, 0.880, 0.910, 1.00},
            navHover = {0.900, 0.900, 0.930, 1.00},
            rowOdd = {0.965, 0.965, 0.975, 1.00},
            rowEven = {0.945, 0.948, 0.960, 1.00},
            rowHover = {0.880, 0.905, 0.960, 1.00},
            rowSelected = {0.820, 0.860, 0.950, 1.00},
        },
    },
    cupertinoDark = {
        label = "Cupertino Dark",
        colors = {
            bg = {0.090, 0.090, 0.100, 0.97},
            chrome = {0.070, 0.070, 0.080, 1.00},
            panel = {0.120, 0.120, 0.135, 1.00},
            panelAlt = {0.105, 0.105, 0.120, 1.00},
            borderAccent = {0.350, 0.550, 0.950, 0.60},
            accent = {0.350, 0.600, 1.000, 1.00},
            accentDim = {0.350, 0.600, 1.000, 0.08},
            accentMid = {0.350, 0.600, 1.000, 0.25},
            textAccent = {0.500, 0.700, 1.000, 1.00},
            btnPrimary = {0.180, 0.320, 0.600, 1.00},
            btnPrimHov = {0.250, 0.420, 0.780, 1.00},
            navActive = {0.150, 0.150, 0.180, 1.00},
            navHover = {0.130, 0.130, 0.160, 1.00},
            rowSelected = {0.200, 0.300, 0.450, 1.00},
        },
    },
}

local PRESET_ORDER = {
    "guildcore",
    "ember",
    "tideglass",
    "voidsteel",
    "verdant",
    "stormforge",
    "bloodwake",
    "gilded",
    "cupertino",
    "cupertinoDark",
}
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

local function colorTexture(texture, c)
    if texture and c then
        texture:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    end
end

local function colorVertex(texture, c)
    if texture and c then
        texture:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
    end
end

local function addRoundedCorner(parent, layer, sublevel, point, texturePath, radius, c)
    local corner = parent:CreateTexture(nil, layer, nil, sublevel)
    corner:SetSize(radius, radius)
    corner:SetPoint(point)
    corner:SetTexture(texturePath)
    corner:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
    return corner
end

local function applyFontStringColor(fontString, colorKey)
    local c = colorKey and T.c[colorKey]
    if fontString and c then
        fontString:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    end
end

local function resolveFontThemeName(name)
    if T.fontThemes[name] then
        return name
    end
    local wanted = tostring(name or ""):lower()
    for _, key in ipairs(FONT_THEME_ORDER) do
        if key:lower() == wanted then
            return key
        end
    end
    return "wowDefault"
end

function T.GetFontThemeName()
    return T.activeFontTheme or resolveFontThemeName(GC.DB and GC.DB.GetSettings and GC.DB:GetSettings() and GC.DB:GetSettings().fontTheme)
end

function T.GetFontThemeKeys()
    return FONT_THEME_ORDER
end

function T.GetFontThemeLabel(name)
    return FONT_THEME_LABELS[name] or tostring(name or "Font")
end

function T.SetFontTheme(name)
    local themeName = resolveFontThemeName(name)
    T.activeFontTheme = themeName
    T.f = T.fontThemes[themeName] or T.fontThemes.wowDefault
    local settings = GC.DB and GC.DB.GetSettings and GC.DB:GetSettings()
    if settings then
        settings.fontTheme = themeName
    end
    T:RefreshRegistered()
    return themeName
end

function T.GetTextScale()
    local settings = GC.DB and GC.DB.GetSettings and GC.DB:GetSettings()
    return math.max(1, math.min(1.3, tonumber(settings and settings.textScale) or 1))
end

function T.SetTextScale(value)
    local scale = math.max(1, math.min(1.3, tonumber(value) or 1))
    local settings = GC.DB and GC.DB.GetSettings and GC.DB:GetSettings()
    if settings then
        settings.textScale = scale
    end
    T:RefreshRegistered()
    return scale
end

function T.GetFont(role)
    local fontTheme = T.fontThemes[T.GetFontThemeName()] or T.fontThemes.wowDefault
    local fd = fontTheme[role] or fontTheme.body or T.fontThemes.wowDefault.body
    local path = fd and fd[1] or FALLBACK_FONT
    if not path or path == "" then
        path = FALLBACK_FONT
    end
    local baseSize = fd and fd[2] or 12
    local scaledSize = math.floor((baseSize * T.GetTextScale()) + 0.5)
    return {path, scaledSize, fd and fd[3] or ""}
end

function T.ApplyFont(fontString, role)
    if not fontString then return end
    local fd = T.GetFont(role or "body")
    fontString:SetFont(fd[1], fd[2], fd[3])
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

function T:GetRefreshCallbackCount()
    return #refreshCallbacks
end

function T:RefreshRegistered()
    for _, item in ipairs(themedTextures) do
        applyTextureColor(item.texture, item.colorKey, item.alpha)
    end
    for _, item in ipairs(themedFontStrings) do
        self.ApplyFont(item.fontString, item.role)
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
    T.SetFontTheme(settings and settings.fontTheme or "wowDefault")
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

function T.RoundedSurface(frame, c, border, radius, layer, sublevel)
    radius = radius or T.cornerRadius or 8
    layer = layer or "BACKGROUND"
    sublevel = sublevel or -8
    if GC.Perf then GC.Perf:CountUI("textures", border and 17 or 9) end

    local surface = {fillRects = {}, fillCorners = {}, borderRects = {}, borderCorners = {}}

    local function addFill()
        local tex = frame:CreateTexture(nil, layer, nil, sublevel)
        surface.fillRects[#surface.fillRects + 1] = tex
        return tex
    end

    local center = addFill()
    center:SetPoint("TOPLEFT", frame, "TOPLEFT", radius, 0)
    center:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -radius, 0)

    local left = addFill()
    left:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -radius)
    left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, radius)
    left:SetWidth(radius)

    local right = addFill()
    right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -radius)
    right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, radius)
    right:SetWidth(radius)

    surface.fillCorners[#surface.fillCorners + 1] = addRoundedCorner(frame, layer, sublevel, "TOPLEFT", ROUNDED_CORNERS.tl, radius, c)
    surface.fillCorners[#surface.fillCorners + 1] = addRoundedCorner(frame, layer, sublevel, "TOPRIGHT", ROUNDED_CORNERS.tr, radius, c)
    surface.fillCorners[#surface.fillCorners + 1] = addRoundedCorner(frame, layer, sublevel, "BOTTOMLEFT", ROUNDED_CORNERS.bl, radius, c)
    surface.fillCorners[#surface.fillCorners + 1] = addRoundedCorner(frame, layer, sublevel, "BOTTOMRIGHT", ROUNDED_CORNERS.br, radius, c)

    local top = addFill()
    top:SetPoint("TOPLEFT", frame, "TOPLEFT", radius, 0)
    top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -radius, 0)
    top:SetHeight(radius)

    local bottom = addFill()
    bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", radius, 0)
    bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -radius, 0)
    bottom:SetHeight(radius)

    function surface:SetColorTexture(r, g, b, a)
        for _, tex in ipairs(self.fillRects) do
            tex:SetColorTexture(r, g, b, a or 1)
        end
        for _, tex in ipairs(self.fillCorners) do
            tex:SetVertexColor(r, g, b, a or 1)
        end
    end

    function surface:SetAlpha(alpha)
        for _, tex in ipairs(self.fillRects) do tex:SetAlpha(alpha) end
        for _, tex in ipairs(self.fillCorners) do tex:SetAlpha(alpha) end
        for _, tex in ipairs(self.borderRects) do tex:SetAlpha(alpha) end
        for _, tex in ipairs(self.borderCorners) do tex:SetAlpha(alpha) end
    end

    surface:SetColorTexture(c[1], c[2], c[3], c[4] or 1)

    if border then
        local function addBorderTexture()
            local tex = frame:CreateTexture(nil, layer, nil, sublevel + 1)
            surface.borderRects[#surface.borderRects + 1] = tex
            return tex
        end

        local topEdge = addBorderTexture()
        topEdge:SetPoint("TOPLEFT", frame, "TOPLEFT", radius, 0)
        topEdge:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -radius, 0)
        topEdge:SetHeight(1)

        local bottomEdge = addBorderTexture()
        bottomEdge:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", radius, 0)
        bottomEdge:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -radius, 0)
        bottomEdge:SetHeight(1)

        local leftEdge = addBorderTexture()
        leftEdge:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -radius)
        leftEdge:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, radius)
        leftEdge:SetWidth(1)

        local rightEdge = addBorderTexture()
        rightEdge:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -radius)
        rightEdge:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, radius)
        rightEdge:SetWidth(1)

        surface.borderCorners[#surface.borderCorners + 1] = addRoundedCorner(frame, layer, sublevel + 1, "TOPLEFT", ROUNDED_BORDER_CORNERS.tl, radius, border)
        surface.borderCorners[#surface.borderCorners + 1] = addRoundedCorner(frame, layer, sublevel + 1, "TOPRIGHT", ROUNDED_BORDER_CORNERS.tr, radius, border)
        surface.borderCorners[#surface.borderCorners + 1] = addRoundedCorner(frame, layer, sublevel + 1, "BOTTOMLEFT", ROUNDED_BORDER_CORNERS.bl, radius, border)
        surface.borderCorners[#surface.borderCorners + 1] = addRoundedCorner(frame, layer, sublevel + 1, "BOTTOMRIGHT", ROUNDED_BORDER_CORNERS.br, radius, border)

        function surface:SetBorderColor(r, g, b, a)
            for _, tex in ipairs(self.borderRects) do
                tex:SetColorTexture(r, g, b, a or 1)
            end
            for _, tex in ipairs(self.borderCorners) do
                tex:SetVertexColor(r, g, b, a or 1)
            end
        end

        surface:SetBorderColor(border[1], border[2], border[3], border[4] or 1)
    end

    return surface
end

-- Apply a themed background to a frame. Bordered surfaces use rounded corners
-- by default; pass {square = true} as the fourth argument to keep hard edges.
function T.Bg(frame, c, border, opts)
    local bgKey = colorKeyFor(c)
    local borderKey = colorKeyFor(border)
    local rounded = opts and opts.rounded or (border and not (opts and opts.square))

    if rounded then
        local bg = T.RoundedSurface(frame, c, border, opts and opts.radius or T.cornerRadius)
        frame._bg = bg
        if bgKey or borderKey then
            T:RegisterRefresh(function()
                local fill = bgKey and T.c[bgKey] or c
                if fill and bg.SetColorTexture then bg:SetColorTexture(fill[1], fill[2], fill[3], fill[4] or 1) end
                local edge = borderKey and T.c[borderKey] or border
                if edge and bg.SetBorderColor then bg:SetBorderColor(edge[1], edge[2], edge[3], edge[4] or 1) end
            end)
        end
        return bg
    end

    if GC.Perf then GC.Perf:CountUI("textures", border and 5 or 1) end
    local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetAllPoints()
    colorTexture(bg, c)
    trackTexture(bg, bgKey)
    frame._bg = bg
    if border then
        local b = border
        local function edge()
            local e = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
            colorTexture(e, b)
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
    if GC.Perf then GC.Perf:CountUI("textures", 1) end
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
    if GC.Perf then GC.Perf:CountUI("fontStrings", 1) end
    local c  = colorKey and T.c[colorKey] or T.c.textPrimary
    local fs = parent:CreateFontString(nil, "OVERLAY")
    T.ApplyFont(fs, fontKey)
    fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    themedFontStrings[#themedFontStrings + 1] = {fontString = fs, role = fontKey or "body", colorKey = colorKey or "textPrimary"}
    if text then fs:SetText(text) end
    return fs
end

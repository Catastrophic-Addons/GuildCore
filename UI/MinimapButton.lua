-- UI/MinimapButton.lua
-- Small draggable minimap access point for the Guild Core main UI.
local addonName, ns = ...
local GC = ns.GuildCore

GC.UI.MinimapButton = {}
local MB = GC.UI.MinimapButton

local ICON = "Interface\\AddOns\\GuildCore\\Assets\\icons\\GC_Gold.tga"
local DEFAULT_ANGLE = 225

local function atan2(y, x)
    if math.atan2 then
        return math.atan2(y, x)
    end
    if x and x ~= 0 then
        local angle = math.atan(y / x)
        if x < 0 then
            angle = angle + math.pi
        end
        return angle
    end
    return y and y < 0 and -math.pi / 2 or math.pi / 2
end

local function uiState()
    if GC.DB and GC.DB.GetUIState then
        return GC.DB:GetUIState()
    end
    return nil
end

local function getAngle()
    local ui = uiState()
    return ui and ui.minimapButtonAngle or DEFAULT_ANGLE
end

local function saveAngle(angle)
    local ui = uiState()
    if ui then
        ui.minimapButtonAngle = angle
    end
end

local function positionButton(angle)
    if not MB.button or not Minimap then return end
    local radius = 80
    local radians = math.rad(angle or getAngle())
    local x = math.cos(radians) * radius
    local y = math.sin(radians) * radius
    MB.button:ClearAllPoints()
    MB.button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function updateDragPosition()
    if not MB.button or not Minimap then return end
    local scale = UIParent:GetEffectiveScale() or 1
    local cursorX, cursorY = GetCursorPosition()
    local centerX, centerY = Minimap:GetCenter()
    if not cursorX or not cursorY or not centerX or not centerY then return end

    cursorX = cursorX / scale
    cursorY = cursorY / scale
    local angle = math.deg(atan2(cursorY - centerY, cursorX - centerX))
    saveAngle(angle)
    positionButton(angle)
end

local function safeSetTexture(texture, path)
    if not texture then return end
    local ok = pcall(texture.SetTexture, texture, path)
    if not ok then
        texture:SetColorTexture(0.94, 0.75, 0.10, 1)
    end
end

function MB:Create()
    if self.button or not Minimap then return end

    local button = CreateFrame("Button", "GuildCoreMinimapButton", Minimap)
    button:SetSize(32, 32)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel((Minimap:GetFrameLevel() or 0) + 8)
    button:RegisterForClicks("LeftButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetClampedToScreen(true)
    button:EnableMouse(true)

    local border = button:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints()
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetTexCoord(0, 0.6, 0, 0.6)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 1)
    safeSetTexture(icon, ICON)
    self.icon = icon

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Guild Core", 1, 1, 1, 1, true)
        GameTooltip:AddLine("Left Click: Open/Close Guild Core", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "LeftButton" and GC.UI and GC.UI.Toggle then
            GC.UI:Toggle()
        end
    end)
    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", updateDragPosition)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        updateDragPosition()
    end)

    self.button = button
    positionButton(getAngle())
end

function MB:Initialize()
    self:Create()
end

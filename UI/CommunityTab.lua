-- UI/CommunityTab.lua
-- Guild Core access button for Blizzard's Guild/Community interface.

local addonName, ns = ...
local GC = ns.GuildCore

GC.UI.CommunityTab = {}
local CT = GC.UI.CommunityTab

local ICON = "Interface\\AddOns\\GuildCore\\Assets\\icons\\GC_Gold.tga"

local BUTTON_SIZE = 48
local BUTTON_OFFSET_X = -1
local BUTTON_OFFSET_Y = 25

local function safeSetTexture(texture, path)
    if not texture then return end

    local ok = pcall(texture.SetTexture, texture, path)
    if not ok then
        texture:SetColorTexture(0.94, 0.75, 0.10, 1)
    end
end

local function getCommunityFrame()
    return _G.CommunitiesFrame or _G.GuildFrame
end

local function ensureHooks(parent)
    if not parent or CT.hookedParents[parent] then return end

    CT.hookedParents[parent] = true

    parent:HookScript("OnShow", function()
        C_Timer.After(0, function()
            CT:Reposition()
        end)
    end)

    parent:HookScript("OnHide", function()
        if CT.button then
            CT.button:Hide()
        end
    end)
end

function CT:Reposition()
    local parent = getCommunityFrame()
    if not parent or not self.button then return end

    self.button:SetParent(parent)
    self.button:ClearAllPoints()

    self.button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    self.button:SetPoint("BOTTOMLEFT", parent, "BOTTOMRIGHT", BUTTON_OFFSET_X, BUTTON_OFFSET_Y)
    self.button:SetFrameStrata(parent:GetFrameStrata() or "MEDIUM")
    self.button:SetFrameLevel((parent:GetFrameLevel() or 1) + 10)

    self.button:SetShown(parent:IsShown())
    ensureHooks(parent)
    if GC.UI.FrameLayering then
        GC.UI.FrameLayering:AttachBlizzardFocusHandlers()
    end
end

function CT:Create()
    local parent = getCommunityFrame()
    if not parent then return false end

    if not self.button then
        local button = CreateFrame("Button", "GuildCoreCommunityTabButton", parent)
        button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
        button:RegisterForClicks("LeftButtonUp")
        button:EnableMouse(true)

        local bg = button:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0)
        button._bg = bg

        local ring = button:CreateTexture(nil, "BORDER")
        ring:SetAllPoints()
        ring:SetTexture("Interface\\Buttons\\UI-Quickslot2")
        ring:SetVertexColor(0.7, 0.55, 0.22, 0.18)
        button._ring = ring

        button:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")

        button:SetHighlightTexture("Interface\\Buttons\\WHITE8X8", "ADD")
        local highlight = button:GetHighlightTexture()
        if highlight then
            highlight:ClearAllPoints()
            highlight:SetAllPoints()
            highlight:SetVertexColor(0.72, 0.58, 0.28, 0.07)
        end

        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", 3, -3)
        icon:SetPoint("BOTTOMRIGHT", -3, 3)
        safeSetTexture(icon, ICON)
        icon:SetVertexColor(0.92, 0.92, 0.92, 1)
        button.icon = icon

        button:SetScript("OnEnter", function(self)
            if self._bg then
                self._bg:SetColorTexture(0.12, 0.08, 0.02, 0.18)
            end

            if self.icon then
                self.icon:SetVertexColor(1, 1, 1, 1)
            end

            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Guild Core", 1, 1, 1, 1, true)
            GameTooltip:AddLine("Left Click: Open/Close Guild Core", 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)

        button:SetScript("OnLeave", function(self)
            if self._bg then
                self._bg:SetColorTexture(0, 0, 0, 0)
            end

            if self.icon then
                self.icon:SetVertexColor(0.92, 0.92, 0.92, 1)
            end

            GameTooltip:Hide()
        end)

        button:SetScript("OnClick", function()
            if GC.UI and GC.UI.Toggle then
                GC.UI:Toggle()
            end
        end)

        self.button = button
    end

    self:Reposition()
    return true
end

function CT:TryCreate()
    if self:Create() then return end
    if self.retrying then return end

    self.retrying = true

    C_Timer.After(1, function()
        CT.retrying = false
        CT:Create()
    end)
end

function CT:Initialize()
    self.hookedParents = self.hookedParents or {}

    if not self.hookedRefresh then
        self.hookedRefresh = true

        if _G.CommunitiesFrame_Update then
            hooksecurefunc("CommunitiesFrame_Update", function()
                CT:Reposition()
            end)
        end

        if _G.GuildFrame_TabClicked then
            hooksecurefunc("GuildFrame_TabClicked", function()
                C_Timer.After(0, function()
                    CT:Reposition()
                end)
            end)
        end
    end

    self:TryCreate()
end

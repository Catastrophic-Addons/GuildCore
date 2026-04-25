-- UI/CommunityTab.lua
-- Guild Core access button for Blizzard's Guild/Community interface.
local addonName, ns = ...
local GC = ns.GuildCore

GC.UI.CommunityTab = {}
local CT = GC.UI.CommunityTab

local ICON = "Interface\\AddOns\\GuildCore\\Assets\\icons\\GC_Gold.tga"

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

local function getExistingRightTab(parent)
    local bestTab, bestBottom
    local namedTabs = {
        "ChatTab",
        "RosterTab",
        "GuildBenefitsTab",
        "GuildInfoTab",
        "GuildNewsTab",
        "PerksTab",
        "InfoTab",
    }

    for _, tabName in ipairs(namedTabs) do
        local tab = parent and parent[tabName]
        if tab and tab.GetBottom then
            local bottom = tab:GetBottom()
            if not bestTab or (bottom and bestBottom and bottom < bestBottom) or (bottom and not bestBottom) then
                bestTab = tab
                bestBottom = bottom
            end
        end
    end

    local globalPrefixes = {
        "CommunitiesFrameTab",
        "GuildFrameTab",
        "CommunitiesFrameGuildDetailsFrameTab",
    }

    for _, prefix in ipairs(globalPrefixes) do
        for i = 1, 10 do
            local tab = _G[prefix .. i]
            if tab and tab.GetParent and (tab:GetParent() == parent or tab:IsVisible()) then
                local bottom = tab.GetBottom and tab:GetBottom() or nil
                if not bestTab or (bottom and bestBottom and bottom < bestBottom) or (bottom and not bestBottom) then
                    bestTab = tab
                    bestBottom = bottom
                end
            end
        end
    end

    return bestTab
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

    local tab = getExistingRightTab(parent)
    if tab then
        self.button:SetPoint("TOP", tab, "BOTTOM", 0, -6)
        self.button:SetFrameStrata(tab:GetFrameStrata() or parent:GetFrameStrata() or "MEDIUM")
        self.button:SetFrameLevel((tab:GetFrameLevel() or parent:GetFrameLevel() or 1) + 1)
    else
        self.button:SetPoint("TOPLEFT", parent, "TOPRIGHT", 4, -96)
        self.button:SetFrameStrata(parent:GetFrameStrata() or "MEDIUM")
        self.button:SetFrameLevel((parent:GetFrameLevel() or 1) + 1)
    end

    self.button:SetShown(parent:IsShown())
    ensureHooks(parent)
end

function CT:Create()
    local parent = getCommunityFrame()
    if not parent then return false end

    if not self.button then
        local button = CreateFrame("Button", "GuildCoreCommunityTabButton", parent)
        button:SetSize(32, 32)
        button:RegisterForClicks("LeftButtonUp")
        button:EnableMouse(true)

        local bg = button:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.04, 0.04, 0.055, 0.72)

        local border = button:CreateTexture(nil, "BORDER")
        border:SetPoint("TOPLEFT", -1, 1)
        border:SetPoint("BOTTOMRIGHT", 1, -1)
        border:SetColorTexture(0.94, 0.75, 0.10, 0.38)

        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetSize(24, 24)
        icon:SetPoint("CENTER")
        safeSetTexture(icon, ICON)

        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Guild Core", 1, 1, 1, 1, true)
            GameTooltip:AddLine("Left Click: Open/Close Guild Core", 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function()
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

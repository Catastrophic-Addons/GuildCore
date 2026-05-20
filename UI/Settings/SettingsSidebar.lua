-- /GuildCore/UI/Settings/SettingsSidebar.lua
local addonName, ns = ...
local GC = ns.GuildCore

GC.UI.SettingsSidebar = {}
local Sidebar = GC.UI.SettingsSidebar

local function T() return GC.UI.Theme end

function Sidebar:Build(parent)
    self.parent = parent
    self.buttons = {}
    local y = -6
    for _, id in ipairs(GC.Settings.order or {}) do
        local def = GC.Settings.categories[id]
        if def then
            local btn = CreateFrame("Button", nil, parent)
            btn:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, y)
            btn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -6, y)
            btn:SetHeight(30)
            btn._id = id
            btn._bg = btn:CreateTexture(nil, "BACKGROUND")
            btn._bg:SetAllPoints()
            local label = T().Fs(btn, "body", def.label, "textSecond")
            label:SetPoint("LEFT", btn, "LEFT", 10, 0)
            btn._label = label
            btn:SetScript("OnClick", function() GC.Settings:SelectCategory(id) end)
            btn:SetScript("OnEnter", function(selfBtn)
                if GC.Settings.activeCategory ~= id then
                    local c = T().c.navHover
                    selfBtn._bg:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
                end
            end)
            btn:SetScript("OnLeave", function() Sidebar:Refresh() end)
            self.buttons[id] = btn
            y = y - 34
        end
    end
    self:Refresh()
end

function Sidebar:Refresh()
    if not self.buttons then return end
    for id, btn in pairs(self.buttons) do
        local active = GC.Settings.activeCategory == id
        local bg = T().c[active and "navActive" or "panelAlt"]
        local txt = T().c[active and "textAccent" or "textSecond"]
        btn._bg:SetColorTexture(bg[1], bg[2], bg[3], bg[4] or 1)
        btn._label:SetTextColor(txt[1], txt[2], txt[3], txt[4] or 1)
    end
end

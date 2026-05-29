-- /GuildCore/UI/Settings/SettingsFrame.lua
-- Modular settings shell with fixed category sidebar and lazy content panels.
local addonName, ns = ...
local GC = ns.GuildCore

GC.Settings = GC.Settings or { categories = {}, order = {}, index = {} }
local Settings = GC.Settings

local function T() return GC.UI.Theme end
local function DS() return GC.Services.DataStore end

local function status(message, colorKey)
    if GC.UI and GC.UI.MainFrame then
        GC.UI.MainFrame:SetStatus(message, colorKey or "textSuccess")
    end
end

local function lower(value)
    return tostring(value or ""):lower()
end

local function settingText(def)
    return lower((def.label or "") .. " " .. (def.description or "") .. " " .. (def.keywords or ""))
end

function Settings:RegisterCategory(def)
    if not def or not def.id then return end
    if not self.index[def.id] then
        self.order[#self.order + 1] = def.id
    end
    self.categories[def.id] = def
    self.index[def.id] = true
end

function Settings:GetSetting(key)
    local settings = DS():GetSettings() or {}
    local cursor = settings
    for part in tostring(key or ""):gmatch("[^%.]+") do
        if type(cursor) ~= "table" then return nil end
        cursor = cursor[part]
    end
    return cursor
end

function Settings:SetSetting(key, value, label)
    local root = DS():GetSettings() or {}
    local cursor = root
    local parts = {}
    for part in tostring(key or ""):gmatch("[^%.]+") do
        parts[#parts + 1] = part
    end
    for i = 1, math.max(1, #parts - 1) do
        local part = parts[i]
        cursor[part] = type(cursor[part]) == "table" and cursor[part] or {}
        cursor = cursor[part]
    end
    cursor[parts[#parts] or key] = value
    status((label or key) .. " updated.", "textSuccess")
end

function Settings:CreateSection(parent, title, y)
    local Th = T()
    local card = CreateFrame("Frame", nil, parent)
    if GC.Perf then
        GC.Perf:CountUI("frames", 1)
        GC.Perf:CountUI("settingsControls", 1)
    end
    card:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    card:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, y)
    card:SetHeight(36)
    Th.Bg(card, Th.c.panel, Th.c.border)
    local stripe = card:CreateTexture(nil, "ARTWORK")
    stripe:SetPoint("TOPLEFT"); stripe:SetPoint("BOTTOMLEFT"); stripe:SetWidth(2)
    local ac = Th.c.accent
    stripe:SetColorTexture(ac[1], ac[2], ac[3], 0.85)
    local label = Th.Fs(card, "subheader", title, "textAccent")
    label:SetPoint("LEFT", card, "LEFT", 12, 0)
    return card, y - 46
end

function Settings:CreateCard(parent, y, title, description, height)
    local Th = T()
    local card = CreateFrame("Frame", nil, parent)
    if GC.Perf then
        GC.Perf:CountUI("frames", 1)
        GC.Perf:CountUI("settingsControls", 1)
    end
    card:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    card:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, y)
    card:SetHeight(height or 72)
    Th.Bg(card, Th.c.panelAlt, Th.c.border)

    local titleFs = Th.Fs(card, "body", title, "textPrimary")
    titleFs:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -10)
    titleFs:SetPoint("TOPRIGHT", card, "TOPRIGHT", -190, -10)
    titleFs:SetWordWrap(false)

    if description and description ~= "" then
        local descFs = Th.Fs(card, "small", description, "textDimmed")
        descFs:SetPoint("TOPLEFT", titleFs, "BOTTOMLEFT", 0, -4)
        descFs:SetPoint("RIGHT", card, "RIGHT", -190, 0)
        descFs:SetWordWrap(true)
    end
    card._searchText = lower((title or "") .. " " .. (description or ""))
    return card
end

function Settings:CreateToggle(parent, y, def)
    local Th = T()
    local card = self:CreateCard(parent, y, def.label, def.description, def.height or 70)
    local switch = CreateFrame("Button", nil, card)
    if GC.Perf then
        GC.Perf:CountUI("buttons", 1)
        GC.Perf:CountUI("textures", 2)
    end
    switch:SetSize(46, 22)
    switch:SetPoint("RIGHT", card, "RIGHT", -16, 0)
    local track = switch:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    local knob = switch:CreateTexture(nil, "OVERLAY")
    knob:SetSize(18, 18)

    local function draw()
        local value = self:GetSetting(def.key)
        if value == nil and def.default ~= nil then value = def.default end
        local on = value and true or false
        local c = on and Th.c.accent or Th.c.btnDisabled
        track:SetColorTexture(c[1], c[2], c[3], on and 0.45 or 1)
        knob:SetColorTexture(on and Th.c.accent[1] or 0.45, on and Th.c.accent[2] or 0.45, on and Th.c.accent[3] or 0.5, 1)
        knob:ClearAllPoints()
        knob:SetPoint(on and "RIGHT" or "LEFT", switch, on and "RIGHT" or "LEFT", on and -2 or 2, 0)
    end
    switch:SetScript("OnClick", function()
        local current = self:GetSetting(def.key)
        if current == nil then current = def.default end
        self:SetSetting(def.key, not current, def.label)
        draw()
        if def.onChange then def.onChange(not current) end
    end)
    draw()
    card._refresh = draw
    return card, y - (def.height or 70) - 8
end

function Settings:CreateInput(parent, y, def)
    local Th = T()
    local card = self:CreateCard(parent, y, def.label, def.description, def.height or 76)
    local box = GC.UI.Panel.Input(card, def.width or 170, Th.inputH)
    box:SetPoint("RIGHT", card, "RIGHT", -16, 0)
    if def.numeric then box:SetNumeric(false) end
    local function save()
        local value = box:GetText() or ""
        if def.numeric then
            value = tonumber(value)
            if not value then
                status("Invalid value for " .. def.label, "textDanger")
                return
            end
            if def.min then value = math.max(def.min, value) end
            if def.max then value = math.min(def.max, value) end
            box:SetText(tostring(value))
        end
        self:SetSetting(def.key, value, def.label)
        if def.onChange then def.onChange(value) end
    end
    local originalFocusLost = box:GetScript("OnEditFocusLost")
    box:SetScript("OnEnterPressed", function(selfBox) selfBox:ClearFocus() end)
    box:SetScript("OnEditFocusLost", function(selfBox)
        if originalFocusLost then originalFocusLost(selfBox) end
        save()
    end)
    card._refresh = function()
        local value = self:GetSetting(def.key)
        if value == nil then value = def.default or "" end
        box:SetText(tostring(value))
    end
    card._refresh()
    return card, y - (def.height or 76) - 8
end

function Settings:CreateDropdown(parent, y, def)
    local Th = T()
    local card = self:CreateCard(parent, y, def.label, def.description, def.height or 76)
    local btn = GC.UI.Button.Create(card, "", "secondary", def.width or 170, Th.btnH)
    btn:SetPoint("RIGHT", card, "RIGHT", -16, 0)
    local function labelFor(key)
        for _, option in ipairs(def.options or {}) do
            if option.key == key then return option.label end
        end
        return def.options and def.options[1] and def.options[1].label or "-"
    end
    local menu = CreateFrame("Frame", nil, UIParent)
    if GC.Perf then GC.Perf:CountUI("frames", 1) end
    menu:SetSize(def.width or 170, math.max(1, #(def.options or {})) * Th.btnH)
    if GC.UI.FrameLayering then
        GC.UI.FrameLayering:PreparePopupFrame(menu, GC.UI.MainFrame and GC.UI.MainFrame.frame, 90)
    else
        menu:SetFrameStrata("DIALOG")
    end
    T().Bg(menu, T().c.panel, T().c.borderAccent)
    menu:Hide()
    for i, option in ipairs(def.options or {}) do
        local row = GC.UI.Button.Create(menu, option.label, "secondary", def.width or 170, Th.btnH)
        row:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, -((i - 1) * Th.btnH))
        row:SetScript("OnClick", function()
            self:SetSetting(def.key, option.key, def.label)
            btn:SetLabel(option.label)
            menu:Hide()
            if def.onChange then def.onChange(option.key) end
        end)
    end
    btn:SetScript("OnClick", function()
        if menu:IsShown() then menu:Hide(); return end
        menu:ClearAllPoints()
        menu:SetPoint("TOPRIGHT", btn, "BOTTOMRIGHT", 0, -2)
        menu:Show()
    end)
    btn:SetScript("OnHide", function() menu:Hide() end)
    card._refresh = function()
        local value = self:GetSetting(def.key)
        if value == nil then value = def.default end
        btn:SetLabel(labelFor(value))
    end
    card._refresh()
    return card, y - (def.height or 76) - 8
end

function Settings:CreateButton(parent, y, def)
    local Th = T()
    local card = self:CreateCard(parent, y, def.label, def.description, def.height or 70)
    local btn = GC.UI.Button.Create(card, def.buttonText or def.label, def.danger and "danger" or "secondary", def.width or 160, Th.btnH)
    btn:SetPoint("RIGHT", card, "RIGHT", -16, 0)
    btn:SetScript("OnClick", function() if def.onClick then def.onClick() end end)
    return card, y - (def.height or 70) - 8
end

function Settings:BuildSetting(parent, y, def)
    if def.type == "toggle" then return self:CreateToggle(parent, y, def) end
    if def.type == "input" then return self:CreateInput(parent, y, def) end
    if def.type == "dropdown" then return self:CreateDropdown(parent, y, def) end
    if def.type == "button" then return self:CreateButton(parent, y, def) end
    return nil, y
end

function Settings:Create(parent)
    if self.frame then return end
    local Th = T()
    local P = Th.padding
    local frame = CreateFrame("Frame", nil, parent)
    if GC.Perf then GC.Perf:CountUI("frames", 1) end
    frame:SetAllPoints(parent)
    frame:Hide()
    Th.Bg(frame, Th.c.bg)
    self.frame = frame

    local header = Th.Fs(frame, "header", "Settings", "textPrimary")
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", P, -P)
    local search = GC.UI.Panel.Input(frame, 260, Th.inputH)
    search:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -P, -P)
    self.searchBox = search
    local hint = Th.Fs(search, "small", "Search settings...", "textDimmed")
    hint:SetPoint("LEFT", search, "LEFT", 7, 0)
    search:SetScript("OnTextChanged", function(box)
        hint:SetShown((box:GetText() or "") == "")
        Settings:ApplySearch(box:GetText() or "")
    end)

    local sidebar = CreateFrame("Frame", nil, frame)
    if GC.Perf then GC.Perf:CountUI("frames", 1) end
    sidebar:SetPoint("TOPLEFT", frame, "TOPLEFT", P, -58)
    sidebar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", P, P)
    sidebar:SetWidth(168)
    Th.Bg(sidebar, Th.c.panelAlt, Th.c.border)
    self.sidebar = sidebar

    local contentShell = CreateFrame("Frame", nil, frame)
    if GC.Perf then GC.Perf:CountUI("frames", 1) end
    contentShell:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", P, 0)
    contentShell:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -P, P)
    Th.Bg(contentShell, Th.c.panel, Th.c.border)
    self.contentShell = contentShell

    local scroll = CreateFrame("ScrollFrame", nil, contentShell)
    if GC.Perf then GC.Perf:CountUI("frames", 1) end
    scroll:SetPoint("TOPLEFT", contentShell, "TOPLEFT", P, -P)
    scroll:SetPoint("BOTTOMRIGHT", contentShell, "BOTTOMRIGHT", -P, P)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(selfScroll, delta)
        local child = selfScroll:GetScrollChild()
        local maxScroll = math.max(0, (child and child:GetHeight() or 0) - selfScroll:GetHeight())
        selfScroll:SetVerticalScroll(math.min(maxScroll, math.max(0, selfScroll:GetVerticalScroll() - delta * 28)))
    end)
    self.contentScroll = scroll

    self.categoryFrames = {}
    self.navButtons = {}
    self.scrollPositions = {}
    if GC.UI.SettingsSidebar and GC.UI.SettingsSidebar.Build then
        GC.UI.SettingsSidebar:Build(sidebar)
    end
    self:SelectCategory(self.order[1] or "appearance")
end

function Settings:BuildCategory(id)
    if self.categoryFrames[id] then return self.categoryFrames[id] end
    local def = self.categories[id]
    if not def then return nil end
    local content = CreateFrame("Frame", nil, self.contentScroll)
    if GC.Perf then GC.Perf:CountUI("frames", 1) end
    content:SetWidth(math.max(520, self.contentShell:GetWidth() - 36))
    content:Hide()
    self.categoryFrames[id] = content

    local y = -2
    local title = T().Fs(content, "subheader", def.label, "textAccent")
    title:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    y = y - 34
    if def.build then
        y = def.build(self, content, y) or y
    end
    content:SetHeight(math.abs(y) + 24)
    return content
end

function Settings:SelectCategory(id)
    if not self.frame then return end
    local content = self:BuildCategory(id)
    if not content then return end
    if self.activeCategory and self.categoryFrames[self.activeCategory] then
        if self.contentScroll then
            self.scrollPositions = self.scrollPositions or {}
            self.scrollPositions[self.activeCategory] = self.contentScroll:GetVerticalScroll()
        end
        self.categoryFrames[self.activeCategory]:Hide()
    end
    self.activeCategory = id
    self.contentScroll:SetScrollChild(content)
    content:Show()
    self.contentScroll:SetVerticalScroll(self.scrollPositions and self.scrollPositions[id] or 0)
    if GC.UI.SettingsSidebar and GC.UI.SettingsSidebar.Refresh then
        GC.UI.SettingsSidebar:Refresh()
    end
    self:Refresh()
    self:FilterActiveCategory(self.searchBox and self.searchBox:GetText() or "")
end

function Settings:ApplySearch(query)
    query = lower(query)
    if query == "" then
        self:SelectCategory(self.activeCategory or self.order[1])
        self:FilterActiveCategory("")
        return
    end
    for _, id in ipairs(self.order) do
        local def = self.categories[id]
        local haystack = lower((def.label or "") .. " " .. (def.keywords or ""))
        for _, setting in ipairs(def.settings or {}) do
            haystack = haystack .. " " .. settingText(setting)
        end
        if haystack:find(query, 1, true) then
            self:SelectCategory(id)
            self:FilterActiveCategory(query)
            return
        end
    end
    self:FilterActiveCategory(query)
end

function Settings:FilterActiveCategory(query)
    query = lower(query or "")
    local active = self.categoryFrames and self.categoryFrames[self.activeCategory or ""]
    if not active then return end
    local anyFilter = query ~= ""
    for _, child in ipairs({active:GetChildren()}) do
        if child._searchText then
            child:SetShown((not anyFilter) or child._searchText:find(query, 1, true) ~= nil)
        else
            child:Show()
        end
    end
end

function Settings:Refresh()
    if not self.categoryFrames then return end
    local active = self.categoryFrames[self.activeCategory or ""]
    if not active then return end
    for _, child in ipairs({active:GetChildren()}) do
        if child._refresh then child:_refresh() end
    end
end

function Settings:GetObjectStats()
    local built = 0
    for _ in pairs(self.categoryFrames or {}) do built = built + 1 end
    return {
        categoriesBuilt = built,
        categoryFrames = built,
    }
end

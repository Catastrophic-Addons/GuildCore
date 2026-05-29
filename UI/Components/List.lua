-- UI/Components/List.lua
-- Virtual scrollable list component. Renders rows by calling a builder callback.
-- Supports row hover, row selection, and alternating row colors.
local addonName, ns = ...
local GC = ns.GuildCore

GC.UI       = GC.UI or {}
GC.UI.List  = {}
local List  = GC.UI.List

local function T() return GC.UI.Theme end

-- Create a scrollable list inside `parent`.
-- @param parent       Parent frame
-- @param rowH         Height of each row (px)
-- @param buildRow     fn(rowFrame, data, index) — populate a row
-- @param onSelect     fn(data, index, button) — called when a row is clicked
-- @param onContext    fn(data, index, row) — called on right click
-- @returns list object with :Refresh(dataArray), :SetSelected(key)
function List.Create(parent, rowH, buildRow, onSelect, onContext)
    local Th  = T()
    local obj = {}

    rowH = rowH or Th.rowH

    -- Clip frame clips child frames during scroll
    local clip = CreateFrame("Frame", nil, parent)
    if GC.Perf then GC.Perf:CountUI("frames", 1) end
    clip:SetAllPoints()
    obj.clip = clip

    -- Scroll frame
    local sf = CreateFrame("ScrollFrame", nil, clip)
    if GC.Perf then GC.Perf:CountUI("frames", 1) end
    sf:SetAllPoints()
    obj.scrollFrame = sf

    -- Scroll bar (right edge)
    local scrollBar = CreateFrame("Slider", nil, clip)
    if GC.Perf then
        GC.Perf:CountUI("frames", 1)
        GC.Perf:CountUI("textures", 2)
    end
    scrollBar:SetWidth(12)
    scrollBar:SetPoint("TOPRIGHT",    clip, "TOPRIGHT", -1,  2)
    scrollBar:SetPoint("BOTTOMRIGHT", clip, "BOTTOMRIGHT", -1, -2)
    scrollBar:SetMinMaxValues(0, 0)
    scrollBar:SetValue(0)
    scrollBar:SetOrientation("VERTICAL")
    scrollBar:SetValueStep(rowH)
    local track = scrollBar:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("TOP", scrollBar, "TOP", 0, 0)
    track:SetPoint("BOTTOM", scrollBar, "BOTTOM", 0, 0)
    track:SetWidth(6)
    local tc = Th.c.panelAlt or Th.c.chrome
    track:SetColorTexture(tc[1], tc[2], tc[3], 0.75)
    -- Thumb
    local thumb = scrollBar:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(10, math.max(34, rowH))
    local ac = Th.c.accent
    thumb:SetColorTexture(ac[1], ac[2], ac[3], 0.7)
    scrollBar:SetThumbTexture(thumb)
    scrollBar:Hide()

    -- Content frame (scrolled child)
    local content = CreateFrame("Frame", nil, sf)
    if GC.Perf then GC.Perf:CountUI("frames", 1) end
    content:SetWidth(clip:GetWidth())
    content:SetHeight(1)
    sf:SetScrollChild(content)
    obj.content = content

    -- Row pool. Keep this capped to visible rows; do not create one frame per
    -- data item. This was the largest roster memory spike after filtering work.
    local rows = {}
    local selectedKey = nil
    local currentData = {}
    local totalCreated = 0
    local clearSelection
    local applySelectionStyles

    local function visibleCapacity()
        local clipH = math.max(1, clip:GetHeight() or 1)
        return math.max(1, math.ceil(clipH / rowH) + 3)
    end

    -- Refresh from a pool — reuse or create visible row frames only.
    local function getRow(i)
        if not rows[i] then
            local row = CreateFrame("Button", nil, content)
            if GC.Perf then
                GC.Perf:CountUI("listRows", 1)
                GC.Perf:CountUI("buttons", 1)
                GC.Perf:CountUI("textures", 4)
            end
            row:SetHeight(rowH)
            row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            -- Backgrounds: base and hover overlay
            local base = row:CreateTexture(nil, "BACKGROUND", nil, -8)
            base:SetAllPoints()
            local hov  = row:CreateTexture(nil, "BACKGROUND", nil, -7)
            hov:SetAllPoints(); hov:SetAlpha(0)
            local sel  = row:CreateTexture(nil, "BACKGROUND", nil, -6)
            sel:SetAllPoints(); sel:SetAlpha(0)
            -- Left selection accent bar
            local bar  = row:CreateTexture(nil, "ARTWORK")
            bar:SetWidth(2); bar:SetPoint("TOPLEFT"); bar:SetPoint("BOTTOMLEFT")
            local a = Th.c.accent
            bar:SetColorTexture(a[1], a[2], a[3], 1)
            bar:SetAlpha(0)

            row._base = base; row._hov = hov; row._sel = sel; row._bar = bar

            row:SetScript("OnEnter", function(self)
                local h = Th.c.rowHover
                self._hov:SetColorTexture(h[1], h[2], h[3], h[4])
                self._hov:SetAlpha(1)
                if GameTooltip and self._tooltipText then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    if self._tooltipTitle then
                        GameTooltip:AddLine(self._tooltipTitle, 1, 1, 1)
                    end
                    local count = 0
                    for line in tostring(self._tooltipText):gmatch("([^\n]+)") do
                        count = count + 1
                        if count > 5 then break end
                        GameTooltip:AddLine(line, 1, 0.82, 0.35, true)
                    end
                    GameTooltip:Show()
                end
            end)
            row:SetScript("OnLeave", function(self)
                self._hov:SetAlpha(0)
                if GameTooltip and self._tooltipText then
                    GameTooltip:Hide()
                end
            end)
            row:SetScript("OnClick", function(self, button)
                local item = self._item
                local index = self._dataIndex
                if not item then return end
                if button == "RightButton" and onContext then
                    onContext(item, index, self)
                    return
                end
                clearSelection()
                selectedKey = item.key
                applySelectionStyles()
                if onSelect then onSelect(item, index, button) end
            end)

            rows[i] = row
            totalCreated = totalCreated + 1
        end
        return rows[i]
    end

    local function renderVisible()
        local Th2 = T()
        local count = currentData and #currentData or 0
        local scroll = sf:GetVerticalScroll() or 0
        local firstIndex = math.max(1, math.floor(scroll / rowH) + 1)
        local capacity = visibleCapacity()

        for slot = 1, capacity do
            local dataIndex = firstIndex + slot - 1
            local row = getRow(slot)
            local item = currentData[dataIndex]
            if item then
                row._item = item
                row._itemKey = item.key
                row._dataIndex = dataIndex

                local c = (dataIndex % 2 == 0) and Th2.c.rowEven or Th2.c.rowOdd
                row._base:SetColorTexture(c[1], c[2], c[3], c[4])
                row._hov:SetAlpha(0)
                row._bar:SetAlpha(0)

                if selectedKey and item.key and item.key == selectedKey then
                    local sc = Th2.c.rowSelected
                    row._sel:SetColorTexture(sc[1], sc[2], sc[3], sc[4])
                    row._sel:SetAlpha(1)
                    local a = Th2.c.accent
                    row._bar:SetColorTexture(a[1], a[2], a[3], 1)
                    row._bar:SetAlpha(1)
                else
                    row._sel:SetAlpha(0)
                end

                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -((dataIndex - 1) * rowH))
                row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -((dataIndex - 1) * rowH))
                row:Show()
                buildRow(row, item, dataIndex)
            else
                row._item = nil
                row._itemKey = nil
                row._dataIndex = nil
                row._tooltipTitle = nil
                row._tooltipText = nil
                row:Hide()
            end
        end

        for i = capacity + 1, #rows do
            rows[i]._item = nil
            rows[i]._itemKey = nil
            rows[i]._dataIndex = nil
            rows[i]._tooltipTitle = nil
            rows[i]._tooltipText = nil
            rows[i]:Hide()
        end

        if obj._emptyLabel then
            if count == 0 then obj._emptyLabel:Show() else obj._emptyLabel:Hide() end
        end
    end

    -- Deselect all rows visually
    clearSelection = function()
        for _, row in ipairs(rows) do
            if row._sel then row._sel:SetAlpha(0) end
            if row._bar then row._bar:SetAlpha(0) end
        end
    end

    applySelectionStyles = function()
        local Th2 = T()
        for _, row in ipairs(rows) do
            if row._itemKey and selectedKey and row._itemKey == selectedKey then
                local sc = Th2.c.rowSelected
                row._sel:SetColorTexture(sc[1], sc[2], sc[3], sc[4])
                row._sel:SetAlpha(1)
                local a = Th2.c.accent
                row._bar:SetColorTexture(a[1], a[2], a[3], 1)
                row._bar:SetAlpha(1)
            else
                if row._sel then row._sel:SetAlpha(0) end
                if row._bar then row._bar:SetAlpha(0) end
            end
        end
    end

    -- Public: Refresh list with new data array
    function obj:Refresh(data)
        local count = data and #data or 0
        local totalH = count * rowH
        currentData = data or {}

        content:SetHeight(math.max(totalH, 1))

        -- Update scroll bar
        local clipH   = clip:GetHeight()
        local maxScroll = math.max(0, totalH - clipH)
        if maxScroll > 0 then
            scrollBar:SetMinMaxValues(0, maxScroll)
            scrollBar:Show()
        else
            scrollBar:SetMinMaxValues(0, 0)
            scrollBar:SetValue(0)
            scrollBar:Hide()
        end

        renderVisible()
    end

    -- Public: programmatically mark a key as selected
    function obj:SetSelected(key, scrollToSelection)
        selectedKey = key
        applySelectionStyles()
        if scrollToSelection then
            self:ScrollToKey(key)
        end
    end

    function obj:GetSelected()
        return selectedKey
    end

    function obj:ScrollToIndex(index)
        index = tonumber(index)
        if not index or index < 1 then
            return false
        end
        local _, max_ = scrollBar:GetMinMaxValues()
        local target = math.max(0, math.min(max_ or 0, (index - 1) * rowH))
        scrollBar:SetValue(target)
        return true
    end

    function obj:ScrollToKey(key)
        if not key then
            return false
        end
        for index, item in ipairs(currentData or {}) do
            if item and item.key == key then
                return self:ScrollToIndex(index)
            end
        end
        return false
    end

    -- Public: set placeholder text shown when the list is empty
    function obj:SetEmptyText(msg)
        if not obj._emptyLabel then
            local Th2 = T()
            local lbl = clip:CreateFontString(nil, "OVERLAY")
            Th2.ApplyFont(lbl, "body")
            if Th2.RegisterRefresh then
                Th2:RegisterRefresh(function()
                    T().ApplyFont(lbl, "body")
                end)
            end
            local dc  = Th2.c.textDimmed
            lbl:SetTextColor(dc[1], dc[2], dc[3], dc[4] or 1)
            lbl:SetPoint("CENTER", clip, "CENTER", 0, 0)
            lbl:SetJustifyH("CENTER")
            lbl:Hide()
            obj._emptyLabel = lbl
        end
        obj._emptyLabel:SetText(msg or "")
    end

    -- Wire scroll bar to scroll frame
    scrollBar:SetScript("OnValueChanged", function(_, val)
        sf:SetVerticalScroll(val)
        renderVisible()
    end)

    -- Mouse wheel on scroll frame
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(_, delta)
        local cur   = scrollBar:GetValue()
        local min_, max_ = scrollBar:GetMinMaxValues()
        local step  = rowH * 3
        local new   = math.max(min_, math.min(max_, cur - delta * step))
        scrollBar:SetValue(new)
    end)

    -- Keep content width synced if the clip resizes
    clip:SetScript("OnSizeChanged", function(self, w)
        content:SetWidth(w - 16) -- scrollbar gutter
        renderVisible()
    end)

    function obj:GetStats()
        return {
            totalCreated = totalCreated,
            pooledRows = #rows,
            visibleRows = visibleCapacity(),
            currentData = #(currentData or {}),
        }
    end

    return obj
end

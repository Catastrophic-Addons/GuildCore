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
    clip:SetAllPoints()
    obj.clip = clip

    -- Scroll frame
    local sf = CreateFrame("ScrollFrame", nil, clip)
    sf:SetAllPoints()
    obj.scrollFrame = sf

    -- Scroll bar (right edge)
    local scrollBar = CreateFrame("Slider", nil, clip)
    scrollBar:SetWidth(6)
    scrollBar:SetPoint("TOPRIGHT",    clip, "TOPRIGHT", 0,  0)
    scrollBar:SetPoint("BOTTOMRIGHT", clip, "BOTTOMRIGHT", 0, 0)
    scrollBar:SetMinMaxValues(0, 0)
    scrollBar:SetValue(0)
    scrollBar:SetOrientation("VERTICAL")
    scrollBar:SetValueStep(rowH)
    -- Thumb
    local thumb = scrollBar:CreateTexture(nil, "OVERLAY")
    local ac = Th.c.accent
    thumb:SetColorTexture(ac[1], ac[2], ac[3], 0.45)
    scrollBar:SetThumbTexture(thumb)
    scrollBar:Hide()

    -- Content frame (scrolled child)
    local content = CreateFrame("Frame", nil, sf)
    content:SetWidth(clip:GetWidth())
    content:SetHeight(1)
    sf:SetScrollChild(content)
    obj.content = content

    -- Row pool
    local rows = {}
    local selectedKey = nil

    -- Refresh from a pool — reuse or create row frames
    local function getRow(i)
        if not rows[i] then
            local row = CreateFrame("Button", nil, content)
            row:SetHeight(rowH)
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
            end)
            row:SetScript("OnLeave", function(self)
                self._hov:SetAlpha(0)
            end)

            rows[i] = row
        end
        return rows[i]
    end

    -- Deselect all rows visually
    local function clearSelection()
        for _, row in ipairs(rows) do
            if row._sel then row._sel:SetAlpha(0) end
            if row._bar then row._bar:SetAlpha(0) end
        end
    end

    -- Public: Refresh list with new data array
    function obj:Refresh(data)
        local Th2   = T()
        local count = data and #data or 0
        local totalH = count * rowH

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

        for i = 1, count do
            local row  = getRow(i)
            local item = data[i]

            -- Alternating row color
            local c = (i % 2 == 0) and Th2.c.rowEven or Th2.c.rowOdd
            row._base:SetColorTexture(c[1], c[2], c[3], c[4])

            -- Reset highlight and selection
            row._hov:SetAlpha(0)
            row._bar:SetAlpha(0)

            -- Restore selection if key matches
            if selectedKey and item.key and item.key == selectedKey then
                local sc = Th2.c.rowSelected
                row._sel:SetColorTexture(sc[1], sc[2], sc[3], sc[4])
                row._sel:SetAlpha(1)
                local a = Th2.c.accent
                row._bar:SetColorTexture(a[1], a[2], a[3], 1)
                row._bar:SetAlpha(1)
            else
                if row._sel then row._sel:SetAlpha(0) end
            end

            row:SetPoint("TOPLEFT",  content, "TOPLEFT", 0, -(i-1)*rowH)
            row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(i-1)*rowH)
            row:Show()

            -- Populate row content via callback
            buildRow(row, item, i)

            -- Click handler
            row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            row:SetScript("OnClick", function(_, button)
                clearSelection()
                selectedKey = item.key
                local sc = Th2.c.rowSelected
                row._sel:SetColorTexture(sc[1], sc[2], sc[3], sc[4])
                row._sel:SetAlpha(1)
                local a = Th2.c.accent
                row._bar:SetColorTexture(a[1], a[2], a[3], 1)
                row._bar:SetAlpha(1)
                if button == "RightButton" and onContext then
                    onContext(item, i, row)
                    return
                end
                if onSelect then onSelect(item, i, button) end
            end)
        end

        -- Hide excess rows
        for i = count + 1, #rows do
            rows[i]:Hide()
        end

        -- Toggle empty state label
        if obj._emptyLabel then
            if count == 0 then obj._emptyLabel:Show() else obj._emptyLabel:Hide() end
        end
    end

    -- Public: programmatically mark a key as selected
    function obj:SetSelected(key)
        selectedKey = key
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
        content:SetWidth(w - 8) -- 8px scrollbar gutter
    end)

    return obj
end

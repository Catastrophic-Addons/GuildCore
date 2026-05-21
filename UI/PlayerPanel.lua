-- UI/PlayerPanel.lua
-- Read-only character profile panel for the roster detail column.
local addonName, ns = ...
local GC = ns.GuildCore

GC.UI.PlayerPanel = {}
local PP = GC.UI.PlayerPanel

local currentPlayer = nil

local function T()  return GC.UI.Theme end
local function DS() return GC.Services.DataStore end
local function GS() return GC.Services.GuildService end

local function trim(value)
    return GC.Utils and GC.Utils.Trim and GC.Utils.Trim(value or "") or tostring(value or ""):match("^%s*(.-)%s*$")
end

local function joinTags(tags)
    return type(tags) == "table" and table.concat(tags, ", ") or ""
end

local function shortName(key)
    return key and (tostring(key):match("^([^%-]+)") or tostring(key)) or nil
end

local function fmtDate(ts)
    return tonumber(ts) and date("%Y-%m-%d", ts) or "-"
end

local function normalizedRealm(realm)
    realm = tostring(realm or "")
    if realm == "" then
        realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName() or ""
    end
    return tostring(realm):gsub("%s+", "")
end

local function unitMatchesPlayer(unit, player)
    if not unit or not player or not UnitExists or not UnitExists(unit) then
        return false
    end

    local guid = player.guid or player.GUID or player.playerGUID or player.memberGUID
    if guid and UnitGUID and UnitGUID(unit) == guid then
        return true
    end

    if not UnitFullName then
        return false
    end
    local name, realm = UnitFullName(unit)
    if not name or name == "" then
        return false
    end
    local targetKey = GC.Utils.NormalizePlayerKey(name, normalizedRealm(realm))
    return targetKey == player.key
end

local function findVisibleUnitToken(player)
    local tokens = {"player", "target", "focus", "mouseover"}
    for i = 1, 4 do
        tokens[#tokens + 1] = "party" .. i
    end
    for i = 1, 40 do
        tokens[#tokens + 1] = "raid" .. i
    end
    for _, token in ipairs(tokens) do
        if unitMatchesPlayer(token, player) then
            return token
        end
    end
    return nil
end

local function setClassIcon(texture, classKey)
    classKey = classKey and tostring(classKey):upper() or nil
    local coords = classKey and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classKey]
    if coords then
        texture:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
        texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        return true
    end

    texture:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    return false
end

local function labelValue(parent, label, y)
    local Th = T()
    local P = Th.padding
    local l = Th.Fs(parent, "small", label, "textSecond")
    l:SetPoint("TOPLEFT", parent, "TOPLEFT", P, y)
    l:SetWidth(128)
    local v = Th.Fs(parent, "data", "-", "textPrimary")
    v:SetPoint("TOPLEFT", parent, "TOPLEFT", P + 130, y + 1)
    v:SetPoint("RIGHT", parent, "RIGHT", -P, 0)
    v:SetJustifyH("LEFT")
    v:SetWordWrap(false)
    return v
end

local function section(parent, title, y)
    local Th = T()
    local P = Th.padding
    local fs = Th.Fs(parent, "tiny", title, "textAccent")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", P, y)
    local sep = parent:CreateTexture(nil, "ARTWORK")
    sep:SetPoint("TOPLEFT", parent, "TOPLEFT", P, y - 15)
    sep:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -P, y - 15)
    sep:SetHeight(1)
    local c = Th.c.separator
    sep:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    return y - 28
end

local function getLivePlayer()
    if not currentPlayer then return nil end
    return DS():GetPlayer(currentPlayer.key) or currentPlayer
end

function PP:SetPlayer(viewModel)
    currentPlayer = viewModel
end

function PP:GetCurrentPlayer()
    return currentPlayer
end

function PP:ShowPlayerByKey(key)
    local entry = GS():GetRosterEntry(key)
    if not entry then
        return false
    end
    self:SetPlayer(entry)
    self:Refresh()
    return true
end

function PP:Create(parent)
    if self.frame then return end
    local Th = T()
    local P = Th.padding

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    self.frame = frame
    Th.Bg(frame, Th.c.panelAlt)

    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(122)
    Th.Bg(header, Th.c.chrome, Th.c.border)
    self.header = header
    if GC.UI and GC.UI.CharacterContextMenu then
        GC.UI.CharacterContextMenu:Attach(header, function()
            local player = getLivePlayer()
            if player then player.source = "Profile" end
            return player
        end)
    end

    local portrait = CreateFrame("Frame", nil, header)
    portrait:SetSize(58, 58)
    portrait:SetPoint("TOPLEFT", P, -P)
    Th.Bg(portrait, Th.c.panel, Th.c.borderAccent)
    self.portrait = portrait

    local portraitTexture = portrait:CreateTexture(nil, "ARTWORK")
    portraitTexture:SetPoint("TOPLEFT", portrait, "TOPLEFT", 3, -3)
    portraitTexture:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", -3, 3)
    portraitTexture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    self.portraitTexture = portraitTexture

    local portraitText = Th.Fs(portrait, "subheader", "?", "textAccent")
    portraitText:SetPoint("CENTER")
    portraitText:Hide()
    self.portraitText = portraitText

    local name = Th.Fs(header, "subheader", "No character selected", "textPrimary")
    name:SetPoint("TOPLEFT", portrait, "TOPRIGHT", 10, -2)
    name:SetPoint("TOPRIGHT", header, "TOPRIGHT", -P, -P)
    name:SetWordWrap(false)
    self.nameLabel = name

    local meta = Th.Fs(header, "data", "", "textSecond")
    meta:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -4)
    meta:SetPoint("RIGHT", header, "RIGHT", -P, 0)
    self.metaLabel = meta

    local status = Th.Fs(header, "status", "", "statusActive")
    status:SetPoint("TOPLEFT", meta, "BOTTOMLEFT", 0, -5)
    self.statusLabel = status

    local editBtn = GC.UI.Button.Create(header, "Edit Character", "primary", Th.detailWidth - P * 2, Th.btnH)
    editBtn:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", P, 10)
    editBtn:SetScript("OnClick", function()
        local player = getLivePlayer()
        if player and GC.UI.EditCharacterPopup then
            GC.UI.EditCharacterPopup:Open(player)
        end
    end)
    self.editBtn = editBtn

    local scroll = CreateFrame("ScrollFrame", nil, frame)
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -126)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta)
        scroll:SetVerticalScroll(math.max(0, scroll:GetVerticalScroll() - delta * 28))
    end)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(Th.detailWidth)
    scroll:SetScrollChild(content)
    self.content = content

    local y = -10
    y = section(content, "IDENTITY", y)
    self.roleValue = labelValue(content, "Role", y); y = y - 18
    self.mainValue = labelValue(content, "Main", y); y = y - 18
    self.altsValue = labelValue(content, "Connected Characters", y); y = y - 18
    self.realmValue = labelValue(content, "Realm", y); y = y - 18
    self.joinValue = labelValue(content, "Joined", y); y = y - 18
    self.firstSeenValue = labelValue(content, "First Seen", y); y = y - 18
    self.lastSeenValue = labelValue(content, "Last Seen", y); y = y - 26

    y = section(content, "GUILD DATA", y)
    self.rankValue = labelValue(content, "Rank", y); y = y - 18
    self.pointsValue = labelValue(content, "Points", y); y = y - 18
    self.tagsValue = labelValue(content, "Tags", y); y = y - 18
    self.discordValue = labelValue(content, "Discord", y); y = y - 18
    self.activityValue = labelValue(content, "Activity", y); y = y - 26

    y = section(content, "NOTES", y)
    self.publicNoteValue = labelValue(content, "Public", y); y = y - 34
    self.officerNoteValue = labelValue(content, "Officer", y); y = y - 34
    self.customNoteValue = labelValue(content, "Custom", y); y = y - 34

    y = section(content, "LOCATION", y)
    self.locationValue = labelValue(content, "Zone", y); y = y - 18
    self.onlineValue = labelValue(content, "Status", y); y = y - 26

    content:SetHeight(math.abs(y) + P)
end

function PP:_updatePortrait(player, live)
    if not self.portraitTexture then return end
    player = player or {}
    live = live or player

    self.portraitText:Hide()
    self.portraitTexture:Show()
    self.portraitTexture:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local unit = (player.isOnline or live.isOnline) and findVisibleUnitToken(live) or nil
    if unit and SetPortraitTexture then
        local ok = pcall(SetPortraitTexture, self.portraitTexture, unit)
        if ok and (not self.portraitTexture.GetTexture or self.portraitTexture:GetTexture()) then
            return
        end
    end

    -- Offline, cross-realm, or non-visible guild members do not always have a
    -- unit token available, so fall back to Blizzard's class icon sheet.
    local hasClassIcon = setClassIcon(self.portraitTexture, player.class or player.classFileName or live.class or live.classFileName)
    if not hasClassIcon and self.portraitText then
        self.portraitText:SetText("?")
        self.portraitText:Show()
    end
end

function PP:Refresh()
    if not self.frame then return end
    local Th = T()
    local P = Th.padding

    if not currentPlayer then
        self.nameLabel:SetText("No character selected")
        self.metaLabel:SetText("Select a roster row to view the profile.")
        self.statusLabel:SetText("")
        setClassIcon(self.portraitTexture, nil)
        self.portraitText:SetText("?")
        self.portraitText:Show()
        self.editBtn:SetEnabled(false)
        for _, fs in ipairs({
            self.roleValue, self.mainValue, self.altsValue, self.realmValue, self.joinValue,
            self.firstSeenValue, self.lastSeenValue, self.rankValue, self.pointsValue,
            self.tagsValue, self.discordValue, self.activityValue, self.publicNoteValue,
            self.officerNoteValue, self.customNoteValue, self.locationValue, self.onlineValue,
        }) do
            fs:SetText("-")
        end
        return
    end

    local p = GS():GetRosterEntry(currentPlayer.key) or currentPlayer
    currentPlayer = p
    local live = DS():GetPlayer(p.key) or p
    local rgb = p.classRGB or { 1, 1, 1 }
    local className = p.classDisplayName or p.class or "-"
    local specLine = p.specDisplay and (className .. " / " .. p.specDisplay) or className
    local points = live.points and live.points.balance or 0
    local tags = joinTags(live.notes and live.notes.tags or {})
    local discord = live.officerData and live.officerData.discordName or ""
    local verified = live.officerData and live.officerData.discordVerified
    local group = GC.AltMain and GC.AltMain:GetGroup(live.key) or nil
    local mainKey = group and group.mainKey or live.main or live.key
    local connectedCount = GC.AltMain and GC.AltMain:GetConnectedCount(live.key) or 1

    self.editBtn:SetEnabled(true)
    self.nameLabel:SetText(p.key or p.name or "Unknown")
    self.nameLabel:SetTextColor(rgb[1], rgb[2], rgb[3], 1)
    self.metaLabel:SetText(string.format("%s  |  %s  |  L%s", p.rankName or "-", specLine, tostring(p.level or "?")))
    local statusColor = Th.c[p.statusKey] or Th.c.textDimmed
    self.statusLabel:SetText(p.statusLabel or "-")
    self.statusLabel:SetTextColor(statusColor[1], statusColor[2], statusColor[3], statusColor[4] or 1)
    self:_updatePortrait(p, live)

    self.roleValue:SetText(p.classificationLabel or live.classification or "Unknown")
    self.mainValue:SetText(mainKey and mainKey ~= live.key and shortName(mainKey) or "-")
    self.altsValue:SetText(tostring(connectedCount))
    self.realmValue:SetText(p.realm or live.realm or "-")
    self.joinValue:SetText(p.joinedDisplay or fmtDate(live.joinedAt))
    self.firstSeenValue:SetText(p.firstSeenDisplay or fmtDate(live.firstSeenAt))
    self.lastSeenValue:SetText(p.lastSeenDisplay or fmtDate(live.lastSeenAt))

    self.rankValue:SetText(p.rankName or "-")
    self.pointsValue:SetText(tostring(points))
    self.tagsValue:SetText(tags ~= "" and tags or "None")
    self.discordValue:SetText(discord ~= "" and (verified == false and (discord .. " (not verified)") or discord) or "-")
    self.activityValue:SetText(p.needsPrompt and "Needs classification" or "Tracked")

    self.publicNoteValue:SetText(trim(live.publicNote or p.publicNote) ~= "" and trim(live.publicNote or p.publicNote) or "-")
    self.officerNoteValue:SetText(trim(live.officerNote or p.officerNote) ~= "" and trim(live.officerNote or p.officerNote) or "-")
    self.customNoteValue:SetText(live.notes and trim(live.notes.custom) ~= "" and live.notes.custom or "-")

    self.locationValue:SetText(p.locationDisplay or live.zone or "-")
    self.onlineValue:SetText(p.statusLabel or "-")

    self.content:SetHeight(math.max(self.content:GetHeight() or 1, 430 + P))
end

function PP:RefreshActionMacroState()
    -- Kept for compatibility with macro callbacks; full action state now lives
    -- in EditCharacterPopup and the shared context menu.
end

function PP:SetActionFeedback(message, colorKey)
    if GC.UI.MainFrame then
        GC.UI.MainFrame:SetStatus(message, colorKey or "textDimmed")
    end
end

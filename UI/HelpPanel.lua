-- UI/HelpPanel.lua
-- In-game reference for officers: icons, indicators, workflows, and commands.
local addonName, ns = ...
local GC = ns.GuildCore

GC.UI.HelpPanel = {}
local HP = GC.UI.HelpPanel

local function T() return GC.UI.Theme end

local HELP_SECTIONS = {
    {
        title = "Roster Indicators",
        lines = {
            "[M] Main: primary character for a linked group. Shown in green.",
            "[A] Alt: linked alt character. Shown in gold.",
            "[?] Unknown: needs officer classification.",
            "! Roster Data Issue: relationship data needs review.",
            "Grey names are offline. Online names use class color.",
            "Rank text is colored separately from class and status.",
        },
    },
    {
        title = "Relationship Issues",
        lines = {
            "Alt has no valid linked Main: assign a Main manually.",
            "Placeholder connected character: safe repair can remove stale placeholder links.",
            "Missing reciprocal link: safe repair can restore obvious one-way links.",
            "Multiple Mains: choose the real Main in Edit Character.",
            "Open Dashboard > Roster Data Issues to filter affected characters.",
            "Use Dashboard > Repair Alt Links to preview safe cleanup.",
        },
    },
    {
        title = "Common Officer Workflows",
        lines = {
            "Classify a character: Roster > select character > Edit Character > Main / Alt.",
            "Mark as Main: Edit Character > Main / Alt > Mark as Main > Save.",
            "Mark as Alt: type/select the target main in Add Alt, click Mark as Alt, then Save.",
            "Link alts to a main: open the main, add each alt under Add Alt, then Save.",
            "Review issues: Dashboard > Roster Data Issues, then open affected rows.",
            "Safe cleanup: Dashboard > Repair Alt Links, review preview, then Apply Safe Repairs.",
        },
    },
    {
        title = "GRM Import",
        lines = {
            "Roster > Import GRM opens the paste-based importer.",
            "Use Parse / Preview before applying any import.",
            "Validate View shows how data will appear on the current roster.",
            "Members not in the current guild are skipped by default.",
            "Default mode fills blanks only and avoids overwriting officer-managed data.",
            "The addon never reads arbitrary export files directly from disk.",
        },
    },
    {
        title = "Recruitment And Invites",
        lines = {
            "Invite tab contains invite scanning, filters, queue controls, and dry run.",
            "Use Dry Run before a real queue pass when testing filters.",
            "Invite scan status and debug controls live on the Invite tab.",
            "Ban Book keeps local moderation records for characters you do not want invited.",
        },
    },
    {
        title = "Messages",
        lines = {
            "Messages stores reusable guild message templates.",
            "Categories organize templates for officers.",
            "Preview Send validates placeholders and output before queueing.",
            "Imports are validated before creating local template copies.",
        },
    },
    {
        title = "Purge And Activity",
        lines = {
            "Purge tab reviews inactivity candidates and protected members.",
            "Build Macro prepares guild removal commands; Confirm is deliberate.",
            "Activity tab shows roster, rank, note, point, bank, and alt-link events.",
            "Dashboard cards route to filtered roster, purge, or activity views.",
        },
    },
    {
        title = "Useful Slash Commands",
        lines = {
            "/gc or /guildcore: toggle Guild Core.",
            "/gc dashboard, /gc roster, /gc invite, /gc purge: open a tab.",
            "/gc messages, /gc banbook, /gc log, /gc settings, /gc help: open tools.",
            "/gc scan: request a roster scan.",
            "/gc validate-links: print relationship issue counts.",
            "/gc repair-links-preview: print safe/manual repair counts.",
            "/gc mem, /gc perf, /gc uiobjects: diagnostics.",
        },
    },
}

local function makeSection(parent, title, y)
    local Th = T()
    local P = Th.padding
    local header = Th.Fs(parent, "subheader", title, "textAccent")
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", P, y)
    local sep = parent:CreateTexture(nil, "ARTWORK")
    sep:SetPoint("TOPLEFT", parent, "TOPLEFT", P, y - 20)
    sep:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -P, y - 20)
    sep:SetHeight(1)
    local c = Th.c.separator
    sep:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    return y - 30
end

local function makeText(parent, text, x, y, width, colorKey)
    local Th = T()
    local fs = Th.Fs(parent, "data", text, colorKey or "textSecond")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fs:SetWidth(width)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(true)
    return fs
end

local function makeCard(parent, x, y, width, height, section)
    local Th = T()
    local card = CreateFrame("Frame", nil, parent)
    card:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    card:SetSize(width, height)
    Th.Bg(card, Th.c.panelAlt, Th.c.border)

    local stripe = card:CreateTexture(nil, "ARTWORK")
    stripe:SetPoint("TOPLEFT")
    stripe:SetPoint("BOTTOMLEFT")
    stripe:SetWidth(3)
    local ac = Th.c.accent
    stripe:SetColorTexture(ac[1], ac[2], ac[3], 0.9)

    local title = Th.Fs(card, "small", section.title, "textAccent")
    title:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -8)
    title:SetPoint("RIGHT", card, "RIGHT", -8, 0)
    title:SetJustifyH("LEFT")

    local yy = -30
    for _, line in ipairs(section.lines or {}) do
        local bullet = Th.Fs(card, "data", "-", "textWarn")
        bullet:SetPoint("TOPLEFT", card, "TOPLEFT", 10, yy)
        bullet:SetWidth(10)
        local fs = Th.Fs(card, "data", line, "textSecond")
        fs:SetPoint("TOPLEFT", card, "TOPLEFT", 24, yy)
        fs:SetPoint("RIGHT", card, "RIGHT", -8, 0)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(true)
        yy = yy - 18
    end

    return card
end

function HP:Create(parent)
    if self.frame then return end
    local Th = T()
    local P = Th.padding

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    frame:Hide()
    self.frame = frame
    Th.Bg(frame, Th.c.bg)

    local hdr = Th.Fs(frame, "header", "Help", "textPrimary")
    hdr:SetPoint("TOPLEFT", frame, "TOPLEFT", P, -P)

    local sub = Th.Fs(frame, "data", "Icons, Commands, and Officer Guide", "textDimmed")
    sub:SetPoint("LEFT", hdr, "RIGHT", 12, -2)

    local scroll = CreateFrame("ScrollFrame", nil, frame)
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -(P + 40))
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, P)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local child = self:GetScrollChild()
        local maxScroll = math.max(0, (child and child:GetHeight() or 0) - (self:GetHeight() or 0))
        self:SetVerticalScroll(math.min(maxScroll, math.max(0, (self:GetVerticalScroll() or 0) - delta * 34)))
    end)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(1040)
    scroll:SetScrollChild(content)
    self.content = content

    local introY = -2
    introY = makeSection(content, "Officer Reference", introY)
    makeText(content, "This page explains Guild Core's roster indicators, relationship warnings, import safety checks, and common officer tools. It is a local reference only; it does not change guild data.", P, introY, 980, "textSecond")

    local startY = introY - 46
    local cardW = 500
    local cardH = 150
    local gapX = 18
    local gapY = 16
    for index, section in ipairs(HELP_SECTIONS) do
        local col = (index - 1) % 2
        local row = math.floor((index - 1) / 2)
        makeCard(content, P + col * (cardW + gapX), startY - row * (cardH + gapY), cardW, cardH, section)
    end

    local rows = math.ceil(#HELP_SECTIONS / 2)
    content:SetHeight(math.abs(startY) + rows * (cardH + gapY) + P)
end

function HP:Refresh()
    -- Static reference page; kept for panel registry consistency.
end

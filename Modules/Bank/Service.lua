local addonName, ns = ...
local GC = ns.GuildCore

local GuildBankService = {}
GuildBankService.__index = GuildBankService

local function settingsEnabled()
    local settings = GC.DB and GC.DB.GetSettings and GC.DB:GetSettings()
    return not settings or settings.enableGuildBankModule ~= false
end

local function splitNameRealm(fullName)
    if not fullName or fullName == "" then
        return nil, nil
    end
    local name, realm = strsplit("-", fullName)
    return name, realm
end

local function normalizePlayerKey(name)
    if not name or name == "" then
        return nil
    end
    local playerName, realm = splitNameRealm(name)
    return GC.Utils.NormalizePlayerKey(playerName or name, realm)
end

local function approxOccurredAt(capturedAt, years, months, days, hours)
    local ageHours = (tonumber(hours) or 0)
        + ((tonumber(days) or 0) * 24)
        + ((tonumber(months) or 0) * 30 * 24)
        + ((tonumber(years) or 0) * 365 * 24)

    local estimate = (capturedAt or time()) - (ageHours * 3600)
    return estimate - (estimate % 3600)
end

local function itemNameFromLink(link)
    if not link then
        return nil
    end
    local itemName = GetItemInfo and GetItemInfo(link)
    if itemName then
        return itemName
    end
    return link:match("%[(.-)%]") or link
end

local function buildItemSummary(entry)
    local label = entry.itemName or entry.itemLink or "item"
    if entry.transactionType == "move" then
        return string.format("Moved x%d %s (%s -> %s)",
            tonumber(entry.count or 0),
            label,
            tostring(entry.fromTabName or entry.fromTab or "?"),
            tostring(entry.toTabName or entry.toTab or "?")
        )
    end
    return string.format("%s x%d %s (%s)",
        entry.transactionType == "deposit" and "Deposited" or "Withdrew",
        tonumber(entry.count or 0),
        label,
        tostring(entry.tabName or entry.tab or "?")
    )
end

local function formatCopper(amount)
    amount = tonumber(amount) or 0
    local gold = math.floor(amount / 10000)
    local silver = math.floor((amount % 10000) / 100)
    local copper = amount % 100
    if gold > 0 then
        return string.format("%dg %ds %dc", gold, silver, copper)
    end
    if silver > 0 then
        return string.format("%ds %dc", silver, copper)
    end
    return string.format("%dc", copper)
end

local function buildMoneySummary(entry)
    local verb = ({
        deposit = "Deposited",
        withdrawal = "Withdrew",
        repair = "Used for repairs",
    })[entry.transactionType] or "Updated"

    return string.format("%s %s", verb, formatCopper(entry.amount))
end

local function appendActivityLog(entry)
    local eventType = entry.kind == "money" and "BANK_MONEY" or "BANK_ITEM"
    GC.Services.DataStore:AppendLog({
        -- Mirror the actual bank-log entry time, not the time GuildCore pulled
        -- the log into saved variables. Blizzard exposes bank log age as
        -- relative fields, so occurredAt is a best-effort absolute timestamp.
        timestamp = entry.occurredAt or entry.capturedAt or time(),
        event = eventType,
        playerKey = entry.playerKey or entry.playerName or "Unknown",
        newValue = entry.summary,
        reason = "guild-bank",
        bankKind = entry.kind,
        bankTransactionType = entry.transactionType,
        bankTab = entry.tabName or entry.tab,
        bankCapturedAt = entry.capturedAt,
    })
end

local function getTabName(tab)
    local name = GC.API.GetGuildBankTabInfo and GC.API.GetGuildBankTabInfo(tab)
    if type(name) == "string" and name ~= "" then
        return name
    end
    return string.format("Tab %d", tonumber(tab) or 0)
end

function GuildBankService:_captureItemLogs(capturedAt)
    local entries = {}
    local tabCount = tonumber(GC.API.GetNumGuildBankTabs()) or 0

    for tab = 1, tabCount do
        local txnCount = tonumber(GC.API.GetNumGuildBankTransactions(tab)) or 0
        for index = 1, txnCount do
            local transactionType, playerName, itemLink, count, tab1, tab2, years, months, days, hours = GC.API.GetGuildBankTransaction(tab, index)
            if transactionType and playerName then
                local occurredAt = approxOccurredAt(capturedAt, years, months, days, hours)
                local entry = {
                    kind = "item",
                    tab = tab,
                    tabName = getTabName(tab),
                    transactionType = transactionType,
                    playerName = playerName,
                    playerKey = normalizePlayerKey(playerName),
                    itemLink = itemLink,
                    itemName = itemNameFromLink(itemLink),
                    count = tonumber(count) or 0,
                    fromTab = tonumber(tab1),
                    toTab = tonumber(tab2),
                    fromTabName = transactionType == "move" and getTabName(tonumber(tab1) or 0) or nil,
                    toTabName = transactionType == "move" and getTabName(tonumber(tab2) or 0) or nil,
                    occurredAt = occurredAt,
                    capturedAt = capturedAt,
                    sourceIndex = index,
                }
                entry.summary = buildItemSummary(entry)
                entry.signature = table.concat({
                    "item",
                    tostring(entry.transactionType),
                    tostring(entry.playerName),
                    tostring(entry.itemLink or entry.itemName or ""),
                    tostring(entry.count),
                    tostring(entry.fromTab or entry.tab or ""),
                    tostring(entry.toTab or ""),
                    tostring(entry.occurredAt),
                }, "|")
                entries[#entries + 1] = entry
            end
        end
    end

    return entries
end

function GuildBankService:_captureMoneyLogs(capturedAt)
    local entries = {}
    local txnCount = tonumber(GC.API.GetNumGuildBankMoneyTransactions()) or 0

    for index = 1, txnCount do
        local transactionType, playerName, amount, years, months, days, hours = GC.API.GetGuildBankMoneyTransaction(index)
        if transactionType and playerName then
            local entry = {
                kind = "money",
                transactionType = transactionType,
                playerName = playerName,
                playerKey = normalizePlayerKey(playerName),
                amount = tonumber(amount) or 0,
                occurredAt = approxOccurredAt(capturedAt, years, months, days, hours),
                capturedAt = capturedAt,
                sourceIndex = index,
            }
            entry.summary = buildMoneySummary(entry)
            entry.signature = table.concat({
                "money",
                tostring(entry.transactionType),
                tostring(entry.playerName),
                tostring(entry.amount),
                tostring(entry.occurredAt),
            }, "|")
            entries[#entries + 1] = entry
        end
    end

    return entries
end

function GuildBankService:Capture()
    if not settingsEnabled() or not IsInGuild() then
        return 0
    end

    local capturedAt = time()
    local allEntries = {}
    local itemEntries = self:_captureItemLogs(capturedAt)
    local moneyEntries = self:_captureMoneyLogs(capturedAt)

    for _, entry in ipairs(itemEntries) do
        allEntries[#allEntries + 1] = entry
    end
    for _, entry in ipairs(moneyEntries) do
        allEntries[#allEntries + 1] = entry
    end

    table.sort(allEntries, function(a, b)
        if a.occurredAt ~= b.occurredAt then
            return a.occurredAt < b.occurredAt
        end
        return (a.sourceIndex or 0) < (b.sourceIndex or 0)
    end)

    local inserted = 0
    for _, entry in ipairs(allEntries) do
        if GC.Services.DataStore:AppendGuildBankEntry(entry) then
            appendActivityLog(entry)
            inserted = inserted + 1
        end
    end

    GC:Debug(string.format(
        "Guild bank capture: itemLogs=%d moneyLogs=%d newEntries=%d",
        #itemEntries,
        #moneyEntries,
        inserted
    ))

    return inserted
end

function GuildBankService:EnsureHooks()
    if self.hooksInstalled then
        return true
    end

    if not GuildBankFrame then
        return false
    end

    GuildBankFrame:HookScript("OnShow", function()
        if GC.Services.GuildBank then
            GC.Services.GuildBank:OnGuildBankOpened()
        end
    end)
    GuildBankFrame:HookScript("OnHide", function()
        if GC.Services.GuildBank then
            GC.Services.GuildBank:OnGuildBankClosed()
        end
    end)

    self.hooksInstalled = true
    GC:Debug("Guild bank frame hooks installed.")
    return true
end

function GuildBankService:RequestCapture(reason)
    if not settingsEnabled() or not IsInGuild() then
        return
    end

    self.captureReason = reason or "manual"
    self.bankOpen = true

    local tabCount = tonumber(GC.API.GetNumGuildBankTabs()) or 0
    if tabCount <= 0 then
        self.captureRetries = (self.captureRetries or 0) + 1
        if self.captureRetries <= 3 then
            if self.captureTimer then
                self.captureTimer:Cancel()
            end
            self.captureTimer = C_Timer.NewTimer(0.4, function()
                self.captureTimer = nil
                if self.bankOpen then
                    self:RequestCapture(self.captureReason)
                end
            end)
        end
        return
    end

    self.captureRetries = 0
    local moneyTab = (MAX_GUILDBANK_TABS or 8) + 1

    for tab = 1, tabCount do
        GC.API.QueryGuildBankLog(tab)
    end
    GC.API.QueryGuildBankLog(moneyTab)

    if self.captureTimer then
        self.captureTimer:Cancel()
    end
    self.captureTimer = C_Timer.NewTimer(1.2, function()
        self.captureTimer = nil
        if self.bankOpen then
            self:Capture()
        end
    end)
end

function GuildBankService:OnGuildBankOpened()
    self.bankOpen = true
    self.captureRetries = 0
    GC:Debug("Guild bank opened; requesting log capture.")
    self:RequestCapture("open")
end

function GuildBankService:OnGuildBankClosed()
    self.bankOpen = false
    self.captureRetries = 0
    if self.captureTimer then
        self.captureTimer:Cancel()
        self.captureTimer = nil
    end
end

function GuildBankService:OnGuildBankLogUpdate()
    if not self.bankOpen then
        return
    end

    if self.captureTimer then
        self.captureTimer:Cancel()
    end
    self.captureTimer = C_Timer.NewTimer(0.35, function()
        self.captureTimer = nil
        if self.bankOpen then
            self:Capture()
        end
    end)
end

GC:RegisterService("GuildBank", setmetatable({}, GuildBankService))

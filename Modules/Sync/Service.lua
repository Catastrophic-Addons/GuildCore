-- /GuildCore/Modules/Sync/Service.lua
-- Safe officer-to-officer addon-message sync. Compatibility is checked before
-- any dataset is sent or applied.
local addonName, ns = ...
local GC = ns.GuildCore

GC.Sync = GC.Sync or {}
local Sync = GC.Sync

local PREFIX = "GuildCoreSync"
local CHUNK_SIZE = 180
local SESSION_TIMEOUT = 30
local PEER_COOLDOWN = 600
local SYNC_SCHEMA_VERSION = 1

GC.SYNC_SCHEMA_VERSION = GC.SYNC_SCHEMA_VERSION or SYNC_SCHEMA_VERSION
GC.DATA_SCHEMA_VERSION = GC.DATA_SCHEMA_VERSION or 1
GC.VERSION = GC.VERSION or GC.Version or "dev"

local function settings()
    local root = (GC.DB and GC.DB.Root and GC.DB.GetSettings and GC.DB:GetSettings())
        or (type(GuildCoreDB) == "table" and GuildCoreDB.settings)
        or {}
    root.sync = type(root.sync) == "table" and root.sync or {}
    local s = root.sync
    if s.enabled == nil then s.enabled = root.enableSyncModule == true end
    if s.autoOnLogin == nil then s.autoOnLogin = false end
    if s.autoOnPeerDetected == nil then s.autoOnPeerDetected = false end
    if s.showMessages == nil then s.showMessages = true end
    if s.debug == nil then s.debug = false end
    return s, root
end

local function message(...)
    local s = settings()
    if s.showMessages ~= false and GC.Print then
        GC:Print(...)
    end
end

local function debugLog(...)
    local s = settings()
    if s.debug == true and GC.Print then
        GC:Print("Sync:", ...)
    end
end

local function now()
    return GC.Utils and GC.Utils.Now and GC.Utils.Now() or time()
end

local function trim(value)
    return GC.Utils and GC.Utils.Trim and GC.Utils.Trim(value or "") or tostring(value or ""):match("^%s*(.-)%s*$")
end

local function playerFullName()
    local name, realm
    if UnitFullName then
        name, realm = UnitFullName("player")
    elseif UnitName then
        name = UnitName("player")
    end
    name = trim(name)
    realm = trim(realm)
    if realm == "" then
        realm = trim((GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or "")
    end
    realm = realm:gsub("%s+", "")
    if name == "" then return "Unknown" end
    return realm ~= "" and (name .. "-" .. realm) or name
end

local function normalizeSender(sender)
    sender = trim(sender)
    if sender == "" then return "" end
    local name, realm = sender:match("^([^%-]+)%-(.+)$")
    if not name then
        name = sender
        realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or ""
    end
    realm = trim(realm):gsub("%s+", "")
    return realm ~= "" and (name .. "-" .. realm) or name
end

local function senderInGuild(peerName)
    if not peerName or peerName == "" then return false end
    if not GetNumGuildMembers or not GetGuildRosterInfo then
        return IsInGuild and IsInGuild() or false
    end
    local target = peerName:lower()
    local count = GetNumGuildMembers() or 0
    for index = 1, count do
        local fullName = GetGuildRosterInfo(index)
        if normalizeSender(fullName):lower() == target then
            return true
        end
    end
    return false
end

local function guildRankIndex(peerName)
    if not peerName or peerName == "" or not GetNumGuildMembers or not GetGuildRosterInfo then
        return nil
    end
    local target = peerName:lower()
    local count = GetNumGuildMembers() or 0
    for index = 1, count do
        local fullName, _, rankIndex = GetGuildRosterInfo(index)
        if normalizeSender(fullName):lower() == target then
            return tonumber(rankIndex)
        end
    end
    return nil
end

local function encode(value)
    value = tostring(value or "")
    return (value:gsub("([^%w%-%._~])", function(ch)
        return string.format("%%%02X", string.byte(ch))
    end))
end

local function decode(value)
    value = tostring(value or "")
    return (value:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end))
end

local function joinFields(...)
    local out = {}
    for i = 1, select("#", ...) do
        out[i] = encode(select(i, ...))
    end
    return table.concat(out, "|")
end

local function splitFields(payload)
    local fields = {}
    payload = tostring(payload or "")
    if payload == "" then return fields end
    for part in (payload .. "|"):gmatch("(.-)|") do
        fields[#fields + 1] = decode(part)
        if #fields > 64 then break end
    end
    return fields
end

local function checksum(text)
    local sum = 0
    for i = 1, #tostring(text or "") do
        sum = (sum + string.byte(text, i) * i) % 1000000007
    end
    return tostring(sum)
end

local function safeUpdatedAt(record)
    if type(record) ~= "table" then return 0 end
    return tonumber(record.updatedAt or record.addedAt or record.timestamp or record.lastUpdatedAt) or 0
end

local function ensureRecordAudit(record, peer)
    if type(record) ~= "table" then return end
    record.updatedAt = tonumber(record.updatedAt or record.addedAt) or now()
    record.updatedBy = record.updatedBy or record.addedBy or peer
    record.sourceVersion = record.sourceVersion or tostring(GC.Version or GC.VERSION or "dev")
end

local function serializeRecords(records)
    local rows = {}
    for _, record in ipairs(records or {}) do
        local fields = {}
        for _, value in ipairs(record) do
            fields[#fields + 1] = encode(value)
        end
        rows[#rows + 1] = table.concat(fields, "\t")
    end
    return table.concat(rows, "\n")
end

local function deserializeRecords(payload)
    local rows = {}
    for line in tostring(payload or ""):gmatch("[^\n]+") do
        local record = {}
        for field in (line .. "\t"):gmatch("(.-)\t") do
            record[#record + 1] = decode(field)
            if #record > 64 then break end
        end
        rows[#rows + 1] = record
    end
    return rows
end

local function playerSyncTimestamp(player)
    if type(player) ~= "table" then return 0 end
    local meta = player.syncMeta or {}
    return math.max(
        tonumber(meta.main) or 0,
        tonumber(meta.customNote) or 0,
        tonumber(meta.joinedAt) or 0,
        tonumber(meta.promotedAt) or 0,
        tonumber(player.updatedAt) or 0
    )
end

local function joinList(values)
    local out = {}
    if type(values) ~= "table" then return "" end
    for _, value in pairs(values) do
        if value ~= nil and tostring(value) ~= "" then
            out[#out + 1] = tostring(value)
        end
    end
    table.sort(out)
    return table.concat(out, ",")
end

local function wipeTable(tbl)
    if type(tbl) ~= "table" then return end
    if wipe then
        wipe(tbl)
        return
    end
    for key in pairs(tbl) do tbl[key] = nil end
end

local DATASETS = {
    banBook = {
        version = 1,
        build = function()
            local rows = {}
            local storage = GC.BanBook and GC.BanBook.GetStorage and GC.BanBook:GetStorage() or (GuildCoreDB and GuildCoreDB.banBook) or {}
            for key, entry in pairs(storage or {}) do
                if type(entry) == "table" then
                    ensureRecordAudit(entry, playerFullName())
                    rows[#rows + 1] = {
                        key,
                        entry.name or "",
                        entry.realm or "",
                        entry.reason or "",
                        entry.notes or "",
                        tostring(tonumber(entry.addedAt) or 0),
                        entry.addedBy or "",
                        entry.active == false and "0" or "1",
                        tostring(safeUpdatedAt(entry)),
                        entry.updatedBy or entry.addedBy or "",
                    }
                end
            end
            return serializeRecords(rows)
        end,
        apply = function(payload, peer)
            if not (GC.BanBook and GC.BanBook.GetStorage and GC.BanBook.NormalizeKey) then
                return false, "Ban Book module unavailable."
            end
            local storage = GC.BanBook:GetStorage()
            local changed = 0
            for _, row in ipairs(deserializeRecords(payload)) do
                local key = row[1]
                local normalized = GC.BanBook:NormalizeKey(key)
                if normalized then
                    local remote = {
                        key = normalized,
                        name = row[2] ~= "" and row[2] or normalized:match("^([^%-]+)"),
                        realm = row[3] ~= "" and row[3] or normalized:match("%-(.+)$"),
                        reason = row[4] or "",
                        notes = row[5] or "",
                        addedAt = tonumber(row[6]) or now(),
                        addedBy = row[7] or peer,
                        active = row[8] ~= "0",
                        updatedAt = tonumber(row[9]) or tonumber(row[6]) or now(),
                        updatedBy = row[10] ~= "" and row[10] or peer,
                        sourceVersion = tostring(GC.Version or GC.VERSION or "dev"),
                    }
                    local localEntry = storage[normalized]
                    if type(localEntry) ~= "table" or safeUpdatedAt(remote) > safeUpdatedAt(localEntry) then
                        storage[normalized] = remote
                        changed = changed + 1
                        debugLog("merged banBook", normalized)
                    end
                end
            end
            return true, changed
        end,
    },
    memberMeta = {
        version = 1,
        build = function()
            local rows = {}
            for key, player in pairs((GC.DB and GC.DB.GetPlayers and GC.DB:GetPlayers()) or {}) do
                if type(player) == "table" and player.status == "active" then
                    local officerData = player.officerData or {}
                    local notes = player.notes or {}
                    rows[#rows + 1] = {
                        key,
                        player.classification or "unknown",
                        player.main or "",
                        joinList(player.alts),
                        officerData.discordName or "",
                        officerData.discordVerified and "1" or "0",
                        tostring(tonumber(officerData.joinDate) or 0),
                        notes.custom or "",
                        joinList(notes.tags),
                        tostring(player.points and tonumber(player.points.balance) or 0),
                        tostring(playerSyncTimestamp(player)),
                    }
                end
            end
            return serializeRecords(rows)
        end,
        apply = function(payload, peer)
            local roster = GC.DB and GC.DB.GetPlayers and GC.DB:GetPlayers()
            if not roster then return false, "Roster unavailable." end
            local changed = 0
            for _, row in ipairs(deserializeRecords(payload)) do
                local key = row[1]
                local localPlayer = key and roster[key]
                if type(localPlayer) == "table" then
                    local remoteUpdatedAt = tonumber(row[11]) or 0
                    if remoteUpdatedAt > playerSyncTimestamp(localPlayer) then
                        if row[2] ~= "" and (row[2] ~= "unknown" or (localPlayer.classification or "unknown") == "unknown") then
                            localPlayer.classification = row[2]
                        end
                        if row[3] ~= "" then localPlayer.main = row[3] end
                        localPlayer.alts = localPlayer.alts or {}
                        for altKey in tostring(row[4] or ""):gmatch("([^,]+)") do
                            if roster[altKey] and altKey ~= key and not GC.Utils.ArrayContains(localPlayer.alts, altKey) then
                                localPlayer.alts[#localPlayer.alts + 1] = altKey
                            end
                        end
                        localPlayer.officerData = localPlayer.officerData or {}
                        if row[5] ~= "" then localPlayer.officerData.discordName = row[5] end
                        localPlayer.officerData.discordVerified = row[6] == "1"
                        if tonumber(row[7]) and tonumber(row[7]) > 0 then localPlayer.officerData.joinDate = tonumber(row[7]) end
                        localPlayer.notes = localPlayer.notes or {}
                        if row[8] ~= "" then localPlayer.notes.custom = row[8] end
                        localPlayer.notes.tags = localPlayer.notes.tags or {}
                        for tag in tostring(row[9] or ""):gmatch("([^,]+)") do
                            if not GC.Utils.ArrayContains(localPlayer.notes.tags, tag) then
                                localPlayer.notes.tags[#localPlayer.notes.tags + 1] = tag
                            end
                        end
                        localPlayer.points = localPlayer.points or { balance = 0, lifetime = 0, transactions = {} }
                        localPlayer.points.balance = tonumber(row[10]) or localPlayer.points.balance or 0
                        localPlayer.syncMeta = localPlayer.syncMeta or {}
                        localPlayer.syncMeta.main = remoteUpdatedAt
                        localPlayer.syncMeta.customNote = remoteUpdatedAt
                        localPlayer.updatedAt = remoteUpdatedAt
                        localPlayer.updatedBy = peer
                        changed = changed + 1
                        debugLog("merged memberMeta", key)
                    end
                end
            end
            if GC.AltMain and GC.AltMain.Repair then GC.AltMain:Repair() end
            return true, changed
        end,
    },
}

local function compatible(peer)
    if tonumber(peer.syncSchema) ~= tonumber(GC.SYNC_SCHEMA_VERSION) then
        return false, "sync version"
    end
    if tonumber(peer.dataSchema) ~= tonumber(GC.DATA_SCHEMA_VERSION) then
        return false, "data version"
    end
    return true
end

function Sync:IsEnabled()
    local s, rootSettings = settings()
    return rootSettings.enableSyncModule == true and s.enabled == true
end

function Sync:IsOfficerPeer(sender, channel)
    if not IsInGuild or not IsInGuild() then return false end
    local rankIndex = guildRankIndex(sender)
    if rankIndex ~= nil then
        local _, rootSettings = settings()
        return rankIndex <= (tonumber(rootSettings.officerRankThreshold) or 4)
    end
    return channel == "GUILD" or senderInGuild(sender)
end

function Sync:Send(command, target, channel, ...)
    if not C_ChatInfo or not C_ChatInfo.SendAddonMessage then
        return false, "Addon messages unavailable."
    end
    local payload = command .. "|" .. joinFields(...)
    if channel == "WHISPER" then
        C_ChatInfo.SendAddonMessage(PREFIX, payload, "WHISPER", target)
    else
        C_ChatInfo.SendAddonMessage(PREFIX, payload, channel or "GUILD")
    end
    return true
end

function Sync:Register()
    if self.frame then return end
    self.peers = self.peers or {}
    self.sessions = self.sessions or {}
    self.outbox = self.outbox or {}
    self.outboxHead = self.outboxHead or 1
    self.outboxTail = self.outboxTail or 0
    self.lastAutoSyncAt = self.lastAutoSyncAt or {}

    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
        debugLog("prefix registered", PREFIX)
    end

    local frame = CreateFrame("Frame")
    frame:RegisterEvent("CHAT_MSG_ADDON")
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:SetScript("OnEvent", function(_, event, ...)
        if event == "CHAT_MSG_ADDON" then
            local prefix, payload, channel, sender = ...
            local ok, err = pcall(function() self:OnAddonMessage(prefix, payload, channel, sender) end)
            if not ok then
                debugLog("packet handler failed", tostring(err))
            end
        elseif event == "PLAYER_LOGIN" then
            self:OnLogin()
        end
    end)
    self.frame = frame
    if C_Timer and C_Timer.NewTicker then
        self.cleanupTicker = C_Timer.NewTicker(10, function() self:CleanupTimeouts() end)
    end
end

function Sync:OnLogin()
    self:Register()
    local s = settings()
    if self:IsEnabled() and s.autoOnLogin then
        if C_Timer and C_Timer.After then
            C_Timer.After(8, function() self:SyncNow("login") end)
        else
            self:SyncNow("login")
        end
    end
end

function Sync:BroadcastHello(reason)
    if not self:IsEnabled() then
        return false
    end
    self:Register()
    self:Send("HELLO", nil, "GUILD", GC.Version or GC.VERSION or "dev", GC.SYNC_SCHEMA_VERSION, GC.DATA_SCHEMA_VERSION, reason or "manual")
    self.discoveryStartedAt = now()
    debugLog("HELLO sent", tostring(reason or "manual"))
    return true
end

function Sync:SyncNow(reason)
    if not self:IsEnabled() then
        message("Sync skipped. Officer Data Sync is disabled.")
        return false
    end
    if InCombatLockdown and InCombatLockdown() then
        message("Sync skipped. Try again after combat.")
        return false
    end
    self.synced = 0
    self.skipped = 0
    self.checked = 0
    if GC.Perf then GC.Perf:Snapshot("Sync start") end
    message("Sync started with online Guild Core users.")
    return self:BroadcastHello(reason or "manual")
end

function Sync:StartSession(peerName)
    local peer = self.peers and self.peers[peerName]
    if not peer then return false, "peer not found" end
    local ok, why = compatible(peer)
    self.checked = (self.checked or 0) + 1
    if not ok then
        self.skipped = (self.skipped or 0) + 1
        message("Sync skipped with " .. peerName .. ". Incompatible " .. tostring(why) .. ".")
        debugLog("compat mismatch", peerName, tostring(peer.version), tostring(peer.syncSchema), tostring(peer.dataSchema))
        return false, why
    end
    local last = self.lastAutoSyncAt and self.lastAutoSyncAt[peerName]
    if last and (now() - last) < PEER_COOLDOWN then
        debugLog("peer cooldown", peerName)
        return false, "cooldown"
    end
    local sessionId = tostring(now()) .. tostring(math.random(1000, 9999))
    local expected = 0
    for _ in pairs(DATASETS) do expected = expected + 1 end
    self.sessions[sessionId] = { peer = peerName, outbound = true, inbound = true, startedAt = now(), expected = expected, done = 0, datasets = {} }
    self.lastAutoSyncAt[peerName] = now()
    message("Sync started with " .. peerName .. ".")
    self:Send("SYNC_REQUEST", peerName, "WHISPER", sessionId)
    self:SendAllDatasets(peerName, sessionId)
    return true
end

function Sync:SendDataset(peerName, sessionId, datasetName, dataset)
    local memBefore = GC.Perf and GC.Perf:Snapshot("Sync build " .. tostring(datasetName) .. " before")
    local ok, payloadOrErr = pcall(dataset.build)
    if not ok then
        self:Fail(peerName, sessionId, "serialize failed")
        debugLog("serialize failed", datasetName, tostring(payloadOrErr))
        return
    end
    local payload = payloadOrErr or ""
    if GC.Perf then GC.Perf:Delta("Sync build " .. tostring(datasetName) .. " after", memBefore) end
    local total = math.max(1, math.ceil(#payload / CHUNK_SIZE))
    local sum = checksum(payload)
    self:Send("SYNC_START", peerName, "WHISPER", sessionId, datasetName, dataset.version, total)
    local session = self.sessions and self.sessions[sessionId]
    if session and not session.sendingMessageShown then
        session.sendingMessageShown = true
        message("Sending sync data to " .. peerName .. "...")
    end
    for index = 1, total do
        local chunk = payload:sub(((index - 1) * CHUNK_SIZE) + 1, index * CHUNK_SIZE)
        self:QueueOutbox({ peerName, sessionId, datasetName, index, total, chunk })
    end
    self:QueueOutbox({ peerName, sessionId, datasetName, "END", total, sum })
    self:PumpOutbox()
end

function Sync:QueueOutbox(item)
    self.outbox = self.outbox or {}
    self.outboxTail = (self.outboxTail or 0) + 1
    self.outbox[self.outboxTail] = item
end

function Sync:PumpOutbox()
    if self.sending then return end
    self.sending = true
    local function step()
        local head = self.outboxHead or 1
        if head > (self.outboxTail or 0) then
            self.sending = false
            wipeTable(self.outbox)
            self.outboxHead = 1
            self.outboxTail = 0
            return
        end
        local item = self.outbox[head]
        self.outbox[head] = nil
        self.outboxHead = head + 1
        if not item then
            if C_Timer and C_Timer.After then
                C_Timer.After(0.08, step)
            else
                step()
            end
            return
        end
        local peerName, sessionId, datasetName, index, total, payload = unpack(item)
        wipeTable(item)
        if index == "END" then
            self:Send("SYNC_END", peerName, "WHISPER", sessionId, datasetName, payload)
        else
            self:Send("SYNC_CHUNK", peerName, "WHISPER", sessionId, datasetName, index, total, payload)
            debugLog("chunk sent", datasetName, tostring(index), "/", tostring(total))
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(0.08, step)
        else
            step()
        end
    end
    step()
end

function Sync:SendAllDatasets(peerName, sessionId)
    for name, dataset in pairs(DATASETS) do
        self:SendDataset(peerName, sessionId, name, dataset)
    end
end

function Sync:Fail(peerName, sessionId, reason)
    message("Sync failed with " .. tostring(peerName or "peer") .. ". Reason: " .. tostring(reason or "unknown") .. ".")
    if sessionId and self.sessions then self:ClearSession(sessionId) end
end

function Sync:ClearSession(sessionId)
    local session = self.sessions and self.sessions[sessionId]
    if not session then return end
    for index, item in pairs(self.outbox or {}) do
        if type(item) == "table" and item[2] == sessionId then
            wipeTable(item)
            self.outbox[index] = nil
        end
    end
    if session.datasets then
        for _, dataset in pairs(session.datasets) do
            if dataset.chunks then wipeTable(dataset.chunks) end
            wipeTable(dataset)
        end
        wipeTable(session.datasets)
    end
    wipeTable(session)
    self.sessions[sessionId] = nil
end

function Sync:TryCompleteSession(sessionId, peerName)
    local session = self.sessions and self.sessions[sessionId]
    if not session then return end
    local inboundDone = not session.inbound or session.inboundComplete == true
    local outboundDone = not session.outbound or session.outboundComplete == true
    if inboundDone and outboundDone then
        self.synced = (self.synced or 0) + 1
        message("Sync completed with " .. tostring(peerName or session.peer or "peer") .. ".")
        if GC.Perf then GC.Perf:Snapshot("Sync complete") end
        self:ClearSession(sessionId)
    end
end

function Sync:OnAddonMessage(prefix, payload, channel, sender)
    if prefix ~= PREFIX then return end
    local peerName = normalizeSender(sender)
    if peerName == "" or peerName == playerFullName() then return end
    if not self:IsEnabled() then return end
    if not self:IsOfficerPeer(peerName, channel) then return end

    local command, rest = tostring(payload or ""):match("^([^|]+)|?(.*)$")
    local fields = splitFields(rest or "")
    debugLog("received", tostring(command), "from", peerName)

    if command == "HELLO" then
        self.peers[peerName] = {
            version = fields[1],
            syncSchema = tonumber(fields[2]),
            dataSchema = tonumber(fields[3]),
            seenAt = now(),
        }
        self:Send("HELLO_ACK", peerName, "WHISPER", GC.Version or GC.VERSION or "dev", GC.SYNC_SCHEMA_VERSION, GC.DATA_SCHEMA_VERSION)
        local ok, why = compatible(self.peers[peerName])
        if not ok then
            message("Sync skipped. " .. peerName .. " is using incompatible version " .. tostring(fields[1] or "unknown") .. ".")
            debugLog("HELLO incompatible", peerName, tostring(why))
            return
        end
        local s = settings()
        if s.autoOnPeerDetected then
            self:StartSession(peerName)
        end
    elseif command == "HELLO_ACK" then
        self.peers[peerName] = {
            version = fields[1],
            syncSchema = tonumber(fields[2]),
            dataSchema = tonumber(fields[3]),
            seenAt = now(),
        }
        local ok, why = compatible(self.peers[peerName])
        if ok then
            self:StartSession(peerName)
        else
            self.skipped = (self.skipped or 0) + 1
            message("Sync skipped. " .. peerName .. " is using incompatible version " .. tostring(fields[1] or "unknown") .. ".")
            debugLog("HELLO_ACK incompatible", peerName, tostring(why))
        end
    elseif command == "SYNC_REQUEST" then
        local sessionId = fields[1]
        local peer = self.peers[peerName]
        if not peer then
            self:Send("HELLO_ACK", peerName, "WHISPER", GC.Version or GC.VERSION or "dev", GC.SYNC_SCHEMA_VERSION, GC.DATA_SCHEMA_VERSION)
            return
        end
        local ok, why = compatible(peer)
        if not ok then
            self:Send("SYNC_FAIL", peerName, "WHISPER", sessionId, "incompatible " .. tostring(why))
            message("Sync skipped with " .. peerName .. ". Incompatible sync version.")
            return
        end
        local expected = 0
        for _ in pairs(DATASETS) do expected = expected + 1 end
        local session = self.sessions[sessionId] or { peer = peerName, startedAt = now(), datasets = {} }
        session.peer = peerName
        session.inbound = true
        session.outbound = true
        session.expected = expected
        session.done = session.done or 0
        session.datasets = session.datasets or {}
        self.sessions[sessionId] = session
        self:SendAllDatasets(peerName, sessionId)
    elseif command == "SYNC_START" then
        local sessionId, datasetName, version, chunkTotal = fields[1], fields[2], tonumber(fields[3]), tonumber(fields[4])
        local dataset = DATASETS[datasetName]
        if not dataset or dataset.version ~= version then
            self:Fail(peerName, sessionId, "invalid dataset")
            return
        end
        self.sessions[sessionId] = self.sessions[sessionId] or { peer = peerName, startedAt = now(), datasets = {} }
        local session = self.sessions[sessionId]
        session.inbound = true
        session.datasets = session.datasets or {}
        session.datasets[datasetName] = { total = chunkTotal or 0, chunks = {}, received = 0, version = version }
        if not session.receivingMessageShown then
            session.receivingMessageShown = true
            message("Receiving sync data from " .. peerName .. "...")
        end
    elseif command == "SYNC_CHUNK" then
        local sessionId, datasetName, index, total, chunk = fields[1], fields[2], tonumber(fields[3]), tonumber(fields[4]), fields[5] or ""
        local session = self.sessions and self.sessions[sessionId]
        local dataset = session and session.datasets and session.datasets[datasetName]
        if not dataset or not index or not total or total ~= dataset.total then return end
        if not dataset.chunks[index] then
            dataset.received = dataset.received + 1
        end
        dataset.chunks[index] = chunk
        debugLog("chunk received", datasetName, tostring(index), "/", tostring(total))
        if index == 1 and GC.Perf then GC.Perf:Snapshot("Sync receive chunks " .. tostring(datasetName)) end
    elseif command == "SYNC_END" then
        local sessionId, datasetName, expectedChecksum = fields[1], fields[2], fields[3]
        local session = self.sessions and self.sessions[sessionId]
        local inbound = session and session.datasets and session.datasets[datasetName]
        local dataset = DATASETS[datasetName]
        if not inbound or not dataset then
            self:Fail(peerName, sessionId, "missing dataset")
            return
        end
        if inbound.received ~= inbound.total then
            self:Fail(peerName, sessionId, "missing chunks")
            return
        end
        local chunks = {}
        for i = 1, inbound.total do
            if inbound.chunks[i] == nil then
                self:Fail(peerName, sessionId, "missing chunk " .. tostring(i))
                return
            end
            chunks[#chunks + 1] = inbound.chunks[i]
        end
        local data = table.concat(chunks)
        wipeTable(chunks)
        if checksum(data) ~= expectedChecksum then
            data = nil
            self:Fail(peerName, sessionId, "checksum mismatch")
            return
        end
        local memBefore = GC.Perf and GC.Perf:Snapshot("Sync merge " .. tostring(datasetName) .. " before")
        local ok, resultOrErr, changed = pcall(dataset.apply, data, peerName)
        data = nil
        if not ok or resultOrErr ~= true then
            self:Fail(peerName, sessionId, tostring(changed or resultOrErr or "merge failed"))
            return
        end
        if GC.Perf then GC.Perf:Delta("Sync merge " .. tostring(datasetName) .. " after", memBefore) end
        debugLog("dataset applied", datasetName, tostring(changed or 0))
        if inbound.chunks then wipeTable(inbound.chunks) end
        wipeTable(inbound)
        session.datasets[datasetName] = nil
        session.appliedCount = (session.appliedCount or 0) + 1
        self:Send("SYNC_DONE", peerName, "WHISPER", sessionId, datasetName)
        local expected = 0
        for _ in pairs(DATASETS) do expected = expected + 1 end
        if session.appliedCount >= expected then
            session.inboundComplete = true
            self:TryCompleteSession(sessionId, peerName)
        end
    elseif command == "SYNC_DONE" then
        local sessionId = fields[1]
        local session = self.sessions and self.sessions[sessionId]
        if session then
            session.done = (session.done or 0) + 1
            if session.done >= (session.expected or 1) then
                session.outboundComplete = true
                self:TryCompleteSession(sessionId, peerName)
            end
        end
    elseif command == "SYNC_FAIL" then
        self:Fail(peerName, fields[1], fields[2] or "remote failure")
    end
end

function Sync:CleanupTimeouts()
    local cutoff = now() - SESSION_TIMEOUT
    for sessionId, session in pairs(self.sessions or {}) do
        if (session.startedAt or 0) < cutoff then
            self:Fail(session.peer, sessionId, "timeout")
        end
    end
    local peerCutoff = now() - 3600
    for peerName, peer in pairs(self.peers or {}) do
        if (peer.seenAt or 0) < peerCutoff then
            self.peers[peerName] = nil
            if self.lastAutoSyncAt then self.lastAutoSyncAt[peerName] = nil end
        end
    end
    if GC.Perf then GC.Perf:Snapshot("Sync timeout cleanup") end
end

function Sync:GetStats()
    local sessions, chunks = 0, 0
    for _, session in pairs(self.sessions or {}) do
        sessions = sessions + 1
        for _, dataset in pairs(session.datasets or {}) do
            chunks = chunks + (dataset.received or 0)
        end
    end
    local outbox = 0
    for _ in pairs(self.outbox or {}) do outbox = outbox + 1 end
    return {
        sessions = sessions,
        bufferedChunks = chunks,
        outbox = outbox,
    }
end

function Sync:QueueOutboundChange(payload)
    local guild = GC.DB:GetGuild()
    if not guild then return false end
    guild.sync = guild.sync or {}
    guild.sync.outboundQueue = guild.sync.outboundQueue or {}
    table.insert(guild.sync.outboundQueue, payload)
    return true
end

Sync:Register()
GC:RegisterService("Sync", Sync)

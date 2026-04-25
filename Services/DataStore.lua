-- Services/DataStore.lua
-- Clean read/write layer over the raw Database. UI and modules use this
-- instead of touching GuildCoreDB directly.
local addonName, ns = ...
local GC = ns.GuildCore

GC.Services           = GC.Services or {}
GC.Services.DataStore = {}
local DS              = GC.Services.DataStore

-- Internal: resolve the current guild DB table.
local function guild() return GC.DB:GetGuild() end

-- Return the current guild's player table, or nil.
function DS:GetPlayers()
    local db = guild()
    return db and db.players or nil
end

-- Return a single player by key, or nil.
function DS:GetPlayer(key)
    local players = self:GetPlayers()
    return players and players[key] or nil
end

-- Upsert a player record. Merges provided fields; never overwrites with nil.
function DS:SavePlayer(key, fields)
    local db = guild()
    if not db then return end
    db.players = db.players or {}
    local p = db.players[key] or {key = key}
    for k, v in pairs(fields) do
        if v ~= nil then p[k] = v end
    end
    db.players[key] = p
end

-- Return the addon log array for the current guild.
function DS:GetLogs()
    local db = guild()
    return db and db.logs or nil
end

-- Append a log entry (table). Enforces a max of 2000 entries.
function DS:AppendLog(entry)
    local db = guild()
    if not db then return end
    db.logs = db.logs or {}
    table.insert(db.logs, entry)
    while #db.logs > 2000 do
        table.remove(db.logs, 1)
    end
end

function DS:ClearLogs()
    local db = guild()
    if not db then return false end
    db.logs = {}
    return true
end

function DS:GetGuildBankState()
    local db = guild()
    if not db then return nil end
    db.bank = db.bank or {}
    db.bank.entries = db.bank.entries or {}
    db.bank.seenKeys = db.bank.seenKeys or {}
    return db.bank
end

function DS:GetGuildBankEntries()
    local bank = self:GetGuildBankState()
    return bank and bank.entries or nil
end

function DS:HasGuildBankEntry(signature)
    local bank = self:GetGuildBankState()
    if not bank or not signature then
        return false
    end
    return bank.seenKeys and bank.seenKeys[signature] == true
end

function DS:AppendGuildBankEntry(entry)
    local bank = self:GetGuildBankState()
    if not bank or not entry or not entry.signature then
        return false
    end

    if bank.seenKeys[entry.signature] then
        return false
    end

    bank.entries[#bank.entries + 1] = entry
    bank.seenKeys[entry.signature] = true
    bank.lastCapturedAt = entry.capturedAt or time()

    while #bank.entries > 1000 do
        local removed = table.remove(bank.entries, 1)
        if removed and removed.signature then
            bank.seenKeys[removed.signature] = nil
        end
    end

    return true
end

-- Return the current settings table (live reference — do not cache).
function DS:GetSettings()
    return GC.DB:GetSettings()
end

-- Write one setting key=value.
function DS:SetSetting(key, value)
    local s = GC.DB:GetSettings()
    if s then s[key] = value end
end

-- Return the last stored roster snapshot (stored under guild.snapshots.latest).
function DS:GetLastSnapshot()
    local db = guild()
    return db and db.snapshots and db.snapshots.latest or nil
end

-- Persist a roster snapshot under guild.snapshots.latest.
function DS:SaveSnapshot(snapshot)
    local db = guild()
    if not db then return end
    db.snapshots = db.snapshots or {}
    db.snapshots.latest = snapshot
end

function DS:GetScanHistory()
    local db = guild()
    if not db then return nil end
    db.scans = db.scans or {}
    db.scans.history = db.scans.history or {}
    return db.scans.history
end

function DS:AppendScanSummary(summary)
    local history = self:GetScanHistory()
    if not history then return end

    table.insert(history, summary)
    while #history > 100 do
        table.remove(history, 1)
    end
end

function DS:GetLatestScanSummary()
    local history = self:GetScanHistory()
    if not history or #history == 0 then
        return nil
    end
    return history[#history]
end

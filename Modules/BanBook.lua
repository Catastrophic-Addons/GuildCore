-- /GuildCore/Modules/BanBook.lua
-- Central moderation blacklist used by invite and future onboarding flows.
local addonName, ns = ...
local GC = ns.GuildCore

GC.BanBook = GC.BanBook or {}
local BanBook = GC.BanBook

local function trim(value)
    return GC.Utils and GC.Utils.Trim and GC.Utils.Trim(value or "") or tostring(value or ""):match("^%s*(.-)%s*$")
end

local function titleToken(value)
    value = trim(value):gsub("%s+", "")
    if value == "" then
        return ""
    end
    local lower = value:lower()
    return lower:sub(1, 1):upper() .. lower:sub(2)
end

local function splitKey(value)
    local name, realm = tostring(value or ""):match("^%s*([^%-]+)%-(.+)%s*$")
    if name and realm then
        return name, realm
    end
    return value, nil
end

local function now()
    return GC.Utils and GC.Utils.Now and GC.Utils.Now() or time()
end

local function currentOfficer()
    local name, realm
    if UnitFullName then
        name, realm = UnitFullName("player")
    elseif UnitName then
        name = UnitName("player")
    end
    name = trim(name)
    realm = trim(realm)
    if name == "" then
        return "Unknown"
    end
    return realm ~= "" and string.format("%s-%s", name, realm:gsub("%s+", "")) or name
end

function BanBook:Init()
    local root = GC.DB and GC.DB.GetRoot and GC.DB:GetRoot() or GuildCoreDB
    if type(root) ~= "table" then
        GuildCoreDB = GuildCoreDB or {}
        root = GuildCoreDB
    end
    if type(root.banBook) ~= "table" then
        root.banBook = {}
    end
    self.entries = root.banBook
    return self.entries
end

function BanBook:GetStorage()
    if type(self.entries) ~= "table" then
        return self:Init()
    end
    return self.entries
end

function BanBook:NormalizeKey(name, realm)
    if realm == nil then
        name, realm = splitKey(name)
    end

    local cleanName = titleToken(name)
    local cleanRealm = titleToken(realm)
    if cleanRealm == "" then
        cleanRealm = titleToken((GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or "")
    end
    if cleanName == "" or cleanRealm == "" then
        return nil, cleanName, cleanRealm
    end

    return string.format("%s-%s", cleanName, cleanRealm), cleanName, cleanRealm
end

function BanBook:Add(name, realm, reason, notes)
    local key, cleanName, cleanRealm = self:NormalizeKey(name, realm)
    if not key then
        return false, "Character name and realm are required."
    end

    local entries = self:GetStorage()
    local existing = type(entries[key]) == "table" and entries[key] or nil
    local reasonText = trim(reason)
    local notesText = trim(notes)

    local active = true
    if existing and existing.active ~= nil then
        active = existing.active ~= false
    end

    entries[key] = {
        name = cleanName,
        realm = cleanRealm,
        key = key,
        reason = reasonText ~= "" and reasonText or (existing and existing.reason) or "",
        notes = notesText ~= "" and notesText or (existing and existing.notes) or "",
        addedAt = now(),
        addedBy = existing and trim(existing.addedBy) ~= "" and existing.addedBy or currentOfficer(),
        active = active,
    }

    return true, entries[key], existing ~= nil
end

function BanBook:Remove(key)
    local normalized = self:NormalizeKey(key)
    if not normalized then
        return false, "Ban Book entry is unavailable."
    end
    local entries = self:GetStorage()
    if not entries[normalized] then
        return false, "Ban Book entry was not found."
    end
    entries[normalized] = nil
    return true
end

function BanBook:Update(key, data)
    local normalized = self:NormalizeKey(key)
    if not normalized then
        return false, "Ban Book entry is unavailable."
    end

    local entries = self:GetStorage()
    local entry = type(entries[normalized]) == "table" and entries[normalized] or nil
    if not entry then
        return false, "Ban Book entry was not found."
    end

    data = type(data) == "table" and data or {}
    if data.name or data.realm then
        local newKey, cleanName, cleanRealm = self:NormalizeKey(data.name or entry.name, data.realm or entry.realm)
        if not newKey then
            return false, "Character name and realm are required."
        end
        if newKey ~= normalized and entries[newKey] ~= nil then
            return false, "Another Ban Book entry already exists for that character."
        end
        if newKey ~= normalized then
            entries[normalized] = nil
            normalized = newKey
            entries[normalized] = entry
        end
        entry.name = cleanName
        entry.realm = cleanRealm
        entry.key = normalized
    end
    if data.reason ~= nil then entry.reason = trim(data.reason) end
    if data.notes ~= nil then entry.notes = trim(data.notes) end
    if data.active ~= nil then entry.active = data.active == true end
    entry.updatedAt = now()
    entry.updatedBy = currentOfficer()
    return true, entry
end

function BanBook:GetEntry(name, realm)
    local key = self:NormalizeKey(name, realm)
    local entry = key and self:GetStorage()[key] or nil
    if type(entry) ~= "table" then
        return nil
    end
    entry.key = entry.key or key
    entry.name = entry.name or (key and key:match("^([^%-]+)"))
    entry.realm = entry.realm or (key and key:match("%-(.+)$"))
    if entry.active == nil then
        entry.active = true
    end
    return entry
end

function BanBook:IsBanned(name, realm)
    local entry = self:GetEntry(name, realm)
    return entry ~= nil and entry.active ~= false, entry
end

function BanBook:GetAll()
    local rows = {}
    for key, entry in pairs(self:GetStorage()) do
        if type(entry) == "table" then
            entry.key = entry.key or key
            rows[#rows + 1] = entry
        end
    end
    table.sort(rows, function(a, b)
        return tostring(a.key or "") < tostring(b.key or "")
    end)
    return rows
end

function BanBook:InviteBlockMessage(name, realm)
    local banned, entry = self:IsBanned(name, realm)
    if not banned then
        return nil
    end
    return string.format("Cannot invite %s. Character is listed in Ban Book.", entry.key or tostring(name or "this character")), entry
end

BanBook:Init()

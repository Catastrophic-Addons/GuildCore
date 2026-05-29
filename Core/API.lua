-- Core/API.lua
-- GuildCore compatibility wrapper for WoW API changes.

local addonName, ns = ...
local GC = ns.GuildCore

GC.API = GC.API or {}

local API = GC.API

local function normalizeRealmName(realm)
    realm = realm or (GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName() or ""
    return tostring(realm):gsub("%s+", "")
end

local function splitPlayerName(name)
    if not name or name == "" then
        return nil, nil
    end

    local shortName, realm = tostring(name):match("^([^%-]+)%-(.+)$")
    if shortName and realm then
        return shortName, normalizeRealmName(realm)
    end

    return tostring(name), nil
end

local function trimString(value)
    if value == nil then
        return ""
    end
    return tostring(value):match("^%s*(.-)%s*$") or ""
end

local function firstNonEmptyString(...)
    for i = 1, select("#", ...) do
        local value = trimString(select(i, ...))
        if value ~= "" then
            return value
        end
    end
    return ""
end

function API.NormalizePlayerName(name, fallbackRealm)
    local shortName, realm = splitPlayerName(name)
    if not shortName or shortName == "" then
        return nil
    end

    return string.format("%s-%s", shortName, normalizeRealmName(realm or fallbackRealm))
end

function API.FormatNameForGuildInvite(name, fallbackRealm)
    local shortName, realm = splitPlayerName(name)
    if not shortName or shortName == "" then
        return nil
    end
    if realm or fallbackRealm then
        realm = normalizeRealmName(realm or fallbackRealm)
    end

    if realm and realm == normalizeRealmName() then
        return shortName
    end

    return realm and string.format("%s-%s", shortName, realm) or shortName
end

function API.GuildInvite(name, realm)
    local inviteName = API.FormatNameForGuildInvite(name, realm)
    if not inviteName then
        return false, "No player name supplied."
    end

    -- Ban Book is the final shared guard for every current and future guild
    -- invite path routed through Guild Core.
    if GC.BanBook and GC.BanBook.InviteBlockMessage then
        local message, entry = GC.BanBook:InviteBlockMessage(name, realm)
        if message then
            GC:InviteDebug("warn", "Skipped banned character:", tostring(entry and entry.key or name))
            return false, message
        end
    end

    local fn = C_GuildInfo and C_GuildInfo.Invite or GuildInvite
    if not fn then
        return false, "No guild invite API is available."
    end

    local ok, result = pcall(fn, inviteName)
    if not ok then
        return false, tostring(result)
    end

    return true
end

function API.SetWhoToUi(enabled)
    if C_FriendList and C_FriendList.SetWhoToUi then
        return C_FriendList.SetWhoToUi(enabled and true or false)
    end
end

function API.SendWho(query)
    query = GC.Utils and GC.Utils.Trim(query or "") or tostring(query or "")
    if query == "" then
        return false, "WHO query is empty."
    end

    if not (C_FriendList and C_FriendList.SendWho) then
        return false, "C_FriendList.SendWho is unavailable."
    end

    -- Requires in-game testing: C_FriendList.SendWho is documented as NOT
    -- hardware-event restricted on Retail (unlike spell casts), but may be
    -- throttled server-side. Use pcall to capture any unexpected Lua errors.
    local ok, err = pcall(C_FriendList.SendWho, query)
    if not ok then
        -- Surface the exact error so it appears in the addon error log.
        GC:Print("Invite scan SendWho error:", tostring(err))
        return false, tostring(err)
    end

    return true
end

function API.GetNumWhoResults()
    if C_FriendList and C_FriendList.GetNumWhoResults then
        local total, shown = C_FriendList.GetNumWhoResults()
        return total or 0, shown or 0
    end

    return 0, 0
end

function API.GetWhoInfo(index)
    if not (C_FriendList and C_FriendList.GetWhoInfo) then
        return nil
    end

    local info = C_FriendList.GetWhoInfo(index)
    if type(info) ~= "table" then
        return info
    end

    local guild = firstNonEmptyString(info.fullGuildName, info.Guild, info.guild)

    return {
        name = info.fullName or info.Name or info.name,
        normalizedName = API.NormalizePlayerName(info.fullName or info.Name or info.name),
        guild = guild,
        level = info.level or info.Level or 0,
        race = info.raceStr or info.Race or info.race or "",
        class = info.classStr or info.Class or info.class or "",
        zone = info.area or info.Zone or info.zone or "",
        classFileName = info.filename or info.NoLocaleClass or info.classFileName,
        gender = info.gender or info.Sex,
        raw = info,
    }
end

function API.GuildRoster()
    if C_GuildInfo and C_GuildInfo.GuildRoster then
        return C_GuildInfo.GuildRoster()
    end

    if GuildRoster then
        return GuildRoster()
    end

    return nil
end

function API.GetGuildRosterInfo(index)
    if C_GuildInfo and C_GuildInfo.GetGuildRosterInfo then
        local info = C_GuildInfo.GetGuildRosterInfo(index)
        if type(info) == "table" then
            return info.name,
                info.rankName,
                info.rankOrder or info.rankIndex,
                info.level,
                info.className,
                info.area,
                info.note,
                info.officerNote,
                info.isOnline,
                info.status,
                info.classFilename,
                info.achievementPoints,
                info.achievementRank,
                info.isMobile,
                info.canSoR,
                info.reputation,
                info.yearsOffline or info.offlineYears,
                info.monthsOffline or info.offlineMonths,
                info.daysOffline or info.offlineDays,
                info.hoursOffline or info.offlineHours,
                info.guid or info.GUID or info.playerGUID or info.memberGUID or info.guildMemberGUID or info.clubMemberGUID
        end
        return info
    end

    if GetGuildRosterInfo then
        return GetGuildRosterInfo(index)
    end

    return nil
end

function API.GetGuildRosterLastOnline(index)
    if C_GuildInfo and C_GuildInfo.GetGuildRosterLastOnline then
        return C_GuildInfo.GetGuildRosterLastOnline(index)
    end

    if GetGuildRosterLastOnline then
        return GetGuildRosterLastOnline(index)
    end

    return nil
end

function API.GetNumGuildMembers()
    if GetNumGuildMembers then
        local total, online, onlineAndMobile = GetNumGuildMembers()
        return total or 0, online or 0, onlineAndMobile or 0
    end

    return 0, 0, 0
end

function API.CanSpeakInGuildChat()
    if not IsInGuild or not IsInGuild() then
        return false
    end

    if C_GuildInfo and C_GuildInfo.CanSpeakInGuildChat then
        local ok, allowed = pcall(C_GuildInfo.CanSpeakInGuildChat)
        if ok then
            return allowed == true
        end
    end

    return true
end

function API.SendGuildMessage(message)
    if type(message) ~= "string" or message == "" then
        return false, "Guild message is empty."
    end

    local messages = GC.Services and GC.Services.Messages
    if messages and messages.QueueGuildMessage then
        return messages:QueueGuildMessage(message, { autoSend = true })
    end

    if not SendChatMessage then
        return false, "SendChatMessage is unavailable."
    end

    local ok, err = pcall(SendChatMessage, message, "GUILD")
    if not ok then
        return false, tostring(err)
    end
    return true
end

function API.SetGuildRosterShowOffline(showOffline)
    if C_GuildInfo and C_GuildInfo.SetGuildRosterShowOffline then
        return C_GuildInfo.SetGuildRosterShowOffline(showOffline)
    end

    if SetGuildRosterShowOffline then
        return SetGuildRosterShowOffline(showOffline)
    end
end

local function normalizeNameForRosterLookup(name)
    if not name or name == "" then
        return nil
    end
    local shortName = tostring(name):match("^([^%-]+)") or tostring(name)
    return shortName:lower()
end

local function extractRosterGuid(info)
    if type(info) ~= "table" then
        return nil
    end

    return info.guid
        or info.GUID
        or info.playerGUID
        or info.memberGUID
        or info.guildMemberGUID
        or info.clubMemberGUID
end

function API.FindGuildRosterIndex(name)
    if not GetNumGuildMembers then
        return nil
    end
    local target = normalizeNameForRosterLookup(name)
    if not target then
        return nil
    end
    for index = 1, GetNumGuildMembers() do
        local fullName
        if C_GuildInfo and C_GuildInfo.GetGuildRosterInfo then
            local info = C_GuildInfo.GetGuildRosterInfo(index)
            fullName = type(info) == "table" and info.name or nil
        end
        if (not fullName or fullName == "") and GetGuildRosterInfo then
            fullName = GetGuildRosterInfo(index)
        end
        if normalizeNameForRosterLookup(fullName) == target then
            return index
        end
    end
    return nil
end

function API.FindGuildRosterGuid(name)
    if not GetNumGuildMembers then
        return nil
    end
    local target = normalizeNameForRosterLookup(name)
    if not target then
        return nil
    end

    for index = 1, GetNumGuildMembers() do
        if C_GuildInfo and C_GuildInfo.GetGuildRosterInfo then
            local info = C_GuildInfo.GetGuildRosterInfo(index)
            if type(info) == "table" and normalizeNameForRosterLookup(info.name) == target then
                local guid = extractRosterGuid(info)
                if guid and guid ~= "" then
                    return guid
                end
            end
        end

        if GetGuildRosterInfo then
            local fullName = GetGuildRosterInfo(index)
            if normalizeNameForRosterLookup(fullName) == target then
                local guid = select(17, GetGuildRosterInfo(index))
                if guid and guid ~= "" then
                    return guid
                end
            end
        end
    end
    return nil
end

function API.GetGuildMemberNote(name, officer)
    local index = API.FindGuildRosterIndex(name)
    if not index then
        return nil, "Guild roster entry was not found."
    end

    local _, _, _, _, _, _, publicNote, officerNote = API.GetGuildRosterInfo(index)
    local value = officer and officerNote or publicNote
    return tostring(value or "")
end

function API.SetGuildMemberNote(name, note, officer)
    local index = API.FindGuildRosterIndex(name)
    if not index then
        return false, "Guild roster entry was not found."
    end
    note = tostring(note or "")
    local beforeNote = API.GetGuildMemberNote(name, officer)
    if beforeNote == note then
        return true
    end

    local missingModernGuid = false
    local attempted = false
    if C_GuildInfo and C_GuildInfo.SetNote then
        local guid = API.FindGuildRosterGuid(name)
        if guid then
            local ok, err = pcall(C_GuildInfo.SetNote, guid, note, officer ~= true)
            if not ok then
                return false, tostring(err)
            end
            attempted = true
        else
            missingModernGuid = true
        end
    end

    if not attempted then
        local fn = officer and GuildRosterSetOfficerNote or GuildRosterSetPublicNote
        if not fn then
            if missingModernGuid then
                return false, "Guild roster GUID was unavailable. Refresh the roster and try again."
            end
            return false, officer and "Officer note API is unavailable." or "Public note API is unavailable."
        end
        local ok, err = pcall(fn, index, note)
        if not ok then
            return false, tostring(err)
        end
        attempted = true
    end

    if attempted and API.GuildRoster then
        API.GuildRoster()
    end

    local afterNote, readErr = API.GetGuildMemberNote(name, officer)
    if afterNote == note then
        return true
    end

    -- Protected note calls can fail silently when the target is at the same
    -- guild rank or higher. Re-read the roster note so the UI does not report
    -- a successful save that Blizzard rejected.
    if afterNote ~= nil then
        return false, "Unable to update this character's note. Your guild rank may not have permission to edit notes for members at this rank or higher."
    end

    return false, readErr or "Unable to verify that the guild note was saved."
end

function API.GetItemInfo(item)
    if C_Item and C_Item.GetItemInfo then
        return C_Item.GetItemInfo(item)
    end

    if GetItemInfo then
        return GetItemInfo(item)
    end

    return nil
end

function API.GetItemCount(item, includeBank, includeUses, includeReagentBank)
    if C_Item and C_Item.GetItemCount then
        return C_Item.GetItemCount(item, includeBank, includeUses, includeReagentBank)
    end

    if GetItemCount then
        return GetItemCount(item, includeBank, includeUses, includeReagentBank)
    end

    return 0
end

function API.GetContainerNumSlots(bagID)
    if C_Container and C_Container.GetContainerNumSlots then
        return C_Container.GetContainerNumSlots(bagID)
    end

    if GetContainerNumSlots then
        return GetContainerNumSlots(bagID)
    end

    return 0
end

function API.GetContainerItemInfo(bagID, slotIndex)
    if C_Container and C_Container.GetContainerItemInfo then
        return C_Container.GetContainerItemInfo(bagID, slotIndex)
    end

    if GetContainerItemInfo then
        return GetContainerItemInfo(bagID, slotIndex)
    end

    return nil
end

function API.PickupContainerItem(bagID, slotIndex)
    if C_Container and C_Container.PickupContainerItem then
        return C_Container.PickupContainerItem(bagID, slotIndex)
    end

    if PickupContainerItem then
        return PickupContainerItem(bagID, slotIndex)
    end
end

function API.GetSpellInfo(spellID)
    if C_Spell and C_Spell.GetSpellInfo then
        return C_Spell.GetSpellInfo(spellID)
    end

    if GetSpellInfo then
        return GetSpellInfo(spellID)
    end

    return nil
end

function API.IsSpellKnown(spellID, isPet)
    if C_Spell and C_Spell.IsSpellKnown then
        return C_Spell.IsSpellKnown(spellID, isPet)
    end

    if IsSpellKnown then
        return IsSpellKnown(spellID, isPet)
    end

    return false
end

function API.GuildPromote(name)
    -- Modern WoW blocks addon-driven rank changes. Use
    -- GC.Services.OperationsMacro to write /gpromote into a user-clicked macro.
    return nil, "Guild rank changes require a user-executed macro."
end

function API.GuildDemote(name)
    -- Modern WoW blocks addon-driven rank changes. Use
    -- GC.Services.OperationsMacro to write /gdemote into a user-clicked macro.
    return nil, "Guild rank changes require a user-executed macro."
end

function API.CanGuildRemove()
    if CanGuildRemove then
        return CanGuildRemove()
    end
    return false
end

function API.GuildUninvite(name)
    -- Guild removal is protected in modern WoW. GuildCore intentionally does
    -- not call GuildUninvite/GuildRemove directly; use a user-clicked /gremove
    -- macro through the purge service instead.
    return nil, "Guild removal requires a user-executed /gremove macro."
end

function API.InviteUnit(name)
    if InviteUnit then
        return InviteUnit(name)
    end
end

function API.QueryGuildBankLog(tab)
    if QueryGuildBankLog then
        return QueryGuildBankLog(tab)
    end
end

function API.GetNumGuildBankTabs()
    if GetNumGuildBankTabs then
        return GetNumGuildBankTabs()
    end
    return 0
end

function API.GetNumGuildBankTransactions(tab)
    if GetNumGuildBankTransactions then
        return GetNumGuildBankTransactions(tab)
    end
    return 0
end

function API.GetGuildBankTransaction(tab, index)
    if GetGuildBankTransaction then
        return GetGuildBankTransaction(tab, index)
    end
    return nil
end

function API.GetNumGuildBankMoneyTransactions()
    if GetNumGuildBankMoneyTransactions then
        return GetNumGuildBankMoneyTransactions()
    end
    return 0
end

function API.GetGuildBankMoneyTransaction(index)
    if GetGuildBankMoneyTransaction then
        return GetGuildBankMoneyTransaction(index)
    end
    return nil
end

function API.GetGuildBankTabInfo(tab)
    if GetGuildBankTabInfo then
        return GetGuildBankTabInfo(tab)
    end
    return nil
end

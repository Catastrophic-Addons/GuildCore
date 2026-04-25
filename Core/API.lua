-- Core/API.lua
-- GuildCore compatibility wrapper for WoW API changes.

local addonName, ns = ...
local GC = ns.GuildCore

GC.API = GC.API or {}

local API = GC.API

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
                info.reputation
        end
        return info
    end

    if GetGuildRosterInfo then
        return GetGuildRosterInfo(index)
    end

    return nil
end

function API.SetGuildRosterShowOffline(showOffline)
    if C_GuildInfo and C_GuildInfo.SetGuildRosterShowOffline then
        return C_GuildInfo.SetGuildRosterShowOffline(showOffline)
    end

    if SetGuildRosterShowOffline then
        return SetGuildRosterShowOffline(showOffline)
    end
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
    if GuildPromote then
        return GuildPromote(name)
    end
end

function API.GuildDemote(name)
    if GuildDemote then
        return GuildDemote(name)
    end
end

function API.GuildUninvite(name)
    if GuildUninvite then
        return GuildUninvite(name)
    end
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

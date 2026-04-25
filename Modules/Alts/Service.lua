local addonName, ns = ...
local GC = ns.GuildCore

local AltService = {}
AltService.__index = AltService

local function players()
    return GC.DB:GetPlayers()
end

local function getPlayer(key)
    local roster = players()
    return roster and roster[key] or nil
end

local function ensureRelationshipFields(player)
    player.alts = player.alts or {}
    player.classification = player.classification or "unknown"
    player.promptState = player.promptState or {}
end

local function completePrompt(player)
    ensureRelationshipFields(player)
    player.promptState.dismissedAt = GC.Utils.Now()
    player.promptState.completedAt = GC.Utils.Now()
    player.promptState.bootstrapSuppressed = nil
end

local function appendLog(eventType, playerKey, oldValue, newValue, reason)
    local logs = GC.DB:GetLogs()
    if not logs then
        return
    end

    logs[#logs + 1] = {
        timestamp = GC.Utils.Now(),
        event = eventType,
        playerKey = playerKey,
        oldValue = oldValue,
        newValue = newValue,
        reason = reason,
    }
end

local function detachFromCurrentMain(playerKey)
    local player = getPlayer(playerKey)
    if not player or not player.main then
        return
    end

    local currentMain = getPlayer(player.main)
    if currentMain then
        currentMain.alts = currentMain.alts or {}
        GC.Utils.RemoveArrayValue(currentMain.alts, playerKey)
    end

    player.main = nil
end

function AltService:ValidateLink(mainKey, altKey)
    if not mainKey or not altKey then
        return false, "Both characters must be specified."
    end

    if mainKey == altKey then
        return false, "A character cannot link to itself."
    end

    local mainPlayer = getPlayer(mainKey)
    if not mainPlayer then
        return false, "Main character is unknown."
    end

    local altPlayer = getPlayer(altKey)
    if not altPlayer then
        return false, "Alt character is unknown."
    end

    ensureRelationshipFields(mainPlayer)
    ensureRelationshipFields(altPlayer)

    if mainPlayer.status ~= "active" then
        return false, "Main character is no longer in the tracked roster."
    end

    if altPlayer.status ~= "active" then
        return false, "Alt character is no longer in the tracked roster."
    end

    if mainPlayer.main then
        return false, "The selected main is already linked as an alt."
    end

    if altPlayer.alts and #altPlayer.alts > 0 then
        return false, "An alt cannot own other alts. Clear those links first."
    end

    local cursor = mainPlayer
    while cursor do
        if cursor.key == altKey then
            return false, "That link would create a circular relationship."
        end
        if not cursor.main then
            break
        end
        cursor = getPlayer(cursor.main)
    end

    return true
end

function AltService:LinkAlt(mainKey, altKey, reason)
    local ok, err = self:ValidateLink(mainKey, altKey)
    if not ok then
        return false, err
    end

    local mainPlayer = getPlayer(mainKey)
    local altPlayer = getPlayer(altKey)
    ensureRelationshipFields(mainPlayer)
    ensureRelationshipFields(altPlayer)

    detachFromCurrentMain(altKey)

    mainPlayer.classification = "main"
    altPlayer.classification = "alt"
    altPlayer.main = mainKey
    completePrompt(altPlayer)
    mainPlayer.promptState.dismissedAt = nil
    mainPlayer.promptState.bootstrapSuppressed = nil

    if not GC.Utils.ArrayContains(mainPlayer.alts, altKey) then
        table.insert(mainPlayer.alts, altKey)
    end

    appendLog("ALT_LINKED", altKey, nil, mainKey, reason or "manual")
    return true
end

function AltService:UnlinkAlt(altKey, reason)
    local altPlayer = getPlayer(altKey)
    if not altPlayer then
        return false, "Character not found."
    end

    ensureRelationshipFields(altPlayer)
    if not altPlayer.main then
        return false, "Character is not linked as an alt."
    end
    local oldMain = altPlayer.main
    detachFromCurrentMain(altKey)

    altPlayer.classification = "unknown"
    altPlayer.promptState.dismissedAt = GC.Utils.Now()
    altPlayer.promptState.completedAt = nil
    altPlayer.promptState.bootstrapSuppressed = nil

    appendLog("ALT_UNLINKED", altKey, oldMain, nil, reason or "manual")
    appendLog("CLASSIFICATION_CHANGED", altKey, "alt", "unknown", reason or "manual")
    return true
end

function AltService:SetMain(playerKey, reason)
    local player = getPlayer(playerKey)
    if not player then
        return false, "Character not found."
    end

    ensureRelationshipFields(player)
    detachFromCurrentMain(playerKey)

    local oldClassification = player.classification
    player.classification = "main"
    completePrompt(player)

    if oldClassification ~= "main" then
        appendLog("CLASSIFICATION_CHANGED", playerKey, oldClassification, "main", reason or "manual")
    end

    return true
end

function AltService:SetUnknown(playerKey, reason)
    local player = getPlayer(playerKey)
    if not player then
        return false, "Character not found."
    end

    ensureRelationshipFields(player)
    if player.alts and #player.alts > 0 then
        return false, "Clear linked alts before changing this character."
    end

    local oldClassification = player.classification
    detachFromCurrentMain(playerKey)
    player.classification = "unknown"
    player.promptState.dismissedAt = GC.Utils.Now()
    player.promptState.completedAt = nil
    player.promptState.bootstrapSuppressed = nil

    if oldClassification ~= "unknown" then
        appendLog("CLASSIFICATION_CHANGED", playerKey, oldClassification, "unknown", reason or "manual")
    end

    return true
end

function AltService:SetAlt(playerKey, mainKey, reason)
    local player = getPlayer(playerKey)
    if not player then
        return false, "Character not found."
    end

    ensureRelationshipFields(player)
    local oldClassification = player.classification
    local ok, err = self:LinkAlt(mainKey, playerKey, reason)
    if not ok then
        return false, err
    end

    if oldClassification ~= "alt" then
        appendLog("CLASSIFICATION_CHANGED", playerKey, oldClassification, "alt", reason or "manual")
    end

    return true
end

function AltService:DismissPrompt(playerKey, reason)
    local player = getPlayer(playerKey)
    if not player then
        return false, "Character not found."
    end

    ensureRelationshipFields(player)
    player.promptState.dismissedAt = GC.Utils.Now()
    player.promptState.bootstrapSuppressed = nil
    appendLog("PROMPT_DISMISSED", playerKey, nil, nil, reason or "manual")
    return true
end

GC:RegisterService("Alts", setmetatable({}, AltService))

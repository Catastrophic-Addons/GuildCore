local addonName, ns = ...
local GC = ns.GuildCore

local AltService = {}
AltService.__index = AltService

local function wipeTable(t)
    for k in pairs(t) do t[k] = nil end
    return t
end

local _altDataVersion  = 0   -- bumped when alt/main relationships change
local _repairVersion   = -1  -- tracks which version Repair() last ran for
local _groupCache      = {}  -- [characterKey] -> group result table
local _groupDataCache  = {}  -- [mainKey]      -> {members, alts} (shared)
local _repairSeen      = {}  -- reused scratch table inside Repair()

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

GC.AltMain = GC.AltMain or {}
local AltMain = GC.AltMain

local function addUnique(values, seen, key)
    if key and not seen[key] and getPlayer(key) then
        seen[key] = true
        values[#values + 1] = key
        return true
    end
    return false
end

function AltMain:GetMainKey(characterKey)
    local cursorKey = characterKey
    local seen = {}
    while cursorKey do
        if seen[cursorKey] then
            return characterKey
        end
        seen[cursorKey] = true
        local player = getPlayer(cursorKey)
        if not player then return nil end
        if not player.main or not getPlayer(player.main) then
            return cursorKey
        end
        cursorKey = player.main
    end
    return characterKey
end

function AltMain:GetAltKeys(mainKey)
    local mainPlayer = getPlayer(mainKey)
    local alts, seen = {}, {}
    if not mainPlayer then return alts end
    for _, altKey in ipairs(mainPlayer.alts or {}) do
        addUnique(alts, seen, altKey)
    end
    return alts
end

function AltMain:GetGroup(characterKey)
    -- Run Repair once per alt-data version; also clears both cache layers.
    if _repairVersion ~= _altDataVersion then
        wipeTable(_groupCache)
        wipeTable(_groupDataCache)
        self:Repair()
        _repairVersion = _altDataVersion
    end

    if _groupCache[characterKey] then
        return _groupCache[characterKey]
    end

    local selected = getPlayer(characterKey)
    if not selected then
        local result = {
            mainKey     = characterKey,
            selectedKey = characterKey,
            role        = "Unknown",
            members     = {},
            alts        = {},
        }
        _groupCache[characterKey] = result
        return result
    end

    local mainKey = self:GetMainKey(characterKey) or characterKey

    -- Build or reuse shared group data for this mainKey.
    -- members/alts arrays are shared across all characters in the same group.
    local gd = _groupDataCache[mainKey]
    if not gd then
        local mainPlayer = getPlayer(mainKey) or selected
        local members, seen = {}, {}
        addUnique(members, seen, mainKey)
        local alts    = {}
        local altSeen = {}
        for _, altKey in ipairs(mainPlayer.alts or {}) do
            if addUnique(alts, altSeen, altKey) then
                addUnique(members, seen, altKey)
            end
        end
        gd = {members = members, alts = alts}
        _groupDataCache[mainKey] = gd
    end

    local role = mainKey == characterKey and "Main" or "Alt"
    if (selected.classification or "unknown") == "unknown"
        and mainKey == characterKey
        and #gd.alts == 0 then
        role = "Unknown"
    end

    local result = {
        mainKey     = mainKey,
        selectedKey = characterKey,
        role        = role,
        members     = gd.members,
        alts        = gd.alts,
    }
    _groupCache[characterKey] = result
    return result
end

function AltMain:InvalidateGroupCache()
    _altDataVersion = _altDataVersion + 1
end

function AltMain:GetGroupCacheStats()
    local cachedChars  = 0
    local cachedGroups = 0
    local maxGroupSize = 0
    for _ in pairs(_groupCache) do cachedChars = cachedChars + 1 end
    for _, gd in pairs(_groupDataCache) do
        cachedGroups = cachedGroups + 1
        local n = #(gd.members or {})
        if n > maxGroupSize then maxGroupSize = n end
    end
    return {
        cachedCharacters = cachedChars,
        cachedGroups     = cachedGroups,
        maxGroupSize     = maxGroupSize,
        altDataVersion   = _altDataVersion,
        repairVersion    = _repairVersion,
        isCacheValid     = _repairVersion == _altDataVersion,
    }
end

function AltMain:GetConnectedCount(characterKey)
    local group = self:GetGroup(characterKey)
    return math.max(1, #(group.members or {}))
end

function AltMain:IsMain(characterKey)
    return self:GetRole(characterKey) == "Main"
end

function AltMain:IsAlt(characterKey)
    return self:GetRole(characterKey) == "Alt"
end

function AltMain:GetRole(characterKey)
    return self:GetGroup(characterKey).role
end

function AltMain:Repair()
    local roster = players()
    if not roster or self._repairing then return 0 end
    self._repairing = true
    local repairs = 0

    for key, player in pairs(roster) do
        ensureRelationshipFields(player)
        wipeTable(_repairSeen)
        local cleaned = {}
        for _, altKey in ipairs(player.alts or {}) do
            local altPlayer = getPlayer(altKey)
            if altPlayer and altKey ~= key and not _repairSeen[altKey] then
                _repairSeen[altKey] = true
                cleaned[#cleaned + 1] = altKey
                ensureRelationshipFields(altPlayer)
                if altPlayer.main ~= key then
                    altPlayer.main = key
                    altPlayer.classification = "alt"
                    repairs = repairs + 1
                    if GC.Debug then
                        GC:Debug("AltMain repair: linked", tostring(altKey), "to", tostring(key))
                    end
                end
            end
        end
        player.alts = cleaned
        if #cleaned > 0 then
            player.classification = "main"
        end
    end

    for key, player in pairs(roster) do
        if player.main and getPlayer(player.main) then
            local mainPlayer = getPlayer(player.main)
            ensureRelationshipFields(mainPlayer)
            if key ~= player.main and not GC.Utils.ArrayContains(mainPlayer.alts, key) then
                mainPlayer.alts[#mainPlayer.alts + 1] = key
                repairs = repairs + 1
                if GC.Debug then
                    GC:Debug("AltMain repair: linked", tostring(key), "to", tostring(player.main))
                end
            end
        elseif player.main and not getPlayer(player.main) then
            player.main = nil
            if player.classification == "alt" then
                player.classification = "unknown"
            end
            repairs = repairs + 1
        end
    end

    self._repairing = false
    return repairs
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

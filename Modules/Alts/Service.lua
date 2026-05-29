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

local function isActivePlayer(key)
    local player = getPlayer(key)
    return player and player.status == "active" and player or nil
end

local function isPlaceholderKey(key)
    key = tostring(key or ""):lower()
    return key == "" or key:find("^connected%s+character%s+%d+$") ~= nil
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

local function debugRelationships(...)
    if GC.Debug then
        GC:Debug("RosterRelationships:", ...)
    end
end

local function refreshRelationshipViews()
    if GC.AltMain and GC.AltMain.InvalidateGroupCache then
        GC.AltMain:InvalidateGroupCache()
    end
    if GC.Services and GC.Services.GuildService and GC.Services.GuildService.InvalidateRosterCache then
        GC.Services.GuildService:InvalidateRosterCache()
    end
    if GC.UI and GC.UI.PlayerPanel and GC.UI.PlayerPanel.Refresh then GC.UI.PlayerPanel:Refresh() end
    if GC.UI and GC.UI.RosterPanel and GC.UI.RosterPanel.Refresh then GC.UI.RosterPanel:Refresh() end
    if GC.UI and GC.UI.Dashboard and GC.UI.Dashboard.Refresh then GC.UI.Dashboard:Refresh() end
    if GC.UI and GC.UI.LogPanel and GC.UI.LogPanel.Refresh then GC.UI.LogPanel:Refresh() end
end

local function addKey(values, seen, key)
    if key and not seen[key] and isActivePlayer(key) and not isPlaceholderKey(key) then
        seen[key] = true
        values[#values + 1] = key
        return true
    end
    return false
end

local function collectConnectedGroup(seedKeys)
    local roster = players()
    local keys, seen = {}, {}
    if not roster then return keys, seen end

    local function visit(key)
        if not addKey(keys, seen, key) then return end
        local player = getPlayer(key)
        if not player then return end
        if player.main then
            visit(player.main)
        end
        for _, altKey in ipairs(player.alts or {}) do
            visit(altKey)
        end

        -- Repair stale one-way links: any active record pointing at, or owning,
        -- a visited member is part of the same connected relationship group.
        for otherKey, other in pairs(roster) do
            if other and other.status == "active" then
                if other.main == key then
                    visit(otherKey)
                else
                    for _, altKey in ipairs(other.alts or {}) do
                        if altKey == key then
                            visit(otherKey)
                            break
                        end
                    end
                end
            end
        end
    end

    for _, key in ipairs(seedKeys or {}) do
        visit(key)
    end
    return keys, seen
end

local function sanitizeAltList(ownerKey, altList, removeKeys)
    local cleaned, seen = {}, {}
    removeKeys = removeKeys or {}
    for _, altKey in ipairs(altList or {}) do
        if altKey ~= ownerKey and not removeKeys[altKey] then
            addKey(cleaned, seen, altKey)
        end
    end
    return cleaned
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

    if (selected.classification or "unknown") == "alt"
        and selected.main
        and not isActivePlayer(selected.main) then
        local result = {
            mainKey     = selected.main,
            selectedKey = characterKey,
            role        = "Alt",
            members     = { characterKey },
            alts        = {},
            missingMain = true,
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

    return true
end

function AltService:NormalizeGroup(mainKey, extraKeys, reason)
    local mainPlayer = isActivePlayer(mainKey)
    if not mainPlayer then
        return false, "Selected main character is not in the active roster cache."
    end

    local seeds, seedSeen = { mainKey }, { [mainKey] = true }
    for _, key in ipairs(extraKeys or {}) do
        if key and not seedSeen[key] then
            seeds[#seeds + 1] = key
            seedSeen[key] = true
        end
    end

    local groupKeys, groupSeen = collectConnectedGroup(seeds)
    if not groupSeen[mainKey] then
        groupKeys[#groupKeys + 1] = mainKey
        groupSeen[mainKey] = true
    end

    local roster = players()
    if not roster then return false, "Roster data is unavailable." end

    local altKeys = {}
    for _, key in ipairs(groupKeys) do
        if key ~= mainKey and isActivePlayer(key) and not isPlaceholderKey(key) then
            altKeys[#altKeys + 1] = key
        end
    end
    table.sort(altKeys)

    local changed = 0
    for key, player in pairs(roster) do
        if player then
            ensureRelationshipFields(player)
            local oldAltCount = #(player.alts or {})
            local cleaned = sanitizeAltList(key, player.alts, groupSeen)
            if #cleaned ~= oldAltCount then
                player.alts = cleaned
                changed = changed + 1
            else
                player.alts = cleaned
            end
            if player.main and groupSeen[player.main] and not groupSeen[key] then
                player.main = nil
                changed = changed + 1
            end
        end
    end

    ensureRelationshipFields(mainPlayer)
    local oldMainClassification = mainPlayer.classification
    local oldMain = mainPlayer.main
    mainPlayer.main = nil
    mainPlayer.alts = altKeys
    mainPlayer.classification = "main"
    completePrompt(mainPlayer)
    if oldMain or oldMainClassification ~= "main" then
        appendLog("CLASSIFICATION_CHANGED", mainKey, oldMainClassification, "main", reason or "normalize-group")
        changed = changed + 1
    end

    for _, altKey in ipairs(altKeys) do
        local altPlayer = getPlayer(altKey)
        if altPlayer then
            ensureRelationshipFields(altPlayer)
            local oldClassification = altPlayer.classification
            local oldMain = altPlayer.main
            altPlayer.classification = "alt"
            altPlayer.main = mainKey
            altPlayer.alts = {}
            completePrompt(altPlayer)
            if oldClassification ~= "alt" then
                appendLog("CLASSIFICATION_CHANGED", altKey, oldClassification, "alt", reason or "normalize-group")
            end
            if oldMain ~= mainKey then
                appendLog("ALT_LINKED", altKey, oldMain, mainKey, reason or "normalize-group")
            end
            if oldClassification ~= "alt" or oldMain ~= mainKey then
                changed = changed + 1
            end
        end
    end

    refreshRelationshipViews()
    return true, {
        mainKey = mainKey,
        altKeys = altKeys,
        members = groupKeys,
        changed = changed,
    }
end

function AltService:LinkAlt(mainKey, altKey, reason)
    local ok, err = self:ValidateLink(mainKey, altKey)
    if not ok then
        return false, err
    end
    return self:NormalizeGroup(mainKey, { altKey }, reason or "manual")
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
    refreshRelationshipViews()
    return true
end

function AltService:SetMain(playerKey, reason)
    local player = getPlayer(playerKey)
    if not player then
        return false, "Character not found."
    end

    return self:NormalizeGroup(playerKey, nil, reason or "manual")
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

    refreshRelationshipViews()
    return true
end

function AltService:SetAlt(playerKey, mainKey, reason)
    local player = getPlayer(playerKey)
    if not player then
        return false, "Character not found."
    end

    ensureRelationshipFields(player)
    local ok, err = self:LinkAlt(mainKey, playerKey, reason)
    if not ok then
        return false, err
    end

    return true
end

function AltService:SetMissingMainReference(playerKey, mainKey, reason)
    local player = isActivePlayer(playerKey)
    if not player then
        return false, "Character is not in the active roster cache."
    end
    if not mainKey or mainKey == "" then
        return false, "Linked Main is missing."
    end
    if mainKey == playerKey then
        return false, "A character cannot link to itself."
    end
    if isPlaceholderKey(mainKey) then
        return false, "Linked Main is a placeholder."
    end
    if isActivePlayer(mainKey) then
        return self:SetAlt(playerKey, mainKey, reason or "missing-main-reference")
    end

    ensureRelationshipFields(player)
    local oldClassification = player.classification
    local oldMain = player.main
    player.classification = "alt"
    player.main = mainKey
    player.alts = {}
    completePrompt(player)

    if oldClassification ~= "alt" then
        appendLog("CLASSIFICATION_CHANGED", playerKey, oldClassification, "alt", reason or "missing-main-reference")
    end
    if oldMain ~= mainKey then
        appendLog("ALT_LINKED", playerKey, oldMain, mainKey, reason or "missing-main-reference")
    end

    refreshRelationshipViews()
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
    refreshRelationshipViews()
    return true
end

GC:RegisterService("Alts", setmetatable({}, AltService))

GC.Modules.RosterRelationships = GC.Modules.RosterRelationships or {}
local RosterRelationships = GC.Modules.RosterRelationships
local _issueCacheVersion = -1
local _issueCache = nil

function RosterRelationships:SetMain(characterKey, reason)
    return GC.Services.Alts:NormalizeGroup(characterKey, nil, reason or "roster-relationships")
end

function RosterRelationships:NormalizeGroup(mainKey, extraKeys, reason)
    return GC.Services.Alts:NormalizeGroup(mainKey, extraKeys, reason or "roster-relationships")
end

function RosterRelationships:SetMissingMainReference(characterKey, mainKey, reason)
    return GC.Services.Alts:SetMissingMainReference(characterKey, mainKey, reason or "roster-relationships")
end

local function addRelationshipIssue(cache, key, code, message, severity)
    if not key then return end
    cache.byKey[key] = cache.byKey[key] or {}
    cache.byKey[key][#cache.byKey[key] + 1] = {
        code = code,
        message = message,
        severity = severity or "warning",
    }
    cache.summary.total = cache.summary.total + 1
    cache.summary.byCode[code] = (cache.summary.byCode[code] or 0) + 1
end

local function addEdge(adjacency, a, b)
    if not a or not b or a == b then return end
    adjacency[a] = adjacency[a] or {}
    adjacency[b] = adjacency[b] or {}
    adjacency[a][b] = true
    adjacency[b][a] = true
end

local function sortRepairActions(actions)
    table.sort(actions, function(a, b)
        if (a.characterKey or "") ~= (b.characterKey or "") then
            return (a.characterKey or "") < (b.characterKey or "")
        end
        if (a.action or "") ~= (b.action or "") then
            return (a.action or "") < (b.action or "")
        end
        return tostring(a.targetKey or "") < tostring(b.targetKey or "")
    end)
end

function RosterRelationships:ValidateAll()
    if _issueCache and _issueCacheVersion == _altDataVersion then
        return _issueCache
    end

    local roster = players() or {}
    local cache = {
        byKey = {},
        summary = {
            total = 0,
            characters = 0,
            byCode = {},
        },
    }
    local active = {}
    local adjacency = {}

    for key, player in pairs(roster) do
        if player and player.status == "active" then
            active[key] = player
            adjacency[key] = adjacency[key] or {}
        end
    end

    for key, player in pairs(active) do
        local classification = player.classification or "unknown"
        local mainKey = player.main

        if classification == "alt" and not mainKey then
            addRelationshipIssue(cache, key, "alt_missing_main", "Alt has no linked Main.", "danger")
        elseif classification == "alt" and mainKey and not active[mainKey] then
            addRelationshipIssue(cache, key, "main_not_active", "Linked Main is not in the active guild roster: " .. tostring(mainKey) .. ".", "danger")
        end
        if classification == "main" and mainKey and active[mainKey] then
            addRelationshipIssue(cache, key, "main_has_main", "Main is also linked as an Alt.", "danger")
        end
        if classification == "alt" and type(player.alts) == "table" and #player.alts > 0 then
            addRelationshipIssue(cache, key, "alt_owns_alts", "Alt owns linked alts; reselect the true Main for this group.", "danger")
        end

        if mainKey and active[mainKey] then
            local mainPlayer = active[mainKey]
            if GC.Utils.ArrayContains(mainPlayer.alts or {}, key) then
                addEdge(adjacency, key, mainKey)
            else
                addRelationshipIssue(cache, key, "missing_reciprocal_alt", "Main does not list this Alt reciprocally.", "warning")
            end
        end

        for _, altKey in ipairs(player.alts or {}) do
            if isPlaceholderKey(altKey) then
                addRelationshipIssue(cache, key, "placeholder_alt", "Placeholder connected-character entry is still stored.", "warning")
            elseif altKey == key then
                addRelationshipIssue(cache, key, "self_alt", "Character is listed as its own Alt.", "danger")
            elseif not active[altKey] then
                addRelationshipIssue(cache, key, "alt_not_active", "Linked Alt is not in the active guild roster.", "warning")
            else
                if active[altKey].main == key then
                    addEdge(adjacency, key, altKey)
                else
                    addRelationshipIssue(cache, altKey, "missing_main_pointer", "Alt is listed under a Main but does not point back to it.", "warning")
                end
            end
        end
    end

    local visited = {}
    for key in pairs(active) do
        if not visited[key] then
            local stack = { key }
            local component = {}
            visited[key] = true
            while #stack > 0 do
                local current = table.remove(stack)
                component[#component + 1] = current
                for neighbor in pairs(adjacency[current] or {}) do
                    if active[neighbor] and not visited[neighbor] then
                        visited[neighbor] = true
                        stack[#stack + 1] = neighbor
                    end
                end
            end

            local mains = {}
            for _, memberKey in ipairs(component) do
                local member = active[memberKey]
                if member and member.classification == "main" then
                    mains[#mains + 1] = memberKey
                end
            end
            if #mains > 1 then
                table.sort(mains)
                for _, mainKey in ipairs(mains) do
                    addRelationshipIssue(cache, mainKey, "multiple_mains", "Connected group has multiple Mains: " .. table.concat(mains, ", "), "danger")
                end
            end
        end
    end

    for key, issues in pairs(cache.byKey) do
        if issues and #issues > 0 then
            cache.summary.characters = cache.summary.characters + 1
        end
    end

    _issueCache = cache
    _issueCacheVersion = _altDataVersion
    return cache
end

function RosterRelationships:GetIssuesForCharacter(characterKey)
    local service = self == RosterRelationships and self or RosterRelationships
    if self ~= RosterRelationships then
        characterKey = self
    end
    local cache = service:ValidateAll()
    return (cache.byKey and cache.byKey[characterKey]) or {}
end

function RosterRelationships:HasIssue(characterKey)
    local service = self == RosterRelationships and self or RosterRelationships
    if self ~= RosterRelationships then
        characterKey = self
    end
    return #(service:GetIssuesForCharacter(characterKey) or {}) > 0
end

function RosterRelationships:GetIssueSummary()
    local service = self == RosterRelationships and self or RosterRelationships
    local cache = service:ValidateAll()
    return cache.summary or { total = 0, characters = 0, byCode = {} }
end

function RosterRelationships:BuildRepairPreview()
    local roster = players() or {}
    local active = {}
    local actions = {}
    local unsafe = {}
    local actionSeen = {}

    local function addAction(action, characterKey, targetKey, message)
        if not action or not characterKey then return end
        local id = table.concat({ action, characterKey, targetKey or "" }, "\001")
        if actionSeen[id] then return end
        actionSeen[id] = true
        actions[#actions + 1] = {
            action = action,
            characterKey = characterKey,
            targetKey = targetKey,
            message = message,
        }
    end

    local function addUnsafe(characterKey, code, message)
        unsafe[#unsafe + 1] = {
            characterKey = characterKey,
            code = code,
            message = message,
        }
    end

    for key, player in pairs(roster) do
        if player and player.status == "active" then
            active[key] = player
        end
    end

    for key, player in pairs(active) do
        for _, altKey in ipairs(player.alts or {}) do
            if isPlaceholderKey(altKey) then
                addAction("removeAltReference", key, altKey, 'Remove placeholder alt link "' .. tostring(altKey) .. '".')
            elseif altKey == key then
                addAction("removeAltReference", key, altKey, "Remove self-link from alt list.")
            elseif not active[altKey] then
                addAction("removeAltReference", key, altKey, "Remove alt link to character not in the active roster: " .. tostring(altKey) .. ".")
            else
                local altPlayer = active[altKey]
                local altMain = altPlayer and altPlayer.main
                local altMainActive = altMain and active[altMain]
                if altPlayer and altPlayer.classification ~= "main" and (not altMain or not altMainActive) then
                    addAction("restoreMainPointer", altKey, key, "Restore reciprocal alt link to " .. tostring(key) .. ".")
                elseif altPlayer and altMain ~= key then
                    addUnsafe(altKey, "conflicting_main_pointer", "Alt is listed under one Main but points to another active Main. Choose the correct Main manually.")
                end
            end
        end

        if player.main and not active[player.main] then
            addAction("clearInactiveMain", key, player.main, "Clear linked Main that is not in the active roster: " .. tostring(player.main) .. ".")
        elseif player.main and active[player.main] then
            local mainPlayer = active[player.main]
            if not GC.Utils.ArrayContains(mainPlayer.alts or {}, key) then
                addAction("addReciprocalAlt", player.main, key, "Add missing reciprocal alt entry for " .. tostring(key) .. ".")
            end
        elseif (player.classification or "unknown") == "alt" then
            addUnsafe(key, "alt_missing_main", "Alt has no linked Main. Assign a Main manually.")
        end
    end

    local service = self == RosterRelationships and self or RosterRelationships
    local validation = service:ValidateAll()
    for key, issues in pairs((validation and validation.byKey) or {}) do
        for _, issue in ipairs(issues or {}) do
            if issue.code == "multiple_mains" or issue.code == "main_has_main" or issue.code == "alt_owns_alts" then
                addUnsafe(key, issue.code, tostring(issue.message or "Review this relationship manually.") .. " Manual review required.")
            end
        end
    end

    sortRepairActions(actions)
    table.sort(unsafe, function(a, b)
        if (a.characterKey or "") ~= (b.characterKey or "") then
            return (a.characterKey or "") < (b.characterKey or "")
        end
        return tostring(a.code or "") < tostring(b.code or "")
    end)

    local preview = {
        actions = actions,
        unsafe = unsafe,
        summary = {
            safeActions = #actions,
            manualReview = #unsafe,
        },
    }
    debugRelationships("repair preview built", "safe", tostring(#actions), "manual", tostring(#unsafe))
    return preview
end

function RosterRelationships:ApplyRepairPreview(preview)
    local service = self == RosterRelationships and self or RosterRelationships
    if self ~= RosterRelationships then
        preview = self
    end
    preview = preview or service:BuildRepairPreview()
    local roster = players() or {}
    local applied, skipped = 0, 0
    local appliedByAction = {}

    local function count(action)
        appliedByAction[action] = (appliedByAction[action] or 0) + 1
    end

    for _, action in ipairs(preview.actions or {}) do
        local player = roster[action.characterKey]
        local target = action.targetKey
        if not player or player.status ~= "active" then
            skipped = skipped + 1
        elseif action.action == "removeAltReference" then
            ensureRelationshipFields(player)
            local before = #(player.alts or {})
            GC.Utils.RemoveArrayValue(player.alts, target)
            if #(player.alts or {}) ~= before then
                appendLog("ALT_UNLINKED", action.characterKey, target, nil, "safe-relationship-repair")
                applied = applied + 1
                count(action.action)
            else
                skipped = skipped + 1
            end
        elseif action.action == "clearInactiveMain" then
            ensureRelationshipFields(player)
            if player.main == target and not isActivePlayer(target) then
                player.main = nil
                if player.classification == "alt" then
                    player.classification = "unknown"
                    player.promptState.completedAt = nil
                    player.promptState.bootstrapSuppressed = nil
                end
                appendLog("ALT_UNLINKED", action.characterKey, target, nil, "safe-relationship-repair")
                applied = applied + 1
                count(action.action)
            else
                skipped = skipped + 1
            end
        elseif action.action == "addReciprocalAlt" then
            local altPlayer = roster[target]
            if target and altPlayer and altPlayer.status == "active" and altPlayer.main == action.characterKey then
                ensureRelationshipFields(player)
                if not GC.Utils.ArrayContains(player.alts or {}, target) then
                    player.alts[#player.alts + 1] = target
                    table.sort(player.alts)
                    applied = applied + 1
                    count(action.action)
                else
                    skipped = skipped + 1
                end
            else
                skipped = skipped + 1
            end
        elseif action.action == "restoreMainPointer" then
            local mainPlayer = roster[target]
            if target and mainPlayer and mainPlayer.status == "active" and GC.Utils.ArrayContains(mainPlayer.alts or {}, action.characterKey) then
                ensureRelationshipFields(player)
                local currentMainActive = player.main and isActivePlayer(player.main)
                if player.classification ~= "main" and not currentMainActive then
                    local oldMain = player.main
                    player.main = target
                    player.classification = "alt"
                    player.alts = {}
                    completePrompt(player)
                    appendLog("ALT_LINKED", action.characterKey, oldMain, target, "safe-relationship-repair")
                    applied = applied + 1
                    count(action.action)
                else
                    skipped = skipped + 1
                end
            else
                skipped = skipped + 1
            end
        else
            skipped = skipped + 1
        end
    end

    if applied > 0 then
        refreshRelationshipViews()
    else
        _issueCache = nil
        _issueCacheVersion = -1
    end

    local result = {
        applied = applied,
        skipped = skipped,
        manualReview = preview.summary and preview.summary.manualReview or #(preview.unsafe or {}),
        byAction = appliedByAction,
        remainingIssues = service:GetIssueSummary(),
    }
    debugRelationships("safe repairs applied", "applied", tostring(applied), "skipped", tostring(skipped), "manual", tostring(result.manualReview or 0))
    return result
end

function RosterRelationships:RepairSafeIssues()
    local service = self == RosterRelationships and self or RosterRelationships
    local preview = service:BuildRepairPreview()
    local result = service:ApplyRepairPreview(preview)
    result.preview = preview
    return result
end

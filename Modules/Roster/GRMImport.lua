-- /GuildCore/Modules/Roster/GRMImport.lua
-- Paste-based importer for Guild Roster Manager roster exports.
local addonName, ns = ...
local GC = ns.GuildCore

GC.Modules.GRMImport = {}
local GRM = GC.Modules.GRMImport

local EXPECTED_HEADERS = {
    "Name", "Rank", "Level", "Class", "Race", "Sex", "Last Online (Days)",
    "Main/Alt", "Player Alts", "Join Date", "Promo Date", "Rank History",
    "Birthday", "Guild Rep", "Public Note", "Officer Note", "Custom Note",
    "Mythic+ Score", "Faction",
}

local MONTHS = {
    jan = 1, feb = 2, mar = 3, apr = 4, may = 5, jun = 6,
    jul = 7, aug = 8, sep = 9, oct = 10, nov = 11, dec = 12,
}

local MAX_PASTE_BYTES = 2 * 1024 * 1024
local LOW_ROW_COUNT_WARNING = 10
local INVALID_ROW_WARNING_RATIO = 0.05
local NOT_FOUND_WARNING_RATIO = 0.25

local DEFAULT_OPTIONS = {
    mode = "fill",
    dryRun = false,
    clearMissing = false,
    joinDate = true,
    promoDate = true,
    rankHistory = true,
    publicNote = true,
    officerNote = false,
    customNote = true,
    discord = true,
    mainAlt = true,
    noteMainAltHints = false,
    altLinks = false,
    birthday = true,
    mythicScore = true,
    guildRep = true,
    referenceInfo = true,
    lastOnlineSnapshot = true,
    autoMainStandalone = true,
}

local function trim(value)
    return GC.Utils and GC.Utils.Trim and GC.Utils.Trim(value or "") or tostring(value or ""):match("^%s*(.-)%s*$")
end

local function copyOptions(options)
    local out = {}
    for k, v in pairs(DEFAULT_OPTIONS) do out[k] = v end
    for k, v in pairs(options or {}) do out[k] = v end
    return out
end

local function asBlankNil(value)
    value = trim(value)
    if value == "" then return nil end
    return value
end

local function addUnique(values, value)
    if not value or value == "" then return false end
    for _, existing in ipairs(values) do
        if existing == value then return false end
    end
    values[#values + 1] = value
    return true
end

local function normalizeRealm(realm)
    realm = trim(realm)
    if realm == "" then return nil end
    return realm:gsub("%s+", "")
end

local function splitNameRealm(value)
    value = trim(value)
    if value == "" then return nil, nil end
    local name, realm = value:match("^([^%-]+)%-(.+)$")
    if name and realm then
        return trim(name), normalizeRealm(realm)
    end
    return value, nil
end

local function makeKey(name, realm)
    if not name or name == "" then return nil end
    if realm and realm ~= "" then
        return name .. "-" .. normalizeRealm(realm)
    end
    return GC.Utils.NormalizePlayerKey(name)
end

local function parseNumber(value)
    value = trim(value)
    if value == "" then return nil end
    return tonumber(value)
end

local function addIssue(report, severity, code, message)
    local issue = { severity = severity, code = code, message = message }
    if severity == "error" then
        report.errors[#report.errors + 1] = issue
    else
        report.warnings[#report.warnings + 1] = issue
    end
    return issue
end

local function debugImport(...)
    if GC.Debug then
        GC:Debug("GRMImport:", ...)
    end
end

local function addRowIssue(row, severity, code, message)
    row.issues = row.issues or {}
    row.issues[#row.issues + 1] = { severity = severity, code = code, message = message }
end

local function hasControlCharacters(value)
    return tostring(value or ""):find("[%z\1-\8\11\12\14-\31]") ~= nil
end

local function lower(value)
    return tostring(value or ""):lower()
end

local function parseSimpleDelimited(line, delimiter)
    local fields, field, inQuotes = {}, {}, false
    local i, len = 1, #line
    while i <= len do
        local ch = line:sub(i, i)
        if ch == '"' then
            if inQuotes and line:sub(i + 1, i + 1) == '"' then
                field[#field + 1] = '"'
                i = i + 1
            else
                inQuotes = not inQuotes
            end
        elseif ch == delimiter and not inQuotes then
            fields[#fields + 1] = trim(table.concat(field))
            field = {}
        else
            field[#field + 1] = ch
        end
        i = i + 1
    end
    fields[#fields + 1] = trim(table.concat(field))
    return fields
end

function GRM.GetDefaultOptions()
    return copyOptions()
end

function GRM.NormalizeLine(line)
    line = tostring(line or ""):gsub("\r$", "")
    if line:sub(1, 1) == '"' and line:sub(-1) == '"' then
        line = line:sub(2, -2):gsub('""', '"')
    end
    return line
end

function GRM.DetectDelimiter(headerLine)
    headerLine = tostring(headerLine or "")
    if headerLine:find("\t", 1, true) then return "\t", "tsv" end
    if headerLine:find(";", 1, true) then return ";", "semicolon" end
    if headerLine:find(",", 1, true) then return ",", "csv" end
    return nil, "unknown"
end

function GRM.ValidateHeaders(headers)
    if #headers ~= #EXPECTED_HEADERS then
        return false, string.format("Expected %d columns, found %d.", #EXPECTED_HEADERS, #headers)
    end
    for i, expected in ipairs(EXPECTED_HEADERS) do
        if trim(headers[i]) ~= expected then
            return false, string.format("Header %d should be %q, found %q.", i, expected, tostring(headers[i] or ""))
        end
    end
    return true
end

function GRM.ParseDate(value)
    value = trim(value)
    if value == "" then return nil, nil end

    local day, mon, year = value:match("^(%d%d?)%s+(%a+)%s+'(%d%d)$")
    if day and mon and year then
        local month = MONTHS[mon:lower():sub(1, 3)]
        if month then
            local fullYear = tonumber(year)
            fullYear = fullYear and (fullYear >= 70 and (1900 + fullYear) or (2000 + fullYear)) or nil
            if fullYear then
                return time({ year = fullYear, month = month, day = tonumber(day), hour = 12, min = 0, sec = 0 }), value
            end
        end
    end

    day, mon = value:match("^(%d%d?)%s+(%a+)$")
    if day and mon and MONTHS[mon:lower():sub(1, 3)] then
        return nil, value
    end

    local parsed = GC.Utils.ParseFlexibleDate and GC.Utils.ParseFlexibleDate(value) or nil
    return parsed, value
end

function GRM.ParseAltList(value)
    local alts, main = {}, nil
    for part in string.gmatch(tostring(value or ""), "([^,]+)") do
        local item = trim(part)
        if item ~= "" then
            local isMain = item:lower():find("%(main%)") ~= nil
            item = trim(item:gsub("%s*%([Mm][Aa][Ii][Nn]%)", ""))
            if item ~= "" then
                alts[#alts + 1] = { raw = item, isMain = isMain }
                if isMain then main = item end
            end
        end
    end
    return alts, main
end

function GRM.ExtractDiscord(value)
    value = trim(value)
    if value == "" then return nil end
    local patterns = {
        "[Dd]iscord%s*[:%-=]%s*([^,;|/]+)",
        "[Dd]isc%s*[:%-=]?%s*([^,;|/]+)",
        "[Dd][Cc]%s*[:%-=]%s*([^,;|/]+)",
        "[Dd]iscord%s+([^,;|/]+)",
    }
    for _, pattern in ipairs(patterns) do
        local match = value:match(pattern)
        match = trim(match)
        if match ~= "" then
            return match
        end
    end
    return nil
end

function GRM.ExtractMainAltHint(value)
    value = trim(value)
    if value == "" then return nil end
    local lower = value:lower()
    if lower == "main" or lower:match("%f[%a]character%s*%-?%s*main%f[%A]") or lower:match("%f[%a]main%f[%A]") then
        return { role = "main" }
    end
    local mainName = value:match("^[Aa]lt%s*%-%s*(.+)$")
    if mainName then return { role = "alt", mainName = trim(mainName) } end
    mainName = value:match("^(.+)%s*%-%s*[Aa]lt$")
    if mainName then return { role = "alt", mainName = trim(mainName) } end
    mainName = value:match("^(.+)%s*%-%s*[Mm]ain$")
    if mainName then return { role = "main", mainName = trim(mainName) } end
    return nil
end

function GRM.Parse(rawText)
    rawText = tostring(rawText or "")
    local result = {
        headers = {},
        rows = {},
        invalidRows = {},
        totalLines = 0,
        delimiter = nil,
        delimiterName = "unknown",
        validHeader = false,
        headerError = nil,
        validation = {
            errors = {},
            warnings = {},
            rowWarnings = 0,
            blocked = false,
        },
    }

    if #rawText > MAX_PASTE_BYTES then
        result.headerError = "Pasted input is too large. Split the export or use a smaller GRM export."
        addIssue(result.validation, "error", "input_too_large", result.headerError)
        result.validation.blocked = true
        return result
    end

    if hasControlCharacters(rawText) then
        addIssue(result.validation, "warning", "control_characters", "Suspicious control characters were found in the pasted text.")
    end
    if rawText:find("�", 1, true) or rawText:find("ï¿½", 1, true) then
        addIssue(result.validation, "warning", "encoding_artifacts", "Possible unsupported encoding artifacts were found in the pasted text.")
    end

    rawText = rawText:gsub("^\239\187\191", ""):gsub("\r\n", "\n"):gsub("\r", "\n")
    local lines = {}
    for line in (rawText .. "\n"):gmatch("(.-)\n") do
        if trim(line) ~= "" then lines[#lines + 1] = line end
    end
    result.totalLines = #lines
    if #lines == 0 then
        result.headerError = "Paste box is empty."
        addIssue(result.validation, "error", "missing_header", result.headerError)
        result.validation.blocked = true
        return result
    end

    local headerLine = GRM.NormalizeLine(lines[1])
    local delimiter, delimiterName = GRM.DetectDelimiter(headerLine)
    result.delimiter = delimiter
    result.delimiterName = delimiterName
    if not delimiter then
        result.headerError = "Could not detect a delimiter from the header."
        addIssue(result.validation, "error", "unsupported_delimiter", result.headerError)
        result.validation.blocked = true
        return result
    end

    result.headers = parseSimpleDelimited(headerLine, delimiter)
    result.validHeader, result.headerError = GRM.ValidateHeaders(result.headers)
    if not result.validHeader then
        addIssue(result.validation, "error", "invalid_header", result.headerError or "Header does not match the expected GRM export fields.")
        result.validation.blocked = true
        return result
    end

    for lineIndex = 2, #lines do
        local line = GRM.NormalizeLine(lines[lineIndex])
        local fields = parseSimpleDelimited(line, delimiter)
        if #fields ~= #EXPECTED_HEADERS then
            result.invalidRows[#result.invalidRows + 1] = {
                line = lineIndex,
                columnCount = #fields,
                raw = line,
                reason = string.format("Expected 19 columns, found %d.", #fields),
            }
        else
            local levelRaw = trim(fields[3])
            local lastOnlineRaw = trim(fields[7])
            local mythicRaw = trim(fields[18])
            local row = {
                line = lineIndex,
                fields = fields,
                name = asBlankNil(fields[1]),
                rank = asBlankNil(fields[2]),
                level = parseNumber(levelRaw),
                class = asBlankNil(fields[4]),
                race = asBlankNil(fields[5]),
                sex = asBlankNil(fields[6]),
                lastOnlineDays = parseNumber(lastOnlineRaw),
                mainAlt = asBlankNil(fields[8]),
                playerAltsRaw = asBlankNil(fields[9]),
                joinDateRaw = asBlankNil(fields[10]),
                promoDateRaw = asBlankNil(fields[11]),
                rankHistoryRaw = asBlankNil(fields[12]),
                birthdayRaw = asBlankNil(fields[13]),
                guildRep = asBlankNil(fields[14]),
                publicNote = asBlankNil(fields[15]),
                officerNote = asBlankNil(fields[16]),
                customNote = asBlankNil(fields[17]),
                mythicScore = parseNumber(mythicRaw),
                faction = asBlankNil(fields[19]),
                issues = {},
            }
            row.joinDate, row.joinDateDisplay = GRM.ParseDate(row.joinDateRaw)
            row.promoDate, row.promoDateDisplay = GRM.ParseDate(row.promoDateRaw)
            row.birthdayDate, row.birthdayDisplay = GRM.ParseDate(row.birthdayRaw)
            row.altRefs, row.mainRef = GRM.ParseAltList(row.playerAltsRaw)
            row.discordName = GRM.ExtractDiscord((row.publicNote or "") .. " / " .. (row.customNote or "") .. " / " .. (row.officerNote or ""))
            row.publicHint = GRM.ExtractMainAltHint(row.publicNote)
            row.customHint = GRM.ExtractMainAltHint(row.customNote)

            if not row.name then
                addRowIssue(row, "error", "missing_name", "Name is required.")
            end
            if levelRaw ~= "" and not row.level then
                addRowIssue(row, "error", "bad_level", "Level must be numeric if present.")
            end
            if lastOnlineRaw ~= "" and not row.lastOnlineDays then
                addRowIssue(row, "error", "bad_last_online", "Last Online Days must be numeric if present.")
            end
            if mythicRaw ~= "" and not row.mythicScore then
                addRowIssue(row, "error", "bad_mythic_score", "Mythic+ Score must be numeric if present.")
            end
            if row.mainAlt and lower(row.mainAlt) ~= "main" and lower(row.mainAlt) ~= "alt" then
                addRowIssue(row, "error", "bad_main_alt", "Main/Alt must be Main, Alt, or blank.")
            end
            if row.faction and lower(row.faction) ~= "horde" and lower(row.faction) ~= "alliance" and lower(row.faction) ~= "unknown" then
                addRowIssue(row, "warning", "unknown_faction", "Faction is not Horde, Alliance, blank, or unknown.")
            end
            if row.joinDateRaw and not row.joinDate then
                addRowIssue(row, "warning", "raw_join_date", "Join Date was preserved as raw text.")
            end
            if row.promoDateRaw and not row.promoDate then
                addRowIssue(row, "warning", "raw_promo_date", "Promo Date was preserved as raw text.")
            end
            if row.birthdayRaw and not row.birthdayDate then
                addRowIssue(row, "warning", "raw_birthday", "Birthday was preserved as raw/yearless text.")
            end

            local hasError = false
            for _, issue in ipairs(row.issues or {}) do
                if issue.severity == "error" then
                    hasError = true
                    break
                end
            end

            if hasError then
                result.invalidRows[#result.invalidRows + 1] = {
                    line = lineIndex,
                    columnCount = #fields,
                    raw = line,
                    row = row,
                    reason = row.issues[1] and row.issues[1].message or "Row failed validation.",
                }
            else
                if #(row.issues or {}) > 0 then
                    result.validation.rowWarnings = result.validation.rowWarnings + #row.issues
                end
                result.rows[#result.rows + 1] = row
            end
        end
    end

    local totalRows = math.max(0, #lines - 1)
    if totalRows > 0 and (#result.invalidRows / totalRows) > INVALID_ROW_WARNING_RATIO then
        addIssue(result.validation, "warning", "many_invalid_rows", "More than 5% of rows failed validation. The pasted export may be corrupted.")
    end
    if #result.rows > 0 and #result.rows < LOW_ROW_COUNT_WARNING then
        addIssue(result.validation, "warning", "low_row_count", "Fewer than 10 valid rows were parsed. This may be a truncated export.")
    end
    if totalRows == 0 then
        addIssue(result.validation, "warning", "no_data_rows", "Header was found, but there are no roster rows.")
    end

    return result
end

local function buildRosterIndexes(currentRoster)
    local byKey, byBase, duplicateBases, inactiveByKey, inactiveByBase = {}, {}, {}, {}, {}
    for key, player in pairs(currentRoster or {}) do
        local base = tostring((player.name and player.name ~= "" and player.name) or key):match("^([^%-]+)") or key
        base = base:lower()
        if player.status == "active" then
            byKey[key] = player
            byBase[base] = byBase[base] or {}
            byBase[base][#byBase[base] + 1] = key
            if #byBase[base] == 2 then
                duplicateBases[base] = true
            end
        else
            inactiveByKey[key] = player
            inactiveByBase[base] = inactiveByBase[base] or {}
            inactiveByBase[base][#inactiveByBase[base] + 1] = key
        end
    end
    return byKey, byBase, duplicateBases, inactiveByKey, inactiveByBase
end

local function resolveName(value, byKey, byBase, inactiveByKey, inactiveByBase)
    local name, realm = splitNameRealm(value)
    if not name then return nil, "missing" end
    if realm then
        local exact = makeKey(name, realm)
        if byKey[exact] then return exact, "exact" end
        if inactiveByKey and inactiveByKey[exact] then return nil, "leftGuild" end
        return nil, "notFound"
    end
    local defaultKey = makeKey(name)
    if byKey[defaultKey] then return defaultKey, "defaultRealm" end
    local matches = byBase[name:lower()] or {}
    if #matches == 1 then return matches[1], "base" end
    if #matches > 1 then return nil, "ambiguous", matches end
    local inactiveMatches = inactiveByBase and inactiveByBase[name:lower()] or {}
    if inactiveByKey and inactiveByKey[defaultKey] then return nil, "leftGuild" end
    if #inactiveMatches > 0 then return nil, "leftGuild", inactiveMatches end
    return nil, "notFound"
end

local function rawKey(value)
    local name, realm = splitNameRealm(value)
    return name and makeKey(name, realm) or nil
end

local function classifyExplicit(row)
    local value = tostring(row.mainAlt or ""):lower()
    if value == "main" then return "main" end
    if value == "alt" then return "alt" end
    return nil
end

local function addRelationshipWarning(entry, code, message)
    entry.relationshipWarnings = entry.relationshipWarnings or {}
    entry.relationshipWarnings[#entry.relationshipWarnings + 1] = {
        code = code,
        message = message,
    }
end

local function resolveRelationship(row, key, byKey, byBase, inactiveByKey, inactiveByBase, importStatusByKey, options)
    local explicit = classifyExplicit(row)
    local refs = row.altRefs or {}
    local resolvedRefs = {}
    local result = {
        explicit = explicit,
        mainCandidate = nil,
        linkedAlts = {},
        ambiguous = false,
        warnings = {},
    }

    local function warn(code, message)
        result.warnings[#result.warnings + 1] = { code = code, message = message }
    end

    for _, ref in ipairs(refs) do
        local refKey, refMatch = resolveName(ref.raw, byKey, byBase, inactiveByKey, inactiveByBase)
        resolvedRefs[#resolvedRefs + 1] = {
            raw = ref.raw,
            rawKey = rawKey(ref.raw),
            key = refKey,
            matchType = refMatch,
            isMain = ref.isMain == true,
        }
    end

    local noteHint = options.noteMainAltHints and (row.publicHint or row.customHint) or nil

    if explicit == "main" then
        for _, ref in ipairs(resolvedRefs) do
            if ref.isMain then
                warn("main_row_has_main_marker", "Main row has a Player Alts entry marked (main); that marker will be ignored for this row.")
            else
                result.linkedAlts[#result.linkedAlts + 1] = ref
            end
        end
    elseif explicit == "alt" then
        local markedMains = {}
        for _, ref in ipairs(resolvedRefs) do
            if ref.isMain then
                markedMains[#markedMains + 1] = ref
            end
        end

        if #markedMains == 1 then
            result.mainCandidate = markedMains[1]
            warn("main_marker_used", "Player Alts includes (main); treating " .. tostring(markedMains[1].raw) .. " as the linked Main.")
        elseif #markedMains > 1 then
            result.ambiguous = true
            warn("multiple_main_markers", "Player Alts has multiple (main) markers; manual review required.")
        elseif #resolvedRefs == 1 then
            result.mainCandidate = resolvedRefs[1]
            warn("single_alt_ref_as_main", "Alt row has one Player Alts entry; treating " .. tostring(resolvedRefs[1].raw) .. " as the linked Main.")
        elseif #resolvedRefs > 1 then
            local explicitMainRefs = {}
            for _, ref in ipairs(resolvedRefs) do
                if ref.key and importStatusByKey[ref.key] == "main" then
                    explicitMainRefs[#explicitMainRefs + 1] = ref
                end
            end
            if #explicitMainRefs == 1 then
                result.mainCandidate = explicitMainRefs[1]
                warn("batch_main_used", "Another imported row marks " .. tostring(explicitMainRefs[1].raw) .. " as Main; using it as the linked Main.")
            else
                result.ambiguous = true
                warn("multiple_alt_refs_no_main", "Alt row has multiple linked characters and no clear Main marker; manual review required.")
            end
        end

        if result.mainCandidate then
            for _, ref in ipairs(resolvedRefs) do
                local sameRaw = result.mainCandidate.raw and ref.raw == result.mainCandidate.raw
                local sameKey = result.mainCandidate.key and ref.key == result.mainCandidate.key
                if not sameRaw and not sameKey then
                    result.linkedAlts[#result.linkedAlts + 1] = ref
                end
            end
        end
    elseif noteHint and noteHint.role == "alt" and noteHint.mainName then
        local mainKey, mainMatch = resolveName(noteHint.mainName, byKey, byBase, inactiveByKey, inactiveByBase)
        result.mainCandidate = {
            raw = noteHint.mainName,
            rawKey = rawKey(noteHint.mainName),
            key = mainKey,
            matchType = mainMatch,
            isMain = true,
        }
        warn("note_hint_used", "Using note-derived Main/Alt hint because the GRM Main/Alt column is blank.")
    end

    debugImport(
        "relationship",
        tostring(row.name or key or "?"),
        "explicit", tostring(explicit or ""),
        "refs", tostring(#refs),
        "main", tostring(result.mainCandidate and (result.mainCandidate.key or result.mainCandidate.rawKey or result.mainCandidate.raw) or ""),
        "ambiguous", tostring(result.ambiguous)
    )

    return result
end

local function stageChange(entry, field, oldValue, newValue, group)
    if newValue == nil then return end
    if oldValue == newValue then return end
    entry.changes[#entry.changes + 1] = {
        field = field,
        oldValue = oldValue,
        newValue = newValue,
        group = group,
    }
    entry.summary.fieldsUpdated = entry.summary.fieldsUpdated + 1
    entry.summary.fieldCounts[field] = (entry.summary.fieldCounts[field] or 0) + 1
    if field == "classification" and group == "autoMainStandalone" then
        entry.summary.autoMainStandalone = (entry.summary.autoMainStandalone or 0) + 1
    end
end

local function canWrite(existing, incoming, options, protected)
    if incoming == nil then return false end
    if protected then return false, "protected" end
    if options.mode == "preview" or options.mode == "dryRun" then return true end
    if options.mode == "overwrite" then return true end
    if options.mode == "skipExisting" then
        return existing == nil or existing == ""
    end
    return existing == nil or existing == ""
end

local function addConflict(entry, field, existing, incoming, reason)
    if incoming == nil or existing == incoming then return end
    if existing == nil or existing == "" then return end
    entry.conflicts[#entry.conflicts + 1] = {
        field = field,
        existing = existing,
        incoming = incoming,
        reason = reason or "Existing value differs from import.",
    }
end

local function maybeStage(entry, player, options, field, existing, incoming, group, protected)
    if incoming == nil then return end
    if field == "classification" and existing == "unknown" then
        existing = nil
    end
    addConflict(entry, field, existing, incoming, protected and "Protected value will not be overwritten." or nil)
    local ok = canWrite(existing, incoming, options, protected)
    if ok then
        stageChange(entry, field, existing, incoming, group)
    end
end

local function hasStagedField(entry, field)
    for _, change in ipairs(entry.changes or {}) do
        if change.field == field then
            return true
        end
    end
    return false
end

function GRM.BuildPreview(parsed, currentRoster, options)
    options = copyOptions(options)
    currentRoster = currentRoster or {}
    local byKey, byBase, duplicateBases, inactiveByKey, inactiveByBase = buildRosterIndexes(currentRoster)
    local activeRosterCount = 0
    for _ in pairs(byKey) do activeRosterCount = activeRosterCount + 1 end
    local importBaseCounts, duplicateImportBases = {}, {}
    local importedAltKeys, importedLinkedKeys = {}, {}
    local importStatusByKey = {}
    for _, row in ipairs((parsed and parsed.rows) or {}) do
        local name = row.name and (row.name:match("^([^%-]+)") or row.name) or nil
        if name then
            local base = name:lower()
            importBaseCounts[base] = (importBaseCounts[base] or 0) + 1
            if importBaseCounts[base] == 2 then
            duplicateImportBases[base] = true
            end
        end
    end
    if parsed and parsed.validHeader then
        for _, row in ipairs(parsed.rows or {}) do
            local key = resolveName(row.name, byKey, byBase, inactiveByKey, inactiveByBase)
            local explicit = key and classifyExplicit(row) or nil
            if key and explicit then
                importStatusByKey[key] = explicit
            end
        end
        for _, row in ipairs(parsed.rows or {}) do
            local key = resolveName(row.name, byKey, byBase, inactiveByKey, inactiveByBase)
            if key then
                local explicit = classifyExplicit(row)
                local relationship = resolveRelationship(row, key, byKey, byBase, inactiveByKey, inactiveByBase, importStatusByKey, options)
                if explicit == "alt" then
                    importedAltKeys[key] = true
                    importedLinkedKeys[key] = true
                    if relationship.mainCandidate and relationship.mainCandidate.key then
                        importedLinkedKeys[relationship.mainCandidate.key] = true
                    end
                    for _, linkedAlt in ipairs(relationship.linkedAlts or {}) do
                        if linkedAlt.key then
                            importedAltKeys[linkedAlt.key] = true
                            importedLinkedKeys[linkedAlt.key] = true
                        end
                    end
                elseif explicit == "main" then
                    importedLinkedKeys[key] = true
                    for _, linkedAlt in ipairs(relationship.linkedAlts or {}) do
                        if linkedAlt.key then
                            importedLinkedKeys[linkedAlt.key] = true
                            importedAltKeys[linkedAlt.key] = true
                        end
                    end
                elseif row.altRefs and #row.altRefs > 0 then
                    importedLinkedKeys[key] = true
                end
                local hint = row.publicHint or row.customHint
                if hint and hint.role == "alt" then
                    importedAltKeys[key] = true
                    importedLinkedKeys[key] = true
                    if hint.mainName then
                        local hintMainKey = resolveName(hint.mainName, byKey, byBase, inactiveByKey, inactiveByBase)
                        if hintMainKey then importedLinkedKeys[hintMainKey] = true end
                    end
                end
            end
        end
    end
    local preview = {
        options = options,
        parsed = parsed,
        entries = {},
        ready = {},
        conflicts = {},
        ambiguous = {},
        notFound = {},
        leftGuild = {},
        skipped = {},
        invalid = parsed and parsed.invalidRows or {},
        duplicateBases = duplicateBases,
        duplicateImportBases = duplicateImportBases,
        summary = {
            totalRows = parsed and (#(parsed.rows or {}) + #(parsed.invalidRows or {})) or 0,
            validRows = parsed and #(parsed.rows or {}) or 0,
            invalidRows = parsed and #(parsed.invalidRows or {}) or 0,
            membersMatched = 0,
            membersNotFound = 0,
            ambiguousMatches = 0,
            duplicateNames = 0,
            conflicts = 0,
            fieldsUpdated = 0,
            rowsToApply = 0,
            rowsSkipped = 0,
            leftGuildRows = 0,
            activeRosterMembers = activeRosterCount,
            hasRosterData = activeRosterCount > 0,
            autoMainStandalone = 0,
            fieldCounts = {},
        },
        validation = {
            errors = {},
            warnings = {},
            blocked = parsed and parsed.validation and parsed.validation.blocked or false,
        },
    }

    if parsed and parsed.validation then
        for _, issue in ipairs(parsed.validation.errors or {}) do
            preview.validation.errors[#preview.validation.errors + 1] = issue
        end
        for _, issue in ipairs(parsed.validation.warnings or {}) do
            preview.validation.warnings[#preview.validation.warnings + 1] = issue
        end
    end

    for _ in pairs(duplicateBases) do preview.summary.duplicateNames = preview.summary.duplicateNames + 1 end
    for base in pairs(duplicateImportBases) do
        if not duplicateBases[base] then
            preview.summary.duplicateNames = preview.summary.duplicateNames + 1
        end
    end
    if activeRosterCount == 0 then
        addIssue(preview.validation, "error", "no_current_roster", "No current guild roster data is available. Refresh/load the roster before applying a GRM import.")
        preview.validation.blocked = true
    end
    if not parsed or not parsed.validHeader then return preview end

    for _, row in ipairs(parsed.rows or {}) do
        local key, matchType, matches = resolveName(row.name, byKey, byBase, inactiveByKey, inactiveByBase)
        local entry = {
            row = row,
            key = key,
            matchType = matchType,
            ambiguousKeys = matches,
            skipped = false,
            skipReason = nil,
            changes = {},
            conflicts = {},
            altSuggestions = {},
            relationshipWarnings = {},
            summary = preview.summary,
        }

        if not key then
            if matchType == "ambiguous" then
                preview.summary.ambiguousMatches = preview.summary.ambiguousMatches + 1
                entry.skipped = true
                entry.skipReason = "Ambiguous current guild match."
                preview.ambiguous[#preview.ambiguous + 1] = entry
                preview.skipped[#preview.skipped + 1] = entry
            elseif matchType == "leftGuild" then
                preview.summary.membersNotFound = preview.summary.membersNotFound + 1
                preview.summary.leftGuildRows = preview.summary.leftGuildRows + 1
                entry.skipped = true
                entry.skipReason = "Skipped because this character is not currently in the guild."
                preview.leftGuild[#preview.leftGuild + 1] = entry
                preview.notFound[#preview.notFound + 1] = entry
                preview.skipped[#preview.skipped + 1] = entry
            else
                preview.summary.membersNotFound = preview.summary.membersNotFound + 1
                entry.skipped = true
                entry.skipReason = "Skipped because this character is not currently in the guild."
                preview.notFound[#preview.notFound + 1] = entry
                preview.skipped[#preview.skipped + 1] = entry
            end
        else
            local player = byKey[key]
            preview.summary.membersMatched = preview.summary.membersMatched + 1

            local imported = {
                source = "GRM",
                importedAt = time(),
                rank = row.rank,
                level = row.level,
                class = row.class,
                race = row.race,
                sex = row.sex,
                lastOnlineDays = row.lastOnlineDays,
                guildRep = row.guildRep,
                faction = row.faction,
                mythicScore = row.mythicScore,
                birthdayRaw = row.birthdayRaw,
                birthdayDate = row.birthdayDate,
                rankHistoryRaw = row.rankHistoryRaw,
                joinDateRaw = row.joinDateRaw,
                promoDateRaw = row.promoDateRaw,
                publicNote = row.publicNote,
                officerNote = row.officerNote,
                customNote = row.customNote,
            }

            if options.referenceInfo or options.guildRep or options.mythicScore or options.birthday or options.rankHistory or options.lastOnlineSnapshot then
                stageChange(entry, "imports.grm", player.imports and player.imports.grm or nil, imported, "metadata")
            end

            if options.joinDate then
                local joinDate = row.joinDate
                if not joinDate and row.customNote then
                    local raw = row.customNote:match("[Jj]oined:%s*([^,]+)") or row.customNote:match("[Rr]ejoined:%s*([^,]+)")
                    joinDate = raw and GRM.ParseDate(raw) or nil
                end
                maybeStage(entry, player, options, "joinedAt", player.joinedAt, joinDate, "dates", player.joinedAtSource == "manual" and options.mode ~= "overwrite")
            end
            if options.promoDate then
                maybeStage(entry, player, options, "promotedAt", player.promotedAt, row.promoDate, "dates")
            end
            if options.publicNote then
                maybeStage(entry, player, options, "publicNote", player.publicNote, row.publicNote, "notes")
            end
            if options.officerNote then
                maybeStage(entry, player, options, "officerNote", player.officerNote, row.officerNote, "notes")
            end
            if options.customNote then
                local existing = player.notes and player.notes.custom or nil
                maybeStage(entry, player, options, "notes.custom", existing, row.customNote, "notes")
            end
            if options.discord and row.discordName then
                local existingDiscord = player.officerData and player.officerData.discordName or nil
                local protected = player.officerData and player.officerData.discordVerified == true and trim(existingDiscord or "") ~= ""
                maybeStage(entry, player, options, "officerData.discordName", existingDiscord, row.discordName, "discord", protected)
            end
            if options.mainAlt then
                local explicit = classifyExplicit(row)
                local anyHint = row.publicHint or row.customHint
                local hint = options.noteMainAltHints and anyHint or nil
                local wanted = explicit or (hint and hint.role)
                if explicit and anyHint and anyHint.role and explicit ~= anyHint.role then
                    addRelationshipWarning(entry, "note_main_alt_conflict", "Public/custom note says " .. tostring(anyHint.role) .. ", but GRM Main/Alt says " .. tostring(explicit) .. ". Explicit GRM field will be used.")
                end
                maybeStage(entry, player, options, "classification", player.classification or "unknown", wanted, "mainAlt")
            end

            for _, altRef in ipairs(row.altRefs or {}) do
                local altKey, altMatch = resolveName(altRef.raw, byKey, byBase, inactiveByKey, inactiveByBase)
                entry.altSuggestions[#entry.altSuggestions + 1] = {
                    raw = altRef.raw,
                    isMain = altRef.isMain,
                    key = altKey,
                    matchType = altMatch,
                }
            end

            if options.altLinks and GC.Services and GC.Services.Alts then
                local relationship = resolveRelationship(row, key, byKey, byBase, inactiveByKey, inactiveByBase, importStatusByKey, options)
                for _, warning in ipairs(relationship.warnings or {}) do
                    addRelationshipWarning(entry, warning.code, warning.message)
                end

                if relationship.ambiguous then
                    addRelationshipWarning(entry, "relationship_manual_review", "Imported main/alt relationship is ambiguous and will not be applied automatically.")
                elseif (relationship.explicit == "alt" or (not relationship.explicit and relationship.mainCandidate)) and relationship.mainCandidate then
                    local mainKey = relationship.mainCandidate.key
                    local missingMainKey = relationship.mainCandidate.rawKey or relationship.mainCandidate.raw
                    if mainKey and mainKey ~= key then
                        local ok, err = GC.Services.Alts:ValidateLink(mainKey, key)
                        if ok then
                            stageChange(entry, "__altLink", player.main, mainKey, "altLinks")
                            for _, linkedAlt in ipairs(relationship.linkedAlts or {}) do
                                if linkedAlt.key and linkedAlt.key ~= key and linkedAlt.key ~= mainKey then
                                    local linkOk, linkErr = GC.Services.Alts:ValidateLink(mainKey, linkedAlt.key)
                                    if linkOk then
                                        stageChange(entry, "__altLink", nil, { mainKey = mainKey, altKey = linkedAlt.key }, "altLinks")
                                    else
                                        addRelationshipWarning(entry, "linked_alt_skipped", tostring(linkedAlt.raw) .. " was not linked: " .. tostring(linkErr or "not available."))
                                    end
                                elseif linkedAlt.raw then
                                    addRelationshipWarning(entry, "linked_alt_not_active", tostring(linkedAlt.raw) .. " is not currently in the guild and will not be linked.")
                                end
                            end
                        else
                            addConflict(entry, "altLink", player.main, mainKey, err)
                        end
                    elseif missingMainKey and missingMainKey ~= key then
                        stageChange(entry, "__missingMainRef", player.main, missingMainKey, "altLinks")
                        addRelationshipWarning(entry, "linked_main_not_active", "Linked Main " .. tostring(missingMainKey) .. " is not currently in the guild; relationship will require review.")
                    end
                elseif relationship.explicit == "main" then
                    for _, linkedAlt in ipairs(relationship.linkedAlts or {}) do
                        if linkedAlt.key and linkedAlt.key ~= key then
                            local ok, err = GC.Services.Alts:ValidateLink(key, linkedAlt.key)
                            if ok then
                                stageChange(entry, "__altLink", nil, { mainKey = key, altKey = linkedAlt.key }, "altLinks")
                            else
                                addRelationshipWarning(entry, "linked_alt_skipped", tostring(linkedAlt.raw) .. " was not linked: " .. tostring(err or "not available."))
                            end
                        elseif linkedAlt.raw then
                            addRelationshipWarning(entry, "linked_alt_not_active", tostring(linkedAlt.raw) .. " is not currently in the guild and will not be linked.")
                        end
                    end
                end
            end

            if options.autoMainStandalone then
                local currentClassification = player.classification or "unknown"
                local explicit = classifyExplicit(row)
                local hint = row.publicHint or row.customHint
                local hasExistingMain = player.main ~= nil and player.main ~= ""
                local hasExistingAlts = type(player.alts) == "table" and #player.alts > 0
                local hasImportedAltStatus = importedAltKeys[key] == true
                local hasImportedRelationship = importedLinkedKeys[key] == true
                local hasImportedStatus = explicit ~= nil or (hint and hint.role ~= nil) or hasStagedField(entry, "classification")
                local shouldConsider = not hasExistingMain
                    and not hasExistingAlts
                    and not hasImportedAltStatus
                    and not hasImportedRelationship
                    and not hasImportedStatus
                    and currentClassification ~= "main"
                    and currentClassification ~= "alt"

                if options.mode == "overwrite" then
                    shouldConsider = not hasExistingMain
                        and not hasExistingAlts
                        and not hasImportedAltStatus
                        and not hasImportedRelationship
                        and not hasImportedStatus
                        and currentClassification ~= "alt"
                        and currentClassification ~= "main"
                elseif options.mode == "skipExisting" then
                    shouldConsider = shouldConsider and (currentClassification == nil or currentClassification == "")
                else
                    shouldConsider = shouldConsider and (currentClassification == nil or currentClassification == "" or currentClassification == "unknown")
                end

                if shouldConsider then
                    stageChange(entry, "classification", currentClassification, "main", "autoMainStandalone")
                end
            end

            if #entry.conflicts > 0 then
                preview.summary.conflicts = preview.summary.conflicts + #entry.conflicts
                preview.conflicts[#preview.conflicts + 1] = entry
            end
            if #entry.changes > 0 and (#entry.conflicts == 0 or options.mode == "overwrite") then
                preview.ready[#preview.ready + 1] = entry
            end
        end
        preview.entries[#preview.entries + 1] = entry
    end

    preview.summary.rowsToApply = #preview.ready
    preview.summary.rowsSkipped = #(preview.skipped or {}) + #(preview.invalid or {})
    if options.mode ~= "overwrite" then
        preview.summary.rowsSkipped = preview.summary.rowsSkipped + #(preview.conflicts or {})
    end

    if preview.summary.totalRows > 0 and (preview.summary.invalidRows / preview.summary.totalRows) > INVALID_ROW_WARNING_RATIO then
        addIssue(preview.validation, "warning", "many_invalid_rows", "More than 5% of rows are invalid. The pasted data may be corrupted.")
    end
    if preview.summary.validRows > 0 and (preview.summary.membersNotFound / preview.summary.validRows) > NOT_FOUND_WARNING_RATIO then
        addIssue(preview.validation, "warning", "many_not_in_guild", "More than 25% of valid rows are not in the current guild. This export may include members who left after the export was created.")
    end
    if preview.summary.validRows > 0 and preview.summary.validRows < LOW_ROW_COUNT_WARNING then
        addIssue(preview.validation, "warning", "low_row_count", "Fewer than 10 valid rows were parsed. Apply is blocked unless a safe override is added later.")
        preview.validation.blocked = true
    end

    return preview
end

local function setPath(player, path, value)
    if path == "notes.custom" then
        player.notes = player.notes or {}
        player.notes.custom = value
    elseif path == "officerData.discordName" then
        player.officerData = player.officerData or {}
        player.officerData.discordName = value
        if value and value ~= "" and player.officerData.discordVerified == nil then
            player.officerData.discordVerified = false
        end
    elseif path == "imports.grm" then
        player.imports = player.imports or {}
        player.imports.grm = value
    else
        player[path] = value
        if path == "joinedAt" then
            player.joinedAtSource = "grm"
        end
    end
end

function GRM.Apply(preview, options)
    options = copyOptions(options or (preview and preview.options) or {})
    local conflictsSkipped = options.mode == "overwrite" and 0 or (preview and #(preview.conflicts or {}) or 0)
    local summary = {
        appliedRows = 0,
        appliedFields = 0,
        skippedRows = 0,
        skippedNotInGuild = preview and preview.summary and preview.summary.membersNotFound or 0,
        skippedAmbiguous = preview and preview.summary and preview.summary.ambiguousMatches or 0,
        skippedInvalid = preview and preview.summary and preview.summary.invalidRows or 0,
        skippedConflicts = conflictsSkipped,
        autoMainStandalone = preview and preview.summary and preview.summary.autoMainStandalone or 0,
        errors = {},
        dryRun = options.dryRun == true or options.mode == "preview" or options.mode == "dryRun",
    }
    if not preview then
        summary.errors[#summary.errors + 1] = "No preview was built."
        return summary
    end
    if preview.validation and preview.validation.blocked then
        summary.errors[#summary.errors + 1] = "Import is blocked by validation errors. Refresh the roster or fix the pasted export and preview again."
        summary.skippedRows = (preview.summary and preview.summary.totalRows) or 0
        return summary
    end
    if summary.dryRun then
        summary.appliedRows = #(preview.ready or {})
        for _, entry in ipairs(preview.ready or {}) do
            summary.appliedFields = summary.appliedFields + #(entry.changes or {})
        end
        summary.skippedRows = (preview.summary and preview.summary.rowsSkipped) or 0
        return summary
    end

    local players = GC.Services and GC.Services.DataStore and GC.Services.DataStore:GetPlayers() or {}
    for _, entry in ipairs(preview.ready or {}) do
        local player = entry.key and players[entry.key] or nil
        if player and player.status == "active" then
            for _, change in ipairs(entry.changes or {}) do
                if change.field == "__altLink" then
                    local mainKey, altKey
                    if type(change.newValue) == "table" then
                        mainKey = change.newValue.mainKey
                        altKey = change.newValue.altKey
                    else
                        mainKey = change.newValue
                        altKey = entry.key
                    end
                    local mainPlayer = mainKey and players[mainKey] or nil
                    local altPlayer = altKey and players[altKey] or nil
                    if not mainPlayer or mainPlayer.status ~= "active" or not altPlayer or altPlayer.status ~= "active" then
                        summary.skippedRows = summary.skippedRows + 1
                        summary.skippedNotInGuild = summary.skippedNotInGuild + 1
                    else
                        debugImport("apply SetAlt", tostring(altKey), "->", tostring(mainKey))
                        local ok, err = GC.Services.Alts:SetAlt(altKey, mainKey, "grm-import")
                        if ok then
                            summary.appliedFields = summary.appliedFields + 1
                        else
                            summary.errors[#summary.errors + 1] = tostring(altKey) .. ": " .. tostring(err or "Unable to link alt.")
                        end
                    end
                elseif change.field == "__missingMainRef" then
                    if GC.Services and GC.Services.Alts and GC.Services.Alts.SetMissingMainReference then
                        debugImport("apply missing main ref", tostring(entry.key), "->", tostring(change.newValue))
                        local ok, err = GC.Services.Alts:SetMissingMainReference(entry.key, change.newValue, "grm-import")
                        if ok then
                            summary.appliedFields = summary.appliedFields + 1
                        else
                            summary.errors[#summary.errors + 1] = tostring(entry.key) .. ": " .. tostring(err or "Unable to preserve missing linked Main.")
                        end
                    else
                        setPath(player, "classification", "alt")
                        setPath(player, "main", change.newValue)
                        summary.appliedFields = summary.appliedFields + 1
                    end
                else
                    if change.field == "classification" and change.newValue == "main"
                        and GC.Services and GC.Services.Alts and GC.Services.Alts.SetMain then
                        local ok, err = GC.Services.Alts:SetMain(entry.key, "grm-import")
                        if ok then
                            summary.appliedFields = summary.appliedFields + 1
                        else
                            summary.errors[#summary.errors + 1] = tostring(entry.key) .. ": " .. tostring(err or "Unable to mark Main.")
                        end
                    else
                        setPath(player, change.field, change.newValue)
                        summary.appliedFields = summary.appliedFields + 1
                    end
                end
            end
            summary.appliedRows = summary.appliedRows + 1
        else
            summary.skippedRows = summary.skippedRows + 1
            summary.skippedNotInGuild = summary.skippedNotInGuild + 1
        end
    end
    summary.skippedRows = summary.skippedRows + (preview.summary and preview.summary.rowsSkipped or 0)

    if GC.Services and GC.Services.GuildService and GC.Services.GuildService.InvalidateRosterCache then
        GC.Services.GuildService:InvalidateRosterCache()
    end
    if GC.Modules and GC.Modules.RosterHistory and GC.Modules.RosterHistory.AppendCustomLog then
        GC.Modules.RosterHistory:AppendCustomLog("GRM_IMPORT", nil, nil, summary.appliedFields, "grm-import")
    end
    return summary
end

function GRM.RunValidationSelfTest()
    local header = table.concat(EXPECTED_HEADERS, ";")
    local function row(values)
        local fields = {}
        for i = 1, #EXPECTED_HEADERS do fields[i] = values[i] or "" end
        return table.concat(fields, ";")
    end

    local valid = row({"Current-Hellscream", "Member", "90", "Paladin", "Human", "Male", "1", "Main", "", "04 Apr '26", "05 Apr '26", "Member: 05 Apr '26", "29 Jun", "Exalted", "Discord: current", "", "Joined: 04 Apr '26", "2500", "Alliance"})
    local atreya = row({"Atreya-Zangarmarsh", "Member", "90", "Mage", "Human", "Male", "0.92", "Alt", "Thrally-Zangarmarsh", "29 Apr '26", "30 Apr '26", "Member: 30 Apr '26", "", "Exalted", "Atreya - Main // discord: atn5", "", "Joined: 29 Apr '26", "0", "Alliance"})
    local ambiguousAlt = row({"Altmulti-Hellscream", "Member", "90", "Mage", "Human", "Male", "0", "Alt", "One-Hellscream,Two-Hellscream", "", "", "", "", "", "", "", "", "0", "Alliance"})
    local solo = row({"Solo-Hellscream", "Member", "90", "Hunter", "Orc", "Male", "1", "", "", "04 Apr '26", "", "", "", "Exalted", "", "", "", "0", "Horde"})
    local left = row({"Former-Hellscream", "Member", "90", "Mage", "Human", "Female", "10", "Main", "", "04 Apr '26", "", "", "", "Exalted", "", "", "", "0", "Alliance"})
    local ambiguous = row({"Twin", "Member", "90", "Druid", "Tauren", "Female", "1", "Main", "", "04 Apr '26", "", "", "", "Exalted", "", "", "", "0", "Horde"})
    local blankName = row({"", "Member", "90", "Druid", "Tauren", "Female", "1", "Main", "", "04 Apr '26", "", "", "", "Exalted", "", "", "", "0", "Horde"})
    local badNumeric = row({"Badnum-Hellscream", "Member", "oops", "Druid", "Tauren", "Female", "later", "Main", "", "bad date", "", "", "", "Exalted", "", "", "", "many", "Horde"})
    local wrongHeader = "Wrong;Header\n" .. valid
    local largeLines = { header }
    for i = 1, 50 do
        largeLines[#largeLines + 1] = row({"Bulk" .. i .. "-Hellscream", "Member", "90", "Hunter", "Orc", "Male", "1", "Main", "", "04 Apr '26", "", "", "", "Exalted", "", "", "", "0", "Horde"})
    end

    local roster = {
        ["Current-Hellscream"] = { key = "Current-Hellscream", name = "Current", status = "active", classification = "unknown", notes = {}, officerData = {} },
        ["Atreya-Zangarmarsh"] = { key = "Atreya-Zangarmarsh", name = "Atreya", status = "active", classification = "unknown", notes = {}, officerData = {} },
        ["Thrally-Zangarmarsh"] = { key = "Thrally-Zangarmarsh", name = "Thrally", status = "active", classification = "unknown", notes = {}, officerData = {} },
        ["Altmulti-Hellscream"] = { key = "Altmulti-Hellscream", name = "Altmulti", status = "active", classification = "unknown", notes = {}, officerData = {} },
        ["One-Hellscream"] = { key = "One-Hellscream", name = "One", status = "active", classification = "unknown", notes = {}, officerData = {} },
        ["Two-Hellscream"] = { key = "Two-Hellscream", name = "Two", status = "active", classification = "unknown", notes = {}, officerData = {} },
        ["Solo-Hellscream"] = { key = "Solo-Hellscream", name = "Solo", status = "active", classification = "unknown", notes = {}, officerData = {} },
        ["Former-Hellscream"] = { key = "Former-Hellscream", name = "Former", status = "left", classification = "unknown", notes = {}, officerData = {} },
        ["Twin-Realmone"] = { key = "Twin-Realmone", name = "Twin", status = "active", classification = "unknown", notes = {}, officerData = {} },
        ["Twin-Realmtwo"] = { key = "Twin-Realmtwo", name = "Twin", status = "active", classification = "unknown", notes = {}, officerData = {} },
    }

    local parsed = GRM.Parse(table.concat({ header, valid, solo, left, ambiguous, blankName, badNumeric, "Too;Few;Columns" }, "\n"))
    local preview = GRM.BuildPreview(parsed, roster, { mode = "fill" })
    local relationshipParsed = GRM.Parse(table.concat({ header, atreya, ambiguousAlt }, "\n"))
    local relationshipPreview = GRM.BuildPreview(relationshipParsed, roster, { mode = "fill", altLinks = true, mainAlt = true, discord = true })
    local wrongParsed = GRM.Parse(wrongHeader)
    local lowParsed = GRM.Parse(header .. "\n" .. valid)
    local largeParsed = GRM.Parse(table.concat(largeLines, "\n"))

    return {
        mixed = {
            validRows = #(parsed.rows or {}),
            invalidRows = #(parsed.invalidRows or {}),
            ready = #(preview.ready or {}),
            notFound = #(preview.notFound or {}),
            leftGuild = #(preview.leftGuild or {}),
            ambiguous = #(preview.ambiguous or {}),
            skipped = #(preview.skipped or {}),
            autoMainStandalone = preview.summary and preview.summary.autoMainStandalone or 0,
            blocked = preview.validation and preview.validation.blocked or false,
        },
        wrongHeaderBlocked = wrongParsed.validation and wrongParsed.validation.blocked or false,
        lowRowBlocked = GRM.BuildPreview(lowParsed, roster, { mode = "fill" }).validation.blocked == true,
        largeValidRows = #(largeParsed.rows or {}),
        relationshipDirection = {
            discord = relationshipParsed.rows and relationshipParsed.rows[1] and relationshipParsed.rows[1].discordName or nil,
            ready = #(relationshipPreview.ready or {}),
            conflicts = #(relationshipPreview.conflicts or {}),
            atreyaWarnings = relationshipPreview.entries and relationshipPreview.entries[1] and #(relationshipPreview.entries[1].relationshipWarnings or {}) or 0,
            ambiguousWarnings = relationshipPreview.entries and relationshipPreview.entries[2] and #(relationshipPreview.entries[2].relationshipWarnings or {}) or 0,
        },
    }
end

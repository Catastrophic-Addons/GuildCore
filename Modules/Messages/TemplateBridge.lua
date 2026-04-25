local addonName, ns = ...
local GC = ns.GuildCore

local TemplateBridge = {}
TemplateBridge.__index = TemplateBridge

local DEFAULT_CATEGORY_ID = "general"
local EXPORT_SCHEMA_VERSION = 1
local EXPORT_HEADER = "GuildCoreMessageTemplates:1"

local function messages()
    return GC.Services and GC.Services.Messages or nil
end

local function trim(value)
    return GC.Utils.Trim(value or "")
end

local function lowerText(value)
    return trim(value):lower()
end

local function normalizeTags(tags)
    if type(tags) ~= "table" then
        return {}
    end

    local normalized = {}
    for _, tag in ipairs(tags) do
        tag = trim(tag)
        if tag ~= "" then
            normalized[#normalized + 1] = tag
        end
    end
    return normalized
end

local function copyTable(source)
    local result = {}
    for key, value in pairs(source or {}) do
        result[key] = value
    end
    return result
end

local function encodeValue(value)
    value = tostring(value or "")
    value = value:gsub("%%", "%%25")
    value = value:gsub("\r", "%%0D")
    value = value:gsub("\n", "%%0A")
    value = value:gsub("|", "%%7C")
    value = value:gsub("=", "%%3D")
    return value
end

local function decodeValue(value)
    return tostring(value or ""):gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16) or 0)
    end)
end

local function encodeBool(value)
    return value == true and "true" or "false"
end

local function decodeBool(value)
    return tostring(value or ""):lower() == "true"
end

local function encodeTags(tags)
    local encoded = {}
    for _, tag in ipairs(normalizeTags(tags)) do
        encoded[#encoded + 1] = encodeValue(tag)
    end
    return table.concat(encoded, "|")
end

local function decodeTags(value)
    local tags = {}
    value = tostring(value or "")
    if value == "" then
        return tags
    end
    for token in value:gmatch("([^|]+)") do
        local tag = trim(decodeValue(token))
        if tag ~= "" then
            tags[#tags + 1] = tag
        end
    end
    return tags
end

local function findCategoryByName(storage, name)
    local wanted = lowerText(name)
    if wanted == "" then
        wanted = lowerText("General")
    end
    for _, category in pairs(storage.categories or {}) do
        if type(category) == "table" and lowerText(category.name) == wanted then
            return copyTable(category)
        end
    end
    return nil
end

local function getUniqueTitle(storage, title, reservedTitles)
    title = trim(title)
    if title == "" then
        title = "Imported Message"
    end

    local taken = {}
    for _, message in pairs(storage.messages or {}) do
        if type(message) == "table" then
            taken[lowerText(message.title)] = true
        end
    end
    for titleKey in pairs(reservedTitles or {}) do
        taken[titleKey] = true
    end
    if not taken[lowerText(title)] then
        return title
    end

    local base = title .. " Copy"
    local candidate = base
    local suffix = 2
    while taken[lowerText(candidate)] do
        candidate = base .. " " .. tostring(suffix)
        suffix = suffix + 1
    end
    return candidate
end

function TemplateBridge:GetExportableTemplates(options)
    local svc = messages()
    local storage = svc and svc:GetStorage() or nil
    if not storage then
        return {}
    end

    options = options or {}
    local selected = {}
    if type(options.messageIds) == "table" and #options.messageIds > 0 then
        for _, messageId in ipairs(options.messageIds) do
            local message = storage.messages[messageId]
            if message then
                selected[#selected + 1] = message
            end
        end
        return selected
    end

    local seen = {}
    for _, categoryId in ipairs(storage.categoryOrder or {}) do
        for _, messageId in ipairs(storage.messageOrderByCategory[categoryId] or {}) do
            local message = storage.messages[messageId]
            if message and not seen[messageId] then
                selected[#selected + 1] = message
                seen[messageId] = true
            end
        end
    end

    local remaining = {}
    for messageId, message in pairs(storage.messages or {}) do
        if type(message) == "table" and not seen[messageId] then
            remaining[#remaining + 1] = message
        end
    end
    table.sort(remaining, function(a, b)
        return tostring(a.id or "") < tostring(b.id or "")
    end)
    for _, message in ipairs(remaining) do
        selected[#selected + 1] = message
    end

    return selected
end

function TemplateBridge:ExportTemplates(options)
    local svc = messages()
    local storage = svc and svc:GetStorage() or nil
    if not storage then
        return nil, "Storage not available."
    end

    local lines = { EXPORT_HEADER }
    local exported = 0
    for _, message in ipairs(self:GetExportableTemplates(options)) do
        local category = storage.categories[message.categoryId or DEFAULT_CATEGORY_ID]
        lines[#lines + 1] = "BEGIN_TEMPLATE"
        lines[#lines + 1] = "schemaVersion=" .. tostring(EXPORT_SCHEMA_VERSION)
        lines[#lines + 1] = "title=" .. encodeValue(message.title)
        lines[#lines + 1] = "body=" .. encodeValue(message.body)
        lines[#lines + 1] = "notes=" .. encodeValue(message.notes)
        lines[#lines + 1] = "categoryName=" .. encodeValue(category and category.name or "General")
        lines[#lines + 1] = "tags=" .. encodeTags(message.tags)
        lines[#lines + 1] = "targetChannel=" .. encodeValue(svc:NormalizeTargetChannel(message.targetChannel or "GUILD"))
        lines[#lines + 1] = "favorite=" .. encodeBool(message.favorite)
        lines[#lines + 1] = "archived=" .. encodeBool(message.archived)
        lines[#lines + 1] = "END_TEMPLATE"
        exported = exported + 1
    end

    if exported == 0 then
        return nil, "No templates available to export."
    end
    return table.concat(lines, "\n"), nil, exported
end

function TemplateBridge:ParseTemplateExport(text)
    local svc = messages()
    text = tostring(text or "")
    if trim(text) == "" then
        return nil, "Paste a GuildCore template export first."
    end
    if not svc then
        return nil, "Messaging service unavailable."
    end

    local templates = {}
    local current = nil
    local sawHeader = false
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        line = line:gsub("\r$", "")
        if line == EXPORT_HEADER then
            sawHeader = true
        elseif line == "BEGIN_TEMPLATE" then
            if current then
                return nil, "Export has a nested template block."
            end
            current = {}
        elseif line == "END_TEMPLATE" then
            if not current then
                return nil, "Export has an end marker without a template."
            end
            current.title = trim(current.title)
            current.body = tostring(current.body or "")
            current.notes = tostring(current.notes or "")
            current.categoryName = trim(current.categoryName)
            if current.categoryName == "" then
                current.categoryName = "General"
            end
            current.tags = normalizeTags(current.tags)
            current.targetChannel = svc:NormalizeTargetChannel(current.targetChannel or "GUILD")
            current.favorite = current.favorite == true
            current.archived = current.archived == true
            if current.title == "" then
                return nil, "Imported templates must include a title."
            end
            if trim(current.body) == "" then
                return nil, "Imported templates must include a body."
            end
            templates[#templates + 1] = current
            current = nil
        elseif current and line ~= "" then
            local key, value = line:match("^([^=]+)=(.*)$")
            if key then
                if key == "title" or key == "body" or key == "notes" or key == "categoryName" or key == "targetChannel" then
                    current[key] = decodeValue(value)
                elseif key == "tags" then
                    current.tags = decodeTags(value)
                elseif key == "favorite" or key == "archived" then
                    current[key] = decodeBool(value)
                elseif key == "schemaVersion" then
                    current.schemaVersion = tonumber(value) or EXPORT_SCHEMA_VERSION
                end
            end
        end
    end

    if current then
        return nil, "Export ended before a template block was closed."
    end
    if not sawHeader then
        return nil, "Export header was not recognized."
    end
    if #templates == 0 then
        return nil, "No templates found in export."
    end

    return templates
end

function TemplateBridge:PreviewTemplateImport(text)
    local templates, err = self:ParseTemplateExport(text)
    if not templates then
        return nil, err
    end

    local svc = messages()
    local storage = svc and svc:GetStorage() or nil
    if not storage then
        return nil, "Storage not available."
    end

    local existingTitles = {}
    local existingCategories = {}
    for _, message in pairs(storage.messages or {}) do
        if type(message) == "table" then
            existingTitles[lowerText(message.title)] = true
        end
    end
    for _, category in pairs(storage.categories or {}) do
        if type(category) == "table" then
            existingCategories[lowerText(category.name)] = true
        end
    end

    local categoriesToCreate = {}
    local categorySeen = {}
    local duplicates = {}
    local incomingTitles = {}
    for _, template in ipairs(templates) do
        local categoryKey = lowerText(template.categoryName)
        if categoryKey ~= "" and not existingCategories[categoryKey] and not categorySeen[categoryKey] then
            categoriesToCreate[#categoriesToCreate + 1] = template.categoryName
            categorySeen[categoryKey] = true
        end
        local titleKey = lowerText(template.title)
        if existingTitles[titleKey] or incomingTitles[titleKey] then
            duplicates[#duplicates + 1] = template.title
        end
        incomingTitles[titleKey] = true
    end

    return {
        templateCount = #templates,
        categoryCount = #categoriesToCreate,
        duplicateCount = #duplicates,
        categoriesToCreate = categoriesToCreate,
        duplicates = duplicates,
    }
end

function TemplateBridge:ImportTemplates(text)
    local templates, err = self:ParseTemplateExport(text)
    if not templates then
        return nil, err
    end

    local svc = messages()
    local storage = svc and svc:GetStorage() or nil
    if not storage then
        return nil, "Storage not available."
    end

    local previousCategoryId = storage.meta.selectedCategoryId
    local previousMessageId = storage.meta.selectedMessageId
    local function restoreSelection()
        storage = svc:GetStorage()
        if storage and storage.meta then
            storage.meta.selectedCategoryId = storage.categories[previousCategoryId] and previousCategoryId or DEFAULT_CATEGORY_ID
            storage.meta.selectedMessageId = storage.messages[previousMessageId] and previousMessageId or nil
        end
    end

    local created = {}
    local createdCategories = {}
    local reservedTitles = {}
    for _, template in ipairs(templates) do
        local existingCategory = findCategoryByName(storage, template.categoryName)
        local category = existingCategory
        if not category then
            local categoryErr
            category, categoryErr = svc:CreateCategory(template.categoryName)
            if not category then
                restoreSelection()
                return nil, categoryErr or "Unable to create import category."
            end
            storage = svc:GetStorage()
            createdCategories[category.id] = category.name
        end

        local title = getUniqueTitle(storage, template.title, reservedTitles)
        reservedTitles[lowerText(title)] = true
        local message, createErr = svc:CreateMessage({
            title = title,
            body = template.body,
            notes = template.notes,
            categoryId = category.id,
            tags = template.tags,
            targetChannel = template.targetChannel,
            favorite = template.favorite == true,
            archived = template.archived == true,
        })
        if not message then
            restoreSelection()
            return nil, createErr or "Unable to import template."
        end
        created[#created + 1] = message
        storage = svc:GetStorage()
    end

    restoreSelection()

    local categoryCount = 0
    for _ in pairs(createdCategories) do
        categoryCount = categoryCount + 1
    end

    return {
        importedCount = #created,
        categoryCount = categoryCount,
        messages = created,
    }
end

GC:RegisterService("MessageTemplateBridge", setmetatable({}, TemplateBridge))

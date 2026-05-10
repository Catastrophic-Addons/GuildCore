local addonName, ns = ...
local GC = ns.GuildCore

local H = ns.MessagesHelpers
local I = ns.MessagesImpl

local DEFAULT_CATEGORY_ID = H.DEFAULT_CATEGORY_ID
local trim             = H.trim
local now              = H.now
local copyTable        = H.copyTable
local removeArrayValue = H.removeArrayValue
local lowerText        = H.lowerText

function I:GetSelectedCategoryId()
    local storage = self:GetStorage()
    return storage and storage.meta.selectedCategoryId or DEFAULT_CATEGORY_ID
end

function I:SetSelectedCategory(categoryId)
    local storage = self:GetStorage()
    if storage and storage.categories[categoryId] then
        storage.meta.selectedCategoryId = categoryId
    end
end

function I:ListCategories(options)
    local storage = self:GetStorage()
    if not storage then return {} end

    options = options or {}
    local showArchived = options.showArchived == true
    local rows = {}
    for _, categoryId in ipairs(storage.categoryOrder) do
        local category = storage.categories[categoryId]
        if category and (showArchived or category.archived ~= true) then
            rows[#rows + 1] = {
                id        = category.id,
                key       = category.id,
                name      = category.name,
                count     = #(storage.messageOrderByCategory[categoryId] or {}),
                isDefault = category.id == DEFAULT_CATEGORY_ID,
                createdAt = category.createdAt,
                updatedAt = category.updatedAt,
                archived  = category.archived == true,
                collapsed = category.collapsed == true,
                color     = category.color,
                icon      = category.icon,
            }
        end
    end
    return rows
end

function I:GetCategory(categoryId)
    local storage = self:GetStorage()
    local category = storage and storage.categories[categoryId] or nil
    return category and copyTable(category) or nil
end

function I:GetCategoryIndex(categoryId)
    local storage = self:GetStorage()
    if not storage then return nil end
    for index, currentId in ipairs(storage.categoryOrder or {}) do
        if currentId == categoryId then return index end
    end
    return nil
end

function I:MoveCategoryToIndex(categoryId, desiredIndex)
    local storage = self:GetStorage()
    if not storage then return false, "Storage not available." end
    if not storage.categories[categoryId] then return false, "Category not found." end

    local order = storage.categoryOrder or {}
    local currentIndex
    for index, currentId in ipairs(order) do
        if currentId == categoryId then
            currentIndex = index
            break
        end
    end
    if not currentIndex then return false, "Category order could not be updated." end

    desiredIndex = math.max(1, math.min(#order, tonumber(desiredIndex) or currentIndex))
    if desiredIndex == currentIndex then return true end

    table.remove(order, currentIndex)
    table.insert(order, desiredIndex, categoryId)
    storage.categories[categoryId].updatedAt = now()
    return true
end

function I:MoveCategoryUp(categoryId)
    return self:MoveCategoryToIndex(categoryId, (self:GetCategoryIndex(categoryId) or 1) - 1)
end

function I:MoveCategoryDown(categoryId)
    return self:MoveCategoryToIndex(categoryId, (self:GetCategoryIndex(categoryId) or 1) + 1)
end

function I:SetCategoryCollapsed(categoryId, collapsed)
    local storage = self:GetStorage()
    if not storage then return false, "Storage not available." end
    local category = storage.categories[categoryId]
    if not category then return false, "Category not found." end
    category.collapsed = collapsed == true
    category.updatedAt = now()
    return true
end

function I:ToggleCategoryCollapsed(categoryId)
    local category = self:GetCategory(categoryId)
    if not category then return false, "Category not found." end
    return self:SetCategoryCollapsed(categoryId, not category.collapsed)
end

function I:SetCategoryArchived(categoryId, archived)
    local storage = self:GetStorage()
    if not storage then return false, "Storage not available." end
    local category = storage.categories[categoryId]
    if not category then return false, "Category not found." end
    if categoryId == DEFAULT_CATEGORY_ID and archived == true then
        return false, "The default category cannot be archived."
    end
    category.archived  = archived == true
    category.updatedAt = now()
    if category.archived and storage.meta.selectedCategoryId == categoryId then
        storage.meta.selectedCategoryId = DEFAULT_CATEGORY_ID
        storage.meta.selectedMessageId  = nil
    end
    return true
end

function I:ArchiveCategory(categoryId)
    return self:SetCategoryArchived(categoryId, true)
end

function I:UnarchiveCategory(categoryId)
    return self:SetCategoryArchived(categoryId, false)
end

function I:CreateCategory(name)
    local storage = self:GetStorage()
    if not storage then return nil, "No guild data available." end

    name = trim(name)
    if name == "" then return nil, "Category name is required." end

    local wanted = name:lower()
    for _, category in pairs(storage.categories) do
        if trim(category.name):lower() == wanted then
            return nil, "A category with that name already exists."
        end
    end

    local categoryId = "cat-" .. tostring(storage.meta.nextCategoryId)
    storage.meta.nextCategoryId = storage.meta.nextCategoryId + 1
    local stamp = now()
    storage.categories[categoryId] = {
        id = categoryId, name = name,
        createdAt = stamp, updatedAt = stamp,
        archived = false, collapsed = false, color = nil, icon = nil,
    }
    storage.categoryOrder[#storage.categoryOrder + 1] = categoryId
    storage.messageOrderByCategory[categoryId] = {}
    storage.meta.selectedCategoryId = categoryId
    return self:GetCategory(categoryId)
end

function I:RenameCategory(categoryId, name)
    local storage = self:GetStorage()
    if not storage then return false, "Storage not available." end
    local category = storage.categories[categoryId]
    if not category then return false, "Category not found." end

    name = trim(name)
    if name == "" then return false, "Category name is required." end

    for otherId, other in pairs(storage.categories) do
        if otherId ~= categoryId and trim(other.name):lower() == name:lower() then
            return false, "A category with that name already exists."
        end
    end

    category.name      = name
    category.updatedAt = now()
    return true
end

function I:DeleteCategory(categoryId, targetCategoryId)
    local storage = self:GetStorage()
    if not storage then return false, "Storage not available." end
    local category = storage.categories[categoryId]
    if not category then return false, "Category not found." end
    if categoryId == DEFAULT_CATEGORY_ID then
        return false, "The default category cannot be deleted."
    end

    targetCategoryId = targetCategoryId or DEFAULT_CATEGORY_ID
    if not storage.categories[targetCategoryId] then
        targetCategoryId = DEFAULT_CATEGORY_ID
    end
    storage.messageOrderByCategory[targetCategoryId] = storage.messageOrderByCategory[targetCategoryId] or {}

    for _, messageId in ipairs(storage.messageOrderByCategory[categoryId] or {}) do
        local message = storage.messages[messageId]
        if message then
            message.categoryId = targetCategoryId
            storage.messageOrderByCategory[targetCategoryId][#storage.messageOrderByCategory[targetCategoryId] + 1] = messageId
        end
    end

    storage.messageOrderByCategory[categoryId] = nil
    storage.categories[categoryId]             = nil
    removeArrayValue(storage.categoryOrder, categoryId)

    if storage.meta.selectedCategoryId == categoryId then
        storage.meta.selectedCategoryId = targetCategoryId
    end

    self:ValidateStorage(storage)
    return true
end

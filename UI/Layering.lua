-- UI/Layering.lua
-- Shared frame focus/layer helpers for Guild Core windows and popups.
local addonName, ns = ...
local GC = ns.GuildCore

GC.UI.FrameLayering = GC.UI.FrameLayering or {}
GC.UI.Layering = GC.UI.FrameLayering

local L = GC.UI.FrameLayering

L.MAIN_STRATA = "HIGH"
L.POPUP_STRATA = "DIALOG"
L.CONTEXT_STRATA = "FULLSCREEN_DIALOG"
L.MAIN_BASE_LEVEL = 80
L.MAIN_FRONT_LEVEL = 140
L.EXTERNAL_FRONT_LEVEL = 160
L.POPUP_OFFSET = 100
L.POPUP_MIN_LEVEL = 220
L.CONTEXT_CATCHER_LEVEL = 240
L.CONTEXT_MENU_LEVEL = 260

local function safeSetFrameStrata(frame, strata)
    if frame and frame.SetFrameStrata then
        pcall(frame.SetFrameStrata, frame, strata)
    end
end

local function safeSetFrameLevel(frame, level)
    if frame and frame.SetFrameLevel then
        pcall(frame.SetFrameLevel, frame, level)
    end
end

local function getSafeFrameLevel(frame)
    if frame and frame.GetFrameLevel then
        local ok, level = pcall(frame.GetFrameLevel, frame)
        if ok and type(level) == "number" then
            return level
        end
    end
    return 1
end

local function getSafeFrameStrata(frame, fallback)
    if frame and frame.GetFrameStrata then
        local ok, strata = pcall(frame.GetFrameStrata, frame)
        if ok and type(strata) == "string" then
            return strata
        end
    end
    return fallback
end

local function safeEnableMouse(frame)
    if frame and frame.EnableMouse then
        pcall(frame.EnableMouse, frame, true)
    end
end

local function safeHook(frame, scriptName, callback, marker)
    if not frame or not frame.HookScript or frame[marker] then return end
    frame[marker] = true
    pcall(frame.HookScript, frame, scriptName, callback)
end

local function getMainFrame()
    return GC.UI and GC.UI.MainFrame and GC.UI.MainFrame.frame or nil
end

local function getMainShadow()
    return GC.UI and GC.UI.MainFrame and GC.UI.MainFrame.shadowFrame or nil
end

local function layerShadow()
    local shadow = getMainShadow()
    local main = getMainFrame()
    if shadow and main then
        safeSetFrameStrata(shadow, L.MAIN_STRATA)
        safeSetFrameLevel(shadow, math.max(1, getSafeFrameLevel(main) - 1))
    end
end

local function knownBlizzardGuildFrames()
    local frames = {}
    if _G.CommunitiesFrame then frames[#frames + 1] = _G.CommunitiesFrame end
    if _G.GuildFrame then frames[#frames + 1] = _G.GuildFrame end
    return frames
end

local function sendBlizzardGuildFramesBack()
    for _, frame in ipairs(knownBlizzardGuildFrames()) do
        if frame then
            safeSetFrameStrata(frame, L.MAIN_STRATA)
            safeSetFrameLevel(frame, L.MAIN_BASE_LEVEL)
        end
    end
end

function L:GetSafeFrameLevel(frame)
    return getSafeFrameLevel(frame)
end

function L:BringToFront(frame)
    if not frame then return end
    local main = getMainFrame()

    if frame == main or frame == (GC.UI and GC.UI.MainFrame and GC.UI.MainFrame.miniFrame) then
        safeSetFrameStrata(frame, self.MAIN_STRATA)
        safeSetFrameLevel(frame, self.MAIN_FRONT_LEVEL)
        sendBlizzardGuildFramesBack()
        layerShadow()
        return
    end

    local parent = frame._guildCoreLayerParent or main
    local parentLevel = getSafeFrameLevel(parent)
    safeSetFrameStrata(frame, frame._guildCoreLayerStrata or self.POPUP_STRATA)
    safeSetFrameLevel(frame, math.max(self.POPUP_MIN_LEVEL, parentLevel + (frame._guildCoreLayerOffset or self.POPUP_OFFSET)))
end

function L:BringExternalFrameToFront(frame)
    if not frame then return end
    safeSetFrameStrata(frame, self.MAIN_STRATA)
    safeSetFrameLevel(frame, self.EXTERNAL_FRONT_LEVEL)

    local main = getMainFrame()
    if main then
        safeSetFrameStrata(main, self.MAIN_STRATA)
        safeSetFrameLevel(main, self.MAIN_BASE_LEVEL)
    end
    local mini = GC.UI and GC.UI.MainFrame and GC.UI.MainFrame.miniFrame or nil
    if mini then
        safeSetFrameStrata(mini, self.MAIN_STRATA)
        safeSetFrameLevel(mini, self.MAIN_BASE_LEVEL)
    end
    layerShadow()
end

function L:AttachFocusHandlers(frame)
    if not frame then return end
    safeEnableMouse(frame)
    safeHook(frame, "OnMouseDown", function(f)
        L:BringToFront(f)
    end, "_guildCoreLayerMouseHooked")
    safeHook(frame, "OnShow", function(f)
        L:BringToFront(f)
    end, "_guildCoreLayerShowHooked")
end

function L:AttachExternalFocusHandlers(frame)
    if not frame then return end
    safeHook(frame, "OnMouseDown", function(f)
        L:BringExternalFrameToFront(f)
    end, "_guildCoreExternalLayerMouseHooked")
    safeHook(frame, "OnShow", function(f)
        L:BringExternalFrameToFront(f)
    end, "_guildCoreExternalLayerShowHooked")
end

function L:AttachExternalFocusTree(frame, depth)
    if not frame or (depth or 0) > 3 then return end
    self:AttachExternalFocusHandlers(frame)
    if frame.GetChildren then
        local ok, children = pcall(function()
            return { frame:GetChildren() }
        end)
        if ok then
            for _, child in ipairs(children) do
                self:AttachExternalFocusTree(child, (depth or 0) + 1)
            end
        end
    end
end

function L:AttachBlizzardFocusHandlers()
    local function attach()
        for _, frame in ipairs(knownBlizzardGuildFrames()) do
            self:AttachExternalFocusTree(frame)
        end
    end

    attach()
    if C_Timer and C_Timer.After and not self._guildCoreBlizzardFocusScheduled then
        self._guildCoreBlizzardFocusScheduled = true
        C_Timer.After(1, attach)
        C_Timer.After(3, attach)
    end
end

function L:PrepareMainFrame(frame)
    if not frame then return end
    safeSetFrameStrata(frame, self.MAIN_STRATA)
    safeSetFrameLevel(frame, self.MAIN_FRONT_LEVEL)
    safeEnableMouse(frame)
    self:AttachFocusHandlers(frame)
    self:AttachBlizzardFocusHandlers()
end

function L:PrepareShadowFrame(frame, owner)
    if not frame then return end
    frame._guildCoreLayerParent = owner
    safeSetFrameStrata(frame, self.MAIN_STRATA)
    safeSetFrameLevel(frame, math.max(1, getSafeFrameLevel(owner) - 1))
end

function L:PreparePopupFrame(frame, parent, levelOffset, strata)
    if not frame then return end
    frame._guildCoreLayerParent = parent or getMainFrame()
    frame._guildCoreLayerOffset = levelOffset or self.POPUP_OFFSET
    frame._guildCoreLayerStrata = strata or self.POPUP_STRATA

    -- Strata controls the broad rendering layer; frame level controls order
    -- within that strata, so both are needed to keep dialogs above Guild Core.
    safeSetFrameStrata(frame, frame._guildCoreLayerStrata)
    safeSetFrameLevel(frame, math.max(self.POPUP_MIN_LEVEL, getSafeFrameLevel(frame._guildCoreLayerParent) + frame._guildCoreLayerOffset))
    safeEnableMouse(frame)
    self:AttachFocusHandlers(frame)
end

function L:PrepareContextMenuFrame(frame, level)
    if not frame then return end
    frame._guildCoreLayerStrata = self.CONTEXT_STRATA
    safeSetFrameStrata(frame, self.CONTEXT_STRATA)
    safeSetFrameLevel(frame, level or self.CONTEXT_MENU_LEVEL)
    safeEnableMouse(frame)
end

function L:PrepareChildPopupFrame(frame, parent, levelOffset)
    if not frame then return end
    frame._guildCoreLayerParent = parent
    safeSetFrameStrata(frame, getSafeFrameStrata(parent, self.POPUP_STRATA))
    safeSetFrameLevel(frame, getSafeFrameLevel(parent) + (levelOffset or 20))
    safeEnableMouse(frame)
end

function L:PrepareStaticPopup(frame, parent)
    if not frame then return end
    self:PreparePopupFrame(frame, parent or getMainFrame(), self.POPUP_OFFSET + 40, self.POPUP_STRATA)
    self:BringToFront(frame)
end

function L:ShowStaticPopup(...)
    local frame = StaticPopup_Show(...)
    self:PrepareStaticPopup(frame)
    return frame
end

-- Backwards-compatible names used by older UI modules.
function L:ApplyMainFrame(frame)
    self:PrepareMainFrame(frame)
end

function L:ApplyShadow(frame, owner)
    self:PrepareShadowFrame(frame, owner)
end

function L:ApplyPopup(frame, owner, levelOffset)
    self:PreparePopupFrame(frame, owner, levelOffset)
end

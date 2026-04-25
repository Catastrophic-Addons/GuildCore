-- UI/Layering.lua
-- Shared frame strata helpers for Guild Core windows and popups.
local addonName, ns = ...
local GC = ns.GuildCore

GC.UI.Layering = {}
local L = GC.UI.Layering

L.MAIN_STRATA = "DIALOG"
L.POPUP_STRATA = "DIALOG"
L.TOOLTIP_STRATA = "TOOLTIP"
L.MAIN_LEVEL = 80

function L:ApplyMainFrame(frame)
    if not frame then return end
    frame:SetFrameStrata(self.MAIN_STRATA)
    frame:SetFrameLevel(self.MAIN_LEVEL)
end

function L:ApplyShadow(frame, owner)
    if not frame then return end
    frame:SetFrameStrata(self.MAIN_STRATA)
    local ownerLevel = owner and owner.GetFrameLevel and owner:GetFrameLevel() or self.MAIN_LEVEL
    frame:SetFrameLevel(math.max(1, ownerLevel - 1))
end

function L:ApplyPopup(frame, owner, levelOffset)
    if not frame then return end
    frame:SetFrameStrata(self.POPUP_STRATA)
    local ownerLevel = owner and owner.GetFrameLevel and owner:GetFrameLevel() or self.MAIN_LEVEL
    frame:SetFrameLevel(ownerLevel + (levelOffset or 20))
end


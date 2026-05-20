-- /GuildCore/Modules/Roster/Service.lua
local addonName, ns = ...
local GC = ns.GuildCore

local RosterService = {}
RosterService.__index = RosterService

-- RunScan is called ONLY from GUILD_ROSTER_UPDATE (or manual "/gc scan").
-- Data is therefore guaranteed to be current at call time.
-- reason: "login" | "event" | "ticker" | "manual"
function RosterService:RunScan(reason)
    if not IsInGuild() then return end

    local settings = GC.DB:GetSettings()
    if settings and settings.enableRosterModule == false then return end

    local snapshot = GC.Modules.RosterScan:Capture()
    if not snapshot or not snapshot.members then return end

    local isBootstrap = (GC.Modules.RosterDiff:GetPreviousSnapshot() == nil)

    local scanSummary

    if isBootstrap then
        -- First ever scan for this guild: populate player records from the
        -- live roster without emitting JOINED changes for every member.
        scanSummary = GC.Modules.RosterHistory:Bootstrap(snapshot)
    else
        local changes = GC.Modules.RosterDiff:Compare(snapshot)
        scanSummary = GC.Modules.RosterHistory:ApplyChanges(snapshot, changes, reason)
    end

    GC.Modules.RosterDiff:StoreSnapshot(snapshot)

    if GC.Services and GC.Services.GuildService and GC.Services.GuildService.InvalidateRosterCache then
        GC.Services.GuildService:InvalidateRosterCache()
    end

    if scanSummary then
        GC:Debug(string.format(
            "Scan %s: tracked=%d online=%d excluded=%d changes=%d pendingPrompts=%d%s",
            tostring(scanSummary.reason or reason or "scan"),
            tonumber(scanSummary.trackedMembers or 0),
            tonumber(scanSummary.trackedOnline or 0),
            tonumber(scanSummary.excludedMembers or 0),
            tonumber(scanSummary.changes or 0),
            tonumber(scanSummary.pendingPrompts or 0),
            snapshot.usedRankFallback and " fallback=all-ranks" or ""
        ))
    end

    -- Refresh the open UI panel if the main frame is visible.
    local mf = GC.UI.MainFrame
    if mf and mf.frame and mf.frame:IsShown() then
        mf:RefreshActive()
        mf:RefreshPrompt()
    end
end

function RosterService:GetPlayers()
    return GC.DB:GetPlayers()
end

GC:RegisterService("Roster", setmetatable({}, RosterService))

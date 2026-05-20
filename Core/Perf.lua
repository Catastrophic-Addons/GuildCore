-- /GuildCore/Core/Perf.lua
-- Lightweight memory/performance diagnostics. Snapshots only print when
-- debugMode or perfMode is enabled, except explicit slash diagnostics.
local addonName, ns = ...
local GC = ns.GuildCore

GC.Perf = GC.Perf or {}
local Perf = GC.Perf
Perf.uiCounts = Perf.uiCounts or {}

function Perf:CountUI(key, amount)
    key = tostring(key or "unknown")
    self.uiCounts[key] = (self.uiCounts[key] or 0) + (amount or 1)
end

local function settings()
    return GC.DB and GC.DB.GetSettings and GC.DB:GetSettings() or {}
end

function Perf:IsEnabled()
    local s = settings()
    return s.perfMode == true or s.debugMode == true
end

function Perf:MemoryKB()
    return collectgarbage and collectgarbage("count") or 0
end

function Perf:Snapshot(label)
    if not self:IsEnabled() then return self:MemoryKB() end
    local kb = self:MemoryKB()
    if GC.Print then
        GC:Print(string.format("Perf: %s: %.1f KB", tostring(label or "memory"), kb))
    end
    return kb
end

function Perf:Delta(label, beforeKB)
    local afterKB = self:MemoryKB()
    if self:IsEnabled() and beforeKB then
        local delta = afterKB - beforeKB
        if GC.Print then
            GC:Print(string.format("Perf: %s: %.1f KB (%+.1f KB)", tostring(label or "delta"), afterKB, delta))
        end
    end
    return afterKB
end

local function countPairs(tbl)
    local n = 0
    if type(tbl) ~= "table" then return 0 end
    for _ in pairs(tbl) do n = n + 1 end
    return n
end

local function countAltLinks(players)
    local n = 0
    for _, player in pairs(players or {}) do
        if type(player) == "table" and type(player.alts) == "table" then
            n = n + #player.alts
        end
    end
    return n
end

function Perf:PrintDBSizes()
    local root = GC.DB and GC.DB.GetRoot and GC.DB:GetRoot() or GuildCoreDB or {}
    local guild = GC.DB and GC.DB.GetGuild and GC.DB:GetGuild() or {}
    local players = GC.DB and GC.DB.GetPlayers and GC.DB:GetPlayers() or {}
    local logs = GC.DB and GC.DB.GetLogs and GC.DB:GetLogs() or {}
    local syncStats = GC.Sync and GC.Sync.GetStats and GC.Sync:GetStats() or {}
    local listStats = GC.UI and GC.UI.RosterPanel and GC.UI.RosterPanel.GetListStats and GC.UI.RosterPanel:GetListStats() or {}

    if not GC.Print then return end
    GC:Print(string.format("Memory: %.1f KB", self:MemoryKB()))
    GC:Print(string.format("Roster: %d records, %d visible, %d filtered", countPairs(players), tonumber(listStats.visibleRows) or 0, tonumber(listStats.currentData) or 0))
    GC:Print(string.format("Roster frames: %d created, %d pooled", tonumber(listStats.totalCreated) or 0, tonumber(listStats.pooledRows) or 0))
    GC:Print(string.format("Alt links: %d, Ban Book: %d", countAltLinks(players), countPairs(root.banBook)))
    GC:Print(string.format("Activity logs: %d, Dashboard snapshots: %d", #logs, countPairs(root.dashboardSnapshots)))
    GC:Print(string.format("Sync: %d sessions, %d buffered chunks, %d outbox items", tonumber(syncStats.sessions) or 0, tonumber(syncStats.bufferedChunks) or 0, tonumber(syncStats.outbox) or 0))
    if guild.sync and guild.sync.outboundQueue then
        GC:Print(string.format("Sync saved queue: %d", #guild.sync.outboundQueue))
    end
end

function Perf:GetUIObjectStats()
    local roster = GC.UI and GC.UI.RosterPanel and GC.UI.RosterPanel.GetListStats and GC.UI.RosterPanel:GetListStats() or {}
    local dashboardCards = GC.UI and GC.UI.Dashboard and GC.UI.Dashboard.GetObjectStats and GC.UI.Dashboard:GetObjectStats() or {}
    local settingsStats = GC.Settings and GC.Settings.GetObjectStats and GC.Settings:GetObjectStats() or {}
    local editStats = GC.UI and GC.UI.EditCharacterPopup and GC.UI.EditCharacterPopup.GetObjectStats and GC.UI.EditCharacterPopup:GetObjectStats() or {}
    local syncStats = GC.Sync and GC.Sync.GetStats and GC.Sync:GetStats() or {}
    return {
        roster = roster,
        dashboard = dashboardCards,
        settings = settingsStats,
        editPopup = editStats,
        sync = syncStats,
        counts = self.uiCounts or {},
    }
end

function Perf:PrintRosterDump()
    if not GC.Print then return end
    local rp = GC.UI and GC.UI.RosterPanel
    if not (rp and rp.DumpStats) then
        GC:Print("|cff4fd1c5Guild Core:|r RosterPanel not initialized or roster not loaded.")
        return
    end
    local d       = rp:DumpStats()
    local GS      = GC.Services and GC.Services.GuildService
    local cachev, datav = 0, 0
    if GS and GS.GetRosterCacheVersion then
        cachev, datav = GS:GetRosterCacheVersion()
        cachev = cachev or 0
        datav  = datav  or 0
    end
    local Th = GC.UI and GC.UI.Theme

    local memBefore = self:MemoryKB()
    if collectgarbage then collectgarbage("collect") end
    local memAfter = self:MemoryKB()
    GC:Print("|cff4fd1c5Guild Core|r Roster Dump:")
    GC:Print(string.format("  Lua memory:        %.1f KB  (post-GC: %.1f KB  freed: %.1f KB)",
        memBefore, memAfter, memBefore - memAfter))
    GC:Print(string.format("  Roster cache:      v%d/%d %s",
        cachev, datav, cachev == datav and "(valid)" or "(stale)"))
    GC:Print(string.format("  RefreshCallbacks:  %d",
        Th and Th.GetRefreshCallbackCount and Th:GetRefreshCallbackCount() or 0))
    GC:Print(string.format("  All data:          %d members", d.allDataCount or 0))
    GC:Print(string.format("  Filtered/display:  %d rows", d.filteredCount or 0))
    GC:Print(string.format("  Mains: %d  Alts: %d  Unlinked: %d  Indented: %d",
        d.mainRows or 0, d.altRows or 0, d.unlinkedRows or 0, d.indentedRows or 0))
    GC:Print(string.format("  Total alt links:   %d", d.totalAltLinks or 0))
    GC:Print(string.format("  Filter rebuilds:   %d  Group rebuilds: %d",
        d.filterRebuildCount or 0, d.groupRebuildCount or 0))
    GC:Print(string.format("  Sort pool:         %d entries", d.sortPoolSize or 0))
    GC:Print(string.format("  Group cache:       %d chars / %d unique groups  max=%d  %s",
        d.groupCacheChars or 0, d.groupCacheGroups or 0, d.maxGroupSize or 0,
        d.groupCacheValid and "(valid)" or "(stale)"))
    GC:Print(string.format("  Alt data version:  v%d  Repair version: v%d",
        d.altDataVersion or 0, d.repairVersion or 0))
    GC:Print(string.format("  Rows w/ nested tables: %d  (should be 0)", d.nestedTableRows or 0))
end

function Perf:PrintPerfSummary()
    if not GC.Print then return end
    local rp        = GC.UI and GC.UI.RosterPanel
    local roster    = rp and rp.GetListStats and rp:GetListStats() or {}
    local Th        = GC.UI and GC.UI.Theme
    local GS        = GC.Services and GC.Services.GuildService
    local ecp       = GC.UI and GC.UI.EditCharacterPopup
    local ecpStats  = ecp and ecp.GetObjectStats and ecp:GetObjectStats() or {}
    local filterStr = rp and rp._filterStatusParts and rp:_filterStatusParts() or "n/a"
    local cacheVer, dataVer = 0, 0
    if GS and GS.GetRosterCacheVersion then
        cacheVer, dataVer = GS:GetRosterCacheVersion()
        cacheVer = cacheVer or 0
        dataVer  = dataVer  or 0
    end

    GC:Print("|cff4fd1c5Guild Core|r Perf Summary:")
    GC:Print(string.format("  Lua memory:       %.1f KB", self:MemoryKB()))
    GC:Print(string.format("  RefreshCallbacks: %d",
        Th and Th.GetRefreshCallbackCount and Th:GetRefreshCallbackCount() or 0))
    GC:Print(string.format("  Roster cache:     v%d/%d %s",
        cacheVer, dataVer, cacheVer == dataVer and "(valid)" or "(stale)"))
    GC:Print(string.format("  Roster data:      %d total · %d filtered",
        roster.allDataCount or 0, roster.filteredCount or 0))
    GC:Print(string.format("  Roster rows:      %d active · %d pooled",
        roster.visibleRows or 0, roster.pooledRows or 0))
    GC:Print(string.format("  Filter rebuilds:  %d · group rebuilds: %d",
        roster.filterRebuildCount or 0, roster.groupRebuildCount or 0))
    GC:Print(string.format("  Sort pool:        %d entries", roster.sortPoolSize or 0))
    GC:Print(string.format("  Active filters:   %s", filterStr))
    GC:Print(string.format("  Edit popup:       built=%s · open=%s · opens=%d · altRows=%d · autocomplete=%d",
        tostring(ecpStats.built == true),
        tostring(ecpStats.isOpen == true),
        ecpStats.openCount or 0,
        ecpStats.linkedAltRows or 0,
        ecpStats.autocompleteRows or 0))
end

function Perf:PrintUIObjects()
    if not GC.Print then return end
    local stats = self:GetUIObjectStats()
    local counts = stats.counts or {}
    GC:Print(string.format("UI memory: %.1f KB", self:MemoryKB()))
    GC:Print(string.format("Roster rows: %d created, %d pooled, %d data rows", stats.roster.totalCreated or 0, stats.roster.pooledRows or 0, stats.roster.currentData or 0))
    GC:Print(string.format("Dashboard: %d cards, %d quick buttons", stats.dashboard.metricCards or 0, stats.dashboard.quickButtons or 0))
    GC:Print(string.format("Settings: %d categories built, %d cached frames", stats.settings.categoriesBuilt or 0, stats.settings.categoryFrames or 0))
    GC:Print(string.format("Edit popup: built=%s linked-alt rows=%d autocomplete rows=%d", tostring(stats.editPopup.built == true), stats.editPopup.linkedAltRows or 0, stats.editPopup.autocompleteRows or 0))
    GC:Print(string.format("Sync: %d sessions, %d buffered chunks, %d outbox items", stats.sync.sessions or 0, stats.sync.bufferedChunks or 0, stats.sync.outbox or 0))
    GC:Print(string.format("Helper-created objects: frames=%d buttons=%d listRows=%d fontStrings=%d textures=%d inputs=%d settingsControls=%d", counts.frames or 0, counts.buttons or 0, counts.listRows or 0, counts.fontStrings or 0, counts.textures or 0, counts.inputs or 0, counts.settingsControls or 0))
end

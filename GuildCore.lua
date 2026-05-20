-- /GuildCore/GuildCore.lua
local addonName, ns = ...

local GC = ns.GuildCore
if not GC then
    return
end

local function formatInviteFilterTable(values)
    if type(values) ~= "table" then
        return "none"
    end

    local rows = {}
    for key, value in pairs(values) do
        if type(key) == "number" then
            if tostring(value or "") ~= "" then
                rows[#rows + 1] = tostring(value)
            end
        elseif value then
            rows[#rows + 1] = tostring(key)
        end
    end
    table.sort(rows)
    return #rows > 0 and table.concat(rows, ", ") or "none"
end

local function maxPlayerLevel()
    return (GetMaxPlayerLevel and GetMaxPlayerLevel()) or 90
end

local function effectiveGuildlessOnly(settings)
    local filters = GC.Modules and GC.Modules.Invite and GC.Modules.Invite.Filters
    if filters and filters.EffectiveGuildlessOnly then
        return filters.EffectiveGuildlessOnly(settings)
    end
    return not (settings and settings.guildlessOnly == false)
end

local function inviteFilterSettings()
    local service = GC.Services and GC.Services.Invite
    local storage = service and service.GetStorage and service:GetStorage() or nil
    return storage, storage and storage.settings or nil
end

local function printInviteFilters()
    local storage, settings = inviteFilterSettings()
    if not settings then
        print("|cff4fd1c5Guild Core:|r Invite filter settings are unavailable.")
        return
    end

    local ignoredCount = 0
    for _ in pairs((storage.ignored and storage.ignored.names) or {}) do
        ignoredCount = ignoredCount + 1
    end
    local recentCount = 0
    for _ in pairs(storage.recentInvites or {}) do
        recentCount = recentCount + 1
    end

    print("|cff4fd1c5Guild Core:|r Invite filters:")
    print("  level:", tostring(settings.levelMin or 1) .. "-" .. tostring(settings.levelMax or maxPlayerLevel()))
    print("  guildlessOnly:", tostring(settings.guildlessOnly))
    print("  effectiveGuildlessOnly:", tostring(effectiveGuildlessOnly(settings)))
    print("  includeConnectedRealms:", tostring(settings.includeConnectedRealms ~= false))
    print("  includeClasses:", formatInviteFilterTable(settings.includeClasses))
    print("  excludeClasses:", formatInviteFilterTable(settings.excludeClasses))
    print("  zoneIncludes:", formatInviteFilterTable(settings.zoneIncludes))
    print("  zoneExcludes:", formatInviteFilterTable(settings.zoneExcludes))
    print("  excludeRecentlyInvited:", settings.excludeRecentlyInvited ~= false and "true" or "false")
    print("  recentInviteDays:", tostring(settings.recentInviteDays or 30))
    print("  whoQueryMode:", tostring(settings.whoQueryMode or "safe"))
    print("  scanQueryMode:", tostring(settings.scanQueryMode or "adaptive-level-range"))
    print("  scanLevelMin:", tostring(settings.scanLevelMin or 1))
    print("  scanLevelMax:", tostring(settings.scanLevelMax or maxPlayerLevel()))
    print("  whoCapThreshold:", tostring(settings.whoCapThreshold or 50))
    print("  maxSplitDepth:", tostring(settings.maxSplitDepth or 6))
    print("  guildRealmOverride:", tostring(settings.guildRealmOverride or "auto"))
    print("  scanClasses:", formatInviteFilterTable(settings.scanClasses))
    print("  realmFilterMode:", tostring(settings.realmFilterMode or "local"))
    print("  inviteDelaySeconds:", tostring(settings.inviteDelaySeconds or 3))
    print("  debugEnabled:", tostring(settings.debugEnabled == true))
    print("  showGuildedCandidates:", tostring(settings.showGuildedCandidates == true))
    print("  showRecentlyInvitedCandidates:", tostring(settings.showRecentlyInvitedCandidates == true))
    print("  showRecentlyDeclinedCandidates:", tostring(settings.showRecentlyDeclinedCandidates == true))
    print("  ignored names:", tostring(ignoredCount))
    print("  recent invites:", tostring(recentCount))
end

local function resetInviteFilters()
    local _, settings = inviteFilterSettings()
    if not settings then
        print("|cff4fd1c5Guild Core:|r Invite filter settings are unavailable.")
        return
    end

    settings.guildlessOnly = true
    settings.excludeRecentlyInvited = true
    settings.includeConnectedRealms = true
    settings.scanQueryMode = "adaptive-level-range"
    settings.autoAdvanceScan = false
    settings.levelMin = 1
    settings.levelMax = maxPlayerLevel()
    settings.scanLevelMin = 1
    settings.scanLevelMax = maxPlayerLevel()
    settings.whoCapThreshold = 50
    settings.maxSplitDepth = 6
    settings.inviteDelaySeconds = 3
    settings.debugEnabled = false
    settings.showGuildedCandidates = false
    settings.showRecentlyInvitedCandidates = false
    settings.showRecentlyDeclinedCandidates = false
    settings.scanLevelBands = {
        { min = 75, max = maxPlayerLevel() },
        { min = 50, max = 74 },
        { min = 25, max = 49 },
        { min = 1, max = 24 },
    }

    print("|cff4fd1c5Guild Core:|r Invite filters reset to safe recruitment defaults.")
    printInviteFilters()
end

local function setInviteFilter(key, value)
    local _, settings = inviteFilterSettings()
    if not settings then
        print("|cff4fd1c5Guild Core:|r Invite filter settings are unavailable.")
        return
    end

    if key == "guildlessOnly" then
        if value == "true" then
            settings.guildlessOnly = true
        elseif value == "false" then
            settings.guildlessOnly = false
        else
            print("|cff4fd1c5Guild Core:|r Usage: /gc invitefilters set guildlessOnly <true|false>")
            return
        end
        print("|cff4fd1c5Guild Core:|r invite.filters.guildlessOnly set to " .. tostring(settings.guildlessOnly) .. ".")
        printInviteFilters()
        return
    end

    print("|cff4fd1c5Guild Core:|r Supported setting: guildlessOnly")
end

SLASH_GUILDCORE1 = "/guildcore"
SLASH_GUILDCORE2 = "/gc"

SlashCmdList["GUILDCORE"] = function(msg)
    msg = GC.Utils.Trim(msg or "")

    local fontCmd = msg == "font" and "" or msg:match("^font%s+(.+)$")
    if fontCmd ~= nil then
        local Th = GC.UI and GC.UI.Theme
        if not Th or not Th.GetFontThemeKeys then
            print("|cff4fd1c5Guild Core:|r Font themes are unavailable.")
            return
        end

        fontCmd = GC.Utils.Trim(fontCmd)
        if fontCmd == "" then
            print("|cff4fd1c5Guild Core:|r Current font theme:", Th.GetFontThemeName())
            print("|cff4fd1c5Guild Core:|r Available font themes:", table.concat(Th.GetFontThemeKeys(), ", "))
            return
        end

        local applied = Th.SetFontTheme(fontCmd)
        if GC.UI.MainFrame and GC.UI.MainFrame.ApplyTheme then
            GC.UI.MainFrame:ApplyTheme()
        end
        print("|cff4fd1c5Guild Core:|r Font theme set to " .. applied .. ".")
        return
    end

    if msg == "scan" then
        local ok, err = GC.Services.GuildService:TriggerScan()
        print("|cff4fd1c5Guild Core:|r " .. (ok and "Roster scan requested." or (err or "Unable to request scan.")))
        return
    end

    if msg == "debug" then
        local guildKey = GC.DB:GetCurrentGuildKey()
        print("|cff4fd1c5Guild Core:|r Guild key:", guildKey or "none")
        local s = GC.DB:GetSettings()
        print("|cff4fd1c5Guild Core:|r Debug mode:", s and s.debugMode and "on" or "off")
        return
    end

    if msg == "perf" then
        if GC.Perf and GC.Perf.PrintPerfSummary then
            GC.Perf:PrintPerfSummary()
        else
            print("|cff4fd1c5Guild Core:|r Perf diagnostics are unavailable.")
        end
        return
    end

    if msg == "rosterdump" then
        if GC.Perf and GC.Perf.PrintRosterDump then
            GC.Perf:PrintRosterDump()
        else
            print("|cff4fd1c5Guild Core:|r Roster dump unavailable.")
        end
        return
    end

    if msg == "mem" or msg == "memory" then
        if GC.Perf and GC.Perf.PrintDBSizes then
            GC.Perf:PrintDBSizes()
        else
            print("|cff4fd1c5Guild Core:|r Memory diagnostics are unavailable.")
        end
        return
    end

    if msg == "uiobjects" or msg == "ui objects" then
        if GC.Perf and GC.Perf.PrintUIObjects then
            GC.Perf:PrintUIObjects()
        else
            print("|cff4fd1c5Guild Core:|r UI object diagnostics are unavailable.")
        end
        return
    end

    if msg == "gc" then
        if collectgarbage then
            local before = collectgarbage("count")
            collectgarbage("collect")
            local after = collectgarbage("count")
            print(string.format("|cff4fd1c5Guild Core:|r Garbage collection complete: %.1f KB -> %.1f KB.", before, after))
        end
        return
    end

    if msg == "sync" or msg == "sync now" then
        if GC.Sync and GC.Sync.SyncNow then
            GC.Sync:SyncNow("slash")
        else
            print("|cff4fd1c5Guild Core:|r Sync service is unavailable.")
        end
        return
    end

    if msg == "macrodebug" then
        local index = GetMacroIndexByName and GetMacroIndexByName("GuildCore_Action")
        print(index)
        if GetMacroBody then
            print(index and index > 0 and GetMacroBody(index) or GetMacroBody("GuildCore_Action"))
        end
        if GC.UI and GC.UI.PlayerPanel and GC.UI.PlayerPanel.confirmActionBtn then
            local btn = GC.UI.PlayerPanel.confirmActionBtn
            print("Confirm button enabled:", btn.IsEnabled and btn:IsEnabled() or "unknown")
        end
        return
    end

    local inviteDebugName = msg == "invitedebug" and "" or msg:match("^invitedebug%s+(.+)$")
    if inviteDebugName ~= nil then
        if GC.Services.InviteProbe and GC.Services.InviteProbe.PrintInviteDebug then
            GC.Services.InviteProbe:PrintInviteDebug(GC.Utils.Trim(inviteDebugName))
        else
            print("|cff4fd1c5Guild Core:|r Invite probe service is unavailable.")
        end
        return
    end

    local whoDebugQuery = msg == "whodebug" and "" or msg:match("^whodebug%s+(.+)$")
    if whoDebugQuery ~= nil then
        if GC.Services.InviteProbe and GC.Services.InviteProbe.StartWhoProbe then
            GC.Services.InviteProbe:StartWhoProbe(GC.Utils.Trim(whoDebugQuery))
        else
            print("|cff4fd1c5Guild Core:|r WHO probe service is unavailable.")
        end
        return
    end

    -- /gc invitescan           -> fresh scan from guild realm (clears candidates)
    -- /gc invitescan next      -> manually send next pending query if auto scan pauses
    -- /gc invitescan stop      -> cancel scan and discard pending queries
    -- /gc invitescan clear     -> stop scan and clear all candidates
    -- /gc invitescan status    -> print current scan state
    -- /gc invitescan realm     -> print realm detection debug
    -- /gc invitescan testrealm -> compare WHO realm query syntax manually
    -- /gc invitescan <filter>  -> fresh scan with extra WHO filter
    if msg == "invitescan" or msg:match("^invitescan") then
        local sub = GC.Utils.Trim(msg:match("^invitescan%s+(.+)$") or "")
        local scanner = GC.Services.InviteScanner

        if sub == "realm" then
            local Realm = GC.Modules.Invite and GC.Modules.Invite.Realm
            if Realm and Realm.PrintRealmDebug then
                local storage = GC.Services.Invite and GC.Services.Invite.GetStorage
                    and GC.Services.Invite:GetStorage()
                Realm.PrintRealmDebug(storage and storage.settings or {})
            else
                print("|cff4fd1c5Guild Core:|r Invite Realm module is unavailable.")
            end
            return
        end

        if not (scanner and scanner.StartScan) then
            print("|cff4fd1c5Guild Core:|r Invite scanner service is unavailable.")
            return
        end

        if sub == "next" then
            local ok, err = scanner:NextQuery()
            if not ok then
                print("|cff4fd1c5Guild Core:|r " .. (err or "Unable to send next query."))
            end
            return
        end

        if sub == "testrealm" then
            local ok, err = scanner:StartRealmQueryTest()
            if not ok then
                print("|cff4fd1c5Guild Core:|r " .. (err or "Unable to start realm query test."))
            end
            return
        end

        if sub == "testrealm next" then
            local ok, err = scanner:NextRealmQueryTest()
            if not ok then
                print("|cff4fd1c5Guild Core:|r " .. (err or "Unable to send next realm test query."))
            end
            return
        end

        if sub == "stop" then
            scanner:StopScan("user")
            return
        end

        if sub == "clear" then
            scanner:ClearScan()
            return
        end

        if sub == "status" then
            local s = scanner:GetScanStatus()
            print(string.format("|cff4fd1c5Guild Core:|r Scan status:  active=%s  timedOut=%s",
                tostring(s.active), tostring(s.timedOut)))
            print(string.format("  query=%d/%d  pending=%d  candidates=%d  anchor=%s",
                s.queryIndex, s.totalQueries, s.pendingCount,
                s.candidateCount, tostring(s.anchor or "?")))
            if s.currentQuery then
                print("  current: " .. s.currentQuery)
            end
            if s.statusLine then
                print("  status: " .. s.statusLine)
            end
            if s.warning then
                print("  warning: " .. s.warning)
            end
            return
        end

        -- Fresh scan. sub is "" for plain /gc invitescan, or an extra filter otherwise.
        local ok, err = scanner:StartScan(sub ~= "" and sub or nil)
        if not ok then
            print("|cff4fd1c5Guild Core:|r " .. (err or "Unable to start invite scan."))
        end
        return
    end

    local inviteFiltersSub = msg:match("^invitefilters%s+(.+)$")
    if msg == "invitefilters" or inviteFiltersSub ~= nil then
        local sub = GC.Utils.Trim(inviteFiltersSub or "")
        if sub == "" then
            printInviteFilters()
            return
        end

        if sub == "reset" then
            resetInviteFilters()
            return
        end

        local key, value = sub:match("^set%s+(%S+)%s+(%S+)$")
        if key then
            setInviteFilter(key, value)
            return
        end

        print("|cff4fd1c5Guild Core:|r Usage: /gc invitefilters [reset|set guildlessOnly <true|false>]")
        printInviteFilters()
        return
    end

    local inviteQueueSub = msg:match("^invitequeue%s+(.+)$")
    if msg == "invitequeue" or inviteQueueSub ~= nil then
        local sub = GC.Utils.Trim(inviteQueueSub or "")
        local q = GC.Services and GC.Services.InviteQueue
        if not q then
            print("|cff4fd1c5Guild Core:|r Invite queue service is unavailable.")
            return
        end

        if sub == "addeligible" then
            local scanner = GC.Services.InviteScanner
            if not scanner then
                print("|cff4fd1c5Guild Core:|r Invite scanner is unavailable.")
                return
            end
            local candidates = scanner:GetCandidates()
            local eligible = {}
            for _, c in ipairs(candidates) do
                if c.eligible == true then eligible[#eligible + 1] = c end
            end
            local queued, duplicates, queueIneligible = q:AddCandidates(eligible)
            local ineligibleSkipped = (#candidates - #eligible) + (queueIneligible or 0)
            print(string.format(
                "|cff4fd1c5Guild Core:|r Invite queue: total=%d  eligible added=%d  duplicates skipped=%d  ineligible skipped=%d",
                #candidates,
                queued or 0,
                duplicates or 0,
                ineligibleSkipped
            ))

        elseif sub == "list" then
            q:PrintList()

        elseif sub == "dryrun" then
            local ok, err = q:StartDryRun()
            if not ok then
                print("|cff4fd1c5Guild Core:|r " .. (err or "Unable to start dry run."))
            end

        elseif sub == "pause" then
            q:Pause()

        elseif sub == "resume" then
            q:Resume()

        elseif sub == "cancel" then
            q:Cancel()

        elseif sub == "clear" then
            q:Clear()

        else
            print("|cff4fd1c5Guild Core:|r Usage: /gc invitequeue <addeligible|list|dryrun|pause|resume|cancel|clear>")
        end
        return
    end

    -- Panel shortcuts: /gc roster, /gc purge, /gc banbook, /gc log, /gc settings, /gc messages
    local panelMap = {
        roster = "roster",
        purge = "purge",
        invite = "invite",
        banbook = "banbook",
        ban = "banbook",
        log = "log",
        settings = "settings",
        dashboard = "dashboard",
        messaging = "messaging",
        messages = "messaging",
    }
    if panelMap[msg] then
        GC.UI:Show()
        GC.UI:SetActivePanel(panelMap[msg])
        return
    end

    GC.UI:Toggle()
end

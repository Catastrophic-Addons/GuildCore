-- UI/PlayerPanel.lua
-- Right-side detail panel: player info display + editable fields + action buttons.
local addonName, ns = ...
local GC = ns.GuildCore

GC.UI.PlayerPanel = {}
local PP = GC.UI.PlayerPanel

local function T()  return GC.UI.Theme end
local function DS() return GC.Services.DataStore end
local function GS() return GC.Services.GuildService end
local function OPS() return GC.Services.Operations end

local currentPlayer  = nil

local function appendOfficerActionLog(playerKey, actionLabel, detail)
    if not GC.Modules or not GC.Modules.RosterHistory or not GC.Modules.RosterHistory.AppendCustomLog then
        return
    end

    GC.Modules.RosterHistory:AppendCustomLog("CUSTOM", playerKey, nil, actionLabel, detail)
end

local function requestOfficerActionRefresh()
    if not GS() then
        return
    end

    local ok = GS():TriggerScan()
    if ok then
        C_Timer.After(1.5, function()
            if GS() then
                GS():TriggerScan()
            end
        end)
    end
end

local function buildOfficerMacro(command, player)
    local name = player and player.name
    if not name or name == "" then
        return nil
    end
    return string.format("/%s %s", command, name)
end

local function setOfficerActionFeedback(self, message, colorKey)
    if self and self.actionResult then
        self.pendingActionMessage = message or ""
        self.pendingActionColorKey = colorKey or "textDimmed"
        local color = T().c[colorKey] or T().c.textDimmed
        self.actionResult:SetTextColor(color[1], color[2], color[3], color[4] or 1)
        self.actionResult:SetText(message or "")
    end
    GC.UI.MainFrame:SetStatus(message, colorKey)
end

local function parseDateToTimestamp(text)
    text = (text or ""):match("^%s*(.-)%s*$")
    local y, m, d = text:match("^(%d%d%d%d)%-(%d%d?)%-(%d%d?)$")
    if not y then return nil end
    return time({year=tonumber(y), month=tonumber(m), day=tonumber(d), hour=12, min=0, sec=0})
end

function PP:SetPlayer(viewModel) currentPlayer = viewModel end

function PP:ShowPlayerByKey(key)
    local entry = GS():GetRosterEntry(key)
    if not entry then
        return false
    end
    self:SetPlayer(entry)
    self:Refresh()
    return true
end

function PP:Create(parent)
    if self.frame then return end
    local Th = T()
    local P  = Th.padding

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    self.frame = frame
    Th.Bg(frame, Th.c.panelAlt)

    -- Header chrome
    local hdrBg = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
    hdrBg:SetPoint("TOPLEFT"); hdrBg:SetPoint("TOPRIGHT"); hdrBg:SetHeight(52)
    local ch = Th.c.chrome
    hdrBg:SetColorTexture(ch[1], ch[2], ch[3], ch[4])
    local hdrEdge = frame:CreateTexture(nil, "ARTWORK")
    hdrEdge:SetPoint("TOPLEFT",0,-52); hdrEdge:SetPoint("TOPRIGHT",0,-52); hdrEdge:SetHeight(1)
    local ac = Th.c.accent
    hdrEdge:SetColorTexture(ac[1], ac[2], ac[3], 0.4)
    local bar = frame:CreateTexture(nil, "ARTWORK")
    bar:SetWidth(2); bar:SetPoint("TOPLEFT",0,-52); bar:SetPoint("BOTTOMLEFT")
    bar:SetColorTexture(ac[1], ac[2], ac[3], 0.6)

    local nameFs = Th.Fs(frame, "subheader", "No player selected", "textPrimary")
    nameFs:SetPoint("TOPLEFT", P, -P); nameFs:SetWidth(Th.detailWidth - P*2)
    self.nameLabel = nameFs

    local rankFs = Th.Fs(frame, "small", "", "textSecond")
    rankFs:SetPoint("TOPLEFT", P, -(P+18)); rankFs:SetWidth(Th.detailWidth - P*2)
    self.rankLabel = rankFs

    local statusFs = Th.Fs(frame, "status", "", "statusActive")
    statusFs:SetPoint("TOPRIGHT", -P, -P-4)
    self.statusLabel = statusFs

    -- Scroll area for editable content
    local scroll = CreateFrame("ScrollFrame", nil, frame)
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -56)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta)
        scroll:SetVerticalScroll(math.max(0, scroll:GetVerticalScroll() - delta*24))
    end)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(Th.detailWidth)
    scroll:SetScrollChild(content)
    self.content = content

    local y = 0
    local function gap(n)    y = y - (n or Th.sectionGap) end
    local function secLabel(txt)
        gap(4)
        local fs = Th.Fs(content, "tiny", txt, "textDimmed")
        fs:SetPoint("TOPLEFT", P, y); gap(14)
        local sep = content:CreateTexture(nil,"ARTWORK"); sep:SetHeight(1)
        sep:SetPoint("TOPLEFT",content,"TOPLEFT",P,y); sep:SetPoint("TOPRIGHT",content,"TOPRIGHT",-P,y)
        local sc = Th.c.separator; sep:SetColorTexture(sc[1],sc[2],sc[3],sc[4])
        gap(6)
    end

    gap(-4)
    secLabel("PLAYER INFO")
    local joinDisplay = Th.Fs(content,"small","Joined: —","textSecond"); joinDisplay:SetPoint("TOPLEFT",P,y); gap(16); self.joinDisplay=joinDisplay
    local firstSeenDisplay = Th.Fs(content,"small","First seen: —","textSecond"); firstSeenDisplay:SetPoint("TOPLEFT",P,y); gap(16); self.firstSeenDisplay=firstSeenDisplay
    local seenDisplay = Th.Fs(content,"small","Last seen: —","textSecond"); seenDisplay:SetPoint("TOPLEFT",P,y); gap(16); self.seenDisplay=seenDisplay
    local locationDisplay = Th.Fs(content,"small","Location: —","textSecond"); locationDisplay:SetPoint("TOPLEFT",P,y); gap(16); self.locationDisplay=locationDisplay
    local ptsDisplay  = Th.Fs(content,"small","Points: 0","textSecond");  ptsDisplay:SetPoint("TOPLEFT",P,y);  gap(16); self.ptsDisplay=ptsDisplay
    local roleDisplay = Th.Fs(content,"small","Classification: Unknown","textSecond"); roleDisplay:SetPoint("TOPLEFT",P,y); gap(16); self.roleDisplay=roleDisplay
    local mainDisplay = Th.Fs(content,"small","Main: —","textSecond");    mainDisplay:SetPoint("TOPLEFT",P,y); gap(16); self.mainDisplay=mainDisplay
    local altDisplay  = Th.Fs(content,"small","Alts: —","textSecond");    altDisplay:SetPoint("TOPLEFT",P,y);  gap(16); self.altDisplay=altDisplay
    local discordDisplay = Th.Fs(content,"small","Discord: —","textSecond"); discordDisplay:SetPoint("TOPLEFT",P,y); gap(20); self.discordDisplay=discordDisplay

    secLabel("CUSTOM NOTE")
    local noteBox = GC.UI.Panel.Input(content, Th.detailWidth - P*2, Th.inputH)
    noteBox:SetPoint("TOPLEFT",P,y); noteBox:SetMaxLetters(150); gap(Th.inputH+4); self.noteBox=noteBox
    local saveNoteBtn = GC.UI.Button.Create(content,"Save Note","primary",Th.detailWidth-P*2,Th.btnH)
    saveNoteBtn:SetPoint("TOPLEFT",P,y); gap(Th.btnH+Th.sectionGap)
    saveNoteBtn:SetScript("OnClick",function()
        if not currentPlayer then return end
        local live = DS():GetPlayer(currentPlayer.key) or {}
        live.notes = live.notes or {}; live.notes.custom = noteBox:GetText() or ""
        DS():SavePlayer(currentPlayer.key,{notes=live.notes})
        GC.UI.MainFrame:SetStatus("Note saved.","textSuccess")
    end)

    secLabel("DISCORD NAME")
    local discordBox = GC.UI.Panel.Input(content, Th.detailWidth - P*2, Th.inputH)
    discordBox:SetPoint("TOPLEFT", P, y); discordBox:SetMaxLetters(64); gap(Th.inputH+4); self.discordBox = discordBox
    local saveDiscordBtn = GC.UI.Button.Create(content,"Save Discord","primary",Th.detailWidth-P*2,Th.btnH)
    saveDiscordBtn:SetPoint("TOPLEFT",P,y); gap(Th.btnH+Th.sectionGap)
    saveDiscordBtn:SetScript("OnClick",function()
        if not currentPlayer then return end
        local live = DS():GetPlayer(currentPlayer.key) or {}
        live.officerData = live.officerData or {}
        live.officerData.discordName = GC.Utils.Trim(discordBox:GetText() or "")
        DS():SavePlayer(currentPlayer.key,{officerData=live.officerData})
        GC.UI.MainFrame:SetStatus("Discord name saved.","textSuccess")
        PP:Refresh()
    end)

    secLabel("JOIN DATE")
    local joinBox = GC.UI.Panel.Input(content, Th.detailWidth-P*2, Th.inputH)
    joinBox:SetPoint("TOPLEFT",P,y); joinBox:SetMaxLetters(10); gap(Th.inputH+4); self.joinBox=joinBox
    local saveDateBtn = GC.UI.Button.Create(content,"Save Date","primary",Th.detailWidth-P*2,Th.btnH)
    saveDateBtn:SetPoint("TOPLEFT",P,y); gap(Th.btnH+Th.sectionGap)
    saveDateBtn:SetScript("OnClick",function()
        if not currentPlayer then return end
        local ts = parseDateToTimestamp(joinBox:GetText() or "")
        if not ts then GC.UI.MainFrame:SetStatus("Invalid date. Use YYYY-MM-DD.","textDanger"); return end
        DS():SavePlayer(currentPlayer.key,{joinedAt=ts, joinedAtSource="manual"})
        GC.UI.MainFrame:SetStatus("Join date saved.","textSuccess"); PP:Refresh()
    end)

    secLabel("POINTS ADJUSTMENT")
    local amtBox = GC.UI.Panel.Input(content,60,Th.inputH); amtBox:SetPoint("TOPLEFT",P,y); amtBox:SetMaxLetters(6); self.amtBox=amtBox
    local rsnBox = GC.UI.Panel.Input(content,Th.detailWidth-P*2-68,Th.inputH); rsnBox:SetPoint("LEFT",amtBox,"RIGHT",8,0); rsnBox:SetMaxLetters(64); self.rsnBox=rsnBox
    gap(Th.inputH+4)
    local applyBtn = GC.UI.Button.Create(content,"Apply Points","success",Th.detailWidth-P*2,Th.btnH)
    applyBtn:SetPoint("TOPLEFT",P,y); gap(Th.btnH+Th.sectionGap)
    applyBtn:SetScript("OnClick",function()
        if not currentPlayer then return end
        local amt = tonumber(amtBox:GetText())
        if not amt then GC.UI.MainFrame:SetStatus("Enter a valid number.","textDanger"); return end
        if GC.Services.Points then GC.Services.Points:AddPoints(currentPlayer.key,amt,rsnBox:GetText()) end
        amtBox:SetText(""); rsnBox:SetText("")
        GC.UI.MainFrame:SetStatus(string.format("Points adjusted: %+d",amt),"textSuccess"); PP:Refresh()
    end)

    secLabel("MAIN / ALT")
    local setMainBtn = GC.UI.Button.Create(content,"Mark as Main","secondary",Th.detailWidth-P*2,Th.btnH)
    setMainBtn:SetPoint("TOPLEFT",P,y); gap(Th.btnH+4)
    setMainBtn:SetScript("OnClick",function()
        if not currentPlayer then return end
        local ok, err = GC.Services.Alts:SetMain(currentPlayer.key, "player-panel")
        GC.UI.MainFrame:SetStatus(ok and "Character marked as Main." or err, ok and "textSuccess" or "textDanger")
        if ok then PP:Refresh() end
    end)
    local setUnknownBtn = GC.UI.Button.Create(content,"Mark as Unknown","secondary",Th.detailWidth-P*2,Th.btnH)
    setUnknownBtn:SetPoint("TOPLEFT",P,y); gap(Th.btnH+4)
    setUnknownBtn:SetScript("OnClick",function()
        if not currentPlayer then return end
        local ok, err = GC.Services.Alts:SetUnknown(currentPlayer.key, "player-panel")
        GC.UI.MainFrame:SetStatus(ok and "Character marked as Unknown." or err, ok and "textWarn" or "textDanger")
        if ok then PP:Refresh() end
    end)
    local mainBox = GC.UI.Panel.Input(content, Th.detailWidth-P*2, Th.inputH)
    mainBox:SetPoint("TOPLEFT", P, y); mainBox:SetMaxLetters(40); gap(Th.inputH+4); self.mainLinkBox=mainBox
    local linkBtn = GC.UI.Button.Create(content,"Link as Alt to Main","secondary",Th.detailWidth-P*2,Th.btnH)
    linkBtn:SetPoint("TOPLEFT",P,y); gap(Th.btnH+4)
    linkBtn:SetScript("OnClick",function()
        if not currentPlayer then return end
        local mainKey = GS():ResolvePlayerKey(mainBox:GetText() or "")
        if not mainKey then
            GC.UI.MainFrame:SetStatus("Enter a known main character name or key.","textDanger")
            return
        end
        local ok, err = GC.Services.Alts:SetAlt(currentPlayer.key, mainKey, "player-panel")
        GC.UI.MainFrame:SetStatus(ok and "Alt link saved." or err, ok and "textSuccess" or "textDanger")
        if ok then PP:Refresh() end
    end)
    local unlinkBtn = GC.UI.Button.Create(content,"Remove Alt Link","danger",Th.detailWidth-P*2,Th.btnH)
    unlinkBtn:SetPoint("TOPLEFT",P,y); gap(Th.btnH+4)
    unlinkBtn:SetScript("OnClick",function()
        if not currentPlayer then return end
        local ok, err = GC.Services.Alts:UnlinkAlt(currentPlayer.key, "player-panel")
        GC.UI.MainFrame:SetStatus(ok and "Alt link removed." or err, ok and "textWarn" or "textDanger")
        if ok then PP:Refresh() end
    end)

    secLabel("OFFICER ACTIONS")
    local promoteBtn = GC.UI.Button.CreateSecure(content,"Promote","secondary",Th.detailWidth-P*2,Th.btnH)
    promoteBtn:SetPoint("TOPLEFT",P,y); gap(Th.btnH+4); self.promoteBtn = promoteBtn
    promoteBtn:RegisterForClicks("AnyUp")
    promoteBtn:SetAttribute("type", "macro")
    promoteBtn:SetScript("PostClick",function()
        if not currentPlayer or not OPS() then return end
        local live = DS():GetPlayer(currentPlayer.key) or currentPlayer
        local message = string.format("%s promotion requested. Guild roster will refresh shortly.", live.name or "Member")
        appendOfficerActionLog(live.key, "Promotion requested", message)
        setOfficerActionFeedback(PP, message, "textSuccess")
        requestOfficerActionRefresh()
    end)

    local demoteBtn = GC.UI.Button.CreateSecure(content,"Demote","secondary",Th.detailWidth-P*2,Th.btnH)
    demoteBtn:SetPoint("TOPLEFT",P,y); gap(Th.btnH+4); self.demoteBtn = demoteBtn
    demoteBtn:RegisterForClicks("AnyUp")
    demoteBtn:SetAttribute("type", "macro")
    demoteBtn:SetScript("PostClick",function()
        if not currentPlayer or not OPS() then return end
        local live = DS():GetPlayer(currentPlayer.key) or currentPlayer
        local message = string.format("%s demotion requested. Guild roster will refresh shortly.", live.name or "Member")
        appendOfficerActionLog(live.key, "Demotion requested", message)
        setOfficerActionFeedback(PP, message, "textWarn")
        requestOfficerActionRefresh()
    end)

    local kickBtn = GC.UI.Button.CreateSecure(content,"Kick From Guild","danger",Th.detailWidth-P*2,Th.btnH)
    kickBtn:SetPoint("TOPLEFT",P,y); gap(Th.btnH+4); self.kickBtn = kickBtn
    kickBtn:RegisterForClicks("AnyUp")
    kickBtn:SetAttribute("type", "macro")
    kickBtn:SetScript("PostClick",function()
        if not currentPlayer or not OPS() then return end
        local live = DS():GetPlayer(currentPlayer.key) or currentPlayer
        local message = string.format("%s removal requested. Guild roster will refresh shortly.", live.name or "Member")
        appendOfficerActionLog(live.key, "Guild removal requested", message)
        setOfficerActionFeedback(PP, message, "textWarn")
        requestOfficerActionRefresh()
    end)

    local actionResult = Th.Fs(content, "small", "", "textDimmed")
    actionResult:SetPoint("TOPLEFT", P, y)
    actionResult:SetPoint("TOPRIGHT", content, "TOPRIGHT", -P, y)
    actionResult:SetWordWrap(true)
    gap(28)
    self.actionResult = actionResult

    local actionHint = Th.Fs(content, "small", "", "textDimmed")
    actionHint:SetPoint("TOPLEFT", P, y)
    actionHint:SetPoint("TOPRIGHT", content, "TOPRIGHT", -P, y)
    actionHint:SetWordWrap(true)
    gap(22)
    self.actionHint = actionHint

    content:SetHeight(math.abs(y)+P)
end

function PP:Refresh()
    if not self.frame then return end
    if not currentPlayer then
        self.nameLabel:SetText("No player selected"); self.rankLabel:SetText(""); self.statusLabel:SetText("")
        self.joinDisplay:SetText("Joined: —"); self.firstSeenDisplay:SetText("First seen: —"); self.seenDisplay:SetText("Last seen: —"); self.locationDisplay:SetText("Location: —")
        self.ptsDisplay:SetText("Points: 0"); self.roleDisplay:SetText("Classification: Unknown"); self.mainDisplay:SetText("Main: —"); self.altDisplay:SetText("Alts: —"); self.discordDisplay:SetText("Discord: —")
        self.noteBox:SetText(""); self.discordBox:SetText(""); self.joinBox:SetText(""); self.mainLinkBox:SetText("")
        if self.promoteBtn then self.promoteBtn:SetEnabled(false) end
        if self.demoteBtn then self.demoteBtn:SetEnabled(false) end
        if self.kickBtn then self.kickBtn:SetEnabled(false) end
        if self.promoteBtn then self.promoteBtn:SetAttribute("macrotext", nil) end
        if self.demoteBtn then self.demoteBtn:SetAttribute("macrotext", nil) end
        if self.kickBtn then self.kickBtn:SetAttribute("macrotext", nil) end
        self.pendingActionMessage = nil
        self.pendingActionColorKey = nil
        if self.actionResult then self.actionResult:SetText("") end
        if self.actionHint then self.actionHint:SetText("Select a guild member to view officer actions.") end
        return
    end
    local Th  = T()
    local p   = GS():GetRosterEntry(currentPlayer.key) or currentPlayer
    currentPlayer = p
    local live = DS():GetPlayer(p.key) or p
    local rgb = p.classRGB or {1,1,1}
    self.nameLabel:SetText(p.name or "Unknown"); self.nameLabel:SetTextColor(rgb[1],rgb[2],rgb[3],1)
    local classLine = p.specDisplay and (p.classDisplayName .. " / " .. p.specDisplay) or (p.classDisplayName or p.class or "—")
    self.rankLabel:SetText(string.format("%s  ·  %s  ·  L%s", p.rankName or "—", classLine, tostring(p.level or "?")))
    local sc = p.statusKey and Th.c[p.statusKey] or Th.c.textDimmed
    self.statusLabel:SetText(p.statusLabel or ""); self.statusLabel:SetTextColor(sc[1],sc[2],sc[3],sc[4] or 1)
    self.joinDisplay:SetText("Joined: "..(p.joinedDisplay or "—"))
    self.firstSeenDisplay:SetText("First seen: "..(p.firstSeenDisplay or "—"))
    self.seenDisplay:SetText("Last seen: "..(p.lastSeenDisplay or "—"))
    self.locationDisplay:SetText("Location: "..(p.locationDisplay or live.zone or "—"))
    self.ptsDisplay:SetText("Points: "..tostring(live.points and live.points.balance or 0))
    self.roleDisplay:SetText("Classification: "..(p.classificationLabel or "Unknown"))
    self.mainDisplay:SetText("Main: "..(live.main and (live.main:match("^([^%-]+)") or live.main) or "—"))
    local alts = live.alts or {}
    self.altDisplay:SetText("Alts: "..(#alts>0 and table.concat(alts,", ") or "None"))
    local officerData = live.officerData or {}
    local discordBits = {}
    if officerData.discordVerified ~= nil then
        discordBits[#discordBits + 1] = officerData.discordVerified and "verified" or "not verified"
    end
    if officerData.discordName and officerData.discordName ~= "" then
        discordBits[#discordBits + 1] = officerData.discordName
    end
    self.discordDisplay:SetText("Discord: "..(#discordBits > 0 and table.concat(discordBits, " · ") or "—"))
    self.noteBox:SetText(live.notes and live.notes.custom or "")
    self.discordBox:SetText(officerData.discordName or "")
    self.joinBox:SetText(p.joinedAt and date("%Y-%m-%d",p.joinedAt) or "")
    self.mainLinkBox:SetText(live.main or "")
    self.amtBox:SetText(""); self.rsnBox:SetText("")
    if self.actionResult then
        local color = T().c[self.pendingActionColorKey or "textDimmed"] or T().c.textDimmed
        self.actionResult:SetTextColor(color[1], color[2], color[3], color[4] or 1)
        self.actionResult:SetText(self.pendingActionMessage or "")
    end

    local availability = OPS() and OPS():GetActionAvailability(live) or nil
    if availability then
        if self.promoteBtn then self.promoteBtn:SetEnabled(availability.promote.enabled) end
        if self.demoteBtn then self.demoteBtn:SetEnabled(availability.demote.enabled) end
        if self.kickBtn then self.kickBtn:SetEnabled(availability.kick.enabled) end
        if self.promoteBtn then
            self.promoteBtn:SetAttribute("macrotext", availability.promote.enabled and buildOfficerMacro("guildpromote", live) or nil)
        end
        if self.demoteBtn then
            self.demoteBtn:SetAttribute("macrotext", availability.demote.enabled and buildOfficerMacro("guilddemote", live) or nil)
        end
        if self.kickBtn then
            self.kickBtn:SetAttribute("macrotext", availability.kick.enabled and buildOfficerMacro("guildremove", live) or nil)
        end

        if self.actionHint then
            if not availability.isOfficer then
                self.actionHint:SetText("Officer actions are only available to ranks allowed in Settings.")
            elseif availability.promote.enabled or availability.demote.enabled or availability.kick.enabled then
                self.actionHint:SetText("You may manage only guild members below your rank.")
            else
                local reason = availability.promote.reason or availability.demote.reason or availability.kick.reason or "No officer actions available for this member."
                self.actionHint:SetText(reason)
            end
        end
    end
end

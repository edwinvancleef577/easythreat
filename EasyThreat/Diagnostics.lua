local E=EasyThreat
function E:UIDependencies()
    local names={}
    local count=self:Call(GetNumAddOns) or 0
    for i=1,count do
        local name=self:Call(GetAddOnInfo,i)
        local lower=type(name)=="string" and string.lower(name) or ""
        if name and name~="EasyThreat" and self:Call(IsAddOnLoaded,name) and
            (string.find(lower,"tooltip",1,true) or string.find(lower,"tip",1,true) or
            string.find(lower,"dragonflight",1,true) or lower=="pfui" or string.find(lower,"shagu",1,true)) then
            table.insert(names,name)
        end
    end
    return table.concat(names,", ")
end
E.diagnosticColors={error={1,0.38,0.32},warning={1,0.83,0.26},info={0.48,0.77,1}}
function E:ServerDiagnosis()
    local state=self:ServerQueryState()
    if state=="disabled" then return "info","Addon disabled. Enable EasyThreat in Displays." end
    if state=="transport" then return "error","Server messages unavailable. Reload the UI and check the client." end
    if state=="coordinated" then return "info","Server: another EasyThreat player coordinates queries." end
    if state=="target" or state=="combat" then
        return "info","Server: select a living enemy in combat. Normal enemies and solo play are queried too."
    end
    if state=="foreign" then return "warning","Server query overlaps another threat addon. Test with only one meter querying." end
    if state=="changed" then return "info","Server: target changed; briefly waiting to avoid mixing enemies." end
    if self.serverSendError then return "error","Server request failed. Reload the UI; print diagnostics if it repeats." end
    local watch=self.serverWatch
    if watch and watch.guid==self:GUID("target") then
        if watch.accepted>0 and self.serverMetrics and GetTime()-(self.serverMetrics.lastReply or -10)<3 then
            return "info","Server: %d replies assigned to this target. Assignment is checked separately from display.",watch.accepted
        end
        if watch.sent>=3 and GetTime()-watch.at>=5 then
            if watch.received>0 then
                local reasons={format="Unknown packet format",sender="Unverified sender",channel="Wrong channel",
                    expired="Expired reply",target="Changed target",foreign="Overlapping query"}
                return "warning","Server: replies could not be assigned safely (%s). Use /et trace on.",self:L(reasons[self.serverRejectReason] or "Unverified sender")
            end
            return "warning","Server: no recent reply after %d requests. Run /et test start and share /et test show.",watch.sent
        end
        return "info","Server: waiting for a reply."
    end
    return "info","Server: ready to query the selected enemy."
end
function E:DiagnosisEntries()
    local lines={}
    local function add(key,a,b,severity) table.insert(lines,{text=E:L(key,a,b),severity=severity or "info",order=table.getn(lines)+1}) end
    add("Build: %s",self.build)
    if not self.db.enabled then add("Addon disabled. Enable EasyThreat in Displays.") end
    if not self:OutputEnabled("tooltip") then add("Tooltip disabled for %s. Enable it in the Displays table.",self:L(self.roleLabels[self:Role(self.playerKey)])) end
    add("Your role: %s. Displays apply to your character.",self:L(self.roleLabels[self:Role(self.playerKey)]))
    self:DisplayStatusLines(add)
    if self.targetDisplayReason then add("Target frame: %s",self:L(self.targetDisplayReason,self.db.threshold)) end
    if self.plateDisplayReason then add(self.plateDisplayReason) end
    local context=self:GroupContext()
    if not self.db.filters.context[context] then add("%s display disabled in Enemy filters.",self:L(context=="party" and "Party" or context=="raid" and "Raid" or "Solo")) end
    if context=="raid" and self.db.filters.context.raid then add("Raid support is experimental. Assign every tank in Roles.") end
    if not GameTooltip then add("GameTooltip is missing. This custom tooltip needs an adapter.",nil,nil,"error")
    elseif self.tooltipError then add("Tooltip error: %s",self.tooltipError,nil,"error")
    else
        local diagnostic=self.tooltipDiagnostic
        if not diagnostic then add("No enemy tooltip recorded. Hover an enemy during combat.")
        else
            add("Last enemy tooltip: %s (%ds ago)",diagnostic.name,math.floor(GetTime()-diagnostic.at))
            local reason=diagnostic.reason
            if reason=="visible" then add("The threat footer was displayed successfully.")
            elseif reason=="empty-idle" then add("Empty bars outside combat")
            elseif reason=="held" then add("Last value")
            elseif reason=="hidden" then add("The standard tooltip stayed hidden. A custom tooltip may need a separate adapter.",nil,nil,"warning")
            elseif reason=="combat" then add("No combat detected. Test while you or your pet are fighting.")
            elseif reason=="source" then add("No usable threat data. Target this enemy and check the sources below.",nil,nil,"warning")
            elseif reason=="threshold" then add("Threat below %d%%. Lower the threshold or use Positions > Preview.",self.db.threshold)
            elseif reason=="filter" then add("Enemy hidden by filters. Check Enemy filters.")
            elseif reason=="withheld" then add("Threat calculation incomplete; see class warnings. The display is enabled.",nil,nil,"warning")
            else add("Tooltip unit unresolved. Try the standard tooltip or reload the UI.",nil,nil,"warning") end
        end
    end
    if self.tooltipHookError then add("Another tooltip hook raised an error: %s",self.tooltipHookError,nil,"error")
    elseif self.tooltipHookReplaced or self.tooltipFrameReplaced then add("Tooltip integration was replaced and has been reattached.") end
    local severity,key,value=self:ServerDiagnosis(); add(key,value,nil,severity)
    local sm=self.serverMetrics or {}
    add("Server requests: %d; replies: %d.",sm.sent or 0,sm.received or 0)
    add("Server assigned: %d; used: %d.",sm.accepted or 0,sm.used or 0)
    local test=self:GetSourceTest()
    if test then
        for _,entry in ipairs(self:SourceTestLines(test)) do add("%s",entry.text,nil,entry.severity) end
    else add("Source test: /et test start, fight normally, then /et test show.") end
    self:AppendDependencyDiagnosis(add)
    if self.spellTooltipError then add("Skill tooltip error: %s",self.spellTooltipError,nil,"error") end
    local spell=self.spellTooltipLast
    if self.db.spellThreatTooltip and spell then
        add("Last spell: %s",self:L("Spell identity: %s / ID %s / rank %s",spell.name or "?",tostring(spell.id or "?"),tostring(spell.rank or "?")))
        add("Spell lookup: %s",(spell.method or "?").." / "..(spell.source or "?"))
        local known=spell.status=="ok" or spell.status=="none" or spell.status=="special"
        add("Spell result: %s",spell.message,nil,known and "info" or "warning")
    end
    if self.caps and self.caps.super then add("SuperWoW transport help") end
    local current=self.enemies[self:GUID("target") or ""]
    for key,sample in pairs(current and current.samples or {}) do
        if sample.rangeSource=="conservative" and (not current.owner or key~=current.owner.key) then
            add("Conservative range help"); break
        end
    end
    if self.targetIssue then add(self.targetMessages[self.targetIssue],nil,nil,
        self.targetIssue=="blocked" and "error" or self.targetIssue=="identity" and "warning" or "info") end
    if self:GUID("player") then add("Events: %s. ~ marks estimated percentages; AGGRO is a state label.",self.localBackend or "CHAT_MSG") end
    self:AppendClassDiagnosis(lines)
    if not self.db.groupSync then add("Group exchange disabled.")
    else
        local count,total=1,0
        for _,m in ipairs(self.roster) do if not m.pet and m.connected then total=total+1; if self:PeerProfile(m) then count=count+1 end end end
        add("Group exchange: %d/%d players available.",count,total)
        local timing=self:PeerTimingSnapshot(self:GUID("target"))
        if timing.last and timing.responseAge<15 then
            add("Threat reply: %d ms; average %d ms.",math.floor(timing.last*1000+.5),math.floor(timing.average*1000+.5))
            if timing.last>1.2 then add("Threat reply delayed help",nil,nil,"warning") end
        end
        for _,actor in ipairs(timing.actors) do
            local member=self:MemberForGUID(actor.actor)
            if member and not member.pet then add("%s: shared threat received %.1f s ago.",member.name,actor.age) end
        end
        if self.peerRejects and self.peerRejects.version then add("Different rule versions in group. Update EasyThreat on all clients.",nil,nil,"warning") end
    end
    if EasyThreatRecorder and EasyThreatRecorder.db then
        local r=EasyThreatRecorder; local session=r.db.sessionDiagnostics
        if session then
            if session.stop=="storage-limit" or session.detailLimit then add("Recording storage full. Export before clearing.",nil,nil,"warning") end
            if session.stop=="30-minutes" then add("Thirty-minute recording finished. Export the session.") end
            if r.sessionFault then add("Session diagnostics failed. Export the existing recording.",nil,nil,"error") end
            add("Session: %d clips retained. Build %s.",table.getn(r.db.clips),self.build)
        end
        table.insert(lines,{text=self:RecordingStatus(),severity=EasyThreatRecorder.fault and "error" or "info",order=table.getn(lines)+1})
    end
    local group=self.groupRecorder
    -- Profiles and recordings share the same client transport. Report a common
    -- failure once; retain distinct technical details without counting them as
    -- additional failures of the addon.
    if (self.db.groupSync and self.peerSendError) or (group and group.sendError) then
        add("Group messages could not be sent.",nil,nil,"error")
        local seen,escape={},false
        local function detail(reason)
            if reason and not seen[reason] then
                seen[reason]=true
                add("Client send error: %s",reason)
                if string.find(string.lower(reason),"invalid escape",1,true) then escape=true end
            end
        end
        if self.peerSendError then detail(self.peerSendReason) end
        if group then detail(group.sendError) end
        if escape then
            add("Client rejected chat escape characters. Update EasyThreat on all party clients and reload the UI.",nil,nil,"warning")
        else
            add("Local combat events still work. Reload the UI; if sending fails again, share this error.",nil,nil,"warning")
        end
    end
    if group then
        if group.captureError then add("Group recording failed; local recordings remain available.",nil,nil,"error") end
        if (group.queueCount or 0)>0 then add("Queued recordings: %d clips. Transfer continues after combat.",group.queueCount) end
        if group:Bundle() then
            local complete,total,combat=group:Progress()
            -- An empty local capture is not a missing remote response. Keep
            -- completeness counters for export, explain current states here.
            local remotes=0
            for _,member in pairs(group:Bundle().members) do
                if not member.isLocal and group:ExpectedMember(member) then remotes=remotes+1 end
            end
            if remotes==0 then add("No other online party members. Recording locally.")
            else add("Group recordings received: %d/%d clients.",complete,total,"info") end
            if combat then add("Recording in progress. Wait until after combat for transfer.") end
            local bundle=group:Bundle()
            add("Group storage: %d/%d clips.",bundle.clips,bundle.limits and bundle.limits.clips or 48)
            for _,member in pairs(group:Bundle().members) do
                local severity,message=group:MemberStatus(member)
                add("%s: %s",member.isLocal and self:L("This client") or member.class,self:L(message),severity)
            end
        end
    end
    if self.missingPlaques and next(self.missingPlaques) then
        add("Role plaques unavailable. Exit the game completely, copy the full EasyThreat folder including Media, then restart.",nil,nil,"warning")
    end
    if self.journal and self.journal.missingIcons then
        local missing={}
        for name in pairs(self.journal.missingIcons) do table.insert(missing,name) end
        if table.getn(missing)>0 then
            table.sort(missing)
            add("Journal icons unavailable: %s. Exit the game completely, copy the full EasyThreat folder, then restart.",table.concat(missing,", "),nil,"warning")
        end
    end
    if self.journal and self.journal.fault then
        add("Journal capture failed",nil,nil,"error")
        add("%s",tostring(self.journal.fault),nil,"error")
    elseif self.db.journalEnabled and self.journal and self.journal.db and self.journal.db.last then
        add("Journal local observations only")
        if self.journal.db.last.notes["Journal capture limit reached"] then add("Journal capture limit reached",nil,nil,"warning") end
    end
    local addons=self:UIDependencies()
    if addons~="" then add("Loaded UI/tooltip addons: %s",addons) end
    local priority={error=1,warning=2,info=3}
    table.sort(lines,function(a,b)
        if a.severity~=b.severity then return priority[a.severity]<priority[b.severity] end
        return a.order<b.order
    end)
    return lines
end
function E:DiagnosisLines(colored)
    local lines={}
    for _,entry in ipairs(self:DiagnosisEntries()) do
        local prefix=self:L(entry.severity=="error" and "Error" or entry.severity=="warning" and "Warning" or "Info")..": "
        local color=entry.severity=="error" and "|cffff6152" or entry.severity=="warning" and "|cffffd442" or "|cff7ac4ff"
        table.insert(lines,(colored and color or "")..prefix..entry.text..(colored and "|r" or ""))
    end
    return lines
end
function E:BuildDiagnostics(pane)
    pane.lines={}; pane.offset=0
    pane.range=self:Text(pane,9); pane.range:SetPoint("TOPRIGHT",pane,"TOPRIGHT",-16,-74)
    pane.summary=self:Text(pane,10); pane.summary:SetWidth(250); pane.summary:SetHeight(13)
    pane.summary:SetPoint("TOPLEFT",pane,"TOPLEFT",16,-73)
    pane:EnableMouseWheel(true)
    pane:SetScript("OnMouseWheel",function() pane.offset=pane.offset-(arg1 or 0); E:UpdateDiagnostics() end)
    for i=1,5 do
        local label=self:Text(pane,10)
        label:SetWidth(358); label:SetHeight(34); label:SetJustifyV("TOP")
        label:SetPoint("TOPLEFT",pane,"TOPLEFT",16,-87-(i-1)*35)
        pane.lines[i]=label
    end
    local function toggle(label,x,callback)
        local button=E:Place(pane,E:Button(pane,label,171,25,callback),x,302)
        button.text:SetWidth(121); button.text:ClearAllPoints(); button.text:SetPoint("CENTER",button,"CENTER",-17,0)
        E:RegisterFont(button.text,10,"OUTLINE")
        button.state=E:Text(button,9); button.state:SetWidth(35); button.state:SetJustifyH("CENTER")
        button.state:SetPoint("RIGHT",button,"RIGHT",-3,0)
        return button
    end
    pane.sync=toggle("Group exchange",16,function() E.db.groupSync=not E.db.groupSync; E:ResetPeers(); E:UpdateDiagnostics() end)
    pane.collect=toggle("Collect group recordings",16,function() E:RecordingCommand("collect") end)
    pane.share=toggle("Share recordings",203,function() E:RecordingCommand("share") end)
    self:Place(pane,pane.collect,16,272); self:Place(pane,pane.share,203,272)
    pane.record=toggle("Record 30-minute session",203,function()
        local r=EasyThreatRecorder; E:RecordingCommand(r and r.db and r.db.enabled and "off" or "on"); E:UpdateDiagnostics()
    end)
    pane.mark=E:Place(pane,E:Button(pane,"Mark problem",171,25,function() E:RecordingCommand("mark") end),16,332)
    pane.recordExport=E:Place(pane,E:Button(pane,"Export recording",171,25,function() E:ShowRecordingExport() end),203,332)
    E:RegisterFont(pane.recordExport.text,10,"OUTLINE")
    pane.refresh=self:Place(pane,self:Button(pane,"Refresh",171,25,function() E:InitThreatTooltip(); E:UpdateDiagnostics() end),16,374)
    pane.print=self:Place(pane,self:Button(pane,"Print to chat",171,25,function() E:Status() end),203,374)
    pane.export=self:Place(pane,self:Button(pane,"Export settings",171,25,function() E:ShowSettingsExport() end),16,404)
    pane.import=self:Place(pane,self:Button(pane,"Import settings",171,25,function() E:ShowSettingsImport() end),203,404)
    self:RegisterFont(pane.export.text,10,"OUTLINE"); self:RegisterFont(pane.import.text,10,"OUTLINE")
    pane.undo=self:Place(pane,self:Button(pane,"Undo import",358,20,function()
        local ok,problem=E:UndoSettingsImport()
        if not ok then E:Print(E:ImportMessage(problem)) end
        E:UpdateDiagnostics()
    end),16,435)
end
function E:UpdateDiagnostics()
    local pane=self.pages and self.pages.diagnostics
    if not pane then return end
    if pane.exportMode then return end
    pane.sync:Show(); pane.record:Show(); pane.mark:Show(); pane.recordExport:Show()
    pane.collect:Show(); pane.share:Show()
    self:SetToggleState(pane.collect,self.recorder and self.recorder.db and self.recorder.db.collectGroup)
    self:SetToggleState(pane.share,self.groupRecorder and self.groupRecorder.sharing)
    self:SetToggleState(pane.sync,self.db.groupSync)
    self:SetToggleState(pane.record,EasyThreatRecorder and EasyThreatRecorder.db and EasyThreatRecorder.db.enabled)
    pane.refresh:Show(); pane.print:Show(); pane.export:Show(); pane.import:Show(); pane.range:Show()
    if self.importUndo then pane.undo:Show() else pane.undo:Hide() end
    local lines=self:DiagnosisEntries()
    local errors,warnings=0,0
    for _,entry in ipairs(lines) do
        if entry.severity=="error" then errors=errors+1 elseif entry.severity=="warning" then warnings=warnings+1 end
    end
    pane.summary:Show()
    pane.summary:SetText(self:L("%d errors / %d warnings",errors,warnings))
    pane.summary:SetTextColor(unpack(self.diagnosticColors[errors>0 and "error" or warnings>0 and "warning" or "info"]))
    local visible=table.getn(pane.lines)
    pane.offset=self:Clamp(pane.offset,0,math.max(0,table.getn(lines)-visible))
    pane.range:SetText(table.getn(lines)>visible and string.format("%d–%d / %d",pane.offset+1,pane.offset+visible,table.getn(lines)) or "")
    for i,label in ipairs(pane.lines) do
        label:Show()
        local entry=lines[i+pane.offset]
        if entry then
            local prefix=self:L(entry.severity=="error" and "Error" or entry.severity=="warning" and "Warning" or "Info")
            label:SetText(prefix..": "..entry.text); label:SetTextColor(unpack(self.diagnosticColors[entry.severity]))
        else label:SetText("") end
    end
end

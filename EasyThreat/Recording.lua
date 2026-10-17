-- Recording controls; local capture starts manually or for a shared party session.
local E=EasyThreat
function E:RecordingSession()
    local group=self.groupRecorder
    if group and group.job and group:Channel() and (group.collecting or
        (group.sharing and self:MemberForGUID(group.host))) then return group.job end
    if not self.peerBoot then self:ResetPeers() end
    local leader=self:GUID("player") or ""; local session=self.peerBoot
    for _,m in ipairs(self.roster) do
        local p=self:PeerProfile(m)
        if p and not m.pet and m.guid<leader then leader=m.guid; session=self.peerOwners[m.guid].boot end
    end
    return session
end
function E:JSON(value,maxBytes)
    local stack={}
    local bytes=0
    local function count(text)
        bytes=bytes+string.len(text)
        if maxBytes and bytes>maxBytes then error("record-size") end
        return text
    end
    local function quote(s)
        return '"'..string.gsub(s,'[%z\1-\31\\"]',function(c)
            if c=='"' then return '\\"' elseif c=='\\' then return '\\\\' end
            return string.format('\\u%04x',string.byte(c))
        end)..'"'
    end
    local encode
    encode=function(v,depth)
        if depth>20 then error("record-depth") end
        if type(v)=="number" then if v-v~=0 then error("record-number") end; return count(string.format("%.17g",v))
        elseif type(v)=="string" then return count(quote(v))
        elseif type(v)=="boolean" then return count(v and "true" or "false")
        elseif type(v)=="nil" then return count("null")
        elseif type(v)~="table" or stack[v] then error("record-type") end
        stack[v]=true
        local array,n,keys=true,0,{}
        for k in pairs(v) do
            n=n+1; table.insert(keys,k)
            if type(k)~="number" or k~=math.floor(k) or k<1 then array=false end
        end
        if n==0 or n~=table.getn(v) then array=false end
        count("{}"); if n>1 then count(string.rep(",",n-1)) end
        local out={}
        if array then for i=1,n do table.insert(out,encode(v[i],depth+1)) end
        else
            table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
            for _,k in ipairs(keys) do table.insert(out,count(quote(tostring(k))..":")..encode(v[k],depth+1)) end
        end
        stack[v]=nil
        return (array and "[" or "{")..table.concat(out,",")..(array and "]" or "}")
    end
    return encode(value,0)
end
function E:RecordingStatus()
    local r=EasyThreatRecorder
    if not r or not r.db then return self:L("Recorder module not loaded.") end
    if r.fault then return self:L("Recording stopped after an error. Threat display remains active.") end
    return self:L(r.db.enabled and "Recording ON: %d clips; %d events in current clip." or "Recording OFF: %d saved clips.",
        table.getn(r.db.clips),r.clip and table.getn(r.clip.events) or 0)
end
function E:ShowRecordingExport()
    local r=EasyThreatRecorder
    if not r or not r.db then self:Print(self:L("Recorder module not loaded.")); return end
    local group=self.groupRecorder and self.groupRecorder:Bundle()
    if group then
        local complete,total,combat=self.groupRecorder:Progress()
        group.transportComplete=complete==total and not combat and not self.groupRecorder.wanted and
            not self.groupRecorder.captureError and not self.groupRecorder.sendError
        group.inCombat=combat and true or false
    end
    if table.getn(r.db.clips)==0 and not group and not r.db.sessionDiagnostics then self:Print(self:L("No recording yet.")); return end
    -- Include all retained clips, not just the final death after a useful fight.
    local ok,text=pcall(function() return E:JSON({schema=1,sessionDiagnostics=r.db.sessionDiagnostics,clips=r.db.clips,group=group,
        capture={active=r.db.enabled and true or false,elapsed=r.sessionRun and (r.sessionRun.duration or GetTime()-r.sessionRun.monotonicStart),
            limitSeconds=1800,currentEvents=r.clip and table.getn(r.clip.events) or 0},
        journal=r.JournalEvidence and E.journal and r:JournalEvidence(E.journal.fight or (E.journal.db and E.journal.db.last)),
        transport=E.groupRecorder and E.groupRecorder:TransportSnapshot()},500000) end)
    if not ok then
        if string.find(tostring(text),"record-size",1,true) then return self:ShowSavedVariablesExport(-1) end
        return self:ShowSavedVariablesExport()
    end
    if string.len(text)>500000 then return self:ShowSavedVariablesExport(string.len(text)) end
    self:ShowPage("diagnostics"); self:OpenSettingsTransfer("recording",text)
    self.pages.diagnostics.exportPanel.hint:SetText(self:L(r.db.enabled and "Active recording: export is a snapshot. Longer sessions are shared as a saved file." or "Copy recording with Ctrl+C. No player names or chat text included."))
    return true
end
function E:ShowRecordingChoice()
    local group=self.groupRecorder
    if not group or not group:Bundle() or group.collecting then return end
    self:ShowPage("diagnostics")
    if not self.recordingChoice then
        local cover=CreateFrame("Button","EasyThreatRecordingChoice",self.window)
        cover:SetAllPoints(self.window); cover:SetFrameLevel(self.window:GetFrameLevel()+30); cover:EnableMouse(true)
        local panel=self:Box(cover,354,245)
        panel:SetPoint("CENTER",cover,"CENTER",0,0); panel:SetFrameLevel(cover:GetFrameLevel()+1)
        panel:SetBackdropColor(0.045,0.051,0.046,1)
        panel.title=self:Text(panel,13); panel.title:SetPoint("TOPLEFT",panel,"TOPLEFT",14,-14)
        self:BindText(panel.title,"Saved group recording")
        panel.message=self:Text(panel,11); panel.message:SetWidth(326); panel.message:SetHeight(68)
        panel.message:SetJustifyV("TOP"); panel.message:SetPoint("TOPLEFT",panel,"TOPLEFT",14,-43)
        cover.panel=panel; self.recordingChoice=cover
        panel.export=self:Place(panel,self:Button(panel,"Export recording",326,30,function()
            local saved=cover.bundle
            cover:Hide()
            if E:ShowRecordingExport() then E.pages.diagnostics.recordingChoiceBundle=saved
            else
                E:ShowRecordingChoice()
                panel.message:SetText(E:L("Copy SavedVariables/EasyThreat.lua after logout."))
            end
        end),14,117)
        panel.restart=self:Place(panel,self:Button(panel,"Discard recordings and start",326,30,function()
            local ok,problem=group:Restart(cover.bundle)
            if ok or not problem then cover:Hide(); E:UpdateDiagnostics()
            else panel.message:SetText(E:L(problem)) end
        end),14,158)
        panel.cancel=self:Place(panel,self:Button(panel,"Cancel",326,30,function() cover:Hide() end),14,199)
        cover:SetScript("OnHide",function() cover.bundle=nil end)
        if UISpecialFrames then table.insert(UISpecialFrames,"EasyThreatRecordingChoice") end
    end
    local cover=self.recordingChoice
    cover.bundle=group:Bundle()
    cover.panel.message:SetText(self:L("A group recording is saved. Export it, or discard the saved test recordings and start a new collection."))
    cover:Show()
end
function E:RecordingCommand(command)
    local r=EasyThreatRecorder
    if not r or not r.db then self:Print(self:L("Recorder module not loaded.")); return end
    if command=="on" then r:SetEnabled(true)
    elseif command=="off" then r:SetEnabled(false)
    elseif command=="mark" then if r.db.enabled then r:Mark("manual") else self:Print(self:RecordingStatus()) end
    elseif command=="export" then self:ShowRecordingExport()
    elseif command=="clear" then r:Clear()
    elseif command=="collect" then self.groupRecorder:Begin(not r.db.collectGroup)
    elseif command=="share" then self.groupRecorder:Share(not self.groupRecorder.sharing)
    else self:Print(self:RecordingStatus()) end
end

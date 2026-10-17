-- Passive, bounded source test. No fake combat, changed roles or hidden filters.
local E=EasyThreat
local function copy(t)
    if type(t)~="table" then return t end
    local out={}; for k,v in pairs(t) do out[k]=copy(v) end; return out
end
function E:GetSourceTest()
    if self.sourceTest then return self.sourceTest end
    local saved=self.recorder and self.recorder.db and self.recorder.db.sourceTest
    if saved then saved.active=false; self.sourceTest=saved end -- never resume an old monotonic clock
    return saved
end
function E:SourceTestEnemy(guid)
    local test=self:GetSourceTest()
    if not test or not guid then return end
    self.sourceTestEnemies=self.sourceTestEnemies or {}
    if not self.sourceTestEnemies[guid] then
        -- Ordinals are local to this short test; never export names/raw GUIDs.
        if (test.targets or 0)>=256 then test.targetLimit=true; return end
        test.targets=(test.targets or 0)+1; self.sourceTestEnemies[guid]=test.targets
    end
    return self.sourceTestEnemies[guid]
end
function E:SourceTestContext()
    local party=self:Call(GetNumPartyMembers) or 0
    local raid=self:Call(GetNumRaidMembers) or 0
    local state,guid=self:ServerTargetStatus()
    local context={group=raid>0 and "raid" or party>0 and "party" or "solo",party=party,raid=raid,
        onlinePlayers=0,players=0,pets=0,target={state=state,hasGUID=guid~=nil,enemy=self:SourceTestEnemy(guid)}}
    for _,m in ipairs(self.roster or {}) do
        if m.pet then context.pets=context.pets+1 else
            context.players=context.players+1
            if m.connected then context.onlinePlayers=context.onlinePlayers+1 end
        end
    end
    if state~="none" then
        context.target.kind=self:Call(UnitClassification,"target") or "unknown"
        context.target.level=self:Call(UnitLevel,"target")
    end
    return context
end
function E:NoteSourceQuery(prefix,channel,ok)
    local test=self:GetSourceTest(); if not test or not test.active then return end
    local context=self:SourceTestContext()
    local row={t=GetTime()-test.started,prefix=prefix,channel=channel,limit=self.serverRequestLimit,
        sent=ok,context=context}
    local key=context.group..":"..(context.target.kind or "unknown")
    test.queryContexts=test.queryContexts or {}
    if ok then
        test.queryContexts[key]=(test.queryContexts[key] or 0)+1
        local kind=context.target.kind
        if context.group~="solo" and (kind=="elite" or kind=="rareelite" or kind=="worldboss") then
            test.groupedEliteQueries=(test.groupedEliteQueries or 0)+1
        end
    end
    test.queries=test.queries or {}
    if table.getn(test.queries)<128 then table.insert(test.queries,row)
    else test.queriesOmitted=(test.queriesOmitted or 0)+1 end
end
function E:NoteSourceMessage(prefix,body,channel,sender)
    local test=self:GetSourceTest(); if not test or not test.active then return end
    local traffic=test.traffic or {}; test.traffic=traffic
    traffic.total=(traffic.total or 0)+1
    -- Classify traffic without retaining unrelated addons' payloads or names.
    local marker=type(body)=="string" and string.find(body,"TWTv%d+=")
    local twtPrefix=type(prefix)=="string" and (string.find(prefix,"^TWT") or prefix=="TWThreat")
    local key="other"
    if marker then key="threatReply"
    elseif twtPrefix then key=(type(body)=="string" and string.find(body,"^limit=")) and "threatQuery" or "threatOther"
    elseif prefix==self.peerPrefix or prefix==self.peerMetaPrefix then key="peer"
    elseif self.groupRecorder and prefix==self.groupRecorder.prefix then key="recording" end
    traffic[key]=(traffic[key] or 0)+1
    local relation=sender==self.playerKey and "self" or self:MemberForName(sender) and "roster" or "other"
    if key=="peer" then
        local field=relation=="roster" and "peerFromRoster" or relation=="self" and "peerSelf" or "peerUnknown"
        traffic[field]=(traffic[field] or 0)+1
    end
    if key=="threatReply" or key=="threatOther" then
        test.envelopes=test.envelopes or {}
        if table.getn(test.envelopes)<12 then
            local format=marker and string.sub(body,marker,math.min(marker+23,string.find(body,"=",marker,true))) or "unknown"
            local safeChannel=(channel=="PARTY" or channel=="RAID" or channel=="WHISPER" or channel=="GUILD" or channel=="BATTLEGROUND") and channel or "other"
            table.insert(test.envelopes,{t=GetTime()-test.started,format=format,channel=safeChannel,
                sender=relation,
                bytes=type(body)=="string" and string.len(body) or 0})
        else test.envelopesOmitted=(test.envelopesOmitted or 0)+1 end
    end
end
function E:NoteSourceDisplay(output,guid,main,pet,box,reason)
    local test=self:GetSourceTest(); if not test or not test.active or not guid then return end
    test.displays=test.displays or {}
    local summary=test.displays[output] or {checks=0,maxRows=0,maxReferences=0}; test.displays[output]=summary
    local now=GetTime()-test.started
    if summary.last and now-summary.last.t<1 then return end
    local ledger=self.ledger and self.ledger[guid]
    local row={t=now,enemy=self:SourceTestEnemy(guid),reason=reason,actors={},references={},
        ledger=ledger~=nil,startKnown=ledger and ledger.startKnown or false,
        incompleteStart=ledger and ledger.incompleteStart or false}
    local function model(value,frame)
        if not value then return end
        local m=value.actor
        return {unit=m and m.unit,pet=value.pet or false,role=m and self:Role(m.key),
            phase=value.phase,amount=value.amount,fill=value.fillPct,unknown=value.unknown or false,
            held=value.held or false,aggro=value.aggro or false,source=value.quantitySource,
            shown=frame and frame:IsShown() and true or false,visible=frame and frame:IsVisible() and true or false,
            height=frame and frame:GetHeight()}
    end
    row.own=model(main,box); row.pet=model(pet,box and box.petBar)
    for i,value in ipairs(main and main.references or {}) do
        table.insert(row.references,model(value,box and box.referenceBars and box.referenceBars[i]))
    end
    for _,m in ipairs(self.roster or {}) do
        local amount,shared=self:PeerAmount(guid,m)
        table.insert(row.actors,{unit=m.unit,class=m.class,level=self:Call(UnitLevel,m.unit),
            pet=m.pet or false,role=self:Role(m.key),connected=m.connected,alive=m.alive,hasGUID=m.guid~=nil,
            localAmount=ledger and m.guid and ledger.values[m.guid],peerAmount=shared and amount or nil,
            participated=ledger and m.guid and ledger.threatActors and ledger.threatActors[m.guid] or false,
            blocked=m.guid and ((ledger and ledger.uncertain[m.guid]) or (self.blockedActors and self.blockedActors[m.guid])) or nil})
    end
    local count=(main and 1 or 0)+(pet and 1 or 0)+table.getn(row.references)
    summary.checks=summary.checks+1; summary.maxRows=math.max(summary.maxRows,count)
    summary.maxReferences=math.max(summary.maxReferences,table.getn(row.references)); summary.last=row
    -- Retain recent evidence across the whole test, rather than filling a cap
    -- in the first fight. Names, raw GUIDs and unrelated message text stay out.
    test.displaySamples=test.displaySamples or {}; test.displayBytes=test.displayBytes or 0
    local sample={output=output,value=copy(row)}
    sample.bytes=string.len(self:JSON(sample)); test.displayBytes=test.displayBytes+sample.bytes
    table.insert(test.displaySamples,sample)
    while table.getn(test.displaySamples)>48 or test.displayBytes>96000 do
        local old=table.remove(test.displaySamples,1); test.displayBytes=test.displayBytes-old.bytes
        test.displaysOmitted=(test.displaysOmitted or 0)+1
    end
end
function E:NoteSourceEvent(name,a,b,c,d)
    local actor
    if string.find(name,"^AUTO_ATTACK_") or string.find(name,"^DAMAGE_SHIELD_") or string.find(name,"^SPELL_DISPEL_BY_") then actor=a
    elseif string.find(name,"^SPELL_DAMAGE_EVENT_") or string.find(name,"^SPELL_HEAL_BY_") or string.find(name,"^AURA_CAST_") then actor=b end
    if actor and self:MemberForGUID(actor) then
        self.eventCounts=self.eventCounts or {}; self.eventCounts[name]=(self.eventCounts[name] or 0)+1
        if string.find(name,"^AURA_CAST_") and type(c)=="string" and tonumber(a) then
            self.pendingDebuffs=self.pendingDebuffs or {}
            for key,row in pairs(self.pendingDebuffs) do if GetTime()-row.at>2 then self.pendingDebuffs[key]=nil end end
            local count=0; for _ in pairs(self.pendingDebuffs) do count=count+1 end
            if count<128 then self.pendingDebuffs[c..":"..a]={at=GetTime(),actor=b} end
        end
    elseif string.find(name,"^DEBUFF_ADDED_") and type(a)=="string" and tonumber(c) then
        local key=a..":"..c; local row=self.pendingDebuffs and self.pendingDebuffs[key]
        if row then
            self.pendingDebuffs[key]=nil
            if GetTime()-row.at<=2 and self:MemberForGUID(row.actor) then
                self.eventCounts=self.eventCounts or {}; self.eventCounts.debuffConfirmed=(self.eventCounts.debuffConfirmed or 0)+1
                -- Evidence only: a successful debuff supplies no threat amount.
                local r=self.recorder
                if r and r.db and r.db.enabled and r.SessionEntry then
                    r:SessionEntry("debuff-confirmed",{actor=r:ID(row.actor),target=r:ID(a),spell=tonumber(c)})
                end
            end
        end
    end
end
function E:CompareServerThreat(snapshot,rtt)
    local data=self.ledger and self.ledger[snapshot.guid]
    local test=self:GetSourceTest()
    local r=self.recorder
    local record=r and r.db and r.db.enabled and r.SessionEntry and GetTime()-(self.lastComparisonRecording or -10)>=2
    local capture=(test and test.active) or record
    local row={rtt=rtt,backend=self.localBackend or "chat",startKnown=data and data.startKnown and not data.incompleteStart or false,actors={}}
    local observed=self:GUID("targettarget")
    local holder=snapshot.owner and self:MemberForName(snapshot.owner.name)
    row.ownerMatches=observed and holder and observed==holder.guid or false
    for _,entry in ipairs(snapshot.actors) do
        local m=self:MemberForName(entry.name)
        if m and m.guid==entry.memberGUID then
            local value=data and data.values[m.guid]
            local reason=(self.blockedActors and self.blockedActors[m.guid]) or (data and data.uncertain[m.guid])
            local actor={unit=m.unit,class=m.class,pet=m.pet and true or false,server=entry.amount,
                localAmount=value,reason=reason or nil,state=capture and copy(self:ClassState(m)) or nil,assumptions={}}
            for _,limit in pairs(self.classLimits or {}) do
                if limit.key==m.key and GetTime()-limit.at<=300 then table.insert(actor.assumptions,limit.reason) end
            end
            actor.comparable=row.ownerMatches and row.startKnown and self.localBackend=="nampower" and
                not reason and self:Finite(value) and entry.amount>0 or false
            if actor.comparable then
                actor.difference=value-entry.amount
                actor.relative=actor.difference/entry.amount*100
                self:ServerCount("comparisons")
            end
            table.insert(row.actors,actor)
        end
    end
    self.serverComparison=row
    if test and test.active then
        row=copy(row); row.t=GetTime()-test.started
        row.enemy=self:SourceTestEnemy(snapshot.guid)
        local bytes=string.len(self:JSON(row))
        if table.getn(test.samples)<120 and (test.sampleBytes or 0)+bytes<=160000 then
            table.insert(test.samples,row); test.sampleBytes=(test.sampleBytes or 0)+bytes
        else test.samplesOmitted=(test.samplesOmitted or 0)+1 end
    end
    if record then
        self.lastComparisonRecording=GetTime()
        local saved=copy(row); saved.enemy=r:ID(snapshot.guid)
        r:SessionEntry("server-comparison",saved)
    end
end
function E:ServerSourceSnapshot()
    local out=copy(self.serverMetrics or {})
    if out.lastReply then out.replyAge=math.max(0,GetTime()-out.lastReply); out.lastReply=nil end
    out.state=self:ServerQueryState(); out.limit=self.serverRequestLimit
    out.reason=self.serverRejectReason
    return out
end
function E:SourceTestTick()
    local test=self:GetSourceTest()
    if not test or not test.active or GetTime()<(self.nextSourceTestTick or 0) then return end
    self.nextSourceTestTick=GetTime()+1
    test.duration=math.max(0,GetTime()-test.started)
    test.server={}; test.events={}
    for key,value in pairs(self.serverMetrics or {}) do
        if key~="lastReply" and key~="lastRTT" then test.server[key]=value-(test.baseServer[key] or 0) end
    end
    for key,value in pairs(self.eventCounts or {}) do test.events[key]=value-(test.baseEvents[key] or 0) end
    local state=self:ServerQueryState()
    test.states[state]=(test.states[state] or 0)+1; test.lastState=state
    test.lastReject=self.serverRejectReason; test.backend=self.localBackend or "chat"
    test.caps=self:Capabilities() -- current evidence, not a frozen pre-combat snapshot
    local context=self:SourceTestContext()
    test.targetStates=test.targetStates or {}
    test.targetStates[context.target.state]=(test.targetStates[context.target.state] or 0)+1
    test.lastContext=context
    test.pendingAtEnd=self.serverPending and {age=GetTime()-self.serverPending.at,channel=self.serverPending.channel} or nil
    if test.duration>=120 then
        test.active=false
        self:Print(self:L("Source test finished. Use /et test show to copy the result."))
    end
end
function E:SourceTestLines(test)
    local rows={}
    local function add(severity,key,a,b) table.insert(rows,{severity=severity,text=self:L(key,a,b)}) end
    if not test then add("info","Source test: /et test start, fight normally, then /et test show."); return rows end
    add("info","Source test: %.0f s",test.duration or 0)
    local server=test.server or {}; local events=test.events or {}; local count,shield=0,0
    for key,n in pairs(events) do if key~="debuffConfirmed" then count=count+n end end
    shield=(events.DAMAGE_SHIELD_SELF or 0)+(events.DAMAGE_SHIELD_OTHER or 0)
    add("info","Source test events: %d; damage shields: %d.",count,shield)
    add("info","Server requests: %d; replies: %d.",server.sent or 0,server.received or 0)
    add("info","Server assigned: %d; used: %d.",server.accepted or 0,server.used or 0)
    if (server.sendErrors or 0)>0 then add("error","Server request failed. Reload the UI; print diagnostics if it repeats.")
    elseif (server.accepted or 0)>0 then
        add("info","Server replies assigned. This confirms reception, not every spell formula.")
        if (server.used or 0)==0 then add("warning","Replies received but not used: check the target, aggro holder and roster in the recording.") end
    elseif (server.received or 0)>0 then
        add("warning","Replies could not be assigned. Copy this test report; do not change your display settings.")
    elseif (server.sent or 0)>0 then
        if (test.groupedEliteQueries or 0)>0 then
            add("warning","No server reply despite group/elite queries. Copy this report; repeating the same test is not needed. Local calculation continues.")
        else
            add("info","No server reply. Local calculation continues; server availability here is unconfirmed. A group/elite comparison is not recorded yet.")
        end
    elseif (test.states.coordinated or 0)>0 then
        add("info","Another EasyThreat client queries the server. Run the test there too.")
    elseif (test.states.foreign or 0)>0 then
        add("warning","Server query overlaps another threat addon. Test with only one meter querying.")
    else add("info","No eligible query yet. Select a living enemy during combat; EasyThreat must be enabled.") end
    if test.targetStates then
        local targets=test.targetStates; local checks=0
        for _,value in pairs(targets) do checks=checks+value end
        add("info","Target checks: %d; living combat target: %d. These are samples, not seconds.",checks,targets.combat or 0)
        if (targets.none or 0)>0 or (targets.dead or 0)>0 then
            add("info","No selected target: %d checks; dead target: %d checks.",targets.none or 0,targets.dead or 0)
        end
        if (targets.guid or 0)>0 then add("warning","Target GUID unreadable in %d checks. Copy the report; display filters are unrelated.",targets.guid) end
    end
    if test.traffic then
        add("info","Addon messages observed: %d; EasyThreat messages from other group members: %d. Combat events do not prove group sharing works.",test.traffic.total or 0,test.traffic.peerFromRoster or 0)
        if (server.received or 0)==0 and ((test.traffic.threatReply or 0)>0 or (test.traffic.threatOther or 0)>0) then
            add("warning","Threat-related messages arrived in another format. Copy this report; their values were not used.")
        end
    end
    if count==0 then add("info","No structured events in this test. Fight once; chat fallback remains available.") end
    if shield==0 then add("info","No damage-shield hit observed; this is normal without an active damage shield.") end
    add("info","Comparable actor samples: %d. Timing differences can affect this comparison.",server.comparisons or 0)
    return rows
end
function E:SourceTestReport()
    local test=self:GetSourceTest(); if not test then return self:L("Source test: /et test start, fight normally, then /et test show.") end
    local lines={"EasyThreat "..self.build.." - source test"}
    for _,row in ipairs(self:SourceTestLines(test)) do table.insert(lines,self:L(row.severity=="warning" and "Warning" or row.severity=="error" and "Error" or "Info")..": "..row.text) end
    local report=copy(test); report.baseServer=nil; report.baseEvents=nil; report.started=nil
    table.insert(lines,self:JSON(report))
    return table.concat(lines,"\n")
end
function E:SourceTestCommand(command)
    command=string.lower(command or "")
    if command=="start" or command=="" then
        local current=self:GetSourceTest()
        if current and current.active then self:Print(self:L("Source test is already running. Use /et test show or /et test stop.")); return end
        if self.demo then self:Print(self:L("Source test requires real combat. Turn Preview off first.")); return end
        local test={schema=2,build=self.build,active=true,started=GetTime(),wall=self:Call(time),duration=0,
            baseServer=copy(self.serverMetrics or {}),baseEvents=copy(self.eventCounts or {}),server={},events={},states={},samples={},
            queries={},traffic={},backendStart=self.localBackend or "chat",
            settings={enabled=self.db.enabled,localThreat=self.db.localThreat,threshold=self.db.threshold,groupSync=self.db.groupSync,
                filters=copy(self.db.filters),views=copy(self.db.roleViews),role=self:Role(self.playerKey),
                otherBars=self.db.otherBars,targetPet=self.db.targetPet,tooltipAlways=self.db.tooltipAlways},caps=self:Capabilities()}
        self.sourceTest=test; self.sourceTestEnemies={}; self.nextSourceTestTick=0
        test.capsStart=copy(test.caps); test.contextStart=self:SourceTestContext()
        if self.recorder and self.recorder.db then self.recorder.db.sourceTest=test end
        self:Print(self:L("Source test started for 2 minutes. Fight normally with an enemy selected; then /et test show."))
    elseif command=="stop" or command=="show" then
        self.nextSourceTestTick=0; self:SourceTestTick()
        local test=self:GetSourceTest()
        if command=="stop" and test then test.active=false end
        self:ShowPage("diagnostics")
        self:OpenSettingsTransfer("export",self:SourceTestReport())
        self.pages.diagnostics.exportPanel.hint:SetText(self:L("Copy the source test with Ctrl+A, Ctrl+C. No file search is needed."))
    else self:Print("/et test start|show|stop") end
end

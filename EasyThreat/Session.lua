-- Bounded session evidence, separate from deterministic threat replay events.
local E=EasyThreat
local R=E.recorder
local function copy(v) return E.journal.Copy(v) end
function R:SettingsSnapshot()
    local out={values={},roles={},build=E.build,rules=E.ruleVersion,client=E:Call(GetBuildInfo),
        locale=E:Call(GetLocale),backend=E.localBackend or "chat",caps=E:Capabilities(),addons=E:UIDependencies(),eventSwitches={}}
    for _,key in ipairs({"NP_EnableAutoAttackEvents","NP_EnableSpellHealEvents","NP_EnableAuraCastEvents","NP_EnableSpellGoEvents"}) do
        out.eventSwitches[key]=E:Call(GetCVar,key)
    end
    for key,value in pairs(E.db or {}) do
        if type(value)=="boolean" or type(value)=="number" or type(value)=="string" then out.values[key]=value end
    end
    out.filters=copy(E.db.filters); out.roleViews=copy(E.db.roleViews)
    out.recording={collectGroup=self.db.collectGroup,sharing=self.db.sharing,enabled=self.db.enabled}
    out.context=E:GroupContext(); out.playerRole=E:Role(E.playerKey)
    for _,m in ipairs(E.roster) do
        if m.guid then table.insert(out.roles,{id=self:ID(m.guid),role=E:Role(m.key),pet=m.pet,connected=m.connected,color=copy(E:IdentityColor(m)),peer=not m.pet and copy(E:PeerInfo(m)) or nil}) end
    end
    return out
end
function R:SessionEnabled(enabled)
    if enabled then
        if not self.ids and not self:Start() then return end
        self.db.sessionDiagnostics=self.db.sessionDiagnostics or {schema=1,runs={},entries={},bytes=0}
        local data=self.db.sessionDiagnostics
        if table.getn(data.runs)>=100 or data.bytes>=4*1024*1024 then
            self.db.enabled=false; data.active=false; data.stop="diagnostic-limit"; self.sessionBlocked=E:RecordingSession(); return
        end
        local run={startedAt=E:Call(time),monotonicStart=GetTime(),build=E.build,settings=self:SettingsSnapshot()}
        table.insert(data.runs,run); self.sessionRun=run
        data.active=true; data.stop=nil; self.sessionNext=0; self.lastDisplay=nil; self.lastSettings=nil
    elseif self.db.sessionDiagnostics then
        self.db.sessionDiagnostics.active=false
        if self.sessionRun then self.sessionRun.endedAt=E:Call(time); self.sessionRun.duration=GetTime()-self.sessionRun.monotonicStart end
    end
end
function R:SessionEntry(kind,value)
    local data=self.db.sessionDiagnostics
    if not data or not self.sessionRun then return end
    local row={kind=kind,t=GetTime()-self.sessionRun.monotonicStart,run=table.getn(data.runs),session=self.session,clip=self.clip and self.clip.id,value=value}
    local bytes=string.len(E:JSON(row))+2
    if data.bytes+bytes>4*1024*1024 or table.getn(data.entries)>=10000 then data.detailLimit=true; return end
    data.bytes=data.bytes+bytes; table.insert(data.entries,row)
end
function R:SessionTick()
    if not self.sessionRun then self:SessionEnabled(true) end
    if not self.sessionRun or GetTime()<(self.sessionNext or 0) then return end
    self.sessionNext=GetTime()+0.5
    if GetTime()-self.sessionRun.monotonicStart>=1800 then
        self.db.sessionDiagnostics.stop="30-minutes"; self.sessionBlocked=E:RecordingSession(); self:SetEnabled(false); return
    end
    local settings=self:SettingsSnapshot(); local stableSettings=copy(settings)
    stableSettings.caps.native=nil; stableSettings.caps.serverReceived=nil
    for _,member in ipairs(stableSettings.roles) do
        if member.peer then
            for _,key in ipairs({"seq","wall","uptime","at","receivedAt"}) do member.peer[key]=nil end
        end
    end
    local encoded=E:JSON(stableSettings)
    if encoded~=self.lastSettings then self.lastSettings=encoded; self:SessionEntry("settings",settings) end
    local target=E:GUID("target"); local enemy=target and E.enemies[target]
    -- Record the model actually painted by RefreshUI. Re-evaluating TargetModels
    -- here mixed a new target with the PREVIOUS frame and changed hysteresis.
    local rendered=E.targetRender
    local synchronized=rendered and rendered.guid==target and true or false
    local function model(v)
        if not v then return false end
        local out=copy(v); out.actor=v.actor and R:ID(v.actor); return out
    end
    local references={}
    for _,other in ipairs(rendered and rendered.references or {}) do table.insert(references,model(other)) end
    local own=synchronized and model(rendered.own) or false
    local pet=synchronized and model(rendered.pet) or false
    local render=rendered and {sequence=rendered.sequence,age=math.max(0,GetTime()-rendered.at),
        target=self:ID(rendered.guid),reason=rendered.reason,wanted=rendered.wanted,preview=rendered.preview,
        own=model(rendered.own),pet=model(rendered.pet),reference=model(rendered.reference),references=references} or false
    local withheld={}
    local ledger=target and E.ledger and E.ledger[target]
    if ledger then
        for _,member in ipairs(E.roster) do
            local guid=member.guid
            local why=guid and (ledger.uncertain[guid] or (E.blockedActors and E.blockedActors[guid]))
            if why and ledger.involved[guid] then withheld[self:ID(guid)]=tostring(why) end
        end
    end
    local tip=E.tooltipDiagnostic
    local view={target=self:ID(target),targetReason=synchronized and rendered.reason or "pending-refresh",own=own,pet=pet,
        render=render,displaySynchronized=synchronized,withheld=withheld,
        observedOwner=enemy and enemy.owner and self:ID(enemy.owner.guid),ownerQuality=enemy and enemy.ownerQuality,
        startKnown=ledger and ledger.startKnown or false,uiParentVisible=UIParent:IsVisible() and true or false,
        targetFrameShown=E.target and E.target:IsShown() and true or false,
        targetShown=E.target and E.target:IsVisible() or false,
        petShown=E.target and E.target.petBar and E.target.petBar:IsVisible() or false,
        reference=synchronized and model(rendered.reference) or false,referenceShown=E.target and E.target.referenceBar and E.target.referenceBar:IsVisible() or false,
        targetExists=E:Exists("target") and true or false,
        playerCombat=E:Call(UnitAffectingCombat,"player") and true or false,
        petCombat=E:Call(UnitAffectingCombat,"pet") and true or false,
        enemyCombat=enemy and enemy.combat or false,enemyStale=enemy and enemy.stale or false,tooltipShown=E.tooltipBar and E.tooltipBar:IsShown() or false,
        tooltipReason=tip and tip.reason,tooltipFilter=tip and tip.filter,tooltipIdentity=E.tooltipIdentitySource,
        tooltipEnemy=tip and self:ID(tip.guid),tooltipAge=tip and math.floor(GetTime()-tip.at),
        overheads=E.shownOverheads or 0,plateReason=E.plateDisplayReason,backend=E.localBackend or "chat",
        tooltipFault=E.tooltipError and true or false,peerSendFault=E.peerSendError and true or false,
        groupTransport=E.groupRecorder and E.groupRecorder:TransportSnapshot() or nil}
    local input=E.sourceStats or {}
    view.threatTransport=E:PeerTimingSnapshot(target)
    view.serverTransport=E:ServerSourceSnapshot()
    for _,actor in ipairs(view.threatTransport.actors) do actor.actor=self:ID(actor.actor) end
    view.displays={}
    for output,state in pairs(E.displayStates or {}) do
        view.displays[output]={reason=state.reason,filter=state.filter,enemy=state.guid and self:ID(state.guid)}
    end
    view.inputs={structured=input.structured or 0,localEvents=input["local-event"] or 0,server=input.received or 0}
    -- Age and packet counters change even while the UI is idle. Retain them
    -- in the ten-second heartbeat without filling a session with non-changes.
    local stable=copy(view); stable.tooltipAge=nil; stable.inputs=nil
    stable.threatTransport=nil -- diagnostics heartbeat carries changing ages
    stable.serverTransport=nil
    if stable.render then stable.render.age=nil; stable.render.sequence=nil end
    if stable.groupTransport then stable.groupTransport.sent=nil; stable.groupTransport.received=nil end
    local signature=E:JSON(stable)
    if signature~=self.lastDisplay or not self.lastHeartbeat or GetTime()-self.lastHeartbeat>=10 then
        self.lastDisplay=signature; self.lastHeartbeat=GetTime(); self:SessionEntry("display",view)
    end
    -- Participation history is only a display aid, never a threat ledger.
    for guid,at in pairs(E.participation or {}) do if GetTime()-at>180 then E.participation[guid]=nil end end
end
function R:JournalEvidence(f)
    if not f or not self.session then return nil end
    local out={schema=1,session=self.session,startedAt=f.stamp,monotonicStart=f.started,duration=f.duration,
        finished=f.finished and true or false,source=f.source,damage=f.damage,enemies={},actors={},notes=copy(f.notes)}
    -- Pure salted IDs do not consume the live replay recorder's entity budget.
    local function id(guid) return guid and E:RecordingPseudonym(guid,R.session) or nil end
    for guid,a in pairs(f.actors or {}) do
        out.actors[id(guid)]={class=a.class,pet=a.pet,role=a.role,own=a.own,damage=a.damage,cost=copy(a.cost)}
    end
    for guid,enemy in pairs(f.enemies or {}) do
        local entry={start=enemy.start,dead=enemy.dead,level=enemy.level,classification=enemy.classification,
            firstDamageAt=enemy.firstDamageAt,firstThreatAt=E.journal:FirstThreatPoint(enemy),series={}}
        for actor,series in pairs(enemy.series or {}) do
            local first,last,missing,values=nil,nil,0,0
            for _,p in ipairs(series) do
                if p.v~=nil then first=first or p.t; last=p.t; values=values+1 else missing=missing+1 end
            end
            entry.series[id(actor)]={first=first,last=last,values=values,missing=missing}
        end
        out.enemies[id(guid)]=entry
    end
    return out
end
local recordingEvent=R.frame:GetScript("OnEvent")
R.frame:RegisterEvent("PLAYER_LOGOUT")
R.frame:SetScript("OnEvent",function()
    if event=="PLAYER_LOGOUT" and R.db then
        local ok=pcall(function()
            R:Finish("logout"); R:SessionEnabled(false); R.db.enabled=false
        end)
        if not ok then R.sessionFault=true end
    elseif recordingEvent then recordingEvent() end
end)

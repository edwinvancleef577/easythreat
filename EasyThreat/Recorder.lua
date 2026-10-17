-- Built-in recordings. No HTTP, chat bodies, player names or raw GUIDs in exports.
local E=EasyThreat
local R={maxEvents=1500,maxBytes=350000,maxClips=3,maxEntities=256}
EasyThreatRecorder=R
E.recorder=R
local function clone(value)
    if type(value)~="table" then return value end
    local out={}; for k,v in pairs(value) do out[k]=clone(v) end; return out
end
function R:InCombat()
    if E:AnyCombat() then return true end
    -- Some clients omit party/pet combat flags while an observed enemy is
    -- still attacking that party. A short observation lease bridges this gap.
    return self.clip and self.lastCombatObservation and GetTime()-self.lastCombatObservation<1.5 and true or false
end
function R:ID(guid)
    if not guid then return "-" end
    if not self.ids[guid] then
        if self.idCount>=self.maxEntities then self.overflow=true; return "overflow" end
        self.idCount=self.idCount+1
        local source=self.session..":"..tostring(guid); local hash=5381
        for i=1,string.len(source) do hash=math.mod(hash*33+string.byte(source,i),4294967291) end
        local id=string.format("U%08x",hash)
        -- Salted pseudonyms align across clients in the same recording session.
        -- Detect collisions locally rather than merging two game entities.
        if self.idOwners[id] and self.idOwners[id]~=guid then id=id.."-"..self.idCount; self.overflow=true end
        self.ids[guid]=id; self.idOwners[id]=guid
    end
    return self.ids[guid]
end
function R:Ledger()
    local out={}
    local count=0
    for guid,data in pairs(E.ledger or {}) do
        count=count+1; if count>64 then self.overflow=true; break end
        local item={values={},uncertain={},involved={},casts={},updated=data.updated-self.started,startKnown=data.startKnown and true or false}
        for actor,value in pairs(data.values) do if E:Finite(value) then item.values[self:ID(actor)]=value end end
        for actor,reason in pairs(data.uncertain) do item.uncertain[self:ID(actor)]=tostring(reason) end
        for actor in pairs(data.involved) do item.involved[self:ID(actor)]=true end
        for key,at in pairs(data.casts or {}) do
            local _,_,actor,spell=string.find(key,"^(.-):(.+)$")
            if actor and string.find(spell,"^%d+$") then item.casts[self:ID(actor)..":"..spell]=at-self.started end
        end
        out[self:ID(guid)]=item
    end
    return out
end
function R:Blocked()
    local result={}
    for guid,reason in pairs(E.blockedActors or {}) do result[self:ID(guid)]=tostring(reason) end
    return result
end
function R:Barriers()
    local result={}
    for enemy,actors in pairs(E.blockedEnemies or {}) do
        local row={}; for actor,reason in pairs(actors) do row[self:ID(actor)]=tostring(reason) end
        result[self:ID(enemy)]=row
    end
    return result
end
function R:Roster()
    local rows={}
    for _,m in ipairs(E.roster) do
        if m.guid then
            local owner=m.pet and E:MemberForName(m.owner)
            table.insert(rows,{id=self:ID(m.guid),class=m.class,pet=m.pet,owner=owner and self:ID(owner.guid),
                alive=m.alive,connected=m.connected,level=E:Call(UnitLevel,m.unit) or 0})
        end
    end
    return rows
end
function R:Unit(guid)
    local m=E:MemberForGUID(guid)
    return {id=self:ID(guid),exists=E:Exists(guid) and true or false,combat=E:Call(UnitAffectingCombat,guid) and true or false,
        hostile=E:Call(UnitCanAttack,"player",guid) and true or false,dead=E:Call(UnitIsDeadOrGhost,guid) and true or false,
        player=m and not m.pet or false,target=self:ID(E:GUID(guid.."target"))}
end
function R:Context(actor,target)
    local context={roster=self:Roster(),units={},states={}}
    local seen={}
    local function unit(guid)
        if guid and not seen[guid] then seen[guid]=true; table.insert(context.units,R:Unit(guid)) end
    end
    unit(actor); unit(target)
    for guid in pairs(E.ledger or {}) do unit(guid) end
    local m=E:MemberForGUID(actor)
    if m then context.states[self:ID(actor)]=E:ClassState(m) end
    local health=target and E.healthBefore and E.healthBefore[target]
    if health then context.health={id=self:ID(target),health=health.health,max=health.max,age=GetTime()-health.at} end
    if target and E.enemySeenIdle and E.enemySeenIdle[target] then context.idle={id=self:ID(target),age=GetTime()-E.enemySeenIdle[target]} end
    return context
end
function R:Start()
    if not self.db or not self.db.enabled or not E.db.enabled or E.demo then return end
    self.started=GetTime(); self.ids={}; self.idOwners={}; self.idCount=0; self.overflow=nil; self.lastObservation={}; self.lastOwner={}
    self.lastCombatObservation=nil
    local session=E:RecordingSession(); self.session=session
    self.db.serial=(self.db.serial or 0)+1
    local clip={id=self.db.serial,schema=1,version=E.version,rules=E.ruleVersion,session=session,
        client=tostring(E:Call(GetBuildInfo) or "?"),backend=E.localBackend or "chat",caps=E:Capabilities(),
        partial=E:AnyCombat() and true or false,player=self:ID(E:GUID("player")),events={},marked=false,
        startedAt=E:Call(time)}
    if self.SettingsSnapshot then clip.settings=self:SettingsSnapshot(); clip.build=E.build; clip.monotonicStart=self.started end
    clip.roster=self:Roster(); clip.seed=self:Ledger(); clip.blocked=self:Blocked(); clip.barriers=self:Barriers()
    -- A partial/colliding seed is not a replayable baseline. Stop only capture.
    if self.overflow then self:Fault(); return end
    self.clip=clip; self.saved=false; self.bytes=string.len(E:JSON(clip))+1000
    return clip
end
function R:SaveClip()
    if self.saved or not self.clip then return end
    if self.db.sessionDiagnostics then
        local total=0; for _,old in ipairs(self.db.clips) do total=total+(old.bytes or 0) end
        if total>=32*1024*1024 or table.getn(self.db.clips)>=600 then
            self.db.enabled=false; self.db.sessionDiagnostics.stop="storage-limit"; self.db.sessionDiagnostics.active=false; self.sessionBlocked=E:RecordingSession()
            E:Print(E:L("Recording storage full. Export before clearing.")); return
        end
    end
    while not self.db.sessionDiagnostics and table.getn(self.db.clips)>=self.maxClips do
        local remove=1
        for i,old in ipairs(self.db.clips) do if not old.marked then remove=i; break end end
        table.remove(self.db.clips,remove)
    end
    table.insert(self.db.clips,self.clip)
    self.saved=true
end
function R:Ensure()
    if not self.db or not self.db.enabled or not E.db.enabled or E.demo or self.busy then return end
    if self.clip and self.clip.session~=E:RecordingSession() then self:Finish("group-session") end
    if self.clip and (GetTime()-self.started>120 or table.getn(self.clip.events)>=self.maxEvents or self.bytes>=self.maxBytes or self.overflow) then
        self:Finish("limit")
    end
    if not self.clip then return self:Start() end
    return self.clip
end
function R:Add(row)
    local clip=self.clip
    if not clip then return end
    row.t=GetTime()-self.started
    if row.t>120 or self.overflow then
        clip.dropped=(clip.dropped or 0)+1; self:Finish(self.overflow and "entity-limit" or "limit"); return
    end
    local encoded=E:JSON(row)
    if self.bytes+string.len(encoded)+2>self.maxBytes or table.getn(clip.events)>=self.maxEvents then
        clip.dropped=(clip.dropped or 0)+1; self:Finish("limit"); return
    end
    self.bytes=self.bytes+string.len(encoded)+2
    table.insert(clip.events,row); clip.duration=row.t; clip.bytes=self.bytes
    -- Idle toggles, housekeeping and ambient deaths cannot evict a fight.
    -- Observations without numbers are useful for diagnosing missing events.
    if row.op=="threat" or row.op=="heal" or row.op=="incoming" or row.op=="observe" or
        row.op=="server" or row.op=="mark" or (row.op=="signal" and
        (string.find(row.event,"^AUTO_ATTACK") or string.find(row.event,"^SPELL_DAMAGE") or
         string.find(row.event,"^SPELL_HEAL"))) then self:SaveClip() end
end
function R:Finish(reason)
    if self.clip then
        self.clip.finish=reason; self.clip.duration=math.min(120,GetTime()-self.started)
        self.clip.endedAt=E:Call(time)
        if self.saved and E.groupRecorder then
            local ok=pcall(function() E.groupRecorder:Capture(R.clip) end)
            if not ok then E.groupRecorder.captureError=true end
        end
    end
    self.clip=nil
end
function R:Mark(reason)
    if not self:Ensure() then return end
    self.clip.marked=true; self:Add({op="mark",reason=reason or "manual"})
end
function R:SetEnabled(enabled,automatic)
    if enabled and automatic and self.sessionBlocked==E:RecordingSession() then return end
    if enabled and not automatic then self.sessionBlocked=nil end
    self.fault=nil
    if not enabled then self:Finish("stopped") end
    self.db.enabled=enabled and true or false
    self.db.groupAuto=automatic and enabled and true or nil
    if enabled and not self.clip then local ok=pcall(function() R:Start() end); if not ok then self:Fault() end end
    if self.SessionEnabled then self:SessionEnabled(enabled) end
    E:Print(E:RecordingStatus()); E:UpdateDiagnostics()
end
function R:Clear()
    self:Finish("cleared"); self.db.clips={}; self.db.serial=0
    if E.groupRecorder then E.groupRecorder:Begin(false) end
    self.db.group=nil; self.db.sessionDiagnostics=nil; self.db.lastJournal=nil; self.sessionRun=nil; self.lastDisplay=nil; self.lastSettings=nil; self.sessionBlocked=nil
    E:UpdateDiagnostics()
end
local function numeric(v) return type(v)=="number" and v-v==0 and math.abs(v)<1000000000000 and v or nil end
function R:Invoke(op,args,actor,target,run)
    if not self.db or not self.db.enabled or self.busy then return run() end
    local ready,before,row=pcall(function()
        if not R:Ensure() then return end
        return R:Ledger(),{op=op,args=args(),context=R:Context(actor,target)}
    end)
    if not ready then self:Fault(); return run() end
    if not row then return run() end
    self.busy=true
    local ok,result=pcall(run)
    self.busy=nil
    local recorded=pcall(function()
        row.after=R:Ledger(); row.blocked=R:Blocked()
        -- Keep changed enemies only; actual rule inputs are recorded above.
        row.check={}
        for key,data in pairs(row.after) do if E:JSON(data)~=E:JSON(before[key] or {}) then row.check[key]=data end end
        row.removed={}
        for key in pairs(before) do if not row.after[key] then table.insert(row.removed,key) end end
        row.after=nil
        if not ok then row.failed=true end -- never persist arbitrary error text
        R:Add(row)
    end)
    if not recorded then self:Fault() end
    if not ok then error(result) end
    return result
end
function R:Fault()
    self:Finish("recorder-error")
    self.fault=true; self.db.enabled=false
end
function R:SafeRaw(name,a,b,c,d,e,f,g)
    if not self.db or not self.db.enabled then return end
    local ok=pcall(function() R:Raw(name,a,b,c,d,e,f,g) end)
    if not ok then self:Fault() end
end
function R:Raw(name,a,b,c,d,e,f,g)
    local actor,target,id,amount
    if name=="AUTO_ATTACK_SELF" or name=="AUTO_ATTACK_OTHER" or string.find(name,"^DAMAGE_SHIELD_") then actor=a; target=b; amount=c
    elseif string.find(name,"^SPELL_DISPEL_BY_") then actor=a; target=b; id=c
    elseif string.find(name,"^SPELL_DAMAGE_EVENT") or string.find(name,"^SPELL_HEAL_BY") then actor=b; target=a; id=c; amount=d
    elseif string.find(name,"^AURA_CAST") then actor=b; target=c; id=a
    elseif string.find(name,"^SPELL_MISS") then actor=a; target=b; id=c
    elseif string.find(name,"^BUFF_") or string.find(name,"^DEBUFF_") then actor=a; target=a; id=c
    elseif name=="UNIT_DIED" then actor=a; target=a
    else return end
    if type(actor)~="string" or type(target)~="string" then return end
    local owner=E:MemberForGUID(E:GUID(actor.."owner"))
    if not E:MemberForGUID(actor) and not E:MemberForGUID(target) and not owner then return end
    if not self:Ensure() then return end
    self:Add({op="signal",event=name,actor=self:ID(actor),target=self:ID(target),owner=owner and self:ID(owner.guid),
        spell=numeric(id),amount=numeric(amount),detail={numeric(d) or false,numeric(e) or false,numeric(f) or false,numeric(g) or false}})
end
function R:Install()
    if self.installed then return end
    self.installed=true
    self.originals={}
    for _,name in ipairs({"NoteClassLimit","RecordThreatEvent","RecordThreatHeal","InvalidateActor",
        "ResetThreatSources","ActivateStructured","StructuredThreatEvent","PruneThreatSources","ReceiveServerThreat","ReadEnemy"}) do
        self.originals[name]=E[name]
    end
    local note=E.NoteClassLimit
    E.NoteClassLimit=function(engine,member,reason,detail)
        note(engine,member,reason,detail)
        if R.db and R.db.enabled and R.clip and reason~="foreign-talents" and reason~="talents" and reason~="talent-layout" and
            reason~="school" and reason~="shield" and reason~="stance" and reason~="shield-identity" then
            R.clip.marked=true; R.clip.reasons=R.clip.reasons or {}; R.clip.reasons[reason]=true
        end
    end
    local threat=E.RecordThreatEvent
    E.RecordThreatEvent=function(engine,kind,actor,target,amount,id,school,rule)
        return R:Invoke("threat",function()
            return {kind=kind,actor=R:ID(actor),target=R:ID(target),amount=amount,spell=id,school=school,
                spellName=E:Call(GetSpellRecField,id,"name") or (rule and rule.names and rule.names[1]),spellEvent=rule and rule.spell or id~=nil}
        end,actor,target,function() return threat(engine,kind,actor,target,amount,id,school,rule) end)
    end
    local heal=E.RecordThreatHeal
    E.RecordThreatHeal=function(engine,actor,target,amount,id,rule)
        return R:Invoke("heal",function()
            return {actor=R:ID(actor),target=R:ID(target),amount=amount,spell=id,school=E:SchoolForSpell(id),
                spellName=E:Call(GetSpellRecField,id,"name") or (rule and rule.names and rule.names[1])}
        end,actor,target,function() return heal(engine,actor,target,amount,id,rule) end)
    end
    local invalidate=E.InvalidateActor
    E.InvalidateActor=function(engine,actor,reason,target)
        return R:Invoke("invalidate",function() return {actor=R:ID(actor),target=target and R:ID(target),reason=reason} end,
            actor,target,function() return invalidate(engine,actor,reason,target) end)
    end
    local reset=E.ResetThreatSources
    E.ResetThreatSources=function(engine)
        return R:Invoke("reset",function() return {} end,nil,nil,function() return reset(engine) end)
    end
    local activate=E.ActivateStructured
    E.ActivateStructured=function(engine)
        return R:Invoke("backend",function() return {} end,nil,nil,function() return activate(engine) end)
    end
    local structured=E.StructuredThreatEvent
    E.StructuredThreatEvent=function(engine,name,a,b,c,d,e,f,g,h,i)
        R:SafeRaw(name,a,b,c,d,e,f,g)
        if name=="UNIT_DIED" and engine:TrackedDeath(a) then
            return R:Invoke("death",function() return {actor=R:ID(a)} end,a,a,function() return structured(engine,name,a,b,c,d,e,f,g,h,i) end)
        end
        local incomingActor,incomingTarget,amount,spell
        if name=="AUTO_ATTACK_SELF" or name=="AUTO_ATTACK_OTHER" or string.find(name,"^DAMAGE_SHIELD_") then incomingActor=a; incomingTarget=b; amount=tonumber(c)
        elseif name=="SPELL_DAMAGE_EVENT_SELF" or name=="SPELL_DAMAGE_EVENT_OTHER" then incomingActor=b; incomingTarget=a; amount=tonumber(d); spell=tonumber(c) end
        if type(incomingActor)=="string" and type(incomingTarget)=="string" and not engine:MemberForGUID(incomingActor) and
            engine:MemberForGUID(incomingTarget) and engine:Call(UnitCanAttack,"player",incomingActor) then
            -- Incoming hits create participation without player-generated threat.
            -- That changes the later split of healing across enemies.
            return R:Invoke("incoming",function()
                return {event=name,actor=R:ID(incomingActor),target=R:ID(incomingTarget),amount=amount,spell=spell,school=engine:SchoolForSpell(spell)}
            end,incomingActor,incomingTarget,function() return structured(engine,name,a,b,c,d,e,f,g,h,i) end)
        end
        local result=structured(engine,name,a,b,c,d,e,f,g,h,i)
        return result
    end
    local prune=E.PruneThreatSources
    local server=E.ReceiveServerThreat
    E.ReceiveServerThreat=function(engine,prefix,body,channel,sender)
        server(engine,prefix,body,channel,sender)
        if not R.db or not R.db.enabled or type(body)~="string" or not string.find(body,"TWTv4=",1,true) then return end
        local ok=pcall(function()
            if not R:Ensure() then return end
            local parsed=engine:ParseServerThreat(body)
            local actors={}
            if parsed then
                for _,actor in ipairs(parsed.actors) do
                    local member=engine:MemberForName(actor.name)
                    table.insert(actors,{id=member and R:ID(member.guid) or "external",amount=actor.amount,raw=actor.raw,tank=actor.tank,melee=actor.melee})
                end
            end
            local member=engine:MemberForName(sender)
            R:Add({op="server",bytes=string.len(body),sender=member and R:ID(member.guid) or "external",
                parsed=parsed~=nil,reason=engine.serverRejectReason or "context",actors=actors})
        end)
        if not ok then R:Fault() end
    end
    E.PruneThreatSources=function(engine)
        if not R.db or not R.db.enabled or not R.clip then return prune(engine) end
        local before={}; for guid in pairs(engine.ledger or {}) do before[guid]=true end
        prune(engine)
        local ok=pcall(function()
            local removed={}
            for guid in pairs(before) do if not engine.ledger[guid] then table.insert(removed,R:ID(guid)) end end
            if table.getn(removed)>0 then R:Add({op="prune",removed=removed}) end
        end)
        if not ok then R:Fault() end
    end
    local read=E.ReadEnemy
    E.ReadEnemy=function(engine,unit,key,guid)
        local enemy=read(engine,unit,key,guid)
        if not R.db or not R.db.enabled then return enemy end
        local ok=pcall(function()
        if enemy and enemy.combat and not engine:Call(UnitIsDeadOrGhost,unit) and R:Ensure() then
            R.lastCombatObservation=GetTime()
            if GetTime()-(R.lastObservation[guid or key] or -10)<1 then return end
            R.lastObservation[guid or key]=GetTime()
            local samples,estimates={},{}
            for actor,sample in pairs(enemy.samples) do
                local member=engine:Member(actor)
                if member then
                    local target=(sample.quality=="api" or sample.quality=="context") and samples or estimates
                    target[R:ID(member.guid)]={pct=sample.pct,amount=sample.amount,quality=sample.quality,shared=sample.shared and true or false}
                end
            end
            local owner=enemy.owner and R:ID(enemy.owner.guid)
            if R.lastOwner[guid or key] and owner~=R.lastOwner[guid or key] then
                R.clip.marked=true; R.clip.reasons=R.clip.reasons or {}; R.clip.reasons["target-change"]=true
            end
            R.lastOwner[guid or key]=owner
            R:Add({op="observe",enemy=R:ID(guid),owner=owner,quality=enemy.ownerQuality,samples=samples,
                estimates=estimates,threshold=engine.db.threshold,role=engine:Role(engine.playerKey),
                target=R:ID(enemy.observedTargetGUID),ownerRejected=enemy.ownerRejected})
        end
        end)
        if not ok then R:Fault() end
        return enemy
    end
end
-- A leftover standalone copy may load after EasyThreat. Detach its capture
-- hooks once loading finishes, so it cannot record twice or replace this UI.
function R:UseIntegrated()
    local old=EasyThreatRecorder
    if not old or old==self then return end
    self.standaloneFound=true
    if old.frame then
        old.frame:SetScript("OnEvent",nil); old.frame:SetScript("OnUpdate",nil)
        E:Call(old.frame.UnregisterAllEvents,old.frame)
    end
    if self.db and table.getn(self.db.clips)==0 and old.db and old.db.schema==1 and type(old.db.clips)=="table" then
        for i=math.max(1,table.getn(old.db.clips)-self.maxClips+1),table.getn(old.db.clips) do
            table.insert(self.db.clips,old.db.clips[i])
        end
        self.db.serial=tonumber(old.db.serial) or 0
    end
    for name,original in pairs(self.originals or {}) do E[name]=original end
    self.installed=nil
    EasyThreatRecorder=self; EasyThreatRecordingDB=self.db
    self:Install()
end
local frame=CreateFrame("Frame","EasyThreatRecordingEvents",UIParent)
R.frame=frame; frame:RegisterEvent("PLAYER_LOGIN")
function E:InitRecording()
    if not R.db then
        if type(EasyThreatRecordingDB)~="table" or EasyThreatRecordingDB.schema~=1 then EasyThreatRecordingDB={schema=1,enabled=false,collectGroup=true,clips={},serial=0} end
        R.db=EasyThreatRecordingDB
        -- Older installs did not persist collection intent. Preserve their
        -- inactive state; new installs enable collection when a party forms.
        if type(R.db.collectGroup)~="boolean" then R.db.collectGroup=false end
        if R.db.groupAuto then R.db.enabled=false; R.db.groupAuto=nil end
        -- Ready to join a party collector; automatic startup is staggered by
        -- RecordingGroup. Keep an explicit sharing opt-out across reloads.
        if type(R.db.sharing)~="boolean" then R.db.sharing=true end
        if E.groupRecorder then E.groupRecorder.sharing=R.db.sharing end
        if type(R.db.clips)~="table" then R.db.clips={} end
        while not R.db.sessionDiagnostics and table.getn(R.db.clips)>R.maxClips do table.remove(R.db.clips,1) end
        R:Install()
        for _,name in ipairs({"SPELL_MISS_SELF","SPELL_MISS_OTHER","BUFF_ADDED_SELF","BUFF_REMOVED_SELF","BUFF_ADDED_OTHER","BUFF_REMOVED_OTHER",
            "DEBUFF_REMOVED_SELF","DEBUFF_REMOVED_OTHER"}) do pcall(frame.RegisterEvent,frame,name) end
    end
end
frame:SetScript("OnEvent",function()
    if event=="PLAYER_LOGIN" then R:UseIntegrated()
    elseif R.db then R:SafeRaw(event,arg1,arg2,arg3,arg4,arg5,arg6,arg7) end
end)
frame:SetScript("OnUpdate",function()
    if R.db then R:UseIntegrated() end
    if E.groupRecorder and R.db then
        local ok=pcall(function() E.groupRecorder:Tick() end)
        if not ok then E.groupRecorder.captureError=true end
    end
    if not R.db or not R.db.enabled then return end
    if R.SessionTick then local ok=pcall(function() R:SessionTick() end); if not ok then R.sessionFault=true end end
    if R.clip and not R:InCombat() and table.getn(R.clip.events)>0 and GetTime()-R.started>1 then R:Finish("combat-end") end
    if R.clip and not E.db.enabled then R:Finish("addon-disabled") end
end)

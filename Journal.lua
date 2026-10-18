-- Local combat journal. Measurements and missing observations stay distinct.
-- Server-event layouts: github.com/Emyrk/nampower/blob/main/EVENTS.md
local E=EasyThreat
local J={schema=1,interval=0.5,limit=24000,eventLimit=5000}
E.journal=J
local function count(t) local n=0; for _ in pairs(t or {}) do n=n+1 end; return n end
local function copy(v)
    if type(v)~="table" then return v end
    local t={}; for k,x in pairs(v) do t[k]=copy(x) end; return t
end
J.Copy=copy
local creatureIcons={
    {"Ability_Hunter_Pet_Wolf","Beast","Wildtier","Bête","Bestia","Fera","Животное","야수","野兽"},
    {"INV_Helmet_03","Humanoid","Humanoide","Humanoïde","Гуманоид","인간형","人型生物"},
    {"Spell_Shadow_SummonVoidWalker","Demon","Dämon","Démon","Demonio","Demônio","Демон","악마","恶魔"},
    {"Spell_Shadow_RaiseDead","Undead","Untoter","Mort-vivant","No-muerto","Morto-vivo","Нежить","언데드","亡灵"},
    {"Spell_Nature_Earthquake","Elemental","Elementar","Élémentaire","Элементаль","정령","元素生物"},
    {"Ability_Hunter_Pet_WindSerpent","Dragonkin","Drachkin","Draconien","Dragón","Draconiano","Дракон","용족","龙类"},
}
function J:EnemyIcon(unit)
    local family=E:Call(UnitCreatureFamily,unit)
    if family and E.demonIcons[family] then return "Interface\\Icons\\"..E.demonIcons[family] end
    local kind=E:Call(UnitCreatureType,unit)
    for _,row in ipairs(creatureIcons) do for i=2,table.getn(row) do
        if row[i]==kind then return "Interface\\Icons\\"..row[1] end
    end end
    return "Interface\\Icons\\Ability_Creature_Cursed_02"
end
local function finite(n) return type(n)=="number" and n==n and n>-1e12 and n<1e12 end
local function clean(s) return string.gsub(tostring(s or ""),"|","/") end
function J:Allowed() return self.db and E.db and E.db.enabled and E.db.journalEnabled and not E.demo and not self.fault end
function J:Time(at) return math.max(0,(at or GetTime())-(self.fight and self.fight.started or GetTime())) end
function J:Note(key) if self.fight then self.fight.notes[key]=true end end
function J:Begin(at)
    if self.fight or not self:Allowed() then return self.fight end
    at=at or GetTime()
    self.fight={schema=1,started=at,stamp=E:Call(time),duration=0,actors={},order={},enemies={},enemyOrder={},
        events={},notes={},points=0,damage=0,knownOwner=0,tankOwner=0,unknownOwner=0,source=self.backend or "chat"}
    self.fight.peers=self:GroupEvidence()
    self.lastActive=at; self.lastSample=nil; self.previousOwners={}; self.resources={}
    self:RefreshActors(at)
    if self.idleAt and at-self.idleAt<2 then
        for id,p in pairs(self.idleResources or {}) do
            local a=self.fight.actors[id]
            if a then a.startPower=p.value; a.startMax=p.max; a.startType=p.kind; a.startHealth=p.health end
            self.resources[id]=copy(p)
        end
    else self:Note("Journal start may be incomplete") end
    return self.fight
end
function J:Actor(member,at)
    if not member or not self.fight then return end
    -- A newly summoned pet is a new actor, even if the owner key is reused.
    local id=member.guid or member.key
    local a=self.fight.actors[id]
    if not a then
        if count(self.fight.actors)>=80 then self:Note("Journal capture limit reached"); return end
        a={id=id,key=member.key,name=clean(member.name),class=member.class,pet=member.pet,owner=member.owner,
            own=member.key==E.playerKey or member.owner==E.playerKey,role=E:Role(member.key),
            color=copy(E:IdentityColor(member)),level=E:Call(UnitLevel,member.unit),
            stock={},spend={},healing={},overheal={},damage=0,healed=0,over=0,cost={},
            seen=self:Time(at),icon=member.pet and ("Interface\\Icons\\"..
                (E.demonIcons[E:Call(UnitCreatureFamily,member.unit)] or "Ability_Hunter_Pet_Wolf")) or nil}
        self.fight.actors[id]=a; table.insert(self.fight.order,id)
        if self:Time(at)>1 then self:Note("Journal roster changed") end
    end
    return a
end
function J:RefreshActors(at)
    for _,m in ipairs(E.roster or {}) do if m.connected then self:Actor(m,at) end end
end
function J:Point(series,t,v,q,kind,max)
    if not self.fight or self.fight.points>=self.limit then self:Note("Journal capture limit reached"); return end
    if not finite(t) or (v~=nil and not finite(v)) then return end
    local p={t=t,v=v,q=q,kind=kind,max=max}
    local prev=series[table.getn(series)]
    if prev and t<prev.t then return end
    if prev and t==prev.t then series[table.getn(series)]=p; return end
    table.insert(series,p); self.fight.points=self.fight.points+1
end
function J:Enemy(guid,unit,at,name)
    if not self.fight or not guid then self:Note("Journal enemy identity unavailable"); return end
    local enemy=self.fight.enemies[guid]
    if not enemy then
        if count(self.fight.enemies)>=40 then self:Note("Journal capture limit reached"); return end
        unit=unit or guid
        enemy={id=guid,name=clean(name or E:Call(UnitName,unit) or E:L("Unknown")),mark=E:Call(GetRaidTargetIndex,unit),
            level=E:Call(UnitLevel,unit),classification=E:Call(UnitClassification,unit) or "normal",
            creature=E:Call(UnitCreatureType,unit),start=self:Time(at),series={},owners={},
            icon=self:EnemyIcon(unit)}
        local display=E:Call(GetUnitField,unit,"displayId")
        if finite(display) then enemy.display=display end
        self.fight.enemies[guid]=enemy; table.insert(self.fight.enemyOrder,guid)
    end
    -- Metadata may first arrive through an unresolved combat-event GUID.
    local resolved=E:ResolveEnemyUnit({guid=guid,unit=unit})
    if resolved then
        local classification=E:Call(UnitClassification,resolved)
        if classification then enemy.classification=classification end
        enemy.level=E:Call(UnitLevel,resolved) or enemy.level
        enemy.creature=E:Call(UnitCreatureType,resolved) or enemy.creature
        enemy.icon=self:EnemyIcon(resolved)
        if self.CapturePortrait then self:CapturePortrait(enemy,resolved) end
    end
    enemy.last=self:Time(at); return enemy
end
function J:AddEvent(kind,actor,target,amount,spell,at,extra)
    local f=self.fight; if not f then return end
    if table.getn(f.events)>=self.eventLimit then self:Note("Journal capture limit reached"); return end
    local row={t=self:Time(at),kind=kind,actor=actor,target=target,amount=amount,spell=spell,sequence=table.getn(f.events)+1}
    for k,v in pairs(extra or {}) do row[k]=v end
    table.insert(f.events,row)
end
function J:Spell(id,name)
    local label=name or (id and E:Call(GetSpellRecField,id,"name"))
    local texture=id and E:Call(GetSpellTexture,"spellId:"..id)
    return clean(label or (id and (E:L("Ability").." "..id)) or E:L("Melee")),texture
end
function J:Damage(actor,target,amount,spell,at,name,crit)
    if actor and amount and amount>0 then E:NoteParticipation(actor.guid,target) end
    if not self:Allowed() or not actor or not finite(amount) or amount<0 then return end
    self:Begin(at); local a=self:Actor(actor,at); if not a then return end
    self.lastActive=at; a.damage=a.damage+amount; self.fight.damage=self.fight.damage+amount
    local enemy=target and self:Enemy(target,target,at)
    if enemy then enemy.firstDamageAt=enemy.firstDamageAt or self:Time(at) end
    local label,texture=self:Spell(spell,name)
    self:AddEvent("damage",a.id,enemy and enemy.id,amount,spell,at,{name=label,icon=texture,crit=crit})
end
function J:Heal(actor,target,amount,spell,at,name,crit)
    if not self:Allowed() or not actor or not finite(amount) or amount<0 then return end
    if not self.fight and not E:AnyCombat() then return end
    self:Begin(at); local a=self:Actor(actor,at); if not a then return end
    self.lastActive=at
    local targetMember=E:MemberForGUID(target)
    local h=self.health and self.health[target]
    local effective,over
    if h and at-h.at<0.65 and h.max>0 then
        effective=math.min(amount,math.max(0,h.max-h.health)); over=amount-effective
        h.health=h.health+effective
        a.healed=a.healed+effective; a.over=a.over+over
        if not a.healingGap then
            self:Point(a.healing,self:Time(at),a.healed,"estimate")
            self:Point(a.overheal,self:Time(at),a.over,"estimate")
        end
        self:Note("Journal healing uses observed health")
    else
        self:Point(a.healing,self:Time(at),nil,"missing")
        self:Point(a.overheal,self:Time(at),nil,"missing")
        a.healingGap=true; self:Note("Journal healing incomplete")
    end
    local label,texture=self:Spell(spell,name)
    self:AddEvent("heal",a.id,targetMember and (targetMember.guid or targetMember.key),amount,spell,at,
        {name=label,icon=texture,effective=effective,overheal=over,crit=crit,q="estimate"})
end
function J:Death(guid,at)
    if not self.fight then return end
    local enemy=self.fight.enemies[guid]; local a=self.fight.actors[guid]
    if enemy and not enemy.dead then
        self.lastActive=at
        enemy.dead=self:Time(at); enemy.last=enemy.dead
        self:AddEvent("death",nil,guid,nil,nil,at,{name=enemy.name})
        self.previousOwners[guid]=nil
    elseif a and not a.dead then
        self.lastActive=at
        a.dead=self:Time(at); self:AddEvent("death",guid,nil,nil,nil,at,{name=a.name})
        self:Point(a.stock,a.dead,nil,"dead")
    end
end
function J:Structured(name,a,b,c,d,e,f,g,h)
    if not self:Allowed() then return end
    local actor,target,amount,id,kind,critical,label
    if name=="UNIT_DIED" then self:Death(a,GetTime()); return
    elseif name=="AUTO_ATTACK_SELF" or name=="AUTO_ATTACK_OTHER" then
        actor=a; target=b; amount=tonumber(c); kind="damage"
        critical=finite(d) and math.mod(math.floor(d/128),2)==1
    elseif name=="SPELL_DAMAGE_EVENT_SELF" or name=="SPELL_DAMAGE_EVENT_OTHER" then
        actor=b; target=a; amount=tonumber(d); id=tonumber(c); kind="damage"
        critical=finite(f) and math.mod(math.floor(f/2),2)==1
        if type(h)=="string" and string.find(h,",89$") then self:Note("Journal percentage damage unavailable"); return end
    elseif name=="SPELL_HEAL_BY_SELF" or name=="SPELL_HEAL_BY_OTHER" then
        actor=b; target=a; amount=tonumber(d); id=tonumber(c); kind="heal"; critical=e==1
    elseif name=="DAMAGE_SHIELD_SELF" or name=="DAMAGE_SHIELD_OTHER" then
        actor=a; target=b; amount=tonumber(c); kind="damage"; label=E:L("Damage shield")
    else return end
    local member=E:MemberForGUID(actor)
    if not member then return end
    if not self.backend then self.backend="structured"; self.pending={}; if self.fight and self.fight.damage>0 then self:Note("Journal event source changed") end end
    if kind=="damage" then
        if E:MemberForGUID(target) then return end
        self:Damage(member,target,amount,id,GetTime(),label,critical)
    else self:Heal(member,target,amount,id,GetTime(),nil,critical) end
end
function J:Text(message)
    if not self:Allowed() or self.backend then return end
    local actor,target,amount,spell=E:ParseDamage(message)
    local kind="damage"
    if not actor then actor,target,amount,spell=E:ParseHeal(message); kind="heal" end
    local m=actor and E:MemberForName(actor)
    if not m or not finite(amount) then return end
    local tm=kind=="heal" and E:MemberForName(target)
    local guid=tm and tm.guid or E:UniqueEnemyForText(target)
    self.pending=self.pending or {}
    if table.getn(self.pending)<100 then table.insert(self.pending,{at=GetTime(),actor=copy(m),target=guid,amount=amount,spell=spell,kind=kind}) end
end
function J:Cast(item,spell,caster,target)
    if not self:Allowed() then return end
    local member=E:MemberForGUID(caster)
    if not member or (not self.fight and not E:AnyCombat()) then return end
    self:Begin(); local a=self:Actor(member); if not a then return end
    local label,texture=self:Spell(tonumber(spell))
    local cd=E:Call(GetSpellRecField,tonumber(spell),"recoveryTime")
    if finite(cd) then cd=cd/1000 else cd=nil end
    if member.key==E.playerKey then
        local data=E:Call(GetSpellIdCooldown,tonumber(spell))
        if type(data)=="table" then
            cd=math.max(tonumber(data.individualDurationMs) or 0,tonumber(data.categoryDurationMs) or 0)/1000
        end
    end
    local rule=E:ThreatRule(tonumber(spell),member)
    local threat=rule and (rule.kind=="flat" or rule.kind=="addDamage" or rule.kind=="invalidate" or
        rule.kind=="petInvalidate" or ((rule.kind=="holy" or rule.kind=="damage") and rule.value and rule.value~=1))
    local kind=threat and "threat" or cd and cd>=60 and "cooldown" or nil
    local itemId=tonumber(item)
    if itemId and itemId>0 then
        local name=E:Call(GetItemInfo,itemId) or E:Call(GetItemStatsField,itemId,"displayName")
        label=clean(name or label)
        local display=E:Call(GetItemStatsField,itemId,"displayInfoID")
        local path=display and E:Call(GetItemIcon,itemId)
        if type(path)=="string" then texture=path end
        kind="item"
    end
    if kind then self:AddEvent(kind,a.id,target,nil,tonumber(spell),GetTime(),{name=label,icon=texture,item=itemId,cd=cd,threat=threat and true or nil}) end
end
function J:SampleResources(at,record)
    local observed={}; self.health=self.health or {}
    for _,m in ipairs(E.roster or {}) do
        local id=m.guid or m.key
        local value,max=E:Call(UnitMana,m.unit),E:Call(UnitManaMax,m.unit)
        local kind=E:Call(UnitPowerType,m.unit)
        local hp,hmax=E:Call(UnitHealth,m.unit),E:Call(UnitHealthMax,m.unit)
        if m.connected and finite(hp) and finite(hmax) and hmax>0 then self.health[id]={health=hp,max=hmax,at=at} end
        if m.connected and finite(value) and finite(max) and max>0 and finite(kind) then
            local current={value=value,max=max,kind=kind,health=hp,at=at,alive=m.alive}
            observed[id]=current
            if record then
                local a=self:Actor(m,at)
                if a then
                    a.startPower=a.startPower or value; a.startMax=a.startMax or max; a.startType=a.startType or kind
                    self:Point(a.stock,self:Time(at),m.alive and value/max*100 or nil,"observed",kind,max)
                    local prev=self.resources[id]
                    if prev and prev.kind==kind and prev.max==max and prev.alive and m.alive and at-prev.at<1.25 then
                        local spent=math.max(0,prev.value-value)
                        a.cost[kind]=(a.cost[kind] or 0)+spent
                        self:Point(a.spend,self:Time(at),a.cost[kind],"estimate",kind)
                    elseif prev and (prev.kind~=kind or prev.max~=max) then
                        self:Point(a.spend,self:Time(at),nil,"missing",kind)
                        self:Note("Journal resource type changed")
                    end
                    if not m.alive then self:Death(id,at) elseif a.dead then a.dead=nil end
                end
            end
        elseif record and self.fight.actors[id] then
            self:Point(self.fight.actors[id].stock,self:Time(at),nil,"missing")
            self:Note("Journal resource observations missing")
        end
    end
    if record then self.resources=observed else self.idleResources=observed; self.idleAt=at end
end
function J:Sample(at)
    local fight=self.fight; if not fight then return end
    if fight.points>=self.limit then self:Note("Journal capture limit reached"); return end
    self:RefreshActors(at); self:SampleResources(at,true)
    local seen={}; local t=self:Time(at); local elapsed=self.lastSample and math.min(1,at-self.lastSample) or 0
    for _,entry in pairs(E.enemies or {}) do
        if entry.guid and entry.combat and not entry.stale then
            local enemy=self:Enemy(entry.guid,entry.unit,at,entry.name)
            if enemy and not enemy.dead then
                seen[entry.guid]=true; enemy.mark=entry.mark or enemy.mark
                local holder=entry.owner and self.fight.actors[entry.owner.guid or entry.owner.key]
                local role=holder and E:Role(holder.key)
                local owner=holder and holder.id
                local quality=entry.ownerQuality
                local prev=self.previousOwners[entry.guid]
                if prev and elapsed>0 then
                    if prev.quality=="api" and quality=="api" and owner==prev.owner and owner then
                        fight.knownOwner=fight.knownOwner+elapsed
                        if role=="tank" and prev.role=="tank" then fight.tankOwner=fight.tankOwner+elapsed end
                    else fight.unknownOwner=fight.unknownOwner+elapsed end
                end
                table.insert(enemy.owners,{t=t,id=owner,role=role,q=quality})
                if owner and prev and prev.owner~=owner then self:AddEvent("aggro",owner,entry.guid,nil,nil,at,{previous=prev.owner,q=quality}) end
                self.previousOwners[entry.guid]={owner=owner,quality=quality,role=role}
                for _,id in ipairs(fight.order) do
                    local actor=fight.actors[id]; local sample=entry.samples and entry.samples[actor.key]
                    enemy.series[id]=enemy.series[id] or {}
                    self:Point(enemy.series[id],t,sample and sample.pct or nil,sample and sample.quality or "missing")
                    if sample and sample.pct and sample.pct>0 then enemy.firstThreatAt=enemy.firstThreatAt or t end
                end
            end
        end
    end
    for id,enemy in pairs(fight.enemies) do
        if not enemy.dead and not seen[id] then
            if E:Call(UnitIsDeadOrGhost,id) then self:Death(id,at)
            else
                for _,series in pairs(enemy.series) do self:Point(series,t,nil,"missing") end
                table.insert(enemy.owners,{t=t,q="missing"}); fight.unknownOwner=fight.unknownOwner+elapsed
                self.previousOwners[id]=nil
            end
        end
    end
    for _,a in pairs(fight.actors) do
        if a.healed>0 and not a.healingGap then self:Point(a.healing,t,a.healed,"estimate"); self:Point(a.overheal,t,a.over,"estimate") end
    end
    self.lastSample=at; fight.duration=t
end
function J:Finish(at)
    if not self.fight then return end
    local f=self.fight; f.duration=math.max(0.1,(at or self.lastActive or GetTime())-f.started)
    f.finished=true; f.source=self.backend or "chat"; f.peers=self:GroupEvidence()
    table.sort(f.events,function(a,b) if a.t==b.t then return a.sequence<b.sequence end; return a.t<b.t end)
    f.notes["Journal resource consumption is a lower bound"]=true
    f.notes["Journal local observations only"]=true
    if f.damage>0 or table.getn(f.enemyOrder)>0 or table.getn(f.events)>0 then
        self.db.last=f
        local recorder=E.recorder
        if recorder and recorder.db and recorder.db.enabled and recorder.JournalEvidence then
            local ok=pcall(function()
                local evidence=recorder:JournalEvidence(f)
                recorder.db.lastJournal=evidence
                recorder:SessionEntry("journal",evidence)
            end)
            if not ok then recorder.sessionFault=true end
        end
        if self.window and self.window:IsShown() then self.viewFight=nil; self:Show() end
    end
    self.fight=nil; self.resources={}; self.lastSample=nil
end
function J:Tick()
    if not self:Allowed() then if self.fight then self:Note("Journal capture interrupted"); self:Finish(GetTime()) end; return end
    local at=GetTime()
    if not self.backend and self.pending then
        local keep={}
        for _,p in ipairs(self.pending) do
            if at-p.at>0.35 then
                if p.kind=="damage" then self:Damage(p.actor,p.target,p.amount,nil,p.at,p.spell)
                else self:Heal(p.actor,p.target,p.amount,nil,p.at,p.spell) end
            else table.insert(keep,p) end
        end
        self.pending=keep
    end
    local combat=E:AnyCombat()
    if not combat then self.capped=nil end
    if combat and not self.capped then self:Begin(at); self.lastActive=at end
    if self.fight then
        if at-self.fight.started>1800 then self:Note("Journal capture limit reached"); self.capped=true; self:Finish(at); return end
        local firstObservation=false
        for id,enemy in pairs(self.fight.enemies) do
            local entry=E.enemies and E.enemies[id]
            if not enemy.firstThreatAt and not enemy.dead and entry and entry.combat then
                for _,sample in pairs(entry.samples or {}) do if sample.pct and sample.pct>0 then firstObservation=true end end
            end
        end
        -- Do not defer the first available value to the next half-second
        -- interval. Keep its real observation time; never backfill from zero.
        if firstObservation or combat and (not self.lastSample or at-self.lastSample>=self.interval) then self:Sample(at) end
        if not combat and at-(self.lastActive or at)>=1 then self:Finish(self.lastActive) end
    elseif not self.idleAt or at-self.idleAt>=0.5 then self:SampleResources(at,false) end
end
function J:At(series,t,maxGap)
    if not series or table.getn(series)==0 then return end
    local lo,hi=1,table.getn(series)
    if t<series[1].t or t>series[hi].t then return end
    while lo<hi do local mid=math.floor((lo+hi+1)/2); if series[mid].t<=t then lo=mid else hi=mid-1 end end
    local a,b=series[lo],series[lo+1]
    if not a or a.v==nil then return end
    if t==a.t then return a.v,a end
    if not b or b.v==nil or b.kind~=a.kind or b.t-a.t>(maxGap or 1.25) then return end
    return a.v+(b.v-a.v)*(t-a.t)/(b.t-a.t),a
end
function J:HeldAt(series,t,maxGap)
    local value,point=self:At(series,t,maxGap)
    if value~=nil then return value,point end
    if not series or table.getn(series)==0 or t<series[1].t then return end
    local lo,hi=1,table.getn(series)
    while lo<hi do local mid=math.floor((lo+hi+1)/2); if series[mid].t<=t then lo=mid else hi=mid-1 end end
    -- Cache previous usable indices for long recordings. Never change the raw
    -- points: analysts must still see precisely where capture became unknown.
    self.holdCache=self.holdCache or setmetatable({},{__mode="k"})
    local cache=self.holdCache[series]; local n=table.getn(series)
    if not cache or cache.n~=n or cache.last~=series[n] then
        cache={n=n,last=series[n],indices={}}; local previous
        for i,p in ipairs(series) do
            if p.q=="dead" or (previous and p.kind~=nil and series[previous].kind~=p.kind) then previous=nil end
            if p.v~=nil then previous=i end
            cache.indices[i]=previous
        end
        self.holdCache[series]=cache
    end
    local index=cache.indices[lo]
    if not index then return end
    local p=series[index]
    return p.v,{t=p.t,v=p.v,q=p.q,kind=p.kind,max=p.max,held=true,observedAt=p.t}
end
function J:OwnerAt(enemy,t)
    if enemy.dead and t>=enemy.dead then return end
    local points=enemy.owners; local lo,hi=1,table.getn(points)
    if hi==0 or t<points[1].t then return end
    while lo<hi do local mid=math.floor((lo+hi+1)/2); if points[mid].t<=t then lo=mid else hi=mid-1 end end
    local p=points[lo]; if t-p.t<1.25 then return p end
end
function J:FirstThreatPoint(enemy)
    local first
    for _,series in pairs(enemy.series or {}) do
        for _,point in ipairs(series) do
            if point.v~=nil and point.v>0 then first=math.min(first or point.t,point.t); break end
        end
    end
    return first
end
function J:Summary(f)
    if not f then return {} end
    local mana,hasMana=0,false
    for _,a in pairs(f.actors) do
        mana=mana+(a.cost[0] or 0)
        if a.cost[0]~=nil then hasMana=true end
    end
    local observed=f.knownOwner+f.unknownOwner
    local partial=f.notes["Journal capture limit reached"] or f.notes["Journal capture interrupted"]
    return {dps=f.damage/math.max(0.1,f.duration),damage=f.damage,duration=f.duration,mana=hasMana and mana or nil,
        ratio=not partial and hasMana and f.damage>0 and mana/f.damage or nil,
        damagePerMana=not partial and hasMana and mana>0 and not f.notes["Journal resource observations missing"] and f.damage/mana or nil,
        binding=not partial and f.knownOwner>0 and f.tankOwner/f.knownOwner*100 or nil,
        coverage=observed>0 and f.knownOwner/observed*100 or 0}
end
function J:SaveReference()
    local f=self.viewFight or self.db.last
    if not f or not f.finished then return false end
    self.db.reference=copy(f); self.compare=true; return true
end
function J:CaptureStructured(name,a,b,c,d,e,f,g,h)
    if not self.db then return end
    local ok,err=pcall(function() J:Structured(name,a,b,c,d,e,f,g,h) end)
    if not ok then self.fault=tostring(err) end
end
function J:CaptureText(message)
    if not self.db then return end
    local ok,err=pcall(function() J:Text(message) end)
    if not ok then self.fault=tostring(err) end
end
function E:InitJournal()
    if J.db then return end
    if type(EasyThreatJournalDB)~="table" or EasyThreatJournalDB.schema~=1 then EasyThreatJournalDB={schema=1} end
    J.db=EasyThreatJournalDB
    J.frame=CreateFrame("Frame",nil,UIParent)
    for _,name in ipairs({"SPELL_GO_SELF","SPELL_GO_OTHER","PLAYER_LOGOUT"}) do pcall(J.frame.RegisterEvent,J.frame,name) end
    local v=self:Call(GetCVar,"NP_EnableSpellGoEvents")
    if v and v~="" and type(SetCVar)=="function" then pcall(SetCVar,"NP_EnableSpellGoEvents","1") end
    J.frame:SetScript("OnEvent",function()
        local ok,err=pcall(function() if event=="PLAYER_LOGOUT" then J:Note("Journal capture interrupted"); J:Finish(GetTime()) else J:Cast(arg1,arg2,arg3,arg4) end end)
        if not ok then J.fault=tostring(err) end
    end)
    J.frame:SetScript("OnUpdate",function()
        J.elapsed=(J.elapsed or 0)+(arg1 or 0); if J.elapsed<0.1 then return end; J.elapsed=0
        local ok,err=pcall(function() J:Tick() end); if not ok then J.fault=tostring(err) end
    end)
    J:InitBook()
end
-- Enemy-seconds with a stable observed target; never claim this is a threat API.
function J:TankControl(f)
    local assigned=false
    for _,a in pairs(f.actors) do if a.role=="tank" then assigned=true end end
    for _,enemy in pairs(f.enemies) do for _,point in ipairs(enemy.owners or {}) do if point.role=="tank" then assigned=true end end end
    if not assigned then return nil,0,false end
    local known,tank,total,approximate=0,0,0,false
    for _,enemy in pairs(f.enemies) do
        local finish=math.min(f.duration,enemy.dead or f.duration)
        total=total+math.max(0,finish-(enemy.start or 0))
        for i,p in ipairs(enemy.owners or {}) do
            local nextPoint=enemy.owners[i+1]
            if nextPoint and p.id and p.id==nextPoint.id and p.role==nextPoint.role and
                (p.q=="api" or p.q=="observed") and (nextPoint.q=="api" or nextPoint.q=="observed") then
                local elapsed=math.max(0,math.min(nextPoint.t,finish)-p.t)
                if elapsed<=1.25 then
                    known=known+elapsed
                    if p.role=="tank" then tank=tank+elapsed end
                    if p.q~="api" or nextPoint.q~="api" then approximate=true end
                end
            end
        end
    end
    return known>0 and tank/known*100 or nil,total>0 and known/total*100 or 0,approximate,known,tank
end
function J:GroupEvidence()
    local out={}
    for _,m in ipairs(E.roster) do if not m.pet then
        local localPlayer=m.key==E.playerKey
        local profile=not localPlayer and E:PeerProfile(m)
        local info=not localPlayer and E:PeerInfo(m)
        local status=info and (info.build~=E.build or info.rules~=E.ruleVersion) and "Different addon build" or not m.connected and "Offline" or localPlayer and "This client" or profile and "Exchange active" or "No addon reply"
        local sharing
        if localPlayer and E.groupRecorder then sharing=E.groupRecorder.sharing
        elseif info then sharing=info.sharing end
        table.insert(out,{name=clean(m.name),status=status,build=localPlayer and E.build or info and info.build or nil,
            sharing=sharing,
            rules=localPlayer and E.ruleVersion or info and info.rules})
    end end
    return out
end

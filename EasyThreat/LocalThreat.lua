-- Per creature GUID and actor GUID ledger. No fight-wide damage ratios.
local E=EasyThreat
-- Participation is separate from computed amounts: unsupported taunts/heals
-- must end build-up too. Taking damage or merely targeting is not an action.
function E:NoteThreatAction(data,member)
    if not data or not member or not member.guid then return end
    data.threatActors=data.threatActors or {}
    data.threatActors[member.guid]=true
end
function E:MemberForGUID(guid)
    if type(guid)~="string" then return end
    for _,member in ipairs(self.roster) do if member.guid==guid then return member end end
end
function E:ActivateStructured()
    self.localBackend="nampower"
    -- The numeric stream restarts to prevent double counting. Participation
    -- does not: changing provider cannot make an ongoing fight an opener.
    for guid,data in pairs(self.ledger or {}) do
        self.ledger[guid]={guid=guid,name=data.name,values={},uncertain={},involved=data.involved,
            threatActors=data.threatActors,startKnown=data.startKnown,updated=GetTime(),
            incompleteStart=data.incompleteStart or next(data.values or {})~=nil}
    end
    self.ledger=self.ledger or {}
end
function E:LocalEnemy(guid)
    if type(guid)~="string" or not self:Exists(guid) or not self:Call(UnitCanAttack,"player",guid) or
        self:Call(UnitIsPlayer,guid) or self:Call(UnitIsDeadOrGhost,guid) then return end
    self.ledger=self.ledger or {}
    local data=self.ledger[guid]
    if not data then
        data={guid=guid,name=self:Call(UnitName,guid),values={},uncertain={},involved={},updated=GetTime()}
        data.startKnown=self.enemySeenIdle and self.enemySeenIdle[guid] and GetTime()-self.enemySeenIdle[guid]<15 and true or false
        if self.enemySeenIdle then self.enemySeenIdle[guid]=nil end
        for actor,reason in pairs(self.blockedEnemies and self.blockedEnemies[guid] or {}) do data.uncertain[actor]=reason end
        self.ledger[guid]=data
    end
    data.updated=GetTime()
    return data
end
function E:InvalidateActor(guid,reason,enemyGUID)
    if type(guid)~="string" then return end
    if enemyGUID then
        self.blockedEnemies=self.blockedEnemies or {}
        self.blockedEnemies[enemyGUID]=self.blockedEnemies[enemyGUID] or {}
        self.blockedEnemies[enemyGUID][guid]=reason or true
        self:LocalEnemy(enemyGUID)
    else self.blockedActors=self.blockedActors or {}; self.blockedActors[guid]=reason or true end
    for key,data in pairs(self.ledger or {}) do
        if not enemyGUID or key==enemyGUID then
            data.values[guid]=nil; data.uncertain[guid]=reason or true
        end
    end
    self.tooltipSample=nil
    self:ThreatDiagnostics("invalidated",reason)
end
function E:RuleFailure(member,reason,enemyGUID,spellID)
    if not member then return end
    self:NoteClassLimit(member,reason or "special-threat",spellID)
    self:InvalidateActor(member.guid,reason,enemyGUID)
end
function E:RecordThreatEvent(kind,actorGUID,enemyGUID,amount,spellID,school,rule)
    if self.NoteParticipation and kind=="damage" and self:Finite(amount) and amount>0 then self:NoteParticipation(actorGUID,enemyGUID) end
    if not self.db or self.demo or not self.db.enabled then return end
    local member=self:MemberForGUID(actorGUID)
    if not member or not member.alive or not member.connected then return end
    rule=rule or self:ThreatRule(spellID,member)
    if rule and ((rule.pet and not member.pet) or (rule.class and (member.pet or member.class~=rule.class))) then rule=nil end
    if rule and rule.kind=="invalidate" then
        local affected=self:LocalEnemy(enemyGUID)
        local scope=rule.scope=="enemy" and affected and enemyGUID or nil
        if affected then self:NoteThreatAction(affected,member) end
        if not self.db.localThreat then return end
        self:RuleFailure(member,rule.reason or "taunt",scope,spellID); return
    end
    if rule and rule.kind=="petInvalidate" then
        if not self.db.localThreat then return end
        local pet=self:MemberForGUID(enemyGUID)
        if pet and pet.pet and pet.owner==member.name then self:RuleFailure(pet,rule.reason,nil,spellID) end
        return
    end
    if not self:Finite(amount or 0) then return end
    if kind=="damage" and (amount or 0)<=0 then return end
    if kind=="aura" and rule and rule.reason=="split-threat" then
        if not self.db.localThreat then return end
        self:RuleFailure(member,rule.reason,nil,spellID); return
    end
    local data=self:LocalEnemy(enemyGUID)
    if not data then return end
    data.involved[actorGUID]=true
    if (kind=="damage" and not (rule and rule.kind=="nothreat")) or (rule and (rule.kind=="flat" or rule.kind=="unresolved")) then
        self:NoteThreatAction(data,member)
    end
    if not self.db.localThreat then return end
    if rule and rule.kind=="unresolved" then
        if rule.reason=="ignite-share" then
            for _,mage in ipairs(self.roster) do
                if not mage.pet and mage.class=="MAGE" then self:RuleFailure(mage,rule.reason,enemyGUID,spellID) end
            end
        else self:RuleFailure(member,rule.reason,enemyGUID,spellID) end
        return
    end
    local gain,multiplier,reason=0
    if kind=="damage" then
        if spellID and not rule then rule={spell=true} end
        if (spellID or (rule and rule.spell)) and not school and not (rule and (rule.kind=="holy" or rule.kind=="nothreat")) then
            self:NoteClassLimit(member,"school",spellID)
        end
        multiplier,reason=self:ThreatMultiplier(member,school,rule)
        if not multiplier then self:RuleFailure(member,reason,enemyGUID,spellID); return end
        gain=((amount or 0)+(rule and rule.kind=="addDamage" and rule.value or 0))*multiplier
    elseif kind=="aura" and rule and rule.kind=="flat" then
        data.casts=data.casts or {}
        local cast=actorGUID..":"..tostring(spellID or rule.rank)
        if data.casts[cast] and GetTime()-data.casts[cast]<0.1 then return end
        data.casts[cast]=GetTime()
        multiplier,reason=self:ThreatMultiplier(member,school,rule)
        if not multiplier then self:RuleFailure(member,reason,enemyGUID,spellID); return end
        gain=rule.value*multiplier
        if gain<0 and data.values[actorGUID]==nil then return end
    else return end
    if data.uncertain[actorGUID] or (self.blockedActors and self.blockedActors[actorGUID]) then return end
    if self.RecordOpeningThreat then self:RecordOpeningThreat(data,member,gain) end
    data.values[actorGUID]=math.max(0,(data.values[actorGUID] or 0)+gain)
    data.source=self.localBackend or "chat"
    self:ThreatDiagnostics("local-event",kind.." "..tostring(spellID or "melee"))
    self.tooltipSample=nil
end
function E:CaptureHealth()
    self.healthBefore=self.healthBefore or {}
    for _,member in ipairs(self.roster) do
        local health,max=self:Call(UnitHealth,member.unit),self:Call(UnitHealthMax,member.unit)
        if member.guid and self:Finite(health) and self:Finite(max) and max>0 then
            self.healthBefore[member.guid]={health=health,max=max,at=GetTime()}
        end
    end
end
function E:RecordThreatHeal(actorGUID,targetGUID,amount,spellID,rule)
    if not self.db.enabled or self.demo then return end
    local member=self:MemberForGUID(actorGUID)
    local target=self:MemberForGUID(targetGUID)
    local health=self.healthBefore and self.healthBefore[targetGUID]
    if not member or not target or not member.alive or not target.alive or not self:Finite(amount) or amount<=0 then return end
    local healthKnown=health and GetTime()-health.at<=0.6
    -- Use recent pre-heal health; cap overheal and reserve this gain immediately
    -- so simultaneous healing cannot fill the same health deficit twice.
    local effective=healthKnown and math.min(amount,math.max(0,health.max-health.health))
    if healthKnown then health.health=health.health+effective end
    local mobs={}
    for _,data in pairs(self.ledger or {}) do
        local current=self:Exists(data.guid) and self:Call(UnitAffectingCombat,data.guid)
        if current and not self:Call(UnitIsDeadOrGhost,data.guid) and (data.involved[targetGUID] or
            self:GUID(data.guid.."target")==targetGUID) then table.insert(mobs,data) end
    end
    local count=table.getn(mobs)
    if count==0 or (effective and effective<=0) then return end
    rule=rule or self:ThreatRule(spellID,member)
    if not rule or (rule.kind~="noheal" and rule.kind~="nothreat") then
        for _,data in ipairs(mobs) do self:NoteThreatAction(data,member) end
    end
    -- A heal with unknown overheal ends the safe single-actor assumption,
    -- but still cannot supply an invented numerical threat amount.
    if not healthKnown then self:ThreatDiagnostics("heal-no-health"); return end
    if not self.db.localThreat then return end
    if rule and rule.kind=="unresolved" then self:RuleFailure(member,rule.reason,nil,spellID); return end
    local school=self:SchoolForSpell(spellID)
    if not school and not (rule and (rule.kind=="noheal" or rule.kind=="nothreat")) then self:NoteClassLimit(member,"school",spellID) end
    local multiplier,reason=self:HealingThreatMultiplier(member,rule,school)
    if not multiplier then self:RuleFailure(member,reason,nil,spellID); return end
    if self.blockedActors and self.blockedActors[actorGUID] then return end
    local gain=effective*multiplier/count
    if gain<=0 then return end
    for _,data in ipairs(mobs) do
        if not data.uncertain[actorGUID] then data.values[actorGUID]=(data.values[actorGUID] or 0)+gain end
        data.updated=GetTime(); data.involved[actorGUID]=true
    end
    self:ThreatDiagnostics("local-heal",tostring(effective).." / "..count)
    self.tooltipSample=nil
end
function E:TrackedDeath(guid)
    if type(guid)~="string" then return false end
    if self:MemberForGUID(guid) or (self.ledger and self.ledger[guid]) or
        (self.serverSnapshots and self.serverSnapshots[guid]) then return true end
    for _,enemy in pairs(self.enemies or {}) do if enemy.guid==guid then return true end end
    return false
end
function E:StructuredThreatEvent(name,a,b,c,d,e,f,g,h,i)
    if self.journal then self.journal:CaptureStructured(name,a,b,c,d,e,f,g,h) end
    if not self.db.enabled or self.demo then return end
    if self.NoteSourceEvent then self:NoteSourceEvent(name,a,b,c,d) end
    if name=="UNIT_DIED" then
        if not self:TrackedDeath(a) then return end
        if self.ledger then self.ledger[a]=nil end
        if self.serverSnapshots then self.serverSnapshots[a]=nil end
        -- Remove cached marked enemies even if their corpse GUID is already
        -- out of range. Unrelated world deaths must not fill actor barriers.
        for key,enemy in pairs(self.enemies or {}) do
            if enemy.guid==a then
                self.enemies[key]=nil
                if self.visibility then self.visibility[key]=nil end
                if self.pairVisibility then self.pairVisibility[key]=nil end
            end
        end
        if self:MemberForGUID(a) then self:InvalidateActor(a,"death") end
        self.tooltipSample=nil
        return
    end
    if self.NoteParticipation then
        if (name=="AUTO_ATTACK_SELF" or name=="AUTO_ATTACK_OTHER") and self:Finite(tonumber(c)) and tonumber(c)>0 then self:NoteParticipation(a,b)
        elseif (name=="SPELL_DAMAGE_EVENT_SELF" or name=="SPELL_DAMAGE_EVENT_OTHER") and self:Finite(tonumber(d)) and tonumber(d)>0 then self:NoteParticipation(b,a) end
    end
    local kind,actor,target,amount,id,school,rule
    if name=="AUTO_ATTACK_SELF" or name=="AUTO_ATTACK_OTHER" then kind="damage"; actor=a; target=b; amount=tonumber(c); school="physical"
    elseif name=="DAMAGE_SHIELD_SELF" or name=="DAMAGE_SHIELD_OTHER" then
        -- Nampower reports the shield wearer, attacker, damage, school ENUM.
        -- It does not report the spell ID. Keep the real damage and school,
        -- but do not pretend to know an ability-specific threat multiplier.
        kind="damage"; actor=a; target=b; amount=tonumber(c)
        school=self.schoolNames[tonumber(d)]; rule={spell=true}
    elseif name=="SPELL_DAMAGE_EVENT_SELF" or name=="SPELL_DAMAGE_EVENT_OTHER" then
        kind="damage"; actor=b; target=a; id=tonumber(c); amount=tonumber(d)
        -- DBC school is an enum. Do not guess whether an event's field is a mask.
        school=self:SchoolForSpell(id)
    elseif name=="AURA_CAST_ON_SELF" or name=="AURA_CAST_ON_OTHER" then
        kind="aura"; id=tonumber(a); actor=b; target=c; amount=0
    elseif name=="SPELL_HEAL_BY_SELF" or name=="SPELL_HEAL_BY_OTHER" then
        kind="heal"; actor=b; target=a; id=tonumber(c); amount=tonumber(d)
    else return end
    if type(actor)~="string" or type(target)~="string" or not self:Finite(amount) then return end
    local source,targetMember=self:MemberForGUID(actor),self:MemberForGUID(target)
    if not source then
        local owner=self:MemberForGUID(self:Call(UnitOwnerGUID,actor) or self:GUID(actor.."owner"))
        if owner and owner.class=="SHAMAN" then
            if not self.localBackend then self:ActivateStructured() end
            self:ThreatDiagnostics("structured",name)
            local transfer,known=self:TalentAmount(owner,"totemicAlignment")
            if not known or transfer>0 then
                self:NoteClassLimit(owner,"totem-transfer")
                self:InvalidateActor(owner.guid,"totem-transfer",kind=="damage" and target or nil)
            end
            return
        end
        if not targetMember then return end
    end
    if not self.localBackend then
        -- First delivered structured event takes over; discard text totals so
        -- the transition cannot count that same event twice.
        self:ActivateStructured()
    end
    self:ThreatDiagnostics("structured",name)
    if rule and source then self:NoteClassLimit(source,"shield-identity") end
    if kind=="heal" then self:RecordThreatHeal(actor,target,amount,id)
    elseif source then self:RecordThreatEvent(kind,actor,target,amount,id,school,rule)
    elseif targetMember and kind=="damage" then
        local data=self:LocalEnemy(actor)
        if data then data.involved[target]=true end
    end
end
function E:InitLocalThreat()
    self.ledger={}; self:CaptureHealth()
    self.structuredRegistration={}
    -- Enable only known, already-existing extension switches. RegisterEvent is
    -- guarded because ordinary Vanilla clients reject unknown event names.
    for _,cvar in ipairs({"NP_EnableAutoAttackEvents","NP_EnableSpellHealEvents","NP_EnableAuraCastEvents"}) do
        local value=self:Call(GetCVar,cvar)
        if value~=nil and value~="" and type(SetCVar)=="function" then pcall(SetCVar,cvar,"1") end
    end
    for _,name in ipairs({"AUTO_ATTACK_SELF","AUTO_ATTACK_OTHER","SPELL_DAMAGE_EVENT_SELF","SPELL_DAMAGE_EVENT_OTHER",
        "SPELL_HEAL_BY_SELF","SPELL_HEAL_BY_OTHER","AURA_CAST_ON_SELF","AURA_CAST_ON_OTHER","UNIT_DIED",
        "DAMAGE_SHIELD_SELF","DAMAGE_SHIELD_OTHER","SPELL_DISPEL_BY_SELF","SPELL_DISPEL_BY_OTHER",
        "DEBUFF_ADDED_SELF","DEBUFF_ADDED_OTHER"}) do
        local ok,result=pcall(self.eventFrame.RegisterEvent,self.eventFrame,name)
        self.structuredRegistration[name]=ok and result~=false
    end
end
function E:UniqueEnemyForText(name)
    local guid
    for _,unit in ipairs(self:CollectUnits()) do
        if self:Call(UnitName,unit)==name and self:Call(UnitCanAttack,"player",unit) then
            local found=self:GUID(unit)
            if not found or (guid and guid~=found) then return end
            guid=found
        end
    end
    return guid
end
function E:RecordLocalText(message)
    if self.journal then self.journal:CaptureText(message) end
    if self.localBackend or self.demo then return end
    local actor,victim,amount,spell,school=self:ParseDamage(message)
    if not actor then
        actor,victim,amount,spell=self:ParseHeal(message)
        local healer=actor and self:MemberForName(actor)
        local target=victim and self:MemberForName(victim)
        if healer and target and healer.guid and target.guid then
            self:RecordThreatHeal(healer.guid,target.guid,amount,nil,self:RuleForText(healer,spell))
        end
        -- Successful Feign Death can still be resisted by individual creatures.
        -- Invalidate local estimates instead of pretending all enemies reset.
        local pattern=self:CompileFormat(AURAADDEDSELFHELPFUL)
        if pattern then
            local _,_,buff=string.find(message,pattern)
            local rule=self:RuleForText(self:Member(self.playerKey),buff)
            if rule and rule.kind=="invalidate" then self:RuleFailure(self:Member(self.playerKey),rule.reason or "temporary-reset",nil,buff) end
        end
        return
    end
    local member=actor and self:MemberForName(actor)
    if not member or not member.guid or not victim or not amount then return end
    local guid=self:UniqueEnemyForText(victim)
    if not guid then
        for _,unit in ipairs(self:CollectUnits()) do
            if self:Call(UnitName,unit)==victim and self.ledger then self.ledger[self:GUID(unit) or ""]=nil end
        end
        self:ThreatDiagnostics("ambiguous-text"); return
    end
    local rule=self:RuleForText(member,spell)
    if not rule and spell then rule={spell=true} end
    if not spell and not school then school="physical" end
    self:RecordThreatEvent("damage",member.guid,guid,amount,nil,school,rule)
end
function E:ApplyLocalThreat(enemy)
    if not self.db.localThreat or not enemy.combat or not enemy.owner or not enemy.guid then return end
    local data=self.ledger and self.ledger[enemy.guid]
    -- These are accumulated totals, not short-lived observations. Pausing
    -- attacks must not discard the baseline while this enemy still fights.
    if not data then return end
    local owner=enemy.owner.guid or (self:Member(enemy.owner.key) and self:Member(enemy.owner.key).guid)
    local ownerMember=self:MemberForGUID(owner)
    local base,remote=self:PeerAmount(enemy.guid,ownerMember)
    if not remote then base=owner and data.values[owner] end
    if not base or base<=0 or (not remote and (data.uncertain[owner] or (self.blockedActors and self.blockedActors[owner]))) then return end
    for _,member in ipairs(self.roster) do
        local amount,shared,receivedAt=self:PeerAmount(enemy.guid,member)
        if not shared then amount=member.guid and data.values[member.guid] end
        if member.alive and member.connected and amount and (shared or (not data.uncertain[member.guid] and not (self.blockedActors and self.blockedActors[member.guid]))) and not enemy.samples[member.key] then
            local threshold,rangeSource=self:PullThreshold(enemy,member)
            enemy.samples[member.key]={pct=self:Clamp(member.guid==owner and 100 or amount/base/threshold*100,0,100),
                amount=amount,quality="estimate",shared=shared,at=receivedAt or data.updated,
                threshold=threshold,rangeSource=rangeSource}
            enemy.source=enemy.source or (data.source or "local"); enemy.sourceAt=enemy.sourceAt or data.updated
        end
    end
end
function E:PruneThreatSources()
    for guid,at in pairs(self.enemySeenIdle or {}) do if GetTime()-at>15 then self.enemySeenIdle[guid]=nil end end
    for guid,data in pairs(self.ledger or {}) do
        if self:Exists(guid) then
            if self:Call(UnitIsDeadOrGhost,guid) or not self:Call(UnitAffectingCombat,guid) then
                self.ledger[guid]=nil
            else data.seenCombat=GetTime() end
        elseif GetTime()-(data.seenCombat or data.updated)>30 then
            -- Bound memory for enemies we can no longer observe. This does
            -- not mean that their threat fell to zero.
            self.ledger[guid]=nil
        end
    end
    for guid,data in pairs(self.serverSnapshots or {}) do
        if GetTime()-data.at>1.5 then self.serverSnapshots[guid]=nil end
    end
end

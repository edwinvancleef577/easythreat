local E=EasyThreat
-- Presentation memory never feeds the ledger, peer messages or recorded samples.
-- Values remain tied to one enemy, actor and numerical source, and clear at reset.
function E:DisplayQuantities(enemy)
    local values,source,data=self:ThreatQuantities(enemy)
    local key=enemy.guid or enemy.key
    self.displayQuantities=self.displayQuantities or {}
    for id,old in pairs(self.displayQuantities) do if GetTime()-old.at>180 then self.displayQuantities[id]=nil end end
    local memory=key and self.displayQuantities[key]
    local ledger=enemy.guid and self.ledger and self.ledger[enemy.guid]
    if memory and ((ledger and memory.ledger~=ledger) or GetTime()-memory.at>180) then memory=nil end
    if source and (not memory or memory.source~=source) then memory=nil end
    if not memory then memory={source=source,data=data,ledger=ledger,values={}} end
    memory.at=GetTime()
    local result={}
    for key,entry in pairs(values or {}) do
        memory.values[key]={amount=entry.amount,quality=entry.quality,guid=entry.member.guid,at=GetTime()}
        result[key]=entry
    end
    for key,old in pairs(memory.values) do
        local member=self:Member(key)
        if not result[key] and member and member.alive and member.connected and member.guid==old.guid then
            result[key]={amount=old.amount,quality=old.quality,member=member,held=true,at=old.at}
        end
    end
    if key then self.displayQuantities[key]=memory end
    if next(result) then return result,source or memory.source,data or memory.data end
end
function E:RoleBarColor(enemy,member,pct)
    local owner=enemy.owner
    if self.db.alwaysPlayerColors or member.key~=self.playerKey then
        return self:IdentityColor(member)
    end
    if self:IsTank(member.key) then
        if owner and owner.key~=member.key then return self.colors.red end
        if owner then return self.colors.green end
    elseif owner and owner.key==member.key then return self.colors.red end
    return self:RiskColor(pct or 0)
end
function E:TargetCombatModels(enemy)
    local own=self:Member(self.playerKey)
    if not own or not own.alive or not own.connected then return end
    local values,source,data=self:DisplayQuantities(enemy)
    values=values or {}
    local view=self:ThreatViewState(enemy,values,source,data)
    self.targetHistory=self.targetHistory or {}
    for id,old in pairs(self.targetHistory) do if GetTime()-old.at>180 then self.targetHistory[id]=nil end end
    local key=enemy.guid or enemy.key
    local history=self.targetHistory[key]
    local ledger=enemy.guid and self.ledger and self.ledger[enemy.guid]
    if not history or (ledger and history.ledger~=ledger) or (source and history.source~=source) or GetTime()-history.at>180 then
        history={ledger=ledger,source=source,actors={}}; self.targetHistory[key]=history
    end
    history.at=GetTime()
    local function actor(member,thin)
        if not member or not member.alive or not member.connected then return end
        local entry=values[member.key]
        local sample=enemy.samples and enemy.samples[member.key]
        local heldRisk=not sample and history.actors[member.guid or member.key]
        local last=history.actors[member.guid or member.key]
        local model=E:ActorBarModel(enemy,member) or {pct=0,text="",unknown=true,color=E.colors.neutral}
        model.riskKnown=model.aggro or (sample and E:Finite(sample.pct)) or (heldRisk and heldRisk.riskKnown)
        if heldRisk and not model.aggro then model.pct=heldRisk.pct end
        model.actor=member; model.fixedStack=true; model.rankStack=true; model.riskStack=true; model.phase=view.phase
        model.fleeing=enemy.fleeing or false
        model.stackIdentity=key..":"..(own.guid or own.key)..":fixed"
        model.identity=key..":"..(member.guid or member.key)..":"..(source or "percent")..":"..view.phase
        model.pressure=nil
        local risk,riskSource,threshold=E:PullRisk(enemy,member,values,source)
        model.riskSource=riskSource; model.pullThreshold=threshold
        if entry and source then
            model.amount=entry.amount; model.quantitySource=source
        end
        if view.building and view.builder==(member.guid or member.key) and entry then
            model.fillPct=E:Clamp(entry.amount/view.scale*100,0,100); model.scaleMax=view.scale
            model.sharedScale=true; model.unknown=nil; model.held=entry.held; model.observedAt=entry.at
        elseif risk~=nil then
            model.fillPct=risk; model.pct=risk; model.riskKnown=true; model.unknown=nil
            model.observedAt=sample and sample.at
        elseif last and last.phase==view.phase then
            model.fillPct=last.fillPct; model.pct=last.pct; model.unknown=last.unknown
            model.held=true; model.observedAt=last.at
        else model.fillPct=0; model.unknown=true end
        if not model.held and (not model.unknown or model.riskKnown) then
            history.actors[member.guid or member.key]={fillPct=model.fillPct or model.pct,pct=model.pct,
                unknown=model.unknown,riskKnown=model.riskKnown,at=GetTime(),phase=view.phase}
        end
        model.color=E:RoleBarColor(enemy,member,model.pct)
        if not model.held and history.actors[member.guid or member.key] then history.actors[member.guid or member.key].color=model.color end
        model.borderColor=model.aggro and (E:IsTank(member.key) and E.colors.green or E.colors.red) or nil
        if enemy.fleeing then
            model.text=thin and member.name or E:L("Fleeing!")
            if member.key==E.playerKey and not E.db.alwaysPlayerColors then model.color=E.colors.neutral end
        elseif view.building and view.builder==(member.guid or member.key) and entry then
            model.building=true
            model.color=(E.db.alwaysPlayerColors or member.key~=E.playerKey) and E:IdentityColor(member) or E.colors.build
            model.buildAmount=string.format("%.0f",entry.amount)
            model.text=(thin and member.name or E:L("Build-up"))..": "..model.buildAmount
            model.whiteText=true
        elseif thin then model.text=member.name
        elseif model.aggro then model.text=E:L(E:IsTank(member.key) and "AGGRO" or "You have aggro")
        elseif E:IsTank(member.key) and enemy.owner then model.text=E:L("Aggro lost")
        elseif model.unknown then model.text=""
        elseif model.held then model.text=E:L("Last value")
        else model.text="" end
        return model
    end
    local petMember=self:Member(self.playerKey..":pet")
    local pet=actor(petMember,true)
    if pet then pet.pet=true end
    local choices={}
    for _,member in ipairs(self.roster) do
        if member.key~=own.key and member.alive and member.connected and (not petMember or member.key~=petMember.key) then
            local entry=values[member.key]
            local amount=entry and entry.amount or 0
            local holder=enemy.owner and enemy.owner.key==member.key
            if amount>0 or holder or self:IsTank(member.key) or view.participants[member.guid or member.key] then
                table.insert(choices,{member=member,amount=amount,holder=holder})
            end
        end
    end
    table.sort(choices,function(a,b)
        if a.amount~=b.amount then return a.amount>b.amount end
        if not not a.holder~=not not b.holder then return a.holder and true or false end
        return a.member.key<b.member.key
    end)
    local main=actor(own)
    main.references={}
    for i=1,math.min(table.getn(choices),self.db.otherBars or 1) do
        local other=actor(choices[i].member,true)
        other.comparison=true; table.insert(main.references,other)
    end
    main.reference=main.references[1]
    return main,pet
end

-- Comparable threat quantities drive bar length; pull-risk percentages only
-- drive warnings. Never mix damage, scaled pull risk, and absolute threat.
local E=EasyThreat
function E:RecordOpeningThreat(data,member,gain)
    if not data.startKnown or not self:Finite(gain) or gain<=0 or data.values[member.guid]~=nil then return end
    data.openers=data.openers or {}
    if data.openers[member.guid] then return end
    self.openingThreat=self.openingThreat or {}
    if not data.viewReference then
        local best=0
        for _,actor in ipairs(self.roster) do
            local prior=actor.guid and self.openingThreat[actor.guid]
            if actor.alive and actor.connected and prior and GetTime()-prior.at<1800 and prior.level==actor.level then
                best=math.max(best,prior.amount)
            end
        end
        data.viewReference=best>0 and best or gain*3
        data.viewReferenceSource=best>0 and "previous-opener" or "own-opener-times-three"
    end
    data.openers[member.guid]=gain
    self.openingThreat[member.guid]={amount=gain,at=GetTime(),level=member.level}
end
function E:ThreatQuantities(enemy)
    local cohorts={api={},context={},relative={},localValues={}}
    for _,member in ipairs(self.roster) do
        local sample=enemy.samples and enemy.samples[member.key]
        if member.alive and member.connected and sample then
            if (sample.quality=="api" or sample.quality=="context") and self:Finite(sample.amount) and sample.amount>=0 then
                cohorts[sample.quality][member.key]={amount=sample.amount,quality=sample.quality,member=member}
            end
            if sample.quality=="api" and self:Finite(sample.raw) and sample.raw>=0 then
                cohorts.relative[member.key]={amount=sample.raw,quality="api",member=member}
            end
        end
    end
    -- A higher-quality cohort must never be completed with estimated amounts:
    -- even absolute APIs and local models may use different numeric units.
    if next(cohorts.api) then return cohorts.api,"api" end
    if next(cohorts.context) then return cohorts.context,"context" end
    if next(cohorts.relative) then
        local owner=enemy.owner
        if owner and enemy.ownerQuality=="api" and self:Member(owner.key) and not cohorts.relative[owner.key] then
            cohorts.relative[owner.key]={amount=100,quality="api",member=owner}
        end
        return cohorts.relative,"relative"
    end
    if not self.db.localThreat or not enemy.guid then return end
    local data=self.ledger and self.ledger[enemy.guid]
    if not data then return end
    for _,member in ipairs(self.roster) do
        if member.alive and member.connected and member.guid then
            local amount,shared=self:PeerAmount(enemy.guid,member)
            if not shared then
                amount=data.values[member.guid]
                if data.uncertain[member.guid] or (self.blockedActors and self.blockedActors[member.guid]) then amount=nil end
            end
            if self:Finite(amount) and amount>=0 then
                cohorts.localValues[member.key]={amount=amount,quality="estimate",member=member,shared=shared}
            end
        end
    end
    if next(cohorts.localValues) then return cohorts.localValues,"local",data end
end
function E:ThreatViewState(enemy,values,source,data)
    self.threatViews=self.threatViews or {}
    local key=enemy.guid or enemy.key
    local ledger=enemy.guid and self.ledger and self.ledger[enemy.guid]
    local view=self.threatViews[key]
    if not view then
        local idle=self.enemySeenIdle and self.enemySeenIdle[key]
        view={participants={},startKnown=(ledger and ledger.startKnown) or (idle and GetTime()-idle<15) or false}
        self.threatViews[key]=view
    end
    if not view.engaged and ledger and ledger.startKnown then view.startKnown=true end
    view.ledger=ledger; view.at=GetTime()
    -- A change of numeric provider may change units, but never restarts phase.
    if view.source~=source then view.source=source; view.reference=nil end
    local maximum=0
    for key,entry in pairs(values or {}) do
        maximum=math.max(maximum,entry.amount)
        if entry.amount>0 then view.participants[entry.member.guid or key]=true end
    end
    for key,sample in pairs(enemy.samples or {}) do
        local member=self:Member(key)
        if member and sample.amount==nil and sample.raw==nil and self:Finite(sample.pct) and sample.pct>0 then
            view.participants[member.guid or key]=true
        end
    end
    for guid in pairs(ledger and ledger.threatActors or {}) do view.participants[guid]=true end
    -- Legacy uncertainty flags still prove a relevant, unquantified action.
    for guid in pairs(ledger and ledger.involved or {}) do
        if (ledger.uncertain[guid] or (self.blockedActors and self.blockedActors[guid])) and self:MemberForGUID(guid) then
            view.participants[guid]=true
        end
    end
    local count,sole=0
    for id in pairs(view.participants) do count=count+1; sole=id end
    if count>1 or (count>0 and not view.startKnown) then view.engaged=true end
    view.building=not view.engaged and count==1 and source~="relative" and source~=nil
    view.builder=view.building and sole or nil
    if view.building and not view.reference and maximum>0 then
        view.reference=source=="local" and data and data.viewReference and data.viewReference*3 or maximum*9
    end
    view.scale=view.building and math.max(1,view.reference or maximum) or (maximum>0 and maximum or 1)
    view.phase=view.building and "build" or "ranking"
    for id,old in pairs(self.threatViews) do if GetTime()-old.at>180 then self.threatViews[id]=nil end end
    return view
end
function E:ComparisonModels(enemy,force,output)
    if not enemy.combat or enemy.stale then return end
    if force then return self:TargetCombatModels(enemy) end
    local threshold,key=self:OptionalThreshold(enemy,output)
    local main,pet=self:TooltipCombatModels(enemy,threshold,key)
    return main,pet,true
end
function E:TankBuildingInList(enemy,member)
    if not member or not self:IsTank(member.key) then return false end
    local values,source,data=self:ThreatQuantities(enemy)
    local view=self:ThreatViewState(enemy,values,source,data)
    return view.building and view.builder==member.guid or false
end
function E:ListThreatEntries(enemy)
    if not enemy.combat then return end
    local values=self:ThreatQuantities(enemy)
    if not values then return end
    -- Without the holder's amount its numerical rank is unknown. Use the
    -- state-first layout instead of silently dropping its AGGRO cell.
    if enemy.owner and (not values[enemy.owner.key] or values[enemy.owner.key].amount<=0) then return end
    local result={}
    for key,entry in pairs(values) do
        local sample=enemy.samples[key]
        local owner=enemy.owner and enemy.owner.key==key
        if entry.amount>0 and (owner or self:IsTank(key) or (sample and sample.pct and sample.pct>=self.db.threshold)) then
            table.insert(result,{member=entry.member,amount=entry.amount,pct=sample and sample.pct,
                quality=owner and enemy.ownerQuality or entry.quality,owner=owner})
        end
    end
    local function order(a,b)
        if a.amount~=b.amount then return a.amount>b.amount end
        if not not a.owner~=not not b.owner then return a.owner and true or false end
        return a.member.key<b.member.key
    end
    table.sort(result,order)
    -- Keep the actual holder visible even when several actors already have
    -- more raw threat but have not taken the enemy away yet.
    local limit=self.db.maxCandidates+1
    for i=limit+1,table.getn(result) do
        if result[i].owner then
            local holder=table.remove(result,i); table.insert(result,limit,holder)
            local head={}; for j=1,limit do head[j]=result[j] end
            table.sort(head,order); for j=1,limit do result[j]=head[j] end
            break
        end
    end
    if table.getn(result)>0 then return result end
end

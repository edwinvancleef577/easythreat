-- Visibility belongs to the local role and output, never to a class. Keep
-- missing calculations separate from the decision to display a combat state.
local E=EasyThreat
function E:OptionalThreshold(enemy,output)
    if self.visibilityThreshold~=self.db.threshold then
        self.visibilityThreshold=self.db.threshold; self.pairVisibility={}; self.visibility={}
    end
    self.pairVisibility=self.pairVisibility or {}
    local key=output and (output..":"..enemy.key) or enemy.key
    return self.db.threshold-(self.pairVisibility[key] and self.db.hysteresis or 0),key
end
function E:VisibilityEnemyKey(key)
    if string.sub(key,1,8)=="tooltip:" then return string.sub(key,9) end
    if string.sub(key,1,9)=="overhead:" then return string.sub(key,10) end
    return key
end
function E:MissingDisplayReason(enemy)
    local data=enemy.guid and self.ledger and self.ledger[enemy.guid]
    for _,member in ipairs(self.roster) do
        if member.key==self.playerKey or member.owner==self.playerKey or self:IsTank(member.key) then
            local guid=member.guid
            if guid and data and data.involved[guid] and
                (data.uncertain[guid] or (self.blockedActors and self.blockedActors[guid])) then return "withheld" end
        end
    end
    return "source"
end
function E:EmptyActorModel(enemy,member)
    if not member or not member.alive or not member.connected then return end
    return {pct=0,fillPct=0,unknown=true,text=member.pet and member.name or "",actor=member,
        pet=member.pet,color=self.colors.neutral,identity=enemy.key..":"..(member.guid or member.key)}
end
function E:OptionalActorModel(enemy,member)
    if not member or not member.alive or not member.connected then return end
    local result=self:ActorBarModel(enemy,member)
    local sample=enemy.samples and enemy.samples[member.key]
    local key=(enemy.guid or enemy.key)..":"..(member.guid or member.key)
    self.optionalActorCache=self.optionalActorCache or {}
    for id,value in pairs(self.optionalActorCache) do if GetTime()-value.at>180 then self.optionalActorCache[id]=nil end end
    if result and sample and self:Finite(sample.pct) then
        self.optionalActorCache[key]={pct=sample.pct,quality=sample.quality,at=sample.at or GetTime()}
    elseif not result and self.optionalActorCache[key] then
        local old=self.optionalActorCache[key]
        result={pct=old.pct,text=member.pet and member.name or self:L("Last value"),
            quality=old.quality,held=true,observedAt=old.at,actor=member,
            color=self:RoleBarColor(enemy,member,old.pct),identity=key}
    end
    return result
end
function E:OptionalModelReason(main,pet)
    if main and (main.held or (pet and pet.held)) then return "held" end
    for _,other in ipairs(main and main.references or {}) do if other.held then return "held" end end
    return main and "visible" or "threshold"
end
function E:EmptyTooltipModels(enemy,idle)
    local own=self:Member(self.playerKey)
    local main=self:EmptyActorModel(enemy,own)
    if not main then return end
    local key=enemy.guid or enemy.key
    -- Presentation caches must not revive the previous fight after an idle bar.
    if self.targetHistory then self.targetHistory[key]=nil end
    if self.displayQuantities then self.displayQuantities[key]=nil end
    if self.threatViews then self.threatViews[key]=nil end
    main.fixedStack=true; main.rankStack=true; main.phase="idle"; main.stackIdentity=key..":"..(own.guid or own.key)..":fixed"
    -- An idle hint is not a measured zero. Never show it just because the
    -- combat model is stale or a live threat source has gone missing.
    if idle then main.text=self:L("No aggro"); main.subtleText=true end
    local petMember=self:Member(self.playerKey..":pet")
    local pet=self:EmptyActorModel(enemy,petMember)
    local tanks={}
    for _,member in ipairs(self.roster) do
        if member.key~=own.key and (not pet or member.key~=pet.actor.key) and member.alive and member.connected and
            self:IsTank(member.key) then table.insert(tanks,member) end
    end
    table.sort(tanks,function(a,b) return a.key<b.key end)
    main.references={}
    for i=1,math.min(table.getn(tanks),self.db.otherBars or 1) do
        local other=self:EmptyActorModel(enemy,tanks[i]); other.text=tanks[i].name; other.comparison=true
        table.insert(main.references,other)
    end
    main.reference=main.references[1]
    return main,pet
end
function E:TooltipCombatModels(enemy,threshold,key)
    -- Exactly the target frame's perspective and scale: self, pet, comparison.
    -- Only eligibility differs: the tooltip still respects its enemy filters
    -- and configured threshold. A role or data source never reorders the rows.
    local main,pet=self:TargetCombatModels(enemy)
    if not main then return nil,nil,"no-player" end
    local sample=enemy.samples and enemy.samples[self.playerKey]
    local risk=sample and self:Finite(sample.pct) and sample.pct or
        (main.held and main.riskKnown and main.pct)
    local petSample=pet and enemy.samples and enemy.samples[pet.actor.key]
    local petRisk=petSample and self:Finite(petSample.pct) and petSample.pct or
        (pet and pet.held and pet.riskKnown and pet.pct)
    local reference=main.reference
    local building=not risk and ((main.amount and main.amount>0) or
        (main.unknown and reference and (reference.aggro or (reference.amount and reference.amount>0))))
    local active=main.aggro or (pet and pet.aggro) or building or
        (self:IsTank(self.playerKey) and enemy.owner) or
        (self:IsTank(self.playerKey) and reference and
            ((reference.amount or 0)>0 or reference.pct>0)) or
        (risk and risk>=threshold) or (petRisk and petRisk>=threshold)
    if not active then
        self.pairVisibility[key]=nil
        return nil,nil,(risk or petRisk) and "threshold" or self:MissingDisplayReason(enemy)
    end
    self.pairVisibility[key]=true
    return main,pet,self:OptionalModelReason(main,pet)
end
function E:OptionalModels(enemy,output)
    if not self.db.enabled or (output and not self:OutputEnabled(output)) then return nil,nil,"disabled" end
    if not enemy then return nil,nil,"source" end
    local threshold,key=self:OptionalThreshold(enemy,output)
    local allowed,filter=self:EnemyAllowed(enemy,output)
    if not allowed then self.pairVisibility[key]=nil; return nil,nil,"filter",filter end
    local me=self:Member(self.playerKey)
    if not me or not me.alive or not me.connected then self.pairVisibility[key]=nil; return nil,nil,"no-player" end
    if output=="tooltip" and self.db.tooltipAlways and not enemy.dead then
        self.pairVisibility[key]=nil
        -- Query the current unit flag, not a cached participation grace period.
        -- This also clears immediately while fighting a different enemy.
        local fighting=enemy.combat
        if enemy.unit then fighting=self:Call(UnitAffectingCombat,enemy.unit) end
        if not fighting or enemy.stale then
            local main,pet=self:EmptyTooltipModels(enemy,not fighting)
            return main,pet,"empty-idle"
        end
        local main,pet=self:TargetCombatModels(enemy)
        return main,pet,self:OptionalModelReason(main,pet)
    end
    if enemy.dead or enemy.stale or not enemy.combat then self.pairVisibility[key]=nil; return nil,nil,"combat" end
    return self:TooltipCombatModels(enemy,threshold,key)
end
function E:RememberDisplay(output,reason,enemy,filter)
    self.displayStates=self.displayStates or {}
    self.displayStates[output]={reason=reason,filter=filter,guid=enemy and enemy.guid,at=GetTime()}
end
function E:DisplayReasonText(reason,filter)
    local keys={visible="Visible",["combat-target"]="Visible",disabled="Disabled for your role",held="Last value",
        ["addon-disabled"]="Addon disabled. Enable EasyThreat in Displays.",
        combat="No combat detected. Test while you or your pet are fighting.",
        threshold="Threat below %d%%. Lower the threshold or use Positions > Preview.",
        source="No usable threat data. Target this enemy and check the sources below.",
        withheld="Threat calculation incomplete; see class warnings. The display is enabled.",
        ["no-player"]="Your character is dead, offline or not available.",
        ["no-target-data"]="Select a living enemy.",dead="Select a living enemy.",
        plate="No matching nameplate. Enable enemy nameplates to show this bar.",
        empty="No enemies pass the current filters.",["empty-idle"]="Empty bars outside combat",preview="Demo values",
        hidden="No enemy tooltip recorded. Hover an enemy during combat.",
        identity="Tooltip unit unresolved. Try the standard tooltip or reload the UI."}
    if reason=="filter" then
        if filter=="context" then return self:L("%s display disabled in Enemy filters.",self:L(self:GroupContext()=="solo" and "Solo" or self:GroupContext()=="raid" and "Raid" or "Party")) end
        return self:L("Hidden by enemy filter: %s",self:L(filter=="level" and "Enemy level" or filter=="kind" and "Enemy type" or "Raid list: marked enemies only"))
    end
    return self:L(keys[reason] or keys.source,self.db.threshold)
end
function E:DisplayStatusLines(add)
    local outputs={{"target","Target frame"},{"tooltip","Mouse tooltip"},{"overhead","Nameplates"},{"list","Enemy list"}}
    for _,row in ipairs(outputs) do
        local output,label=row[1],row[2]
        local state=self.displayStates and self.displayStates[output]
        local reason=state and state.reason or (output=="tooltip" and "hidden" or "no-target-data")
        local filter=state and state.filter
        if output=="tooltip" and not state and self.tooltipDiagnostic then reason=self.tooltipDiagnostic.reason; filter=self.tooltipDiagnostic.filter end
        if not self.db.enabled then reason="addon-disabled"
        elseif not self:OutputEnabled(output) then reason="disabled" end
        add("%s: %s",self:L(label),self:DisplayReasonText(reason,filter),reason=="withheld" and "warning" or "info")
    end
end

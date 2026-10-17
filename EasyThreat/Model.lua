local E = EasyThreat
-- Only scalar presentation fields: safe to retain for diagnostics without
-- keeping enemy/member tables alive or copying names into recording output.
function E:DisplayModel(model)
    if not model then return false end
    return {pct=(model.riskKnown or not model.unknown) and model.pct or nil,unknown=model.unknown or false,
        aggro=model.aggro or false,quality=model.quality,pet=model.pet or false,
        amount=model.amount,fillPct=model.fillPct,scaleMax=model.scaleMax,
        quantitySource=model.quantitySource,riskSource=model.riskSource,pullThreshold=model.pullThreshold,
        phase=model.phase,building=model.building or false,held=model.held or false,observedAt=model.observedAt,fleeing=model.fleeing or false,
        actor=model.actor and model.actor.guid}
end
function E:IsApproximate(quality) return quality=="estimate" or quality=="observed" or quality=="context" end
-- Six equal bands from green to orange. Actual unwanted aggro jumps to red.
E.riskColors={E.colors.green,{.48,.79,.27},{.73,.81,.20},
    {.94,.77,.22},{1,.61,.16},{1,.43,.12}}
function E:RiskColor(pct)
    local threshold=self.db and self.db.threshold or self.defaults.threshold
    local band=math.floor((pct-threshold)/math.max(1,100-threshold)*6)+1
    return self.riskColors[self:Clamp(band,1,6)]
end
function E:OwnerState(enemy)
    if not enemy.combat or not enemy.owner then return "unknown" end
    if self:IsTank(enemy.owner.key) then return "good" end
    return "bad"
end
function E:Candidates(enemy, threshold)
    local result = {}
    for key, sample in pairs(enemy.samples or {}) do
        local member = self:Member(key)
        if member and member.alive and member.connected and sample.pct and
            sample.pct >= (threshold or self.db.threshold) and not self:IsTank(key) and
            (not enemy.owner or key ~= enemy.owner.key) then
            table.insert(result, {member=member, pct=sample.pct, quality=sample.quality})
        end
    end
    table.sort(result, function(a,b)
        if a.pct ~= b.pct then return a.pct > b.pct end
        return a.member.key < b.member.key
    end)
    return result
end
function E:OverheadModel(enemy)
    if not enemy.combat or enemy.stale then return nil end
    local result
    if self:ViewMode() == "personal" then
        if enemy.owner and enemy.owner.key == self.playerKey then
            local good = self:IsTank(self.playerKey)
            result = {pct=100, text=self:L("AGGRO"), color=good and self.colors.green or self.colors.red,
                aggro=true, quality=enemy.ownerQuality}
        else
            local sample = enemy.samples[self.playerKey]
            if sample and sample.pct then
                result = {pct=sample.pct, color=self:RiskColor(sample.pct), quality=sample.quality}
            end
        end
    else
        local state = self:OwnerState(enemy)
        if state == "bad" then
            result = {pct=100, text=self:L("AGGRO"), color=self.colors.red, aggro=true, quality=enemy.ownerQuality}
        else
            local candidates = self:Candidates(enemy, self.db.threshold-self.db.hysteresis)
            local candidate = candidates[1]
            if candidate then
                result = {pct=candidate.pct, color=self:RiskColor(candidate.pct), quality=candidate.quality}
            elseif state=="good" then
                result = {pct=100,text=self:L("AGGRO"),color=self.colors.green,aggro=true,quality=enemy.ownerQuality}
            end
        end
    end
    self.visibility = self.visibility or {}
    local wasVisible = self.visibility[enemy.key]
    local threshold = self.db.threshold - (wasVisible and self.db.hysteresis or 0)
    if not result or (not result.aggro and result.pct < threshold) then
        self.visibility[enemy.key] = nil
        return nil
    end
    self.visibility[enemy.key] = true
    if not result.text then result.text = string.format("%d%%", math.floor(result.pct + 0.5)) end
    -- AGGRO is a state label. Keep provenance in the model and detail tooltip;
    -- numerical estimates still carry ~ even when the apparent lead is large.
    if not result.aggro and self:IsApproximate(result.quality) then result.text = "~" .. result.text end
    result.identity=enemy.key..":"..(self:ViewMode()=="personal" and self.playerKey or "tank")
    if enemy.fleeing then result.text=self:L("Fleeing!"); result.color=self.colors.neutral; result.fleeing=true end
    return self:DecorateOwnerModel(result,enemy)
end
function E:ActorBarModel(enemy,member)
    if not member or not member.alive or not member.connected then return end
    local result
    if enemy.owner and enemy.owner.key==member.key then
        result={pct=100,text=self:L("AGGRO"),aggro=true,quality=enemy.ownerQuality,
            color=self:IsTank(member.key) and self.colors.green or self.colors.red}
    else
        local sample=enemy.samples[member.key]
        if sample and self:Finite(sample.pct) then
            result={pct=sample.pct,color=self:RiskColor(sample.pct),quality=sample.quality}
        end
    end
    if not result then return end
    result.identity=(enemy.key or enemy.guid or "")..":"..(member.guid or member.key)
    result.text=result.text or string.format("%d%%",math.floor(result.pct+0.5))
    if not result.aggro and self:IsApproximate(result.quality) then result.text="~"..result.text end
    if member.pet then result.text=member.name end
    if enemy.fleeing and member.key==self.playerKey then result.text=self:L("Fleeing!"); result.color=self.colors.neutral; result.fleeing=true end
    return self:DecorateOwnerModel(result,enemy)
end
function E:CompactModels(enemy,output) return self:OptionalModels(enemy,output) end
-- Participation is independent of whether a class rule can calculate threat.
function E:NoteParticipation(actor,guid)
    local member=self:MemberForGUID(actor)
    if not guid or not member or (member.key~=self.playerKey and member.owner~=self.playerKey) then return end
    self.participation=self.participation or {}
    local now=GetTime()
    if now>=(self.participationCleanup or 0) then
        for key,at in pairs(self.participation) do if now-at>180 then self.participation[key]=nil end end
        self.participationCleanup=now+30
    end
    self.participation[guid]=now
end
function E:TargetModels(enemy)
    if not self.db.enabled or not self:OutputEnabled("target") then return nil,nil,"disabled" end
    local unit=self:ResolveEnemyUnit(enemy)
    if enemy.dead or self:Call(UnitIsDeadOrGhost,unit) then return nil,nil,"dead" end
    -- The role's target switch remains authoritative. Enemy filters and the
    -- threshold govern the other outputs, not the always-on combat target.
    if not enemy.stale and (enemy.combat or self:AnyCombat()) then
        local own,pet=self:TargetCombatModels(enemy)
        return own,pet,own and "combat-target" or "no-player"
    end
    return nil,nil,"combat"
end
function E:TooltipModels(enemy) return self:OptionalModels(enemy,"tooltip") end
function E:TankFallbackModels(enemy,output)
    local owner=enemy.owner
    local main={pct=owner and 100 or 0,unknown=not owner,aggro=owner~=nil,
        identity=enemy.key..":owner:"..(owner and owner.key or ""),quality=enemy.ownerQuality,
        color=owner and (self:IsTank(owner.key) and self.colors.green or self.colors.red) or self.colors.neutral,
        text=owner and ((owner.key==self.playerKey and output~="tooltip" and "" or self:ShortName(owner.name,14).."  ")..self:L("AGGRO")) or ""}
    local challenger=self:Candidates(enemy)[1]
    local other
    if challenger then
        other=self:ActorBarModel(enemy,challenger.member)
        other.text=self:ShortName(challenger.member.name,14).."  "..other.text
        other.actor=challenger.member
    end
    if not owner then return other end
    main.actor=owner
    return self:DecorateOwnerModel(main,enemy),other
end
function E:SortedEnemies(output)
    local result = {}
    for _, enemy in pairs(self.enemies) do
        if not (output=="list" and self.dismissedEnemies and self.dismissedEnemies[enemy.key]) and self:EnemyAllowed(enemy,output) then
            enemy.candidates = self:Candidates(enemy)
            local score = enemy.candidates[1] and enemy.candidates[1].pct or 0
            if self:OwnerState(enemy) == "bad" then score = 200 end
            enemy.score = score
            table.insert(result, enemy)
        end
    end
    table.sort(result, function(a,b)
        if not not a.stale ~= not not b.stale then return not a.stale end
        if a.score ~= b.score then return a.score > b.score end
        if a.mark ~= b.mark then return (a.mark or 0) > (b.mark or 0) end
        if a.name ~= b.name then return a.name < b.name end
        return a.key < b.key
    end)
    return result
end
-- A thin competitor marker complements AGGRO without changing its meaning.
-- Only sampled competitors participate; no invented countdown or future cast.
function E:DecorateOwnerModel(model,enemy)
    if not self.db.pressureMarker or not model or not model.aggro or not enemy.owner or not (enemy.key or enemy.guid) then return model end
    local candidate
    local ownerTank=self:IsTank(enemy.owner.key)
    for key,sample in pairs(enemy.samples or {}) do
        local member=self:Member(key)
        if key~=enemy.owner.key and member and member.alive and member.connected and
            self:Finite(sample.pct) and sample.pct>0 and (not ownerTank or not self:IsTank(key)) and
            (not sample.at or GetTime()-sample.at<=1.5) then
            if not candidate or sample.pct>candidate.pct then candidate={pct=sample.pct,member=member,quality=sample.quality} end
        end
    end
    if not candidate then return model end
    self.pressureHistory=self.pressureHistory or {}
    local key=(enemy.key or enemy.guid)..":"..enemy.owner.key..":"..candidate.member.key
    local previous=self.pressureHistory[key]; local now=GetTime()
    if not previous or now-previous.at>2 or previous.quality~=candidate.quality then previous={at=now,pct=candidate.pct,slope=0,quality=candidate.quality}; self.pressureHistory[key]=previous
    elseif now-previous.at>=.5 then
        previous.slope=previous.slope*.5+(candidate.pct-previous.pct)/(now-previous.at)*.5
        previous.pct=candidate.pct; previous.at=now
    end
    candidate.direction=previous.slope>2 and 1 or previous.slope< -2 and -1 or 0
    model.pressure=candidate
    for id,p in pairs(self.pressureHistory) do if now-p.at>10 then self.pressureHistory[id]=nil end end
    return model
end

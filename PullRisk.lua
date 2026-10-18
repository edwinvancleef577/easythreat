local E=EasyThreat
-- A native scaled percentage or a server melee flag is preferable to guessing
-- from class, spell range, or the distance to a friendly party member.
function E:PullThreshold(enemy,member)
    if member and member.unit=="player" and
        ((enemy.guid and enemy.guid==self:GUID("target")) or enemy.unit=="target") and
        type(IsAttackAction)=="function" and type(IsActionInRange)=="function" then
        if not self.attackSlotAt or GetTime()-self.attackSlotAt>2 then
            self.attackSlot=nil; self.attackSlotAt=GetTime()
            for slot=1,120 do
                local attack=self:Call(IsAttackAction,slot)
                if attack==true or attack==1 then self.attackSlot=slot; break end
            end
        end
        local attack=self.attackSlot and self:Call(IsAttackAction,self.attackSlot)
        if attack==true or attack==1 then
            local range=self:Call(IsActionInRange,self.attackSlot)
            if range==1 then return 1.1,"attack-range" end
            if range==0 then return 1.3,"attack-range" end
        end
    end
    -- Unknown is NOT assumed to be ranged. This warns early instead of making
    -- a melee player wait for a false 130% threshold. No DLL is required.
    return 1.1,"conservative"
end
function E:PullRisk(enemy,member,values,source)
    if enemy.owner and enemy.owner.key==member.key then return 100,"holder" end
    local sample=enemy.samples and enemy.samples[member.key]
    if sample and self:Finite(sample.pct) then
        return self:Clamp(sample.pct,0,100),sample.rangeSource or sample.quality,sample.threshold
    end
    local entry=values and values[member.key]
    local base=values and enemy.owner and values[enemy.owner.key]
    if entry and base and base.amount>0 and not entry.held and not base.held then
        local threshold,why=self:PullThreshold(enemy,member)
        return self:Clamp(entry.amount/base.amount/threshold*100,0,100),why,threshold
    end
end

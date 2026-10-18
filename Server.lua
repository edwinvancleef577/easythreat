-- TWT client protocol, independently implemented. See TESTING.md.
-- Unscoped TWT packets never become authoritative: the protocol has no request ID.
local E=EasyThreat
local lifetime=1.5
E.serverRequestLimit=10
-- Session counters survive target switches and combat end. Sending is not
-- receiving, and an accepted packet is still only bound by context (no nonce).
function E:ServerCount(key)
    self.serverMetrics=self.serverMetrics or {}
    self.serverMetrics[key]=(self.serverMetrics[key] or 0)+1
end
function E:Finite(value)
    return type(value)=="number" and value==value and value>=0 and value<1000000000000
end
function E:Split(value,delimiter)
    local out,pos={},1
    while true do
        local stop=string.find(value,delimiter,pos,true)
        table.insert(out,string.sub(value,pos,stop and stop-1 or -1))
        if not stop then return out end
        pos=stop+string.len(delimiter)
    end
end
function E:ThreatDiagnostics(kind,detail)
    self.sourceStats=self.sourceStats or {}
    self.sourceStats[kind]=(self.sourceStats[kind] or 0)+1
    if not self.traceEnabled then return end
    self.db.trace=self.db.trace or {}
    table.insert(self.db.trace,string.format("%.2f %s %s",GetTime(),kind,string.sub(tostring(detail or ""),1,900)))
    while table.getn(self.db.trace)>30 do table.remove(self.db.trace,1) end
end
function E:ResetThreatSources()
    self.displayQuantities={}; self.targetHistory={}; self.fleeingEnemies={}
    self.combatEventWatch=nil; self.participation={}; self.pressureHistory={}; self.threatViews={}
    self.pendingDebuffs={}
    self.blockedActors={}; self.blockedEnemies={}
    self.enemySeenIdle={}; self.peerValues={}; self.peerRequests={}
    self.serverSnapshots={}; self.serverPending=nil
    self.serverWatch=nil; self.serverRejectReason=nil; self.serverSendError=nil
    self.serverChanged=GetTime(); self.serverGeneration=(self.serverGeneration or 0)+1
    self.ledger={}; self.damage={}; self.tooltipSample=nil; self.pairVisibility={}; self.optionalActorCache={}
end
function E:ThreatTargetChanged()
    self.serverPending=nil; self.serverSnapshots={}; self.tooltipSample=nil
    self.serverWatch=nil; self.serverRejectReason=nil; self.serverSendError=nil
    self.serverChanged=GetTime(); self.serverGeneration=(self.serverGeneration or 0)+1
end
-- A failed query target used to collapse into one opaque "target" state.
-- Keep query eligibility unchanged, but expose the observed cause to the test.
function E:ServerTargetStatus()
    if not self:Exists("target") then return "none" end
    local guid=self:GUID("target")
    if not guid then return "guid" end
    if self:Call(UnitIsDeadOrGhost,"target") then return "dead",guid end
    if self:Call(UnitIsPlayer,"target") then return "player",guid end
    if not self:Call(UnitCanAttack,"player","target") then return "friendly",guid end
    if not self:Call(UnitAffectingCombat,"target") then return "idle",guid end
    return "combat",guid
end
function E:ServerQueryState()
    if self.demo or not self.db.enabled then return "disabled" end
    if type(SendAddonMessage)~="function" then return "transport" end
    local now=GetTime()
    local raid=self:Call(GetNumRaidMembers) or 0
    local target,guid=self:ServerTargetStatus()
    if target=="idle" then return "combat" end
    if target~="combat" then return "target" end
    local coordinator=self.ServerCoordinator and self:ServerCoordinator()
    if coordinator and coordinator~=self:GUID("player") then return "coordinated" end
    if now-(self.serverForeignQuery or -10)<lifetime then return "foreign" end
    if now-(self.serverChanged or -10)<lifetime then return "changed" end
    if self.serverPending and now-self.serverPending.at<lifetime then return "pending" end
    if self.serverPending then self:ServerCount("timeouts"); self.serverPending=nil end
    if now-(self.serverLastQuery or -10)<0.5 then return "rate" end
    return "ready",guid,raid>0 and "RAID" or "PARTY"
end
function E:QueryServerThreat()
    local state,guid,channel=self:ServerQueryState()
    if state~="ready" then return end
    local now=GetTime()
    -- Use the basic target protocol in every display mode. The extended TM
    -- route is not needed for requesting these ten actor rows.
    local prefix="TWT_UDTSv4"
    self.serverLastQuery=now
    self.serverPending={guid=guid,at=now,generation=self.serverGeneration,channel=channel,prefix=prefix}
    local ok,result=pcall(SendAddonMessage,prefix,"limit="..self.serverRequestLimit,channel)
    if self.NoteSourceQuery then self:NoteSourceQuery(prefix,channel,ok and result~=false) end
    if ok and result~=false then
        self:ServerCount("sent")
        self.serverSendError=nil
        if not self.serverWatch or self.serverWatch.guid~=guid then self.serverWatch={guid=guid,at=now,sent=0,received=0,accepted=0} end
        self.serverWatch.sent=self.serverWatch.sent+1
        self:ThreatDiagnostics("query",guid .. " " .. prefix .. " " .. channel)
    else self.serverPending=nil; self.serverSendError=true; self:ServerCount("sendErrors"); self:ThreatDiagnostics("send-error") end
end
function E:MemberForName(name)
    local result
    for _,member in ipairs(self.roster) do
        if member.name==name then
            if result then return nil end -- two pets with the same name are ambiguous
            result=member
        end
    end
    return result
end
function E:ParseServerThreat(body)
    if type(body)~="string" or string.len(body)>8192 or string.find(body,"[%c|]") then return end
    local blocks=self:Split(body,"#")
    if table.getn(blocks)>2 or string.sub(blocks[1],1,6)~="TWTv4=" then return end
    if blocks[2] and string.sub(blocks[2],1,6)~="TMTv1=" then return end
    local result={actors={},mobs={}}
    local names,count={},0
    for _,row in ipairs(self:Split(string.sub(blocks[1],7),";")) do
        if row~="" then
            local p=self:Split(row,":")
            local amount,raw=tonumber(p[3]),tonumber(p[4])
            if table.getn(p)~=5 or not p[1] or p[1]=="" or names[p[1]] or
                (p[2]~="0" and p[2]~="1") or (p[5]~="0" and p[5]~="1") or
                not self:Finite(amount) or not self:Finite(raw) then return end
            names[p[1]]=true; count=count+1
            if count>40 then return end
            local actor={name=p[1],amount=amount,raw=raw,tank=p[2]=="1",melee=p[5]=="1"}
            table.insert(result.actors,actor)
            if actor.tank then
                if result.owner then return end
                result.owner=actor
            end
        end
    end
    if blocks[2] then
        local seen={}
        for _,row in ipairs(self:Split(string.sub(blocks[2],7),";")) do
            if row~="" then
                local p=self:Split(row,":")
                local raw=tonumber(p[4])
                if table.getn(p)~=4 or p[1]=="" or not string.find(p[2],"^0x%x+$") or
                    seen[p[2]] or not self:Finite(raw) then return end
                seen[p[2]]=true
                table.insert(result.mobs,{name=p[1],guid=p[2],second=p[3],raw=raw})
                if table.getn(result.mobs)>40 then return end
            end
        end
    end
    return result
end
function E:ReceiveServerThreat(prefix,body,channel,sender)
    if prefix=="TWT_UDTSv4" or prefix=="TWT_UDTSv4_TM" then
        if type(body)=="string" and string.find(body,"^limit=") then
            if sender~=self.playerKey then
                self.serverForeignQuery=GetTime(); self.serverPending=nil; self.serverSnapshots={}
            end
            return
        end
    end
    if type(body)~="string" or not string.find(body,"TWTv4=",1,true) then return end
    self:ServerCount("received")
    self:ThreatDiagnostics("received",tostring(prefix).." / "..tostring(channel).." / "..tostring(sender).." / "..body)
    if self.serverWatch then self.serverWatch.received=self.serverWatch.received+1 end
    local parsed=self:ParseServerThreat(body)
    if not parsed then self.serverRejectReason="format"; self:ServerCount("rejected-format"); self:ThreatDiagnostics("rejected-format"); return end
    local pending=self.serverPending
    local now=GetTime()
    -- Accept only the local request's sender/context. Unknown server sender
    -- conventions are retained in opt-in diagnostics, not silently trusted.
    local rejected
    if now-(self.serverForeignQuery or -10)<lifetime then rejected="foreign"
    elseif not pending or now-pending.at>lifetime then rejected="expired"
    elseif pending.guid~=self:GUID("target") or pending.generation~=self.serverGeneration or
        not self:Call(UnitAffectingCombat,"target") then rejected="target"
    elseif channel~=pending.channel then rejected="channel"
    elseif sender~=self.playerKey then rejected="sender" end
    if rejected then
        self.serverRejectReason=rejected; self:ServerCount("rejected-"..rejected); self:ThreatDiagnostics("rejected-context",rejected); return
    end
    self.serverPending=nil
    self:ServerCount("accepted")
    self.serverMetrics.lastReply=now
    self.serverMetrics.lastRTT=now-pending.at
    self.serverRejectReason=nil
    if self.serverWatch then self.serverWatch.accepted=self.serverWatch.accepted+1 end
    parsed.at=now; parsed.guid=pending.guid
    for _,actor in ipairs(parsed.actors) do
        local member=self:MemberForName(actor.name)
        actor.memberGUID=member and member.guid
    end
    self.serverSnapshots=self.serverSnapshots or {}
    self.serverSnapshots[pending.guid]=parsed
    if self.CompareServerThreat then self:CompareServerThreat(parsed,now-pending.at) end
    -- TMT identifies enemies but not the querying actor. Keep the same caution
    -- as TWT, and only merge creatures whose GUID can actually be resolved.
    for _,mob in ipairs(parsed.mobs) do
        if self:Exists(mob.guid) and self:Call(UnitName,mob.guid)==mob.name and self:Call(UnitCanAttack,"player",mob.guid) then
            self.serverSnapshots[mob.guid]={at=now,guid=mob.guid,partial=mob,requesterGUID=self:GUID("player")}
        end
    end
    -- Preserve the more complete target snapshot if TMT also contains it.
    self.serverSnapshots[pending.guid]=parsed
    self.tooltipSample=nil
    self:ThreatDiagnostics("accepted-context",pending.guid)
end
function E:ApplyServerThreat(enemy)
    local snapshot=enemy.guid and self.serverSnapshots and self.serverSnapshots[enemy.guid]
    if not snapshot or GetTime()-snapshot.at>lifetime then return end
    if not self:Call(UnitAffectingCombat,enemy.unit) then return end
    local owner
    if snapshot.partial then
        if not snapshot.requesterGUID or snapshot.requesterGUID~=self:GUID("player") then return end
        owner=self:Member(self.playerKey)
    elseif snapshot.owner then
        owner=self:MemberForName(snapshot.owner.name)
        if not owner or not snapshot.owner.memberGUID or owner.guid~=snapshot.owner.memberGUID then return end
    end
    -- A disagreement with current observation is evidence against this context.
    if not owner or not owner.alive or not owner.connected or (enemy.owner and enemy.owner.key~=owner.key) then return end
    enemy.combat=true
    if enemy.ownerQuality~="api" then enemy.owner=owner; enemy.ownerQuality="context" end
    enemy.source="TWT context"; enemy.sourceAt=snapshot.at
    if snapshot.partial then
        -- No melee flag and no verified percentage convention: don't turn the
        -- runner-up field into a falsely normalized bar.
        enemy.serverRunner=snapshot.partial.second; enemy.serverRaw=snapshot.partial.raw
        return
    end
    local base=snapshot.owner and snapshot.owner.amount
    if not base or base<=0 then return end
    for _,actor in ipairs(snapshot.actors) do
        local member=self:MemberForName(actor.name)
        if member and actor.memberGUID and member.guid==actor.memberGUID and member.alive and member.connected and not enemy.samples[member.key] then
            enemy.samples[member.key]={pct=self:Clamp(actor.tank and 100 or actor.amount/base/(actor.melee and 1.1 or 1.3)*100,0,100),
                amount=actor.amount,raw=actor.raw,quality="context",at=snapshot.at,
                threshold=actor.melee and 1.1 or 1.3,rangeSource="server-range"}
            if not snapshot.used then snapshot.used=true; self:ServerCount("used") end
        end
    end
end

-- Versioned, bounded group transport. Never evaluates received Lua.
local E=EasyThreat
E.peerPrefix="EasyThreat1"
-- Pipes introduce WoW chat escapes, even in addon messages on some clients.
-- Internal fields use pipes; the wire uses semicolons (absent from all field
-- alphabets, including recording base64). This preserves empty fields and size.
function E:EncodeGroupMessage(body)
    if type(body)~="string" or string.find(body,"[%c;]") then return end
    local wire=string.gsub(body,"|",";")
    return wire
end
function E:SplitGroupMessage(body)
    if type(body)~="string" or string.find(body,"[%c]") then return {} end
    local pipes=string.find(body,"|",1,true)
    if pipes and string.find(body,";",1,true) then return {} end
    -- Read old peers where their client permits it; every sender must update.
    return self:Split(body,pipes and "|" or ";")
end
E.peerBuffs={"spell_holy_sealoffury","ability_racial_avatar","spell_shadow_psychicscream",
    "spell_holy_sealofsalvation","spell_holy_greaterblessingofsalvation","spell_nature_brilliance",
    "ability_warrior_defensivestance","ability_warrior_offensivestance","ability_racial_bearform","ability_druid_catform"}
local classes={WARRIOR=true,PALADIN=true,HUNTER=true,ROGUE=true,PRIEST=true,SHAMAN=true,MAGE=true,WARLOCK=true,DRUID=true}
local forms={other=true,defensive=true,battle=true,berserker=true,bear=true,cat=true}
local function ident(value)
    return type(value)=="string" and string.len(value)<=64 and string.find(value,"^[%w%-]+$")~=nil
end
local function integer(value,max)
    local n=tonumber(value)
    if n and n==math.floor(n) and n>=0 and n<=max then return n end
end
local function flag(value) if value=="1" then return true elseif value=="0" then return false end end
local function tri(value) if value==true then return "1" elseif value==false then return "0" end; return "?" end
function E:PeerChannel()
    if not self.db or not self.db.groupSync or not self.db.enabled or self.demo or type(SendAddonMessage)~="function" then return end
    if (self:Call(GetNumRaidMembers) or 0)>0 then return "RAID" end
    if (self:Call(GetNumPartyMembers) or 0)>0 then return "PARTY" end
end
function E:ResetPeers()
    self.peerInfo={}; self.peerLastInfo=nil
    self.peerProfiles={}; self.peerOwners={}; self.peerValues={}; self.peerRequests={}; self.peerQueue={}
    self.peerLastProfile=nil; self.peerLastAsk=nil; self.peerSeenGUIDs={}; self.peerAskIndex=0; self.peerAskTarget=false
    self.peerBoot=string.format("%.0f-%d",(self:Call(time) or GetTime())*1000,math.random(100000,999999))
    self.peerSequence=0; self.peerNonce=0; self.peerNextSend=GetTime(); self.peerGroup=self.groupKey
    self.peerCoordinator=nil; self.peerCoordinatorAt=GetTime()
    self.peerSendError=nil; self.peerSendReason=nil
    self.peerTiming={responses=0,timeouts=0,expired=0}
end
function E:PeerProfile(member)
    if not member or member.unit=="player" or member.unit=="pet" or not self:PeerChannel() then return end
    local p=self.peerProfiles and self.peerProfiles[member.guid]
    if not p or p.class~=member.class or GetTime()-p.at>6 then return end
    local owner=self:MemberForGUID(p.owner)
    if not owner or not owner.connected or (member.pet and member.owner~=owner.name) then return end
    return p
end
function E:ClassState(member)
    local p=self:PeerProfile(member)
    if p then return {class=p.class,level=p.level,form=p.form,shield=p.shield,enchant=p.enchant,ranks=p.ranks,buffs=p.buffs} end
    local state={class=member.class,level=self:Call(UnitLevel,member.unit) or 0,form="other",ranks={},buffs={}}
    if not member.pet then
        if member.class=="WARRIOR" or member.class=="DRUID" then state.form=self:ClassForm(member) end
        state.shield=self:WearsShield(member)
        local known,enchanted=self:WeaponEnchantState(member)
        if known then state.enchant=enchanted end
        if member.unit=="player" then
            local snapshot=self:RefreshClassTalents()
            for key,rank in pairs(snapshot.ranks) do state.ranks[key]=rank end
        end
    end
    for i=1,32 do
        local texture,stacks=self:Call(UnitBuff,member.unit,i)
        if not texture then break end
        if type(texture)=="string" then
            local _,_,icon=string.find(string.lower(texture),"([^\\/]+)$")
            for _,allowed in ipairs(self.peerBuffs) do
                if icon==allowed then state.buffs[icon]=math.min(10,math.max(1,tonumber(stacks) or 1)) end
            end
        end
    end
    return state
end
function E:EligibleServerTarget()
    if self:Call(UnitAffectingCombat,"target") and self:Call(UnitCanAttack,"player","target") and
        not self:Call(UnitIsPlayer,"target") and not self:Call(UnitIsDeadOrGhost,"target") then return self:GUID("target") end
end
function E:QueuePeer(kind,fields,key,priority)
    if not self:PeerChannel() then return end
    if not self.peerBoot then self:ResetPeers() end
    local queue=self.peerQueue
    -- Coalesce pending heartbeats/answers; no unbounded send backlog.
    for i,row in ipairs(queue) do if row.key==key then table.remove(queue,i); break end end
    if table.getn(queue)>=40 then self.peerDropped=(self.peerDropped or 0)+1; return end
    table.insert(queue,{kind=kind,fields=fields,key=key,priority=priority or 2,at=GetTime()})
end
function E:SendPeerProfile(member)
    local state=self:ClassState(member)
    local talents,buffs={},{}
    for key,rank in pairs(state.ranks) do
        local rule=self.classTalents[key]
        if rule and rule.class==member.class then table.insert(talents,rule.id..":"..rank) end
    end
    table.sort(talents)
    for i,icon in ipairs(self.peerBuffs) do if state.buffs[icon] then table.insert(buffs,i..":"..state.buffs[icon]) end end
    self:QueuePeer("P",{self:GUID("player"),member.guid,member.class,tostring(state.level),state.form,
        tri(state.shield),tri(state.enchant),table.concat(talents,","),table.concat(buffs,","),
        member.unit=="player" and (self:EligibleServerTarget() or "-") or "-"},"profile:"..member.guid,1)
end
function E:PeerOwner(sender)
    local found
    for _,m in ipairs(self.roster) do
        if not m.pet and m.name==sender and m.connected and m.guid and m.unit~="player" then
            if found then return end
            found=m
        end
    end
    return found
end
function E:ReadPeerProfile(p,owner)
    if table.getn(p)~=14 or p[5]~=owner.guid or not ident(p[6]) or not classes[p[7]] then return end
    local member=self:MemberForGUID(p[6])
    if not member or member.class~=p[7] or (member.guid~=owner.guid and (not member.pet or member.owner~=owner.name)) then return end
    local level=integer(p[8],255)
    if not level or not forms[p[9]] or not string.find(p[10],"^[01?]$") or not string.find(p[11],"^[01?]$") or
        (p[14]~="-" and not ident(p[14])) or (member.pet and p[14]~="-") then return end
    local result={owner=owner.guid,guid=member.guid,class=member.class,level=level,form=p[9],shield=flag(p[10]),enchant=flag(p[11]),
        ranks={},buffs={},at=GetTime(),target=p[14]~="-" and p[14] or nil}
    for _,field in ipairs(p[12]~="" and self:Split(p[12],",") or {}) do
        local a=self:Split(field,":"); local id=integer(a[1],1000000); local rank=integer(a[2],10); local key
        if table.getn(a)~=2 or not id or not rank or member.pet then return end
        for k,rule in pairs(self.classTalents) do if rule.id==id and rule.class==member.class and rank<=rule.max then key=k end end
        if not key or result.ranks[key]~=nil then return end
        result.ranks[key]=rank
    end
    for _,field in ipairs(p[13]~="" and self:Split(p[13],",") or {}) do
        local a=self:Split(field,":"); local index=integer(a[1],table.getn(self.peerBuffs)); local stacks=integer(a[2],10)
        if table.getn(a)~=2 or not index or index<1 or not stacks or stacks<1 then return end
        local icon=self.peerBuffs[index]
        if result.buffs[icon] then return end
        result.buffs[icon]=stacks
    end
    return result
end
function E:PeerReject(reason)
    self.peerRejects=self.peerRejects or {}; self.peerRejects[reason]=(self.peerRejects[reason] or 0)+1
end
function E:ReceivePeer(prefix,body,channel,sender)
    if prefix==self.peerMetaPrefix then return self:ReceivePeerMeta(body,channel,sender) end
    if prefix~=self.peerPrefix then return false end
    if not self:PeerChannel() or channel~=self:PeerChannel() then return true end
    if not self.peerBoot then self:ResetPeers() end
    local owner=self:PeerOwner(sender)
    if not owner then return true end
    if type(body)~="string" or string.len(body)>220 or string.find(body,"[%c]") then self:PeerReject("format"); return true end
    local p=self:SplitGroupMessage(body)
    if table.getn(p)<4 or not ident(p[2]) or string.len(p[2])>32 or not integer(p[3],1000000000) then self:PeerReject("format"); return true end
    if p[4]~=self.ruleVersion then self:PeerReject("version"); return true end
    local runtime=self.peerOwners[owner.guid]
    if p[1]~="P" and (not runtime or runtime.boot~=p[2] or GetTime()-runtime.at>6) then self:PeerReject("session"); return true end
    if runtime and runtime.boot==p[2] and tonumber(p[3])<=runtime.seq then self:PeerReject("sequence"); return true end
    if runtime and runtime.retired and runtime.retired[p[2]] then self:PeerReject("session"); return true end
    local profile
    if p[1]=="P" then
        profile=self:ReadPeerProfile(p,owner)
        if not profile then self:PeerReject("profile"); return true end
    elseif p[1]=="A" then
        if table.getn(p)~=6 or not ident(p[5]) or not integer(p[6],1000000000) then self:PeerReject("format"); return true end
    elseif p[1]=="V" then
        if table.getn(p)~=11 or not ident(p[5]) or not ident(p[6]) or not integer(p[7],1000000000) or not ident(p[8]) or
            (p[9]~="?" and not self:Finite(tonumber(p[9]))) or (p[10]~="?" and not self:Finite(tonumber(p[10]))) or
            (p[11]~="-" and not ident(p[11])) then self:PeerReject("format"); return true end
    else self:PeerReject("format"); return true end
    if not runtime or runtime.boot~=p[2] then
        local retired=runtime and runtime.retired or {}
        if runtime then retired[runtime.boot]=true end
        local n=0; for _ in pairs(retired) do n=n+1 end
        if n>12 then self:PeerReject("restarts"); return true end
        runtime={boot=p[2],retired=retired}; self.peerOwners[owner.guid]=runtime
        for guid,old in pairs(self.peerProfiles) do if old.owner==owner.guid then self.peerProfiles[guid]=nil end end
        for _,values in pairs(self.peerValues) do values[owner.guid]=nil end
    end
    runtime.seq=tonumber(p[3]); runtime.at=GetTime()
    if profile then
        local previous=self.peerProfiles[profile.guid]
        local m=self:MemberForGUID(profile.guid)
        local changed=not previous
        if m and (m.pet or (profile.level>0 and profile.level<10)) then
            -- Pets have no talent ranks; sub-level-10 players are already known
            -- to have zero talent points. Their first profile changes no prior
            -- talent multiplier and must not erase the whole fight's totals.
            changed=false
        elseif previous then
            for key in pairs(self.classTalents) do if previous.ranks[key]~=profile.ranks[key] then changed=true end end
        end
        if changed then
            -- A late profile cannot repair earlier increments retroactively.
            for _,data in pairs(self.ledger or {}) do
                if data.values[profile.guid]~=nil then self:InvalidateActor(profile.guid,"peer-talents"); break end
            end
        end
        self.peerProfiles[profile.guid]=profile
        self.classLimits=self.classLimits or {}
        if m then self.classLimits[m.key..":foreign-talents"]=nil end
    elseif p[1]=="A" and self:PeerChannel()=="PARTY" then
        local data=self.ledger and self.ledger[p[5]]
        local function amount(guid)
            if data and data.startKnown and self:Call(UnitAffectingCombat,p[5]) and not self:Call(UnitIsDeadOrGhost,p[5]) and not data.uncertain[guid] and
                not (self.blockedActors and self.blockedActors[guid]) and self:Finite(data.values[guid]) then
                return string.format("%.6f",data.values[guid])
            end
            return "?"
        end
        local pet=self:GUID("pet")
        self:QueuePeer("V",{owner.guid,p[2],p[6],p[5],amount(self:GUID("player")),pet and amount(pet) or "?",pet or "-"},
            "answer:"..owner.guid..":"..p[5],2)
    elseif p[1]=="V" and self:PeerChannel()=="PARTY" then
        local request=self.peerRequests[p[8]]
        if p[5]~=self:GUID("player") then return true end
        if p[6]~=self.peerBoot or not request or request.nonce~=tonumber(p[7]) or GetTime()-request.at>2.5 then
            self.peerTiming.expired=self.peerTiming.expired+1; self:PeerReject("expired"); return true
        end
        local data=self.ledger and self.ledger[p[8]]
        if not data or not data.startKnown or request.data~=data then self:PeerReject("baseline"); return true end
        request.responses=request.responses or {}
        local pet=p[11]~="-" and self:MemberForGUID(p[11])
        if p[11]~="-" and (not pet or not pet.pet or pet.owner~=owner.name) then self:PeerReject("pet"); return true end
        local first=not request.responses[owner.guid]; request.responses[owner.guid]=true
        local elapsed=GetTime()-request.at
        local timing=self.peerTiming
        timing.responses=timing.responses+(first and 1 or 0); timing.last=elapsed; timing.at=GetTime()
        timing.average=timing.average and timing.average*.8+elapsed*.2 or elapsed
        timing.maximum=math.max(timing.maximum or 0,elapsed)
        self.peerValues[p[8]]=self.peerValues[p[8]] or {}
        local values=self.peerValues[p[8]]
        values[owner.guid]={amount=tonumber(p[9]),at=GetTime(),boot=p[2],owner=owner.guid,data=data}
        if pet then values[pet.guid]={amount=tonumber(p[10]),at=GetTime(),boot=p[2],owner=owner.guid,data=data} end
        self.tooltipSample=nil
    end
    return true
end
function E:PeerAmount(enemyGUID,member)
    if not self:PeerChannel() or not member or member.unit=="player" or member.unit=="pet" then return nil,false end
    local entry=self.peerValues and self.peerValues[enemyGUID] and self.peerValues[enemyGUID][member.guid]
    local owner=entry and self.peerOwners[entry.owner]
    if not entry or GetTime()-entry.at>3 or not owner or owner.boot~=entry.boot or GetTime()-owner.at>6 or
        not self:PeerProfile(member) or entry.data~=(self.ledger and self.ledger[enemyGUID]) then return nil,false end
    return entry.amount,true,entry.at
end
function E:ServerCoordinator()
    if not self:PeerChannel() then return end
    local candidate=self:EligibleServerTarget() and self:GUID("player")
    for _,member in ipairs(self.roster) do
        if not member.pet then
            local profile=self:PeerProfile(member)
            if profile and profile.target and (not candidate or profile.guid<candidate) then candidate=profile.guid end
        end
    end
    return candidate
end
function E:PeerRequestInterval()
    local players=0
    for _,member in ipairs(self.roster) do
        if not member.pet and member.connected then players=players+1 end
    end
    -- Each request elicits one reply from every other participant. Scaling
    -- avoids flooding a five-player group with the two-player polling rate.
    return math.max(.6,players*.3)
end
function E:PeerTick()
    if not self:PeerChannel() then
        if self.peerGroup then self:ResetPeers(); self.peerGroup=nil end
        return
    end
    if not self.peerBoot or self.peerGroup~=self.groupKey then self:ResetPeers() end
    local now=GetTime()
    for guid in pairs(self.peerOwners) do if not self:MemberForGUID(guid) then self.peerOwners[guid]=nil end end
    for guid,profile in pairs(self.peerProfiles) do
        local member=self:MemberForGUID(guid)
        if not member or not member.connected or now-profile.at>6 then self.peerProfiles[guid]=nil end
    end
    for enemy,values in pairs(self.peerValues) do
        for guid,entry in pairs(values) do if now-entry.at>3 or not self:MemberForGUID(guid) then values[guid]=nil end end
        if not next(values) then self.peerValues[enemy]=nil end
    end
    for enemy,request in pairs(self.peerRequests) do
        if now-request.at>3 then
            if not request.responses or not next(request.responses) then self.peerTiming.timeouts=self.peerTiming.timeouts+1 end
            self.peerRequests[enemy]=nil
        end
    end
    if now-(self.peerLastProfile or -10)>=2 then
        self.peerLastProfile=now
        for _,unit in ipairs({"player","pet"}) do
            local member=self:MemberForUnit(unit)
            if member and member.guid and ident(member.guid) then self:SendPeerProfile(member) end
        end
    end
    if self:PeerChannel()=="PARTY" and now-(self.peerLastAsk or -10)>=self:PeerRequestInterval() then
        self.peerLastAsk=now
        local enemies={}
        for guid,data in pairs(self.ledger or {}) do
            if data.startKnown and self:Call(UnitAffectingCombat,guid) and not self:Call(UnitIsDeadOrGhost,guid) then table.insert(enemies,guid) end
        end
        table.sort(enemies)
        if table.getn(enemies)>0 then
            local target=self:GUID("target"); local guid
            self.peerAskTarget=not self.peerAskTarget
            if self.peerAskTarget then for _,id in ipairs(enemies) do if id==target then guid=id; break end end end
            if not guid then
                self.peerAskIndex=math.mod(self.peerAskIndex or 0,table.getn(enemies))+1
                guid=enemies[self.peerAskIndex]
            end
            local pending=self.peerRequests[guid]; local waiting=false
            for _,m in ipairs(self.roster) do
                if not m.pet and m.unit~="player" and self:PeerProfile(m) and
                    pending and not (pending.responses and pending.responses[m.guid]) then waiting=true end
            end
            -- Do not replace a nonce while a slow peer can still answer it.
            if not pending or not waiting or now-pending.at>2.5 then
                self.peerNonce=self.peerNonce+1
                self:QueuePeer("A",{guid,tostring(self.peerNonce)},"ask:"..guid,3)
            end
        end
    end
    if now-(self.peerLastInfo or -10)>=6 then
        self.peerLastInfo=now
        self:QueuePeer("I",{self.build,self.groupRecorder and self.groupRecorder.sharing and "1" or "0",
            string.format("%.0f",self:Call(time) or 0),string.format("%.3f",now)},"info",4)
    end
    if now<(self.peerNextSend or 0) then return end
    local queue=self.peerQueue
    table.sort(queue,function(a,b) if a.priority~=b.priority then return a.priority<b.priority end; return a.at<b.at end)
    while table.getn(queue)>0 do
        local row=table.remove(queue,1)
        if now-row.at<2 then
            self.peerSequence=self.peerSequence+1
            local body=row.kind.."|"..self.peerBoot.."|"..self.peerSequence.."|"..self.ruleVersion.."|"..table.concat(row.fields,"|")
            local wire=self:EncodeGroupMessage(body)
            if wire and string.len(wire)<=220 then
                local ok,result=pcall(SendAddonMessage,row.kind=="I" and self.peerMetaPrefix or self.peerPrefix,wire,self:PeerChannel())
                ok=ok and result~=false
                self.peerSendError=not ok
                self.peerSendReason=not ok and string.sub(string.gsub(tostring(result),"[\r\n|]"," "),1,180) or nil
                self.peerTiming.queueWait=now-row.at
                -- Do not hammer a failing client transport five times a second.
                self.peerNextSend=now+(ok and 0.2 or 3)
                if ok and row.kind=="A" then
                    self.peerRequests[row.fields[1]]={nonce=tonumber(row.fields[2]),at=now,data=self.ledger[row.fields[1]]}
                end
            else self:PeerReject("size") end
            break
        end
    end
end
-- Separate prefix: older clients may ignore metadata without rejecting profiles.
E.peerMetaPrefix="EasyThreatMeta1"
function E:ReceivePeerMeta(body,channel,sender)
    if not self:PeerChannel() or channel~=self:PeerChannel() then return true end
    local member=self:PeerOwner(sender)
    if not member or type(body)~="string" or string.len(body)>220 then return true end
    local p=self:SplitGroupMessage(body)
    if table.getn(p)~=8 or p[1]~="I" or not ident(p[2]) or not integer(p[3],1000000000) or
        not ident(p[4]) or not ident(p[5]) or (p[6]~="0" and p[6]~="1") or
        not self:Finite(tonumber(p[7])) or not self:Finite(tonumber(p[8])) then return true end
    self.peerInfo=self.peerInfo or {}
    local old=self.peerInfo[member.guid]
    if old and old.boot==p[2] and tonumber(p[3])<=old.seq then return true end
    self.peerInfo[member.guid]={boot=p[2],seq=tonumber(p[3]),rules=p[4],build=p[5],sharing=p[6]=="1",
        wall=tonumber(p[7]),uptime=tonumber(p[8]),at=GetTime(),receivedAt=self:Call(time)}
    return true
end
function E:PeerInfo(member)
    local info=member and self.peerInfo and self.peerInfo[member.guid]
    if info and member.connected and GetTime()-info.at<=15 then return info end
end
function E:PeerTimingSnapshot(enemyGUID)
    local timing=self.peerTiming or {}
    local result={responses=timing.responses or 0,last=timing.last,average=timing.average,maximum=timing.maximum,
        queueWait=timing.queueWait,timeouts=timing.timeouts or 0,expired=timing.expired or 0,
        responseAge=timing.at and math.max(0,GetTime()-timing.at),queue=table.getn(self.peerQueue or {}),actors={}}
    for _,member in ipairs(self.roster) do
        local amount,shared,at=self:PeerAmount(enemyGUID,member)
        if shared and member.guid then
            table.insert(result.actors,{actor=member.guid,age=math.max(0,GetTime()-at),known=amount~=nil})
        end
    end
    return result
end

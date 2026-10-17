local E,R=EasyThreat,EasyThreatRecorder
local G={prefix="EasyThreatR1",chunk=140,maxPlain=400000,maxTotal=64*1024*1024,maxClips=3000,
    maxQueued=600,maxQueueBytes=32*1024*1024}
E.groupRecorder=G
local function number(value,limit)
    local n=tonumber(value)
    if n and n==math.floor(n) and n>=0 and n<=limit then return n end
end
function G:Channel() return E:PeerChannel()=="PARTY" and "PARTY" or nil end
function G:Send(body)
    local wire=E:EncodeGroupMessage(body)
    if not self:Channel() or not wire or string.len(wire)>240 then return false end
    local ok,result=pcall(SendAddonMessage,self.prefix,wire,"PARTY")
    ok=ok and result~=false
    self.sent=(self.sent or 0)+(ok and 1 or 0)
    self.failedSends=(self.failedSends or 0)+(ok and 0 or 1)
    self.sendError=not ok and string.sub(string.gsub(tostring(result),"[\r\n|]"," "),1,180) or nil
    self.nextSend=GetTime()+(ok and 0.25 or 3)
    return ok
end
function G:Control(body) self.control=body end
function G:Bundle() return R.db and R.db.group end
function G:Member(guid)
    local bundle=self:Bundle()
    local id=E:RecordingPseudonym(guid,bundle.session)
    local member=bundle.members[id]
    if not member then
        local m=E:MemberForGUID(guid)
        member={class=m and m.class or "?",connected=m and m.connected,received=0,cursor=0,expected=0,state="waiting",dropped=0,isLocal=guid==E:GUID("player"),joinedAt=GetTime()}
        bundle.members[id]=member
    end
    return member,id
end
function G:Begin(collect,automatic)
    -- Opening the saved-recording choice is not a successful start. Keep an
    -- inactive toggle off until the player explicitly starts a new capture.
    if collect and not self.collecting and self:Bundle() then
        if not automatic then E:ShowRecordingChoice() end
        return
    end
    if R.db then R.db.collectGroup=collect and true or false end
    if collect then
        if not self:Channel() then E:Print(E:L("Group recording needs a party and Group exchange.")); return end
        if self.collecting then return end
        local session=string.format("%x-%x",math.floor(GetTime()*1000),math.random(100000,999999))
        R.db.group={schema=1,session=session,members={},bundles={},bytes=0,clips=0,
            limits={clips=self.maxClips,plainBytes=self.maxTotal},build=E.build}
        self.collecting=true; self.job=session; self.host=E:GUID("player"); self.serial=0
        self:ClearQueue(); self.wanted=nil; self.partialRequests={}; self.lastMember=nil
        self.lastHello=nil; self.dropped=0; self.captureError=nil; self.sendError=nil
        self.wasCombat=nil; self.confirmAfter=nil
        self.sent=0; self.failedSends=0; self.received=0; self.unknownSenders=0
        for _,m in ipairs(E.roster) do if not m.pet and m.guid then self:Member(m.guid) end end
        R:Finish("group-session"); R:SetEnabled(true)
    else
        R:Finish("group-stopped")
        if self.collecting then self:Send("X|"..self.job) end
        self.collecting=false; self.job=nil; self.host=nil; self.wanted=nil; self.control=nil
        self:ClearQueue(); self.partialRequests={}
    end
    E:UpdateDiagnostics()
    return true
end
function G:AutoCollect()
    if not R.db or not R.db.collectGroup or not self.sharing or self.collecting or self.job or self:Bundle() or
        not E.db.enabled or not self:Channel() or R.sessionBlocked==E:RecordingSession() then return end
    -- Stagger starts by party GUID. The first installed, enabled client sends
    -- its hello before later clients try. A member without EasyThreat cannot
    -- prevent another member from starting. Existing recordings are never reset.
    local me=E:GUID("player")
    if not me then return end
    local rank=0
    for _,member in ipairs(E.roster) do
        if not member.pet and member.connected and member.guid and member.guid<me then rank=rank+1 end
    end
    if self.autoGroup~=E.groupKey then self.autoGroup=E.groupKey; self.autoDue=GetTime()+4+rank*4 end
    if GetTime()>=(self.autoDue or 0) then self:Begin(true,true) end
end
function G:Restart(previous)
    -- Only the explicitly reviewed recording can be discarded. Check transport
    -- before clearing anything, so losing the party cannot destroy saved data.
    if not previous or self:Bundle()~=previous or self.collecting then return false end
    if not self:Channel() then return false,"Group recording needs a party and Group exchange." end
    R:Clear()
    return self:Begin(true)
end
function G:Share(enabled)
    self.sharing=enabled and true or false
    self.autoGroup=nil; self.autoDue=nil
    if R.db then R.db.sharing=self.sharing end
    if not enabled and not self.collecting then
        -- Stop transmitting immediately. Local recording remains the player's choice.
        self:StopSharingSession()
    end
    E:UpdateDiagnostics()
end
function G:StopSharingSession()
    if R.db and R.db.groupAuto then R:SetEnabled(false,true)
    elseif self.job then R:Finish("group-stopped") end
    self.job=nil; self.host=nil; self.control=nil; self:ClearQueue()
    -- Wait for a fresh collector hello after a stop/restart. An expired timer
    -- from the prior session must not turn a follower into a competing host.
    self.autoGroup=nil; self.autoDue=nil
end
function G:ClearQueue()
    self.outbox={}; self.queueMissing={}; self.queueBytes=0; self.queueCount=0; self.tx=nil
end
function G:Missing(guid,seq,reason)
    local member=self:Member(guid)
    member.missing=member.missing or {}
    if not member.missing[seq] then
        member.missing[seq]=reason; member.missingCount=(member.missingCount or 0)+1
    end
    member.cursor=math.max(member.cursor or member.received or 0,seq)
    member.state="missing"
end
function G:Store(guid,seq,packet)
    local bundle=self:Bundle(); local member,id=self:Member(guid)
    local key=id..":"..seq
    if bundle.bundles[key] then return true end
    if bundle.bytes+packet.plain>self.maxTotal or bundle.clips>=self.maxClips then
        member.state="full"; bundle.limitReason=bundle.clips>=self.maxClips and "clips" or "bytes"; return false
    end
    bundle.bundles[key]={source=id,sequence=seq,codec="lzw12",data=packet.data,bytes=string.len(packet.data),
        checksum=packet.checksum,plainBytes=packet.plain}
    bundle.bytes=bundle.bytes+packet.plain; bundle.clips=bundle.clips+1
    member.received=(member.received or 0)+1
    member.cursor=math.max(member.cursor or 0,seq); member.state="ready"
    return true
end
function G:Capture(clip)
    if not self.job or clip.session~=self.job or not (self.collecting or self.sharing) then return end
    self.serial=(self.serial or 0)+1
    local member=self.collecting and self:Member(E:GUID("player"))
    if member then member.expected=self.serial end
    local text=E:JSON({schema=1,clips={clip}})
    local size=string.len(text)
    if size>self.maxPlain then
        self.dropped=(self.dropped or 0)+1
        self.queueMissing=self.queueMissing or {}; self.queueMissing[self.serial]="size"
        if member then member.dropped=member.dropped+1; self:Missing(E:GUID("player"),self.serial,"size") end
        return
    end
    if self.collecting then
        local packet={data=E:PackRecording(text),plain=size}
        packet.checksum=E:RecordingChecksum(packet.data)
        if not self:Store(E:GUID("player"),self.serial,packet) then member.dropped=member.dropped+1 end
    else
        -- Finished clips already live in the bounded local recording. Keep
        -- references, not hundreds of extra compressed copies. Encode only the
        -- requested clip outside combat; an ACK releases its queue entry.
        self.outbox=self.outbox or {}
        if (self.queueCount or 0)>=self.maxQueued or (self.queueBytes or 0)+size>self.maxQueueBytes then
            self.dropped=(self.dropped or 0)+1
            self.queueMissing=self.queueMissing or {}; self.queueMissing[self.serial]="queue"
        else
            self.outbox[self.serial]={clip=clip,plain=size}
            self.queueCount=(self.queueCount or 0)+1; self.queueBytes=(self.queueBytes or 0)+size
        end
    end
end
function G:QueuedPacket(seq)
    local queued=self.outbox and self.outbox[seq]
    if not queued then return end
    if queued.data then return queued end
    local text=E:JSON({schema=1,clips={queued.clip}})
    local data=E:PackRecording(text)
    return {data=data,plain=string.len(text),checksum=E:RecordingChecksum(data)}
end
function G:Receive(body,channel,sender)
    if not self:Channel() or channel~="PARTY" or type(body)~="string" or string.len(body)>240 or string.find(body,"[%c]") then return end
    -- Own PARTY echoes are not remote replies and must not inflate diagnostics.
    if sender==E:Call(UnitName,"player") then return end
    self.received=(self.received or 0)+1
    local owner=E:PeerOwner(sender)
    if not owner then self.unknownSenders=(self.unknownSenders or 0)+1; return end
    local p=E:SplitGroupMessage(body); local kind,job=p[1],p[2]
    if not job or not string.find(job,"^[%x]+%-%x+$") or string.len(job)>32 then return end
    local now=GetTime(); local me=E:GUID("player")
    if kind=="H" and table.getn(p)==2 then
        if self.collecting then
            -- Two collectors used to silently ignore one another forever.
            self:Control("S|"..job.."|"..owner.guid.."|busy|0|0|-")
            return
        end
        local state=self.sharing and "ready" or "off"
        if self.job and (self.job~=job or self.host~=owner.guid) and now-(self.heard or 0)<15 then state="busy" end
        if state=="ready" then
            if self.job~=job or self.host~=owner.guid then
                R:Finish("group-session")
                self.job=job; self.host=owner.guid; self.serial=0; self.dropped=0; self:ClearQueue()
                self.boot=string.format("%x",math.random(100000,999999))
                if not R.db.enabled then R:SetEnabled(true,true) end
            end
            self.heard=now
        end
        self:Control("S|"..job.."|"..owner.guid.."|"..state.."|"..(self.serial or 0).."|"..(self.dropped or 0).."|"..(self.boot or "-"))
        return
    end
    if kind=="X" and self.host==owner.guid and self.job==job and not self.collecting then
        self:StopSharingSession(); return
    end
    if job~=self.job or p[3]~=me then return end
    if self.collecting then
        local member,id=self:Member(owner.guid)
        if kind=="S" and table.getn(p)==7 then
            local expected,dropped=number(p[5],100000),number(p[6],100000)
            if not expected or not dropped or (p[4]~="ready" and p[4]~="off" and p[4]~="busy") then return end
            if p[4]=="ready" then
                if string.len(p[7])>12 or not string.find(p[7],"^%x+$") then return end
                if member.boot and member.boot~=p[7] then
                    member.state="restarted"
                    if self.wanted and self.wanted.guid==owner.guid then self.wanted=nil end
                    return
                end
                member.boot=p[7]
            end
            member.expected=expected; member.dropped=dropped; member.heard=now
            if member.state~="full" and member.state~="corrupt" and member.state~="restarted" then member.state=p[4] end
            return
        end
        local seq=number(p[4],100000); if not seq or seq<1 then return end
        local saved=self:Bundle().bundles[id..":"..seq]
        if kind=="D" and saved then
            self:Control("A|"..job.."|"..owner.guid.."|"..seq.."|"..math.ceil(saved.bytes/self.chunk)); return
        end
        local wanted=self.wanted
        if not wanted or wanted.guid~=owner.guid or wanted.seq~=seq then return end
        if kind=="N" and table.getn(p)==5 and (p[5]=="queue" or p[5]=="size" or p[5]=="missing") then
            self:Missing(owner.guid,seq,p[5]); self.wanted=nil
            return
        elseif kind=="M" and table.getn(p)==8 then
            local parts,bytes,sum,plain=number(p[5],6000),number(p[6],800000),number(p[7],4294967295),number(p[8],self.maxPlain)
            if not parts or not bytes or not sum or not plain or parts<1 or bytes<1 or math.ceil(bytes/self.chunk)~=parts then return end
            if not wanted.parts then
                wanted.parts=parts; wanted.bytes=bytes; wanted.sum=sum; wanted.plain=plain; wanted.chunks={}; wanted.got=0; wanted.size=0
            elseif wanted.parts~=parts or wanted.bytes~=bytes or wanted.sum~=sum or wanted.plain~=plain then member.state="corrupt"; self.wanted=nil; return end
            wanted.at=now; wanted.resume=nil
            self:Control("A|"..job.."|"..owner.guid.."|"..seq.."|"..wanted.got)
        elseif kind=="D" and table.getn(p)==6 and wanted.parts then
            local part=number(p[5],wanted.parts); local data=p[6]
            if not part or part<1 or string.len(data)>self.chunk or not string.find(data,"^[%w+/]+$") then return end
            if part==wanted.got+1 then
                table.insert(wanted.chunks,data); wanted.got=part; wanted.size=wanted.size+string.len(data); wanted.at=now
            elseif part<=wanted.got and wanted.chunks[part]~=data then member.state="corrupt"; self.wanted=nil; return end
            if wanted.got==wanted.parts then
                local packed=table.concat(wanted.chunks)
                if wanted.size~=wanted.bytes or E:RecordingChecksum(packed)~=wanted.sum then
                    member.state="corrupt"; self.wanted=nil; return
                end
                if not self:Store(owner.guid,seq,{data=packed,checksum=wanted.sum,plain=wanted.plain}) then self.wanted=nil; return end
                self.wanted=nil
            end
            self:Control("A|"..job.."|"..owner.guid.."|"..seq.."|"..wanted.got)
        end
    elseif self.sharing and self.host==owner.guid then
        local seq=number(p[4],100000); if not seq then return end
        if kind=="Q" and table.getn(p)==4 and not R:InCombat() then
            local packet=self.tx and self.tx.seq==seq and self.tx.packet or self:QueuedPacket(seq)
            if packet then self.tx={seq=seq,packet=packet,part=0,retries=0}
            elseif seq>0 and seq<=(self.serial or 0) then
                self:Control("N|"..job.."|"..owner.guid.."|"..seq.."|"..(self.queueMissing and self.queueMissing[seq] or "missing"))
            end
        elseif kind=="A" and table.getn(p)==5 and self.tx and self.tx.seq==seq then
            local part=number(p[5],math.ceil(string.len(self.tx.packet.data)/self.chunk))
            if part and self.tx.sent and (part==self.tx.part or self.tx.part==0) then
                if part==math.ceil(string.len(self.tx.packet.data)/self.chunk) then
                    local queued=self.outbox[seq]
                    if queued then
                        self.queueBytes=math.max(0,(self.queueBytes or 0)-queued.plain)
                        self.queueCount=math.max(0,(self.queueCount or 0)-1); self.outbox[seq]=nil
                    end
                    self.tx=nil
                else self.tx.part=part+1; self.tx.sent=nil; self.tx.retries=0 end
            end
        end
    end
end
function G:Tick()
    if R.db and self.job and not self.collecting and
        (not E.db.enabled or not self:Channel() or not E:MemberForGUID(self.host)) then
        self:StopSharingSession()
    end
    if not R.db or not E.db.enabled or not self:Channel() then return end
    self:AutoCollect()
    local now=GetTime()
    if self.collecting then
        local combat=R:InCombat()
        if self.wasCombat and not combat then self.confirmAfter=now+1.2 end
        self.wasCombat=combat
        if combat and self.wanted then self.wanted.at=now end
        local present={}
        for _,m in ipairs(E.roster) do
            if not m.pet and m.guid then
                local member,id=self:Member(m.guid); present[id]=true; member.connected=m.connected
            end
        end
        for id,m in pairs(self:Bundle().members) do if not present[id] then m.connected=false end end
    end
    if now<(self.nextSend or 0) then return end
    -- Keep the session alive even during a continuous stream of data ACKs.
    -- Otherwise long clips starve the hello and followers discard their queue.
    if self.collecting and now-(self.lastHello or -10)>3 then
        self.lastHello=now; self:Send("H|"..self.job); return
    end
    if self.control then local body=self.control; self.control=nil; self:Send(body); return end
    if self.collecting then
        for _,m in ipairs(E.roster) do if not m.pet and m.guid then self:Member(m.guid) end end
        if R:InCombat() then return end
        if self.wanted and now-self.wanted.at>8 then
            local member=self:Member(self.wanted.guid)
            member.state="timeout"; member.retryAt=now+2
            self.partialRequests=self.partialRequests or {}
            self.wanted.resume=true; self.wanted.asked=nil
            self.partialRequests[self.wanted.guid]=self.wanted; self.wanted=nil
        end
        if not self.wanted then
            for offset=1,table.getn(E.roster) do
                local index=math.mod((self.lastMember or 0)+offset-1,table.getn(E.roster))+1
                local m=E.roster[index]
                if not m.pet and m.unit~="player" and m.guid and m.connected then
                    local member=self:Member(m.guid)
                    local cursor=member.cursor or member.received or 0
                    if (member.state=="ready" or member.state=="missing" or member.state=="timeout") and
                        member.expected>cursor and now>=(member.retryAt or 0) then
                        local previous=self.partialRequests and self.partialRequests[m.guid]
                        self.wanted=previous and previous.seq==cursor+1 and previous or {guid=m.guid,seq=cursor+1}
                        self.wanted.at=now; self.lastMember=index
                        if self.partialRequests then self.partialRequests[m.guid]=nil end
                        break
                    end
                end
            end
        end
        local wanted=self.wanted
        if wanted and (not wanted.parts or wanted.resume) and now-(wanted.asked or -10)>1 then
            wanted.asked=now; self:Send("Q|"..self.job.."|"..wanted.guid.."|"..wanted.seq)
        end
    elseif self.sharing and self.tx and not R:InCombat() then
        if now-(self.heard or 0)>15 or not E:MemberForGUID(self.host) then self.tx=nil; return end
        local tx=self.tx
        if tx.sent and now-tx.sent<1 then return end
        if tx.retries>=6 then self.tx=nil; return end
        local head=(tx.part==0 and "M|" or "D|")..self.job.."|"..self.host.."|"..tx.seq.."|"
        local data=tx.packet.data
        if tx.part==0 then
            head=head..math.ceil(string.len(data)/self.chunk).."|"..string.len(data).."|"..tx.packet.checksum.."|"..tx.packet.plain
        else head=head..tx.part.."|"..string.sub(data,(tx.part-1)*self.chunk+1,tx.part*self.chunk) end
        if self:Send(head) then tx.sent=now; tx.retries=tx.retries+1 end
    end
end
function G:ExpectedMember(member)
    -- A player offline throughout the session owes us no recording. A player
    -- who leaves after announcing clips still owes those clips: keep that gap.
    return member.isLocal or member.connected~=false or (member.expected or 0)>0 or (member.received or 0)>0 or (member.dropped or 0)>0
end
function G:TransportSnapshot()
    local bundle=self:Bundle()
    return {collecting=self.collecting and true or false,sharing=self.sharing and true or false,
        exchange=E.db.groupSync and true or false,channel=self:Channel() or "none",
        sent=self.sent or 0,received=self.received or 0,failedSends=self.failedSends or 0,
        unknownSenders=self.unknownSenders or 0,sendFailed=self.sendError and true or false,
        captureFailed=self.captureError and true or false,pending=self.wanted and true or false,
        queuedClips=self.queueCount or 0,queuedBytes=self.queueBytes or 0,droppedClips=self.dropped or 0,
        queueClipLimit=self.maxQueued,queueByteLimit=self.maxQueueBytes,
        storedClips=bundle and bundle.clips or 0,storedBytes=bundle and bundle.bytes or 0,
        storeClipLimit=self.maxClips,storeByteLimit=self.maxTotal,
        limitReason=bundle and bundle.limitReason or nil}
end
function G:MemberStatus(member)
    if (member.missingCount or 0)>0 then return "error","Recording status: missing" end
    if member.state=="full" then return "error","Recording status: full" end
    if member.state=="corrupt" or member.state=="full" or (member.dropped or 0)>0 then
        return "error","Recording status: "..((member.dropped or 0)>0 and "dropped" or member.state)
    end
    if member.isLocal then
        if (member.received or 0)<(member.expected or 0) then return "warning","Local recording is incomplete; send the saved file." end
        return "info",(member.received or 0)>0 and "Local recording saved. No network reply is needed." or "Local recording: no combat clip yet. No action needed."
    end
    if not self:ExpectedMember(member) then return "info","Offline; no recording expected." end
    if member.state=="ready" and (member.expected or 0)==0 then return "info","Connected; no combat clip yet. No action needed." end
    if member.state=="ready" and member.received==member.expected then return "info","Recording status: ready" end
    if member.state=="ready" and (member.received or 0)<(member.expected or 0) then
        return "info","Recording status: pending"
    end
    if member.state=="waiting" and self.collecting and GetTime()-(member.joinedAt or 0)<10 then
        return "info","Waiting for the first group reply."
    end
    return "warning","Recording status: "..member.state
end
function G:Progress()
    local bundle=self:Bundle(); if not bundle then return 0,0,false end
    local complete,total=0,0
    for _,m in pairs(bundle.members) do
        if self:ExpectedMember(m) then
            total=total+1
            local fresh=not self.collecting or m.isLocal or (m.heard and m.heard>=(self.confirmAfter or 0))
            if fresh and m.state=="ready" and m.expected>0 and m.received==m.expected and m.dropped==0 and
                (m.missingCount or 0)==0 then complete=complete+1 end
        end
    end
    return complete,total,self.collecting and R:InCombat()
end

local E=EasyThreat
-- Short visual transitions only. Models, warning colours and hit identities
-- always use current data; missing values and actual aggro never ease to zero.
function E:AnimationDriver()
    if not self.animationFrame then
        self.valueAnimations={}; self.pointAnimations={}
        self.animationFrame=CreateFrame("Frame",nil,UIParent)
        self.animationFrame:SetScript("OnUpdate",function() E:AdvanceAnimations() end)
    end
    self.animationFrame:Show()
end
function E:AdvanceAnimations()
    local now=GetTime()
    for box,m in pairs(self.valueAnimations or {}) do
        local t=self:Clamp((now-m.at)/0.18,0,1)
        if not box:IsVisible() then t=1 end
        local eased=1-(1-t)*(1-t)
        box.displayValue=m.from+(m.to-m.from)*eased
        box.bar:SetValue(box.displayValue)
        if t==1 then self.valueAnimations[box]=nil end
    end
    for frame,m in pairs(self.pointAnimations or {}) do
        local t=self:Clamp((now-m.at)/0.22,0,1)
        if not frame:IsVisible() or (self.list and self.list.dragging) then t=1 end
        local eased=t*t*(3-2*t)
        frame.motionX=m.x+(m.toX-m.x)*eased; frame.motionY=m.y+(m.toY-m.y)*eased
        frame:ClearAllPoints(); frame:SetPoint("TOPLEFT",m.parent,"TOPLEFT",frame.motionX,frame.motionY)
        if t==1 then self.pointAnimations[frame]=nil end
    end
    if self.animationFrame and not next(self.valueAnimations) and not next(self.pointAnimations) then self.animationFrame:Hide() end
end
function E:AnimateValue(box,value,key,immediate)
    value=self:Clamp(value or 0,0,100)
    local same=key and box.valueKey==key
    box.valueKey=key
    if immediate or not same or not box:IsVisible() or box.displayValue==nil then
        if self.valueAnimations then self.valueAnimations[box]=nil end
        box.displayValue=value; box.bar:SetValue(value); return
    end
    local current=self.valueAnimations and self.valueAnimations[box]
    if current and current.to==value then return end
    if box.displayValue==value then
        if self.valueAnimations then self.valueAnimations[box]=nil end
        return
    end
    self:AnimationDriver()
    self.valueAnimations[box]={from=box.displayValue,to=value,at=GetTime()}
end
function E:AnimatePoint(frame,parent,x,y,key)
    local same=frame.motionKey==key and frame.motionParent==parent
    frame.motionKey=key; frame.motionParent=parent
    if not same or not frame:IsVisible() or frame.motionX==nil then
        if self.pointAnimations then self.pointAnimations[frame]=nil end
        frame.motionX=x; frame.motionY=y
        frame:ClearAllPoints(); frame:SetPoint("TOPLEFT",parent,"TOPLEFT",x,y); return
    end
    local current=self.pointAnimations and self.pointAnimations[frame]
    if current and current.toX==x and current.toY==y then return end
    if frame.motionX==x and frame.motionY==y then
        if self.pointAnimations then self.pointAnimations[frame]=nil end
        return
    end
    self:AnimationDriver()
    self.pointAnimations[frame]={x=frame.motionX,y=frame.motionY,toX=x,toY=y,parent=parent,at=GetTime()}
end
function E:ArrangeRows(sorted,offset,visible,pitch)
    local old,used,ordered=self.rows,{},{}
    -- Reserve identities before assigning spare frames to newly seen enemies.
    for i=1,visible do
        local enemy=sorted[i+offset]
        for _,row in ipairs(old) do
            if row.entry and row.entry.key==enemy.key then ordered[i]=row; used[row]=true; break end
        end
    end
    for i=1,visible do
        if not ordered[i] then
            for _,row in ipairs(old) do if not used[row] then ordered[i]=row; used[row]=true; break end end
            if not ordered[i] then ordered[i]=self:MakeRow(); used[ordered[i]]=true end
        end
    end
    for _,row in ipairs(old) do if not used[row] then table.insert(ordered,row) end end
    self.rows=ordered
    for i=1,visible do
        local row,enemy=ordered[i],sorted[i+offset]
        self:AnimatePoint(row,self.list,0,-(i-1)*pitch,enemy.key)
        self:RenderRow(row,enemy)
    end
end
function E:ArrangePlayers(row,enemy,candidates,entries)
    local pool={row.badge,row.candidates[1],row.candidates[2],row.candidates[3]}
    local members={}; members[1]=enemy.owner
    for i=1,3 do members[i+1]=candidates[i] and candidates[i].member end
    if entries then
        members={}; for i=1,4 do members[i]=entries[i] and entries[i].member end
    end
    local used,ordered={},{}
    for i=1,4 do
        local member=members[i]
        local key=member and (member.guid or member.key)
        for _,box in ipairs(pool) do
            if key and not used[box] and box.actorKey==key and box.enemyKey==enemy.key then
                ordered[i]=box; used[box]=true; break
            end
        end
    end
    for i=1,4 do
        if not ordered[i] then
            for _,box in ipairs(pool) do if not used[box] then ordered[i]=box; used[box]=true; break end end
        end
        local box,member=ordered[i],members[i]
        box.actorKey=member and (member.guid or member.key); box.enemyKey=enemy.key
        self:AnimatePoint(box,row,self.db.enemyWidth+3+(i-1)*(self.db.cellWidth+3),0,
            enemy.key..":"..(box.actorKey or ("empty"..i)))
    end
    row.badge=ordered[1]; row.candidates={ordered[2],ordered[3],ordered[4]}
end
function E:AcquireOverlay(key)
    local candidate
    for _,box in ipairs(self.overlays) do
        if not box.used and box.enemyKey==key then candidate=box; break end
    end
    if not candidate then
        -- Do not steal a live frame from an enemy processed later in this scan.
        for _,box in ipairs(self.overlays) do if not box.used and not box:IsShown() then candidate=box; break end end
    end
    if not candidate then
        candidate=self:Bar(UIParent,self.db.barWidth,self.db.barHeight); candidate:Hide()
        table.insert(self.overlays,candidate)
    end
    candidate.used=true; candidate.enemyKey=key
    return candidate
end

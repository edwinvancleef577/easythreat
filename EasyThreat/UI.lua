local E = EasyThreat
local texture="Interface\\Buttons\\WHITE8X8"
function E:Text(parent,size)
    local text=parent:CreateFontString(nil,"OVERLAY")
    self:RegisterFont(text,size or 10,"OUTLINE")
    text:SetTextColor(0.93,0.90,0.80)
    text:SetJustifyH("LEFT")
    return text
end
function E:Box(parent,width,height,name,kind)
    local box=CreateFrame(kind or "Frame",name,parent)
    box:SetWidth(width); box:SetHeight(height)
    box:SetBackdrop({bgFile=texture,edgeFile=texture,tile=false,edgeSize=1,
        insets={left=1,right=1,top=1,bottom=1}})
    box:SetBackdropColor(0.045,0.051,0.046,0.94)
    box:SetBackdropBorderColor(unpack(self.colors.bronze))
    return box
end
function E:Bar(parent,width,height)
    local box=self:Box(parent,width,height)
    box.bar=CreateFrame("StatusBar",nil,box)
    box.bar:EnableMouse(false)
    box.bar:SetPoint("TOPLEFT",box,"TOPLEFT",1,-1)
    box.bar:SetPoint("BOTTOMRIGHT",box,"BOTTOMRIGHT",-1,1)
    box.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    box.bar:SetMinMaxValues(0,100)
    box.content=CreateFrame("Frame",nil,box)
    box.content:EnableMouse(false)
    box.content:SetAllPoints(box); box.content:SetFrameLevel(box.bar:GetFrameLevel()+1)
    box.label=self:Text(box.content,9)
    box.label:SetPoint("CENTER",box.bar,"CENTER",0,0)
    return box
end
function E:WrapTooltipText(text,width)
    if not self.tooltipMeasure then
        self.tooltipMeasure=UIParent:CreateFontString(nil,"OVERLAY"); self.tooltipMeasure:Hide()
    end
    local measure=self.tooltipMeasure
    local original=getglobal and getglobal("GameTooltipTextLeft1")
    local path,size,flags
    if original then path,size,flags=self:Call(original.GetFont,original) end
    size=size or 12
    measure:SetFont(path or self:FontPath(),size,flags or ""); measure:SetWidth(2000)
    local function length(value)
        measure:SetText(value)
        local pixels=E:Call(measure.GetStringWidth,measure)
        if pixels then return pixels end
        local _,characters=string.gsub(value,"[^\128-\191]","")
        return characters*size*.65
    end
    local lines,line={},""
    local at=1
    while at<=string.len(text) do
        local byte=string.byte(text,at)
        local count=byte>=240 and 4 or byte>=224 and 3 or byte>=192 and 2 or 1
        local char=string.sub(text,at,at+count-1); at=at+count
        if char=="\n" then table.insert(lines,line); line=""
        else
            if line~="" and length(line..char)>width then
                local _,_,head,tail=string.find(line,"^(.*)%s+(%S*)$")
                table.insert(lines,head or line); line=tail or ""
            end
            if line~="" or not string.find(char,"%s") then line=line..char end
        end
    end
    table.insert(lines,line)
    return table.concat(lines,"\n")
end
function E:Tooltip(frame,text,width)
    frame:EnableMouse(true)
    frame.tip=text; frame.tipWidth=width
    frame:SetScript("OnEnter",function()
        if GameTooltip and frame.tip then
            GameTooltip:SetOwner(frame,"ANCHOR_RIGHT")
            local text=frame.tipWidth and E:WrapTooltipText(frame.tip,frame.tipWidth) or frame.tip
            GameTooltip:SetText(text,0.93,0.90,0.80,1,true)
            GameTooltip:Show()
        end
    end)
    frame:SetScript("OnLeave",function() if GameTooltip then GameTooltip:Hide() end end)
end
function E:StartHUDDrag(frame)
    if self.db.locked or not self.db.enabled or frame.dragging then return end
    frame.dragging=true; frame:StartMoving()
end
-- Dedicated handles follow cursor coordinates. Some legacy UI combinations
-- deliver mouse presses but never dispatch OnDragStart to the original HUD.
function E:StartHandleDrag(frame)
    if self.db.locked or not self.db.enabled or frame.dragging then return end
    local cx,cy=GetCursorPosition()
    local left,top=frame:GetLeft(),frame:GetTop()
    if not cx or not cy or not left or not top then return end
    if self.handleDragFrame then self:StopHUDDrag(self.handleDragFrame) end
    local parentScale=UIParent:GetEffectiveScale()
    local ratio=frame:GetEffectiveScale()/parentScale
    local x,y=left*ratio,top*ratio-UIParent:GetHeight()
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT",UIParent,"TOPLEFT",x/ratio,y/ratio)
    frame.pointerDrag={cx=cx,cy=cy,x=x,y=y,lastX=x,lastY=y,ratio=ratio,parentScale=parentScale}
    frame.dragging=true; self.handleDragFrame=frame
    if not self.handleDragDriver then
        self.handleDragDriver=CreateFrame("Frame",nil,UIParent)
        self.handleDragDriver:SetScript("OnUpdate",function()
            local moving=E.handleDragFrame
            if not moving then E.handleDragDriver:Hide(); return end
            E:MoveHandleDrag(moving)
            if E.db.locked or not E.db.enabled or E:Call(IsMouseButtonDown,"LeftButton")==false then
                E:StopHUDDrag(moving)
            end
        end)
    end
    self.handleDragDriver:Show()
end
function E:MoveHandleDrag(frame)
    local drag=frame and frame.pointerDrag
    if not drag then return end
    local cx,cy=GetCursorPosition()
    if not cx or not cy then return end
    drag.lastX=drag.x+(cx-drag.cx)/drag.parentScale
    drag.lastY=drag.y+(cy-drag.cy)/drag.parentScale
    frame:SetPoint("TOPLEFT",UIParent,"TOPLEFT",drag.lastX/drag.ratio,drag.lastY/drag.ratio)
end
function E:StopHUDDrag(frame)
    if not frame or not frame.dragging then return end
    local drag=frame.pointerDrag
    local x,y
    if drag then
        self:MoveHandleDrag(frame); x,y=drag.lastX,drag.lastY
        frame.pointerDrag=nil; self.handleDragFrame=nil; self.handleDragDriver:Hide()
    else
        frame:StopMovingOrSizing()
        local left,top=frame:GetLeft(),frame:GetTop()
        local ratio=frame:GetEffectiveScale()/UIParent:GetEffectiveScale()
        if left and top then x,y=left*ratio,top*ratio-UIParent:GetHeight() end
    end
    frame.dragging=nil
    if x and y then
        if frame==self.list then self.db.x=x; self.db.y=y
        elseif frame==self.target then self.db.targetX=x; self.db.targetY=y; self.db.targetFree=true end
    end
    if frame==self.list then self:PositionList() else self:PositionTarget() end
    self:UpdatePositions()
end
function E:BindHUDDrag(surface,frame)
    surface:EnableMouse(true); surface:RegisterForDrag("LeftButton")
    surface:SetScript("OnDragStart",function() E:StartHUDDrag(frame) end)
    surface:SetScript("OnDragStop",function() E:StopHUDDrag(frame) end)
    surface:SetScript("OnMouseUp",function() E:StopHUDDrag(frame) end)
end
function E:MakeMoveHandle(frame,label)
    -- Root-level hit surface: stays usable without a target, live enemies or
    -- Preview. It must not inherit the visibility of a conditional threat bar.
    local handle=self:Box(UIParent,184,25,nil,"Button")
    handle:SetPoint("BOTTOMLEFT",frame,"TOPLEFT",0,4)
    handle:SetFrameStrata("DIALOG"); handle:SetFrameLevel(100)
    handle:SetBackdropColor(0.14,0.12,0.07,1)
    handle:SetBackdropBorderColor(0.90,0.69,0.30,1)
    for i=1,6 do
        local dot=handle:CreateTexture(nil,"ARTWORK")
        dot:SetTexture(texture); dot:SetVertexColor(0.90,0.69,0.30)
        dot:SetWidth(3); dot:SetHeight(3)
        dot:SetPoint("TOPLEFT",handle,"TOPLEFT",6+math.mod(i-1,2)*6,-6-math.floor((i-1)/2)*5)
    end
    handle.label=self:Text(handle,10)
    handle.label:SetPoint("LEFT",handle,"LEFT",24,0)
    handle.label:SetWidth(154); handle.label:SetHeight(22); handle.label:SetJustifyH("LEFT")
    handle.caption=label; frame.moveHandle=handle
    self:BindHUDDrag(handle,frame)
    handle:SetScript("OnMouseDown",function(_,button)
        if (button or arg1)=="LeftButton" then E:StartHandleDrag(frame) end
    end)
    handle:SetScript("OnHide",function() E:StopHUDDrag(frame) end)
    handle:SetScript("OnEnter",function() handle:SetBackdropColor(0.24,0.19,0.09,1) end)
    handle:SetScript("OnLeave",function() handle:SetBackdropColor(0.14,0.12,0.07,1) end)
    handle:Hide()
end
function E:UpdateMoveHandles()
    local editing=self.db.enabled and not self.db.locked
    for _,frame in ipairs({self.list,self.target}) do
        local handle=frame.moveHandle
        if editing then
            handle:SetScale(self.db.uiScale)
            handle:SetFrameLevel(math.max(100,self.window and self.window:GetFrameLevel()+20 or 100))
            handle.label:SetText(self:L(handle.caption)); handle:Show()
            if frame==self.list then self.list.caption:Hide() end
        else handle:Hide() end
    end
end
function E:InitUI()
    self.list=CreateFrame("Frame","EasyThreatList",UIParent)
    self.list:SetWidth(350); self.list:SetHeight(20)
    self.list:SetMovable(true); self:BindHUDDrag(self.list,self.list)
    self.list:SetScript("OnHide",function() E:StopHUDDrag(E.list) end)
    self.list:EnableMouseWheel(true)
    self.scroll=0
    self.list:SetScript("OnMouseWheel",function()
        E.scroll=E:Clamp(E.scroll-(arg1 or 0),0,E.maxScroll or 0)
        E:RefreshUI()
    end)
    self.list.caption=self:Text(self.list,10)
    self.list.caption:SetPoint("BOTTOMLEFT",self.list,"TOPLEFT",0,4)
    self.list.more=self:Text(self.list,9)
    self.list.more:SetPoint("TOPLEFT",self.list,"BOTTOMLEFT",0,-3)
    self.rows={}; self.overlays={}
    self.target=self:Bar(UIParent,100,12)
    self.target:SetMovable(true); self:BindHUDDrag(self.target,self.target)
    self.target:SetScript("OnHide",function() E:StopHUDDrag(E.target) end)
    self:MakeMoveHandle(self.list,"Enemy list"); self:MakeMoveHandle(self.target,"Target frame")
    self.target:Hide()
    self:PositionList(); self:PositionTarget(); self.list:Hide()
end
function E:PositionList()
    if not self.list or self.list.dragging then return end
    self.list:ClearAllPoints()
    local scale=self.db.scale*self.db.uiScale
    self.list:SetScale(scale)
    self.list:SetPoint("TOPLEFT",UIParent,"TOPLEFT",self.db.x/scale,self.db.y/scale)
    self.list:SetWidth(self.db.enemyWidth+(self.db.cellWidth+3)*(self.db.maxCandidates+1))
end
function E:PositionTarget()
    if not self.target or self.target.dragging then return end
    local db=self.db
    local scale=db.targetScale*db.uiScale
    self.target.petGap=db.targetPetGap; self.target.otherGap=db.targetOtherGap
    self.target:ClearAllPoints(); self.target:SetScale(scale)
    self.target:SetWidth(db.targetWidth); self.target:SetHeight(db.targetHeight)
    self.target:SetPoint("TOPLEFT",db.targetFree and UIParent or (TargetFrame or UIParent),
        db.targetFree and "TOPLEFT" or "BOTTOMLEFT",db.targetX/scale,db.targetY/scale)
end
function E:SetMark(texture,index)
    texture:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    local slot=index-1
    local left=math.mod(slot,4)*0.25
    local top=math.floor(slot/4)*0.25
    texture:SetTexCoord(left,left+0.25,top,top+0.25)
end
function E:PlayerBox(parent)
    local box=self:Bar(parent,self.db.cellWidth,20)
    box.icon=box.content:CreateTexture(nil,"OVERLAY")
    box.icon:SetWidth(14); box.icon:SetHeight(14)
    box.icon:SetPoint("LEFT",box,"LEFT",3,0)
    self:Tooltip(box,"")
    return box
end
E.roleTextures={tank="Interface\\Icons\\Ability_Defend",heal="Interface\\Icons\\Spell_Holy_Heal",damage="Interface\\Icons\\Ability_DualWield"}
E.roleLabels={tank="Tank",heal="Healer",damage="Damage"}
E.rolePlaques={tank="PlaqueTank",damage="PlaqueDamage",heal="PlaqueHeal"}
local function plaqueTexture(region,path)
    if region.plaquePath==path then return true end
    local ok,value=pcall(region.SetTexture,region,path)
    local loaded=ok and value~=false and (value or E:Call(region.GetTexture,region)==path)
    if not loaded then
        ok,value=pcall(region.SetTexture,region,path..".tga")
        loaded=ok and value~=false and (value or E:Call(region.GetTexture,region)==path..".tga")
    end
    region.plaquePath=loaded and path or nil
    return loaded
end
function E:PaintRolePlaque(box,role,risk)
    local name=self.rolePlaques[role]
    if not box.roleFace then
        box.roleFace=box:CreateTexture(nil,"BACKGROUND"); box.roleFace:SetAllPoints(box)
        box.roleEdge=box.content:CreateTexture(nil,"ARTWORK"); box.roleEdge:SetAllPoints(box)
    end
    box.plaqueRole=role
    box.bar:ClearAllPoints()
    if name then
        local path="Interface\\AddOns\\EasyThreat\\Media\\"..name
        local face=plaqueTexture(box.roleFace,path.."Face")
        local edge=plaqueTexture(box.roleEdge,path.."Edge")
        self.missingPlaques=self.missingPlaques or {}
        self.missingPlaques[name]=not (face and edge) or nil
        if not face or not edge then name=nil end
    end
    if name then
        box.roleFace:Show(); box.roleEdge:Show()
        -- A transparent original backdrop is essential: a rectangular fill
        -- behind the textures would erase the distinguishing role silhouette.
        box:SetBackdropColor(0,0,0,0); box:SetBackdropBorderColor(0,0,0,0)
        if self.db.listBars then box.roleFace:SetVertexColor(.075,.082,.072,.97)
        else box.roleFace:SetVertexColor(risk[1]*.70,risk[2]*.70,risk[3]*.70,.97) end
        -- Native status bars cannot be masked on Vanilla. Keep their rectangle
        -- inside the shared interior of all three shapes at any row height.
        local height=box:GetHeight()
        box.bar:SetPoint("TOPLEFT",box,"TOPLEFT",4,-height*.25)
        box.bar:SetPoint("BOTTOMRIGHT",box,"BOTTOMRIGHT",-4,height*.18)
    else
        -- Unknown actors must not acquire a made-up role from a pooled cell.
        -- Missing artwork must never turn the actor's status invisible either.
        box.roleFace:Hide(); box.roleEdge:Hide()
        box:SetBackdropBorderColor(.67,.61,.46,.9)
        if self.db.listBars then box:SetBackdropColor(.045,.051,.046,.94)
        else box:SetBackdropColor(risk[1]*.62,risk[2]*.62,risk[3]*.62,.97) end
        box.bar:SetPoint("TOPLEFT",box,"TOPLEFT",1,-1)
        box.bar:SetPoint("BOTTOMRIGHT",box,"BOTTOMRIGHT",-1,1)
    end
end
function E:PaintPlayer(box,member,pct,quality,risk,owner)
    local db=self.db
    if db.alwaysPlayerColors and member then risk=self:IdentityColor(member) end
    box:SetWidth(db.cellWidth)
    local role=member and self:Role(member.key)
    self:PaintRolePlaque(box,role,risk)
    if box.roleEdge:IsShown() then
        local edge=owner and (role=="tank" and self.colors.green or self.colors.red) or {1,1,1}
        box.roleEdge:SetVertexColor(unpack(edge))
    end
    if db.listBars then
        box.bar:Show(); self:AnimateValue(box,owner and 100 or (pct or 0),
            (box.enemyKey or "")..":"..(member and (member.guid or member.key) or ""),owner or not pct)
        box.bar:SetStatusBarColor(unpack(owner and risk or self:IdentityColor(member)))
    else
        box.bar:Hide()
    end
    if db.listRoles and member then box.icon:SetTexture(self.roleTextures[role]); box.icon:Show() else box.icon:Hide() end
    local iconSize=math.min(db.roleIconSize,db.cellWidth-16)
    local insetSize=math.min(iconSize,box:GetHeight()*.57)
    box.icon:SetWidth(insetSize); box.icon:SetHeight(insetSize)
    box.icon:ClearAllPoints(); box.icon:SetPoint("LEFT",box,"LEFT",3+(iconSize-insetSize)/2,0)
    box.icon:SetVertexColor(0.78,0.75,0.65,0.9)
    local width=db.cellWidth-(db.listRoles and member and iconSize+8 or 8)
    local parts={}
    local percent
    if db.listPercent then
        if owner then percent=member and self:L("AGGRO") or "?"
        elseif pct then percent=(self:IsApproximate(quality) and "~" or "") .. math.floor(pct+0.5) .. "%" end
    end
    if db.listNames then
        local room=width-(percent and (string.len(percent)*4.7+4) or 0)
        local name=member and (member.pet and member.name or member.name) or "?"
        table.insert(parts,self:ShortName(name,math.max(2,math.floor(room/5.5))))
    end
    if percent then table.insert(parts,percent) end
    box.label:ClearAllPoints(); box.label:SetWidth(math.max(8,width)); box.label:SetHeight(18)
    box.label:SetPoint("LEFT",box,"LEFT",db.listRoles and member and iconSize+6 or 4,0)
    box.label:SetJustifyH("CENTER"); box.label:SetText(table.concat(parts," "))
    box.tip=member and (member.name .. (member.pet and " (" .. self:L("Pet of %s",member.owner) .. ")" or "") ..
        "\n" .. self:L(self.roleLabels[role])) or self:L("Unknown aggro holder")
    if owner then
        box.tip=box.tip .. "\n" .. self:L(quality=="context" and "Server reply; target context uncertain" or
            quality=="observed" and "Observed target; may be a spell target" or "Aggro reported by threat API")
    elseif pct then
        box.tip=box.tip .. "\n" .. (self:IsApproximate(quality) and "~" or "") .. string.format("%.1f%%",pct)
    end
    box:Show()
end
function E:MakeRow()
    local row=CreateFrame("Frame",nil,self.list)
    row:SetWidth(342); row:SetHeight(20)
    row.enemy=self:Box(row,100,20)
    row.enemy:SetPoint("LEFT",row,"LEFT",0,0)
    row.enemy.mark=row.enemy:CreateTexture(nil,"ARTWORK")
    row.enemy.mark:SetWidth(16); row.enemy.mark:SetHeight(16)
    row.enemy.mark:SetPoint("LEFT",row.enemy,"LEFT",3,0)
    row.enemy.text=self:Text(row.enemy,10)
    row.enemy.text:SetHeight(16)
    row.badge=self:PlayerBox(row)
    self:BindHUDDrag(row.badge,self.list)
    row.badge:SetPoint("LEFT",row.enemy,"RIGHT",3,0)
    row.candidates={}
    local previous=row.badge
    for i=1,3 do
        local box=self:PlayerBox(row)
        box:SetPoint("LEFT",previous,"RIGHT",3,0)
        row.candidates[i]=box; previous=box
        self:Tooltip(box,"")
        self:BindHUDDrag(box,self.list)
    end
    self:Tooltip(row.enemy,"")
    self:Tooltip(row.badge,"")
    -- Native drag threshold distinguishes moving the unlocked list from a click.
    -- Capture identity, not the pooled row: scans can reorder rows mid-click.
    row.enemy:RegisterForDrag("LeftButton")
    row.enemy:SetScript("OnMouseDown",function()
        row.enemy.press=nil
        if arg1=="LeftButton" and row.entry then
            local x,y=GetCursorPosition()
            row.enemy.press={key=row.entry.key,guid=row.entry.guid,x=x,y=y}
        end
    end)
    row.enemy:SetScript("OnDragStart",function()
        if row.enemy.press then row.enemy.press.dragged=true end
        local start=E.list:GetScript("OnDragStart"); if start then start() end
    end)
    row.enemy:SetScript("OnDragStop",function()
        if row.enemy.press then row.enemy.press.dragged=true end
        local stop=E.list:GetScript("OnDragStop"); if stop then stop() end
    end)
    row.enemy:SetScript("OnMouseUp",function()
        local press=row.enemy.press; row.enemy.press=nil
        local dragging=E.list.dragging
        local stop=E.list:GetScript("OnDragStop"); if stop then stop() end
        if arg1~="LeftButton" or not press or press.dragged or dragging then return end
        local x,y=GetCursorPosition()
        if math.abs(x-press.x)>5 or math.abs(y-press.y)>5 then return end
        local enemy=row.entry
        if row:IsVisible() and enemy and enemy.key==press.key and enemy.guid==press.guid then
            E:TargetEnemy(enemy)
        end
    end)
    return row
end
function E:RenderRow(row,enemy)
    row.entry=enemy
    local candidates=enemy.candidates or self:Candidates(enemy)
    local entries=self:ListThreatEntries(enemy)
    self:ArrangePlayers(row,enemy,candidates,entries)
    local height=self:ListRowHeight()
    row:SetHeight(height); row.enemy:SetHeight(height); row.badge:SetHeight(height)
    for _,box in ipairs(row.candidates) do box:SetHeight(height) end
    local markerSize=self.db.markerSize
    row.enemy.mark:SetWidth(markerSize); row.enemy.mark:SetHeight(markerSize)
    row:SetWidth(self.db.enemyWidth+(self.db.cellWidth+3)*(self.db.maxCandidates+1)); row.enemy:SetWidth(self.db.enemyWidth)
    row.enemy.text:ClearAllPoints()
    row.enemy.text:SetPoint("LEFT",row.enemy,"LEFT",enemy.mark and markerSize+7 or 6,0)
    row.enemy.text:SetWidth(self.db.enemyWidth-(enemy.mark and markerSize+27 or 26))
    local limit=math.floor((self.db.enemyWidth-(enemy.mark and markerSize+16 or 16))/5.5)
    row.enemy.text:SetText(self:ShortName(enemy.name,limit-2))
    if not row.dismiss then
        row.dismiss=CreateFrame("Button",nil,row.enemy); row.dismiss:SetWidth(14); row.dismiss:SetHeight(14)
        row.dismiss:SetPoint("RIGHT",row.enemy,"RIGHT",-1,0)
        row.dismiss.text=self:Text(row.dismiss,11); row.dismiss.text:SetText("×"); row.dismiss.text:SetPoint("CENTER",row.dismiss,"CENTER",0,0)
        self:Tooltip(row.dismiss,self:L("Hide this enemy for two minutes"))
        row.dismiss:SetScript("OnClick",function()
            if row.entry then E.dismissedEnemies=E.dismissedEnemies or {}; E.dismissedEnemies[row.entry.key]=GetTime()+120; E:RefreshUI() end
        end)
    end
    row.dismiss:Show()
    local age=enemy.stale and GetTime()-(enemy.retired or enemy.seen or GetTime()) or 0
    row:SetAlpha(enemy.stale and self:Clamp((15-age)/5,0,1) or 1)
    local selected=enemy.unit and self:Call(UnitIsUnit,enemy.unit,"target")
    row.enemy:SetBackdropBorderColor(unpack(selected and {0.77,0.63,0.32} or self.colors.bronze))
    row.enemy:SetAlpha(1)
    if enemy.mark then
        self:SetMark(row.enemy.mark,enemy.mark)
        row.enemy.mark:Show()
    else row.enemy.mark:Hide() end
    row.enemy.tip=enemy.name .. (enemy.stale and "\n" .. self:L("Last seen; no current data") or "")
    row.enemy.tip=row.enemy.tip .. "\n" .. self:L("Left-click to target")
    if enemy.source then row.enemy.tip=row.enemy.tip .. "\n" .. enemy.source .. " (~)" end
    if enemy.serverRunner and enemy.serverRunner~="" then
        row.enemy.tip=row.enemy.tip .. "\nTMT: " .. enemy.serverRunner .. " " .. tostring(enemy.serverRaw) .. "% (raw)"
    end
    if entries then
        local boxes={row.badge,row.candidates[1],row.candidates[2],row.candidates[3]}
        for i,box in ipairs(boxes) do
            local entry=entries[i]
            if entry and i<=self.db.maxCandidates+1 then
                local color=entry.owner and (self:IsTank(entry.member.key) and self.colors.green or self.colors.red) or
                    (entry.pct and self:RiskColor(entry.pct) or self.colors.neutral)
                color=self:RoleBarColor(enemy,entry.member,entry.pct)
                self:PaintPlayer(box,entry.member,entry.pct,entry.quality,color,entry.owner)
            else box:Hide() end
        end
    elseif enemy.combat and enemy.owner then
        local state=self:OwnerState(enemy)
        local color=state=="good" and self.colors.green or state=="bad" and self.colors.red or self.colors.neutral
        local owner=enemy.owner
        if owner then color=self:RoleBarColor(enemy,owner,100) end
        local sample=owner and enemy.samples[owner.key]
        self:PaintPlayer(row.badge,owner,sample and sample.pct,enemy.ownerQuality,color,true)
    else row.badge:Hide() end
    if not entries then
        if not (enemy.combat and enemy.owner) then
            for i,box in ipairs(row.candidates) do
                self:AnimatePoint(box,row,self.db.enemyWidth+3+(i-1)*(self.db.cellWidth+3),0,enemy.key..":"..(box.actorKey or ("empty"..i)))
            end
        end
        for i,box in ipairs(row.candidates) do
            local candidate=candidates[i]
            if enemy.combat and candidate and i<=self.db.maxCandidates then
                self:PaintPlayer(box,candidate.member,candidate.pct,candidate.quality,self:RiskColor(candidate.pct),false)
            else box:Hide() end
        end
    end
    local hidden=entries or candidates
    local limit=entries and self.db.maxCandidates+1 or self.db.maxCandidates
    if table.getn(hidden)>limit then
        row.enemy.text:SetText(row.enemy.text:GetText() .. " +")
        row.enemy.tip=row.enemy.tip .. "\n" .. self:L("More players") .. ":"
        for i=limit+1,table.getn(hidden) do
            row.enemy.tip=row.enemy.tip .. "\n" .. hidden[i].member.name .. (hidden[i].pct and (" " .. math.floor(hidden[i].pct) .. "%") or "")
        end
    end
    row:Show()
end
function E:PaintAggroBorder(box,color)
    -- The backdrop sits behind the status bar. Explicit overlay edges remain
    -- visible on thin bars and tooltip skins, without thickening a losing tank.
    if color and not box.aggroEdges then
        box.aggroEdges={}
        for _,side in ipairs({"TOP","BOTTOM","LEFT","RIGHT"}) do
            local edge=box.content:CreateTexture(nil,"OVERLAY"); edge:SetTexture(texture)
            if side=="TOP" or side=="BOTTOM" then
                edge:SetPoint(side.."LEFT",box,side.."LEFT",0,0)
                edge:SetPoint(side.."RIGHT",box,side.."RIGHT",0,0); edge:SetHeight(1)
            else
                edge:SetPoint("TOP"..side,box,"TOP"..side,0,0)
                edge:SetPoint("BOTTOM"..side,box,"BOTTOM"..side,0,0); edge:SetWidth(1)
            end
            table.insert(box.aggroEdges,edge)
        end
    end
    for _,edge in ipairs(box.aggroEdges or {}) do
        if color then edge:SetVertexColor(unpack(color)); edge:Show() else edge:Hide() end
    end
end
function E:PaintBar(box,model)
    self:AnimateValue(box,model.fillPct or model.pct,model.identity,model.unknown or
        (model.rankStack and not model.riskStack and not model.building and model.fillPct==100) or (model.aggro and not model.sharedScale))
    box.bar:SetStatusBarColor(unpack(model.color))
    box.bar:SetAlpha(model.held and .42 or 1)
    box:SetBackdropBorderColor(unpack(model.borderColor or (model.aggro and model.color) or self.colors.bronze))
    box.label:SetTextColor(unpack(model.whiteText and {1,1,1} or model.subtleText and {0.58,0.57,0.53} or {0.93,0.90,0.80}))
    box.label:SetText(model.text)
    box.label:ClearAllPoints()
    box.label:SetPoint("CENTER",box.bar,"CENTER",0,0)
    box.label:SetJustifyH("CENTER")
    self:PaintAggroBorder(box,model.borderColor)
    box.barLayoutModel=model
    self:PositionBarMarkers(box,model)
    box:Show()
end
function E:PositionBarMarkers(box,model)
    if box.buildLabel then box.buildLabel:Hide() end
    local labelWidth=math.max(1,box:GetWidth()-8)
    if model.buildAmount then
        -- One centered label, not a truncated prefix next to a separate value.
        -- Remeasure when the native tooltip/EasyCast changes the final width.
        box.label:SetWidth(0); box.label:SetText(model.text)
        local pixels=self:Call(box.label.GetStringWidth,box.label)
        if not pixels then
            local _,characters=string.gsub(model.text,"[^\128-\191]","")
            local path,size=box.label:GetFont(); pixels=characters*(size or 9)*.65
        end
        if pixels>labelWidth then box.label:SetText(model.buildAmount) end
    end
    box.label:SetWidth(labelWidth); box.label:SetHeight(box:GetHeight())
    if model.marker then
        if not box.buildMarker then box.buildMarker=box.content:CreateTexture(nil,"OVERLAY"); box.buildMarker:SetTexture(texture) end
        box.buildMarker:ClearAllPoints(); box.buildMarker:SetPoint("BOTTOMLEFT",box,"BOTTOMLEFT",1+(box:GetWidth()-2)*model.marker/100,1)
        box.buildMarker:SetWidth(1); box.buildMarker:SetHeight(3); box.buildMarker:SetVertexColor(.94,.94,.90,.9); box.buildMarker:Show()
    elseif box.buildMarker then box.buildMarker:Hide() end
    if model.pressure then
        if not box.pressure then
            box.pressure=box.content:CreateTexture(nil,"OVERLAY"); box.pressure:SetTexture("Interface\\Buttons\\WHITE8X8")
            box.pressureTrail=box.content:CreateTexture(nil,"OVERLAY"); box.pressureTrail:SetTexture("Interface\\Buttons\\WHITE8X8")
        end
        local p=model.pressure; local color=self:IdentityColor(p.member)
        local width=box:GetWidth()-4; local x=2+self:Clamp(p.pct,0,100)/100*width
        box.pressure:ClearAllPoints(); box.pressure:SetPoint("BOTTOMLEFT",box,"BOTTOMLEFT",x,1)
        box.pressure:SetWidth(2); box.pressure:SetHeight(math.max(3,box:GetHeight()-2))
        box.pressure:SetVertexColor(color[1],color[2],color[3],1); box.pressure:Show()
        box.pressureTrail:ClearAllPoints(); box.pressureTrail:SetPoint("BOTTOMLEFT",box,"BOTTOMLEFT",math.max(1,x+(p.direction<0 and -7 or 0)),1)
        box.pressureTrail:SetWidth(7); box.pressureTrail:SetHeight(2)
        box.pressureTrail:SetVertexColor(color[1],color[2],color[3],.85)
        if p.direction~=0 then box.pressureTrail:Show() else box.pressureTrail:Hide() end
    elseif box.pressure then box.pressure:Hide(); box.pressureTrail:Hide() end
end
function E:PetBarHeight(height) return math.max(8,height*self.db.petHeight/100) end
function E:ListRowHeight()
    return math.max(20,self.db.markerSize+4,self.db.listRoles and self.db.roleIconSize+4 or 0)
end
function E:PaintPetIcon(texture)
    local member=self:Member(self.playerKey..":pet")
    local family=self:Call(UnitCreatureFamily,"pet")
    local icon=family and self.demonIcons[family]
    texture:SetTexCoord(0,1,0,1)
    if member and member.class=="WARLOCK" and icon then
        texture:SetTexture("Interface\\Icons\\"..icon)
    elseif self:Exists("pet") and type(SetPortraitTexture)=="function" then
        -- Native portrait also covers custom-realm demons and renamed pets.
        SetPortraitTexture(texture,"pet")
    else texture:SetTexture("Interface\\Icons\\Ability_Hunter_BeastCall") end
end
function E:PaintLegacyThreatPair(box,model,pet)
    self:PaintBar(box,model)
    if model.pet then
        if not box.mainIcon then box.mainIcon=box.content:CreateTexture(nil,"OVERLAY") end
        self:PaintPetIcon(box.mainIcon)
        local size=math.min(self.db.petIconSize,box:GetHeight()-2)
        box.mainIcon:SetWidth(size); box.mainIcon:SetHeight(size)
        box.mainIcon:SetPoint("LEFT",box,"LEFT",2,0); box.mainIcon:Show()
    elseif box.mainIcon then box.mainIcon:Hide() end
    if not pet then if box.petBar then box.petBar:Hide() end; return end
    if not box.petBar then
        box.petBar=self:Bar(box,70,8)
        box.petBar:EnableMouse(false)
        box.petBar.icon=box.petBar.content:CreateTexture(nil,"OVERLAY")
        if box==self.target then self:BindHUDDrag(box.petBar,self.target) end
    end
    local child=box.petBar
    if pet.actor and not pet.pet then
        child.icon:SetTexture(self.roleTextures[self:Role(pet.actor.key)])
        child.icon:SetTexCoord(0,1,0,1)
    else self:PaintPetIcon(child.icon) end
    local height=self:PetBarHeight(box:GetHeight())
    local iconSize=self.db.petIconSize*(box.iconScale or 1)
    child:ClearAllPoints(); child:SetPoint("TOPRIGHT",box,"BOTTOMRIGHT",0,-(box.petGap or self.db.petGap)*(box.iconScale or 1))
    child:SetWidth(math.max(20,math.min(box:GetWidth()*self.db.petWidth/100,box:GetWidth()-iconSize-3))); child:SetHeight(height)
    child:SetFrameLevel(box:GetFrameLevel()+1)
    child.bar:SetFrameLevel(child:GetFrameLevel()+1); child.content:SetFrameLevel(child.bar:GetFrameLevel()+1)
    iconSize=math.min(iconSize,height)
    child.icon:SetWidth(iconSize); child.icon:SetHeight(iconSize)
    child.icon:ClearAllPoints(); child.icon:SetPoint("RIGHT",child,"LEFT",-3,0)
    local path,size,flags=box.label:GetFont()
    child.label:SetFont(path,math.max(7,math.min(size,height-1)),flags or "")
    self:PaintBar(child,pet)
end
function E:LayoutStackPet(box,child,top)
    -- In a tooltip the icon and bar share one row's available width. The
    -- pet bar stays right-aligned even after another addon widens the tip.
    local scale=box.iconScale or 1
    local size=math.min(self.db.petIconSize*scale,child:GetHeight())
    local iconGap=3
    local inset=0
    if box.tooltipFullStack then
        iconGap=math.min(3*scale,math.max(0,box:GetWidth()-2))
        size=math.min(size,math.max(1,box:GetWidth()-iconGap-1))
        inset=size+iconGap
    end
    child.stackPetTop=top; child.stackPetInset=inset
    child:ClearAllPoints(); child:SetPoint("TOPLEFT",box,"TOPLEFT",inset,-top)
    child:SetWidth(math.max(1,box:GetWidth()-inset))
    child.icon=child.icon or child.content:CreateTexture(nil,"OVERLAY")
    self:PaintPetIcon(child.icon)
    child.icon:ClearAllPoints(); child.icon:SetPoint("RIGHT",child,"LEFT",-iconGap,0)
    child.icon:SetWidth(size); child.icon:SetHeight(size); child.icon:Show()
    if child.barLayoutModel then self:PositionBarMarkers(child,child.barLayoutModel) end
end
function E:ThreatStackLayout(box,model,pet,height,gap,scale)
    if model.rankStack then
        local layout={references={}}; local offset=height
        if pet then
            local h=math.max(5,math.min(height-2,height*self.db.petHeight/100))
            offset=offset+gap*scale; layout.pet={top=offset,height=h,model=pet}; offset=offset+h
        end
        local h=box.tooltipReferenceHeight and math.max(5,height*box.tooltipReferenceHeight/100) or math.max(5,math.min(height-2,height*.65))
        for i,other in ipairs(model.references or {}) do
            offset=offset+(i==1 and (box.otherGap or 2) or 2)*scale
            table.insert(layout.references,{top=offset,height=h,model=other}); offset=offset+h
        end
        layout.reference=layout.references[1]
        return layout,offset-height
    end
    if model.fixedStack then
        -- Stable slots: self, optional pet, reference. Once a pet has appeared
        -- its empty slot is retained until this target changes.
        local key=model.stackIdentity or model.identity
        if box.stackKey~=key then box.stackKey=key; box.stackSeen={}; box.stackOrder={} end
        if pet then box.stackSeen.pet=true end
        if self.db.targetPet==false then box.stackSeen.pet=nil end
        local layout={}; local offset=height
        local thin=math.max(5,math.min(height-2,height*.65))
        if box.tooltipReferenceHeight then thin=math.max(5,height*box.tooltipReferenceHeight/100) end
        if pet or box.stackSeen.pet then
            local petHeight=math.max(5,math.min(height-2,height*self.db.petHeight/100))
            offset=offset+gap*scale; layout.pet={top=offset,height=petHeight,model=pet}; offset=offset+petHeight
        end
        if model.reference then
            offset=offset+(box.otherGap or 2)*scale; layout.reference={top=offset,height=thin,model=model.reference}; offset=offset+thin
        end
        return layout,offset-height
    end
    local key=model.stackIdentity or model.identity
    if box.stackKey~=key then box.stackKey=key; box.stackOrder={}; box.stackSeen={} end
    box.stackOrder=box.stackOrder or {}; box.stackSeen=box.stackSeen or {}
    local models={reference=model.reference,pet=pet}
    for _,kind in ipairs({"reference","pet"}) do
        if models[kind] and not box.stackSeen[kind] then
            table.insert(box.stackOrder,kind); box.stackSeen[kind]=true
        end
    end
    local offset,total=height,0
    local layout={}
    for _,kind in ipairs(box.stackOrder) do
        local h=kind=="reference" and math.max(7,height*.55) or self:PetBarHeight(height)
        if kind=="reference" and box.tooltipReferenceHeight then h=math.max(5,height*box.tooltipReferenceHeight/100) end
        local g=(kind=="reference" and (box.otherGap or 2) or gap)*scale
        offset=offset+g
        layout[kind]={top=offset,height=h,model=models[kind]}
        offset=offset+h; total=offset-height
    end
    return layout,total
end
function E:ThreatStackExtra(box,model,pet,height,gap,scale)
    if not model.sharedScale and not model.fixedStack then return pet and (self:PetBarHeight(height)+gap*scale) or 0 end
    local layout,total=self:ThreatStackLayout(box,model,pet,height,gap,scale)
    return total
end
function E:OverheadStackReserve()
    return self:PetBarHeight(self.db.barHeight)+self.db.petGap+(math.max(7,self.db.barHeight*.65)+2)*(self.db.otherBars or 1)
end
function E:PaintRankStack(box,model,pet)
    self:PaintBar(box,model)
    if box.mainIcon then box.mainIcon:Hide() end
    local scale=box.iconScale or 1
    local layout=self:ThreatStackLayout(box,model,pet,box:GetHeight(),box.petGap or self.db.petGap,scale)
    local function paint(child,slot)
        child:SetWidth(box:GetWidth()); child:SetHeight(slot.height)
        child:SetFrameLevel(box:GetFrameLevel()+1); child.bar:SetFrameLevel(child:GetFrameLevel()+1)
        child.content:SetFrameLevel(child.bar:GetFrameLevel()+1)
        local path,size,flags=box.label:GetFont()
        child.label:SetFont(path,math.max(6,math.min(size,slot.height-1)),flags or "")
        E:PaintBar(child,slot.model)
    end
    if layout.pet then
        if not box.petBar then box.petBar=self:Bar(box,box:GetWidth(),layout.pet.height); box.petBar:EnableMouse(false) end
        local child=box.petBar
        paint(child,layout.pet)
        self:LayoutStackPet(box,child,layout.pet.top)
        if box==self.target then self:BindHUDDrag(child,self.target) end
    elseif box.petBar then box.petBar:Hide() end
    box.comparisonBars=box.comparisonBars or {}
    if box.referenceBar and table.getn(box.comparisonBars)==0 then table.insert(box.comparisonBars,box.referenceBar) end
    local ordered,used={},{}
    for i,slot in ipairs(layout.references) do
        for _,child in ipairs(box.comparisonBars) do
            if not used[child] and child.rankIdentity==slot.model.identity then ordered[i]=child; used[child]=true; break end
        end
    end
    for i,slot in ipairs(layout.references) do
        local child=ordered[i]
        if not child then
            for _,spare in ipairs(box.comparisonBars) do if not used[spare] then child=spare; break end end
            if not child then child=self:Bar(box,box:GetWidth(),slot.height); child:EnableMouse(false); table.insert(box.comparisonBars,child) end
            ordered[i]=child; used[child]=true
        end
        child.rankIdentity=slot.model.identity
        if box==self.target then self:BindHUDDrag(child,self.target) end
        self:AnimatePoint(child,box,0,-slot.top,child.rankIdentity)
        paint(child,slot)
    end
    for _,child in ipairs(box.comparisonBars) do if not used[child] then child:Hide() end end
    box.referenceBar=ordered[1] or box.comparisonBars[1]
    box.referenceBars=ordered
end
function E:PaintThreatPair(box,model,pet)
    if model.rankStack then return self:PaintRankStack(box,model,pet) end
    for _,child in ipairs(box.comparisonBars or {}) do child:Hide() end
    if not model.sharedScale and not model.fixedStack then
        if box.referenceBar then box.referenceBar:Hide() end
        box.stackKey=nil; box.stackOrder=nil; box.stackSeen=nil
        return self:PaintLegacyThreatPair(box,model,pet)
    end
    self:PaintBar(box,model)
    if box.mainIcon then box.mainIcon:Hide() end
    local scale=box.iconScale or 1
    local layout=self:ThreatStackLayout(box,model,pet,box:GetHeight(),box.petGap or self.db.petGap,scale)
    for _,kind in ipairs({"reference","pet"}) do
        local field=kind=="reference" and "referenceBar" or "petBar"
        local slot=layout[kind]
        local child=box[field]
        if slot and slot.model then
            if not child then
                child=self:Bar(box,box:GetWidth(),slot.height); child:EnableMouse(false); box[field]=child
                if box==self.target then self:BindHUDDrag(child,self.target) end
            end
            child:ClearAllPoints(); child:SetPoint("TOPLEFT",box,"TOPLEFT",0,-slot.top)
            child:SetWidth(box:GetWidth()); child:SetHeight(slot.height)
            child:SetFrameLevel(box:GetFrameLevel()+1); child.bar:SetFrameLevel(child:GetFrameLevel()+1)
            child.content:SetFrameLevel(child.bar:GetFrameLevel()+1)
            local path,size,flags=box.label:GetFont()
            child.label:SetFont(path,math.max(6,math.min(size,slot.height-1)),flags or "")
            if kind=="pet" then
                self:LayoutStackPet(box,child,slot.top)
            end
            self:PaintBar(child,slot.model)
            if kind=="reference" and not slot.model.aggro then child:SetBackdropBorderColor(.26,.29,.28,.5) end
        elseif child then child:Hide() end
    end
end
function E:ClearOverlays()
    for _, box in ipairs(self.overlays or {}) do box:Hide(); box:ClearAllPoints() end
    self.shownOverheads=0; self.lastPlateAdapter=nil
end
function E:HideUnusedRows(visible)
    for i,row in ipairs(self.rows) do
        if i>visible then row.entry=nil; row.enemy.press=nil; row:Hide() end
    end
end
function E:RememberTargetRender(guid,model,pet,reason,preview)
    self.targetRenderSequence=(self.targetRenderSequence or 0)+1
    local references={}
    for _,other in ipairs(model and model.references or {}) do table.insert(references,self:DisplayModel(other)) end
    self.targetRender={sequence=self.targetRenderSequence,at=GetTime(),guid=guid,
        reason=reason,preview=preview or false,wanted=model and true or false,
        own=self:DisplayModel(model),pet=self:DisplayModel(pet),reference=self:DisplayModel(model and model.reference),references=references}
    if not preview then self:NoteSourceDisplay("target",guid,model,pet,self.target,reason) end
end
function E:RefreshUI()
    if self.journal then self.journal:PositionBook() end
    if not self.list or not self.profile then return end
    if self.db.locked or not self.db.enabled then
        self:StopHUDDrag(self.list); self:StopHUDDrag(self.target)
    end
    for _,box in ipairs(self.overlays) do box.used=false end
    -- Do not hide and re-show active rows every scan: that can cancel native
    -- mouse capture mid-click or interrupt a drag in the real client.
    self:SafeTooltipUpdate()
    if self.layoutPreview and self.db.enabled then
        self:ClearOverlays()
        self:RenderPreviews()
        if not self.list.dragging then self:HideUnusedRows(1) end
        for _,output in ipairs({"target","overhead","list"}) do self:RememberDisplay(output,"preview") end
        self:UpdateMoveHandles(); self:RememberTargetRender(self:GUID("target"),nil,nil,"preview",true); return
    end
    self:HidePreviews()
    if not self.db.enabled then
        self:ClearOverlays(); self:HideUnusedRows(0); self.list:Hide(); self.target:Hide(); self:UpdateMoveHandles()
        for _,output in ipairs({"target","overhead","list"}) do self:RememberDisplay(output,"disabled") end
        self:RememberTargetRender(self:GUID("target"),nil,nil,"disabled"); return
    end
    local sorted=self:SortedEnemies("list")
    local listReason=self:ShowEnemyList() and (table.getn(sorted)>0 and "visible" or "empty") or "disabled"
    local listFilter
    if listReason=="empty" then
        for _,enemy in pairs(self.enemies) do
            local allowed,filter=self:EnemyAllowed(enemy,"list")
            if not allowed then listReason="filter"; listFilter=filter; break end
        end
    end
    self:RememberDisplay("list",listReason,nil,listFilter)
    if self.list.dragging then
        -- Keep the grabbed row and mouse surface stable until the drop.
    elseif self.demo or self:ShowEnemyList() then
        self.list:Show()
        self.list.caption:SetText(self.demo and self:L("Demo values") or self:L("Drag to move"))
        if self.demo or not self.db.locked then self.list.caption:Show() else self.list.caption:Hide() end
        self.maxScroll=math.max(0,table.getn(sorted)-self.db.maxRows)
        self.scroll=self:Clamp(self.scroll or 0,0,self.maxScroll)
        local visible=math.min(self.db.maxRows,table.getn(sorted))
        local pitch=self:ListRowHeight()+3
        self.list:SetHeight(math.max(20,visible*pitch-3))
        self.list.more:SetText(self.maxScroll>0 and self:L("Scroll for more enemies") or "")
        self:ArrangeRows(sorted,self.scroll,visible,pitch)
        self:HideUnusedRows(visible)
        if visible==0 and self.db.locked and not self.demo then self.list:Hide() end
    else self:HideUnusedRows(0); self.list:Hide() end
    local index=0
    local targetShown=false
    local paintedMain,paintedPet
    self.targetModelReason="no-target-data"
    self.targetDisplayReason=nil; self.plateDisplayReason=nil
    self:RememberDisplay("overhead",self:OutputEnabled("overhead") and "no-target-data" or "disabled")
    for _,enemy in pairs(self.enemies) do
        local unit=self:ResolveEnemyUnit(enemy)
        if unit and ((enemy.guid and enemy.guid==self:GUID("target")) or self:Call(UnitIsUnit,unit,"target")) then
            local main,companion,reason=self:TargetModels(enemy)
            self.targetModelReason=reason
            if main then
                self:PaintThreatPair(self.target,main,companion); targetShown=true; paintedMain=main; paintedPet=companion
            end
        end
    end
    for _, enemy in pairs(self.enemies) do
        local unit=self:ResolveEnemyUnit(enemy)
        local current=unit~=nil
        local isTarget=current and ((enemy.guid and self:GUID("target")==enemy.guid) or self:Call(UnitIsUnit,unit,"target"))
        local model,pet,reason,filter
        if current then model,pet,reason,filter=self:CompactModels(enemy,"overhead") else reason="identity" end
        if model then
            if self.demo and self:OutputEnabled("target") and isTarget and not targetShown then
                self:PaintThreatPair(self.target,model,pet); targetShown=true
                paintedMain=model; paintedPet=pet; self.targetModelReason="visible"
            end
            if self:OutputEnabled("overhead") then
                local plate,adapter=self:PlateForUnit(unit)
                if not plate and enemy.unit~=unit and self:GUID(enemy.unit)==enemy.guid then plate,adapter=self:PlateForUnit(enemy.unit) end
                if plate and self:Call(plate.IsShown,plate) then
                    index=index+1
                    local box=self:AcquireOverlay(enemy.key)
                    local scale=self.db.overheadScale*self.db.uiScale
                    box:SetScale(scale)
                    box:SetWidth(self.db.barWidth); box:SetHeight(self.db.barHeight)
                    -- Keep the primary anchor fixed. New rows extend DOWN.
                    box:SetPoint("BOTTOM",plate,"TOP",self.db.overheadX/scale,self.db.overheadY/scale+self:OverheadStackReserve())
                    self:PaintThreatPair(box,model,pet)
                    self.lastPlateAdapter=adapter or "api"
                else
                    reason="plate"
                    if isTarget then self.plateDisplayReason="No matching nameplate. Enable enemy nameplates to show this bar." end
                end
            end
        end
        local previous=self.displayStates.overhead
        if isTarget or ((not previous.guid or previous.guid~=self:GUID("target")) and
            (reason=="visible" or reason=="held" or previous.reason=="no-target-data")) then
            self:RememberDisplay("overhead",reason,enemy,filter)
        end
    end
    self.shownOverheads=index
    for _,box in ipairs(self.overlays) do if not box.used then box:Hide(); box:ClearAllPoints() end end
    if not targetShown and not self.target.dragging then self.target:Hide() end
    self:UpdateMoveHandles()
    self:RememberDisplay("target",self.targetModelReason)
    self:RememberTargetRender(self:GUID("target"),paintedMain,paintedPet,self.targetModelReason)
end

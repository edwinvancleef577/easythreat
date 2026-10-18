-- Vanilla-compatible journal UI. Settings live only in the minimap configuration.
local E=EasyThreat
local J=E.journal
local white="Interface\\Buttons\\WHITE8X8"
local media="Interface\\AddOns\\EasyThreat\\Media\\"
local laneHeight=150
local chartHeight=300
local plotTop,plotBottom,plotHeight=14,96,102
local textures={threat=media.."JournalBinding",stock=media.."JournalStock",spend=media.."JournalSpend",
    healing=media.."JournalHeal",damage=media.."JournalDamage",efficiency=media.."JournalEfficiency",
    aggro=media.."JournalBinding",item="Interface\\Icons\\INV_Potion_54",
    cooldown="Interface\\Icons\\Spell_Nature_TimeStop",death="Interface\\Icons\\Ability_Rogue_FeignDeath",
    events="Interface\\Icons\\Spell_Holy_MagicalSentry",group=media.."JournalGroup",
    own=media.."JournalOwn",reference="Interface\\Icons\\INV_Misc_Note_01"}
local labels={threat="Threat abilities",stock="Resource availability",spend="Resource consumption",healing="Healing",damage="Damage",aggro="Aggro changes",
    item="Items and potions",cooldown="Long cooldowns",death="Deaths",events="Event icons",group="Group",own="Me and pets"}
local classLabels={normal="Normal",rare="Rare",elite="Elite",rareelite="Rare elite",worldboss="Boss"}
local fallbackIcons={JournalStock="INV_Potion_76",JournalSpend="Spell_Nature_Lightning",
    JournalHeal="Spell_Holy_FlashHeal",JournalDamage="Ability_MeleeDamage",
    JournalEfficiency="INV_Potion_76",JournalBinding="INV_Shield_05",JournalBook="INV_Misc_Book_09",
    JournalGroup="Spell_Holy_PrayerOfHealing",JournalOwn="INV_Chest_Chain"}
function J:SetIconTexture(texture,path)
    local key=type(path)=="string" and string.sub(path,1,string.len(media))==media and string.sub(path,string.len(media)+1)
    if not key or not fallbackIcons[key] then texture:SetTexture(path); return end
    -- Vanilla reports a failed file load. Try the explicit extension as well,
    -- then show a built-in icon so a missing/new file never leaves an empty slot.
    local ok,result=pcall(texture.SetTexture,texture,path)
    local loaded=ok and result~=false and (result or E:Call(texture.GetTexture,texture)==path)
    if not loaded then
        ok,result=pcall(texture.SetTexture,texture,path..".tga")
        loaded=ok and result~=false and (result or E:Call(texture.GetTexture,texture)==path..".tga")
    end
    self.missingIcons=self.missingIcons or {}
    if loaded then self.missingIcons[key]=nil
    else
        self.missingIcons[key]=true
        texture:SetTexture("Interface\\Icons\\"..fallbackIcons[key])
    end
end
function J:EnemyTip(enemy)
    local lines={self:EnemyTitle(enemy),E:L("Level").." "..(enemy.level==-1 and "??" or tostring(enemy.level or "?")).." · "..
        E:L(classLabels[enemy.classification] or "Other"),enemy.creature or ""}
    local first=self:FirstThreatPoint(enemy)
    if first then table.insert(lines,E:L("First threat observation: %.1f s. Earlier threat is unknown.",first))
    else table.insert(lines,E:L("No usable threat observation for this enemy.")) end
    return lines
end
local function text(parent,size,label)
    local f=E:Text(parent,size); if label then f:SetText(label) end; return f
end
local function at(frame,parent,x,y,w,h)
    frame:ClearAllPoints(); frame:SetPoint("TOPLEFT",parent,"TOPLEFT",x,-y)
    if w then frame:SetWidth(w) end; if h then frame:SetHeight(h) end
end
local function number(v) if v==nil then return "—" end; return string.format("%.1f",v) end
local function round(v) if v==nil then return "—" end; return tostring(math.floor(v+0.5)) end
local function decimal(v)
    if v==nil then return "—" end
    local value=string.format(v>=100 and "%.0f" or "%.2f",v)
    if E.db.language=="deDE" or (E.db.language=="auto" and GetLocale()=="deDE") then value=string.gsub(value,"%.",",") end
    return value
end
local function tint(a)
    -- Reuse live identity rules, including distinct pet colors for older fights.
    return E:IdentityColor(a,a and a.color or {0.75,0.73,0.67})
end
local function colored(s,a)
    local c=tint(a); return string.format("|cff%02x%02x%02x",c[1]*255,c[2]*255,c[3]*255)..s.."|r"
end
function J:Tip(button,lines)
    if not self.tip then self.tip=CreateFrame("GameTooltip","EasyThreatJournalTooltip",UIParent,"GameTooltipTemplate") end
    local tip=self.tip; tip:SetOwner(button,"ANCHOR_RIGHT"); tip:ClearLines()
    for i,line in ipairs(lines) do if line and line~="" then tip:AddLine(line,i==1 and 0.95 or 0.84,i==1 and 0.82 or 0.81,i==1 and 0.52 or 0.73,1) end end
    tip:Show()
end
function J:BindTip(frame,get)
    frame:EnableMouse(true)
    frame.journalTip=get
    if frame.journalTipBound then return end
    frame.journalTipBound=true
    local enter,leave=frame:GetScript("OnEnter"),frame:GetScript("OnLeave")
    frame:SetScript("OnEnter",function()
        if enter then enter() end
        J:Tip(frame,frame.journalTip())
    end)
    frame:SetScript("OnLeave",function()
        if leave then leave() end
        if J.tip then J.tip:Hide() end
    end)
end
function J:Icon(parent,path,size,tip,click)
    local b=E:Button(parent,"",size,size,click or function() end); b.text:Hide()
    -- Native normal/pushed button faces occupy ARTWORK. A child frame keeps
    -- icons above both faces, regardless of the client's texture batch order.
    b.iconLayer=CreateFrame("Frame",nil,b); b.iconLayer:SetAllPoints(b)
    b.iconLayer:SetFrameLevel(b:GetFrameLevel()+1); b.iconLayer:EnableMouse(false)
    b.icon=b.iconLayer:CreateTexture(nil,"ARTWORK"); self:SetIconTexture(b.icon,path)
    b.icon:SetPoint("CENTER",b,"CENTER",0,0)
    local function fit()
        local inset=math.min(b:GetWidth(),b:GetHeight())<=24 and 3 or 4
        b.icon:SetWidth(math.max(1,b:GetWidth()-2*inset))
        b.icon:SetHeight(math.max(1,b:GetHeight()-2*inset))
        b.iconLayer:SetFrameLevel(b:GetFrameLevel()+1)
    end
    local resize=b:GetScript("OnSizeChanged")
    b:SetScript("OnSizeChanged",function() if resize then resize() end; fit() end)
    fit()
    b.icon:SetTexCoord(0,1,0,1)
    self:BindTip(b,type(tip)=="function" and tip or function() return {E:L(tip)} end)
    return b
end
function J:Selected(button,on)
    button.border=on and {0.83,0.65,0.32} or {0.34,0.31,0.25}
    button.faceColor=on and {0.26,0.20,0.10} or {0.07,0.075,0.06}
    button.icon:SetVertexColor(on and 1 or 0.57,on and 1 or 0.57,on and 1 or 0.57,1)
    if button.portrait then button.portrait:SetAlpha(on and 1 or 0.57) end
    E:PaintButton(button)
end
function J:CapturePortrait(enemy,unit)
    if type(SetPortraitTexture)~="function" or E:GUID(unit)~=enemy.id then return end
    self.portraits=self.portraits or {}; self.portraitPool=self.portraitPool or {}
    local cached=self.portraits[enemy.id]
    if cached then return end
    if not self.portraitStorage then self.portraitStorage=CreateFrame("Frame",nil,UIParent); self.portraitStorage:Hide() end
    if table.getn(self.portraitPool)>=80 then
        cached=table.remove(self.portraitPool,1); self.portraits[cached.id]=nil
        for _,frame in ipairs(cached.frames) do
            if frame.button then frame.button.portrait=nil; frame.button.icon:Show(); frame.button=nil end
            frame:Hide(); frame:SetParent(self.portraitStorage)
        end
    else
        cached={frames={}}
        for i=1,2 do
            local frame=CreateFrame("Frame",nil,self.portraitStorage); frame:EnableMouse(false)
            frame:SetWidth(32); frame:SetHeight(32)
            frame.texture=frame:CreateTexture(nil,"ARTWORK"); frame.texture:SetAllPoints(frame)
            cached.frames[i]=frame
        end
    end
    cached.id=enemy.id; cached.valid=false
    for _,frame in ipairs(cached.frames) do
        frame.texture:SetTexCoord(0,1,0,1); frame.texture:SetVertexColor(1,1,1,1)
        local ok,result=pcall(SetPortraitTexture,frame.texture,unit)
        if ok and result~=false then cached.valid=true else cached.valid=false; break end
    end
    self.portraits[enemy.id]=cached; table.insert(self.portraitPool,cached)
end
function J:EnemyArt(button,enemy,slot)
    if button.portrait then
        button.portrait:Hide(); button.portrait.button=nil; button.portrait:SetParent(self.portraitStorage)
        button.portrait=nil
    end
    button.icon:Show(); button.icon:SetTexCoord(0,1,0,1)
    if not enemy then return end
    local fallback=enemy.icon
    if fallback=="Interface\\Icons\\INV_Misc_Head_Human_01" then fallback="Interface\\Icons\\INV_Helmet_03" end
    if fallback=="Interface\\Icons\\INV_Misc_Head_Dragon_01" then fallback="Interface\\Icons\\Ability_Hunter_Pet_WindSerpent" end
    button.icon:SetTexture(fallback)
    local unit=E:ResolveEnemyUnit({guid=enemy.id})
    if unit then self:CapturePortrait(enemy,unit) end
    local cached=self.portraits and self.portraits[enemy.id]
    if cached and cached.valid then
        local frame=cached.frames[slot]
        if frame.button and frame.button~=button then frame.button.portrait=nil; frame.button.icon:Show() end
        frame.button=button; button.portrait=frame
        frame:SetParent(button.iconLayer); frame:SetFrameLevel(button.iconLayer:GetFrameLevel()+1)
        frame:ClearAllPoints(); frame:SetPoint("CENTER",button,"CENTER",0,0)
        frame:SetWidth(button:GetWidth()-4); frame:SetHeight(button:GetHeight()-4)
        frame:SetAlpha(1); frame:Show(); button.icon:Hide()
    end
end
function J:EnemyMarker(button,x,y)
    local layer=CreateFrame("Frame",nil,button); layer:SetAllPoints(button)
    layer:SetFrameLevel(button.iconLayer:GetFrameLevel()+4); layer:EnableMouse(false)
    local mark=layer:CreateTexture(nil,"OVERLAY"); at(mark,button,x,y,13,13)
    return mark
end
function J:EnemyRim(button,enemy)
    local kind=enemy and enemy.classification
    if kind=="elite" or kind=="rare" or kind=="rareelite" or kind=="worldboss" then
        if not button.rarity then
            button.rarity=CreateFrame("Frame",nil,button)
            button.rarity.texture=button.rarity:CreateTexture(nil,"OVERLAY")
            button.rarity.texture:SetTexture(media.."JournalPortraitRim"); button.rarity.texture:SetAllPoints(button.rarity)
            button.rarity:SetPoint("CENTER",button,"CENTER",0,0)
            button.rarity:SetWidth(button:GetWidth()+7); button.rarity:SetHeight(button:GetHeight()+7)
            button.rarity:EnableMouse(false)
        end
        local silver=kind=="rare" or kind=="rareelite"
        local color=silver and {.82,.89,1} or {1,1,1}
        button.rarity.texture:SetDesaturated(silver and true or false)
        button.rarity.texture:SetVertexColor(color[1],color[2],color[3],1)
        button.rarity:SetFrameLevel(button.iconLayer:GetFrameLevel()+3); button.rarity:Show()
    elseif button.rarity then button.rarity:Hide() end
end
function J:PositionBook()
    if not self.book or not E.db then return end
    local s=E.db.uiScale
    E.db.journalBookX=E:Clamp(E.db.journalBookX,0,math.max(0,UIParent:GetWidth()-E.db.journalBookSize*s))
    E.db.journalBookY=E:Clamp(E.db.journalBookY,0,math.max(0,UIParent:GetHeight()-E.db.journalBookSize*s))
    self.book:SetScale(s); self.book:SetWidth(E.db.journalBookSize); self.book:SetHeight(E.db.journalBookSize)
    if not self.bookDragging then
        self.book:ClearAllPoints(); self.book:SetPoint("BOTTOMLEFT",UIParent,"BOTTOMLEFT",E.db.journalBookX/s,E.db.journalBookY/s)
    end
    if E.db.enabled and E.db.journalEnabled and E.db.journalBook then self.book:Show() else self.book:Hide() end
    if not E.db.locked and self.book:IsShown() then self.book.grip:Show() else self.book.grip:Hide() end
end
function J:InitBook()
    if self.book then return end
    -- The book's transparent silhouette is the entire launcher: no button face
    -- or slot border. Only its brightness changes on hover.
    local b=CreateFrame("Button",nil,UIParent); b:SetWidth(36); b:SetHeight(36)
    b:SetFrameStrata("MEDIUM"); b:RegisterForClicks("LeftButtonUp"); self.book=b
    b.icon=b:CreateTexture(nil,"ARTWORK"); self:SetIconTexture(b.icon,media.."JournalBook")
    b.icon:SetTexCoord(0,1,0,1); b.icon:SetPoint("CENTER",b,"CENTER",0,0)
    b.shadow=b:CreateTexture(nil,"BACKGROUND"); self:SetIconTexture(b.shadow,media.."JournalBook")
    -- These silhouettes overlap. Low per-layer alpha matters: four opaque
    -- outlines plus a large shadow used to look like a solid dark backing.
    b.shadow:SetVertexColor(0.02,0.02,0.02,0.22); b.shadow:SetPoint("CENTER",b,"CENTER",.5,-1)
    b.outlines={}
    for _,offset in ipairs({{-.5,0},{.5,0},{0,-.5},{0,.5}}) do
        local edge=b:CreateTexture(nil,"BORDER"); self:SetIconTexture(edge,media.."JournalBook")
        edge:SetDesaturated(true); edge:SetVertexColor(.72,.75,.73,.08)
        edge:SetPoint("CENTER",b,"CENTER",offset[1],offset[2]); table.insert(b.outlines,edge)
    end
    local function resize()
        b.icon:SetWidth(b:GetWidth()); b.icon:SetHeight(b:GetHeight())
        b.shadow:SetWidth(b:GetWidth()+5); b.shadow:SetHeight(b:GetHeight()+5)
        for _,edge in ipairs(b.outlines) do edge:SetWidth(b:GetWidth()+1); edge:SetHeight(b:GetHeight()+1) end
    end
    local function rest() b.icon:SetVertexColor(0.78,0.78,0.78,1) end
    b:SetScript("OnSizeChanged",resize); resize(); rest()
    b:SetScript("OnEnter",function() b.icon:SetVertexColor(1,1,1,1) end)
    b:SetScript("OnLeave",rest); b:SetScript("OnShow",rest)
    b:SetScript("OnHide",function() rest(); if J.tip then J.tip:Hide() end end)
    b:SetScript("OnClick",function() if not J.bookDragging then J:Toggle() end end)
    self:BindTip(b,function() return {E:L("Combat journal")} end)
    local grip=E:Box(b,64,16,nil,"Button"); grip:SetPoint("BOTTOMLEFT",b,"TOPLEFT",0,3)
    local label=text(grip,9,"···"); label:SetPoint("CENTER",grip,"CENTER",0,1); b.grip=grip
    grip:EnableMouse(true); grip:RegisterForClicks("LeftButtonUp")
    grip:SetScript("OnMouseDown",function()
        if E.db.locked then return end
        local x,y=GetCursorPosition(); J.bookDragging={x=x,y=y,bx=E.db.journalBookX,by=E.db.journalBookY}
    end)
    local function stop() J.bookDragging=nil; J:PositionBook(); E:UpdatePositions() end
    grip:SetScript("OnMouseUp",stop); grip:SetScript("OnHide",function() J.bookDragging=nil end)
    grip:SetScript("OnUpdate",function()
        local d=J.bookDragging; if not d then return end
        if E:Call(IsMouseButtonDown,"LeftButton")==false then stop(); return end
        local x,y=GetCursorPosition(); local scale=UIParent:GetEffectiveScale()
        E.db.journalBookX=E:Clamp(d.bx+(x-d.x)/scale,0,UIParent:GetWidth()-E.db.journalBookSize)
        E.db.journalBookY=E:Clamp(d.by+(y-d.y)/scale,0,UIParent:GetHeight()-E.db.journalBookSize)
        b:ClearAllPoints(); b:SetPoint("BOTTOMLEFT",UIParent,"BOTTOMLEFT",E.db.journalBookX/E.db.uiScale,E.db.journalBookY/E.db.uiScale)
    end)
    self:PositionBook()
end
function J:Toggle() if self.window and self.window:IsShown() then self.window:Hide() else self:Show() end end
function J:Actors(f)
    local result={}
    for _,id in ipairs(f.order or {}) do local a=f.actors[id]; if not E.db.journalOwn or a.own then table.insert(result,a) end end
    return result
end
function J:ReferenceActor(f,a)
    for _,id in ipairs(f.order or {}) do local b=f.actors[id]; if b.key==a.key and b.name==a.name and b.class==a.class then return b end end
end
function J:ReferenceEnemy(f,enemy)
    local matches={}
    for _,id in ipairs(f.enemyOrder or {}) do local b=f.enemies[id]; if b.name==enemy.name and b.classification==enemy.classification then table.insert(matches,b) end end
    if table.getn(matches)==1 then return matches[1] end
    for _,b in ipairs(matches) do if enemy.mark and b.mark==enemy.mark then return b end end
end
function J:Values(f,lane,a)
    if lane.kind=="damage" then return a.damageLine end
    if lane.kind=="enemy" then
        local enemy=lane.enemy
        if f~=self.viewFight then enemy=self:ReferenceEnemy(f,enemy) end
        return enemy and enemy.series[a.id]
    end
    return a[lane.kind]
end
function J:Value(f,lane,a,t)
    if lane.kind=="damage" then return self:At(a.damageLine,t,1) end
    if a.dead and t>=a.dead and lane.kind~="healing" and lane.kind~="spend" then return end
    local enemy=lane.enemy
    if enemy and f~=self.viewFight then enemy=self:ReferenceEnemy(f,enemy) end
    if enemy and enemy.dead and t>=enemy.dead then return end
    local series=self:Values(f,lane,a)
    return self:HeldAt(series,t,lane.kind=="healing" and 2 or 1.25)
end
function J:MakeWindow()
    if self.window then return end
    local w=E:Box(UIParent,660,700,"EasyThreatJournalWindow"); self.window=w
    w:SetFrameStrata("DIALOG"); w:SetBackdrop({bgFile=white,
        edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",tile=false,edgeSize=24,
        insets={left=8,right=8,top=8,bottom=8}})
    -- The dialog background may be translucent or replaced by a UI skin.
    -- A solid dark surface keeps the plots readable over the game world.
    w:SetBackdropColor(0.045,0.051,0.046,1); w:SetBackdropBorderColor(0.8,0.74,0.6,1)
    w:SetPoint("CENTER",UIParent,"CENTER",0,0); w:SetMovable(true); w:EnableMouse(true)
    w:RegisterForDrag("LeftButton"); w:SetScript("OnDragStart",function() w:StartMoving() end)
    w:SetScript("OnDragStop",function() w:StopMovingOrSizing() end)
    w:SetScript("OnHide",function() J.timeDrag=nil; J.hover=nil; if J.tip then J.tip:Hide() end end)
    if UISpecialFrames then table.insert(UISpecialFrames,"EasyThreatJournalWindow") end
    w.title=text(w,19,E:L("Combat journal")); w.title:SetPoint("TOP",w,"TOP",0,-17)
    w.title:SetTextColor(0.94,0.82,0.53)
    w.close=CreateFrame("Button",nil,w,"UIPanelCloseButton"); at(w.close,w,622,10,28,28)
    w.close:SetScript("OnClick",function() w:Hide() end)
    w.summary=E:Box(w,616,48); at(w.summary,w,22,46)
    w.summary:SetBackdropColor(0.105,0.092,0.060,1); w.summary:SetBackdropBorderColor(0.60,0.48,0.27,1)
    w.stats={}
    for i,path in ipairs({textures.damage,textures.efficiency,textures.aggro}) do
        local b=E:Box(w.summary,198,46,nil,"Button"); at(b,w.summary,7+(i-1)*204,1)
        b:SetBackdropBorderColor(0,0,0,0); b:SetBackdropColor(0,0,0,0)
        b.icon=b:CreateTexture(nil,"ARTWORK"); self:SetIconTexture(b.icon,path); at(b.icon,b,1,7,32,32)
        b.label=text(b,17); b.label:SetPoint("LEFT",b.icon,"RIGHT",9,0); b.label:SetWidth(151); b.label:SetHeight(30)
        b.label:SetJustifyV("MIDDLE")
        if i>1 then
            b.divider=b:CreateTexture(nil,"BORDER"); b.divider:SetTexture(white); b.divider:SetVertexColor(0.60,0.48,0.27,0.55)
            at(b.divider,b,-5,8,1,30)
        end
        local index=i; self:BindTip(b,function() return J:SummaryTip(index) end); w.stats[i]=b
    end
    w.general={}; local x=346
    for _,kind in ipairs({"stock","spend","healing","damage","events"}) do
        local key=kind
        local b=self:Icon(w,textures[kind],24,labels[kind],function()
            if key=="events" then E.db.journalEvents=not E.db.journalEvents else E.db.journalViews[key]=not E.db.journalViews[key] end
            J:Render()
        end); at(b,w,x,102); x=x+30; w.general[kind]=b
    end
    -- Two positions of one switch: both choices stay visible, with a gold
    -- selected face. Each half sets its state instead of toggling blindly.
    w.scopeToggle=E:Box(w,59,28); at(w.scopeToggle,w,573,100)
    w.scopeToggle.group=self:Icon(w.scopeToggle,textures.group,26,"Group",function() E.db.journalOwn=false; J:Render() end)
    w.scopeToggle.own=self:Icon(w.scopeToggle,textures.own,26,"Me and pets",function() E.db.journalOwn=true; J:Render() end)
    at(w.scopeToggle.group,w.scopeToggle,2,1); at(w.scopeToggle.own,w.scopeToggle,31,1)
    w.quality=self:Icon(w,"Interface\\Icons\\INV_Misc_Note_01",22,"Journal data quality",function() end)
    at(w.quality,w,20,15); self:BindTip(w.quality,function() return J:QualityTip() end)
    w.enemyButtons={}; w.lanes={}; w.legend=text(w,11); at(w.legend,w,22,157,610,18)
    w.charts=CreateFrame("ScrollFrame","EasyThreatJournalCharts",w,"UIPanelScrollFrameTemplate")
    w.chartChild=CreateFrame("Frame",nil,w.charts); w.chartChild:SetWidth(606); w.chartChild:SetHeight(1); w.charts:SetScrollChild(w.chartChild)
    local chartScroll=w.charts:GetScript("OnVerticalScroll")
    w.charts:SetScript("OnVerticalScroll",function()
        local offset=arg1 or 0; if not J.scrolling then J.scrollTarget=nil end; if chartScroll then chartScroll() end
        J:DrawCharts(offset,false)
    end)
    w.charts:EnableMouseWheel(true)
    w.charts:SetScript("OnMouseWheel",function()
        local maximum=math.max(0,table.getn(J.selectedLanes or {})*laneHeight-chartHeight)
        J.scrollTarget=E:Clamp((J.scrollTarget or J.chartOffset or 0)-(arg1 or 0)*65,0,maximum)
    end)
    w.axis={}; w.refAxis={}
    for i=1,5 do w.axis[i]=text(w,10); w.refAxis[i]=text(w,10); w.refAxis[i]:SetTextColor(0.55,0.53,0.48) end
    w.seek=CreateFrame("Slider",nil,w); w.seek:SetOrientation("HORIZONTAL"); w.seek:SetMinMaxValues(0,1); w.seek:SetValueStep(0.01)
    w.seek:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    w.seek:SetBackdrop({bgFile=white}); w.seek:SetBackdropColor(0.18,0.16,0.11,1)
    w.seek:SetScript("OnValueChanged",function() if not J.settingSeek then J:SetTime(w.seek:GetValue()) end end)
    w.range=E:Box(w,550,8); w.range:EnableMouse(true)
    w.range.selection=w.range:CreateTexture(nil,"ARTWORK"); w.range.selection:SetTexture(white); w.range.selection:SetVertexColor(0.7,0.53,0.24,0.5)
    w.range.grips={}
    for _,side in ipairs({"start","finish"}) do
        local key=side; local b=E:Button(w.range,"",10,20,function() end); b.text:Hide(); w.range.grips[side]=b
        b:SetScript("OnMouseDown",function() J:StartRangeDrag(key) end)
        b:SetScript("OnMouseUp",function() J.timeDrag=nil end)
    end
    w.range:SetScript("OnMouseDown",function() J:StartRangeDrag("move") end)
    w.range:SetScript("OnMouseUp",function() J.timeDrag=nil end)
    w.rangeLabel=text(w,10)
    w.log=E:Box(w,616,168); w.log:SetBackdropColor(0.025,0.028,0.022,1)
    w.log.title=text(w.log,12,E:L("Combat log")); at(w.log.title,w.log,10,8,175,18)
    w.log.filters={}
    for i,kind in ipairs({"damage","heal","aggro","item","cooldown","death","threat"}) do
        local key=kind; local path=textures[kind] or textures.healing
        local b=self:Icon(w.log,path,22,labels[kind] or "Healing",function()
            E.db.journalFilters[key]=not E.db.journalFilters[key]; J:RenderLog(true)
        end)
        at(b,w.log,410+(i-1)*28,6); w.log.filters[kind]=b
    end
    w.log.scroll=CreateFrame("ScrollFrame","EasyThreatJournalLog",w.log,"UIPanelScrollFrameTemplate")
    at(w.log.scroll,w.log,7,34,578,125); w.log.child=CreateFrame("Frame",nil,w.log.scroll)
    w.log.child:SetWidth(578); w.log.child:SetHeight(125); w.log.scroll:SetScrollChild(w.log.child)
    w.log.rows={}
    local scrollHandler=w.log.scroll:GetScript("OnVerticalScroll")
    w.log.scroll:SetScript("OnVerticalScroll",function()
        local offset=arg1 or 0
        if scrollHandler then scrollHandler() end
        J:FillLog(offset)
    end)
    w.footer=E:Box(w,616,38); w.footer:SetBackdropColor(0.08,0.075,0.056,1)
    w.compare=E:Button(w.footer,"Show reference",218,27,function() if J.db.reference then J.compare=not J.compare; J:Render() end end)
    at(w.compare,w.footer,6,6); w.compare.state=text(w.compare,10); w.compare.state:SetPoint("RIGHT",w.compare,"RIGHT",-8,0)
    self:BindTip(w.compare,function() return {E:L("Show reference"),E:L("Journal normalized comparison")} end)
    w.compare.text:SetWidth(172); w.compare.text:ClearAllPoints(); w.compare.text:SetPoint("LEFT",w.compare,"LEFT",8,0)
    w.save=E:Button(w.footer,"Save as new reference",260,27,function()
        if J:SaveReference() then J:Render(); J:Tip(w.save,{E:L("Reference saved"),E:L("Entire fight")..": "..number(J.db.reference.duration).." s"}) end
    end); at(w.save,w.footer,350,6)
    w:SetScript("OnUpdate",function()
        J.uiElapsed=(J.uiElapsed or 0)+(arg1 or 0); if J.uiElapsed<0.04 then return end
        local dt=J.uiElapsed; J.uiElapsed=0
        if J.scrollTarget then
            local offset=J.chartOffset or 0
            local remaining=J.scrollTarget-offset
            offset=offset+remaining*math.min(1,dt*14)
            if math.abs(remaining)<0.4 then offset=J.scrollTarget; J.scrollTarget=nil end
            J.scrolling=true
            local bar=_G["EasyThreatJournalChartsScrollBar"]; if bar then bar:SetValue(offset) end
            w.charts:SetVerticalScroll(offset); J:DrawCharts(offset,false); J.scrolling=nil
        end
        if J.timeDrag then J:MoveRangeDrag()
        elseif J.hover and J.viewFight then
            local row=J.hover; local x=GetCursorPosition()/row.canvas:GetEffectiveScale()-row.canvas:GetLeft()
            J:SetTime(J.start+E:Clamp(x/row.canvas:GetWidth(),0,1)*(J.finish-J.start))
            J:PlotTip(row)
        end
    end)
    w:Hide()
end
function J:Show()
    if not self.db then return end
    self:MakeWindow()
    local f=self.db.last
    if not f then self:Tip(self.book,{E:L("Combat journal"),E:L("Journal available after combat")}); return end
    if self.viewFight~=f then self.viewFight=f; self.start=0; self.finish=f.duration; self.moment=0; self.enemySelection={}; self.chartOffset=0 end
    self.window:Show(); self:Render()
end
function J:SummaryTip(i)
    local f=self.viewFight; local s=self:Summary(f); if not f then return {E:L("Combat journal")} end
    if i==1 then return {E:L("Group DPS"),E:L("Entire fight"),round(s.damage).." "..E:L("Damage"),number(s.duration).." s",E:L("Journal local observations only")}
    elseif i==2 then
        local lines={E:L("Damage per mana"),decimal(s.damagePerMana).." "..E:L("Damage / mana abbreviation"),
            round(s.damage).." "..E:L("Damage").." / "..round(s.mana).." "..E:L("Mana"),
            E:L("All group damage divided by observed group mana use, including healing. Not a player rating."),
            E:L("Journal resource consumption is a lower bound")}
        local reference=self.compare and self.db.reference and self:Summary(self.db.reference)
        if reference and reference.damagePerMana and reference.damagePerMana>0 then
            table.insert(lines,E:L("Reference = 100%%: %s damage per mana.",decimal(reference.damagePerMana)))
            table.insert(lines,E:L("Fight composition, healing and resource regeneration affect this comparison."))
        else table.insert(lines,E:L("Show a reference fight to display this ratio as a percentage.")) end
        return lines
    else
        local control,coverage,approximate,known,tank=self:TankControl(f)
        return {E:L("Tank control"),number(tank).." / "..number(known).." "..E:L("Known enemy-seconds"),
            E:L("Coverage")..": "..round(coverage).."%",E:L("Journal observed targets are not certain aggro"),
            E:L("No tank or less than 50% coverage: no score.")}
    end
end
function J:QualityState(f)
    if self.fault or f.notes["Journal capture interrupted"] then return "error" end
    if f.source~="structured" or f.notes["Journal capture limit reached"] or f.notes["Journal healing incomplete"] or
        f.notes["Journal start may be incomplete"] or f.notes["Journal event source changed"] then return "warning" end
    for _,peer in ipairs(f.peers or {}) do if peer.status=="No addon reply" or peer.status=="Different addon build" then return "warning" end end
    return "ok"
end
function J:QualityTip()
    local result={E:L("Journal data quality")}
    if self.fault then table.insert(result,E:L("Journal capture failed")); table.insert(result,tostring(self.fault)) end
    local f=self.viewFight or self.db.last
    if f then
        local state=self:QualityState(f)
        local messages={error="Red: recording failed or was interrupted.",warning="Yellow: some observations are missing or less precise.",ok="Green: no capture problem detected; threat may still be estimated."}
        table.insert(result,E:L(messages[state]))
        table.insert(result,E:L(f.source=="structured" and "Client combat events: actor, target and amounts arrive separately." or "Combat chat: localized messages are parsed; unrecognized messages can be missed."))
        table.insert(result,E:L("Resource use is sampled. An observed target may be a spell target, not the threat owner."))
        for _,peer in ipairs(f.peers or {}) do
            local sharing=peer.sharing==true and E:L("On") or peer.sharing==false and E:L("Off") or E:L("Unknown")
            table.insert(result,peer.name.." · "..E:L("Share recordings")..": "..sharing)
            table.insert(result,peer.name..": "..E:L(peer.status)..(peer.build and " · "..peer.build or " · "..E:L("Version not reported")))
        end
        table.insert(result,E:L("Sharing transfers recordings, not a complete live journal. It may be disabled to limit traffic and shared data."))
        for key in pairs(f.notes) do table.insert(result,E:L(key)) end
    end
    return result
end
function J:MakeLane(index)
    local w=self.window; local row=CreateFrame("Frame",nil,w.chartChild); row:SetWidth(606); row:SetHeight(laneHeight)
    row.icon=self:Icon(row,textures.stock,24,"Combat journal",function() end); at(row.icon,row,2,1)
    row.heading=text(row,12); at(row.heading,row,34,3,565,20)
    row.surface=row:CreateTexture(nil,"BACKGROUND"); row.surface:SetTexture(white); at(row.surface,row,0,29,601,116)
    -- A recessed metal rail separates whole tracks, including their headings.
    row.divider=row:CreateTexture(nil,"BORDER"); row.divider:SetTexture(white)
    row.divider:SetVertexColor(.055,.045,.032,1); at(row.divider,row,0,145,601,5)
    row.dividerLight=row:CreateTexture(nil,"BORDER"); row.dividerLight:SetTexture(white)
    row.dividerLight:SetVertexColor(.62,.52,.35,.85); at(row.dividerLight,row,0,145,601,1)
    row.dividerInset=row:CreateTexture(nil,"BORDER"); row.dividerInset:SetTexture(white)
    row.dividerInset:SetVertexColor(.22,.19,.13,1); at(row.dividerInset,row,1,147,599,1)
    row.mark=self:EnemyMarker(row.icon,17,-3)
    row.canvas=CreateFrame("Frame",nil,row); at(row.canvas,row,40,31,560,plotHeight); row.canvas:EnableMouse(true)
    row.textures={}; row.events={}; row.count=0; row.shades={}
    row.baseline=row.canvas:CreateTexture(nil,"BACKGROUND"); row.baseline:SetTexture(white); row.baseline:SetVertexColor(0.5,0.46,0.36,0.2)
    at(row.baseline,row.canvas,0,plotBottom,560,1)
    row.guide=row.canvas:CreateTexture(nil,"OVERLAY"); row.guide:SetTexture(white); row.guide:SetVertexColor(0.91,0.83,0.68,0.65)
    row.canvas:SetScript("OnEnter",function() J.hover=row end)
    row.canvas:SetScript("OnLeave",function() J.hover=nil; if J.tip then J.tip:Hide() end end)
    row.canvas:SetScript("OnMouseDown",function() J.hover=row end)
    w.lanes[index]=row; return row
end
function J:PaintTexture(row,x,y,width,height,color,alpha,path,coords)
    row.count=row.count+1; local t=row.textures[row.count]
    if not t then t=row.canvas:CreateTexture(nil,"ARTWORK"); row.textures[row.count]=t end
    t:SetTexture(path or white); t:SetVertexColor(color[1],color[2],color[3],alpha or 1)
    at(t,row.canvas,x,y,math.max(.6,width),math.max(.6,height))
    if coords then t:SetTexCoord(unpack(coords)) else t:SetTexCoord(0,1,0,1) end
    t:Show()
end
function J:Line(row,x1,y1,x2,y2,color,alpha)
    local dx,dy=x2-x1,y2-y1; local len=math.sqrt(dx*dx+dy*dy)
    if len<0.1 then return end
    local pad=1; local left,top=math.min(x1,x2)-pad,math.min(y1,y2)-pad
    local width,height=math.abs(dx)+2*pad,math.abs(dy)+2*pad
    local function u(x,y) return 0.5+(-(x-x1)*dy+(y-y1)*dx)/len/256 end
    self:PaintTexture(row,left,top,width,height,color,alpha,media.."JournalLine",
        {u(left,top),0,u(left,top+height),1,u(left+width,top),0,u(left+width,top+height),1})
end
function J:HasJournalTank(f)
    for _,a in pairs(f.actors) do if a.role=="tank" then return true end end
    return false
end
function J:UnexpectedOwner(f,p)
    if not p or (p.q~="api" and p.q~="observed") or (p.role~="damage" and p.role~="heal") then return end
    local a=f.actors[p.id]
    if a and (not E.db.journalOwn or a.own) then return a end
end
function J:AggroWindows(enemy)
    local result={}; local f=self.viewFight
    if not self:HasJournalTank(f) then return result end
    for i,p in ipairs(enemy.owners) do
        local a=self:UnexpectedOwner(f,p)
        local nextPoint=enemy.owners[i+1]
        local first=math.max(self.start,p.t)
        local last=math.min(self.finish,f.duration,enemy.dead or f.duration,p.t+1.25,nextPoint and nextPoint.t or f.duration)
        if a and last>first then
            local previous=result[table.getn(result)]
            if previous and previous.actor==a and previous.q==p.q and previous.finish==first then previous.finish=last
            else table.insert(result,{actor=a,q=p.q,start=first,finish=last}) end
        end
    end
    return result
end
function J:PlotAggro(row,lane,steps,yy)
    local n=0; local span=self.finish-self.start
    local function shade(x,y,width,height,alpha)
        if width<=0 or height<=0 then return end
        n=n+1; local t=row.shades[n]
        if not t then
            -- Separate draw layer keeps the warning behind every player's curve.
            t=row.canvas:CreateTexture(nil,"BORDER"); t:SetTexture(white); row.shades[n]=t
        end
        t:SetVertexColor(0.94,0.18,0.12,alpha)
        at(t,row.canvas,x,y,width,height); t:Show()
    end
    if lane.enemy and span>0 then for _,period in ipairs(self:AggroWindows(lane.enemy)) do
        local x=(period.start-self.start)/span*560
        local width=(period.finish-period.start)/span*560
        -- The target can be observed even when a numerical threat curve is missing.
        -- Mark that interval without inventing threat percentages.
        shade(x,plotTop,width,plotBottom-plotTop,period.q=="api" and 0.19 or 0.14)
        local slices=math.max(1,math.ceil(width/560*steps))
        for i=0,slices-1 do
            local t=period.start+(period.finish-period.start)*(i+0.5)/slices
            local v=self:Value(self.viewFight,lane,period.actor,t)
            if v and v>0 then local y=yy(v); shade(x+width*i/slices,y,width/slices,plotBottom-y,0.19) end
        end
    end end
    for i=n+1,table.getn(row.shades) do row.shades[i]:Hide() end
end
function J:Plot(row,lane)
    row.heading:SetText(lane.enemy and self:EnemyTitle(lane.enemy) or E:L(labels[lane.kind]))
    if E.db.journalTitles then row.heading:Show() else row.heading:Hide() end
    local special=lane.enemy and lane.enemy.classification~="normal"
    if lane.enemy then row.surface:SetVertexColor(special and .18 or .13,.075,.065,.7)
    else row.surface:SetVertexColor(.075,.09,.085,.7) end
    row.lane=lane; row.count=0; self:SetIconTexture(row.icon.icon,lane.enemy and lane.enemy.icon or textures[lane.kind])
    self:EnemyArt(row.icon,lane.enemy,2)
    self:EnemyRim(row.icon,lane.enemy)
    if lane.enemy then
        if lane.enemy.mark then E:SetMark(row.mark,lane.enemy.mark); row.mark:Show() else row.mark:Hide() end
        row.icon:SetBackdropBorderColor(unpack(lane.enemy.classification=="elite" and {0.8,0.64,0.25} or
            (lane.enemy.classification=="rare" or lane.enemy.classification=="rareelite") and {0.7,0.76,0.82} or E.colors.bronze))
    else row.mark:Hide(); row.icon:SetBackdropBorderColor(unpack(E.colors.bronze)) end
    self:BindTip(row.icon,function() return lane.enemy and J:EnemyTip(lane.enemy) or {E:L(labels[lane.kind])} end)
    local f=self.viewFight; local actors=self:PlotActors(lane,f); local max=lane.kind=="stock" and 100 or 1
    for _,a in ipairs(actors) do for _,p in ipairs(self:Values(f,lane,a) or {}) do if p.v and p.v>max then max=p.v end end end
    if lane.kind=="enemy" then max=100 end
    local ref=self.compare and self.db.reference
    if ref then for _,a in ipairs(actors) do local b=lane.kind=="damage" and self:DamageActor(ref) or self:ReferenceActor(ref,a); if b then for _,p in ipairs(self:Values(ref,lane,b) or {}) do if p.v and p.v>max then max=p.v end end end end end
    if lane.kind=="healing" and E.db.journalOverheal then
        for _,a in ipairs(actors) do
            for _,p in ipairs(a.healing) do local over=self:At(a.overheal,p.t,2); if p.v and over then max=math.max(max,p.v+over) end end
        end
    end
    row.max=max
    local steps=math.min(160,math.max(20,math.floor(400/math.max(1,table.getn(actors)))))
    local function yy(v) return plotBottom-E:Clamp(v/max,0,1)*(plotBottom-plotTop) end
    self:PlotAggro(row,lane,steps,yy)
    for pass=1,2 do
        local source; if pass==1 then source=ref else source=f end
        if source then
            for _,actor in ipairs(actors) do
                local a; if pass==1 then a=lane.kind=="damage" and self:DamageActor(source) or self:ReferenceActor(source,actor) else a=actor end
                if a then
                    local prev,prevx,prevy,prevHeld
                    for i=0,steps do
                        local t=(self.start+(self.finish-self.start)*i/steps)/f.duration*source.duration
                        local v,p=self:Value(source,lane,a,t); local x=560*i/steps
                        local positive=v and (v>0 or lane.kind=="stock")
                        if positive then
                            local y=yy(v)
                            -- Quality is explained in the tooltip. Never encode
                            -- estimates by punching artificial holes in a curve.
                            if prev then
                                local held=(p and p.held) or prevHeld
                                self:Line(row,prevx,prevy,x,y,tint(actor),pass==1 and (held and .14 or .25) or (held and .38 or .95))
                            end
                            if pass==2 and lane.kind=="healing" and E.db.journalOverheal then
                                local over=self:At(a.overheal,t,2)
                                if over and over>0 then self:PaintTexture(row,x,yy(v+over),1,math.max(1,y-yy(v+over)),tint(actor),0.28) end
                            end
                            prev=true; prevx=x; prevy=y; prevHeld=p and p.held
                        else prev=nil end
                    end
                end
            end
        end
    end
    for i=row.count+1,table.getn(row.textures) do row.textures[i]:Hide() end
    self:PlotEvents(row)
end
function J:PlotEvents(row)
    local n=0; local lane=row.lane; local f=self.viewFight
    if E.db.journalEvents then for _,ev in ipairs(f.events) do
        local relevant=(ev.kind=="item" or ev.kind=="cooldown" or ev.kind=="death" or ev.kind=="threat") and ev.t>=self.start and ev.t<=self.finish
        if lane.enemy then
            local selfCast=ev.threat and ev.actor and (not ev.target or ev.target==ev.actor) and
                self:At(lane.enemy.series[ev.actor],ev.t,1.25)~=nil
            relevant=relevant and (ev.target==lane.enemy.id or selfCast)
        else relevant=relevant and (ev.kind~="death" or f.actors[ev.actor]) end
        if E.db.journalOwn and ev.actor and f.actors[ev.actor] and not f.actors[ev.actor].own then relevant=false end
        if relevant and n<40 then
            n=n+1; local b=row.events[n]
            if not b then
                b=CreateFrame("Button",nil,row.canvas); b:SetWidth(18); b:SetHeight(18)
                b.icon=b:CreateTexture(nil,"ARTWORK"); b.icon:SetAllPoints(b)
                b:SetScript("OnClick",function() if b.ev then J:SetTime(b.ev.t) end end); row.events[n]=b
                self:BindTip(b,function() return J:EventTip(b.ev) end)
            end
            b.ev=ev; self:SetIconTexture(b.icon,ev.icon or textures[ev.kind] or textures.item)
            local x=E:Clamp((ev.t-self.start)/(self.finish-self.start)*560-9,0,540)
            at(b,row.canvas,x,2); b:Show()
        end
    end end
    for i=n+1,table.getn(row.events) do row.events[i]:Hide() end
end
function J:PlotTip(row)
    local lines={row.lane.enemy and row.lane.enemy.name or E:L(labels[row.lane.kind]),number(self.moment).." s"}
    local estimated=false
    local owner=row.lane.enemy and self:OwnerAt(row.lane.enemy,self.moment)
    local unexpected=self:UnexpectedOwner(self.viewFight,owner)
    if unexpected and self:HasJournalTank(self.viewFight) then
        local key=owner.q=="api" and "Confirmed aggro on non-tank" or "Observed target: non-tank (aggro unconfirmed)"
        table.insert(lines,"|cffff796a"..E:L(key).."|r: "..colored(unexpected.name,unexpected))
    end
    for _,a in ipairs(self:PlotActors(row.lane,self.viewFight)) do
        local v,p=self:Value(self.viewFight,row.lane,a,self.moment)
        if v and p and p.q~="api" and p.q~="observed" then estimated=true end
        local value=round(v)
        if row.lane.kind=="stock" and v then value=round(v*p.max/100).." / "..round(p.max).." ("..round(v).."%)" end
        if (row.lane.kind=="stock" or row.lane.kind=="spend") and p then
            local kind=({[0]="Mana",[1]="Rage",[2]="Focus",[3]="Energy"})[p.kind]
            if kind then value=value.." "..E:L(kind) end
        end
        if row.lane.kind=="enemy" and v then value=value.."%" end
        if row.lane.kind=="damage" and v then value=value.." DPS" end
        if p and p.held then value=value.." · "..E:L("Last value (%.1f s old)",math.max(0,self.moment-p.observedAt)) end
        table.insert(lines,colored(a.name,a)..": "..value)
    end
    if row.lane.kind=="damage" then table.insert(lines,E:L("Damage across all enemies, trailing two seconds. Observed events only.")) end
    if row.lane.kind=="spend" then table.insert(lines,E:L("Journal resource consumption is a lower bound")) end
    if row.lane.kind=="healing" then table.insert(lines,E:L("Journal healing uses observed health")) end
    if row.lane.kind=="enemy" and estimated then table.insert(lines,E:L("Journal threat values are estimates")) end
    self:Tip(row.icon,lines)
end
function J:Render()
    local f=self.viewFight; local w=self.window; if not f or not w then return end
    local s=self:Summary(f)
    w.title:SetText(E:L("Combat journal")); w.log.title:SetText(E:L("Combat log"))
    local quality=self:QualityState(f)
    if quality=="error" then w.quality.icon:SetVertexColor(1,.3,.25,1)
    elseif quality=="warning" then w.quality.icon:SetVertexColor(1,.8,.2,1)
    else w.quality.icon:SetVertexColor(.3,.9,.4,1) end
    w.stats[1].label:SetText(round(s.dps).." DPS")
    local reference=self.compare and self.db.reference and self:Summary(self.db.reference)
    if s.damagePerMana and reference and reference.damagePerMana and reference.damagePerMana>0 then
        w.stats[2].label:SetText("≈"..round(100*s.damagePerMana/reference.damagePerMana).."%")
    else w.stats[2].label:SetText((s.damagePerMana and "≈" or "")..decimal(s.damagePerMana).." "..E:L("Damage / mana abbreviation")) end
    local control,coverage,approximate=self:TankControl(f)
    w.stats[3].label:SetText((control and coverage>=50 and (approximate and "≈" or "")..round(control) or "—").."%")
    for _,b in ipairs(w.stats) do
        -- GetStringWidth can report the clipped width on Vanilla. Measure on
        -- a separate unconstrained string; never feed a clipped value back.
        if not b.measure then b.measure=text(b,17); b.measure:Hide() end
        local path,_,flags=b.label:GetFont(); b.label:SetFont(path,17,flags)
        b.measure:SetFont(path,17,flags); b.measure:SetWidth(2000); b.measure:SetText(b.label:GetText())
        local needed=math.max(80,E:Call(b.measure.GetStringWidth,b.measure) or 145)
        if needed>145 then b.label:SetFont(path,math.max(10,17*145/needed),flags) end
        local width=math.min(145,needed+6)
        local left=(198-32-9-width)/2
        at(b.icon,b,left,7,32,32); b.label:SetWidth(width); b.label:SetJustifyH("LEFT")
    end
    for key,b in pairs(w.general) do self:Selected(b,key=="events" and E.db.journalEvents or E.db.journalViews[key]) end
    self:Selected(w.scopeToggle.group,not E.db.journalOwn)
    self:Selected(w.scopeToggle.own,E.db.journalOwn)
    local lanes={}
    for i,id in ipairs(f.enemyOrder) do
        local enemy=f.enemies[id]; local b=w.enemyButtons[i]
        if not b then
            b=self:Icon(w,enemy.icon,24,"Enemy",function() if b.enemy then J.enemySelection[b.enemy.id]=not J.enemySelection[b.enemy.id]; J:Render() end end)
            b.mark=self:EnemyMarker(b,15,-1); w.enemyButtons[i]=b
            self:BindTip(b,function() return J:EnemyTip(b.enemy) end)
        end
        b.enemy=enemy; self:EnemyArt(b,enemy,1)
        if enemy.mark then E:SetMark(b.mark,enemy.mark); b.mark:Show() else b.mark:Hide() end
        if self.enemySelection[id]==nil then self.enemySelection[id]=true end
        self:Selected(b,self.enemySelection[id]); at(b,w,22+math.mod(i-1,7)*30,102+math.floor((i-1)/7)*29); b:Show()
        self:EnemyRim(b,enemy)
        if self.enemySelection[id] then table.insert(lanes,{kind="enemy",enemy=enemy}) end
    end
    for i=table.getn(f.enemyOrder)+1,table.getn(w.enemyButtons) do w.enemyButtons[i]:Hide() end
    for _,kind in ipairs({"stock","spend","healing","damage"}) do
        if E.db.journalViews[kind] then table.insert(lanes,{kind=kind}) end
    end
    local y=106+math.max(1,math.ceil(table.getn(f.enemyOrder)/7))*29
    if E.db.journalLegend then
        local names={}; for _,a in ipairs(self:Actors(f)) do table.insert(names,colored(a.name,a)) end
        at(w.legend,w,22,y,610,18); w.legend:SetText(table.concat(names,"   ")); w.legend:Show(); y=y+22
    else w.legend:Hide() end
    local n=table.getn(lanes); local height=chartHeight
    at(w.charts,w,22,y,606,height); w.chartChild:SetHeight(math.max(height,n*laneHeight))
    self.selectedLanes=lanes
    self.chartOffset=E:Clamp(self.chartOffset or 0,0,math.max(0,n*laneHeight-height))
    w.charts:SetVerticalScroll(self.chartOffset)
    self:DrawCharts(self.chartOffset,true)
    local scroll=_G["EasyThreatJournalChartsScrollBar"]
    if scroll then
        scroll:SetValue(E:Clamp(scroll:GetValue() or 0,0,math.max(0,n*laneHeight-height)))
        if n*laneHeight>height then scroll:Show() else scroll:Hide() end
    end
    w.charts:UpdateScrollChildRect()
    y=y+height+4
    for i=1,5 do
        local t=self.start+(self.finish-self.start)*(i-1)/4
        local x=62+560*(i-1)/4; local align="CENTER"
        if i==1 then align="LEFT" elseif i==5 then align="RIGHT"; x=x-62 else x=x-31 end
        at(w.axis[i],w,x,y,62,16); w.axis[i]:SetText(number(t).." s"); w.axis[i]:SetJustifyH(align)
        if self.compare and self.db.reference then
            at(w.refAxis[i],w,x,y+15,62,14); w.refAxis[i]:SetJustifyH(align)
            w.refAxis[i]:SetText(number(t/f.duration*self.db.reference.duration).." s"); w.refAxis[i]:Show()
        else w.refAxis[i]:Hide() end
    end
    y=y+(self.compare and self.db.reference and 32 or 18)
    at(w.seek,w,62,y,560,8); y=y+17
    at(w.rangeLabel,w,62,y,140,16); y=y+19
    at(w.range,w,62,y,560,6); y=y+19
    at(w.log,w,22,y); y=y+178
    at(w.footer,w,22,y); w:SetHeight(y+49)
    local fit=math.min(E.db.uiScale,(UIParent:GetWidth()-20)/660,(UIParent:GetHeight()-20)/w:GetHeight())
    w:SetScale(math.max(0.5,fit))
    w.compare.text:SetText(E:L("Show reference")); E:SetToggleState(w.compare,self.compare and self.db.reference)
    w.save.text:SetText(E:L("Save as new reference"))
    self:SetTime(self.moment or self.start); self:RenderLog(true)
end
function J:DrawCharts(offset,force)
    local w=self.window; if not w or not self.selectedLanes then return end
    self.chartOffset=offset
    local first=math.floor(offset/laneHeight)+1
    for slot=1,math.ceil(chartHeight/laneHeight)+1 do
        local index=first+slot-1; local lane=self.selectedLanes[index]; local row=w.lanes[slot]
        if lane then
            row=row or self:MakeLane(slot)
            at(row,w.chartChild,0,(index-1)*laneHeight)
            if force or row.lane~=lane then self:Plot(row,lane) end
            row:Show()
        elseif row then row:Hide() end
    end
end
function J:StartRangeDrag(kind)
    local x=GetCursorPosition(); self.timeDrag={kind=kind,x=x,a=self.start,b=self.finish}
end
function J:MoveRangeDrag()
    if E:Call(IsMouseButtonDown,"LeftButton")==false then self.timeDrag=nil; return end
    local d=self.timeDrag; local f=self.viewFight; local scale=self.window.range:GetEffectiveScale()
    local delta=(GetCursorPosition()-d.x)/scale/560*f.duration
    if d.kind=="start" then self.start=E:Clamp(d.a+delta,0,self.finish-math.min(.5,f.duration))
    elseif d.kind=="finish" then self.finish=E:Clamp(d.b+delta,self.start+math.min(.5,f.duration),f.duration)
    else local span=d.b-d.a; self.start=E:Clamp(d.a+delta,0,f.duration-span); self.finish=self.start+span end
    self:Render()
end
function J:SetTime(t)
    if not self.viewFight then return end
    self.moment=E:Clamp(t,self.start,self.finish); local w=self.window
    if not w then return end
    self.settingSeek=true; w.seek:SetMinMaxValues(self.start,self.finish); w.seek:SetValue(self.moment); self.settingSeek=nil
    w.rangeLabel:SetText(number(self.start).."–"..number(self.finish).." s")
    local duration=self.viewFight.duration; local a,b=self.start/duration*560,self.finish/duration*560
    w.rangeLabel:ClearAllPoints(); w.rangeLabel:SetPoint("BOTTOM",w.range,"TOPLEFT",E:Clamp((a+b)/2,70,490),5)
    w.rangeLabel:SetJustifyH("CENTER")
    at(w.range.selection,w.range,a,0,math.max(1,b-a),6)
    at(w.range.grips.start,w.range,a-5,-7); at(w.range.grips.finish,w.range,b-5,-7)
    for _,row in ipairs(w.lanes) do if row:IsShown() then at(row.guide,row.canvas,(self.moment-self.start)/math.max(.01,self.finish-self.start)*560,2,1,plotHeight-2) end end
    self:RenderLog(false)
end
function J:EventTip(ev)
    if not ev then return {} end
    local f=self.viewFight; local a=f.actors[ev.actor]; local target=f.actors[ev.target] or f.enemies[ev.target]
    local lines={ev.name or E:L(labels[ev.kind] or "Combat log"),number(ev.t).." s"}
    if a then table.insert(lines,a.name) end; if target then table.insert(lines,target.name) end
    if ev.amount then table.insert(lines,round(ev.amount).." "..E:L(ev.kind=="heal" and "Healing" or "Damage")) end
    if ev.effective then table.insert(lines,E:L("Effective healing")..": "..round(ev.effective)); table.insert(lines,E:L("Overhealing")..": "..round(ev.overheal)) end
    if ev.threat then table.insert(lines,E:L("Threat ability cast observed; its actual effect may differ.")) end
    if ev.crit then table.insert(lines,E:L("Critical hit (chance)")) end
    if ev.cd then table.insert(lines,E:L("Cooldown")..": "..round(ev.cd).." s") end
    if ev.kind=="aggro" and ev.q~="api" then table.insert(lines,E:L("Journal observed targets are not certain aggro")) end
    return lines
end
function J:RenderLog(rebuild)
    local f=self.viewFight; local w=self.window; if not f or not w then return end
    if rebuild then
        self.logEvents={}
        for _,ev in ipairs(f.events) do
            local actor=f.actors[ev.actor]; local prev=f.actors[ev.previous]; local target=f.actors[ev.target]
            local scope=not E.db.journalOwn or (actor and actor.own) or (prev and prev.own) or (target and target.own) or ev.kind=="death"
            if scope and E.db.journalFilters[ev.kind] and ev.t>=self.start and ev.t<=self.finish then table.insert(self.logEvents,ev) end
        end
        for key,b in pairs(w.log.filters) do self:Selected(b,E.db.journalFilters[key]) end
        w.log.child:SetHeight(math.max(125,table.getn(self.logEvents)*25)); w.log.scroll:UpdateScrollChildRect()
    end
    local nearest,distance
    for i,ev in ipairs(self.logEvents or {}) do local d=math.abs(ev.t-self.moment); if not distance or d<distance then nearest=i; distance=d end end
    self.nearestLog=nearest
    if nearest and (rebuild or self.lastLogMoment~=self.moment) then
        self.logOffset=E:Clamp((nearest-3)*25,0,math.max(0,table.getn(self.logEvents)*25-125))
        w.log.scroll:SetVerticalScroll(self.logOffset)
    end
    self:FillLog(self.logOffset or 0)
    self.lastLogMoment=self.moment
end
function J:FillLog(offset)
    local f=self.viewFight; local w=self.window
    if not f or not w or not self.logEvents then return end
    self.logOffset=offset
    local first=math.floor(offset/25)+1
    -- Six recycled buttons cover the five-line viewport, including partial rows.
    for slot=1,6 do
        local i=first+slot-1; local ev=self.logEvents[i]; local b=w.log.rows[slot]
        if ev then
            if not b then
                b=E:Box(w.log.child,576,25,nil,"Button"); b:RegisterForClicks("LeftButtonUp")
                b:SetScript("OnClick",function() if b.ev then J:SetTime(b.ev.t) end end)
                b.time=text(b,10); at(b.time,b,5,6,48,16)
                b.icon=b:CreateTexture(nil,"ARTWORK"); at(b.icon,b,55,5,15,15)
                b.label=text(b,11); at(b.label,b,77,5,398,18)
                b.amount=text(b,12); at(b.amount,b,482,4,87,19); b.amount:SetJustifyH("RIGHT")
                b.amount:SetShadowColor(0,0,0,1); b.amount:SetShadowOffset(1,-1)
                self:BindTip(b,function() return J:EventTip(b.ev) end); w.log.rows[slot]=b
            end
            b.ev=ev; at(b,w.log.child,0,(i-1)*25); b.time:SetText(number(ev.t).." s")
            self:SetIconTexture(b.icon,ev.icon or textures[ev.kind] or textures.healing)
            if E.db.journalLogIcons then b.icon:Show() else b.icon:Hide() end
            local a=f.actors[ev.actor]
            local caption=ev.name or E:L(labels[ev.kind] or "Combat log")
            if a and E.db.journalLogNames then caption=colored(E:ShortName(a.name,16),a).."  "..caption end
            b.amount:SetText(ev.amount and (round(ev.amount)..(ev.crit and " !" or "")) or "")
            local path=E:FontPath()
            b.amount:SetFont(path,ev.crit and 14 or 12,"OUTLINE")
            if ev.kind=="damage" then
                b.amount:SetTextColor(1,ev.crit and 0.36 or 0.53,ev.crit and 0.18 or 0.46)
            else b.amount:SetTextColor(0.48,0.93,0.60) end
            -- Independent bold-looking value; changing font never enlarges the entire log row.
            b.amount:SetShadowOffset(ev.crit and 1.5 or 1,-1)
            b.label:SetText(caption); b:Show()
            if i==self.nearestLog then b:SetBackdropColor(.24,.18,.09,.8); b:SetAlpha(1)
            else b:SetBackdropColor(0,0,0,0); b:SetAlpha(.7) end
            b:SetBackdropBorderColor(0,0,0,0)
        elseif b then b:Hide() end
    end
end
function E:BuildJournalSettings(pane)
    pane.refreshers={}
    self:Toggle(pane,"Enable combat journal","journalEnabled",85)
    self:Toggle(pane,"Show journal book","journalBook",120)
    self:Toggle(pane,"Player color legend","journalLegend",155)
    self:Toggle(pane,"Names in combat log","journalLogNames",190)
    self:Toggle(pane,"Icons in combat log","journalLogIcons",225)
    self:Toggle(pane,"Show overhealing","journalOverheal",260)
    self:Toggle(pane,"Graph headings","journalTitles",294)
    self:Place(pane,self:Button(pane,"Open combat journal",358,28,function() J:Show() end),16,334)
    self:Place(pane,self:Button(pane,"Journal book position",358,28,function() E:ShowPage("positions"); E.pages.positions.scope="journal"; E:UpdatePositions() end),16,370)
    table.insert(pane.refreshers,function() J:PositionBook(); if J.window and J.window:IsShown() then J:Render() end end)
end

function J:DamageActor(f)
    local key=E.db.journalOwn and "own" or "group"
    self.damageCache=self.damageCache or setmetatable({},{__mode="k"})
    self.damageCache[f]=self.damageCache[f] or {}
    local cache=self.damageCache[f][key]
    if cache and cache.fight==f and cache.duration==f.duration then return cache.actor end
    local a={name=E:L(E.db.journalOwn and "Me and pets" or "Group"),color={.94,.63,.38},damageLine={}}
    local events={}
    for _,ev in ipairs(f.events) do
        local actor=f.actors[ev.actor]
        if ev.kind=="damage" and (not E.db.journalOwn or actor and actor.own) then table.insert(events,ev) end
    end
    table.sort(events,function(a,b) return a.t<b.t end)
    local steps=math.ceil(f.duration/.5); local left,right,sum=1,1,0
    for i=0,steps do
        local t=math.min(f.duration,i*.5); local start=math.max(0,t-2)
        while events[right] and events[right].t<=t do sum=sum+(events[right].amount or 0); right=right+1 end
        while left<right and events[left].t<=start do sum=sum-(events[left].amount or 0); left=left+1 end
        table.insert(a.damageLine,{t=t,v=math.max(0,sum)/math.max(.5,t-start),q="observed"})
    end
    self.damageCache[f][key]={fight=f,duration=f.duration,actor=a}; return a
end
function J:PlotActors(lane,f)
    if lane.kind=="damage" then return {self:DamageActor(f)} end
    return self:Actors(f)
end

function J:EnemyTitle(enemy)
    local count,index=0,0
    for _,id in ipairs(self.viewFight and self.viewFight.enemyOrder or {}) do
        local candidate=self.viewFight.enemies[id]
        if candidate.name==enemy.name then count=count+1; if id==enemy.id then index=count end end
    end
    return enemy.name..(count>1 and index>0 and (" · "..index) or "")
end

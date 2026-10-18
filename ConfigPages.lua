local E=EasyThreat
function E:Input(parent,width)
    local input=self:Box(parent,width,23,nil,"EditBox")
    self:RegisterFont(input,11,"")
    input:SetAutoFocus(false); input:EnableMouse(true)
    input:SetScript("OnMouseDown",function() input:SetFocus() end)
    input:SetTextInsets(6,6,0,0); input:SetMaxLetters(48)
    input:SetTextColor(0.92,0.90,0.82)
    input:SetScript("OnEscapePressed",function() input:ClearFocus() end)
    return input
end
function E:LayoutChanged()
    self:PositionList(); self:PositionTarget(); self:PositionWindow()
    self:RefreshUI(); self:UpdatePositions()
    if self.journal and self.journal.window and self.journal.window:IsShown() then self.journal:Render() end
end
function E:ResetPositions()
    for _, rules in pairs(self.positionRules) do
        for _, rule in ipairs(rules) do self.db[rule[1]]=self.defaults[rule[1]] end
    end
    self.db.targetFree=false; self.db.windowX=0; self.db.windowY=40; self:LayoutChanged()
end
E.positionRules={
    journal={{"journalBookX","X from left",0,4000,5},{"journalBookY","Y from bottom",0,4000,5},
        {"journalBookSize","Book size",28,64,2}},
    list={{"x","X from left",-4000,4000,5},{"y","Y from top",-4000,4000,5},
        {"scale","Scale",0.6,1.6,0.05},{"enemyWidth","Enemy box width",100,200,5},{"maxRows","Visible rows",3,12,1}},
    target={{"targetX","X",-4000,4000,5,"spacing"},{"targetY","Y",-4000,4000,5,"spacing"},
        {"targetScale","Scale",0.6,1.6,0.05},{"targetWidth","Bar width",60,200,5},{"targetHeight","Bar height",8,24,1},
        {"targetPetGap","Pet gap",0,16,1,"spacing"},{"targetOtherGap","Gap to other players",0,24,1,"spacing"}},
    overhead={{"overheadX","Horizontal offset",-200,200,2},{"overheadY","Vertical offset",-100,150,2},
        {"overheadScale","Scale",0.6,1.6,0.05},{"barWidth","Bar width",60,140,2},{"barHeight","Bar height",8,18,1}},
    tooltip={{"tooltipHeight","Bar height",10,24,1},
        {"tooltipReferenceHeight","Tank/player height (%)",30,150,5},{"tooltipFont","Relative font size (%)",50,150,5},
        {"tooltipInset","Horizontal inset",4,24,1,"spacing"},{"tooltipGap","Gap above bar",0,24,1,"spacing"},
        {"tooltipBottom","Bottom inset",4,24,1,"spacing"},{"tooltipPetGap","Pet gap",0,16,1,"spacing"},
        {"tooltipOtherGap","Gap to other players",0,24,1,"spacing"}},
    pet={{"petWidth","Pet width (%)",50,100,2},{"petHeight","Pet height (%)",60,120,5},
        {"petGap","Pet gap",0,16,1},{"petIconSize","Pet icon size",6,20,1}}
}
function E:BuildPositions(pane)
    pane.scope="list"; pane.fields={}; pane.tooltipSection="bars"; pane.targetSection="bars"; pane.tooltipSections={}
    pane.scopeChoice=self:Place(pane,self:Dropdown(pane,358,{{"list","Enemy list"},{"target","Target frame"},
        {"overhead","Nameplates"},{"tooltip","Mouse tooltip"},{"pet","Pet bar"},{"journal","Journal book"}},
        function() return pane.scope end,function(key) pane.scope=key; E:UpdatePositions() end),16,85)
    for i,item in ipairs({{"bars","Bars"},{"spacing","Spacing"}}) do
        local key,label=item[1],item[2]
        pane.tooltipSections[key]=self:Place(pane,self:Button(pane,label,175,25,function()
            if pane.scope=="target" then pane.targetSection=key else pane.tooltipSection=key end
            E:UpdatePositions()
        end),16+(i-1)*183,119)
    end
    for i=1,6 do
        local row=CreateFrame("Frame",nil,pane)
        row:SetWidth(358); row:SetHeight(26); self:Place(pane,row,16,122+(i-1)*32)
        row.label=self:Text(row,10); row.label:SetPoint("LEFT",row,"LEFT",0,0); row.label:SetWidth(193)
        row.input=self:Input(row,80); row.input:SetPoint("RIGHT",row,"RIGHT",-32,0)
        local function apply(value)
            local rule=row.rule
            if not rule then return end
            if type(value)=="number" and value==value then
                value=E:Clamp(value,rule[3],rule[4])
                if rule[5]>=1 then value=math.floor(value+0.5) end
                E.db[rule[1]]=value
            end
            E:LayoutChanged()
        end
        row.input:SetScript("OnEnterPressed",function() apply(tonumber(row.input:GetText())); row.input:ClearFocus() end)
        row.input:SetScript("OnEditFocusLost",function() apply(tonumber(row.input:GetText())) end)
        row.input:SetScript("OnEscapePressed",function() E:UpdatePositions(); row.input:ClearFocus() end)
        row.minus=self:Button(row,"-",23,23,function() if row.rule then apply(E.db[row.rule[1]]-row.rule[5]) end end)
        row.minus:SetPoint("RIGHT",row.input,"LEFT",-5,0)
        row.plus=self:Button(row,"+",23,23,function() if row.rule then apply(E.db[row.rule[1]]+row.rule[5]) end end)
        row.plus:SetPoint("RIGHT",row,"RIGHT",0,0)
        pane.fields[i]=row
    end
    pane.anchor=self:Place(pane,self:Button(pane,"",358,25,function()
        E.db.targetFree=not E.db.targetFree
        if E.db.targetFree then
            local ratio=E.target:GetEffectiveScale()/UIParent:GetEffectiveScale()
            E.db.targetX=E.target:GetLeft()*ratio; E.db.targetY=E.target:GetTop()*ratio-UIParent:GetHeight()
        else E.db.targetX=25; E.db.targetY=-4 end
        E:LayoutChanged()
    end),16,285)
    pane.anchor.state=self:Text(pane.anchor,10); pane.anchor.state:SetPoint("RIGHT",pane.anchor,"RIGHT",-9,0)
    pane.anchor.text:SetWidth(275); pane.anchor.text:ClearAllPoints(); pane.anchor.text:SetPoint("LEFT",pane.anchor,"LEFT",9,0)
    pane.tooltipAlways=self:Place(pane,self:Button(pane,"Always show",174,25,function()
        E.db.tooltipAlways=not E.db.tooltipAlways; E.tooltipSample=nil; E.pairVisibility={}; E:LayoutChanged()
    end),16,351)
    pane.tooltipAlways.state=self:Text(pane.tooltipAlways,10)
    pane.tooltipAlways.state:SetPoint("RIGHT",pane.tooltipAlways,"RIGHT",-9,0)
    pane.tooltipAlways.text:SetWidth(118); pane.tooltipAlways.text:ClearAllPoints()
    pane.tooltipAlways.text:SetPoint("LEFT",pane.tooltipAlways,"LEFT",9,0)
    local enter,leave=pane.tooltipAlways:GetScript("OnEnter"),pane.tooltipAlways:GetScript("OnLeave")
    self:Tooltip(pane.tooltipAlways,self:L("Always show tooltip help"),300)
    local tipEnter,tipLeave=pane.tooltipAlways:GetScript("OnEnter"),pane.tooltipAlways:GetScript("OnLeave")
    pane.tooltipAlways:SetScript("OnEnter",function() enter(); tipEnter() end)
    pane.tooltipAlways:SetScript("OnLeave",function() leave(); tipLeave() end)
    pane.tooltipDynamicWidth=self:Place(pane,self:Button(pane,"Dynamic width",175,25,function()
        E.db.tooltipDynamicWidth=not E.db.tooltipDynamicWidth; E:LayoutChanged()
    end),199,351)
    pane.tooltipDynamicWidth.state=self:Text(pane.tooltipDynamicWidth,10)
    pane.tooltipDynamicWidth.state:SetPoint("RIGHT",pane.tooltipDynamicWidth,"RIGHT",-9,0)
    pane.tooltipDynamicWidth.text:SetWidth(119); pane.tooltipDynamicWidth.text:ClearAllPoints()
    pane.tooltipDynamicWidth.text:SetPoint("LEFT",pane.tooltipDynamicWidth,"LEFT",9,0)
    local widthEnter,widthLeave=pane.tooltipDynamicWidth:GetScript("OnEnter"),pane.tooltipDynamicWidth:GetScript("OnLeave")
    self:Tooltip(pane.tooltipDynamicWidth,self:L("Dynamic tooltip width help"),300)
    local widthTipEnter,widthTipLeave=pane.tooltipDynamicWidth:GetScript("OnEnter"),pane.tooltipDynamicWidth:GetScript("OnLeave")
    pane.tooltipDynamicWidth:SetScript("OnEnter",function() widthEnter(); widthTipEnter() end)
    pane.tooltipDynamicWidth:SetScript("OnLeave",function() widthLeave(); widthTipLeave() end)
    pane.reset=self:Place(pane,self:Button(pane,"Reset position",358,25,function()
        for _,rule in ipairs(E.positionRules[pane.scope]) do E.db[rule[1]]=E.defaults[rule[1]] end
        if pane.scope=="target" then E.db.targetFree=false end
        E:LayoutChanged()
    end),16,318)
    pane.lock=self:Place(pane,self:Button(pane,"Allow dragging",358,25,function()
        E.db.locked=not E.db.locked; E:LayoutChanged()
    end),16,351)
    pane.lock.state=self:Text(pane.lock,10); pane.lock.state:SetPoint("RIGHT",pane.lock,"RIGHT",-9,0)
    pane.lock.text:SetWidth(275); pane.lock.text:ClearAllPoints(); pane.lock.text:SetPoint("LEFT",pane.lock,"LEFT",9,0)
    self:BuildPreviewButton(pane)
end
function E:UpdatePositions()
    self:UpdatePreviewButtons()
    local pane=self.pages and self.pages.positions
    if not pane then return end
    self:UpdateDropdown(pane.scopeChoice)
    local sectioned=pane.scope=="tooltip" or pane.scope=="target"
    local section=pane.scope=="target" and pane.targetSection or pane.tooltipSection
    local rules={}
    for _,rule in ipairs(self.positionRules[pane.scope]) do
        if not sectioned or (rule[6] or "bars")==section then table.insert(rules,rule) end
    end
    for key,button in pairs(pane.tooltipSections) do
        self:SetToggleState(button,key==section)
        button.text:SetText(self:L(key=="bars" and "Bars" or "Spacing"))
        if sectioned then button:Show() else button:Hide() end
    end
    for i,row in ipairs(pane.fields) do
        row.rule=rules[i]
        if row.rule then
            row:ClearAllPoints(); self:Place(pane,row,16,(sectioned and 155 or 122)+(i-1)*32)
            row.label:SetText(self:L(row.rule[2]))
            row.input:SetText(string.format(row.rule[5]<1 and "%.2f" or "%d",self.db[row.rule[1]]))
            row:Show()
        else row:Hide() end
    end
    pane.anchor.text:SetText(self:L("Anchor: target frame"))
    self:SetToggleState(pane.anchor,not self.db.targetFree)
    if pane.scope=="target" then pane.anchor:Show() else pane.anchor:Hide() end
    pane.tooltipAlways.text:SetText(self:L("Always show"))
    pane.tooltipAlways.tip=self:L("Always show tooltip help")
    self:SetToggleState(pane.tooltipAlways,self.db.tooltipAlways)
    if pane.scope=="tooltip" then pane.tooltipAlways:Show() else pane.tooltipAlways:Hide() end
    pane.tooltipDynamicWidth.text:SetText(self:L("Dynamic width"))
    pane.tooltipDynamicWidth.tip=self:L("Dynamic tooltip width help")
    self:SetToggleState(pane.tooltipDynamicWidth,self.db.tooltipDynamicWidth)
    if pane.scope=="tooltip" then pane.tooltipDynamicWidth:Show() else pane.tooltipDynamicWidth:Hide() end
    pane.lock.text:SetText(self:L("Allow dragging")); self:SetToggleState(pane.lock,not self.db.locked)
    -- These two HUDs have independent screen positions. The other controls
    -- adjust offsets/sizes within their nameplate, tooltip or parent bar.
    if pane.scope=="list" or pane.scope=="target" or pane.scope=="journal" then pane.lock:Show() else pane.lock:Hide() end
    pane.preview.text:SetText(self:L("Preview")); self:SetToggleState(pane.preview,self.layoutPreview)
end
function E:ColorLabel(key)
    local member=self:Member(key)
    if member then return member.name .. (member.pet and " (" .. member.owner .. ")" or "") end
    return key
end
function E:EditColor(key)
    if not ColorPickerFrame then return end
    local previous=self.db.colors[key]
    local color=self:IdentityColor(self:Member(key) or {key=key})
    self.colorEdit=nil
    ColorPickerFrame.func=nil; ColorPickerFrame.cancelFunc=nil; ColorPickerFrame:Hide()
    ColorPickerFrame:SetColorRGB(unpack(color)); ColorPickerFrame.hasOpacity=false
    local edit={key=key}; self.colorEdit=edit
    ColorPickerFrame.func=function()
        if E.colorEdit~=edit then return end
        local r,g,b=ColorPickerFrame:GetColorRGB()
        E.db.colors[key]={r,g,b}; E:UpdateColors(); E:RefreshUI()
    end
    ColorPickerFrame.cancelFunc=function()
        if E.colorEdit~=edit then return end
        E.colorEdit=nil; E.db.colors[key]=previous; E:UpdateColors(); E:RefreshUI()
    end
    ColorPickerFrame:Show()
end
function E:AddColor(name)
    local _,_,key=string.find(name or "","^%s*(.-)%s*$")
    if not key or key=="" or string.find(key,"[%c|]") then self:Print(self:L("Enter a player name")); return end
    for _, member in ipairs(self.roster) do
        if string.lower(member.key)==string.lower(key) then key=member.key; break end
    end
    for saved in pairs(self.db.colors) do
        if string.lower(saved)==string.lower(key) then key=saved; break end
    end
    if not self.db.colors[key] then
        local color=self:IdentityColor(self:Member(key) or {key=key})
        self.db.colors[key]={color[1],color[2],color[3]}
    end
    -- Adding a name is complete before editing its color. Cancel restores the
    -- saved color, never silently removes the identity just added.
    self:UpdateColors()
    local pane=self.pages and self.pages.colors
    if pane then
        for i,saved in ipairs(pane.keys) do
            if saved==key then pane.offset=math.max(0,i-table.getn(pane.rows)); break end
        end
        self:UpdateColors()
    end
    self:RefreshUI(); self:EditColor(key)
    return key
end
function E:DeleteColor(key)
    if not key then return end
    if self.colorEdit and self.colorEdit.key==key then
        self.colorEdit=nil
        ColorPickerFrame.func=nil; ColorPickerFrame.cancelFunc=nil; ColorPickerFrame:Hide()
    end
    if self.db.colors[key] then self.deletedColor={key=key,color=self.db.colors[key]} end
    self.db.colors[key]=nil; self:UpdateColors(); self:RefreshUI()
end
function E:BuildColors(pane)
    pane.rows={}; pane.offset=0; pane.rosterIndex=1; pane.refreshers={}
    pane.nameInput=self:Place(pane,self:Input(pane,171),16,79)
    pane.nameInput:SetText("")
    local function add()
        if E:AddColor(pane.nameInput:GetText()) then pane.nameInput:SetText(""); pane.nameInput:ClearFocus() end
    end
    pane.add=self:Place(pane,self:Button(pane,"Add name",171,24,function()
        add()
    end),203,79)
    pane.nameInput:SetScript("OnEnterPressed",add)
    pane.group=self:Place(pane,self:Button(pane,"",358,23,function()
        local member=E.roster[pane.rosterIndex] or E.roster[1]
        if member then pane.nameInput:SetText(member.key) end
        pane.rosterIndex=math.mod(pane.rosterIndex,math.max(1,table.getn(E.roster)))+1
        E:UpdateColors()
    end),16,111)
    local title=self:Label(pane,"Saved colors",10)
    title:SetPoint("TOPLEFT",pane,"TOPLEFT",16,-149)
    pane.empty=self:Label(pane,"No custom colors",10)
    pane.empty:SetPoint("TOPLEFT",pane,"TOPLEFT",16,-177); pane.empty:SetWidth(358)
    for i=1,7 do
        local row=CreateFrame("Frame",nil,pane)
        row:SetWidth(358); row:SetHeight(24); self:Place(pane,row,16,170+(i-1)*27)
        row.text=self:Text(row,11); row.text:SetPoint("LEFT",row,"LEFT",0,0); row.text:SetWidth(190)
        row.color=self:Button(row,"Color",65,23,function() if row.key then E:EditColor(row.key) end end)
        row.color:SetPoint("RIGHT",row,"RIGHT",-85,0)
        row.delete=self:Button(row,"Delete",78,23,function() E:DeleteColor(row.key) end)
        row.delete.text:SetTextColor(0.90,0.57,0.49)
        row.delete:SetPoint("RIGHT",row,"RIGHT",0,0)
        pane.rows[i]=row
    end
    pane:EnableMouseWheel(true)
    pane:SetScript("OnMouseWheel",function()
        pane.offset=E:Clamp(pane.offset-(arg1 or 0),0,math.max(0,table.getn(pane.keys or {})-7)); E:UpdateColors()
    end)
    pane.alwaysColors=self:Toggle(pane,"Always use player colors","alwaysPlayerColors",375)
    local enter,leave=pane.alwaysColors:GetScript("OnEnter"),pane.alwaysColors:GetScript("OnLeave")
    self:Tooltip(pane.alwaysColors,self:L("Player color mode help"),300)
    local tipEnter,tipLeave=pane.alwaysColors:GetScript("OnEnter"),pane.alwaysColors:GetScript("OnLeave")
    pane.alwaysColors:SetScript("OnEnter",function() if enter then enter() end; tipEnter() end)
    pane.alwaysColors:SetScript("OnLeave",function() if leave then leave() end; tipLeave() end)
    pane.undo=self:Place(pane,self:Button(pane,"Undo deletion",171,24,function()
        if E.deletedColor then
            E.db.colors[E.deletedColor.key]=E.deletedColor.color; E.deletedColor=nil
            E:UpdateColors(); E:RefreshUI()
        end
    end),203,412)

end
function E:UpdateColors()
    local pane=self.pages and self.pages.colors
    if not pane then return end
    local keys={}
    for key,color in pairs(self.db.colors) do
        if type(key)=="string" and type(color)=="table" then table.insert(keys,key) end
    end
    table.sort(keys); pane.keys=keys
    pane.offset=self:Clamp(pane.offset or 0,0,math.max(0,table.getn(keys)-7))
    for i,row in ipairs(pane.rows) do
        row.key=keys[i+pane.offset]
        if row.key then
            row.text:SetText(self:ShortName(self:ColorLabel(row.key),25))
            local color=self:IdentityColor(self:Member(row.key) or {key=row.key})
            row.text:SetTextColor(unpack(color)); row.color.border=color; self:PaintButton(row.color); row:Show()
        else row:Hide() end
    end
    if table.getn(keys)==0 then pane.empty:Show() else pane.empty:Hide() end
    if self.deletedColor then pane.undo:Show() else pane.undo:Hide() end
    local member=self.roster[pane.rosterIndex] or self.roster[1]
    pane.group.text:SetText(member and self:L("Use %s",self:ShortName(self:ColorLabel(member.key),26)) or self:L("No group"))
    for _,refresh in ipairs(pane.refreshers or {}) do refresh() end

end

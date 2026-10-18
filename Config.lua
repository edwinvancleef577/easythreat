local E=EasyThreat
function E:PaintButton(button)
    local c=button.faceColor
    local factor=button.pressed and 0.65 or 1
    local border=button.hovered and {0.88,0.72,0.35} or button.border or self.colors.bronze
    -- Explicit RGBA on every path, including first creation and parent OnShow.
    button:SetBackdropColor(c[1]*factor,c[2]*factor,c[3]*factor,1)
    button:SetBackdropBorderColor(border[1],border[2],border[3],1)
    button.fill:SetTexture(c[1]*factor,c[2]*factor,c[3]*factor,1)
    button.fill:SetAlpha(1); button.fill:Show()
    button.sheen:SetVertexColor(c[1],c[2],c[3],1)
    button.downFace:SetVertexColor(c[1]*0.65,c[2]*0.65,c[3]*0.65,1)
    for _,texture in ipairs({button.fill,button.sheen,button.downFace}) do
        texture:SetWidth(math.max(1,button:GetWidth()-2))
        texture:SetHeight(math.max(1,button:GetHeight()-2))
        texture:SetAlpha(1)
    end
    if button.pressed then
        button.topEdge:SetVertexColor(0,0,0,0.65)
        button.bottomEdge:SetVertexColor(1,0.89,0.64,0.18)
    else
        button.topEdge:SetVertexColor(1,0.89,0.64,0.27)
        button.bottomEdge:SetVertexColor(0,0,0,0.70)
    end
end
function E:Button(parent,text,width,height,callback)
    local button=self:Box(parent,width,height or 24,nil,"Button")
    button.bg=button
    button.faceColor={0.24,0.21,0.15}
    -- An opaque solid base does not depend on a patched/missing statusbar asset.
    button.fill=button:CreateTexture(nil,"BACKGROUND")
    button.fill:SetPoint("CENTER",button,"CENTER",0,0)
    local function face()
        local texture=button:CreateTexture(nil,"ARTWORK")
        texture:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
        texture:SetPoint("CENTER",button,"CENTER",0,0)
        return texture
    end
    button.sheen=face(); button.downFace=face()
    -- Use the client's normal/pushed texture slots, as UIPanelButtonTemplate
    -- does, rather than relying on an unattached decorative artwork layer.
    button:SetNormalTexture(button.sheen); button:SetPushedTexture(button.downFace)
    -- Native textures: subtle raised edges, with the bevel reversed while pressed.
    local function edge(anchor,offset,r,g,b,alpha)
        local texture=button:CreateTexture(nil,"OVERLAY")
        texture:SetTexture("Interface\\Buttons\\WHITE8X8")
        texture:SetHeight(1)
        texture:SetPoint(anchor.."LEFT",button,anchor.."LEFT",2,offset)
        texture:SetPoint(anchor.."RIGHT",button,anchor.."RIGHT",-2,offset)
        texture:SetVertexColor(r,g,b,alpha)
        return texture
    end
    button.topEdge=edge("TOP",-2,1,0.89,0.64,0.27)
    button.bottomEdge=edge("BOTTOM",2,0,0,0,0.70)
    button.shadow=edge("BOTTOM",-1,0,0,0,0.40)
    button:RegisterForClicks("LeftButtonUp")
    -- Keep decoration separate from the client's press/release state. Forcing
    -- NORMAL from OnMouseUp can consume the click before OnClick is dispatched.
    button:SetScript("OnMouseDown",function()
        button.pressed=true; E:PaintButton(button)
    end)
    local function release()
        button.pressed=nil; E:PaintButton(button)
    end
    button:SetScript("OnMouseUp",release)
    local function reset() button.hovered=nil; release() end
    button:SetScript("OnShow",reset)
    button:SetScript("OnHide",reset)
    button:SetScript("OnSizeChanged",function() E:PaintButton(button) end)
    button.text=self:Text(button,11)
    button.text:SetShadowColor(0,0,0,0.85); button.text:SetShadowOffset(1,-1)
    button.text:SetWidth(width-12); button.text:SetHeight(height or 24)
    button.text:SetJustifyH("CENTER"); button.text:SetJustifyV("MIDDLE")
    button.text:SetPoint("CENTER",button,"CENTER",0,0)
    self:BindText(button.text,text)
    button:SetScript("OnClick",callback)
    button:SetScript("OnEnter",function() button.hovered=true; E:PaintButton(button) end)
    button:SetScript("OnLeave",reset)
    reset()
    return button
end
function E:CloseDropdown()
    if self.dropdownLayer then self.dropdownLayer:Hide() end
    self.dropdownOwner=nil
end
function E:OpenDropdown(button)
    if self.dropdownLayer and self.dropdownLayer:IsShown() and self.dropdownOwner==button then self:CloseDropdown(); return end
    if not self.dropdownLayer then
        local layer=CreateFrame("Button",nil,UIParent)
        layer:SetAllPoints(UIParent); layer:SetFrameStrata("FULLSCREEN_DIALOG")
        layer:RegisterForClicks("LeftButtonUp"); layer:Hide()
        layer:EnableMouse(true); layer:SetScript("OnClick",function() E:CloseDropdown() end)
        self.dropdownLayer=layer
        local menu=self:Box(layer,180,24)
        menu:SetFrameLevel(layer:GetFrameLevel()+1); menu:EnableMouse(true)
        menu:SetBackdropColor(0.05,0.05,0.05,1)
        menu.rows={}; self.dropdownMenu=menu
    end
    local menu=self.dropdownMenu
    self.dropdownOwner=button
    -- Make hit order explicit on clients/UI skins that alter inherited levels.
    self.dropdownLayer:SetFrameLevel(self.window:GetFrameLevel()+10)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetFrameLevel(self.dropdownLayer:GetFrameLevel()+1)
    local options=type(button.options)=="function" and button.options() or button.options
    local width=math.max(180,button:GetWidth())
    menu:SetScale(self.window:GetEffectiveScale()/UIParent:GetEffectiveScale())
    menu:SetWidth(width); menu:SetHeight(table.getn(options)*25+8); menu:ClearAllPoints()
    local scale=menu:GetEffectiveScale()/UIParent:GetEffectiveScale()
    local top=button:GetTop()*button:GetEffectiveScale()/UIParent:GetEffectiveScale()
    if top-menu:GetHeight()*scale<10 then
        menu:SetPoint("BOTTOMRIGHT",button,"TOPRIGHT",0,3)
    else menu:SetPoint("TOPRIGHT",button,"BOTTOMRIGHT",0,-3) end
    for i,item in ipairs(options) do
        if not menu.rows[i] then
            local row
            row=self:Button(menu,"",width-8,24,function()
                -- Hiding the popup fires nested callbacks in Vanilla. Capture
                -- the choice before those callbacks change globals or pages.
                local owner,value=row.owner,row.value
                E:CloseDropdown()
                if owner then owner.choose(value); E:UpdateDropdown(owner) end
            end)
            menu.rows[i]=row
        end
        local row=menu.rows[i]
        row.owner=button
        row:SetFrameStrata("FULLSCREEN_DIALOG"); row:SetFrameLevel(menu:GetFrameLevel()+1)
        row.value=item[1]; row:SetWidth(width-8); row.text:SetWidth(width-20)
        row.text:SetText(self:L(item[2])); row.text:SetJustifyH("LEFT")
        row.text:SetTextColor(unpack(button.value()==item[1] and {0.94,0.80,0.46} or {0.88,0.87,0.80}))
        row:SetPoint("TOPLEFT",menu,"TOPLEFT",4,-4-(i-1)*25); row:Show()
    end
    for i=table.getn(options)+1,table.getn(menu.rows) do menu.rows[i]:Hide() end
    self.dropdownLayer:Show(); menu:Show()
end
function E:Dropdown(parent,width,options,value,choose)
    local button
    button=self:Button(parent,"",width,25,function() E:OpenDropdown(button) end)
    button.options=options; button.value=value; button.choose=choose
    button.arrow=button:CreateTexture(nil,"OVERLAY")
    button.arrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
    button.arrow:SetWidth(16); button.arrow:SetHeight(16)
    button.arrow:SetPoint("RIGHT",button,"RIGHT",-3,0)
    button.text:SetWidth(width-28); button.text:ClearAllPoints()
    button.text:SetPoint("LEFT",button,"LEFT",7,0); button.text:SetJustifyH("LEFT")
    self:UpdateDropdown(button)
    return button
end
function E:UpdateDropdown(button)
    local options=type(button.options)=="function" and button.options() or button.options
    for _, item in ipairs(options) do if item[1]==button.value() then button.text:SetText(self:L(item[2])); return end end
    button.text:SetText("?")
end
function E:InitConfig()
    self.window=self:Box(UIParent,410,465,"EasyThreatWindow")
    -- Same built-in Blizzard dialog textures used by AtlasLoot TW's options frame.
    self.window:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",tile=true,tileSize=32,edgeSize=32,
        insets={left=11,right=12,top=12,bottom=11}})
    self.window:SetBackdropColor(1,1,1,1); self.window:SetBackdropBorderColor(1,1,1,1)
    local header=self.window:CreateTexture(nil,"ARTWORK")
    header:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    header:SetWidth(256); header:SetHeight(64); header:SetPoint("TOP",self.window,"TOP",0,12)
    self.window.title=self:Text(self.window,14)
    self.window.title:SetWidth(220); self.window.title:SetHeight(24)
    self.window.title:SetJustifyH("CENTER")
    self.window.title:SetPoint("CENTER",header,"CENTER",0,12); self.window.title:SetJustifyV("MIDDLE"); self.window.title:SetText("EasyThreat")
    self.window.title:SetTextColor(0.95,0.82,0.52)
    self:PositionWindow()
    self.window:SetFrameStrata("DIALOG")
    self.window:SetMovable(true); self.window:EnableMouse(true); self.window:RegisterForDrag("LeftButton")
    self.window:SetScript("OnDragStart",function() E.window:StartMoving() end)
    self.window:SetScript("OnDragStop",function()
        E.window:StopMovingOrSizing()
        local x,y=E.window:GetCenter(); local cx,cy=UIParent:GetCenter()
        local ratio=E.window:GetEffectiveScale()/UIParent:GetEffectiveScale()
        E.db.windowX=x*ratio-cx; E.db.windowY=y*ratio-cy; E:PositionWindow()
    end)
    self.window:SetScript("OnHide",function()
        if E.recordingChoice then E.recordingChoice:Hide() end
        E:CloseDropdown(); E:HideSettingsExport(); E.layoutPreview=nil
        E:StopHUDDrag(E.list); E:StopHUDDrag(E.target); E:RefreshUI()
    end)
    local close=CreateFrame("Button","EasyThreatCloseButton",self.window,"UIPanelCloseButton")
    close:SetWidth(32); close:SetHeight(32)
    close:SetPoint("TOPRIGHT",self.window,"TOPRIGHT",-8,-6)
    close:SetScript("OnClick",function() E.window:Hide() end)
    self.window.close=close
    self.navigation=self:Dropdown(self.window,172,{{"roles","Roles"},{"settings","Displays"},
        {"list","Enemy list"},{"filters","Enemy filters"},{"colors","Player colors"},{"spells","Skill tooltips"},{"journal","Combat journal"},{"positions","Positions"},{"diagnostics","Diagnostics"}},
        function() return E.window.page or "roles" end,function(page) E:ShowPage(page) end)
    self.navigation:SetPoint("TOPRIGHT",self.window,"TOPRIGHT",-26,-44)
    self.navigation:SetFrameLevel(self.window:GetFrameLevel()+4)
    self.window.heading=self:Text(self.window,13)
    self.window.heading:SetPoint("TOPLEFT",self.window,"TOPLEFT",26,-49)
    self.window.heading:SetWidth(173); self.window.heading:SetHeight(22)
    self.window.heading:SetTextColor(0.90,0.77,0.47)
    if UISpecialFrames then table.insert(UISpecialFrames,"EasyThreatWindow") end
    self.window:Hide()
end
function E:PositionWindow()
    if not self.window then return end
    -- Keep the entire dialog accessible even on a small viewport.
    local fit=math.min((UIParent:GetWidth()-16)/self.window:GetWidth(),(UIParent:GetHeight()-30)/self.window:GetHeight())
    local scale=math.min(self.db.uiScale,math.max(0.3,fit))
    self.window:SetScale(scale)
    local maxX=math.max(0,(UIParent:GetWidth()-self.window:GetWidth()*scale)/2-8)
    local maxY=math.max(0,(UIParent:GetHeight()-self.window:GetHeight()*scale)/2-15)
    self.db.windowX=self:Clamp(self.db.windowX,-maxX,maxX); self.db.windowY=self:Clamp(self.db.windowY,-maxY,maxY)
    self.window:ClearAllPoints()
    self.window:SetPoint("CENTER",UIParent,"CENTER",self.db.windowX/scale,self.db.windowY/scale)
end
E.pageTitles={spells="Skill tooltips",journal="Combat journal",roles="Roles",settings="Displays",colors="Player colors",positions="Positions",list="Enemy list",filters="Enemy filters",diagnostics="Diagnostics"}
function E:ShowPage(page)
    if not self.db or not self.window then return end
    if page=="appearance" then page="settings" end
    if not self.pageTitles[page] then page="roles" end
    if self.recordingChoice then self.recordingChoice:Hide() end
    self:HideSettingsExport()
    if page~="positions" and page~="list" then self.layoutPreview=nil end
    if self.demo then self:ToggleDemo() end
    self:RefreshRoster(); self:CloseDropdown(); self:PositionWindow()
    self.window.page=page; self.pages=self.pages or {}
    if not self.pages[page] then
        local pane=CreateFrame("Frame",nil,self.window)
        pane:SetPoint("TOPLEFT",self.window,"TOPLEFT",10,0); pane:SetWidth(390); pane:SetHeight(455)
        self.pages[page]=pane
        if page=="roles" then self:BuildRoles(pane)
        elseif page=="colors" then self:BuildColors(pane)
        elseif page=="positions" then self:BuildPositions(pane)
        elseif page=="diagnostics" then self:BuildDiagnostics(pane)
        elseif page=="list" then self:BuildListSettings(pane)
        elseif page=="filters" then self:BuildFilters(pane)
        elseif page=="journal" then self:BuildJournalSettings(pane)
        elseif page=="spells" then self:BuildSpellSettings(pane)
        else self:BuildSettings(pane) end
    end
    for key,pane in pairs(self.pages) do if key==page then pane:Show() else pane:Hide() end end
    self.window.heading:SetText(self:L(self.pageTitles[page])); self:UpdateDropdown(self.navigation)
    if page=="roles" then self:UpdateRoles()
    elseif page=="colors" then self:UpdateColors()
    elseif page=="positions" then self:UpdatePositions()
    elseif page=="diagnostics" then self:UpdateDiagnostics()
    else for _, refresh in ipairs(self.pages[page].refreshers or {}) do refresh() end end
    self.window:Show(); self:RefreshUI()
end
function E:Place(parent,control,x,y)
    control:SetPoint("TOPLEFT",parent,"TOPLEFT",x,-y); return control
end
function E:BuildRoles(pane)
    pane.rows={}; pane.offset=0
    local options={{"damage","Damage"},{"heal","Healer"},{"tank","Tank"}}
    for i=1,10 do
        local row=CreateFrame("Frame",nil,pane)
        row:SetWidth(358); row:SetHeight(31); self:Place(pane,row,16,87+(i-1)*33)
        row.text=self:Text(row,12); row.text:SetPoint("LEFT",row,"LEFT",0,0); row.text:SetWidth(222); row.text:SetHeight(28)
        row.button=self:Dropdown(row,122,options,function() return row.member and E:Role(row.member.key) or "damage" end,
            function(role) if row.member then E:SetRole(row.member.key,role) end end)
        row.button:SetPoint("RIGHT",row,"RIGHT",0,0); pane.rows[i]=row
    end
    pane:EnableMouseWheel(true)
    pane:SetScript("OnMouseWheel",function() E:CloseDropdown(); pane.offset=pane.offset-(arg1 or 0); E:UpdateRoles() end)
    pane.previous=self:Place(pane,self:Button(pane,"<",32,22,function() E:CloseDropdown(); pane.offset=pane.offset-10; E:UpdateRoles() end),16,421)
    pane.next=self:Place(pane,self:Button(pane,">",32,22,function() E:CloseDropdown(); pane.offset=pane.offset+10; E:UpdateRoles() end),342,421)
    pane.range=self:Text(pane,10); pane.range:SetPoint("TOP",pane,"TOP",0,-426)
end
function E:UpdateRoles()
    local pane=self.pages and self.pages.roles
    if not pane then return end
    local count=table.getn(self.roster)
    pane.offset=self:Clamp(pane.offset or 0,0,math.max(0,count-10))
    if count>10 then
        pane.previous:Show(); pane.next:Show(); pane.range:Show()
        pane.range:SetText(string.format("%d–%d / %d",pane.offset+1,math.min(count,pane.offset+10),count))
    else pane.previous:Hide(); pane.next:Hide(); pane.range:Hide() end
    for i,row in ipairs(pane.rows) do
        local member=self.roster[i+pane.offset]
        if self.dropdownOwner==row.button and (not member or not row.member or
            member.key~=row.member.key or member.roleKey~=row.member.roleKey) then self:CloseDropdown() end
        row.member=member
        if member then
            row.text:SetText(self:ShortName(member.name,18) .. (member.pet and " (" .. self:ShortName(member.owner,10) .. ")" or ""))
            row.text:SetTextColor(unpack(self:IdentityColor(member))); self:UpdateDropdown(row.button)
            row.button.border=self:IsTank(member.key) and self.colors.green or self.colors.bronze
            self:PaintButton(row.button); row:Show()
        else row:Hide() end
    end
end
function E:Toggle(pane,label,key,y)
    local button
    button=self:Button(pane,label,358,25,function()
        self.db[key]=not self.db[key]; self:RefreshUI()
        if pane.refreshers then for _, f in ipairs(pane.refreshers) do f() end end
    end)
    button.text:ClearAllPoints(); button.text:SetPoint("LEFT",button,"LEFT",9,0)
    button.text:SetWidth(297); button.text:SetJustifyH("LEFT")
    button.state=self:Text(button,10); button.state:SetPoint("RIGHT",button,"RIGHT",-9,0)
    self:Place(pane,button,16,y)
    pane.toggles=pane.toggles or {}; pane.toggles[key]=button
    table.insert(pane.refreshers,function()
        E:SetToggleState(button,self.db[key])
    end)
    return button
end
function E:Stepper(pane,label,key,low,high,step,y,format)
    local text=self:Text(pane,11); text:SetPoint("TOPLEFT",pane,"TOPLEFT",16,-y-6); text:SetWidth(288); text:SetHeight(25)
    local function change(delta)
        self.db[key]=self:Clamp(self.db[key]+delta,low,high); self:LayoutChanged()
        for _, f in ipairs(pane.refreshers) do f() end
    end
    self:Place(pane,self:Button(pane,"-",24,24,function() change(-step) end),318,y)
    self:Place(pane,self:Button(pane,"+",24,24,function() change(step) end),350,y)
    table.insert(pane.refreshers,function() text:SetText(self:L(label) .. ": " .. string.format(format or "%d",self.db[key])) end)
    return text
end
function E:SetToggleState(button,on)
    button.border=on and self.colors.green or self.colors.neutral
    button.faceColor=on and {0.08,0.22,0.10} or {0.09,0.095,0.09}
    self:PaintButton(button)
    local text=button.state or button.text
    text:SetText(self:L(on and "On" or "Off")); text:SetTextColor(unpack(on and {0.73,1,0.72} or {0.69,0.67,0.61}))
end
function E:BuildSettings(pane)
    pane.refreshers={}
    self:Toggle(pane,"Enable EasyThreat","enabled",85)
    local function dropdown(label,y,options,value,choose)
        local title=E:Label(pane,label,11); title:SetPoint("TOPLEFT",pane,"TOPLEFT",16,-y-6); title:SetWidth(135)
        local control=E:Dropdown(pane,206,options,value,choose); E:Place(pane,control,168,y)
        table.insert(pane.refreshers,function() E:UpdateDropdown(control) end)
        return control
    end
    pane.language=dropdown("Language",117,self.languageOptions,function() return E.db.language end,function(value) E:SetLanguage(value) end)
    pane.font=dropdown("Font",149,function() return E:AvailableFonts() end,function() return E:FontKey() end,function(value)
        E.db.font=value; E:ApplyFonts(); E:RefreshUI()
    end)
    self:Stepper(pane,"Interface scale","uiScale",0.7,1.5,0.05,181,"%.2f")
    local threshold=self:Stepper(pane,"Show threat from (%)","threshold",0,95,5,213)
    local hint=CreateFrame("Frame",nil,pane); hint:SetAllPoints(threshold)
    self:Tooltip(hint,self:L("Display threshold help"),300)
    pane.otherBars=self:Stepper(pane,"Other players/pets","otherBars",1,4,1,245)
    local othersHint=CreateFrame("Frame",nil,pane); othersHint:SetAllPoints(pane.otherBars)
    self:Tooltip(othersHint,self:L("Other bars help"),300)
    pane.matrix={}; pane.roleHints={}
    local outputs={{"tooltip","Mouse tooltip"},{"overhead","Nameplates"},{"target","Target frame"},{"list","Enemy list"}}
    for i,entry in ipairs(outputs) do
        local label=self:Label(pane,entry[2],9)
        label:SetWidth(68); label:SetHeight(32); label:SetJustifyH("CENTER"); label:SetJustifyV("MIDDLE")
        label:SetPoint("TOPLEFT",pane,"TOPLEFT",93+(i-1)*70,-281)
    end
    for i,role in ipairs({"tank","damage","heal"}) do
        local key=role; pane.matrix[key]={}
        local title=self:Label(pane,self.roleLabels[key],11)
        local rowY=318+(i-1)*34
        title:SetWidth(73); title:SetHeight(28); title:SetJustifyV("MIDDLE")
        title:SetPoint("TOPLEFT",pane,"TOPLEFT",16,-rowY)
        local roleHint=self:Label(pane,"(your role)",8)
        roleHint:SetWidth(73); roleHint:SetHeight(11); roleHint:SetTextColor(.70,.68,.60)
        roleHint:SetPoint("TOPLEFT",pane,"TOPLEFT",16,-rowY-16)
        pane.roleHints[key]=roleHint
        table.insert(pane.refreshers,function()
            if E:Role(E.playerKey)==key then
                title:SetHeight(14); roleHint:Show()
            else
                title:SetHeight(28); roleHint:Hide()
            end
        end)
        for j,entry in ipairs(outputs) do
            local output=entry[1]
            local button=self:Button(pane,"",64,28,function()
                E:SetOutput(key,output,not E:OutputEnabled(output,key))
                for _,refresh in ipairs(pane.refreshers) do refresh() end
            end)
            self:Place(pane,button,95+(j-1)*70,rowY)
            pane.matrix[key][output]=button
            local enter,leave=button:GetScript("OnEnter"),button:GetScript("OnLeave")
            local help=output=="target" and "Target display help" or output=="tooltip" and "Tooltip display help" or output=="list" and "List display help" or "Optional display help"
            self:Tooltip(button,self:L(help),300)
            local tipEnter,tipLeave=button:GetScript("OnEnter"),button:GetScript("OnLeave")
            button:SetScript("OnEnter",function() if enter then enter() end; tipEnter() end)
            button:SetScript("OnLeave",function() if leave then leave() end; tipLeave() end)
            table.insert(pane.refreshers,function()
                E:SetToggleState(button,E:OutputEnabled(output,key))
                button.tip=E:L(help)..(output=="tooltip" and ("\n\n"..E:L("Always show tooltip help")) or "")
            end)
        end
    end
end
function E:BuildListSettings(pane)
    pane.refreshers={}
    self:Toggle(pane,"Bars","listBars",90)
    self:Toggle(pane,"Names","listNames",125)
    self:Toggle(pane,"Percentages","listPercent",160)
    self:Toggle(pane,"Role icons","listRoles",195)
    self:Stepper(pane,"Player box width","cellWidth",36,140,4,239)
    self:Stepper(pane,"Additional players per enemy","maxCandidates",1,3,1,274)
    self:Stepper(pane,"Marker size","markerSize",8,24,1,309)
    self:Stepper(pane,"Role icon size","roleIconSize",8,24,1,344)
    self:BuildPreviewButton(pane)
end
function E:PositionMinimap()
    local button=self.minimapButton
    if not button then return end
    local db=self.db or self.defaults
    if db.minimap then button:Show() else button:Hide() end
    -- Reforged owns anchors and drag scripts after collector reparenting.
    if button:GetParent()~=Minimap then return end
    local angle=db.minimapAngle*math.pi/180
    local x,y=math.cos(angle),math.sin(angle)
    if db.squareMinimap then
        local divisor=math.max(math.abs(x),math.abs(y))
        x=x/divisor; y=y/divisor
    end
    button:ClearAllPoints()
    button:SetPoint("CENTER",Minimap,"CENTER",x*(Minimap:GetWidth()/2+5),y*(Minimap:GetHeight()/2+5))
end
function E:InitMinimap()
    if not Minimap then return end
    -- Name deliberately has no 'MinimapIcon': Reforged's collector excludes it.
    local button=CreateFrame("Button","EasyThreatButton",Minimap)
    button:SetWidth(32); button:SetHeight(32); button:SetFrameStrata("MEDIUM")
    local icon=button:CreateTexture(nil,"ARTWORK")
    icon:SetTexture("Interface\\AddOns\\EasyThreat\\Media\\EasyThreatIcon")
    icon:SetWidth(20); icon:SetHeight(20); icon:SetPoint("CENTER",button,"CENTER",0,0)
    button.icon=icon
    -- Keep the familiar round minimap rim, with space around the shield.
    local border=button:CreateTexture(nil,"OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetWidth(54); border:SetHeight(54); border:SetPoint("TOPLEFT",button,"TOPLEFT",0,0)
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    button:RegisterForClicks("LeftButtonUp","RightButtonUp")
    button:SetScript("OnClick",function()
        if not E.db then return end
        if arg1=="RightButton" and E.journal then E.journal:Toggle() else E:ShowPage("roles") end
    end)
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart",function() if button:GetParent()==Minimap then button.dragging=true end end)
    button:SetScript("OnDragStop",function() button.dragging=false end)
    button:SetScript("OnUpdate",function()
        if button.dragging and E.db and button:GetParent()==Minimap then
            local x,y=GetCursorPosition()
            local cx,cy=Minimap:GetCenter()
            local scale=Minimap:GetEffectiveScale()
            local angle=math.atan2(y/scale-cy,x/scale-cx)*180/math.pi
            if angle<0 then angle=angle+360 end
            E.db.minimapAngle=angle; E:PositionMinimap()
        end
    end)
    button:SetScript("OnEnter",function()
        if not E.minimapTip then E.minimapTip=CreateFrame("GameTooltip","EasyThreatMinimapTooltip",UIParent,"GameTooltipTemplate") end
        local tip=E.minimapTip; tip:SetOwner(button,"ANCHOR_RIGHT"); tip:ClearLines()
        tip:AddLine("EasyThreat",1,.82,.15)
        tip:AddLine(E:L("Left-click to open configuration"),1,1,1)
        tip:AddLine(E:L("Right-click to open the combat journal"),1,1,1)
        local title=_G["EasyThreatMinimapTooltipTextLeft1"]
        if title then title:SetFont(E:FontPath(),15) end
        tip:Show()
    end)
    button:SetScript("OnLeave",function() if E.minimapTip then E.minimapTip:Hide() end end)
    self.minimapButton=button
    self:PositionMinimap()
end
-- Build at file load so a one-pass minimap collector can find the button.
E:InitMinimap()

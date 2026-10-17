-- Deliberately explicit mock surface: missing methods fail instead of silently
-- accepting typos. Models legacy global callback arguments, not modern ones.
SetPortraitTexture=nil -- Clear an enhanced test stub when reloading the plain Vanilla mock.
Mock={frames={},units={},clock=10,messages={},plates={}}
local methods={}
local function object(kind,name,parent)
    local o={kind=kind,name=name,parent=parent,shown=true,width=100,height=20,scale=1,
        scripts={},events={},children={},regions={},level=1,alpha=1}
    setmetatable(o,{__index=methods})
    if parent then table.insert(parent.children,o) end
    if name then _G[name]=o end
    table.insert(Mock.frames,o)
    return o
end
function CreateFrame(kind,name,parent,template)
    local result=object(kind,name,parent); result.template=template; return result
end
function methods:GetName(flag) if flag==1 then return self.guid end; return self.name end
function methods:GetParent() return self.parent end
function methods:SetParent(parent) self.parent=parent end
function methods:SetWidth(n) self.width=n end
function methods:GetWidth() return self.width end
function methods:SetHeight(n) self.height=n end
function methods:GetHeight() return self.height end
function methods:SetScale(n) self.scale=n end
function methods:GetEffectiveScale() return self.scale*(self.parent and self.parent:GetEffectiveScale() or 1) end
function methods:SetPoint(a,b,c,d,e) self.point={a,b,c,d,e} end
function methods:ClearAllPoints() self.point=nil end
function methods:SetAllPoints(frame) self.allPoints=frame end
function methods:GetLeft() return 270 end
function methods:GetTop() return 630 end
function methods:GetCenter() if self.center then return unpack(self.center) end; return 800,700 end
function methods:SetFrameStrata(strata) self.strata=strata end
function methods:SetFrameLevel(level) self.level=level end
function methods:GetFrameLevel() return self.level end
function methods:Show() self.shown=true end
function methods:Hide() self.shown=false end
function methods:IsShown() return self.shown end
function methods:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function methods:SetAlpha(alpha) self.alpha=alpha end
function methods:GetAlpha() return self.alpha end
function methods:SetScript(event,fn) self.scripts[event]=fn end
function methods:GetScript(event) return self.scripts[event] end
function methods:RegisterEvent(event) self.events[event]=true end
function methods:EnableMouse(value) self.mouse=value end
function methods:EnableMouseWheel(value) self.wheel=value end
function methods:SetMovable(value) self.movable=value end
function methods:RegisterForDrag(button) self.dragButton=button end
function methods:RegisterForClicks(a,b) self.clicks={a,b} end
function methods:StartMoving() self.moving=true end
function methods:StopMovingOrSizing() self.moving=false end
function methods:SetBackdrop(value) self.backdrop=value end
function methods:SetBackdropColor(r,g,b,a) self.bgColor={r,g,b,a} end
function methods:SetBackdropBorderColor(r,g,b,a) self.borderColor={r,g,b,a} end
function methods:SetStatusBarTexture(path) self.texture=path end
function methods:SetStatusBarColor(r,g,b,a) self.barColor={r,g,b,a} end
function methods:SetMinMaxValues(low,high) self.min=low; self.max=high end
function methods:SetOrientation(value) self.orientation=value end
function methods:SetValue(n) self.value=n end
function methods:GetValue() return self.value end
function methods:SetValueStep(n) self.valueStep=n end
function methods:SetThumbTexture(path) self.thumbTexture=path end
function methods:SetTexture(path,g,b,a)
    self.texture=path
    if type(path)=="number" then self.solidColor={path,g,b,a} else self.solidColor=nil end
    return path and 1 or nil
end
function methods:GetTexture() return self.texture end
function methods:SetTexCoord(a,b,c,d,e,f,g,h) self.texCoords={a,b,c,d,e,f,g,h} end
function methods:GetTexCoord() return unpack(self.texCoords or {0,1,0,1}) end
function methods:SetVertexColor(r,g,b,a) self.vertexColor={r,g,b,a} end
function methods:SetDesaturated(value) self.desaturated=value end
function methods:SetHighlightTexture(path) self.highlight=path end
function methods:SetNormalTexture(texture) self.normalTexture=texture end
function methods:SetPushedTexture(texture) self.pushedTexture=texture end
function methods:GetNormalTexture() return self.normalTexture end
function methods:GetPushedTexture() return self.pushedTexture end
function methods:SetButtonState(state) self.buttonState=state end
function methods:GetButtonState() return self.buttonState or "NORMAL" end
function methods:SetFont(path,size,flags) self.font=path; self.fontSize=size; self.fontFlags=flags end
function methods:SetText(text)
    self.text=text
    if self.kind=="GameTooltip" then self:ClearLines(); self:AddLine(text); self.mockUnit=nil end
end
function methods:GetFont() return self.font or "Fonts\\FRIZQT__.TTF",self.fontSize or 12,self.fontFlags or "" end
function methods:GetOwner() return self.owner end
function methods:ClearLines() self.lines=0; self.mockUnit=nil; self.height=14 end
function methods:NumLines() return self.lines or 0 end
function methods:AddLine(text)
    self.lines=(self.lines or 0)+1
    local name=self.name .. "TextLeft" .. self.lines
    local line=_G[name] or self:CreateFontString(name,"OVERLAY")
    line:SetText(text); line:Show(); self.height=14+self.lines*14
end
function methods:SetUnit(unit)
    self:ClearLines(); self.mockUnit=unit
    self:AddLine(UnitName(unit) or "?"); self:AddLine("Level 5")
    return true,"preserved"
end
function methods:GetUnit() return UnitName(self.mockUnit),self.mockUnit end
function methods:SetHyperlink(link) self:ClearLines(); self:AddLine(link) end
function methods:GetText() return self.text end
function methods:SetShadowColor(r,g,b,a) self.shadowColor={r,g,b,a} end
function methods:SetShadowOffset(x,y) self.shadowOffset={x,y} end
function methods:SetTextColor(r,g,b) self.textColor={r,g,b} end
function methods:SetJustifyH(value) self.justifyH=value end
function methods:SetJustifyV(value) self.justifyV=value end
function methods:SetAutoFocus(value) self.autoFocus=value end
function methods:SetMultiLine(value) self.multiLine=value end
function methods:SetFocus() self.focused=true end
function methods:HighlightText() self.highlighted=true end
function methods:SetScrollChild(child) self.scrollChild=child end
function methods:UpdateScrollChildRect() self.scrollUpdates=(self.scrollUpdates or 0)+1 end
function methods:SetVerticalScroll(value) self.verticalScroll=value end
function methods:SetTextInsets(a,b,c,d) self.insets={a,b,c,d} end
function methods:SetMaxLetters(n) self.maxLetters=n end
function methods:ClearFocus() self.focused=false end
function methods:SetOwner(owner) self.owner=owner end
function methods:SetColorRGB(r,g,b) self.rgb={r,g,b} end
function methods:GetColorRGB() return unpack(self.rgb) end
function methods:GetChildren() return unpack(self.children) end
function methods:GetRegions() return unpack(self.regions) end
function methods:CreateTexture(name,layer)
    local region=object("Texture",name,nil); region.parent=self
    table.insert(self.regions,region); return region
end
function methods:CreateFontString(name,layer) return self:CreateTexture(name,layer) end
UIParent=CreateFrame("Frame","UIParent"); UIParent:SetWidth(1600); UIParent:SetHeight(900)
WorldFrame=CreateFrame("Frame","WorldFrame",UIParent)
TargetFrame=CreateFrame("Frame","TargetFrame",UIParent)
Minimap=CreateFrame("Frame","Minimap",UIParent); Minimap:SetWidth(140); Minimap:SetHeight(140)
GameTooltip=CreateFrame("GameTooltip","GameTooltip",UIParent)
GameTooltip:SetScript("OnUpdate",function() Mock.tooltipUpdates=(Mock.tooltipUpdates or 0)+1 end)
GameTooltip:SetScript("OnHide",function() Mock.tooltipHides=(Mock.tooltipHides or 0)+1 end)
ColorPickerFrame=CreateFrame("Frame","ColorPickerFrame",UIParent)
UISpecialFrames={}; SlashCmdList={}
RAID_CLASS_COLORS={WARRIOR={r=0.8,g=0.6,b=0.4},HUNTER={r=0.6,g=0.8,b=0.3},WARLOCK={r=0.6,g=0.5,b=0.9}}
DEFAULT_CHAT_FRAME={AddMessage=function(self,msg) table.insert(Mock.messages,msg) end}
function GetTime() return Mock.clock end
function time() return Mock.clock end
function GetBuildInfo() return "1.12.1","5875" end
function GetCursorPosition() return 800,700 end
function Mock.Resolve(token)
    if type(token)~="string" then return nil end
    if Mock.units[token] then return Mock.units[token] end
    for _, unit in pairs(Mock.units) do if unit.guid==token then return unit end end
    if string.sub(token,-6)=="target" then
        local unit=Mock.Resolve(string.sub(token,1,-7))
        if unit then return Mock.Resolve(unit.target) end
    end
end
function UnitExists(token) local u=Mock.Resolve(token); if u then return 1,u.guid end end
function UnitGUID(token) local u=Mock.Resolve(token); return u and u.guid end
function UnitName(token) local u=Mock.Resolve(token); return u and u.name end
function UnitClass(token) local u=Mock.Resolve(token); return u and u.class,u and u.class end
function UnitIsConnected(token) local u=Mock.Resolve(token); if u and not u.offline then return 1 end end
function UnitIsDeadOrGhost(token) local u=Mock.Resolve(token); return u and u.dead end
function UnitAffectingCombat(token) local u=Mock.Resolve(token); return u and u.combat end
function UnitCanAttack(a,b) local u=Mock.Resolve(b); return u and u.hostile end
function UnitIsPlayer(token) local u=Mock.Resolve(token); return u and u.player end
function UnitIsUnit(a,b) local u,v=Mock.Resolve(a),Mock.Resolve(b); return u and v and u==v end
function GetRaidTargetIndex(token) local u=Mock.Resolve(token); return u and u.mark end
function UnitDetailedThreatSituation(who,mob)
    local enemy=Mock.Resolve(mob); local unit=Mock.Resolve(who)
    local sample=enemy and unit and enemy.threat and enemy.threat[unit.name]
    if sample then return sample.tanking,sample.status,sample.scaled,sample.raw,sample.value end
end
C_NamePlate={GetNamePlateForUnit=function(token)
    local unit=Mock.Resolve(token); return unit and Mock.plates[unit.guid]
end}
CLASSIC_API_VERSION="test"
function Mock.Event(name,value,second,third,fourth)
    event=name; arg1=value; arg2=second; arg3=third; arg4=fourth
    EasyThreat.eventFrame.scripts.OnEvent()
    event=nil; arg1=nil; arg2=nil; arg3=nil; arg4=nil
end
function Mock.Click(button,mouse)
    this=button; arg1=mouse or "LeftButton"; button.scripts.OnClick(); this=nil; arg1=nil
end

function GetLocale() return Mock.locale or "enUS" end
function getglobal(name) return _G[name] end
function UnitCreatureFamily(unit) local u=Mock.Resolve(unit); return u and u.family end

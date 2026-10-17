local E=EasyThreat
local function resizeTooltipRow(row,width)
    if row and row:IsShown() and math.abs(row:GetWidth()-width)>.1 then
        row:SetWidth(width)
        if row.barLayoutModel then E:PositionBarMarkers(row,row.barLayoutModel) end
    end
end
-- Extend the native tooltip without taking over its anchor or content.
function E:ClearThreatTooltip(clearUnit)
    if self.tooltipBar then self.tooltipBar:Hide() end
    if self.tooltipBar and self.tooltipBar.petBar then self.tooltipBar.petBar:Hide() end
    local layout,tip=self.tooltipLayout,self.tooltipFrame or GameTooltip
    if layout and tip and math.abs(tip:GetHeight()-layout.height)<0.1 then tip:SetHeight(layout.base) end
    self.tooltipLayout=nil
    if clearUnit then self.tooltipUnit=nil; self.tooltipGUID=nil; self.tooltipSample=nil end
end
function E:TooltipUnit()
    local tip=GameTooltip
    self.tooltipIdentitySource=nil
    if not tip then return nil,"missing" end
    if self.tooltipNonUnit=="hard" then return nil,"item" end
    -- ClassicAPI exposes the engine's tooltip GUID even when a skin bypasses
    -- Lua SetUnit. A missing/unresolvable GUID must not replace working paths.
    local _,guid=self:Call(tip.GetUnitGUID,tip)
    if type(guid)=="string" then
        local resolved=self:ResolveEnemyUnit({guid=guid})
        if resolved then self.tooltipIdentitySource="tooltip-guid"; return resolved end
    end
    local _,unit=self:Call(tip.GetUnit,tip)
    if unit and self:Exists(unit) then
        if unit==self.tooltipUnit and self.tooltipGUID and self:GUID(unit)~=self.tooltipGUID then return nil,"changed" end
        self.tooltipIdentitySource="tooltip-unit"; return unit
    end
    if self.tooltipUnit and self:Exists(self.tooltipUnit) then
        if not self.tooltipGUID or self:GUID(self.tooltipUnit)==self.tooltipGUID then self.tooltipIdentitySource="set-unit"; return self.tooltipUnit end
        return nil,"changed"
    end
    local owner=self:Call(tip.GetOwner,tip)
    local focus=self:Call(GetMouseFocus)
    if owner~=UIParent and owner~=WorldFrame and focus~=WorldFrame then return nil,"anchor" end
    local name=self:Call(UnitName,"mouseover")
    -- Skins may prepend a health row, use a cursor owner frame, or rebuild the
    -- lines with ClearLines/SetText instead of calling Lua SetUnit.
    local count=self:Call(tip.NumLines,tip)
    for i=1,math.min(3,type(count)=="number" and count or 3) do
        local line=getglobal and getglobal("GameTooltipTextLeft"..i)
        local text=line and self:Call(line.IsShown,line) and line:GetText()
        if text then
            text=string.gsub(string.gsub(string.gsub(text,"|c%x%x%x%x%x%x%x%x",""),"|r",""),"|T.-|t","")
            text=string.gsub(string.gsub(text,"^%s+",""),"%s+$","")
        end
        if name and text==name then self.tooltipIdentitySource="mouseover-name"; return "mouseover" end
    end
    self.tooltipIdentitySource=nil; return nil,"identity"
end
function E:RememberTooltip(reason,unit)
    if unit and (not self:Call(UnitCanAttack,"player",unit) or self:Call(UnitIsPlayer,unit)) then return end
    local name=unit and self:Call(UnitName,unit)
    if not name and self:Call(UnitCanAttack,"player","mouseover") then name=self:Call(UnitName,"mouseover") end
    if name then
        self.tooltipDiagnostic={reason=reason,name=name,at=GetTime(),guid=unit and self:GUID(unit)}
        self:RememberDisplay("tooltip",reason,{guid=unit and self:GUID(unit)})
    end
end
function E:SyncTooltipWidth(tip,box)
    if not self.db or not self.db.tooltipDynamicWidth or not box.tooltipDynamicWidth or
        not tip:IsShown() or not box:IsShown() then return end
    -- Read the real parent width AFTER the native setter/other footer ran.
    -- Do not repaint the tooltip or call its setters from this path: EasyCast
    -- temporarily retracts its footer before rebuilding it on every update.
    local width=math.max(20,tip:GetWidth()-2*self.db.tooltipInset)
    resizeTooltipRow(box,width)
    if box.tooltipFullStack then
        if box.petBar and box.petBar:IsShown() and box.petBar.stackPetTop and
            math.abs(box.petBar:GetWidth()+(box.petBar.stackPetInset or 0)-width)>.1 then
            self:LayoutStackPet(box,box.petBar,box.petBar.stackPetTop)
        end
        resizeTooltipRow(box.referenceBar,width)
        for _,child in ipairs(box.comparisonBars or {}) do resizeTooltipRow(child,width) end
    else
        local iconSize=self.db.petIconSize*(box.iconScale or 1)
        resizeTooltipRow(box.petBar,math.max(20,math.min(width*self.db.petWidth/100,width-iconSize-3)))
    end
end
function E:WatchTooltipWidth(tip,box)
    if not box.tooltipWidthUpdate then
        -- Also catch native engine/skin resizes that bypass Lua SetWidth.
        box.tooltipWidthUpdate=function()
            local ok,err=pcall(E.SyncTooltipWidth,E,tip,box)
            if not ok then E.tooltipError=tostring(err) end
        end
        box:SetScript("OnUpdate",box.tooltipWidthUpdate)
    end
    local sync=box.tooltipWidthUpdate
    local setWidth=tip.SetWidth
    if setWidth~=box.tooltipWidthHook then
        local handler=function(frame,width)
            local a,b,c,d,e=setWidth(frame,width)
            if frame==tip then sync() end
            return a,b,c,d,e
        end
        tip.SetWidth=handler; box.tooltipWidthHook=handler
    end
end
function E:PaintTooltipFooter(tip,box,base,model,pet,fontLine)
    local path,size,flags
    if fontLine then path,size,flags=self:Call(fontLine.GetFont,fontLine) end
    local scale=self.db.uiScale
    local barHeight=self.db.tooltipHeight*scale
    box.tooltipReferenceHeight=self.db.tooltipReferenceHeight
    box.otherGap=self.db.tooltipOtherGap
    local petExtra=self:ThreatStackExtra(box,model,pet,barHeight,self.db.tooltipPetGap,scale)
    local extra=barHeight+self.db.tooltipGap+petExtra+self.db.tooltipBottom-9
    tip:SetHeight(base+extra)
    -- Anchor to the original content rather than the growing tooltip bottom.
    box:ClearAllPoints(); box:SetPoint("TOPLEFT",tip,"TOPLEFT",self.db.tooltipInset,-(base+self.db.tooltipGap-9))
    box:SetWidth(math.max(20,tip:GetWidth()-2*self.db.tooltipInset)); box:SetHeight(barHeight)
    box.tooltipDynamicWidth=self.db.tooltipDynamicWidth
    box.tooltipFullStack=model.rankStack or model.fixedStack or model.sharedScale
    if box.tooltipDynamicWidth then self:WatchTooltipWidth(tip,box) end
    box:SetFrameLevel(tip:GetFrameLevel()+2); box.iconScale=scale; box.petGap=self.db.tooltipPetGap
    box.bar:SetFrameLevel(box:GetFrameLevel()+1); box.content:SetFrameLevel(box.bar:GetFrameLevel()+1)
    box.label:SetFont(self:FontKey()=="native" and (path or self:FontPath()) or self:FontPath(),
        math.max(6,math.min((size or 10)*scale*self.db.tooltipFont/100,barHeight-2)),flags or "")
    self:PaintThreatPair(box,model,pet)
    self:SyncTooltipWidth(tip,box)
    return {base=base,height=base+extra}
end
function E:UpdateThreatTooltip()
    local tip=GameTooltip
    if not tip then self:RememberDisplay("tooltip","identity"); self:ClearThreatTooltip(false); return end
    if not self.db or not self.tooltipBar then return end
    if not self.db.enabled or not self:OutputEnabled("tooltip") or self.demo or self.layoutPreview or not tip:IsShown() then
        self:RememberDisplay("tooltip",(not self.db.enabled or not self:OutputEnabled("tooltip")) and "disabled" or
            (self.demo or self.layoutPreview) and "preview" or "hidden")
        if self.db.enabled and self:OutputEnabled("tooltip") and not self.demo and not self.layoutPreview and
            not tip:IsShown() and self:Call(GetMouseFocus)==WorldFrame then self:RememberTooltip("hidden","mouseover") end
        self:ClearThreatTooltip(false); return
    end
    local unit,reason=self:TooltipUnit()
    if not unit or not self:Call(UnitCanAttack,"player",unit) or self:Call(UnitIsDeadOrGhost,unit) or self:Call(UnitIsPlayer,unit) then
        if reason~="item" then self:RememberTooltip(reason or "combat",unit) end
        self:ClearThreatTooltip(false); return
    end
    local guid=self:GUID(unit)
    local key=guid or "tooltip:"..unit
    local cached=self.tooltipSample
    local fighting=self:Call(UnitAffectingCombat,unit) and true or false
    if not guid or not cached or cached.key~=key or GetTime()-cached.at>=0.1 or
        (self.db.tooltipAlways and cached.combat~=fighting) then
        cached={key=key,at=GetTime(),combat=fighting,enemy=self:ReadEnemy(unit,key,guid)}; self.tooltipSample=cached
    end
    local enemy=cached.enemy
    if not enemy and self.db.tooltipAlways then
        -- Unmarked idle enemies deliberately have no tracked combat model.
        enemy={key=key,guid=guid,unit=unit,samples={},combat=false,
            level=self:Call(UnitLevel,unit),classification=self:Call(UnitClassification,unit)}
    end
    local allowed,filter=self:EnemyAllowed(enemy or {level=self:Call(UnitLevel,unit),classification=self:Call(UnitClassification,unit)})
    if not allowed then
        self:RememberTooltip("filter",unit); self.tooltipDiagnostic.filter=filter
        self:RememberDisplay("tooltip","filter",enemy,filter)
        self:ClearThreatTooltip(false); return
    end
    local model,pet,modelReason
    if enemy then model,pet,modelReason=self:TooltipModels(enemy) end
    if not model then
        self:NoteSourceDisplay("tooltip",guid,nil,nil,self.tooltipBar,modelReason or "source")
        local reason=modelReason or "source"
        if not enemy or not enemy.combat then
            reason=(self:Call(UnitAffectingCombat,unit) or self:Call(UnitAffectingCombat,"player")) and "source" or "combat"
        end
        self:RememberTooltip(reason,unit); self:ClearThreatTooltip(false); return
    end
    local old=self.tooltipLayout
    local height=tip:GetHeight()
    local base=old and math.abs(height-old.height)<0.1 and old.base or height
    self.tooltipLayout=self:PaintTooltipFooter(tip,self.tooltipBar,base,model,pet,getglobal and getglobal("GameTooltipTextLeft1"))
    self:NoteSourceDisplay("tooltip",guid,model,pet,self.tooltipBar,modelReason or "visible")
    self:RememberTooltip(modelReason or "visible",unit)
end
function E:SafeTooltipUpdate()
    local ok,err=pcall(self.UpdateThreatTooltip,self)
    if not ok then self.tooltipError=tostring(err); self:ClearThreatTooltip(false) end
end
function E:InitThreatTooltip()
    local tip=GameTooltip
    if not tip then return end
    if tip~=self.tooltipFrame then
        if self.tooltipFrame then self:ClearThreatTooltip(true); self.tooltipFrameReplaced=true end
        self.tooltipFrame=tip; self.tooltipMethods={}; self.tooltipOnUpdate=nil; self.tooltipOnHide=nil
        self.tooltipBar=self:Bar(tip,100,12); self.tooltipBar:EnableMouse(false); self.tooltipBar:Hide()
    end
    local methods=self.tooltipMethods
    local setUnit=tip.SetUnit
    if type(setUnit)=="function" and setUnit~=methods.SetUnit then
        tip.SetUnit=function(frame,unit,a,b,c)
            if frame~=E.tooltipFrame then return setUnit(frame,unit,a,b,c) end
            E:ClearThreatTooltip(true); E.tooltipNonUnit=nil
            local r1,r2,r3,r4,r5=setUnit(frame,unit,a,b,c)
            E.tooltipNonUnit=nil; E.tooltipUnit=unit; E.tooltipGUID=E:GUID(unit)
            return r1,r2,r3,r4,r5
        end
        methods.SetUnit=tip.SetUnit
    end
    local clear=tip.ClearLines
    if type(clear)=="function" and clear~=methods.ClearLines then
        tip.ClearLines=function(frame)
            if frame~=E.tooltipFrame then return clear(frame) end
            E:ClearThreatTooltip(true); E.tooltipNonUnit=nil
            return clear(frame)
        end
        methods.ClearLines=tip.ClearLines
    end
    for _,method in ipairs({"SetText","SetHyperlink","SetBagItem","SetInventoryItem","SetLootItem",
        "SetMerchantItem","SetQuestItem","SetQuestLogItem","SetSpell","SetSpellByID","SetAction","SetTalent","SetTradeSkillItem","SetCraftItem"}) do
        local original=tip[method]
        local spellMethod=method
        local kind=method=="SetText" and "soft" or "hard"
        if type(original)=="function" and original~=methods[method] then
            tip[method]=function(frame,a,b,c,d,e,f)
                if frame~=E.tooltipFrame then return original(frame,a,b,c,d,e,f) end
                E:ClearThreatTooltip(true)
                E.spellTooltipDepth=(E.spellTooltipDepth or 0)+1
                local r1,r2,r3,r4,r5=original(frame,a,b,c,d,e,f)
                E.spellTooltipDepth=E.spellTooltipDepth-1
                E.tooltipNonUnit=kind
                if E.spellTooltipDepth==0 and E.AppendSpellThreat then
                    local ok,err=pcall(E.AppendSpellThreat,E,frame,spellMethod,a,b)
                    E.spellTooltipError=not ok and tostring(err) or nil
                end
                return r1,r2,r3,r4,r5
            end
            methods[method]=tip[method]
        end
    end
    for _,method in ipairs({"AddLine","AddDoubleLine","Show"}) do
        local original=tip[method]
        if type(original)=="function" and original~=methods[method] then
            tip[method]=function(frame,a,b,c,d,e,f,g,h,i)
                if frame==E.tooltipFrame then E:ClearThreatTooltip(false) end
                return original(frame,a,b,c,d,e,f,g,h,i)
            end
            methods[method]=tip[method]
        end
    end
    local hide=tip:GetScript("OnHide")
    if not self.tooltipOnHide or hide~=self.tooltipOnHide then
        local handler=function()
            if tip==E.tooltipFrame then E:ClearThreatTooltip(true); E.tooltipNonUnit=nil end
            if hide then hide() end
        end
        tip:SetScript("OnHide",handler); self.tooltipOnHide=handler
    end
    local update=tip:GetScript("OnUpdate")
    if not self.tooltipOnUpdate or update~=self.tooltipOnUpdate then
        if self.tooltipOnUpdate then self.tooltipHookReplaced=true end
        local handler=function()
            if update then
                local ok,err=pcall(update)
                if not ok then E.tooltipHookError=tostring(err) end
            end
            if tip==E.tooltipFrame then E:SafeTooltipUpdate() end
        end
        tip:SetScript("OnUpdate",handler); self.tooltipOnUpdate=handler
    end
end

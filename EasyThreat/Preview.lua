local E=EasyThreat
function E:AnyCombat()
    for _,member in ipairs(self.roster) do if self:Call(UnitAffectingCombat,member.unit) then return true end end
    return false
end
function E:BuildPreviewButton(pane)
    pane.preview=self:Place(pane,self:Button(pane,"Preview",358,32,function()
        if E:AnyCombat() then E:Print(E:L("Preview outside combat")); return end
        E.layoutPreview=not E.layoutPreview; E:LayoutChanged()
    end),16,393)
    pane.preview.state=self:Text(pane.preview,11); pane.preview.state:SetPoint("RIGHT",pane.preview,"RIGHT",-12,0)
    pane.refreshers=pane.refreshers or {}
    table.insert(pane.refreshers,function() E:UpdatePreviewButtons() end)
end
function E:UpdatePreviewButtons()
    for _,pane in pairs(self.pages or {}) do
        if pane.preview then pane.preview.text:SetText(self:L("Preview")); self:SetToggleState(pane.preview,self.layoutPreview) end
    end
end
-- One layout preview for every output. It never changes live units, roles,
-- source caches or the roster, and does not require nameplates or combat.
function E:HidePreviews()
    if self.previewsVisible then
        self.previewsVisible=nil
        self:StopHUDDrag(self.list); self:StopHUDDrag(self.target)
    end
    if self.previewPlate then self.previewPlate:Hide() end
    if self.previewTooltip then self.previewTooltip:Hide() end
end
function E:RenderPreviews()
    self.previewsVisible=true
    local own={pct=78,fillPct=52,text="78%",color=self:RiskColor(78),sharedScale=true,identity="preview:own",stackIdentity="preview:stack"}
    local pet={pct=45,fillPct=30,text="45%",color=self:RiskColor(45),pet=true,sharedScale=true,identity="preview:pet"}
    own.reference={pct=100,fillPct=70,text=self:L("Tank"),color=self.colors.green,comparison=true,sharedScale=true,identity="preview:tank"}
    own.fixedStack=true; own.rankStack=true; own.riskStack=true; pet.text=self:L("Pet bar")
    own.fillPct=78; own.text=""; pet.fillPct=45; own.reference.fillPct=100
    own.reference.aggro=true; own.reference.borderColor=self.colors.green
    local player=self:Member(self.playerKey)
    if self.db.alwaysPlayerColors then own.color=self:IdentityColor(player); pet.color=self:IdentityColor(self:Member(self.playerKey..":pet") or player) end
    own.reference.color=self:IdentityColor({key="preview:tank",class="WARRIOR"})
    own.references={own.reference}
    for i=2,self.db.otherBars or 1 do
        table.insert(own.references,{fillPct=65-(i-2)*20,text=self:L(i==2 and "Damage" or i==3 and "Healer" or "Pet bar"),
            color=self:IdentityColor({key="preview:other"..i,class=i==2 and "MAGE" or "PRIEST"}),
            identity="preview:other"..i,rankStack=true,riskStack=true,comparison=true})
    end
    local targetPet=pet
    self:PaintThreatPair(self.target,own,targetPet)
    own.fixedStack=nil
    if not self.previewPlate then
        self.previewPlate=self:Bar(UIParent,105,10)
        self.previewPlate.title=self:Text(self.previewPlate,11)
        self.previewPlate.title:SetPoint("BOTTOM",self.previewPlate,"TOP",0,38)
    end
    local plate=self.previewPlate
    plate:ClearAllPoints(); plate:SetPoint("TOPLEFT",self.window,"TOPRIGHT",35,-40)
    plate.title:SetText(self:L("Preview enemy"))
    self:PaintBar(plate,{pct=100,text="",color=self.colors.neutral})
    if not self.overlays[1] then self.overlays[1]=self:Bar(UIParent,self.db.barWidth,self.db.barHeight) end
    local bar=self.overlays[1]
    local scale=self.db.overheadScale*self.db.uiScale
    bar:ClearAllPoints(); bar:SetScale(scale); bar:SetWidth(self.db.barWidth); bar:SetHeight(self.db.barHeight)
    bar:SetPoint("BOTTOM",plate,"TOP",self.db.overheadX/scale,self.db.overheadY/scale+self:OverheadStackReserve())
    self:PaintThreatPair(bar,own,pet)
    if not self.previewTooltip then
        local tip=self:Box(UIParent,195,58)
        local backdrop=self:Call(GameTooltip and GameTooltip.GetBackdrop,GameTooltip)
        tip:SetBackdrop(backdrop or {bgFile="Interface\\Tooltips\\UI-Tooltip-Background",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
            tile=true,tileSize=16,edgeSize=16,insets={left=4,right=4,top=4,bottom=4}})
        tip:SetBackdropColor(0.05,0.05,0.05,0.98)
        tip.title=self:Text(tip,12); tip.title:SetPoint("TOPLEFT",tip,"TOPLEFT",9,-10)
        tip.title:SetTextColor(1,0.85,0.25)
        tip.note=self:Text(tip,10); tip.note:SetPoint("TOPLEFT",tip,"TOPLEFT",9,-28)
        tip.bar=self:Bar(tip,177,14); self.previewTooltip=tip
    end
    local tip=self.previewTooltip
    tip:ClearAllPoints(); tip:SetPoint("TOPLEFT",self.window,"TOPRIGHT",25,-120)
    tip.title:SetText(self:L("Preview enemy")); tip.note:SetText(self:L("Preview"))
    own.fixedStack=true
    self:PaintTooltipFooter(tip,tip.bar,58,own,targetPet,tip.title); tip:Show()
    if self.list.dragging then return end
    local me=self:Member(self.playerKey) or {key="preview:me",name=self.playerKey or "Player"}
    local candidate={key="preview:damage",name="DPS",class="MAGE",alive=true,connected=true}
    self.list:SetHeight(self:ListRowHeight()); self.list:Show(); self.list.caption:SetText(self:L("Preview")); self.list.caption:Show(); self.list.more:SetText("")
    if not self.rows[1] then self.rows[1]=self:MakeRow() end
    local row=self.rows[1]; row:ClearAllPoints(); row:SetPoint("TOPLEFT",self.list,"TOPLEFT",0,0)
    self:RenderRow(row,{key="preview:enemy",name=self:L("Preview enemy"),mark=8,combat=true,owner=me,ownerQuality="api",samples={},
        candidates={{member=candidate,pct=86,quality="api"}}})
end

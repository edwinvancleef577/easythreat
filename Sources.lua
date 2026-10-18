local E = EasyThreat
function E:Capabilities()
    return {
        detailed=type(UnitDetailedThreatSituation)=="function",
        situation=type(UnitThreatSituation)=="function",
        classic=CLASSIC_API_VERSION ~= nil,
        classicVersion=CLASSIC_API_VERSION and tostring(CLASSIC_API_VERSION) or nil,
        tooltipGUID=GameTooltip and type(GameTooltip.GetUnitGUID)=="function" or false,
        ownerGUID=type(UnitOwnerGUID)=="function",
        auraData=C_UnitAuras and type(C_UnitAuras.GetAuraDataByIndex)=="function" or false,
        castData=C_Spell and type(C_Spell.UnitCastingInfo)=="function" or false,
        super=SUPERWOW_VERSION ~= nil or SUPERWOW_STRING ~= nil,
        plates=(C_NamePlate and type(C_NamePlate.GetNamePlateForUnit)=="function") or type(UnitNameplate)=="function" or
            table.getn(self.nativePlates or {})>0,
        guid=self:GUID("player") ~= nil,
        native=table.getn(self.nativePlates or {}),
        structured=self.localBackend=="nampower",
        serverReceived=self.sourceStats and self.sourceStats.received or 0
    }
end
function E:CollectUnits()
    local units, seen = {}, {}
    local function add(unit)
        if unit and not seen[unit] and E:Exists(unit) then
            seen[unit]=true; table.insert(units, unit)
        end
    end
    add("target"); add("mouseover")
    for _, member in ipairs(self.roster) do add(member.unit .. "target") end
    for i=1,8 do add("mark" .. i) end
    -- No break on gaps: a client may keep sparse slots after a plate disappears.
    for i=1,80 do add("nameplate" .. i) end
    if C_NamePlate and C_NamePlate.GetNamePlateGUIDs then
        local guids = self:Call(C_NamePlate.GetNamePlateGUIDs)
        if type(guids)=="table" then for _, guid in pairs(guids) do add(guid) end end
    end
    for _, record in ipairs(self.nativePlates or {}) do add(record.guid) end
    -- Re-query GUID handles, never a recycled target/nameplate token.
    for _, enemy in pairs(self.enemies) do if enemy.guid then add(enemy.guid) end end
    for guid in pairs(self.serverSnapshots or {}) do add(guid) end
    for guid in pairs(self.ledger or {}) do add(guid) end
    return units
end
function E:ResolveEnemyUnit(enemy)
    if not enemy then return end
    if not enemy.guid then return self:Exists(enemy.unit) and enemy.unit or nil end
    -- Prefer stable native tokens for renderers; some nameplate adapters accept
    -- "target" but not raw GUIDs. Never reuse a token for a different creature.
    if self:GUID("target")==enemy.guid then return "target" end
    if self:GUID("mouseover")==enemy.guid then return "mouseover" end
    if enemy.unit and enemy.unit~=enemy.guid and self:GUID(enemy.unit)==enemy.guid then return enemy.unit end
    for _,unit in ipairs(self.knownUnits or {}) do if unit~=enemy.guid and self:GUID(unit)==enemy.guid then return unit end end
    if self:GUID(enemy.guid)==enemy.guid then return enemy.guid end
end
function E:ReadEnemy(unit, key, guid)
    -- GUID identity support does not guarantee every unit API accepts GUIDs.
    -- Prefer a verified token for this very creature before probing combat;
    -- an unsupported GUID probe must not reset an active target's ledger.
    if guid then unit=self:ResolveEnemyUnit({guid=guid,unit=unit}) or unit end
    local enemy = {key=key, guid=guid, unit=unit, name=self:Call(UnitName,unit) or "?",
        mark=self:Call(GetRaidTargetIndex,unit), samples={}, seen=GetTime(),
        level=self:Call(UnitLevel,unit),classification=self:Call(UnitClassification,unit)}
    if type(enemy.mark) ~= "number" or enemy.mark < 1 or enemy.mark > 8 then enemy.mark=nil end
    local fighting = self:Call(UnitAffectingCombat, unit)
    local flee=guid and self.fleeingEnemies and self.fleeingEnemies[guid]
    enemy.fleeing=flee and fighting and GetTime()-flee<8 or false
    if guid and not fighting then
        self.enemySeenIdle=self.enemySeenIdle or {}; self.enemySeenIdle[guid]=GetTime()
        if self.threatViews then self.threatViews[guid]=nil end
        if self.ledger then self.ledger[guid]=nil end
        if self.displayQuantities then self.displayQuantities[guid]=nil end
        if self.targetHistory then self.targetHistory[guid]=nil end
    end
    local target = unit .. "target"
    -- Some Vanilla extensions resolve an enemy GUID/mouseover but not its
    -- concatenated target handle. Reuse targettarget only for the SAME unit.
    if not self:Exists(target) and self:Call(UnitIsUnit,unit,"target") and self:Exists("targettarget") then target="targettarget" end
    -- A creature may target itself (for example during a self-cast). Some
    -- extensions also resolve unsupported GUID suffixes back to that creature.
    -- Neither case identifies a player who holds its aggro.
    local function usableTarget(token)
        if not E:Exists(token) then return false,"unavailable" end
        if E:Call(UnitIsUnit,unit,token) or (guid and E:GUID(token)==guid) then return false,"self-target" end
        if E:Call(UnitCanAttack,"player",token) and not E:Call(UnitIsPlayer,token) then return false,"hostile-creature" end
        return true
    end
    local targetOK,rejected=usableTarget(target)
    if not targetOK and target~="targettarget" and self:Call(UnitIsUnit,unit,"target") then
        local fallbackOK=usableTarget("targettarget")
        if fallbackOK then target="targettarget"; targetOK=true; rejected=nil end
    end
    enemy.observedTargetGUID=self:GUID(target)
    enemy.ownerRejected=rejected
    local observed = targetOK and self:MemberForUnit(target) or nil
    local related = observed ~= nil and fighting
    local tankingCount = 0
    for _, member in ipairs(self.roster) do
        if member.alive and member.connected then
            local tanking, status, scaled, raw, amount = self:Call(UnitDetailedThreatSituation, member.unit, unit)
            if self:Finite(scaled) then
                enemy.samples[member.key] = {pct=self:Clamp(scaled,0,100), quality="api",at=GetTime(),
                    amount=self:Finite(amount) and amount or nil,raw=self:Finite(raw) and raw or nil}
                if scaled > 0 then related=true end
            end
            if status == nil then status=self:Call(UnitThreatSituation, member.unit, unit) end
            if tanking or status == 2 or status == 3 then
                tankingCount=tankingCount+1
                enemy.owner=member; enemy.ownerQuality="api"; related=true
            end
        end
    end
    -- Inconsistent addon-provided APIs must not select an arbitrary owner.
    if tankingCount > 1 then enemy.owner=nil; enemy.ownerQuality=nil end
    if not enemy.owner and fighting and targetOK then
        enemy.owner=observed or {key="outside:" .. (self:Call(UnitName,target) or "?"),
            name=self:Call(UnitName,target) or "?",guid=self:GUID(target)}
        enemy.ownerQuality="observed" -- target of a cast can differ from the threat owner
    end
    local damage = self.damage and self.damage[key]
    if damage and GetTime()-damage.updated < 12 then related=true end
    enemy.combat = related and (fighting or tankingCount > 0 or damage ~= nil) and true or false
    local participation=guid and self.participation and self.participation[guid]
    if participation and (GetTime()-participation<3 or fighting) then enemy.combat=true end
    self:ApplyServerThreat(enemy)
    local ledger=guid and self.ledger and self.ledger[guid]
    if ledger and fighting then enemy.combat=true end
    self:ApplyLocalThreat(enemy)
    if enemy.mark or enemy.combat or (self:Call(UnitIsUnit,unit,"target") and self:AnyCombat()) then return enemy end
end
function E:ObserveFleeEmote(message,sender)
    if type(message)~="string" or type(sender)~="string" then return end
    -- Monster emotes are an observed cue, not a deduction from missing threat.
    -- Servers may send English text even on a localized client.
    local text=string.lower(message)
    if not string.find(text,"attempts to run away in fear",1,true) and
        not string.find(text,"versucht vor angst zu fliehen",1,true) and
        not string.find(text,"versucht, vor angst zu fliehen",1,true) then return end
    local found
    for _,unit in ipairs(self:CollectUnits()) do
        if self:Call(UnitName,unit)==sender and self:Call(UnitCanAttack,"player",unit) and
            not self:Call(UnitIsPlayer,unit) and not self:Call(UnitIsDeadOrGhost,unit) then
            local guid=self:GUID(unit)
            if guid then
                if found and found~=guid then return end -- names do not identify duplicate mobs
                found=guid
            end
        end
    end
    if found then
        self.fleeingEnemies=self.fleeingEnemies or {}; self.fleeingEnemies[found]=GetTime()
        if self.enemies[found] then self.enemies[found].fleeing=true end
    end
end
function E:Scan()
    self:UpdateEventHealth()
    self:PeerTick()
    self:PruneThreatSources(); self:QueryServerThreat(); self:CaptureHealth()
    self:ScanNativePlates()
    self.caps = self:Capabilities()
    local nextEnemies, current = {}, {}
    local units = self:CollectUnits()
    self.knownUnits = units
    for _, unit in ipairs(units) do
        if self:Call(UnitCanAttack,"player",unit) and not self:Call(UnitIsDeadOrGhost,unit)
            and not self:Call(UnitIsPlayer,unit) then
            local duplicate = false
            for _, old in ipairs(current) do
                if self:Call(UnitIsUnit,unit,old.unit) then duplicate=true; break end
            end
            if not duplicate then
                local guid = self:GUID(unit)
                local mark = self:Call(GetRaidTargetIndex,unit)
                -- Without GUIDs, these keys are for this scan only. Never persist token identity.
                local key = guid or (mark and "mark:"..mark) or "unit:"..unit
                table.insert(current,{unit=unit,name=self:Call(UnitName,unit),guid=guid})
                local enemy = self:ReadEnemy(unit,key,guid)
                if enemy then nextEnemies[key]=enemy end
            end
        end
    end
    local nameCounts={}
    for _, entry in ipairs(current) do
        if entry.name then nameCounts[entry.name]=(nameCounts[entry.name] or 0)+1 end
    end
    for _, entry in ipairs(current) do
        if entry.guid and nameCounts[entry.name]>1 and self.damage then self.damage[entry.guid]=nil end
    end
    if self.db.estimates then
        for _, enemy in pairs(nextEnemies) do
            if enemy.combat and nameCounts[enemy.name]==1 then self:ApplyEstimate(enemy) end
        end
    end
    -- Preserve observed marked enemies as explicitly stale planning entries.
    -- A marker update or zone change clears this memory immediately.
    for key, old in pairs(self.enemies) do
        local dead=old.dead or (old.guid and self:Call(UnitIsDeadOrGhost,old.guid))
        local retired=old.retired or (dead and GetTime()) or old.seen
        local invalid=not dead and old.guid and self:Exists(old.guid) and self:Call(GetRaidTargetIndex,old.guid)~=old.mark
        if old.mark and not invalid and not nextEnemies[key] and GetTime()-retired < 15 then
            local reassigned=false
            for _, fresh in pairs(nextEnemies) do if fresh.mark==old.mark then reassigned=true end end
            if not reassigned then
                nextEnemies[key]={key=key,guid=old.guid,name=old.name,mark=old.mark,seen=old.seen,
                    level=old.level,classification=old.classification,stale=true,dead=dead and true or false,retired=retired,combat=false,samples={}}
            end
        end
    end
    for key,expiry in pairs(self.dismissedEnemies or {}) do
        if GetTime()>=expiry then self.dismissedEnemies[key]=nil end
    end
    self.enemies=nextEnemies
    for key in pairs(self.visibility or {}) do if not nextEnemies[key] then self.visibility[key]=nil end end
    for key in pairs(self.pairVisibility or {}) do if not nextEnemies[self:VisibilityEnemyKey(key)] then self.pairVisibility[key]=nil end end
    if self.demo then self:DemoData() end
    self:RefreshUI()
end
function E:PlateForUnit(unit)
    if not unit then return end
    if C_NamePlate and C_NamePlate.GetNamePlateForUnit then
        local plate=self:Call(C_NamePlate.GetNamePlateForUnit,unit)
        if plate then return plate end
    end
    local plate=self:Call(UnitNameplate,unit)
    if plate then return plate,"api" end
    return self:NativePlateForUnit(unit)
end
function E:Status()
    local c=self:Capabilities()
    self:Print(self.version .. "; " .. self:L(self.roleLabels[self:Role(self.playerKey)]))
    for _,line in ipairs(self:DiagnosisLines(true)) do self:Print(line) end
    self:Print("Client=" .. tostring(self:Call(GetBuildInfo) or "?") ..
        "; ClassicAPI=" .. tostring(CLASSIC_API_VERSION or false) .. "; SuperWoW=" .. tostring(SUPERWOW_VERSION or false))
    self:Print("Threat API=" .. tostring(c.detailed) .. "; Status API=" .. tostring(c.situation) ..
        "; GUID=" .. tostring(c.guid) .. "; Nameplate anchor=" .. tostring(c.plates))
    self:Print("Native plates=" .. c.native .. "; Overlays=" .. (self.shownOverheads or 0) ..
        "; Adapter=" .. (self.lastPlateAdapter or "-") .. "; Tooltip=" .. tostring(self.tooltipBar and self.tooltipBar:IsShown() or false))
    local count,values,context,estimates=0,0,0,0
    for _,enemy in pairs(self.enemies) do
        count=count+1
        for _,sample in pairs(enemy.samples) do
            if sample.quality=="api" then values=values+1
            elseif sample.quality=="context" then context=context+1
            elseif sample.quality=="estimate" then estimates=estimates+1 end
        end
    end
    self:Print("Enemies=" .. count .. "; API=" .. values .. "; TWT context (~)=" .. context .. "; Local (~)=" .. estimates)
    self:Print("TWT received="..c.serverReceived.."; Events="..(self.localBackend or "localized chat").."; /et trace on|off|show")
    local stats=self.sourceStats or {}
    self:Print("Queries="..(stats.query or 0).."; Accepted="..(stats["accepted-context"] or 0)..
        "; Rejected="..((stats["rejected-context"] or 0)+(stats["rejected-format"] or 0)).."; Trace="..tostring(self.traceEnabled or false))
end

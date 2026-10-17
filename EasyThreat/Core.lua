-- Original EasyThreat code. Keep all shipped Lua compatible with Lua 5.0.
EasyThreat = { version = "dev", build = "20261016-target3", roster = {}, enemies = {}, serial = 0 }
local E = EasyThreat
E.colors = {
    green = {0.24, 0.76, 0.34}, yellow = {0.94, 0.77, 0.22},
    orange = {1, 0.43, 0.12}, red = {0.96, 0.04, 0.08},
    neutral = {0.48, 0.47, 0.43}, bronze = {0.48, 0.40, 0.26},
    build = {0.20, 0.49, 0.78}
}
E.defaults = {
    enabled = true, overhead = true, tooltipBar = true, tooltipAlways = false, tooltipDynamicWidth = true, targetHUD = true,
    listDamage = false, listHeal = false, listBars = false, listNames = true,
    listPercent = false, listRoles = true, cellWidth = 68, uiScale = 1,
    language = "auto", font = "native", petRoles = {}, petMigrated = {},
    threshold = 0, hysteresis = 5, maxCandidates = 3, maxRows = 7,
    scale = 1, barWidth = 102, barHeight = 9, overheadY = -4,
    overheadX = 0, overheadScale = 1.3, tankSafe = true, enemyWidth = 119,
    targetX = 5, targetY = 16, targetFree = false, targetScale = 1,
    targetWidth = 130, targetHeight = 11, targetPetGap = 4, targetOtherGap = 6,
    windowX = 497.77819683545982, windowY = -38.814820788224779,
    estimates = false, localThreat = true, locked = false, groupSync = true,
    roleViews = {}, tooltipInset=10, tooltipBottom=11, tooltipGap=6, tooltipHeight=16, tooltipScale=1,
    tooltipFont=70, tooltipPetGap=5, tooltipOtherGap=6, tooltipReferenceHeight=65, markerSize=13, roleIconSize=16, filters={}, raidMarkedOnly=true,
    petWidth=91, petHeight=80, petGap=4, petIconSize=12,
    minimap = true, minimapAngle = 220, squareMinimap = false,
    x = 260, y = -150, colors = {}, groups = {},
    journalEnabled=true, journalBook=true, journalBookSize=40, journalBookX=620, journalBookY=110,
    journalLegend=false, journalLogNames=true, journalLogIcons=true, journalOverheal=true,
    journalEvents=true, journalOwn=false, journalViews={}, journalFilters={}, journalTitles=true,
    targetOnAttack=true, targetPet=true, pressureMarker=true, otherBars=3,
    alwaysPlayerColors=false, spellThreatTooltip=false,
}
E.settingRanges = {otherBars={1,4},journalBookSize={28,64},journalBookX={0,4000},journalBookY={0,4000},threshold={0,95}, hysteresis={0,15}, maxCandidates={1,3},
        maxRows={3,12}, uiScale={0.7,1.5}, cellWidth={36,140}, scale={0.6,1.6}, barWidth={60,140}, barHeight={8,18},
        overheadX={-200,200}, overheadY={-100,150}, overheadScale={0.6,1.6},
        enemyWidth={100,200}, targetX={-4000,4000}, targetY={-4000,4000},
        targetScale={0.6,1.6}, targetWidth={60,200}, targetHeight={8,24}, targetPetGap={0,16}, targetOtherGap={0,24},
        windowX={-4000,4000}, windowY={-4000,4000},
        minimapAngle={0,360}, x={-4000,4000}, y={-4000,4000},
        tooltipInset={4,24},tooltipBottom={4,24},tooltipGap={0,24},tooltipHeight={10,24},tooltipScale={0.6,1.6},
        tooltipFont={50,150},tooltipPetGap={0,16},tooltipOtherGap={0,24},tooltipReferenceHeight={30,150},markerSize={8,24},roleIconSize={8,24},
        petWidth={50,100},petHeight={60,120},petGap={0,16},petIconSize={6,20}}

function E:Call(fn, a, b, c)
    if type(fn) ~= "function" then return nil end
    local ok, v1, v2, v3, v4, v5 = pcall(fn, a, b, c)
    if ok then return v1, v2, v3, v4, v5 end
end
function E:Exists(unit) return unit and self:Call(UnitExists, unit) end
function E:GUID(unit)
    local guid = self:Call(UnitGUID, unit)
    if not guid then local exists; exists, guid = self:Call(UnitExists, unit) end
    if type(guid) == "string" and guid ~= "" then return guid end
end
function E:Clamp(n, lo, hi) return math.max(lo, math.min(hi, n)) end
function E:Print(message)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffe0bd73EasyThreat|r " .. message) end
end
function E:InitDB()
    if type(EasyThreatDB) ~= "table" or next(EasyThreatDB)==nil then
        -- Fresh defaults are already in the current layout; old installs still migrate.
        EasyThreatDB = {layoutVersion=2,revision=2,tooltipLayoutVersion=1}
    end
    self.db = EasyThreatDB
    -- The target used the shared pet gap before gaining its own control.
    if self.db.targetPetGap==nil then self.db.targetPetGap=self.db.petGap end
    if self.db.tooltipWidthVersion~=1 then
        -- Full final tooltip width is now the default, including existing
        -- profiles. A later explicit opt-out is retained across reload/import.
        self.db.tooltipDynamicWidth=true; self.db.tooltipWidthVersion=1
    end
    for k, v in pairs(self.defaults) do
        if type(self.db[k]) ~= type(v) then
            if type(v) == "table" then self.db[k] = {} else self.db[k] = v end
        end
    end

    for k, r in pairs(self.settingRanges) do
        local n = self.db[k]
        if n ~= n then n = self.defaults[k] end
        self.db[k] = self:Clamp(n, r[1], r[2])
    end
    self.db.maxCandidates = math.floor(self.db.maxCandidates)
    self.db.otherBars = math.floor(self.db.otherBars)
    self.db.maxRows = math.floor(self.db.maxRows)
    if self.db.tooltipLayoutVersion~=1 then
        -- Preserve the old effective bar height; font size now has its own control.
        self.db.tooltipHeight=self:Clamp(self.db.tooltipHeight*self.db.tooltipScale,10,24)
        self.db.tooltipFont=self:Clamp(100*self.db.tooltipScale,50,150)
        self.db.tooltipPetGap=self.db.petGap
        self.db.tooltipScale=1; self.db.tooltipLayoutVersion=1
    end
    self:InitFilters()
    for _,key in ipairs({"stock","spend","healing"}) do
        if type(self.db.journalViews[key])~="boolean" then self.db.journalViews[key]=true end
    end
    for _,key in ipairs({"damage","heal","aggro","item","cooldown","death","threat"}) do
        if type(self.db.journalFilters[key])~="boolean" then self.db.journalFilters[key]=true end
    end
    if self.db.layoutVersion~=2 then
        self.db.x=self.db.x*self.db.scale; self.db.y=self.db.y*self.db.scale
        self.db.layoutVersion=2
    end
    self.db.includePets=nil; self.db.tankList=nil
    if self.db.revision~=2 then self.db.estimates=false; self.db.revision=2 end
    for _,role in ipairs({"tank","damage","heal"}) do
        if type(self.db.roleViews[role])~="table" then self.db.roleViews[role]={} end
        local defaults={tooltip=self.db.tooltipBar,overhead=self.db.overhead,target=self.db.targetHUD,
            list=role=="tank" or (role=="heal" and self.db.listHeal) or (role=="damage" and self.db.listDamage)}
        for output,value in pairs(defaults) do
            if type(self.db.roleViews[role][output])~="boolean" then self.db.roleViews[role][output]=value and true or false end
        end
    end
    self:RefreshRoster()
end
function E:RefreshRoster()
    if not self.db then return end
    local roster, names = {}, {}
    local function add(unit, owner)
        local name = E:Call(UnitName, unit)
        if not E:Exists(unit) or not name or name == "" or name == "Unknown" or name == UNKNOWN or name == UNKNOWNOBJECT then return end
        local _, class = E:Call(UnitClass, owner and owner.unit or unit)
        local key = owner and (owner.name .. ":pet") or name
        local entry = {key=key, name=name, unit=unit, guid=E:GUID(unit), class=class,
            pet=owner ~= nil, owner=owner and owner.name,
            roleKey=owner and (owner.name .. ":" .. name .. ":" .. (E:Call(UnitCreatureFamily,unit) or "")),
            alive=not E:Call(UnitIsDeadOrGhost, unit),
            connected=E:Call(UnitIsConnected, owner and owner.unit or unit) and true or false}
        table.insert(roster, entry)
        return entry
    end
    local me = add("player")
    if not me then return end
    self.playerKey = me.key
    table.insert(names, me.name)
    add("pet", me)
    local raid=self:Call(GetNumRaidMembers) or 0
    local prefix=raid>0 and "raid" or "party"
    for i=1,(raid>0 and math.min(40,raid) or 4) do
        local unit=prefix..i
        -- Keep player/pet canonical; the raid roster also contains the player.
        if not self:Call(UnitIsUnit,unit,"player") then
            local owner = add(unit)
            if owner then
                table.insert(names, owner.name)
                add(prefix.."pet"..i, owner)
            end
        end
    end
    table.sort(names)
    local signature = table.concat(names, "|")
    local identities={}
    for _,member in ipairs(roster) do identities[member.key]=member.guid end
    for key,guid in pairs(self.rosterGUIDs or {}) do
        if identities[key]~=guid then self.tooltipSample=nil; self.pairVisibility={} end
    end
    local previousGUIDs=self.rosterGUIDs or {}
    local samePlayer=me.guid and previousGUIDs[me.key]==me.guid
    local previousProfile=self.profile
    self.rosterGUIDs=identities
    self.roster = roster
    local groupChanged=self.groupKey~=signature
    if groupChanged then
        self.groupKey = signature
        if samePlayer then
            -- Group membership is not a combat reset. Keep accumulated local
            -- threat, but revalidate replies tied to the former group.
            self.tooltipSample=nil
            if self.ThreatTargetChanged then self:ThreatTargetChanged() end
            if self.ResetPeers then self:ResetPeers() end
            for _,member in ipairs(roster) do
                if member.guid and not member.pet and previousGUIDs[member.key]~=member.guid then
                    for guid,data in pairs(self.ledger or {}) do
                        if data.values[member.guid]==nil and self:Call(UnitAffectingCombat,guid) then
                            self:InvalidateActor(member.guid,"joined-combat",guid)
                        end
                    end
                end
            end
        else
            self.enemies, self.damage, self.visibility = {}, {}, {}
            if self.ResetThreatSources then self:ResetThreatSources() end
        end
        if type(self.db.groups[signature]) ~= "table" then
            self.db.groups[signature] = { roles={} }
            -- Adding a guest should not silently turn the tank's list off.
            -- Existing saved group profiles and solo profiles stay independent.
            if samePlayer and table.getn(names)>1 and previousProfile then
                for _,member in ipairs(roster) do
                    if not member.pet and previousGUIDs[member.key]==member.guid then
                        self.db.groups[signature].roles[member.key]=previousProfile.roles[member.key]
                    end
                end
            end
        end
        self.profile = self.db.groups[signature]
        if type(self.profile.roles) ~= "table" then self.profile.roles = {} end
        if self.profile.mode=="tank" and not self.profile.roles[self.playerKey] then
            self.profile.roles[self.playerKey]="tank"
        end
        self.profile.used = self:Call(time) or 0
        -- Bound per-character group history without changing the active party.
        local count, oldest, oldestTime = 0, nil, nil
        for key, p in pairs(self.db.groups) do
            count = count + 1
            if key ~= signature and (not oldestTime or (p.used or 0) < oldestTime) then
                oldest, oldestTime = key, p.used or 0
            end
        end
        if count > 20 and oldest then self.db.groups[oldest] = nil end
    end
    self.profile.activePets=self.profile.activePets or {}
    for _, member in ipairs(roster) do
        if member.pet and (groupChanged or self.profile.activePets[member.key]~=member.roleKey) then
            local role=self.db.petRoles[member.roleKey]
            if not self.db.petMigrated[member.owner] then
                role=role or self.profile.roles[member.key]
                self.db.petMigrated[member.owner]=true
            end
            role=role or "damage"
            self.profile.roles[member.key]=role
            self.db.petRoles[member.roleKey]=role
            self.profile.activePets[member.key]=member.roleKey
        end
    end
    self.profile.mode=self:ViewMode()
end
function E:Member(key)
    for _, member in ipairs(self.roster) do if member.key == key then return member end end
end
function E:MemberForUnit(unit)
    if not self:Exists(unit) then return nil end
    for _, m in ipairs(self.roster) do
        if self:Call(UnitIsUnit, unit, m.unit) then return m end
    end
end
function E:IsTank(key) return key and self.profile and self.profile.roles[key] == "tank" end
function E:Role(key)
    local role=self.profile and self.profile.roles[key]
    if role=="tank" or role=="heal" then return role end
    return "damage"
end
function E:ViewMode() return self:IsTank(self.playerKey) and "tank" or "personal" end
function E:SetRole(key,role)
    if role~="tank" and role~="heal" then role="damage" end
    self.profile.roles[key]=role
    local member=self:Member(key)
    if member and member.pet then self.db.petRoles[member.roleKey]=role end
    self.profile.mode=self:ViewMode()
    self.visibility={}; self.pairVisibility={}; self.tooltipSample=nil
    self:UpdateRoles(); self:RefreshUI()
end
function E:SetMode(mode)
    -- Compatibility for existing slash commands; role is the sole source of truth.
    self:SetRole(self.playerKey,mode=="tank" and "tank" or "damage")
end
function E:ShowEnemyList()
    return self:OutputEnabled("list")
end
function E:OutputEnabled(output,role)
    local views=self.db and self.db.roleViews
    local view=views and views[role or self:Role(self.playerKey)]
    return view and view[output] and true or false
end
function E:SetOutput(role,output,value)
    self.db.roleViews[role][output]=value and true or false
    self.tooltipSample=nil; self.pairVisibility={}; self.visibility={}; self:RefreshUI()
end
function E:IdentityColor(member)
    local custom = member and (self.db.colors[member.key] or self.db.colors[member.owner])
    if type(custom) == "table" and type(custom[1]) == "number" and
        type(custom[2]) == "number" and type(custom[3]) == "number" then return custom end
    local class = member and RAID_CLASS_COLORS and RAID_CLASS_COLORS[member.class]
    if class then return {class.r, class.g, class.b} end
    return {0.60, 0.68, 0.78}
end
function E:ShortName(text, limit)
    -- Do not cut a UTF-8 code point in half (German and non-Latin names).
    text = text or "?"
    local i, count = 1, 0
    while i <= string.len(text) and count < limit do
        local byte = string.byte(text, i)
        if byte < 128 then i=i+1 elseif byte < 224 then i=i+2
        elseif byte < 240 then i=i+3 else i=i+4 end
        count=count+1
    end
    if i <= string.len(text) then return string.sub(text,1,i-1) .. "." end
    return text
end

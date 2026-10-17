-- Original implementation. Numeric talent data: OctoWoW's public calculator,
-- Server behavior still requires calibration through controlled in-game tests.
local E=EasyThreat
E.ruleVersion="octo-sources2"
E.classTalents={}
local function talent(key,class,id,name,de,values)
    E.classTalents[key]={class=class,id=id,name=name,de=de,values=values,max=table.getn(values)}
end
talent("defiance","WARRIOR",12303,"Defiance","Trotz",{4,8,12,15,20})
talent("defensiveTactics","WARRIOR",51606,"Defensive Tactics",nil,{60,120,180})
talent("feralInstinct","DRUID",16947,"Feral Instinct","Instinkt der Wildnis",{5,10,15})
talent("subtlety","DRUID",17118,"Subtlety","Feingefühl",{4,8,12,16,20})
talent("improvedRF","PALADIN",20468,"Improved Righteous Fury","Verbesserter Zorn der Gerechtigkeit",{25,50,75})
talent("righteousStrikes","PALADIN",51341,"Righteous Strikes",nil,{5,10,15,20,25})
talent("vengeance","PALADIN",20049,"Vengeance","Rache",{2,4,6,8,10})
talent("arcaneSubtlety","MAGE",11210,"Arcane Subtlety","Arkanes Feingefühl",{20,40})
talent("burningSoul","MAGE",11083,"Burning Soul","Brennende Seele",{15,30})
talent("frostChanneling","MAGE",11160,"Frost Channeling","Frost-Kanalisierung",{10,20,30})
talent("silentResolve","PRIEST",14523,"Silent Resolve","Schweigsame Entschlossenheit",{4,8,12,16,20})
talent("shadowAffinity","PRIEST",15318,"Shadow Affinity","Schattenaffinität",{8,16,25})
talent("improvedFade","PRIEST",15274,"Improved Fade","Verbessertes Verblassen",{25,50})
talent("spiritArmor","SHAMAN",45951,"Spirit Armor",nil,{5,10})
talent("naturesGrace","SHAMAN",29187,"Nature's Grace",nil,{5,10,15})
talent("calmingWinds","SHAMAN",51383,"Calming Winds",nil,{8,16,25})
talent("totemicAlignment","SHAMAN",51381,"Totemic Alignment",nil,{45,90})
E.schoolNames={[0]="physical",[1]="holy",[2]="fire",[3]="nature",[4]="frost",[5]="shadow",[6]="arcane"}
function E:SchoolForSpell(id)
    local value=self:Call(GetSpellRecField,tonumber(id),"school")
    return self.schoolNames[tonumber(value)]
end
function E:SchoolForText(text)
    if type(text)~="string" then return end
    local lower=string.lower(text)
    for index,name in pairs(self.schoolNames) do
        local localized=_G["SPELL_SCHOOL"..index.."_CAP"]
        if lower==name or (type(localized)=="string" and lower==string.lower(localized)) then return name end
    end
    local german={heilig="holy",feuer="fire",natur="nature",frost="frost",schatten="shadow",arkan="arcane",physisch="physical"}
    return german[lower]
end
function E:NoteClassLimit(member,reason,detail)
    self.classLimits=self.classLimits or {}
    local count,oldest,oldestAt=0,nil,GetTime()
    for key,entry in pairs(self.classLimits) do
        if GetTime()-entry.at>300 then self.classLimits[key]=nil
        else
            count=count+1
            if entry.at<=oldestAt then oldest=key; oldestAt=entry.at end
        end
    end
    local key=(member and member.key or "?")..":"..reason
    local previous=self.classLimits[key]
    if not previous and count>=48 and oldest then self.classLimits[oldest]=nil end
    if not previous then self:ThreatDiagnostics("class-limit",key.." "..tostring(detail or "")) end
    self.classLimits[key]={actor=member and member.name or "?",key=member and member.key,
        reason=reason,detail=detail,at=GetTime()}
end
function E:RefreshClassTalents(force)
    local guid=self:GUID("player") or self.playerKey
    local cached=self.talentSnapshot
    if not force and cached and cached.guid==guid and cached.provider==GetTalentInfo and
        cached.names==GetSpellRecField and GetTime()-cached.at<2 then return cached end
    local snapshot={guid=guid,at=GetTime(),provider=GetTalentInfo,names=GetSpellRecField,ranks={},invalid={}}
    self.talentSnapshot=snapshot
    local _,class=self:Call(UnitClass,"player")
    local definitions={}
    for key,rule in pairs(self.classTalents) do
        if rule.class==class then
            local localized=self:Call(GetSpellRecField,rule.id,"name")
            definitions[key]={rule=rule,localized=type(localized)=="string" and localized~="" and localized or nil}
        end
    end
    local tabs=self:Call(GetNumTalentTabs)
    if type(tabs)~="number" or tabs<1 or tabs>8 or type(GetTalentInfo)~="function" then return snapshot end
    for tab=1,tabs do
        local count=self:Call(GetNumTalents,tab)
        if type(count)~="number" or count<0 or count>100 then return snapshot end
        for index=1,count do
            local ok,name,icon,tier,column,rank,maxRank=pcall(GetTalentInfo,tab,index)
            if ok then
                for key,entry in pairs(definitions) do
                    local rule=entry.rule
                    if name==rule.name or (rule.de and name==rule.de) or (entry.localized and name==entry.localized) then
                        if snapshot.ranks[key]~=nil or type(rank)~="number" or rank~=math.floor(rank) or
                            rank<0 or rank>rule.max or maxRank~=rule.max then
                            snapshot.invalid[key]=true; snapshot.ranks[key]=nil
                        elseif not snapshot.invalid[key] then snapshot.ranks[key]=rank end
                    end
                end
            end
        end
    end
    return snapshot
end
function E:TalentAmount(member,key)
    local rule=self.classTalents[key]
    if not member or member.pet or not rule or rule.class~=member.class then return 0,true end
    local level=self:Call(UnitLevel,member.unit)
    if type(level)=="number" and level>0 and level<10 then return 0,true end
    if member.unit~="player" and not self:Call(UnitIsUnit,member.unit,"player") then
        local profile=self.PeerProfile and self:PeerProfile(member)
        local rank=profile and profile.ranks[key]
        if rank~=nil then return rank>0 and rule.values[rank] or 0,true end
        -- Never lend our own talent ranks to a party member of the same class.
        self:NoteClassLimit(member,"foreign-talents"); return 0,false
    end
    local snapshot=self:RefreshClassTalents()
    local rank=snapshot.ranks[key]
    if rank==nil then
        self:NoteClassLimit(member,snapshot.invalid[key] and "talent-layout" or "talents",rule.name)
        return 0,false
    end
    return rank>0 and rule.values[rank] or 0,true
end
function E:ClassTalentsChanged()
    local previous=self.talentSnapshot
    local current=self:RefreshClassTalents(true)
    if not previous or previous.guid~=current.guid then return end
    for key,rule in pairs(self.classTalents) do
        if previous.ranks[key]~=current.ranks[key] or previous.invalid[key]~=current.invalid[key] then
            -- Spells also change on shapeshift/pet updates. Only changed ranks
            -- with an existing combat ledger can invalidate accumulated threat.
            for _,data in pairs(self.ledger or {}) do
                if data.values[current.guid]~=nil then
                    self:RuleFailure(self:MemberForGUID(current.guid),"talent-change",nil,rule.name)
                    return
                end
            end
        end
    end
end
local function textureKey(value)
    if type(value)~="string" then return nil end
    local _,_,last=string.find(string.lower(value),"([^\\/]+)$")
    return last
end
function E:BuffByIcon(member,icon)
    if not member or not member.unit then return false end
    local profile=self.PeerProfile and self:PeerProfile(member)
    if profile then local stacks=profile.buffs[string.lower(icon)]; return stacks~=nil,stacks or 1 end
    for i=1,32 do
        local texture,stacks=self:Call(UnitBuff,member.unit,i)
        if not texture then break end
        if textureKey(texture)==string.lower(icon) then
            return true,type(stacks)=="number" and math.max(1,stacks) or 1
        end
    end
    return false
end
function E:ClassForm(member)
    local profile=self.PeerProfile and self:PeerProfile(member)
    if profile then return profile.form end
    if member.class=="DRUID" and not member.pet then
        local power=self:Call(UnitPowerType,member.unit)
        if power==1 then return "bear" elseif power==3 then return "cat" end
    end
    local forms={ability_warrior_defensivestance="defensive",ability_warrior_offensivestance="battle",
        ability_racial_avatar="berserker",ability_racial_bearform="bear",ability_druid_catform="cat"}
    if member.unit=="player" and type(GetShapeshiftFormInfo)=="function" then
        for i=1,10 do
            local texture,name,active=self:Call(GetShapeshiftFormInfo,i)
            if not texture then break end
            if active==true or active==1 then return forms[textureKey(texture)] or "other" end
        end
    end
    for icon,form in pairs(forms) do
        if self:BuffByIcon(member,icon) then return form end
    end
    if member.class=="WARRIOR" then self:NoteClassLimit(member,"stance") end
    return "other"
end
function E:WearsShield(member)
    local profile=self.PeerProfile and self:PeerProfile(member)
    if profile then return profile.shield end
    if type(GetInventoryItemLink)~="function" then return nil end
    local item=self:Call(GetInventoryItemLink,member.unit,17)
    if not item then return false end
    if type(GetItemInfo)~="function" then return nil end
    local ok,name,link,quality,level,kind,subtype,stack,equip=pcall(GetItemInfo,item)
    if ok and name and type(equip)=="string" then return equip=="INVTYPE_SHIELD" end
end
function E:WeaponEnchantState(member)
    local profile=self.PeerProfile and self:PeerProfile(member)
    if profile then return profile.enchant~=nil,profile.enchant end
    local own=member.unit=="player" or self:Call(UnitIsUnit,member.unit,"player")
    local known,main,remaining,charges,off=false
    if own and type(GetWeaponEnchantInfo)=="function" then known,main,remaining,charges,off=pcall(GetWeaponEnchantInfo) end
    return known,main==true or main==1 or off==true or off==1
end
function E:ClassMultiplier(member,school,rule,healing)
    local class=not member.pet and member.class
    local spell=healing or (rule and rule.spell) or (school and school~="physical")
    local value=1
    if class=="WARRIOR" then
        local form=self:ClassForm(member)
        if form=="defensive" then value=1.3*(1+self:TalentAmount(member,"defiance")/100)
        elseif form=="battle" or form=="berserker" then
            value=0.8
            if self:TalentAmount(member,"defensiveTactics")>0 and self:WearsShield(member)~=false then
                self:NoteClassLimit(member,"defensive-tactics"); return nil,"defensive-tactics"
            end
        end
    elseif class=="DRUID" then
        local form=self:ClassForm(member)
        if form=="bear" then value=1.3*(1+self:TalentAmount(member,"feralInstinct")/100)
        elseif form=="cat" then value=0.71 end
        if spell then value=value*(1-self:TalentAmount(member,"subtlety")/100) end
    elseif class=="ROGUE" then value=0.71
    elseif class=="PALADIN" then
        local fury=self:BuffByIcon(member,"Spell_Holy_SealOfFury")
        if fury and school=="holy" and not healing then value=1+0.6*(1+self:TalentAmount(member,"improvedRF")/100) end
        if rule and rule.holyStrike and not healing then value=value*(1+self:TalentAmount(member,"righteousStrikes")/100) end
        local vengeance,stacks=self:BuffByIcon(member,"Ability_Racial_Avatar")
        if vengeance and not fury then value=value*(1-self:TalentAmount(member,"vengeance")*math.min(stacks,3)/100) end
    elseif class=="WARLOCK" then
        if self:BuffByIcon(member,"Spell_Shadow_PsychicScream") then value=value*0.9 end -- Succubus sacrifice
    elseif class=="MAGE" then
        local key=school=="arcane" and "arcaneSubtlety" or school=="fire" and "burningSoul" or school=="frost" and "frostChanneling"
        if key then value=value*(1-self:TalentAmount(member,key)/100)
        elseif not school then self:NoteClassLimit(member,"school") end
    elseif class=="PRIEST" and spell then
        value=value*(1-self:TalentAmount(member,"silentResolve")/100)
        if school=="shadow" then value=value*(1-self:TalentAmount(member,"shadowAffinity")/100) end
    elseif class=="SHAMAN" then
        local armor=self:TalentAmount(member,"spiritArmor")
        local shield=armor>0 and self:WearsShield(member)
        if armor>0 and shield==nil then self:NoteClassLimit(member,"shield")
        elseif shield then value=value*(1+armor/100) end
        if school=="nature" then value=value*(1-self:TalentAmount(member,"naturesGrace")/100) end
        if not healing and (school=="physical" or (rule and rule.imbue)) then
            local calm=self:TalentAmount(member,"calmingWinds")
            local known,enchanted=self:WeaponEnchantState(member)
            if known and not enchanted then value=value*(1-calm/100)
            elseif calm>0 or (known and enchanted) then
                -- Weapon enchants are not reliably identified by UnitBuff.
                -- A reduction without knowing Rockbiter would create late warnings.
                self:NoteClassLimit(member,"rockbiter"); return nil,"rockbiter"
            end
        end
    end
    if self:BuffByIcon(member,"Spell_Holy_SealOfSalvation") or self:BuffByIcon(member,"Spell_Holy_GreaterBlessingofSalvation") then value=value*0.7 end
    if self:BuffByIcon(member,"Spell_Nature_Brilliance") then value=value*0.8 end -- Tranquil Air
    -- No Imp/Master Demonologist threat reduction: Octo changed it to spell cost.
    return value
end

function E:AppendClassDiagnosis(lines)
    local function add(key,a,b,severity)
        table.insert(lines,{text=E:L(key,a,b),severity=severity or "info",order=table.getn(lines)+1})
    end
    add("Class rules: %s. Live server calibration is pending.",self.ruleVersion)
    local recent={}
    for _,entry in pairs(self.classLimits or {}) do
        if GetTime()-entry.at<=300 and self:Member(entry.key) then table.insert(recent,entry) end
    end
    table.sort(recent,function(a,b)
        if a.at~=b.at then return a.at>b.at end
        return a.key..a.reason<b.key..b.reason
    end)
    local groups={}
    for _,entry in ipairs(recent) do
        local reason=entry.reason
        local category=reason=="foreign-talents" and "foreign" or
            reason=="shield-identity" and "shield-identity" or
            (reason=="talents" or reason=="talent-layout") and "talents" or
            (reason=="school" or reason=="shield" or reason=="stance") and "state" or "rule"
        local key=entry.key..":"..category
        if not groups[key] then
            groups[key]=true
            if category=="shield-identity" then add("%s: damage-shield hits measured; exact spell unknown, special threat multiplier unverified.",entry.actor,nil,"warning")
            elseif category=="foreign" then add("%s: party talents unavailable; using approximate base values.",entry.actor,nil,"warning")
            elseif category=="talents" then add("%s: talent not identified (%s). Check client language and talent data.",entry.actor,entry.detail or "?","warning")
            elseif category=="state" then add("%s: %s unavailable; class factors may be incomplete.",entry.actor,
                self:L(reason=="school" and "Spell school" or reason=="shield" and "Off-hand item" or "Stance"),"warning")
            else
                local label=self:Call(GetSpellRecField,tonumber(entry.detail),"name") or entry.detail or reason
                local detail=tostring(label)
                if reason=="totem-transfer" then detail=self:L("Totem threat transfer")
                elseif reason=="rockbiter" then detail=self:L("Weapon enchant not identified")
                elseif reason=="defensive-tactics" then detail="Defensive Tactics"
                elseif reason=="talent-change" then detail=self:L("Talents changed during combat") end
                add("%s: %s needs verification. Affected local percentages withheld until combat ends.",entry.actor,detail,"warning")
            end
        end
    end
end

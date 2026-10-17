local E=EasyThreat
-- Names identify ordinary families, not coefficients. All coefficients below
-- come from the SAME rule/class calculator as the live ledger. Unsupported
-- families never silently acquire a supposed exact 1:1 ratio.
E.tooltipFamilies={
    {686,"damage","shadow","Shadow Bolt","Schattenblitz"},
    {172,"damage","shadow","Corruption","Verderbnis"},
    {348,"damage","fire","Immolate","Feuerbrand"},
    {133,"damage","fire","Fireball","Feuerball"},
    {116,"damage","frost","Frostbolt","Frostblitz"},
    {5143,"damage","arcane","Arcane Missiles","Arkane Geschosse"},
    {585,"damage","holy","Smite","Göttliche Pein"},
    {589,"damage","shadow","Shadow Word: Pain","Schattenwort: Schmerz"},
    {403,"damage","nature","Lightning Bolt","Blitzschlag"},
    {421,"damage","nature","Chain Lightning","Kettenblitzschlag"},
    {5176,"damage","nature","Wrath","Zorn"},
    {8921,"damage","arcane","Moonfire","Mondfeuer"},
    {3044,"damage","arcane","Arcane Shot","Arkaner Schuss"},
    {1978,"damage","nature","Serpent Sting","Schlangenbiss"},
    {1752,"damage","physical","Sinister Strike","Finsterer Stoß"},
    {53,"damage","physical","Backstab","Meucheln"},
    {635,"heal","holy","Holy Light","Heiliges Licht"},
    {19750,"heal","holy","Flash of Light","Lichtblitz"},
    {2050,"heal","holy","Lesser Heal","Geringes Heilen"},
    {2054,"heal","holy","Heal","Heilen"},
    {2061,"heal","holy","Flash Heal","Blitzheilung"},
    {139,"heal","holy","Renew","Erneuerung"},
    {331,"heal","nature","Healing Wave","Welle der Heilung"},
    {8004,"heal","nature","Lesser Healing Wave","Geringe Welle der Heilung"},
    {5185,"heal","nature","Healing Touch","Heilende Berührung"},
    {774,"heal","nature","Rejuvenation","Verjüngung"},
    {8936,"heal","nature","Regrowth","Nachwachsen"},
    {6807,"damage","physical","Maul","Zermalmen"},
    {779,"damage","physical","Swipe","Prankenhieb"},
    {8042,"damage","nature","Earth Shock","Erdschock"},
    {8092,"damage","shadow","Mind Blast","Gedankenschlag"},
    {5676,"damage","fire","Searing Pain","Sengender Schmerz"},
    {78,"damage","physical","Heroic Strike","Heldenhafter Stoß"},
    {6572,"damage","physical","Revenge","Rache"},
    {23922,"damage","physical","Shield Slam","Schildschlag"},
    {72,"damage","physical","Shield Bash","Schildhieb"},
}
local function cleanName(value)
    if type(value)~="string" then return end
    value=string.gsub(string.gsub(value,"|c%x%x%x%x%x%x%x%x",""),"|r","")
    value=string.gsub(string.gsub(value,"^%s+",""),"%s+$","")
    if value~="" then return value end
end
local function rankNumber(text)
    local _,_,number=string.find(type(text)=="string" and text or "","(%d+)")
    return tonumber(number)
end
local function spellID(value)
    local id=tonumber(value)
    if id and id>0 and id==math.floor(id) then return id end
end
local function spellLink(link)
    local _,_,id=string.find(type(link)=="string" and link or "","spell:(%d+)")
    return spellID(id)
end
-- Read by ID, never as a spellbook slot. Different optional client extensions
-- expose different APIs; the existence of one does not imply the others exist.
function E:SpellDisplayInfo(id)
    id=spellID(id); if not id then return end
    local name=cleanName(self:Call(GetSpellRecField,id,"name"))
    if name then return name,self:Call(GetSpellRecField,id,"rank"),"GetSpellRecField" end
    local rank
    name,rank=self:Call(SpellInfo,id)
    if cleanName(name) then return cleanName(name),rank,"SpellInfo" end
    name,rank=self:Call(GetSpellNameAndRankForId,id)
    if cleanName(name) then return cleanName(name),rank,"GetSpellNameAndRankForId" end
    local api=type(C_Spell)=="table" and C_Spell
    local info=self:Call(api and api.GetSpellInfo,id)
    if type(info)=="table" and cleanName(info.name) then
        return cleanName(info.name),info.rank or self:Call(api.GetSpellSubtext,id),"C_Spell.GetSpellInfo"
    end
    name=self:Call(api and api.GetSpellName,id)
    if cleanName(name) then return cleanName(name),self:Call(api.GetSpellSubtext,id),"C_Spell.GetSpellName" end
    name,rank=self:Call(GetSpellInfo,id)
    if cleanName(name) then return cleanName(name),rank,"GetSpellInfo" end
end
function E:SpellDisplayName(id)
    local name=self:SpellDisplayInfo(id)
    return name
end
function E:TooltipSpellRule(member,id,name,rank)
    local direct=id and self:ThreatRule(id,member)
    if direct then return direct end
    local result
    for spell,rule in pairs(self.threatRules) do
        local matches=name and name==self:SpellDisplayName(spell)
        for _,alias in ipairs(rule.names or {}) do if name==alias then matches=true end end
        if matches and (not rule.pet or member.pet) and
            not (member.pet and not rule.pet and rule.names and rule.names[1]=="Cower") and
            (not rule.class or rule.class==member.class) and
            (not rank or not rule.rank or rank==rule.rank) then
            if result and (result.kind~=rule.kind or result.value~=rule.value) then return {kind="unresolved"} end
            result=rule
        end
    end
    return result or self:RuleForText(member,name)
end
function E:SpellThreatDescription(member,id,name,rank)
    if not member then return {self:L("Spell identity unknown")},"identity" end
    name=name or (id and self:SpellDisplayName(id))
    local rule=self:TooltipSpellRule(member,id,name,rank)
    local kind,school
    for _,family in ipairs(self.tooltipFamilies) do
        if id==family[1] or (name and (name==family[4] or name==family[5] or name==self:SpellDisplayName(family[1]))) then
            kind=family[2]; school=family[3]; break
        end
    end
    school=(id and self:SchoolForSpell(id)) or school
    if rule then
        if rule.kind=="unresolved" then
            return {self:L(rule.reason=="spell-rank" and "Spell rank formula unknown" or "Spell threat unknown")},rule.reason=="spell-rank" and "rank" or "unsupported"
        end
        if rule.kind=="invalidate" or rule.kind=="petInvalidate" then return {self:L("Spell threat special")},"special" end
        if rule.kind=="nothreat" then return {self:L("Spell threat none")},"none" end
        if rule.kind=="holy" then school="holy" end
        if rule.kind=="damage" or rule.kind=="holy" or rule.kind=="addDamage" or rule.kind=="noheal" then kind="damage" end
        if rule.kind=="flat" then kind="flat" end
    end
    if not kind then return {self:L(name and "Spell threat unknown" or "Spell identity unknown")},name and "unsupported" or "identity" end
    -- Incomplete talent reads must not be presented as an exact multiplier.
    for key,definition in pairs(self.classTalents) do
        if not member.pet and definition.class==member.class then
            local value,known=self:TalentAmount(member,key)
            if not known then return {self:L("Spell threat talents unknown")},"talents" end
        end
    end
    if not school and kind~="flat" and not member.pet then return {self:L("Spell school unknown")},"school" end
    rule=rule or {spell=true}
    local coefficient=kind=="heal" and self:HealingThreatMultiplier(member,rule,school) or self:ThreatMultiplier(member,school,rule)
    if not self:Finite(coefficient) then return {self:L("Spell state unknown")},"state" end
    local lines={}
    if kind=="flat" then
        table.insert(lines,self:L(rule.value<0 and "Spell threat reduction %.0f" or "Spell threat flat %.0f",math.abs(rule.value*coefficient)))
    elseif kind=="heal" then
        table.insert(lines,self:L("Spell threat healing %.2f",coefficient))
        table.insert(lines,self:L("Spell healing split"))
    else
        table.insert(lines,self:L("Spell threat damage %.2f",coefficient))
        if rule.kind=="addDamage" then table.insert(lines,self:L("Spell threat additional %.0f",rule.value*coefficient)) end
        if rule.kind=="noheal" then table.insert(lines,self:L("Spell leech healing none")) end
        if id==20473 or id==20929 or id==20930 or name=="Holy Shock" or name=="Heiliger Schock" then
            table.insert(lines,self:L("Spell threat healing %.2f",self:HealingThreatMultiplier(member,rule,"holy")))
            table.insert(lines,self:L("Spell healing split"))
        end
    end
    return lines,"ok"
end
local function tooltipText(tip,side)
    local line=getglobal and getglobal((tip:GetName() or "GameTooltip")..side.."1")
    return line and (not line.IsShown or line:IsShown()) and cleanName(line:GetText()) or nil
end
function E:TooltipBookSpell(slot,book)
    book=book or BOOKTYPE_SPELL or "spell"
    local name,rank=self:Call(GetSpellName,slot,book)
    name=cleanName(name)
    local id=spellLink(self:Call(GetSpellLink,slot,book))
    -- Nampower supplies the ID with the exact slot and book. A bare name can
    -- select the highest learned rank, so require the original slot to match.
    if not id and name then
        local query=name..(cleanName(rank) and "("..rank..")" or "")
        local foundSlot,foundBook,foundID=self:Call(GetSpellSlotTypeIdForName,query)
        if foundSlot==slot and foundBook==book then id=spellID(foundID) end
    end
    return name,rank,id
end
function E:ResolveTooltipSpell(tip,method,a,b)
    local name,rank,id,pet,source
    if method=="SetSpell" then
        name,rank,id=self:TooltipBookSpell(a,b); pet=b==(BOOKTYPE_PET or "pet"); source="spellbook"
    elseif method=="SetSpellByID" then
        id=spellID(a); if not id then return end
    elseif method=="SetHyperlink" then
        id=spellLink(a); if not id then return end
    elseif method=="SetAction" then
        local text,kind,actionID=self:Call(GetActionText,a)
        kind=type(kind)=="string" and string.lower(kind) or nil
        if (kind and kind~="spell") or (text and not kind) then return end
        if kind=="spell" then id=spellID(actionID); source="GetActionText" end -- SuperWoW
        if not id then
            kind,actionID=self:Call(GetActionInfo,a)
            kind=type(kind)=="string" and string.lower(kind) or nil
            if kind and kind~="spell" then return end
            if kind=="spell" then id=spellID(actionID); source="GetActionInfo" end
        end
        if not id then
            -- Vanilla has no action spell ID. Match the tooltip to a unique
            -- spellbook entry; never treat an item/macro title as a spell ID.
            local candidate=tooltipText(tip,"TextLeft")
            local wanted=rankNumber(tooltipText(tip,"TextRight")); local count=0
            for slot=1,1024 do
                local n,r=self:Call(GetSpellName,slot,BOOKTYPE_SPELL or "spell")
                if not n then break end
                if cleanName(n)==candidate and (not wanted or wanted==rankNumber(r)) then
                    name,rank,id=self:TooltipBookSpell(slot,BOOKTYPE_SPELL or "spell"); count=count+1
                end
            end
            if count~=1 then return end
            source="spellbook"
        end
    else return end
    if id then
        local resolved,subtext,provider=self:SpellDisplayInfo(id)
        name=name or resolved; rank=rank or subtext
        if provider then source=(source and source.." / " or "")..provider end
        -- A confirmed spell ID remains a spell even without a name API. Read
        -- the already rendered native title/rank; this never runs for items
        -- or macros, which have been excluded above.
        if not name then name=tooltipText(tip,"TextLeft"); source=(source and source.." / " or "").."tooltip" end
        if not rank then rank=tooltipText(tip,"TextRight") end
    end
    if not name and not id then return end
    return self:Member(self.playerKey..(pet and ":pet" or "")),id,name,rankNumber(rank),source or method
end
function E:AppendSpellThreat(tip,method,a,b)
    if not self.db or not self.db.enabled or not self.db.spellThreatTooltip then return end
    local member,id,name,rank,source=self:ResolveTooltipSpell(tip,method,a,b)
    if not member then return end
    local count=self:Call(tip.NumLines,tip) or 0
    for i=1,count do
        local line=getglobal and getglobal((tip:GetName() or "GameTooltip").."TextLeft"..i)
        if line and line:GetText()==self:L("EasyThreat estimate") then return end
    end
    local lines,status=self:SpellThreatDescription(member,id,name,rank)
    self.spellTooltipLast={name=name,id=id,rank=rank,method=method,source=source,status=status,at=GetTime(),message=lines[1]}
    tip:AddLine(self:L("EasyThreat estimate"),.90,.77,.47,true)
    for _,line in ipairs(lines) do tip:AddLine(line,.90,.90,.85,true) end
    tip:Show()
end
function E:BuildSpellSettings(pane)
    pane.refreshers={}
    self:Toggle(pane,"Show spell threat","spellThreatTooltip",90)
    local text=self:Label(pane,"Spell tooltip help",11)
    text:SetPoint("TOPLEFT",pane,"TOPLEFT",16,-135); text:SetWidth(358); text:SetHeight(180); text:SetJustifyV("TOP")
end

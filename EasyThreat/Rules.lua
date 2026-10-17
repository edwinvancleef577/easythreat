-- OctoWoW documented overrides plus explicitly estimated historical baselines.
-- Spell IDs identify ranks; UI roles NEVER change threat arithmetic.
local E=EasyThreat
E.threatRules={}
local function ranks(ids,values,kind,names,pet)
    for rank,id in ipairs(ids) do
        E.threatRules[id]={kind=kind,value=type(values)=="table" and values[rank] or values,
            rank=rank,names=names,pet=pet,spell=true}
    end
end
ranks({2649,14916,14917,14918,14919,14920,14921},{50,65,110,170,240,320,415},"flat",{"Growl","Knurren"},true)
ranks({3716,7809,7810,7811,11774,11775},{45,75,125,215,300,395},"flat",{"Torment","Qual"},true)
ranks({17735,17750,17751,17752},{150,300,450,600},"flat",{"Suffering","Leiden"},true)
ranks({1742,1753,1754,1755,1756,16697},{-30,-55,-85,-125,-175,-225},"flat",{"Cower","Ducken"},true)
ranks({781,14272,14273},{-140,-280,-405},"flat",{"Disengage","Rückzug"})
ranks({20736,14274,15629,15630,15631,15632},{110,160,250,350,465,600},"flat",{"Distracting Shot","Ablenkender Schuss"})
ranks({5676,17919,17920,17921,17922,17923},1,"damage",{"Searing Pain","Sengender Schmerz"})
ranks({20473,20929,20930},1,"holy",{"Holy Shock","Heiliger Schock"})
ranks({20925,20927,20928},1.5,"holy",{"Holy Shield","Heiliger Schild"})
ranks({689,699,709,7651,11699,11700},0,"noheal",{"Drain Life","Blutsauger"})
ranks({18265,18879,18880,18881},0,"noheal",{"Siphon Life","Lebensentzug"})
ranks({6789,17925,17926},0,"noheal",{"Death Coil","Todesmantel"})
-- The class calculator says reduced threat; the older public DB says zero.
-- A zero coefficient would silently lose healing/damage threat if the new text is live.
ranks({15237,15430,15431,27799,27800,27801},0,"unresolved",{"Holy Nova","Heilige Nova"})
for _,id in ipairs({15237,15430,15431,27799,27800,27801}) do E.threatRules[id].reason="holy-nova" end
-- Damage multipliers and explicit high-rank additive amounts are historical
-- baselines; unsupported low-rank additive casts are rejected by family below.
ranks({6807,6808,6809,8972,9745,9880,9881},1.75,"damage",{"Maul","Zermalmen"})
ranks({779,780,769,9754,9908},1.75,"damage",{"Swipe","Prankenhieb"})
ranks({8042,8044,8045,8046,10412,10413,10414},2,"damage",{"Earth Shock","Erdschock"})
ranks({8092,8102,8103,8104,8105,8106,10945,10946,10947},2,"damage",{"Mind Blast","Gedankenschlag"})
ranks({1966,6768,8637,11303,25302},{-150,-240,-390,-600,-800},"flat",{"Feint","Finte"})
ranks({8998,9000,9892},{-240,-390,-600},"flat",{"Cower","Ducken"})
ranks({11597},260,"flat",{"Sunder Armor","Rüstung zerreißen"})
ranks({11567,25286},{145,173},"addDamage",{"Heroic Strike","Heldenhafter Stoß"})
ranks({11600,11601},{315,355},"addDamage",{"Revenge","Rache"})
ranks({23925},250,"addDamage",{"Shield Slam","Schildschlag"})
ranks({1672},180,"addDamage",{"Shield Bash","Schildhieb"})
for id,rank in pairs({[11597]=5,[11567]=8,[25286]=9,[11600]=5,[11601]=6,[23925]=4,[1672]=3}) do E.threatRules[id].rank=rank end
for _,id in ipairs({586,9578,9579,9592,10941,10942,1856,1857}) do
    E.threatRules[id]={kind="invalidate",spell=true,reason="temporary-reset"}
end
E.threatRules[12654]={kind="unresolved",spell=true,reason="ignite-share",names={"Ignite","Entzünden"}}
E.threatRules[19577]={kind="petInvalidate",spell=true,reason="intimidation",names={"Intimidation","Einschüchterung"}}
-- Names are resolved through IDs in the client where available; custom spell
-- families use exact names until their effect IDs have been verified.
E.customThreatRules={
    {names={"Holy Strike"},kind="holy",value=1,holyStrike=true,spell=true,class="PALADIN"},
    {names={"Exorcism","Exorzismus"},kind="unresolved",reason="exorcism",spell=true,class="PALADIN"},
    {names={"Hand of Reckoning"},kind="invalidate",reason="taunt",scope="enemy",spell=true,class="PALADIN"},
    {names={"Savage Bite"},kind="unresolved",reason="special-threat",spell=true,class="DRUID"},
    {names={"Agitating Poison"},kind="unresolved",reason="special-threat",spell=true,class="ROGUE"},
    {names={"Shadow Mend"},kind="unresolved",reason="special-threat",spell=true,class="PRIEST"},
    {names={"Piercing Shots"},kind="nothreat",value=0,spell=true,class="HUNTER"},
    {names={"Shadowguard","Schattenschild"},kind="nothreat",value=0,spell=true,class="PRIEST"},
    {names={"Sunder Armor","Rüstung zerreißen"},kind="unresolved",reason="spell-rank",spell=true,class="WARRIOR"},
    {names={"Heroic Strike","Heldenhafter Stoß"},kind="unresolved",reason="spell-rank",spell=true,class="WARRIOR"},
    {names={"Shield Slam","Schildschlag"},kind="unresolved",reason="spell-rank",spell=true,class="WARRIOR"},
    {names={"Revenge","Rache"},kind="unresolved",reason="spell-rank",spell=true,class="WARRIOR"},
    {names={"Shield Bash","Schildhieb"},kind="unresolved",reason="spell-rank",spell=true,class="WARRIOR"},
    {names={"Concussion Blow","Erschütternder Schlag"},kind="unresolved",reason="special-threat",spell=true,class="WARRIOR"},
    {names={"Cleave","Spalten","Demoralizing Shout","Demoralisierender Ruf","Battle Shout","Schlachtruf"},kind="unresolved",reason="split-threat",spell=true,class="WARRIOR"},
    {names={"Stormstrike","Sturmschlag","Lightning Strike"},kind="damage",value=1,spell=true,imbue=true,class="SHAMAN"},
}
-- Known spell IDs make the unverified families visible even without a name API.
for _,id in ipairs({879,5614,5615,10312,10313,10314}) do E.threatRules[id]=E.customThreatRules[2] end
for _,id in ipairs({7386,7405,8380,11596,78,284,285,1608,11564,11565,11566,6572,6574,7379,11600,23922,23923,23924,72,12809}) do
    if not E.threatRules[id] then E.threatRules[id]={kind="unresolved",spell=true,reason="spell-rank"} end
end
E.threatRules[5384]={kind="invalidate",names={"Feign Death","Totstellen"}}
-- Forced-target effects and threat reductions without a verified result are
-- invalidation signals, not arbitrary flat threat or an invented full reset.
for _,id in ipairs({355,6795,6360,7813,11784,11785}) do E.threatRules[id]={kind="invalidate"} end
for _,id in ipairs({355,6795}) do E.threatRules[id].scope="enemy" end
function E:ThreatRule(id,member)
    local rule=self.threatRules[tonumber(id)]
    if rule then return rule end
    local name=self:Call(GetSpellRecField,tonumber(id),"name")
    for _,entry in ipairs(self.customThreatRules) do
        if not member or entry.class==member.class then
            for _,alias in ipairs(entry.names) do if name==alias then return entry end end
        end
    end
end
function E:RuleForText(member,name)
    if not name or not member then return end
    if not self.ruleNames or self.ruleNameProvider~=GetSpellRecField then
        self.ruleNameProvider=GetSpellRecField; self.ruleNames={}
        for id,rule in pairs(self.threatRules) do
            local names={}
            for _,alias in ipairs(rule.names or {}) do names[alias]=true end
            local localized=self:Call(GetSpellRecField,id,"name")
            if type(localized)=="string" and localized~="" then names[localized]=true end
            for alias in pairs(names) do
                self.ruleNames[alias]=self.ruleNames[alias] or {}
                table.insert(self.ruleNames[alias],rule)
            end
        end
    end
    local rank
    -- Pet spellbook exposes the actual learned rank even when combat text does
    -- not. Player books often contain several ranks; never pick the highest.
    if member.unit=="pet" and type(GetSpellName)=="function" then
        for i=1,80 do
            local spell,rankText=self:Call(GetSpellName,i,BOOKTYPE_PET or "pet")
            if not spell then break end
            if spell==name and type(rankText)=="string" then
                local _,_,n=string.find(rankText,"(%d+)"); rank=tonumber(n)
            end
        end
    end
    local result,ambiguous
    for _,rule in ipairs(self.ruleNames[name] or {}) do
        if (not rule.pet or member.pet) and not (member.pet and not rule.pet and rule.names and rule.names[1]=="Cower") then
            if rule.kind=="damage" or rule.kind=="holy" or rule.kind=="invalidate" or rule.kind=="noheal" or
                rule.kind=="nothreat" or rule.kind=="unresolved" or rule.kind=="petInvalidate" or rank==rule.rank then
                if result and (result.kind~=rule.kind or result.value~=rule.value) then ambiguous=true end
                result=rule
            end
        end
    end
    if result and not ambiguous then return result end
    for _,rule in ipairs(self.customThreatRules) do
        if not rule.class or rule.class==member.class then
            for _,alias in ipairs(rule.names) do if name==alias then return rule end end
        end
    end
    if self.ruleNames[name] then return {kind="unresolved",spell=true,reason="spell-rank"} end
end

function E:HasThreatBuff(member,icon) return self:BuffByIcon(member,icon) end
function E:ThreatMultiplier(member,school,rule)
    if rule and rule.kind=="nothreat" then return 0 end
    local value=rule and (rule.kind=="damage" or rule.kind=="holy") and rule.value or 1
    if rule and rule.kind=="holy" then school="holy" end
    local class,reason=self:ClassMultiplier(member,school,rule,false)
    if not class then return nil,reason end
    return value*class
end
function E:HealingThreatMultiplier(member,rule,school)
    if rule and (rule.kind=="noheal" or rule.kind=="nothreat") then return 0 end
    local class,reason=self:ClassMultiplier(member,school,rule,true)
    if not class then return nil,reason end
    return 0.5*(not member.pet and member.class=="PALADIN" and 0.5 or 1)*class
end

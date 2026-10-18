-- Optional, deliberately low-confidence damage-ratio preview. This is NOT a
-- class-complete threat engine. Disabled by default; every value carries '~'.
local E = EasyThreat
function E:CompileFormat(format)
    if type(format) ~= "string" then return nil end
    local pattern, order, index, implicit = "^", {}, 1, 0
    while index <= string.len(format) do
        local char=string.sub(format,index,index)
        if char=="%" then
            local a,b,position,kind=string.find(format,"^%%(%d+)%$([sd])",index)
            if not a then
                a,b,kind=string.find(format,"^%%([sd])",index)
                if a then implicit=implicit+1; position=implicit end
            end
            if a then
                table.insert(order,tonumber(position))
                pattern=pattern .. (kind=="d" and "(%d+)" or "(.-)")
                index=b+1
            elseif string.sub(format,index+1,index+1)=="%" then
                pattern=pattern .. "%%"; index=index+2
            else return nil end
        else
            if string.find("^$()%.[]*+-?",char,1,true) then pattern=pattern .. "%" end
            pattern=pattern .. char; index=index+1
        end
    end
    return pattern,order -- allow Blizzard's absorbed/resisted suffixes
end
function E:InitFormats()
    self.formats={}
    self.healFormats={}
    local specs={
        -- Spell messages must precede generic melee patterns: "%s hits ..."
        -- also matches "Your Shadow Bolt hits ..." and "Imp's Firebolt hits ...".
        -- Taking that match first invents an actor named "Imp's Firebolt" and
        -- silently drops the real caster's threat (and the pet's second row).
        {"SPELLLOGSELFOTHER",0,2,3,1}, {"SPELLLOGCRITSELFOTHER",0,2,3,1},
        {"SPELLLOGSCHOOLSELFOTHER",0,2,3,1,4}, {"SPELLLOGCRITSCHOOLSELFOTHER",0,2,3,1,4},
        {"SPELLLOGOTHEROTHER",1,3,4,2}, {"SPELLLOGCRITOTHEROTHER",1,3,4,2},
        {"SPELLLOGSCHOOLOTHEROTHER",1,3,4,2,5}, {"SPELLLOGCRITSCHOOLOTHEROTHER",1,3,4,2,5},
        {"PERIODICAURADAMAGESELFOTHER",0,1,2,4,3}, {"PERIODICAURADAMAGEOTHEROTHER",4,1,2,5,3},
        {"COMBATHITSELFOTHER",0,1,2}, {"COMBATHITCRITSELFOTHER",0,1,2},
        {"COMBATHITSCHOOLSELFOTHER",0,1,2,nil,3}, {"COMBATHITCRITSCHOOLSELFOTHER",0,1,2,nil,3},
        {"COMBATHITOTHEROTHER",1,2,3}, {"COMBATHITCRITOTHEROTHER",1,2,3},
        {"COMBATHITSCHOOLOTHEROTHER",1,2,3,nil,4}, {"COMBATHITCRITSCHOOLOTHEROTHER",1,2,3,nil,4}
    }
    for _, spec in ipairs(specs) do
        local pattern,order=self:CompileFormat(_G[spec[1]])
        if pattern then table.insert(self.formats,{pattern=pattern,order=order,actor=spec[2],victim=spec[3],amount=spec[4],spell=spec[5],school=spec[6]}) end
    end
    for _,spec in ipairs({
        {"HEALEDSELFSELF",0,0,2,1},{"HEALEDCRITSELFSELF",0,0,2,1},
        {"HEALEDSELFOTHER",0,2,3,1},{"HEALEDCRITSELFOTHER",0,2,3,1},
        {"HEALEDOTHERSELF",1,0,3,2},{"HEALEDCRITOTHERSELF",1,0,3,2},
        {"HEALEDOTHEROTHER",1,3,4,2},{"HEALEDCRITOTHEROTHER",1,3,4,2},
        {"PERIODICAURAHEALSELFSELF",0,0,1,2},{"PERIODICAURAHEALSELFOTHER",0,1,2,3},
        {"PERIODICAURAHEALOTHERSELF",2,0,1,3},{"PERIODICAURAHEALOTHEROTHER",3,1,2,4}
    }) do
        local pattern,order=self:CompileFormat(_G[spec[1]])
        if pattern then table.insert(self.healFormats,{pattern=pattern,order=order,actor=spec[2],victim=spec[3],amount=spec[4],spell=spec[5]}) end
    end
end
function E:ParseHeal(message)
    for _,format in ipairs(self.healFormats or {}) do
        local captures={string.find(message,format.pattern)}
        if captures[1] then
            local values={}
            for i,position in ipairs(format.order) do values[position]=captures[i+2] end
            return format.actor==0 and self.playerKey or values[format.actor],
                format.victim==0 and self.playerKey or values[format.victim],tonumber(values[format.amount]),values[format.spell]
        end
    end
end
function E:ParseDamage(message)
    for _, format in ipairs(self.formats or {}) do
        local captures={string.find(message,format.pattern)}
        if captures[1] then
            local values={}
            for i,position in ipairs(format.order) do values[position]=captures[i+2] end
            local actor=format.actor==0 and self.playerKey or values[format.actor]
            local school=format.school and values[format.school]
            return actor,values[format.victim],tonumber(values[format.amount]),format.spell and values[format.spell],self:SchoolForText(school)
        end
    end
end
function E:RecordDamage(message)
    if not self.db.estimates or self.demo then return end
    local actor,victim,amount=self:ParseDamage(message)
    if not actor or not victim or not amount or amount<=0 then return end
    local member
    for _, entry in ipairs(self.roster) do
        if actor==entry.name then
            if member then return end -- pets can share a name
            member=entry
        end
    end
    if not member then return end
    local matches, enemyKey=0,nil
    local seen={}
    -- GUIDs are mandatory for accumulating data across target changes.
    for _, unit in ipairs(self.knownUnits or {}) do
        if self:Call(UnitName,unit)==victim and self:Call(UnitCanAttack,"player",unit) then
            local guid=self:GUID(unit)
            if not guid then return end
            if not seen[guid] then matches=matches+1; enemyKey=guid; seen[guid]=true end
        end
    end
    if matches~=1 then return end
    self.damage=self.damage or {}
    local data=self.damage[enemyKey]
    if not data then data={values={},updated=GetTime()}; self.damage[enemyKey]=data end
    data.values[member.key]=(data.values[member.key] or 0)+amount
    data.updated=GetTime()
end
function E:ApplyEstimate(enemy)
    local data=self.damage and self.damage[enemy.key]
    if not data or not enemy.owner or GetTime()-data.updated>12 then return end
    local baseline=data.values[enemy.owner.key]
    if not baseline or baseline<=0 then return end
    for key,damage in pairs(data.values) do
        if not enemy.samples[key] then
            -- Conservative 110% assumption; unknown distance, modifiers, healing,
            -- taunts and flat spell threat mean this must stay an estimate.
            enemy.samples[key]={pct=self:Clamp(damage/baseline/1.1*100,0,100),quality="estimate"}
        end
    end
end

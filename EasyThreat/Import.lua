local E=EasyThreat
-- A bounded data parser, deliberately independent of Lua's compiler/evaluator.
-- Accept the export grammar and ordinary SavedVariables table keys, never code.
function E:ParseSettings(text)
    local pos,nodes=1,0
    local function fail(code,path) error({code=code,pos=pos,path=path}) end
    local function parse()
        if type(text)~="string" or string.len(text)>524288 then fail("size") end
        local length=string.len(text)
        local function char() return string.sub(text,pos,pos) end
        local function skip()
            while pos<=length do
                if string.find(char(),"%s") then pos=pos+1
                elseif string.sub(text,pos,pos+1)=="--" then
                    local finish=string.find(text,"\n",pos+2,true)
                    pos=finish and finish+1 or length+1
                else return end
            end
        end
        local function take(token)
            skip()
            if string.sub(text,pos,pos+string.len(token)-1)~=token then fail("syntax") end
            pos=pos+string.len(token)
        end
        local function quoted()
            local quote=char(); pos=pos+1
            local out={}
            while pos<=length do
                local c=char(); pos=pos+1
                if c==quote then return table.concat(out) end
                if c=="\\" then
                    c=char(); pos=pos+1
                    local escapes={a="\a",b="\b",f="\f",n="\n",r="\r",t="\t",v="\v"}
                    if escapes[c] then c=escapes[c]
                    elseif c=="\r" then if char()=="\n" then pos=pos+1 end; c="\n"
                    elseif string.find(c,"%d") then
                        local digits=c
                        for i=1,2 do
                            if string.find(char(),"%d") then digits=digits..char(); pos=pos+1 else break end
                        end
                        local number=tonumber(digits)
                        if number>255 then fail("syntax") end
                        c=string.char(number)
                    elseif c~="\\" and c~='"' and c~="'" and c~="\n" then fail("syntax") end
                elseif c=="\n" then fail("syntax") end -- Lua 5.0 %q can contain a literal CR.
                table.insert(out,c)
            end
            fail("syntax")
        end
        local value
        value=function(depth)
            skip(); nodes=nodes+1
            if depth>12 or nodes>16000 then fail("size") end
            local c=char()
            if c=='"' or c=="'" then return quoted() end
            if c=="{" then
                pos=pos+1; skip()
                local result={}
                while char()~="}" do
                    local key
                    if char()=="[" then
                        pos=pos+1; key=value(depth+1); take("]")
                    else
                        local _,finish,identifier=string.find(text,"^([%a_][%w_]*)",pos)
                        local begin=string.find(text,"^[%a_]",pos)
                        if begin~=pos then fail("syntax") end
                        key=identifier; pos=finish+1
                    end
                    if type(key)~="string" and type(key)~="number" then fail("syntax") end
                    if result[key]~=nil then fail("duplicate") end
                    take("="); result[key]=value(depth+1); skip()
                    if char()=="," or char()==";" then pos=pos+1; skip()
                    elseif char()~="}" then fail("syntax") end
                end
                pos=pos+1; return result
            end
            for _,word in ipairs({"true","false"}) do
                if string.sub(text,pos,pos+string.len(word)-1)==word then
                    pos=pos+string.len(word); return word=="true"
                end
            end
            local begin,finish,number=string.find(text,"^([%+%-]?%d+%.?%d*[eE][%+%-]?%d+)",pos)
            if begin~=pos then begin,finish,number=string.find(text,"^([%+%-]?%d+%.?%d*)",pos) end
            if begin~=pos then fail("syntax") end
            pos=finish+1; number=tonumber(number)
            if not number or number-number~=0 then fail("value") end
            return number
        end
        skip()
        if char()~="{" then take("EasyThreatDB"); take("=") end
        local result=value(0); skip()
        if type(result)~="table" then fail("syntax") end
        if char()==";" then pos=pos+1; skip() end
        if pos<=length then fail("syntax") end
        return result
    end
    local ok,result=pcall(parse)
    if ok then return result end
    return nil,type(result)=="table" and result or {code="syntax",pos=pos}
end

function E:ValidateSettings(data)
    local function fail(code,path) error({code=code,path=path}) end
    local function named(key,path)
        if type(key)~="string" or key=="" or string.len(key)>4096 or string.find(key,"[%c]") then fail("value",path) end
    end
    local function map(value,path,visit)
        if type(value)~="table" then fail("type",path) end
        for key,item in pairs(value) do named(key,path); visit(key,item,path.."."..key) end
    end
    local function role(value,path)
        if value~="tank" and value~="heal" and value~="damage" then fail("value",path) end
    end
    local function boolean(value,path) if type(value)~="boolean" then fail("type",path) end end
    local function validate()
        if type(data)~="table" or next(data)==nil then fail("syntax") end
        local known=0
        for key,value in pairs(data) do
            local expected=E.defaults[key]
            if expected~=nil then
                known=known+1
                if type(value)~=type(expected) then fail("type",tostring(key)) end
                local range=E.settingRanges[key]
                if range and (value-value~=0 or value<range[1] or value>range[2]) then fail("value",key) end
                if (key=="maxRows" or key=="maxCandidates" or key=="otherBars") and value~=math.floor(value) then fail("value",key) end
            elseif key=="layoutVersion" or key=="revision" or key=="tooltipLayoutVersion" or key=="tooltipWidthVersion" or key=="journalScopeVersion" then
                local maximum=(key=="layoutVersion" or key=="revision") and 2 or 1
                if type(value)~="number" or value<0 or value>maximum or value~=math.floor(value) then fail("version",key) end
            else fail("unknown",tostring(key)) end
        end
        if known==0 then fail("syntax") end
        if data.language and data.language~="auto" and not E.translations[data.language] then fail("value","language") end
        if data.font and data.font~="native" and not E.fontPaths[data.font] then fail("value","font") end
        if data.filters then map(data.filters,"filters",function(group,values,path)
            if not E.filterDefaults[group] then fail("unknown",path) end
            map(values,path,function(key,item,field)
                if E.filterDefaults[group][key]==nil then fail("unknown",field) end
                boolean(item,field)
            end)
        end) end
        if data.roleViews then map(data.roleViews,"roleViews",function(key,values,path)
            role(key,path)
            map(values,path,function(output,item,field)
                if output~="list" and output~="tooltip" and output~="target" and output~="overhead" then fail("unknown",field) end
                boolean(item,field)
            end)
        end) end
        for key,allowed in pairs({journalViews={stock=true,spend=true,healing=true,damage=true},
            journalFilters={damage=true,heal=true,aggro=true,item=true,cooldown=true,death=true,threat=true}}) do
            if data[key] then map(data[key],key,function(field,item,path)
                if not allowed[field] then fail("unknown",path) end
                boolean(item,path)
            end) end
        end
        if data.colors then map(data.colors,"colors",function(key,values,path)
            if type(values)~="table" then fail("type",path) end
            for component,item in pairs(values) do
                if component~=1 and component~=2 and component~=3 then fail("unknown",path) end
                if type(item)~="number" or item-item~=0 or item<0 or item>1 then fail("value",path) end
            end
            if values[1]==nil or values[2]==nil or values[3]==nil then fail("value",path) end
        end) end
        if data.petRoles then map(data.petRoles,"petRoles",function(key,item,path) role(item,path) end) end
        if data.petMigrated then map(data.petMigrated,"petMigrated",function(key,item,path) boolean(item,path) end) end
        if data.groups then map(data.groups,"groups",function(key,profile,path)
            map(profile,path,function(field,item,entry)
                if field=="roles" then map(item,entry,function(name,r,p) role(r,p) end)
                elseif field=="activePets" then map(item,entry,function(name,identity,p) named(identity,p) end)
                elseif field=="mode" then if item~="personal" and item~="tank" then fail("value",entry) end
                elseif field=="used" then
                    if type(item)~="number" or item-item~=0 or item<0 or item>1000000000000 then fail("value",entry) end
                else fail("unknown",entry) end
            end)
        end) end
        return data
    end
    local ok,result=pcall(validate)
    if ok then return result end
    return nil,type(result)=="table" and result or {code="type"}
end

local function copy(value)
    if type(value)~="table" then return value end
    local result={}; for key,item in pairs(value) do result[key]=copy(item) end; return result
end
function E:ApplySettings(data)
    if self:Call(UnitAffectingCombat,"player") or self:Call(UnitAffectingCombat,"pet") then return nil,{code="combat"} end
    local old=self.db
    local function activate(settings)
        EasyThreatDB=settings; E.db=settings; E.groupKey=nil; E.profile=nil
        E.demo=nil; E.liveRoster=nil; E.layoutPreview=nil; E.tooltipSample=nil
        E.visibility={}; E.pairVisibility={}; E:ResetThreatSources(); E:InitDB()
        if E.window then
            E:CloseDropdown()
            -- Invalidate any old picker callback before replacing its data model.
            E.colorEdit=nil; E.deletedColor=nil
            if ColorPickerFrame then ColorPickerFrame:Hide() end
            E:SetLanguage(E.db.language); E:LayoutChanged(); E:PositionMinimap()
        end
    end
    local ok=pcall(function() activate(data) end)
    if not ok then
        EasyThreatDB=old; self.db=old
        pcall(function() activate(old) end)
        return nil,{code="apply"}
    end
    return true
end
function E:ImportSettings(text)
    local data,problem=self:ParseSettings(text)
    if not data then return nil,problem end
    data,problem=self:ValidateSettings(data)
    if not data then return nil,problem end
    -- Partial pastes merge into a snapshot; full exports replace nested maps,
    -- including empty color/profile maps. Diagnostic recordings are retained locally.
    local merged=copy(self.db)
    for key,value in pairs(data) do merged[key]=value end
    local old=self.db
    local ok; ok,problem=self:ApplySettings(merged)
    if not ok then return nil,problem end
    self.importUndo=old; self:UpdateDiagnostics()
    return true
end
function E:UndoSettingsImport()
    if not self.importUndo then return nil,{code="apply"} end
    local ok,problem=self:ApplySettings(copy(self.importUndo))
    if ok then self.importUndo=nil; self:UpdateDiagnostics() end
    return ok,problem
end
function E:ImportMessage(problem)
    local messages={combat="Import settings outside combat.",size="Import too large or too deeply nested.",syntax="Invalid settings text. Paste a complete EasyThreat export.",
        duplicate="Duplicate setting in pasted text.",type="Wrong setting type",value="Setting outside allowed values",
        unknown="Unknown setting",version="Unsupported settings version",apply="Could not apply settings. Previous settings restored."}
    local message=self:L(messages[problem.code] or messages.syntax)
    if problem.path then message=message..": "..string.gsub(self:ShortName(problem.path,70),"|","/") end
    if problem.pos then message=message.." ("..problem.pos..")" end
    return message
end
function E:ShowSettingsImport()
    local pane=self.pages and self.pages.diagnostics
    if not pane then return end
    if not pane.exportPanel then self:BuildSettingsExport(pane) end
    self:OpenSettingsTransfer("import","")
end

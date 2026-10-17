local E=EasyThreat
E.filterDefaults={
    context={solo=false,party=true,raid=false},
    level={gray=false,green=false,yellow=true,orange=true,red=true},
    kind={normal=true,rare=true,elite=true,rareelite=true,worldboss=true,other=true}
}
function E:InitFilters()
    for group,values in pairs(self.filterDefaults) do
        if type(self.db.filters[group])~="table" then self.db.filters[group]={} end
        for key,value in pairs(values) do
            if type(self.db.filters[group][key])~="boolean" then self.db.filters[group][key]=value end
        end
    end
end
function E:GroupContext()
    if (self:Call(GetNumRaidMembers) or 0)>0 then return "raid" end
    if (self:Call(GetNumPartyMembers) or 0)>0 then return "party" end
    return "solo"
end
function E:LevelBand(level,classification)
    if classification=="worldboss" or level==-1 then return "red" end
    local own=self:Call(UnitLevel,"player")
    -- Missing metadata is unknown, never an invented gray enemy.
    if type(level)~="number" or level<1 or type(own)~="number" or own<1 then return nil end
    local difference=level-own
    if difference>=5 then return "red" end
    if difference>=3 then return "orange" end
    if difference>=-2 then return "yellow" end
    local range=self:Call(GetQuestGreenRange)
    if type(range)~="number" then return nil end
    return -difference<=range and "green" or "gray"
end
function E:EnemyAllowed(enemy,output)
    if self.demo or self.layoutPreview then return true end
    local filter=self.db and self.db.filters
    if not filter or not filter.context then return true end
    local context=self:GroupContext()
    if not filter.context[context] then return false,"context" end
    local kind=enemy.classification or "normal"
    if self.filterDefaults.kind[kind]==nil then kind="other" end
    if not filter.kind[kind] then return false,"kind" end
    local band=self:LevelBand(enemy.level,enemy.classification)
    if band and not filter.level[band] then return false,"level" end
    if output=="list" and context=="raid" and self.db.raidMarkedOnly and not enemy.mark then return false,"mark" end
    return true
end
function E:FiltersChanged()
    self.tooltipSample=nil; self.visibility={}; self.pairVisibility={}; self:RefreshUI()
end
function E:BuildFilters(pane)
    pane.refreshers={}; pane.filters={}
    local function section(group,title,options,y,columns)
        local heading=E:Label(pane,title,11); heading:SetPoint("TOPLEFT",pane,"TOPLEFT",16,-y)
        local width=358/columns
        pane.filters[group]={}
        for i,option in ipairs(options) do
            local key=option[1]
            local x=16+math.mod(i-1,columns)*width
            local top=y+20+math.floor((i-1)/columns)*52
            local label=E:Label(pane,option[2],10)
            label:SetWidth(width-5); label:SetHeight(19); label:SetJustifyH("CENTER")
            label:SetPoint("TOPLEFT",pane,"TOPLEFT",x,-top)
            local button=E:Place(pane,E:Button(pane,"",width-5,23,function()
                E.db.filters[group][key]=not E.db.filters[group][key]; E:FiltersChanged()
                for _,refresh in ipairs(pane.refreshers) do refresh() end
            end),x,top+20)
            pane.filters[group][key]=button
            table.insert(pane.refreshers,function() E:SetToggleState(button,E.db.filters[group][key]) end)
        end
    end
    section("context","Play context",{{"solo","Solo"},{"party","Party"},{"raid","Raid"}},85,3)
    section("level","Enemy level",{{"gray","Gray"},{"green","Green"},{"yellow","Yellow"},{"orange","Orange"},{"red","Red"}},161,5)
    section("kind","Enemy type",{{"normal","Normal"},{"rare","Rare"},{"elite","Elite"},
        {"rareelite","Rare elite"},{"worldboss","Boss"},{"other","Other types"}},237,3)
    self:Toggle(pane,"Raid list: marked enemies only","raidMarkedOnly",378)
    local hint=self:Label(pane,"Target frame stays visible in combat.",10)
    hint:SetWidth(358); hint:SetHeight(24); hint:SetPoint("TOPLEFT",pane,"TOPLEFT",16,-410)
end

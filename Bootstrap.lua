local E=EasyThreat
function E:DemoData()
    local me=self:Member(self.playerKey)
    if not me then return end
    -- Demo uses an isolated roster and never writes fake roles or saved settings.
    self.liveRoster=self.liveRoster or self.roster
    local a={key="demo:a",name="Hunter",class="HUNTER",alive=true,connected=true}
    local b={key="demo:b",name="Warlock",class="WARLOCK",alive=true,connected=true}
    local p={key="demo:p",name="Wolf",owner="Hunter",pet=true,class="HUNTER",alive=true,connected=true}
    self.roster={me,a,b,p}
    self.enemies={
        ["demo:1"]={key="demo:1",name="Defiasbandit",mark=8,combat=true,owner=me,ownerQuality="api",samples={
            [a.key]={pct=93,quality="api"},[b.key]={pct=71,quality="api"},[p.key]={pct=65,quality="api"}}},
        ["demo:2"]={key="demo:2",name="Junger Wolf",mark=7,combat=true,owner=b,ownerQuality="api",samples={
            [a.key]={pct=88,quality="api"}}},
        ["demo:3"]={key="demo:3",name="Koboldarbeiter",mark=5,combat=false,samples={}}
    }
end
function E:ToggleDemo()
    self.demo=not self.demo
    if self.demo then
        self:DemoData(); self:Print(self:L("Demo values") .. " - /et demo")
    else
        if self.liveRoster then self.roster=self.liveRoster end
        self.liveRoster=nil; self.enemies={}; self:RefreshRoster()
        self:Print(self:L("Demo off"))
    end
    self:RefreshUI()
end
function E:Command(message)
    local _,_,command,rest=string.find(message or "","^%s*(%S*)%s*(.-)%s*$")
    command=string.lower(command or "")
    if command=="" or command=="roles" then self:ShowPage("roles")
    elseif command=="appearance" then self:ShowPage("appearance")
    elseif command=="list" then self:ShowPage("list")
    elseif command=="filters" then self:ShowPage("filters")
    elseif command=="config" then self:ShowPage("settings")
    elseif command=="colors" then self:ShowPage("colors")
    elseif command=="positions" then self:ShowPage("positions")
    elseif command=="resetpositions" then self:ResetPositions()
    elseif command=="status" or command=="debug" then self:Status()
    elseif command=="record" then self:RecordingCommand(rest)
    elseif command=="test" then self:SourceTestCommand(rest)
    elseif command=="trace" then
        if rest=="on" then self.traceEnabled=true; self.db.trace={}; self:Print(self:L("Trace recording started"))
        elseif rest=="off" then self.traceEnabled=false; self:Print(self:L("Trace recording stopped"))
        elseif rest=="show" then
            for _,line in ipairs(self.db.trace or {}) do self:Print(string.gsub(line,"|","/")) end
        elseif rest=="clear" then self.db.trace={}; self:Print(self:L("Trace cleared"))
        else self:Print("/et trace on|off|show|clear") end
    elseif command=="tank" then self:SetRole(self.playerKey,"tank")
    elseif command=="personal" or command=="solo" then self:SetRole(self.playerKey,"damage")
    elseif command=="heal" then self:SetRole(self.playerKey,"heal")
    elseif command=="demo" then
        if self:Call(UnitAffectingCombat,"player") then self:Print(self:L("Preview outside combat")) else self:ToggleDemo() end
    elseif command=="unlock" or command=="lock" then self.db.locked=command=="lock"; self:RefreshUI()
    elseif command=="clear" then self.enemies={}; self:ResetThreatSources(); self.visibility={}; self.pairVisibility={}; self:RefreshUI()
    elseif command=="position" then self:ShowPage("positions")
    elseif command=="minimap" then self.db.minimap=not self.db.minimap; self:PositionMinimap()
    elseif command=="square" then self.db.squareMinimap=not self.db.squareMinimap; self:PositionMinimap()
    elseif command=="threshold" and tonumber(rest) then
        self.db.threshold=self:Clamp(tonumber(rest),0,95); self:RefreshUI()
        self:Print(self:L("Show threat from (%)") .. ": " .. self.db.threshold)
    elseif command=="offset" and tonumber(rest) then
        self.db.overheadY=self:Clamp(tonumber(rest),-100,150); self:RefreshUI()
    else self:Print("/et [roles|config|list|appearance|colors|positions|resetpositions|tank|personal|demo|status|lock|unlock|clear|minimap|square|threshold 60|offset 12]") end
end
SLASH_EASYTHREAT1="/et"
SLASH_EASYTHREAT2="/easythreat"
SlashCmdList["EASYTHREAT"]=function(message) if E.db then E:Command(message) end end

local frame=CreateFrame("Frame","EasyThreatEvents",UIParent)
E.eventFrame=frame
local events={"ADDON_LOADED","PLAYER_ENTERING_WORLD","PARTY_MEMBERS_CHANGED","RAID_ROSTER_UPDATE","UNIT_PET",
    "PLAYER_REGEN_DISABLED","PLAYER_REGEN_ENABLED","RAID_TARGET_UPDATE","PLAYER_TARGET_CHANGED","CHAT_MSG_ADDON","CHAT_MSG_MONSTER_EMOTE","UPDATE_MOUSEOVER_UNIT","CHARACTER_POINTS_CHANGED","SPELLS_CHANGED"}
for _, name in ipairs(events) do frame:RegisterEvent(name) end
local logs={"CHAT_MSG_COMBAT_SELF_HITS","CHAT_MSG_COMBAT_PET_HITS","CHAT_MSG_COMBAT_PARTY_HITS",
    "CHAT_MSG_COMBAT_FRIENDLYPLAYER_HITS","CHAT_MSG_SPELL_SELF_DAMAGE","CHAT_MSG_SPELL_PET_DAMAGE",
    "CHAT_MSG_SPELL_PARTY_DAMAGE","CHAT_MSG_SPELL_FRIENDLYPLAYER_DAMAGE",
    "CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE","CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE",
    "CHAT_MSG_SPELL_SELF_BUFF","CHAT_MSG_SPELL_PET_BUFF","CHAT_MSG_SPELL_PARTY_BUFF","CHAT_MSG_SPELL_FRIENDLYPLAYER_BUFF",
    "CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS","CHAT_MSG_SPELL_PERIODIC_PARTY_BUFFS","CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_BUFFS"}
for _, name in ipairs(logs) do frame:RegisterEvent(name) end
frame:SetScript("OnEvent",function()
    if event=="ADDON_LOADED" and arg1=="EasyThreat" then
        E:InitDB(); E:InitFormats(); E:InitLocalThreat(); E:InitUI(); E:InitThreatTooltip(); E:InitConfig(); E:PositionMinimap()
        E:InitRecording(); E:InitJournal()
        E:Print(E.version .. " - /et")
    elseif E.db then
        if event=="CHARACTER_POINTS_CHANGED" or event=="SPELLS_CHANGED" then
            E:ClassTalentsChanged()
        elseif event=="UPDATE_MOUSEOVER_UNIT" then
            if E:Call(GetMouseFocus)==WorldFrame then E:ClearThreatTooltip(true); E.tooltipNonUnit=nil end
        elseif event=="CHAT_MSG_MONSTER_EMOTE" then
            E:ObserveFleeEmote(arg1,arg2)
        elseif event=="CHAT_MSG_ADDON" then
            E:NoteSourceMessage(arg1,arg2,arg3,arg4)
            if E.db.enabled and not E.demo then
                if E.groupRecorder and arg1==E.groupRecorder.prefix then
                    local ok=pcall(function() E.groupRecorder:Receive(arg2,arg3,arg4) end)
                    if not ok then E.groupRecorder.captureError=true end
                elseif not E:ReceivePeer(arg1,arg2,arg3,arg4) then E:ReceiveServerThreat(arg1,arg2,arg3,arg4) end
            end
        elseif event=="PARTY_MEMBERS_CHANGED" or event=="RAID_ROSTER_UPDATE" or event=="UNIT_PET" then
            if E.demo then E:ToggleDemo() end
            E:RefreshRoster(); E:UpdateRoles(); E:UpdateColors()
        elseif event=="PLAYER_ENTERING_WORLD" or event=="RAID_TARGET_UPDATE" then
            E:ClearOverlays(); E.nativePlates={}
            E.enemies={}; E.visibility={}
            if event=="PLAYER_ENTERING_WORLD" then E:ResetThreatSources(); E:RefreshRoster() end
            if event=="PLAYER_ENTERING_WORLD" and E.recorder and E.recorder.db and E.recorder.db.fileExportPending then
                E.recorder.db.fileExportPending=nil
                E:ShowSavedVariablesExport(nil,true)
                E.pages.diagnostics.exportPanel.hint:SetText(E:L("UI reloaded. Copy the saved file from the path below."))
            end
        elseif event=="PLAYER_REGEN_DISABLED" then
            E.layoutPreview=nil
            if E.demo then E:ToggleDemo() end
            E:RefreshUI(); E:UpdatePositions()
        elseif event=="PLAYER_TARGET_CHANGED" then
            -- Unit tokens without GUIDs can be recycled for a different mob.
            if not E:GUID("target") then E.targetHistory={}; E.displayQuantities={} end
            E:ThreatTargetChanged(); E.pairVisibility={}
            E:ClearOverlays(); E.nativePlates={}
            for _, enemy in pairs(E.enemies) do
                if not enemy.guid then enemy.stale=true; enemy.combat=false; enemy.samples={}; enemy.owner=nil end
            end
        elseif event=="PLAYER_REGEN_ENABLED" then
            -- Some party mobs still fight after this player leaves combat.
            local any=false
            for _, m in ipairs(E.roster) do if E:Call(UnitAffectingCombat,m.unit) then any=true end end
            if not any then E:ResetThreatSources() end
        elseif string.find(event,"^CHAT_MSG_") and type(arg1)=="string" then
            if E.db.enabled then E:RecordLocalText(arg1); E:RecordDamage(arg1) end
        else
            E:StructuredThreatEvent(event,arg1,arg2,arg3,arg4,arg5,arg6,arg7,arg8,arg9)
        end
        E.elapsed=event=="PLAYER_TARGET_CHANGED" and 0 or 0.2
    end
end)
frame:SetScript("OnUpdate",function()
    if not E.db then return end
    E.elapsed=(E.elapsed or 0)+(arg1 or 0)
    if E.elapsed<0.2 then return end
    E.elapsed=0
    E:SourceTestTick()
    if E.layoutPreview and E:AnyCombat() then E.layoutPreview=nil; E:RefreshUI(); E:UpdatePositions() end
    if E.db.enabled then
        E:RefreshRoster()
        if GetTime()-(E.lastTooltipHookCheck or -10)>1 then
            E.lastTooltipHookCheck=GetTime(); E:InitThreatTooltip()
            if E.window and E.window:IsShown() and E.window.page=="diagnostics" then E:UpdateDiagnostics() end
        end
        if E.demo then E:DemoData(); E:RefreshUI() else E:Scan() end
        for key,data in pairs(E.damage or {}) do if GetTime()-data.updated>30 then E.damage[key]=nil end end
    end
end)

-- Diagnose observed capabilities, not presumed dependencies on a UI skin.
local E=EasyThreat
function E:AddonInventory()
    local out={}
    local count=self:Call(GetNumAddOns)
    if type(count)~="number" or type(GetAddOnInfo)~="function" then return out,false end
    for i=1,count do
        local ok,name,title,notes,enabled,loadable,reason=pcall(GetAddOnInfo,i)
        if ok and type(name)=="string" then
            out[string.lower(name)]={name=name,enabled=enabled==1 or enabled==true,
                loadable=loadable==1 or loadable==true,reason=reason,
                loaded=self:Call(IsAddOnLoaded,name) and true or false}
        end
    end
    return out,true
end
function E:AddonLoadReason(addon)
    if not addon.enabled then return ADDON_DISABLED or self:L("Off") end
    if addon.reason then return _G["ADDON_"..addon.reason] or addon.reason end
    return self:L("Reload UI")
end
function E:UpdateEventHealth()
    if not self.db.enabled or self.demo or not self:AnyCombat() then self.combatEventWatch=nil; return end
    if not self.combatEventWatch then
        self.combatEventWatch={at=GetTime()}
    end
end
function E:AppendDependencyDiagnosis(add)
    local caps=self:Capabilities()
    if not caps.guid then
        add("GUID access missing. Local percentages need client extensions; check the launcher's Mods page.",nil,nil,"error")
    else add("GUID access is working.") end
    if self.db.localThreat and type(GetSpellRecField)~="function" then
        add("Spell data missing. Check Nampower in the launcher; some class rules are unavailable.",nil,nil,"warning")
    end
    local support=self.structuredRegistration
    local damage=support and (support.AUTO_ATTACK_SELF or support.AUTO_ATTACK_OTHER or
        support.SPELL_DAMAGE_EVENT_SELF or support.SPELL_DAMAGE_EVENT_OTHER)
    local watch=self.combatEventWatch
    local received=(self.sourceStats and self.sourceStats.structured or 0)>0
    if self.db.localThreat then
        if received then add("Structured combat events have been received.")
        elseif self.sourceStats and (self.sourceStats["local-event"] or 0)>0 then
            add("Combat text fallback is active. No structured combat events received.")
        elseif support and not damage then
            add("Structured combat events are unsupported. Check Nampower in the launcher and restart the game.",nil,nil,"warning")
        elseif watch and GetTime()-watch.at>=5 then
            add("No structured events in this fight yet. Check Nampower in the launcher; text fallback may be limited.",nil,nil,"warning")
        else add("Combat events not tested yet. Fight briefly, then reopen Diagnostics.") end
    end
    if self:ViewMode()=="personal" then
        add("Personal bars appear from %d%%. Set 0%% in Displays to see known values from the first hit.",self.db.threshold)
    end
    if caps.super then add("SuperWoW: %s.",tostring(SUPERWOW_VERSION or SUPERWOW_STRING))
    else add("SuperWoW not detected; available client functions are checked separately.") end
    add("ClassicAPI and SuperWoW are optional. Missing extensions are not addon errors.")
    if caps.classic then add("ClassicAPI detected: %s.",tostring(caps.classicVersion)) end
    if caps.tooltipGUID then add("Direct tooltip identity is available; EasyThreat uses it when resolvable.") end
    local inventory,known=self:AddonInventory()
    local api=inventory.superapi
    if api and not caps.super then
        add("SuperAPI is installed, but SuperWoW is not detected. SuperAPI alone cannot enable it.",nil,nil,"warning")
    elseif api and not api.loaded then
        add("Addon %s is not loaded (%s). Check the character's AddOns list.",api.name,self:AddonLoadReason(api),"warning")
    elseif api and not SuperAPI then
        add("SuperAPI did not initialize. Check its SuperWoW version requirement and login errors.",nil,nil,"warning")
    elseif api then add("SuperAPI is active.")
    elseif caps.super and known then
        add("SuperWoW is active; optional SuperAPI is missing. Use a version matching your client.")
    end
    add("ShaguTweaks is optional. EasyThreat does not require it.")
    if not EasyThreatRecorder or not EasyThreatRecorder.db then
        add("Recording could not initialize. Reinstall EasyThreat and check login errors.",nil,nil,"error")
    end
    if inventory.easythreat_recorder or (self.recorder and self.recorder.standaloneFound) then
        add("Recording is built in. Remove the separate EasyThreat_Recorder folder and restart the game.",nil,nil,"warning")
    end
end

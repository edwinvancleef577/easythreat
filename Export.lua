local E=EasyThreat
local limit=524288
-- Serialize data only. No executable input is loaded by the addon.
-- Keep migration markers so restoring a snapshot cannot re-scale positions.
function E:SettingsSnapshot()
    local result={}
    for key in pairs(self.defaults) do result[key]=self.db[key] end
    for _,key in ipairs({"layoutVersion","revision","tooltipLayoutVersion","tooltipWidthVersion","journalScopeVersion"}) do result[key]=self.db[key] end
    return result
end
function E:SerializeSettings(snapshot)
    local out,ancestors={},{}
    local length=0
    local function append(text)
        length=length+string.len(text)
        if length>limit then error("export-size") end
        table.insert(out,text)
    end
    local write
    write=function(value,depth)
        local kind=type(value)
        if kind=="string" then append(string.format("%q",value))
        elseif kind=="boolean" then append(value and "true" or "false")
        elseif kind=="number" then
            if value-value~=0 then error("export-number") end
            append(string.format("%.17g",value))
        elseif kind=="table" then
            if depth>12 or ancestors[value] then error("export-cycle") end
            ancestors[value]=true
            local keys={}
            for key in pairs(value) do
                if type(key)~="number" and type(key)~="string" then error("export-key") end
                table.insert(keys,key)
            end
            table.sort(keys,function(a,b)
                if type(a)~=type(b) then return type(a)<type(b) end
                return a<b
            end)
            append("{\n")
            for _,key in ipairs(keys) do
                append(string.rep("  ",depth+1).."["); write(key,depth+1); append("] = ")
                write(value[key],depth+1); append(",\n")
            end
            append(string.rep("  ",depth).."}"); ancestors[value]=nil
        else error("export-type") end
    end
    append("-- EasyThreat "..self.version.." settings\nEasyThreatDB = ")
    write(snapshot,0); append("\n")
    return table.concat(out)
end
function E:HideSettingsExport()
    local pane=self.pages and self.pages.diagnostics
    if not pane or not pane.exportPanel then return end
    pane.exportPanel.edit:ClearFocus(); pane.exportPanel:Hide(); pane.exportMode=nil
    pane.recordingChoiceBundle=nil
end
function E:ReturnFromSettingsTransfer()
    local pane=self.pages and self.pages.diagnostics
    local previous=pane and pane.recordingChoiceBundle
    self:HideSettingsExport(); self:UpdateDiagnostics()
    if previous and self.groupRecorder:Bundle()==previous and not self.groupRecorder.collecting then self:ShowRecordingChoice() end
end
function E:BuildSettingsExport(pane)
    local panel=CreateFrame("Frame",nil,pane)
    panel:SetWidth(358); panel:SetHeight(346); self:Place(pane,panel,16,87)
    local hint=self:Text(panel,10); panel.hint=hint
    hint:SetWidth(358); hint:SetHeight(34); hint:SetJustifyV("TOP"); hint:SetPoint("TOPLEFT",panel,"TOPLEFT",0,0)
    local background=self:Box(panel,358,267); self:Place(panel,background,0,40)
    local scroll=CreateFrame("ScrollFrame","EasyThreatExportScroll",background,"UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",background,"TOPLEFT",8,-8); scroll:SetWidth(318); scroll:SetHeight(251)
    local edit=CreateFrame("EditBox",nil,scroll)
    edit:SetWidth(318); edit:SetHeight(251); edit:SetMultiLine(true); edit:SetAutoFocus(false); edit:SetMaxLetters(limit)
    self:RegisterFont(edit,10,""); edit:SetTextColor(0.92,0.90,0.82)
    scroll:SetScrollChild(edit)
    edit:SetScript("OnTextChanged",function()
        -- The export is a snapshot: typing cannot change it or the live DB.
        if (pane.exportMode=="export" or pane.exportMode=="recording" or pane.exportMode=="file") and panel.value and edit:GetText()~=panel.value then edit:SetText(panel.value) end
        scroll:UpdateScrollChildRect()
    end)
    edit:SetScript("OnCursorChanged",function()
        if type(ScrollingEdit_OnCursorChanged)=="function" then ScrollingEdit_OnCursorChanged(arg1,arg2,arg3,arg4) end
    end)
    edit:SetScript("OnUpdate",function()
        if type(ScrollingEdit_OnUpdate)=="function" then ScrollingEdit_OnUpdate(scroll) end
    end)
    edit:SetScript("OnEscapePressed",function() E:ReturnFromSettingsTransfer() end)
    panel.edit=edit; panel.scroll=scroll
    panel.back=self:Place(panel,self:Button(panel,"Back",171,25,function() E:ReturnFromSettingsTransfer() end),0,321)
    panel.select=self:Place(panel,self:Button(panel,"Select all",171,25,function() edit:SetFocus(); edit:HighlightText() end),187,321)
    panel.save=self:Place(panel,self:Button(panel,"Save & reload UI",171,25,function() E:SaveRecordingFile() end),187,321)
    panel.apply=self:Place(panel,self:Button(panel,"Apply settings",171,25,function()
        local value=edit:GetText()
        local ok,problem=E:ImportSettings(value)
        if ok then
            E:OpenSettingsTransfer("applied",value)
            panel.hint:SetText(E:L("Settings applied. Undo is available until the next reload."))
            panel.hint:SetTextColor(0.62,0.92,0.67)
        else
            if pane.exportMode~="import" then E:OpenSettingsTransfer("import",value) end
            panel.hint:SetText(E:ImportMessage(problem)); panel.hint:SetTextColor(1,0.35,0.30)
        end
    end),187,321)
    panel.undo=self:Place(panel,self:Button(panel,"Undo import",171,25,function()
        local ok,problem=E:UndoSettingsImport()
        if ok then E:HideSettingsExport(); E:UpdateDiagnostics()
        else panel.hint:SetText(E:ImportMessage(problem)); panel.hint:SetTextColor(1,0.35,0.30) end
    end),187,321)
    pane.exportPanel=panel
end
function E:ShowSettingsExport()
    local pane=self.pages and self.pages.diagnostics
    if not pane then return end
    local ok,value=pcall(function() return E:SerializeSettings(E:SettingsSnapshot()) end)
    if not ok then return self:ShowSavedVariablesExport() end
    self:OpenSettingsTransfer("export",value)
end
function E:ShowSavedVariablesExport(bytes,reloaded)
    -- The client owns this file. Addons cannot create an arbitrary export file
    -- or discover the account/install directory through the standard API.
    local realm=self:Call(GetRealmName) or "<Realm>"
    local character=self:Call(UnitName,"player") or "<Character>"
    local path="WTF\\Account\\<Account>\\"..realm.."\\"..character.."\\SavedVariables\\EasyThreat.lua"
    local reason=reloaded and self:L("UI reloaded. Copy the saved file from the path below.") or bytes==-1 and self:L("Recording exceeds the copy limit. Use the saved file.") or bytes and self:L("Recording export is %d KB; too large for the copy window.",math.ceil(bytes/1024)) or
        self:L("Text export failed. Use the saved file below.")
    local text=reason.."\n\n"..self:L("Export does not create a separate file. Save & reload UI, or exit the game normally. Then open this path in the active game folder:")..
        "\n\n"..path.."\n\n"..self:L("Choose your account folder under Account. If needed, search WTF for EasyThreat.lua.")..
        "\n\n"..self:L("This is not the Interface/AddOns folder. If no file appears after saving, fully restart the game and check the active installation and folder write permissions.")..
        "\n\n"..self:L("Send this file. It includes recordings, settings and journal names. Keep the WTF folder when updating.")
    self:ShowPage("diagnostics"); self:OpenSettingsTransfer("file",text)
    self.pages.diagnostics.exportPanel.hint:SetText(self:L("Saved file export"))
    return true
end
function E:SaveRecordingFile()
    local panel=self.pages and self.pages.diagnostics and self.pages.diagnostics.exportPanel
    local problem
    if self:AnyCombat() then problem=self:L("Save outside combat; reloading interrupts the UI.")
    elseif type(ReloadUI)~="function" then problem=self:L("Reload unavailable. Exit the game normally to save.") end
    if problem then
        if panel then panel.hint:SetText(problem); panel.hint:SetTextColor(1,.65,.15) end
        return false
    end
    -- PLAYER_LOGOUT finishes the recorder's current clip. The native client
    -- writes all three SavedVariablesPerCharacter tables, without deleting any.
    local r=self.recorder and self.recorder.db
    if r then r.fileExportPending=true end
    local ok=pcall(ReloadUI)
    if not ok then
        if r then r.fileExportPending=nil end
        if panel then panel.hint:SetText(self:L("Reload unavailable. Exit the game normally to save.")); panel.hint:SetTextColor(1,.35,.3) end
    end
    return ok
end
function E:OpenSettingsTransfer(mode,value)
    local pane=self.pages.diagnostics
    if not pane.exportPanel then self:BuildSettingsExport(pane) end
    for _,line in ipairs(pane.lines) do line:Hide() end
    pane.refresh:Hide(); pane.print:Hide(); pane.export:Hide(); pane.import:Hide(); pane.undo:Hide(); pane.range:Hide()
    pane.sync:Hide(); pane.record:Hide(); pane.mark:Hide(); pane.recordExport:Hide(); pane.summary:Hide()
    pane.collect:Hide(); pane.share:Hide()
    pane.exportMode=mode
    local panel=pane.exportPanel
    panel.select:Hide(); panel.apply:Hide(); panel.undo:Hide(); panel.save:Hide()
    if mode=="file" then panel.save:Show()
    elseif mode=="export" or mode=="recording" then panel.select:Show()
    elseif mode=="applied" then panel.undo:Show()
    else panel.apply:Show() end
    panel.hint:SetText(self:L(mode=="export" and "Select all, then Ctrl+C. Paste into a text file to save." or
        "Paste with Ctrl+V. Supplied settings replace current values; other settings stay unchanged."))
    panel.hint:SetTextColor(0.90,0.88,0.79)
    panel.value=value; panel.edit:SetText(value); panel.scroll:UpdateScrollChildRect(); panel.scroll:SetVerticalScroll(0)
    panel:Show(); panel.edit:SetFocus()
    if mode=="export" or mode=="recording" then panel.edit:HighlightText() end
end

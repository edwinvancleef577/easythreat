-- Capability-based native fallback: no branded DLL global is required.
-- All code is original. No name-only association between different enemies.
local E=EasyThreat
function E:ReadMarkTexture(region)
    if not region or not region.GetTexture or not region.GetTexCoord then return end
    if not self:Call(region.IsShown,region) then return end
    local path=self:Call(region.GetTexture,region)
    if type(path)~="string" then return end
    path=string.lower(path)
    if not string.find(path,"ui%-raidtargetingicons$") then return end
    local ok,coords=pcall(function() return {region:GetTexCoord()} end)
    if not ok then return end
    local left,right,top,bottom
    if table.getn(coords)==4 then left,right,top,bottom=unpack(coords)
    elseif table.getn(coords)==8 then left,top,right,bottom=coords[1],coords[2],coords[7],coords[8] end
    if not left or not right or not top or not bottom then return end
    if math.abs(right-left-0.25)>0.01 or math.abs(bottom-top-0.25)>0.01 then return end
    local column,row=math.floor(left*4+0.5),math.floor(top*4+0.5)
    if column<0 or column>3 or row<0 or row>1 then return end
    return row*4+column+1
end
function E:DescribePlate(frame)
    if not frame or not frame.GetRegions or not self:Call(frame.IsShown,frame) then return end
    local raw=self:Call(frame.GetName,frame,1)
    local guid
    if type(raw)=="string" and self:Exists(raw) and self:GUID(raw)==raw then guid=raw end
    local ok,regions=pcall(function() return {frame:GetRegions()} end)
    if not ok then return end
    local native,name,mark=false,nil,nil
    for _, region in ipairs(regions) do
        local path=self:Call(region.GetTexture,region)
        if type(path)=="string" and string.lower(path)=="interface\\tooltips\\nameplate-border" then native=true end
        local text=self:Call(region.GetText,region)
        if type(text)=="string" and text~="" and not tonumber(text) and text~="??" then name=name or text end
        mark=mark or self:ReadMarkTexture(region)
    end
    -- pfUI/ShaguPlates keep the native frame and its original name region.
    local decorated=frame.nameplate
    if type(decorated)=="table" and type(decorated.original)=="table" and decorated.original.name then
        native=true
        name=self:Call(decorated.original.name.GetText,decorated.original.name)
        mark=mark or self:ReadMarkTexture(decorated.raidicon)
    end
    if not native and not guid then return end
    return {frame=frame,guid=guid,name=name,mark=mark,native=native,
        alpha=self:Call(frame.GetAlpha,frame) or 0}
end
function E:ScanNativePlates()
    self.nativePlates={}
    if not WorldFrame then return end
    local children={WorldFrame:GetChildren()}
    for _, frame in ipairs(children) do
        local record=self:DescribePlate(frame)
        if record then table.insert(self.nativePlates,record) end
    end
end
function E:NativePlateForUnit(unit)
    if not self:Exists(unit) then return end
    local guid,mark,name=self:GUID(unit),self:Call(GetRaidTargetIndex,unit),self:Call(UnitName,unit)
    local direct,marked,target,fullAlpha= {},{},{},0
    -- Re-read before attaching: engines recycle a frame for a different mob.
    for _, cached in ipairs(self.nativePlates or {}) do
        local record=self:DescribePlate(cached.frame)
        if record then
            if guid and record.guid==guid then table.insert(direct,record.frame) end
            if mark and record.mark==mark and (not record.guid or not guid or record.guid==guid) then
                table.insert(marked,record.frame)
            end
            if record.native and record.alpha>0.999 then
                fullAlpha=fullAlpha+1
                if record.name==name and (not record.mark or record.mark==mark) and
                    (not record.guid or record.guid==guid) then table.insert(target,record.frame) end
            end
        end
    end
    if table.getn(direct)==1 then return direct[1],"native-guid" end
    if table.getn(marked)==1 then return marked[1],"native-marker" end
    -- Stock Vanilla identifies its current target by alpha=1, other plates=.5.
    -- Restrict this fallback to one bright native plate AND the current target.
    if table.getn(target)==1 and fullAlpha==1 and self:Call(UnitIsUnit,unit,"target") then
        return target[1],"native-target"
    end
end

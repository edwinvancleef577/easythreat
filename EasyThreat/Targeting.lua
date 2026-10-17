local E=EasyThreat
E.targetMessages={
    preview="Preview enemies cannot be targeted. Turn Preview off.",
    unavailable="Enemy no longer reachable. Hover or target it in the world to update the list.",
    identity="Safe targeting needs GUID access. Check the launcher's client extensions.",
    blocked="Client did not allow target selection. Reload the UI and check client extensions.",
}
function E:TargetEnemy(enemy)
    local function fail(reason)
        E.targetIssue=reason; E:Print(E:L(E.targetMessages[reason])); return false
    end
    if self.demo or self.layoutPreview then return fail("preview") end
    if not enemy then return fail("unavailable") end
    if not enemy.guid then return fail("identity") end
    -- Resolve the recorded GUID again immediately inside the mouse event.
    -- A target/nameplate/marker token may now represent a different mob.
    -- Never use TargetByName: identical mob names are common in a pull.
    local handles={enemy.guid}
    if enemy.unit then table.insert(handles,1,enemy.unit) end
    if enemy.mark then table.insert(handles,"mark"..enemy.mark) end
    for _,unit in ipairs(handles) do
        if self:Exists(unit) and self:GUID(unit)==enemy.guid and
            self:Call(UnitCanAttack,"player",unit) and not self:Call(UnitIsDeadOrGhost,unit) then
            if type(TargetUnit)~="function" then return fail("blocked") end
            local ok=pcall(TargetUnit,unit)
            if ok and self:GUID("target")==enemy.guid then
                self.targetIssue=nil
                self:RefreshUI()
                return true
            end
            return fail("blocked")
        end
    end
    return fail("unavailable")
end

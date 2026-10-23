#!/usr/bin/env python3
"""Death icons survive log/timeline reuse and missing historical actor data."""
from pathlib import Path
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parent.parent
lua = LuaRuntime()
lua.execute((ROOT / "tests/wow_mock.lua").read_text())
for entry in (ROOT / "EasyThreat.toc").read_text().splitlines():
    if entry.endswith(".lua"):
        lua.execute((ROOT / entry).read_text(), name="@EasyThreat/" + entry)
lua.execute(r'''
local E,J=EasyThreat,EasyThreat.journal
Mock.units.player={name="Healer",guid="0xDA01",class="PRIEST",player=true}
Mock.Event("ADDON_LOADED","EasyThreat")
E.db.journalLogIcons=true; E.db.journalLogNames=false; E.db.journalEvents=true; E.db.journalOwn=false
local death={kind="death",actor="healer",t=1,name="Healer"}
local spell={kind="cooldown",actor="healer",t=2,icon="Interface\\Icons\\Spell_Holy_FlashHeal"}
J.viewFight={actors={healer={name="Healer",class="PRIEST"},
    pet={pet=true,class="HUNTER",icon="Interface\\Icons\\Ability_Hunter_Pet_Wolf"}},events={death},enemies={}}
J.window={log={child=CreateFrame("Frame",nil,UIParent),rows={}}}
J.logEvents={death}; J:FillLog(0)
local icon=J.window.log.rows[1].icon
local atlas="Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
assert(icon.texture==atlas and icon.texCoords[1]==.5 and icon.texCoords[3]==.25,"log displays deceased priest")
J.logEvents={spell}; J:FillLog(0)
assert(icon.texture==spell.icon and icon.texCoords[1]==0 and icon.texCoords[2]==1,"recycled spell row restores full texture")
J.logEvents={death}; E.db.journalLogIcons=false; J:FillLog(0)
assert(not icon:IsShown(),"log icon setting remains respected")
J.start=0; J.finish=5
local row={lane={},canvas=CreateFrame("Frame",nil,UIParent),events={}}
J:PlotEvents(row)
assert(row.events[1].icon.texture==atlas,"timeline displays deceased player's class")
-- The actual screenshot uses ENEMY lanes. Player deaths have no enemy target.
row.lane.enemy={id="enemy",start=0,last=5,series={}}
J:PlotEvents(row)
assert(row.events[1]:IsShown() and row.events[1].icon.texture==atlas,"death is visible on an active enemy lane even without threat samples")
row.lane.enemy.last=.5; J:PlotEvents(row)
assert(row.events[1]:IsShown(),"last observation is not an enemy death; a final player death remains visible")
row.lane.enemy.dead=.5; J:PlotEvents(row)
assert(not row.events[1]:IsShown(),"death after this enemy died is not attached to its lane")
row.lane.enemy.dead=nil; row.lane.enemy.start=2; J:PlotEvents(row)
assert(not row.events[1]:IsShown(),"death before this enemy appeared is not attached to its lane")
row.lane.enemy.start=0; E.db.journalOwn=true; J:PlotEvents(row)
assert(not row.events[1]:IsShown(),"own-only filter still applies")
E.db.journalOwn=false; row.lane.enemy=nil
J.viewFight.events={spell}; J:PlotEvents(row)
assert(row.events[1].icon.texture==spell.icon and row.events[1].icon.texCoords[2]==1,"timeline reuse restores full texture")
J:SetEventIcon(icon,{kind="death",actor="pet"})
assert(icon.texture==J.viewFight.actors.pet.icon and icon.texCoords[2]==1,"pet uses its own icon, not owner's class")
for _,id in ipairs({"missing","healer"}) do
    J.viewFight.actors.healer.class=nil
    J:SetEventIcon(icon,{kind="death",actor=id})
    assert(icon.texture=="Interface\\Icons\\Spell_Shadow_DeathCoil" and icon.texCoords[2]==1,"old or unknown actor has a full fallback icon")
end
-- A death must be recorded even when resource APIs return nil or zero max.
E.db.journalEnabled=true; J:Begin(0)
local member={key="Healer",guid="0xDA01",name="Healer",class="PRIEST",unit="player",connected=true,alive=false}
E.roster={member}; J:Actor(member,0)
UnitMana=function() return nil end; UnitManaMax=function() return 0 end
local before=table.getn(J.fight.events)
J:SampleResources(2,true); J:SampleResources(3,true)
assert(table.getn(J.fight.events)==before+1 and J.fight.events[before+1].kind=="death","resource-less death recorded once")
member.alive=true; J:SampleResources(4,true); member.alive=false; J:SampleResources(5,true)
assert(table.getn(J.fight.events)==before+2,"resurrection permits the next death")
member.alive=true; J:SampleResources(6,true); member.connected=false; member.alive=false; J:SampleResources(7,true)
assert(table.getn(J.fight.events)==before+2,"offline entry is not a death")
print("PASS: death icons in log and timeline, pooled texture reuse, pet and unknown-class fallbacks, visibility setting")
''')

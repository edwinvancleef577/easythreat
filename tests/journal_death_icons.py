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
J.viewFight.events={spell}; J:PlotEvents(row)
assert(row.events[1].icon.texture==spell.icon and row.events[1].icon.texCoords[2]==1,"timeline reuse restores full texture")
J:SetEventIcon(icon,{kind="death",actor="pet"})
assert(icon.texture==J.viewFight.actors.pet.icon and icon.texCoords[2]==1,"pet uses its own icon, not owner's class")
for _,id in ipairs({"missing","healer"}) do
    J.viewFight.actors.healer.class=nil
    J:SetEventIcon(icon,{kind="death",actor=id})
    assert(icon.texture=="Interface\\Icons\\Spell_Shadow_DeathCoil" and icon.texCoords[2]==1,"old or unknown actor has a full fallback icon")
end
print("PASS: death icons in log and timeline, pooled texture reuse, pet and unknown-class fallbacks, visibility setting")
''')

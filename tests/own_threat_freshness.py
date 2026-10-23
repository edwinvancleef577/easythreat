"""Own accumulated threat and a current relative aggro percentage are distinct."""
from pathlib import Path
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parent.parent
lua = LuaRuntime()
lua.execute((ROOT / "tests/wow_mock.lua").read_text())
for name in (ROOT / "EasyThreat.toc").read_text().splitlines():
    if name.endswith(".lua"):
        lua.execute((ROOT / name).read_text(), name="@EasyThreat/" + name)
lua.execute(r'''
local E=EasyThreat
Mock.units={player={name="Caster",guid="0xEA01",class="MAGE",player=true,combat=true},
    party1={name="Guardian",guid="0xEA02",class="WARRIOR",player=true,combat=true}}
Mock.Event("ADDON_LOADED","EasyThreat")
E.db.language="enUS"; E.db.localThreat=true; E.db.groupSync=false
local own,tank=E:Member("Caster"),E:Member("Guardian")
local enemy={key="0xEB01",guid="0xEB01",combat=true,owner=tank,samples={}}
E.ledger={}
E.ledger[enemy.guid]={values={[own.guid]=40,[tank.guid]=100},uncertain={},startKnown=true}
local first=E:TargetCombatModels(enemy)
assert(first.amount==40 and not first.held and not first.unknown)
-- No new action for 30 seconds: an accumulated ledger amount doesn't expire.
Mock.clock=Mock.clock+30
local unchanged=E:TargetCombatModels(enemy)
assert(unchanged.amount==40 and not unchanged.held)
-- Own amount remains current, but the other actor's comparison is unavailable.
E.ledger[enemy.guid].uncertain[tank.guid]=true
E.ledger[enemy.guid].values[own.guid]=50
local held=E:TargetCombatModels(enemy)
assert(held.amount==50 and held.held and held.fillPct==first.fillPct)
assert(held.text==E:L("Last value"),"label describes held percentage, not lost own amount")
E.ledger[enemy.guid].uncertain[tank.guid]=nil
local fresh=E:TargetCombatModels(enemy)
assert(not fresh.held and fresh.fillPct>first.fillPct)
print("PASS: own ledger survives idle time; missing comparison holds percentage; fresh comparison restores it")
''')

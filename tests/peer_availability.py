#!/usr/bin/env python3
"""Two online players, an offline roster slot and a pet; unequal pull visibility."""
from pathlib import Path
from lupa.lua51 import LuaRuntime

TESTS = Path(__file__).resolve().parent
ROOT = TESTS.parent
if (ROOT / "EasyThreat/EasyThreat.toc").is_file():
    ROOT = ROOT / "EasyThreat"
nodes, pending, history = [], [], []
checks = 0


def check(value, message):
    global checks
    checks += 1
    assert value, message


for index in range(2):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute((TESTS / "wow_mock.lua").read_text())
    lua.globals().nodeIndex = index
    lua.globals().transmit = lambda prefix, body, channel, sender=index: pending.append((sender, prefix, body, channel))
    lua.execute(r'''
        Mock.clock=80000
        local tank={name="Guardian",guid="0xAA01",class="PALADIN",level=11,player=true}
        local caster={name="Caster",guid="0xAA02",class="WARLOCK",level=11,player=true}
        local pet={name="Imp",guid="0xAA03",level=11}
        local offline={name="Away",guid="0xAA04",class="HUNTER",level=0,player=true,offline=true}
        Mock.units={player=nodeIndex==0 and tank or caster,party1=nodeIndex==0 and caster or tank,party2=offline}
        Mock.units[nodeIndex==0 and "partypet1" or "pet"]=pet
        Mock.units.target={name="Boar",guid="0xBB01",hostile=true,classification="normal",level=10,
            combat=false,target=nodeIndex==0 and "player" or "party1"}
        function GetNumPartyMembers() return 2 end
        function GetNumRaidMembers() return 0 end
        function UnitLevel(id) local u=Mock.Resolve(id); return u and u.level end
        function UnitClassification(id) local u=Mock.Resolve(id); return u and u.classification end
        function UnitBuff() return nil end
        function GetNumTalentTabs() return 0 end
        function SendAddonMessage(prefix,body,channel) transmit(prefix,body,channel) end
        UnitDetailedThreatSituation=nil; UnitThreatSituation=nil
    ''')
    for line in (ROOT / "EasyThreat.toc").read_text().splitlines():
        if line.endswith(".lua"):
            lua.execute((ROOT / line).read_text(), name="@" + line)
    lua.execute('''
        Mock.Event("ADDON_LOADED","EasyThreat")
        EasyThreat.db.groupSync=true; EasyThreat.db.threshold=0; EasyThreat.db.otherBars=4
        EasyThreat.db.language="enUS"; EasyThreat:ResetPeers(); EasyThreat.localBackend="nampower"
        EasyThreat.profile.roles.Guardian="tank"; EasyThreat.profile.roles.Caster="damage"
    ''')
    nodes.append(lua)

clock = 80000


def advance(ticks):
    global clock
    for _ in range(ticks):
        clock += .21
        for node in nodes:
            node.globals().Mock.clock = clock
            E = node.globals().EasyThreat
            E.PeerTick(E)
        packets, pending[:] = pending[:], []
        for sender, prefix, body, channel in packets:
            history.append((sender, prefix, body, channel))
            other = nodes[1 - sender].globals().EasyThreat
            other.ReceivePeer(other, prefix, body, channel, ("Guardian", "Caster")[sender])


advance(20)
nodes[0].execute('EasyThreat:ReadEnemy("target","0xBB01","0xBB01")')
for node in nodes:
    node.execute('''
        Mock.units.target.combat=true
        for _,m in ipairs(EasyThreat.roster) do if m.connected then Mock.Resolve(m.guid).combat=true end end
        EasyThreat:RecordThreatEvent("damage","0xAA01","0xBB01",80,nil,"physical")
        EasyThreat:RecordThreatEvent("damage","0xAA02","0xBB01",29,695,"shadow")
        EasyThreat:RecordThreatEvent("damage","0xAA03","0xBB01",18,7799,"fire")
    ''')
check(nodes[0].eval('EasyThreat.ledger["0xBB01"].startKnown') is True, "tank observed idle enemy")
check(not nodes[1].eval('EasyThreat.ledger["0xBB01"].startKnown'), "caster first observed enemy in combat")
advance(24)
tank, caster = nodes
tank.execute('result=EasyThreat:ReadEnemy("target","0xBB01","0xBB01")')
check(tank.eval('result.samples.Caster and result.samples.Caster.amount') == 29,
      "missing peer baseline must not erase the tank's valid local caster value")
check(tank.eval('result.samples["Caster:pet"] and result.samples["Caster:pet"].amount') == 18,
      "missing peer baseline must not erase the locally observed pet")
check(tank.eval('result.samples.Caster.shared') is False, "fallback stays labelled as local estimate")
caster.execute('result=EasyThreat:ReadEnemy("target","0xBB01","0xBB01")')
check(caster.eval('result.samples.Guardian.shared') is True,
      "complete remote tank total can repair a receiver with an incomplete local start")
tank.execute('''
    main=EasyThreat:TargetCombatModels(result)
    local values=EasyThreat:ThreatQuantities(result)
    quantityCaster=values.Caster and values.Caster.amount
    quantityPet=values["Caster:pet"] and values["Caster:pet"].amount
    timing=EasyThreat:PeerTimingSnapshot("0xBB01")
''')
check(tank.eval('quantityCaster') == 29 and tank.eval('quantityPet') == 18,
      "shared source selection retains both display/journal quantities")
check(tank.eval('#main.references') == 2, "target model contains caster and pet as separate extra rows")
check(tank.eval('timing.actors[1].fallback') is True and tank.eval('timing.actors[1].reason') == "incomplete-start",
      "diagnostics explain the peer gap and local fallback")

# A real reset is different from a missing observation: no old total revival.
caster.execute('EasyThreat:InvalidateActor("0xAA02","temporary-reset","0xBB01")')
advance(16)
tank.execute('result=EasyThreat:ReadEnemy("target","0xBB01","0xBB01")')
check(tank.eval('result.samples.Caster') is None, "reported invalidation blocks an otherwise plausible local total")
check(tank.eval('result.samples["Caster:pet"].amount') == 18, "player reset does not erase independent pet value")
caster.execute('EasyThreat.db.groupSync=false')
advance(20)
tank.execute('result=EasyThreat:ReadEnemy("target","0xBB01","0xBB01")')
check(tank.eval('result.samples.Caster') is None, "connection loss after a real reset cannot revive the old local total")
caster.execute('EasyThreat.db.groupSync=true')

# GUID identity can work even when a combat API only supports native tokens.
for node in nodes:
    node.execute('''
        EasyThreat:ResetThreatSources()
        EasyThreat.enemySeenIdle["0xBB01"]=Mock.clock
        EasyThreat:RecordThreatEvent("damage","0xAA01","0xBB01",80,nil,"physical")
        EasyThreat:RecordThreatEvent("damage","0xAA02","0xBB01",29,695,"shadow")
        EasyThreat:RecordThreatEvent("damage","0xAA03","0xBB01",18,7799,"fire")
        local originalCombat=UnitAffectingCombat
        function UnitAffectingCombat(unit)
            if type(unit)=="string" and string.sub(unit,1,2)=="0x" then return nil end
            return originalCombat(unit)
        end
    ''')
advance(24)
tank.execute('result=EasyThreat:ReadEnemy("target","0xBB01","0xBB01")')
check(tank.eval('result.samples.Caster and result.samples.Caster.amount') == 29,
      "sender resolves matching target token before checking combat")
check(tank.eval('result.samples.Caster.shared') is True, "matching native token allows a real peer value")
for node in nodes:
    node.execute('EasyThreat:PruneThreatSources()')
    check(node.eval('EasyThreat.ledger["0xBB01"]~=nil'), "pruning cannot erase an active native-token enemy")
check(all(len(body.encode()) <= 220 and "|" not in body for _, prefix, body, _ in history if prefix == "EasyThreat1"),
      "extended responses remain bounded and chat-escape safe")
print(f"PASS: {checks} assertions (two-client incomplete start, offline slot, pet, reset and native combat token)")

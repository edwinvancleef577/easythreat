#!/usr/bin/env python3
"""Regression: identity fills, distinct pets, semantic borders and group defaults."""
from pathlib import Path
from lupa.lua51 import LuaRuntime

TESTS = Path(__file__).resolve().parent
ROOT = TESTS.parent
if (ROOT / "EasyThreat/EasyThreat.toc").is_file():
    ROOT = ROOT / "EasyThreat"
lua = LuaRuntime()
lua.execute((TESTS / "wow_mock.lua").read_text())
for entry in (ROOT / "EasyThreat.toc").read_text().splitlines():
    if entry.endswith(".lua"):
        lua.execute((ROOT / entry).read_text(), name="@EasyThreat/" + entry)
lua.execute(r'''
local E,J=EasyThreat,EasyThreat.journal
local checks=0
local function check(ok,why) checks=checks+1; assert(ok,why) end
local function rgb(a,b)
    return a and b and math.abs(a[1]-b[1])<.00001 and math.abs(a[2]-b[2])<.00001 and math.abs(a[3]-b[3])<.00001
end
local tank={name="Guardian",guid="0xCA01",class="WARRIOR",player=true,combat=true}
local hunter={name="Ranger",guid="0xCA02",class="HUNTER",player=true,combat=true}
local wolf={name="Wolf",guid="0xCA03",combat=true}
local caster={name="Caster",guid="0xCA04",class="WARLOCK",player=true,combat=true}
local imp={name="Imp",guid="0xCA05",combat=true}
Mock.units={player=tank,party1=hunter,partypet1=wolf,party2=caster,partypet2=imp,
    target={name="Creature",guid="0xCB01",hostile=true,combat=true}}
EasyThreatDB={journalOwn=true}
Mock.Event("ADDON_LOADED","EasyThreat")
check(E.db.journalOwn==false and E.db.journalScopeVersion==1,"upgrade starts in group view")
E.db.journalOwn=true; E:InitDB()
check(E.db.journalOwn==true,"subsequent explicit own-only choice survives reload")
check(E.defaults.journalOwn==false,"new installations default to group")
local exported=E:SettingsSnapshot()
check(exported.journalScopeVersion==1 and E:ValidateSettings(exported),"export/import preserves scope migration")
check(not E:ValidateSettings({journalOwn=true,journalScopeVersion=2}),"invalid scope version rejected")
E.db.otherBars=4; E.db.threshold=0; E.db.alwaysPlayerColors=false; E.db.journalOwn=false
E.db.colors={Guardian={.2,.4,.9},Ranger={.67,.83,.45},Caster={.58,.51,.79}}
E.profile.roles.Guardian="tank"
local guardian=E:Member("Guardian"); local ranger=E:Member("Ranger"); local pet=E:Member("Ranger:pet")
local mage=E:Member("Caster"); local demon=E:Member("Caster:pet")
local wolfColor=E:IdentityColor(pet); local impColor=E:IdentityColor(demon)
check(not rgb(wolfColor,E:IdentityColor(ranger)),"hunter pet has a distinct default color")
check(not rgb(impColor,E:IdentityColor(mage)) and not rgb(wolfColor,impColor),"two pets are distinguishable")
check(rgb(wolfColor,E:IdentityColor({key="Ranger:pet"})),"offline color-editor entry resolves the same pet color")
wolf.guid="0xCA99"; E:RefreshRoster(); pet=E:Member("Ranger:pet")
check(rgb(wolfColor,E:IdentityColor(pet)),"resummoning does not recolor the pet")
local enemy={key="0xCB01",guid="0xCB01",combat=true,owner=guardian,ownerQuality="api",samples={}}
enemy.samples.Guardian={pct=100,amount=100,quality="api"}
enemy.samples.Ranger={pct=60,amount=66,quality="api"}
enemy.samples[pet.key]={pct=50,amount=55,quality="api"}
enemy.samples.Caster={pct=40,amount=44,quality="api"}
enemy.samples[demon.key]={pct=30,amount=33,quality="api"}
local function reference(main,key)
    for _,a in ipairs(main.references) do if a.actor.key==key then return a end end
end
local main=E:TargetCombatModels(enemy)
check(rgb(main.color,E.colors.green),"own tank holding aggro keeps the green state fill")
check(rgb(reference(main,ranger.key).color,E.db.colors.Ranger),"other player keeps configured color")
check(rgb(reference(main,pet.key).color,wolfColor),"other pet uses its own color")
enemy.owner=pet; main=E:TargetCombatModels(enemy)
check(rgb(main.color,E.colors.red),"own tank losing aggro changes to red")
check(rgb(reference(main,pet.key).color,wolfColor) and reference(main,pet.key).borderColor==E.colors.red,
    "pet taking unwanted aggro changes its frame, never its fill")
enemy.fleeing=true; main=E:TargetCombatModels(enemy)
check(rgb(main.color,E.colors.neutral) and rgb(reference(main,pet.key).color,wolfColor),"only own fleeing fill becomes gray")
enemy.fleeing=nil
local tooltip=E:TooltipCombatModels(enemy,0,"tooltip:test")
local overhead=E:ComparisonModels(enemy,false,"overhead")
check(rgb(reference(tooltip,pet.key).color,wolfColor) and rgb(reference(overhead,pet.key).color,wolfColor),
    "tooltip and nameplate models use the same pet color")
local cell=E:PlayerBox(UIParent)
for _,bars in ipairs({true,false}) do
    E.db.listBars=bars; E:PaintPlayer(cell,pet,100,"api",E.colors.red,true)
    local c=bars and cell.bar.barColor or cell.roleFace.vertexColor
    if not bars then c={c[1]/.70,c[2]/.70,c[3]/.70} end
    check(rgb(c,wolfColor),"enemy list pet color is fixed with or without a bar")
end
E.db.listBars=true
E:PaintPlayer(cell,guardian,80,"api",E.colors.red,false)
check(rgb(cell.bar.barColor,E.colors.red),"own list bar follows supplied warning color even without aggro")

-- Own pets also keep their identity; only the local character uses warn colors.
E.playerKey="Ranger"; E.profile.roles[pet.key]="tank"
local mine,mypet=E:TargetCombatModels(enemy)
check(rgb(mypet.color,wolfColor) and mypet.borderColor==E.colors.green,"own tank pet has fixed fill and green holder frame")
E.profile.roles[pet.key]="damage"; mine,mypet=E:TargetCombatModels(enemy)
check(rgb(mypet.color,wolfColor) and mypet.borderColor==E.colors.red,"own damage pet has fixed fill and red holder frame")
E.db.colors[pet.key]={.91,.52,.19}
mine,mypet=E:TargetCombatModels(enemy)
check(rgb(mypet.color,E.db.colors[pet.key]),"explicit pet color overrides automatic hue")
E.db.alwaysPlayerColors=true; enemy.owner=ranger; mine=E:TargetCombatModels(enemy)
check(rgb(mine.color,E.db.colors.Ranger) and mine.borderColor==E.colors.red,"optional fixed own color keeps aggro warning frame")
E.db.alwaysPlayerColors=false; E.db.colors[pet.key]=nil
E:ResetThreatSources(); E.enemySeenIdle[enemy.guid]=GetTime()
E:RecordThreatEvent("damage",tank.guid,enemy.guid,30,nil,"physical")
enemy.owner=guardian; enemy.samples={Guardian={pct=100,amount=30,quality="calculated"}}
mine=E:TargetCombatModels(enemy)
check(mine.reference.building and rgb(mine.reference.color,E.db.colors.Guardian),"foreign tank stays in player color during build-up")
E.playerKey="Guardian"; main=E:TargetCombatModels(enemy)
check(main.building and rgb(main.color,E.colors.build),"own initial build-up remains blue")

-- A saved pre-fix journal stored identical owner/pet RGBs. Repaint both the
-- graph and log with the live identity resolver, without altering recordings.
local a={id=pet.guid,key=pet.key,name=pet.name,owner=pet.owner,pet=true,class="HUNTER",own=false,
    color=E.db.colors.Ranger,spend={{t=0,v=1},{t=1,v=2}}}
J.viewFight={duration=1,actors={[pet.guid]=a},order={pet.guid},events={{kind="damage",actor=pet.guid,t=.5,name="Bite",amount=2}},enemies={}}
J.start=0; J.finish=1; J.compare=false; E.db.journalOwn=false
J:MakeWindow()
local plotColor; J.Line=function(self,row,x1,y1,x2,y2,color,alpha) plotColor=color end
local lane=J:MakeLane(1); J:Plot(lane,{kind="spend"})
check(rgb(plotColor,wolfColor),"older journal curves no longer inherit owner color")
J.moment=.5; J:RenderLog(true)
local hex=string.format("|cff%02x%02x%02x",wolfColor[1]*255,wolfColor[2]*255,wolfColor[3]*255)
check(string.find(J.window.log.rows[1].label:GetText(),hex,1,true),"journal log uses the same pet color")
check(rgb(a.color,E.db.colors.Ranger),"rendering does not rewrite recorded evidence")
print("PASS: "..checks.." player/pet color and group-default assertions")
''')

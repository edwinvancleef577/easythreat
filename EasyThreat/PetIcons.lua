-- Built-in Vanilla summon icons, keyed by creature family (never the pet name).
-- Unknown/custom demons use SetPortraitTexture in UI.lua.
local families={
    {"Spell_Shadow_SummonImp","Imp","Wichtel","Diablotin","Diablillo","Diabrete","Бес","임프","小鬼"},
    {"Spell_Shadow_SummonVoidWalker","Voidwalker","Leerwandler","Marcheur du Vide","Abisario","Emissário do Caos","Демон Бездны","공허방랑자","虚空行者"},
    {"Spell_Shadow_SummonSuccubus","Succubus","Sukkubus","Succube","Súcubo","Суккуб","서큐버스","魅魔"},
    {"Spell_Shadow_SummonFelHunter","Felhunter","Teufelsjäger","Chasseur corrompu","Manáfago","Caçador Vil","Охотник Скверны","지옥사냥개","地狱猎犬"}
}
EasyThreat.demonIcons={}
for _,family in ipairs(families) do
    for i=2,table.getn(family) do EasyThreat.demonIcons[family[i]]=family[1] end
end

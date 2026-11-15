-- lua5.4 tests/test_switches.lua
local S = dofile("Scripts/switches.lua")
local fails = 0
local function check(ok, msg)
    print((ok and "ok   " or "FAIL ") .. msg)
    if not ok then fails = fails + 1 end
end

local FRIEND, ENEMY = 1, 2
local FIGHT, ABILITY, MAGIC, LB, ITEM, SUMMON, FINISH, THROW, ESCAPE = 1, 3, 4, 5, 6, 7, 9, 11, 16
local function row(t) t.effects = t.effects or {} return t end
local function eff(...)
    local out = {}
    for i, v in ipairs({ ... }) do out[i] = { type = v } end
    return out
end

-- parse
check(S.parse("Heals", nil) == "auto", "a missing line is auto")
check(S.parse("Heals", "") == "auto", "an empty value is auto")
check(S.parse("Heals", "OFF") == "off", "case does not matter")
check(S.parse("Heals", " hand ") == "hand", "spaces around the value are dropped")
local v, ok = S.parse("Heals", "maybe")
check(v == "auto" and ok == false, "an unknown value is auto, and flagged")
v, ok = S.parse("Escape", "hand")
check(v == "auto" and ok == false, "Escape takes no hand")
v, ok = S.parse("Spellblades", "hand")
check(v == "hand" and ok == true, "Spellblades takes hand")
v, ok = S.parse("Escape", "off")
check(v == "off" and ok == true, "Escape takes off")

-- categoryOf
check(S.categoryOf(row({ attr = FIGHT, rel = ENEMY, power = 100, kind = "damage" })) == nil, "Attack has no category")
check(S.categoryOf(row({ attr = MAGIC, rel = ENEMY, power = 150, kind = "damage" })) == nil, "a damage spell has no category")
check(S.categoryOf(row({ attr = ABILITY, rel = ENEMY, power = 0, breakPower = 40, kind = "damage" })) == nil,
    "a stagger-only hit has no category")
check(S.categoryOf(row({ attr = LB, rel = ENEMY, power = 500, kind = "damage" })) == "Limits", "a damage Limit is a Limit")
check(S.categoryOf(row({ attr = LB, rel = FRIEND, kind = "revive" })) == "Limits", "a raise Limit is a Limit")
check(S.categoryOf(row({ attr = 15, rel = ENEMY, power = 39, breakPower = 30, kind = "damage" })) == "Spellblades",
    "a spellblade is a Spellblade, not a plain hit")
check(S.categoryOf(row({ attr = 15, rel = ENEMY, power = 15, kind = "damage", effects = eff(42) })) == "Spellblades",
    "a spellblade with a rider is still a Spellblade")
check(S.categoryOf(row({ attr = SUMMON, rel = ENEMY, power = 300, kind = "damage" })) == nil, "an Esper is left to EsperLevelGap")
check(S.categoryOf(row({ attr = FINISH, rel = ENEMY, power = 300 })) == nil, "a Vision finish is left to ResonanceLevelGap")
check(S.categoryOf(row({ attr = ESCAPE })) == "Escape", "Escape is Escape")
check(S.categoryOf(row({ attr = ITEM })) == "Items", "an item row is an Item")
check(S.categoryOf(row({ attr = THROW })) == "Items", "Throw is an Item")
check(S.categoryOf(row({ attr = MAGIC, rel = FRIEND, kind = "heal" })) == "Heals", "Cure is a Heal")
check(S.categoryOf(row({ attr = MAGIC, rel = FRIEND, kind = "cure" })) == "Heals", "a status cure is a Heal")
check(S.categoryOf(row({ attr = MAGIC, rel = FRIEND, kind = "revive" })) == "Raises", "Raise is a Raise")
check(S.categoryOf(row({ attr = ABILITY, rel = FRIEND, kind = "defend" })) == "Guards", "Defend is a Guard")
check(S.categoryOf(row({ attr = ABILITY, rel = FRIEND, kind = "buff", effects = eff(41) })) == "Guards",
    "Cover is a Guard, whatever classify called it")
check(S.categoryOf(row({ attr = ABILITY, rel = FRIEND, kind = "damage", effects = eff(41) })) == "Guards",
    "Cover classify fell through to damage on is still a Guard")
check(S.categoryOf(row({ attr = ABILITY, rel = ENEMY, power = 0, kind = "debuff", effects = eff(99) })) == "Guards",
    "Provoke is a Guard, not a Debuff")
check(S.categoryOf(row({ attr = ABILITY, rel = ENEMY, power = 120, kind = "damage", effects = eff(99) })) == nil,
    "a hit that also draws attacks is a hit")
check(S.categoryOf(row({ attr = ABILITY, rel = ENEMY, power = 0, effects = eff(29) })) == "Scan", "Scan is Scan")
check(S.categoryOf(row({ attr = ABILITY, rel = ENEMY, power = 0, effects = eff(142) })) == "Scan", "a Mog scan is Scan")
check(S.categoryOf(row({ attr = MAGIC, rel = ENEMY, power = 0, kind = "debuff" })) == "Debuffs", "Slow is a Debuff")
check(S.categoryOf(row({ attr = ABILITY, rel = ENEMY, power = 0, kind = "damage", effects = eff(27) })) == "Debuffs",
    "a break mark on a foe is a Debuff")
check(S.categoryOf(row({ attr = MAGIC, rel = FRIEND, kind = "buff" })) == "Buffs", "Haste is a Buff")
check(S.categoryOf(row({ attr = ABILITY, rel = FRIEND, kind = "damage" })) == "Buffs",
    "a party-side row with no hit is a Buff, even when classify fell through")
check(S.categoryOf(nil) == nil, "nil is no category")

-- items
local function has(list, x)
    for _, v in ipairs(list) do if v == x then return true end end
    return false
end
check(has(S.itemCategories("heal"), "Items") and has(S.itemCategories("heal"), "Heals"), "a Potion is an Item and a Heal")
check(has(S.itemCategories("hp"), "Heals"), "the chosen hp use is a Heal")
check(has(S.itemCategories("cure"), "Heals"), "an Antidote is a Heal")
check(has(S.itemCategories("revive"), "Raises"), "a Phoenix Down is a Raise")
check(#S.itemCategories("mp") == 1, "an Ether is only an Item")
check(#S.itemCategories("attack") == 1, "a thrown item is only an Item")
check(#S.itemCategories(nil) == 1, "an item with no use is only an Item")

-- verdict
local all = {}
for _, n in ipairs(S.NAMES) do all[n] = "auto" end
check(S.verdict(all, { "Heals" }) == "auto", "every switch auto lets a heal through")
check(S.verdict(all, { nil }) == "auto", "no category is auto")
check(S.verdict(nil, { "Heals" }) == "auto", "no config is auto")
local cfg = { Items = "auto", Heals = "off", Raises = "hand" }
local got, by = S.verdict(cfg, S.itemCategories("heal"))
check(got == "off" and by == "Heals", "Heals off stops a Potion even with Items auto")
got, by = S.verdict(cfg, S.itemCategories("revive"))
check(got == "hand" and by == "Raises", "Raises hand hands over a Phoenix Down")
got = S.verdict({ Items = "off", Raises = "hand" }, S.itemCategories("revive"))
check(got == "off", "off wins over hand")
check(S.off({ Items = "off" }, S.itemCategories("mp")), "Items off stops an Ether")
check(not S.off({ Heals = "off" }, S.itemCategories("mp")), "Heals off leaves an Ether")

-- summary
check(S.summary(all) == nil, "all auto has no summary")
check(S.summary({ Heals = "off", Limits = "hand" }) == "Limits hand, Heals off", "the summary lists the changed switches in order")

-- every name has a parse, and the list matches what config.ini documents
check(#S.NAMES == 10, "ten switches")

if fails > 0 then
    print(fails .. " failed")
    os.exit(1)
end
print("all passed")

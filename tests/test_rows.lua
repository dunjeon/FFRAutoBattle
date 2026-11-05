-- lua5.4 tests/test_rows.lua
local R = dofile("Scripts/rows.lua")
local fails = 0
local function check(ok, msg)
    print((ok and "ok   " or "FAIL ") .. msg)
    if not ok then fails = fails + 1 end
end
local hit = { id = 1, name = "Spark", attr = 4, effect = 1, varType = 1, dmgType = 2, target = 1, rel = 2, cost = 5, power = 20, breakPower = 17, element = "thunder", effects = {} }
local heal = { id = 2, name = "Mend", attr = 4, effect = 1, varType = 0, dmgType = 2, target = 2, rel = 1, cost = 9, power = 200, breakPower = 0, effects = {} }
local shield = { id = 3, name = "Ward", attr = 4, effect = 0, varType = 0, dmgType = 0, target = 1, rel = 1, cost = 5, power = 0, breakPower = 0, effects = { { type = 26, status = 27, params = { 2, 30 }, turns = 5 } } }
local weaken = { id = 4, name = "Soften", attr = 4, effect = 0, varType = 0, dmgType = 0, target = 1, rel = 2, cost = 5, power = 0, breakPower = 0, effects = { { type = 3, status = 16, params = {}, turns = 5 } } }
local limit = { id = 5, name = "Big One", attr = 5, effect = 1, varType = 1, dmgType = 1, target = 2, rel = 2, cost = 200, power = 33, breakPower = 35, effects = {} }
local potion = { id = 6, name = "Sip", attr = 6, effect = 1, varType = 0, paramType = 1, dmgType = 0, target = 1, rel = 1, cost = 0, power = 200, breakPower = 0, effects = {} }
local cure = { id = 7, name = "Clean", attr = 6, effect = 0, varType = 0, dmgType = 0, target = 1, rel = 1, cost = 0, power = 0, breakPower = 0, effects = { { type = 19, status = 0, params = { 0, 0, 0, 5 } } } }
local d = R.build({
    skills = { hit, heal, shield, weaken, limit, potion, cure },
    units = { [9] = { name = "Foe", maxBreak = 100, boss = true, elements = { [5] = 1, [6] = 2, [1] = 3, [2] = 4 }, status = { [3] = 100 }, traits = { "Immune to physical attacks.", "Becomes enraged if the battle drags on." }, highRisk = { 1 }, counters = {} } },
    items = { [1] = { name = "Sip", skillId = 6, price = 100, sale = true, scene = 3 }, [2] = { name = "Clean", skillId = 7, price = 100, sale = true, scene = 1 } },
})
check(d.known["spark"].use == "break" and d.known["spark"].element == "thunder" and d.known["spark"].magic, "a damage row is a hit, with its element and kind")
check(d.known["mend"].use == "heal" and d.known["mend"].party, "a recovery row is a heal, and a group row is a party heal")
check(d.known["ward"].use == "guardbuff" and d.known["ward"].guards == "magic", "a defense row is a guard of its kind")
check(d.known["soften"].use == "debuff" and d.known["soften"].effect == "defenseDown", "a debuff row is named by its status")
check(d.limits["big one"].use == "lb-cash" and d.limits["big one"].gauges == 2 and d.limits["big one"].area, "a Limit's gauges come from its cost")
check(d.items.items["sip"] == "hp" and d.items.items["clean"] == "cure" and d.items.clears["clean"][5], "items come from their skill row")
local c = d.units[9]
check(c.weak.thunder and c.half.water and c.no.fire and c.absorb.ice and c.ail.sleep, "resistances come from the enemy's row")
check(c.danger and (c.no.physical == nil), "a trait's text decides nothing")
check(c.danger[1] == "Spark" and c.hits == "magic", "dangerous moves and their kind come from the game's list")
check(c.dangerIds and #c.dangerIds == #c.danger, "the card keeps the dangerous moves' ids for the warned-hit estimate")
check(d.mobs["foe"] == c, "an enemy is also found by name")
local same1 = { id = 80, name = "Twin", attr = 4, effect = 1, varType = 1, dmgType = 2, target = 1, rel = 2, cost = 5, power = 20, breakPower = 10, element = "fire", effects = {} }
local same2 = { id = 81, name = "Twin", attr = 4, effect = 1, varType = 1, dmgType = 2, target = 1, rel = 2, cost = 5, power = 90, breakPower = 10, element = "ice", effects = {} }
local beg = { id = 82, name = "Beg", attr = 3, effect = 1, varType = 0, dmgType = 0, target = 1, rel = 1, cost = 0, power = 99999, breakPower = 0, effects = {} }
local d3 = R.build({ skills = { [80] = same1, [81] = same2, [82] = beg }, units = {
    [90] = { name = "Jar", elements = {}, status = {}, traits = {}, moves = { 82 } },
    [91] = { name = "Biter", elements = {}, status = {}, traits = {}, moves = { 82, 80 } },
    [92] = { name = "Blank", elements = {}, status = {}, traits = {}, moves = {} },
}, items = {} })
check(d3.knownById[80].fact.element == "fire" and d3.knownById[81].fact.element == "ice", "rows that share a name keep their own facts")
check(d3.knownById[80].name == "twin", "a row's fact remembers its name")
local bio = { id = 20, name = "Toxin", attr = 4, effect = 1, varType = 1, dmgType = 2, target = 1, rel = 2, cost = 10, power = 20, breakPower = 20, effects = { { type = 2, status = 1, params = {}, turns = 5 } } }
local gale = { id = 21, name = "Gale", attr = 4, effect = 1, varType = 1, dmgType = 2, target = 1, rel = 2, cost = 0, power = 20, breakPower = 0, element = "wind", effects = {} }
local esper = { id = 22, name = "Sprite", attr = 7, effect = 0, varType = 0, dmgType = 0, target = 0, rel = 1, cost = 50, power = 0, breakPower = 0, effects = { { type = 37, status = 0, params = { 2, 70 }, turns = -1 } } }
local d2 = R.build({ skills = { [20] = bio, [21] = gale, [22] = esper }, units = { [70] = { name = "Sprite Unit", elements = {}, status = {}, traits = {}, moves = { 21, 20 } } }, items = {} })
check(d2.espers["sprite"].element == "wind" and d2.espers["sprite"].role == "damage", "an Esper's element and role come from its moves")
os.exit(fails == 0 and 0 or 1)

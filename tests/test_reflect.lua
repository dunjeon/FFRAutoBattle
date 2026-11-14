-- lua5.4 tests/test_reflect.lua
local R = dofile("Scripts/reflect.lua")
local fails = 0
local function check(ok, msg)
    print((ok and "ok   " or "FAIL ") .. msg)
    if not ok then fails = fails + 1 end
end

-- Rows from the fight-43 report: Cura (attr 4), First Aid and Pray (attr 3).
local cura = { name = "Cura", attr = 4 }
local cure = { name = "Cure", attr = 4 }
local firstAid = { name = "First Aid", attr = 3 }
local pray = { name = "Pray", attr = 3 }
local fire = { name = "Fire", attr = 4, element = "fire" }
local attack = { name = "Attack", attr = 1 }
local summon = { name = "Carbuncle", attr = 7 }
local limit = { name = "Holy Ray", attr = 5 }
local potion = { name = "Potion", attr = 6, isItem = true }
local pierceFlag = { name = "Pierce", attr = 4, pierce = true }
local pierceEffect = { name = "Pierce2", attr = 4, effects = { { type = 34 }, { type = 62 } } }

local reflected = { [25] = true, [27] = true, [30] = true, [32] = true }
local clear = { [25] = true, [27] = true, [30] = true }

check(R.on(reflected) == true, "status 32 is Reflect")
check(R.on(clear) == false, "Protect, Shell and Regen are not Reflect")
check(R.on(nil) == false, "no status read is not Reflect")

check(R.bounces(cura) and R.bounces(cure) and R.bounces(fire), "white and black magic bounce")
check(not R.bounces(firstAid), "First Aid is an ability and lands (seen: 249 on Fina under Reflect)")
check(not R.bounces(pray), "Pray is an ability and lands")
check(not R.bounces(attack), "a basic attack is not magic")
check(not R.bounces(summon), "an Esper call is not magic")
check(not R.bounces(limit), "a Limit Burst is not magic")
check(not R.bounces(potion), "an item is not magic")
check(not R.bounces(pierceFlag), "isReflectPenetration passes Reflect")
check(not R.bounces(pierceEffect), "a ReflectPenetration effect passes Reflect")
check(not R.bounces(nil), "no row does not bounce")

check(R.blocked(cura, reflected) == true, "Cura at an ally under Reflect is blocked (it healed Ignis for 1296)")
check(R.blocked(cura, clear) == false, "Cura at an ally without Reflect lands (it healed Rain for 1417)")
check(R.blocked(firstAid, reflected) == false, "First Aid at an ally under Reflect is not blocked")

-- A foe with Reflect: the same rule, whatever put it there.
check(R.blocked(fire, { [32] = true }) == true, "a spell at a foe under Reflect is blocked")
check(R.blocked(attack, { [32] = true }) == false, "a physical hit at a foe under Reflect is not")

local sets = { [1] = reflected, [2] = clear, [3] = reflected }
local function statusOf(id) return sets[id] end
local off = R.bouncedOff(cura, { 1, 2, 3 }, statusOf)
check(#off == 2 and off[1] == 1 and off[2] == 3, "a party spell bounces off each target with Reflect")
check(#R.bouncedOff(firstAid, { 1, 2, 3 }, statusOf) == 0, "an ability bounces off no one")
check(#R.bouncedOff(cura, { 2 }, statusOf) == 0, "no target with Reflect, nothing bounces")
check(#R.bouncedOff(cura, { 9 }, function() error("no read") end) == 0, "a status read that fails is not Reflect")

print(fails == 0 and "all reflect tests pass" or (fails .. " reflect tests FAILED"))
os.exit(fails == 0 and 0 or 1)

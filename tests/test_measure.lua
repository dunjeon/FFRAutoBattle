-- lua5.4 tests/test_measure.lua
local M = dofile("Scripts/measure.lua")
local fails = 0
local function check(ok, msg)
    print((ok and "ok   " or "FAIL ") .. msg)
    if not ok then fails = fails + 1 end
end
local b = M.new()
check(M.expect(b, 1, 10, 9, 100) == nil, "nothing measured, nothing to expect")
M.add(b, 1, 10, 9, 1000, 100, false)
local v, sure = M.expect(b, 1, 10, 9, 100)
check(v == 1000 and sure, "a measured hit is used")
local g, gs = M.expect(b, 1, 11, 9, 50)
check(g == 500 and not gs, "an untried skill is scaled by what this caster really did")
check(M.expect(b, 2, 11, 9, 50) == nil, "another caster's numbers don't carry over")
M.add(b, 1, 10, 9, 1500, 100, true)
check(M.expect(b, 1, 10, 9, 100) == 1000, "a staggered hit is scaled back to the same terms")
M.add(b, 1, 10, 9, 500, 100, false)
check(M.expect(b, 1, 10, 9, 100) == 750, "recent hits count most, so a change in the fight shows")
M.add(b, 1, 12, 9, 0, 100, false)
check(M.expect(b, 1, 12, 9, nil) == nil, "a hit that did nothing isn't counted as a number")
check(M.fresh(b, "a") and not M.fresh(b, "a"), "the same hit isn't counted twice")
check(#M.lines(b, function() return "x" end) == 1, "the report lists what was measured")

-- Numbers from a real Expert Leviathan fight: Tsunami power 30, Killer Tsunami 99.
local rows = {
    [1] = { power = 30, dmgType = 2 }, [2] = { power = 99, dmgType = 2 },
    [3] = { power = 50, dmgType = 1 }, [4] = { power = 0, dmgType = 2 },
}
local rowOf = function(id) return rows[id] end
local seen = { [1] = { fullTo = { [7] = 540 } } }
check(M.warnedCast({}, { 1, 2 }, rowOf, 7) == nil, "nothing seen from this foe, nothing to expect")
check(M.warnedCast(seen, { 2 }, rowOf, 8) == nil, "another ally's numbers don't carry over")
check(math.abs(M.warnedCast(seen, { 2 }, rowOf, 7) - 1782) < 0.01, "an unseen warned move is scaled by its power")
check(M.warnedCast(seen, { 3 }, rowOf, 7) == nil, "a move of another damage type isn't a guide")
check(M.warnedCast(seen, { 4 }, rowOf, 7) == nil, "a move with no power gives no number")
check(math.abs(M.warnedCast(seen, { 1, 2 }, rowOf, 7) - 1782) < 0.01, "the worst warned move counts")
local both = { [1] = { fullTo = { [7] = 540 } }, [2] = { fullTo = { [7] = 1500 } } }
check(M.warnedCast(both, { 2 }, rowOf, 7) == 1500, "what the move really did beats the estimate")
check(M.pickKill({ { real = 100, cost = 0 } }, 500) == nil, "a hit that won't kill isn't a kill")
check(M.pickKill({}, 500) == nil, "nothing to hit with")
local cheap, dear = { real = 700, cost = 0 }, { real = 2000, cost = 15 }
check(M.pickKill({ dear, cheap }, 500) == cheap, "the cheapest hit with room to spare")
local thin, wide = { real = 460, cost = 0 }, { real = 600, cost = 15 }
check(M.pickKill({ thin, wide }, 432) == thin, "the cheapest hit that meets the remaining HP")
check(M.pickKill({ thin }, 432) == thin, "a hit that meets the remaining HP is taken")
local crit = { [1] = { fullTo = { [7] = 540 } }, [3] = { fullTo = { [7] = 2000 } }, [5] = { fullTo = { [7] = 600 } } }
rows[3].dmgType, rows[5] = 2, { power = 30, dmgType = 2 }
check(math.abs(M.warnedCast(crit, { 2 }, rowOf, 7) - (20 * 99)) < 0.01, "one outsized hit doesn't set the estimate")
check(M.damageFit(3) == 1.5 and M.damageFit(1) == 1 and M.damageFit(0.5) == 0.5, "weakness is smaller on damage than on stagger")
check(M.hitFactor(1, nil, false) == 1.5 and M.hitFactor(2, nil, false) == 0.5 and M.hitFactor(3, nil, false) == 0, "with no multiplier, resistance is the factor")
check(M.hitFactor(1, 2.25, true) == 1.5, "a hit's own multiplier gives the break factor back")

-- Misses, in numbers from a real fight: lands for 544, 50% accuracy, 6 of 15 missed.
local m = M.new()
check(M.landRate(m, 1, 5, 50) == 0.5, "before the first cast, the row's accuracy is the guess")
local onlyMiss = M.new()
M.noteCast(onlyMiss, 1, 5, false)
check(M.landRate(onlyMiss, 1, 5, 50) == 0.5, "a miss with no land still uses the row")
check(M.landRate(m, 1, 5, 100) == 1 and M.landRate(m, 1, 5, 500) == 1 and M.landRate(m, 1, 5, 0) == 1 and M.landRate(m, 1, 5, nil) == 1, "100, over 100, 0 and missing all mean it doesn't miss")
M.add(m, 1, 5, 9, 544, nil, false)
for i = 1, 15 do M.noteCast(m, 1, 5, i > 6) end
local rate = M.landRate(m, 1, 5, 50)
check(math.abs(rate - (9 / 15)) < 0.001, "after a cast, this fight's lands are the rate")
check(math.abs(M.expect(m, 1, 5, 9, nil, 50) - (544 * 9 / 15)) < 0.01, "expected damage counts the misses")
M.add(m, 1, 6, 9, 460, nil, false)
M.noteCast(m, 1, 6, true)
check(M.expect(m, 1, 6, 9, nil, 100) > M.expect(m, 1, 5, 9, nil, 50), "a sure 460 beats a coin-flip 544")
check(M.lesson(1, false, 400) == "weak", "resistance 1 is a weakness")
check(M.lesson(2, false, 50) == "half", "resistance 2 is a half")
check(M.lesson(3, false, 0) == "no", "resistance 3 is a null")
check(M.lesson(4, false, 0) == "absorb", "resistance 4 is an absorb")
check(M.lesson(5, false, 0) == "reflect", "resistance 5 is a reflect")
check(M.lesson(nil, true, 0) == nil, "a miss teaches nothing")
check(M.lesson(1, true, 400) == nil, "a miss is not a weakness")
check(M.lesson(nil, false, 0) == "no", "a hit that took no HP is a null")
check(M.lesson(nil, false, 200) == nil, "a plain hit with no resistance field teaches nothing")
check(M.lesson(nil, false, nil) == nil, "a guarded hit with no resistance teaches nothing")
local foes = {}
check(M.noteFoe(foes, 9, "thunder", "weak"), "the first weakness is new")
check(not M.noteFoe(foes, 9, "thunder", "weak"), "the same weakness is not new again")
check(M.foeFactor(foes, 9, "thunder", "magic") == 3, "a learned weakness is the card's factor, for any caster")
check(M.foeFactor(foes, 9, "fire", "magic") == nil, "another element is untouched")
check(M.foeFactor(foes, 8, "thunder", "magic") == nil, "another foe is untouched")
M.noteFoe(foes, 9, "fire", "no")
check(M.foeFactor(foes, 9, "fire", "magic") == 0, "a learned null is no damage")
check(M.foeFactor(foes, 9, "thunder", "magic") == 3, "a null on one element leaves the weakness")
M.noteFoe(foes, 9, "physical", "no")
check(M.foeFactor(foes, 9, nil, "physical") == 0, "a hit with no element files the kind")
check(M.foeFactor(foes, 9, "thunder", "magic") == 3, "a magic weakness stays when physical is the null")
M.noteFoe(foes, 4, "ice", "absorb")
check(M.foeFactor(foes, 4, "ice", nil) == 0, "a learned absorb is no damage")
M.noteFoe(foes, 4, "water", "half")
check(M.foeFactor(foes, 4, "water", nil) == 0.5, "a learned half is the card's half")
M.noteFoe(foes, 2, "fire", "no", "8,40")
check(M.foeFactor(foes, 2, "fire", nil, "8,40") == 0, "a resist holds while the same statuses are up")
check(M.foeFactor(foes, 2, "fire", nil, "8") == nil, "a changed status list lifts the resist")
check(M.noteFoe(foes, 2, "fire", "weak", "8"), "a later hit replaces the resist")
check(M.foeFactor(foes, 2, "fire", nil, "8") == 3, "the new result is the one that counts")
M.noteFoe(foes, 3, "thunder", "reflect", "12")
check(M.foeFactor(foes, 3, "thunder", nil, "12") == 0, "a reflect is no damage while that status list holds")
check(M.foeFactor(foes, 3, "thunder", nil, "") == nil, "a reflect lifts when the status list changes")
check(M.landRate(m, 2, 5, 50) == 0.5, "another caster's misses don't carry over")
check(M.landRate(nil, 1, 5, 50) == 0.5, "before any hit lands in the fight, the row's number still answers")
os.exit(fails == 0 and 0 or 1)

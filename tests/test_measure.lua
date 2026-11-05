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
os.exit(fails == 0 and 0 or 1)

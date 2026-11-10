-- lua5.4 tests/test_pace.lua
local P = dofile("Scripts/pace.lua")
local fails = 0
local function check(ok, msg)
    print((ok and "ok   " or "FAIL ") .. msg)
    if not ok then fails = fails + 1 end
end

local marks = { 1, 1.5, 2 }

check(P.fastest(marks) == 2, "the last mark is the fastest")
check(P.fastest({ 2, 1 }) == 2, "order does not matter")
check(P.fastest({}) == nil, "an empty list has no mark")
check(P.fastest(nil) == nil, "a missing list has no mark")
check(P.fastest({ 0, -1 }) == nil, "a non-positive mark is not a speed")

check(P.rate(marks, 0.2, false, false) == 6, "actions run at three times the fastest mark")
check(P.rate(marks, 0.2, true, false) == 0.2, "the menu stays at the command-select speed")
check(P.rate(marks, nil, true, false) == 1, "a missing command speed does not crawl the menu")
check(P.rate(marks, 0.2, true, true) == 1, "a watched scene stays unsped even while a menu is open")
check(P.rate(marks, 0.2, false, true) == 1, "a watched scene stays unsped during an action")
check(P.rate(nil, 0.2, false, false) == nil, "no marks means leave the battle alone")
check(P.rate({}, 0.2, false, false) == nil, "an empty mark list means leave the battle alone")

os.exit(fails == 0 and 0 or 1)

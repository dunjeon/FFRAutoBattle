-- lua5.4 tests/test_growth.lua
local G = dofile("Scripts/growth.lua")
local fails = 0
local function check(ok, msg)
    print((ok and "ok   " or "FAIL ") .. msg)
    if not ok then fails = fails + 1 end
end

local under = { { level = 8 }, { level = 9 } }
local mixed = { { level = 8 }, { level = 12 } }
local same = { { level = 10 } }

check(G.keeps(10, mixed) == true, "one mob at or above keeps the payout")
check(G.keeps(10, same) == true, "a mob at this level keeps the payout")
check(G.keeps(10, under) == false, "every mob under this level zeroes the gain")
check(G.keeps(10, {}) == nil, "no mobs leaves the payout alone")
check(G.keeps(nil, same) == nil, "no level leaves the payout alone")
check(G.keeps(10, { { level = 4 }, { exp = 10 } }) == nil, "a mob with no level leaves the payout alone")

check(G.apply(1000, 1800, true) == 1800, "a kept payout is the game's number")
check(G.apply(1000, 1800, nil) == 1800, "an unread fight is the game's number")
check(G.apply(1000, 1800, false) == 1000, "a fight under this level adds nothing")
check(G.apply(1000, 1000, false) == 1000, "no gain stays put")
check(G.apply(1000, 900, false) == 900, "a drop is not turned into a gain")

local kept = G.row(10, 1000, 12, 1800, true)
check(kept.afterExp == 1800 and kept.afterLevel == 12 and not kept.clear, "a kept row stays")
local cut = G.row(40, 5000, 43, 9000, false)
check(cut.afterExp == 5000 and cut.afterLevel == 40 and cut.clear, "a cut row stays at the old level")

os.exit(fails == 0 and 0 or 1)

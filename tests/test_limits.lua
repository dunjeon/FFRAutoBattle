-- lua5.4 tests/test_limits.lua
local L = dofile("Scripts/limits.lua")
local fails = 0
local function check(ok, msg)
    print((ok and "ok   " or "FAIL ") .. msg)
    if not ok then fails = fails + 1 end
end

check(L.filled(0, 100, 200, 0, nil) == 0, "an empty bar stays empty when the gauge count is 0")
check(L.filled(97, 100, 200, 0, nil) == 0, "points under one gauge are not a gauge")
check(L.filled(100, 100, 200, 0, nil) == 1, "100 points is one gauge even if the count stays 0")
check(L.filled(199, 100, 200, 0, nil) == 1, "one short of the second gauge is still one")
check(L.filled(200, 100, 200, 0, nil) == 2, "200 points is two gauges even if the count stays 0")
check(L.filled(100, 100, 100, 0, nil) == 1, "a 100-point bar holds one gauge")
check(L.filled(200, nil, 200, 0, nil) == 2, "with no one-gauge size, the bar's max splits into gauges")
check(L.filled(100, nil, 100, 0, nil) == 1, "a 100-point max with no one-gauge size is one gauge")
check(L.filled(nil, 100, 200, 2, nil) == 2, "the gauge count is used only when the points are missing")
check(L.filled(0, 100, 200, 2, nil) == 0, "a gauge count does not replace a point read of 0")
check(L.filled(50, nil, nil, 0, nil) == 0, "when the points cannot be split, the gauge count is the fallback")
check(L.filled(nil, nil, nil, nil, nil) == nil, "with no read at all, the caller asks the command flag")

local function row(gauges, kills, damage, stagger, limit)
    return { gauges = gauges, kills = kills, damage = damage, stagger = stagger, limit = limit }
end
check(L.ahead(row(2, 0, 0, 0, true), row(1, 0, 0, 0, true), true), "two ready Limits: the higher gauge cost wins a tie")
check(not L.ahead(row(2, 0, 0, 0, true), row(1, 1, 0, 0, true), true), "a Limit that kills beats a higher gauge that does not")
check(L.ahead(row(1, 0, 0, 0, true), row(0, 0, 900, 0, false), true), "on a break a Limit beats a spell that kills no more")
check(not L.ahead(row(2, 0, 0, 0, true), row(0, 1, 10, 0, false), true), "on a break a spell that kills more still wins")
check(L.ahead(row(0, 0, 40, 0, false), row(0, 0, 10, 0, false), false), "two spells stay on damage")
check(not L.ahead(row(1, 0, 0, 0, true), row(0, 0, 40, 0, false), false), "off a break a Limit does not outrank a harder spell")

os.exit(fails == 0 and 0 or 1)

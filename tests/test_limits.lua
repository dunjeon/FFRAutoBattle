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
check(L.ahead(row(3, 0, 0, 0, true), row(2, 0, 0, 0, true), true), "three gauges beat two on a break when nothing else differs")
check(L.gauges(200, 100) == 2, "200 points is two gauges when one gauge is 100")
check(L.gauges(300, nil) == 3, "with no live gauge size, 100 points is one gauge")
check(L.gauges(150, 100) == 2, "a cost rounds to the nearest gauge")
check(L.capacity(100, 300, nil) == 3, "a 300-point bar holds three gauges")
check(L.capacity(nil, nil, 4) == 4, "the library's gauge count is the bar's size")
check(L.holds(1, 1, 2, { 2 }), "a cheaper Limit waits while a higher one is still out of reach")
check(not L.holds(1, 2, 2, { 2 }), "a full bar does not wait")
check(not L.holds(1, 1, 1, { 2 }), "a bar that cannot hold the higher cost does not wait")
check(L.holds(1, 0, 3, { 3 }), "a one-gauge row waits for a three-gauge row the bar can still reach")
check(not L.holds(2, 3, 3, { 3 }), "once the higher cost can be paid, the cheaper row does not wait")
check(not L.holds(1, 1, 2, {}), "with no higher row, nothing waits")
check(not L.holds(1, nil, 2, { 2 }), "an unread bar does not wait")

os.exit(fails == 0 and 0 or 1)

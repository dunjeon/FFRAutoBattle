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

-- Each Limit's use case.
local function lim(role, gauges, area, lands, pour, blocked)
    return { role = role, gauges = gauges or 1, area = area or false, lands = lands or { true }, pour = pour or { 10 }, blocked = blocked or false }
end
local function foe(broken, remain, hp, boss)
    return { broken = broken, remain = remain or 100, hp = hp or 1, boss = boss or false }
end
local function plan(t)
    t.stage = t.stage or "main"
    t.up = t.up or 4
    t.down = t.down or 0
    t.filled = t.filled or 1
    t.max = t.max or 1
    return L.plan(t)
end
local p = plan({ stage = "urgent", limits = { lim("revive") }, foes = { foe(false) }, down = 2, up = 2 })
check(p and p.all, "two down: the party raise goes")
check(plan({ stage = "urgent", limits = { lim("revive") }, foes = { foe(false) }, down = 1, up = 3 }) == nil, "one down with three standing: the raise item or spell does it")
check(plan({ stage = "urgent", limits = { lim("revive") }, foes = { foe(false) }, down = 1, up = 2 }) ~= nil, "one down with two standing: the party raise goes")
check(plan({ stage = "urgent", limits = { lim("nuke") }, foes = { foe(true) } }) == nil, "the urgent step asks only the raise")
p = plan({ limits = { lim("double", 2) }, foes = { foe(true) }, filled = 2, max = 2 })
check(p and p.all and p.why:find("double"), "a stagger open: the party acts twice")
check(plan({ limits = { lim("double", 2) }, foes = { foe(false) }, filled = 2, max = 2 }) == nil, "no stagger: the double waits")
p = plan({ limits = { lim("stagger", 1, false, { true, true }, { 10, 10 }) }, foes = { foe(false, 50, 0.9), foe(true, 0, 0.5) } })
check(p and p.foe == 2, "a stagger Limit goes on the staggered body")
check(plan({ limits = { lim("stagger") }, foes = { foe(false, 5) }, max = 2, filled = 1 }) == nil, "a stagger Limit does not make the break")
p = plan({ limits = { lim("mark") }, foes = { foe(true, 0) }, boss = true })
check(p == nil, "the mark is not spent on a staggered body")
p = plan({ limits = { lim("mark", 1, false, { true }, { 20 }) }, foes = { foe(false, 300, 1, true) }, boss = true })
check(p and p.foe == 1 and p.why:find("mark"), "the mark goes on an open gauge before the break")
check(plan({ limits = { lim("mark", 1, false, { true }, { 20 }) }, foes = { foe(false, 300, 1, true) }, breakClose = true }) == nil, "the mark waits when the break is this round's")
check(plan({ limits = { lim("mark", 1, false, { true }, { 400 }) }, foes = { foe(false, 300, 1, true) } }) == nil, "a mark whose own hit empties the gauge is not a mark")
p = plan({ limits = { lim("fill") }, foes = { foe(false) } })
check(p and p.all and p.why:find("fill"), "no stagger: the fill goes so the bars grow")
p = plan({ limits = { lim("nuke", 1, true, { true, true }, { 40, 40 }) }, foes = { foe(false, 30), foe(false, 200) }, max = 2 })
check(p and p.all and p.why:find("lands the break"), "an area Limit whose stagger empties a gauge lands the break")
check(plan({ limits = { lim("nuke", 1, true, { true, true }, { 40, 40 }, true) }, foes = { foe(false, 30), foe(false, 200) }, max = 2 }) == nil, "an area Limit a foe nulls is not cast")
p = plan({ limits = { lim("nuke") }, foes = { foe(false, 300, 1, true) }, filled = 1, max = 1 })
check(p and p.why:find("bar full"), "a full bar is spent, not held")
check(plan({ limits = { lim("nuke") }, foes = { foe(false, 300, 1, true) }, filled = 1, max = 2 }) == nil, "a bar with room left keeps filling")
check(plan({ limits = { lim("stagger") }, foes = { foe(false, 300) }, filled = 1, max = 1 }) == nil, "a full bar still waits for the stagger its Limit needs")
-- Two gauges.
local hold = { limits = { lim("nuke", 1) }, foes = { foe(true, 0, 0.8, true) }, filled = 1, max = 2, higher = 2, boss = true }
check(plan(hold) == nil, "a long boss fight: one gauge waits for the two-gauge Limit")
hold.foes = { foe(true, 0, 0.2, true) }
check(plan(hold) ~= nil, "a boss under 30%: one gauge is spent")
hold = { limits = { lim("nuke", 1) }, foes = { foe(true, 0, 0.8, true) }, filled = 1, max = 2, higher = 2, boss = false }
check(plan(hold) ~= nil, "not a boss: one gauge is spent")
p = plan({ limits = { lim("nuke", 1), lim("nuke", 2) }, foes = { foe(true, 0, 0.8, true) }, filled = 2, max = 2, higher = 2, boss = true })
check(p and p.at == 2, "two gauges full: the two-gauge Limit goes")

os.exit(fails == 0 and 0 or 1)

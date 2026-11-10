-- lua5.4 tests/test_espers.lua
local E = dofile("Scripts/espers.lua")
local fails = 0
local function check(ok, msg)
    print((ok and "ok   " or "FAIL ") .. msg)
    if not ok then fails = fails + 1 end
end

check(E.stillOut(0, 100, nil, 4) == false, "a blank stay is not still out")
check(E.stillOut(0, 100, -1, 4) == false, "a table count of -1 is not a stay")
check(E.stillOut(0, 3, 2, 2) == true, "two turns of a party of two are still inside the stay")
check(E.stillOut(0, 4, 2, 2) == false, "the stay ends after that many ally commands")

local waiting = { seen = false, acted = false }
check(E.holding(nil, false) == false, "no call is out")
check(E.holding(nil, true) == true, "a unit on the field holds the call even if the mark was dropped")
check(E.holding(waiting, false) == true, "a call that has not acted stays out when the list misses it")
check(E.holding(waiting, true) == true, "the unit on the field is still out")
waiting.seen = true
check(E.holding(waiting, false) == true, "listed once, then missing, is still out until that unit acts")
waiting.acted = true
check(E.holding(waiting, true) == true, "after it acts, it stays out while the list still has it")
check(E.holding(waiting, false) == false, "after it acts, a list that had it and lost it is the unit leaving")
local unseen = { seen = false, acted = true }
check(E.holding(unseen, false) == false, "after it acts, a unit that is not up can be called again")
check(E.holding(unseen, true) == true, "after it acts, a unit that is still up stays out")

check(E.outLeveled(50, { 30, 35 }, 10) == true, "every foe ten or more under is out-leveled")
check(E.outLeveled(50, { 30, 41 }, 10) == false, "one foe inside the gap keeps the call open")
check(E.outLeveled(50, { 40 }, 10) == true, "exactly the gap counts as under")
check(E.outLeveled(50, { 30 }, 0) == false, "a gap of 0 is off")
check(E.outLeveled(nil, { 30 }, 10) == false, "an unread caller level keeps the call open")
check(E.outLeveled(50, { 30, false }, 10) == false, "an unread foe level keeps the call open")
check(E.outLeveled(50, {}, 10) == false, "no foes is not out-leveled")

local function hits(prefer, other)
    return { { factor = prefer, prefer = true }, { factor = other, prefer = false } }
end
local thunder = { element = "thunder", role = "damage", area = true }
local water = { element = "water", role = "damage", area = true }
local fire = { element = "fire", role = "damage", area = true }
local plain = { role = "damage", area = true }
local wall = { role = "guard" }

check(E.score(thunder, hits(3, 1)) == 100, "a weakness on the foe that matters is the call")
check(E.score(fire, hits(1, 3)) == 20, "a weakness on someone else does not outrank the foe that matters")
check(E.score(water, hits(0.5, 1)) == 10, "a hit the foe resists ranks last")
check(E.score(plain, hits(1, 1)) == 40, "a damage row with no element still lands")
check(E.score(plain, hits(0, 1)) == nil, "an area hit a foe nulls is not called, element or not")
check(E.score({ role = "damage" }, hits(1, 0)) == 40, "a single-target hit with no element ignores a null on someone else")
check(E.score(wall, hits(1, 1)) == 15, "a support row waits behind a hit that lands")
check(E.score(thunder, hits(0, 3)) == nil, "an area signature that one foe nulls is not called")
check(E.score({ element = "thunder", role = "damage" }, hits(3, 0)) == 100, "a single-target signature ignores a null on someone else")

local picked = E.best({
    { name = "water", fact = water, hits = hits(0.5, 1) },
    { name = "thunder", fact = thunder, hits = hits(3, 1) },
    { name = "wall", fact = wall, hits = hits(1, 1) },
    { name = "fire", fact = fire, hits = hits(1, 1) },
})
check(picked and picked.name == "thunder", "the equipped row that matches the foe is the one called")

local only = E.best({
    { name = "wall", fact = wall, hits = hits(1, 1) },
    { name = "water", fact = water, hits = hits(0, 1) },
})
check(only and only.name == "wall", "when every damage row is nulled, the support row is the call")

local function cand(name, fact, prefer, other, dealt, kills)
    return { name = name, fact = fact, hits = hits(prefer, other), dealt = dealt, kills = kills }
end
local measured = E.best({
    cand("thunder", thunder, 3, 1),
    cand("water", water, 0.5, 1, 900, 0),
})
check(measured and measured.name == "water", "a hit this fight already measured outranks an unmeasured element")
local harder = E.best({
    cand("thunder", thunder, 3, 1, 400, 0),
    cand("water", water, 0.5, 1, 900, 0),
})
check(harder and harder.name == "water", "the larger measured hit is the call")
local kill = E.best({
    cand("thunder", thunder, 3, 1, 5000, 0),
    cand("fire", fire, 1, 1, 200, 1),
})
check(kill and kill.name == "fire", "a measured kill comes before a harder hit")
local missed = E.best({
    cand("water", water, 0.5, 1, 0, 0),
    cand("thunder", thunder, 3, 1),
})
check(missed and missed.name == "thunder", "a measured miss leaves the element prior in place")
local nulled = E.best({
    cand("thunder", thunder, 0, 3, 9999, 1),
    cand("wall", wall, 1, 1),
})
check(nulled and nulled.name == "wall", "a measured hit the signature nulls is not called")

E.load({
    sprite = { unit = 70, element = "wind", role = "damage" },
    caller = { unit = 71, element = "thunder", role = "damage", area = true },
})
check(E.isUnit(70) and E.isUnit(71) and (not E.isUnit(9)), "the summon row's unit id is the unit on the field")
check(E.lookup("Sprite").unit == 70, "a lookup keeps the unit id")

os.exit(fails == 0 and 0 or 1)

-- lua5.4 tests/test_kits.lua
local K = dofile("Scripts/kits.lua")
local fails = 0
local function check(ok, msg)
    print((ok and "ok   " or "FAIL ") .. msg)
    if not ok then fails = fails + 1 end
end
K.load({ book = {
    ["formation:assail"] = { kind = "formation", rank = 1, turns = 3, party = true, timed = true },
    ["formation:bulwark"] = { kind = "formation", rank = 3, turns = 3, party = true, afterHit = true },
    ["placidity"] = { kind = "ready", rank = 5, turns = 5 },
    ["stratagem"] = { kind = "mark", rank = 1, turns = 3, timed = true },
}, draw = {}, stance = {}, stanceOff = {}, haste = {}, mechabo = {} })
local me = { id = 1, name = "Me", hp = 1 }
local function ctx(extra)
    local c = { allies = { me }, foes = { { id = 9, name = "Foe", gauge = 100 } }, selfId = 1, actions = 10, mp = 100, maxMp = 100,
        keep = 0, pay = true, claim = {}, sent = {} }
    for k, v in pairs(extra or {}) do c[k] = v end
    return c
end
local assail = { name = "Formation: Assail", cost = 6 }
local bulwark = { name = "Formation: Bulwark", cost = 8 }
local placid = { name = "Placidity", cost = 25 }
local mark = { name = "Stratagem", cost = 8 }
check(not K.pick({ assail }, ctx()), "no short buff in the opening")
check(not K.pick({ assail }, ctx({ chipped = true })), "a short buff waits for the right moment after the first hit")
check(K.pick({ assail }, ctx({ chipped = true, timedOk = true })), "a short buff goes when it can pay off")
check(not K.pick({ mark }, ctx()), "a mark waits too")
check(K.pick({ mark }, ctx({ timedOk = true })), "a mark goes when it can pay off")
check(not K.pick({ bulwark }, ctx()), "a defense formation waits for the first hit")
check(K.pick({ bulwark }, ctx({ chipped = true })), "a defense formation goes after it")
check(K.pick({ placid }, ctx()), "a long buff can go in the opening")
os.exit(fails == 0 and 0 or 1)

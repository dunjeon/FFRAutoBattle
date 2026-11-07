-- lua5.4 tests/test_health.lua
local H = dofile("Scripts/health.lua")
local fails = 0
local function check(ok, msg)
    print((ok and "ok   " or "FAIL ") .. msg)
    if not ok then fails = fails + 1 end
end

check(not H.walkedInHurt(nil), "no bar is not hurt")
check(not H.walkedInHurt(0), "empty is not a living hurt bar")
check(not H.walkedInHurt(0.5), "half is not under the hurt share")
check(H.walkedInHurt(0.49), "just under half walked in hurt")
check(H.walkedInHurt(0.04), "a sliver walked in hurt")
check(not H.walkedInHurt(1), "full is not hurt")

check(H.hitWouldDrop(12, 326, 14), "a hit already shown would drop 12 HP")
check(not H.hitWouldDrop(40, 326, 14), "40 HP survives a 14 hit")
check(not H.hitWouldDrop(180, 200, 250), "a hit over the whole bar is not a heal")
check(not H.hitWouldDrop(0, 200, 14), "a fallen ally is not this heal")

check(H.openingHurt(0.04, 12, 326, nil), "under half needs care with no hit yet")
check(H.openingHurt(0.65, 180, 270, 200), "above half still needs care when the hit would drop them")
check(not H.openingHurt(0.65, 180, 270, 14), "above half, and the hit would not drop them")

check(H.careStatus({ [1] = true }), "poison is an opening problem")
check(H.careStatus({ [11] = true }), "doom is an opening problem")
check(H.careStatus({ [9] = true }), "stop is an opening problem")
check(not H.careStatus({}), "an empty set is not")
check(not H.careStatus(nil), "no statuses is not")
check(not H.careStatus({ [89] = true }), "a break is not an ally problem")

local needs = { { id = 1, hp = 0.40 }, { id = 2, hp = 0.04 } }
check(H.openingTarget(1, needs, 1) == 2, "the healer takes the lowest")
check(H.openingTarget(2, needs, 1) == 2, "a hurt ally takes care of themselves")
check(H.openingTarget(3, needs, 1) == nil, "a healthy ally leaves it to the healer")
check(H.openingTarget(3, needs, nil) == 2, "with no healer, whoever is up takes the lowest")
check(H.openingTarget(1, {}, 1) == nil, "nobody waiting means no opening heal")
check(H.openingTarget(1, needs, 9) == 1, "someone else's heal still lets a hurt ally drink")

os.exit(fails == 0 and 0 or 1)

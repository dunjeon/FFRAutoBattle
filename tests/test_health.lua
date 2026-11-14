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

-- Heal amounts by calc, from the fight-43 rows. First Aid is power 15 of
-- the target's max HP (calc 5): 249 on Fina's 1663, 236 on Jake's 1575.
-- Cure, Cura and Pray scale with the caster: Fina measured 2.81 HP per power.
local firstAid = { name = "First Aid", power = 15, cost = 0, calc = H.MAX_RATIO, attr = 3 }
local pray = { name = "Pray", power = 200, cost = 14, calc = 2, attr = 3 }
local cure = { name = "Cure", power = 200, cost = 6, calc = 2, attr = 4 }
local cura = { name = "Cura", power = 500, cost = 18, calc = 2, attr = 4 }
local fina = { hp = 638, maxHp = 1663 }
check(math.floor(H.healAmount(firstAid, 2.81, fina)) == 249, "a max-HP share heal is that share of the target's max HP")
check(H.healAmount(firstAid, nil, fina) ~= nil, "a share heal needs no measured rate")
check(H.healAmount(firstAid, 2.81, {}) == nil, "a share heal with no max HP read has no amount")
check(math.floor(H.healAmount(pray, 2.81, fina)) == 562, "a stat-scaled heal is its power times the rate")
check(H.healAmount(pray, nil, fina) == nil, "a stat-scaled heal with no rate has no amount")
check(H.healAmount({ power = 300, calc = H.FIXED }, 2.81, fina) == 300, "a Fixed heal is its power")
check(math.floor(H.healAmount({ power = 10, calc = H.CUR_RATIO }, nil, fina)) == 63, "a current-HP share is that share of current HP")

local function rank(s, missing, rate) return H.spellRank(s, missing, 0, false, 3, rate, fina) end
-- Fina at 638 of 1663: 1025 missing. Nothing covers it but Cura; Pray gives more than First Aid.
check(rank(pray, 1025, 2.81) > rank(firstAid, 1025, 2.81), "with a rate, Pray's 562 outranks First Aid's 249 when neither covers")
check(rank(cura, 1025, 2.81) > rank(pray, 1025, 2.81), "a heal that covers what is missing outranks one that does not")
-- 200 missing: First Aid covers it for free and overheals least.
check(rank(firstAid, 200, 2.81) > rank(pray, 200, 2.81), "the closest cover wins: First Aid when it is enough")
check(rank(firstAid, 200, 2.81) > rank(cure, 200, 2.81), "the closest cover beats a bigger spell")
-- No rate yet: First Aid's free cost no longer makes it look stronger than Pray.
check(rank(pray, 1025, nil) > rank(firstAid, 1025, nil), "before a rate, Pray is not passed over for First Aid's cost of 0")
check(H.spellRank(firstAid, 1025, 4, true, 3, 2.81, fina) > 1000, "a party heal still wins when most of the party is hurt")

os.exit(fails == 0 and 0 or 1)

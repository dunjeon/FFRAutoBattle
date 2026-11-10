-- lua5.4 tests/test_shapes.lua
local S = dofile("Scripts/shapes.lua")
local fails = 0
local function check(ok, msg)
    print((ok and "ok   " or "FAIL ") .. msg)
    if not ok then fails = fails + 1 end
end

-- A hand cast seen in a fight report: a command, then two All casts under it.
--   action 1: id 400730, parent 1/1, targets [3]
--   action 2: id 225010, parent 1/400730, all, targets [8,9]
--   action 3: id 225040, parent 1/400730, all, targets [8,9]
--   command 1, keys [1/1 1/400730 1/220020 1/220060]
local parents = { [400730] = true }
local attrs = { [400730] = 3, [225010] = 4, [225040] = 4, [405010] = 1 }
local function isParent(id) return parents[id] == true end
local function attrOf(id) return attrs[id] end
local items = {
    { actionId = 400730, pCat = 1, pId = 1 },
    { actionId = 225010, pCat = 1, pId = 400730 },
    { actionId = 225040, pCat = 1, pId = 400730 },
}
local keys = { { 1, 1 }, { 1, 400730 }, { 1, 220020 }, { 1, 220060 } }
local shape = S.read(items, keys, 1, isParent, attrOf)
check(shape and shape.parent == 400730 and shape.picks == 2, "a hand decide gives the command and its pick count")
check(shape and S.fits(shape, 4) and not S.fits(shape, 1), "the picks' attribute fits, another does not")
check(shape and #shape.prefix == 2 and shape.prefix[2][2] == 400730 and shape.keyCat == 1, "the keys before the picks are kept")

-- Built again from the shape, the decide matches what the game took.
local entries, built = S.build(shape, 3, {
    { id = 225010, menuId = 220020, isAll = true, targets = { 8, 9 } },
    { id = 225040, menuId = 220060, isAll = true, targets = { 8, 9 } },
})
check(#entries == 3 and entries[1].actionId == 400730 and entries[1].pCat == 1 and entries[1].pId == 1
    and entries[1].targets[1] == 3, "the command goes first, on the caster, under its own parent")
check(entries[2].pId == 400730 and entries[3].pId == 400730 and entries[2].isAll and entries[3].targets[2] == 9,
    "each pick goes under the command, with its own targets")
local want = { { 1, 1 }, { 1, 400730 }, { 1, 220020 }, { 1, 220060 } }
local same = #built == #want
for i, k in ipairs(want) do same = same and built[i][1] == k[1] and built[i][2] == k[2] end
check(same, "the action keys match the hand decide")

-- Kept across sessions.
local line = S.encode(shape)
check(not line:find("[;#]"), "the saved line has no comment marks")
local back = S.decode(400730, line)
check(back and S.same(back, shape), "a saved shape reads back the same")
check(S.decode(400730, "picks:0 attrs:4") == nil and S.decode(400730, "picks:2 attrs:") == nil,
    "a shape with no picks or no kinds is not kept")

-- What does not make a shape.
check(S.read({ { actionId = 405010, pCat = 1, pId = 1 } }, {}, 1, isParent, attrOf) == nil, "a plain command is no shape")
check(S.read({ items[1] }, keys, 1, isParent, attrOf) == nil, "the command alone is no shape")
check(S.read({ items[1], { actionId = 225010, pCat = 1, pId = 1 } }, keys, 1, isParent, attrOf) == nil,
    "a second entry that is not under the command is no shape")
check(S.read({ items[1], { actionId = 999, pCat = 1, pId = 400730 } }, keys, 1, isParent, attrOf) == nil,
    "a pick whose row is unknown is no shape")

-- A second cast adds what it showed, unless the count changed.
attrs[226000] = 5
local other = S.read({ items[1], { actionId = 226000, pCat = 1, pId = 400730 }, items[3] }, keys, 1, isParent, attrOf)
local merged = S.merge(S.decode(400730, line), other)
check(S.fits(merged, 4) and S.fits(merged, 5), "a second hand cast adds its kinds")
local three = S.read({ items[1], items[2], items[3], items[2] }, keys, 1, isParent, attrOf)
check(S.merge(shape, three).picks == 3, "a new count replaces the old one")

if fails > 0 then print(fails .. " failed") os.exit(1) end

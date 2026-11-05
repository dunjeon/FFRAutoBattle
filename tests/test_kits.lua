-- lua5.4 tests/test_kits.lua
local K = dofile("Scripts/kits.lua")
local fails = 0
local function check(ok, msg)
    print((ok and "ok   " or "FAIL ") .. msg)
    if not ok then fails = fails + 1 end
end
K.load({ draw = { lure = { kind = "provoke", turns = 3 } }, haste = { quick = { party = false } } })
check(K.key("Lure") == "lure" and K.key("Quick") == "quick", "draw and haste rows are found")
check(K.key("Other") == nil, "anything else isn't")
check(K.pick == nil and K.stance == nil and K.gated == nil, "no hand-ranked kit book remains")
local me = { id = 1, name = "Me", hp = 1 }
local you = { id = 2, name = "You", hp = 1 }
local lure = { name = "Lure", cost = 0 }
check(K.pickDraw({ lure }, { allies = { me, you }, selfId = 1, danger = true, pay = true, mp = 10, keep = 0 }), "a draw answers a danger on the field")
check(not K.pickDraw({ lure }, { allies = { me, you }, selfId = 1, danger = false, pay = true, mp = 10, keep = 0 }), "a calm field spends none")
os.exit(fails == 0 and 0 or 1)

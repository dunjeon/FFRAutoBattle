-- lua5.4 tests/test_debuffs.lua
local D = dofile("Scripts/debuffs.lua")
local I = dofile("Scripts/items.lua")
local fails = 0
local function check(ok, msg)
    print((ok and "ok   " or "FAIL ") .. msg)
    if not ok then fails = fails + 1 end
end
local function skill(effect) return { name = effect, known = { effect = effect } } end
local protect, shell, brave = skill("protect"), skill("shell"), skill("attack")
local foes = { { id = 1, prefer = true } }
local function pick(share, list)
    return (D.choose(list or { protect, shell, brave }, foes, {}, {}, false, share))
end

check(pick({ physical = 1, magic = 0 }) == protect, "a physical party lowers physical defense")
check(pick({ physical = 0, magic = 1 }) == shell, "a magic party lowers magic defense")
check(pick({ physical = 0.3, magic = 0.7 }) == shell, "a mixed party follows its larger share")
check(pick({ physical = 0.7, magic = 0.3 }) == protect, "either way round")
check(pick({ physical = 0, magic = 1 }, { protect, brave }) == brave, "a defense debuff that wouldn't help gives way to another")
check(pick({ physical = 0, magic = 1 }, { protect }) == nil, "and if it's all there is, the turn isn't spent on it")
check(pick(nil) == protect, "with nothing to go on, the old order stands")

I.load({ clears = { ["cure all"] = true, ["doom drop"] = { [11] = true }, ["eye drop"] = { [2] = true } } })
local doomed = { id = 2, statuses = { [11] = true } }
local blinded = { id = 3, statuses = { [2] = true } }
local party = { doomed, blinded }
check(I.holdDoomCure("Cure All", 1, blinded, party), "the last item that cures everything waits for doom")
check(I.holdDoomCure("Doom Drop", 1, blinded, party), "so does any item whose row cures doom, whatever it's called")
check(not I.holdDoomCure("Eye Drop", 1, blinded, party), "an item that can't cure doom isn't held")
check(not I.holdDoomCure("Doom Drop", 2, blinded, party), "a spare one isn't held")
check(not I.holdDoomCure("Doom Drop", 1, doomed, party), "it goes to the ally with doom")
check(not I.holdDoomCure("Doom Drop", 1, blinded, { blinded }), "with no doom about, it can be used")
os.exit(fails == 0 and 0 or 1)

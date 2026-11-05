-- lua5.4 tests/test_debuffs.lua
local D = dofile("Scripts/debuffs.lua")
local fails = 0
local function check(ok, msg)
    print((ok and "ok   " or "FAIL ") .. msg)
    if not ok then fails = fails + 1 end
end
local function skill(effect) return { name = effect, known = { effect = effect } } end
local protect, shell, other = skill("defenseDown"), skill("mindDown"), skill("poison")
local foes = { { id = 1, prefer = true } }
local function pick(share, list)
    return (D.choose(list or { protect, shell, other }, foes, {}, {}, share))
end

check(pick({ physical = 1, magic = 0 }) == protect, "a physical party lowers physical defense")
check(pick({ physical = 0, magic = 1 }) == shell, "a magic party lowers magic defense")
check(pick({ physical = 0.3, magic = 0.7 }) == shell, "a mixed party follows its larger share")
check(pick({ physical = 0.7, magic = 0.3 }) == protect, "either way round")
check(pick({ physical = 1, magic = 0 }, { other }) == nil, "a debuff with no general rule isn't cast")
check(pick({ physical = 0, magic = 1 }, { protect }) == nil, "and if it's all there is, the turn isn't spent on it")
check(pick(nil) == protect, "with nothing to go on, the old order stands")

os.exit(fails == 0 and 0 or 1)

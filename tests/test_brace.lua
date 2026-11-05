-- lua5.4 tests/test_brace.lua
local B = dofile("Scripts/brace.lua")
local fails = 0
local function check(ok, msg)
    print((ok and "ok   " or "FAIL ") .. msg)
    if not ok then fails = fails + 1 end
end
local PHYS, MAGIC = 1, 2
local function cut(which, pct, status, turns) return { type = 26, status = status or 0, turns = turns or 3, params = { which, pct } } end
local defend = { target = 0, effects = { cut(1, 50, 36, 1), cut(2, 50, 0, 1) } }
local shell = { target = 1, effects = { cut(2, 30, 27, 5) } }
local wall = { target = 2, effects = { cut(2, 50, 43, 3) } }
local cover = { target = 1, effects = { { type = 41, status = 34, turns = 2, params = { 1, 0 } } } }

-- What a row is, for any move that has these effects.
check(B.describe(defend, MAGIC).through == 0.5 and B.describe(defend, MAGIC).scope == "self", "a cut comes from the row, on the kind asked about")
check(B.describe(shell, PHYS) == nil, "a magic cut does nothing for a physical hit")
check(B.describe(shell, nil) == nil, "with the kind unknown, only a cut of both kinds counts")
check(B.describe(defend, nil) == nil, "two separate cuts aren't one of both kinds")
check(B.describe({ target = 2, effects = { cut(0, 15, 82) } }, nil).through == 0.85, "a cut of both kinds counts when the kind is unknown")
check(B.describe({ target = 1, effects = { { type = 2, params = {} } } }, MAGIC) == nil, "a row with no cut or cover is not a guard")
local map = B.statusCuts({ defend, shell })
check(map[36][MAGIC] == 0.5 and map[36][PHYS] == 0.5, "a status carries every cut of its row")
check(map[27][MAGIC] == 0.7 and map[27][PHYS] == nil, "a status only cuts its own kind")
check(math.abs(B.through({ [36] = true, [27] = true }, MAGIC, map) - 0.35) < 0.001, "cuts on one unit multiply")
check(B.through({ [36] = true }, nil, map) == 1, "with the kind unknown, nothing is counted on")

local function opt(row, kind, extra)
    local d = B.describe(row, kind)
    for k, v in pairs(extra or {}) do d[k] = v end
    return d
end
local function team()
    return {
        { id = 1, hp = 1000, maxHp = 2000, hit = 1500, share = 1 },
        { id = 2, hp = 1000, maxHp = 2000, hit = 1500, share = 1 },
        { id = 3, hp = 1800, maxHp = 2000, hit = 1500, share = 1 },
    }
end

check(B.lethal(team()) == 2, "the count of who would fall")
check(#B.rank({ { id = 1, hp = 2000, maxHp = 2000, hit = 500, share = 1 } }, { opt(defend, MAGIC) }, 1, false) == 0, "nobody would fall, so nothing to do: keep hitting")
local r = B.rank(team(), { opt(defend, MAGIC), opt(wall, MAGIC) }, 1, false)
check(r[1].option.scope == "all" and r[1].saved == 2, "a party guard that saves two beats a Defend that saves one")
r = B.rank(team(), { opt(defend, MAGIC) }, 1, false)
check(#r == 1 and r[1].targets[1] == 1, "Defend saves the one using it")
r = B.rank(team(), { opt(defend, MAGIC) }, 3, false)
check(#r == 0, "a unit who lives through it doesn't Defend")

local low = team()
low[1].hp = 500
check(#B.rank(low, { opt(defend, MAGIC) }, 1, false) == 0, "when not even Defend saves them, the turn goes elsewhere")

local before = team()
before[1].actsFirst = true
check(#B.rank(before, { opt(defend, MAGIC) }, 1, false) == 0, "a one-action guard is wasted if they act again before the hit")
check(#B.rank(before, { opt(wall, MAGIC) }, 3, false) == 1, "a longer guard outlasts their next action")

local heal = { heal = 900, scope = "one", cost = 6 }
r = B.rank(team(), { heal }, 3, false)
check(r[1] and r[1].saved == 1, "a heal counts when the HP it gives is enough to live")
check(#B.rank(team(), { { heal = 100, scope = "one" } }, 3, false) == 0, "a heal too small to matter doesn't count")
local spent = team()
spent[1].hp, spent[1].maxHp = 1000, 1100
spent[2].hp, spent[2].maxHp = 1000, 1100
check(#B.rank(spent, { heal }, 3, false) == 0, "a heal can't go over max HP, so it can't save them")
local stance = team()
stance[1].noSpell, stance[2].noSpell = true, true
check(#B.rank(stance, { { heal = 900, scope = "one", spell = true } }, 3, false) == 0, "a spell heal doesn't reach an ally who can't take one")

local covered = opt(cover, MAGIC)
check(#B.rank(team(), { covered }, 3, false) == 0, "cover isn't counted on a group hit")
r = B.rank(team(), { covered }, 3, true)
check(r[1] and r[1].saved == 1, "cover saves an ally from a hit aimed at one, if the one covering lives")
check(#B.rank(team(), { covered }, 1, true) == 0, "cover isn't counted when the one covering would fall")

local has = team()
has[1].statuses, has[2].statuses = { [43] = true }, { [43] = true }
check(#B.rank(has, { opt(wall, MAGIC) }, 3, false) == 0, "a guard already on them adds nothing")
local sheltered = team()
sheltered[1].share, sheltered[2].share = 0.5, 0.5
check(B.lethal(sheltered) == 0, "a guard that is already up counts toward surviving")

r = B.rank(team(), { { heal = 900, scope = "one", cost = 40 }, { heal = 900, scope = "one", cost = 6 } }, 3, false)
check(r[1].option.cost == 6, "the cheaper of two equal answers")
os.exit(fails == 0 and 0 or 1)

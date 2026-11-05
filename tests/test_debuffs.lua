-- lua5.4 tests/test_debuffs.lua
local D = dofile("Scripts/debuffs.lua")
local I = dofile("Scripts/items.lua")
local fails = 0
local function check(ok, msg)
    print((ok and "ok   " or "FAIL ") .. msg)
    if not ok then fails = fails + 1 end
end
local function skill(effect) return { name = effect, known = { effect = effect } } end
local protect, shell, brave = skill("deprotect"), skill("deshell"), skill("debrave")
local faith = skill("defaith")
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

-- Debuffs that cut a foe's damage follow the damage it really deals.
local function aimed(deals, list)
    return (D.choose(list, { { id = 1, prefer = true, deals = deals } }, {}, {}, false, nil))
end
local magicFoe = D.dealsOf({ [1] = { total = 33265, dtype = 2 }, [2] = { total = 7558, dtype = 1 } })
check(math.abs(magicFoe.physical - 0.185) < 0.001, "a foe's split comes from what it has dealt")
check(aimed(magicFoe, { brave, faith }) == faith, "a mostly magic foe gets Defaith")
check(aimed(magicFoe, { brave }) == brave, "a small physical share still gets Debrave")
local physFoe = D.dealsOf({ [1] = { total = 900, dtype = 1 }, [2] = { total = 100, dtype = 2 } })
check(aimed(physFoe, { brave, faith }) == brave, "a mostly physical foe gets Debrave")
check(aimed(physFoe, { faith }) == faith, "a small magic share still gets Defaith")
check(aimed({ physical = 0.5, magic = 0.5 }, { brave }) == brave, "a mixed foe can take either")
check(aimed(nil, { brave }) == brave, "with nothing to go on, it stays available")
local marked = { name = "Soften", known = { effect = "deprotect" }, enemyStatus = { [16] = true } }
local held = { id = 4, prefer = true, statuses = {} }
local claimed = { [4] = { deprotect = true } }
check(D.up("deprotect", held, claimed, {}, marked) == true, "a listed status that was claimed and never seen stays up")
check(D.choose({ marked }, { held }, claimed, {}, false, { physical = 1 }) == nil, "a resist is not cast every turn")
local saw = { [4] = { deprotect = true } }
local again, _, why = D.choose({ marked }, { held }, claimed, saw, false, { physical = 1 })
check(again == marked and why == "refresh", "seen, then gone, is a refresh")
held.statuses = { [16] = true }
check(D.up("deprotect", held, claimed, saw, marked) == true, "a listed status still showing is up")
check(D.dealsOf({}, "magic").magic == 1 and D.dealsOf(nil, "physical").physical == 1, "before any hit, its dangerous moves are the guide")
check(D.dealsOf({}, nil) == nil, "no hits and no guide, no answer")
check(aimed(magicFoe, { protect }) == protect, "a debuff for the party's own damage isn't affected")

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
I.load({ items = { elixir = "both" }, leave = {}, attack = {}, clears = {} })
local elixir = I.entry(9, "Elixir", 1, {})
check(elixir and elixir.hp and elixir.mp and elixir.kind == "heal", "a row filed as both restores HP and MP")
local potion = I.entry(11, "Potion", 1, { rowHp = true, amount = 100 })
local mega = I.entry(10, "Mega Potion", 1, { rowHp = true, party = true, amount = 500 })
local partyItem = I.recovery({ potion, mega }, "heal", { partyOnly = true, spread = false })
check(partyItem and partyItem.party, "a party item is spent when the caller asked only for one")
check(I.recovery({ potion }, "heal", { partyOnly = true, spread = false }) == nil, "with no party item, that request spends nothing")
-- MP items: the smallest that covers the gap, one-target first, no fixed amount last.
local ether = { name = "Ether", mp = true, amount = 50 }
local turbo = { name = "Turbo", mp = true, amount = 150 }
local mist = { name = "Mist", mp = true, amount = 50, party = true }
local mpElixir = { name = "Elixir", mp = true, hp = true, kind = "heal" }
local mpMega = { name = "Megalixir", mp = true, hp = true, kind = "heal", party = true }
local function mpPick(bag, gap) return I.recovery(bag, "mp", { missing = gap, dire = false }) end
check(mpPick({ mpMega, mpElixir, mist, turbo, ether }, 40) == ether, "the smallest that covers the gap, whatever the bag order")
check(mpPick({ ether, turbo }, 100) == turbo, "a small gap's item isn't picked for a larger gap")
check(mpPick({ turbo, ether }, 500) == turbo, "when none covers, the largest")
check(mpPick({ mist, ether }, 500) == ether, "a one-target item comes before a party item")
check(mpPick({ mpElixir, mist }, 40) == mist, "a sized party item comes before a row with no fixed amount")
check(mpPick({ mpMega, mpElixir }, 40) == mpElixir, "with only percentage rows, one target before the party")
check(mpPick({ turbo, ether }, nil) == ether, "an unread gap takes the smallest")
check(mpPick({ { name = "Phoenix", mp = true, kind = "revive", amount = 50 } }, 40) == nil, "a raise is not an MP item")
-- The sighting comes from the row's own status, the same path the planner uses.
local softened = { id = 7, prefer = true, statuses = {} }
local softOn, softIds, softSeen = { [7] = { deprotect = true } }, { [7] = { deprotect = { [16] = true } } }, {}
D.noteSeen(softened, softOn, softIds, softSeen)
check(D.choose({ marked }, { softened }, softOn, softSeen, false, { physical = 1 }) == nil, "not showing yet, and never seen, is not cast again")
softened.statuses = { [16] = true }
D.noteSeen(softened, softOn, softIds, softSeen)
check(D.up("deprotect", softened, softOn, softSeen, marked) == true, "showing is up")
softened.statuses = {}
D.noteSeen(softened, softOn, softIds, softSeen)
local redo, _, redoWhy = D.choose({ marked }, { softened }, softOn, softSeen, false, { physical = 1 })
check(redo == marked and redoWhy == "refresh", "a row's status that showed and wore off is refreshed")
local unclaimed = {}
D.noteSeen({ id = 8, statuses = { [16] = true } }, {}, {}, unclaimed)
check(unclaimed[8] == nil, "a status nobody claimed is not noted for a row effect")
os.exit(fails == 0 and 0 or 1)

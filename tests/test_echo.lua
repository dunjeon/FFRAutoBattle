-- lua5.4 tests/test_echo.lua
local E = dofile("Scripts/echo.lua")
local fails = 0
local function check(ok, msg)
    print((ok and "ok   " or "FAIL ") .. msg)
    if not ok then fails = fails + 1 end
end

-- A hand Dualcast seen in a fight report, read as main.lua reads a decide:
--   action 1: id 400730, unit 3, parent 1/1, targets [3]
--   action 2: id 225010, parent 1/400730, all, targets [8,9]
--   action 3: id 225040, parent 1/400730, all, targets [8,9]
--   command 1, keys [1/1 1/400730 1/220020 1/220060]
local function dualcast()
    return {
        cmdType = 0, notConsume = false, calcOrder = true, command = 1,
        keys = { { 1, 1 }, { 1, 400730 }, { 1, 220020 }, { 1, 220060 } },
        entries = {
            { id = 400730, unit = 3, item = false, all = false, pCat = 1, pId = 1, params = {},
                targets = { { id = 3, side = "self" } } },
            { id = 225010, unit = 3, item = false, all = true, pCat = 1, pId = 400730, params = {},
                targets = { { id = 8, side = "foe" }, { id = 9, side = "foe" } } },
            { id = 225040, unit = 3, item = false, all = true, pCat = 1, pId = 400730, params = {},
                targets = { { id = 8, side = "foe" }, { id = 9, side = "foe" } } },
        },
    }
end
local function hit(id, foe)
    return {
        cmdType = 0, notConsume = false, calcOrder = true, command = id, keys = { { 1, id } },
        entries = { { id = id, unit = 1, item = false, all = false, pCat = 1, pId = id, params = { 7 },
            targets = { { id = foe, side = "foe" } } } },
    }
end

-- The tape.
local tape = E.new()
check(E.turn(tape, "Vivi") == nil, "nothing recorded is no turn")
check(E.note(tape, "Vivi", dualcast(), false) == 1, "a hand turn is kept")
check(#E.turn(tape, "Vivi")[1].entries == 3, "the Dualcast keeps its command and both picks")
check(E.note(tape, "Vivi", hit(220020, 8), true) == 2, "a second decide in the same turn is added to it")
check(E.note(tape, "Vivi", hit(220060, 9), false) == 1 and E.turn(tape, "Vivi")[1].entries[1].id == 220060,
    "a new turn by hand replaces the old one")
check(E.note(tape, "Steiner", hit(10, 8), false) == 1 and E.turn(tape, "Vivi") ~= nil, "each character has their own turn")
check(E.note(tape, "Steiner", { entries = {} }, false) == nil and E.turn(tape, "Steiner")[1].entries[1].id == 10,
    "an empty decide changes nothing")
local kept = dualcast()
E.note(tape, "Quina", kept, false)
kept.entries[1].id = 1
check(E.turn(tape, "Quina")[1].entries[1].id == 400730, "the tape keeps its own copy")

check(E.step(1, 1) == 1 and E.step(2, 1) == 1, "a one-decide turn repeats on an extra menu")
check(E.step(1, 2) == 1 and E.step(2, 2) == 2 and E.step(3, 2) == 1, "a two-decide turn goes in order, then starts over")
check(E.step(1, 0) == nil, "an empty turn has no step")

-- Targets. Ids in game order, best first, as main.lua's look gives them.
local function look(foes, allies, names)
    return {
        valid = function(_, side) if side == "foe" then return foes end return allies end,
        ally = function(name) return names and names[name] end,
    }
end

-- Same fight, everyone still up: the decide goes out as it was sent.
local same = E.aim(dualcast(), 3, 3, look({ 8, 9 }, { 1, 3 }))
check(same.command == 1 and #same.keys == 4 and same.keys[4][2] == 220060, "the command and keys are the player's")
check(same.entries[1].unit == 3 and same.entries[1].targets[1] == 3, "the command stays on the caster")
check(same.entries[2].pId == 400730 and same.entries[3].pId == 400730, "each pick stays under the command")
check(same.entries[2].targets[1] == 8 and same.entries[2].targets[2] == 9, "an All cast keeps every foe")

-- Next fight: new unit ids, a foe fewer.
local later = E.aim(dualcast(), 2, 3, look({ 12 }, { 0, 2 }))
check(later.entries[1].unit == 2 and later.entries[2].unit == 2 and later.entries[3].unit == 2, "every action goes to the caster's new unit")
check(later.entries[1].targets[1] == 2, "a self target follows the caster")
check(#later.entries[2].targets == 1 and later.entries[2].targets[1] == 12, "an All cast takes the foes there are now")

-- One target.
local kept1 = E.aim(hit(220020, 8), 1, 1, look({ 9, 8 }, {}))
check(kept1.entries[1].targets[1] == 8, "a foe still standing stays the target")
check(kept1.entries[1].params[1] == 7, "the parameters are kept")
local moved = E.aim(hit(220020, 8), 1, 1, look({ 9, 10 }, {}))
check(moved.entries[1].targets[1] == 9, "a fallen foe's hit goes to the best foe left")
local none, why = E.aim(hit(220020, 8), 1, 1, look({}, {}))
check(none == nil and why ~= nil, "no foe to hit hands the turn back")

-- Allies.
local heal = {
    command = 5, keys = {}, entries = { { id = 5, unit = 1, all = false, pCat = 1, pId = 5, params = {},
        targets = { { id = 4, side = "ally", name = "Garnet" } } } },
}
check(E.aim(heal, 1, 1, look({}, { 6, 2 }, { Garnet = 2 })).entries[1].targets[1] == 2, "an ally is found by name in a new fight")
check(E.aim(heal, 1, 1, look({}, { 6 }, { Garnet = 2 })).entries[1].targets[1] == 6,
    "an ally who can't take it gives way to the best ally who can")
check(E.aim(heal, 1, 1, look({}, {}, { Garnet = 2 })) == nil, "a raise with nobody down hands the turn back")
local odd = { entries = { { id = 5, unit = 1, targets = { { id = 4, side = "?" } } } } }
check(E.aim(odd, 1, 1, look({}, {})).entries[1].targets[1] == 4, "a target of unknown side is kept as sent")

-- Two single targets on one foe list do not both take the same foe while another is up.
local two = { entries = { { id = 7, unit = 1, targets = { { id = 8, side = "foe" }, { id = 9, side = "foe" } } } } }
local spread, groupMoved = E.aim(two, 1, 1, look({ 10, 11, 12 }, {}))
check(#spread.entries[1].targets == 3 and spread.entries[1].targets[3] == 12, "a group action takes every foe up now")
check(#groupMoved == 1 and groupMoved[1].from == "8, 9" and #groupMoved[1].group == 3, "a group that lost targets is one change")
local _, groupSame = E.aim(two, 1, 1, look({ 8, 9 }, {}))
check(#groupSame == 0, "a group with every target still up is no change")
local rec = dualcast()
E.aim(rec, 2, 3, look({ 12 }, {}))
check(rec.entries[1].unit == 3 and #rec.entries[2].targets == 2, "aiming does not change the tape")

-- What it spends.
local items, skills = E.uses(dualcast())
check(next(items) == nil and #skills == 3, "a Dualcast spends three skill rows")
check(skills[1].top and not skills[2].top and not skills[3].top, "only the command sits under the menu")
check(skills[2].all, "an All pick is costed as All")
local potion = { entries = { { id = 1, item = true }, { id = 1, item = true } } }
check(E.uses(potion)[1] == 2, "an item counts once per use")


check(E.describe(dualcast(), function(id) return "#" .. id end) == "#400730 + #225010 (all) + #225040 (all)", "the log names every action")


-- The targets it changed, for the log.
local _, none0 = E.aim(hit(220020, 8), 1, 1, look({ 8 }, {}))
check(#none0 == 0, "a target kept is no change")
local named = hit(220020, 8)
named.entries[1].targets[1].name = "Goblin A"
local _, moved1 = E.aim(named, 1, 1, look({ 9 }, {}))
check(#moved1 == 1 and moved1[1].from == "Goblin A" and moved1[1].to == 9 and moved1[1].side == "foe", "a new target is a change, named by the old one")
local _, fresh = E.aim(dualcast(), 2, 3, look({ 12 }, {}))
check(#fresh == 2 and fresh[1].from == "8, 9" and fresh[2].from == "8, 9",
    "a self target following the caster is no change; each All cast that lost its foes is one")
local _, byName = E.aim(heal, 1, 1, look({}, { 6, 2 }, { Garnet = 2 }))
check(#byName == 0, "an ally found by name is no change")

-- Across sessions.
local saved = E.new()
E.note(saved, "Vivi", dualcast(), false)
E.note(saved, "Vivi", hit(220020, 8), true)
E.note(saved, "Mr. \"Q\"\n's", heal, false)
local text = E.encode(saved)
local back, err = E.decode(text)
check(back ~= nil, "a saved tape reads back: " .. tostring(err))
check(back and #back.turns.Vivi == 2 and #back.turns.Vivi[1].entries == 3, "every decide and every action comes back")
local d1 = back and back.turns.Vivi[1]
check(d1 and d1.command == 1 and d1.keys[4][2] == 220060 and d1.entries[2].pId == 400730 and d1.entries[2].all == true
    and d1.entries[1].targets[1].side == "self" and d1.entries[2].targets[2].id == 9, "the Dualcast comes back exactly")
check(back and back.turns.Vivi[2].entries[1].params[1] == 7, "the parameters come back")
check(back and back.turns["Mr. \"Q\"\n's"] ~= nil, "an odd name comes back")
check(E.encode(back) == text, "a tape read back saves the same")
check(E.decode('return { version = 1, turns = {}, wheel = { skip = true } }').wheel == nil, "a wheel from an older build is not read")
check(E.decode(E.encode(E.new())) ~= nil, "an empty tape saves and reads")

check(E.decode("") == nil and E.decode(nil) == nil, "no file is no tape")
check(E.decode("return {") == nil, "a cut-off file is no tape")
check(E.decode("return 5") == nil, "a file without a tape is no tape")
check(E.decode("return { version = 99, turns = {} }") == nil, "another version is not read")
check(E.decode("return os.exit()") == nil, "the file can reach nothing outside itself")
local mixed = E.decode('return { version = 1, turns = { A = { { entries = { { id = 5 } } } }, B = { { entries = {} } }, C = 3 } }')
check(mixed and mixed.turns.A and (mixed.turns.B == nil) and (mixed.turns.C == nil),
    "a bad turn is dropped, the rest is kept")
check(E.summary(back) == "2 turns (Mr. \"Q\"\n's, Vivi)", "the log names who has a turn")
check(E.summary(E.new()) == "0 turns (nobody)", "an empty tape says so")


-- An echo sent the turn's first part, then the player sent the next by hand.
local cut = E.new()
E.note(cut, "Rain", hit(1, 8), false)
E.note(cut, "Rain", hit(2, 8), true)
E.note(cut, "Rain", hit(3, 8), true)
check(E.note(cut, "Rain", hit(4, 8), true, 1) == 2 and E.turn(cut, "Rain")[2].entries[1].id == 4,
    "a hand part after an echoed part replaces the rest of the turn")
check(E.note(cut, "Rain", hit(5, 8), false, 1) == 1, "a new turn ignores the cut")

os.exit(fails == 0 and 0 or 1)

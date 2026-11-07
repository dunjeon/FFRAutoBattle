-- The game's own rows, turned into what the planner reads. This is the only
-- source of skill, Limit, Esper, role, item, and enemy facts. main.lua walks
-- the live DataTables and hands the rows here. Nothing here names a skill, an
-- item, or an enemy. Numbers are the game's enums (mucha_enums.hpp).

local M = {}

local ELEMENT = { "fire", "ice", "wind", "earth", "thunder", "water", "light", "dark" }
local PHYS, MAGIC = 1, 2
local UP = 0
local T_SELF, T_GROUP, T_SPREAD, T_ALL = 0, 2, 3, 4
local FRIEND, ENEMY = 1, 2
local A_FIGHT, A_LB, A_SUMMON, A_FINISH, A_THROW, A_MONEY, A_MIMIC, A_MECHA = 1, 5, 7, 9, 11, 12, 14, 8

local E = {
    PARAM = 2, CONT = 3, ESCAPE = 5, MIMIC2 = 13, STEAL = 23, CURE = 19, REVIVE = 20, DEF = 26, BREAKDEF = 27,
    ANALYZE = 29, DEATH = 30, REFLECT = 34, SUMMON = 37, COVER = 41, AUTO = 42, UNSUMMON = 43, BERSERK = 46,
    LUCK = 72, CRIT = 77, BREAKUP = 92, EXTEND = 94, DMG = 98, HATE = 99, CLOCK = 116, HONE = 118, OVERCLOCK = 119,
    ACT = 129, MOGSCAN = 142, DEMON = 144, UNDEMON = 145, RANDOM = 154, NOLB = 95,
}

-- eUnitStatusCondition, by what the planner's debuffs are called.
local DEBUFF = { [1] = "poison", [2] = "blind", [4] = "silence", [6] = "confuse", [8] = "charm", [12] = "slow",
    [15] = "debrave", [16] = "deprotect", [17] = "defaith", [18] = "deshell" }
local ST_HASTE, ST_DEFEND = 33, 36
-- The names the planner's ailment checks use.
local STATUS = { [1] = "poison", [2] = "blind", [3] = "sleep", [4] = "silence", [5] = "paralysis", [6] = "confuse",
    [7] = "petrify", [8] = "charm", [9] = "stop", [10] = "berserk", [11] = "doom", [12] = "slow", [13] = "instant death",
    [14] = "gravity", [15] = "debrave", [16] = "deprotect", [17] = "defaith", [18] = "deshell" }
local FORMATION = { [80] = 1, [81] = 2, [82] = 3, [83] = 4, [79] = 5 }

-- The same folding the planner's lookups use.
function M.fold(name)
    return (tostring(name or ""):lower():gsub("’", "'"):gsub("‘", "'"):gsub("`", "'"))
end
local fold = M.fold

-- The tighter key kits.lua matches on.
local function kitKey(name)
    local n = fold(name):gsub("：", ":"):gsub("﹕", ":")
    return (n:gsub("[%s_%-]+", ""))
end

local function lasting(e)
    local t = e and e.turns
    if t and t > 0 then return t end
    return nil
end

local function has(row, kind)
    for _, e in ipairs(row.effects or {}) do
        if e.type == kind then return e end
    end
    return nil
end

local function statusOn(row, id)
    for _, e in ipairs(row.effects or {}) do
        if e.status == id then return true end
    end
    return false
end

local function kindOf(row)
    return (row.dmgType == PHYS and "phys") or (row.dmgType == MAGIC and "magic") or nil
end

local function wide(row)
    return row.target == T_GROUP or row.target == T_SPREAD or row.target == T_ALL
end

-- What the row does.
local function useOf(row)
    local hits = row.effect == 1
    local up = row.varType == UP
    if row.attr == A_FINISH then
        if hits and up then return "heal" end
        return hits and "finish" or "buff"
    end
    if has(row, E.ANALYZE) then return "scan" end
    if row.target == T_ALL and row.rel ~= FRIEND then return "skip" end
    if has(row, E.STEAL) or has(row, E.ESCAPE) or has(row, E.BERSERK) then return "skip" end
    if row.attr == A_THROW or row.attr == A_MONEY or row.attr == A_MIMIC then return "skip" end
    if has(row, E.REVIVE) and row.rel == FRIEND then return "revive" end
    if hits and up then return "heal" end
    if hits then return "break" end
    if has(row, E.DEATH) then return "skip" end
    if row.rel == ENEMY then
        if has(row, E.RANDOM) or (has(row, E.AUTO) and (row.power >= 20)) then return "break" end
        if has(row, E.HATE) or has(row, E.BREAKDEF) or has(row, E.MOGSCAN) then return "buff" end
        if #(row.effects or {}) > 0 then return "debuff" end
        return "break"
    end
    if has(row, E.CURE) then return "cure" end
    if statusOn(row, ST_DEFEND) or has(row, E.NOLB) then return "guard" end
    if has(row, E.HONE) then return "opener" end
    local def = has(row, E.DEF)
    if def and (statusOn(row, 25) or statusOn(row, 27)) and #row.effects == 1 then return "guardbuff" end
    return "buff"
end

local function guardsOf(row)
    local def = has(row, E.DEF)
    local p = def and def.params and def.params[1]
    if p == 1 then return "physical" end
    if p == 2 then return "magic" end
    return nil
end

local function factOf(row)
    local use = useOf(row)
    local info = { use = use, element = row.element, stagger = row.breakPower, source = "row" }
    local k = kindOf(row)
    if k == "phys" then info.phys = true end
    if k == "magic" then info.magic = true end
    if use == "guardbuff" then info.guards = guardsOf(row) end
    if (use == "heal") and wide(row) then info.party = true end
    if use == "debuff" then
        for _, e in ipairs(row.effects) do
            if DEBUFF[e.status] then info.effect = DEBUFF[e.status] break end
        end
    end
    return info
end

local function limitOf(row)
    -- The row's cost is in points. One gauge is 100 until the battle says otherwise.
    local points = tonumber(row.cost) or 0
    if points <= 0 then points = 100 end
    local info = { points = points, gauges = math.max(1, math.floor((points / 100) + 0.5)), element = row.element,
        stagger = row.breakPower, area = wide(row) or nil }
    local k = kindOf(row)
    if k == "phys" then info.phys = true end
    if k == "magic" then info.magic = true end
    -- A hit stays a hit. Another effect on the same row does not replace it.
    local ordinary = useOf(row)
    if ordinary == "break" then
        info.use = "lb-cash"
        if has(row, E.BREAKDEF) then info.breakDef = true end
        return info
    end
    if ordinary == "revive" or has(row, E.REVIVE) then
        info.use, info.party = "lb-revive", true
        return info
    end
    if has(row, E.DEF) then
        info.use, info.party = "lb-guard", true
        return info
    end
    -- A support row keeps the use an ordinary skill with that effect already has.
    if ordinary == "heal" or ordinary == "cure" or ordinary == "debuff"
        or ordinary == "guard" or ordinary == "guardbuff" or ordinary == "opener"
        or ordinary == "buff" then
        info.use = ordinary
        if wide(row) then info.party = true end
        return info
    end
    info.use = "skip"
    return info
end

-- An Esper's moves, from the game's AI row. The first listed move is its
-- signature, which gives its element and the power a spell's row would give.
-- The summon effect names the unit it puts on the field. With no damage move
-- past its basic attack it is a support Esper.
local function esperOf(row, units, skills)
    local fx = has(row, E.SUMMON)
    local uid = fx and fx.params and fx.params[2]
    local unit = uid and units[uid]
    local stay = fx and fx.turns
    local info = { role = "guard" }
    if uid then info.unit = uid end
    if stay and stay > 0 then info.turns = stay end
    for i, id in ipairs((unit and unit.moves) or {}) do
        local move = skills[id]
        if move then
            if i == 1 then
                info.element = move.element
                if wide(move) then info.area = true end
                if move.dmgType == PHYS then info.phys = true end
                if move.dmgType == MAGIC then info.magic = true end
                local power = move.power or 0
                if power > 0 then info.power = power end
                if move.accuracy then info.accuracy = move.accuracy end
            end
            if (move.effect == 1) and (move.varType ~= UP) and (move.attr ~= A_FIGHT) then info.role = "damage" end
        end
    end
    return info
end

-- A row's place in the kit book, or nil.
local function roleOf(row, books)
    local key = kitKey(row.name)
    if row.attr == A_MECHA and row.effect == 1 then
        books.mechabo[key] = true
    end
    if has(row, E.DEMON) then
        books.stance[key] = { off = true }
        return
    end
    if has(row, E.UNDEMON) then
        books.stanceOff[key] = true
        return
    end
    if has(row, E.HATE) and (row.effect ~= 1) and row.rel == ENEMY then
        books.draw[key] = { kind = "provoke", turns = lasting(has(row, E.HATE)) }
        return
    end
    if has(row, E.COVER) and row.rel == FRIEND then
        books.draw[key] = { kind = "cover", party = wide(row) or nil }
        return
    end
    if statusOn(row, ST_HASTE) and (#row.effects == 1) then
        books.haste[key] = { party = wide(row) }
        return
    end
    if row.effect == 1 then return end
    for _, e in ipairs(row.effects or {}) do
        if FORMATION[e.status] and (row.attr ~= A_LB) then
            -- A defense status waits for the first hit.
            local defense = has(row, E.DEF) and true or false
            books.book[key] = { kind = "formation", defense = defense or nil, turns = lasting(e), party = true,
                timed = (not defense) or nil, afterHit = defense or nil }
            return
        end
    end
    if has(row, E.ACT) then
        books.book[key] = { kind = "ready", turns = lasting(has(row, E.ACT)), with = "formation", timed = true }
    elseif has(row, E.EXTEND) then
        books.book[key] = { kind = "ready", turns = lasting(has(row, E.EXTEND)), with = "formation", timed = true }
    elseif has(row, E.OVERCLOCK) then
        books.book[key] = { kind = "ready", turns = lasting(has(row, E.OVERCLOCK)), with = "mechabo", group = "overclock" }
    elseif has(row, E.MOGSCAN) then
        books.book[key] = { kind = "weak", rank = 1, once = true }
    elseif has(row, E.LUCK) then
        books.book[key] = { kind = "luck", rank = 1 }
    elseif has(row, E.BREAKDEF) and row.rel == ENEMY then
        books.book[key] = { kind = "mark", turns = lasting(has(row, E.BREAKDEF)), timed = true }
    elseif (row.target == T_SELF) and has(row, E.BREAKUP) then
        local b = has(row, E.BREAKUP)
        if statusOn(row, 77) then
            books.book[key] = { kind = "mark", turns = lasting(b), weakMagic = true, timed = true }
        elseif has(row, E.DMG) then
            books.book[key] = { kind = "ready", turns = lasting(b), with = "area", offHeal = true }
        elseif has(row, E.CONT) then
            books.book[key] = { kind = "ready", turns = lasting(b) }
        end
    end
end

-- A bag row's facts. fold(name) -> use, from the item's skill row.
local function itemOf(item, row, books)
    local key = fold(item.name)
    if (not row) or (item.scene == 2) or item.held then
        books.leave[key] = { use = "out" }
        return
    end
    local price = item.price or 0
    local rare = item.rare == true
    local rank = math.floor(price / 1000) + 1
    if row.effect == 1 and row.varType ~= UP then
        books.attack[key] = { element = row.element, magic = (row.dmgType == MAGIC) or nil,
            phys = (row.dmgType ~= MAGIC) or nil, rank = rank }
        return
    end
    local use = nil
    if has(row, E.REVIVE) then use = "revive"
    elseif has(row, E.CURE) then
        use = "cure"
        local p = has(row, E.CURE).params or {}
        books.clears[key] = (p[1] == 1) and true or { [p[4] or -1] = true }
    elseif row.effect == 1 then
        use = (row.paramType == 2) and "mp" or "hp"
        local more = has(row, E.PARAM)
        if more and more.params and more.params[2] == 2 then use = "both" end
    end
    if not use then
        books.leave[key] = { use = "out" }
    elseif rare then
        books.leave[key] = { use = use, rank = rank }
    else
        books.items[key] = use
    end
end

-- Facts from an enemy's own row. Resistances, danger moves, and counters are
-- fields and skill ids. Trait sentences stay on the card for the log only.
local function cardOf(u, skills)
    local card = { gauge = u.maxBreak, weak = {}, half = {}, absorb = {}, no = {}, ail = {}, boss = u.boss or nil, traits = u.traits }
    local sawRes = false
    for el, res in pairs(u.elements or {}) do
        local name = ELEMENT[el]
        if name then
            sawRes = true
            if res == 1 then card.weak[name] = true end
            if res == 2 then card.half[name] = true end
            if res == 3 then card.no[name] = true end
            if res == 4 then card.absorb[name] = true end
        end
    end
    if sawRes then card.resists = true end
    for id, name in pairs(STATUS) do
        if ((u.status or {})[id] or 0) >= 100 then card.ail[name] = true end
    end
    -- The game's own list of this enemy's dangerous moves, and the damage they deal.
    local danger = {}
    local kinds = {}
    for _, id in ipairs(u.highRisk or {}) do
        local row = skills[id]
        if row then
            danger[#danger + 1] = row.name
            if row.dmgType == PHYS then kinds.physical = true end
            if row.dmgType == MAGIC then kinds.magic = true end
        end
    end
    if #danger > 0 then
        card.danger = danger
        card.dangerIds = u.highRisk
    end
    if kinds.magic and (not kinds.physical) then card.hits = "magic" end
    if kinds.physical and (not kinds.magic) then card.hits = "physical" end
    -- No move it has can damage the other side, so it can't hurt anyone. A move
    -- aimed at its own side doesn't count, however large its number.
    local moves, hurts = 0, false
    for _, id in ipairs(u.moves or {}) do
        local row = skills[id]
        if row then
            moves = moves + 1
            if (row.rel == ENEMY) and (((row.power or 0) > 0) or (row.effect == 1)) then hurts = true end
        end
    end
    if (moves > 0) and (not hurts) then card.harmless = true end
    local counterPhys, counterMagic = false, false
    for _, id in ipairs(u.counters or {}) do
        local row = skills[id]
        if row then
            if row.dmgType == PHYS then counterPhys = true end
            if row.dmgType == MAGIC then counterMagic = true end
        end
    end
    if counterPhys and counterMagic then card.counter = "hit"
    elseif counterPhys then card.counter = "physical"
    elseif counterMagic then card.counter = "magic" end
    return card
end

-- raw: skills, units, items, each by id, from the game's tables.
function M.build(raw)
    local out = { known = {}, knownById = {}, limits = {}, espers = {}, mobs = {}, units = {},
        kits = { book = {}, draw = {}, stance = {}, stanceOff = {}, haste = {}, mechabo = {} },
        items = { items = {}, leave = {}, attack = {}, clears = {} } }
    local ids = {}
    for id in pairs(raw.skills or {}) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local row = raw.skills[id]
        if row.name and row.name ~= "" then
            local key = fold(row.name)
            local fact = factOf(row)
            if out.known[key] == nil or row.fromUnit then out.known[key] = fact end
            out.knownById[id] = { name = key, fact = fact }
            if row.attr == A_LB then out.limits[key] = limitOf(row) end
            if row.attr == A_SUMMON and has(row, E.SUMMON) then out.espers[key] = esperOf(row, raw.units or {}, raw.skills) end
            if row.effects then roleOf(row, out.kits) end
        end
    end
    for id, u in pairs(raw.units or {}) do
        local card = cardOf(u, raw.skills or {})
        out.units[id] = card
        if u.name and u.name ~= "" then
            local key = fold(u.name)
            if not out.mobs[key] then out.mobs[key] = card end
        end
    end
    for _, item in pairs(raw.items or {}) do
        if item.name and item.name ~= "" then
            itemOf(item, raw.skills and raw.skills[item.skillId], out.items)
        end
    end
    return out
end

return M

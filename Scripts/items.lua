-- Items. The item book and the rules for which item to spend. The planner
-- reads the bag and sends the command. This file does not name a fight, a
-- character, or a Vision, and it does not touch the battle libraries.
--
-- Common shop items only, outside a boss fight. In a boss fight a rare item
-- is spent when no common item does the job, the cheapest rank first: a
-- raise at once, a heal or MP item only under dire need. Scrolls and knives
-- are thrown in a boss fight on a weakness the bar cannot pay, or when
-- nothing payable lands. Tents and Healing Spring stay put. A Pot fight
-- spends nothing.

local BOOK = {
    -- Shop recovery the player can buy again.
    items = {
        ["potion"] = "hp",
        ["hi-potion"] = "hp",
        ["mist potion"] = "hp",
        ["ether"] = "mp",
        ["mist ether"] = "mp",
        ["phoenix down"] = "revive",
        ["antidote"] = "cure",
        ["antidote herb"] = "cure",
        ["eye drops"] = "cure",
        ["echo herb"] = "cure",
        ["smelling salts"] = "cure",
        ["unicorn horn"] = "cure",
        ["gold needle"] = "cure",
        ["herb of awakening"] = "cure",
        ["remedy"] = "cure",
    },
    -- Rare recovery. Spent only in a boss fight, cheapest rank first, when no
    -- common item covers the need. "out" never leaves the bag in battle.
    leave = {
        -- Healing Spring is a slow regen, too slow for a critical ally.
        ["mist hi-potion"] = { use = "hp", rank = 1 },
        ["x-potion"] = { use = "hp", rank = 2 },
        ["mist x-potion"] = { use = "hp", rank = 3 },
        ["turbo ether"] = { use = "mp", rank = 2 },
        ["mist turbo ether"] = { use = "mp", rank = 3 },
        ["x-ether"] = { use = "mp", rank = 4 },
        ["mist x-ether"] = { use = "mp", rank = 5 },
        ["phoenix pinion"] = { use = "revive", rank = 3 },
        ["elixir"] = { use = "both", rank = 6 },
        ["megalixir"] = { use = "both", rank = 9 },
        ["tent"] = { use = "out" },
        ["healing spring"] = { use = "out" },
    },
    -- Thrown attack items, from the public item list read 2026-11-02. Scrolls
    -- are single-target magic of their element. Knives and blades are physical;
    -- a knife also adds its status. Thrown only in a boss fight, lowest rank first.
    attack = {
        ["flame scroll i"] = { element = "fire", magic = true, rank = 1 },
        ["ice scroll i"] = { element = "ice", magic = true, rank = 1 },
        ["wind scroll i"] = { element = "wind", magic = true, rank = 1 },
        ["earth scroll i"] = { element = "earth", magic = true, rank = 1 },
        -- Lightning is thunder, to match the book (mobs.lua and known.lua).
        ["lightning scroll i"] = { element = "thunder", magic = true, rank = 1 },
        ["water scroll i"] = { element = "water", magic = true, rank = 1 },
        ["flame scroll ii"] = { element = "fire", magic = true, rank = 2 },
        ["ice scroll ii"] = { element = "ice", magic = true, rank = 2 },
        ["wind scroll ii"] = { element = "wind", magic = true, rank = 2 },
        ["earth scroll ii"] = { element = "earth", magic = true, rank = 2 },
        ["lightning scroll ii"] = { element = "thunder", magic = true, rank = 2 },
        ["water scroll ii"] = { element = "water", magic = true, rank = 2 },
        ["shuriken"] = { phys = true, rank = 1 },
        ["knife of blind"] = { phys = true, status = "blind", rank = 1 },
        ["knife of silence"] = { phys = true, status = "silence", rank = 1 },
        ["knife of poison"] = { phys = true, status = "poison", rank = 2 },
        ["knife of confuse"] = { phys = true, status = "confuse", rank = 2 },
        ["knife of paralysis"] = { phys = true, status = "paralysis", rank = 2 },
        ["knife of sleep"] = { phys = true, status = "sleep", rank = 2 },
        ["fuma shuriken"] = { phys = true, rank = 3 },
        ["chef's knife"] = { phys = true, rank = 4 },
    },}

-- Status ids, the same as health.lua.
local POISON, BLIND, SILENCE, SLEEP = 1, 2, 4, 3
local PARALYSIS, CONFUSE, PETRIFY = 5, 6, 7
local DOOM = 11
local LOCK = {
    [3] = true, [4] = true, [5] = true, [6] = true, [7] = true,
    [8] = true, [9] = true, [10] = true, [11] = true,
}
local SOFT = { [POISON] = true, [BLIND] = true }

-- Shop cures and the status they clear. Remedy clears a lock only.
-- It does not clear poison, blind, or slow. A name that is not here still
-- clears a lock. It does not clear poison or blind.
local CURE_ITEM = {
    antidote = { [POISON] = true },
    ["antidote herb"] = { [POISON] = true },
    ["eye drops"] = { [BLIND] = true },
    ["echo herb"] = { [SILENCE] = true },
    ["smelling salts"] = { [CONFUSE] = true },
    ["unicorn horn"] = { [PARALYSIS] = true },
    ["gold needle"] = { [PETRIFY] = true },
    ["herb of awakening"] = { [SLEEP] = true },
    remedy = true,
}

-- A scroll or knife the book does not list still reads by its name.
local SCROLL_WORDS = {
    flame = "fire", fire = "fire", ice = "ice", blizzard = "ice", wind = "wind",
    earth = "earth", lightning = "thunder", thunder = "thunder", water = "water",
}

local function fold(name)
    local n = (name or ""):lower()
    n = n:gsub("’", "'"):gsub("‘", "'"):gsub("`", "'")
    return n
end

local function anyOf(set, ids)
    if not set then return false end
    for id in pairs(ids) do
        if set[id] then return true end
    end
    return false
end

local M = {}
M.book = BOOK

-- "hp", "mp", "revive", "cure", or nil for a shop item name.
function M.listed(name)
    return BOOK.items[fold(name)]
end

-- One bag row, or nil when the item is not spent in battle.
-- f is what the game's own rows say: rare (the row's flag), amount (a fixed
-- restore), revive, cure, rowHp and rowMp (the item's skill row restores
-- it), saysHp and saysMp (the library answers yes), party (the item's skill
-- row targets every ally).
function M.entry(id, name, count, f)
    f = f or {}
    local lowered = fold(name)
    local listed = BOOK.items[lowered]
    local rareRow = BOOK.leave[lowered]
    if (not rareRow) and lowered:find("elixir", 1, true) then rareRow = { use = "both", rank = 7 } end
    local rare = f.rare or (rareRow ~= nil)
    local throw = BOOK.attack[lowered]
    if (not throw) and lowered:find("scroll", 1, true) then
        for word, el in pairs(SCROLL_WORDS) do
            if lowered:find(word, 1, true) then throw = { element = el, magic = true, rank = 3 } end
        end
    end
    if (not throw) and (lowered:find("knife", 1, true) or lowered:find("shuriken", 1, true)) then
        throw = { phys = true, rank = 4 }
    end
    if throw then
        return { id = id, name = name, count = count, attack = throw, rank = throw.rank or 5 }
    end
    if rareRow and rareRow.use == "out" then return nil end
    local hp, mp, kind = false, false, nil
    if listed == "hp" then hp, kind = true, "heal" end
    if listed == "mp" then mp = true end
    if listed == "revive" then kind = "revive" end
    if listed == "cure" then kind = "cure" end
    local use = rareRow and rareRow.use
    if use == "hp" or use == "both" then hp, kind = true, "heal" end
    if use == "mp" or use == "both" then mp = true end
    if use == "revive" then kind = "revive" end
    if f.revive then kind = "revive" end
    if f.cure then kind = "cure" end
    if f.rowHp then hp, kind = true, "heal" end
    if f.rowMp then mp = true end
    if f.saysHp then hp = true end
    if f.saysMp then mp = true end
    if not (hp or mp or kind == "revive" or kind == "cure") then return nil end
    return {
        id = id, name = name, hp = hp, mp = mp, kind = kind,
        count = count, amount = f.amount, party = f.party and true or nil,
        rare = rare and true or nil, rank = (rareRow and rareRow.rank) or 8,
    }
end

-- The bag line for the log.
function M.bagLine(out, answered)
    if #out == 0 then
        return string.format("bag: no potion, ether, or phoenix down (%d item ids answered)", answered or 0)
    end
    local bits = {}
    for _, it in ipairs(out) do
        local tag = it.kind or (it.mp and "mp") or (it.hp and "hp")
            or (it.attack and (it.attack.element or "physical")) or "item"
        if it.party then tag = tag .. " party" end
        if it.rare then tag = tag .. " rare" end
        bits[#bits + 1] = string.format("%s x%s %s", it.name, tostring(it.count), tag)
    end
    return "bag: " .. table.concat(bits, ", ")
end

-- A Pot fight spends nothing.
function M.potFight(enemies)
    for _, u in ipairs(enemies or {}) do
        local n = (u.name or ""):lower()
        if n == "pot" or n:find(" pot", 1, true) then return true end
    end
    return false
end

-- Common, rare, and thrown rows. Rare and thrown rows are the boss fight's.
local function pools(owned, boss)
    local items, rares, throws = {}, {}, {}
    for _, it in ipairs(owned or {}) do
        if it.attack then
            if boss then throws[#throws + 1] = it end
        elseif it.rare then
            if boss then rares[#rares + 1] = it end
        else
            items[#items + 1] = it
        end
    end
    table.sort(rares, function(a, b) return (a.rank or 8) < (b.rank or 8) end)
    table.sort(throws, function(a, b) return (a.rank or 5) < (b.rank or 5) end)
    return items, rares, throws
end

local function firstOf(list, pred)
    for _, it in ipairs(list) do
        if pred(it) then return it end
    end
    return nil
end

-- Smallest potion that covers the gap. If none covers, the largest amount.
-- No readable amount keeps the first matching item.
function M.choosePotion(items, missing)
    local first, cover, coverAmt, best, bestAmt = nil, nil, nil, nil, -1
    for _, it in ipairs(items or {}) do
        if it.hp or it.kind == "heal" then
            if not first then first = it end
            local amount = it.amount
            if amount and (amount > 0) and missing and (missing > 0) then
                if (amount >= missing) and ((not cover) or (amount < coverAmt)) then
                    cover, coverAmt = it, amount
                end
                if amount > bestAmt then best, bestAmt = it, amount end
            end
        end
    end
    if cover then return cover end
    if best then return best end
    return first
end

-- True when this item can clear a status that is on the ally right now.
-- Poison and blind qualify only on the self-care line. Slow is not an
-- item unless a cure has already been seen to clear it. Remedy never
-- qualifies for poison, blind, or slow.
function M.itemClears(name, statuses, soft)
    local row = CURE_ITEM[fold(name)]
    if row == nil then
        if soft or (not statuses) then return false end
        return anyOf(statuses, LOCK)
    end
    if row == false then return false end
    if not statuses then return false end
    if row == true then return anyOf(statuses, LOCK) end
    for id in pairs(row) do
        if statuses[id] then
            if LOCK[id] then return true end
            if soft and SOFT[id] then return true end
        end
    end
    return false
end

-- The last Remedy stays for doom, or for a lock on the main healer.
-- healerOf(allies) is the party's main healer.
function M.holdRemedy(name, count, target, allies, healerOf)
    if fold(name) ~= "remedy" then return false end
    if (not count) or (count > 1) then return false end
    if target and target.statuses and target.statuses[DOOM] then return false end
    local healer = healerOf and healerOf(allies) or nil
    if healer and target and (healer.id == target.id) and anyOf(target.statuses, LOCK) then
        return false
    end
    for _, a in ipairs(allies or {}) do
        if (not a.dead) and a.statuses and a.statuses[DOOM] then return true end
    end
    if healer and (not healer.dead) and anyOf(healer.statuses, LOCK) then return true end
    return false
end

-- The item to spend, or nil. The second return is true when it is a rare
-- row spent in a boss fight.
-- want "revive": ctx.boss.
-- want "heal": ctx.boss, ctx.missing (HP the ally is short), ctx.dire,
-- ctx.spread (most of the living party is under half: a party item is a
-- group heal and beats every single heal), ctx.partyOnly (a party item or
-- nothing). Without the spread, a single item goes first.
-- want "mp": ctx.boss, ctx.dire.
function M.recovery(owned, want, ctx)
    ctx = ctx or {}
    local items, rares = pools(owned, ctx.boss)
    local it, fromRare = nil, false
    if want == "revive" then
        local function raise(row) return row.kind == "revive" end
        it = firstOf(items, raise)
        if not it then it, fromRare = firstOf(rares, raise), true end
    elseif want == "heal" then
        local function heals(row) return row.hp or row.kind == "heal" end
        local function group(row) return heals(row) and row.party end
        if ctx.spread then
            it = firstOf(items, group)
            if (not it) and ctx.dire then
                local big = firstOf(rares, group)
                if big then it, fromRare = big, true end
            end
        end
        if (not it) and (not ctx.partyOnly) then
            local singles = {}
            for _, row in ipairs(items) do
                if not row.party then singles[#singles + 1] = row end
            end
            it = M.choosePotion(singles, ctx.missing) or M.choosePotion(items, ctx.missing) or firstOf(items, heals)
            local short = (not it) or (ctx.missing and it.amount and (it.amount < ctx.missing))
            if short and ctx.dire then
                -- A rare row replaces the common pick only when it restores more.
                local function bigger(row)
                    return heals(row) and ((not it) or (not it.amount) or (not row.amount) or (row.amount > it.amount))
                end
                local big = firstOf(rares, function(row) return bigger(row) and not row.party end)
                    or firstOf(rares, bigger)
                if big then it, fromRare = big, true end
            end
        end
    elseif want == "mp" then
        it = firstOf(items, function(row) return row.mp and row.kind ~= "revive" end)
        if (not it) and ctx.dire then
            it = firstOf(rares, function(row) return row.mp and row.kind ~= "revive" and not row.hp end)
                or firstOf(rares, function(row) return row.mp and row.kind ~= "revive" end)
            fromRare = true
        end
    end
    if not it then return nil end
    return it, (fromRare and it.rare) and true or false
end

-- A cure item for who, or nil. The second return is true when the bag held
-- a cure item that this status or the last-Remedy rule kept back.
-- ctx: soft (the self-care line), allies, healerOf.
function M.cure(owned, who, ctx)
    ctx = ctx or {}
    local items = pools(owned, false)
    local saw = false
    local it = firstOf(items, function(row)
        if row.kind ~= "cure" then return false end
        saw = true
        if M.holdRemedy(row.name, row.count, who, ctx.allies, ctx.healerOf) then return false end
        return M.itemClears(row.name, who and who.statuses, ctx.soft)
    end)
    return it, saw
end

-- A thrown item in a boss fight, the enemy, and the factor it lands at.
-- list is the pool. factorOf(fake, enemy) is the planner's element factor.
-- A weakness is the call; with landing, any item that lands will do.
function M.throw(owned, ctx)
    ctx = ctx or {}
    local _, _, throws = pools(owned, ctx.boss)
    local best, bestF, bestU = nil, 0, nil
    for _, it in ipairs(throws) do
        local fake = { name = it.name, known = it.attack, attr = ctx.itemAttr }
        for _, u in ipairs(ctx.list or {}) do
            local f = ctx.factorOf(fake, u)
            local want = ctx.landing and (f > 0) or (f >= 3)
            if want and (f > bestF) then best, bestF, bestU = it, f, u end
        end
    end
    if not best then return nil end
    return best, bestU, bestF
end

return M

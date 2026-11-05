-- Items. The item book and the rules for which item to spend. The planner
-- reads the bag and sends the command. This file does not name a fight, a
-- character, or a Vision, and it does not touch the battle libraries.
--
-- Common items first. A buy price above the cap in config.ini is not spent.
-- A rare item is the row's own flag, or a buy price on the high side of the
-- widest step in that table. It is spent when no common item does the job
-- and the need is real: someone down, someone a hit already
-- seen would kill, or MP short of a skill the field needs. Scrolls and knives
-- are thrown when the bar has no weakness that will land. A neutral spell
-- does not hold a weakness item back. Tents and Healing Spring stay put. A
-- fight where no foe can hurt the party spends nothing.

local BOOK = { items = {}, leave = {}, attack = {} }
-- Status ids, the same as health.lua.
local POISON, BLIND, DOOM = 1, 2, 11
local LOCK = {
    [3] = true, [4] = true, [5] = true, [6] = true, [7] = true,
    [8] = true, [9] = true, [10] = true, [11] = true,
}
local SOFT = { [POISON] = true, [BLIND] = true }

-- What each cure item clears, from its skill row. true is every lock.
local CURE_ITEM = {}


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

-- Buy prices from one item table. The high side of the one step that is
-- wider than every other step is rare. Equal steps are a shop ladder. A
-- price of 0 is not a buy price. The gil amounts are the table's own.
function M.rarePrices(prices)
    local seen, list = {}, {}
    for _, p in ipairs(prices or {}) do
        local n = tonumber(p)
        if n and (n > 0) and (not seen[n]) then
            seen[n] = true
            list[#list + 1] = n
        end
    end
    table.sort(list)
    if #list < 2 then return {} end
    local bestHi, bestLo, at, ties = 0, 1, nil, 0
    for i = 2, #list do
        local hi, lo = list[i], list[i - 1]
        local cmp = (hi * bestLo) - (bestHi * lo)
        if cmp > 0 then
            bestHi, bestLo, at, ties = hi, lo, i, 1
        elseif cmp == 0 then
            ties = ties + 1
        end
    end
    if (not at) or (ties ~= 1) then return {} end
    local rare = {}
    for i = at, #list do rare[list[i]] = true end
    return rare
end

-- The player's cap from config.ini. A buy price above it stays in the bag.
-- A price equal to the cap is still spent. A missing price is not above it.
function M.abovePrice(price, cap)
    price, cap = tonumber(price), tonumber(cap)
    if (not price) or (not cap) then return false end
    return price > cap
end

-- Filled from the game's rows (rows.lua).
function M.load(t)
    BOOK, CURE_ITEM = t, t.clears
    M.book = t
end

-- "hp", "mp", "revive", "cure", or nil for a shop item name.
function M.listed(name)
    return BOOK.items[fold(name)]
end

-- One bag row, or nil when the item is not spent in battle.
-- f is what the game's own rows say: rare (the row's flag), held (the buy
-- price is above the cap), amount (a fixed restore), revive, cure, rowHp
-- and rowMp (the item's skill row restores it), saysHp and saysMp (the
-- library answers yes), party (the item's skill row targets every ally).
function M.entry(id, name, count, f)
    f = f or {}
    if f.held then return nil end
    local lowered = fold(name)
    local listed = BOOK.items[lowered]
    local rareRow = BOOK.leave[lowered]
    local rare = f.rare or (rareRow ~= nil)
    local throw = BOOK.attack[lowered]
    if throw then
        return { id = id, name = name, count = count, attack = throw, rank = throw.rank or 5 }
    end
    if rareRow and rareRow.use == "out" then return nil end
    local hp, mp, kind = false, false, nil
    if listed == "hp" or listed == "both" then hp, kind = true, "heal" end
    if listed == "mp" or listed == "both" then mp = true end
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

-- Common, rare, and thrown rows. Rare is the item row's flag, in any fight.
local function pools(owned)
    local items, rares, throws = {}, {}, {}
    for _, it in ipairs(owned or {}) do
        if it.attack then
            throws[#throws + 1] = it
        elseif it.rare then
            rares[#rares + 1] = it
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

-- The MP item for a gap, using the amounts the game's rows give. A one-target
-- item comes before a party item, since a party item spends more on one need.
-- The smallest that covers the gap, or if none does, the largest. A row with no
-- fixed amount, such as a percentage restore, comes last.
function M.chooseMp(items, missing)
    local need = (missing and (missing > 0)) and missing or 0
    local function usable(it) return it.mp and (it.kind ~= "revive") end
    local function sized(party)
        local cover, coverAmt, best, bestAmt = nil, nil, nil, -1
        for _, it in ipairs(items or {}) do
            local amount = it.amount
            if usable(it) and ((it.party and true or false) == party) and amount and (amount > 0) then
                if (amount >= need) and ((not cover) or (amount < coverAmt)) then
                    cover, coverAmt = it, amount
                end
                if amount > bestAmt then best, bestAmt = it, amount end
            end
        end
        return cover or best
    end
    return sized(false) or sized(true)
        or firstOf(items or {}, function(it) return usable(it) and not it.party end)
        or firstOf(items or {}, usable)
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

-- The last of an item that cures doom stays for doom, or for a lock on the main
-- healer. healerOf(allies) is the party's main healer.
function M.holdDoomCure(name, count, target, allies, healerOf)
    local clears = CURE_ITEM and CURE_ITEM[fold(name)]
    if not ((clears == true) or (type(clears) == "table" and clears[DOOM])) then return false end
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

-- The item to spend, or nil. The second return is true when it is a rare row.
-- want "revive".
-- want "heal": ctx.missing (HP the ally is short), ctx.dire,
-- ctx.spread (most of the living party is under half: a party item is a
-- group heal and beats every single heal), ctx.partyOnly (a party item or
-- nothing). Without the spread, a single item goes first.
-- want "mp": ctx.missing (MP the actor is short), ctx.dire.
function M.recovery(owned, want, ctx)
    ctx = ctx or {}
    local items, rares = pools(owned)
    local it, fromRare = nil, false
    if want == "revive" then
        local function raise(row) return row.kind == "revive" end
        it = firstOf(items, raise)
        if not it then it, fromRare = firstOf(rares, raise), true end
    elseif want == "heal" then
        local function heals(row) return row.hp or row.kind == "heal" end
        local function group(row) return heals(row) and row.party end
        if ctx.spread or ctx.partyOnly then
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
        it = M.chooseMp(items, ctx.missing)
        local short = (not it) or (ctx.missing and it.amount and (it.amount < ctx.missing))
        if short and ctx.dire then
            -- A rare row replaces the common pick only when it restores more.
            local function bigger(row)
                return row.mp and (row.kind ~= "revive")
                    and ((not it) or (not it.amount) or (not row.amount) or (row.amount > it.amount))
            end
            local big = firstOf(rares, function(row) return bigger(row) and (not row.hp) and (not row.party) end)
                or firstOf(rares, function(row) return bigger(row) and (not row.party) end)
                or firstOf(rares, bigger)
            if big then it, fromRare = big, true end
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
    local items = pools(owned)
    local saw = false
    local it = firstOf(items, function(row)
        if row.kind ~= "cure" then return false end
        saw = true
        if M.holdDoomCure(row.name, row.count, who, ctx.allies, ctx.healerOf) then return false end
        return M.itemClears(row.name, who and who.statuses, ctx.soft)
    end)
    return it, saw
end

-- A thrown item, the enemy, and the factor it lands at.
-- list is the pool. factorOf(fake, enemy) is the planner's element factor.
-- A weakness is the call; with landing, any item that lands will do.
function M.throw(owned, ctx)
    ctx = ctx or {}
    local _, _, throws = pools(owned)
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

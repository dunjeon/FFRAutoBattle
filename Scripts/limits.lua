-- Limit Bursts, as skill rows. The planner calls this. This file does not
-- name a fight, a character, or a Vision, and it does not touch the battle
-- libraries.
--
-- A Limit is a skill whose cost is gauges. The row keeps the element, the
-- power, the stagger, the target, and each effect. A second effect stays
-- attached. It does not replace a hit. Gauge cost is the row's point cost
-- divided by the live size of one gauge. 100 is only the fallback when the
-- battle library does not say.
--   lb-cash    a damage row. It enters the same comparison as any other hit.
--   lb-guard   a party barrier. The caller uses the barrier rule.
--   lb-revive  a raise. The caller uses the raise rule.
-- A support row keeps the use an ordinary skill with that effect already has.
-- An ordinary skill that shares a name is not a Limit Burst. The caller
-- applies a row only when the live attribute is a Limit Burst.
-- Lightning is stored as thunder, the same word the enemy book uses.

local BOOK = {}

local function fold(name)
    local n = (name or ""):lower()
    n = n:gsub("’", "'"):gsub("‘", "'"):gsub("`", "'")
    return n
end

local function hasName(key, limit)
    if key == limit then return true end
    local stripped = key:gsub("^limit burst[:%s]+", ""):gsub("^limit[:%s]+", "")
    return stripped == limit
end

local function copyOf(row)
    local copy = {}
    for k, v in pairs(row) do copy[k] = v end
    return copy
end

local M = {}

-- Filled from the game's rows (rows.lua).
function M.load(t) BOOK = t end

-- Book role wins. The book's stagger wins when it has one. A known
-- stagger stays when the book has none. The caller uses this only for
-- a live Limit Burst.
function M.apply(known, fact)
    if not fact then return known end
    local merged = {}
    if known then
        for k, v in pairs(known) do merged[k] = v end
    end
    merged.use = fact.use
    merged.gauges = fact.gauges
    merged.points = fact.points
    merged.element = fact.element
    merged.party = fact.party and true or nil
    if fact.breakDef then merged.breakDef = true end
    if fact.phys then merged.phys = true end
    if fact.magic then merged.magic = true end
    if fact.area then merged.area = true end
    if fact.stagger then merged.stagger = fact.stagger end
    merged.role = fact.role
    return merged
end

-- The live Limit Burst name, or nil when the row is not one of these.
function M.lookup(name)
    local key = fold(name)
    if key == "" then return nil end
    if BOOK[key] then return copyOf(BOOK[key]) end
    for limit, row in pairs(BOOK) do
        if hasName(key, limit) then return copyOf(row) end
    end
    return nil
end

-- Filled gauges from the live bar. points is the unit's Limit Burst points.
-- one is how many points one gauge holds. maxPoints is the bar's size, used
-- only when one is missing. counted is the battle library's gauge count,
-- used only when the points are missing. A count does not replace points.
-- An empty count at the start of a fight is not proof the count is the bar.
-- 100 is the one-gauge size every live read has returned. It is used only
-- when the game does not say.
function M.filled(points, one, maxPoints, counted, slots)
    local gauge = tonumber(one)
    if (gauge == nil) or (gauge <= 0) then
        local maxv = tonumber(maxPoints)
        local n = tonumber(slots)
        if (n == nil) or (n < 1) then
            if maxv and (maxv > 0) then
                n = math.floor((maxv / 100) + 0.5)
                if n < 1 then n = 1 end
            end
        end
        if maxv and n and (n > 0) then gauge = maxv / n end
    end
    local pts = tonumber(points)
    if pts and gauge and (gauge > 0) then
        if pts < 0 then pts = 0 end
        return math.floor((pts / gauge) + 1e-6)
    end
    local c = tonumber(counted)
    if c and (c >= 0) then return c end
    return nil
end

-- How many gauges a row spends. points is the row's cost. one is the live
-- size of one gauge. 100 is used only when the battle library does not say.
function M.gauges(points, one)
    local pts = tonumber(points)
    if (not pts) or (pts <= 0) then return nil end
    local gauge = tonumber(one)
    if (not gauge) or (gauge <= 0) then gauge = 100 end
    local n = math.floor((pts / gauge) + 0.5)
    if n < 1 then n = 1 end
    return n
end

-- How many gauges this bar can hold. slots is the library's own count.
-- Otherwise the bar's max points divided by one gauge.
function M.capacity(one, maxPoints, slots)
    local n = tonumber(slots)
    if n and (n >= 1) then return math.floor(n) end
    local gauge = tonumber(one)
    if (not gauge) or (gauge <= 0) then gauge = 100 end
    local maxv = tonumber(maxPoints)
    if (not maxv) or (maxv <= 0) then return nil end
    local c = math.floor((maxv / gauge) + 0.5)
    if c < 1 then c = 1 end
    return c
end

-- A cheaper damage Limit waits while a higher-cost one on this same bar
-- is still out of reach. filled is what the bar holds now. maxGauges is
-- what it can hold. higher is the list of higher costs that can still land.
-- A full bar does not wait. A bar that cannot hold the higher cost does not wait.
function M.holds(cost, filled, maxGauges, higher)
    cost = tonumber(cost) or 1
    filled = tonumber(filled)
    maxGauges = tonumber(maxGauges)
    if (not filled) or (not maxGauges) then return false end
    if filled >= maxGauges then return false end
    if type(higher) ~= "table" then return false end
    for i = 1, #higher do
        local g = tonumber(higher[i])
        if g and (g > cost) and (g <= maxGauges) and (g > filled) then return true end
    end
    return false
end

-- Whether candidate replaces the current pick. During a break, a Limit is
-- the spend unless another action kills more. Two Limits: more kills, then
-- the higher gauge cost, then damage, then stagger. A spell against a spell
-- stays on kills, then damage, then stagger. No score weight.
function M.ahead(candidate, current, cashing)
    if not current then return true end
    local function kills(x) return tonumber(x.kills) or 0 end
    local function dmg(x) return tonumber(x.damage) or 0 end
    local function stag(x) return tonumber(x.stagger) or 0 end
    local function gauges(x) return tonumber(x.gauges) or 0 end
    local function lim(x) return x.limit and true or false end
    if cashing and (lim(candidate) ~= lim(current)) then
        if kills(candidate) ~= kills(current) then return kills(candidate) > kills(current) end
        return lim(candidate)
    end
    if lim(candidate) and lim(current) then
        if kills(candidate) ~= kills(current) then return kills(candidate) > kills(current) end
        if gauges(candidate) ~= gauges(current) then return gauges(candidate) > gauges(current) end
        if dmg(candidate) ~= dmg(current) then return dmg(candidate) > dmg(current) end
        return stag(candidate) > stag(current)
    end
    if kills(candidate) ~= kills(current) then return kills(candidate) > kills(current) end
    if dmg(candidate) ~= dmg(current) then return dmg(candidate) > dmg(current) end
    return stag(candidate) > stag(current)
end

-- Each Limit's use case, asked early in the turn. The caller passes plain
-- tables and maps the answer back to a skill and its targets.
-- ctx.limits: the ready Limits, each { role, gauges, area, lands = {[i]=bool},
--   pour = {[i]=stagger}, blocked = an area row that a foe nulls }.
-- ctx.foes: { broken, remain, hp, boss }, in the same order as lands and pour.
-- ctx.filled, ctx.max: the bar now, and what it holds. ctx.higher: the
--   largest gauge cost of a damage Limit this unit has equipped.
-- ctx.boss, ctx.bonus, ctx.breakClose, ctx.up (allies standing), ctx.down.
-- ctx.stage: "urgent" asks only the raise. "main" asks the rest.
-- Returns { at = index in ctx.limits, foe = index in ctx.foes or nil,
--   all = true for a party or area cast, why = text } or nil.
local DAMAGE = { mark = true, stagger = true, few = true, luck = true, nuke = true }
M.DAMAGE = DAMAGE

function M.plan(ctx)
    local limits, foes = ctx.limits or {}, ctx.foes or {}
    local filled = tonumber(ctx.filled) or 0
    local maxG = tonumber(ctx.max) or filled
    local full = (filled > 0) and (filled >= maxG)
    local function pick(i, foe, all, why) return { at = i, foe = foe, all = all and true or false, why = why } end

    if ctx.stage == "urgent" then
        local down, up = tonumber(ctx.down) or 0, tonumber(ctx.up) or 0
        for i, l in ipairs(limits) do
            if (l.role == "revive") and ((down >= 2) or ((down >= 1) and (up <= 2))) then
                return pick(i, nil, true, "lb raise, " .. down .. " down")
            end
        end
        return nil
    end

    -- The boss is the largest open body. Its HP says whether the fight is long.
    local bossHp = nil
    for _, f in ipairs(foes) do
        if f.boss then bossHp = f.hp end
    end
    -- On a long boss fight a one-gauge damage Limit waits for the larger one.
    -- A full bar, or a boss under 30%, spends what it has.
    local function held(l)
        if not DAMAGE[l.role] then return false end
        if full then return false end
        local higher = tonumber(ctx.higher) or 0
        if (higher <= (l.gauges or 1)) or (higher > maxG) then return false end
        if not ctx.boss then return false end
        if bossHp and (bossHp <= 0.30) then return false end
        return true
    end
    local function better(l, best)
        if not best then return true end
        return (l.gauges or 1) > (best.gauges or 1)
    end
    -- The foe to hit: the boss when the Limit lands on it, else the most HP.
    local function target(l, ok)
        local best, bestHp, bestBoss = nil, -1, false
        for i, f in ipairs(foes) do
            if l.lands[i] and ok(f, i) then
                local boss = f.boss and true or false
                if (best == nil) or (boss and not bestBoss) or ((boss == bestBoss) and ((f.hp or 0) > bestHp)) then
                    best, bestHp, bestBoss = i, f.hp or 0, boss
                end
            end
        end
        return best
    end

    local window = ctx.bonus and true or false
    local brokenN = 0
    for _, f in ipairs(foes) do
        if f.broken then window = true brokenN = brokenN + 1 end
    end
    local up = tonumber(ctx.up) or 0

    if window then
        -- The party acts twice while the foe cannot act.
        for i, l in ipairs(limits) do
            if (l.role == "double") and (up >= 2) then return pick(i, nil, true, "lb double, stagger open") end
        end
        -- A damage Limit on the staggered body. The mark waits for an open gauge.
        local best, bestI, bestFoe = nil, nil, nil
        for i, l in ipairs(limits) do
            if DAMAGE[l.role] and (l.role ~= "mark") and (not held(l)) then
                if l.area then
                    local reach = false
                    for j, f in ipairs(foes) do
                        if f.broken and l.lands[j] then reach = true end
                    end
                    if reach and (not l.blocked) and better(l, best) then best, bestI, bestFoe = l, i, nil end
                else
                    local foe = target(l, function(f) return f.broken end)
                    if foe and better(l, best) then best, bestI, bestFoe = l, i, foe end
                end
            end
        end
        if best then return pick(bestI, bestFoe, best.area, "lb " .. best.role .. " on the stagger") end
        return nil
    end

    -- No stagger open. The bars fill while the party acts.
    for i, l in ipairs(limits) do
        if (l.role == "fill") and (up >= 2) then return pick(i, nil, true, "lb fill the party's bars") end
    end
    -- The mark goes on before the break, on a gauge its own hit does not empty.
    if not ctx.breakClose then
        for i, l in ipairs(limits) do
            if (l.role == "mark") and (not held(l)) then
                local foe = target(l, function(f, j) return (not f.broken) and ((f.remain or 0) > (l.pour[j] or 0)) end)
                if foe then return pick(i, foe, false, "lb mark before the break") end
            end
        end
    end
    -- A Limit whose stagger empties a gauge lands the break. A Limit that
    -- waits for a stagger does not spend itself making one.
    local best, bestI, bestFoe = nil, nil, nil
    for i, l in ipairs(limits) do
        if DAMAGE[l.role] and (l.role ~= "stagger") and (l.role ~= "mark") then
            if l.area then
                local breaks = false
                for j, f in ipairs(foes) do
                    if (not f.broken) and l.lands[j] and ((l.pour[j] or 0) >= (f.remain or 0)) and ((f.remain or 0) > 0) then
                        breaks = true
                    end
                end
                if breaks and (not l.blocked) and better(l, best) then best, bestI, bestFoe = l, i, nil end
            else
                local foe = target(l, function(f, j)
                    return (not f.broken) and ((f.remain or 0) > 0) and ((l.pour[j] or 0) >= (f.remain or 0))
                end)
                if foe and better(l, best) then best, bestI, bestFoe = l, i, foe end
            end
        end
    end
    if best then return pick(bestI, bestFoe, best.area, "lb " .. best.role .. " lands the break") end
    -- A full bar fills no further. It is spent rather than held, unless the
    -- Limit waits for a stagger or the break is this round's.
    if full and (not ctx.breakClose) then
        for i, l in ipairs(limits) do
            if DAMAGE[l.role] and (l.role ~= "stagger") and (l.role ~= "mark") and better(l, best) then
                local foe = (not l.area) and target(l, function() return true end) or nil
                if (l.area and not l.blocked) or foe then best, bestI, bestFoe = l, i, foe end
            end
        end
        if best then return pick(bestI, bestFoe, best.area, "lb " .. best.role .. ", bar full") end
    end
    return nil
end

-- Which raise to spend. The second return is true when it raises the party.
-- One fallen ally keeps a single raise. The party row is the last resort
-- for that one body, and only when allowOne is set.
function M.bestRaise(skills, downN, pay, allowOne)
    local party, single = nil, nil
    for _, s in ipairs(skills or {}) do
        local payable = true
        if pay then payable = pay(s) and true or false end
        if (s.kind == "revive") and payable then
            if s.known and s.known.party then
                if not party then party = s end
            elseif not single then
                single = s
            end
        end
    end
    local n = tonumber(downN) or 0
    if (n >= 2) and party then return party, true end
    if single then return single, false end
    if allowOne and party and (n >= 1) then return party, true end
    return nil, false
end

return M

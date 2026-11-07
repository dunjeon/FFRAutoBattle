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

-- Limit Bursts, as skill rows. The planner calls this. This file does not
-- name a fight, a character, or a Vision, and it does not touch the battle
-- libraries.
--
-- The live row has cost and no element. This book names the element, how
-- many gauges the row spends, and whether the payoff is a setup, a hit, or
-- a raise. An ordinary skill that shares a name is not a Limit Burst. The
-- caller applies a row only when the live attribute is a Limit Burst.
-- Lightning is stored as thunder, the same word the enemy book uses.

local BOOK = {
    ["null moon"] = { use = "lb-setup", gauges = 1, stagger = 27, phys = true },
    ["infinity drive"] = { use = "lb-cash", gauges = 1, stagger = 25, element = "fire", phys = true },
    ["crimson onslaught"] = { use = "lb-cash", gauges = 2, stagger = 35, element = "fire", phys = true, area = true },
    ["transient rite"] = { use = "lb-cash", gauges = 2, stagger = 35, element = "ice", phys = true, area = true },
    ["holy ray"] = { use = "lb-cash", gauges = 1, stagger = 25, element = "light", magic = true, area = true },
    ["radiant restoration"] = { use = "lb-revive", gauges = 2, stagger = 50, party = true },
    ["march of the machines"] = { use = "lb-cash", gauges = 1, stagger = 40, phys = true, area = true },
    ["enterprise airstrike"] = { use = "lb-cash", gauges = 2, stagger = 55, phys = true, area = true },
    ["t.r.n.d."] = { use = "lb-cash", gauges = 1, stagger = 27, element = "wind", phys = true },
    ["glücksschmied"] = { use = "lb-cash", gauges = 2, stagger = 30, phys = true },
    ["formation: steeled advance"] = { use = "lb-setup", gauges = 1, party = true },
    ["mirroring prism"] = { use = "lb-setup", gauges = 2, party = true },
    ["eternal veil"] = { use = "lb-setup", gauges = 1, party = true },
    ["sakura's ultima"] = { use = "lb-cash", gauges = 2, stagger = 55, magic = true, area = true },
    ["chaotic convergence"] = { use = "lb-cash", gauges = 1, stagger = 25, element = "dark", magic = true },
    ["abyss graviton"] = { use = "lb-cash", gauges = 2, stagger = 40, element = "dark", magic = true },
}

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
    merged.element = fact.element
    merged.party = fact.party and true or nil
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

-- The ready setup row that spends the most gauges. nil when none can be paid.
function M.bestSetup(skills, pay)
    local best, bestG = nil, -1
    for _, s in ipairs(skills or {}) do
        local info = s.known
        local use = info and info.use
        local payable = true
        if pay then payable = pay(s) and true or false end
        if (use == "lb-setup") and payable then
            local g = tonumber(s.lbCost) or tonumber(info.gauges) or 1
            if g > bestG then best, bestG = s, g end
        end
    end
    return best
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

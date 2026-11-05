-- Espers, as skill rows. The planner calls this. This file does not name a
-- fight, a character, or a Vision, and it does not touch the battle libraries.
--
-- The unit on the field is the stay. A call stays out until that unit has
-- acted and, after the ally list has included it, the list no longer does.
-- A gap in the list before that action is not the unit leaving. A counted
-- stay on the row is not a clock. The element is the signature hit, and it
-- is the prior until this fight has measured the call. A support row has no
-- element. Lightning is stored as thunder, the same word the enemy book uses.

local BOOK = {}
local UNITS = {}
local LOADED = false

local function fold(name)
    local n = (name or ""):lower()
    n = n:gsub("’", "'"):gsub("‘", "'"):gsub("`", "'")
    return n
end

local function hasName(key, esper)
    if key == esper then return true end
    local stripped = key:gsub("^summon[:%s]+", ""):gsub("%s+esper$", "")
    return stripped == esper
end

local function copyOf(row)
    local copy = { use = "summon" }
    for k, v in pairs(row) do copy[k] = v end
    copy.use = "summon"
    return copy
end

local M = {}

-- Filled from the game's rows (rows.lua).
function M.load(t)
    BOOK = t or {}
    UNITS = {}
    for _, row in pairs(BOOK) do
        if row.unit then UNITS[row.unit] = true end
    end
    LOADED = true
end

-- True once the game's rows have been handed in. An empty book still counts.
function M.loaded() return LOADED end

-- True when this catalog id is the unit a summon row calls.
function M.isUnit(id)
    return UNITS[id] and true or false
end

-- The live summon name, or nil when the row is not one of these Espers.
function M.lookup(name)
    local key = fold(name)
    if key == "" then return nil end
    if BOOK[key] then return copyOf(BOOK[key]) end
    for esper, row in pairs(BOOK) do
        if hasName(key, esper) then return copyOf(row) end
    end
    return nil
end

-- True while a counted stay that started at `at` is still inside `now`.
-- One Esper turn is about one pass of the party. The count is ally commands.
-- No count, or a count the table left blank, is not a stay. The caller asks
-- the field whether the unit is still there.
function M.stillOut(at, now, turns, party)
    local stay = tonumber(turns)
    if not stay or stay < 1 then return false end
    local size = tonumber(party) or 1
    if size < 1 then size = 1 end
    local span = stay * size
    local startAt = tonumber(at) or 0
    local clock = tonumber(now) or 0
    return (clock - startAt) < span
end

-- True while another Esper must not be called.
-- `present` means this ally scan lists that unit alive. `mark.acted` means
-- the unit has taken its own action. `mark.seen` means an earlier ally scan
-- listed it. Until it has acted, it is still out. After that, it is out
-- until a scan that had listed it no longer does.
function M.holding(mark, present)
    if present then return true end
    if not mark then return false end
    if not mark.acted then return true end
    if not mark.seen then return true end
    return false
end

-- Higher is a better call. nil means do not call this row.
-- `prefer` is the foe the turn is about. A weakness there outranks a weakness
-- on someone else, which outranks a hit that simply lands. A support row is
-- the call when no damage row lands. An element the signature would null or
-- absorb, on a foe that signature hits, is not called. `area` means the
-- signature hits every living enemy, so one null on the field is enough.
function M.score(fact, hits)
    if not fact then return nil end
    local role = fact.role or "damage"
    if role == "guard" then return 15 end
    if not fact.element then
        for _, h in ipairs(hits or {}) do
            if ((h.factor or 1) <= 0) and (fact.area or h.prefer) then return nil end
        end
        return 40
    end
    local prefer, weak = nil, false
    local saw = false
    for _, h in ipairs(hits or {}) do
        local f = h.factor or 1
        if (f <= 0) and (fact.area or h.prefer) then return nil end
        if (f >= 3) and (h.prefer or not fact.area) then weak = true end
        if h.prefer then
            saw = true
            prefer = f
        end
    end
    if not saw then prefer = 1 end
    if prefer <= 0 then return nil end
    if prefer >= 3 then return 100 end
    if weak and (prefer >= 1) then return 60 end
    if prefer < 1 then return 10 end
    return 20
end

-- The call this fight has measured comes first: a kill, then the damage, the
-- same order a spell uses. The signature's element breaks a tie, and it picks
-- the call when nothing has been measured yet. A measured miss leaves that
-- prior in place.
function M.best(cands)
    local best, bestScore = nil, 0
    for _, c in ipairs(cands or {}) do
        local score = M.score(c.fact, c.hits)
        if score then
            local function ahead()
                if not best then return true end
                local ck, bk = c.kills or 0, best.kills or 0
                if ck ~= bk then return ck > bk end
                local cd, bd = c.dealt, best.dealt
                local cHas, bHas = cd ~= nil, bd ~= nil
                if cHas and bHas and (cd ~= bd) then return cd > bd end
                if cHas ~= bHas then
                    if cHas and (cd > 0) then return true end
                    if bHas and (bd > 0) then return false end
                end
                return score > bestScore
            end
            if ahead() then best, bestScore = c, score end
        end
    end
    return best
end

return M

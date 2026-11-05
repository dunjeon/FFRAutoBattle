-- Espers, as skill rows. The planner calls this. This file does not name a
-- fight, a character, or a Vision, and it does not touch the battle libraries.
--
-- A summon stays for the turn count on its row. With no count, it stays until
-- the game says it left. The party can call it again. The element is the
-- signature hit. A support row has no element. Lightning is stored as thunder,
-- the same word the enemy book uses.

local BOOK = {}

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
function M.load(t) BOOK = t end

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

-- True while the stay that started at `at` is still inside `now`.
-- One Esper turn is about one pass of the party. The count is ally commands.
function M.stillOut(at, now, turns, party)
    local stay = tonumber(turns)
    if not stay or stay < 1 then return true end
    local size = tonumber(party) or 1
    if size < 1 then size = 1 end
    local span = stay * size
    local startAt = tonumber(at) or 0
    local clock = tonumber(now) or 0
    return (clock - startAt) < span
end

-- Higher is a better call. nil means do not call this row.
-- mode "break" is the moment before a gauge empties, so a support row waits.
-- An element the field absorbs or nulls is not called. The signature hits everyone.
function M.score(fact, hits, mode)
    if not fact then return nil end
    local role = fact.role or "damage"
    if role == "guard" then
        if mode == "break" then return nil end
        return 30
    end
    if not fact.element then return 40 end
    local prefer, weak = nil, false
    local saw = false
    for _, h in ipairs(hits or {}) do
        local f = h.factor or 1
        if f <= 0 then return nil end
        if f >= 3 then weak = true end
        if h.prefer then
            saw = true
            prefer = f
        end
    end
    if not saw then prefer = 1 end
    if prefer >= 3 then return 100 end
    if weak then return 60 end
    if (prefer > 0) and (prefer < 1) then return 10 end
    return 20
end

function M.best(cands, mode)
    local best, bestScore = nil, 0
    for _, c in ipairs(cands or {}) do
        local score = M.score(c.fact, c.hits, mode)
        if score and (score > bestScore) then
            best, bestScore = c, score
        end
    end
    return best
end

return M

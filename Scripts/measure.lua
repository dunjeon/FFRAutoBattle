-- What actually hit hard this fight, from the game's own hit records. This file
-- only keeps numbers. It starts empty each fight and names nothing.

local M = {}

-- A staggered enemy takes more. These hits are scaled back so a number means
-- the same thing whether or not the target was staggered.
local BREAK_SCALE = 1.5

function M.new()
    return { byFoe = {}, bySkill = {}, sums = {}, seen = {} }
end

-- False when this exact hit was already read. The list is read more than once.
function M.fresh(book, sig)
    if book.seen[sig] then return false end
    book.seen[sig] = true
    return true
end

local function blend(rec, value)
    rec.uses = rec.uses + 1
    rec.avg = (rec.avg == nil) and value or ((rec.avg + value) / 2)
    if value > rec.best then rec.best = value end
end

-- Weakness is 3x on the stagger gauge (measured 3.08x) but about 1.5x on damage.
-- elementFactor gives the stagger number, so a damage estimate converts it here.
M.WEAK_DAMAGE = 1.5
function M.damageFit(f)
    if f >= 3 then return M.WEAK_DAMAGE end
    return f
end

-- One cast by one caster on one enemy. raw: total damage. est: power times hits
-- times the element factor, the number the row alone would give.
function M.add(book, from, skill, to, raw, est, onBreak)
    if (not raw) or (raw <= 0) then return end
    local value = onBreak and (raw / BREAK_SCALE) or raw
    local foeKey = tostring(from) .. ":" .. tostring(skill) .. ":" .. tostring(to)
    local skillKey = tostring(from) .. ":" .. tostring(skill)
    book.byFoe[foeKey] = book.byFoe[foeKey] or { uses = 0, best = 0 }
    book.bySkill[skillKey] = book.bySkill[skillKey] or { uses = 0, best = 0, from = from, skill = skill }
    blend(book.byFoe[foeKey], value)
    blend(book.bySkill[skillKey], value)
    if est and est > 0 then
        local sum = book.sums[from] or { raw = 0, est = 0 }
        sum.raw, sum.est = sum.raw + value, sum.est + est
        book.sums[from] = sum
    end
end

-- The damage to expect, or nil when there's nothing to go on. What this hit did
-- to this enemy comes first. Otherwise the row's number, scaled by what this
-- caster's other hits really did. The same skill on another enemy is only a
-- guide, since that enemy's weakness can differ.
function M.expect(book, from, skill, to, est)
    local rec = book.byFoe[tostring(from) .. ":" .. tostring(skill) .. ":" .. tostring(to)]
    if rec then return rec.avg, true end
    local sum = book.sums[from]
    if sum and (sum.est > 0) and est and (est > 0) then
        return est * (sum.raw / sum.est), false
    end
    return nil, false
end

-- What a warned move should do to this ally at full size, and that move's row.
-- The list doesn't say which of the foe's dangerous moves is coming, so this is
-- the worst of them. A move already seen on this ally uses that number. Otherwise
-- its power is scaled by what this foe's other moves of the same damage type did
-- to this ally. Nil with nothing to go on. foeBook: this foe's hit book. rowOf:
-- skill id to its row.
function M.warnedCast(foeBook, risk, rowOf, ally)
    local worst, worstRow = nil, nil
    for _, id in ipairs(risk or {}) do
        local row = rowOf(id)
        local amount = foeBook[id] and foeBook[id].fullTo and foeBook[id].fullTo[ally]
        if (not amount) and row and ((row.power or 0) > 0) then
            local rate = nil
            for sid, sk in pairs(foeBook) do
                local other = rowOf(sid)
                local did = sk.fullTo and sk.fullTo[ally]
                if did and other and ((other.power or 0) > 0) and (other.dmgType == row.dmgType) then
                    local r = did / other.power
                    if (not rate) or (r > rate) then rate = r end
                end
            end
            if rate then amount = rate * row.power end
        end
        if amount and ((not worst) or (amount > worst)) then worst, worstRow = amount, row end
    end
    return worst, worstRow
end

-- The hit to kill a foe with this much HP, or nil. shots: { skill, real, cost }.
-- The cheapest one with room to spare, or the hardest one that should just do it.
function M.pickKill(shots, hp)
    local sure, close = nil, nil
    for _, shot in ipairs(shots or {}) do
        if (shot.real * 0.9) >= hp then
            if (not sure) or (shot.cost < sure.cost) or ((shot.cost == sure.cost) and (shot.real > sure.real)) then sure = shot end
        elseif shot.real >= hp then
            if (not close) or (shot.real > close.real) then close = shot end
        end
    end
    return sure or close
end

-- The hardest hits, for the report.
function M.lines(book, nameOf)
    local list = {}
    for _, rec in pairs(book.bySkill) do list[#list + 1] = rec end
    table.sort(list, function(a, b) return a.avg > b.avg end)
    local out = {}
    for i = 1, math.min(#list, 12) do
        local r = list[i]
        out[#out + 1] = string.format("  %s: %d a cast lately, best %d, %d casts", nameOf(r.from, r.skill), math.floor(r.avg + 0.5), math.floor(r.best + 0.5), r.uses)
    end
    return out
end

return M

-- What actually hit hard this fight, from the game's own hit records. This file
-- only keeps numbers. It starts empty each fight and names nothing.

local M = {}

-- The game's break factor. A staggered target takes 1.5x damage (probe: isOnBreak).
-- Hits are scaled back so a number means the same thing on or off a break.
local BREAK_SCALE = 1.5

function M.new()
    return { byFoe = {}, bySkill = {}, sums = {}, seen = {}, land = {} }
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

-- The game's resistance factors. resistance 1 is weakness: 1.5x damage, and the
-- stagger factor elementFactor returns for a weakness is 3. resistance 2 is half,
-- 3 is a null, 4 absorbs. A hit record's damageMultiplier already includes
-- weakness, a break, and a critical. The book stores damage off a break, so
-- that multiplier gives the break factor back. With no multiplier, the
-- resistance field is the factor.
M.WEAK_DAMAGE = 1.5
M.HALF_DAMAGE = 0.5
local RESIST_DAMAGE = { [0] = 1, [1] = 1.5, [2] = 0.5, [3] = 0, [4] = -1 }
function M.damageFit(f)
    if f >= 3 then return M.WEAK_DAMAGE end
    return f
end

function M.hitFactor(res, mult, onBreak)
    local m = tonumber(mult)
    if m then
        if onBreak and (BREAK_SCALE ~= 0) then m = m / BREAK_SCALE end
        return m
    end
    local f = RESIST_DAMAGE[tonumber(res) or -1]
    if f == nil then return 1 end
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

-- One cast by one caster on one target, landed or missed. A hit that misses does
-- nothing, so what a skill is worth has to include how often it misses.
function M.noteCast(book, from, skill, landed)
    local key = tostring(from) .. ":" .. tostring(skill)
    local rec = book.land[key] or { casts = 0, landed = 0 }
    rec.casts = rec.casts + 1
    if landed then rec.landed = rec.landed + 1 end
    book.land[key] = rec
end

-- How often this hit lands, 0 to 1. Until a cast has landed, the row's accuracy
-- is the answer. Misses alone do not retire it. Once one has landed, the casts
-- are the answer. Rows list 0 for no roll and over 100 for a sure hit.
function M.landRate(book, from, skill, accuracy)
    local listed = 1
    if accuracy and (accuracy > 0) and (accuracy < 100) then listed = accuracy / 100 end
    local rec = book and book.land[tostring(from) .. ":" .. tostring(skill)]
    if not rec or rec.casts < 1 or rec.landed < 1 then return listed end
    return rec.landed / rec.casts
end

-- What one hit record says about that foe. res is the row's resistance:
-- 1 weak, 2 half, 3 null, 4 absorb, 5 reflect. A miss says nothing. A hit
-- that took no HP, and was not a miss, is a null. A plain hit with no
-- resistance field says nothing, so a critical is not filed as a weakness.
function M.lesson(res, missed, raw)
    if missed then return nil end
    res = tonumber(res)
    if res == 1 then return "weak" end
    if res == 2 then return "half" end
    if res == 3 then return "no" end
    if res == 4 then return "absorb" end
    if res == 5 then return "reflect" end
    if (raw ~= nil) and (raw <= 0) then return "no" end
    return nil
end

local LESSONS = { "weak", "half", "no", "absorb", "reflect" }

-- The first time this foe shows this result for this element or kind.
-- stamp is the foe's status list. The same result under a new list replaces
-- the old stamp. A different result clears the old one.
function M.noteFoe(book, foe, key, lesson, stamp)
    if (not book) or (foe == nil) or (not key) or (not lesson) then return false end
    local rec = book[foe]
    if not rec then
        rec = { weak = {}, half = {}, no = {}, absorb = {}, reflect = {} }
        book[foe] = rec
    end
    if not rec[lesson] then rec[lesson] = {} end
    for _, name in ipairs(LESSONS) do
        if name ~= lesson and rec[name] then rec[name][key] = nil end
    end
    local slot = rec[lesson]
    local prev = slot[key]
    slot[key] = stamp or true
    return prev == nil
end

-- The factor elementFactor already uses, or nil when this fight has not
-- seen the element. A null, an absorb, and a reflect are no damage. A
-- weakness is 3. stamp is the foe's status list now. A lesson filed under
-- another list no longer applies.
function M.foeFactor(book, foe, element, kind, stamp)
    local rec = book and book[foe]
    if not rec then return nil end
    local function listed(slot, key)
        if not (key and slot and slot[key] ~= nil) then return false end
        if stamp == nil then return true end
        local held = slot[key]
        if held == true then return true end
        return held == stamp
    end
    if listed(rec.no, kind) or listed(rec.absorb, kind) or listed(rec.reflect, kind)
        or listed(rec.no, element) or listed(rec.absorb, element) or listed(rec.reflect, element) then
        return 0
    end
    if listed(rec.weak, element) then return 3 end
    if listed(rec.half, element) then return 0.5 end
    return nil
end

-- The damage to expect, or nil when there's nothing to go on. What this hit did
-- to this enemy comes first. Otherwise the row's number, scaled by what this
-- caster's other hits really did. The same skill on another enemy is only a
-- guide, since that enemy's weakness can differ.
function M.expect(book, from, skill, to, est, accuracy)
    local land = M.landRate(book, from, skill, accuracy)
    local rec = book.byFoe[tostring(from) .. ":" .. tostring(skill) .. ":" .. tostring(to)]
    if rec then return rec.avg * land, true end
    local sum = book.sums[from]
    if sum and (sum.est > 0) and est and (est > 0) then
        return est * (sum.raw / sum.est) * land, false
    end
    return nil, false
end

-- A kill is a measured hit that reaches the foe's current HP. A scaled
-- estimate can order damage. It is not a kill.
function M.kills(amount, hp, measured)
    if measured ~= true then return false end
    amount = tonumber(amount)
    hp = tonumber(hp)
    if (not amount) or (not hp) or (hp <= 0) then return false end
    return amount >= hp
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
            -- The middle of what its moves did per point of power, so one critical
            -- doesn't set the size of a move that hasn't landed yet.
            local rates = {}
            for sid, sk in pairs(foeBook) do
                local other = rowOf(sid)
                local did = sk.fullTo and sk.fullTo[ally]
                if did and other and ((other.power or 0) > 0) and (other.dmgType == row.dmgType) then
                    rates[#rates + 1] = did / other.power
                end
            end
            if #rates > 0 then
                table.sort(rates)
                local mid = rates[math.ceil(#rates / 2)]
                amount = mid * row.power
            end
        end
        if amount and ((not worst) or (amount > worst)) then worst, worstRow = amount, row end
    end
    return worst, worstRow
end

-- The hit to kill a foe with this much HP, or nil. shots: { skill, real, cost }.
-- A measured hit that meets the remaining HP. The cheapest such hit, and on a
-- tie the harder one.
function M.pickKill(shots, hp)
    local sure = nil
    for _, shot in ipairs(shots or {}) do
        if shot.real >= hp then
            if (not sure) or (shot.cost < sure.cost) or ((shot.cost == sure.cost) and (shot.real > sure.real)) then sure = shot end
        end
    end
    return sure
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

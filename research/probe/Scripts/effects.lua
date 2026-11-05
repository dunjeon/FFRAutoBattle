-- Planner 2, Phase 3: cause and effect.
--
-- Two halves:
--  * rules: what can happen when an action meets a target, from the game's
--    own tables (data.lua) and live statuses. Element against resistance,
--    Reflect and its pierce flag, element-null statuses, absorb, status
--    opposites and stacking.
--  * learner: how much. Real stagger and damage per hit depend on the
--    attacker's stats, buffs, role passives, hit split, and the target, and
--    vary from 0.26x to 6x the table's base for the same resistance (probe
--    v0.6, game-surface.md). So amounts are learned from the game's own
--    per-hit records (socket hits) and the table base is only the first
--    guess.
--
-- Every number this returns says where it came from: "seen" (learned from
-- this attacker and skill), "scaled" (this attacker's other skills), or
-- "table" (base value times the resistance factor).

local M = {}

-- eResistance: 0 None, 1 Weakness, 2 Halved, 3 Invalid, 4 Absorb, 5 Reflect.
-- Damage factors are the game's (weak x1.5, halved x0.5; probe v0.6).
-- Stagger on a weakness is x3 by the guides and fits the logged spread;
-- halved stagger is assumed x0.5 until a log shows it.
M.DAMAGE = { [0] = 1, [1] = 1.5, [2] = 0.5, [3] = 0, [4] = -1 }
M.STAGGER = { [0] = 1, [1] = 3, [2] = 0.5, [3] = 0, [4] = 0 }
M.BROKEN_DAMAGE = 1.5

-- Status ids (eUnitStatusCondition).
local ST = { REFLECT = 32, BREAK = 89 }
local INVALID = { [1] = 61, [2] = 62, [3] = 63, [4] = 64, [5] = 65, [6] = 66, [7] = 67, [8] = 68 }
-- eElement: 1 Fire 2 Ice 3 Wind 4 Earth 5 Thunder 6 Water 7 Light 8 Dark;
-- Invalid statuses run Fire Ice Wind Earth Thunder Water Light Dark too.

local MAGIC = 2

-- The resistance a target has to an element, best source first:
--   seen   : a hit of that element on this body already told us
--   status : an Invalid<Element> status on the body
--   table  : the unit's ElementResistanceList (data.lua units)
-- The enemy book (Scripts/mobs.lua) by name, as v0.1.x reads it: "GoblinC"
-- matches "goblin"; apostrophes fold.
local function card(world, target)
    local mobs = world.mobs
    if not (mobs and target.name) then return nil end
    local n = target.name:lower():gsub("\226\128\153", "'")
    if mobs[n] then return mobs[n] end
    local base = n:gsub("[abcd]$", ""):gsub("%s+$", "")
    return mobs[base]
end
M.card = card

local NAMES = { "fire", "ice", "wind", "earth", "thunder", "water", "light", "dark" }

function M.resistance(world, target, element)
    if not element or element == 0 then return 0, "none" end
    local seen = world.seenRes and world.seenRes[target.uid]
    if seen and seen[element] then return seen[element], "seen" end
    if target.statuses and target.statuses[INVALID[element]] then return 3, "status" end
    local u = target.unitId and world.data and world.data.units[target.unitId]
    if u and u.elements and u.elements[element] then return u.elements[element], "table" end
    local c = card(world, target)
    local en = NAMES[element]
    if c and en then
        if c.weak and c.weak[en] then return 1, "book" end
        if c.half and c.half[en] then return 2, "book" end
        if c.no and c.no[en] then return 3, "book" end
        if c.absorb and c.absorb[en] then return 4, "book" end
        return 0, "book"
    end
    return 0, "unknown"
end

-- A kind of hit (eSkillDamageType 1 physical, 2 magic) that does nothing to
-- this body: the book's no.physical / no.magic, or two hits of that kind
-- seen to do no damage this fight (world.nullKind, AGENTS.md).
function M.kindNulled(world, skill, target)
    local kind = skill.dmgType
    if kind ~= 1 and kind ~= 2 then return false end
    local learned = world.nullKind and world.nullKind[target.uid]
    if learned and (learned[kind] or 0) >= 2 then return true end
    local c = card(world, target)
    if c and c.no then
        if kind == 1 and c.no.physical then return true end
        if kind == 2 and c.no.magic then return true end
    end
    return false
end

-- What a single-target action does when it meets this target, before amounts.
--   { lands, bounces, element, resistance, resSource, damageFactor, staggerFactor }
function M.contact(world, skill, target)
    local out = { lands = true, element = skill.element or 0 }
    if skill.dmgType == MAGIC and target.statuses and target.statuses[ST.REFLECT] and not skill.pierceReflect then
        out.bounces = true
        out.assumed = "reflect bounce (R5)"
    end
    local r, src = M.resistance(world, target, out.element)
    out.resistance, out.resSource = r, src
    out.damageFactor = M.DAMAGE[r] or 1
    out.staggerFactor = M.STAGGER[r] or 1
    if r == 3 or r == 4 then out.lands = false end
    if M.kindNulled(world, skill, target) then out.lands = false; out.kindNull = true end
    if target.statuses and target.statuses[ST.BREAK] then
        out.broken = true
        out.damageFactor = out.damageFactor * M.BROKEN_DAMAGE
    end
    return out
end

-- Status rules from UNIT_STATUSCONDITION_DETAIL_DATA (data.lua statuses).
-- Would adding `status` to a body that has `have` do anything?
function M.statusGain(world, status, have)
    local st = world.data and world.data.statuses[status]
    -- No status row (the sim has no status table): an up status is no gain.
    if not st then
        if have[status] then return false, "already up" end
        return true, "unknown"
    end
    if have[status] and not st.stacks and not st.overwrite then return false, "already up" end
    if st.opposite and st.opposite ~= 0 and have[st.opposite] then return true, "cancels opposite" end
    return true, "new"
end

-- Is this status a reason to act (bad, takes the turn, takes control)?
function M.statusWeight(world, status)
    local st = world.data and world.data.statuses[status]
    if not st then return 0 end
    local w = 0
    if st.bad then w = w + 1 end
    if st.takesAction then w = w + 2 end
    if st.takesControl then w = w + 2 end
    return w
end

--------------------------------------------------------------------------------
-- Learner: per-hit stagger and damage from the game's own records.
--------------------------------------------------------------------------------

-- A key is attacker uid and skill id. Values are normalized to a neutral,
-- unbroken target: observed / resistance factor (/ broken factor for damage).
function M.newLearner()
    return { stag = {}, dmg = {}, heal = {}, actorStag = {}, actorDmg = {}, actorHeal = {}, seenRes = {}, n = 0 }
end

local function push(t, k, v)
    local e = t[k]
    if not e then e = { sum = 0, n = 0 }; t[k] = e end
    e.sum = e.sum + v
    e.n = e.n + 1
end

local function mean(e) return e and e.n > 0 and (e.sum / e.n) or nil end

-- Feed one socket hit record (fields as the probe logs them).
function M.learn(L, D, h)
    local s = h.SkillId and D.skills[h.SkillId]
    if not s or not h.from or not h.to then return end
    local res = h.resistance or 0
    local el = (h.elements and h.elements[1]) or s.element or 0
    if el ~= 0 then
        L.seenRes[h.to] = L.seenRes[h.to] or {}
        L.seenRes[h.to][el] = res
    end
    local key = h.from .. ":" .. h.SkillId
    local sf = M.STAGGER[res] or 1
    if (h.breakDamageValue or 0) > 0 and sf > 0 then
        local v = h.breakDamageValue / sf
        push(L.stag, key, v)
        if (s.stagger or 0) > 0 then push(L.actorStag, h.from, v / s.stagger) end
    end
    local df = M.DAMAGE[res] or 1
    if h.isOnBreak then df = df * M.BROKEN_DAMAGE end
    if h.VariationType == 1 and (h.VariationValue or 0) > 0 and df > 0 then
        local v = h.VariationValue / df
        push(L.dmg, key, v)
        if (s.power or 0) > 0 then push(L.actorDmg, h.from, v / s.power) end
    end
    if h.VariationType == 0 and (h.VariationValue or 0) > 0 and (h.variationParameter or 1) == 1 then
        push(L.heal, key, h.VariationValue)
        if (s.power or 0) > 0 then push(L.actorHeal, h.from, h.VariationValue / s.power) end
    end
    L.n = L.n + 1
end

-- Stagger one hit of `skill` from `actor` will pour into a target with
-- resistance `res`. Returns value and source.
function M.staggerPerHit(L, skill, actor, res)
    local f = M.STAGGER[res or 0] or 1
    local e = mean(L.stag[actor .. ":" .. skill.id])
    if e then return e * f, "seen" end
    local a = mean(L.actorStag[actor])
    if a and skill.stagger then return skill.stagger * a * f, "scaled" end
    return (skill.stagger or 0) * f, "table"
end

function M.damagePerHit(L, skill, actor, res, broken)
    local f = M.DAMAGE[res or 0] or 1
    if broken then f = f * M.BROKEN_DAMAGE end
    local e = mean(L.dmg[actor .. ":" .. skill.id])
    if e then return e * f, "seen" end
    local a = mean(L.actorDmg[actor])
    if a and skill.power then return skill.power * a * f, "scaled" end
    return nil, "none"
end

function M.healPerHit(L, skill, actor)
    local e = mean(L.heal[actor .. ":" .. skill.id])
    if e then return e, "seen" end
    local a = mean(L.actorHeal[actor])
    if a and skill.power then return skill.power * a, "scaled" end
    return nil, "none"
end

return M

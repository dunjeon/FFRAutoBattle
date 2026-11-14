-- Reflect, on any unit, from any source. This file does not name a skill, an
-- Esper, or a fight, and it does not touch the battle libraries.
--
-- Status 32 is Reflect (eUnitStatusCondition). The game's text: it reflects
-- black or white magic cast at the unit; certain spells pass it. A spell
-- that passes it has isReflectPenetration on its row, or a
-- ReflectPenetration (62) effect. Abilities and items are not magic and
-- land: First Aid healed an ally under Reflect, while every single Cure and
-- Cura cast at an ally under Reflect healed the boss instead.
--
-- Not yet seen in play: a party-wide spell cast while some of the party has
-- Reflect. Until a fight shows it lands, it is treated as bouncing off each
-- unit that has Reflect.

local M = {}

M.STATUS = 32
M.MAGIC = 4
M.PIERCE_EFFECT = 62

-- True when this row passes Reflect.
function M.pierces(skill)
    if type(skill) ~= "table" then return false end
    if skill.pierce then return true end
    for _, e in ipairs(skill.effects or {}) do
        if e.type == M.PIERCE_EFFECT then return true end
    end
    return false
end

-- True when this row bounces off a unit under Reflect.
function M.bounces(skill)
    if type(skill) ~= "table" then return false end
    if skill.isItem then return false end
    if skill.attr ~= M.MAGIC then return false end
    return not M.pierces(skill)
end

-- True when this status set has Reflect.
function M.on(set)
    return (type(set) == "table") and (set[M.STATUS] and true or false) or false
end

-- True when this row cast at a unit with this status set would bounce.
function M.blocked(skill, set)
    return M.on(set) and M.bounces(skill)
end

-- The target ids this row would bounce off. statusOf(id) gives a status set.
function M.bouncedOff(skill, ids, statusOf)
    local out = {}
    if not M.bounces(skill) then return out end
    for _, id in ipairs(ids or {}) do
        local ok, set = pcall(statusOf, id)
        if ok and M.on(set) then out[#out + 1] = id end
    end
    return out
end

return M

-- Debuffs. The planner calls these. This file does not name a fight,
-- a character, or a Vision, and it does not touch the battle libraries.
--
-- protect is physical defense down. shell is magic defense down.
-- attack is physical attack down. Those three have no status id, so each
-- is spent once on the danger body, or on the largest gauge.
-- blind and silence are spent on a caster. charm, confuse, poison, and
-- slow are a fallback when none of those is equipped.
-- A status still on the body is not cast again. Once it has been seen and
-- then drops, it can be refreshed. The book ail list is a full immunity.

local STATUS = {
    poison = 1,
    blind = 2,
    silence = 4,
    confuse = 6,
    charm = 8,
    slow = 12,
}

local RANK = {
    protect = 50,
    shell = 40,
    attack = 30,
    silence = 20,
    blind = 10,
}

local FALLBACK = {
    charm = true,
    confuse = true,
    poison = true,
    slow = true,
}

local M = {}
M.STATUS = STATUS

function M.effectOf(skill)
    local info = skill and skill.known
    local effect = info and info.effect
    if (type(effect) ~= "string") or (effect == "") then return nil end
    return effect
end

function M.matter(effect)
    return RANK[effect] ~= nil
end

local function immune(effect, foe)
    local ail = foe and foe.ail
    return (ail and effect and ail[effect]) and true or false
end

-- True while this effect should not be cast again.
-- No status id means the claim lasts the fight.
-- A claimed status that has never been seen stays claimed, so a resist
-- is not cast every turn. Seen, then gone, is a refresh.
function M.up(effect, foe, on, seen)
    if (not effect) or (not foe) then return false end
    local id = STATUS[effect]
    local statuses = foe.statuses
    if id and statuses and statuses[id] then return true end
    local claimed = on and on[foe.id] and on[foe.id][effect]
    if not claimed then return false end
    if not id then return true end
    local saw = seen and seen[foe.id] and seen[foe.id][effect]
    if not saw then return true end
    return false
end

local function classOk(effect, foe, fallback)
    if RANK[effect] then
        if (effect == "silence") or (effect == "blind") then
            return foe.counter == "magic"
        end
        return foe.prefer and true or false
    end
    if fallback and FALLBACK[effect] then
        return foe.prefer and true or false
    end
    return false
end

local function openFoe(foe)
    if not foe then return false end
    if foe.empty or foe.broken or foe.about then return false end
    return true
end

local function better(rank, foe, bestRank, bestFoe)
    if not bestFoe then return true end
    if rank > bestRank then return true end
    if rank < bestRank then return false end
    local danger = (foe.danger and 1 or 0) - (bestFoe.danger and 1 or 0)
    if danger > 0 then return true end
    if danger < 0 then return false end
    return (foe.gauge or 0) > (bestFoe.gauge or 0)
end

local function preferAbout(foes)
    for _, foe in ipairs(foes or {}) do
        if foe.prefer and foe.about then return true end
    end
    return false
end

function M.choose(skills, foes, on, seen, fallback)
    if preferAbout(foes) then return nil end
    local bestS, bestF, bestRank = nil, nil, 0
    for _, skill in ipairs(skills or {}) do
        local effect = M.effectOf(skill)
        local rank = (effect and RANK[effect]) or 0
        if (rank == 0) and fallback and effect and FALLBACK[effect] then rank = 1 end
        if rank > 0 then
            for _, foe in ipairs(foes or {}) do
                if openFoe(foe) and classOk(effect, foe, fallback) and (not immune(effect, foe))
                    and (not M.up(effect, foe, on, seen)) then
                    if better(rank, foe, bestRank, bestF) then
                        bestS, bestF, bestRank = skill, foe, rank
                    end
                end
            end
        end
    end
    if not bestS then return nil end
    local effect = M.effectOf(bestS)
    local claimed = on and on[bestF.id] and on[bestF.id][effect]
    local saw = seen and seen[bestF.id] and seen[bestF.id][effect]
    local why = "setup"
    if claimed and saw then why = "refresh" end
    return bestS, bestF, why
end

-- The effect that would have been spent, except every open body it fits is immune.
function M.immuneEffect(skills, foes, fallback)
    if preferAbout(foes) then return nil end
    local found = nil
    for _, skill in ipairs(skills or {}) do
        local effect = M.effectOf(skill)
        local rank = (effect and RANK[effect]) or 0
        local fb = (rank == 0) and fallback and effect and FALLBACK[effect]
        if (rank > 0) or fb then
            local anyFit, anyImmune = false, false
            for _, foe in ipairs(foes or {}) do
                if openFoe(foe) and classOk(effect, foe, fallback) then
                    if immune(effect, foe) then anyImmune = true else anyFit = true end
                end
            end
            if anyImmune and (not anyFit) then found = effect end
        end
    end
    return found
end

return M

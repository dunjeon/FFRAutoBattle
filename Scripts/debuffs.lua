-- Debuffs. The planner calls these. This file does not name a fight,
-- a character, or a Vision, and it does not touch the battle libraries.
--
-- A defense debuff makes the party's own damage land harder, so it follows what
-- this party really deals. Other debuffs have no general rule, so they aren't cast.
-- A status still on the body is not cast again. Once it has been seen and then
-- drops, it can be refreshed. An immune foe is skipped.

local RANK = {
    defenseDown = 50,
    mindDown = 40,
}

-- Which of this party's damage each defense debuff helps.
local HELPS = { defenseDown = "physical", mindDown = "magic" }
-- Under this share of the damage it would touch, a debuff isn't worth a turn.
local WORTH = 0.2

-- A debuff's rank. The larger share of this party's damage goes first.
-- share: { physical, magic }.
local function rankOf(effect, share)
    local base = effect and RANK[effect]
    if not base then return 0 end
    local helps = share and HELPS[effect]
    if not helps then return base end
    local part = share[helps] or 0
    if part < WORTH then return 0 end
    return 40 + (part * 20)
end

local M = {}

function M.effectOf(skill)
    local info = skill and skill.known
    local effect = info and info.effect
    if (type(effect) ~= "string") or (effect == "") then return nil end
    return effect
end

local function immune(effect, foe)
    local ail = foe and foe.ail
    return (ail and effect and ail[effect]) and true or false
end

-- True while this effect should not be cast again. With no status on the row, the
-- claim lasts the fight.
-- skill: the live row. When it lists the status it puts on the enemy, that
-- status showing is the timer: held while it shows, refreshed once it is gone.
local function rowStatus(skill)
    local map = skill and skill.enemyStatus
    if type(map) ~= "table" then return nil end
    for _ in pairs(map) do return map end
    return nil
end

function M.up(effect, foe, on, seen, skill)
    if (not effect) or (not foe) then return false end
    local map = rowStatus(skill)
    if map then
        for sid in pairs(map) do
            if foe.statuses and foe.statuses[sid] then return true end
        end
        return false
    end
    return (on and on[foe.id] and on[foe.id][effect]) and true or false
end

local function classOk(effect, foe)
    return (RANK[effect] and foe.prefer) and true or false
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

function M.choose(skills, foes, on, seen, share)
    if preferAbout(foes) then return nil end
    local bestS, bestF, bestRank = nil, nil, 0
    for _, skill in ipairs(skills or {}) do
        local effect = M.effectOf(skill)
        local rank = rankOf(effect, share)
        if rank > 0 then
            for _, foe in ipairs(foes or {}) do
                if openFoe(foe) and classOk(effect, foe) and (not immune(effect, foe))
                    and (not M.up(effect, foe, on, seen, skill)) then
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
    local why = "setup"
    if claimed then why = "refresh" end
    return bestS, bestF, why
end

-- The effect that would have been spent, except every open body it fits is immune.
function M.immuneEffect(skills, foes, share)
    if preferAbout(foes) then return nil end
    local found = nil
    for _, skill in ipairs(skills or {}) do
        local effect = M.effectOf(skill)
        local rank = rankOf(effect, share)
        if rank > 0 then
            local anyFit, anyImmune = false, false
            for _, foe in ipairs(foes or {}) do
                if openFoe(foe) and classOk(effect, foe) then
                    if immune(effect, foe) then anyImmune = true else anyFit = true end
                end
            end
            if anyImmune and (not anyFit) then found = effect end
        end
    end
    return found
end

return M

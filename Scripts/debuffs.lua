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
    deprotect = 50,
    deshell = 40,
    debrave = 30,
    defaith = 30,
    silence = 20,
    blind = 10,
}

local FALLBACK = {
    charm = true,
    confuse = true,
    poison = true,
    slow = true,
}

-- Which of this party's damage each defense debuff helps.
local HELPS = { deprotect = "physical", deshell = "magic" }
-- Which of a foe's damage each offense debuff cuts.
local CUTS = { debrave = "physical", defaith = "magic" }

-- How much of the matching damage this debuff touches. 0 means it does not fit.
-- A measured share sorts above one we have not measured yet. With no
-- measurement, it stays available and the first such skill wins.
local function rankOf(effect, share, foe)
    if not (effect and RANK[effect]) then return 0 end
    local function measured(part)
        if part <= 0 then return 0 end
        return 1 + part
    end
    local helps = HELPS[effect]
    if helps then
        if not share then return 1 end
        return measured(share[helps] or 0)
    end
    local cuts = CUTS[effect]
    if cuts then
        if not (foe and foe.deals) then return 1 end
        return measured(foe.deals[cuts] or 0)
    end
    return 1
end

local M = {}
M.STATUS = STATUS

-- How much of this foe's damage is physical and how much magic: what it has really
-- dealt, or before any hit, the kind of its dangerous moves. Nil with neither.
-- foeBook: its hit book, skill id to { total, dtype }. hits: "physical" or "magic".
function M.dealsOf(foeBook, hits)
    local phys, magic = 0, 0
    for _, sk in pairs(foeBook or {}) do
        if sk.dtype == 1 then phys = phys + (sk.total or 0) end
        if sk.dtype == 2 then magic = magic + (sk.total or 0) end
    end
    local total = phys + magic
    if total > 0 then return { physical = phys / total, magic = magic / total } end
    if hits == "physical" then return { physical = 1, magic = 0 } end
    if hits == "magic" then return { physical = 0, magic = 1 } end
    return nil
end

function M.effectOf(skill)
    local info = skill and skill.known
    local effect = info and info.effect
    if (type(effect) ~= "string") or (effect == "") then return nil end
    return effect
end

function M.matter(effect)
    return RANK[effect] ~= nil
end

-- Records what is showing on this foe, so a status that goes later reads as worn
-- off, not as a resist. watch: foe id to effect to the status ids its row lists.
function M.noteSeen(foe, on, watch, seen)
    local set = foe and foe.statuses
    if not (set and seen) then return end
    local function mark(effect)
        seen[foe.id] = seen[foe.id] or {}
        seen[foe.id][effect] = true
    end
    for effect, id in pairs(STATUS) do
        if set[id] then mark(effect) end
    end
    local ids = watch and watch[foe.id]
    for effect in pairs((on and on[foe.id]) or {}) do
        for sid in pairs((ids and ids[effect]) or {}) do
            if set[sid] then mark(effect) end
        end
    end
end

local function immune(effect, foe)
    local ail = foe and foe.ail
    return (ail and effect and ail[effect]) and true or false
end

-- True while this effect should not be cast again.
-- No status id means the claim lasts the fight.
-- A claimed status that has never been seen stays claimed, so a resist
-- is not cast every turn. Seen, then gone, is a refresh.
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
    else
        local id = STATUS[effect]
        if id and foe.statuses and foe.statuses[id] then return true end
    end
    local claimed = on and on[foe.id] and on[foe.id][effect]
    if not claimed then return false end
    -- No status to watch: the claim lasts the fight. A listed status that
    -- was claimed and never seen is a resist, so it is not cast every turn.
    -- Seen, then gone, is a refresh.
    if (not map) and (not STATUS[effect]) then return true end
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

function M.choose(skills, foes, on, seen, fallback, share)
    if preferAbout(foes) then return nil end
    local bestS, bestF, bestRank = nil, nil, 0
    for _, skill in ipairs(skills or {}) do
        local effect = M.effectOf(skill)
        local listed = effect and RANK[effect]
        for _, foe in ipairs(foes or {}) do
            local rank = listed and rankOf(effect, share, foe) or 0
            if (rank == 0) and fallback and effect and FALLBACK[effect] then rank = 1 end
            if rank > 0 then
                if openFoe(foe) and classOk(effect, foe, fallback) and (not immune(effect, foe))
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
    local saw = seen and seen[bestF.id] and seen[bestF.id][effect]
    local why = "setup"
    if claimed and (saw or rowStatus(bestS)) then why = "refresh" end
    return bestS, bestF, why
end

-- The effect that would have been spent, except every open body it fits is immune.
function M.immuneEffect(skills, foes, fallback, share)
    if preferAbout(foes) then return nil end
    local found = nil
    for _, skill in ipairs(skills or {}) do
        local effect = M.effectOf(skill)
        local rank = rankOf(effect, share, nil)
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

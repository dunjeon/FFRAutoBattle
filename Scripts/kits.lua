-- Role skills. The planner calls this. This file does not name a fight,
-- a character, or a Vision, and it does not touch the battle libraries.
--
-- A formation lifts the party. The skill that makes the next formation
-- grant another action goes first, then the one that makes a formation last.
-- Stagger, then critical hits, then defense, then attack.
-- A mechabo hit waits for its overclock. A stance that raises stagger goes
-- out before the chip. A mark sits on one enemy. A weakness is given only
-- when the book lists none, and only once. A luck toss is spent only while
-- a gated hit is sealed and no other hit is ready.
-- Haste, Faith, Bravery, Provoke, Cover, and the other generic buffs are
-- not in this book. A stance that blocks white-magic healing is not either.

local BOOK = {
    ["formation:assail"] = { kind = "formation", rank = 1, turns = 3, party = true },
    ["formation:charge"] = { kind = "formation", rank = 2, turns = 3, party = true },
    ["formation:bulwark"] = { kind = "formation", rank = 3, turns = 3, party = true },
    ["formation:regroup"] = { kind = "formation", rank = 4, turns = 3, party = true },
    ["tactic:fluidwarfare"] = { kind = "ready", rank = 1, turns = 3, with = "formation" },
    ["godofwater'sblessing"] = { kind = "ready", rank = 2, turns = 3, with = "formation" },
    ["overclockzero"] = { kind = "ready", rank = 3, turns = 3, with = "mechabo", group = "overclock" },
    ["overclock"] = { kind = "ready", rank = 4, turns = 3, with = "mechabo", group = "overclock" },
    ["placidity"] = { kind = "ready", rank = 5, turns = 5 },
    ["eminentcasting"] = { kind = "ready", rank = 6, turns = 3, with = "area", offHeal = true },
    ["stratagem"] = { kind = "mark", rank = 1, turns = 3 },
    ["sage'seye"] = { kind = "mark", rank = 2, turns = 4, weakMagic = true },
    ["mechamogscan"] = { kind = "weak", rank = 1, once = true },
    ["cointoss"] = { kind = "luck", rank = 1 },
}

local GATED = {
    ["blitzstrahl"] = true,
    ["demolisherrush"] = true,
}

local MECHABO = {
    ["mechabokick"] = true,
    ["mechabotackle"] = true,
    ["mechafatchocobo"] = true,
    ["mechabehemoth"] = true,
}

-- Spaces and a wide colon are not part of the match. The live name may
-- write either, and the book still finds the row.
local function fold(name)
    local n = (name or ""):lower()
    n = n:gsub("’", "'"):gsub("‘", "'"):gsub("`", "'")
    n = n:gsub("：", ":"):gsub("﹕", ":")
    n = n:gsub("[%s_%-]+", "")
    return n
end

local function listed(map)
    if type(map) ~= "table" then return false end
    for _ in pairs(map) do return true end
    return false
end

local function bodyHas(body, map)
    if (not body) or (not body.statuses) or (not map) then return false end
    for id in pairs(map) do
        if body.statuses[id] then return true end
    end
    return false
end

local M = {}

function M.lookup(name)
    return BOOK[fold(name)]
end

function M.key(name)
    local k = fold(name)
    if BOOK[k] then return k end
    return nil
end

function M.gated(name)
    return GATED[fold(name)] and true or false
end

function M.pick(skills, ctx)
    if (not skills) or (not ctx) then return nil end
    local allies = ctx.allies or {}
    local foes = ctx.foes or {}
    local claim = ctx.claim or {}
    local sent = ctx.sent or {}
    local selfBody = nil
    local party = 0
    for _, a in ipairs(allies) do
        if not a.dead then
            party = party + 1
            if a.id == ctx.selfId then selfBody = a end
        end
    end
    if party < 1 then party = 1 end

    local function timed(key, turns)
        local at = sent[key]
        if type(at) ~= "number" then return false end
        local span = (turns or 3) * party
        local now = ctx.actions or 0
        return (now - at) < span
    end

    local function friendUp(skill, key, turns, partyHit)
        local map = skill.friendStatus
        if listed(map) then
            if partyHit then
                for _, a in ipairs(allies) do
                    if (not a.dead) and bodyHas(a, map) then return true end
                end
            elseif bodyHas(selfBody, map) then
                return true
            end
        end
        return timed(key, turns)
    end

    local function foeUp(skill, foe, key, turns)
        local map = skill.enemyStatus
        if listed(map) and bodyHas(foe, map) then return true end
        return timed(key, turns)
    end

    -- A paid kit goes while MP is above the low band. The low band keeps
    -- the weakness and the free hits. A free kit can go on any band.
    local function afford(skill)
        local cost = skill.cost or 0
        local mp = ctx.mp or 0
        if cost > mp then return false end
        if (mp - cost) < (ctx.keep or 0) then return false end
        local room = ctx.pay
        if room == nil then room = ctx.high end
        if (not room) and (cost > 0) then return false end
        return true
    end

    local function rowOf(skill)
        return BOOK[fold(skill.name)]
    end

    local function hasFormation()
        for _, s in ipairs(skills) do
            local row = rowOf(s)
            if row and (row.kind == "formation") then return true end
        end
        return false
    end

    local function hasMechabo()
        for _, s in ipairs(skills) do
            if MECHABO[fold(s.name)] and (s.kind == "damage") then return true end
        end
        return false
    end

    local function hasAreaMagic()
        for _, s in ipairs(skills) do
            local t = s.target or 0
            local wide = (t == 2) or (t == 3) or (t == 4)
            local info = s.known
            if wide and info and info.magic and (s.kind == "damage") then return true end
        end
        return false
    end

    local function allowed(row)
        if row.offHeal and ctx.healer then return false end
        if row.with == "formation" then return hasFormation() end
        if row.with == "mechabo" then return hasMechabo() end
        if row.with == "area" then return hasAreaMagic() end
        return true
    end

    local function groupUp(group)
        if not group then return false end
        for _, s in ipairs(skills) do
            local row = rowOf(s)
            if row and (row.group == group) then
                local key = fold(s.name)
                if friendUp(s, key, row.turns, row.party) then return true end
            end
        end
        return false
    end

    local function better(rank, best)
        if not best then return true end
        return rank < best
    end

    -- A ready that sets up a formation is spent only when the formation it
    -- sets up still fits after it: the MP covers both, the heal kept back
    -- still fits, and a paid formation is not left in the low band.
    local function followFits(s, row)
        if row.with ~= "formation" then return true end
        local mp = (ctx.mp or 0) - (s.cost or 0)
        local maxMp = ctx.maxMp or 0
        for _, f in ipairs(skills) do
            local frow = rowOf(f)
            if frow and (frow.kind == "formation") and (not claim[fold(f.name)])
                and (not friendUp(f, fold(f.name), frow.turns, true)) then
                local cost = f.cost or 0
                local left = mp - cost
                local band = (cost <= 0) or (maxMp <= 0) or ((mp / maxMp) >= 0.20)
                if (left >= 0) and (left >= (ctx.keep or 0)) and band then return true end
            end
        end
        return false
    end

    local function takeReady()
        local best, bestRank = nil, nil
        for _, s in ipairs(skills) do
            local row = rowOf(s)
            local key = fold(s.name)
            if row and (row.kind == "ready") and allowed(row) and afford(s) and followFits(s, row)
                and (not claim[key]) and (not groupUp(row.group))
                and (not friendUp(s, key, row.turns, row.party))
                and better(row.rank, bestRank) then
                best, bestRank = s, row.rank
            end
        end
        if not best then return nil end
        local row = rowOf(best)
        local mode = (row.party or ((best.target == 2) or (best.target == 3) or (best.target == 4))) and "party" or "self"
        return {
            skill = best, key = fold(best.name), mode = mode,
            why = "setup " .. (best.name or "buff"),
        }
    end

    local function takeFormation()
        local best, bestRank = nil, nil
        for _, s in ipairs(skills) do
            local row = rowOf(s)
            local key = fold(s.name)
            if row and (row.kind == "formation") and afford(s) and (not claim[key])
                and (not friendUp(s, key, row.turns, true))
                and better(row.rank, bestRank) then
                best, bestRank = s, row.rank
            end
        end
        if not best then return nil end
        return {
            skill = best, key = fold(best.name), mode = "party",
            why = "setup formation " .. (best.name or "formation"),
        }
    end

    local function bestFoe(pred)
        local foe, gauge = nil, -1
        for _, u in ipairs(foes) do
            if pred(u) and ((u.gauge or 0) > gauge) then
                foe, gauge = u, u.gauge or 0
            end
        end
        return foe
    end

    local function takeMark()
        local best, bestRank, foe = nil, nil, nil
        for _, s in ipairs(skills) do
            local row = rowOf(s)
            if row and (row.kind == "mark") and afford(s) and better(row.rank, bestRank) then
                local hit = bestFoe(function(u)
                    if row.weakMagic and (not u.magicWeak) then return false end
                    local key = fold(s.name) .. ":" .. tostring(u.id)
                    if claim[key] then return false end
                    if foeUp(s, u, key, row.turns) then return false end
                    return true
                end)
                if hit then best, bestRank, foe = s, row.rank, hit end
            end
        end
        if not best or not foe then return nil end
        return {
            skill = best, foe = foe, mode = "foe",
            key = fold(best.name) .. ":" .. tostring(foe.id),
            why = "setup mark " .. (best.name or "mark") .. " " .. (foe.name or "enemy"),
        }
    end

    local function takeWeak()
        local best = nil
        for _, s in ipairs(skills) do
            local row = rowOf(s)
            if row and (row.kind == "weak") and afford(s) then best = s end
        end
        if not best then return nil end
        if claim.weak or sent.weak then return nil end
        local foe = bestFoe(function(u) return u.bare and true or false end)
        if not foe then return nil end
        return {
            skill = best, foe = foe, mode = "foe", key = "weak",
            why = "setup weakness " .. (foe.name or "enemy"),
        }
    end

    local function takeLuck()
        if not ctx.tossOk then return nil end
        for _, s in ipairs(skills) do
            local row = rowOf(s)
            local key = fold(s.name)
            if row and (row.kind == "luck") and afford(s) and (not claim[key]) then
                return {
                    skill = s, key = key, mode = "self", luck = true,
                    why = "setup luck " .. (s.name or "toss"),
                }
            end
        end
        return nil
    end

    return takeReady() or takeFormation() or takeMark() or takeWeak() or takeLuck()
end

return M

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
-- Every table below is filled from the game's rows at launch.

local BOOK = {}

-- Skills that pull enemy attacks onto the caster. Provoke draws every
-- enemy for about three turns. Cover takes the hits meant for one ally.
-- Multi-Cover does that for the party. Cover has no published duration,
-- so it is held while its live status is up, or cast once a fight when
-- the row lists no status.
local DRAW = {}

-- Stances that stay up until their off skill goes out. Each one lifts the
-- caster and blocks white-magic healing on the caster. It goes up on a hard
-- field while the caster is healthy, and comes off when the caster is under
-- the recover line and a spell heal could reach them once it is off.
local STANCE = {}
local STANCE_OFF = {}

-- Haste. It is the answer to Slow, and it speeds the ally a long fight
-- leans on. Hastega is the party row.
local HASTE = {}
local SLOW_ID = 12

local GATED = {}

local MECHABO = {}

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

-- Fills the tables from the game's rows (rows.lua).
function M.load(k)
    BOOK, DRAW, HASTE, MECHABO = k.book, k.draw, k.haste, k.mechabo
    STANCE, STANCE_OFF = {}, {}
    for on in pairs(k.stance) do
        local off = k.stanceOff["end" .. on]
        if not off then off = next(k.stanceOff) and ("end" .. on) end
        STANCE[on] = { off = "end" .. on }
        STANCE_OFF["end" .. on] = on
    end
end

function M.lookup(name)
    return BOOK[fold(name)]
end

-- "on" or "off" and the stance key, or nil when the name is no stance skill.
function M.stance(name)
    local k = fold(name)
    if STANCE[k] then return "on", k end
    if STANCE_OFF[k] then return "off", STANCE_OFF[k] end
    return nil
end

-- True when the kit carries Provoke, Cover, or Multi-Cover.
function M.guards(kit)
    for _, s in ipairs((kit and kit.spells) or {}) do
        if DRAW[fold(s.name)] then return true end
    end
    return false
end

-- Put a stance up, take it down, or nil.
-- ctx: allies, selfId, on (the stance is up on the actor), hard, recoverAt,
-- spellHeal (a living ally can pay a white-magic heal), round, endedRound,
-- mp, keep, pay.
-- Up: a hard field, the actor at 75% or more, and two rounds since it came
-- off. Down: the actor under the recover line and a spell heal is there to
-- use once it is off. With no spell heal, items still reach the actor, so
-- the stance stays up.
function M.pickStance(skills, ctx)
    if (not skills) or (not ctx) then return nil end
    local selfBody = nil
    for _, a in ipairs(ctx.allies or {}) do
        if (a.id == ctx.selfId) and (not a.dead) then selfBody = a end
    end
    if not selfBody then return nil end
    local hp = selfBody.hp or 1
    for _, s in ipairs(skills) do
        local k = fold(s.name)
        local row = STANCE[k]
        local offRow = STANCE_OFF[k] and STANCE[STANCE_OFF[k]]
        local on = ctx.on and ctx.on[STANCE_OFF[k] or k]
        if offRow and on then
            if (hp < (ctx.recoverAt or 0.50)) and ctx.spellHeal and ((s.cost or 0) <= (ctx.mp or 0)) then
                return {
                    skill = s, key = STANCE_OFF[k], off = true, mode = "self",
                    why = string.format("stance off %s at %d%%", s.name or "stance", math.floor(hp * 100 + 0.5)),
                }
            end
        elseif row and (not on) and ctx.hard and (hp >= 0.75) then
            local cost = s.cost or 0
            local mp = ctx.mp or 0
            local ended = ctx.endedRound and ctx.endedRound[k]
            local rested = (type(ended) ~= "number") or (((ctx.round or 0) - ended) >= 2)
            local fits = (cost <= mp) and ((mp - cost) >= (ctx.keep or 0)) and ((cost <= 0) or ctx.pay)
            if rested and fits then
                return { skill = s, key = k, mode = "self", why = "stance " .. (s.name or "stance") }
            end
        end
    end
    return nil
end

function M.key(name)
    local k = fold(name)
    if BOOK[k] or DRAW[k] or HASTE[k] then return k end
    return nil
end

-- Haste for the actor to cast, or nil.
-- A slowed ally gets it first, on any field: Haste is the answer to Slow.
-- On a hard field, while the bar is above half, the healer and then the
-- strongest damage dealer get it. A cast is held while its status is on
-- that ally. With no status id, each ally gets it once a fight. One per
-- round. A paid one goes while MP is above the low band, and a carried
-- heal is kept back. Hastega goes when two or more allies want it.
-- ctx: allies, selfId, healerId, dealerId, hard, rich, mp, keep, pay,
-- claim, sent.
function M.pickHaste(skills, ctx)
    if (not skills) or (not ctx) then return nil end
    local claim = ctx.claim or {}
    local sent = ctx.sent or {}
    if claim.haste then return nil end
    local single, party = nil, nil
    for _, s in ipairs(skills) do
        local row = HASTE[fold(s.name)]
        local cost = s.cost or 0
        local mp = ctx.mp or 0
        local fits = (cost <= mp) and ((mp - cost) >= (ctx.keep or 0)) and ((cost <= 0) or ctx.pay)
        if row and fits then
            if row.party then party = party or s else single = single or s end
        end
    end
    if not (single or party) then return nil end
    local function hasted(skill, a)
        local map = skill.friendStatus
        if listed(map) then return bodyHas(a, map) end
        return sent["haste:" .. tostring(a.id)] ~= nil
    end
    local any = single or party
    local want, seen = {}, {}
    local function add(a, why)
        if a and (not a.dead) and (not seen[a.id]) and (not hasted(any, a)) then
            seen[a.id] = true
            want[#want + 1] = { ally = a, why = why }
        end
    end
    local byId = {}
    for _, a in ipairs(ctx.allies or {}) do
        if not a.dead then byId[a.id] = a end
        if (not a.dead) and a.statuses and a.statuses[SLOW_ID] then add(a, "slow") end
    end
    if ctx.hard and ctx.rich then
        add(byId[ctx.healerId], "healer")
        add(byId[ctx.dealerId], "dealer")
    end
    if #want == 0 then return nil end
    if party and ((#want >= 2) or (not single)) then
        local names = {}
        for _, w in ipairs(want) do names[#names + 1] = w.ally.name or "ally" end
        return {
            skill = party, mode = "party", keys = want,
            why = "haste party " .. table.concat(names, ", "),
        }
    end
    local first = want[1]
    return {
        skill = single, mode = "ally", target = first.ally, keys = { first },
        why = "haste " .. (first.ally.name or "ally") .. ((first.why == "slow") and ", slow" or ""),
    }
end

-- Provoke, Cover, or Multi-Cover for the actor, or nil.
-- They answer a threat: a dangerous attack still open on the field, or a
-- healer under the recover line. A calm field spends none. The healer
-- does not pull attacks, and neither does an ally under the recover line.
-- There has to be someone else to protect. One of them per round, then
-- the chip. A paid one goes while MP is above the low band.
-- ctx: allies, selfId, healerId, recoverAt, danger, mp, keep, pay,
-- claim, sent, round, drawRound.
function M.pickDraw(skills, ctx)
    if (not skills) or (not ctx) then return nil end
    local claim = ctx.claim or {}
    local sent = ctx.sent or {}
    if claim.draw then return nil end
    local line = ctx.recoverAt or 0.50
    local selfBody, healer, others, lowest = nil, nil, 0, nil
    local party = 0
    for _, a in ipairs(ctx.allies or {}) do
        if not a.dead then
            party = party + 1
            if a.id == ctx.selfId then
                selfBody = a
            else
                others = others + 1
                if (not lowest) or ((a.hp or 1) < (lowest.hp or 1)) then lowest = a end
            end
            if a.id == ctx.healerId then healer = a end
        end
    end
    if (not selfBody) or (others == 0) then return nil end
    if ctx.healerId and (ctx.selfId == ctx.healerId) then return nil end
    if (selfBody.hp or 1) < line then return nil end
    local healerHurt = healer and (healer.id ~= ctx.selfId) and ((healer.hp or 1) < line)
    if not (ctx.danger or healerHurt) then return nil end

    local function afford(skill)
        local cost = skill.cost or 0
        local mp = ctx.mp or 0
        if cost > mp then return false end
        if (mp - cost) < (ctx.keep or 0) then return false end
        if (cost > 0) and (not ctx.pay) then return false end
        return true
    end
    -- Up while its status is on a living ally. A status seen and then
    -- gone can be recast. A status the game has not shown since the cast
    -- is treated as no status: Provoke is up for its turns, and a Cover
    -- is spent once a fight.
    local seen = ctx.seen or {}
    -- Draw timing is in the planner's rounds, one turn for each party
    -- member, so Haste and extra turns do not shorten it.
    local castAt = ctx.drawRound or {}
    local round = ctx.round or 0
    local function up(skill, row, key)
        local at = castAt[key]
        local now = round
        local span = row.turns or 0
        local map = skill.friendStatus
        if listed(map) then
            for _, a in ipairs(ctx.allies or {}) do
                if (not a.dead) and bodyHas(a, map) then
                    seen[key] = true
                    return true
                end
            end
            if seen[key] then return false end
        end
        if type(at) ~= "number" then return false end
        if row.kind == "provoke" then return (now - at) < span end
        return true
    end

    -- One draw at a time. Provoke, Cover, and Multi-Cover all pull the hits
    -- onto the caster, so a second one waits while another is up: its
    -- status is on an ally, or it went out within three rounds.
    for key in pairs(DRAW) do
        local at = castAt[key]
        if (type(at) == "number") and ((round - at) < 3) then return nil end
    end
    for _, s in ipairs(skills) do
        local row = DRAW[fold(s.name)]
        if row and listed(s.friendStatus) then
            for _, a in ipairs(ctx.allies or {}) do
                if (not a.dead) and bodyHas(a, s.friendStatus) then return nil end
            end
        end
    end

    local found = {}
    for _, s in ipairs(skills) do
        local key = fold(s.name)
        local row = DRAW[key]
        if row and afford(s) and (not up(s, row, key)) then
            local slot = (row.kind == "cover") and (row.party and "party" or "cover") or "provoke"
            if not found[slot] then found[slot] = { skill = s, key = key } end
        end
    end
    local order = healerHurt and { "cover", "party", "provoke" } or { "provoke", "party", "cover" }
    for _, slot in ipairs(order) do
        local f = found[slot]
        if f then
            -- This cast starts a new watch for its status.
            seen[f.key] = nil
            if slot == "cover" then
                local target = (healerHurt and healer) or lowest
                if target then
                    return {
                        skill = f.skill, key = f.key, mode = "ally", target = target,
                        why = "draw " .. (f.skill.name or "cover") .. " on " .. (target.name or "ally"),
                    }
                end
            elseif slot == "party" then
                return {
                    skill = f.skill, key = f.key, mode = "party",
                    why = "draw " .. (f.skill.name or "cover") .. " party",
                }
            else
                return {
                    skill = f.skill, key = f.key, mode = "self",
                    why = "draw " .. (f.skill.name or "provoke"),
                }
            end
        end
    end
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

    -- A short buff wears off fast, so it waits until a weak hitter can cast it
    -- with a break close enough to land while it's up. A defense waits for the
    -- first hit. Long buffs can go any time.
    local function inTime(row)
        if row.timed and (not ctx.timedOk) then return false end
        if row.afterHit and (not ctx.chipped) then return false end
        return true
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
            if row and (row.kind == "ready") and inTime(row) and allowed(row) and afford(s) and followFits(s, row)
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
            if row and (row.kind == "formation") and inTime(row) and afford(s) and (not claim[key])
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
            if row and (row.kind == "mark") and inTime(row) and afford(s) and better(row.rank, bestRank) then
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

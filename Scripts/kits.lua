-- Skills that pull hits onto the caster or speed the party. The planner calls this.
-- This file does not name a fight, a character, or a Vision, and it does not touch
-- the battle libraries. Every table below is filled from the game's rows at launch.

-- Skills that pull enemy attacks onto the caster. A Cover with no published
-- duration is held while its live status is up, or cast once a fight when the
-- row lists no status.
local DRAW = {}

-- It is the answer to Slow, and it speeds the ally a long fight leans on.
local HASTE = {}
local SLOW_ID = 12

-- Spaces and a wide colon are not part of the match. The live name may
-- write either, and the rows still finds the row.
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
    DRAW, HASTE = k.draw, k.haste
end

-- True when the kit carries a draw.
function M.guards(kit)
    for _, s in ipairs((kit and kit.spells) or {}) do
        if DRAW[fold(s.name)] then return true end
    end
    return false
end

function M.key(name)
    local k = fold(name)
    if DRAW[k] or HASTE[k] then return k end
    return nil
end

-- Haste for the actor to cast, or nil.
-- A slowed ally gets it first, on any field: Haste is the answer to Slow.
-- On a hard field, while the bar is above half, the healer and then the
-- strongest damage dealer get it. A cast is held while its status is on
-- that ally. With no status id, each ally gets it once a fight. One per
-- round. A paid one goes while MP is above the low band, and a carried
-- heal is kept back. The party row goes when two or more allies want it.
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

-- a draw for the actor, or nil.
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
    -- is treated as no status: A provoke row is up for its turns, and a cover row
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

    -- One draw at a time. Draws all pull the hits
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

return M

-- How the team gets ready for a warned hit. One question for every tool: what is
-- about to land, whom would it kill, and which action this unit holds saves the
-- most of them. This file only does the numbers. It names no skill, unit or boss.

local M = {}

local PHYS, MAGIC = 1, 2
local SELF, SINGLE = 0, 1
local EFFECT_CUT, EFFECT_COVER = 26, 41
-- Hits of one move vary a little, so a close call counts as not surviving.
local MARGIN = 1.1

-- Share of a hit that gets through a cut row, or nil when it doesn't touch this kind.
-- param 1: 0 both kinds, 1 physical, 2 magic. param 2: the percent removed.
local function cutOf(e, kind)
    local which, pct = e.params and e.params[1], e.params and e.params[2]
    if not (which and pct and (pct > 0)) then return nil end
    if (which ~= 0) and kind and (which ~= kind) then return nil end
    -- Kind unknown: only a cut that covers both can be counted on.
    if (which ~= 0) and (not kind) then return nil end
    return math.max(0, 1 - (pct / 100))
end

-- What a friendly row does against a hit, or nil when it does nothing. Rows can
-- cut each kind with a separate effect, and only one of those may carry the status.
function M.describe(row, kind)
    local through, status, turns, cover = nil, nil, nil, false
    for _, e in ipairs(row.effects or {}) do
        if e.type == EFFECT_CUT then
            local share = cutOf(e, kind)
            if share then
                through = (through or 1) * share
                if (e.turns or 0) > 0 then turns = math.min(turns or e.turns, e.turns) end
            end
            if (e.status or 0) > 0 then status = e.status end
        elseif e.type == EFFECT_COVER then
            cover = true
            if (e.status or 0) > 0 then status = e.status end
            if (e.turns or 0) > 0 then turns = math.min(turns or e.turns, e.turns) end
        end
    end
    if (not through) and (not cover) then return nil end
    local scope = (row.target == SELF and "self") or (row.target == SINGLE and "one") or "all"
    return { through = through, cover = cover, status = status, turns = turns, scope = scope }
end

-- Status id to what it lets through, per kind, from every row that sets one.
function M.statusCuts(rows)
    local map = {}
    for _, row in pairs(rows or {}) do
        local status = nil
        for _, e in ipairs(row.effects or {}) do
            if (e.type == EFFECT_CUT) and ((e.status or 0) > 0) then status = e.status end
        end
        if status then
            map[status] = map[status] or {}
            for _, kind in ipairs({ PHYS, MAGIC }) do
                local through = nil
                for _, e in ipairs(row.effects) do
                    if e.type == EFFECT_CUT then
                        local share = cutOf(e, kind)
                        if share then through = (through or 1) * share end
                    end
                end
                if through then map[status][kind] = through end
            end
        end
    end
    return map
end

-- The share of a hit of this kind that gets through what's on this unit now.
function M.through(statuses, kind, map)
    local share = 1
    if not kind then return share end
    for id in pairs(statuses or {}) do
        local row = map and map[id]
        if row and row[kind] then share = share * row[kind] end
    end
    return share
end

local function dies(hp, hit)
    return hp <= (hit * MARGIN)
end

-- team: { id, hp, maxHp, hit (full size against this ally), share (what gets
-- through now), statuses, actsFirst (acts again before the hit), noSpell }.
-- option: { key, through, cover, status, turns, heal, scope, spell, cost }.
-- Returns the options that save someone, best first, each with its targets.
function M.rank(team, options, selfId, singleTarget)
    local me = nil
    for _, a in ipairs(team) do
        if a.id == selfId then me = a end
    end
    local function worth(opt, a)
        if a.hit <= 0 then return false, 0 end
        local before = a.hit * a.share
        local hp, after = a.hp, before
        if opt.heal then
            if opt.spell and a.noSpell then return false, 0 end
            hp = math.min(a.hp + opt.heal, a.maxHp or (a.hp + opt.heal))
        else
            if opt.status and a.statuses and a.statuses[opt.status] then return false, 0 end
            -- An effect that ends at the target's next action has to outlast it.
            if (opt.turns == 1) and a.actsFirst then return false, 0 end
            if opt.through then after = after * opt.through end
            if opt.cover then
                -- Covering is only counted on a hit aimed at one ally, and only
                -- when the one taking it lives through it.
                if (not singleTarget) or (not me) or (a.id == selfId) then return false, 0 end
                local mine = me.hit * me.share * (opt.through or 1)
                if dies(me.hp, mine) then return false, 0 end
                after = 0
            end
        end
        local saved = dies(a.hp, before) and (not dies(hp, after))
        local eased = (before - after) + (hp - a.hp)
        return saved, eased
    end
    local out = {}
    for _, opt in ipairs(options) do
        local targets, saved, eased = {}, 0, 0
        if opt.scope == "self" then
            if me then
                local s, e = worth(opt, me)
                targets[1], saved, eased = me.id, s and 1 or 0, e
            end
        elseif opt.scope == "one" then
            local bestS, bestE, bestId = false, -1, nil
            for _, a in ipairs(team) do
                local s, e = worth(opt, a)
                if (s and (not bestS)) or ((s == bestS) and (e > bestE)) then
                    bestS, bestE, bestId = s, e, a.id
                end
            end
            if bestId then targets[1], saved, eased = bestId, bestS and 1 or 0, bestE end
        else
            for _, a in ipairs(team) do
                local s, e = worth(opt, a)
                targets[#targets + 1] = a.id
                if s then saved = saved + 1 end
                eased = eased + e
            end
        end
        if saved > 0 then
            out[#out + 1] = { option = opt, targets = targets, saved = saved, eased = eased }
        end
    end
    table.sort(out, function(x, y)
        if x.saved ~= y.saved then return x.saved > y.saved end
        if x.eased ~= y.eased then return x.eased > y.eased end
        return (x.option.cost or 0) < (y.option.cost or 0)
    end)
    return out
end

-- How many of the team this hit would kill as things stand.
function M.lethal(team)
    local n = 0
    for _, a in ipairs(team) do
        if (a.hit > 0) and dies(a.hp, a.hit * a.share) then n = n + 1 end
    end
    return n
end

return M

-- Planner 2: hard rules. A rule only says no, with a reason. It never picks.
--
-- check(world, option) -> true | false, reason
-- The list follows AGENTS.md "Rules that keep the planner general". Rules
-- that need items, claims, or the round arrive with those layers; they are
-- listed at the bottom as TODO so the gap stays visible.

local M = {}
-- The caller sets M.E = effects.lua (no file paths inside modules).
local function E() return M.E end

-- FinishBlow and LimitBurst are matched by the numbers in world.attr, which
-- the caller fills from eSkillAttributeType (mucha_enums.hpp).
local RULES = {}

local function add(name, fn) RULES[#RULES + 1] = { name = name, fn = fn } end

-- Only CanUnitActivateSkill decides; IsEnableCommand read false for every
-- skill in game (probe v1.1).
add("the game says it can't be used now", function(w, o)
    local b = o.bar
    if b and b.canActivate == false then return false end
    return true
end)

add("not paid", function(w, o)
    local actor = w.snap.units[w.snap.actor]
    if actor and actor.mp and (o.cost or 0) > actor.mp then return false end
    return true
end)

add("no Finish Blow outside the Resonance phase", function(w, o)
    if w.attr and o.skill.attr == w.attr.FinishBlow and not w.snap.finish then return false end
    return true
end)

-- eSkillAttributeType 16 Escape; eSkillEffectType 5 Escape. v0.1.x's escape
-- policy (no boss, not a locked fight, after the party can't win) is not
-- here yet, so planner 2 never escapes.
add("no escape yet", function(w, o)
    if o.skill.attr == 16 or o.skill.effectType == 5 then return false end
    return true
end)

add("Limit Bursts wait for their layer", function(w, o)
    if w.attr and o.skill.attr == w.attr.LimitBurst then return false end
    return true
end)

add("no target on a body with no HP", function(w, o)
    if o.side == "dead" then return true end
    for _, t in ipairs(o.targets) do
        if (t.hp or 0) <= 0 and not o.skill.whenDead then return false end
    end
    return true
end)

add("a raise goes only to a fallen ally", function(w, o)
    if o.side ~= "dead" then return true end
    for _, t in ipairs(o.targets) do
        if (t.hp or 0) > 0 then return false end
    end
    return true
end)

-- AGENTS.md / design doc: the living come first. A raise waits while a
-- living ally is under 30% and not healed since the last hit (world.handled).
add("the living come first", function(w, o)
    if o.side ~= "dead" then return true end
    for _, u in ipairs(w.snap.party or {}) do
        local r = (u.hp or 0) / math.max(u.maxHp or 1, 1)
        if u.alive and r < 0.30 and not (w.summons and w.summons[u.uid])
            and not (w.handled and w.handled[u.uid]) then return false end
    end
    return true
end)

-- AGENTS.md: claims stop a second heal, a second revive, or a second Ether
-- in the same round. world.claims comes from round.lua.
add("claimed this round", function(w, o)
    local c = w.claims
    if not c then return true end
    if o.side == "dead" then
        for _, t in ipairs(o.targets) do if c.revive[t.uid] then return false end end
    elseif o.side == "ally" and (o.heal or (o.item and o.item.kind == "heal")) and not o.group then
        for _, t in ipairs(o.targets) do if c.heal[t.uid] then return false end end
    end
    return true
end)

add("a summon is not healed, raised, or cured", function(w, o)
    if o.side ~= "ally" or o.group then return true end
    for _, t in ipairs(o.targets) do
        if w.summons and w.summons[t.uid] then return false end
    end
    return true
end)

add("a nulled element or kind is a miss", function(w, o)
    if o.side ~= "foe" or o.group then return true end
    local c = E().contact(w, o.skill, o.targets[1])
    if not c.lands then return false end
    return true
end)

add("magic on a Reflect body bounces", function(w, o)
    if o.side ~= "foe" or o.group then return true end
    local c = E().contact(w, o.skill, o.targets[1])
    if c.bounces then return false end
    return true
end)

-- TODO with later layers: claims (second heal, raise, Ether in a round),
-- rare items outside a boss / dire need, tents and Healing Spring, Pot
-- fights, Vision ids not guessed from bar ids, Take it Easy = Attack only.

function M.check(world, option)
    for _, r in ipairs(RULES) do
        local ok = r.fn(world, option)
        if not ok then return false, r.name end
    end
    return true
end

function M.filter(world, options)
    local kept, dropped = {}, {}
    for _, o in ipairs(options) do
        local ok, why = M.check(world, o)
        if ok then kept[#kept + 1] = o else o.why = why; dropped[#dropped + 1] = o end
    end
    return kept, dropped
end

M.RULES = RULES
return M

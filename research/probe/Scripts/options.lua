-- Planner 2: every command the open menu could take, unranked.
--
-- options(world) -> list of { skill = <data.lua skill>, id, targets = {unit...},
--                             group = bool, side = "foe" | "ally" | "dead",
--                             item = <items.lua entry> or nil }
-- world = { snap = socket Snapshot, data = data.lua books, items = items.lua,
--           summons = { [uid] = true } }
--
-- Skills on the actor's bar: one option per single target, one per group or
-- all-target skill, revive skills on each fallen ally. Items: the item the
-- book (items.lua, the AGENTS.md item rules) picks for each need, as one
-- option per ally it could go to. No items in a Pot fight. Thrown items,
-- Limits, and Defend come later.

local M = {}

-- eSkillTargetType (mucha_enums.hpp): 0 Self, 1 Single, 2 Group, 3 Spread,
-- 4 All, 5 Random, 6 SkillTarget, 7 SingleAndGroup.
local T_SELF, T_SINGLE, T_GROUP, T_SPREAD, T_ALL, T_RANDOM, T_SINGLE_GROUP = 0, 1, 2, 3, 4, 5, 7
-- eRelation: 1 Friendlies, 2 Enemies. eSkillEffectType 20 Revival.
local R_FRIEND = 1
local EFF_REVIVAL = 20
-- eSkillEffectType 1 DamageAndRecovery, eUnitParameterType 1 HP,
-- eUnitParameterVariationType 0 Increase / 2 RatioIncrease.
local EFF_DMG_REC, PAR_HP = 1, 1

local function living(list, summons)
    local out = {}
    for _, u in ipairs(list or {}) do
        if u.alive and not u.missing and not (summons and summons[u.uid]) then out[#out + 1] = u end
    end
    return out
end

local function isRevive(s)
    return s.effectType == EFF_REVIVAL or s.targetState == 2 or s.whenDead == true
end

local function isHealSkill(s)
    return s.relation == R_FRIEND and s.effectType == EFF_DMG_REC and s.paramType == PAR_HP
        and (s.varType == 0 or s.varType == 2)
end

local function isAoe(s)
    return s.target == T_GROUP or s.target == T_SPREAD or s.target == T_ALL
end

-- The book's rows for what the bag holds (items.lua M.entry), with the
-- facts the game's own skill row gives.
local function owned(world)
    local snap, D, Items = world.snap, world.data, world.items
    local out = {}
    if not Items then return out end
    for id, count in pairs(snap.bag or {}) do
        local row = D and D.items[id]
        local s = row and row.skill and D.skills[row.skill]
        local f = {}
        if s then
            if isRevive(s) then f.revive = true end
            if s.relation == R_FRIEND and s.effectType == EFF_DMG_REC and s.paramType == PAR_HP
                and (s.varType == 0 or s.varType == 2) then f.rowHp = true end
            if s.relation == R_FRIEND and isAoe(s) then f.party = true end
        end
        local name = (snap.bagNames and snap.bagNames[id]) or ("item " .. id)
        local e = Items.entry(id, name, count, f)
        if e then e.skill = s; out[#out + 1] = e end
    end
    return out
end

function M.options(world)
    local snap, D = world.snap, world.data
    local actor = snap.units[snap.actor]
    local out = {}
    if not actor then return out end
    local foes, party = living(snap.foes), living(snap.party, world.summons)
    local dead = {}
    for _, u in ipairs(snap.dead or {}) do
        if not (world.summons and world.summons[u.uid]) then dead[#dead + 1] = u end
    end
    for _, b in ipairs(snap.bar or {}) do
        local s = D and D.skills[b.id]
        if s then
            local cost = b.cost or s.cost or 0
            if isRevive(s) then
                for _, t in ipairs(dead) do
                    out[#out + 1] = { skill = s, id = s.id, targets = { t }, side = "dead", cost = cost, bar = b }
                end
            else
                local rel = s.relation
                local pool = (rel == R_FRIEND) and party or foes
                local side = (rel == R_FRIEND) and "ally" or "foe"
                local heal = isHealSkill(s)
                if s.target == T_SINGLE or s.target == T_SINGLE_GROUP then
                    for _, t in ipairs(pool) do
                        out[#out + 1] = { skill = s, id = s.id, targets = { t }, side = side, cost = cost, bar = b, heal = heal }
                    end
                elseif s.target == T_GROUP or s.target == T_SPREAD or s.target == T_ALL or s.target == T_RANDOM then
                    if #pool > 0 then
                        out[#out + 1] = { skill = s, id = s.id, targets = pool, group = true, side = side, cost = cost, bar = b, heal = heal }
                    end
                elseif s.target == T_SELF then
                    out[#out + 1] = { skill = s, id = s.id, targets = { actor }, side = "ally", cost = cost, bar = b }
                end
            end
        end
    end
    -- Items, by the book's choice for each need. A Pot fight spends nothing.
    local Items = world.items
    if Items and not (Items.potFight and Items.potFight(snap.foes)) then
        local bag = owned(world)
        if #bag > 0 then
            local boss = snap.boss and true or false
            local crit, under = 0, 0
            for _, u in ipairs(party) do
                local r = (u.hp or 0) / math.max(u.maxHp or 1, 1)
                if r < 0.30 then crit = crit + 1 end
                if r < 0.50 then under = under + 1 end
            end
            -- AGENTS.md dire need: an ally down, an ally under 30%, or most
            -- of the living party under half.
            local dire = boss and (#dead > 0 or crit > 0 or under * 2 > #party)
            -- AGENTS.md: a rare item only when no common item does the job. With
            -- any common heal or raise item in the bag, rare ones aren't offered.
            local commonHeal, commonRaise = false, false
            for _, e in ipairs(bag) do
                if not e.rare then
                    if e.hp or e.kind == "heal" then commonHeal = true end
                    if e.kind == "revive" then commonRaise = true end
                end
            end
            local partyDone = false
            for _, t in ipairs(party) do
                local missing = (t.maxHp or 0) - (t.hp or 0)
                if missing > 0 then
                    local it = Items.recovery(bag, "heal", { boss = boss, dire = dire, missing = missing,
                        spread = under >= 2 })
                    if it and it.rare and commonHeal then it = nil end
                    if it and not (it.party and partyDone) then
                        if it.party then partyDone = true end
                        out[#out + 1] = { skill = it.skill or { id = it.id }, id = it.id, item = it, isItem = true,
                            targets = it.party and party or { t }, group = it.party and true or false,
                            side = "ally", cost = 0 }
                    end
                end
            end
            local raiseItem = Items.recovery(bag, "revive", { boss = boss })
            if raiseItem and raiseItem.rare and commonRaise then raiseItem = nil end
            if raiseItem then
                for _, t in ipairs(dead) do
                    out[#out + 1] = { skill = raiseItem.skill or { id = raiseItem.id }, id = raiseItem.id,
                        item = raiseItem, isItem = true, targets = { t }, side = "dead", cost = 0 }
                end
            end
        end
    end
    return out
end

M.isRevive = isRevive
M.isHealSkill = isHealSkill
return M

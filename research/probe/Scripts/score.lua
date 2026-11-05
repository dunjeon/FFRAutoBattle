-- Planner 2: the scorer. value = sum of weight x term, per option.
--
--   local P = score.new({ effects = E, rules = R, options = O, tactics = T })
--   local top = P.plan(world, learner, "balanced", 3)
--   -> { { option, value, terms = {...}, why = "..."}, ... }
--
-- world = { snap = socket Snapshot, data = data.lua books, attr = {...},
--           summons = { [uid] = true }, seenRes = learner.seenRes }
--
-- Terms (tactics.lua weights):
--   damage   share of the living field's HP this takes off
--   stagger  share of the target's gauge this pours (capped at what's left)
--   breakNow 1 when this empties a gauge (a bonus turn)
--   cancel   1 when that break lands on a body on the warning list
--   early    -1 when it breaks one gauge while another is over half full
--            and the target is not warned (the sync rule)
--   kill     share of the field this removes
--   heal     missing HP restored, weighted by how low the ally is
--   cost     -(MP spent / MP the actor has)
-- A term with no estimate is 0 and says so in `why`.

local M = {}

-- eSkillEffectType 1 DamageAndRecovery; eUnitParameterVariationType 0
-- Increase; eUnitParameterType 1 HitPoint.
local EFF_DMG_REC, VAR_INC, PAR_HP = 1, 0, 1

function M.new(mods)
    local E, R, O, T = mods.effects, mods.rules, mods.options, mods.tactics
    R.E = E
    local P = {}

    local function inList(list, x)
        for _, v in ipairs(list or {}) do if v == x then return true end end
        return false
    end

    local function foeHp(snap)
        local t = 0
        for _, u in ipairs(snap.foes) do if u.alive then t = t + (u.hp or 0) end end
        return t > 0 and t or 1
    end

    local function livingFoes(snap)
        local n = 0
        for _, u in ipairs(snap.foes) do if u.alive then n = n + 1 end end
        return n > 0 and n or 1
    end

    local function isHeal(s)
        return s.relation == 1 and s.effectType == EFF_DMG_REC and s.varType == VAR_INC and s.paramType == PAR_HP
    end

    -- Statuses a skill puts on its targets: the row's own status and each
    -- effect bundle's status. A bundle's targetRelation is not a side: it
    -- reads 1 (Friendlies) on Debrave and Poison too, which target enemies
    -- (DT_SkillData). The status lands where the skill lands.
    local function statusesOf(world, s, side)
        local out, D = {}, world.data
        if (s.status or 0) > 0 then out[#out + 1] = s.status end
        for _, b in ipairs(s.effects or {}) do
            local e = D and D.effects[b.effect]
            if e and (e.status or 0) > 0 then out[#out + 1] = e.status end
        end
        return out
    end

    -- Guards worth more while a warning is up: DefenceUp 25, MindUp 27,
    -- VeilDefenceUp 39, SuperiorGuard 43, MagicBarrier 59 (eUnitStatusCondition).
    local GUARD = { [25] = true, [27] = true, [39] = true, [43] = true, [59] = true }

    -- setup: a status that isn't already up. Buffs on allies are worth more
    -- on a hard field (boss or a warning up); debuffs and ailments on foes
    -- scale by the foe's own status resistance (0-100, DT_UnitParameter).
    local function setupValue(world, s, o)
        local snap, D = world.snap, world.data
        local hard = snap.boss or (#(snap.risk or {}) > 0)
        local v = 0
        local list = statusesOf(world, s, o.side)
        if #list == 0 then return 0 end
        if o.side == "ally" then
            local n = 0
            for _, u in ipairs(snap.party) do if u.alive and not (world.summons and world.summons[u.uid]) then n = n + 1 end end
            n = math.max(n, 1)
            for _, t in ipairs(o.targets) do
                for _, st in ipairs(list) do
                    local row = D.statuses[st]
                    local ok = E.statusGain(world, st, t.statuses or {})
                    if ok and row and not row.bad then
                        local x = 0.4
                        if hard then x = x * 2 end
                        if GUARD[st] and #(snap.risk or {}) > 0 then x = x * 1.5 end
                        v = v + x / n
                    end
                end
            end
        else
            local n = 0
            for _, u in ipairs(snap.foes) do if u.alive then n = n + 1 end end
            n = math.max(n, 1)
            for _, t in ipairs(o.targets) do
                local unit = t.unitId and D.units[t.unitId]
                for _, st in ipairs(list) do
                    local row = D.statuses[st]
                    local ok = E.statusGain(world, st, t.statuses or {})
                    if ok and row and (row.bad or row.debuff) then
                        local res = unit and unit.statusRes and unit.statusRes[st] or 0
                        local chance = math.max(0, 1 - (res or 0) / 100)
                        local x = (row.takesAction and 0.8) or (row.takesControl and 0.6) or (row.debuff and 0.5) or 0.3
                        if snap.boss then x = x * 1.5 end
                        for _, r in ipairs(snap.risk or {}) do if r == t.uid then x = x * 1.5 end end
                        v = v + x * chance / n
                    end
                end
            end
        end
        return v
    end

    function P.score(world, o, L)
        local snap, s = world.snap, o.skill
        local actor = snap.actor
        local terms = { damage = 0, stagger = 0, breakNow = 0, cancel = 0, early = 0, kill = 0, heal = 0, setup = 0, revive = 0, item = 0, cost = 0 }
        local notes = {}
        local hits = (s.hits and s.hits > 0) and s.hits or 1
        if o.side == "foe" then
            local total, nfoes = foeHp(snap), livingFoes(snap)
            for _, t in ipairs(o.targets) do
                local c = E.contact(world, s, t)
                if c.lands and not c.bounces then
                    local gl, gmax = t.gauge or 0, (t.maxGauge and t.maxGauge > 0) and t.maxGauge or 1
                    local per, src = E.staggerPerHit(L, s, actor, c.resistance)
                    local pour = per * hits
                    if gl > 0 and pour > 0 then
                        terms.stagger = terms.stagger + math.min(pour, gl) / gmax
                        if pour >= gl then
                            terms.breakNow = terms.breakNow + 1
                            if inList(snap.risk, t.uid) then
                                terms.cancel = terms.cancel + 1
                            else
                                for _, f in ipairs(snap.foes) do
                                    if f.uid ~= t.uid and f.alive and (f.maxGauge or 0) > 0
                                        and (f.gauge or 0) / f.maxGauge > 0.5 then
                                        terms.early = terms.early - 1
                                        break
                                    end
                                end
                            end
                        end
                    end
                    notes[#notes + 1] = string.format("stagger %s", src)
                    local dmg, dsrc = E.damagePerHit(L, s, actor, c.resistance, c.broken or (gl <= 0))
                    if dmg then
                        dmg = dmg * hits
                        local hp = t.hp or 0
                        terms.damage = terms.damage + math.min(dmg, hp) / total
                        if dmg >= hp and hp > 0 then terms.kill = terms.kill + 1 / nfoes end
                    end
                    notes[#notes + 1] = "damage " .. dsrc
                end
            end
        elseif o.side == "dead" then
            -- A fallen ally back: worth less while a living ally is critical
            -- and not healed since the last hit (AGENTS.md: the living first).
            local critical = false
            for _, u in ipairs(snap.party) do
                local r = (u.hp or 0) / math.max(u.maxHp or 1, 1)
                if u.alive and r < 0.30 and not (world.handled and world.handled[u.uid]) then critical = true end
            end
            terms.revive = critical and 0.3 or 1.0
            notes[#notes + 1] = critical and "revive, a living ally is critical" or "revive"
        elseif o.side == "ally" and (o.heal or isHeal(s) or (o.item and o.item.kind == "heal")) then
            local amount, hsrc = E.healPerHit(L, s, actor)
            for _, t in ipairs(o.targets) do
                local maxHp = (t.maxHp and t.maxHp > 0) and t.maxHp or 1
                local missing = maxHp - (t.hp or 0)
                local r = (t.hp or 0) / maxHp
                -- AGENTS.md: an ally under 30% is dire need.
                local danger = (r < 0.3 and 3) or (r < 0.5 and 1.5) or 0.5
                local got = amount and math.min(amount * hits, missing) or (missing * 0.5)
                terms.heal = terms.heal + danger * got / maxHp
            end
            notes[#notes + 1] = "heal " .. hsrc
        else
            terms.setup = setupValue(world, s, o)
            notes[#notes + 1] = terms.setup > 0 and "setup" or "no term for this effect yet"
        end
        if o.side == "foe" and terms.setup == 0 then terms.setup = setupValue(world, s, o) * 0.5 end
        -- An item spends the bag: a rare one costs more (the book only offers
        -- it under the AGENTS.md boss and dire-need rules).
        if o.item then terms.item = o.item.rare and -0.6 or -0.15 end
        local me = snap.units[actor]
        if me and (o.cost or 0) > 0 then
            terms.cost = -math.min(1, (o.cost or 0) / math.max(me.mp or 1, 1))
        end
        return terms, notes
    end

    function P.plan(world, L, tactic, n)
        local W = T[tactic or "balanced"] or T.balanced
        local opts = O.options(world)
        local kept, dropped = R.filter(world, opts)
        local scored = {}
        for _, o in ipairs(kept) do
            local terms, notes = P.score(world, o, L)
            local v = 0
            for k, x in pairs(terms) do v = v + (W[k] or 0) * x end
            scored[#scored + 1] = { option = o, value = v, terms = terms, notes = notes }
        end
        table.sort(scored, function(a, b)
            if a.value ~= b.value then return a.value > b.value end
            return a.option.id < b.option.id
        end)
        local top = {}
        for i = 1, math.min(n or 3, #scored) do top[i] = scored[i] end
        return top, { options = #opts, kept = #kept, dropped = dropped }
    end

    -- One line per choice for the log.
    function P.explain(entry, names)
        local o = entry.option
        local tgt = {}
        for _, t in ipairs(o.targets) do tgt[#tgt + 1] = tostring(t.uid) end
        local parts = {}
        local keys = {}
        for k, v in pairs(entry.terms) do if v ~= 0 then keys[#keys + 1] = k end end
        table.sort(keys)
        for _, k in ipairs(keys) do parts[#parts + 1] = string.format("%s %.2f", k, entry.terms[k]) end
        local name = (names and names[o.id]) or ("#" .. o.id)
        return string.format("%s -> %s%s  %.2f  [%s]", name, o.group and "all " or "", table.concat(tgt, ","),
            entry.value, table.concat(parts, ", "))
    end

    return P
end

return M

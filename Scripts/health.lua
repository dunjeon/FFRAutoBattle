-- Party health. The planner calls these. This file does not name a fight,
-- a character, or a Vision, and it does not touch the battle libraries.
--
-- A heavy danger gauge is one the book lists at 500 or more. Smaller danger
-- moves stay on the 50% recover line unless the fight itself is a boss.
-- Doom is cleared first. A status that takes the main healer's turn is
-- cleared next, item before spell. Sleep, paralysis, stop, petrify,
-- confuse, charm, and berserk are cleared before the recover line.
-- Silence on someone whose spells matter waits until nobody is critical.
-- Poison and blind are that ally's own item, and only when nothing more
-- urgent is waiting. Slow is a spare cure from the healer after it lasts
-- two rounds. The spell's row has to list Slow. A broken stat is still ignored.

local HEAVY = 500
local FIXED = 3
local POISON, BLIND = 1, 2
local SLEEP, SILENCE = 3, 4
local PARALYSIS, CONFUSE, PETRIFY, CHARM = 5, 6, 7, 8
local STOP, BERSERK, DOOM, SLOW = 9, 10, 11, 12
local FIGHT_ATTR, MAGIC_ATTR = 1, 4
local LOCK = {
    [SLEEP] = true, [SILENCE] = true, [PARALYSIS] = true, [CONFUSE] = true,
    [PETRIFY] = true, [CHARM] = true, [STOP] = true, [BERSERK] = true,
    [DOOM] = true,
}
-- These take the turn or hand it to the game. Silence does not: a silenced
-- healer can still use a potion.
local OUT = {
    [SLEEP] = true, [PARALYSIS] = true, [CONFUSE] = true, [PETRIFY] = true,
    [CHARM] = true, [STOP] = true, [BERSERK] = true,
}
local OUT_NAME = {
    [SLEEP] = "sleep", [PARALYSIS] = "paralysis", [CONFUSE] = "confuse", [PETRIFY] = "petrify",
    [CHARM] = "charm", [STOP] = "stop", [BERSERK] = "berserk",
}
-- Two misses, after the cast went out, mark that cure as not working.
-- One miss does not. A Slow that ends is not stored as a clear.
local SLOW_YES, SLOW_NO, SLOW_MISS = {}, {}, {}
-- Ids the planner already understands. Anything else is logged once.
local KNOWN = {
    [34] = true, [35] = true, [36] = true, [89] = true,
}
for id = 1, 12 do KNOWN[id] = true end

local M = {}
M.HEAVY = HEAVY
M.FIXED = FIXED
M.OUT = OUT

function M.recoverAt(boss, rows)
    local at, small = 0.50, false
    for _, row in ipairs(rows or {}) do
        if row.danger and (not row.empty) and (not row.broken) then
            if boss or ((row.gauge or 0) >= HEAVY) then
                at = 0.65
            else
                small = true
            end
        end
    end
    return at, small
end

-- A flat restore is the row's power when the calc type is Fixed. A magic
-- heal's power is a coefficient, not HP, so it keeps the power-per-MP rank.
-- need is how many hurt allies make a party heal the pick: most of the
-- living party, the same share at any size. It is 3 when not given.
function M.partyNeed(living)
    local n = tonumber(living) or 0
    return math.max(2, math.ceil(n * 0.75))
end

function M.spellRank(skill, missing, hurtN, party, need)
    need = need or 3
    -- With most of the party hurt, a party heal wins over every single heal,
    -- including a party row with no magnification. Among party heals the
    -- usual rank decides.
    if party and ((hurtN or 0) >= need) then
        local inner = M.spellRank(skill, missing, 0, false, need)
        return 1000 + inner
    end
    local cost = skill.cost or 0
    if cost < 1 then cost = 1 end
    local power = skill.power or 0
    local amount = nil
    if (skill.calc == FIXED) and (power > 0) then amount = power end
    if amount and missing and (missing > 0) then
        local r
        if amount >= missing then
            r = 2 + (missing / amount)
        else
            r = amount / (amount + missing)
        end
        if (hurtN >= need) and party then r = r * 3 end
        return r + (0.01 / cost)
    end
    if power > 0 then
        local r = power / cost
        if (hurtN >= need) and party then r = r * 3 end
        return r
    end
    if (hurtN >= need) and party then
        return 3 + (0.01 / cost)
    end
    if party then
        return 0.5 + (0.01 / cost)
    end
    return 1 + (0.01 / cost)
end

-- A healer first. On a threatened field (a boss, or a dangerous attack the
-- book lists), the ally whose kit pulls hits off the others (Provoke, Cover,
-- Multi-Cover) is next, the one with the most HP first. Then the kit with the
-- highest damage, then anyone who can act.
-- opts: threat (bool), guards (function(kit) -> bool), maxHpOf (function(id)).
function M.fallen(allies, kitOf, offenseOf, opts)
    opts = opts or {}
    local healer, healBest = nil, -1
    local guard, guardHp = nil, -1
    local dealer, dealBest = nil, -1
    local anyKit, anyBody = nil, nil
    for _, u in ipairs(allies or {}) do
        if u.dead then
            if u.acts ~= false then
                if not anyKit then anyKit = u end
            elseif not anyBody then
                anyBody = u
            end
            local kit = kitOf and kitOf(u.id) or nil
            local hs = (kit and kit.healScore) or 0
            if (hs >= 50) and (hs > healBest) then
                healer, healBest = u, hs
            end
            if opts.threat and opts.guards and (u.acts ~= false) and opts.guards(kit) then
                local mh = (opts.maxHpOf and opts.maxHpOf(u.id)) or 0
                if mh > guardHp then guard, guardHp = u, mh end
            end
            local dmg = 0
            if kit and offenseOf then
                for _, s in ipairs(kit.spells or {}) do
                    local kind = s.kind
                    if kind ~= "heal" and kind ~= "buff" and kind ~= "debuff"
                        and kind ~= "cure" and kind ~= "revive" and kind ~= "defend"
                        and kind ~= "scan" then
                        local power = offenseOf(s)
                        if power and (power > dmg) then dmg = power end
                    end
                end
            end
            if (dmg > 0) and (dmg > dealBest) then
                dealer, dealBest = u, dmg
            end
        end
    end
    if healer then return healer end
    if guard then return guard end
    if dealer then return dealer end
    return anyKit or anyBody
end

local function fold(name)
    local n = (name or ""):lower()
    n = n:gsub("’", "'"):gsub("‘", "'"):gsub("`", "'")
    return n
end

local function hasId(set, id)
    return (set and set[id]) and true or false
end

local function hasAny(set, ids)
    if not set then return false end
    for id in pairs(ids) do
        if set[id] then return true end
    end
    return false
end

local function realHeals(kit)
    local n = 0
    if not kit then return 0 end
    for _, s in ipairs(kit.spells or {}) do
        local patch = s.known and s.known.patch
        if (s.kind == "heal") and (not patch) then n = n + 1 end
    end
    return n
end

local function spellHeal(kit)
    if not kit then return false end
    for _, s in ipairs(kit.spells or {}) do
        if (s.kind == "heal") and not (s.known and s.known.patch) then return true end
    end
    return false
end

local function attackLean(kit)
    local phys, magic = 0, 0
    if not kit then return 0, 0 end
    for _, s in ipairs(kit.spells or {}) do
        if (s.kind == "damage") or (s.kind == nil) then
            local info = s.known
            local isPhys = (s.attr == FIGHT_ATTR) or (info and info.phys)
            local isMagic = (s.attr == MAGIC_ATTR) or (info and info.magic)
            if isPhys and (not isMagic) then phys = phys + 1
            elseif isMagic and (not isPhys) then magic = magic + 1 end
        end
    end
    return phys, magic
end

local function spellsMatter(kit)
    local _, magic = attackLean(kit)
    if magic > 0 then return true end
    if not kit then return false end
    for _, s in ipairs(kit.spells or {}) do
        if (s.kind == "heal") or (s.kind == "cure") or (s.kind == "revive") then
            return true
        end
    end
    return false
end

local function mostlyPhysical(kit)
    local phys, magic = attackLean(kit)
    return (phys > 0) and (phys > magic)
end

-- Living allies who can act, best heal score first. A tie goes to more
-- real heals. Equal kits stay together so neither waits on the other.
local function ranked(allies, kitOf)
    local bestScore, bestN, best = -1, -1, {}
    for _, a in ipairs(allies or {}) do
        if a and (not a.dead) and (a.acts ~= false) then
            local kit = kitOf and kitOf(a.id) or nil
            local score = (kit and kit.healScore) or 0
            if score >= 50 then
                local n = realHeals(kit)
                if (score > bestScore) or ((score == bestScore) and (n > bestN)) then
                    bestScore, bestN, best = score, n, { a }
                elseif (score == bestScore) and (n == bestN) then
                    best[#best + 1] = a
                end
            end
        end
    end
    return best
end

function M.mainHealer(allies, kitOf)
    local best = ranked(allies, kitOf)
    return best[1]
end

-- True when this ally can still deliver their heal. Sleep, paralysis,
-- petrify, confuse, charm, stop, and berserk take the turn. Silence blocks
-- a spell heal. A potion on their own turn is still allowed by the caller.
function M.available(ally, statuses, kitOf, mpOf)
    if (not ally) or ally.dead or (ally.acts == false) then return false end
    local set = statuses or ally.statuses
    local kit = kitOf and kitOf(ally.id) or nil
    if set then
        if hasAny(set, OUT) then return false end
        if set[SILENCE] and spellHeal(kit) then return false end
    end
    local cost = (kit and kit.healCost) or 0
    local mp = (mpOf and mpOf(ally.id)) or 0
    if (cost > 0) and (mp < cost) then return false end
    return true
end

-- The healer is the living ally who can act and whose kit has the highest
-- heal score. A tied score goes to the kit with more real heals. A weaker
-- heal, such as one Cure beside a fuller kit, waits with the damage dealers.
-- On a critical ally the others step in under 15%, or under 20% while a
-- danger gauge is open. A slowed main healer is late, so those lines are
-- 25% and 30%. Above that they leave the heal for the whole round while
-- that healer can still act and pay. On the recover line, once two others
-- have acted and the slowed healer has not, the wait ends. A healer who is
-- out of MP, or stopped by a status, does not hold the line. A healer who
-- is out of MP still spends a potion on their own turn.
function M.healerWaiting(actorId, why, ratio, danger, allies, kitOf, mpOf, went)
    local best = ranked(allies, kitOf)
    if #best == 0 then return false end
    for _, a in ipairs(best) do
        if a.id == actorId then return false end
    end
    -- A healer who already took this round's turn will not get there before
    -- the enemies act again, so a critical ally is not left to them.
    local payable, still = false, false
    for _, a in ipairs(best) do
        if M.available(a, a.statuses, kitOf, mpOf) then
            payable = true
            if not (went and went[a.id]) then still = true end
        end
    end
    if not payable then return false end
    if (why == "critical") and (not still) then return false end
    local healer = best[1]
    local late = healer and hasId(healer.statuses, SLOW)
    if why ~= "critical" then
        if late and went and (not went[healer.id]) then
            local others = 0
            for id, on in pairs(went) do
                if on and (id ~= healer.id) then others = others + 1 end
            end
            if others >= 2 then return false end
        end
        return true
    end
    local dire = 0.15
    if danger then dire = 0.20 end
    if late then
        dire = 0.25
        if danger then dire = 0.30 end
    end
    if (ratio or 1) < dire then return false end
    return true
end

local function pack(ally, tier, itemFirst, itemOnly, soft)
    return {
        id = ally.id,
        name = ally.name,
        statuses = ally.statuses,
        tier = tier,
        itemFirst = itemFirst and true or false,
        itemOnly = itemOnly and true or false,
        soft = soft and true or false,
    }
end

-- One line for what the party brought in. A downed ally and a lock are
-- named. A status this file does not rank is left off the line.
function M.entryNote(allies)
    local bits = {}
    for _, a in ipairs(allies or {}) do
        local name = a.name or "?"
        if a.dead then
            bits[#bits + 1] = name .. " down"
        elseif a.statuses then
            if hasId(a.statuses, DOOM) then bits[#bits + 1] = name .. " doom" end
            for id, label in pairs(OUT_NAME) do
                if a.statuses[id] then bits[#bits + 1] = name .. " " .. label end
            end
            if hasId(a.statuses, SILENCE) then bits[#bits + 1] = name .. " silence" end
            if hasId(a.statuses, POISON) then bits[#bits + 1] = name .. " poison" end
            if hasId(a.statuses, BLIND) then bits[#bits + 1] = name .. " blind" end
            if hasId(a.statuses, SLOW) then bits[#bits + 1] = name .. " slow" end
        end
    end
    if #bits == 0 then return nil end
    return "entry: " .. table.concat(bits, ", ")
end

-- Urgent cures are doom, a healer who cannot act, and the other locks.
-- Poison and blind are the actor's own item after that, and only when
-- nothing more urgent is waiting. Slow is chosen by slowFocus.
function M.cureNow(allies, kitOf, mpOf, ctx)
    ctx = ctx or {}
    local urgent = ctx.urgent ~= false
    local best = ranked(allies, kitOf)
    local healer = best[1]
    if urgent then
        local doomAct, doomBody = nil, nil
        for _, a in ipairs(allies or {}) do
            if (not a.dead) and hasId(a.statuses, DOOM) then
                if a.acts ~= false then doomAct = doomAct or a
                else doomBody = doomBody or a end
            end
        end
        local doom = doomAct or doomBody
        if doom then return pack(doom, "doom", false, false, false) end
        if healer and hasAny(healer.statuses, OUT) then
            return pack(healer, "rescue", true, false, false)
        end
        local function silenceOk(a)
            if not hasId(a.statuses, SILENCE) then return false end
            if ctx.critical then return false end
            local kit = kitOf and kitOf(a.id) or nil
            return spellsMatter(kit)
        end
        local function stopped(a)
            return hasAny(a.statuses, OUT)
        end
        local held, acting, body, silHealer, sil = nil, nil, nil, nil, nil
        for _, a in ipairs(allies or {}) do
            if (not a.dead) and a.statuses then
                if stopped(a) then
                    if a.acts ~= false then acting = acting or a
                    else body = body or a end
                elseif silenceOk(a) then
                    if healer and (a.id == healer.id) then silHealer = a
                    else sil = sil or a end
                end
            end
        end
        held = acting or body
        if held then return pack(held, "a", false, false, false) end
        if silHealer then return pack(silHealer, "a", true, true, false) end
        if sil then return pack(sil, "a", false, false, false) end
        return nil
    end
    if ctx.critical or ctx.dead or ctx.under or ctx.setup then return nil end
    local actor = nil
    for _, a in ipairs(allies or {}) do
        if a.id == ctx.actorId then actor = a end
    end
    if (not actor) or actor.dead or (actor.acts == false) or (not actor.statuses) then
        return nil
    end
    if hasId(actor.statuses, POISON) and ((actor.hp or 1) < 0.60) then
        return pack(actor, "b", true, true, true)
    end
    if hasId(actor.statuses, BLIND) then
        local kit = kitOf and kitOf(actor.id) or nil
        if mostlyPhysical(kit) then return pack(actor, "b", true, true, true) end
    end
    return nil
end

-- MP left after the cure is still above half, and a heal is kept back
-- when keep is the healer's heal cost.
function M.spareMp(mp, maxMp, cost, keep)
    local left = (mp or 0) - (cost or 0)
    if left < (keep or 0) then return false end
    if (not maxMp) or (maxMp <= 0) then return false end
    return (left / maxMp) > 0.50
end

function M.slowKey(kind, name)
    return (kind or "skill") .. ":" .. fold(name or "")
end

function M.slowVerdict(key)
    if SLOW_YES[key] then return "yes" end
    if SLOW_NO[key] then return "no" end
    return nil
end

-- One try per fight until this launch knows the result. A cure that works
-- can be used again. Two misses, after the cast went out, finish it.
function M.slowAllowed(key, used)
    local verdict = M.slowVerdict(key)
    if verdict == "no" then return false end
    if used and (verdict ~= "yes") then return false end
    return true
end

-- Remember the round Slow was first seen. A status that has dropped is
-- forgotten, so a later Slow starts its wait over.
function M.watchSlow(allies, since, round)
    since = since or {}
    local live = {}
    for _, a in ipairs(allies or {}) do
        if a and (not a.dead) and hasId(a.statuses, SLOW) then
            live[a.id] = true
            if since[a.id] == nil then since[a.id] = round or 0 end
        end
    end
    local drop = {}
    for id in pairs(since) do
        if not live[id] then drop[#drop + 1] = id end
    end
    for _, id in ipairs(drop) do since[id] = nil end
    return since
end

-- True when this cure row lists Slow. A cure that only lists other
-- statuses is not spent on Slow, so a miss is not learned for it.
function M.listsSlow(skill)
    local st = skill and skill.friendStatus
    return (st and st[SLOW]) and true or false
end

-- The ally the result is read from. A missing ratio means the body was
-- not readable, so the try stays open.
function M.slowAlly(id, ratio, set)
    if (id == nil) or (ratio == nil) then return {} end
    return {
        { id = id, dead = ratio <= 0, statuses = set },
    }
end

-- The command was accepted. An MP drop of at least the cost means the
-- cast went out. Dead, silenced, or unable to act, with no drop, means
-- it did not. A cast that is only queued stays open. When that caster is
-- asked to act again and the cost has not been paid, it did not go out.
function M.watchSlowCast(try, caster)
    if (not try) or try.out then return try, nil end
    if not caster then return try, nil end
    local cost = try.cost or 0
    local mp = caster.mp
    if (cost > 0) and (type(mp) == "number") and (type(try.mp) == "number") and (mp <= (try.mp - cost)) then
        try.out = true
        return try, nil
    end
    if caster.dead or hasId(caster.statuses, SILENCE) or hasAny(caster.statuses, OUT) then
        return nil, "slow cure did not go out"
    end
    if cost <= 0 then
        try.out = true
        return try, nil
    end
    if (caster.actor ~= nil) and (caster.actor == try.caster) then
        return nil, "slow cure did not go out"
    end
    return try, nil
end

-- The cure went out on an earlier round. Slow still on is one miss. The
-- second miss marks it for this launch. Slow ending is not proof the cure
-- did it, so that is not remembered. A cast that has not gone out stays open.
function M.settleSlow(try, allies, told)
    if not try then return nil, told, nil end
    local who = nil
    for _, a in ipairs(allies or {}) do
        if a.id == try.id then who = a end
    end
    if not who then return try, told, nil end
    if who.dead then return nil, told, nil end
    if not try.out then return try, told, nil end
    told = told or {}
    local still = hasId(who.statuses, SLOW)
    local key = try.key
    local line = nil
    if key then
        if still then
            local n = (SLOW_MISS[key] or 0) + 1
            SLOW_MISS[key] = n
            if n >= 2 then
                SLOW_NO[key] = true
                SLOW_YES[key] = nil
            end
            local mark = (try.name or "cure") .. ((n >= 2) and " remains" or " remains once")
            if not told[mark] then
                told[mark] = true
                if n >= 2 then
                    line = "slow remains after " .. (try.name or "cure")
                else
                    line = "slow remains after " .. (try.name or "cure") .. ", once"
                end
            end
        else
            SLOW_MISS[key] = nil
            local mark = (try.name or "cure") .. " gone"
            if not told[mark] then
                told[mark] = true
                line = "slow gone after " .. (try.name or "cure")
            end
        end
    end
    return nil, told, line
end

-- Once per fight, when Slow is ready to be cured and no living ally has a
-- cure spell whose row lists it.
function M.slowGap(allies, kitOf, told)
    for _, a in ipairs(allies or {}) do
        if a and (not a.dead) then
            local kit = kitOf and kitOf(a.id)
            local spells = (kit and kit.spells) or {}
            for _, s in ipairs(spells) do
                if (s.kind == "cure") and M.listsSlow(s) then return nil end
            end
        end
    end
    told = told or {}
    if told.gap then return nil end
    told.gap = true
    return "slow cure skipped, no skill lists slow"
end

-- The healer clears Slow on their own turn, after it has lasted two
-- rounds. Order is self, then the weakness payer or the stagger
-- finisher, then anyone else. A non-healer casts only when no healer can
-- act, and only for those three value cases.
function M.slowFocus(allies, kitOf, mpOf, ctx)
    ctx = ctx or {}
    if ctx.critical or ctx.dead or ctx.under or ctx.setup then return nil end
    local since = ctx.since or {}
    local round = ctx.round or 0
    local function waited(a)
        if (not a) or a.dead or (not hasId(a.statuses, SLOW)) then return false end
        local at = since[a.id]
        if at == nil then return false end
        return round >= (at + 2)
    end
    local function byId(id)
        if not id then return nil end
        for _, a in ipairs(allies or {}) do
            if a.id == id then return a end
        end
        return nil
    end
    local best = ranked(allies, kitOf)
    local healer = best[1]
    local healerUp = false
    for _, a in ipairs(best) do
        if M.available(a, a.statuses, kitOf, mpOf) and (not hasId(a.statuses, SILENCE)) then
            healerUp = true
        end
    end
    local actor = nil
    for _, a in ipairs(allies or {}) do
        if a.id == ctx.actorId then actor = a end
    end
    if (not actor) or actor.dead or (actor.acts == false) then return nil end
    if hasId(actor.statuses, SILENCE) then return nil end
    local actorIsHealer = false
    for _, a in ipairs(best) do
        if a.id == ctx.actorId then actorIsHealer = true end
    end
    local payer = byId(ctx.weakId)
    local fin = byId(ctx.stagId)
    if actorIsHealer then
        if waited(actor) then return pack(actor, "slow", false, false, false) end
        if waited(payer) then return pack(payer, "slow", false, false, false) end
        if fin and waited(fin) and ((not payer) or (fin.id ~= payer.id)) then
            return pack(fin, "slow", false, false, false)
        end
        for _, a in ipairs(allies or {}) do
            if waited(a) then
                local skip = (a.id == actor.id)
                if payer and (payer.id == a.id) then skip = true end
                if fin and (fin.id == a.id) then skip = true end
                if not skip then return pack(a, "slow", false, false, false) end
            end
        end
        return nil
    end
    if healerUp then return nil end
    if healer and waited(healer) then return pack(healer, "slow", false, false, false) end
    if waited(payer) then return pack(payer, "slow", false, false, false) end
    if waited(fin) then return pack(fin, "slow", false, false, false) end
    return nil
end

-- One line per unknown id. told remembers what this fight already wrote.
function M.unknownNotes(allies, told)
    told = told or {}
    local lines = {}
    for _, a in ipairs(allies or {}) do
        if (not a.dead) and a.statuses then
            for id in pairs(a.statuses) do
                if (not KNOWN[id]) and (not told[id]) then
                    told[id] = true
                    lines[#lines + 1] = string.format(
                        "status %s on %s", tostring(id), a.name or "?")
                end
            end
        end
    end
    return lines
end

function M.locked(allies)
    local acting, body = nil, nil
    for _, u in ipairs(allies or {}) do
        if (not u.dead) and u.statuses then
            local hit = false
            for id in pairs(LOCK) do
                if u.statuses[id] then hit = true end
            end
            if hit then
                if u.statuses[SILENCE] and (u.acts ~= false) then return u end
                if u.acts ~= false then
                    if not acting then acting = u end
                elseif not body then
                    body = u
                end
            end
        end
    end
    return acting or body
end

-- Dire need in a boss fight: an ally is down, an ally is under 30%, or most
-- of the living party is under half. Lifts the one-Ether-per-round limit.
function M.direNeed(w)
    if not (w and w.boss) then return false end
    local living, low = 0, 0
    for _, u in ipairs(w.allies or {}) do
        if u.dead then return true end
        living = living + 1
        local r = u.hp or 1
        if r < 0.30 then return true end
        if r < 0.50 then low = low + 1 end
    end
    return living > 0 and (low * 2) > living
end

return M

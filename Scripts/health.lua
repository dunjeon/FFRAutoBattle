-- Party health. The planner calls these. This file does not name a fight,
-- a character, or a Vision, and it does not touch the battle libraries.
--
-- A heavy danger gauge is one the book lists at 500 or more. Smaller danger
-- moves stay on the 50% recover line unless the fight itself is a boss.
-- Doom is cleared first. A status that takes the main healer's turn is
-- cleared next, item before spell. Sleep, paralysis, stop, petrify,
-- confuse, charm, and berserk are cleared before the recover line.
-- Silence on someone whose spells matter waits until nobody is critical.
-- Poison, blind, and slow are cleared only when nothing more urgent is
-- waiting. A broken stat is still ignored.

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
local SOFT = { [POISON] = true, [BLIND] = true, [SLOW] = true }
-- Ids the planner already understands. Anything else is logged once.
local KNOWN = {
    [34] = true, [35] = true, [36] = true, [89] = true,
}
for id = 1, 12 do KNOWN[id] = true end

-- Shop cures and the status they clear. Remedy clears a lock only.
-- It does not clear poison, blind, or slow. A name that is not here still
-- qualifies, so a new shop cure is not dropped.
local CURE_ITEM = {
    antidote = { [POISON] = true },
    ["antidote herb"] = { [POISON] = true },
    ["eye drops"] = { [BLIND] = true },
    ["echo herb"] = { [SILENCE] = true },
    ["smelling salts"] = { [CONFUSE] = true },
    ["unicorn horn"] = { [PARALYSIS] = true },
    ["gold needle"] = { [PETRIFY] = true },
    ["herb of awakening"] = { [SLEEP] = true },
    remedy = true,
}

local M = {}
M.HEAVY = HEAVY
M.FIXED = FIXED

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
function M.spellRank(skill, missing, hurtN, party)
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
        if (hurtN >= 3) and party then r = r * 3 end
        return r + (0.01 / cost)
    end
    if power > 0 then
        local r = power / cost
        if (hurtN >= 3) and party then r = r * 3 end
        return r
    end
    if (hurtN >= 3) and party then
        return 3 + (0.01 / cost)
    end
    if party then
        return 0.5 + (0.01 / cost)
    end
    return 1 + (0.01 / cost)
end

-- Smallest potion that covers the gap. If none covers, the largest amount.
-- No readable amount keeps the first matching item.
function M.choosePotion(items, missing)
    local first, cover, coverAmt, best, bestAmt = nil, nil, nil, nil, -1
    for _, it in ipairs(items or {}) do
        if it.hp or it.kind == "heal" then
            if not first then first = it end
            local amount = it.amount
            if amount and (amount > 0) and missing and (missing > 0) then
                if (amount >= missing) and ((not cover) or (amount < coverAmt)) then
                    cover, coverAmt = it, amount
                end
                if amount > bestAmt then best, bestAmt = it, amount end
            end
        end
    end
    if cover then return cover end
    if best then return best end
    return first
end

-- A healer first, then the kit with the highest damage, then anyone who can act.
function M.fallen(allies, kitOf, offenseOf)
    local healer, healBest = nil, -1
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

-- True when this item can clear a status that is on the ally right now.
-- Soft statuses (poison, blind, slow) qualify only when the caller is on
-- that line. Remedy never qualifies for them.
function M.itemClears(name, statuses, soft)
    local row = CURE_ITEM[fold(name)]
    if row == nil then return true end
    if row == false then return false end
    if not statuses then return false end
    if row == true then
        for id in pairs(LOCK) do
            if statuses[id] then return true end
        end
        return false
    end
    for id in pairs(row) do
        if statuses[id] then
            if LOCK[id] then return true end
            if soft and SOFT[id] then return true end
        end
    end
    return false
end

-- The last Remedy stays for doom, or for a lock on the main healer.
function M.holdRemedy(name, count, target, allies, kitOf)
    if fold(name) ~= "remedy" then return false end
    if (not count) or (count > 1) then return false end
    if target and hasId(target.statuses, DOOM) then return false end
    local healer = M.mainHealer(allies, kitOf)
    if healer and target and (healer.id == target.id) and hasAny(target.statuses, LOCK) then
        return false
    end
    for _, a in ipairs(allies or {}) do
        if (not a.dead) and hasId(a.statuses, DOOM) then return true end
    end
    if healer and (not healer.dead) and hasAny(healer.statuses, LOCK) then
        return true
    end
    return false
end

-- The healer is the living ally who can act and whose kit has the highest
-- heal score. A tied score goes to the kit with more real heals. A weaker
-- heal, such as one Cure beside a fuller kit, waits with the damage dealers.
-- On a critical ally the others step in under 15%, or under 20% while a
-- danger gauge is open. Above that they leave the heal for the whole round
-- while that healer can still act and pay. A healer who is out of MP, or
-- stopped by a status, does not hold the line. On the recover line the
-- others do not spend a heal or a potion while that healer can act and pay.
-- A healer who is out of MP still spends a potion on their own turn.
function M.healerWaiting(actorId, why, ratio, danger, allies, kitOf, mpOf)
    local best = ranked(allies, kitOf)
    if #best == 0 then return false end
    for _, a in ipairs(best) do
        if a.id == actorId then return false end
    end
    local payable = false
    for _, a in ipairs(best) do
        if M.available(a, a.statuses, kitOf, mpOf) then payable = true end
    end
    if not payable then return false end
    if why ~= "critical" then return true end
    local dire = 0.15
    if danger then dire = 0.20 end
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

-- Urgent cures are doom, a healer who cannot act, and the other locks.
-- The soft line is poison, blind, and slow, and only when nothing more
-- urgent is waiting. A non-healer does not spend that line while a healer
-- can still act and pay.
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
    if ctx.critical then return nil end
    if ctx.band == "low" then return nil end
    local actorIsHealer = false
    for _, a in ipairs(best) do
        if a.id == ctx.actorId then actorIsHealer = true end
    end
    if not actorIsHealer then
        for _, a in ipairs(best) do
            if M.available(a, a.statuses, kitOf, mpOf) then return nil end
        end
    end
    local function softHit(a)
        if a.dead or (not a.statuses) then return false end
        if hasId(a.statuses, POISON) then
            if ((a.hp or 1) < 0.60) or (healer and (a.id == healer.id)) then
                return true
            end
        end
        if hasId(a.statuses, BLIND) then
            local kit = kitOf and kitOf(a.id) or nil
            if mostlyPhysical(kit) then return true end
        end
        if hasId(a.statuses, SLOW) and (ctx.band == "high") then return true end
        return false
    end
    local softHealer, softAct, softBody = nil, nil, nil
    for _, a in ipairs(allies or {}) do
        if softHit(a) then
            if healer and (a.id == healer.id) then softHealer = a
            elseif a.acts ~= false then softAct = softAct or a
            else softBody = softBody or a end
        end
    end
    local soft = softHealer or softAct or softBody
    if soft then return pack(soft, "b", false, false, true) end
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

return M

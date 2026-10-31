-- Party health. The planner calls these. This file does not name a fight,
-- a character, or a Vision, and it does not touch the battle libraries.
--
-- A heavy danger gauge is one the book lists at 500 or more. Smaller danger
-- moves stay on the 50% recover line unless the fight itself is a boss.
-- Poison, blind, and stat-broken are not locks. Stop is. Silence on someone
-- who can still cast is cured before the other locks.

local HEAVY = 500
local FIXED = 3
local SLEEP = 3
local SILENCE = 4
local LOCK = {
    [3] = true, [4] = true, [5] = true, [6] = true, [7] = true,
    [8] = true, [9] = true, [10] = true, [11] = true,
}
-- Shop cures and the lock they clear. Poison and blind are not locks, so
-- those items never qualify. Remedy clears any lock. A name that is not
-- here still qualifies, so a new shop cure is not dropped.
local CURE_ITEM = {
    antidote = false,
    ["antidote herb"] = false,
    ["eye drops"] = false,
    ["echo herb"] = { [SILENCE] = true },
    ["smelling salts"] = { [6] = true },
    ["unicorn horn"] = { [5] = true },
    ["gold needle"] = { [7] = true },
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

-- True when this item can clear a lock that is on the ally right now.
function M.itemClears(name, statuses)
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
        if statuses[id] and LOCK[id] then return true end
    end
    return false
end

-- The healer is the living ally who can act and whose kit has the highest
-- heal score. A tied score goes to the kit with more real heals. A weaker
-- heal, such as one Cure beside a fuller kit, waits with the damage dealers.
-- On a critical ally the others step in under 15%, or under 20% while a
-- danger gauge is open. Above that they leave the heal for the whole round
-- while that healer can pay. On the recover line they do not spend a heal
-- or a potion while that healer can pay. A healer who is out of MP still
-- spends a potion on their own turn.
function M.healerWaiting(actorId, why, ratio, danger, allies, kitOf, mpOf)
    local function weight(a)
        if (not a) or a.dead or (a.acts == false) then return nil end
        local kit = kitOf and kitOf(a.id) or nil
        if (not kit) or ((kit.healScore or 0) < 50) then return nil end
        local n = 0
        for _, s in ipairs(kit.spells or {}) do
            local patch = s.known and s.known.patch
            if (s.kind == "heal") and (not patch) then n = n + 1 end
        end
        return kit.healScore, n
    end
    local function pays(a)
        local kit = kitOf and kitOf(a.id) or nil
        local cost = (kit and kit.healCost) or 0
        local mp = (mpOf and mpOf(a.id)) or 0
        return (cost <= 0) or (mp >= cost)
    end
    local bestScore, bestN, best = -1, -1, {}
    for _, a in ipairs(allies or {}) do
        local score, n = weight(a)
        if score then
            if (score > bestScore) or ((score == bestScore) and (n > bestN)) then
                bestScore, bestN, best = score, n, { a }
            elseif (score == bestScore) and (n == bestN) then
                best[#best + 1] = a
            end
        end
    end
    if #best == 0 then return false end
    for _, a in ipairs(best) do
        if a.id == actorId then return false end
    end
    local payable = false
    for _, a in ipairs(best) do
        if pays(a) then payable = true end
    end
    if not payable then return false end
    if why ~= "critical" then return true end
    local dire = 0.15
    if danger then dire = 0.20 end
    if (ratio or 1) < dire then return false end
    return true
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

-- Party health. The planner calls these. This file does not name a fight,
-- a character, or a Vision, and it does not touch the battle libraries.
--
-- A heavy danger gauge is one the book lists at 500 or more. Smaller danger
-- moves stay on the 50% recover line unless the fight itself is a boss.
-- Poison, blind, and stat-broken are not locks. Stop is. Silence on someone
-- who can still cast is cured before the other locks.

local HEAVY = 500
local FIXED = 3
local SILENCE = 4
local LOCK = {
    [3] = true, [4] = true, [5] = true, [6] = true, [7] = true,
    [8] = true, [9] = true, [10] = true, [11] = true,
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

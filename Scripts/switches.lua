-- The per-category battle switches in config.ini. No Mercy only.
--   auto  the plan uses that kind of command as it always has.
--   off   the plan plays as if the party held none of it.
--   hand  when the plan picks it, the menu is left to the player.
-- A command's category comes from its row: attr, effect ids, target side,
-- power. Nothing here names a skill, an item, a character, or a fight.
-- A plain hit has no category, so Attack is always there.

local M = {}

M.NAMES = { "Limits", "Heals", "Raises", "Buffs", "Debuffs", "Guards", "Items", "Scan", "Escape" }
M.VALUES = { auto = true, off = true, hand = true }
-- hand has no meaning for these: the plan picks them where no one else would.
M.NO_HAND = { Escape = true }

local A = { FIGHT = 1, LB = 5, ITEM = 6, SUMMON = 7, FINISH = 9, THROW = 11, THROW_MONEY = 12, ESCAPE = 16 }
local E = { ANALYZE = 29, COVER = 41, HATE = 99, MOGSCAN = 142 }
local FRIEND, ENEMY = 1, 2

-- A config value, folded. Returns the value and true, or "auto" and false
-- when the line holds something else.
function M.parse(name, value)
    local v = tostring(value or ""):lower():match("^%s*(.-)%s*$")
    if v == "" then return "auto", true end
    if not M.VALUES[v] then return "auto", false end
    if (v == "hand") and M.NO_HAND[name] then return "auto", false end
    return v, true
end

local function hasEffect(s, t)
    if s.effect == t then return true end
    for _, e in ipairs(s.effects or {}) do
        if e.type == t then return true end
    end
    return false
end

-- Damage or stagger on a foe. A heal is a friend-side hit and is read first.
local function hits(s)
    if s.rel == FRIEND then return false end
    return ((s.power or 0) > 0) or ((s.breakPower or 0) > 0)
end

-- The category of a skill row, after classify set s.kind. nil: no switch
-- covers it (a plain hit, an Esper, a Vision finish).
function M.categoryOf(s)
    if type(s) ~= "table" then return nil end
    local a = s.attr
    if a == A.LB then return "Limits" end
    if a == A.SUMMON or a == A.FINISH or a == A.FIGHT then return nil end
    if a == A.ESCAPE then return "Escape" end
    if a == A.ITEM or a == A.THROW or a == A.THROW_MONEY then return "Items" end
    local k = s.kind
    if k == "revive" then return "Raises" end
    if k == "heal" or k == "cure" then return "Heals" end
    if k == "defend" or hasEffect(s, E.COVER) or (hasEffect(s, E.HATE) and not hits(s)) then return "Guards" end
    if hits(s) then return nil end
    if hasEffect(s, E.ANALYZE) or hasEffect(s, E.MOGSCAN) then return "Scan" end
    if k == "debuff" or s.rel == ENEMY then return "Debuffs" end
    if k == "buff" or s.rel == FRIEND then return "Buffs" end
    return nil
end

-- An item is an Item, and a Heal or a Raise too when that is what it does.
-- use is the planner's want: "heal", "hp", "both", "cure", "revive", "mp", "attack".
function M.itemCategories(use)
    local out = { "Items" }
    if use == "heal" or use == "hp" or use == "both" or use == "cure" then out[2] = "Heals" end
    if use == "revive" then out[2] = "Raises" end
    return out
end

-- The strongest setting over a list of categories: off, then hand, then auto.
-- Returns the setting and the category that set it.
function M.verdict(cfg, cats)
    local rank = { auto = 0, hand = 1, off = 2 }
    local best, by = "auto", nil
    for _, c in ipairs(cats or {}) do
        local v = (cfg and cfg[c]) or "auto"
        if (rank[v] or 0) > rank[best] then best, by = v, c end
    end
    return best, by
end

function M.off(cfg, cats)
    return (M.verdict(cfg, cats)) == "off"
end

-- "Heals off, Limits hand", or nil when every switch is auto.
function M.summary(cfg)
    local bits = {}
    for _, name in ipairs(M.NAMES) do
        local v = cfg and cfg[name]
        if v and v ~= "auto" then bits[#bits + 1] = name .. " " .. v end
    end
    if #bits == 0 then return nil end
    return table.concat(bits, ", ")
end

return M

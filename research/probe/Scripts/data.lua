-- Planner 2, Phase 1: the game's own tables, by id.
--
-- Built once per launch from the DataTables the game has loaded, the same
-- walk v0.1.x already does for SKILL_DATA (FindAllOf("DataTable"),
-- GetRowStruct, ForEachRow). No game data is stored in the repo; this reads
-- the player's copy.
--
-- The module never touches UE4SS directly. The caller hands it a source:
--   source.tables(structName)  -> list of tables, each a function(cb) that
--                                 calls cb(rowKey, row) for every row
--   source.get(row, field)     -> the field's value (numbers for enums), or nil
--   source.each(list, cb)      -> calls cb(i, value) for an array field
--   source.pairs(map, cb)      -> calls cb(key, value) for a map field
--   source.text(v)             -> a string for an FName/FText/string, or nil
-- In the game, socket code builds it from live rows. In tests it is built
-- from the offline JSON dump (research/planner2/test_data.lua).
--
-- Enum values are the game's (mucha_enums.hpp): eElement 0 None, 1 Fire,
-- 2 Ice, 3 Wind, 4 Earth, 5 Thunder, 6 Water, 7 Light, 8 Dark;
-- eResistance 0 None, 1 Weakness, 2 Halved, 3 Invalid, 4 Absorb, 5 Reflect.

local M = {}

M.ELEMENT = { [0] = "none", "fire", "ice", "wind", "earth", "thunder", "water", "light", "dark" }
M.RESIST = { [0] = "none", "weak", "halved", "invalid", "absorb", "reflect" }

local function num(v)
    if type(v) == "number" then return v end
    if type(v) == "boolean" then return v and 1 or 0 end
    return nil
end

local function bool(v)
    if type(v) == "boolean" then return v end
    if type(v) == "number" then return v ~= 0 end
    return nil
end

-- Reads named fields off one row into a plain table. A field the row does
-- not have is counted in `missing` so a game patch that renames one shows up.
local function reader(src, missing, struct)
    return function(row, spec)
        local out = {}
        for key, f in pairs(spec) do
            local name, kind = f[1], f[2]
            local v = src.get(row, name)
            if v == nil then
                local k = struct .. "." .. name
                missing[k] = (missing[k] or 0) + 1
            elseif kind == "n" then
                out[key] = num(v)
            elseif kind == "b" then
                out[key] = bool(v)
            else
                out[key] = v
            end
        end
        return out
    end
end

local SKILL = {
    id = { "ID", "n" }, element = { "element", "n" }, dmgType = { "DamageType", "n" },
    calc = { "damageCalcType", "n" }, attr = { "skillAttrType", "n" },
    effectType = { "skillEffectType", "n" }, varType = { "parameterVariationType", "n" },
    paramType = { "parameterType", "n" }, target = { "TargetType", "n" },
    relation = { "defaultTargetRelation", "n" }, targetState = { "defaultTargetState", "n" },
    cost = { "Cost", "n" }, power = { "magnification", "n" }, stagger = { "breakDamageValue", "n" },
    accuracy = { "accuracy", "n" }, crit = { "criticalHitRate", "n" },
    status = { "statusCondition", "n" }, hits = { "hitCount", "n" },
    pierceReflect = { "isReflectPenetration", "b" }, aliveOnly = { "isAliveOnly", "b" },
    canTargetStone = { "canTargetStoneUnit", "b" }, whenDead = { "isAvailableWhenDead", "b" },
    noEscapeBan = { "isUnusableInCannotEscapeBattle", "b" }, applyAllMag = { "isApplyAllMag", "b" },
    undeadReverse = { "isReverseDamageToUndead", "b" },
}

local BUNDLE = {
    effect = { "effectId", "n" }, target = { "TargetType", "n" }, relation = { "targetRelation", "n" },
    activeTiming = { "activeSkillAddTiming", "n" }, passiveTiming = { "passiveSkillAddTiming", "n" },
}

local EFFECT = {
    id = { "ID", "n" }, type = { "EffectType", "n" }, applyTiming = { "applyTiming", "n" },
    proceedTiming = { "proceedTiming", "n" }, turns = { "effectEndActionNum", "n" },
    unremovable = { "isUnremovable", "b" }, addChance = { "addProbability", "n" },
    actChance = { "activationProbability", "n" }, status = { "statusCondition", "n" },
    reaction = { "isExecutingReaction", "b" },
}

local STATUS = {
    status = { "statusCondition", "n" }, bad = { "isBadStatus", "b" }, debuff = { "isDebuff", "b" },
    opposite = { "negateStatusCondition", "n" }, esuna = { "isEsunaToOut", "b" },
    dispel = { "isDispelToOut", "b" }, dispelEvil = { "isDispellingEvilToOut", "b" },
    feather = { "isAngelicFeatherToOut", "b" }, extendable = { "isExtendLifeTurn", "b" },
    stacks = { "isAllowDuplicate", "b" }, overwrite = { "shouldOverwrite", "b" },
    removesExtraTurn = { "isRemoveAdditionalTurn", "b" }, takesControl = { "isControlDisabled", "b" },
    takesAction = { "isActionDisabled", "b" }, releasedBy = { "releaseDamageType", "n" },
}

local UNIT = {
    id = { "ID", "n" }, race = { "Race", "n" }, category = { "Category", "n" },
    maxHp = { "MaxHitPoint", "n" }, maxMp = { "MaxMagicPoint", "n" }, maxBreak = { "MaxBreakPoint", "n" },
    atk = { "Attack", "n" }, def = { "Defence", "n" }, int = { "Intelligence", "n" },
    mind = { "Mind", "n" }, divine = { "Divine", "n" }, agi = { "Agility", "n" },
}

local ITEM = {
    id = { "ID", "n" }, skill = { "SkillId", "n" }, scene = { "usableScene", "n" },
    consumed = { "isConsumedAfterUse", "b" },
}

local DIFFICULTY = {
    difficulty = { "difficulty", "n" }, hp = { "EnemyHpRate", "n" }, gauge = { "EnemyBreakRate", "n" },
    agi = { "EnemyAgilityRate", "n" }, taken = { "DamageTakenRate", "n" }, given = { "DamageGivenRate", "n" },
}

local function bundles(src, read, row, field)
    local list = {}
    local v = src.get(row, field)
    if v == nil then return list end
    src.each(v, function(_, b)
        local e = read(b, BUNDLE)
        if e.effect and e.effect >= 0 then list[#list + 1] = e end
    end)
    return list
end

-- Build every book. Returns the data and a report.
function M.build(src)
    local D = { skills = {}, effects = {}, statuses = {}, units = {}, items = {}, passives = {},
                difficulty = {}, general = {} }
    local missing, counts = {}, {}

    local function walk(struct, fn)
        local n = 0
        for _, forEach in ipairs(src.tables(struct) or {}) do
            forEach(function(key, row)
                local ok, err = pcall(fn, key, row, reader(src, missing, struct))
                if ok then n = n + 1 else missing[struct .. " row error: " .. tostring(err)] = 1 end
            end)
        end
        counts[struct] = n
    end

    walk("SKILL_EFFECT_DATA", function(_, row, read)
        local e = read(row, EFFECT)
        local params = {}
        local p = src.get(row, "ParamList")
        if p ~= nil then src.each(p, function(_, x) params[#params + 1] = num(x) end) end
        e.params = params
        local c = src.get(row, "activationCondition")
        if c ~= nil then
            e.cond = { kind = num(src.get(c, "Condition")), num(src.get(c, "param1")),
                       num(src.get(c, "param2")), num(src.get(c, "param3")) }
        end
        if e.id then D.effects[e.id] = e end
    end)

    walk("SKILL_DATA", function(key, row, read)
        local s = read(row, SKILL)
        s.key = src.text(key)
        s.effects = bundles(src, read, row, "effectBundleList")
        local ratios = {}
        local r = src.get(row, "hitDamageRatioList")
        if r ~= nil then src.each(r, function(_, x) ratios[#ratios + 1] = num(x) end) end
        s.hitRatios = ratios
        -- No damage type on the row (the sim's rows, or a game row that
        -- reads None on a damage skill): take it from the attribute.
        -- eSkillAttributeType 4 Magic -> magic (2); 1 Fight, 2 ChaseAttack,
        -- 3 Ability, 11 Throw, 15 MagicSword -> physical (1).
        if (s.dmgType == nil or s.dmgType == 0) and s.effectType == 1 then
            local a = s.attr
            if a == 4 then s.dmgType = 2
            elseif a == 1 or a == 2 or a == 3 or a == 11 or a == 15 then s.dmgType = 1 end
            s.dmgTypeFrom = "attr"
        end
        if s.id then D.skills[s.id] = s end
    end)

    walk("UNIT_STATUSCONDITION_DETAIL_DATA", function(_, row, read)
        local st = read(row, STATUS)
        if st.status then D.statuses[st.status] = st end
    end)

    walk("UNIT_PARAMETER", function(_, row, read)
        local u = read(row, UNIT)
        u.elements, u.statusRes = {}, {}
        local el = src.get(row, "ElementResistanceList")
        if el ~= nil then src.pairs(el, function(k, v) local e = num(k); if e then u.elements[e] = num(v) end end) end
        local sr = src.get(row, "StatusConditionResistanceList")
        if sr ~= nil then src.pairs(sr, function(k, v) local s = num(k); if s then u.statusRes[s] = num(v) end end) end
        if u.id then D.units[u.id] = u end
    end)

    walk("CONSUMABLES_ITEM_DATA", function(_, row, read)
        local it = read(row, ITEM)
        local t = src.get(row, "throwSkillData")
        if t ~= nil and bool(src.get(t, "isThrow")) then it.throwSkill = num(src.get(t, "SkillId")) end
        if it.id then D.items[it.id] = it end
    end)

    walk("PASSIVE_SKILL_DATA", function(_, row, read)
        local id = num(src.get(row, "ID"))
        if id then D.passives[id] = { id = id, effects = bundles(src, read, row, "effectBundleList") } end
    end)

    walk("GAME_DIFFICULTY_PARAM", function(key, row, read)
        local d = read(row, DIFFICULTY)
        D.difficulty[src.text(key) or tostring(d.difficulty)] = d
    end)

    walk("SKILL_GENERAL_DATA", function(_, row, read)
        local list = {}
        local v = src.get(row, "normalAttackSkills")
        if v ~= nil then src.each(v, function(_, x) list[num(x) or -1] = true end) end
        D.general.normalAttack = list
        D.general.effectMaxLife = num(src.get(row, "effectMaxLifeTime"))
    end)

    local report = { counts = counts, missing = missing }
    return D, report
end

-- One line per book for the log, and one per missing field.
function M.describe(report)
    local lines, keys = {}, {}
    for k in pairs(report.counts) do keys[#keys + 1] = k end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = k .. " " .. report.counts[k] end
    lines[1] = "data: " .. table.concat(parts, ", ")
    local miss = {}
    for k, n in pairs(report.missing) do miss[#miss + 1] = k .. " x" .. n end
    table.sort(miss)
    for _, m in ipairs(miss) do lines[#lines + 1] = "data missing: " .. m end
    return lines
end

-- What a skill does to one target, from its own row and its effect rows.
-- Used by effects.lua (Phase 3); here so tests can check the joins.
function M.skillEffects(D, id)
    local s = D.skills[id]
    if not s then return {} end
    local out = {}
    for _, b in ipairs(s.effects or {}) do
        local e = D.effects[b.effect]
        if e then out[#out + 1] = { bundle = b, effect = e } end
    end
    return out
end

return M

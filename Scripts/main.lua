-- FFR:AutoBattle. One auto-battle switch. One planner for the round, from the
-- design doc: score every enemy, chip the gauges, finish them together.
-- The characters carry out the next slot. Claims stop a second heal, a second
-- buff, or a second Ether in the same round.
-- F10 is on/off and flashes AutoBattle On or Off.
-- F9 is on/off. On flashes AutoBattle: Take it Easy! Off flashes
-- AutoBattle: No Mercy! On is Attack only:
-- no MP and no items. Off is the default. Both choices are remembered.
-- In a fight, the right trigger fires the F10 action and the left trigger
-- fires the F9 action. Outside a fight the triggers stay with the game.
--
-- known.lua is the skill book. mobs.lua is the enemy book. Saves and pak files
-- are not touched. The command goes out through Delegate.Battle.Cmd.Decide.

local TAG = "[FFRAutoBattle] "
local function log(fmt, ...)
    if select("#", ...) == 0 then
        print(TAG .. tostring(fmt) .. "\n")
        return
    end
    print(TAG .. string.format(fmt, ...) .. "\n")
end

local HAS_GAME_TIMERS = (LoopInGameThreadWithDelay ~= nil) and (ExecuteInGameThreadWithDelay ~= nil)
local function gameLoop(ms, fn)
    local function safe()
        local ok, err = pcall(fn)
        if not ok then log("timer error: %s", tostring(err)) end
    end
    if HAS_GAME_TIMERS then
        return LoopInGameThreadWithDelay(ms, safe)
    end
    LoopAsync(ms, function()
        ExecuteInGameThread(safe)
        return false
    end)
end
local function gameDelay(ms, fn)
    local function safe()
        local ok, err = pcall(fn)
        if not ok then log("timer error: %s", tostring(err)) end
    end
    if HAS_GAME_TIMERS then
        return ExecuteInGameThreadWithDelay(ms, safe)
    end
    ExecuteWithDelay(ms, function() ExecuteInGameThread(safe) end)
end

local function modDir()
    local info = debug and debug.getinfo and debug.getinfo(1, "S")
    local src = ((info and info.source) or ""):gsub("^@", ""):gsub("\\", "/")
    return src:match("^(.*)/Scripts/[^/]+$") or "ue4ss/Mods/FFRAutoBattle"
end
local DIR = modDir()
local Known = {}
do
    local ok, loaded = pcall(dofile, DIR .. "/Scripts/known.lua")
    if ok and type(loaded) == "table" then
        Known = loaded
    else
        log("known list unavailable: %s", tostring(loaded))
    end
end
local function knownOf(skill)
    local map = Known.skills
    if not map or not skill or not skill.name then return nil end
    local key = skill.name:lower()
    key = key:gsub("’", "'"):gsub("‘", "'"):gsub("`", "'")
    return map[key]
end
local Mobs = {}
do
    local ok, loaded = pcall(dofile, DIR .. "/Scripts/mobs.lua")
    if ok and type(loaded) == "table" then
        Mobs = loaded
    else
        log("bestiary unavailable: %s", tostring(loaded))
    end
end
local function foldName(name)
    local n = (name or ""):lower()
    n = n:gsub("’", "'"):gsub("‘", "'"):gsub("`", "'")
    return n
end
local function mobKey(name)
    local n = foldName(name)
    if Mobs[n] then return n end
    local stem = n:gsub("%s*[a-z]$", "")
    if stem ~= n and Mobs[stem] then return stem end
    return nil
end
local function mobOf(enemy)
    if not enemy then return nil end
    local key = mobKey(enemy.name)
    return key and Mobs[key] or nil, key
end

local CONFIG_PATH = DIR .. "/config.ini"
local STATE_PATH = DIR .. "/state.txt"
local LOG_PATH = DIR .. "/battle_log.txt"

local ATTR = {
    FIGHT = 1, CHASE = 2, ABILITY = 3, MAGIC = 4, LB = 5,
    ITEM = 6, SUMMON = 7, FINISH = 9,
    MIX = 10, THROW = 11, THROW_MONEY = 12,
    DUAL = 13, MIMIC = 14, SWORD = 15, ESCAPE = 16,
}
local SKIP = {
    [ATTR.CHASE] = true, [ATTR.ITEM] = true, [ATTR.MIX] = true,
    [ATTR.THROW] = true, [ATTR.THROW_MONEY] = true, [ATTR.DUAL] = true,
    [ATTR.MIMIC] = true, [ATTR.SWORD] = true, [ATTR.ESCAPE] = true,
}
local EFF = { DAMAGE = 1, PARAM = 2, CURE = 19, REVIVE = 20, DEFEND = 26, ANALYZE = 29, COVER = 41 }
local TGT = { SELF = 0, SINGLE = 1, GROUP = 2, SPREAD = 3, ALL = 4 }
local REL = { FRIEND = 1, ENEMY = 2 }
local PARAM = { HP = 1, MP = 2, LB = 4 }
local VAR = { UP = 0, RATIO = 2 }
local ST_BREAK = 89
local GUARD_STATUS = { [34] = true, [35] = true, [36] = true }
local OUT_OF_CONTROL = { [6] = "confused", [8] = "charmed", [10] = "berserk" }
local LOCK = { [3] = true, [4] = true, [5] = true, [6] = true, [7] = true, [8] = true, [10] = true, [11] = true }
local PHASE_BONUS, PHASE_FINISH = 1, 2
local DECIDE_MS = 420

local Defaults = {
    Enabled = true, BattleSpeed = 2, Submit = true, AttacksOnly = false,
    TakeOverKey = "F10", MenuKey = "F9",
}
local cfg = {}
for k, v in pairs(Defaults) do cfg[k] = v end

local function parseBool(s)
    s = tostring(s or ""):lower()
    return s == "1" or s == "true" or s == "yes" or s == "on"
end

local function loadIni(path)
    local out = {}
    local f = io.open(path, "r")
    if not f then return out end
    for line in f:lines() do
        local k, v = line:match("^%s*([^;#%[=][^=]-)%s*=%s*(.-)%s*$")
        if k then out[k:lower()] = v end
    end
    f:close()
    return out
end

local function loadConfig()
    local ini = loadIni(CONFIG_PATH)
    local function take(name)
        local v = ini[name:lower()]
        if v == nil or v == "" then return end
        if type(Defaults[name]) == "boolean" then
            cfg[name] = parseBool(v)
        elseif type(Defaults[name]) == "number" then
            cfg[name] = tonumber(v) or Defaults[name]
        else
            cfg[name] = v
        end
    end
    for name in pairs(Defaults) do take(name) end
    if cfg.BattleSpeed < 1 then cfg.BattleSpeed = 1 end
    if cfg.BattleSpeed > 4 then cfg.BattleSpeed = 4 end
    local state = loadIni(STATE_PATH)
    if state.enabled then cfg.Enabled = parseBool(state.enabled) end
    if state.attacks then cfg.AttacksOnly = parseBool(state.attacks) end
end

local function saveState()
    local f = io.open(STATE_PATH, "w")
    if not f then return end
    f:write("enabled=" .. (cfg.Enabled and "true" or "false") .. "\n")
    f:write("attacks=" .. (cfg.AttacksOnly and "true" or "false") .. "\n")
    f:close()
end

local function appendLog(line)
    local f = io.open(LOG_PATH, "a")
    if not f then return end
    f:write(line .. "\n")
    f:close()
end

--------------------------------------------------------------------------------
-- Game objects
--------------------------------------------------------------------------------

local function unwrap(v)
    if type(v) == "userdata" then
        local ok, inner = pcall(function() return v:get() end)
        if ok and inner ~= nil then return inner end
    end
    return v
end

local function num(v)
    v = unwrap(v)
    if type(v) == "number" then return v end
    return nil
end

local function textOf(v)
    if type(v) == "string" then return v end
    if type(v) == "userdata" then
        local ok, s = pcall(function() return v:ToString() end)
        if ok and type(s) == "string" and s ~= "" then return s end
    end
    return nil
end

local function fill(fn)
    local t = {}
    local ok, ret = pcall(fn, t)
    if not ok then return nil, tostring(ret) end
    local out = {}
    local function take(v)
        v = unwrap(v)
        if v ~= nil then out[#out + 1] = v end
    end
    for _, v in pairs(t) do take(v) end
    if type(ret) == "table" then
        for _, v in pairs(ret) do take(v) end
    elseif ret ~= nil then
        take(ret)
    end
    return out
end

local bflBattle, bflSkill
local function battleLib()
    if not (bflBattle and bflBattle:IsValid()) then
        bflBattle = StaticFindObject("/Script/mucha.Default__CPP_BFL_Battle")
    end
    return bflBattle
end
local function skillLib()
    if not (bflSkill and bflSkill:IsValid()) then
        bflSkill = StaticFindObject("/Script/mucha.Default__CPP_BFL_Skill")
    end
    return bflSkill
end

local bflItem = nil
local function itemLib()
    if not (bflItem and bflItem:IsValid()) then
        bflItem = StaticFindObject("/Script/mucha.Default__CPP_BFL_Item")
    end
    return bflItem
end

local function rowStructName(dt)
    local ok, name = pcall(function()
        local s = dt:GetRowStruct()
        if not s or not s:IsValid() then return nil end
        return s:GetFName():ToString()
    end)
    return ok and name or nil
end

local function field(row, name)
    local ok, v = pcall(function() return row[name] end)
    if not ok then return nil end
    return v
end

local SkillIdx = nil
local ItemIdx = nil
local function buildSkillIndex()
    if SkillIdx then return end
    local effects = {}
    local skills = {}
    local tables = FindAllOf("DataTable") or {}
    local effectTables, skillTables, itemTables = {}, {}, {}
    for _, dt in ipairs(tables) do
        pcall(function()
            if type(dt) ~= "userdata" or not dt:IsValid() then return end
            local struct = rowStructName(dt)
            if struct == "SKILL_EFFECT_DATA" then
                effectTables[#effectTables + 1] = dt
            elseif struct == "SKILL_DATA" then
                skillTables[#skillTables + 1] = dt
            elseif struct == "CONSUMABLES_ITEM_DATA" then
                itemTables[#itemTables + 1] = dt
            end
        end)
    end
    for _, dt in ipairs(effectTables) do
        pcall(function()
            dt:ForEachRow(function(_, row)
                local id = num(field(row, "ID"))
                if id then effects[id] = num(field(row, "statusCondition")) or 0 end
            end)
        end)
    end
    for _, dt in ipairs(skillTables) do
        pcall(function()
            dt:ForEachRow(function(_, row)
                local id = num(field(row, "ID"))
                if not id then return end
                local friendStatus, enemyStatus = {}, {}
                local bundles = field(row, "effectBundleList")
                if type(bundles) == "userdata" and bundles.ForEach then
                    bundles:ForEach(function(_, e)
                        local b = unwrap(e)
                        local eid = b and num(b.effectId)
                        local rel = b and num(b.targetRelation)
                        local st = eid and effects[eid]
                        if st and st > 0 then
                            if rel == REL.FRIEND then friendStatus[st] = true end
                            if rel == REL.ENEMY then enemyStatus[st] = true end
                        end
                    end)
                end
                local own = num(field(row, "statusCondition")) or 0
                local rel = num(field(row, "defaultTargetRelation")) or 0
                if own > 0 and rel == REL.FRIEND then friendStatus[own] = true end
                if own > 0 and rel == REL.ENEMY then enemyStatus[own] = true end
                local name = textOf(field(row, "Name"))
                skills[id] = {
                    id = id,
                    name = (name and name ~= "") and name or ("#" .. id),
                    cost = num(field(row, "Cost")) or 0,
                    attr = num(field(row, "skillAttrType")) or 0,
                    effect = num(field(row, "skillEffectType")) or 0,
                    varType = num(field(row, "parameterVariationType")) or -1,
                    paramType = num(field(row, "parameterType")) or 0,
                    target = num(field(row, "TargetType")) or TGT.SINGLE,
                    rel = rel,
                    power = num(field(row, "magnification")) or 0,
                    breakPower = num(field(row, "breakDamageValue")) or 0,
                    hits = num(field(row, "hitCount")) or 1,
                    targetState = num(field(row, "defaultTargetState")) or 0,
                    friendStatus = friendStatus,
                    enemyStatus = enemyStatus,
                }
            end)
        end)
    end
    local n = 0
    for _ in pairs(skills) do n = n + 1 end
    if n > 0 then
        SkillIdx = skills
        log("skill table: %d rows", n)
    end
    local items = {}
    for _, dt in ipairs(itemTables) do
        pcall(function()
            dt:ForEachRow(function(_, row)
                local id = num(field(row, "ID"))
                if not id then return end
                local name = textOf(field(row, "Name"))
                local skillId = nil
                for _, key in ipairs({ "SkillId", "skillId", "SkillID", "UseSkillId", "EffectSkillId" }) do
                    skillId = num(field(row, key))
                    if skillId and skillId > 0 then break end
                    skillId = nil
                end
                items[id] = {
                    id = id,
                    name = (name and name ~= "") and name or ("item " .. id),
                    skillId = skillId,
                    rare = field(row, "Rare") == true or field(row, "IsRare") == true,
                }
            end)
        end)
    end
    local ni = 0
    for _ in pairs(items) do ni = ni + 1 end
    if ni > 0 then
        ItemIdx = items
        log("item table: %d rows", ni)
    end
end

local function skillOf(id)
    buildSkillIndex()
    return SkillIdx and SkillIdx[id]
end

local function paramOf(uid)
    local bfl = battleLib()
    if not (bfl and bfl:IsValid()) then return nil end
    local ok, p = pcall(function() return bfl:GetBattleUnitParameter(uid, true) end)
    if ok and p and p.IsValid and p:IsValid() then return p end
    return nil
end

local function stat(uid, kind, maximum)
    local p = paramOf(uid)
    if not p then return nil end
    local ok, v = pcall(function()
        if maximum then return p:GetMaxParameterByType(kind) end
        return p:GetParameterByType(kind, false)
    end)
    if ok then return num(v) end
    return nil
end

local function hpRatio(uid)
    local cur, maxv = stat(uid, PARAM.HP, false), stat(uid, PARAM.HP, true)
    if not cur or not maxv or maxv <= 0 then return nil end
    return cur / maxv
end

local function statuses(uid)
    local set = {}
    local bfl = battleLib()
    if not (bfl and bfl:IsValid()) then return set end
    local list = fill(function(t) bfl:GetStatusConditionList(t, uid) end)
    if not list then return set end
    for _, v in ipairs(list) do
        local n = num(v)
        if n then set[n] = true end
    end
    return set
end

local function outOfControl(uid)
    local set = statuses(uid)
    for id, name in pairs(OUT_OF_CONTROL) do
        if set[id] then return name end
    end
    return nil
end

local function broken(uid)
    if statuses(uid)[ST_BREAK] then return true end
    local p = paramOf(uid)
    if not p then return false end
    local ok, r = pcall(function() return p:GetBreakPointRatio() end)
    r = ok and num(r) or nil
    return r ~= nil and r <= 0.001
end

local function breakLeft(uid)
    local p = paramOf(uid)
    if not p then return 1 end
    local ok, r = pcall(function() return p:GetBreakPointRatio() end)
    r = ok and num(r) or nil
    if r == nil then return broken(uid) and 0 or 1 end
    if r > 1.5 then return r / 100 end
    return r
end

local function unitName(uid)
    local p = paramOf(uid)
    if p then
        local ok, n = pcall(function() return p:GetDuplicationUnitName() end)
        local s = ok and textOf(n) or nil
        if s and s ~= "" then return s end
        local id
        ok, id = pcall(function() return p:GetUnitId() end)
        id = ok and num(id) or nil
        if id then return "Unit " .. id end
    end
    return "Unit " .. tostring(uid)
end

local function skillCost(uid, id, isAll)
    local info = skillOf(id)
    local bfl, sl = battleLib(), skillLib()
    if bfl and bfl:IsValid() and sl and sl:IsValid() then
        local ok, cost = pcall(function()
            local unitId = bfl:GetBattleUnitParameter(uid, true):GetUnitId()
            return sl:GetSkillCost(id, unitId, isAll and true or false)
        end)
        if ok and type(cost) == "number" and cost >= 0 then return cost end
    end
    return info and info.cost or 0
end

-- true when the game says this unit can activate it, false when it says no,
-- nil when the call is missing. The MP check is separate: a short bar is not a seal.
local function activation(uid, id)
    local bfl = battleLib()
    if not (bfl and bfl:IsValid()) then return nil end
    local ok, v = pcall(function() return bfl:CanUnitActivateSkill(uid, id) end)
    if ok and v == false then return false end
    if v == true then return true end
    return nil
end

local function sealed(uid, id)
    return activation(uid, id) == false
end

-- A Limit crystal is not MP. CanUnitActivateSkill stays false while the
-- crystal is filling, and also on rows the command bar will still accept.
-- IsEnableCommand stays false for the same rows, so the gauge is the check.
local function limitSkill(skill)
    if not skill then return false end
    if skill.attr == ATTR.LB then return true end
    local info = skill.known or knownOf(skill)
    local use = info and info.use
    return use == "lb-setup" or use == "lb-cash" or use == "lb-revive"
end

local function commandEnabled(uid, id)
    local bfl = battleLib()
    if not (bfl and bfl:IsValid()) then return true end
    local ok, enabled = pcall(function() return bfl:IsEnableCommand(uid, id) end)
    if ok and enabled == false then return false end
    return true
end

local function idOf(v)
    local n = num(v)
    if n then return n end
    if type(v) ~= "userdata" then return nil end
    for _, key in ipairs({ "ID", "Id", "SkillId", "skillId", "actionId", "ActionId" }) do
        local ok, inner = pcall(function() return v[key] end)
        inner = ok and num(inner) or nil
        if inner then return inner end
    end
    return nil
end

local loggedUnits = {}
local function equippedIds(uid)
    buildSkillIndex()
    local p = paramOf(uid)
    local bfl = battleLib()
    local unitId = nil
    if p then
        local ok, v = pcall(function() return p:GetUnitId() end)
        if ok then unitId = num(v) end
    end
    local probes = {}
    if p then
        probes[#probes + 1] = { "param.GetActiveSkillListWithVision", function(t) p:GetActiveSkillListWithVision(t) end }
        probes[#probes + 1] = { "param.GetActiveSkillList", function(t) p:GetActiveSkillList(t) end }
        probes[#probes + 1] = { "param.GetActionList", function(t) p:GetActionList(t) end }
    end
    if bfl and bfl:IsValid() then
        probes[#probes + 1] = { "battle.GetActiveSkillListWithVision", function(t) bfl:GetActiveSkillListWithVision(t, uid) end }
        probes[#probes + 1] = { "battle.GetEquipSkills", function(t) bfl:GetEquipSkills(t, unitId or uid) end }
    end
    local sl = skillLib()
    if sl and sl:IsValid() then
        probes[#probes + 1] = { "skill.GetEquipSkills", function(t) sl:GetEquipSkills(t, unitId or uid) end }
    end
    local found, notes = {}, {}
    local function add(v)
        local id = idOf(v)
        if id and id > 0 then found[id] = true end
    end
    for _, probe in ipairs(probes) do
        local list, err = fill(probe[2])
        if list and #list > 0 then
            for _, v in ipairs(list) do add(v) end
            notes[#notes + 1] = string.format("%s=%d", probe[1], #list)
        elseif not loggedUnits[uid] and err then
            notes[#notes + 1] = probe[1] .. " failed"
        end
    end
    if p then
        for _, prop in ipairs({ "activeSkillIdList", "equipSkillList", "commandSkillIdList" }) do
            local ok, arr = pcall(function() return p[prop] end)
            if ok and type(arr) == "userdata" then
                local n = 0
                local walked = pcall(function()
                    arr:ForEach(function(_, e)
                        add(e)
                        n = n + 1
                    end)
                end)
                if walked and n > 0 then
                    notes[#notes + 1] = prop .. "=" .. n
                elseif not walked and not loggedUnits[uid] then
                    notes[#notes + 1] = prop .. " skipped"
                end
            end
        end
    end
    if not loggedUnits[uid] then
        loggedUnits[uid] = true
        local ids = {}
        for id in pairs(found) do ids[#ids + 1] = id end
        table.sort(ids)
        local names = {}
        for i = 1, math.min(#ids, 12) do
            local s = skillOf(ids[i])
            names[#names + 1] = s and s.name or tostring(ids[i])
        end
        log("skill list for unit %s via %s -> %s", tostring(uid),
            (#notes > 0) and table.concat(notes, ", ") or "nothing",
            (#names > 0) and table.concat(names, ", ") or "(empty)")
    end
    local ids = {}
    for id in pairs(found) do ids[#ids + 1] = id end
    table.sort(ids)
    return ids
end

local function targetsFor(uid, skill, relation)
    local bfl = battleLib()
    if not (bfl and bfl:IsValid()) then return {} end
    local list = fill(function(t)
        bfl:GetSkillTargetUnitUniqueIdList(t, uid, skill.id, relation, true)
    end)
    local ids = {}
    if list then
        for _, v in ipairs(list) do
            local n = num(v)
            if n then ids[#ids + 1] = n end
        end
    end
    if #ids == 0 then
        local ok, n = pcall(function() return bfl:GetDefaultSkillTargetUnitUniqueId(uid, skill.id) end)
        n = ok and num(n) or nil
        if n and n >= 0 then ids[1] = n end
    end
    return ids
end

local function members(relation)
    local bfl = battleLib()
    if not (bfl and bfl:IsValid()) then return {} end
    local ids, seen = {}, {}
    local function addList(list)
        if not list then return end
        for _, v in ipairs(list) do
            local n = num(v)
            if not n and type(v) == "userdata" then
                local ok, u = pcall(function() return v:GetUniqueId() end)
                n = ok and num(u) or nil
                if not n then
                    ok, u = pcall(function() return v.UniqueId end)
                    n = ok and num(u) or nil
                end
            end
            if n and not seen[n] then
                seen[n] = true
                ids[#ids + 1] = n
            end
        end
    end
    addList(fill(function(t) bfl:GetBattleUnitListByRelation(t, relation, true) end))
    addList(fill(function(t) bfl:GetBattleUnitListByRelation(t, relation, false) end))
    addList(fill(function(t) bfl:GetBattleUnitListByRelation(t, relation) end))
    return ids
end

-- During a command the relation list often contains only the actor.
local function friendIds()
    local ids, seen = {}, {}
    local function add(n)
        n = num(n)
        if n and n >= 0 and not seen[n] then
            seen[n] = true
            ids[#ids + 1] = n
        end
    end
    for _, id in ipairs(members(REL.FRIEND)) do add(id) end
    local bfl = battleLib()
    if bfl and bfl:IsValid() then
        for uid = 0, 7 do
            local ok, p = pcall(function() return bfl:GetBattleUnitParameter(uid, true) end)
            if ok and p and p.IsValid and p:IsValid() then
                local okR, rel = pcall(function() return p:GetRelation() end)
                if okR and num(rel) == REL.FRIEND then add(uid) end
            end
        end
    end
    return ids
end

--------------------------------------------------------------------------------
-- Skill math. The live row has stagger and no element. known.lua names the element.
--------------------------------------------------------------------------------

local function hitsOf(skill)
    local h = skill.hits or 1
    if h < 1 then h = 1 end
    return h
end

local function aoeOf(skill)
    return skill.target == TGT.GROUP or skill.target == TGT.SPREAD or skill.target == TGT.ALL
end

-- A party heal is the live group target, or a published "all allies" row.
local function partyOf(skill)
    if aoeOf(skill) then return true end
    local info = skill and (skill.known or knownOf(skill))
    return (info and info.party) and true or false
end

local function offenseOf(skill)
    local h = hitsOf(skill)
    local power = skill.power or 0
    if power <= 0 and skill.attr == ATTR.FIGHT then power = 18 end
    local br = skill.breakPower or 0
    local info = skill.known or knownOf(skill)
    -- The published number is the whole skill's stagger, not the stagger of one hit.
    if info and info.stagger then return power * h, info.stagger end
    return power * h, br * h
end

local function elementFactor(skill, enemy)
    local ok, factor = pcall(function()
        local info = skill and (skill.known or knownOf(skill))
        local el = info and info.element
        if not el or not enemy then return 1 end
        local card = mobOf(enemy)
        if not card then return 1 end
        if card.absorb and card.absorb[el] then return 0 end
        if card.no and card.no[el] then return 0 end
        if card.half and card.half[el] then return 0.5 end
        if card.weak and card.weak[el] then return 3 end
        return 1
    end)
    if not ok or type(factor) ~= "number" then return 1 end
    return factor
end

local function counterScale(skill, enemy)
    local ok, scale = pcall(function()
        local card = mobOf(enemy)
        if not card or not card.counter then return 1 end
        local info = skill and (skill.known or knownOf(skill))
        local phys = skill.attr == ATTR.FIGHT or (info and info.phys)
        local magic = skill.attr == ATTR.MAGIC or (info and info.magic)
        local countered = false
        if card.counter == "physical" then countered = phys and not magic end
        if card.counter == "magic" then countered = magic and not phys end
        if card.counter == "hit" then countered = phys or magic end
        if not countered then return 1 end
        if elementFactor(skill, enemy) >= 3 then return 0.85 end
        return 0.2
    end)
    if not ok or type(scale) ~= "number" then return 1 end
    return scale
end

local Fight
local unitKit
-- A friend, a nameless slot, or a body with no HP is not a foe.
-- The enemy-target list has included the actor. The book also has a Lasswell card at gauge 9999.
local function keepFoe(id)
    if not id or not Fight then return false end
    local function drop()
        if Fight.seenFoe then Fight.seenFoe[id] = nil end
        return false
    end
    for _, fid in ipairs(friendIds()) do
        if fid == id then return drop() end
    end
    if Fight.seenAlly and Fight.seenAlly[id] then return drop() end
    local p = paramOf(id)
    if not p then return drop() end
    local ok, n = pcall(function() return p:GetDuplicationUnitName() end)
    local s = ok and textOf(n) or nil
    if not s or s == "" then return drop() end
    if Fight.seenAlly then
        local folded = foldName(s)
        for _, name in pairs(Fight.seenAlly) do
            if foldName(name) == folded then return drop() end
        end
    end
    local r = hpRatio(id)
    if r == nil or r <= 0 then return drop() end
    return true
end
local function monoScale(skill, enemy)
    if not Fight or not Fight.elemRun or not enemy then return 1 end
    local card = mobOf(enemy)
    if not card or not card.mono then return 1 end
    local info = skill and (skill.known or knownOf(skill))
    local el = info and info.element
    if not el then return 1 end
    local run = Fight.elemRun[enemy.id]
    if run and run.el == el and run.n >= 2 then return 0.05 end
    return 1
end

local function anyKey(set)
    if not set then return false end
    for _ in pairs(set) do return true end
    return false
end

local function isGuard(skill)
    local info = skill.known or knownOf(skill)
    if info and info.use == "guard" then return true end
    local name = skill.name and skill.name:lower() or ""
    if name == "defend" or name == "guard" then return true end
    if skill.effect == EFF.DEFEND or skill.effect == EFF.COVER then return true end
    if (skill.power or 0) > 0 or (skill.breakPower or 0) > 0 then return false end
    if skill.friendStatus then
        for id in pairs(skill.friendStatus) do
            if GUARD_STATUS[id] then return true end
        end
    end
    return false
end

local function classify(skill)
    if skill.effect == EFF.REVIVE or (skill.rel == REL.FRIEND and skill.targetState == 2) then return "revive" end
    if skill.effect == EFF.CURE then return "cure" end
    if isGuard(skill) then return "defend" end
    if skill.rel == REL.FRIEND and skill.effect == EFF.DAMAGE and skill.paramType == PARAM.HP
        and (skill.varType == VAR.UP or skill.varType == VAR.RATIO) then
        return "heal"
    end
    if anyKey(skill.friendStatus) and skill.rel == REL.FRIEND and skill.effect ~= EFF.DAMAGE then return "buff" end
    if anyKey(skill.enemyStatus) and skill.rel == REL.ENEMY and (skill.power or 0) <= 0 and (skill.breakPower or 0) <= 0 then
        return "debuff"
    end
    if skill.effect == EFF.ANALYZE and (skill.power or 0) <= 0 and (skill.breakPower or 0) <= 0 then return nil end
    if skill.effect == EFF.DAMAGE or (skill.power or 0) > 0 or (skill.breakPower or 0) > 0
        or skill.attr == ATTR.FIGHT or skill.attr == ATTR.ABILITY or skill.attr == ATTR.MAGIC
        or skill.attr == ATTR.LB or skill.attr == ATTR.FINISH or skill.attr == ATTR.SUMMON then
        return "damage"
    end
    return nil
end

-- Filled gauges, from the live limit points. IsEnableCommand is only the
-- fallback when the battle library does not answer. A full gauge is enough.
local function limitReady(uid, skill)
    local need = (skill and skill.lbCost) or 1
    if need < 1 then need = 1 end
    local bfl = battleLib()
    local points, one, slots, unitGauges = nil, nil, nil, nil
    if bfl and bfl:IsValid() then
        local ok, v
        ok, v = pcall(function() return bfl:GetUnitLimitBurstPoint(uid) end)
        if ok then points = num(v) end
        ok, v = pcall(function() return bfl:GetLimitBurstPointOneGauge() end)
        if ok then one = num(v) end
        if (one == nil) or (one <= 0) then
            ok, v = pcall(function() return bfl:GetLimitBurstPointOneGauge(uid) end)
            if ok then one = num(v) end
        end
        ok, v = pcall(function() return bfl:GetLimitBurstPointMaxGaugeNum() end)
        if ok then slots = num(v) end
        if slots == nil then
            ok, v = pcall(function() return bfl:GetLimitBurstPointMaxGaugeNum(uid) end)
            if ok then slots = num(v) end
        end
        ok, v = pcall(function() return bfl:GetUnitLimitBurstPointGaugeNum(uid) end)
        if ok then unitGauges = num(v) end
    end
    local p = paramOf(uid)
    if (points == nil) and p then
        local ok, v = pcall(function() return p:GetLimitBurstPoint() end)
        if ok then points = num(v) end
    end
    if points == nil then points = stat(uid, PARAM.LB, false) end
    local maxv = stat(uid, PARAM.LB, true)
    if ((one == nil) or (one <= 0)) and maxv and (maxv > 0) then
        local n = slots
        if (n == nil) or (n < 1) or (n > 4) then n = 1 end
        one = maxv / n
    end
    local filled = nil
    if (points ~= nil) and (one ~= nil) and (one > 0) then
        filled = math.floor((points / one) + 1e-6)
    end
    -- GaugeNum is trusted only after it has read empty once. A call that
    -- always returns 1 is the slot count, not a full crystal.
    if (filled == nil) and (unitGauges ~= nil) and (unitGauges >= 0) and (unitGauges <= 4) and Fight then
        Fight.lbGaugeApi = Fight.lbGaugeApi or {}
        if unitGauges == 0 then Fight.lbGaugeApi[uid] = true end
        if Fight.lbGaugeApi[uid] then filled = unitGauges end
    end
    if Fight then
        Fight.lbRead = Fight.lbRead or {}
        local bucket = filled
        if (bucket == nil) and (points ~= nil) then bucket = math.floor(points) end
        local prev = Fight.lbRead[uid]
        if prev ~= bucket then
            Fight.lbRead[uid] = bucket
            log("%s limit points %s max %s one %s slots %s unit %s needs %s",
                unitName(uid), tostring(points), tostring(maxv), tostring(one),
                tostring(slots), tostring(unitGauges), tostring(need))
            if (filled ~= nil) and (filled >= need) and ((type(prev) ~= "number") or (prev < need)) then
                appendLog("  " .. unitName(uid) .. " limit ready")
            end
        end
    end
    if filled == nil then return commandEnabled(uid, skill.id) end
    return filled >= need
end

local function tagSkill(uid, id, borrowed)
    if borrowed and activation(uid, id) ~= true then return nil end
    local s = skillOf(id)
    if not s or SKIP[s.attr] then return nil end
    local lb = limitSkill(s)
    if not borrowed and sealed(uid, id) and not lb then return nil end
    local copy = {}
    for k, v in pairs(s) do copy[k] = v end
    copy.known = knownOf(copy)
    local okKind, kind = pcall(classify, copy)
    copy.kind = okKind and kind or nil
    local info = copy.known
    if info then
        if info.stagger then copy.breakPower = info.stagger end
        if info.use == "guard" then copy.kind = "defend"
        elseif info.use == "opener" or info.use == "guardbuff" or info.use == "buff" or info.use == "lb-setup" then
            copy.kind = "buff"
        elseif info.use == "lb-revive" then copy.kind = "revive"
        elseif info.use == "heal" then copy.kind = "heal"
        elseif info.use == "cure" then copy.kind = "cure"
        elseif info.use == "debuff" then copy.kind = "debuff"
        elseif info.use == "scan" then copy.kind = "scan"
        elseif info.use == "finish" then
            if copy.kind ~= "heal" and copy.kind ~= "buff" then copy.kind = "damage" end
        elseif copy.kind ~= "heal" and copy.kind ~= "buff" and copy.kind ~= "revive"
            and copy.kind ~= "cure" and copy.kind ~= "defend" and copy.kind ~= "debuff" then
            copy.kind = "damage"
        end
    end
    if copy.effect == EFF.ANALYZE then copy.kind = "scan" end
    copy.cost = skillCost(uid, id, aoeOf(copy))
    if limitSkill(copy) then
        local gauges = nil
        if info and (type(info.gauges) == "number") and (info.gauges >= 1) then
            gauges = info.gauges
        end
        if gauges == nil then
            local raw = copy.cost or 0
            if (raw >= 1) and (raw <= 2) then gauges = raw end
        end
        if gauges == nil then gauges = 1 end
        copy.lbCost = gauges
        copy.cost = 0
        if (not borrowed) and (not limitReady(uid, copy)) then return nil end
    end
    if not copy.kind then return nil end
    return copy
end

unitKit = function(uid)
    if not Fight then return nil end
    Fight.kits = Fight.kits or {}
    local cached = Fight.kits[uid]
    if cached then return cached end
    local kit = { spells = {}, healCost = 0, healScore = 0 }
    local cureCost, raiseCost = 0, 0
    for _, id in ipairs(equippedIds(uid)) do
        local s = skillOf(id)
        if s and (s.attr == ATTR.FINISH or s.attr == ATTR.SUMMON or s.attr == ATTR.LB) then
        elseif s then
            local copy = tagSkill(uid, id, false)
            if copy and copy.attr ~= ATTR.FINISH and copy.attr ~= ATTR.SUMMON and copy.attr ~= ATTR.LB then
                kit.spells[#kit.spells + 1] = copy
                local info = copy.known
                local score = 0
                if info and info.patch then score = 1
                elseif copy.kind == "heal" or (info and info.use == "heal") then score = 50 + (copy.power or 0) end
                if score > kit.healScore then kit.healScore = score end
                if copy.kind == "heal" and score >= 50 and (copy.cost or 0) > 0 then
                    if cureCost == 0 or copy.cost < cureCost then cureCost = copy.cost end
                end
                if copy.kind == "revive" and (copy.cost or 0) > 0 then
                    if raiseCost == 0 or copy.cost < raiseCost then raiseCost = copy.cost end
                end
            end
        end
    end
    local sawFight = false
    for _, s in ipairs(kit.spells) do
        if s.attr == ATTR.FIGHT then sawFight = true end
    end
    if not sawFight and SkillIdx then
        for id, s in pairs(SkillIdx) do
            if s.attr == ATTR.FIGHT then
                local copy = tagSkill(uid, id, true)
                if copy then kit.spells[#kit.spells + 1] = copy end
                break
            end
        end
    end
    kit.healCost = (cureCost > 0) and cureCost or raiseCost
    if #kit.spells > 0 then Fight.kits[uid] = kit end
    return kit
end

local function friendAction(skill)
    if skill.rel == REL.ENEMY then return false end
    if skill.rel == REL.FRIEND then return true end
    if skill.kind == "heal" or skill.kind == "revive" or skill.kind == "buff"
        or skill.kind == "cure" or skill.kind == "defend" then
        return true
    end
    return false
end

local function legalize(uid, skill, targets, isAll)
    if skill.target == TGT.SELF then return targets, false end
    local rel = REL.ENEMY
    if friendAction(skill) then rel = REL.FRIEND end
    local legal = targetsFor(uid, skill, rel)
    if #legal == 0 then return targets, isAll end
    if isAll or aoeOf(skill) then return legal, true end
    for _, id in ipairs(targets or {}) do
        for _, l in ipairs(legal) do
            if id == l then return { id }, false end
        end
    end
    return { legal[1] }, false
end

local function finishChoice(uid, skill, reason, targets, isAll, isItem)
    local ids, all = targets, isAll
    if not isItem then
        ids, all = legalize(uid, skill, targets, isAll)
    end
    if not ids or #ids == 0 then
        log("%s: %s has no legal target", unitName(uid), skill.name)
        return nil
    end
    return {
        id = skill.id, name = skill.name, score = 1, cost = skill.cost or 0,
        kind = skill.kind, reason = reason, targets = ids, isAll = all and true or false,
        attr = skill.attr, isItem = isItem and true or false, known = skill.known,
    }
end

local function idsOf(list)
    local t = {}
    for _, u in ipairs(list or {}) do t[#t + 1] = u.id end
    return t
end

local function lowestAlly(w, pred)
    local best, bestR = nil, 2
    for _, u in ipairs(w.allies) do
        if not u.dead and (not pred or pred(u)) then
            local r = u.hp or 1
            if r < bestR then best, bestR = u, r end
        end
    end
    return best
end

local function firstDead(w, pred)
    for _, u in ipairs(w.allies) do
        if u.dead and (not pred or pred(u)) then return u end
    end
    return nil
end

local function lockedAlly(w)
    local body = nil
    for _, u in ipairs(w.allies) do
        if not u.dead and u.statuses then
            local hit = false
            for id in pairs(LOCK) do
                if u.statuses[id] then hit = true end
            end
            if hit then
                if u.acts ~= false then return u end
                body = body or u
            end
        end
    end
    return body
end

local itemsLogged = false
local potLogged = false

local function potFight(w)
    for _, u in ipairs(w.enemies) do
        local n = (u.name or ""):lower()
        if n == "pot" or n:find(" pot", 1, true) then
            if not potLogged then
                potLogged = true
                log("pot fight: leaving items for you")
            end
            return true
        end
    end
    return false
end

local function saysYes(obj, method, id)
    if not (obj and obj.IsValid and obj:IsValid()) then return false end
    local ok, v = pcall(function() return obj[method](obj, id) end)
    return ok and (v == true or v == 1)
end

local function addItemId(ids, v)
    local n = num(v)
    if not n and type(v) == "userdata" then
        n = num(field(v, "ID")) or num(field(v, "ItemId")) or num(field(v, "itemId"))
        if not n then
            local ok, inner = pcall(function() return v:get() end)
            n = ok and num(inner) or nil
        end
    end
    if n and n > 0 then ids[n] = true end
end

local function eachItemArray(arr, ids)
    if type(arr) == "table" then
        for _, v in pairs(arr) do addItemId(ids, v) end
        return
    end
    if type(arr) ~= "userdata" then return end
    if arr.ForEach then
        pcall(function()
            arr:ForEach(function(_, e) addItemId(ids, e) end)
        end)
    end
    for i = 1, 400 do
        local ok, v = pcall(function() return arr[i] end)
        if not ok or v == nil then break end
        addItemId(ids, v)
    end
end

local function ownedRecovery()
    buildSkillIndex()
    local ids = {}
    local function take(list)
        if not list then return end
        for _, v in ipairs(list) do addItemId(ids, v) end
    end
    local bfl, lib = battleLib(), itemLib()
    if bfl and bfl:IsValid() then take(fill(function(t) bfl:GetConsumableItemList(t) end)) end
    if lib and lib:IsValid() then
        local ok, arr = pcall(function() return lib:GetAllItemIdListByType(1) end)
        if ok then eachItemArray(arr, ids) end
        take(fill(function(t) lib:GetAllItemIdListByType(t, 1) end))
        take(fill(function(t) lib:GetConsumableItemList(t) end))
        take(fill(function(t) lib:GetInventoryItemIdListByConsumableType(t, 1) end))
        take(fill(function(t) lib:GetInventoryAllItemIdList(t) end))
    end
    local out = {}
    local catalog = 0
    for _ in pairs(ids) do catalog = catalog + 1 end
    for id in pairs(ids) do
        local count = nil
        if lib and lib:IsValid() then
            local ok, n = pcall(function() return lib:GetInventoryItemNum(id) end)
            count = ok and num(n) or nil
            if count == nil then
                ok, n = pcall(function() return lib:GetConsumableItemNum(id) end)
                count = ok and num(n) or nil
            end
        end
        if count and count > 0 then
            local row = ItemIdx and ItemIdx[id] or nil
            local name = nil
            if lib and lib:IsValid() then
                local ok, n = pcall(function() return lib:GetItemName(id):ToString() end)
                if ok and type(n) == "string" and n ~= "" then name = n end
            end
            if not name or name == "" then name = row and row.name or ("item " .. id) end
            local lowered = name:lower()
            local listed = Known.items and Known.items[lowered]
            local heldBack = (Known.leave and Known.leave[lowered]) or lowered:find("elixir", 1, true)
                or lowered:find("scroll", 1, true)
            local common = not (row and row.rare) and not heldBack
            if common then
                local hp, mp, kind = false, false, nil
                if listed == "hp" then hp, kind = true, "heal" end
                if listed == "mp" then mp = true end
                if listed == "revive" then kind = "revive" end
                if listed == "cure" then kind = "cure" end
                if row and row.skillId then
                    local s = skillOf(row.skillId)
                    if s then
                        if s.effect == EFF.REVIVE or (s.rel == REL.FRIEND and s.targetState == 2) then kind = "revive" end
                        if s.effect == EFF.CURE then kind = "cure" end
                        if s.rel == REL.FRIEND and s.effect == EFF.DAMAGE and s.paramType == PARAM.HP
                            and (s.varType == VAR.UP or s.varType == VAR.RATIO) then
                            hp = true
                            kind = "heal"
                        end
                        if s.rel == REL.FRIEND and s.paramType == PARAM.MP
                            and (s.varType == VAR.UP or s.varType == VAR.RATIO) then
                            mp = true
                        end
                    end
                end
                if saysYes(bfl, "IsAbleRecoverHitPoint", id) or saysYes(lib, "IsAbleRecoverHitPoint", id) then hp = true end
                if saysYes(bfl, "IsAbleRecoverMagicPoint", id) or saysYes(lib, "IsAbleRecoverMagicPoint", id) then mp = true end
                if hp or mp or kind == "revive" or kind == "cure" then
                    out[#out + 1] = { id = id, name = name, hp = hp, mp = mp, kind = kind, count = count }
                end
            end
        end
    end
    if not itemsLogged then
        itemsLogged = true
        if #out == 0 then
            log("bag: no potion, ether, or phoenix down (%d item ids answered)", catalog)
        else
            local bits = {}
            for _, it in ipairs(out) do
                local tag = it.kind or (it.mp and "mp") or (it.hp and "hp") or "item"
                bits[#bits + 1] = string.format("%s x%s %s", it.name, tostring(it.count), tag)
            end
            log("bag: %s", table.concat(bits, ", "))
        end
    end
    return out
end

local function itemChoice(uid, item, reason, targetId, use)
    local fake = { id = item.id, name = item.name, kind = "item", attr = ATTR.ITEM, target = TGT.SINGLE, cost = 0 }
    local choice = finishChoice(uid, fake, reason, { targetId }, false, true)
    if choice then choice.itemUse = use end
    return choice
end

local function pickRecoveryItem(uid, w, want)
    if potFight(w) then return nil end
    local items = ownedRecovery()
    local function first(pred)
        for _, it in ipairs(items) do
            if pred(it) then return it end
        end
        return nil
    end
    if want == "revive" then
        local dead = firstDead(w, function(u) return u.acts ~= false end) or firstDead(w)
        if not dead then return nil end
        local it = first(function(it) return it.kind == "revive" end)
        if it then return itemChoice(uid, it, "item raise " .. dead.name, dead.id, "revive") end
        return nil
    end
    if want == "heal" then
        local hurt = lowestAlly(w)
        if not hurt then return nil end
        local it = first(function(it) return it.hp or it.kind == "heal" end)
        if not it then return nil end
        local pct = math.floor((hurt.hp or 0) * 100 + 0.5)
        return itemChoice(uid, it, string.format("item heal %s at %d%%", hurt.name, pct), hurt.id, "hp")
    end
    if want == "cure" then
        local who = lockedAlly(w)
        if not who then return nil end
        local it = first(function(it) return it.kind == "cure" end)
        if it then return itemChoice(uid, it, "item cure " .. who.name, who.id, "cure") end
        return nil
    end
    if want == "mp" then
        local it = first(function(it) return it.mp and it.kind ~= "revive" end)
        if it then return itemChoice(uid, it, "ether " .. unitName(uid), uid, "mp") end
    end
    return nil
end

--------------------------------------------------------------------------------
-- The field. The break ratio stays full, so the book gauge is the count.
--------------------------------------------------------------------------------

local function worldOf(uid, boss, summoned)
    local function gaugeOf(id, name)
        local apiLeft = breakLeft(id)
        local card = mobOf({ id = id, name = name })
        local gauge = card and tonumber(card.gauge) or nil
        if Fight then
            Fight.poured = Fight.poured or {}
            Fight.down = Fight.down or {}
            Fight.downTold = Fight.downTold or {}
            Fight.relax = Fight.relax or {}
            Fight.broke = Fight.broke or {}
            Fight.gaugeScale = Fight.gaugeScale or {}
            Fight.brokeOn = Fight.brokeOn or {}
            local scaled = Fight.gaugeScale[id]
            if scaled and (not gauge or scaled > gauge) then gauge = scaled end
        end
        local poured = (Fight and Fight.poured and Fight.poured[id]) or 0
        local down = (Fight and Fight.down and Fight.down[id]) and true or false
        local relaxed = Fight and Fight.relax and Fight.relax[id]
        local unmarked = Fight and Fight.unmarked and (not down)
        if unmarked and Fight and (not Fight.unmarkedTold) then
            Fight.unmarkedTold = true
            log("stagger counts unmarked. chipping from the book until a break shows")
            appendLog("  stagger counts unmarked")
        end
        if (not unmarked) and Fight and gauge and (gauge > 0) and (poured >= gauge) and (not relaxed) then
            Fight.down[id] = true
            Fight.brokeOn = Fight.brokeOn or {}
            Fight.brokeOn[id] = true
            down = true
            if not Fight.downSince then Fight.downSince = #(Fight.actions or {}) end
        end
        if down and Fight and not Fight.downTold[id] then
            Fight.downTold[id] = true
            local by = Fight.last and (Fight.last.who .. " (" .. Fight.last.skill .. ")") or "the party"
            Fight.broke[#Fight.broke + 1] = name .. " by " .. by
            appendLog("  broke: " .. name .. " by " .. by)
            log("%s staggered (%s/%s). bonus cashes them, next gauge is one still up",
                name, tostring(math.floor(poured + 0.5)), tostring(gauge or "?"))
        end
        local left = apiLeft
        if down then
            left = 0
        elseif unmarked then
            left = apiLeft
        elseif gauge and (gauge > 0) then
            local est = 1 - (poured / gauge)
            if est < 0 then est = 0 end
            if est > 1 then est = 1 end
            if relaxed and poured >= gauge then est = 0.15 end
            if apiLeft >= 0.99 then
                left = est
            elseif apiLeft < est then
                left = apiLeft
            else
                left = est
            end
        end
        return down and true or false, left
    end
    if Fight then Fight.gaugeOf = gaugeOf end
    local allies, enemies = {}, {}
    for _, id in ipairs(friendIds()) do
        local r = hpRatio(id)
        allies[#allies + 1] = {
            id = id, name = unitName(id), hp = r or 1,
            dead = (r ~= nil and r <= 0) or false, statuses = statuses(id),
        }
    end
    if #allies == 0 then
        local r = hpRatio(uid)
        allies[1] = { id = uid, name = unitName(uid), hp = r or 1, dead = false, statuses = statuses(uid) }
    end
    if Fight then
        if not Fight.seenAlly then Fight.seenAlly = {} end
        for _, a in ipairs(allies) do
            if not a.dead then Fight.seenAlly[a.id] = a.name end
        end
        for id, name in pairs(Fight.seenAlly) do
            local found = false
            for _, a in ipairs(allies) do
                if a.id == id then found = true break end
            end
            if not found then
                local r = hpRatio(id)
                if r == nil or r <= 0 then
                    allies[#allies + 1] = { id = id, name = name, hp = 0, dead = true, statuses = {} }
                end
            end
        end
    end
    local seenFoe = {}
    local function addEnemy(id)
        if not id or seenFoe[id] then return end
        if not keepFoe(id) then return end
        local r = hpRatio(id)
        if r ~= nil and r <= 0 then
            if Fight and Fight.seenFoe then Fight.seenFoe[id] = nil end
            return
        end
        seenFoe[id] = true
        local name = unitName(id)
        local isBroken, left = gaugeOf(id, name)
        enemies[#enemies + 1] = {
            id = id, name = name, hp = r or 1,
            broken = isBroken, breakLeft = left, statuses = statuses(id),
        }
        if Fight then
            Fight.seenFoe = Fight.seenFoe or {}
            Fight.seenFoe[id] = name
        end
    end
    for _, id in ipairs(members(REL.ENEMY)) do addEnemy(id) end
    local bfl = battleLib()
    if bfl and bfl:IsValid() then
        for n = 0, 15 do
            local ok, p = pcall(function() return bfl:GetBattleUnitParameter(n, true) end)
            if ok and p and p.IsValid and p:IsValid() then
                local okR, rel = pcall(function() return p:GetRelation() end)
                if okR and num(rel) == REL.ENEMY then addEnemy(n) end
            end
        end
    end
    if Fight and Fight.seenFoe then
        for id in pairs(Fight.seenFoe) do addEnemy(id) end
    end
    for _, a in ipairs(allies) do
        local kit = unitKit(a.id)
        a.acts = (kit and kit.spells and #kit.spells > 0) and true or false
    end
    local mp, maxMp = stat(uid, PARAM.MP, false) or 0, stat(uid, PARAM.MP, true) or 0
    return {
        selfId = uid, mp = mp, maxMp = maxMp,
        allies = allies, enemies = enemies, boss = boss, summoned = summoned,
        usedSupport = {},
    }
end

local function bossBattle()
    local bfl = battleLib()
    if not (bfl and bfl:IsValid()) then return false end
    local ok, v = pcall(function() return bfl:IsBossBattle() end)
    return ok and v == true
end

--------------------------------------------------------------------------------
-- Sending a command the way a menu choice does.
--------------------------------------------------------------------------------

local Menu = {
    open = false, serial = 0, actor = -1, decided = true, sub = false,
    byMod = false,
}
local Template = {}
Fight = {
    boss = false, summoned = false,
    actions = {}, casts = {}, castOrder = {}, usedSupport = {}, broke = {}, fell = {},
    scanned = {}, elemRun = {}, seenAlly = {},
    resonanceSent = false, resonanceMiss = false,
    last = nil, prev = {}, active = false, number = 0,
    poured = {}, down = {}, downTold = {}, relax = {}, gaugeScale = {}, brokeOn = {}, gaugeSure = {}, gaugeWas = {},
    downSince = nil, phaseSeen = 0, bonusSeen = false, lastHit = nil, line = false,
    prevHit = nil, building = nil, kits = {},
    claim = { heal = {}, revive = {}, hone = {}, ether = {}, scan = {}, etherRound = false, guard = false, debuff = false, esper = false, lb = false },
    went = {}, rounds = 0, seenFoe = {}, planTag = nil, afterBonus = false,
    fieldTold = false, chipped = false,
}

local function currentActor()
    local ss = FindFirstOf("CPP_UI_BattleSubsystem")
    if not (ss and ss:IsValid()) then return -1 end
    return num(ss.CurrentActionUnitUniqueId) or -1
end

local function currentPhase()
    local ss = FindFirstOf("CPP_UI_BattleSubsystem")
    if not (ss and ss:IsValid()) then return 0 end
    return num(ss.BtlPhaseType) or 0
end

local function inFinishPhase()
    if currentPhase() == PHASE_FINISH then return true end
    local bfl = battleLib()
    if not (bfl and bfl:IsValid()) then return false end
    local ok, v = pcall(function() return bfl:IsFinishPhase() end)
    return ok and v == true
end

local function learn(v)
    local items = {}
    local list = v.cmdDecideDataList
    if not (list and list.ForEach) then return end
    list:ForEach(function(_, e)
        local d = unwrap(e)
        if not d then return end
        local params = {}
        if d.ParameterList and d.ParameterList.ForEach then
            d.ParameterList:ForEach(function(_, x)
                local n = num(x)
                if n then params[#params + 1] = n end
            end)
        end
        items[#items + 1] = {
            actionId = num(d.actionId),
            isUseItem = d.isUseItem and true or false,
            IsAll = d.IsAll and true or false,
            pCat = d.ParentActionKey and num(d.ParentActionKey.Category) or 1,
            pId = d.ParentActionKey and num(d.ParentActionKey.ID) or 0,
            params = params,
        }
    end)
    if #items == 0 or not items[1].actionId then return end
    local keys = {}
    if v.actionKeys and v.actionKeys.ForEach then
        v.actionKeys:ForEach(function(_, e)
            local k = unwrap(e)
            if k then keys[#keys + 1] = { num(k.Category) or 0, num(k.ID) or 0 } end
        end)
    end
    Template[items[1].actionId] = {
        CmdType = num(v.CmdType) or 0,
        isNotConsume = v.isNotConsume and true or false,
        doCalcOrder = v.doCalcOrder ~= false,
        CommandId = num(v.CommandId) or -1,
        item = items[1],
        keys = keys,
    }
end

local function send(uid, choice, phase)
    local learned = (not choice.isItem) and Template[choice.id] or nil
    local cmdType = phase
    local commandId = choice.id
    local isNotConsume, doCalcOrder = false, true
    local pCat, pId = 1, choice.id
    local keys = { { 1, choice.id } }
    if learned then
        commandId = learned.CommandId
        isNotConsume = learned.isNotConsume
        doCalcOrder = learned.doCalcOrder
        pCat = learned.item.pCat or pCat
        pId = learned.item.pId or pId
        if #learned.keys > 0 then keys = learned.keys end
    else
        local limitCast = choice.attr == ATTR.LB
        if choice.known then
            local use = choice.known.use
            if (use == "lb-setup") or (use == "lb-cash") or (use == "lb-revive") then limitCast = true end
        end
        local bfl = battleLib()
        if bfl and bfl:IsValid() and (not limitCast) then
            local ok, enabled = pcall(function() return bfl:IsEnableCommand(uid, choice.id) end)
            if ok and enabled == false then commandId = -1 end
        end
    end
    local cls = StaticFindObject("/Script/mucha.CPP_BtlCmdDecideDelegateVal")
    local disp = FindFirstOf("CPP_MuchaEventDispatcher")
    if not (cls and cls:IsValid() and disp and disp:IsValid()) then
        log("could not build a command")
        return false
    end
    local obj = StaticConstructObject(cls, disp)
    obj.CmdType = cmdType
    obj.isNotConsume = isNotConsume
    obj.doCalcOrder = doCalcOrder
    obj.CommandId = commandId
    obj.cmdDecideDataList[1] = { actionId = choice.id, actionUnitUniqueId = uid }
    local d = obj.cmdDecideDataList[1]
    d.actionId = choice.id
    d.actionUnitUniqueId = uid
    d.isUseItem = choice.isItem and true or false
    d.IsAll = choice.isAll and true or false
    d.ParentActionKey.Category = pCat
    d.ParentActionKey.ID = pId
    for i, tid in ipairs(choice.targets) do
        d.targetUnitUniqueIdList[i] = tid
    end
    local params = (learned and learned.item.params) or {}
    for i, p in ipairs(params) do
        d.ParameterList[i] = p
    end
    for i, k in ipairs(keys) do
        obj.actionKeys[i] = { Category = k[1], ID = k[2] }
        obj.actionKeys[i].Category = k[1]
        obj.actionKeys[i].ID = k[2]
    end
    Menu.byMod = true
    local sentOk, sentErr = pcall(function()
        disp:ExecuteEvent({ TagName = FName("Delegate.Battle.Cmd.Decide") }, obj)
    end)
    if not sentOk then
        Menu.byMod = false
        log("send failed: %s", tostring(sentErr))
        return false
    end
    return true
end

--------------------------------------------------------------------------------
-- The turn. Friends, the weakness, the gauge, then what the last actor changed.
--------------------------------------------------------------------------------

local function usableOf(uid)
    local usable = {}
    for _, id in ipairs(equippedIds(uid)) do
        local copy = tagSkill(uid, id, false)
        if copy then usable[#usable + 1] = copy end
    end
    local haveFight = false
    for _, s in ipairs(usable) do
        if s.attr == ATTR.FIGHT then haveFight = true end
    end
    if not haveFight and SkillIdx then
        for id, s in pairs(SkillIdx) do
            if s.attr == ATTR.FIGHT and activation(uid, id) == true then
                local copy = tagSkill(uid, id, true)
                if copy then usable[#usable + 1] = copy end
                break
            end
        end
    end
    return usable
end

local function pickFinish(uid, finishes, w)
    local list = {}
    for _, s in ipairs(finishes or {}) do
        if s.attr == ATTR.FINISH then list[#list + 1] = s end
    end
    if #list == 0 then return nil end
    local hurt, wounded = nil, 0
    for _, u in ipairs(w.allies or {}) do
        if not u.dead then
            if not hurt or (u.hp or 1) < (hurt.hp or 1) then hurt = u end
            if (u.hp or 1) < 0.40 then wounded = wounded + 1 end
        end
    end
    local function emit(skill, reason, targets, isAll, score)
        local choice = finishChoice(uid, skill, reason, targets, isAll)
        if choice then choice.score = score end
        return choice
    end
    if hurt and ((hurt.hp or 1) < 0.40 or wounded >= 2) then
        for _, s in ipairs(list) do
            local heal = s.kind == "heal" or s.kind == "revive" or (s.known and s.known.use == "heal")
            if heal then
                local targets = partyOf(s) and idsOf(w.allies) or { hurt.id }
                local choice = emit(s, "resonance heal " .. hurt.name, targets, partyOf(s), 100000)
                if choice then return choice end
            end
        end
    end
    local best, bestR = nil, -1
    for _, s in ipairs(list) do
        local support = s.kind == "heal" or s.kind == "buff" or s.kind == "revive"
            or (s.known and (s.known.use == "heal" or s.known.use == "buff" or s.known.use == "guardbuff"))
        if not support then
            local pow = offenseOf(s)
            local factor = 1
            for _, u in ipairs(w.enemies or {}) do
                local f = elementFactor(s, u)
                if f > factor then factor = f end
            end
            if factor > 0 then
                local r = pow * ((factor >= 3) and 1.5 or factor)
                if r > bestR then best, bestR = s, r end
            end
        end
    end
    if not best then best, bestR = list[1], 10 end
    local support = best.kind == "heal" or best.kind == "buff" or best.kind == "revive"
    local foe = nil
    for _, u in ipairs(w.enemies or {}) do
        if not foe or (u.hp or 1) < (foe.hp or 1) then foe = u end
    end
    local tid = (foe and foe.id) or (Fight and Fight.building) or uid
    local targets, isAll
    if support then
        local who = hurt or (w.allies and w.allies[1])
        targets = partyOf(best) and idsOf(w.allies) or { who and who.id or uid }
        isAll = partyOf(best)
    else
        isAll = aoeOf(best) and #(w.enemies or {}) > 1
        targets = isAll and idsOf(w.enemies) or { tid }
    end
    local name = foe and foe.name or "the field"
    return emit(best, "resonance " .. name, targets, isAll, bestR)
end

local function finishList(uid)
    local function asFinish(id)
        local s = skillOf(id)
        local copy = {}
        if s then
            for k, v in pairs(s) do copy[k] = v end
        else
            copy.id = id
            copy.name = "Resonance"
            copy.power = 1
            copy.breakPower = 0
            copy.target = TGT.SINGLE
            copy.rel = REL.ENEMY
            copy.effect = EFF.DAMAGE
            copy.hits = 1
            copy.friendStatus = {}
            copy.enemyStatus = {}
        end
        copy.attr = ATTR.FINISH
        copy.cost = 0
        copy.known = knownOf(copy)
        local okKind, kind = pcall(classify, copy)
        copy.kind = (okKind and kind) or "damage"
        local info = copy.known
        if info and info.use == "heal" then copy.kind = "heal" end
        if info and (info.use == "buff" or info.use == "guardbuff") then copy.kind = "buff" end
        if info and info.use == "finish" and copy.kind ~= "heal" and copy.kind ~= "buff" then
            copy.kind = "damage"
        end
        return copy
    end
    local function visionFinishMap()
        if Fight and Fight.visionFinish then return Fight.visionFinish end
        local map, rows = {}, 0
        local tables = FindAllOf("DataTable") or {}
        for _, dt in ipairs(tables) do
            pcall(function()
                if type(dt) ~= "userdata" or not dt:IsValid() then return end
                if rowStructName(dt) ~= "VISION_ITEM_DATA" then return end
                dt:ForEachRow(function(_, row)
                    rows = rows + 1
                    local id = num(field(row, "ID"))
                    local fin = num(field(row, "finishBlowSkill"))
                    if id and fin and fin > 0 then map[id] = fin end
                end)
            end)
        end
        local n, lo, hi = 0, nil, nil
        for id in pairs(map) do
            n = n + 1
            if not lo or id < lo then lo = id end
            if not hi or id > hi then hi = id end
        end
        log("vision finishers: %d from %d rows, ids %s-%s", n, rows, tostring(lo), tostring(hi))
        if Fight then Fight.visionFinish = map end
        return map
    end
    local function unitFinishId(who)
        local map = visionFinishMap()
        local function fromVision(v)
            local n = num(v)
            if n and map[n] then return map[n] end
            return nil
        end
        local function fromObject(obj)
            if type(obj) ~= "userdata" then return fromVision(obj) end
            for _, key in ipairs({ "equipVisionId", "EquipVisionId", "visionId", "VisionId", "VisionID" }) do
                local fin = fromVision(field(obj, key))
                if fin then return fin end
            end
            local fin = num(field(obj, "finishBlowSkill"))
            if fin and fin > 0 then return fin end
            return nil
        end
        local p = paramOf(who)
        if p then
            local fin = fromObject(p)
            if fin then return fin end
            local okd, data = pcall(function() return p.visionData end)
            if okd then
                fin = fromObject(data)
                if fin then return fin end
            end
            for _, method in ipairs({ "GetVisionId", "GetEquipVisionId" }) do
                local okm, v = pcall(function() return p[method](p) end)
                fin = okm and fromVision(v) or nil
                if fin then return fin end
            end
        end
        local hits = {}
        for _, id in ipairs(equippedIds(who)) do
            if map[id] then hits[#hits + 1] = id end
        end
        if #hits == 1 then return map[hits[1]] end
        return nil
    end
    local out, seen = {}, {}
    local function add(id)
        id = num(id)
        if not id or id <= 0 or seen[id] then return end
        seen[id] = true
        out[#out + 1] = asFinish(id)
    end
    local unknown = {}
    for _, id in ipairs(equippedIds(uid)) do
        local s = skillOf(id)
        if s and s.attr == ATTR.FINISH then add(id)
        elseif not s then unknown[#unknown + 1] = tostring(id) end
    end
    add(unitFinishId(uid))
    if Fight then
        Fight.finishNote = Fight.finishNote or {}
        Fight.finishNote[uid] = #unknown > 0 and table.concat(unknown, ",") or ""
    end
    if #out > 0 then return out end
    if Fight and Fight.finishScan and Fight.finishScan[uid] then
        for _, id in ipairs(Fight.finishScan[uid]) do add(id) end
        return out
    end
    if not SkillIdx then return out end
    local bfl = battleLib()
    local found = {}
    if bfl and bfl:IsValid() then
        for id, s in pairs(SkillIdx) do
            if s.attr == ATTR.FINISH then
                local ok, can = pcall(function() return bfl:CanUnitActivateSkill(uid, id) end)
                if ok and can == true then
                    found[#found + 1] = id
                    add(id)
                end
            end
        end
    end
    if Fight then
        Fight.finishScan = Fight.finishScan or {}
        Fight.finishScan[uid] = found
    end
    return out
end

local function turn(uid, skills, w, phase)
    -- One slot of the round. Care first, then the phase the whole field is in.
    -- Damage is scored against every living gauge, using what earlier slots already claimed.
    w.usedSupport = w.usedSupport or {}
    Fight.claim = Fight.claim or {
        heal = {}, revive = {}, hone = {}, ether = {},
        guard = false, debuff = false, esper = false, lb = false, scan = {},
        etherRound = false,
    }
    Fight.scanned = Fight.scanned or {}
    Fight.poured = Fight.poured or {}
    Fight.down = Fight.down or {}
    Fight.relax = Fight.relax or {}
    Fight.gaugeScale = Fight.gaugeScale or {}
    Fight.brokeOn = Fight.brokeOn or {}

    local function pay(s)
        return (s.cost or 0) <= (w.mp or 0)
    end
    local function useOf(s)
        return s.known and s.known.use or nil
    end
    local function band()
        local maxv = w.maxMp or 0
        if maxv <= 0 then return "low" end
        local ratio = (w.mp or 0) / maxv
        if ratio > 0.50 then return "high" end
        if ratio >= 0.20 then return "mid" end
        return "low"
    end
    local function realCure(s)
        if s.kind ~= "heal" then return false end
        if s.known and s.known.patch then return false end
        return true
    end
    local function isPatch(s)
        return s.known and s.known.patch and true or false
    end
    local function isHit(s, cashing)
        if s.kind == "heal" or s.kind == "buff" or s.kind == "debuff" or s.kind == "cure"
            or s.kind == "revive" or s.kind == "defend" or s.kind == "scan" then
            return false
        end
        if s.attr == ATTR.SUMMON or s.attr == ATTR.FINISH or s.attr == ATTR.ITEM then return false end
        local use = useOf(s)
        if use == "opener" or use == "guardbuff" or use == "guard" or use == "scan" or use == "heal" or use == "cure" then
            return false
        end
        if use == "lb-setup" or use == "lb-revive" then return false end
        if (s.attr == ATTR.LB) or (use == "lb-cash") then
            if cashing then return true end
            return false
        end
        return s.kind == "damage" or s.attr == ATTR.FIGHT or s.attr == ATTR.MAGIC or s.attr == ATTR.ABILITY
    end
    local function gaugeOfEnemy(enemy)
        local card = mobOf(enemy)
        local gauge = (card and tonumber(card.gauge)) or 100
        local scaled = Fight.gaugeScale and Fight.gaugeScale[enemy.id]
        if scaled and scaled > gauge then gauge = scaled end
        if Fight.down[enemy.id] then return gauge, 0, true, card end
        local poured = Fight.poured[enemy.id] or 0
        local remain = gauge - poured
        if remain < 0 then remain = 0 end
        return gauge, remain, remain <= 0, card
    end
    local function handOf(s, enemy)
        return (counterScale(s, enemy) or 1) * (monoScale(s, enemy) or 1)
    end
    local function staggerOf(s, enemy)
        local f = elementFactor(s, enemy)
        if f <= 0 then return 0, f end
        local _, br = offenseOf(s)
        return (br or 0) * f * handOf(s, enemy), f
    end
    local function allyCritical()
        local who = nil
        for _, a in ipairs(w.allies) do
            if not a.dead and (a.hp or 1) < 0.30 and not Fight.claim.heal[a.id] then
                if not who or (a.hp or 1) < (who.hp or 1) then who = a end
            end
        end
        return who
    end

    if phase == PHASE_FINISH then
        local finishes = {}
        for _, s in ipairs(skills) do
            if s.attr == ATTR.FINISH then finishes[#finishes + 1] = s end
        end
        if #finishes == 0 then
            local ok, extra = pcall(finishList, uid)
            if ok and type(extra) == "table" then finishes = extra end
        end
        return pickFinish(uid, finishes, w)
    end

    local open, brokenPool = {}, {}
    local waitParty = 0
    for _ in pairs(Fight.seenAlly or {}) do waitParty = waitParty + 1 end
    if waitParty < 2 then waitParty = 2 end
    local actionsN = #(Fight.actions or {})
    for _, u in ipairs(w.enemies) do
        local _, remain, empty = gaugeOfEnemy(u)
        local waiting = false
        local rec = Fight.gaugeWas and Fight.gaugeWas[u.id]
        if rec and (type(rec.size) == "number") and ((actionsN - (rec.at or 0)) <= waitParty) then
            waiting = true
        end
        if u.broken or empty or waiting then brokenPool[#brokenPool + 1] = u
        else open[#open + 1] = u end
    end

    local hardField = false
    local function styleOf()
        local healers = 0
        hardField = w.boss and true or false
        for _, a in ipairs(w.allies) do
            if not a.dead and a.acts ~= false then
                local kit = unitKit(a.id)
                if kit and (kit.healScore or 0) >= 50 then
                    local mp = stat(a.id, PARAM.MP, false) or 0
                    local cost = kit.healCost or 0
                    if cost <= 0 or mp >= cost then healers = healers + 1 end
                end
            end
        end
        for _, u in ipairs(w.enemies) do
            local card = mobOf(u)
            if card and card.danger and card.danger[1] then hardField = true end
        end
        if hardField and healers == 0 then return "defensive" end
        if hardField then return "balanced" end
        if healers > 0 then return "aggressive" end
        return "balanced"
    end
    local style = styleOf()

    local function modeOf(list)
        if #list <= 1 then return "sync", list, nil end
        local maxGauge = 0
        for _, u in ipairs(list) do
            local gauge = gaugeOfEnemy(u)
            if gauge > maxGauge then maxGauge = gauge end
        end
        local large, small = {}, {}
        for _, u in ipairs(list) do
            local gauge = gaugeOfEnemy(u)
            if maxGauge > 0 and gauge <= maxGauge * 0.6 then
                small[#small + 1] = u
            else
                large[#large + 1] = u
            end
        end
        if #small > 0 and #large > 0 then return "adds", small, large[1] end
        return "sync", list, large[1] or list[1]
    end
    local mode, pool, bossU = modeOf(open)
    if style == "defensive" and allyCritical() and bossU then
        local card = mobOf(bossU)
        if card and card.danger and card.danger[1] then
            local _, remain, _, _ = gaugeOfEnemy(bossU)
            local gauge = gaugeOfEnemy(bossU)
            if remain < gauge * 0.40 then
                pool = { bossU }
                mode = "sync"
            end
        end
    end
    local tag = mode .. "/" .. style
    if Fight.planTag ~= tag then
        Fight.planTag = tag
        local bits = {}
        for _, u in ipairs(pool) do bits[#bits + 1] = u.name end
        local line = string.format("plan %s. pool: %s", tag, (#bits > 0) and table.concat(bits, ", ") or "none")
        log("%s", line)
        appendLog("  " .. line)
    end

    for _, a in ipairs(w.allies) do
        if not a.dead then Fight.claim.revive[a.id] = nil end
    end
    local dead = firstDead(w, function(u) return u.acts ~= false end) or firstDead(w)
    if dead and Fight.claim.revive[dead.id] then
        local at = Fight.claim.revive[dead.id]
        local waitN = #w.allies
        if waitN < 2 then waitN = 2 end
        if (type(at) == "number") and ((#(Fight.actions or {}) - at) >= waitN) then
            Fight.claim.revive[dead.id] = nil
        end
    end
    if dead and not Fight.claim.revive[dead.id] then
        local oneLeft, calm = #w.enemies <= 1, true
        for _, u in ipairs(w.enemies) do
            local card = mobOf(u)
            if card and card.danger and card.danger[1] then calm = false end
            local _, remain, empty, _ = gaugeOfEnemy(u)
            local gauge = gaugeOfEnemy(u)
            if not empty and remain > gauge * 0.25 then calm = false end
        end
        if not (oneLeft and calm) then
            for _, s in ipairs(skills) do
                if s.kind == "revive" and pay(s) then
                    local choice = finishChoice(uid, s, "raise " .. dead.name, { dead.id }, false)
                    if choice then Fight.claim.revive[dead.id] = #(Fight.actions or {}) return choice end
                end
            end
            local item = pickRecoveryItem(uid, w, "revive")
            if item then Fight.claim.revive[dead.id] = #(Fight.actions or {}) return item end
        end
    end

    local function healNow(hurt, why, itemAt)
        if not hurt or Fight.claim.heal[hurt.id] then return nil end
        local skill, rank = nil, -1
        local hurtN = 0
        for _, a in ipairs(w.allies) do
            if not a.dead and (a.hp or 1) < 0.50 then hurtN = hurtN + 1 end
        end
        for _, s in ipairs(skills) do
            if (s.kind == "heal") and pay(s) and (not isPatch(s)) then
                local cost = s.cost or 0
                if cost < 1 then cost = 1 end
                local power = s.power or 0
                local party = partyOf(s)
                local r
                if power > 0 then
                    r = power / cost
                    if (hurtN >= 3) and party then r = r * 3 end
                elseif (hurtN >= 3) and party then
                    r = 3 + (0.01 / cost)
                elseif party then
                    r = 0.5 + (0.01 / cost)
                else
                    r = 1 + (0.01 / cost)
                end
                if r > rank then skill, rank = s, r end
            end
        end
        local itemLine = itemAt or 0.45
        if (not skill) and ((hurt.hp or 1) < itemLine) then
            local item = pickRecoveryItem(uid, w, "heal")
            if item then Fight.claim.heal[hurt.id] = true return item end
        end
        local blocked = false
        for _, s in ipairs(skills) do
            if realCure(s) then
                if pay(s) then blocked = false break end
                blocked = true
            end
        end
        if (not skill) and blocked and (not Fight.claim.ether[uid]) and (not Fight.claim.etherRound) then
            local ether = pickRecoveryItem(uid, w, "mp")
            if ether then
                ether.reason = "ether so a cure fits"
                Fight.claim.ether[uid] = true
                Fight.claim.etherRound = true
                return ether
            end
        end
        if not skill then
            for _, s in ipairs(skills) do
                if (s.kind == "heal") and pay(s) and isPatch(s) then
                    if not (w.usedSupport[s.id] and ((hurt.hp or 1) >= 0.22)) then
                        w.usedSupport[s.id] = true
                        skill = s
                        break
                    end
                end
            end
        end
        if skill then
            local spread = partyOf(skill) and (not isPatch(skill))
            local pct = math.floor((hurt.hp or 0) * 100 + 0.5)
            local choice = finishChoice(uid, skill, string.format("%s %s at %d%%", why, hurt.name, pct),
                spread and idsOf(w.allies) or { hurt.id }, spread)
            if choice then Fight.claim.heal[hurt.id] = true return choice end
        end
        return nil
    end

    local crit = allyCritical()
    local function deferHeal()
        if phase == PHASE_BONUS then return false end
        if crit and (crit.hp or 1) < 0.15 then return false end
        local list = (#pool > 0) and pool or open
        local function pays(spells, mp)
            for _, s in ipairs(spells) do
                if s.kind ~= "heal" and s.kind ~= "buff" and s.kind ~= "debuff"
                    and s.kind ~= "cure" and s.kind ~= "revive" and s.kind ~= "defend"
                    and s.kind ~= "scan" and (s.cost or 0) <= mp then
                    for _, u in ipairs(list) do
                        if elementFactor(s, u) >= 3 then return true end
                    end
                end
            end
            return false
        end
        if not pays(skills, w.mp or 0) then return false end
        local others, otherPays = 0, false
        for _, a in ipairs(w.allies) do
            if a.id ~= uid and not a.dead and a.acts ~= false then
                others = others + 1
                local kit = unitKit(a.id)
                local mp = stat(a.id, PARAM.MP, false) or 0
                if kit and pays(kit.spells or {}, mp) then otherPays = true end
            end
        end
        return others > 0 and not otherPays
    end
    if crit and phase ~= PHASE_BONUS and not deferHeal() then
        local choice = healNow(crit, "critical")
        if choice then return choice end
    end
    if phase == PHASE_BONUS or #brokenPool > 0 and phase == PHASE_BONUS then
        local choice = healNow(crit, "critical")
        if choice then return choice end
    end

    local who = lockedAlly(w)
    if who and phase ~= PHASE_BONUS and not Fight.claim.heal[who.id] then
        for _, s in ipairs(skills) do
            if s.kind == "cure" and pay(s) then
                local choice = finishChoice(uid, s, "cure " .. who.name, { who.id }, aoeOf(s))
                if choice then Fight.claim.heal[who.id] = true return choice end
            end
        end
        local item = pickRecoveryItem(uid, w, "cure")
        if item then Fight.claim.heal[who.id] = true return item end
    end

    local recoverAt = 0.50
    for _, u in ipairs(w.enemies) do
        local card = mobOf(u)
        if card and card.danger and card.danger[1] then
            local _, _, empty = gaugeOfEnemy(u)
            if not empty and not u.broken then recoverAt = 0.65 end
        end
    end
    local function underMark()
        local n, who = 0, nil
        for _, a in ipairs(w.allies) do
            if not a.dead and (a.hp or 1) < recoverAt and not Fight.claim.heal[a.id] then
                if a.acts ~= false then
                    n = n + 1
                    if not who or (a.hp or 1) < (who.hp or 1) then who = a end
                end
            end
        end
        return n, who
    end
    local halfN, halfWho = underMark()
    local recoverGate = recoverAt > 0.50 or (band() == "high"
        and (Fight.afterBonus or (style == "defensive" and halfN >= 2)))
    if halfWho and phase ~= PHASE_BONUS and not deferHeal() and recoverGate then
        local choice = healNow(halfWho, "recover", recoverAt > 0.50 and recoverAt or 0.50)
        if choice then return choice end
    end

    local function debuffOwed()
        if phase ~= 0 or not hardField or style == "aggressive" or Fight.claim.debuff then return false end
        if Fight.fell and #Fight.fell > 0 then return false end
        if allyCritical() then return false end
        for _, a in ipairs(w.allies) do
            if a.dead then return false end
        end
        for _, a in ipairs(w.allies) do
            if not a.dead and a.acts ~= false then
                local kit = unitKit(a.id)
                local mp = stat(a.id, PARAM.MP, false) or 0
                if kit then
                    for _, s in ipairs(kit.spells or {}) do
                        if (useOf(s) == "debuff" or s.kind == "debuff") and (s.cost or 0) <= mp then
                            return true
                        end
                    end
                end
            end
        end
        return false
    end
    local function guardOwed()
        if phase ~= 0 or not hardField or style == "aggressive" or Fight.claim.guard then return false end
        if Fight.fell and #Fight.fell > 0 then return false end
        if allyCritical() then return false end
        for _, a in ipairs(w.allies) do
            if a.dead then return false end
        end
        for _, a in ipairs(w.allies) do
            if not a.dead and a.acts ~= false then
                local kit = unitKit(a.id)
                local mp = stat(a.id, PARAM.MP, false) or 0
                if kit then
                    for _, s in ipairs(kit.spells or {}) do
                        if useOf(s) == "guardbuff" and (s.cost or 0) <= mp then
                            return true
                        end
                    end
                end
            end
        end
        return false
    end
    -- The weakness can sit on someone else. A setup Limit on the buffer
    -- must not be skipped because that buffer has no weakness spell.
    local function partyWeak(skipId, skipCost)
        local foes = (#pool > 0) and pool or open
        if #foes == 0 then foes = w.enemies end
        for _, a in ipairs(w.allies) do
            if not a.dead and a.acts ~= false then
                local mp = (a.id == uid) and (w.mp or 0) or (stat(a.id, PARAM.MP, false) or 0)
                if a.id == skipId then mp = mp - (skipCost or 0) end
                if mp >= 0 then
                    local spells = skills
                    if a.id ~= uid then
                        local kit = unitKit(a.id)
                        spells = (kit and kit.spells) or {}
                    end
                    for _, foe in ipairs(foes) do
                        for _, s in ipairs(spells) do
                            if isHit(s, false) and (elementFactor(s, foe) >= 3) and ((s.cost or 0) <= mp) then
                                return true
                            end
                        end
                    end
                end
            end
        end
        return false
    end
    local lbOwedFlag = nil
    local function lbOwed()
        if lbOwedFlag ~= nil then return lbOwedFlag end
        lbOwedFlag = false
        if phase ~= 0 or not hardField or Fight.claim.lb or Fight.chipped then return false end
        if Fight.fell and #Fight.fell > 0 then return false end
        if allyCritical() then return false end
        for _, a in ipairs(w.allies) do
            if a.dead then return false end
        end
        for _, a in ipairs(w.allies) do
            if not a.dead and a.acts ~= false then
                local mp = (a.id == uid) and (w.mp or 0) or (stat(a.id, PARAM.MP, false) or 0)
                local ids = equippedIds(a.id)
                for _, id in ipairs(ids) do
                    local s = tagSkill(a.id, id, false)
                    if s and useOf(s) == "lb-setup" and (s.cost or 0) <= mp then
                        local keeps = partyWeak(a.id, s.cost or 0) or not partyWeak(nil, 0)
                        if keeps then lbOwedFlag = true return true end
                    end
                end
            end
        end
        return false
    end
    local function burstTargets()
        local held = {}
        local mark = Fight.brokeOn or {}
        for _, u in ipairs(w.enemies) do
            if mark[u.id] or Fight.down[u.id] or u.broken then
                held[#held + 1] = u
            end
        end
        if #held > 0 then return held end
        if #brokenPool > 0 then return brokenPool end
        local best, bestScore = nil, -1
        for _, u in ipairs(w.enemies) do
            local gauge, remain = gaugeOfEnemy(u)
            local score = (gauge > 0) and ((gauge - remain) / gauge) or 0
            if score > bestScore then best, bestScore = u, score end
        end
        if best then return { best } end
        return w.enemies
    end
    local function castDamage(pool, cashing, why)
        if not pool or #pool == 0 then return nil end
        local bestS, bestU, bestScore, bestSpread = nil, nil, -1e9, false
        local function considerSkill(s, targets, spread)
            if not pay(s) then return end
            local spendLb = (useOf(s) == "lb-cash") or (s.attr == ATTR.LB)
            if spendLb and (not hardField) then return end
            if (not cashing) and (debuffOwed() or guardOwed() or lbOwed()) and ((s.cost or 0) > 0) then return end
            local b = band()
            local useful, pts, weak, finishes, early = 0, 0, false, false, false
            for _, u in ipairs(targets) do
                local gauge, remain, empty = gaugeOfEnemy(u)
                local gained, f = staggerOf(s, u)
                local held = (why == "fill")
                if f > 0 and (cashing or (((not empty) or held) and (gained > 0))) then
                    local heavy = false
                    local pow, br = offenseOf(s)
                    if br >= 25 then heavy = true end
                    local allowed = cashing or b == "high" or (s.cost or 0) <= 0 or f >= 3 or heavy
                    if not cashing and b == "low" then allowed = ((s.cost or 0) <= 0) or (f >= 3) end
                    if allowed then
                        useful = useful + 1
                        if cashing then pts = pts + (pow or 0) * f
                        else pts = pts + gained end
                        if f >= 3 then weak = true end
                        if not empty and gained >= remain then finishes = true end
                    end
                end
            end
            if useful == 0 then return end
            if finishes and not cashing and why ~= "burst" then
                for _, other in ipairs(pool) do
                    local gauge, remain, empty = gaugeOfEnemy(other)
                    local hit = false
                    for _, t in ipairs(targets) do
                        if t.id == other.id then hit = true end
                    end
                    if not hit and not empty and remain > gauge * 0.40 then early = true end
                end
            end
            if early and weak then
                local canChip = false
                for _, other in ipairs(skills) do
                    if pay(other) and isHit(other, false) then
                        for _, u in ipairs(pool) do
                            local _, remain, empty = gaugeOfEnemy(u)
                            if not empty then
                                local gained, f = staggerOf(other, u)
                                if f >= 3 and gained > 0 and gained < remain then canChip = true end
                            end
                        end
                    end
                end
                if not canChip then early = false end
            end
            local score = pts
            if weak then score = score + 5000 end
            if spread and useful > 1 then score = score + pts end
            if finishes and cashing then score = score + 4000 end
            if finishes and not cashing and not early then score = score + 8000 - (s.cost or 0) * 20 end
            if finishes and not cashing and early then score = score - 8000 end
            if handOf(s, targets[1]) < 0.5 then score = score - 2000 end
            local threat = 0
            for _, u in ipairs(targets) do
                local card = mobOf(u)
                if card and card.danger and card.danger[1] then threat = 200 end
                if card and card.call and threat < 100 then threat = 100 end
            end
            score = score + threat
            -- A Limit row often has no magnification. On a hard break it is the cash,
            -- so a missing power must not lose to a normal spell. Trash keeps the gauge.
            if cashing and hardField and spendLb then score = score + 100000 end
            if score > bestScore then
                bestS, bestU, bestScore, bestSpread = s, targets[1], score, spread and true or false
            end
        end
        for _, s in ipairs(skills) do
            if isHit(s, cashing) then
                local safe = {}
                if aoeOf(s) then
                    local ok = true
                    for _, u in ipairs(pool) do
                        if elementFactor(s, u) <= 0 then ok = false end
                    end
                    if ok and #pool > 1 then
                        for _, u in ipairs(pool) do safe[#safe + 1] = u end
                        considerSkill(s, safe, true)
                    end
                end
                for _, u in ipairs(pool) do
                    considerSkill(s, { u }, false)
                end
            end
        end
        if not bestS then return nil end
        local targets = bestSpread and idsOf(pool) or { bestU.id }
        local el = (bestS.known and bestS.known.element) or ""
        local name = bestSpread and (#pool .. " foes") or bestU.name
        local reason = why .. " " .. name
        if el ~= "" and elementFactor(bestS, bestU) >= 3 then reason = reason .. " " .. el end
        if (not cashing) and ((bestS.cost or 0) <= 0) and (debuffOwed() or guardOwed() or lbOwed()) then
            reason = reason .. ", setup still open"
        end
        return finishChoice(uid, bestS, reason, targets, bestSpread)
    end

    if phase == PHASE_BONUS then
        return castDamage(burstTargets(), true, "burst")
    end
    if #open == 0 and #brokenPool > 0 then
        if phase == PHASE_BONUS then
            return castDamage(brokenPool, true, "burst")
        end
        return castDamage(brokenPool, false, "fill")
    end

    local function weaknessFits(extra)
        local mp = (w.mp or 0) - (extra or 0)
        if mp < 0 then return false end
        for _, foe in ipairs(#pool > 0 and pool or open) do
            for _, s in ipairs(skills) do
                if isHit(s, false) and elementFactor(s, foe) >= 3 and (s.cost or 0) <= mp then
                    return true
                end
            end
        end
        return false
    end
    local function firstSkill(pred)
        for _, s in ipairs(skills) do
            if pred(s) and pay(s) then return s end
        end
        return nil
    end

    local alreadyFell = Fight.fell and #Fight.fell > 0
    if not Fight.chipped and phase == 0 and not alreadyFell and not allyCritical() and not dead then
        local scanTarget = nil
        for _, u in ipairs(#pool > 0 and pool or w.enemies) do
            if not Fight.scanned[u.id] and not Fight.claim.scan[u.id] then
                local card = mobOf(u)
                if not card or card.shift then scanTarget = u break end
            end
        end
        if scanTarget then
            local spell = firstSkill(function(s) return s.kind == "scan" end)
            if spell then
                local choice = finishChoice(uid, spell, "scout " .. scanTarget.name, { scanTarget.id }, false)
                if choice then
                    Fight.scanned[scanTarget.id] = true
                    Fight.claim.scan[scanTarget.id] = true
                    return choice
                end
            end
        end
        if not Fight.claim.hone[uid] then
            local s = firstSkill(function(x) return useOf(x) == "opener" end)
            if s and weaknessFits(s.cost or 0) then
                local choice = finishChoice(uid, s, "setup opener", { uid }, false)
                if choice then Fight.claim.hone[uid] = true return choice end
            end
        end
        local bossFight = hardField
        if bossFight and style ~= "aggressive" and not Fight.claim.guard then
            local s = firstSkill(function(x) return useOf(x) == "guardbuff" end)
            if s then
                local spread = aoeOf(s)
                local choice = finishChoice(uid, s, "setup guard", spread and idsOf(w.allies) or { uid }, spread)
                if choice then Fight.claim.guard = true return choice end
            end
        end
        if bossFight and style ~= "aggressive" and not Fight.claim.debuff then
            local s = firstSkill(function(x) return useOf(x) == "debuff" or x.kind == "debuff" end)
            local foe, foeGauge, foeDanger = nil, -1, false
            for _, u in ipairs(w.enemies) do
                local _, _, empty = gaugeOfEnemy(u)
                if not empty then
                    local card = mobOf(u)
                    local danger = card and card.danger and card.danger[1] and true or false
                    local gauge = gaugeOfEnemy(u)
                    if not foe or (danger and not foeDanger) or (danger == foeDanger and gauge > foeGauge) then
                        foe, foeGauge, foeDanger = u, gauge, danger
                    end
                end
            end
            foe = foe or pool[1] or open[1] or w.enemies[1]
            if s and foe then
                local choice = finishChoice(uid, s, "setup debuff " .. foe.name, { foe.id }, false)
                if choice then Fight.claim.debuff = true return choice end
            end
        end
        if bossFight and not Fight.claim.lb then
            local s = firstSkill(function(x) return useOf(x) == "lb-setup" end)
            if s and (partyWeak(uid, s.cost or 0) or not partyWeak(nil, 0)) then
                local foe = pool[1] or open[1]
                if foe then
                    local choice = finishChoice(uid, s, "setup lb " .. foe.name, { foe.id }, aoeOf(s))
                    if choice then Fight.claim.lb = true return choice end
                end
            end
        end
        if bossFight and style ~= "aggressive" and not Fight.claim.esper and not Fight.summoned then
            local s = firstSkill(function(x) return x.attr == ATTR.SUMMON end)
            if s and (weaknessFits(s.cost or 0) or #w.enemies >= 3) then
                local foe = pool[1] or open[1]
                if foe then
                    local spread = aoeOf(s)
                    local choice = finishChoice(uid, s, "setup esper", spread and idsOf(pool) or { foe.id }, spread)
                    if choice then Fight.claim.esper = true return choice end
                end
            end
        end
    end
    if phase == 0 and hardField and not Fight.claim.lb then
        local s = firstSkill(function(x) return useOf(x) == "lb-setup" end)
        if s and (partyWeak(uid, s.cost or 0) or not partyWeak(nil, 0)) then
            local foe = pool[1] or open[1] or w.enemies[1]
            if foe then
                local choice = finishChoice(uid, s, "setup lb " .. foe.name, { foe.id }, aoeOf(s))
                if choice then Fight.claim.lb = true return choice end
            end
        end
    end

    local function unpaidWeakness(list)
        for _, s in ipairs(skills) do
            if isHit(s, false) and (s.cost or 0) > (w.mp or 0) then
                for _, u in ipairs(list) do
                    if elementFactor(s, u) >= 3 then return true end
                end
            end
        end
        return false
    end
    if band() == "low" and not Fight.claim.ether[uid] and not Fight.claim.etherRound then
        local list = #pool > 0 and pool or open
        if unpaidWeakness(list) then
            local ether = pickRecoveryItem(uid, w, "mp")
            if ether then
                ether.reason = "ether so the weakness fits"
                Fight.claim.ether[uid] = true
                Fight.claim.etherRound = true
                return ether
            end
        end
    end

    local chip = castDamage(#pool > 0 and pool or open, false, mode)
    if chip then return chip end
    if mode == "adds" and bossU then
        chip = castDamage({ bossU }, false, "boss")
        if chip then return chip end
    end
    chip = castDamage(w.enemies, false, "field")
    if chip then return chip end
    if debuffOwed() or guardOwed() then Fight.deferChip = true end
    return nil
end

local function livingSnapshot()
    local snap = {}
    for _, id in ipairs(friendIds()) do
        snap[id] = { side = "ally", name = unitName(id), hp = hpRatio(id) or 1, broken = false }
    end
    for _, id in ipairs(members(REL.ENEMY)) do
        snap[id] = { side = "enemy", name = unitName(id), hp = hpRatio(id) or 1, broken = broken(id) }
    end
    return snap
end

local function noteChanges(now)
    local last = Fight.last
    for id, was in pairs(Fight.prev) do
        local cur = now[id]
        if was.side == "ally" and was.hp > 0 and (not cur or cur.hp <= 0) then
            Fight.fell[#Fight.fell + 1] = was.name
            appendLog("  fell: " .. was.name)
        end
        if was.side == "enemy" and not was.broken and cur and cur.broken then
            Fight.downTold = Fight.downTold or {}
            if not Fight.downTold[id] then
                Fight.downTold[id] = true
                local by = last and (last.who .. " (" .. last.skill .. ")") or "the party"
                Fight.broke[#Fight.broke + 1] = was.name .. " by " .. by
                appendLog("  broke: " .. was.name .. " by " .. by)
            end
        end
    end
    Fight.prev = now
end

local function basicAttack(uid, skills, w)
    local attack = nil
    for _, s in ipairs(skills) do
        local cost = s.cost or 0
        local basic = (s.attr == ATTR.FIGHT) and (cost <= 0) and (s.kind ~= "defend") and (not s.isItem)
        if basic then
            local named = s.name and (s.name:lower() == "attack")
            if (not attack) or named then attack = s end
            if named then break end
        end
    end
    if not attack then return nil end
    local foe, best = nil, -1
    for _, e in ipairs(w.enemies or {}) do
        if not e.broken then
            local left = e.breakLeft or 0
            if left > best then
                foe = e
                best = left
            end
        end
    end
    if not foe then foe = w.enemies and w.enemies[1] end
    if not foe then return nil end
    return finishChoice(uid, attack, "attack " .. foe.name, { foe.id }, false)
end

local function kitFallback(uid)
    if cfg.AttacksOnly then return nil end
    local mp = stat(uid, PARAM.MP, false) or 0
    local usable = {}
    local ids = {}
    pcall(function() ids = equippedIds(uid) end)
    for _, id in ipairs(ids) do
        local ok, s = pcall(skillOf, id)
        if ok and s and not SKIP[s.attr] and s.attr ~= ATTR.FINISH and s.attr ~= ATTR.SUMMON and s.attr ~= ATTR.ITEM then
            local copy = {}
            for k, v in pairs(s) do copy[k] = v end
            copy.kind = "damage"
            copy.known = knownOf(copy)
            local cost = 0
            pcall(function() cost = skillCost(uid, id, false) or 0 end)
            copy.cost = cost
            if cost <= mp and not (Fight.deferChip and ((cost or 0) > 0)) then
                usable[#usable + 1] = copy
            end
        end
    end
    local best, bestR = nil, -1
    for _, s in ipairs(usable) do
        local ok, pow, br = pcall(offenseOf, s)
        local score = 0
        if ok then score = (br or 0) * 1000 + (pow or 0) end
        if score > bestR then best, bestR = s, score end
    end
    if not best then return nil end
    local tid = nil
    pcall(function()
        local list = members(REL.ENEMY)
        tid = list[1]
    end)
    if not tid then
        pcall(function()
            local probe = targetsFor(uid, best, REL.ENEMY)
            tid = probe and probe[1]
        end)
    end
    if not tid then return nil end
    return finishChoice(uid, best, "kit " .. unitName(tid), { tid }, false)
end

local function consider(uid)
    if outOfControl(uid) then
        log("%s is %s; leaving this turn", unitName(uid), outOfControl(uid))
        return nil
    end
    local usable = usableOf(uid)
    if #usable == 0 then
        log("%s: no usable skill", unitName(uid))
        return nil
    end
    local w = worldOf(uid, Fight.boss, Fight.summoned)
    if not Fight.usedSupport[uid] then Fight.usedSupport[uid] = {} end
    w.usedSupport = Fight.usedSupport[uid]
    local function addFoe(id)
        if not keepFoe(id) then return end
        for _, e in ipairs(w.enemies) do
            if e.id == id then return end
        end
        local name = unitName(id)
        local r = hpRatio(id)
        if r ~= nil and r <= 0 then return end
        local isBroken, left = broken(id), breakLeft(id)
        if Fight and Fight.gaugeOf then isBroken, left = Fight.gaugeOf(id, name) end
        w.enemies[#w.enemies + 1] = {
            id = id, name = name, hp = r or 1,
            broken = isBroken, breakLeft = left, statuses = statuses(id),
        }
        Fight.seenFoe = Fight.seenFoe or {}
        Fight.seenFoe[id] = name
    end
    for _, s in ipairs(usable) do
        if s.kind == "damage" or s.attr == ATTR.FIGHT or s.attr == ATTR.MAGIC or s.attr == ATTR.ABILITY then
            for _, id in ipairs(targetsFor(uid, s, REL.ENEMY)) do addFoe(id) end
        end
    end
    if Fight and not Fight.fieldTold and #w.enemies > 0 then
        Fight.fieldTold = true
        local actors = 0
        for _, a in ipairs(w.allies) do
            if a.acts and not a.dead then actors = actors + 1 end
        end
        local bits = {}
        for _, e in ipairs(w.enemies) do
            local card = mobOf(e)
            local weak = " unknown"
            if card and card.weak then
                local els = {}
                for el, on in pairs(card.weak) do
                    if on then els[#els + 1] = el end
                end
                table.sort(els)
                weak = (#els > 0) and (" weak " .. table.concat(els, ",")) or ""
            end
            local gauge = card and card.gauge and (" gauge " .. tostring(card.gauge)) or ""
            bits[#bits + 1] = e.name .. weak .. gauge
        end
        local line = string.format("field: %d foes, %d who can act. %s",
            #w.enemies, actors, table.concat(bits, "; "))
        log("%s", line)
        appendLog("  " .. line)
    end
    for _, s in ipairs(usable) do
        if s.kind == "revive" then
            for _, id in ipairs(targetsFor(uid, s, REL.FRIEND)) do
                local seen = false
                for _, a in ipairs(w.allies) do
                    if a.id == id then a.dead = true seen = true end
                end
                if not seen then
                    w.allies[#w.allies + 1] = { id = id, name = unitName(id), hp = 0, dead = true, statuses = {}, acts = true }
                end
            end
        end
    end
    local phase = currentPhase()
    if phase ~= PHASE_FINISH and inFinishPhase() then phase = PHASE_FINISH end
    if cfg.AttacksOnly then
        if phase == PHASE_FINISH then return nil end
        return basicAttack(uid, usable, w)
    end
    local okChoice, choice = pcall(turn, uid, usable, w, phase)
    if not okChoice then
        log("choice failed: %s", tostring(choice))
        choice = nil
    end
    if choice then return choice end
    local foe = w.enemies and w.enemies[1]
    if foe then
        local swing, swingR = nil, -1
        for _, s in ipairs(usable) do
            local damage = s.kind == "damage" or s.attr == ATTR.FIGHT
            if damage and s.kind ~= "heal" and s.kind ~= "buff" and s.attr ~= ATTR.FINISH
                and (s.cost or 0) <= (w.mp or 0)
                and not (Fight.deferChip and ((s.cost or 0) > 0)) then
                local _, br = offenseOf(s)
                local score = (br or 0) * 1000 + (s.power or 0)
                if score > swingR then swing, swingR = s, score end
            end
        end
        if swing then
            return finishChoice(uid, swing, "kit " .. foe.name, { foe.id }, false)
        end
    end
    if Fight.deferChip then
        for _, s in ipairs(usable) do
            if s.kind == "defend" and (s.cost or 0) <= (w.mp or 0) then
                return finishChoice(uid, s, "hold for debuff", { uid }, false)
            end
        end
        log("%s: holding the chip until the debuff lands", unitName(uid))
        return nil
    end
    local hurt = lowestAlly(w, function(u) return u.acts ~= false end)
    if (not foe) and hurt and (hurt.hp or 1) < 0.30 then
        for _, s in ipairs(usable) do
            if s.kind == "defend" then
                return finishChoice(uid, s, "defend", { uid }, false)
            end
        end
    end
    log("%s: nothing legal this turn", unitName(uid))
    return nil
end

local Hud = { serial = 0, toastSerial = 0, disabled = false, box = {} }

local function showToast(msg)
    if Hud.toast then Hud.toast(msg) end
end

local function showBadge(msg)
    if Hud.badgeShow then Hud.badgeShow(msg) end
end

local function finishBattle()
    if not Fight.active then return end
    Fight.active = false
    local turns = #Fight.actions
    local broke = (#Fight.broke > 0) and table.concat(Fight.broke, ", ") or "nobody broken"
    local fell = (#Fight.fell > 0) and table.concat(Fight.fell, ", ") or "no one fell"
    for _, who in ipairs(Fight.castOrder) do
        local rec = Fight.casts[who]
        if rec then
            local parts = {}
            for _, name in ipairs(rec.order) do
                local n = rec.n[name]
                parts[#parts + 1] = (n > 1) and (name .. " x" .. n) or name
            end
            appendLog("  " .. who .. ": " .. table.concat(parts, ", "))
        end
    end
    local line = string.format("Auto, %d commands. %s. %s.", turns, broke, fell)
    appendLog("-- " .. line)
    appendLog("")
    log("battle %d done: %s", Fight.number, line)
    Fight.actions, Fight.casts, Fight.castOrder = {}, {}, {}
    Fight.broke, Fight.fell, Fight.prev, Fight.last = {}, {}, {}, nil
end

local function ensureBattle()
    if Fight.active then return end
    Fight.active = true
    Fight.number = Fight.number + 1
    Fight.boss = bossBattle()
    Fight.summoned = false
    Fight.usedSupport = {}
    Fight.actions, Fight.casts, Fight.castOrder = {}, {}, {}
    Fight.broke, Fight.fell, Fight.prev = {}, {}, livingSnapshot()
    Fight.scanned, Fight.elemRun, Fight.seenAlly = {}, {}, {}
    Fight.resonanceSent = false
    Fight.resonanceMiss = false
    Fight.poured, Fight.down, Fight.downTold, Fight.relax, Fight.gaugeScale, Fight.brokeOn, Fight.gaugeSure, Fight.gaugeWas = {}, {}, {}, {}, {}, {}, {}, {}
    Fight.downSince, Fight.phaseSeen, Fight.bonusSeen, Fight.lastHit = nil, 0, false, nil
    Fight.line = false
    Fight.prevHit = nil
    Fight.building = nil
    Fight.kits = {}
    Fight.claim = { heal = {}, revive = {}, hone = {}, ether = {}, scan = {}, etherRound = false, guard = false, debuff = false, esper = false, lb = false }
    Fight.went, Fight.rounds, Fight.seenFoe = {}, 0, {}
    Fight.planTag, Fight.afterBonus = nil, false
    Fight.fieldTold = false
    Fight.chipped = false
    Fight.lbRead = {}
    Fight.lbGaugeApi = {}
    Fight.unmarked = false
    Fight.unmarkedTold = false
    Fight.finishNote = {}
    Fight.finishScan = nil
    itemsLogged = false
    potLogged = false
    appendLog(string.format("== battle %d%s ==", Fight.number, Fight.boss and ", boss" or ""))
    log("battle %d%s", Fight.number, Fight.boss and ", boss" or "")
end

local function rememberCast(who, skill)
    local rec = Fight.casts[who]
    if not rec then
        rec = { order = {}, n = {} }
        Fight.casts[who] = rec
        Fight.castOrder[#Fight.castOrder + 1] = who
    end
    if not rec.n[skill] then rec.order[#rec.order + 1] = skill end
    rec.n[skill] = (rec.n[skill] or 0) + 1
end

local function settleGauges()
    Fight.poured = Fight.poured or {}
    Fight.down = Fight.down or {}
    Fight.downTold = Fight.downTold or {}
    Fight.relax = Fight.relax or {}
    Fight.gaugeScale = Fight.gaugeScale or {}
    Fight.brokeOn = Fight.brokeOn or {}
    local phaseNow = currentPhase()
    local prevPhase = Fight.phaseSeen or 0
    if prevPhase ~= 0 and phaseNow == 0 then
        local ids = {}
        for id in pairs(Fight.down) do ids[#ids + 1] = id end
        for _, id in ipairs(ids) do
            Fight.poured[id] = 0
            Fight.down[id] = nil
            Fight.downTold[id] = nil
            Fight.relax[id] = nil
        end
        Fight.bonusSeen = false
        Fight.downSince = nil
        Fight.afterBonus = true
        Fight.brokeOn = {}
    end
    if phaseNow == PHASE_BONUS or phaseNow == PHASE_FINISH then
        Fight.bonusSeen = true
        Fight.unmarked = false
        Fight.gaugeSure = Fight.gaugeSure or {}
        Fight.gaugeWas = Fight.gaugeWas or {}
        local caught = {}
        for id in pairs(Fight.gaugeWas) do caught[#caught + 1] = id end
        local party = 0
        for _ in pairs(Fight.seenAlly or {}) do party = party + 1 end
        if party < 2 then party = 2 end
        for _, id in ipairs(caught) do
            local rec = Fight.gaugeWas[id]
            local old = rec and rec.size
            local at = (rec and rec.at) or 0
            local fresh = (type(old) == "number") and ((#(Fight.actions or {}) - at) <= party)
            if fresh and Fight.brokeOn[id] then
                Fight.gaugeScale[id] = old
                Fight.gaugeSure[id] = old
                Fight.down[id] = true
                Fight.downTold[id] = true
                Fight.relax[id] = nil
                Fight.poured[id] = 0
                Fight.gaugeWas[id] = nil
                log("%s bonus caught the release. working gauge restored %d", unitName(id), old)
            elseif not fresh then
                Fight.gaugeWas[id] = nil
            end
        end
        local function rememberSure(id)
            if not id or Fight.gaugeSure[id] then return end
            local scaled = Fight.gaugeScale and Fight.gaugeScale[id]
            local poured = Fight.poured[id] or 0
            local card = mobOf({ id = id, name = unitName(id) })
            local book = card and tonumber(card.gauge) or nil
            local size = (((type(scaled) == "number") and (scaled > 0) and scaled) or book)
            if (type(scaled) == "number") and (scaled > 0) and (poured > 0) and (poured < scaled) then
                local proved = math.floor(poured + 0.5)
                if (type(book) == "number") and (proved < book) then proved = book end
                Fight.gaugeScale[id] = proved
                Fight.down[id] = true
                Fight.downTold[id] = true
                Fight.relax[id] = nil
                Fight.poured[id] = 0
                size = proved
                log("%s bonus proved the poured stagger. working gauge %d", unitName(id), proved)
            end
            if (type(size) == "number") and (size > 0) then Fight.gaugeSure[id] = size end
        end
        for id, on in pairs(Fight.down) do
            if on then rememberSure(id) end
        end
        for id, on in pairs(Fight.brokeOn) do
            if on then rememberSure(id) end
        end
        local any = false
        for _, on in pairs(Fight.down) do
            if on then any = true break end
        end
        local last = Fight.lastHit
        if not any and last and #last > 0 then
            local best, bestScore = nil, -1
            for _, tid in ipairs(last) do
                local poured = Fight.poured[tid] or 0
                local card = mobOf({ id = tid, name = unitName(tid) })
                local gauge = card and tonumber(card.gauge) or 0
                local scaled = Fight.gaugeScale and Fight.gaugeScale[tid]
                if scaled and scaled > gauge then gauge = scaled end
                local score = (gauge > 0) and (poured / gauge) or 0
                if score > bestScore then best, bestScore = tid, score end
            end
            if best and bestScore >= 1 then
                Fight.down[best] = true
                Fight.brokeOn = Fight.brokeOn or {}
                Fight.brokeOn[best] = true
                if not Fight.downSince then Fight.downSince = #Fight.actions end
            end
        end
    end
    Fight.phaseSeen = phaseNow
    if not Fight.bonusSeen and Fight.downSince then
        local allies = 0
        for _ in pairs(Fight.seenAlly or {}) do allies = allies + 1 end
        if allies < 2 then allies = 2 end
        if (#Fight.actions - Fight.downSince) >= allies then
            local ids = {}
            for id in pairs(Fight.down) do ids[#ids + 1] = id end
            for _, id in ipairs(ids) do
                Fight.down[id] = nil
                Fight.downTold[id] = nil
                Fight.relax[id] = true
                local sure = Fight.gaugeSure and Fight.gaugeSure[id]
                if (type(sure) == "number") then
                    Fight.poured[id] = 0
                    log("%s break held. working gauge stays %d", unitName(id), sure)
                else
                    local poured = Fight.poured[id] or 0
                    local card = mobOf({ id = id, name = unitName(id) })
                    local book = (card and tonumber(card.gauge)) or 100
                    local grown = math.floor(poured / 0.72 + 0.5)
                    if grown < book + 1 then grown = book + 1 end
                    local prev = Fight.gaugeScale[id] or book
                    if grown > prev then
                        Fight.gaugeWas = Fight.gaugeWas or {}
                        Fight.gaugeWas[id] = { size = prev, at = #(Fight.actions or {}) }
                        Fight.gaugeScale[id] = grown
                    end
                    log("%s gauge estimate released, no bonus phase. working gauge %d",
                        unitName(id), Fight.gaugeScale[id] or grown)
                end
            end
            Fight.downSince = nil
        end
    end
end

local function noteRound(uid)
    Fight.went = Fight.went or {}
    if uid and (uid >= 0) then Fight.went[uid] = true end
    local actors, went = 0, 0
    for _, id in ipairs(friendIds()) do
        local ratio = hpRatio(id)
        if (ratio == nil) or (ratio > 0) then
            local kit = unitKit(id)
            if kit and kit.spells and (#kit.spells > 0) then
                actors = actors + 1
                if Fight.went[id] then went = went + 1 end
            end
        end
    end
    if (actors > 0) and (went >= actors) then
        Fight.went = {}
        Fight.rounds = (Fight.rounds or 0) + 1
        if Fight.claim then
            Fight.claim.heal = {}
            Fight.claim.ether = {}
            Fight.claim.etherRound = false
        end
        Fight.afterBonus = false
    end
end

local function act(serial)
    if not cfg.Enabled then return end
    if (not Menu.open) or (Menu.serial ~= serial) or Menu.sub or Menu.decided then return end
    local uid = currentActor()
    if uid < 0 then uid = Menu.actor end
    if uid < 0 then return end
    pcall(ensureBattle)
    local finishingEarly = false
    pcall(function() finishingEarly = inFinishPhase() end)
    if finishingEarly and Fight.resonanceSent then return end
    pcall(function() noteChanges(livingSnapshot()) end)
    pcall(settleGauges)
    Fight.deferChip = false
    local okPlan, choice = pcall(consider, uid)
    if not okPlan then
        log("plan failed: %s", tostring(choice))
        choice = nil
    end
    if not choice then
        local okKit, hit = pcall(kitFallback, uid)
        if okKit then
            choice = hit
        else
            log("kit fallback failed: %s", tostring(hit))
        end
    end
    if not choice then
        log("%s: no command sent", unitName(uid))
        return
    end
    local finishing = false
    pcall(function() finishing = inFinishPhase() end)
    if finishing and choice.attr ~= ATTR.FINISH then
        log("%s: finish phase, leaving %s off the wheel", unitName(uid), choice.name)
        return
    end
    if not Menu.open or Menu.serial ~= serial then return end
    local who = unitName(uid)
    local phase = finishing and PHASE_FINISH or currentPhase()
    local mpNow = stat(uid, PARAM.MP, false)
    local line = string.format("%s p%d mp%s: %s -> %s", who, phase, tostring(mpNow or "?"), choice.name, choice.reason)
    if not cfg.Submit then
        appendLog("  (not sent) " .. line)
        log("(not sent) %s", line)
        return
    end
    local ok, sent = pcall(send, uid, choice, phase)
    if not ok then
        log("send failed: %s", tostring(sent))
        return
    end
    if not sent then return end
    if choice.attr == ATTR.SUMMON then Fight.summoned = true end
    if choice.attr == ATTR.FINISH then Fight.resonanceSent = true end
    if phase == 0 and choice.kind == "damage" and not choice.isItem then
        Fight.line = true
        local reason = choice.reason or ""
        if (choice.cost or 0) > 0 and not reason:find("^setup") then Fight.chipped = true end
    end
    local limitCast = choice.attr == ATTR.LB
    if choice.known then
        local use = choice.known.use
        if (use == "lb-setup") or (use == "lb-cash") or (use == "lb-revive") then limitCast = true end
    end
    if phase == 0 and choice.targets and ((choice.kind == "damage") or limitCast) and not choice.isItem then
        Fight.poured = Fight.poured or {}
        Fight.down = Fight.down or {}
        Fight.relax = Fight.relax or {}
        Fight.gaugeScale = Fight.gaugeScale or {}
        Fight.lastHit = choice.targets
        local row = skillOf(choice.id)
        local _, br = offenseOf(row or choice)
        if br > 0 then
            for _, tid in ipairs(choice.targets) do
                if not Fight.down[tid] then
                    if Fight.relax[tid] then
                        Fight.relax[tid] = nil
                    end
                    local enemy = { id = tid, name = unitName(tid) }
                    local card = mobOf(enemy)
                    local gauge = card and tonumber(card.gauge) or nil
                    local scaled = Fight.gaugeScale[tid]
                    if scaled and (not gauge or scaled > gauge) then gauge = scaled end
                    local factor = elementFactor(row or choice, enemy)
                    if gauge and gauge > 0 and factor > 0 then
                        Fight.poured[tid] = (Fight.poured[tid] or 0) + br * factor
                    end
                end
            end
        end
    end
    if Fight.elemRun and choice.targets and choice.known and choice.known.element then
        local el = choice.known.element
        for _, tid in ipairs(choice.targets) do
            local run = Fight.elemRun[tid]
            if run and run.el == el then run.n = run.n + 1
            else Fight.elemRun[tid] = { el = el, n = 1 } end
        end
    end
    Fight.actions[#Fight.actions + 1] = line
    rememberCast(who, choice.name)
    Fight.last = { who = who, skill = choice.name }
    Fight.prevHit = {
        who = who, skill = choice.name, kind = choice.kind,
        id = choice.targets and choice.targets[1],
    }
    if choice.kind == "damage" and Fight.prevHit.id then
        Fight.building = Fight.prevHit.id
    end
    noteRound(uid)
    appendLog("  " .. line)
    log("%s", line)
end

--------------------------------------------------------------------------------
-- A command the player chose. The same ledger the mod writes for its own sends.
--------------------------------------------------------------------------------

local function noteHand(v)
    if not (Fight and v) then return end
    pcall(ensureBattle)
    if not Fight.active then return end
    pcall(function() noteChanges(livingSnapshot()) end)
    pcall(settleGauges)
    local uid = Menu.actor
    if (not uid) or (uid < 0) then uid = currentActor() end
    local actionId, isItem, targets, rowObj = nil, false, {}, nil
    local function readIds(list)
        local out = {}
        if not (list and list.ForEach) then return out end
        pcall(function()
            list:ForEach(function(_, x)
                local n = num(unwrap(x))
                if n and (n >= 0) then out[#out + 1] = n end
            end)
        end)
        return out
    end
    local list = v.cmdDecideDataList
    if list and list.ForEach then
        list:ForEach(function(_, e)
            if actionId then return end
            local d = unwrap(e)
            if not d then return end
            rowObj = d
            actionId = num(d.actionId)
            isItem = d.isUseItem and true or false
            for _, key in ipairs({ "targetUnitUniqueIdList", "TargetUnitUniqueIdList", "targetUniqueIdList" }) do
                if #targets == 0 then
                    local raw = nil
                    pcall(function() raw = d[key] end)
                    targets = readIds(raw)
                end
            end
        end)
    end
    if not actionId then return end
    local skill = (not isItem) and skillOf(actionId) or nil
    local name = (skill and skill.name) or ("command " .. tostring(actionId))
    if isItem then
        local row = ItemIdx and ItemIdx[actionId] or nil
        name = (row and row.name) or ("item " .. tostring(actionId))
    end
    local info = skill and knownOf(skill) or nil
    local use = info and info.use or nil
    local kind = nil
    if skill then
        local okKind, got = pcall(classify, skill)
        if okKind then kind = got end
    end
    if isItem then
        local listed = Known.items and Known.items[name:lower()]
        if listed == "hp" then kind = "heal" end
        if listed == "mp" then kind = "ether" end
        if listed == "revive" then kind = "revive" end
        if listed == "cure" then kind = "cure" end
    end
    if (use == "heal") or (use == "patch") then kind = "heal" end
    if use == "cure" then kind = "cure" end
    if use == "debuff" then kind = "debuff" end
    if (not kind) and ((use == "break") or (use == "cash")) then kind = "damage" end
    local phase = currentPhase()
    local who = (uid and (uid >= 0)) and unitName(uid) or "you"
    local line = string.format("player %s p%d: %s", who, phase, name)
    if #targets > 0 then
        local bits = {}
        for _, tid in ipairs(targets) do bits[#bits + 1] = unitName(tid) end
        line = line .. " -> " .. table.concat(bits, ", ")
    end
    log("%s", line)
    appendLog("  " .. line)
    rememberCast(who, name)
    Fight.actions[#Fight.actions + 1] = line
    Fight.last = { who = who, skill = name }
    Fight.prevHit = { who = who, skill = name, kind = kind, id = targets[1] }
    if (kind == "damage") and targets[1] then Fight.building = targets[1] end
    Fight.claim = Fight.claim or {}
    Fight.claim.heal = Fight.claim.heal or {}
    Fight.claim.revive = Fight.claim.revive or {}
    Fight.claim.ether = Fight.claim.ether or {}
    Fight.claim.hone = Fight.claim.hone or {}
    local function eachAlly(pred)
        local ids = {}
        for _, id in ipairs(friendIds()) do
            local ratio = hpRatio(id)
            local dead = (ratio ~= nil) and (ratio <= 0)
            if pred(id, dead) then ids[#ids + 1] = id end
        end
        if (#ids == 0) and uid and (uid >= 0) then ids[1] = uid end
        return ids
    end
    if (kind == "heal") or (kind == "cure") then
        local ids = (#targets > 0) and targets or eachAlly(function(_, dead) return not dead end)
        for _, id in ipairs(ids) do Fight.claim.heal[id] = true end
    end
    if kind == "revive" then
        local ids = (#targets > 0) and targets or eachAlly(function(_, dead) return dead end)
        for _, id in ipairs(ids) do Fight.claim.revive[id] = #Fight.actions end
    end
    if (kind == "ether") and uid and (uid >= 0) then
        Fight.claim.ether[uid] = true
        Fight.claim.etherRound = true
    end
    if kind == "debuff" then Fight.claim.debuff = true end
    if use == "guardbuff" then Fight.claim.guard = true end
    if (use == "opener") and uid and (uid >= 0) then Fight.claim.hone[uid] = true end
    if use == "lb-setup" then Fight.claim.lb = true end
    if skill and (skill.attr == ATTR.SUMMON) then
        Fight.summoned = true
        Fight.claim.esper = true
    end
    if skill and (skill.attr == ATTR.FINISH) then Fight.resonanceSent = true end
    if phase == PHASE_FINISH then Fight.resonanceSent = true end
    local cost = 0
    if skill and uid and (uid >= 0) then
        pcall(function() cost = skillCost(uid, actionId, false) or 0 end)
    end
    if (phase == 0) and (kind == "damage") and (not isItem) and (cost > 0) then
        Fight.line = true
        Fight.chipped = true
    end
    if (phase == 0) and (kind == "damage") and (not isItem) and skill and (#targets > 0) then
        Fight.poured = Fight.poured or {}
        Fight.down = Fight.down or {}
        Fight.relax = Fight.relax or {}
        Fight.gaugeScale = Fight.gaugeScale or {}
        Fight.lastHit = targets
        local _, br = offenseOf(skill)
        if br > 0 then
            for _, tid in ipairs(targets) do
                if not Fight.down[tid] then
                    Fight.relax[tid] = nil
                    local enemy = { id = tid, name = unitName(tid) }
                    local card = mobOf(enemy)
                    local gauge = card and tonumber(card.gauge) or nil
                    local scaled = Fight.gaugeScale[tid]
                    if scaled and ((not gauge) or (scaled > gauge)) then gauge = scaled end
                    local factor = elementFactor(skill, enemy)
                    if gauge and (gauge > 0) and (factor > 0) then
                        Fight.poured[tid] = (Fight.poured[tid] or 0) + (br * factor)
                    end
                end
            end
        end
    elseif (phase == 0) and (kind == "damage") and (not isItem) and (#targets == 0) then
        Fight.unmarked = true
        if rowObj and (not Fight.targetTold) then
            Fight.targetTold = true
            log("player command had no target ids")
        end
        log("stagger from %s was not counted", name)
    end
    if skill and info and info.element and (#targets > 0) then
        Fight.elemRun = Fight.elemRun or {}
        local el = info.element
        for _, tid in ipairs(targets) do
            local run = Fight.elemRun[tid]
            if run and (run.el == el) then run.n = run.n + 1
            else Fight.elemRun[tid] = { el = el, n = 1 } end
        end
    end
    if uid and (uid >= 0) then noteRound(uid) end
end

local function scheduleAct()
    if Menu.sub or Menu.decided or (not Menu.open) then return end
    if not cfg.Enabled then return end
    Menu.due = (Menu.due or 0) + 1
    local due = Menu.due
    local serial = Menu.serial
    gameDelay(DECIDE_MS, function()
        if Menu.due ~= due then return end
        act(serial)
    end)
end

--------------------------------------------------------------------------------
-- Hooks
--------------------------------------------------------------------------------

local function hookDecide()
    RegisterHook("/Script/mucha.CPP_BtlDelEventCmd:OnExecuteDecideCommand", function(_, value)
        pcall(function()
            local v = value:get()
            local fromMod = (Menu.byMod == true)
            Menu.byMod = false
            learn(v)
            Menu.decided = true
            Menu.sub = false
            if not fromMod then
                local okNote, errNote = pcall(noteHand, v)
                if not okNote then log("player command was not recorded: %s", tostring(errNote)) end
            end
        end)
    end)
end

local function hookMenu()
    RegisterHook("/Script/mucha.CPP_MuchaEventDispatcher:ExecuteEvent", function(_, tag)
        local ok, name = pcall(function() return tag:get().TagName:ToString() end)
        if not ok then return end
        if name == "Delegate.Battle.Cmd.List.Begin" then
            local actor = currentActor()
            Menu.sub = (actor == Menu.actor) and (not Menu.decided)
            Menu.actor = actor
            Menu.decided = false
            Menu.open = true
            Menu.serial = Menu.serial + 1
            if Menu.sub then return end
            scheduleAct()
        elseif name == "Delegate.Battle.Cmd.List.End" then
            Menu.open = false
        end
    end)
end

local function findClass(path)
    local cls = StaticFindObject(path)
    if not (cls and cls:IsValid()) then error("missing " .. path) end
    return cls
end

local function makeWidget(kind, ax, ay, alx, aly, size)
    local gi = FindFirstOf("GameInstance")
    if not (gi and gi:IsValid()) then error("no GameInstance") end
    Hud.serial = Hud.serial + 1
    local base = string.format("FFRAutoBattle_%s_%d", kind, Hud.serial)
    local widget = StaticConstructObject(findClass("/Script/UMG.UserWidget"), gi, FName(base))
    local tree = StaticConstructObject(findClass("/Script/UMG.WidgetTree"), widget, FName(base .. "_Tree"))
    widget.WidgetTree = tree
    local canvas = StaticConstructObject(findClass("/Script/UMG.CanvasPanel"), tree, FName(base .. "_Canvas"))
    tree.RootWidget = canvas
    local border = StaticConstructObject(findClass("/Script/UMG.Border"), tree, FName(base .. "_Border"))
    local text = StaticConstructObject(findClass("/Script/UMG.TextBlock"), tree, FName(base .. "_Text"))
    border:SetContent(text)
    border:SetBrushColor({ R = 0.02, G = 0.03, B = 0.05, A = 0.72 })
    border:SetPadding({ Left = 14, Top = 6, Right = 14, Bottom = 6 })
    local slot = canvas:AddChildToCanvas(border)
    slot:SetAutoSize(true)
    slot:SetAnchors({ Minimum = { X = ax, Y = ay }, Maximum = { X = ax, Y = ay } })
    slot:SetAlignment({ X = alx, Y = aly })
    slot:SetPosition({ X = 0, Y = 0 })
    local font = text.Font
    font.Size = size
    text:SetFont(font)
    text:SetColorAndOpacity({ SpecifiedColor = { R = 0.93, G = 0.86, B = 0.62, A = 1 }, ColorUseRule = 0 })
    pcall(function() widget:SetIsFocusable(false) end)
    pcall(function() text:SetIsFocusable(false) end)
    widget:SetVisibility(1)
    widget:AddToViewport(kind == "toast" and 1100 or 1000)
    return { widget = widget, text = text }
end

local function widget(kind)
    local w = Hud.box[kind]
    if w and w.widget:IsValid() and w.text:IsValid() then
        if not w.widget:IsInViewport() then w.widget:AddToViewport(kind == "toast" and 1100 or 1000) end
        return w
    end
    if kind == "toast" then
        w = makeWidget(kind, 0.5, 0.16, 0.5, 0.5, 20)
    else
        w = makeWidget(kind, 0.012, 0.90, 0.0, 1.0, 15)
    end
    Hud.box[kind] = w
    return w
end

Hud.toast = function(msg)
    if Hud.disabled then return end
    ExecuteInGameThread(function()
        local ok, err = pcall(function()
            local w = widget("toast")
            w.text:SetText(FText(msg))
            w.widget:SetVisibility(3)
            Hud.toastSerial = Hud.toastSerial + 1
            local serial = Hud.toastSerial
            gameDelay(1200, function()
                if serial == Hud.toastSerial and w.widget:IsValid() then w.widget:SetVisibility(1) end
            end)
        end)
        if not ok then
            Hud.disabled = true
            log("overlay off: %s", tostring(err))
        end
    end)
end

Hud.badgeShow = function(msg)
    if Hud.disabled then return end
    ExecuteInGameThread(function()
        local ok, err = pcall(function()
            local w = widget("badge")
            if not msg then w.widget:SetVisibility(1) return end
            w.text:SetText(FText(msg))
            w.widget:SetVisibility(3)
        end)
        if not ok then
            Hud.disabled = true
            log("overlay off: %s", tostring(err))
        end
    end)
end

local speedDone = false
local function applySpeed()
    if speedDone or cfg.BattleSpeed == 1 then speedDone = true return end
    local tables = FindAllOf("DataTable")
    if not tables then return end
    local applied = false
    for _, dt in ipairs(tables) do
        pcall(function()
            if type(dt) ~= "userdata" or not dt:IsValid() then return end
            if rowStructName(dt) ~= "BTL_GENERAL_DATA" then return end
            dt:ForEachRow(function(_, row)
                local list = row.GameSpeedList
                if not (list and list.ForEach) then return end
                local first
                list:ForEach(function(i, e)
                    if i == 1 then first = num(e) end
                end)
                if not first or math.abs(first - 1) > 0.05 then
                    log("battle speed left as it is (first step %s)", tostring(first))
                    speedDone = true
                    return
                end
                list:ForEach(function(_, e)
                    local v = num(e)
                    if v then e:set(v * cfg.BattleSpeed) end
                end)
                applied = true
            end)
        end)
    end
    if applied then
        speedDone = true
        log("battle speed x%s", tostring(cfg.BattleSpeed))
    end
end

local function watchField()
    if not (Fight and Fight.active) then return end
    pcall(function() noteChanges(livingSnapshot()) end)
    pcall(settleGauges)
end

local function resonanceWatch()
    if not (Fight and Fight.active) then return end
    if not cfg.Enabled then
        watchField()
        return
    end
    local okPhase, phase = pcall(inFinishPhase)
    local finishing = okPhase and phase == true
    if not finishing then
        Fight.resonanceSent = false
        Fight.resonanceMiss = false
        Fight.resonanceWait = false
        Fight.finishScan = nil
        Fight.attackWheel = false
        return
    end
    if cfg.AttacksOnly then
        if not Fight.attackWheel then
            Fight.attackWheel = true
            log("resonance phase, your pick")
        end
        return
    end
    if Fight.resonanceSent then return end
    if not Fight.resonanceWait then
        Fight.resonanceWait = true
        return
    end
    pcall(buildSkillIndex)
    local bestUid, bestChoice, bestScore = nil, nil, -1e9
    local names = {}
    for _, uid in ipairs(friendIds()) do
        local ratio = hpRatio(uid)
        if (ratio == nil or ratio > 0) and not outOfControl(uid) then
            names[#names + 1] = unitName(uid)
            local okW, w = pcall(worldOf, uid, Fight.boss, Fight.summoned)
            if okW and w then
                local skills = {}
                local okS, got = pcall(finishList, uid)
                if okS and type(got) == "table" then skills = got end
                local okPick, choice = pcall(pickFinish, uid, skills, w)
                if okPick and choice and (choice.score or 0) > bestScore then
                    bestUid, bestChoice, bestScore = uid, choice, choice.score or 0
                end
            end
        end
    end
    if not bestChoice then
        if not Fight.resonanceMiss then
            Fight.resonanceMiss = true
            local detail = {}
            if Fight.finishNote then
                for id, note in pairs(Fight.finishNote) do
                    if note ~= "" then detail[#detail + 1] = unitName(id) .. " bar " .. note end
                end
            end
            log("resonance phase, no finisher on %s%s",
                (#names > 0) and table.concat(names, ", ") or "the party",
                (#detail > 0) and (" (" .. table.concat(detail, "; ") .. ")") or "")
            appendLog("  resonance phase, no finisher equipped")
        end
        return
    end
    local ok, sent = pcall(send, bestUid, bestChoice, PHASE_FINISH)
    if not ok or not sent then
        log("resonance send failed: %s", tostring(sent))
        return
    end
    Fight.resonanceSent = true
    local who = unitName(bestUid)
    local line = string.format("resonance %s by %s -> %s", bestChoice.name, who, bestChoice.reason)
    log("%s", line)
    appendLog("  " .. line)
    rememberCast(who, bestChoice.name)
    Fight.actions[#Fight.actions + 1] = line
    Fight.last = { who = who, skill = bestChoice.name }
end

local absent = 0
gameLoop(400, resonanceWatch)
gameLoop(700, function()
    applySpeed()
    buildSkillIndex()
    if not Fight.active then return end
    local u = FindFirstOf("CPP_BtlUnit")
    if u and u:IsValid() then
        absent = 0
        return
    end
    absent = absent + 1
    if absent >= 2 then finishBattle() end
end)

local function bind(name, fn)
    local keyName = cfg[name]
    local key = keyName and Key[keyName]
    if key == nil then
        log("unknown key %s for %s", tostring(keyName), name)
        return
    end
    RegisterKeyBind(key, function()
        ExecuteInGameThread(fn)
    end)
end

local function pressAuto()
    cfg.Enabled = not cfg.Enabled
    saveState()
    local msg = cfg.Enabled and "AutoBattle On" or "AutoBattle Off"
    log(msg)
    showToast(msg)
    if cfg.Enabled then scheduleAct() end
end

local function pressBasic()
    cfg.AttacksOnly = not cfg.AttacksOnly
    saveState()
    local msg = cfg.AttacksOnly and "AutoBattle: Take it Easy!" or "AutoBattle: No Mercy!"
    log(msg)
    showToast(msg)
end

local function inFight()
    if Fight and Fight.active then return true end
    local ok, u = pcall(function() return FindFirstOf("CPP_BtlUnit") end)
    return (ok and u and u.IsValid and u:IsValid()) and true or false
end

local padTold, padLeft, padRight = false, false, false
local function pollTriggers()
    local okPc, pc = pcall(function() return FindFirstOf("PlayerController") end)
    if not (okPc and pc and pc.IsValid and pc:IsValid()) then return end
    local function down(name)
        local ok, hit = pcall(function()
            return pc:IsInputKeyDown({ KeyName = FName(name) })
        end)
        if not (ok and (type(hit) == "boolean")) then
            ok, hit = pcall(function()
                return pc:IsInputKeyDown(FName(name))
            end)
        end
        if ok and (type(hit) == "boolean") then return hit end
        return nil
    end
    local left = down("Gamepad_LeftTrigger")
    local right = down("Gamepad_RightTrigger")
    if (left == nil) and (right == nil) then
        if not padTold then
            padTold = true
            log("could not read the triggers")
        end
        return
    end
    local function rose(now, was)
        if now == nil then return false, was end
        return (now and not was) and true or false, now
    end
    local leftRose, rightRose
    leftRose, padLeft = rose(left, padLeft)
    rightRose, padRight = rose(right, padRight)
    if not (leftRose or rightRose) then return end
    if not inFight() then return end
    if leftRose then pressBasic() end
    if rightRose then pressAuto() end
end

loadConfig()

bind("TakeOverKey", pressAuto)
bind("MenuKey", pressBasic)
gameLoop(16, pollTriggers)

local okHook, errHook = pcall(function()
    hookDecide()
    hookMenu()
end)
if not okHook then log("hook failed: %s", tostring(errHook)) end

local mobCount = 0
for _ in pairs(Mobs) do mobCount = mobCount + 1 end
log("loaded. planner v0.1.12. %s. %s toggles auto battle. %s basic attacks %s. In a fight, left trigger toggles basic attacks and right trigger toggles auto battle. Bestiary %d. Submit=%s, battle speed x%s.",
    cfg.Enabled and "on" or "off",
    cfg.TakeOverKey,
    cfg.MenuKey,
    cfg.AttacksOnly and "on" or "off",
    mobCount,
    tostring(cfg.Submit), tostring(cfg.BattleSpeed))

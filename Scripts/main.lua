-- FFR:AutoBattle. One auto-battle switch. One planner for the round, from the
-- design doc: score every enemy, chip the gauges, finish them together.
-- The characters carry out the next slot. Claims stop a second heal, a second
-- buff, or a second Ether in the same round.
-- F10 is on/off and flashes AutoBattle On or Off.
-- F9 is on/off. On flashes AutoBattle: Take it Easy! Off flashes
-- AutoBattle: No Mercy! On is Attack only:
-- no MP and no items. Off is the default. Both choices are remembered.
-- In a fight, the right trigger fires the F10 action. While auto battle is
-- on in a fight, the left trigger fires the F9 action. While auto battle is
-- off, or outside a fight, the left trigger stays with the game.
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
    -- Names already in known.lua keep their stagger and use. The catalog only fills gaps.
    local catOk, catalog = pcall(dofile, DIR .. "/Scripts/catalog.lua")
    if catOk and type(catalog) == "table" and type(catalog.skills) == "table" and type(Known.skills) == "table" then
        -- A name known.lua lists keeps its values; a field it leaves out, such
        -- as whether the hit is physical, comes from the catalog.
        local added, filled = 0, 0
        for name, row in pairs(catalog.skills) do
            if type(row) == "table" then
                local mine = Known.skills[name]
                if mine == nil then
                    Known.skills[name] = row
                    added = added + 1
                elseif type(mine) == "table" then
                    -- The kind of hit is one fact: known.lua's phys or magic is not joined by the other.
                    local kinded = mine.phys or mine.magic
                    for k, v in pairs(row) do
                        if (mine[k] == nil) and not (kinded and ((k == "phys") or (k == "magic"))) then
                            mine[k] = v
                            filled = filled + 1
                        end
                    end
                end
            end
        end
        log("catalog %d added", added)
        if filled > 0 then log("catalog %d fields filled", filled) end
    elseif not catOk then
        log("catalog unavailable: %s", tostring(catalog))
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
local Health = {}
do
    local ok, loaded = pcall(dofile, DIR .. "/Scripts/health.lua")
    if ok and type(loaded) == "table" then
        Health = loaded
    else
        log("health unavailable: %s", tostring(loaded))
    end
end
local Debuffs = {}
do
    local ok, loaded = pcall(dofile, DIR .. "/Scripts/debuffs.lua")
    if ok and type(loaded) == "table" then
        Debuffs = loaded
    else
        log("debuffs unavailable: %s", tostring(loaded))
    end
end
local Gauges = {}
do
    local ok, loaded = pcall(dofile, DIR .. "/Scripts/gauges.lua")
    if ok and type(loaded) == "table" then
        Gauges = loaded
    else
        log("gauges unavailable: %s", tostring(loaded))
    end
end
local Espers = {}
do
    local ok, loaded = pcall(dofile, DIR .. "/Scripts/espers.lua")
    if ok and type(loaded) == "table" then
        Espers = loaded
    else
        log("espers unavailable: %s", tostring(loaded))
    end
end
local Limits = {}
do
    local ok, loaded = pcall(dofile, DIR .. "/Scripts/limits.lua")
    if ok and type(loaded) == "table" then
        Limits = loaded
    else
        log("limits unavailable: %s", tostring(loaded))
    end
end
local Kits = {}
do
    local ok, loaded = pcall(dofile, DIR .. "/Scripts/kits.lua")
    if ok and type(loaded) == "table" then
        Kits = loaded
    else
        log("kits unavailable: %s", tostring(loaded))
    end
end
local Items = {}
do
    local ok, loaded = pcall(dofile, DIR .. "/Scripts/items.lua")
    if ok and type(loaded) == "table" then
        Items = loaded
    else
        log("items unavailable: %s", tostring(loaded))
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
-- One Limit gauge is 100 points in every game log so far: a 100-point bar
-- holds one gauge, a 200-point bar two. Used only when the game does not
-- say. The game's own gauge count is trusted for the launch once any unit
-- has read empty on it, since a call that always says 1 is the slot count.
local LB_POINTS = { gauge = 100, countTrusted = false }
local VAR = { UP = 0, RATIO = 2 }
local ST_BREAK = 89
local GUARD_STATUS = { [34] = true, [35] = true, [36] = true }
local OUT_OF_CONTROL = { [6] = "confused", [8] = "charmed", [10] = "berserk" }
-- Sleep, silence, paralysis, confuse, petrify, charm, stop, berserk, doom.
-- Poison and blind are that ally's own item. Slow is the spare cure in health.lua.
-- A broken stat stays off.
local LOCK = {
    [3] = true, [4] = true, [5] = true, [6] = true, [7] = true,
    [8] = true, [9] = true, [10] = true, [11] = true,
}
local PHASE_BONUS, PHASE_FINISH = 1, 2
local DECIDE_MS = 420

local Defaults = {
    Enabled = true, Submit = true, AttacksOnly = false,
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

-- The on-disk log keeps this many fights. A new header drops the oldest.
local function keepFights(text, keep)
    local fights, buf = {}, {}
    local function push()
        if #buf == 0 then return end
        local body = table.concat(buf, "\n")
        if body:match("%S") then fights[#fights + 1] = body end
        buf = {}
    end
    text = (text or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
    for row in (text .. "\n"):gmatch("([^\n]*)\n") do
        if row:match("^== battle ") then push() end
        buf[#buf + 1] = row
    end
    push()
    while #fights > keep do table.remove(fights, 1) end
    return table.concat(fights, "\n")
end

local function appendLog(line)
    if type(line) == "string" and line:match("^== battle ") then
        local read = io.open(LOG_PATH, "r")
        local text, size = "", 0
        if read then
            size = read:seek("end") or 0
            read:seek("set", 0)
            local function slurp()
                local ok, got = pcall(function() return read:read("*a") end)
                if ok and type(got) == "string" and got ~= "" then return got end
                read:seek("set", 0)
                ok, got = pcall(function() return read:read("a") end)
                if ok and type(got) == "string" and got ~= "" then return got end
                read:seek("set", 0)
                local parts = {}
                while true do
                    local block = read:read(8192)
                    if (not block) or (block == "") then break end
                    parts[#parts + 1] = block
                end
                return table.concat(parts)
            end
            local okRead, got = pcall(slurp)
            if okRead and type(got) == "string" then text = got end
            read:close()
        end
        -- A failed read must not replace a log that still has bytes.
        if text == "" and size > 0 then text = nil end
        local kept = text and keepFights(text, 4) or nil
        if kept then
            local out = io.open(LOG_PATH, "w")
            if out then
                if kept ~= "" then
                    out:write(kept)
                    if kept:sub(-1) ~= "\n" then out:write("\n") end
                end
                out:close()
            end
        end
    end
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
                    calc = num(field(row, "damageCalcType")) or 0,
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
    -- A fallen ally is not in the living list. Its slot still has the name.
    if not p then
        local bfl = battleLib()
        if bfl and bfl:IsValid() then
            local ok, q = pcall(function() return bfl:GetBattleUnitParameter(uid, false) end)
            if ok and q and q.IsValid and q:IsValid() then p = q end
        end
    end
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
    return use == "lb-setup" or use == "lb-cash" or use == "lb-revive" or use == "lb-break" or use == "lb-guard"
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
    -- A fallen ally is not in the living list. Its slot still has the bar.
    if (not p) and bfl and bfl:IsValid() then
        local ok, q = pcall(function() return bfl:GetBattleUnitParameter(uid, false) end)
        if ok and q and q.IsValid and q:IsValid() then p = q end
    end
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
        local ready, held, unmatched = {}, {}, {}
        for _, id in ipairs(ids) do
            local s = skillOf(id)
            local name = s and s.name
            if name and (name ~= "") then
                local key = Kits.key and Kits.key(name) or nil
                local low = name:lower()
                local looks = low:find("formation", 1, true) or low:find("tactic", 1, true)
                if key then
                    local blocked = SKIP[s.attr] and true or false
                    if not blocked then
                        local okSeal, isSealed = pcall(sealed, uid, id)
                        if okSeal and isSealed then blocked = true end
                    end
                    local list = blocked and held or ready
                    list[#list + 1] = name
                elseif looks then
                    unmatched[#unmatched + 1] = name
                end
            end
        end
        local mpNow = stat(uid, PARAM.MP, false)
        local mpMax = stat(uid, PARAM.MP, true)
        log("kit bar %s mp %s/%s ready %s; sealed %s; unmatched %s",
            unitName(uid), tostring(mpNow or "?"), tostring(mpMax or "?"),
            (#ready > 0) and table.concat(ready, ", ") or "none",
            (#held > 0) and table.concat(held, ", ") or "none",
            (#unmatched > 0) and table.concat(unmatched, ", ") or "none")
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
        local function friendSlot(uid, aliveOnly)
            local ok, p = pcall(function() return bfl:GetBattleUnitParameter(uid, aliveOnly) end)
            if not (ok and p and p.IsValid and p:IsValid()) then return false end
            local okR, rel = pcall(function() return p:GetRelation() end)
            if okR and (num(rel) == REL.FRIEND) then add(uid) return true end
            return false
        end
        for uid = 0, 7 do
            if not friendSlot(uid, true) then friendSlot(uid, false) end
        end
    end
    return ids
end

--------------------------------------------------------------------------------
-- Skill math. The live row has stagger and no element. known.lua names the element.
--------------------------------------------------------------------------------

-- Declared here so the skill math below can read what a fight has learned.
local Fight
local unitKit

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

-- The kind of hit: physical, magic, or nil when the row is both or neither.
local function kindOf(skill)
    if not skill then return nil end
    local info = skill.known or knownOf(skill)
    local phys = (skill.attr == ATTR.FIGHT) or (info and info.phys)
    local magic = (skill.attr == ATTR.MAGIC) or (info and info.magic)
    if phys and not magic then return "physical" end
    if magic and not phys then return "magic" end
    return nil
end

-- A kind the card nulls, or one this fight has seen do no damage twice, is
-- a miss, the same as a nulled element.
local function elementFactor(skill, enemy)
    local ok, factor = pcall(function()
        local info = skill and (skill.known or knownOf(skill))
        local el = info and info.element
        if not enemy then return 1 end
        local card = mobOf(enemy)
        local kind = kindOf(skill)
        if kind then
            if card and card.no and card.no[kind] then return 0 end
            local learned = Fight and Fight.kindNull and Fight.kindNull[enemy.id]
            if learned and learned[kind] then return 0 end
        end
        if not el then return 1 end
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
    -- With no slot count from the game, the bar's size says how many gauges
    -- it holds. Dividing by one slot read a full 200-point bar as one gauge.
    if ((one == nil) or (one <= 0)) and maxv and (maxv > 0) then
        local n = slots
        if (n == nil) or (n < 1) or (n > 4) then
            n = math.floor((maxv / LB_POINTS.gauge) + 0.5)
            if n < 1 then n = 1 end
            if n > 4 then n = 4 end
        end
        one = maxv / n
    end
    local filled = nil
    if (points ~= nil) and (one ~= nil) and (one > 0) then
        filled = math.floor((points / one) + 1e-6)
    end
    -- The game's own count wins over the math once it is trusted.
    if (unitGauges ~= nil) and (unitGauges >= 0) and (unitGauges <= 4) then
        if unitGauges == 0 then LB_POINTS.countTrusted = true end
        if LB_POINTS.countTrusted then filled = unitGauges end
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
    local info = copy.known
    -- A player-only row stays off the kit. The damage picker never sees it.
    if info and info.use == "skip" then return nil end
    local okKind, kind = pcall(classify, copy)
    copy.kind = okKind and kind or nil
    if copy.attr == ATTR.SUMMON and Espers.lookup then
        local fact = Espers.lookup(copy.name)
        if fact then
            if copy.known then
                local merged = {}
                for k, v in pairs(copy.known) do merged[k] = v end
                for k, v in pairs(fact) do
                    if merged[k] == nil then merged[k] = v end
                end
                if not merged.use then merged.use = "summon" end
                copy.known = merged
            else
                copy.known = fact
            end
        end
        if copy.known and copy.known.role == "guard" then copy.kind = "buff" end
    end
    -- The book is the role for a Limit Burst. A shared name on an ordinary
    -- skill stays a spell. known.lua still supplies a stagger the book omits.
    if copy.attr == ATTR.LB and Limits.lookup then
        local fact = Limits.lookup(copy.name)
        if fact then
            copy.known = Limits.apply(copy.known, fact)
            info = copy.known
        elseif copy.name and Fight then
            Fight.limitUntagged = Fight.limitUntagged or {}
            local key = foldName(copy.name)
            if (key ~= "") and (not Fight.limitUntagged[key]) then
                Fight.limitUntagged[key] = true
                local line = "limit " .. copy.name .. " untagged"
                log("%s", line)
                appendLog("  " .. line)
            end
        end
    end
    if info then
        if info.stagger then copy.breakPower = info.stagger end
        if info.use == "guard" then copy.kind = "defend"
        elseif info.use == "opener" or info.use == "guardbuff" or info.use == "buff" or info.use == "lb-setup"
            or info.use == "lb-break" or info.use == "lb-guard" then
            copy.kind = "buff"
        elseif info.use == "lb-revive" or info.use == "revive" then copy.kind = "revive"
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
        -- Each Limit row once a fight: what the planner thinks it is.
        if Fight and not borrowed then
            Fight.lbRows = Fight.lbRows or {}
            local rowKey = tostring(uid) .. ":" .. tostring(id)
            if not Fight.lbRows[rowKey] then
                Fight.lbRows[rowKey] = true
                local line = string.format("limit row %s on %s: use %s, gauges %s, kind %s, effect %s, target %s",
                    (copy.name and copy.name ~= "") and copy.name or ("#" .. tostring(id)), unitName(uid),
                    tostring(info and info.use or "none"), tostring(gauges), tostring(copy.kind),
                    tostring(copy.effect), tostring(copy.target))
                log("%s", line)
                appendLog("  " .. line)
            end
        end
        if (not borrowed) and (not limitReady(uid, copy)) then return nil end
    end
    if (not copy.kind) and Kits.lookup and Kits.lookup(copy.name) then
        copy.kind = "buff"
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
    -- A kit read while the ally is down is not kept. It is read again
    -- once they stand, so the party knows what they can do.
    local down = Fight.unitDown and Fight.unitDown(uid)
    if (#kit.spells > 0) and (not down) then Fight.kits[uid] = kit end
    return kit
end

local function friendAction(skill)
    if skill.kind == "revive" then return true end
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
    if skill.kind == "revive" then
        for _, id in ipairs(targets or {}) do
            for _, l in ipairs(legal) do
                if id == l then return { id }, false end
            end
        end
        if targets and (#targets > 0) then return targets, false end
    end
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

-- Raise order: the healer, then on a threatened field the ally who pulls
-- hits off the others, then the top damage dealer.
local function raiseOrder()
    return {
        threat = Fight and Fight.threat or false,
        guards = Kits.guards,
        maxHpOf = function(id) return stat(id, PARAM.HP, true) end,
    }
end

-- A stance goes up or comes off when its cast goes out.
local function noteStance(uid, name)
    if (not Kits.stance) or (not uid) or (uid < 0) or (not name) then return end
    local turn, key = Kits.stance(name)
    if not turn then return end
    Fight.stance = Fight.stance or {}
    Fight.stance[uid] = Fight.stance[uid] or {}
    Fight.stanceEnded = Fight.stanceEnded or {}
    Fight.stanceEnded[uid] = Fight.stanceEnded[uid] or {}
    if turn == "on" then
        Fight.stance[uid][key] = Fight.rounds or 0
    else
        Fight.stance[uid][key] = nil
        Fight.stanceEnded[uid][key] = Fight.rounds or 0
    end
end

local function firstDead(w, pred)
    for _, u in ipairs(w.allies) do
        if u.dead and (not pred or pred(u)) then return u end
    end
    return nil
end

local function lockedAlly(w)
    if Health.locked then return Health.locked(w.allies) end
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
    if not (Items.potFight and Items.potFight(w.enemies)) then return false end
    if not potLogged then
        potLogged = true
        log("pot fight: leaving items for you")
    end
    return true
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
    if not Items.entry then return out end
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
            -- What the game's own rows say. The book in items.lua does the rest.
            local f = { rare = row and row.rare or nil }
            local s = row and row.skillId and skillOf(row.skillId) or nil
            if s then
                if Health.FIXED and (s.calc == Health.FIXED) and ((s.power or 0) > 0) then f.amount = s.power end
                if s.effect == EFF.REVIVE or (s.rel == REL.FRIEND and s.targetState == 2) then f.revive = true end
                if s.effect == EFF.CURE then f.cure = true end
                if s.rel == REL.FRIEND and s.effect == EFF.DAMAGE and s.paramType == PARAM.HP
                    and (s.varType == VAR.UP or s.varType == VAR.RATIO) then
                    f.rowHp = true
                end
                if s.rel == REL.FRIEND and s.paramType == PARAM.MP
                    and (s.varType == VAR.UP or s.varType == VAR.RATIO) then
                    f.rowMp = true
                end
                -- The item's own row says whether it lands on every ally.
                if s.rel == REL.FRIEND and aoeOf(s) then f.party = true end
            end
            f.saysHp = saysYes(bfl, "IsAbleRecoverHitPoint", id) or saysYes(lib, "IsAbleRecoverHitPoint", id)
            f.saysMp = saysYes(bfl, "IsAbleRecoverMagicPoint", id) or saysYes(lib, "IsAbleRecoverMagicPoint", id)
            local entry = Items.entry(id, name, count, f)
            if entry then out[#out + 1] = entry end
        end
    end
    if not itemsLogged then
        itemsLogged = true
        log("%s", Items.bagLine(out, catalog))
    end
    return out
end

local function itemChoice(uid, item, reason, targetId, use)
    local fake = { id = item.id, name = item.name, kind = "item", attr = ATTR.ITEM, target = TGT.SINGLE, cost = 0 }
    local choice = finishChoice(uid, fake, reason, { targetId }, false, true)
    if choice then choice.itemUse = use end
    return choice
end

local function pickRecoveryItem(uid, w, want, focus)
    if potFight(w) then return nil end
    if not Items.recovery then return nil end
    local owned = ownedRecovery()
    local dire = (Health.direNeed and Health.direNeed(w)) and true or false
    local function tagged(choice, rare)
        if choice and rare then choice.reason = choice.reason .. " (rare, boss)" end
        return choice
    end
    if want == "revive" then
        local dead = (Health.fallen and Health.fallen(w.allies, unitKit, offenseOf, raiseOrder()))
            or firstDead(w, function(u) return u.acts ~= false end) or firstDead(w)
        if not dead then return nil end
        local it, rare = Items.recovery(owned, "revive", { boss = w.boss })
        if it then return tagged(itemChoice(uid, it, "item raise " .. dead.name, dead.id, "revive"), rare) end
        return nil
    end
    if want == "heal" then
        local hurt = lowestAlly(w)
        if not hurt then return nil end
        local missing = nil
        local maxv = stat(hurt.id, PARAM.HP, true)
        local ratio = hurt.hp or 1
        if maxv and (maxv > 0) and (ratio < 1) then missing = (1 - ratio) * maxv end
        -- Most of the living party under half: a party item is a group heal.
        local living, hurtN = {}, 0
        for _, a in ipairs(w.allies) do
            if not a.dead then
                living[#living + 1] = a.id
                if (a.hp or 1) < 0.50 then hurtN = hurtN + 1 end
            end
        end
        local need = Health.partyNeed and Health.partyNeed(#living) or 3
        local it, rare = Items.recovery(owned, "heal", {
            boss = w.boss, missing = missing, dire = dire,
            spread = hurtN >= need, partyOnly = focus and focus.partyOnly,
        })
        if not it then return nil end
        local pct = math.floor((hurt.hp or 0) * 100 + 0.5)
        if it.party and (#living > 0) then
            local fake = { id = it.id, name = it.name, kind = "item", attr = ATTR.ITEM, target = TGT.ALL, cost = 0 }
            local choice = finishChoice(uid, fake, string.format("item party heal, %s at %d%%", hurt.name, pct),
                living, true, true)
            if choice then
                choice.itemUse = "hp"
                if Fight and Fight.claim and Fight.claim.heal then
                    for _, id in ipairs(living) do Fight.claim.heal[id] = true end
                end
            end
            return tagged(choice, rare)
        end
        return tagged(itemChoice(uid, it, string.format("item heal %s at %d%%", hurt.name, pct), hurt.id, "hp"), rare)
    end
    if want == "cure" then
        local who = focus or lockedAlly(w)
        if not who then return nil end
        local soft = focus and focus.soft
        local it, saw = Items.cure(owned, who, {
            soft = soft, allies = w.allies,
            healerOf = function(allies) return Health.mainHealer and Health.mainHealer(allies, unitKit) or nil end,
        })
        if it then
            local why = "item cure " .. who.name
            if focus and focus.tier == "rescue" then why = "item rescue " .. who.name end
            if focus and focus.tier == "doom" then why = "item cure doom " .. who.name end
            if focus and focus.tier == "b" then why = "item cure soft " .. who.name end
            return itemChoice(uid, it, why, who.id, "cure")
        end
        if saw and (not soft) and Fight and (not Fight.cureHeld) then
            Fight.cureHeld = true
            log("cure item skipped, lock remains")
        end
        return nil
    end
    -- Boss fight attack item. focus is the pool. A scroll goes on a weakness
    -- the bar cannot pay; with focus.landing, any item that lands will do.
    if want == "attack" then
        local best, bestU, bestF = Items.throw(owned, {
            boss = w.boss, list = focus and focus.list, landing = focus and focus.landing,
            factorOf = elementFactor, itemAttr = ATTR.ITEM,
        })
        if not best then return nil end
        local fake = { id = best.id, name = best.name, kind = "item", attr = ATTR.ITEM, target = TGT.SINGLE, cost = 0,
            known = best.attack }
        local why = (bestF >= 3) and ("throw " .. best.name .. " on " .. bestU.name .. " weakness")
            or ("throw " .. best.name .. " on " .. bestU.name .. ", nothing payable lands")
        local choice = finishChoice(uid, fake, why, { bestU.id }, false, true)
        if choice then choice.itemUse = "attack" end
        return choice
    end
    if want == "mp" then
        local it, rare = Items.recovery(owned, "mp", { boss = w.boss, dire = dire })
        if it then return tagged(itemChoice(uid, it, "ether " .. unitName(uid), uid, "mp"), rare) end
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
    local function yes(v)
        return v == true or v == 1
    end
    local function unitDown(id, param)
        local p = param or paramOf(id)
        if not p then
            local bfl = battleLib()
            if bfl and bfl:IsValid() then
                local ok, q = pcall(function() return bfl:GetBattleUnitParameter(id, false) end)
                if ok and q and q.IsValid and q:IsValid() then p = q end
            end
        end
        if p then
            local ok, v = pcall(function() return p:isDead() end)
            if ok and yes(v) then return true end
            ok, v = pcall(function() return p.isDead end)
            if ok and yes(v) then return true end
            ok, v = pcall(function() return p:GetHitPoint() end)
            v = ok and num(v) or nil
            if (v ~= nil) and (v <= 0) then return true end
        end
        local ratio = hpRatio(id)
        return (ratio ~= nil) and (ratio <= 0)
    end
    if Fight then Fight.unitDown = unitDown end
    local function addAlly(id, down)
        local r = hpRatio(id)
        local hp = r or 1
        if down then hp = 0 end
        local name = (Fight and Fight.nameOf) and Fight.nameOf(id) or unitName(id)
        allies[#allies + 1] = {
            id = id, name = name, hp = hp,
            dead = down and true or false, statuses = statuses(id),
        }
    end
    local have = {}
    for _, id in ipairs(friendIds()) do
        have[id] = true
        addAlly(id, unitDown(id))
    end
    local extra = fill(function(t)
        local bfl = battleLib()
        if bfl and bfl:IsValid() then bfl:GetAllBattleUnitPararmeterList(t, false) end
    end)
    if extra then
        for _, p in ipairs(extra) do
            local id = num(p)
            local param = nil
            if (not id) and (type(p) == "userdata") then
                param = p
                local ok, v = pcall(function() return p:GetUniqueId() end)
                id = ok and num(v) or nil
                if not id then
                    ok, v = pcall(function() return p.UniqueId end)
                    id = ok and num(v) or nil
                end
            end
            if id and not have[id] then
                local rel = nil
                if param then
                    local ok, v = pcall(function() return param:GetRelation() end)
                    rel = ok and num(v) or nil
                else
                    local q = paramOf(id)
                    if q then
                        local ok, v = pcall(function() return q:GetRelation() end)
                        rel = ok and num(v) or nil
                    end
                end
                if (rel == REL.FRIEND) and unitDown(id, param) then
                    have[id] = true
                    addAlly(id, true)
                end
            end
        end
    end
    if #allies == 0 then
        addAlly(uid, unitDown(uid))
    end
    if Fight then
        if not Fight.seenAlly then Fight.seenAlly = {} end
        -- The party is on the field when the fight begins. A friend that
        -- arrives later with no skill list, or one the Esper book names, is
        -- a summon: it is not healed, raised, counted, or waited on, and it
        -- stays one for the fight.
        Fight.summons = Fight.summons or {}
        local party = {}
        for _, a in ipairs(allies) do
            if (a.id ~= uid) and Fight.isSummon then Fight.isSummon(a.id, a.name) end
            if not Fight.summons[a.id] then party[#party + 1] = a end
        end
        if #party > 0 then allies = party end
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
    claim = { heal = {}, revive = {}, hone = {}, ether = {}, scan = {}, kit = {}, etherRound = false, guard = false, esper = false, lb = false },
    debuffOn = {}, debuffSeen = {}, debuffTold = {},
    went = {}, rounds = 0, seenFoe = {}, planTag = nil, afterBonus = false,
    fieldTold = false, chipped = false,
    esperOut = nil, esperTold = false, esperSkip = {},
    limitUntagged = {}, limitSkip = {},
    cureHeld = false,
    healLeft = {},
    statusTold = {},
    slowSince = {}, slowTry = nil, slowTold = {}, slowUsed = {},
    underLine = false,
}

-- The summon test, wherever the party is read. See worldOf.
Fight.isSummon = function(id, name)
    Fight.summons = Fight.summons or {}
    if Fight.summons[id] then return true end
    if (not Fight.openIds) or Fight.openIds[id] or (Fight.seenAlly and Fight.seenAlly[id]) then return false end
    local esper = Espers.lookup and Espers.lookup(name or unitName(id))
    if esper or (#equippedIds(id) == 0) then
        Fight.summons[id] = true
        return true
    end
    return false
end

-- A party slot can read no name, when fallen or on the wheel. The name seen
-- earlier in the fight is the party member's name.
Fight.nameOf = function(id)
    local name = unitName(id)
    if name:find("^Unit ") and Fight.seenAlly and Fight.seenAlly[id] then return Fight.seenAlly[id] end
    return name
end

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
        if choice.known and limitSkill({ known = choice.known }) then limitCast = true end
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
    -- No finisher lands on the field: the wheel is left for the player.
    if not best then return nil end
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

local function markDebuff(id, effect)
    if (not id) or (not effect) or (effect == "") then return end
    Fight.debuffOn = Fight.debuffOn or {}
    local row = Fight.debuffOn[id]
    if not row then
        row = {}
        Fight.debuffOn[id] = row
    end
    row[effect] = true
    -- A fresh cast has not been seen yet. Clearing the old sighting
    -- stops a refresh from repeating until the status is back, then gone.
    if Fight.debuffSeen and Fight.debuffSeen[id] then
        Fight.debuffSeen[id][effect] = nil
    end
end

local function turn(uid, skills, w, phase)
    -- One slot of the round. Care first, then the phase the whole field is in.
    -- Damage is scored against every living gauge, using what earlier slots already claimed.
    w.usedSupport = w.usedSupport or {}
    Fight.claim = Fight.claim or {
        heal = {}, revive = {}, hone = {}, ether = {},
        guard = false, esper = false, lb = false, scan = {}, kit = {},
        etherRound = false,
    }
    Fight.debuffOn = Fight.debuffOn or {}
    Fight.debuffSeen = Fight.debuffSeen or {}
    Fight.debuffTold = Fight.debuffTold or {}
    Fight.scanned = Fight.scanned or {}
    Fight.poured = Fight.poured or {}
    Fight.down = Fight.down or {}
    Fight.relax = Fight.relax or {}
    Fight.gaugeScale = Fight.gaugeScale or {}
    Fight.brokeOn = Fight.brokeOn or {}
    Fight.kitOn = Fight.kitOn or {}
    Fight.claim.kit = Fight.claim.kit or {}

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
        if use == "skip" or use == "opener" or use == "guardbuff" or use == "guard" or use == "scan" or use == "heal" or use == "cure" then
            return false
        end
        if use == "lb-setup" or use == "lb-revive" or use == "revive" or use == "lb-break" or use == "lb-guard" then return false end
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

    -- An ally whose status takes the turn is not counted on to act: not to
    -- heal, chip, pay a weakness, or cast the setup. The actor is acting now.
    local function heldOut(a)
        if (not a) or (a.id == uid) or (not Health.OUT) or (not a.statuses) then return false end
        for sid in pairs(Health.OUT) do
            if a.statuses[sid] then return true end
        end
        return false
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
            if not a.dead and a.acts ~= false and not heldOut(a) then
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
    Fight.threat = hardField

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

    if (Fight.rounds or 0) == 0 and not Fight.entryTold and Health.entryNote then
        Fight.entryTold = true
        local note = Health.entryNote(w.allies)
        if note then
            log("%s", note)
            appendLog("  " .. note)
        end
    end
    Fight.downNow = {}
    Fight.stance = Fight.stance or {}
    for _, a in ipairs(w.allies) do
        if a.dead then Fight.stance[a.id] = nil end
        if not a.dead then Fight.claim.revive[a.id] = nil
        elseif a.acts ~= false then Fight.downNow[#Fight.downNow + 1] = a end
    end
    local dead = (Health.fallen and Health.fallen(w.allies, unitKit, offenseOf, raiseOrder()))
        or firstDead(w, function(u) return u.acts ~= false end) or firstDead(w)
    if dead and Fight.claim.revive[dead.id] then
        local at = Fight.claim.revive[dead.id]
        local waitN = #w.allies
        if waitN < 2 then waitN = 2 end
        if (type(at) == "number") and ((#(Fight.actions or {}) - at) >= waitN) then
            Fight.claim.revive[dead.id] = nil
        end
    end
    -- The living come first. A raise waits while a living ally is critical
    -- and not yet healed this round, unless the fallen ally is the party's
    -- best healer. An ally who fell again within two rounds of a raise is
    -- not raised again for three rounds, or sooner once no living ally is
    -- under half. That guard holds for the best healer too. The Timeline is not
    -- readable, so these are the signs that the next hit would drop them.
    Fight.refell = Fight.refell or {}
    Fight.raisedRound = Fight.raisedRound or {}
    for _, a in ipairs(w.allies) do
        local at = Fight.raisedRound[a.id]
        if (not a.dead) and at and (((Fight.rounds or 0) - at) >= 3) then
            Fight.refell[a.id] = nil
            Fight.raisedRound[a.id] = nil
        end
    end
    local raiseHold = nil
    -- A party raise Limit brings every fallen ally back with their HP, so
    -- neither hold applies: it goes out at once when two or more are down.
    local partyRaise = false
    if dead and (#(Fight.downNow or {}) >= 2) then
        for _, s in ipairs(skills) do
            if (s.kind == "revive") and s.known and (s.known.use == "lb-revive") and s.known.party and pay(s) then
                partyRaise = true
            end
        end
    end
    if dead and not Fight.claim.revive[dead.id] and not partyRaise then
        -- How well a kit does the healing job: the heal score, then a raise
        -- spell, then the number of real heals.
        local function healWorth(kit)
            if (not kit) or ((kit.healScore or 0) < 50) then return 0 end
            local raise, heals = 0, 0
            for _, s in ipairs(kit.spells or {}) do
                if s.kind == "revive" then raise = 1 end
                if (s.kind == "heal") and not (s.known and s.known.patch) then heals = heals + 1 end
            end
            return (kit.healScore or 0) * 100 + raise * 10 + heals
        end
        local critical, underHalf, bestLiving = false, false, 0
        for _, a in ipairs(w.allies) do
            if not a.dead then
                -- A critical ally this turn can still help: not yet healed this round.
                if ((a.hp or 1) < 0.30) and (not Fight.claim.heal[a.id]) then critical = true end
                if (a.hp or 1) < 0.50 then underHalf = true end
                if (a.acts ~= false) and (not heldOut(a)) then
                    local worth = healWorth(unitKit(a.id))
                    if worth > bestLiving then bestLiving = worth end
                end
            end
        end
        -- The party's best healer is raised at once: they keep the rest up.
        -- The party's best healer skips the wait on a critical ally. The
        -- cycle guard holds for everyone: a raise that fell straight back
        -- is not repeated into the same hits.
        local bestHealer = healWorth(unitKit(dead.id)) > bestLiving
        -- The guard lasts three rounds from the fall, so no ally is left down for the whole fight.
        local fellAt = Fight.refell[dead.id]
        local cycling = (type(fellAt) == "number") and (((Fight.rounds or 0) - fellAt) < 3)
        if cycling and underHalf then
            raiseHold = dead.name .. " fell again after a raise"
        elseif critical and (not bestHealer) then
            raiseHold = "a living ally is critical"
        end
        if raiseHold then
            Fight.healLeft = Fight.healLeft or {}
            local key = "hold" .. tostring(dead.id)
            if not Fight.healLeft[key] then
                Fight.healLeft[key] = true
                local line = string.format("raise %s waits, %s", dead.name, raiseHold)
                log("%s", line)
                appendLog("  " .. line)
            end
        end
    end
    if dead and not Fight.claim.revive[dead.id] and not raiseHold then
        local oneLeft, calm = #w.enemies == 1, true
        for _, u in ipairs(w.enemies) do
            local card = mobOf(u)
            if card and card.danger and card.danger[1] then calm = false end
            local _, remain, empty, _ = gaugeOfEnemy(u)
            local gauge = gaugeOfEnemy(u)
            if not empty and remain > gauge * 0.25 then calm = false end
        end
        if ((Fight.rounds or 0) == 0) or not (oneLeft and calm) then
            local function raiseFallen(allowOne)
                local downN = #Fight.downNow
                if (downN < 1) and dead then downN = 1 end
                local s, partyHit = nil, false
                if Limits.bestRaise then
                    s, partyHit = Limits.bestRaise(skills, downN, pay, allowOne)
                elseif not allowOne then
                    for _, row in ipairs(skills) do
                        if (row.kind == "revive") and pay(row) then s = row break end
                    end
                end
                if not s then return nil end
                local many = partyHit and (#Fight.downNow >= 2)
                local ids = (many and idsOf(Fight.downNow)) or { dead.id }
                local why = (many and "raise the party") or ("raise " .. dead.name)
                local choice = finishChoice(uid, s, why, ids, many and true or false)
                if not choice then return nil end
                local at = #(Fight.actions or {})
                Fight.claim.revive[dead.id] = at
                if many then
                    for _, ally in ipairs(Fight.downNow) do
                        Fight.claim.revive[ally.id] = at
                    end
                end
                return choice
            end
            local choice = raiseFallen(false)
            if choice then return choice end
            -- Another ally who can pay a raise spell does it better than an
            -- item. Leave it to them while they still have a turn this round.
            -- A raiser who is out of MP, held by a status, or already gone
            -- this round is not waited on, and anyone spends the item.
            local raiser = nil
            for _, a in ipairs(w.allies) do
                if (a.id ~= uid) and (not a.dead) and (a.acts ~= false) and (not heldOut(a))
                    and (not (Fight.went and Fight.went[a.id])) then
                    local kit = unitKit(a.id)
                    local mp = stat(a.id, PARAM.MP, false) or 0
                    for _, s in ipairs((kit and kit.spells) or {}) do
                        if (s.kind == "revive") and ((s.cost or 0) > 0) and ((s.cost or 0) <= mp) then
                            raiser = a
                        end
                    end
                end
            end
            if raiser then
                Fight.healLeft = Fight.healLeft or {}
                local key = "raise" .. tostring(uid)
                if not Fight.healLeft[key] then
                    Fight.healLeft[key] = true
                    local line = string.format("raise left to %s, %s waits", raiser.name, unitName(uid))
                    log("%s", line)
                    appendLog("  " .. line)
                end
            else
                local item = pickRecoveryItem(uid, w, "revive")
                if item then Fight.claim.revive[dead.id] = #(Fight.actions or {}) return item end
                choice = raiseFallen(true)
                if choice then return choice end
            end
        end
    end

    local function healNow(hurt, why, itemAt)
        if not hurt or Fight.claim.heal[hurt.id] then return nil end
        if Health.healerWaiting then
            local danger = false
            for _, u in ipairs(w.enemies) do
                local card = mobOf(u)
                if card and card.danger and card.danger[1] then
                    local _, _, empty = gaugeOfEnemy(u)
                    if (not empty) and (not u.broken) then danger = true end
                end
            end
            local mpOf = function(id)
                if id == uid then return w.mp or 0 end
                return stat(id, PARAM.MP, false) or 0
            end
            if Health.healerWaiting(uid, why, hurt.hp, danger, w.allies, unitKit, mpOf, Fight.went) then
                Fight.healLeft = Fight.healLeft or {}
                if not Fight.healLeft[uid] then
                    Fight.healLeft[uid] = true
                    local line = string.format("heal left, %s waits", unitName(uid))
                    log("%s", line)
                    appendLog("  " .. line)
                end
                return nil
            end
        end
        local skill, rank = nil, -1
        -- A stance on the hurt ally blocks white-magic heals. Items still land.
        local barred = false
        for _ in pairs((Fight.stance and Fight.stance[hurt.id]) or {}) do barred = true end
        -- A party heal is the pick when most of the living party is under
        -- half. The same share at any party size.
        local hurtN, living = 0, 0
        for _, a in ipairs(w.allies) do
            if not a.dead then living = living + 1 end
            if not a.dead and (a.hp or 1) < 0.50 then hurtN = hurtN + 1 end
        end
        local need = Health.partyNeed and Health.partyNeed(living) or 3
        local missing = nil
        local maxv = stat(hurt.id, PARAM.HP, true)
        local ratio = hurt.hp or 1
        if maxv and (maxv > 0) and (ratio < 1) then missing = (1 - ratio) * maxv end
        for _, s in ipairs(skills) do
            if (s.kind == "heal") and pay(s) and (not isPatch(s))
                and not (barred and (s.attr == ATTR.MAGIC)) then
                local party = partyOf(s)
                local r
                if Health.spellRank then
                    r = Health.spellRank(s, missing, hurtN, party, need)
                else
                    local cost = s.cost or 0
                    if cost < 1 then cost = 1 end
                    local power = s.power or 0
                    if power > 0 then
                        r = power / cost
                        if (hurtN >= need) and party then r = r * 3 end
                    elseif (hurtN >= need) and party then
                        r = 3 + (0.01 / cost)
                    elseif party then
                        r = 0.5 + (0.01 / cost)
                    else
                        r = 1 + (0.01 / cost)
                    end
                end
                if r > rank then skill, rank = s, r end
            end
        end
        -- A group heal beats every single heal. With no party heal spell to
        -- pay, a party item goes out on that spread.
        if (hurtN >= need) and ((not skill) or (not partyOf(skill))) then
            local item = pickRecoveryItem(uid, w, "heal", { partyOnly = true })
            if item then Fight.claim.heal[hurt.id] = true return item end
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
        if (not skill) and blocked and (not Fight.claim.ether[uid])
            and ((not Fight.claim.etherRound) or (Health.direNeed and Health.direNeed(w))) then
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
                if (s.kind == "heal") and pay(s) and isPatch(s)
                    and not (barred and (s.attr == ATTR.MAGIC)) then
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
        -- The same hit the damage picker would cast. A summon is not a chip.
        local function pays(spells, mp)
            for _, s in ipairs(spells) do
                if isHit(s, false) and (s.cost or 0) <= mp then
                    for _, u in ipairs(list) do
                        if elementFactor(s, u) >= 3 then return true end
                    end
                end
            end
            return false
        end
        if not pays(skills, w.mp or 0) then return false end
        -- The payer keeps chipping only while someone else can still heal.
        local others, otherPays, otherHeals = 0, false, false
        local mpOf = function(id) return stat(id, PARAM.MP, false) or 0 end
        for _, a in ipairs(w.allies) do
            if a.id ~= uid and not a.dead and a.acts ~= false and not heldOut(a) then
                others = others + 1
                local kit = unitKit(a.id)
                local mp = mpOf(a.id)
                if kit and pays(kit.spells or {}, mp) then otherPays = true end
                if kit and ((kit.healScore or 0) >= 50) then
                    if Health.available then
                        if Health.available(a, a.statuses, unitKit, mpOf) then otherHeals = true end
                    elseif ((kit.healCost or 0) <= 0) or (mp >= (kit.healCost or 0)) then
                        otherHeals = true
                    end
                end
            end
        end
        return others > 0 and not otherPays and otherHeals
    end
    if crit and phase ~= PHASE_BONUS and not deferHeal() then
        local choice = healNow(crit, "critical")
        if choice then return choice end
    end
    if phase == PHASE_BONUS or #brokenPool > 0 and phase == PHASE_BONUS then
        local choice = healNow(crit, "critical")
        if choice then return choice end
    end

    Fight.statusTold = Fight.statusTold or {}
    if Health.unknownNotes then
        local notes = Health.unknownNotes(w.allies, Fight.statusTold)
        for _, line in ipairs(notes) do
            log("%s", line)
            appendLog("  " .. line)
        end
    end
    local function castCure(focus)
        if (not focus) or Fight.claim.heal[focus.id] then return nil end
        local function bySkill()
            if focus.itemOnly then return nil end
            local why = "cure " .. (focus.name or "")
            if focus.tier == "rescue" then why = "rescue " .. (focus.name or "") end
            if focus.tier == "doom" then why = "cure doom " .. (focus.name or "") end
            if focus.tier == "b" then why = "cure soft " .. (focus.name or "") end
            if focus.tier == "slow" then why = "cure slow " .. (focus.name or "") end
            -- A cure is aimed at a status its row lists, when it lists any.
            -- A cure that went out and left the same status is a miss. Two
            -- misses and that cure is not spent on that status this fight.
            Fight.cureTry = Fight.cureTry or {}
            Fight.cureMiss = Fight.cureMiss or {}
            local ids = {}
            for id in pairs(focus.statuses or {}) do
                if LOCK[id] or (id == 1) or (id == 2) or (id == 12) then ids[#ids + 1] = id end
            end
            table.sort(ids)
            local sig = table.concat(ids, ",")
            local try = Fight.cureTry[focus.id]
            if try then
                Fight.cureTry[focus.id] = nil
                local fresh = ((Fight.rounds or 0) - (try.round or 0)) <= 1
                if fresh and (try.sig == sig) and (#(Fight.actions or {}) > (try.at or 0)) then
                    local k = try.name .. "|" .. sig
                    Fight.cureMiss[k] = (Fight.cureMiss[k] or 0) + 1
                    if Fight.cureMiss[k] == 2 then
                        local line = string.format("cure %s does not clear status %s on %s", try.name, sig, focus.name or "?")
                        log("%s", line)
                        appendLog("  " .. line)
                    end
                end
            end
            for _, s in ipairs(skills) do
                if (s.kind == "cure") and pay(s) then
                    local lists, hits = anyKey(s.friendStatus), false
                    if lists then
                        for id in pairs(focus.statuses or {}) do
                            if s.friendStatus[id] then hits = true end
                        end
                    end
                    local missed = (Fight.cureMiss[(s.name or "") .. "|" .. sig] or 0) >= 2
                    if ((not lists) or hits) and (not missed) then
                        local choice = finishChoice(uid, s, why, { focus.id }, aoeOf(s))
                        if choice then
                            Fight.cureTry[focus.id] = {
                                name = s.name or "", sig = sig,
                                at = #(Fight.actions or {}), round = Fight.rounds or 0,
                            }
                            return choice
                        end
                    end
                end
            end
            return nil
        end
        local function byItem()
            return pickRecoveryItem(uid, w, "cure", focus)
        end
        local choice = nil
        if focus.itemOnly or focus.itemFirst then
            choice = byItem() or bySkill()
        else
            choice = bySkill() or byItem()
        end
        if choice then Fight.claim.heal[focus.id] = true end
        return choice
    end
    local function curePass(urgent)
        if urgent then
            Fight.slowSince = Fight.slowSince or {}
            Fight.slowTold = Fight.slowTold or {}
            if Health.watchSlow then
                Health.watchSlow(w.allies, Fight.slowSince, Fight.rounds or 0)
            end
        end
        if (phase == PHASE_BONUS) or (not Health.cureNow) then return nil end
        local mpOf = function(id)
            if id == uid then return w.mp or 0 end
            return stat(id, PARAM.MP, false) or 0
        end
        local calm = (not urgent) and (not allyCritical()) and (not Fight.underLine)
            and (not ((phase == 0) and hardField and (style ~= "aggressive") and (not Fight.chipped)))
        local dead = false
        if not urgent then
            for _, a in ipairs(w.allies) do
                if a.dead then dead = true end
            end
            local owed = Health.cureNow(w.allies, unitKit, mpOf, {
                actorId = uid,
                critical = allyCritical() ~= nil,
                urgent = true,
            })
            if owed then return nil end
        end
        local focus = Health.cureNow(w.allies, unitKit, mpOf, {
            actorId = uid,
            critical = allyCritical() ~= nil,
            band = band(),
            urgent = urgent,
            dead = dead,
            under = (not urgent) and Fight.underLine and true or false,
            setup = (not urgent) and (phase == 0) and hardField and (style ~= "aggressive")
                and (not Fight.chipped) and true or false,
        })
        local choice = castCure(focus)
        if choice or urgent or (not calm) or dead or (not Health.slowFocus) then return choice end
        local foes = (#pool > 0) and pool or open
        if #foes == 0 then foes = w.enemies end
        local weakId, weakN, stagId, stagN, window = nil, 0, nil, 0, false
        for _, u in ipairs(foes) do
            local gauge, remain, empty = gaugeOfEnemy(u)
            local poured = Fight.poured and Fight.poured[u.id] or 0
            if (not empty) and (not u.broken) and (gauge > 0) and (remain < gauge) and (poured > 0) then
                window = true
            end
        end
        for _, a in ipairs(w.allies) do
            if (not a.dead) and (a.acts ~= false) and not heldOut(a) then
                local mp = (a.id == uid) and (w.mp or 0) or (stat(a.id, PARAM.MP, false) or 0)
                local spells = skills
                if a.id ~= uid then
                    local kit = unitKit(a.id)
                    spells = (kit and kit.spells) or {}
                end
                local weak, finish = false, false
                for _, s in ipairs(spells) do
                    if isHit(s, false) and ((s.cost or 0) <= mp) then
                        for _, u in ipairs(foes) do
                            if elementFactor(s, u) >= 3 then weak = true end
                            if window then
                                local _, remain, empty = gaugeOfEnemy(u)
                                if not empty then
                                    local gained, f = staggerOf(s, u)
                                    if (f > 0) and (gained > 0) and (gained >= remain) then
                                        finish = true
                                    end
                                end
                            end
                        end
                    end
                end
                if weak then
                    weakN = weakN + 1
                    weakId = a.id
                end
                if finish then
                    stagN = stagN + 1
                    stagId = a.id
                end
            end
        end
        if weakN ~= 1 then weakId = nil end
        if (not window) or (stagN ~= 1) then stagId = nil end
        focus = Health.slowFocus(w.allies, unitKit, mpOf, {
            actorId = uid,
            round = Fight.rounds or 0,
            since = Fight.slowSince,
            critical = false,
            dead = false,
            under = false,
            setup = false,
            weakId = weakId,
            stagId = stagId,
        })
        if (not focus) or Fight.claim.heal[focus.id] or Fight.slowTry then return nil end
        local maxv = w.maxMp or 0
        local mpNow = w.mp or 0
        local keep = 0
        local selfKit = unitKit(uid)
        local healer = Health.mainHealer(w.allies, unitKit)
        if healer and (healer.id == uid) and selfKit then keep = selfKit.healCost or 0 end
        local pick, pickKey = nil, nil
        Fight.slowUsed = Fight.slowUsed or {}
        for _, s in ipairs(skills) do
            if (s.kind == "cure") and Health.slowKey and Health.spareMp and Health.slowAllowed and Health.listsSlow then
                local key = Health.slowKey("skill", s.name)
                local spare = (Health.listsSlow(s) or (Health.slowVerdict(key) == "yes"))
                    and Health.spareMp(mpNow, maxv, s.cost or 0, keep)
                    and Health.slowAllowed(key, Fight.slowUsed[key])
                if spare and (Health.slowVerdict(key) == "yes") then
                    pick, pickKey = s, key
                    break
                end
                if spare and (not pick) then pick, pickKey = s, key end
            end
        end
        if not pick then
            Fight.slowNote = Health.slowGap and Health.slowGap(w.allies, unitKit, Fight.slowTold) or nil
            if Fight.slowNote then
                log("%s", Fight.slowNote)
                appendLog("  " .. Fight.slowNote)
                Fight.slowNote = nil
            end
            return nil
        end
        choice = finishChoice(uid, pick, "cure slow " .. (focus.name or ""), { focus.id }, aoeOf(pick))
        if not choice then return nil end
        Fight.claim.heal[focus.id] = true
        choice.slow = {
            id = focus.id, key = pickKey, round = Fight.rounds or 0,
            name = pick.name, caster = uid, cost = pick.cost or 0, mp = mpNow,
        }
        return choice
    end
    local cured = curePass(true)
    if cured then return cured end

    local recoverAt, smallDanger = 0.50, false
    if Health.recoverAt then
        local rows = {}
        for _, u in ipairs(w.enemies) do
            local card = mobOf(u)
            local _, _, empty = gaugeOfEnemy(u)
            rows[#rows + 1] = {
                danger = (card and card.danger and card.danger[1]) and true or false,
                empty = empty and true or false,
                broken = u.broken and true or false,
                gauge = card and tonumber(card.gauge) or 0,
            }
        end
        recoverAt, smallDanger = Health.recoverAt(w.boss and true or false, rows)
    else
        for _, u in ipairs(w.enemies) do
            local card = mobOf(u)
            if card and card.danger and card.danger[1] then
                local _, _, empty = gaugeOfEnemy(u)
                if not empty and not u.broken then recoverAt = 0.65 end
            end
        end
    end
    if (not Fight.recoverTold) and ((recoverAt > 0.50) or smallDanger) then
        Fight.recoverTold = true
        if recoverAt > 0.50 then
            log("recover line 65%")
        else
            log("recover line 50%, danger gauge is small")
        end
    end
    local function underMark()
        local n, who = 0, nil
        for _, a in ipairs(w.allies) do
            if not a.dead and (a.hp or 1) < recoverAt then
                Fight.underLine = true
                if (a.acts ~= false) and (not Fight.claim.heal[a.id]) then
                    n = n + 1
                    local bar = next((Fight.stance and Fight.stance[a.id]) or {}) ~= nil
                    local whoBar = who and (next((Fight.stance and Fight.stance[who.id]) or {}) ~= nil)
                    if (not who) or (whoBar and not bar)
                        or ((whoBar == bar) and ((a.hp or 1) < (who.hp or 1))) then who = a end
                end
            end
        end
        return n, who
    end
    Fight.underLine = false
    local halfN, halfWho = underMark()
    local opening = (Fight.rounds or 0) == 0
    local recoverGate = opening or (recoverAt > 0.50) or ((band() == "high")
        and (Fight.afterBonus or ((style == "defensive") and (halfN >= 2))))
    if halfWho and phase ~= PHASE_BONUS and not deferHeal() and recoverGate then
        local choice = healNow(halfWho, opening and "opening" or "recover",
            recoverAt > 0.50 and recoverAt or 0.50)
        if choice then return choice end
    end
    local softer = curePass(false)
    if softer then return softer end

    -- A stance that lifts the actor and blocks white-magic heals on them.
    -- It comes off before the draws when the actor is under the recover line.
    if (phase == 0) and Kits.pickStance then
        local spellHeal = false
        for _, a in ipairs(w.allies) do
            if (not a.dead) and (a.acts ~= false) and (not heldOut(a)) then
                local kit = unitKit(a.id)
                local mp = (a.id == uid) and (w.mp or 0) or (stat(a.id, PARAM.MP, false) or 0)
                for _, s in ipairs((kit and kit.spells) or {}) do
                    if (s.kind == "heal") and (s.attr == ATTR.MAGIC) and ((s.cost or 0) <= mp) then spellHeal = true end
                end
            end
        end
        local own = unitKit(uid)
        Fight.stanceEnded = Fight.stanceEnded or {}
        local picked = Kits.pickStance(skills, {
            allies = w.allies, selfId = uid, on = (Fight.stance or {})[uid],
            hard = hardField and (not allyCritical()) and (not dead),
            recoverAt = recoverAt, spellHeal = spellHeal,
            round = Fight.rounds or 0, endedRound = Fight.stanceEnded[uid],
            mp = w.mp or 0, pay = (band() ~= "low"),
            keep = (own and ((own.healScore or 0) >= 50)) and (own.healCost or 0) or 0,
        })
        if picked then
            local choice = finishChoice(uid, picked.skill, picked.why, { uid }, false)
            if choice then return choice end
        end
    end

    -- Provoke, Cover, Multi-Cover: after the care steps, before setup and
    -- the chip. Someone critical or a fall still down comes first.
    if (phase == 0) and Kits.pickDraw and (not allyCritical()) and (not dead) then
        local danger = false
        for _, u in ipairs(w.enemies) do
            local card = mobOf(u)
            local _, _, empty = gaugeOfEnemy(u)
            if card and card.danger and card.danger[1] and (not empty) and (not u.broken) then danger = true end
        end
        local own = unitKit(uid)
        -- The healer to protect is the best heal kit among the others. The
        -- actor holds back only when its own kit heals better than all of
        -- them. Equal kits mean either one can pull the attacks.
        local ownScore = (own and own.healScore) or 0
        local healer, bestScore = nil, -1
        for _, a in ipairs(w.allies) do
            if (a.id ~= uid) and (not a.dead) and (a.acts ~= false) and (not heldOut(a)) then
                local kit = unitKit(a.id)
                local score = (kit and kit.healScore) or 0
                if (score >= 50) and (score > bestScore) then healer, bestScore = a, score end
            end
        end
        local healerId = healer and healer.id or nil
        if (ownScore >= 50) and (ownScore > bestScore) then healerId = uid end
        Fight.drawSeen = Fight.drawSeen or {}
        local picked = Kits.pickDraw(skills, {
            allies = w.allies, selfId = uid, healerId = healerId, seen = Fight.drawSeen,
            recoverAt = recoverAt, danger = danger,
            mp = w.mp or 0, pay = (band() ~= "low"),
            keep = (own and ((own.healScore or 0) >= 50)) and (own.healCost or 0) or 0,
            claim = Fight.claim.kit, sent = Fight.kitOn, actions = #(Fight.actions or {}),
            round = Fight.rounds or 0, drawRound = Fight.drawRound,
        })
        if picked then
            local ids, isAll = { uid }, false
            if picked.mode == "ally" and picked.target then
                ids = { picked.target.id }
            elseif picked.mode == "party" then
                ids = {}
                for _, a in ipairs(w.allies) do
                    if not a.dead then ids[#ids + 1] = a.id end
                end
                isAll = true
            end
            local choice = finishChoice(uid, picked.skill, picked.why, ids, isAll)
            if choice then
                choice.kitKey = picked.key
                Fight.claim.kit.draw = true
                Fight.drawRound = Fight.drawRound or {}
                Fight.drawRound[picked.key] = Fight.rounds or 0
                return choice
            end
        end
    end

    -- Haste: a slowed ally first, then on a hard field with the bar above
    -- half, the healer and the strongest damage dealer. Same gate as above.
    if (phase == 0) and Kits.pickHaste and (not allyCritical()) and (not dead) then
        local healer = Health.mainHealer and Health.mainHealer(w.allies, unitKit) or nil
        local dealer, dealt = nil, -1
        for _, a in ipairs(w.allies) do
            if (not a.dead) and (a.acts ~= false) then
                local kit = unitKit(a.id)
                for _, s in ipairs((kit and kit.spells) or {}) do
                    if isHit(s, false) then
                        local pow = offenseOf(s)
                        if pow and pow > dealt then dealer, dealt = a, pow end
                    end
                end
            end
        end
        local own = unitKit(uid)
        local picked = Kits.pickHaste(skills, {
            allies = w.allies, selfId = uid,
            healerId = healer and healer.id or nil, dealerId = dealer and dealer.id or nil,
            hard = hardField, rich = (band() == "high"),
            mp = w.mp or 0, pay = (band() ~= "low"),
            keep = (own and ((own.healScore or 0) >= 50)) and (own.healCost or 0) or 0,
            claim = Fight.claim.kit, sent = Fight.kitOn,
        })
        if picked then
            local ids, isAll = {}, false
            if picked.mode == "party" then
                for _, a in ipairs(w.allies) do
                    if not a.dead then ids[#ids + 1] = a.id end
                end
                isAll = true
            else
                ids = { picked.target.id }
            end
            local choice = finishChoice(uid, picked.skill, picked.why, ids, isAll)
            if choice then
                Fight.claim.kit.haste = true
                Fight.kitOn = Fight.kitOn or {}
                for _, k in ipairs(picked.keys or {}) do
                    Fight.kitOn["haste:" .. tostring(k.ally.id)] = #(Fight.actions or {})
                end
                return choice
            end
        end
    end

    local foeRows, seenNoted, matterKnown, debuffOwedFlag = nil, false, nil, nil
    local function hitWouldFinish(enemy, remain)
        for _, a in ipairs(w.allies) do
            if (not a.dead) and (a.acts ~= false) and not heldOut(a) then
                local mp = (a.id == uid) and (w.mp or 0) or (stat(a.id, PARAM.MP, false) or 0)
                local spells = skills
                if a.id ~= uid then
                    local kit = unitKit(a.id)
                    spells = (kit and kit.spells) or {}
                end
                for _, s in ipairs(spells) do
                    if isHit(s, false) and ((s.cost or 0) <= mp) then
                        local gained = staggerOf(s, enemy)
                        if (gained > 0) and (gained >= remain) then return true end
                    end
                end
            end
        end
        return false
    end
    local function debuffFoes()
        if foeRows then return foeRows end
        local rows, preferI, preferGauge, preferDanger = {}, nil, -1, false
        for _, u in ipairs(w.enemies) do
            local gauge, remain, empty = gaugeOfEnemy(u)
            local card = mobOf(u)
            local danger = (card and card.danger and card.danger[1]) and true or false
            local about = false
            if empty then
                about = true
            elseif remain > 0 then
                about = hitWouldFinish(u, remain)
            end
            rows[#rows + 1] = {
                id = u.id,
                name = u.name,
                danger = danger,
                gauge = gauge,
                counter = card and card.counter or nil,
                ail = card and card.ail or nil,
                statuses = statuses(u.id),
                empty = empty and true or false,
                broken = u.broken and true or false,
                about = about,
                prefer = false,
            }
            local row = rows[#rows]
            if (not row.empty) and (not row.broken) then
                local take = (not preferI) or (danger and (not preferDanger))
                    or ((danger == preferDanger) and (gauge > preferGauge))
                if take then preferI, preferGauge, preferDanger = #rows, gauge, danger end
            end
        end
        if preferI then rows[preferI].prefer = true end
        foeRows = rows
        return rows
    end
    local function noteDebuffSeen(foes)
        if seenNoted or (not Debuffs.STATUS) then return end
        seenNoted = true
        Fight.debuffSeen = Fight.debuffSeen or {}
        for _, foe in ipairs(foes or {}) do
            local set = foe.statuses
            if set then
                for effect, id in pairs(Debuffs.STATUS) do
                    if set[id] then
                        Fight.debuffSeen[foe.id] = Fight.debuffSeen[foe.id] or {}
                        Fight.debuffSeen[foe.id][effect] = true
                    end
                end
            end
        end
    end
    local function payableDebuffs(actorId, mp)
        local spells = skills
        if actorId ~= uid then
            local kit = unitKit(actorId)
            spells = (kit and kit.spells) or {}
        end
        local out = {}
        for _, s in ipairs(spells) do
            if ((useOf(s) == "debuff") or (s.kind == "debuff")) and ((s.cost or 0) <= mp) then
                out[#out + 1] = s
            end
        end
        return out
    end
    local function partyMatter()
        if matterKnown ~= nil then return matterKnown end
        matterKnown = false
        if not (Debuffs.matter and Debuffs.effectOf) then return false end
        for _, a in ipairs(w.allies) do
            if (not a.dead) and (a.acts ~= false) then
                local spells = skills
                if a.id ~= uid then
                    local kit = unitKit(a.id)
                    spells = (kit and kit.spells) or {}
                end
                for _, s in ipairs(spells) do
                    if ((useOf(s) == "debuff") or (s.kind == "debuff")) and Debuffs.matter(Debuffs.effectOf(s)) then
                        matterKnown = true
                        return true
                    end
                end
            end
        end
        return false
    end
    local function debuffOwed()
        if debuffOwedFlag ~= nil then return debuffOwedFlag end
        debuffOwedFlag = false
        if Fight.chipped or (phase ~= 0) or (not hardField) or (style == "aggressive") then return false end
        if Fight.fell and (#Fight.fell > 0) then return false end
        if allyCritical() then return false end
        for _, a in ipairs(w.allies) do
            if a.dead then return false end
        end
        if not Debuffs.choose then return false end
        local foes = debuffFoes()
        noteDebuffSeen(foes)
        local fallback = not partyMatter()
        for _, a in ipairs(w.allies) do
            if (not a.dead) and (a.acts ~= false) and not heldOut(a) then
                local mp = (a.id == uid) and (w.mp or 0) or (stat(a.id, PARAM.MP, false) or 0)
                local picks = payableDebuffs(a.id, mp)
                if Debuffs.choose(picks, foes, Fight.debuffOn, Fight.debuffSeen, fallback) then
                    debuffOwedFlag = true
                    return true
                end
            end
        end
        return false
    end
    -- The guard follows the danger's kind of damage: Shell for magic,
    -- Protect for physical. With no kind on the card, one guard of any kind.
    -- Each kind goes out once a fight. The sim found that casting it again
    -- as it wore off cost more turns than it saved.
    Fight.guardOn = Fight.guardOn or {}
    local function guardKind(s) return (s.known and s.known.guards) or "any" end
    local function guardFits(s)
        if useOf(s) ~= "guardbuff" then return false end
        local k = guardKind(s)
        if Fight.guardOn[k] then return false end
        local want, known = {}, false
        for _, u in ipairs(w.enemies) do
            local card = mobOf(u)
            if card and card.danger and card.danger[1] and card.hits then
                want[card.hits] = true
                known = true
            end
        end
        if (not known) or (k == "any") then return next(Fight.guardOn) == nil end
        return want[k] and true or false
    end
    local function markGuard(s)
        Fight.guardOn[guardKind(s)] = { map = s.friendStatus or {}, seen = false }
    end
    local function guardOwed()
        if phase ~= 0 or not hardField or style == "aggressive" then return false end
        if Fight.fell and #Fight.fell > 0 then return false end
        if allyCritical() then return false end
        for _, a in ipairs(w.allies) do
            if a.dead then return false end
        end
        for _, a in ipairs(w.allies) do
            if not a.dead and a.acts ~= false and not heldOut(a) then
                local kit = unitKit(a.id)
                local mp = stat(a.id, PARAM.MP, false) or 0
                if kit then
                    for _, s in ipairs(kit.spells or {}) do
                        if guardFits(s) and (s.cost or 0) <= mp then
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
            if not a.dead and a.acts ~= false and not heldOut(a) then
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
    -- In a boss fight, an ally who carries a two-gauge damage Limit that
    -- lands on the field saves the gauges for it. A one-gauge row from that
    -- ally waits, unless every living enemy is under a quarter of its HP.
    local lbSaveMemo = {}
    local function lbSaved(aid, s)
        if not w.boss then return false end
        if (tonumber(s and s.lbCost) or tonumber(s and s.known and s.known.gauges) or 1) >= 2 then return false end
        local late = #w.enemies > 0
        for _, u in ipairs(w.enemies) do
            if (u.hp or 1) >= 0.25 then late = false end
        end
        if late then return false end
        if lbSaveMemo[aid] ~= nil then return lbSaveMemo[aid] end
        local saved = false
        for _, id in ipairs(equippedIds(aid)) do
            local row = skillOf(id)
            local fact = row and (row.attr == ATTR.LB) and Limits.lookup and Limits.lookup(row.name)
            if fact and (fact.use == "lb-cash") and ((tonumber(fact.gauges) or 1) >= 2) then
                local probe = { known = fact, name = row.name }
                local any, all = false, true
                for _, u in ipairs(w.enemies) do
                    if elementFactor(probe, u) > 0 then any = true else all = false end
                end
                if (fact.area and all) or ((not fact.area) and any) then saved = true end
            end
        end
        lbSaveMemo[aid] = saved
        return saved
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
            if not a.dead and a.acts ~= false and not heldOut(a) then
                local mp = (a.id == uid) and (w.mp or 0) or (stat(a.id, PARAM.MP, false) or 0)
                local ids = equippedIds(a.id)
                for _, id in ipairs(ids) do
                    local s = tagSkill(a.id, id, false)
                    if s and useOf(s) == "lb-setup" and (s.cost or 0) <= mp and not lbSaved(a.id, s) then
                        local keeps = partyWeak(a.id, s.cost or 0) or not partyWeak(nil, 0)
                        if keeps then lbOwedFlag = true return true end
                    end
                end
            end
        end
        return false
    end
    -- The cash belongs to the break the ledger just marked. A body the
    -- game still calls broken from an older wave does not take that hit.
    local function burstTargets()
        local held = {}
        local mark = Fight.brokeOn or {}
        for _, u in ipairs(w.enemies) do
            if mark[u.id] or Fight.down[u.id] then
                held[#held + 1] = u
            end
        end
        if #held == 0 then
            for _, u in ipairs(w.enemies) do
                if u.broken then held[#held + 1] = u end
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
        -- The MP band keeps a free hit in reserve for the weakness. When no
        -- free hit can land on a body, a paid hit that lands is allowed.
        local freeLands = {}
        local function freeOn(u)
            if freeLands[u.id] == nil then
                freeLands[u.id] = false
                for _, x in ipairs(skills) do
                    if isHit(x, false) and ((x.cost or 0) <= 0) and (elementFactor(x, u) > 0) then
                        freeLands[u.id] = true
                    end
                end
            end
            return freeLands[u.id]
        end
        local function considerSkill(s, targets, spread)
            if not pay(s) then return end
            local spendLb = (useOf(s) == "lb-cash") or (s.attr == ATTR.LB)
            if spendLb and (not hardField) then return end
            if spendLb and lbSaved(uid, s) then return end
            -- An area Limit hits every living enemy. A nulled element stays off.
            if spendLb and aoeOf(s) and s.known and s.known.element and (#w.enemies > 0) then
                local blocked = false
                for _, u in ipairs(w.enemies) do
                    if elementFactor(s, u) <= 0 then blocked = true end
                end
                if blocked then
                    Fight.limitSkip = Fight.limitSkip or {}
                    local key = (s.name or "limit") .. ":" .. s.known.element
                    if not Fight.limitSkip[key] then
                        Fight.limitSkip[key] = true
                        local line = "limit " .. (s.name or "limit") .. " skipped, " .. s.known.element .. " null"
                        log("%s", line)
                        appendLog("  " .. line)
                    end
                    return
                end
            end
            -- A paid chip waits for the setup, unless no free hit can land on these targets.
            if (not cashing) and (debuffOwed() or guardOwed() or lbOwed()) and ((s.cost or 0) > 0) then
                local free = false
                for _, u in ipairs(targets) do
                    if freeOn(u) then free = true end
                end
                if free then return end
            end
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
                    if (not allowed) and ((s.cost or 0) > 0) and (not freeOn(u)) then allowed = true end
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
            -- The matching element wins when two bursts are ready. A row with no
            -- element still gets the cash bonus. The heavier gauge wins a tie.
            if cashing and hardField and spendLb then
                score = score + 100000
                if weak then score = score + 20000 end
                score = score + ((s.lbCost or 1) * 100)
            end
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
        -- A bonus opens the next break-time Limit.
        if Fight.claim then Fight.claim.lbBreak = false end
        -- An add broke and the large gauge is still open: a weakness the actor
        -- can pay goes on the large gauge. The add has already lost its turn.
        if (mode == "adds") and bossU and (not bossU.broken) then
            for _, s in ipairs(skills) do
                if isHit(s, false) and pay(s) and (elementFactor(s, bossU) >= 3) then
                    local hit = castDamage({ bossU }, false, "bonus on")
                    if hit then return hit end
                    break
                end
            end
        end
        return castDamage(burstTargets(), true, "burst")
    end
    if #open == 0 and #brokenPool > 0 then
        if phase == PHASE_BONUS then
            return castDamage(brokenPool, true, "burst")
        end
        return castDamage(brokenPool, false, "fill")
    end

    local function esperParty()
        local party = 0
        for _ in pairs(Fight.seenAlly or {}) do party = party + 1 end
        if party < 1 then
            for _, a in ipairs(w.allies) do
                if not a.dead then party = party + 1 end
            end
        end
        if party < 1 then party = 2 end
        return party
    end
    local function esperStill()
        local mark = Fight.esperOut
        if not mark or not Espers.stillOut then return false end
        local up = Espers.stillOut(mark.at or 0, #(Fight.actions or {}), mark.turns or 3, esperParty())
        if (not up) and (not mark.told) then
            mark.told = true
            local line = "esper " .. (mark.name or "summon") .. " finished"
            log("%s", line)
            appendLog("  " .. line)
            Fight.claim.esper = false
            Fight.summoned = false
        end
        return up
    end
    local weaknessFits
    local function summonChoice(mode)
        if not Espers.best then return nil end
        if esperStill() then return nil end
        if Fight.claim.esper then return nil end
        local list = (#pool > 0) and pool or open
        if #list == 0 then list = w.enemies end
        if #list == 0 then return nil end
        local preferId, preferGauge, dangerGauge = nil, -1, -1
        local near, long = false, false
        for _, u in ipairs(list) do
            local card = mobOf(u)
            local gauge, remain, empty = gaugeOfEnemy(u)
            local ratio = 1
            if gauge > 0 then ratio = remain / gauge end
            if not empty then
                if gauge > preferGauge then
                    preferId, preferGauge = u.id, gauge
                end
                if card and card.danger and card.danger[1] and (gauge > dangerGauge) then
                    dangerGauge = gauge
                    preferId = u.id
                end
                if ratio <= 0.40 then near = true end
                if ratio > 0.40 then long = true end
            end
        end
        if (mode == "break") and (not near) then return nil end
        if (mode == "again") and (not Fight.esperOut) then return nil end
        if (mode == "later") and Fight.esperOut then return nil end
        if ((mode == "again") or (mode == "later")) and ((not long) or (band() ~= "high")) then return nil end
        if (mode == "break") and (band() ~= "high") and (not weaknessFits(0)) then return nil end
        local hits = {}
        -- The signature hits every living enemy, not only the current plan.
        local field = (#w.enemies > 0) and w.enemies or list
        for _, u in ipairs(field) do
            local gauge, remain = gaugeOfEnemy(u)
            local ratio = 1
            if gauge > 0 then ratio = remain / gauge end
            hits[#hits + 1] = { id = u.id, prefer = (u.id == preferId), ratio = ratio, foe = u }
        end
        local cands = {}
        for _, s in ipairs(skills) do
            if (s.attr == ATTR.SUMMON) and pay(s) and (useOf(s) ~= "skip") then
                local fact = (Espers.lookup and Espers.lookup(s.name)) or nil
                if not fact then fact = { turns = 3, role = "damage", use = "summon" } end
                local scored, blocked = {}, false
                for _, h in ipairs(hits) do
                    local factor = elementFactor({ known = fact, name = s.name }, h.foe)
                    if fact.element and (factor <= 0) then blocked = true end
                    scored[#scored + 1] = { factor = factor, prefer = h.prefer, ratio = h.ratio }
                end
                if blocked and fact.element then
                    Fight.esperSkip = Fight.esperSkip or {}
                    local key = (s.name or "summon") .. ":" .. fact.element
                    if not Fight.esperSkip[key] then
                        Fight.esperSkip[key] = true
                        local line = "esper " .. (s.name or "summon") .. " skipped, " .. fact.element .. " null"
                        log("%s", line)
                        appendLog("  " .. line)
                    end
                end
                local care = not blocked
                if care then
                    local kit = unitKit(uid)
                    local need = 0
                    if kit and (kit.healScore >= 50) then need = kit.healCost or 0 end
                    if (need > 0) and (((w.mp or 0) - (s.cost or 0)) < need) then care = false end
                end
                if care and (mode == "setup") then
                    local room = weaknessFits(s.cost or 0) or (#w.enemies >= 3) or (not weaknessFits(0))
                    if not room then care = false end
                end
                if care then
                    cands[#cands + 1] = { ref = s, fact = fact, hits = scored }
                end
            end
        end
        if #cands == 0 then return nil end
        if not Fight.esperTold then
            Fight.esperTold = true
            local names = {}
            for _, c in ipairs(cands) do
                local el = c.fact.element or c.fact.role or "summon"
                names[#names + 1] = (c.ref.name or "summon") .. " " .. el
            end
            log("esper equipped: %s", table.concat(names, ", "))
        end
        local picked = Espers.best(cands, mode)
        if not picked then return nil end
        local s, fact = picked.ref, picked.fact
        local foe = nil
        for _, h in ipairs(hits) do
            if h.prefer then foe = h.foe end
        end
        if not foe then foe = list[1] end
        local spread = aoeOf(s)
        local why = "setup esper"
        if mode == "break" then why = "esper before the break" end
        if mode == "again" then why = "esper again" end
        if mode == "later" then why = "esper" end
        why = why .. " " .. (s.name or "summon")
        if fact.element then
            why = why .. " " .. fact.element
        elseif fact.role == "guard" then
            why = why .. " support"
        end
        local choice = finishChoice(uid, s, why, spread and idsOf(list) or { foe.id }, spread)
        if choice then
            choice.esperTurns = fact.turns or 3
            Fight.claim.esper = true
        end
        return choice
    end
    weaknessFits = function(extra)
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
            if useOf(s) ~= "skip" and pred(s) and pay(s) then return s end
        end
        return nil
    end

    -- One setup Limit per fight. A party row lands on the allies. A stagger
    -- row lands on the danger body, or the largest gauge still open.
    local function setupLimit()
        if Fight.claim.lb then return nil end
        local s = nil
        local function spendable(x) return pay(x) and not lbSaved(uid, x) end
        if Limits.bestSetup then s = Limits.bestSetup(skills, spendable) end
        if not s then s = firstSkill(function(x) return useOf(x) == "lb-setup" and not lbSaved(uid, x) end) end
        if not s then return nil end
        if not (partyWeak(uid, s.cost or 0) or (not partyWeak(nil, 0))) then return nil end
        if s.known and s.known.party then
            local ids = {}
            for _, a in ipairs(w.allies) do
                if not a.dead then ids[#ids + 1] = a.id end
            end
            if #ids == 0 then return nil end
            local choice = finishChoice(uid, s, "setup lb " .. (s.name or "limit") .. " party", ids, true)
            if choice then Fight.claim.lb = true end
            return choice
        end
        local best, bestGauge, danger, dangerGauge = nil, -1, nil, -1
        local list = ((#open > 0) and open) or w.enemies
        for _, u in ipairs(list) do
            local gauge, _, empty = gaugeOfEnemy(u)
            if not empty then
                if gauge > bestGauge then best, bestGauge = u, gauge end
                local card = mobOf(u)
                if card and card.danger and card.danger[1] and (gauge > dangerGauge) then
                    danger, dangerGauge = u, gauge
                end
            end
        end
        local foe = danger or best or list[1]
        if not foe then return nil end
        local choice = finishChoice(uid, s, "setup lb " .. (s.name or "limit") .. " " .. foe.name, { foe.id }, false)
        if choice then Fight.claim.lb = true end
        return choice
    end

    local function castDebuff(refreshOnly)
        if (phase ~= 0) or (not hardField) or (style == "aggressive") or (not Debuffs.choose) then
            return nil
        end
        if allyCritical() then return nil end
        for _, a in ipairs(w.allies) do
            if a.dead then return nil end
        end
        local foes = debuffFoes()
        noteDebuffSeen(foes)
        local fallback = not partyMatter()
        local picks = payableDebuffs(uid, w.mp or 0)
        local s, foe, why = Debuffs.choose(picks, foes, Fight.debuffOn, Fight.debuffSeen, fallback)
        if s and foe and ((not refreshOnly) or (why == "refresh")) then
            local effect = Debuffs.effectOf(s) or "debuff"
            local spread = aoeOf(s)
            local ids = { foe.id }
            if spread then
                ids = {}
                for _, row in ipairs(foes) do
                    if (not row.empty) and (not row.broken) then ids[#ids + 1] = row.id end
                end
                if #ids == 0 then ids[1] = foe.id end
            end
            local choice = finishChoice(uid, s, why .. " debuff " .. effect .. " " .. foe.name, ids, spread)
            if choice then
                for _, id in ipairs(ids) do markDebuff(id, effect) end
                return choice
            end
        elseif (not refreshOnly) and (not s) and Debuffs.immuneEffect then
            local skipped = Debuffs.immuneEffect(picks, foes, fallback)
            if skipped and (not Fight.debuffTold[skipped]) then
                Fight.debuffTold[skipped] = true
                local line = "debuff " .. skipped .. " skipped, immune"
                log("%s", line)
                appendLog("  " .. line)
            end
        end
        return nil
    end

    -- A stalemate is five rounds of the party's hits on enemies in which
    -- no enemy loses HP and no bonus phase comes. Turns spent on setup, heals, or items
    -- do not count. Then the party escapes, when the game allows it. A Pot
    -- fight is the player's. A boss fight cannot be fled. An escape that went
    -- out, by the planner or the player, with the fight still going, was
    -- refused. After two refused escapes this fight is not fled again.
    if phase == 0 then
        local tries = Fight.escapeSent or 0
        if tries > (Fight.escapeTold or 0) then
            Fight.escapeTold = tries
            if tries >= 2 then Fight.noEscape = true end
            local line = string.format("escape refused (%d of 2), the fight goes on", tries)
            log("%s", line)
            appendLog("  " .. line)
        end
        Fight.foeLow = Fight.foeLow or {}
        local moved, alive = false, {}
        for _, u in ipairs(w.enemies) do
            alive[u.id] = true
            local low = Fight.foeLow[u.id]
            if low == nil then
                -- A first reading starts the count. Hits before it do not count.
                Fight.foeLow[u.id] = u.hp or 1
                moved = true
            elseif (u.hp or 1) < (low - 0.001) then
                Fight.foeLow[u.id] = u.hp or 1
                moved = true
            end
        end
        for id in pairs(Fight.foeLow) do
            if not alive[id] then
                Fight.foeLow[id] = nil
                moved = true
            end
        end
        -- A bonus phase is the game's word that a gauge broke. The
        -- planner's own break marks are guesses and do not count.
        if Fight.afterBonus then moved = true end
        if moved then Fight.hitsSince = 0 end
        local party = 0
        for _ in pairs(Fight.seenAlly or {}) do party = party + 1 end
        if party < 1 then party = 1 end
        local fleeable = (not w.boss) and (not Fight.noEscape)
        if ((Fight.hitsSince or 0) >= (party * 5)) and (#w.enemies > 0) and (not fleeable)
            and (not Fight.stalemateTold) and (not potFight(w)) then
            Fight.stalemateTold = true
            local line = "stalemate: five rounds of hits and no enemy has lost HP, no escape from this fight"
            log("%s", line)
            appendLog("  " .. line)
        end
        if fleeable and ((Fight.hitsSince or 0) >= (party * 5)) and (#w.enemies > 0) and (not potFight(w)) then
            for _, id in ipairs(equippedIds(uid)) do
                local row = skillOf(id)
                if row and (row.attr == ATTR.ESCAPE) and (activation(uid, id) ~= false) and commandEnabled(uid, id) then
                    if not Fight.stalemateTold then
                        Fight.stalemateTold = true
                        local line = "stalemate: five rounds of hits and no enemy has lost HP"
                        log("%s", line)
                        appendLog("  " .. line)
                    end
                    return {
                        id = row.id, name = row.name, score = 1, cost = 0, kind = "escape",
                        reason = "escape, stalemate", targets = { uid }, isAll = false,
                        attr = ATTR.ESCAPE, isItem = false,
                    }
                end
            end
        end
    end

    local alreadyFell = Fight.fell and #Fight.fell > 0
    -- A paid chip closes the opener and the other setup. It does not close Libra.
    if phase == 0 and not alreadyFell and not allyCritical() and not dead then
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
    end
    if not Fight.chipped and phase == 0 and not alreadyFell and not allyCritical() and not dead then
        if not Fight.claim.hone[uid] then
            local s = firstSkill(function(x) return useOf(x) == "opener" end)
            if s and weaknessFits(s.cost or 0) then
                local choice = finishChoice(uid, s, "setup opener", { uid }, false)
                if choice then Fight.claim.hone[uid] = true return choice end
            end
        end
        local bossFight = hardField
        if bossFight and style ~= "aggressive" then
            local s = firstSkill(guardFits)
            if s then
                local spread = aoeOf(s)
                local choice = finishChoice(uid, s, "setup guard", spread and idsOf(w.allies) or { uid }, spread)
                if choice then markGuard(s) return choice end
            end
        end
        if bossFight and (style ~= "aggressive") then
            local choice = castDebuff(false)
            if choice then return choice end
        end
        if bossFight and not Fight.claim.lb then
            local choice = setupLimit()
            if choice then return choice end
        end
        if bossFight and style ~= "aggressive" then
            local choice = summonChoice("setup")
            if choice then return choice end
        end
    end
    if (phase == 0) and hardField and (style ~= "aggressive") and (not allyCritical()) then
        local someoneDown = false
        for _, a in ipairs(w.allies) do
            if a.dead then someoneDown = true end
        end
        if not someoneDown then
            local choice = summonChoice("break")
            if (not choice) and Fight.esperOut then choice = summonChoice("again") end
            if (not choice) and (not Fight.esperOut) then choice = summonChoice("later") end
            if choice then return choice end
        end
    end
    -- A barrier Limit for the party goes up on a hard field. It is held while
    -- its status shows and cast again once that status has shown and gone,
    -- or two rounds after a cast whose status never showed. A row that lists
    -- no status goes out once a fight.
    local function barrierLimit()
        local veil = Fight.veil
        if veil then
            local up = false
            for _, a in ipairs(w.allies) do
                if not a.dead then
                    local set = statuses(a.id)
                    for sid in pairs(veil.map or {}) do
                        if set[sid] then up = true end
                    end
                end
            end
            if up then veil.seen = true return nil end
            local stale = ((Fight.rounds or 0) - (veil.round or 0)) >= 2
            if (not veil.seen) and (not stale) then return nil end
            if not next(veil.map or {}) then return nil end
            Fight.veil = nil
        end
        local s = firstSkill(function(x) return useOf(x) == "lb-guard" and pay(x) end)
        if not s then return nil end
        local ids = {}
        for _, a in ipairs(w.allies) do
            if not a.dead then ids[#ids + 1] = a.id end
        end
        if #ids == 0 then return nil end
        return finishChoice(uid, s, "barrier lb " .. (s.name or "limit") .. " party", ids, true)
    end
    -- A Limit that lifts the party's next actions (gauge fill, or every
    -- action twice) goes out as the largest open gauge nears its break:
    -- under 40% left. An add's break does not count. Once for each break;
    -- the bonus phase opens the next one. A row whose status still shows on
    -- every living ally is not cast again.
    local function breakLimit()
        if Fight.claim.lbBreak then return nil end
        local big, bigGauge, bigRemain = nil, -1, 0
        for _, u in ipairs(open) do
            local gauge, remain, empty = gaugeOfEnemy(u)
            if (not empty) and (gauge > bigGauge) then big, bigGauge, bigRemain = u, gauge, remain end
        end
        if (not big) or (bigGauge <= 0) or ((bigRemain / bigGauge) > 0.40) then return nil end
        local function stillUp(x)
            if not next(x.friendStatus or {}) then return false end
            local any = false
            for _, a in ipairs(w.allies) do
                if not a.dead then
                    any = true
                    local set, on = statuses(a.id), false
                    for sid in pairs(x.friendStatus) do
                        if set[sid] then on = true end
                    end
                    if not on then return false end
                end
            end
            return any
        end
        local best, bestG = nil, -1
        for _, x in ipairs(skills) do
            if (useOf(x) == "lb-break") and pay(x) and (not stillUp(x)) then
                local g = tonumber(x.lbCost) or 1
                if g > bestG then best, bestG = x, g end
            end
        end
        if not best then return nil end
        local ids = {}
        for _, a in ipairs(w.allies) do
            if not a.dead then ids[#ids + 1] = a.id end
        end
        if #ids == 0 then return nil end
        local choice = finishChoice(uid, best, "break lb " .. (best.name or "limit") .. " party", ids, true)
        if choice then Fight.claim.lbBreak = true end
        return choice
    end
    if (phase == 0) and hardField and (not dead) then
        local choice = barrierLimit()
        if choice then return choice end
    end
    if (phase == 0) and hardField and (not dead) and (not allyCritical()) then
        local choice = breakLimit()
        if choice then return choice end
    end
    -- The gauge may fill after the first chip. That one setup still goes
    -- out then. It does not go out after a fall, or while someone is critical.
    if phase == 0 and hardField and not Fight.claim.lb
        and not alreadyFell and not allyCritical() and not dead then
        local choice = setupLimit()
        if choice then return choice end
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
    -- One Ether on the actor's own turn: a heal they hold no longer fits, or
    -- the bar is low and a known weakness no longer fits.
    -- Dire need in a boss fight lifts the one-Ether-per-round limit.
    if not Fight.claim.ether[uid] and ((not Fight.claim.etherRound) or (Health.direNeed and Health.direNeed(w))) then
        local list = #pool > 0 and pool or open
        local holds, fits = false, false
        for _, s in ipairs(skills) do
            if realCure(s) then
                holds = true
                if pay(s) then fits = true end
            end
        end
        local healGone = holds and not fits
        -- Nothing payable lands on the pool, and a hit on the bar would.
        local paidLands, unpaidLands = false, false
        for _, x in ipairs(skills) do
            if isHit(x, false) then
                for _, u in ipairs(list) do
                    if elementFactor(x, u) > 0 then
                        if pay(x) then paidLands = true else unpaidLands = true end
                    end
                end
            end
        end
        local hitGone = (not paidLands) and unpaidLands
        if healGone or hitGone or ((band() == "low") and unpaidWeakness(list)) then
            local ether = pickRecoveryItem(uid, w, "mp")
            if ether then
                ether.reason = (healGone and "ether so a heal fits") or (hitGone and "ether so a hit lands") or "ether so the weakness fits"
                Fight.claim.ether[uid] = true
                Fight.claim.etherRound = true
                return ether
            end
        end
    end

    -- Once the fight is underway, a support turn is followed by a hit when
    -- the actor has one that lands, so a kit or a refresh does not crowd
    -- out the damage.
    local function supportRested()
        if not Fight.chipped then return false end
        Fight.supportRun = Fight.supportRun or {}
        if (Fight.supportRun[uid] or 0) < 1 then return false end
        for _, x in ipairs(skills) do
            if isHit(x, false) and pay(x) then
                for _, u in ipairs((#pool > 0) and pool or open) do
                    if elementFactor(x, u) > 0 then return true end
                end
            end
        end
        return false
    end
    if Fight.chipped and (phase == 0) and (not allyCritical()) and (not dead) and (not supportRested()) then
        local again = castDebuff(true)
        if again then return again end
    end

    local function castKit()
        if not Kits.pick then return nil end
        if phase ~= 0 then return nil end
        local keep, healer = 0, false
        local uk = unitKit(uid)
        if uk and ((uk.healScore or 0) >= 50) then
            healer = true
            keep = uk.healCost or 0
        end
        -- Every open body, not just the pool: a mark belongs on the largest
        -- gauge, where stagger is the bottleneck, even while the adds go first.
        local list = (#open > 0) and open or pool
        if #list == 0 then list = w.enemies end
        local foes = {}
        for _, u in ipairs(list) do
            local card = mobOf(u)
            local bare = true
            if card and (type(card.weak) == "table") then
                for _ in pairs(card.weak) do
                    bare = false
                    break
                end
            end
            local magicWeak = false
            for _, s in ipairs(skills) do
                local info = s.known
                if info and info.magic and info.element and isHit(s, false)
                    and (elementFactor(s, u) >= 3) and pay(s) then
                    magicWeak = true
                end
            end
            foes[#foes + 1] = {
                id = u.id, name = u.name, statuses = u.statuses,
                bare = bare, magicWeak = magicWeak, gauge = gaugeOfEnemy(u),
            }
        end
        local locked, hitting = false, false
        for _, id in ipairs(equippedIds(uid)) do
            local row = skillOf(id)
            if row and Kits.gated(row.name) and (activation(uid, id) == false) then
                locked = true
            end
        end
        for _, s in ipairs(skills) do
            if isHit(s, false) and pay(s) and (foldName(s.name) ~= "attack") and (not Kits.gated(s.name)) then
                hitting = true
            end
        end
        local tosses = (Fight.luckToss and Fight.luckToss[uid]) or 0
        local picked = Kits.pick(skills, {
            allies = w.allies, foes = foes, selfId = uid,
            actions = #(Fight.actions or {}), mp = w.mp or 0, maxMp = w.maxMp or 0,
            keep = keep, pay = (band() ~= "low"), healer = healer,
            claim = Fight.claim.kit, sent = Fight.kitOn,
            tossOk = locked and (not hitting) and (not Fight.chipped) and (tosses < 2),
        })
        if not picked then return nil end
        local ids, isAll
        if (picked.mode == "foe") and picked.foe then
            ids, isAll = { picked.foe.id }, false
        elseif picked.mode == "party" then
            ids = {}
            for _, a in ipairs(w.allies) do
                if not a.dead then ids[#ids + 1] = a.id end
            end
            isAll = true
        else
            ids, isAll = { uid }, false
        end
        local choice = finishChoice(uid, picked.skill, picked.why, ids, isAll)
        if not choice then return nil end
        choice.kitKey = picked.key
        choice.kitLuck = picked.luck and true or false
        Fight.claim.kit[picked.key] = true
        return choice
    end
    -- A kit waits while someone is critical or a fallen ally is still down.
    -- A fall earlier in the fight does not end it.
    if phase == 0 and not allyCritical() and not dead and not supportRested() then
        local choice = castKit()
        if choice then return choice end
    end

    -- The kit is setup and comes before the chip, so a thrown item waits for it.
    -- Boss fight: an item from the bag carries the hit the bar cannot pay.
    if w.boss and (phase == 0) and not allyCritical() then
        local list = #pool > 0 and pool or open
        local paidLands, paidWeak = false, false
        for _, x in ipairs(skills) do
            if isHit(x, false) and pay(x) then
                for _, u in ipairs(list) do
                    local f = elementFactor(x, u)
                    if f > 0 then paidLands = true end
                    if f >= 3 then paidWeak = true end
                end
            end
        end
        if not paidWeak then
            local thrown = pickRecoveryItem(uid, w, "attack", { list = list, landing = not paidLands })
            if thrown then return thrown end
        end
    end


    -- Adds plan: the only ally who can pay the large gauge's weakness keeps
    -- chipping it while someone else can pay a weakness on the adds.
    if (mode == "adds") and bossU and (phase == 0) then
        local function paysOn(spells, mp, list)
            for _, s in ipairs(spells) do
                if isHit(s, false) and ((s.cost or 0) <= mp) then
                    for _, u in ipairs(list) do
                        if elementFactor(s, u) >= 3 then return true end
                    end
                end
            end
            return false
        end
        if paysOn(skills, w.mp or 0, { bossU }) then
            local rival, cover = false, false
            for _, a in ipairs(w.allies) do
                if (a.id ~= uid) and (not a.dead) and (a.acts ~= false) and (not heldOut(a)) then
                    local kit = unitKit(a.id)
                    local mp = stat(a.id, PARAM.MP, false) or 0
                    if kit and paysOn(kit.spells or {}, mp, { bossU }) then rival = true end
                    if kit and paysOn(kit.spells or {}, mp, pool) then cover = true end
                end
            end
            if (not rival) and cover then
                local held = castDamage({ bossU }, false, "only payer")
                if held then return held end
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
        if not (Fight.isSummon and Fight.isSummon(id)) then
            -- A party slot with no living unit is down. Without this it reads
            -- full, a fall is missed, and an ally who enters down looks like a fall.
            local hp = hpRatio(id) or 0
            if Fight.unitDown and Fight.unitDown(id) then hp = 0 end
            local name = Fight.nameOf(id)
            snap[id] = { side = "ally", name = name, hp = hp, broken = false }
        end
    end
    for _, id in ipairs(members(REL.ENEMY)) do
        snap[id] = { side = "enemy", name = unitName(id), hp = hpRatio(id) or 1, broken = broken(id) }
    end
    return snap
end

local function noteChanges(now)
    local last = Fight.last
    -- Every party member down is a wipe. A retry may follow in the same battle.
    local allies, standing = 0, 0
    for _, cur in pairs(now) do
        if cur.side == "ally" then
            allies = allies + 1
            if cur.hp > 0 then standing = standing + 1 end
        end
    end
    if (allies > 0) and (standing == 0) then Fight.wiped = true end
    for id, was in pairs(Fight.prev) do
        local cur = now[id]
        -- Only a friend can be a summon. An enemy's skill list is not read here.
        local summon = (was.side == "ally") and Fight.isSummon and Fight.isSummon(id)
        if was.side == "ally" and was.hp > 0 and (not cur or cur.hp <= 0) and not summon then
            Fight.fell[#Fight.fell + 1] = was.name
            appendLog("  fell: " .. was.name)
            local at = Fight.raisedRound and Fight.raisedRound[id]
            if at and (((Fight.rounds or 0) - at) <= 2) then
                Fight.refell = Fight.refell or {}
                Fight.refell[id] = Fight.rounds or 0
                appendLog("  " .. was.name .. " fell again right after a raise")
            end
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
            copy.known = knownOf(copy)
            local use = copy.known and copy.known.use
            local cost = 0
            pcall(function() cost = skillCost(uid, id, false) or 0 end)
            copy.cost = cost
            local okKind, kind = pcall(classify, copy)
            local name = copy.name and copy.name:lower() or ""
            local plain = (name == "attack") or ((copy.attr == ATTR.FIGHT) and (cost <= 0) and (kind ~= "defend"))
            local tagged = (use == "break") or (use == "cash")
            local damage = tagged or plain or (okKind and kind == "damage")
            local held = (use == "skip") or (use == "opener") or (use == "guardbuff") or (use == "guard")
                or (use == "scan") or (use == "heal") or (use == "cure") or (use == "debuff")
                or (use == "buff") or (use == "lb-setup") or (use == "lb-revive") or (use == "lb-cash")
                or (use == "lb-break") or (use == "lb-guard")
                or (copy.attr == ATTR.LB)
            if damage and not held and (cost <= mp) and not (Fight.deferChip and (cost > 0)) then
                copy.kind = "damage"
                usable[#usable + 1] = copy
            end
        end
    end
    local best, bestR = nil, -1
    for _, s in ipairs(usable) do
        local okOff, pow, br = pcall(offenseOf, s)
        local score = 0
        if okOff then score = (br or 0) * 1000 + (pow or 0) end
        local name = s.name and s.name:lower() or ""
        local use = s.known and s.known.use
        local plain = (name == "attack") or ((s.attr == ATTR.FIGHT) and ((s.cost or 0) <= 0))
        local tagged = (use == "break") or (use == "cash")
        -- Plain Attack and a published damage row beat an unlabeled skill.
        if plain or tagged then score = score + 1000000 end
        if score > bestR then best, bestR = s, score end
    end
    if not best and SkillIdx then
        for id, s in pairs(SkillIdx) do
            if (not best) and (s.attr == ATTR.FIGHT) and (activation(uid, id) == true) then
                local copy = tagSkill(uid, id, true)
                if copy and ((not copy.known) or (copy.known.use ~= "skip")) and ((copy.cost or 0) <= mp) then
                    best = copy
                end
            end
        end
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
    -- A hit the target nulls is not swung there. Another enemy it lands on is tried.
    pcall(function()
        if elementFactor(best, { id = tid, name = unitName(tid) }) <= 0 then
            for _, id in ipairs(members(REL.ENEMY)) do
                if keepFoe(id) and (elementFactor(best, { id = id, name = unitName(id) }) > 0) then
                    tid = id
                    return
                end
            end
        end
    end)
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
                local ratio = hpRatio(id)
                local down = Fight.unitDown and Fight.unitDown(id)
                if down or (ratio == nil) or (ratio <= 0) then
                    local seen = false
                    for _, a in ipairs(w.allies) do
                        if a.id == id then
                            a.dead = true
                            a.hp = 0
                            seen = true
                        end
                    end
                    if not seen then
                        w.allies[#w.allies + 1] = {
                            id = id, name = unitName(id), hp = 0,
                            dead = true, statuses = statuses(id), acts = true,
                        }
                    end
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
    -- The fallback swing is a payable hit that can land, on a body it lands
    -- on. A hit every enemy nulls is not swung.
    local foe = w.enemies and w.enemies[1]
    if foe then
        local swing, swingR, swingU = nil, -1, nil
        for _, s in ipairs(usable) do
            local playerOnly = s.known and s.known.use == "skip"
            local damage = (s.kind == "damage" or s.attr == ATTR.FIGHT) and not playerOnly
            if damage and s.kind ~= "heal" and s.kind ~= "buff" and s.attr ~= ATTR.FINISH
                and (s.cost or 0) <= (w.mp or 0) then
                local target = nil
                for _, e in ipairs(w.enemies) do
                    if (not target) and (elementFactor(s, e) > 0) then target = e end
                end
                -- While the setup is owed, a paid swing waits if a free one lands there.
                if target and Fight.deferChip and ((s.cost or 0) > 0) then
                    for _, x in ipairs(usable) do
                        if (x.attr == ATTR.FIGHT) and ((x.cost or 0) <= 0) and (x.kind ~= "defend")
                            and (elementFactor(x, target) > 0) then
                            target = nil
                            break
                        end
                    end
                end
                if target then
                    local _, br = offenseOf(s)
                    local score = (br or 0) * 1000 + (s.power or 0)
                    if score > swingR then swing, swingR, swingU = s, score, target end
                end
            end
        end
        if swing then
            return finishChoice(uid, swing, "kit " .. swingU.name, { swingU.id }, false)
        end
        -- Nothing on the bar lands on anyone: guard the turn instead. With
        -- no guard, the turn still goes out, so the menu is never left open.
        for _, s in ipairs(usable) do
            if s.kind == "defend" and (s.cost or 0) <= (w.mp or 0) then
                return finishChoice(uid, s, "defend, no hit lands", { uid }, false)
            end
        end
        for _, s in ipairs(usable) do
            if (s.attr == ATTR.FIGHT) and ((s.cost or 0) <= 0) and (s.kind ~= "defend") then
                return finishChoice(uid, s, "kit " .. foe.name .. ", nothing lands", { foe.id }, false)
            end
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
    Fight.summons = {}
    Fight.openIds = {}
    for _, id in ipairs(friendIds()) do Fight.openIds[id] = true end
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
    Fight.claim = { heal = {}, revive = {}, hone = {}, ether = {}, scan = {}, kit = {}, etherRound = false, guard = false, esper = false, lb = false }
    Fight.kitOn = {}
    Fight.drawSeen, Fight.cureTry, Fight.cureMiss, Fight.drawRound = {}, {}, {}, {}
    Fight.refell, Fight.raisedRound, Fight.wiped = {}, {}, false
    Fight.kindMiss, Fight.kindNull, Fight.kindHit, Fight.hitProbe = {}, {}, {}, nil
    Fight.guardOn = {}
    Fight.veil = nil
    Fight.supportRun = {}
    Fight.foeLow, Fight.hitsSince, Fight.stalemateTold = {}, 0, false
    Fight.luckToss = {}
    Fight.debuffOn, Fight.debuffSeen, Fight.debuffTold = {}, {}, {}
    Fight.went, Fight.rounds, Fight.seenFoe = {}, 0, {}
    Fight.planTag, Fight.afterBonus = nil, false
    Fight.fieldTold = false
    Fight.chipped = false
    Fight.esperOut = nil
    Fight.esperTold = false
    Fight.esperSkip = {}
    Fight.limitUntagged = {}
    Fight.limitSkip = {}
    Fight.cureHeld = false
    Fight.healLeft = {}
    Fight.statusTold = {}
    Fight.slowSince, Fight.slowTry, Fight.slowTold, Fight.slowUsed = {}, nil, {}, {}
    Fight.underLine = false
    Fight.downNow = {}
    Fight.lbRead = {}
    Fight.lbRows = {}
    -- A low bar from the last fight is not a wipe in this one.
    Fight.mpAnchor, Fight.mpLow, Fight.mpBack, Fight.mpFed = {}, {}, {}, {}
    Fight.roundAt = 0
    Fight.unmarked = false
    Fight.unmarkedTold = false
    Fight.recoverTold = false
    Fight.entryTold = false
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

-- The stagger book called a break the game did not give. The gauge is
-- larger than the estimate, or the proven size held.
local function releaseGauge(id)
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
        local grown = math.floor((poured / 0.72) + 0.5)
        if grown < (book + 1) then grown = book + 1 end
        if Gauges.rise then grown = Gauges.rise(book, poured) end
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
    -- A break gives the very next ally turn the bonus. A hit that filled the
    -- book's gauge, followed by a normal turn, did not break: release it now
    -- rather than plan a whole pass around a break that is not there.
    local check = Fight.pourCheck
    Fight.pourCheck = nil
    if check and (phaseNow == 0) and (prevPhase == 0) then
        for _, id in ipairs(check) do
            local poured = Fight.poured[id] or 0
            local card = mobOf({ id = id, name = unitName(id) })
            local gauge = (card and tonumber(card.gauge)) or nil
            local scaled = Fight.gaugeScale[id]
            if scaled and ((not gauge) or (scaled > gauge)) then gauge = scaled end
            if gauge and (gauge > 0) and (poured >= gauge) and (not broken(id)) then
                releaseGauge(id)
                local open = false
                for _ in pairs(Fight.down) do open = true end
                if not open then Fight.downSince = nil end
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
            for _, id in ipairs(ids) do releaseGauge(id) end
            Fight.downSince = nil
        end
    end
end

local function noteRound(uid)
    Fight.went = Fight.went or {}
    if uid and (uid >= 0) then Fight.went[uid] = true end
    -- A round is one turn for every party member who can take one. A summon
    -- and an ally whose status takes the turn are not waited on. A round
    -- never runs past two passes of the party, so nothing can hold it open.
    local actors, went = 0, 0
    for _, id in ipairs(friendIds()) do
        local ratio = hpRatio(id)
        local summon = Fight.isSummon and Fight.isSummon(id)
        -- A fallen ally reads no HP. Down is down, so the round does not wait on them.
        local down = (Fight.unitDown and Fight.unitDown(id)) or ((ratio ~= nil) and (ratio <= 0))
        if (not summon) and (not down) and (ratio ~= nil) then
            local kit = unitKit(id)
            local held = false
            if Health.OUT then
                local set = statuses(id)
                for sid in pairs(Health.OUT) do
                    if set[sid] then held = true end
                end
            end
            if kit and kit.spells and (#kit.spells > 0) and ((not held) or Fight.went[id]) then
                actors = actors + 1
                if Fight.went[id] then went = went + 1 end
            end
        end
    end
    local since = #(Fight.actions or {}) - (Fight.roundAt or 0)
    if (actors > 0) and ((went >= actors) or (since >= actors * 2)) then
        Fight.roundAt = #(Fight.actions or {})
        Fight.went = {}
        Fight.healLeft = {}
        Fight.rounds = (Fight.rounds or 0) + 1
        if Fight.claim then
            Fight.claim.heal = {}
            Fight.claim.ether = {}
            Fight.claim.etherRound = false
            Fight.claim.kit = {}
        end
        Fight.afterBonus = false
    end
end

local function markSummon(skill, turns)
    if not (skill and skill.attr == ATTR.SUMMON) then return end
    local fact = (Espers.lookup and Espers.lookup(skill.name)) or nil
    local stay = turns or (fact and fact.turns) or 3
    Fight.esperOut = {
        at = #(Fight.actions or {}),
        turns = stay,
        name = skill.name or "summon",
        told = false,
    }
    Fight.summoned = true
    Fight.claim = Fight.claim or {}
    Fight.claim.esper = true
end

local function act(serial)
    if not cfg.Enabled then return end
    if (not Menu.open) or (Menu.serial ~= serial) or Menu.sub or Menu.decided then return end
    local uid = currentActor()
    if uid < 0 then uid = Menu.actor end
    if uid < 0 then return end
    pcall(ensureBattle)
    if Fight.slowTry and Health.watchSlowCast and (not Fight.slowTry.out) then
        Fight.slowHeld = Fight.slowTry.key
        Fight.slowTry, Fight.slowNote = Health.watchSlowCast(Fight.slowTry, {
            dead = (hpRatio(Fight.slowTry.caster) or 1) <= 0,
            statuses = statuses(Fight.slowTry.caster),
            mp = stat(Fight.slowTry.caster, PARAM.MP, false),
            actor = uid,
        })
        if Fight.slowTry and Fight.slowTry.out and Fight.slowTry.key then
            Fight.slowUsed = Fight.slowUsed or {}
            Fight.slowUsed[Fight.slowTry.key] = true
        end
        if (not Fight.slowTry) and Fight.slowHeld and Fight.slowUsed then
            Fight.slowUsed[Fight.slowHeld] = nil
        end
        if Fight.slowNote then
            log("%s", Fight.slowNote)
            appendLog("  " .. Fight.slowNote)
            Fight.slowNote = nil
        end
        Fight.slowHeld = nil
    end
    if Fight.slowTry and Health.settleSlow and ((Fight.rounds or 0) > (Fight.slowTry.round or 0)) then
        Fight.slowOut = Fight.slowTry.out and true or false
        Fight.slowHeld = Fight.slowTry.key
        Fight.slowTry, Fight.slowTold, Fight.slowNote = Health.settleSlow(
            Fight.slowTry,
            Health.slowAlly(Fight.slowTry.id, hpRatio(Fight.slowTry.id), statuses(Fight.slowTry.id)),
            Fight.slowTold)
        if (not Fight.slowTry) and Fight.slowHeld and (not Fight.slowOut) and Fight.slowUsed then
            Fight.slowUsed[Fight.slowHeld] = nil
        end
        if Fight.slowNote then
            log("%s", Fight.slowNote)
            appendLog("  " .. Fight.slowNote)
            Fight.slowNote = nil
        end
        Fight.slowHeld = nil
        Fight.slowOut = nil
    end
    -- A wipe puts the party back on its opening MP without a raise we sent.
    -- The stagger book and the one-time setup belong to the attempt that fell.
    local function noteMp(who)
        local mp = stat(who, PARAM.MP, false)
        if (not mp) or (mp <= 0) or (not Fight) or (not Fight.active) then return end
        Fight.mpAnchor = Fight.mpAnchor or {}
        Fight.mpLow = Fight.mpLow or {}
        Fight.mpBack = Fight.mpBack or {}
        local anchor = Fight.mpAnchor[who]
        if (not anchor) or (mp > anchor) then
            Fight.mpAnchor[who] = mp
            anchor = mp
        end
        -- An item put this MP back (an Ether, an Elixir): not a retry.
        Fight.mpFed = Fight.mpFed or {}
        if Fight.mpFed[who] and (mp >= (anchor * 0.8)) then
            Fight.mpFed[who] = nil
            Fight.mpLow[who] = nil
            Fight.mpBack[who] = nil
        end
        if mp < (anchor * 0.8) then
            Fight.mpLow[who] = true
            Fight.mpBack[who] = nil
        elseif Fight.mpLow[who] and (mp >= (anchor * 0.95)) then
            Fight.mpBack[who] = true
        end
        local n, party = 0, 0
        for _, on in pairs(Fight.mpBack) do
            if on then n = n + 1 end
        end
        for _ in pairs(Fight.seenAlly or {}) do party = party + 1 end
        -- After a wipe nobody is left to raise anyone, so a party member
        -- standing again means the game restarted the fight: a retry, at any
        -- HP or MP.
        local retry = false
        if Fight.wiped then
            for id in pairs(Fight.seenAlly or {}) do
                local r = hpRatio(id)
                if r and (r > 0) then retry = true end
            end
        end
        -- Most of the party back at its opening bar. The same share for any size.
        local need = math.max(1, math.ceil(party * 0.75))
        if (n < need) and (not retry) then return end
        Fight.wiped = false
        Fight.refell, Fight.raisedRound = {}, {}
        Fight.mpBack = {}
        Fight.mpLow = {}
        Fight.poured, Fight.down, Fight.downTold = {}, {}, {}
        Fight.relax, Fight.gaugeScale, Fight.brokeOn = {}, {}, {}
        Fight.gaugeSure, Fight.gaugeWas = {}, {}
        Fight.broke, Fight.fell = {}, {}
        Fight.downSince, Fight.bonusSeen, Fight.planTag = nil, false, nil
        Fight.chipped = false
        Fight.claim = Fight.claim or {}
        Fight.claim.lb = false
        Fight.claim.lbBreak = false
        Fight.claim.guard = false
        Fight.guardOn = {}
        Fight.veil = nil
        Fight.claim.hone = {}
        Fight.claim.esper = false
        Fight.esperOut = nil
        Fight.debuffOn, Fight.debuffSeen = {}, {}
        Fight.kitOn, Fight.luckToss = {}, {}
        if Fight.claim then Fight.claim.kit = {} end
        local line = "party restored. ledger cleared"
        log("%s", line)
        appendLog("  " .. line)
    end
    pcall(noteMp, uid)
    local actorName = unitName(uid)
    if Espers.lookup and Espers.lookup(actorName) then
        local line = actorName .. " acts on its own"
        log("%s", line)
        appendLog("  " .. line)
        return
    end
    local finishingEarly = false
    pcall(function() finishingEarly = inFinishPhase() end)
    if finishingEarly and Fight.resonanceSent then return end
    pcall(function() noteChanges(livingSnapshot()) end)
    pcall(settleGauges)
    -- The last hit's targets: a kind that twice in a row took no HP is
    -- treated as nulled on that enemy for the fight. A hit that lands clears
    -- the count.
    pcall(function()
        local probe = Fight.hitProbe
        Fight.hitProbe = nil
        if not probe then return end
        Fight.kindMiss = Fight.kindMiss or {}
        Fight.kindNull = Fight.kindNull or {}
        Fight.kindHit = Fight.kindHit or {}
        for id, before in pairs(probe.hp) do
            local now = hpRatio(id)
            if now and (now > 0) then
                Fight.kindMiss[id] = Fight.kindMiss[id] or {}
                if now >= (before - 0.0005) then
                    local n = (Fight.kindMiss[id][probe.kind] or 0) + 1
                    Fight.kindMiss[id][probe.kind] = n
                    -- A kind that already took HP off this enemy in this fight is not a null.
                    local landed = Fight.kindHit[id] and Fight.kindHit[id][probe.kind]
                    if (n >= 2) and (not landed) and not (Fight.kindNull[id] and Fight.kindNull[id][probe.kind]) then
                        Fight.kindNull[id] = Fight.kindNull[id] or {}
                        Fight.kindNull[id][probe.kind] = true
                        local line = string.format("%s takes no damage from %s hits", unitName(id), probe.kind)
                        log("%s", line)
                        appendLog("  " .. line)
                    end
                elseif not (probe.summon or Fight.summoned) then
                    Fight.kindMiss[id][probe.kind] = 0
                    Fight.kindHit[id] = Fight.kindHit[id] or {}
                    Fight.kindHit[id][probe.kind] = true
                end
                -- A summon hits on its own, so with one out a drop is not this
                -- kind's. It neither lands the kind nor clears the misses.
            end
        end
    end)
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
    local who = Fight.nameOf(uid)
    local phase = finishing and PHASE_FINISH or currentPhase()
    local mpNow = stat(uid, PARAM.MP, false)
    local line = string.format("%s p%d mp%s: %s -> %s", who, phase, tostring(mpNow or "?"), choice.name, choice.reason)
    if not cfg.Submit then
        appendLog("  (not sent) " .. line)
        log("(not sent) %s", line)
        return
    end
    -- The targets' HP before the hit goes out, to learn a kind the enemy nulls.
    local probeHp = nil
    if (choice.kind == "damage") and (not choice.isItem) and (choice.attr ~= ATTR.SUMMON) and choice.targets then
        probeHp = {}
        for _, tid in ipairs(choice.targets) do
            if Fight.seenFoe and Fight.seenFoe[tid] then
                local r = hpRatio(tid)
                if r and (r > 0) then probeHp[tid] = r end
            end
        end
    end
    local ok, sent = pcall(send, uid, choice, phase)
    if not ok then
        log("send failed: %s", tostring(sent))
        return
    end
    if not sent then return end
    noteStance(uid, choice.name)
    if choice.attr == ATTR.ESCAPE then Fight.escapeSent = (Fight.escapeSent or 0) + 1 end
    if choice.kitKey then
        Fight.kitOn = Fight.kitOn or {}
        Fight.kitOn[choice.kitKey] = #(Fight.actions or {})
        if choice.kitLuck and uid and (uid >= 0) then
            Fight.luckToss = Fight.luckToss or {}
            Fight.luckToss[uid] = (Fight.luckToss[uid] or 0) + 1
        end
    end
    if choice.slow then Fight.slowTry = choice.slow end
    -- A support turn in the fight, then a hit: see supportRested.
    Fight.supportRun = Fight.supportRun or {}
    local why = choice.reason or ""
    if (why:find("^setup") or why:find("^refresh")) and Fight.chipped then
        Fight.supportRun[uid] = (Fight.supportRun[uid] or 0) + 1
    elseif choice.kind == "damage" then
        Fight.supportRun[uid] = 0
    end
    -- Watch this hit's targets, to learn a kind the enemy nulls.
    if probeHp and next(probeHp) then
        local kind = kindOf(choice)
        if kind then Fight.hitProbe = { kind = kind, hp = probeHp, summon = Fight.summoned and true or false } end
    end
    if ((choice.kind == "revive") or (choice.itemUse == "revive")) and choice.targets then
        Fight.raisedRound = Fight.raisedRound or {}
        for _, tid in ipairs(choice.targets) do Fight.raisedRound[tid] = Fight.rounds or 0 end
    end
    if choice.attr == ATTR.FINISH then Fight.resonanceSent = true end
    if (choice.kind == "damage") and (not choice.isItem) and (choice.attr ~= ATTR.SUMMON) then
        Fight.hitsSince = (Fight.hitsSince or 0) + 1
    end
    if phase == 0 and choice.kind == "damage" and not choice.isItem then
        Fight.line = true
        local reason = choice.reason or ""
        if (choice.cost or 0) > 0 and (not reason:find("^setup")) and (choice.attr ~= ATTR.SUMMON) then
            Fight.chipped = true
        end
    end
    local limitCast = choice.attr == ATTR.LB
    if choice.known and limitSkill({ known = choice.known }) then limitCast = true end
    -- An item that may refill MP is remembered on its targets, so the MP it
    -- puts back is not read as a retry.
    if choice.isItem and choice.targets then
        Fight.mpFed = Fight.mpFed or {}
        for _, tid in ipairs(choice.targets) do Fight.mpFed[tid] = true end
    end
    -- A thrown item pours the stagger on its own skill row, in its element.
    local thrownRow = nil
    if choice.isItem and (choice.itemUse == "attack") then
        local irow = ItemIdx and ItemIdx[choice.id] or nil
        local srow = irow and irow.skillId and skillOf(irow.skillId) or nil
        if srow then
            thrownRow = { breakPower = srow.breakPower, hits = srow.hits, power = srow.power,
                attr = ATTR.ITEM, known = choice.known, name = choice.name }
        end
    end
    if phase == 0 and choice.targets and ((choice.kind == "damage") or limitCast or thrownRow)
        and ((not choice.isItem) or thrownRow) and (choice.attr ~= ATTR.SUMMON) then
        Fight.poured = Fight.poured or {}
        Fight.down = Fight.down or {}
        Fight.relax = Fight.relax or {}
        Fight.gaugeScale = Fight.gaugeScale or {}
        Fight.lastHit = choice.targets
        local row = thrownRow or skillOf(choice.id)
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
                        Fight.pourCheck = Fight.pourCheck or {}
                        Fight.pourCheck[#Fight.pourCheck + 1] = tid
                    end
                end
            end
        end
    end
    if Fight.elemRun and choice.targets and choice.known and choice.known.element
        and (choice.attr ~= ATTR.SUMMON) then
        local el = choice.known.element
        for _, tid in ipairs(choice.targets) do
            local run = Fight.elemRun[tid]
            if run and run.el == el then run.n = run.n + 1
            else Fight.elemRun[tid] = { el = el, n = 1 } end
        end
    end
    Fight.actions[#Fight.actions + 1] = line
    if choice.attr == ATTR.SUMMON then markSummon(choice, choice.esperTurns) end
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
    -- A pick from an open menu, or on the Resonance wheel, belongs to that
    -- menu's ally. A command with no menu is one the game made for the
    -- unit whose turn it is, such as an ally whose status takes the turn.
    local onWheel = (currentPhase() == PHASE_FINISH)
    local uid = nil
    if Menu.fromMenu or onWheel then uid = Menu.actor else uid = currentActor() end
    if (not uid) or (uid < 0) then uid = Menu.actor end
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
    -- The command names its own unit. A command the game made for an enemy
    -- is the enemy's turn, not the party's: it is not recorded.
    local actorId = nil
    pcall(function() actorId = num(rowObj.actionUnitUniqueId) end)
    if actorId and (actorId >= 0) and not (Menu.fromMenu or onWheel) then uid = actorId end
    if uid and (uid >= 0) then
        local foe = Fight.seenFoe and Fight.seenFoe[uid]
        if not foe then
            local p = paramOf(uid)
            if p then
                local okR, rel = pcall(function() return p:GetRelation() end)
                if okR and (num(rel) == REL.ENEMY) then foe = true end
            end
        end
        if foe then return end
    end
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
        Fight.mpFed = Fight.mpFed or {}
        for _, tid in ipairs(targets) do Fight.mpFed[tid] = true end
        if (#targets == 0) and uid and (uid >= 0) then Fight.mpFed[uid] = true end
        local listed = Items.listed and Items.listed(name)
        if listed == "hp" then kind = "heal" end
        if listed == "mp" then kind = "ether" end
        if listed == "revive" then kind = "revive" end
        if listed == "cure" then kind = "cure" end
    end
    if (use == "heal") or (use == "patch") then kind = "heal" end
    if use == "cure" then kind = "cure" end
    if (use == "revive") or (use == "lb-revive") then kind = "revive" end
    if use == "debuff" then kind = "debuff" end
    if (not kind) and ((use == "break") or (use == "cash")) then kind = "damage" end
    local phase = currentPhase()
    local who = (uid and (uid >= 0)) and Fight.nameOf(uid) or "you"
    local line = string.format("player %s p%d: %s", who, phase, name)
    if #targets > 0 then
        local bits = {}
        for _, tid in ipairs(targets) do bits[#bits + 1] = Fight.nameOf(tid) end
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
        Fight.raisedRound = Fight.raisedRound or {}
        for _, id in ipairs(ids) do Fight.raisedRound[id] = Fight.rounds or 0 end
    end
    if (kind == "ether") and uid and (uid >= 0) then
        Fight.claim.ether[uid] = true
        Fight.claim.etherRound = true
    end
    if (kind == "debuff") and info and info.effect then
        if #targets > 0 then
            for _, id in ipairs(targets) do markDebuff(id, info.effect) end
        end
    end
    if use == "guardbuff" then
        Fight.guardOn = Fight.guardOn or {}
        local copy = { known = info, friendStatus = skill and skill.friendStatus or {} }
        Fight.guardOn[(info and info.guards) or "any"] = { map = copy.friendStatus, seen = false }
    end
    if (use == "opener") and uid and (uid >= 0) then Fight.claim.hone[uid] = true end
    if use == "lb-setup" then Fight.claim.lb = true end
    if use == "lb-break" then Fight.claim.lbBreak = true end
    if use == "lb-guard" then
        Fight.veil = { map = (skill and skill.friendStatus) or {}, seen = false, round = Fight.rounds or 0 }
    end
    noteStance(uid, name)
    if skill and (skill.attr == ATTR.ESCAPE) then Fight.escapeSent = (Fight.escapeSent or 0) + 1 end
    if Kits.key and Kits.key(name) then
        Fight.kitOn = Fight.kitOn or {}
        Fight.kitOn[Kits.key(name)] = #(Fight.actions or {})
        Fight.drawRound = Fight.drawRound or {}
        Fight.drawRound[Kits.key(name)] = Fight.rounds or 0
    end
    if skill and (skill.attr == ATTR.SUMMON) then markSummon(skill) end
    if skill and (skill.attr == ATTR.FINISH) then Fight.resonanceSent = true end
    if phase == PHASE_FINISH then Fight.resonanceSent = true end
    local cost = 0
    if skill and uid and (uid >= 0) then
        pcall(function() cost = skillCost(uid, actionId, false) or 0 end)
    end
    -- Only a hit on an enemy counts toward a stalemate. A confused ally's swing at the party does not.
    if (kind == "damage") and (not isItem) then
        for _, tid in ipairs(targets) do
            if Fight.seenFoe and Fight.seenFoe[tid] then
                Fight.hitsSince = (Fight.hitsSince or 0) + 1
                break
            end
        end
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
                        Fight.pourCheck = Fight.pourCheck or {}
                        Fight.pourCheck[#Fight.pourCheck + 1] = tid
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
    -- The wheel is the party's pick, not a turn.
    if uid and (uid >= 0) and (not onWheel) then noteRound(uid) end
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
            Menu.fromMenu = Menu.open and (not Menu.decided) and true or false
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
        local down = (Fight.unitDown and Fight.unitDown(uid)) or (ratio == nil) or (ratio <= 0)
        if (not down) and not outOfControl(uid) then
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
    buildSkillIndex()
    if not Fight.active then return end
    local u = FindFirstOf("CPP_BtlUnit")
    if u and u:IsValid() then
        absent = 0
        -- A fall between turns is noted here too, so the last one before
        -- the battle ends, such as a wipe, still reaches the log.
        pcall(function() noteChanges(livingSnapshot()) end)
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
    if leftRose and cfg.Enabled then pressBasic() end
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
log("loaded. planner v0.1.36. %s. %s toggles auto battle. %s basic attacks %s. In a fight, while auto battle is on, the left trigger toggles basic attacks. The right trigger toggles auto battle. Bestiary %d. Submit=%s.",
    cfg.Enabled and "on" or "off",
    cfg.TakeOverKey,
    cfg.MenuKey,
    cfg.AttacksOnly and "on" or "off",
    mobCount,
    tostring(cfg.Submit))

-- FFR:AutoBattle. One auto-battle switch. One planner for the round, from the
-- design doc: score every enemy, chip the gauges, finish them together.
-- The characters carry out the next slot. Claims stop a second heal, a second
-- buff, or a second Ether in the same round.
-- F10 is on/off and flashes AutoBattle On or Off.
-- F9 switches the mode between No Mercy (the default, the full plan) and
-- Echo (each character's last turn by hand, sent again; see echo.lua).
-- Both switches are remembered.
-- In a fight, the right trigger fires the F10 action. While auto battle is
-- on in a fight, the left trigger fires the F9 action. While auto battle is
-- off, or outside a fight, the left trigger stays with the game, except that
-- with LargeMap on, the left trigger on the field is the large map, as MapKey.
--
-- Every fact comes from the game's own tables, read live. Saves and pak files
-- are not touched. The command goes out through Delegate.Battle.Cmd.Decide.
-- SkipScenes in config.ini is off unless set. On, it asks the game to skip a
-- Limit Burst, a Vision finish, an Esper summon, or that Esper's own attack
-- once that scene allows a skip. The sequence player is never cut.
-- Other scenes stay.
-- LevelGate is off unless set. On, a character gains no experience from a
-- fight where every monster is under that character's level. A monster at or
-- above them still pays the game's own amount.
-- Turbo is off unless set. On, a fight's actions play at four times the battle
-- speed button's fastest mark. The command menu stays at the game's
-- command-select speed. A Limit Burst, a Vision finish, and an Esper scene
-- stay at normal speed. The speed stops when the battle result begins, so
-- the story after the fight is left alone.

local TAG = "[FFRAutoBattle] "
-- Reporting off: only the startup line and real errors reach UE4SS.log.
local Reporting = false
local function log(fmt, ...)
    local text = tostring(fmt)
    if select("#", ...) > 0 then text = string.format(fmt, ...) end
    if (not Reporting) and not (text:find("loaded. planner", 1, true) or text:find("failed", 1, true)
        or text:find("error", 1, true) or text:find("unavailable", 1, true) or text:find("could not", 1, true)
        or text:find("scene skip", 1, true) or text:find("level gate", 1, true)
        or text:find("turbo", 1, true) or text:find("large map", 1, true)
        or text:find("echo:", 1, true)) then
        return
    end
    print(TAG .. text .. "\n")
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
-- Every fact comes from the game's own rows, built when the tables are read.
local Known = { skills = {} }
do
    local ok, rows = pcall(dofile, DIR .. "/Scripts/rows.lua")
    if ok and type(rows) == "table" then
        Known.rows = rows
    else
        log("rows unavailable: %s", tostring(rows))
    end
end
do
    local okB, brace = pcall(dofile, DIR .. "/Scripts/brace.lua")
    if okB and type(brace) == "table" then
        Known.brace = brace
    else
        log("brace unavailable: %s", tostring(brace))
    end
    local okM, measure = pcall(dofile, DIR .. "/Scripts/measure.lua")
    if okM and type(measure) == "table" then
        Known.measure = measure
    else
        log("measure unavailable: %s", tostring(measure))
    end
    local okR, report = pcall(dofile, DIR .. "/Scripts/report.lua")
    if okR and type(report) == "table" then
        -- Opened after the config is read, and only when reporting is on.
        Known.reportLib = report
    else
        log("report unavailable: %s", tostring(report))
    end
end
local function knownOf(skill)
    if not skill then return nil end
    local key = nil
    if skill.name then
        key = skill.name:lower()
        key = key:gsub("’", "'"):gsub("‘", "'"):gsub("`", "'")
    end
    -- The skill id is the row. A name is only the join when the live command
    -- has no id. An id that belongs to a different name is a collision, not a
    -- match, so it does not fall through to another skill with the same words.
    local own = Known.skillsById and skill.id and Known.skillsById[skill.id]
    if own then
        if (not key) or (own.name == key) then return own.fact end
        return nil
    end
    if not key or not Known.skills then return nil end
    return Known.skills[key]
end
local Mobs = {}
local Growth = {}
do
    local ok, loaded = pcall(dofile, DIR .. "/Scripts/growth.lua")
    if ok and type(loaded) == "table" then
        Growth = loaded
    else
        log("growth unavailable: %s", tostring(loaded))
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
    ok, loaded = pcall(dofile, DIR .. "/Scripts/pace.lua")
    if ok and type(loaded) == "table" then
        Known.pace = loaded
    else
        log("pace unavailable: %s", tostring(loaded))
    end
    ok, loaded = pcall(dofile, DIR .. "/Scripts/minimap.lua")
    if ok and type(loaded) == "table" then
        Known.minimap = loaded
    else
        log("large map unavailable: %s", tostring(loaded))
    end
    -- Echo's tape lives for the launch, so it carries from fight to fight.
    ok, loaded = pcall(dofile, DIR .. "/Scripts/echo.lua")
    if ok and type(loaded) == "table" then
        Known.echo = loaded
        Known.echoTape = loaded.new()
    else
        log("echo unavailable: %s", tostring(loaded))
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
    -- This enemy's own row. Rows under one name can differ.
    if enemy.id and Known.mobRow then
        local ok, card = pcall(Known.mobRow, enemy)
        if ok and card then return card, key end
    end
    return key and Mobs[key] or nil, key
end

local CONFIG_PATH = DIR .. "/config.ini"
local STATE_PATH = DIR .. "/state.txt"

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
local EFF = { DAMAGE = 1, PARAM = 2, CURE = 19, REVIVE = 20, DEFEND = 26, ANALYZE = 29, SUMMON = 37, COVER = 41, UNSUMMON = 43 }
local TGT = { SELF = 0, SINGLE = 1, GROUP = 2, SPREAD = 3, ALL = 4 }
local REL = { FRIEND = 1, ENEMY = 2 }
local PARAM = { HP = 1, MP = 2, BREAK = 3, LB = 4 }
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
    Enabled = true, Submit = true, Reporting = false,
    TakeOverKey = "F10", MenuKey = "F9", ItemPrice = 5000, SkipScenes = false,
    LevelGate = false, Turbo = false, LargeMap = false, MapKey = "F8", MapSize = 80,
    EsperLevelGap = 3, ResonanceLevelGap = 3, Echo = false, EchoKeep = true,
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
        -- A note after the value, as in "Enabled = true ; mine", is not the value.
        -- No setting's value holds ; or #.
        if v then v = v:gsub("%s*[;#].*$", "") end
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
    Reporting = cfg.Reporting
    if Reporting and Known.reportLib and (not Known.report) then
        Known.report = Known.reportLib.new(DIR .. "/battle_report.txt")
        pcall(Known.report.trim, Known.report)
    end
    local state = loadIni(STATE_PATH)
    if state.enabled then cfg.Enabled = parseBool(state.enabled) end
    if state.echo then cfg.Echo = parseBool(state.echo) end
end

local function saveState()
    local f = io.open(STATE_PATH, "w")
    if not f then return end
    f:write("enabled=" .. (cfg.Enabled and "true" or "false") .. "\n")
    f:write("echo=" .. (cfg.Echo and "true" or "false") .. "\n")
    f:close()
end

-- Every line goes to battle_report.txt, which keeps the last five fights.
local function appendLog(line)
    if not Reporting then return end
    if Known.report and type(line) == "string" then pcall(Known.report.note, Known.report, line) end
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
-- Walking these tables while a save is loading crashed the game. The startup
-- timer must not start the walk. It waits until a command menu is open, or a
-- fight is already underway. A hook only schedules the walk.
-- Declared here so battleUp, the row walk and the skill math below read
-- the fight table and not an unset global. It is filled in further down.
local Fight
local hookDepth = 0
local rowsAllowed = false
local rowWalkQueued = false
local queueRowWalk
local function battleUp()
    if Fight and Fight.active then return true end
    local ok, u = pcall(function() return FindFirstOf("CPP_BtlUnit") end)
    return (ok and u and u.IsValid and u:IsValid()) and true or false
end
local function buildSkillIndex(fromBattle)
    if SkillIdx then return end
    if hookDepth > 0 then
        queueRowWalk()
        return
    end
    if not (fromBattle or rowsAllowed or (Fight and Fight.active)) then return end
    if not battleUp() then return end
    local effects = {}
    local effectRows = {}
    local skills = {}
    local tables = FindAllOf("DataTable") or {}
    local effectTables, skillTables, itemTables, unitTables, aiTables = {}, {}, {}, {}, {}
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
            elseif struct == "UNIT_PARAMETER" then
                unitTables[#unitTables + 1] = dt
            elseif struct == "BTL_UNIT_AI_PARAMETER" then
                aiTables[#aiTables + 1] = dt
            end
        end)
    end
    for _, dt in ipairs(effectTables) do
        pcall(function()
            dt:ForEachRow(function(_, row)
                local id = num(field(row, "ID"))
                if id then
                    effects[id] = num(field(row, "statusCondition")) or 0
                    local params = {}
                    local list = field(row, "ParamList")
                    if (type(list) == "userdata" or type(list) == "table") and list.ForEach then
                        pcall(function()
                            list:ForEach(function(i, v) params[i] = num(unwrap(v)) end)
                        end)
                    end
                    effectRows[id] = { type = num(field(row, "EffectType")) or 0, status = effects[id],
                        turns = num(field(row, "effectEndActionNum")) or 0, params = params }
                end
            end)
        end)
    end
    for _, dt in ipairs(skillTables) do
        pcall(function()
            dt:ForEachRow(function(_, row)
                local id = num(field(row, "ID"))
                if not id then return end
                local friendStatus, enemyStatus = {}, {}
                local rowEffects = {}
                local rel = num(field(row, "defaultTargetRelation")) or 0
                -- Where a bundle's status lands is its TargetType, not its
                -- targetRelation, which reads Friendlies on Debrave and Poison
                -- too (DT_SkillData): SkillTarget (6) lands with the skill,
                -- Self (0) on the caster, Group and the rest on the side the
                -- bundle names.
                local bundles = field(row, "effectBundleList")
                if (type(bundles) == "userdata" or type(bundles) == "table") and bundles.ForEach then
                    bundles:ForEach(function(_, e)
                        local b = unwrap(e)
                        local eid = b and num(b.effectId)
                        local brel = b and num(b.targetRelation)
                        local btype = b and num(b.TargetType)
                        local st = eid and effects[eid]
                        if eid and effectRows[eid] then rowEffects[#rowEffects + 1] = effectRows[eid] end
                        if st and st > 0 then
                            local side = brel
                            if btype == 6 then side = rel
                            elseif btype == 0 then side = REL.FRIEND end
                            if side == REL.FRIEND then friendStatus[st] = true end
                            if side == REL.ENEMY then enemyStatus[st] = true end
                        end
                    end)
                end
                local own = num(field(row, "statusCondition")) or 0
                if own > 0 and rel == REL.FRIEND then friendStatus[own] = true end
                if own > 0 and rel == REL.ENEMY then enemyStatus[own] = true end
                local name = textOf(field(row, "Name"))
                -- eElement: 0 none, 1 fire, 2 ice, 3 wind, 4 earth, 5 thunder,
                -- 6 water, 7 light, 8 dark. A missing field is not a none.
                local elN = num(field(row, "element"))
                local element = nil
                if elN ~= nil and elN >= 1 and elN <= 8 then
                    element = ({ "fire", "ice", "wind", "earth", "thunder", "water", "light", "dark" })[elN]
                end
                skills[id] = {
                    id = id,
                    name = (name and name ~= "") and name or ("#" .. id),
                    element = element,
                    elementRead = elN ~= nil,
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
                    effects = rowEffects,
                    dmgType = num(field(row, "DamageType")) or 0,
                    fromUnit = (num(field(row, "hasUnit")) or 10) < 8,
                    modeTwin = num(field(row, "skillIdAfterModeChange")),
                    appliesAll = unwrap(field(row, "isApplyAllMag")) == true,
                    accuracy = num(field(row, "accuracy")),
                }
            end)
        end)
    end
    local n = 0
    for _ in pairs(skills) do n = n + 1 end
    if n > 0 then
        -- Multicast is the game's All cast: isApplyAllMag on its own row, linked
        -- by skillIdAfterModeChange. The row's magnification is what that cast
        -- does. Do not scale it by a share measured in one fight.
        for id, row in pairs(skills) do
            local twin = row.modeTwin and skills[row.modeTwin]
            if twin and twin.appliesAll and (not row.appliesAll) then
                row.multicast = row.modeTwin
                twin.multicastOf = id
            end
        end
        SkillIdx = skills
        log("skill table: %d rows", n)
    end
    local items = {}
    for _, dt in ipairs(itemTables) do
        local batch = {}
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
                local rec = {
                    id = id,
                    name = (name and name ~= "") and name or ("item " .. id),
                    skillId = skillId,
                    rare = field(row, "Rare") == true or field(row, "IsRare") == true,
                    price = num(field(row, "buyingPrice")) or 0,
                    sale = field(row, "isAvailableSale") == true,
                    scene = num(field(row, "usableScene")) or 0,
                }
                if Items.abovePrice and Items.abovePrice(rec.price, cfg.ItemPrice) then
                    rec.held = true
                end
                items[id] = rec
                batch[#batch + 1] = rec
            end)
        end)
        -- The row has no rare field. The buy prices on this table do. The
        -- high side of the one step wider than the rest is held back.
        if Items.rarePrices then
            local prices = {}
            for _, rec in ipairs(batch) do prices[#prices + 1] = rec.price end
            local high = Items.rarePrices(prices)
            local marked = {}
            for _, rec in ipairs(batch) do
                if high[rec.price] then
                    rec.rare = true
                    marked[rec.price] = true
                end
            end
            local bits = {}
            for price in pairs(marked) do bits[#bits + 1] = tostring(price) end
            table.sort(bits)
            if #bits > 0 then log("rare buy prices: %s", table.concat(bits, ", ")) end
        end
    end
    -- Enemy rows, then every fact the planner reads, from what was just walked.
    local units = {}
    local growthRows = {}
    local function readMap(map, into)
        if not (map and map.ForEach) then return end
        pcall(function()
            map:ForEach(function(k, v)
                local a, b = num(unwrap(k)), num(unwrap(v))
                if a and b then into[a] = b end
            end)
        end)
    end
    for _, dt in ipairs(unitTables) do
        pcall(function()
            dt:ForEachRow(function(_, row)
                local id = num(field(row, "ID"))
                if not id then return end
                local u = { name = textOf(field(row, "Name")), elements = {}, status = {}, traits = {},
                    maxBreak = num(field(row, "MaxBreakPoint")) or 0, boss = field(row, "IsBoss") == true }
                readMap(field(row, "ElementResistanceList"), u.elements)
                readMap(field(row, "StatusConditionResistanceList"), u.status)
                local traits = field(row, "Traits")
                if traits and traits.ForEach then
                    pcall(function()
                        traits:ForEach(function(_, t)
                            local text = textOf(unwrap(t) or t)
                            if text and text ~= "" then u.traits[#u.traits + 1] = text end
                        end)
                    end)
                end
                units[id] = u
                local lv = num(field(row, "Level"))
                if lv ~= nil then growthRows[id] = { level = lv } end
            end)
        end)
    end
    if next(growthRows) then Known.growth = growthRows end
    -- The game's own lists of each enemy's dangerous moves and counters.
    local function idList(list, into)
        if not (list and list.ForEach) then return end
        pcall(function()
            list:ForEach(function(_, v)
                local n = num(unwrap(v))
                if n and n > 0 then into[#into + 1] = n end
            end)
        end)
    end
    for _, dt in ipairs(aiTables) do
        pcall(function()
            dt:ForEachRow(function(_, row)
                local u = units[num(field(row, "ID"))]
                if u then
                    u.highRisk, u.counters, u.moves = {}, {}, {}
                    for _, key in ipairs({ "skillRandData1", "skillRandData2" }) do
                        local list = field(row, key)
                        if list and list.ForEach then
                            pcall(function()
                                list:ForEach(function(_, e)
                                    local n = num(unwrap(e).SkillId)
                                    if n and n > 0 then u.moves[#u.moves + 1] = n end
                                end)
                            end)
                        end
                    end
                    idList(field(row, "highRiskSkillIdList"), u.highRisk)
                    idList(field(row, "counterSkillIdList"), u.counters)
                end
            end)
        end)
    end
    if Known.rows and next(skills) then
        local okB, built = pcall(Known.rows.build, { skills = skills, units = units, items = items })
        if okB and built then
            Known.skills = built.known
            Known.skillsById = built.knownById
            Known.unitCards = built.units
            for k, v in pairs(built.mobs) do Mobs[k] = v end
            if Limits.load then Limits.load(built.limits) end
            if Espers.load then Espers.load(built.espers) end
            if Kits.load then Kits.load(built.kits) end
            if Items.load then Items.load(built.items) end
            local cards = 0
            for _ in pairs(built.units) do cards = cards + 1 end
            local mobs = 0
            for _ in pairs(Mobs) do mobs = mobs + 1 end
            log("rows read: %d enemy rows, %d bestiary, %d limits", cards, mobs, (function() local n = 0 for _ in pairs(built.limits) do n = n + 1 end return n end)())
        else
            log("rows failed: %s", tostring(built))
        end
    end
    local ni = 0
    for _ in pairs(items) do ni = ni + 1 end
    if ni > 0 then
        ItemIdx = items
        log("item table: %d rows, price cap %s", ni, tostring(cfg.ItemPrice))
    end
end

queueRowWalk = function()
    if SkillIdx or rowWalkQueued then return end
    rowWalkQueued = true
    gameDelay(0, function()
        rowWalkQueued = false
        buildSkillIndex()
    end)
end

local function skillOf(id)
    buildSkillIndex()
    return SkillIdx and SkillIdx[id]
end

-- Which statuses cut damage, and by how much, from the skill rows. Built once.
function Known.statusMap()
    buildSkillIndex()
    if (not Known.statusCuts) and SkillIdx and Known.brace then
        Known.statusCuts = Known.brace.statusCuts(SkillIdx)
    end
    return Known.statusCuts or {}
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
    local cur = stat(uid, PARAM.BREAK, false)
    local maxv = stat(uid, PARAM.BREAK, true)
    return cur ~= nil and maxv ~= nil and maxv > 0 and cur <= 0
end

-- Current BreakPoint over its max. nil when that read is missing, so the
-- ledger and the book stay the fallback. A failed GetBreakPointRatio used
-- to return 1 here, and gaugeOf then threw away any ratio at 0.99 or above.
-- That is why a missing read looked full. The probe read 0.1 at 12/120, so
-- the ratio itself was never stuck.
local function breakLeft(uid)
    local cur = stat(uid, PARAM.BREAK, false)
    local maxv = stat(uid, PARAM.BREAK, true)
    if cur ~= nil and maxv ~= nil and maxv > 0 then
        if cur <= 0 then return 0 end
        local r = cur / maxv
        if r > 1 then return 1 end
        return r
    end
    if broken(uid) then return 0 end
    return nil
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
-- CanUnitActivateSkill(unit, actionId, IsItem, hierarchySkills, IsAll) has
-- five arguments (C++ header dump). The two-argument call answers some rows
-- and returns nothing for others, so a sealed skill (Silence) was never seen.
-- The five-argument false is trusted once that call has said true for some
-- row this launch; until then the old two-argument answer stands.
local ACT = { fiveWorks = false }
local function activateFive(bfl, uid, id)
    local ok, v = pcall(function() return bfl:CanUnitActivateSkill(uid, id, false, {}, false) end)
    if ok and type(v) == "boolean" then
        if v then ACT.fiveWorks = true end
        return v
    end
    return nil
end

local function activation(uid, id)
    local bfl = battleLib()
    if not (bfl and bfl:IsValid()) then return nil end
    local five = activateFive(bfl, uid, id)
    if five == true then return true end
    -- In game the five-argument false also means "not enough MP" (probe
    -- v1.3: every false on a costed row was cost over MP; on Escape it was a
    -- boss fight). A short bar is not a seal, so that false is a seal only
    -- when the bar covers the cost.
    if five == false and ACT.fiveWorks then
        local cost = skillCost(uid, id, false) or 0
        local mp = stat(uid, PARAM.MP, false)
        if (cost <= 0) or ((mp ~= nil) and (mp >= cost)) then return false end
        return nil
    end
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
-- Skill math. The skill row names the element. The book fills a missing one.
--------------------------------------------------------------------------------

Known.mobRow = function(enemy)
    if not (Known.unitCards and Fight) then return nil end
    Fight.mobCards = Fight.mobCards or {}
    local seen = Fight.mobCards[enemy.id]
    if seen and seen.name == enemy.name then return seen.card end
    local p = paramOf(enemy.id)
    if not p then return nil end
    local ok, unitId = pcall(function() return num(p:GetUnitId()) end)
    local card = ok and unitId and Known.unitCards[unitId] or nil
    if card then Fight.mobCards[enemy.id] = { name = enemy.name, card = card } end
    return card
end
local unitKit

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
    local power = skill.power or 0
    if power <= 0 and skill.attr == ATTR.FIGHT then power = 18 end
    local br = skill.breakPower or 0
    local info = skill.known or knownOf(skill)
    -- Magnification and breakDamageValue are the whole skill. The hit list
    -- splits that total. A second hit does not repeat the whole number.
    if info and info.stagger then return power, info.stagger end
    return power, br
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

-- The row wins. A book element that disagrees is logged once, then dropped.
local function applyRowElement(copy)
    if not (copy and copy.elementRead) then return end
    local info = copy.known or knownOf(copy)
    local book = info and info.element or nil
    local rowEl = copy.element
    if book and book ~= rowEl then
        Known.elementTold = Known.elementTold or {}
        local key = (copy.name or "?"):lower()
        if not Known.elementTold[key] then
            Known.elementTold[key] = true
            log("element %s: book %s, row %s", copy.name or "?", book, rowEl or "none")
        end
    end
    if info == nil then
        if rowEl then copy.known = { element = rowEl } end
        return
    end
    if info.element == rowEl then return end
    local merged = {}
    for k, v in pairs(info) do merged[k] = v end
    merged.element = rowEl
    copy.known = merged
end

-- The foe's status ids, in order. A learned resist applies only while this
-- list is the one it was filed under. A spell that wears off changes the list.
local function statusStamp(id)
    if not (Fight and id) then return "" end
    Fight.stampCache = Fight.stampCache or {}
    local hit = Fight.stampCache[id]
    if hit ~= nil then return hit end
    local ids = {}
    local ok, set = pcall(statuses, id)
    if ok and set then
        for n in pairs(set) do ids[#ids + 1] = n end
    end
    table.sort(ids)
    local stamp = table.concat(ids, ",")
    Fight.stampCache[id] = stamp
    return stamp
end

-- A kind the card nulls, or one this fight has seen do no damage twice, is
-- a miss, the same as a nulled element. ignoreLearned skips a resist this
-- fight learned, and still honors the foe's own row.
local function elementFactor(skill, enemy, ignoreLearned)
    applyRowElement(skill)
    local ok, factor = pcall(function()
        local info = skill and (skill.known or knownOf(skill))
        local el = info and info.element
        if not enemy then return 1 end
        local card = mobOf(enemy)
        local kind = kindOf(skill)
        if kind then
            if card and card.no and card.no[kind] then return 0 end
            local learned = Fight and Fight.kindNull and Fight.kindNull[enemy.id]
            if (not ignoreLearned) and learned and learned[kind] then return 0 end
        end
        -- A skill this foe took twice for no HP stays off while its status
        -- list is the one those zeros were filed under, the same as a
        -- learned resist. A barrier or a phase that ends changes the list.
        local zero = Fight and Fight.skillZero and Fight.skillZero[enemy.id]
        local rec = zero and skill and skill.id and zero[skill.id]
        if (not ignoreLearned) and (type(rec) == "table") and (rec.n >= 2)
            and (rec.stamp == statusStamp(enemy.id)) then
            return 0
        end
        -- What a hit this fight already showed, whoever swung it. The same
        -- factors as the card: a weakness is 3, a half is 0.5, a null is 0.
        -- A reflect is 0 as well. The foe's status list has to still match.
        if (not ignoreLearned) and Fight and Fight.learned and Known.measure and Known.measure.foeFactor then
            local got = Known.measure.foeFactor(Fight.learned, enemy.id, el, kind, statusStamp(enemy.id))
            if got ~= nil then return got end
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

-- A counter is the enemy's own skill. This fight has not measured a reduction
-- to apply to our stagger, so the row's break stands.
local function counterScale()
    return 1
end

-- A friend id, an ally id, a summoned unit, or a body with no HP is not a foe.
-- The enemy-target list has included the actor. A shared name does not.
-- One plan asks this for the same id many times. The answer is kept until
-- the next plan or the next hit walk.
local foeKeep = {}
local function clearFoeKeep()
    foeKeep = {}
end
local function keepFoe(id)
    if not id or not Fight then return false end
    local kept = foeKeep[id]
    if kept ~= nil then return kept end
    local function drop()
        if Fight.seenFoe then Fight.seenFoe[id] = nil end
        foeKeep[id] = false
        return false
    end
    if Fight.summons and Fight.summons[id] then return drop() end
    if Fight.isSummon and Fight.isSummon(id) then return drop() end
    for _, fid in ipairs(friendIds()) do
        if fid == id then return drop() end
    end
    if Fight.seenAlly and Fight.seenAlly[id] then return drop() end
    local p = paramOf(id)
    if not p then return drop() end
    local r = hpRatio(id)
    if r == nil or r <= 0 then return drop() end
    foeKeep[id] = true
    return true
end
-- No row field says a repeated element shrinks. The break on the skill stands.
local function monoScale()
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
    if skill.effect == EFF.DEFEND or skill.effect == EFF.COVER then return true end
    -- A cut on the user alone that ends at their next action is a guard stance.
    if skill.target == TGT.SELF then
        for _, e in ipairs(skill.effects or {}) do
            if (e.type == EFF.DEFEND) and (e.turns == 1) and ((skill.power or 0) <= 0) then return true end
        end
    end
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

-- Filled gauges, from the live limit points. The unit parameter is the bar
-- the report already follows. The battle library's point read and its gauge
-- count are the same bar when they answer. A 0 from either one does not
-- hide a higher point read, and one empty count does not lock the rest of
-- the launch. IsEnableCommand is only the fallback when none of them answer.
local function limitReady(uid, skill)
    local need = (skill and skill.lbCost) or 1
    if need < 1 then need = 1 end
    local bfl = battleLib()
    local libPoints, one, slots, unitGauges = nil, nil, nil, nil
    if bfl and bfl:IsValid() then
        local ok, v
        ok, v = pcall(function() return bfl:GetUnitLimitBurstPoint(uid) end)
        if ok then libPoints = num(v) end
        ok, v = pcall(function() return bfl:GetLimitBurstPointOneGauge() end)
        if ok then one = num(v) end
        if (one == nil) or (one <= 0) then
            ok, v = pcall(function() return bfl:GetLimitBurstPointOneGauge(uid) end)
            if ok then one = num(v) end
        end
        if Fight and one and (one > 0) then Fight.oneGauge = one end
        ok, v = pcall(function() return bfl:GetLimitBurstPointMaxGaugeNum() end)
        if ok then slots = num(v) end
        if slots == nil then
            ok, v = pcall(function() return bfl:GetLimitBurstPointMaxGaugeNum(uid) end)
            if ok then slots = num(v) end
        end
        ok, v = pcall(function() return bfl:GetUnitLimitBurstPointGaugeNum(uid) end)
        if ok then unitGauges = num(v) end
    end
    local paramPoints = nil
    local p = paramOf(uid)
    if p then
        local ok, v = pcall(function() return p:GetLimitBurstPoint() end)
        if ok then paramPoints = num(v) end
    end
    local statPoints = stat(uid, PARAM.LB, false)
    local maxv = stat(uid, PARAM.LB, true)
    local points = nil
    for _, v in ipairs({ libPoints, paramPoints, statPoints }) do
        if (v ~= nil) and ((points == nil) or (v > points)) then points = v end
    end
    local filled = Limits.filled and Limits.filled(points, one, maxv, unitGauges, slots) or nil
    if Fight then
        Fight.lbBar = Fight.lbBar or {}
        Fight.lbBar[uid] = {
            filled = filled,
            max = Limits.capacity and Limits.capacity(one, maxv, slots) or nil,
        }
        Fight.lbRead = Fight.lbRead or {}
        local bucket = filled
        if (bucket == nil) and (points ~= nil) then bucket = math.floor(points) end
        local prev = Fight.lbRead[uid]
        if prev ~= bucket then
            Fight.lbRead[uid] = bucket
            log("%s limit bar stat %s lib %s param %s max %s one %s slots %s count %s filled %s needs %s",
                unitName(uid), tostring(statPoints), tostring(libPoints), tostring(paramPoints),
                tostring(maxv), tostring(one), tostring(slots), tostring(unitGauges),
                tostring(filled), tostring(need))
        end
        if (filled ~= nil) and (filled >= need) then
            Fight.lbTold = Fight.lbTold or {}
            local told = tostring(uid) .. ":" .. tostring(need)
            if not Fight.lbTold[told] then
                Fight.lbTold[told] = true
                appendLog("  " .. unitName(uid) .. " limit ready, gauges " .. tostring(need))
            end
        end
    end
    if filled == nil then return commandEnabled(uid, skill.id) end
    return filled >= need
end

-- borrowed: true asks the game if this unit can activate a row it hasn't equipped.
-- "inherited": a multicast row, already cleared by its base spell's checks.
local function tagSkill(uid, id, borrowed)
    if (borrowed == true) and activation(uid, id) ~= true then return nil end
    local s = skillOf(id)
    if not s or SKIP[s.attr] then return nil end
    -- EsperLevelGap -1: no Esper is ever called. The player can still call one by hand.
    if s.attr == ATTR.SUMMON and (tonumber(cfg.EsperLevelGap) or 0) < 0 then return nil end
    local lb = limitSkill(s)
    if not borrowed and sealed(uid, id) and not lb then return nil end
    local copy = {}
    for k, v in pairs(s) do copy[k] = v end
    copy.known = knownOf(copy)
    applyRowElement(copy)
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
    if info and info.use == "skip" then return nil end
    if limitSkill(copy) then
        local gauges = nil
        if info and Limits.gauges then
            local pts = info.points
            if type(pts) ~= "number" then
                local book = tonumber(info.gauges)
                if book and (book >= 1) then pts = book * 100 end
            end
            local one = Fight and Fight.oneGauge or nil
            if (not one) or (one <= 0) then
                local bfl = battleLib()
                if bfl and bfl:IsValid() then
                    local ok, v = pcall(function() return bfl:GetLimitBurstPointOneGauge() end)
                    if ok then one = num(v) end
                    if (not one) or (one <= 0) then
                        ok, v = pcall(function() return bfl:GetLimitBurstPointOneGauge(uid) end)
                        if ok then one = num(v) end
                    end
                end
                if Fight and one and (one > 0) then Fight.oneGauge = one end
            end
            gauges = Limits.gauges(pts, one)
        end
        if (gauges == nil) and info and (type(info.gauges) == "number") and (info.gauges >= 1) then
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
                local line = string.format("limit row %s on %s: use %s, role %s, gauges %s, kind %s, effect %s, target %s",
                    (copy.name and copy.name ~= "") and copy.name or ("#" .. tostring(id)), unitName(uid),
                    tostring(info and info.use or "none"), tostring(info and info.role or "none"), tostring(gauges), tostring(copy.kind),
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
                if copy.kind == "heal" or (info and info.use == "heal") then score = 1 + (copy.power or 0) end
                if score > kit.healScore then kit.healScore = score end
                if copy.kind == "heal" and score > 0 and (copy.cost or 0) > 0 then
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
            if s.attr == ATTR.FIGHT and activation(uid, id) == true then
                local copy = tagSkill(uid, id, true)
                if copy and ((not copy.known) or (copy.known.use ~= "skip")) then
                    kit.spells[#kit.spells + 1] = copy
                    break
                end
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
    -- A self row is the caster. Aiming it at a foe is not a legal command.
    if skill.target == TGT.SELF then return { uid }, false end
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

-- True when a hit already recorded this fight would drop this ally.
local function allyExposed(a)
    if not a or a.dead or not Fight then return false end
    local hp = stat(a.id, PARAM.HP, false)
    if not hp or hp <= 0 then return false end
    local worst = 0
    for fid, foe in pairs(Fight.hitSeen or {}) do
        if keepFoe(fid) then
            for _, sk in pairs(foe) do
                local n = sk.fullTo and sk.fullTo[a.id]
                if n and n > worst then worst = n end
            end
        end
    end
    return worst > 0 and hp <= worst
end

local function markExposed(w)
    for _, a in ipairs((w and w.allies) or {}) do
        a.exposed = allyExposed(a) or nil
    end
end

-- A foe with a move the game lists as dangerous, or a hit this fight has
-- shown would kill an ally. IsBoss is a field the game stores. It is not
-- this.
local function hardFight(w)
    local hard = false
    for _, u in ipairs(w.enemies or {}) do
        local card = mobOf(u)
        if card and card.danger and card.danger[1] then hard = true end
    end
    for _, a in ipairs(w.allies or {}) do
        if a.exposed then hard = true end
    end
    w.hard = hard
    return hard
end

-- Every foe here has only moves that can't hurt anyone, so nothing is worth an item.
local function potFight(w)
    local any = false
    for _, u in ipairs(w.enemies or {}) do
        local card = mobOf(u)
        if not (card and card.harmless) then return false end
        any = true
    end
    if not any then return false end
    if not potLogged then
        potLogged = true
        log("no foe here can hurt the party: leaving items for you")
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
            local f = { rare = row and row.rare or nil, held = row and row.held or nil }
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
    markExposed(w)
    hardFight(w)
    local dire = (Health.direNeed and Health.direNeed(w)) and true or false
    local function tagged(choice, rare)
        if choice and rare then choice.reason = choice.reason .. " (rare)" end
        return choice
    end
    if want == "revive" then
        local dead = (Health.fallen and Health.fallen(w.allies, unitKit, offenseOf, raiseOrder()))
            or firstDead(w, function(u) return u.acts ~= false end) or firstDead(w)
        if not dead then return nil end
        local it, rare = Items.recovery(owned, "revive", { boss = hardFight(w) })
        if it then return tagged(itemChoice(uid, it, "item raise " .. dead.name, dead.id, "revive"), rare) end
        return nil
    end
    if want == "heal" then
        -- The ally the heal was chosen for, when the caller names one. The
        -- lowest ally instead skipped the kill-range marks and the 65% guard
        -- that cleared the named one (a second Potion at 71% in the sim).
        local hurt = (focus and focus.who) or lowestAlly(w)
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
                if a.exposed then hurtN = hurtN + 1 end
            end
        end
        local need = Health.partyNeed and Health.partyNeed(#living) or 3
        local it, rare = Items.recovery(owned, "heal", {
            boss = hardFight(w), missing = missing, dire = dire,
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
                    Fight.claim.itemHeal = Fight.claim.itemHeal or {}
                    for _, id in ipairs(living) do
                        Fight.claim.heal[id] = true
                        Fight.claim.itemHeal[id] = true
                    end
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
            boss = hardFight(w), list = focus and focus.list, landing = focus and focus.landing,
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
        local mpNow, mpMax = stat(uid, PARAM.MP, false), stat(uid, PARAM.MP, true)
        local short = (mpNow and mpMax and (mpMax > mpNow)) and (mpMax - mpNow) or nil
        local it, rare = Items.recovery(owned, "mp", { boss = hardFight(w), dire = dire, missing = short })
        if it then return tagged(itemChoice(uid, it, "ether " .. unitName(uid), uid, "mp"), rare) end
    end
    return nil
end

--------------------------------------------------------------------------------
-- The field. The live BreakPoint is the gauge. The book is the fallback.
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
        if apiLeft ~= nil then
            -- The live gauge is the break and the recovery. A reading above
            -- empty, with status 89 gone, is no longer broken.
            local stillBroken = statuses(id)[ST_BREAK] and true or false
            if Fight and (not unmarked) and (apiLeft <= 0.001) then
                Fight.down[id] = true
                Fight.brokeOn = Fight.brokeOn or {}
                Fight.brokeOn[id] = true
                down = true
                if not Fight.downSince then Fight.downSince = #(Fight.actions or {}) end
            elseif Fight and (apiLeft > 0.001) and (not stillBroken) then
                Fight.down[id] = nil
                Fight.downTold[id] = nil
                down = false
            end
            if stillBroken then down = true end
        elseif (not unmarked) and Fight and gauge and (gauge > 0) and (poured >= gauge) and (not relaxed) then
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
        local left = 1
        if down then
            left = 0
        elseif apiLeft ~= nil then
            left = apiLeft
        elseif (not unmarked) and gauge and (gauge > 0) then
            local est = 1 - (poured / gauge)
            if est < 0 then est = 0 end
            if est > 1 then est = 1 end
            if relaxed and poured >= gauge then est = 0.15 end
            left = est
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
        -- The party is on the field when the fight begins. A friend the summon
        -- row names by unit id, or one that arrives as that call, is a summon:
        -- it is not healed, raised, counted, or waited on, and it stays one
        -- for the fight.
        Fight.summons = Fight.summons or {}
        local party = {}
        local live = false
        for _, a in ipairs(allies) do
            if Fight.isSummon then Fight.isSummon(a.id, a.name) end
            if Fight.summons[a.id] then
                if not a.dead then live = true end
            else
                party[#party + 1] = a
            end
        end
        -- The friend list can omit the unit for the whole call. A living
        -- body this call put down is still on the field. An unsummon ends it
        -- even if that body's points have not reached 0 yet.
        local function hpUp(id)
            local cur = stat(id, PARAM.HP, false)
            return (cur ~= nil) and (cur > 0)
        end
        local mark = Fight.esperOut
        if mark and mark.left then
            live = false
        elseif not live then
            for id in pairs(Fight.summons) do
                if hpUp(id) then live = true break end
            end
            local bfl = battleLib()
            if (not live) and mark and bfl and bfl:IsValid() then
                for n = 0, 15 do
                    if not (Fight.openIds and Fight.openIds[n]) then
                        local okP, p = pcall(function() return bfl:GetBattleUnitParameter(n, true) end)
                        if okP and p and p.IsValid and p:IsValid() and hpUp(n) then
                            local catalog = nil
                            local okC, got = pcall(function() return p:GetUnitId() end)
                            if okC then catalog = num(got) end
                            local byUnit = mark.unit and catalog and (catalog == mark.unit)
                            local filed = Fight.seenFoe and Fight.seenFoe[n]
                            local byName = mark.name and (unitName(n) == mark.name) and not filed
                            if byUnit or byName then
                                if Fight.isSummon then Fight.isSummon(n, unitName(n)) end
                                live = true
                                break
                            end
                        end
                    end
                end
            end
        end
        Fight.summonLive = live
        -- Seen from a scan that found the unit up. A one-off id during the
        -- summon command is not the unit leaving on the next turn.
        if live and Fight.esperOut then Fight.esperOut.seen = true end
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
        if Growth.enemy then Growth.enemy(id) end
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
    pace = { held = nil, applied = nil, last = nil, guard = 0, marks = nil, command = nil, fast = nil, scene = false, fail = false, lib = nil,
        -- waitFirst: Turbo stays off until the fight's opening is over. A
        -- turn the game sent by itself at the start of a fight plays at the
        -- game's own speed. armed is when the wait ends. See Menu.armPace.
        -- TUNE: set waitFirst false to test the old start, where Turbo began
        -- the moment the mod saw the fight.
        waitFirst = true, armed = false,
        -- seqHook: hook SetSequenceGameSpeed. See Menu.hookPace.
        seqHook = false },
}

function Menu.paceLib()
    local lib = Menu.pace.lib
    if lib and lib.IsValid and lib:IsValid() then return lib end
    local found = StaticFindObject("/Script/Engine.Default__GameplayStatics")
    if found and found.IsValid and found:IsValid() then
        Menu.pace.lib = found
        return found
    end
    return nil
end

-- The world the player is in. FindFirstOf("World") can return a world that is
-- not the one on screen, so a speed written there never reaches the field.
function Menu.paceWorld()
    local ok, world = pcall(function()
        local pc = FindFirstOf("PlayerController")
        if pc and pc.IsValid and pc:IsValid() then return pc:GetWorld() end
        return nil
    end)
    if ok and world and world.IsValid and world:IsValid() then return world end
    ok, world = pcall(function() return FindFirstOf("World") end)
    if ok and world and world.IsValid and world:IsValid() then return world end
    return nil
end

function Menu.worldSettings()
    local world = Menu.paceWorld()
    if world then
        local ok, settings = pcall(function() return world:K2_GetWorldSettings() end)
        if ok and settings and settings.IsValid and settings:IsValid() then return settings end
    end
    local ok, settings = pcall(function() return FindFirstOf("WorldSettings") end)
    if ok and settings and settings.IsValid and settings:IsValid() then return settings end
    return nil
end

function Menu.dilation()
    local lib = Menu.paceLib()
    local world = Menu.paceWorld()
    if lib and world then
        local ok, got = pcall(function() return lib:GetGlobalTimeDilation(world) end)
        if ok and tonumber(got) then return tonumber(got) end
    end
    local settings = Menu.worldSettings()
    if settings then return num(settings.TimeDilation) end
    return nil
end

function Menu.setDilation(rate)
    local function close(now)
        return now and (math.abs(now - rate) < 0.01)
    end
    local lib = Menu.paceLib()
    local world = Menu.paceWorld()
    if lib and world then
        pcall(function() lib:SetGlobalTimeDilation(world, rate) end)
        if close(Menu.dilation()) then return true end
    end
    local settings = Menu.worldSettings()
    if not settings then return false end
    local ok = pcall(function() settings.TimeDilation = rate end)
    return ok and close(num(settings.TimeDilation))
end

function Menu.readMarks()
    if Menu.pace.fast then return true end
    local bfl = battleLib()
    if not (bfl and bfl.IsValid and bfl:IsValid()) then return false end
    local data = nil
    local ok, got = pcall(function()
        local holder = {}
        bfl:GetBattleGeneralData(holder)
        return holder
    end)
    if ok and type(got) == "table" then data = got end
    if not data then
        ok, got = pcall(function() return bfl:GetBattleGeneralData() end)
        if ok then data = got end
    end
    if not data then return false end
    local command = num(field(data, "CommandSelectGameSpeed"))
    local list = field(data, "GameSpeedList")
    local marks = {}
    if list and list.ForEach then
        pcall(function()
            list:ForEach(function(_, v)
                local n = num(v)
                if n and (n > 0) then marks[#marks + 1] = n end
            end)
        end)
    elseif type(list) == "table" then
        for _, v in ipairs(list) do
            local n = num(v)
            if n and (n > 0) then marks[#marks + 1] = n end
        end
    end
    local fast = Known.pace and Known.pace.fastest(marks)
    if not fast then return false end
    Menu.pace.marks = marks
    Menu.pace.command = command
    Menu.pace.fast = fast
    return true
end

-- The opening is over: the planner sent its first command, or a command
-- menu opened after the fight was set up. The game's own Auto can take the
-- first turn (an Esuna after an opening blind) before the mod sees the fight,
-- and that turn crashed the game under Turbo.
function Menu.armPace(why)
    if Menu.pace.armed or not cfg.Turbo then return end
    Menu.pace.armed = true
    Menu.pace.retaken, Menu.pace.seen, Menu.pace.since = 0, nil, os.time()
    log("turbo armed by %s", why)
end

function Menu.applyPace(rate)
    if Menu.pace.applied == rate then return end
    -- Before the call, so a crash inside it still leaves this line.
    log("turbo setting %s", tostring(rate))
    -- held marks that turbo changed the speed. Outside a fight the speed is
    -- always 1, so the end of a fight puts back 1, not whatever was read
    -- at the start: that read could be the game's own battle speed.
    Menu.pace.held = true
    if Menu.setDilation(rate) then
        -- Each change of speed, so a crash log shows what turbo did last.
        local why = (Menu.pace.scene == true and "scene held") or (Menu.open == true and "command menu") or "actions"
        log("turbo set %s for %s (was %s, boss %s)", tostring(rate), why, tostring(Menu.pace.applied),
            tostring(Fight and Fight.boss))
        Menu.pace.applied = rate
        Menu.pace.last = rate
        return
    end
    if not Menu.pace.fail then
        Menu.pace.fail = true
        log("turbo failed: could not set the battle speed")
    end
end

function Menu.restorePace()
    local pace = Menu.pace
    if pace.held == nil then
        -- After a fight, a rate turbo set is put back to 1 if it shows up
        -- again. Only turbo's own last rate is undone, so a speed the game
        -- sets on the field is left alone.
        if pace.guard and pace.guard > 0 then
            pace.guard = pace.guard - 1
            local now = Menu.dilation()
            if now and pace.last and (math.abs(now - pace.last) < 0.01) and (math.abs(now - 1) >= 0.01) then
                Menu.setDilation(1)
            end
            if pace.guard == 0 then pace.last = nil end
        end
        return
    end
    if not Menu.setDilation(1) then
        if not pace.fail then
            pace.fail = true
            log("turbo failed: could not restore the battle speed")
        end
        return
    end
    log("turbo set 1 to restore (was %s)", tostring(pace.applied))
    pace.held, pace.applied = nil, nil
    -- About five seconds of the pace loop.
    pace.guard = 300
end

-- The result is the end of the fight. The story after it is not a battle.
function Menu.stopPace()
    if not Menu.pace.done then
        Menu.pace.done = true
        Menu.pace.scene = false
        if cfg.Turbo then
            Menu.tellRetaken()
            log("turbo off")
        end
    end
    Menu.restorePace()
end

function Menu.keepPace()
    if Menu.pace.done or (not cfg.Turbo) or not (Fight and Fight.active) then
        Menu.restorePace()
        return
    end
    if not Known.pace then return end
    if Menu.pace.waitFirst and not Menu.pace.armed then return end
    if not Menu.readMarks() then
        if not Menu.pace.fail then
            Menu.pace.fail = true
            log("turbo failed: the battle speed marks were not read")
        end
        return
    end
    local rate = Known.pace.rate(Menu.pace.marks, Menu.pace.command, Menu.open == true, Menu.pace.scene == true)
    if not rate then return end
    if (Menu.pace.applied == rate) and Known.pace.taken then
        local now = Menu.dilation()
        if Known.pace.taken(now, rate) then
            -- Quiet on purpose: this can run many times a fight. The count
            -- and the speeds the game wrote go to the log when the fight ends.
            local pace = Menu.pace
            pace.retaken = (pace.retaken or 0) + 1
            pace.seen = pace.seen or {}
            local key = string.format("%.2f", now)
            pace.seen[key] = (pace.seen[key] or 0) + 1
            if not Menu.setDilation(rate) then pace.applied = nil end
            return
        end
    end
    Menu.applyPace(rate)
end

-- How often the game put its own speed back while turbo held a rate. A count
-- near once per tick means the game writes the speed every frame.
function Menu.tellRetaken()
    local pace = Menu.pace
    if (pace.retaken or 0) > 0 then
        local parts = {}
        for k, v in pairs(pace.seen or {}) do parts[#parts + 1] = string.format("%s x%d", k, v) end
        table.sort(parts)
        local secs = pace.since and (os.time() - pace.since) or nil
        log("turbo took the speed back %d times in %s s; the game wrote %s", pace.retaken,
            secs and string.format("%.0f", secs) or "?", table.concat(parts, ", "))
    end
    pace.retaken, pace.seen, pace.since = 0, nil, nil
end

-- A battle-speed mark on a sequence would stack on the world rate.
-- Slows, including the command menu and a hit pause, stay as the game set them.
function Menu.hookPace()
    if not cfg.Turbo then return end
    -- Each hook is registered on its own, so a missing function does not take
    -- the result hooks down with it. That is what kept turbo on through the
    -- result screen: the speed hook failed first and the rest never ran.
    local function hook(label, paths, fn)
        local last = nil
        for _, path in ipairs(paths) do
            local ok, err = pcall(RegisterHook, path, fn)
            if ok then return true end
            last = err
        end
        log("turbo failed: %s: %s", label, tostring(last))
        return false
    end
    -- An object path names a class without its A prefix.
    -- TUNE: off to test the boss-start crash. Four crashes came with this hook
    -- live and Turbo setting no speed, and the hook never logged a change.
    -- Off, a sequence's own battle-speed mark can stack on the Turbo rate.
    if Menu.pace.seqHook then hook("sequence speed", {
        "/Script/mucha.CPP_BtlGameSpeedManager:SetSequenceGameSpeed",
        "/Script/mucha.ACPP_BtlGameSpeedManager:SetSequenceGameSpeed",
    }, function(_, dilation)
        if not (cfg.Turbo and Fight and Fight.active and (not Menu.pace.done) and (not Menu.open) and (not Menu.pace.scene)) then return end
        local fast = Menu.pace.fast
        local d = num(dilation and dilation:get())
        if not fast or not d then return end
        if (d >= 1) and (d <= (fast + 0.01)) then
            -- Logged once per new value, not on every call.
            if Menu.pace.seqTold ~= d then
                Menu.pace.seqTold = d
                log("turbo held a sequence speed of %s at 1", tostring(d))
            end
            dilation:set(1)
        end
    end) end
    -- Win or loss. Either way the actions are over, and a story scene may follow.
    hook("result begin", { "/Script/mucha.CPP_UI_BattleSubsystem:HandleBeginResult" }, function()
        Menu.stopPace()
    end)
    hook("result end", { "/Script/mucha.CPP_BtlDelEventResult:OnExecuteResultEnd" }, function()
        Menu.stopPace()
    end)
end

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
    claim = { heal = {}, cure = {}, revive = {}, hone = {}, ether = {}, scan = {}, kit = {}, etherRound = false, guard = false, esper = false, lb = false },
    debuffOn = {}, debuffSeen = {}, debuffTold = {},
    went = {}, rounds = 0, seenFoe = {}, planTag = nil, afterBonus = false,
    fieldTold = false, chipped = false,
    esperOut = nil, esperTold = false, esperSkip = {}, summonLive = false,
    limitUntagged = {}, limitSkip = {},
    cureHeld = false,
    healLeft = {},
    statusTold = {},
    slowSince = {}, slowTry = nil, slowTold = {}, slowUsed = {},
    underLine = false,
}

-- The catalog id on a battle unit. The summon row stores the same id.
local function catalogOf(id)
    local function from(p)
        if not (p and p.IsValid and p:IsValid()) then return nil end
        local ok, v = pcall(function() return p:GetUnitId() end)
        return ok and num(v) or nil
    end
    local found = from(paramOf(id))
    if found then return found end
    local bfl = battleLib()
    if not (bfl and bfl:IsValid()) then return nil end
    local ok, p = pcall(function() return bfl:GetBattleUnitParameter(id, false) end)
    if ok then return from(p) end
    return nil
end

-- Levels for EsperLevelGap, read the way LevelGate reads them. The live
-- level parameter reads -1 on allies, so it is not used. An ally's level
-- comes from its playable unit; a foe's from its catalog row.
function Known.allyLevel(uid)
    local lib = Known.levelLib
    if not (lib and lib:IsValid()) then
        lib = StaticFindObject("/Script/mucha.Default__CPP_BFL_Unit")
        Known.levelLib = lib
    end
    local unitId = catalogOf(uid)
    if not (unitId and lib and lib:IsValid()) then return nil end
    local ok, v = pcall(function() return lib:GetPlayableUnitLevel(unitId) end)
    v = ok and num(v) or nil
    if v and v > 0 then return v end
    return nil
end
function Known.foeLevel(uid)
    local row = Known.growth and Known.growth[catalogOf(uid)]
    return row and type(row.level) == "number" and row.level or nil
end

-- The summon test, wherever the party is read. See worldOf.
Fight.isSummon = function(id, name)
    Fight.summons = Fight.summons or {}
    if not id then return false end
    local function take(catalog)
        Fight.summons[id] = true
        if Fight.seenAlly then Fight.seenAlly[id] = nil end
        -- A scan that filed this unit as an enemy does not keep that label.
        if Fight.seenFoe then Fight.seenFoe[id] = nil end
        local mark = Fight.esperOut
        if mark and (not mark.who) then
            mark.who = id
            if catalog and (not mark.unit) then mark.unit = catalog end
        end
        return true
    end
    if Fight.summons[id] then return take(catalogOf(id)) end
    local body = paramOf(id)
    if not body then
        local bfl = battleLib()
        if bfl and bfl:IsValid() then
            local okBody, q = pcall(function() return bfl:GetBattleUnitParameter(id, false) end)
            if okBody and q and q.IsValid and q:IsValid() then body = q end
        end
    end
    -- The catalog id is what the summon row stores. Relation is this scan only.
    local catalog = catalogOf(id)
    local mark = Fight.esperOut
    local called = mark and mark.unit and catalog and (catalog == mark.unit)
    if body then
        local okRel, rel = pcall(function() return body:GetRelation() end)
        if okRel and (num(rel) == REL.ENEMY) then
            -- The unit this call put on the field can show up on the enemy
            -- list when the friend list misses it. That body is still the
            -- call. An enemy already filed, or a second body with the same
            -- row, stays an enemy.
            local already = Fight.seenFoe and Fight.seenFoe[id]
            local bound = mark and mark.who and (mark.who ~= id)
            local calledName = mark and mark.name and ((name or unitName(id)) == mark.name)
            if (called or calledName) and not already and not bound then return take(catalog) end
            return false
        end
    end
    -- Whoever was here when the fight opened is the party.
    if Fight.openIds and Fight.openIds[id] then return false end
    local listed = catalog and Espers.isUnit and Espers.isUnit(catalog)
    if called or listed then return take(catalog) end
    -- The unit id could not be read. A friend who was not here at the start,
    -- while a call is still waiting, is the unit that call put on the field.
    local friend = false
    if (not catalog) and mark and (not mark.seen) and Fight.openIds
        and not (Fight.seenAlly and Fight.seenAlly[id]) then
        for _, fid in ipairs(friendIds()) do
            if fid == id then friend = true break end
        end
    end
    if friend and not (Fight.unitDown and Fight.unitDown(id)) then return take(nil) end
    if (not Fight.openIds) or (Fight.seenAlly and Fight.seenAlly[id]) then return false end
    local esper = Espers.lookup and Espers.lookup(name or unitName(id))
    if esper then return take(catalog) end
    -- No skill list, and the Esper rows were not loaded: the only signal left.
    if (not (Espers.loaded and Espers.loaded())) and (#equippedIds(id) == 0) then
        return take(catalog)
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
    -- A multicast goes out as its own row, under the base spell's menu and keys.
    local row = (not choice.isItem) and skillOf(choice.id) or nil
    local menuId = (row and row.multicastOf) or choice.id
    local learned = (not choice.isItem) and (Template[choice.id] or Template[menuId]) or nil
    local cmdType = phase
    local commandId = menuId
    local isNotConsume, doCalcOrder = false, true
    local pCat, pId = 1, menuId
    local keys = { { 1, menuId } }
    if menuId ~= choice.id then
        log("multicast %s: id %d under %d, %s, targets %d", tostring(choice.name), choice.id, menuId, learned and "learned shape" or "plain shape", #(choice.targets or {}))
    end
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
            local ok, enabled = pcall(function() return bfl:IsEnableCommand(uid, menuId) end)
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
        if copy then
            usable[#usable + 1] = copy
            -- The spell's "All" target is another choice. It needs what the spell
            -- needs, so a seal on the spell covers it too.
            if copy.multicast then
                local twin = tagSkill(uid, copy.multicast, "inherited")
                if twin then usable[#usable + 1] = twin end
            end
        end
    end
    local haveFight = false
    for _, s in ipairs(usable) do
        if s.attr == ATTR.FIGHT then haveFight = true end
    end
    if not haveFight and SkillIdx then
        for id, s in pairs(SkillIdx) do
            if s.attr == ATTR.FIGHT and activation(uid, id) == true then
                local copy = tagSkill(uid, id, true)
                if copy and ((not copy.known) or (copy.known.use ~= "skip")) then
                    usable[#usable + 1] = copy
                    break
                end
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
    local hurt, care = nil, false
    for _, u in ipairs(w.allies or {}) do
        if u.dead then
            care = true
        elseif not hurt or (u.hp or 1) < (hurt.hp or 1) then
            hurt = u
        end
        if allyExposed(u) then care = true end
    end
    local function emit(skill, reason, targets, isAll, score)
        local choice = finishChoice(uid, skill, reason, targets, isAll)
        if choice then choice.score = score end
        return choice
    end
    local function rowScore(s)
        local support = s.kind == "heal" or s.kind == "buff" or s.kind == "revive"
            or (s.known and (s.known.use == "heal" or s.known.use == "buff" or s.known.use == "guardbuff"))
        if support then return nil end
        local pow = offenseOf(s)
        local foes = w.enemies or {}
        if #foes == 0 then return pow end
        local factor = nil
        -- The wheel is one throw. A null learned from misses this fight can be
        -- wrong, so only the enemy's card rules a finisher out.
        -- TUNE: if fights show Resonances thrown into enemies that block
        -- them, let the learned nulls count here too.
        for _, u in ipairs(foes) do
            local f = elementFactor(s, u, true)
            if f > 0 and (not factor or f > factor) then factor = f end
        end
        if not factor then return nil end
        return pow * ((factor >= 3) and 1.5 or factor)
    end
    -- For the wheel's log line. A heal below returns before the damage loop.
    for _, s in ipairs(list) do
        local okR, r = pcall(rowScore, s)
        s.wheelScore = okR and r or nil
    end
    if care then
        for _, s in ipairs(list) do
            local heal = s.kind == "heal" or s.kind == "revive" or (s.known and s.known.use == "heal")
            if heal then
                local who = hurt or (w.allies and w.allies[1])
                local targets = partyOf(s) and idsOf(w.allies) or { who and who.id or uid }
                local choice = emit(s, "resonance heal " .. ((who and who.name) or "ally"), targets, partyOf(s), 1)
                if choice then return choice end
            end
        end
    end
    local best, bestR = nil, -1
    for _, s in ipairs(list) do
        local r = rowScore(s)
        if r and r > bestR then best, bestR = s, r end
    end
    -- The card says no finisher lands. The wheel waits for a pick, and the
    -- card has been wrong before, so the strongest finisher goes anyway. It
    -- scores below any finisher that lands, so it never beats one.
    -- TUNE: if fights show these throws doing nothing, skip the wheel
    -- instead. Skip is the B button; the mod has no way to send it yet.
    local forced = false
    if not best then
        local pow = -1
        for _, s in ipairs(list) do
            local okP, p = pcall(offenseOf, s)
            p = (okP and type(p) == "number") and p or 0
            if s.kind == "heal" or s.kind == "buff" or s.kind == "revive" then p = -0.5 end
            if (not best) or p > pow then best, pow = s, p end
        end
        if not best then return nil end
        forced, bestR = true, -1
    end
    local support = best.kind == "heal" or best.kind == "buff" or best.kind == "revive"
    local foe = nil
    for _, u in ipairs(w.enemies or {}) do
        if (forced or elementFactor(best, u, true) > 0) and (not foe or (u.hp or 1) < (foe.hp or 1)) then foe = u end
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
    if forced then name = name .. " (no finisher lands, sent anyway)" end
    return emit(best, "resonance " .. name, targets, isAll, bestR)
end

-- The Vision a character has equipped. 4 is eEquipmentType.Vision, 0 its slot.
local function visionIdOf(uid)
    local p = paramOf(uid)
    if not p then return nil end
    local ok, v = pcall(function() return p:GetEquipmentId(4, 0) end)
    local id = ok and num(v) or nil
    if id and id > 0 then return id end
    return nil
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
        applyRowElement(copy)
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
        local vision = visionIdOf(who)
        return vision and visionFinishMap()[vision] or nil
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
    -- A Vision not read is no row: the wheel is left for the player.
    return out
end

local function markDebuff(id, effect, statusIds)
    if (not id) or (not effect) or (effect == "") then return end
    Fight.debuffOn = Fight.debuffOn or {}
    local row = Fight.debuffOn[id]
    if not row then
        row = {}
        Fight.debuffOn[id] = row
    end
    row[effect] = true
    -- The statuses this cast's row lists are how a later sighting is read.
    Fight.debuffIds = Fight.debuffIds or {}
    Fight.debuffIds[id] = Fight.debuffIds[id] or {}
    Fight.debuffIds[id][effect] = statusIds
    -- A fresh cast has not been seen yet. Clearing the old sighting
    -- stops a refresh from repeating until the status is back, then gone.
    if Fight.debuffSeen and Fight.debuffSeen[id] then
        Fight.debuffSeen[id][effect] = nil
    end
end

local readRisk
local applyPendingOrder
-- The warning list is a living foe whose next slot will hit the party.
-- Slots before that body pour book stagger, weakness at x3 and nothing
-- past that. The slot is spent on the body only when that sum clears the
-- live gauge. Otherwise the slot guards, heals ahead, or defends.
local function warnTurn(uid, skills, w, phase, pay, isHit, isPatch, held)
    if phase ~= 0 then return nil end
    if not Fight then return nil end
    if readRisk then readRisk() end
    local function heldOut(a)
        if (not a) or (a.id == uid) or (not Health.OUT) or (not a.statuses) then return false end
        for sid in pairs(Health.OUT) do
            if a.statuses[sid] then return true end
        end
        return false
    end
    local function idxOf(list, id)
        for i, v in ipairs(list or {}) do
            if v == id then return i end
        end
        return nil
    end
    local function partySlot(id)
        if (not id) or (id < 0) then return false end
        if Fight.isSummon and Fight.isSummon(id) then return false end
        for _, a in ipairs(w.allies) do
            if a.id == id then
                if a.dead or (a.acts == false) or heldOut(a) then return false end
                return true
            end
        end
        return false
    end
    local function foeById(id)
        for _, u in ipairs(w.enemies) do
            if u.id == id then return u end
        end
        return nil
    end
    local order = Fight.order or {}
    local cur = order.current or {}
    local nxt = order.next or {}
    local function slotsFor(foeId)
        local slots = {}
        local function add(id)
            if partySlot(id) then slots[#slots + 1] = id end
        end
        local at = idxOf(cur, foeId)
        if at then
            for i = 1, at - 1 do add(cur[i]) end
            if partySlot(uid) and (not idxOf(cur, uid)) then slots[#slots + 1] = uid end
            return slots, true
        end
        local atNext = idxOf(nxt, foeId)
        if not atNext then return nil, false end
        for _, id in ipairs(cur) do add(id) end
        if partySlot(uid) and (not idxOf(cur, uid)) then add(uid) end
        for i = 1, atNext - 1 do add(nxt[i]) end
        return slots, false
    end
    local best, bestSlots, bestN, bestCur = nil, nil, nil, false
    for _, id in ipairs(Fight.risk or {}) do
        local foe = foeById(id)
        local rec = Fight.warn and Fight.warn[id]
        -- reached: this warning's slot already arrived. The list stays up
        -- through the hit and clears on the following turn.
        if foe and keepFoe(id) and (not foe.broken) and (not broken(id)) and not (rec and rec.reached) then
            local leftNow = stat(id, PARAM.BREAK, false)
            if (type(leftNow) ~= "number") or (leftNow > 0.001) then
                local slots, inCur = slotsFor(id)
                if slots then
                    local n = #slots
                    local take = (not best) or (inCur and (not bestCur)) or ((inCur == bestCur) and (n < bestN))
                    if take then
                        best, bestSlots, bestN, bestCur = foe, slots, n, inCur
                    end
                end
            end
        end
    end
    if not best then return nil end
    local left = stat(best.id, PARAM.BREAK, false)
    local maxv = stat(best.id, PARAM.BREAK, true)
    local function pourOf(allyId)
        local spells = skills
        if allyId ~= uid then
            local kit = unitKit(allyId)
            spells = (kit and kit.spells) or {}
        end
        local mp = (allyId == uid) and (w.mp or 0) or (stat(allyId, PARAM.MP, false) or 0)
        local bestP = 0
        for _, s in ipairs(spells) do
            if isHit(s, false) and ((s.cost or 0) <= mp) and (s.attr ~= ATTR.SUMMON) and not (held and held(s)) then
                local f = elementFactor(s, best)
                if f < 0 then f = 0 end
                if f > 3 then f = 3 end
                local _, br = offenseOf(s)
                local pour = (br or 0) * f
                if pour > bestP then bestP = pour end
            end
        end
        return bestP
    end
    local sum = 0
    for _, id in ipairs(bestSlots) do
        sum = sum + pourOf(id)
    end
    local function say(tail)
        local ltxt = (type(left) == "number") and tostring(math.floor(left + 0.5)) or "?"
        local mtxt = (type(maxv) == "number") and tostring(math.floor(maxv + 0.5)) or "?"
        local line = string.format("warned: %s slot in %d, gauge %s/%s, %s", best.name, bestN, ltxt, mtxt, tail)
        log("%s", line)
        appendLog("  " .. line)
    end
    local canBreak = (type(left) == "number") and (left > 0.001) and ((sum + 0.001) >= left)
    if canBreak then
        local hit, hitWeak, hitBr = nil, false, -1
        for _, s in ipairs(skills) do
            if isHit(s, false) and pay(s) and (s.attr ~= ATTR.SUMMON) and not (held and held(s)) then
                local f = elementFactor(s, best)
                if f > 0 then
                    local _, br = offenseOf(s)
                    br = br or 0
                    local weak = (f >= 3)
                    if (not hit) or (weak and (not hitWeak)) or ((weak == hitWeak) and (br > hitBr)) then
                        hit, hitWeak, hitBr = s, weak, br
                    end
                end
            end
        end
        if hit then
            local choice = finishChoice(uid, hit, "warn break " .. best.name, { best.id }, false)
            if choice then
                say("break in time")
                return choice
            end
        end
    end
    -- Everything below is one question: what lands, whom it kills, and which
    -- action this unit holds saves the most of them. No saving action, keep hitting.
    local Brace = Known.brace
    if not (Brace and Known.measure) then return nil end
    local card = mobOf(best)
    local risk = card and card.dangerIds
    local foeBook = (Fight.hitSeen and Fight.hitSeen[best.id]) or {}
    -- Does this ally act again before the hit? Effects that end at their next action lapse.
    local function actsFirst(id)
        local acts = 0
        local function count(list, stop)
            for _, v in ipairs(list) do
                if v == stop then return end
                if v == id then acts = acts + 1 end
            end
        end
        if bestCur then
            count(cur, best.id)
        else
            count(cur, nil)
            count(nxt, best.id)
        end
        return acts > (((id == uid) and (cur[1] == uid)) and 1 or 0)
    end
    local team, move, byId = {}, nil, {}
    for _, a in ipairs(w.allies) do
        if (not a.dead) and not (Fight.isSummon and Fight.isSummon(a.id)) then
            local hp, maxHp = stat(a.id, PARAM.HP, false), stat(a.id, PARAM.HP, true)
            if hp and (hp > 0) then
                local hit, row = Known.measure.warnedCast(foeBook, risk, skillOf, a.id)
                if row and ((not move) or ((row.power or 0) > (move.power or 0))) then move = row end
                local unit = {
                    id = a.id, name = a.name, hp = hp, maxHp = maxHp, hit = hit, statuses = a.statuses,
                    actsFirst = actsFirst(a.id), noSpell = next((Fight.stance and Fight.stance[a.id]) or {}) ~= nil,
                }
                team[#team + 1] = unit
                byId[a.id] = a
            end
        end
    end
    if not byId[uid] then return nil end
    if not move then
        for _, id in ipairs(risk or {}) do
            local row = skillOf(id)
            if row and ((not move) or ((row.power or 0) > (move.power or 0))) then move = row end
        end
    end
    local kind = move and move.dmgType
    if (kind ~= 1) and (kind ~= 2) then
        kind = (card and card.hits == "physical" and 1) or (card and card.hits == "magic" and 2) or nil
    end
    local cuts = Known.statusMap and Known.statusMap() or {}
    for _, unit in ipairs(team) do
        -- Nothing seen from this foe on this ally: assume it could kill them.
        unit.hit = unit.hit or unit.maxHp or unit.hp
        unit.share = Brace.through(unit.statuses, kind, cuts)
    end
    local options = {}
    for _, s in ipairs(skills) do
        if pay(s) and (not isHit(s, false)) and (s.rel == REL.FRIEND) then
            local d = Brace.describe(s, kind)
            if d then
                d.skill, d.cost = s, s.cost or 0
                options[#options + 1] = d
            end
        end
        if (s.kind == "heal") and pay(s) and (not (isPatch and isPatch(s))) then
            local rate = Fight.healRate and Fight.healRate[uid]
            local amount = nil
            if Health.FIXED and (s.calc == Health.FIXED) and ((s.power or 0) > 0) then amount = s.power
            elseif rate and ((s.power or 0) > 0) then amount = s.power * rate end
            if amount then
                local scope = (partyOf(s) and "all") or ((s.target == TGT.SELF) and "self") or "one"
                options[#options + 1] = { skill = s, heal = amount, scope = scope, spell = (s.attr == ATTR.MAGIC), cost = s.cost or 0 }
            end
        end
    end
    local okItems, owned = pcall(ownedRecovery)
    if okItems and type(owned) == "table" then
        local single, party = nil, nil
        for _, it in ipairs(owned) do
            if (it.hp or (it.kind == "heal")) and it.amount and (it.amount > 0) and (not it.rare) then
                if it.party then
                    if (not party) or (it.amount > party.amount) then party = it end
                elseif (not single) or (it.amount > single.amount) then
                    single = it
                end
            end
        end
        if single then options[#options + 1] = { item = single, heal = single.amount, scope = "one", cost = 0 } end
        if party then options[#options + 1] = { item = party, heal = party.amount, scope = "all", cost = 0 } end
    end
    local lethal = Brace.lethal(team)
    local isSingle = move and (move.target == TGT.SINGLE) or false
    local parts = {}
    for _, unit in ipairs(team) do
        parts[#parts + 1] = string.format("%s %d/%d", unit.name or "?", math.floor(unit.hp), math.floor(unit.hit * unit.share))
    end
    say(string.format("%s, HP/hit: %s, %d would fall", (move and move.name) or "unknown move", table.concat(parts, ", "), lethal))
    for _, entry in ipairs(Brace.rank(team, options, uid, isSingle)) do
        local opt = entry.option
        local why = string.format("brace %s, saves %d", best.name, entry.saved)
        local choice = nil
        if opt.item then
            local who = byId[entry.targets[1]]
            choice = pickRecoveryItem(uid, w, "heal", opt.item.party and { partyOnly = true } or { who = who })
        else
            choice = finishChoice(uid, opt.skill, why, entry.targets, opt.scope == "all")
        end
        if choice then
            Fight.braced = Fight.braced or {}
            for _, id in ipairs(entry.targets) do
                if opt.heal then
                    Fight.claim.heal[id] = true
                else
                    -- Until the next read, the hit book has to know this is on them.
                    -- A cut with a status counts through that status, never both ways.
                    local now = Fight.statusNow and Fight.statusNow[id]
                    if opt.status and now then
                        now[opt.status] = true
                    elseif not opt.status then
                        Fight.braced[id] = opt.through
                    end
                end
            end
            local info = opt.skill and (opt.skill.known or knownOf(opt.skill))
            if info and (info.use == "guardbuff") then
                -- The once-a-fight setup guard reads this.
                Fight.guardOn = Fight.guardOn or {}
                Fight.guardOn[info.guards or "any"] = { map = opt.skill.friendStatus or {}, seen = false }
            end
            say(string.format("prepare: %s", (opt.skill and opt.skill.name) or (opt.item and opt.item.name) or "?"))
            return choice
        end
    end
    return nil
end

local function turn(uid, skills, w, phase)
    -- One slot of the round. Care first, then the phase the whole field is in.
    -- Damage is scored against every living gauge, using what earlier slots already claimed.
    if Fight.braced then Fight.braced[uid] = nil end
    if Fight.claim and Fight.claim.heal and Health.reviewClaims then
        Fight.claimMarks = Fight.claimMarks or {}
        local ids = {}
        for _, a in ipairs(w.allies) do
            if not a.dead then ids[#ids + 1] = a.id end
        end
        for _, id in ipairs(Health.reviewClaims(Fight.claim.heal, Fight.claimMarks, ids, function(id) return stat(id, PARAM.HP, false) end)) do
            appendLog(string.format("  %s took more since the heal, claim released", tostring(Fight.nameOf and Fight.nameOf(id) or id)))
        end
    end
    Fight.statusNow = {}
    for _, a in ipairs(w.allies) do Fight.statusNow[a.id] = a.statuses end
    w.usedSupport = w.usedSupport or {}
    Fight.claim = Fight.claim or {
        heal = {}, revive = {}, hone = {}, ether = {},
        guard = false, esper = false, lb = false, scan = {}, kit = {},
        etherRound = false,
    }
    Fight.debuffOn = Fight.debuffOn or {}
    Fight.debuffSeen = Fight.debuffSeen or {}
    Fight.debuffTold = Fight.debuffTold or {}
    -- Every turn, not only a turn that can cast a debuff, so a status that shows
    -- and wears off between those turns still counts as seen.
    if Debuffs.noteSeen then
        for _, u in ipairs(w.enemies) do
            Debuffs.noteSeen(u, Fight.debuffOn, Fight.debuffIds, Fight.debuffSeen)
        end
    end
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
    -- Set once styleOf has read the field, below. Declared here so isHit
    -- sees this local and not an unset global.
    local limitFight = false
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
        -- A damage Limit is a hit on a fight that may spend one. The break
        -- flag decides whether it outranks another hit. It does not decide
        -- whether the hit is visible.
        if (s.attr == ATTR.LB) or (use == "lb-cash") then
            if not limitFight then return false end
            if (use == "lb-cash") or (s.kind == "damage") then return true end
            return false
        end
        return s.kind == "damage" or s.attr == ATTR.FIGHT or s.attr == ATTR.MAGIC or s.attr == ATTR.ABILITY
    end
    local function gaugeOfEnemy(enemy)
        local card = mobOf(enemy)
        local book = (card and tonumber(card.gauge)) or 100
        local scaled = Fight.gaugeScale and Fight.gaugeScale[enemy.id]
        if scaled and scaled > book then book = scaled end
        -- The live BreakPoint is the bar. The book was 120 where the fight's
        -- bar was 192, so a ledger against the book calls the bar empty early.
        local cur = stat(enemy.id, PARAM.BREAK, false)
        local maxv = stat(enemy.id, PARAM.BREAK, true)
        if cur ~= nil and maxv ~= nil and maxv > 0 then
            if cur < 0 then cur = 0 end
            if broken(enemy.id) then return maxv, 0, true, card end
            return maxv, cur, false, card
        end
        if Fight.down[enemy.id] then return book, 0, true, card end
        local poured = Fight.poured[enemy.id] or 0
        local remain = book - poured
        if remain < 0 then remain = 0 end
        return book, remain, remain <= 0, card
    end
    local function handOf(s, enemy)
        return (counterScale(s, enemy) or 1) * (monoScale(s, enemy) or 1)
    end
    local function staggerOf(s, enemy)
        local f = elementFactor(s, enemy)
        if f <= 0 then return 0, f end
        local _, br = offenseOf(s)
        -- A miss adds no stagger, so what a hit pours is worth how often it lands.
        local land = Known.measure and Known.measure.landRate(Fight.dealtBook, uid, s.id, s.accuracy) or 1
        return (br or 0) * f * handOf(s, enemy) * land, f
    end
    -- How they walked in. Under half, or a hit already shown that their
    -- current HP would not survive. A status this file already clears.
    -- Read once, before the first swing, so a later chip does not reopen it.
    local function noteEntry()
        if Fight.entrySet then return end
        Fight.entrySet = true
        Fight.entryCare = {}
        Fight.entryStatus = false
        local bits = {}
        for _, a in ipairs(w.allies) do
            if not a.dead then
                local shown = Fight.borne and Fight.borne[a.id]
                local hpNow = stat(a.id, PARAM.HP, false)
                local maxHp = stat(a.id, PARAM.HP, true)
                if Health.openingHurt and Health.openingHurt(a.hp, hpNow, maxHp, shown) then
                    Fight.entryCare[a.id] = true
                    bits[#bits + 1] = string.format("%s %d%%", a.name or "?", math.floor((a.hp or 0) * 100 + 0.5))
                end
                if Health.careStatus and Health.careStatus(a.statuses) then Fight.entryStatus = true end
            end
        end
        if #bits > 0 then
            local line = "opening: " .. table.concat(bits, ", ")
            log("%s", line)
            appendLog("  " .. line)
        end
    end
    noteEntry()
    -- Read before the kill below, so a Limit is in reach of it on a fight
    -- that may spend one.
    local hardField = false
    local function styleOf()
        markExposed(w)
        hardField = hardFight(w)
        -- Setup when the field has a danger move or a hit that would kill.
        -- Otherwise hit. Healer count, the boss flag, and the round do not
        -- choose this.
        if hardField then return "balanced" end
        return "aggressive"
    end
    local style = styleOf()
    Fight.threat = hardField
    -- A Limit waits for a danger move, a hit that would kill, or a boss.
    -- A common fight spends the turn on its own skills.
    limitFight = hardField or (Fight.boss and true or false)

    -- A foe this unit can kill right now dies now, ahead of heals and everything
    -- else: a dead foe stops hitting, and a dead boss ends the fight. With more
    -- than one in reach, the biggest goes first.
    if Known.measure and Fight.dealtBook then
        local target, targetMax, shot = nil, -1, nil
        for _, u in ipairs(w.enemies) do
            local hp = stat(u.id, PARAM.HP, false)
            local top = stat(u.id, PARAM.HP, true) or 0
            if hp and (hp > 0) and (top > targetMax) and keepFoe(u.id) then
                local shots, lbShots, bestPlain = {}, {}, 0
                for _, s in ipairs(skills) do
                    if isHit(s, true) and pay(s) then
                        local f = elementFactor(s, u)
                        if f > 0 then
                            local pow = offenseOf(s)
                            local real, measured = Known.measure.expect(Fight.dealtBook, uid, s.id, u.id, (pow or 0) * Known.measure.damageFit(f), s.accuracy)
                            -- Only what this hit has really done to this foe. An estimate
                            -- for an untried hit has been off by four times.
                            if s.attr == ATTR.LB then
                                -- An area Limit hits every living enemy. One that any of
                                -- them nulls stays off, the same as everywhere else.
                                local reaches = true
                                if aoeOf(s) then
                                    for _, other in ipairs(w.enemies) do
                                        if elementFactor(s, other) <= 0 then reaches = false end
                                    end
                                end
                                if reaches then
                                    lbShots[#lbShots + 1] = { skill = s, real = (real and measured) and real or nil, cost = 0 }
                                end
                            elseif real and measured then
                                shots[#shots + 1] = { skill = s, real = real, cost = s.cost or 0 }
                                if real > bestPlain then bestPlain = real end
                            end
                        end
                    end
                end
                -- A Limit that has not landed on this foe counts at twice this
                -- unit's best measured hit on it. Its rows scale with level, and
                -- the logs show it at two and a half to six times that hit.
                local lbReach = {}
                for _, shot in ipairs(lbShots) do
                    if shot.real then
                        lbReach[#lbReach + 1] = shot
                    elseif bestPlain > 0 then
                        shot.real, shot.floor = bestPlain * 2, true
                        lbReach[#lbReach + 1] = shot
                    end
                end
                -- Another hit that kills keeps the Limit for later.
                local pick = Known.measure.pickKill(shots, hp) or Known.measure.pickKill(lbReach, hp)
                if pick then target, targetMax, shot = u, top, pick end
            end
        end
        if shot then
            local why = "kill " .. (target.name or "?")
            if shot.skill.attr == ATTR.LB then
                why = why .. (shot.floor and " with lb, at twice the best hit" or " with lb")
            end
            local ids, all = { target.id }, false
            if (shot.skill.attr == ATTR.LB) and aoeOf(shot.skill) then ids, all = idsOf(w.enemies), true end
            local choice = finishChoice(uid, shot.skill, why, ids, all)
            if choice then return choice end
        end
    end

    local function allyCritical()
        markExposed(w)
        local who, whoHp = nil, nil
        for _, a in ipairs(w.allies) do
            if a.exposed and not Fight.claim.heal[a.id] then
                local hp = stat(a.id, PARAM.HP, false) or 0
                if (not who) or (hp < whoHp) then who, whoHp = a, hp end
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
    -- A gauge the party can empty within this round: setup waits and everyone
    -- hits. Asked once a turn, only by the setup that can wait.
    local breakCloseAnswer = nil
    local function breakClose()
        if breakCloseAnswer ~= nil then return breakCloseAnswer end
        breakCloseAnswer = false
        for _, u in ipairs(open) do
            local _, remain, empty = gaugeOfEnemy(u)
            if (not empty) and (remain > 0) then
                local pour = 0
                for _, a in ipairs(w.allies) do
                    if (not a.dead) and (a.acts ~= false) and (not heldOut(a)) then
                        local kit = (a.id == uid) and { spells = skills } or unitKit(a.id)
                        local amp = (a.id == uid) and (w.mp or 0) or (stat(a.id, PARAM.MP, false) or 0)
                        local top = 0
                        for _, s in ipairs((kit and kit.spells) or {}) do
                            if isHit(s, false) and ((s.cost or 0) <= amp) then
                                local gained = staggerOf(s, u)
                                if gained > top then top = gained end
                            end
                        end
                        pour = pour + top
                    end
                end
                if remain <= pour then breakCloseAnswer = true end
            end
        end
        return breakCloseAnswer
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
        -- A party item's claim does not cover an ally it left under 30%.
        if (not a.dead) and a.exposed and Fight.claim.itemHeal and Fight.claim.itemHeal[a.id] then
            Fight.claim.heal[a.id] = nil
            Fight.claim.itemHeal[a.id] = nil
            appendLog(string.format("  %s still critical after a party item, claim released", tostring(a.name)))
        end
        if a.dead then
            Fight.stance[a.id] = nil
            -- A heal from before the fall does not count once they are down.
            -- A raise brings them back under 30%, and that still needs a turn.
            Fight.claim.heal[a.id] = nil
            if Fight.claim.cure then Fight.claim.cure[a.id] = nil end
            if Fight.killRangeAt then Fight.killRangeAt[a.id] = nil end
            if Fight.healMark then Fight.healMark[a.id] = nil end
        end
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
    -- Each Limit has a use case read from its row (limits.lua). It is asked
    -- here, ahead of the item raise, the opening heal and the setup, so a
    -- full bar is not left behind a turn that could wait. A common fight
    -- spends no Limit.
    local function limitPlan(stage)
        if not (Limits.plan and limitFight) then return nil end
        if phase == PHASE_FINISH then return nil end
        local ready = {}
        for _, s in ipairs(skills) do
            if limitSkill(s) and s.known and s.known.role and pay(s) then ready[#ready + 1] = s end
        end
        if #ready == 0 then return nil end
        local foes, maxGauge = {}, 0
        for _, u in ipairs(w.enemies) do
            local gauge = gaugeOfEnemy(u)
            if gauge > maxGauge then maxGauge = gauge end
        end
        for i, u in ipairs(w.enemies) do
            local gauge, remain = gaugeOfEnemy(u)
            local hp = stat(u.id, PARAM.HP, false) or 0
            local top = stat(u.id, PARAM.HP, true) or 0
            foes[i] = {
                broken = (u.broken or Fight.down[u.id]) and true or false,
                remain = remain or 0,
                hp = (top > 0) and (hp / top) or 1,
                boss = (Fight.boss and (gauge >= maxGauge)) and true or false,
            }
        end
        local list = {}
        for i, s in ipairs(ready) do
            local l = { role = s.known.role, gauges = s.lbCost or 1, area = aoeOf(s) and true or false,
                lands = {}, pour = {}, blocked = false }
            for j, u in ipairs(w.enemies) do
                local f = elementFactor(s, u)
                l.lands[j] = f > 0
                l.pour[j] = (f > 0) and (staggerOf(s, u) or 0) or 0
                if l.area and (f <= 0) then l.blocked = true end
            end
            list[i] = l
        end
        -- The largest damage Limit this unit has equipped, ready or not, that
        -- lands on this field: an area one on every foe, a single one on any.
        -- A larger Limit the field nulls is not worth waiting for. limitHeld
        -- asks the same.
        local higher = 0
        for _, id in ipairs(equippedIds(uid)) do
            local row = skillOf(id)
            local fact = row and (row.attr == ATTR.LB) and Limits.lookup and Limits.lookup(row.name)
            if fact and Limits.DAMAGE and Limits.DAMAGE[fact.role] and (#w.enemies > 0) then
                local probe = { known = fact, name = row.name }
                local any, all = false, true
                for _, foe in ipairs(w.enemies) do
                    if elementFactor(probe, foe) > 0 then any = true else all = false end
                end
                if (fact.area and all) or ((not fact.area) and any) then
                    local g = (Limits.gauges and Limits.gauges(fact.points, Fight.oneGauge)) or tonumber(fact.gauges) or 1
                    if g > higher then higher = g end
                end
            end
        end
        local up = 0
        for _, a in ipairs(w.allies) do
            if not a.dead then up = up + 1 end
        end
        local bar = Fight.lbBar and Fight.lbBar[uid] or {}
        local plan = Limits.plan({
            stage = stage, limits = list, foes = foes,
            filled = bar.filled, max = bar.max, higher = higher,
            boss = Fight.boss and true or false, bonus = (phase == PHASE_BONUS),
            breakClose = breakClose(), up = up, down = #(Fight.downNow or {}),
        })
        if not plan then return nil end
        local s = ready[plan.at]
        local role = s.known.role
        local ids, all
        if role == "revive" then
            ids, all = idsOf(Fight.downNow), true
        elseif (role == "double") or (role == "fill") then
            ids = {}
            for _, a in ipairs(w.allies) do
                if not a.dead then ids[#ids + 1] = a.id end
            end
            all = true
        elseif plan.foe then
            ids, all = { w.enemies[plan.foe].id }, false
        else
            ids, all = idsOf(w.enemies), true
        end
        local who = plan.foe and (" " .. (w.enemies[plan.foe].name or "enemy")) or ""
        local choice = finishChoice(uid, s, plan.why .. who, ids, all)
        if choice and (role == "revive") then
            local at = #(Fight.actions or {})
            for _, ally in ipairs(Fight.downNow) do Fight.claim.revive[ally.id] = at end
        end
        return choice
    end
    do
        local choice = limitPlan("urgent")
        if choice then return choice end
    end

    -- A fallen ally is raised once nobody living would die to a hit this
    -- fight has already shown. A raise is not held for a round count.
    Fight.refell = Fight.refell or {}
    Fight.raisedRound = Fight.raisedRound or {}
    for _, a in ipairs(w.allies) do
        local at = Fight.raisedRound[a.id]
        if (not a.dead) and at and (((Fight.rounds or 0) - at) >= 3) then
            Fight.refell[a.id] = nil
            Fight.raisedRound[a.id] = nil
        end
    end
    local focus = dead
    if focus and Fight.claim.revive[focus.id] then
        local other = nil
        for _, u in ipairs(Fight.downNow) do
            if (u.id ~= focus.id) and (u.acts ~= false) and (not Fight.claim.revive[u.id]) then
                other = u
                break
            end
        end
        focus = other
    end
    if focus and not Fight.claim.revive[focus.id] and not allyCritical() then
            local function raiseFallen(allowOne)
                local downN = #Fight.downNow
                if (downN < 1) and focus then downN = 1 end
                local s, partyHit = nil, false
                if Limits.bestRaise then
                    local pool = skills
                    if not limitFight then
                        pool = {}
                        for _, row in ipairs(skills) do
                            if not limitSkill(row) then pool[#pool + 1] = row end
                        end
                    end
                    s, partyHit = Limits.bestRaise(pool, downN, pay, allowOne)
                elseif not allowOne then
                    for _, row in ipairs(skills) do
                        if (row.kind == "revive") and pay(row) then s = row break end
                    end
                end
                if not s then return nil end
                local many = partyHit and (#Fight.downNow >= 2)
                local ids = (many and idsOf(Fight.downNow)) or { focus.id }
                local why = (many and "raise the party") or ("raise " .. focus.name)
                local choice = finishChoice(uid, s, why, ids, many and true or false)
                if not choice then return nil end
                local at = #(Fight.actions or {})
                Fight.claim.revive[focus.id] = at
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
                if item then Fight.claim.revive[focus.id] = #(Fight.actions or {}) return item end
                choice = raiseFallen(true)
                if choice then return choice end
            end
    end

    -- Largest HP one living foe's cast has taken off one ally. A guard
    -- scales that down only when the same skill has already hit for less
    -- with isDefence set. No such pair, no invented factor.
    local function castThreat(ally)
        local best = 0
        local set = ally.statuses or {}
        local phys = set[25] or set[36]
        local mag = set[27]
        for fid, foeBook in pairs(Fight.hitSeen or {}) do
            if keepFoe(fid) then
                for _, sk in pairs(foeBook) do
                    local amount = sk.cast or 0
                    local guarded = false
                    if sk.dtype == 2 then guarded = mag and true or false
                    elseif sk.dtype == 1 then guarded = phys and true or false
                    else guarded = (mag or phys) and true or false end
                    if guarded and ((sk.castOpen or 0) > (sk.castGuard or 0)) and ((sk.castGuard or 0) > 0) then
                        amount = sk.castGuard
                    end
                    -- The same cast hits each ally differently. Use what it did
                    -- to this one, or the least it did to anyone not yet seen.
                    local top, low = 0, nil
                    for _, v in pairs(sk.castTo or {}) do
                        if v > top then top = v end
                        if (not low) or (v < low) then low = v end
                    end
                    if top > 0 then
                        amount = amount * (((sk.castTo[ally.id]) or low) / top)
                    end
                    if amount > best then best = amount end
                end
            end
        end
        return best
    end
    if readRisk then readRisk() end
    local ranged = nil
    if hardField then
        for _, a in ipairs(w.allies) do
            if (not a.dead) and (not Fight.claim.heal[a.id]) and not (Fight.summons and Fight.summons[a.id]) then
                local hpNow = stat(a.id, PARAM.HP, false)
                local maxHp = stat(a.id, PARAM.HP, true)
                local lineHp = castThreat(a)
                -- A cast at or over max HP cannot be healed out of. That
                -- heal would repeat every turn. After a kill-range heal, the
                -- ally is not healed for kill range again until a hit takes
                -- them below the HP they had when that heal was chosen. A
                -- round count let the planner and the game disagree (a
                -- second heal at 75% in the sim's same round).
                local open = true
                local rec = Fight.killRangeAt and Fight.killRangeAt[a.id]
                if type(rec) == "table" then
                    if (rec.hp == nil) or (hpNow == nil) or (hpNow >= rec.hp) then open = false end
                elseif rec then
                    open = false
                end
                -- AGENTS.md: claims stop a second heal in the same round. The
                -- planner's round can end before the game's, so an ally above
                -- 65% who had any heal in the last two passes of the party is
                -- not healed again for kill range.
                -- a.hp is the share the planner reports and heals by.
                if open and ((a.hp or 0) >= 0.65) then
                    local lastHeal = Fight.healAt and Fight.healAt[a.id]
                    if lastHeal then
                        local live = 0
                        for _, b in ipairs(w.allies) do
                            if (not b.dead) and not (Fight.summons and Fight.summons[b.id]) then live = live + 1 end
                        end
                        if (#(Fight.actions or {}) - lastHeal) < (math.max(live, 1) * 2) then open = false end
                    end
                end
                if open and hpNow and maxHp and (maxHp > 0) and (lineHp > 0) and (lineHp < maxHp) and (hpNow <= lineHp) then
                    if (not ranged) or ((a.hp or 1) < (ranged.hp or 1)) then ranged = a end
                end
            end
        end
    end
    Fight.killHold = (ranged ~= nil)
    -- True when a living foe's slot is before the main healer's next one.
    -- No Timeline read leaves today's wait in place.
    local function foeBeforeHealer()
        local order = Fight.order
        if not order or not order.current then return false end
        if not Health.mainHealer then return false end
        local healer = Health.mainHealer(w.allies, unitKit)
        if not healer then return false end
        local hid = healer.id
        if hid == uid then return false end
        local cur = order.current or {}
        local nxt = order.next or {}
        local function find(list, id)
            for i, v in ipairs(list) do
                if v == id then return i end
            end
            return nil
        end
        local function foeIn(list, i0, i1)
            for i = i0, i1 do
                local id = list[i]
                if id and (id ~= hid) and keepFoe(id) and not (Fight.summons and Fight.summons[id]) then
                    return true
                end
            end
            return false
        end
        local at = find(cur, uid)
        local healAt = find(cur, hid)
        if at and healAt and (healAt > at) then
            return foeIn(cur, at + 1, healAt - 1)
        end
        local from = (at and (at + 1)) or 1
        if foeIn(cur, from, #cur) then return true end
        local healNext = find(nxt, hid)
        if not healNext then return false end
        return foeIn(nxt, 1, healNext - 1)
    end

    local function healNow(hurt, why, itemAt)
        if not hurt or Fight.claim.heal[hurt.id] then return nil end
        -- Opening care already chose this actor. They do not leave it for later.
        if Health.healerWaiting and (why ~= "opening") then
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
                if Fight.killHold and foeBeforeHealer() then
                    Fight.healLeft = Fight.healLeft or {}
                    local key = "skip" .. tostring(uid)
                    if not Fight.healLeft[key] then
                        Fight.healLeft[key] = true
                        local healer = Health.mainHealer and Health.mainHealer(w.allies, unitKit) or nil
                        local line = string.format("heal left skipped, foe before %s", (healer and healer.name) or "?")
                        log("%s", line)
                        appendLog("  " .. line)
                    end
                else
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
        -- A gauge heal is the heal this unit holds when no MP heal can be paid.
        -- It does not outrank a spell the bar can already cast.
        local spellHeal = false
        for _, s in ipairs(skills) do
            if (s.kind == "heal") and (s.attr ~= ATTR.LB) and pay(s) and (not isPatch(s))
                and not (barred and (s.attr == ATTR.MAGIC))
                and not (s.target == TGT.SELF and hurt.id ~= uid) then
                spellHeal = true
                break
            end
        end
        for _, s in ipairs(skills) do
            if (s.kind == "heal") and pay(s) and (not isPatch(s))
                and not (s.attr == ATTR.LB and (spellHeal or not limitFight))
                and not (barred and (s.attr == ATTR.MAGIC))
                and not (s.target == TGT.SELF and hurt.id ~= uid) then
                local party = partyOf(s)
                local r
                if Health.spellRank then
                    r = Health.spellRank(s, missing, hurtN, party, need, Fight.healRate and Fight.healRate[uid])
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
        local function stamp(choice)
            if choice and (why == "kill-range") and choice.reason and (not choice.reason:find("kill-range", 1, true)) then
                choice.reason = "kill-range " .. choice.reason
            end
            if choice then
                local covered = { hurt.id }
                if choice.isAll then
                    covered = {}
                    for _, id in ipairs(choice.targets or {}) do covered[#covered + 1] = id end
                    if #covered == 0 then covered[1] = hurt.id end
                end
                for _, id in ipairs(covered) do Fight.claim.heal[id] = true end
                if why == "kill-range" then
                    Fight.killRangeAt = Fight.killRangeAt or {}
                    local function markFor(id)
                        return { round = Fight.rounds or 0, at = #(Fight.actions or {}), hp = stat(id, PARAM.HP, false) }
                    end
                    Fight.killRangeAt[hurt.id] = markFor(hurt.id)
                    if choice.isAll then
                        for _, id in ipairs(choice.targets or {}) do
                            Fight.killRangeAt[id] = markFor(id)
                        end
                    end
                end
            end
            return choice
        end
        if (hurtN >= need) and ((not skill) or (not partyOf(skill))) then
            local item = pickRecoveryItem(uid, w, "heal", { partyOnly = true })
            if item then return stamp(item) end
        end
        if not skill then
            local item = pickRecoveryItem(uid, w, "heal", { who = hurt })
            if item then return stamp(item) end
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
                    and not (barred and (s.attr == ATTR.MAGIC))
                    and not (s.target == TGT.SELF and hurt.id ~= uid) then
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
            if choice then return stamp(choice) end
        end
        return nil
    end

    -- Before the chip, the Ether, and the summon. Self first when someone
    -- else is the healer. The healer, or anyone if there is none, takes the
    -- lowest. A foe acting before the healer means this actor does not wait.
    local function openingHeal()
        if (phase ~= 0) or (not Fight.entryCare) then return nil end
        local needs = {}
        for _, a in ipairs(w.allies) do
            if Fight.entryCare[a.id] and (not a.dead) and not (Fight.claim.heal and Fight.claim.heal[a.id]) then
                needs[#needs + 1] = { id = a.id, hp = a.hp }
            elseif Fight.entryCare[a.id] then
                Fight.entryCare[a.id] = nil
            end
        end
        if #needs == 0 then return nil end
        local mpOf = function(id)
            if id == uid then return w.mp or 0 end
            return stat(id, PARAM.MP, false) or 0
        end
        local healer = Health.mainHealer and Health.mainHealer(w.allies, unitKit) or nil
        local healerId = nil
        if healer and Health.available and Health.available(healer, healer.statuses, unitKit, mpOf) then
            if (healer.id == uid) or (not foeBeforeHealer()) then healerId = healer.id end
        end
        local pick = Health.openingTarget and Health.openingTarget(uid, needs, healerId) or nil
        if not pick then return nil end
        local who = nil
        for _, a in ipairs(w.allies) do
            if a.id == pick then who = a end
        end
        if not who then return nil end
        local choice = healNow(who, "opening", nil)
        if choice then return choice end
        Fight.entryCare[pick] = nil
        return nil
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
        local s = nil
        for _, x in ipairs(skills) do
            if (not s) and (useOf(x) == "lb-guard") and pay(x) then s = x end
        end
        if not s then return nil end
        local ids = {}
        for _, a in ipairs(w.allies) do
            if not a.dead then ids[#ids + 1] = a.id end
        end
        if #ids == 0 then return nil end
        return finishChoice(uid, s, "barrier lb " .. (s.name or "limit") .. " party", ids, true)
    end
    -- The barrier and every other Limit's use case, before the opening heal
    -- and the setup. Someone a shown hit would kill is healed first.
    if (phase ~= PHASE_FINISH) and limitFight and (not allyCritical()) then
        if (phase == 0) and (not dead) then
            local veil = barrierLimit()
            if veil then return veil end
        end
        local choice = limitPlan("main")
        if choice then return choice end
    end
    local opened = openingHeal()
    if opened then return opened end

    local crit = allyCritical()
    local function deferHeal()
        if phase == PHASE_BONUS then return false end
        if Fight.killHold and foeBeforeHealer() then return false end
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
                if kit and ((kit.healScore or 0) > 0) then
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
    -- Same slot as a critical heal. Under 30% keeps that label. Above it,
    -- the ally is here because a cast already seen would drop them.
    local hurt, why = crit, crit and "critical" or nil
    if ranged and ((not crit) or ((ranged.hp or 1) < (crit.hp or 1))) then
        hurt = ranged
        why = ((ranged.hp or 1) < 0.30) and "critical" or "kill-range"
    end
    local healAt = (why == "kill-range") and 1.01 or nil
    -- The largest gauge is broken: everyone's turn is a hit, the same as a bonus
    -- phase. A critical ally and a raise still come first. Setup and top-offs wait.
    if (phase == 0) and (#brokenPool > 0) and (not hurt) then
        local most, brokeMost = 0, 0
        for _, u in ipairs(w.enemies) do
            local gauge = gaugeOfEnemy(u) or 0
            if gauge > most then most = gauge end
        end
        for _, u in ipairs(brokenPool) do
            local gauge = gaugeOfEnemy(u) or 0
            if u.broken and (gauge > brokeMost) then brokeMost = gauge end
        end
        if (brokeMost > 0) and (brokeMost >= most) then phase = PHASE_BONUS end
    end
    if hurt and (phase ~= PHASE_BONUS) and (not deferHeal()) then
        local choice = healNow(hurt, why, healAt)
        if choice then return choice end
    end
    if phase == PHASE_BONUS or #brokenPool > 0 and phase == PHASE_BONUS then
        local choice = healNow(hurt, why, healAt)
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
        if (not focus) or (Fight.claim.cure and Fight.claim.cure[focus.id]) then return nil end
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
        if choice then
            Fight.claim.cure = Fight.claim.cure or {}
            Fight.claim.cure[focus.id] = true
        end
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
        if (not focus) or (Fight.claim.cure and Fight.claim.cure[focus.id]) or Fight.slowTry then return nil end
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
        Fight.claim.cure = Fight.claim.cure or {}
        Fight.claim.cure[focus.id] = true
        choice.slow = {
            id = focus.id, key = pickKey, round = Fight.rounds or 0,
            name = pick.name, caster = uid, cost = pick.cost or 0, mp = mpNow,
        }
        return choice
    end
    local cured = curePass(true)
    if cured then return cured end
    -- A status they walked in with, before the warning and the chip.
    if Fight.entryStatus and (not Fight.chipped) and (phase == 0) then
        local early = curePass(false)
        if early then return early end
    end
    -- A damage Limit spends the bar on a hit.
    local function spendsLimit(s)
        return (useOf(s) == "lb-cash") or ((s.attr == ATTR.LB) and (s.kind == "damage"))
    end
    -- A cheaper damage Limit waits while a higher-cost one on this bar can
    -- still be reached and cannot be paid yet. Each bar is its own.
    local function limitHeld(s)
        local damage = (useOf(s) == "lb-cash") or ((s.attr == ATTR.LB) and (s.kind == "damage"))
        if not damage then return false end
        local bar = Fight.lbBar and Fight.lbBar[uid]
        if not bar then return false end
        local cost = tonumber(s.lbCost) or tonumber(s.known and s.known.gauges) or 1
        local higher = {}
        local one = Fight.oneGauge
        for _, id in ipairs(equippedIds(uid)) do
            local row = skillOf(id)
            local fact = row and (row.attr == ATTR.LB) and Limits.lookup and Limits.lookup(row.name)
            if fact and (fact.use == "lb-cash") and (row.id ~= s.id) then
                local g = (Limits.gauges and Limits.gauges(fact.points, one)) or tonumber(fact.gauges) or 1
                if (g > cost) and (#w.enemies > 0) then
                    local probe = { known = fact, name = row.name }
                    local any, all = false, true
                    for _, foe in ipairs(w.enemies) do
                        if elementFactor(probe, foe) > 0 then any = true else all = false end
                    end
                    if (fact.area and all) or ((not fact.area) and any) then
                        higher[#higher + 1] = g
                    end
                end
            end
        end
        if Limits.holds then return Limits.holds(cost, bar.filled, bar.max, higher) end
        return false
    end
    -- A live warning outranks the add plan and the sync chip. Raises and a
    -- critical heal have already had this slot.
    local warnedChoice = warnTurn(uid, skills, w, phase, pay, isHit, isPatch, limitHeld)
    if warnedChoice then return warnedChoice end

    markExposed(w)
    local recoverAt = 0
    local function underMark()
        local n, who = 0, nil
        for _, a in ipairs(w.allies) do
            if a.exposed then
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
    local function releaseEsper(mark)
        if (not mark) or mark.told then return end
        mark.told = true
        local line = "esper " .. (mark.name or "summon") .. " finished"
        log("%s", line)
        appendLog("  " .. line)
        Fight.claim.esper = false
        Fight.summoned = false
        Fight.esperOut = nil
    end
    -- Log only: why a unit holding an Esper did not call one, when that changes.
    local function esperGate(why)
        if Fight.esperGateWhy == why then return end
        Fight.esperGateWhy = why
        if not why then return end
        for _, s in ipairs(skills) do
            if (s.attr == ATTR.SUMMON) and (useOf(s) ~= "skip") then
                local line = "esper call held: " .. why
                log("%s", line)
                appendLog("  " .. line)
                break
            end
        end
    end
    local function esperStill()
        -- Out until that unit has acted and has then left the ally list.
        -- One scan that misses it, before that action, is not it leaving.
        local mark = Fight.esperOut
        local live = Fight.summonLive and true or false
        local holding = Espers.holding and Espers.holding(mark, live)
        -- Log only: what the hold sees, when that changes.
        if mark then
            local function said(v) return v and "yes" or "no" end
            local line = string.format("esper hold: %s acted %s, seen %s, on the field %s, claimed %s, holding %s",
                mark.name or "summon", said(mark.acted), said(mark.seen), said(live), said(Fight.claim.esper), said(holding))
            if Fight.esperHoldLine ~= line then
                Fight.esperHoldLine = line
                log("%s", line)
                appendLog("  " .. line)
            end
        end
        if holding then
            return true
        end
        if mark then releaseEsper(mark) end
        return false
    end
    local weaknessFits
    local function summonChoice()
        if not Espers.best then return nil end
        if esperStill() then
            esperGate("the last call is still out")
            return nil
        end
        if Fight.claim.esper then
            esperGate("a call is claimed")
            return nil
        end
        -- A boss, a danger move, or a hit that would kill is worth a call.
        -- A common fight spends the turn on its own skills.
        if not (hardField or Fight.boss) then
            if not Fight.esperCommon then
                for _, s in ipairs(skills) do
                    if (s.attr == ATTR.SUMMON) and (useOf(s) ~= "skip") then
                        Fight.esperCommon = true
                        local line = "esper held: common fight"
                        log("%s", line)
                        appendLog("  " .. line)
                        break
                    end
                end
            end
            return nil
        end
        local field = (#w.enemies > 0) and w.enemies or ((#pool > 0) and pool or open)
        if #field == 0 then return nil end
        -- EsperLevelGap. A danger move on foes far under this unit is not
        -- worth a call. A boss, or a hit this fight has shown would kill an
        -- ally, still is.
        -- TUNE: if under-level fights still go wrong without the call, raise
        -- the gap; if strong under-level foes kill allies before any hit is
        -- measured, add a measured-damage check here.
        local gap = tonumber(cfg.EsperLevelGap) or 0
        if (gap >= 1) and (not Fight.boss) and Espers.outLeveled then
            local exposed = false
            for _, a in ipairs(w.allies or {}) do
                if a.exposed then exposed = true end
            end
            if not exposed then
                local mine = Known.allyLevel(uid)
                local foes = {}
                for i, u in ipairs(field) do foes[i] = Known.foeLevel(u.id) or false end
                if Espers.outLeveled(mine, foes, gap) then
                    esperGate(string.format("every foe is %d or more levels under", gap))
                    return nil
                end
            end
        end
        -- The foe this call is for: a dangerous body, else the largest gauge.
        local preferId, preferGauge, dangerGauge = nil, -1, -1
        for _, u in ipairs(field) do
            local card = mobOf(u)
            local gauge = gaugeOfEnemy(u)
            if gauge > preferGauge then preferId, preferGauge = u.id, gauge end
            if card and card.danger and card.danger[1] and (gauge > dangerGauge) then
                dangerGauge = gauge
                preferId = u.id
            end
        end
        if not preferId then preferId = field[1].id end
        -- One heal stays payable. Two heals, and a share of the bar, do not.
        local healKit = unitKit(uid)
        local healCost = (healKit and ((healKit.healScore or 0) > 0) and healKit.healCost) or 0
        local hits = {}
        for _, u in ipairs(field) do
            hits[#hits + 1] = { id = u.id, prefer = (u.id == preferId), foe = u }
        end
        local cands = {}
        for _, s in ipairs(skills) do
            if (s.attr == ATTR.SUMMON) and pay(s) and (useOf(s) ~= "skip") then
                local fact = (Espers.lookup and Espers.lookup(s.name)) or nil
                if (not fact) and not (Espers.loaded and Espers.loaded()) then
                    fact = { role = "damage", use = "summon" }
                end
                if fact then
                    local scored, blocked = {}, false
                    local foes = {}
                    for _, h in ipairs(hits) do
                        local factor = elementFactor({ known = fact, name = s.name }, h.foe)
                        local lands = fact.area or h.prefer
                        if (fact.role ~= "guard") and lands and (factor <= 0) then blocked = true end
                        scored[#scored + 1] = { factor = factor, prefer = h.prefer }
                        if lands then foes[#foes + 1] = h.foe end
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
                    if (not blocked) and (((w.mp or 0) - (s.cost or 0)) >= healCost) then
                        -- The same number a spell uses: what this caster's call
                        -- did to these foes, or the signature's power scaled by
                        -- this caster's other hits. Nil until there is either.
                        local dealt, kills = nil, 0
                        if Known.measure and Fight.dealtBook and (fact.role ~= "guard") then
                            local sum, any = 0, false
                            for _, foe in ipairs(foes) do
                                local factor = elementFactor({ known = fact, name = s.name }, foe)
                                local fit = Known.measure.damageFit(factor)
                                local est = (fact.power or 0) * fit
                                if est <= 0 then est = nil end
                                local real, measured = Known.measure.expect(Fight.dealtBook, uid, s.id, foe.id, est, fact.accuracy or s.accuracy)
                                if real then
                                    any = true
                                    if real > 0 then sum = sum + real end
                                    if Known.measure.kills(real, stat(foe.id, PARAM.HP, false), measured) then
                                        kills = kills + 1
                                    end
                                end
                            end
                            if any then dealt = sum end
                        end
                        cands[#cands + 1] = { ref = s, fact = fact, hits = scored, dealt = dealt, kills = kills }
                    end
                end
            end
        end
        if #cands == 0 then
            esperGate("no row fits: MP, the heal kept back, or a null")
            return nil
        end
        if not Fight.esperTold then
            Fight.esperTold = true
            local names = {}
            for _, c in ipairs(cands) do
                local el = c.fact.element or c.fact.role or "summon"
                names[#names + 1] = (c.ref.name or "summon") .. " " .. el
            end
            log("esper equipped: %s", table.concat(names, ", "))
        end
        local picked = Espers.best(cands)
        if not picked then
            esperGate("no row scored")
            return nil
        end
        esperGate(nil)
        local s, fact = picked.ref, picked.fact
        local why = "esper " .. (s.name or "summon")
        if fact.element then
            why = why .. " " .. fact.element
        elseif fact.role == "guard" then
            why = why .. " support"
        end
        -- The summon row aims at the caster. The unit it brings does the hitting.
        local choice = finishChoice(uid, s, why, { uid }, false)
        if choice then choice.esperTurns = fact.turns end
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
    Fight.underLine = false
    local halfN, halfWho = underMark()
    local recoverGate = halfWho and true or false
    -- The Esper that fits a boss, or a field with a danger move or a hit that
    -- would kill, once raises and a critical heal have had the slot. A common
    -- fight does not spend one. A hit this fight has measured outranks the
    -- signature's element. Another call waits until that unit has acted and
    -- is no longer up, and the caster can pay it.
    if (phase == 0) and (not allyCritical()) and (not dead) then
        local choice = summonChoice()
        if choice then return choice end
    elseif phase == 0 then
        esperGate(dead and "an ally is down" or "an ally is critical")
    end
    if halfWho and phase ~= PHASE_BONUS and not deferHeal() and recoverGate then
        local choice = healNow(halfWho, "recover", 1)
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
            drop = allyExposed({ id = uid, dead = false }), spellHeal = spellHeal,
            round = Fight.rounds or 0, endedRound = Fight.stanceEnded[uid],
            mp = w.mp or 0, pay = (band() ~= "low"),
            keep = (own and ((own.healScore or 0) > 0)) and (own.healCost or 0) or 0,
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
                if (score > 0) and (score > bestScore) then healer, bestScore = a, score end
            end
        end
        local healerId = healer and healer.id or nil
        if (ownScore > 0) and (ownScore > bestScore) then healerId = uid end
        Fight.drawSeen = Fight.drawSeen or {}
        local picked = Kits.pickDraw(skills, {
            allies = w.allies, selfId = uid, healerId = healerId, seen = Fight.drawSeen,
            recoverAt = recoverAt, danger = danger,
            mp = w.mp or 0, pay = (band() ~= "low"),
            keep = (own and ((own.healScore or 0) > 0)) and (own.healCost or 0) or 0,
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
    if (phase == 0) and Kits.pickHaste and (not allyCritical()) and (not dead) and (not breakClose()) then
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
            hard = hardField and true or false, rich = true,
            mp = w.mp or 0, pay = (band() ~= "low"),
            keep = (own and ((own.healScore or 0) > 0)) and (own.healCost or 0) or 0,
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
                deals = Debuffs.dealsOf and Debuffs.dealsOf(Fight.hitSeen and Fight.hitSeen[u.id], card and card.hits) or nil,
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
        if seenNoted or (not Debuffs.noteSeen) then return end
        seenNoted = true
        Fight.debuffSeen = Fight.debuffSeen or {}
        for _, foe in ipairs(foes or {}) do
            Debuffs.noteSeen(foe, Fight.debuffOn, Fight.debuffIds, Fight.debuffSeen)
        end
    end
    -- How much of this party's damage is physical and how much magic: what it has
    -- really dealt, or before any hit lands, what it holds.
    local shareMemo = nil
    local function damageShare()
        if shareMemo then return shareMemo end
        local phys, magic = 0, 0
        for _, rec in pairs((Fight.dealtBook and Fight.dealtBook.bySkill) or {}) do
            local row = skillOf(rec.skill)
            local amount = (rec.avg or 0) * (rec.uses or 1)
            if row and (row.dmgType == 1) then phys = phys + amount end
            if row and (row.dmgType == 2) then magic = magic + amount end
        end
        if (phys + magic) <= 0 then
            for _, a in ipairs(w.allies) do
                local kit = (not a.dead) and unitKit(a.id) or nil
                for _, x in ipairs((kit and kit.spells) or {}) do
                    if (x.power or 0) > 0 then
                        if x.dmgType == 1 then phys = phys + 1 end
                        if x.dmgType == 2 then magic = magic + 1 end
                    end
                end
            end
        end
        local total = phys + magic
        if total <= 0 then return nil end
        shareMemo = { physical = phys / total, magic = magic / total }
        return shareMemo
    end
    local function payableDebuffs(actorId, mp)
        local spells = skills
        if actorId ~= uid then
            local kit = unitKit(actorId)
            spells = (kit and kit.spells) or {}
        end
        local spellsOnly, limits = {}, {}
        for _, s in ipairs(spells) do
            if ((useOf(s) == "debuff") or (s.kind == "debuff")) and ((s.cost or 0) <= mp) then
                if s.attr == ATTR.LB then limits[#limits + 1] = s else spellsOnly[#spellsOnly + 1] = s end
            end
        end
        -- A gauge debuff is used when it is the debuff this unit holds.
        if #spellsOnly > 0 then return spellsOnly end
        if limitFight then return limits end
        return {}
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
        if Fight.chipped or (phase ~= 0) or (not hardField) or (style == "aggressive") or breakClose() then return false end
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
                if Debuffs.choose(picks, foes, Fight.debuffOn, Fight.debuffSeen, fallback, damageShare()) then
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
        if phase ~= 0 or not hardField or style == "aggressive" or breakClose() then return false end
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
    -- only, when given, limits the skills asked to the ones it accepts.
    local function castDamage(pool, cashing, why, only)
        if not pool or #pool == 0 then return nil end
        local bestS, bestU, bestSpread = nil, nil, false
        local bestKills, bestDamage, bestStagger = -1, -1, -1
        local function considerSkill(s, targets, spread)
            if not pay(s) then return end
            local spendLb = (useOf(s) == "lb-cash") or ((s.attr == ATTR.LB) and (s.kind == "damage"))
            if spendLb and limitHeld(s) then return end
            -- A Limit that marks the gauge goes on before the break. On a
            -- staggered body the mark is lost, so the bar waits for an open one.
            if spendLb and s.known and s.known.breakDef then
                local anyOpen = false
                for _, u in ipairs(targets) do
                    local _, _, empty = gaugeOfEnemy(u)
                    if not (empty or u.broken) then anyOpen = true end
                end
                if not anyOpen then return end
            end
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
            local useful, kills, damage, stagger = 0, 0, 0, 0
            for _, u in ipairs(targets) do
                local _, remain, empty = gaugeOfEnemy(u)
                local gained, f = staggerOf(s, u)
                local held = (why == "fill")
                if f > 0 and (cashing or (((not empty) or held) and (gained > 0))) then
                    useful = useful + 1
                    local pow = offenseOf(s)
                    local fit = Known.measure and Known.measure.damageFit(f) or f
                    local real, measured = nil, false
                    if Known.measure and Fight.dealtBook then
                        real, measured = Known.measure.expect(Fight.dealtBook, uid, s.id, u.id, (pow or 0) * fit, s.accuracy)
                    end
                    if real and real > 0 then
                        damage = damage + real
                        if Known.measure.kills(real, stat(u.id, PARAM.HP, false), measured) then
                            kills = kills + 1
                        end
                    end
                    if not empty then stagger = stagger + (gained or 0) end
                    if (not empty) and gained >= remain then stagger = stagger + remain end
                end
            end
            if useful == 0 then return end
            local function pack(skill, k, d, g)
                return {
                    kills = k, damage = d, stagger = g,
                    limit = skill and (skill.attr == ATTR.LB) or false,
                    gauges = skill and skill.lbCost or 0,
                }
            end
            local ahead
            if Limits.ahead then
                ahead = Limits.ahead(
                    pack(s, kills, damage, stagger),
                    bestS and pack(bestS, bestKills, bestDamage, bestStagger) or nil,
                    cashing)
            elseif not bestS then
                ahead = true
            elseif kills ~= bestKills then
                ahead = kills > bestKills
            elseif damage ~= bestDamage then
                ahead = damage > bestDamage
            else
                ahead = stagger > bestStagger
            end
            if ahead then
                bestS, bestU, bestSpread = s, targets[1], spread and true or false
                bestKills, bestDamage, bestStagger = kills, damage, stagger
            end
        end
        for _, s in ipairs(skills) do
            if isHit(s, cashing) and ((not only) or only(s)) then
                local safe = {}
                if aoeOf(s) then
                    local ok = true
                    for _, u in ipairs(pool) do
                        if elementFactor(s, u) <= 0 then ok = false end
                    end
                    -- "All" reaches every foe, not only this pool.
                    if s.multicastOf then
                        for _, u in ipairs(w.enemies) do
                            if elementFactor(s, u) <= 0 then ok = false end
                        end
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
        -- Nothing left can land. A resist this fight learned gets one more try
        -- while the foe's statuses hold. The foe's own row still blocks. The
        -- mark stops the same try next turn.
        if not bestS then
            local retryS, retryU, retryMark, retryPow = nil, nil, nil, -1
            Fight.retry = Fight.retry or {}
            for _, s in ipairs(skills) do
                local spendLb = (useOf(s) == "lb-cash") or ((s.attr == ATTR.LB) and (s.kind == "damage"))
                if isHit(s, cashing) and ((not only) or only(s)) and pay(s) and not (spendLb and limitHeld(s)) then
                    local info = s.known or knownOf(s)
                    local key = (info and info.element) or kindOf(s)
                    if key then
                        for _, u in ipairs(pool) do
                            local mark = tostring(uid) .. ":" .. tostring(u.id) .. ":" .. key .. ":" .. statusStamp(u.id)
                            if (not Fight.retry[mark]) and (elementFactor(s, u, true) > 0) and (elementFactor(s, u) <= 0) then
                                local pow = offenseOf(s) or 0
                                if pow > retryPow then
                                    retryS, retryU, retryMark, retryPow = s, u, mark, pow
                                end
                            end
                        end
                    end
                end
            end
            if retryS then
                Fight.retry[retryMark] = true
                return finishChoice(uid, retryS, why .. " " .. retryU.name .. ", try again", { retryU.id }, false)
            end
        end
        if not bestS then return nil end
        local targets = bestSpread and idsOf(pool) or { bestU.id }
        local el = (bestS.known and bestS.known.element) or ""
        local name = bestSpread and (#pool .. " foes") or bestU.name
        local reason = why .. " " .. name
        if el ~= "" and elementFactor(bestS, bestU) >= 3 then reason = reason .. " " .. el end
        return finishChoice(uid, bestS, reason, targets, bestSpread)
    end

    -- A common fight does not spend a Limit. On a fight that may, a damage
    -- Limit is already in the hit comparison.
    if not limitFight and not Fight.limitCommon then
        for _, s in ipairs(skills) do
            if limitSkill(s) and (useOf(s) ~= "skip") then
                Fight.limitCommon = true
                local line = "limit held: common fight"
                log("%s", line)
                appendLog("  " .. line)
                break
            end
        end
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
    -- A staggered foe takes a damage Limit on any turn, not only the bonus
    -- turn. Only a Limit is asked here. Without one ready, the turn goes on
    -- as before.
    if (phase == 0) and limitFight then
        local staggered = {}
        for _, u in ipairs(w.enemies) do
            if u.broken or Fight.down[u.id] then staggered[#staggered + 1] = u end
        end
        if #staggered > 0 then
            local hit = castDamage(staggered, true, "stagger", spendsLimit)
            if hit then return hit end
        end
    end
    if #open == 0 and #brokenPool > 0 then
        if phase == PHASE_BONUS then
            return castDamage(brokenPool, true, "burst")
        end
        return castDamage(brokenPool, false, "fill")
    end

    local function firstSkill(pred)
        for _, s in ipairs(skills) do
            if useOf(s) ~= "skip" and pred(s) and pay(s) then return s end
        end
        return nil
    end

    local function castDebuff(refreshOnly)
        if (phase ~= 0) or (not hardField) or (style == "aggressive") or breakClose() or (not Debuffs.choose) then
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
        local s, foe, why = Debuffs.choose(picks, foes, Fight.debuffOn, Fight.debuffSeen, fallback, damageShare())
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
                for _, id in ipairs(ids) do markDebuff(id, effect, s.enemyStatus) end
                return choice
            end
        elseif (not refreshOnly) and (not s) and Debuffs.immuneEffect then
            local skipped = Debuffs.immuneEffect(picks, foes, fallback, damageShare())
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
    -- fight is the player's. The boss flag does not forbid an escape. An
    -- escape that went out, by the planner or the player, with the fight still
    -- going, was refused. After two refused escapes this fight is not fled again.
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
        local fleeable = not Fight.noEscape
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
                if not card or not card.resists then scanTarget = u break end
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
    if not Fight.chipped and phase == 0 and not alreadyFell and not allyCritical() and not dead and not breakClose() then
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
    end

    -- A damage Limit that marks the gauge goes on an open foe before the
    -- break, so the hits after it pour more stagger. The foe with the most
    -- gauge left takes it. It waits while the break is this round's.
    local function setupLimit()
        local best, foe, most = nil, nil, -1
        for _, s in ipairs(skills) do
            if spendsLimit(s) and s.known and s.known.breakDef and isHit(s, false)
                and pay(s) and not limitHeld(s) then
                for _, u in ipairs(open) do
                    local _, remain, empty = gaugeOfEnemy(u)
                    if (not empty) and (not u.broken) and (elementFactor(s, u) > 0) and (remain > most) then
                        best, foe, most = s, u, remain
                    end
                end
            end
        end
        if not best then return nil end
        local name = best.name or "limit"
        if aoeOf(best) then
            for _, u in ipairs(w.enemies) do
                if elementFactor(best, u) <= 0 then return nil end
            end
            return finishChoice(uid, best, "setup lb " .. name .. " " .. #open .. " foes", idsOf(open), true)
        end
        return finishChoice(uid, best, "setup lb " .. name .. " " .. (foe.name or "enemy"), { foe.id }, false)
    end
    if (phase == 0) and limitFight and (not dead) and (not allyCritical()) and (not breakClose()) then
        local choice = setupLimit()
        if choice then return choice end
    end

    -- A foe whose weakness this unit holds but can't pay for at any size. A
    -- weak hit that fits needs no Ether, even if a stronger one doesn't fit.
    local function unpaidWeakness(list)
        for _, u in ipairs(list) do
            local paid, unpaid = false, false
            for _, s in ipairs(skills) do
                if isHit(s, false) and (elementFactor(s, u) >= 3) then
                    if pay(s) then paid = true else unpaid = true end
                end
            end
            if unpaid and (not paid) then return true end
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
        if uk and ((uk.healScore or 0) > 0) then
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
        -- Is a short buff worth casting now? This caster's hit has to be weak next
        -- to the party's best, and the largest open gauge has to be breakable
        -- within about three rounds of what the party can pour into it.
        local timedOk = false
        if Fight.hitLanded then
            local bigFoe, bigRemain, bigGauge = nil, 0, 0
            for _, u in ipairs(open) do
                local gauge, remain = gaugeOfEnemy(u)
                if gauge > bigGauge then bigFoe, bigRemain, bigGauge = u, remain, gauge end
            end
            local ownBest, topBest, pour = 0, 0, 0
            for _, a in ipairs(w.allies) do
                if (not a.dead) and (a.acts ~= false) and (not heldOut(a)) then
                    local kit = (a.id == uid) and { spells = skills } or unitKit(a.id)
                    local amp = (a.id == uid) and (w.mp or 0) or (stat(a.id, PARAM.MP, false) or 0)
                    local mine, stag = 0, 0
                    for _, s in ipairs((kit and kit.spells) or {}) do
                        if isHit(s, false) and ((s.cost or 0) <= amp) then
                            local pow = offenseOf(s) or 0
                            if pow > mine then mine = pow end
                            if bigFoe then
                                local gained = staggerOf(s, bigFoe)
                                if gained > stag then stag = gained end
                            end
                        end
                    end
                    if a.id == uid then ownBest = mine end
                    if mine > topBest then topBest = mine end
                    pour = pour + stag
                end
            end
            timedOk = bigFoe and (ownBest <= (topBest * 0.6)) and (bigRemain <= (pour * 3)) or false
        end
        markExposed(w)
        local warnedKill = false
        for _, a in ipairs(w.allies or {}) do
            if a.exposed then warnedKill = true end
        end
        local kitSkills = skills
        if not limitFight then
            kitSkills = {}
            for _, s in ipairs(skills) do
                if not limitSkill(s) then kitSkills[#kitSkills + 1] = s end
            end
        end
        local picked = Kits.pick(kitSkills, {
            allies = w.allies, foes = foes, selfId = uid,
            actions = #(Fight.actions or {}), mp = w.mp or 0, maxMp = w.maxMp or 0,
            keep = keep, pay = (band() ~= "low"), healer = healer,
            claim = Fight.claim.kit, sent = Fight.kitOn,
            tossOk = locked and (not hitting) and (not Fight.chipped) and (tosses < 2),
            timedOk = timedOk, chipped = Fight.hitLanded and true or false,
            warned = warnedKill,
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
    if phase == 0 and not allyCritical() and not dead and not supportRested() and (not breakClose()) then
        local choice = castKit()
        if choice then return choice end
    end

    -- The kit is setup and comes before the chip, so a thrown item waits for it.
    -- An item from the bag carries a hit the bar cannot pay, in any fight.
    if (phase == 0) and not allyCritical() then
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
            appendLog("  fell: " .. was.name .. (was.raised and " (raised and down again before a menu)" or ""))
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

local function kitFallback(uid)
    if outOfControl(uid) then return nil end
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
    local function labeledHit(s)
        local name = s.name and s.name:lower() or ""
        local use = s.known and s.known.use
        local plain = (name == "attack") or ((s.attr == ATTR.FIGHT) and ((s.cost or 0) <= 0))
        local tagged = (use == "break") or (use == "cash")
        return (plain or tagged) and true or false
    end
    local best = nil
    for _, s in ipairs(usable) do
        local function ahead()
            if not best then return true end
            local ls, lb = labeledHit(s), labeledHit(best)
            if ls ~= lb then return ls end
            local okS, powS, brS = pcall(offenseOf, s)
            local okB, powB, brB = pcall(offenseOf, best)
            brS, brB = (okS and brS) or 0, (okB and brB) or 0
            if brS ~= brB then return brS > brB end
            powS, powB = (okS and powS) or 0, (okB and powB) or 0
            return powS > powB
        end
        if ahead() then best = s end
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
    clearFoeKeep()
    if Fight then Fight.stampCache = {} end
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
        local isBroken, left = broken(id), (breakLeft(id) or 1)
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
        pcall(function()
            local visions = {}
            for _, id in ipairs(friendIds()) do
                visions[#visions + 1] = unitName(id) .. " " .. tostring(visionIdOf(id) or "?")
            end
            local row = "visions: " .. table.concat(visions, ", ")
            log("%s", row)
            appendLog("  " .. row)
        end)
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
    if (not foe) and hurt and (hurt.dead or allyExposed(hurt)) then
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

-- battle_report.txt. Log only: nothing here picks a command, and nothing here
-- can stop one. A failure is logged once and the report stops for that step.
-- These read the game, so they run from a menu turn or the timer, never a hook.
Known.repRun = function(fn, ...)
    if not Known.report then return end
    local ok, err = pcall(fn, ...)
    if (not ok) and (not Known.repErr) then
        Known.repErr = true
        log("report step failed: %s", tostring(err))
        pcall(Known.report.note, Known.report, "report step failed: " .. tostring(err))
    end
end

-- A unit's table row. A body that has fallen still has its row.
Known.repRow = function(id)
    local F = Known.report and Known.report.fight
    if not F then return nil end
    F.rowOf = F.rowOf or {}
    if F.rowOf[id] then return F.rowOf[id] end
    local bfl = battleLib()
    if not (bfl and bfl:IsValid()) then return nil end
    local ok, rowId = pcall(function() return num(bfl:GetBattleUnitParameter(id, false):GetUnitId()) end)
    if ok and rowId then F.rowOf[id] = rowId end
    return F.rowOf[id]
end

-- The relation list can come back empty for enemies in the game, so the
-- enemies the fight has seen and this command's targets count too.
Known.repSnap = function(extra)
    local function unitOf(id, isFoe)
        local set = statuses(id)
        local hp = stat(id, PARAM.HP, false)
        return { name = isFoe and unitName(id) or Fight.nameOf(id), hp = hp, maxHp = stat(id, PARAM.HP, true),
            mp = stat(id, PARAM.MP, false), maxMp = stat(id, PARAM.MP, true), lb = stat(id, PARAM.LB, false),
            gauge = stat(id, PARAM.BREAK, false), maxGauge = stat(id, PARAM.BREAK, true), statuses = set,
            down = (hp == nil) or (hp <= 0) or ((Fight.unitDown and Fight.unitDown(id)) and true) or false }
    end
    local snap = { allies = {}, foes = {} }
    for _, id in ipairs(friendIds()) do
        if not (Fight.isSummon and Fight.isSummon(id)) then snap.allies[id] = unitOf(id, false) end
    end
    local function addFoe(id)
        if snap.foes[id] or snap.allies[id] then return end
        -- The summon is on the friend list, and a missed scan has put that
        -- same id on the enemy list. The report does not call it a foe.
        if Fight.summons and Fight.summons[id] then return end
        if Fight.isSummon and Fight.isSummon(id) then return end
        local hp = stat(id, PARAM.HP, false)
        if hp and hp > 0 then snap.foes[id] = unitOf(id, true) end
    end
    for _, id in ipairs(members(REL.ENEMY)) do addFoe(id) end
    for id in pairs(Fight.seenFoe or {}) do addFoe(id) end
    for _, id in ipairs(extra or {}) do addFoe(id) end
    return snap
end

-- Once per ally and enemy a fight: what the mod knows about them.
Known.repCards = function(snap)
    local F = Known.report.fight
    if not F then return end
    -- Each unit's table row. A hit can land after a body is gone.
    for _, list in ipairs({ snap.foes, snap.allies }) do
        for id in pairs(list) do Known.repRow(id) end
    end
    local function set(t)
        local o = {}
        for k in pairs(t or {}) do o[#o + 1] = tostring(k) end
        table.sort(o)
        return (#o > 0) and table.concat(o, ",") or "-"
    end
    for id, u in pairs(snap.foes) do
        local key = tostring(id) .. ":" .. tostring(u.name)
        if not F.cardSeen[key] then
            F.cardSeen[key] = true
            local card = mobOf({ id = id, name = u.name })
            local p = paramOf(id)
            local okU, unitId = pcall(function() return num(p:GetUnitId()) end)
            Known.report:write({
                string.format("  enemy %s, uid %s, row %s, level %s", tostring(u.name), tostring(id), tostring(okU and unitId), tostring(Known.foeLevel(id))),
                string.format("    weak %s; half %s; absorb %s; null %s; immune %s", set(card and card.weak), set(card and card.half),
                    set(card and card.absorb), set(card and card.no), set(card and card.ail)),
                string.format("    danger %s; hits %s; counter %s; resists %s; hp %s/%s, gauge %s/%s", (card and card.danger and table.concat(card.danger, ",")) or "-",
                    tostring(card and card.hits), tostring(card and card.counter), tostring(card and card.resists), tostring(u.hp), tostring(u.maxHp), tostring(u.gauge), tostring(u.maxGauge)),
                "    traits: " .. ((card and card.traits and table.concat(card.traits, " / ")) or "-"),
            })
        end
    end
    for id, u in pairs(snap.allies) do
        local key = "a" .. tostring(id)
        if (not F.cardSeen[key]) and (not u.down) then
            F.cardSeen[key] = true
            local p = paramOf(id)
            local function row(kind) return tostring(stat(id, kind, false)) end
            local okU, unitId = pcall(function() return num(p:GetUnitId()) end)
            local okV, vision = pcall(function() return num(p:GetEquipmentId(4, 0)) end)
            local lines = { string.format("  ally %s, uid %s, unit %s, vision %s: level %s, hp %s/%s, mp %s/%s, atk %s def %s int %s mind %s agi %s",
                tostring(u.name), tostring(id), tostring(okU and unitId), tostring(okV and vision), tostring(Known.allyLevel(id)), tostring(u.hp), tostring(u.maxHp),
                tostring(u.mp), tostring(u.maxMp), row(5), row(6), row(7), row(8), row(9)) }
            for _, s in ipairs(usableOf(id)) do
                local info = s.known or {}
                lines[#lines + 1] = string.format("    bar %s id %s: cost %s, power %s, stagger %s, hits %s, attr %s, dmg %s, element %s, target %s, use %s, kind %s%s",
                    tostring(s.name), tostring(s.id), tostring(s.cost), tostring(s.power), tostring(s.breakPower), tostring(s.hits), tostring(s.attr),
                    tostring(s.dmgType), tostring(info.element or s.element), tostring(s.target), tostring(info.use), tostring(s.kind), s.lbCost and (", gauges " .. tostring(s.lbCost)) or "")
            end
            Known.report:write(lines)
        end
    end
end

Known.repBegin = function()
    local diff, rates = nil, {}
    pcall(function()
        local lib = StaticFindObject("/Script/mucha.Default__CPP_BFL_SaveDataPlayer")
        if lib and lib:IsValid() then
            diff = num(lib:GetGameDifficulty())
            for _, k in ipairs({ "GetCurDifficultyHpRate", "GetCurDifficultyDamageTakenRate", "GetCurDifficultyDamageGivenRate" }) do
                local ok, v = pcall(function() return lib[k](lib) end)
                if ok then rates[#rates + 1] = (k:gsub("GetCurDifficulty", "")) .. " " .. tostring(num(v) or v) end
            end
        end
    end)
    Known.report:begin({ number = Fight.number, boss = Fight.boss,
        mode = (cfg.Echo and "Echo" or "No Mercy") .. (cfg.Enabled and "" or " (auto battle off)"),
        difficulty = "difficulty " .. tostring(diff) .. ((#rates > 0) and (" (" .. table.concat(rates, ", ") .. ")") or "") })
    local names = {}
    for _, e in ipairs(ownedRecovery() or {}) do names[#names + 1] = tostring(e.name) .. " x" .. tostring(e.count) end
    Known.report:write("  bag: " .. table.concat(names, ", "))
end

-- The player's commands count like the mod's: in the report and in learn.lua.
Known.repHandFlush = function()
    local list = Fight.repHand
    if not list or #list == 0 then return end
    Fight.repHand = {}
    local R = Known.report
    if not R.fight then Known.repBegin() end
    for _, h in ipairs(list) do
        local snap = Known.repSnap(h.targets)
        local who = (h.uid and h.uid >= 0) and Fight.nameOf(h.uid) or "you"
        local row = (not h.isItem) and skillOf(h.id) or nil
        local kind = h.kind or (row and row.kind) or "other"
        if kind == "ether" then kind = "mp" end
        local targets = {}
        for _, tid in ipairs(h.targets or {}) do
            local foe, friend = snap.foes[tid], snap.allies[tid]
            local called = (not foe) and (not friend) and Fight.summons and Fight.summons[tid]
            local t = { name = (foe and foe.name) or (friend and friend.name) or (called and unitName(tid)) or tostring(tid) }
            if foe and row and kind == "damage" then t.factor = elementFactor(row, { id = tid, name = foe.name }) end
            targets[#targets + 1] = t
        end
        local me = h.uid and snap.allies[h.uid]
        R:decide({ byHand = not h.echo, echo = h.echo, who = who, uid = h.uid, phase = h.phase, round = Fight.rounds, mp = me and me.mp, maxMp = me and me.maxMp, lb = me and me.lb,
            name = h.name, id = h.id, kind = kind, reason = h.echo and (h.echoWhy or "echo") or "sent by the player", cost = h.cost, attr = h.attr, dmgType = h.dmgType, targets = targets })
    end
end

Known.repDecide = function(uid, choice, phase)
    local R = Known.report
    if not R.fight then Known.repBegin() end
    Known.repHandFlush()
    local snap = Known.repSnap(choice.targets)
    R:field(snap)
    Known.repCards(snap)
    local me = snap.allies[uid]
    local mp = me and me.mp or 0
    local could, weakBy, canHeal, canRaise, isHealer = {}, {}, false, false, false
    local shortHeal, shortRaise, shortWeak = nil, nil, {}
    local limitReady, bestValue, bestName = nil, nil, nil
    local brokenFoes = {}
    for id, f in pairs(snap.foes) do
        if (f.hp or 0) > 0 and (f.gauge or 1) <= 0 then brokenFoes[id] = f end
    end
    local function hitValue(s)
        local top = 0
        for id, f in pairs(brokenFoes) do
            local x = elementFactor(s, { id = id, name = f.name })
            local v = (s.power or 0) * ((x >= 3) and 1.5 or x)
            if v > top then top = v end
        end
        return top
    end
    local usable = usableOf(uid)
    for _, s in ipairs(usable) do
        local cost = s.cost or 0
        if cost <= mp then
            if s.kind == "heal" and s.attr ~= ATTR.ITEM then canHeal = true end
            if s.kind == "revive" then canRaise = true end
            -- A Limit that marks the gauge waits for an open foe, so it is
            -- not a Limit left unused on a stagger.
            if s.attr == ATTR.LB and s.kind == "damage" and not (s.known and s.known.breakDef) then
                limitReady = limitReady or s.name
            end
            if s.kind == "damage" and next(brokenFoes) then
                local v = hitValue(s)
                if (not bestValue) or v > bestValue then bestValue, bestName = v, s.name end
            end
            local fit = {}
            if s.kind == "damage" then
                for id, f in pairs(snap.foes) do
                    if (f.hp or 0) > 0 then
                        local x = elementFactor(s, { id = id, name = f.name })
                        fit[#fit + 1] = tostring(f.name) .. " x" .. tostring(x)
                        if x >= 3 and s.attr ~= ATTR.SUMMON then weakBy[id] = weakBy[id] or s.name end
                    end
                end
            end
            could[#could + 1] = string.format("%s %s%s", tostring(s.name), tostring(cost), (#fit > 0) and (" (" .. table.concat(fit, ", ") .. ")") or "")
        elseif s.attr ~= ATTR.SUMMON and s.attr ~= ATTR.LB and s.attr ~= ATTR.ITEM then
            -- On the bar, but MP is short. Read against what went out, below.
            if s.kind == "heal" then shortHeal = shortHeal or s.name end
            if s.kind == "revive" then shortRaise = shortRaise or s.name end
            if s.kind == "damage" then
                for id, f in pairs(snap.foes) do
                    if (f.hp or 0) > 0 and elementFactor(s, { id = id, name = f.name }) >= 3 then
                        shortWeak[id] = shortWeak[id] or s.name
                    end
                end
            end
        end
        if s.kind == "heal" and s.attr == ATTR.MAGIC then isHealer = true end
    end
    local targets = {}
    for _, tid in ipairs(choice.targets or {}) do
        local foe, friend = snap.foes[tid], snap.allies[tid]
        local called = (not foe) and (not friend) and Fight.summons and Fight.summons[tid]
        local t = { name = (foe and foe.name) or (friend and friend.name) or (called and unitName(tid)) or tostring(tid) }
        if foe and choice.kind == "damage" then
            t.factor = elementFactor(skillOf(choice.id) or choice, { id = tid, name = foe.name })
            t.weakPaid = weakBy[tid]
        end
        if friend and friend.maxHp and friend.maxHp > 0 then t.pct = math.floor(100 * (friend.hp or 0) / friend.maxHp + 0.5) end
        targets[#targets + 1] = t
    end
    local claims = {}
    for id in pairs((Fight.claim and Fight.claim.heal) or {}) do
        local u = snap.allies[id]
        claims[#claims + 1] = tostring(u and u.name or id)
    end
    local function names(list)
        local o = {}
        for _, id in ipairs(list or {}) do
            local u = snap.allies[id] or snap.foes[id]
            o[#o + 1] = tostring(u and u.name or id)
        end
        return table.concat(o, " ")
    end
    local kind = choice.kind or "other"
    if choice.itemUse == "hp" or choice.itemUse == "both" then kind = "heal" end
    if choice.itemUse == "revive" then kind = "revive" end
    if choice.itemUse == "mp" then kind = "mp" end
    if kind == "item" and type(choice.reason) == "string" and choice.reason:find("^throw") then kind = "throw" end
    -- Needed something MP couldn't pay, with an Ether in the bag, and did
    -- something else. Log only: this is evidence for the Ether rule, not a rule.
    -- A boss or a danger move only. Elsewhere the job is to hit hard and often
    -- and stay alive, and an Ether turn isn't worth weighing.
    local short = {}
    if (kind ~= "mp") and Fight.threat then
        local etherIn = false
        for _, e in ipairs(ownedRecovery() or {}) do
            if e.kind == "mp" or (e.mp and not e.hp) then etherIn = true end
        end
        if etherIn then
            local lowU, downN = nil, 0
            for id, u in pairs(snap.allies) do
                if u.down then
                    downN = downN + 1
                elseif u.maxHp and u.maxHp > 0 and (u.hp or 0) / u.maxHp < 0.30 and not (Fight.claim and Fight.claim.heal and Fight.claim.heal[id]) then
                    lowU = u
                end
            end
            local spent = Fight.claim and Fight.claim.etherRound
            local function add(need, what) short[#short + 1] = { need = need, what = what, spent = spent and true or false } end
            local caring = (kind == "heal") or (kind == "revive") or (kind == "cure")
            if lowU and shortHeal and (not canHeal) and (not caring) then add("heal", shortHeal .. " for " .. tostring(lowU.name)) end
            if (downN > 0) and shortRaise and (not canRaise) and (not caring) then add("raise", shortRaise) end
            if choice.kind == "damage" then
                for _, t in ipairs(targets) do
                    if t.factor and t.factor < 3 and (not t.weakPaid) then
                        for _, tid in ipairs(choice.targets or {}) do
                            if shortWeak[tid] and snap.foes[tid] and snap.foes[tid].name == t.name then
                                add("weakness", shortWeak[tid] .. " on " .. tostring(t.name))
                                break
                            end
                        end
                    end
                end
            end
        end
    end
    local row = skillOf(choice.id)
    -- A Multicast row is its own row in the game's table, with the same name.
    local function allRowFor(wanted)
        local allNames = Known.allMagNames or {}
        if not Known.allMagNames then
            for _, r in pairs(SkillIdx or {}) do
                if r.appliesAll and r.name then allNames[r.name] = true end
            end
            Known.allMagNames = allNames
        end
        for _, s in ipairs(usable) do
            if (s.cost or 0) <= mp and s.attr == ATTR.MAGIC and s.kind == wanted and allNames[s.name] then return s.name end
        end
        return nil
    end
    local multicastSweep, multicastHeal = nil, nil
    if not choice.isAll then
        local foesUp, low = 0, true
        for _, f in pairs(snap.foes) do
            if (f.hp or 0) > 0 then
                foesUp = foesUp + 1
                if (f.gauge or 0) <= 0 or (f.maxGauge or 0) <= 0 or f.gauge / f.maxGauge > 0.25 then low = false end
            end
        end
        if foesUp >= 2 and low then multicastSweep = allRowFor("damage") end
        local up, hurt = 0, 0
        for _, a in pairs(snap.allies) do
            if not a.down then
                up = up + 1
                if a.maxHp and a.maxHp > 0 and (a.hp or 0) / a.maxHp < 0.5 then hurt = hurt + 1 end
            end
        end
        if up >= 2 and hurt * 2 > up then multicastHeal = allRowFor("heal") end
    end
    local chosenValue = (kind == "damage") and next(brokenFoes) and hitValue(row or choice) or nil
    R:decide({ short = short, now = Fight.order and names(Fight.order.current) or nil, limitReady = limitReady, value = chosenValue, bestValue = bestValue, bestName = bestName,
        multicastSweep = multicastSweep, multicastHeal = multicastHeal, who = Fight.nameOf(uid), uid = uid, phase = phase, round = Fight.rounds, mp = me and me.mp, maxMp = me and me.maxMp, lb = me and me.lb,
        name = choice.name, id = choice.id, kind = kind, reason = choice.reason, cost = choice.cost, attr = choice.attr,
        dmgType = row and row.dmgType, targets = targets, could = could, isAll = choice.isAll, canHeal = canHeal, canRaise = canRaise,
        isHealer = isHealer, itemHeal = (choice.itemUse == "hp") or (choice.itemUse == "both"),
        next = Fight.order and ("now " .. names(Fight.order.current) .. " | next " .. names(Fight.order.next)) or nil,
        risk = names(Fight.risk), claims = table.concat(claims, ",") })
end

Known.repFinish = function()
    local R = Known.report
    if not R.fight then return end
    Known.repHandFlush()
    local measured = nil
    if Known.measure and Fight.dealtBook then
        measured = Known.measure.lines(Fight.dealtBook, function(from, skill)
            local row = skillOf(skill)
            return tostring(Fight.nameOf(from)) .. " " .. tostring(row and row.name or skill)
        end)
        table.insert(measured, 1, "what hit hardest:")
    end
    R:finish({ rounds = Fight.rounds, wheelOpen = Fight.repWheelOpen, wheelSent = Fight.repWheelSent, lines = measured })
    Fight.repWheelOpen, Fight.repWheelSent = 0, 0
end

local flushWarn

-- LevelGate. Enemy catalog ids seen this fight, and the exp to write once
-- the game pays out. seen is keyed by slot and catalog id, so a later wave
-- or an add in a dead monster's slot still counts. cuts marks the characters
-- whose gain is 0; a kept payout is never rewritten.
function Growth.install()
local bflUnit, bflSaveUnit
local function unitLib()
    if not (bflUnit and bflUnit:IsValid()) then
        bflUnit = StaticFindObject("/Script/mucha.Default__CPP_BFL_Unit")
    end
    return bflUnit
end
local function saveUnitLib()
    if not (bflSaveUnit and bflSaveUnit:IsValid()) then
        bflSaveUnit = StaticFindObject("/Script/mucha.Default__CPP_BFL_SaveDataUnit")
    end
    return bflSaveUnit
end
local Gate = { seen = {}, targets = {}, cuts = {}, writing = false, missTold = false }

local function playableLevel(unitId)
    local lib = unitLib()
    if not (lib and lib:IsValid()) then return nil end
    local ok, v = pcall(function() return lib:GetPlayableUnitLevel(unitId) end)
    return ok and num(v) or nil
end

local function saveExp(unitId)
    local lib = saveUnitLib()
    if not (lib and lib:IsValid()) then return nil end
    local ok, v = pcall(function() return lib:GetSaveDataUnitExperience(unitId) end)
    return ok and num(v) or nil
end

local function writeExp(unitId, exp)
    local lib = unitLib()
    if not (lib and lib:IsValid()) then return end
    Gate.writing = true
    pcall(function() lib:SetPlayableUnitExperience(unitId, exp, true) end)
    Gate.writing = false
end

local function growthIds()
    local ids = {}
    for _, id in pairs(Gate.seen) do ids[#ids + 1] = id end
    return ids
end

-- nil when a monster's level was not read. The payout is then left alone.
local function growthMobs()
    local ids = growthIds()
    if #ids == 0 or not Known.growth then return nil end
    local mobs, missing = {}, false
    for _, id in ipairs(ids) do
        local row = Known.growth[id]
        if not row or type(row.level) ~= "number" then missing = true
        else mobs[#mobs + 1] = { level = row.level } end
    end
    if missing or #mobs == 0 then return nil end
    return mobs
end

function Growth.enemy(uid)
    if not (cfg.LevelGate and Fight and uid) then return end
    if Fight.summons and Fight.summons[uid] then return end
    local id = catalogOf(uid)
    if id then Gate.seen[tostring(uid) .. ":" .. tostring(id)] = id end
end

function Growth.field()
    if not (cfg.LevelGate and Fight and Fight.active) then return end
    local bfl = battleLib()
    if not (bfl and bfl:IsValid()) then return end
    for n = 0, 15 do
        if not (Fight.summons and Fight.summons[n]) then
            local ok, p = pcall(function() return bfl:GetBattleUnitParameter(n, false) end)
            if ok and p and p.IsValid and p:IsValid() then
                local okR, rel = pcall(function() return p:GetRelation() end)
                if okR and num(rel) == REL.ENEMY then Growth.enemy(n) end
            end
        end
    end
end

-- The payout comes during the result, before the fight closes. After the
-- close, nothing is held, so exp from an item or a quest is never cut by
-- the last fight's monsters, including after a loss or an escape.
function Growth.close()
    Gate.seen, Gate.targets, Gate.cuts = {}, {}, {}
end

function Growth.newFight()
    Gate.seen, Gate.targets, Gate.cuts, Gate.missTold, Gate.sigTold = {}, {}, {}, false, false
end

local function growthTarget(unitId, level, before, after)
    if Gate.targets[unitId] ~= nil then return Gate.targets[unitId] end
    if not (cfg.LevelGate and Growth.keeps and unitId and level and before and after) then return nil end
    local mobs = growthMobs()
    if not mobs then
        if #growthIds() > 0 and not Gate.missTold then
            Gate.missTold = true
            log("level gate could not read the monsters")
        end
        return nil
    end
    local keeps = Growth.keeps(level, mobs)
    if keeps == nil then return nil end
    local target = Growth.apply(before, after, keeps)
    Gate.targets[unitId] = target
    Gate.cuts[unitId] = (target ~= after) or nil
    if target ~= after then
        log("level gate: unit %s level %s gain 0", tostring(unitId), tostring(level))
    end
    return target
end

local function wipeGains(row)
    local function wipe(container)
        if type(container) ~= "userdata" then return end
        pcall(function()
            if container.Empty then container:Empty()
            elseif container.Clear then container:Clear() end
        end)
    end
    wipe(row.increasedParameters)
    wipe(row.addSkillList)
    wipe(row.extraAddSkillList)
end

local function patchGrowthResult(data)
    if not (cfg.LevelGate and data and data.unitDataList and data.unitDataList.ForEach) then return end
    local cut, kept = 0, 0
    pcall(function()
        data.unitDataList:ForEach(function(_, entry)
            local row = unwrap(entry)
            if type(row) ~= "userdata" and type(row) ~= "table" then return end
            local id = num(row.UnitId)
            local level = num(row.beforeBattleLevel)
            local before = num(row.beforeBattleExp)
            local after = num(row.afterBattleExp)
            if not (id and level and before and after) then return end
            local target = growthTarget(id, level, before, after)
            if target == nil then return end
            if target < after then
                cut = cut + 1
                pcall(function() row.afterBattleExp = target end)
                pcall(function() row.afterBattleLevel = level end)
                wipeGains(row)
                local now = saveExp(id)
                if now and now ~= target then writeExp(id, target) end
            elseif target > before then
                kept = kept + 1
            end
        end)
    end)
    if cut > 0 and kept == 0 then
        pcall(function()
            data.totalExperience = 0
            data.baseExperience = 0
            data.bonusExperience = 0
        end)
    end
end

function Growth.hook()
    if not Growth.keeps then return end
    local function guard(label, fn)
        local ok, err = pcall(fn)
        if not ok then log("level gate failed: %s: %s", label, tostring(err)) end
    end
    guard("payout", function()
    RegisterHook("/Script/mucha.CPP_BFL_Unit:SetPlayableUnitExperience", function(_, unitId, exp)
        if Gate.writing or not cfg.LevelGate then return end
        local id = num(unitId and unitId:get())
        local incoming = num(exp and exp:get())
        if not id or incoming == nil then
            if not Gate.sigTold then
                Gate.sigTold = true
                log("level gate could not read the payout")
            end
            return
        end
        local target = Gate.targets[id]
        if target == nil then
            target = growthTarget(id, playableLevel(id), saveExp(id), incoming)
        end
        -- Only a cut is written. A kept payout stays as the game sends it.
        if target ~= nil and Gate.cuts[id] and incoming > target then exp:set(target) end
    end)
    end)
    guard("result", function()
    RegisterHook("/Script/mucha.CPP_UI_BattleSubsystem:HandleBeginResult", function(_, value)
        if not cfg.LevelGate then return end
        pcall(function()
            local row = value:get()
            if row and row.resultData then patchGrowthResult(row.resultData) end
        end)
    end)
    end)
    guard("result end", function()
    RegisterHook("/Script/mucha.CPP_BtlDelEventResult:OnExecuteResultEnd", function()
        -- The payout can still be inside this call. Drop the fight after it returns.
        gameDelay(0, function()
            Growth.close()
        end)
    end)
    end)
end
    if Growth.hook then Growth.hook() end
end
do
    local okGrowth, errGrowth = pcall(Growth.install)
    if not okGrowth then log("level gate failed: %s", tostring(errGrowth)) end
end

local function finishBattle()
    if not Fight.active then return end
    if Growth.close then Growth.close() end
    Known.repRun(Known.repFinish)
    Fight.active = false
    if Menu.stopPace then Menu.stopPace() end
    Fight.hitSeen, Fight.hitHold, Fight.killHold = nil, nil, false
    Fight.orderPending, Fight.orderFresh = nil, false
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
    flushWarn()
    local line = string.format("Auto, %d commands. %s. %s.", turns, broke, fell)
    appendLog("-- " .. line)
    appendLog("")
    if Known.report then pcall(Known.report.flush, Known.report) end
    log("battle %d done: %s", Fight.number, line)
    Fight.actions, Fight.casts, Fight.castOrder = {}, {}, {}
    Fight.broke, Fight.fell, Fight.prev, Fight.last = {}, {}, {}, nil
end

local function ensureBattle()
    if Fight.active then return end
    if Growth.newFight then Growth.newFight() end
    Fight.active = true
    if Menu.pace then Menu.pace.done, Menu.pace.seqTold, Menu.pace.armed = false, nil, false end
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
    Fight.wheelTicks, Fight.wheelSkips = 0, 0
    Fight.poured, Fight.down, Fight.downTold, Fight.relax, Fight.gaugeScale, Fight.brokeOn, Fight.gaugeSure, Fight.gaugeWas = {}, {}, {}, {}, {}, {}, {}, {}
    Fight.downSince, Fight.phaseSeen, Fight.bonusSeen, Fight.lastHit = nil, 0, false, nil
    Fight.line = false
    Fight.prevHit = nil
    Fight.building = nil
    Fight.kits = {}
    Fight.claim = { heal = {}, cure = {}, revive = {}, hone = {}, ether = {}, scan = {}, kit = {}, etherRound = false, guard = false, esper = false, lb = false }
    Fight.kitOn = {}
    Fight.drawSeen, Fight.cureTry, Fight.cureMiss, Fight.drawRound = {}, {}, {}, {}
    Fight.refell, Fight.raisedRound, Fight.wiped = {}, {}, false
    Fight.kindMiss, Fight.kindNull, Fight.kindHit, Fight.hitProbe = {}, {}, {}, nil
    Fight.kindMissBy, Fight.skillZero = {}, {}
    Fight.learned = {}
    Fight.retry = {}
    Fight.stampCache = {}
    Fight.healRate, Fight.healProbe = {}, nil
    Fight.debuffWatch = nil
    Fight.guardOn = {}
    Fight.veil = nil
    Fight.supportRun = {}
    Fight.foeLow, Fight.hitsSince, Fight.stalemateTold = {}, 0, false
    Fight.luckToss = {}
    Fight.debuffOn, Fight.debuffSeen, Fight.debuffTold = {}, {}, {}
    Fight.debuffIds = {}
    Fight.went, Fight.rounds, Fight.seenFoe = {}, 0, {}
    Fight.planTag, Fight.afterBonus = nil, false
    Fight.fieldTold = false
    Fight.chipped = false
    Fight.hitLanded = false
    Fight.stance = {}
    Fight.stanceEnded = {}
    Fight.escapeSent = nil
    Fight.escapeTold = nil
    Fight.noEscape = nil
    Fight.esperOut = nil
    Fight.summonLive = false
    Fight.esperTold = false
    Fight.esperCommon = false
    Fight.limitCommon = false
    Fight.esperGateWhy, Fight.esperHoldLine = nil, nil
    Fight.esperSkip = {}
    Fight.limitUntagged = {}
    Fight.limitSkip = {}
    Fight.cureHeld = false
    Fight.healLeft = {}
    Fight.hitSeen = Fight.hitHold or {}
    Fight.hitHold = nil
    Fight.killHold = false
    Fight.killRangeAt = {}
    Fight.healMark = {}
    Fight.healAt = {}
    Fight.statusTold = {}
    Fight.slowSince, Fight.slowTry, Fight.slowTold, Fight.slowUsed = {}, nil, {}, {}
    Fight.underLine = false
    Fight.downNow = {}
    Fight.warn = {}
    Fight.warnCancel = 0
    Fight.warnLand = 0
    Fight.lbRead = {}
    Fight.lbTold = {}
    Fight.lbRows = {}
    -- A low bar from the last fight is not a wipe in this one.
    Fight.mpAnchor, Fight.mpLow, Fight.mpBack, Fight.mpFed = {}, {}, {}, {}
    Fight.roundAt = 0
    Fight.unmarked = false
    Fight.unmarkedTold = false
    Fight.recoverTold = false
    Fight.entryTold = false
    Fight.entrySet = false
    Fight.entryCare = nil
    Fight.entryStatus = false
    Fight.finishNote = {}
    Fight.mobCards, Fight.dealtBook = nil, nil
    Fight.dealtOpen = nil
    Fight.hitPrint = {}
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
        local grown = (Gauges.rise and Gauges.rise(book, poured)) or (book + 1)
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
    -- A live BreakPoint is the gauge. The ledger marks and releases a break
    -- only for a living enemy whose read is missing. A body with no
    -- parameter is gone, and there is no gauge left to correct.
    local function ledgerOnly(id)
        if not paramOf(id) then return false end
        return breakLeft(id) == nil
    end
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
            if fresh and Fight.brokeOn[id] and ledgerOnly(id) then
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
            if ledgerOnly(id) and (type(scaled) == "number") and (scaled > 0) and (poured > 0) and (poured < scaled) then
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
            if best and (bestScore >= 1) and ledgerOnly(best) then
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
            if gauge and (gauge > 0) and (poured >= gauge) and (not broken(id)) and ledgerOnly(id) then
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
            for _, id in ipairs(ids) do
                if ledgerOnly(id) then releaseGauge(id) end
            end
            Fight.downSince = nil
        end
    end
end

local settleWarn
local function noteRound(uid)
    Fight.went = Fight.went or {}
    if uid and (uid >= 0) then Fight.went[uid] = true end
    -- A round is one turn for every party member who can take one. A summon
    -- and an ally whose status takes the turn are not waited on. A round
    -- never runs past two passes of the party, so nothing can hold it open.
    local actors, went, full = 0, 0, 0
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
            local can = (not held) or Fight.went[id]
            if can then full = full + 1 end
            if kit and kit.spells and (#kit.spells > 0) and can then
                actors = actors + 1
                if Fight.went[id] then went = went + 1 end
            end
        end
    end
    local since = #(Fight.actions or {}) - (Fight.roundAt or 0)
    if (actors > 0) and ((went >= actors) or (since >= actors * 2)) then
        local prev = Fight.rounds or 0
        local nowN = #(Fight.actions or {})
        -- The spell filter can end this round before every living ally has
        -- acted. A kill-range heal from the round that just ended stays
        -- marked, or the next slot heals the same ally again.
        local short = (full > actors) and (went < full) and (since < (full * 2))
        Fight.roundAt = nowN
        Fight.went = {}
        Fight.healLeft = {}
        Fight.rounds = prev + 1
        if Fight.claim then
            Fight.claim.heal = {}
            Fight.claim.cure = {}
            Fight.claim.itemHeal = {}
            Fight.claim.ether = {}
            Fight.claim.etherRound = false
            Fight.claim.kit = {}
        end
        if short and Fight.killRangeAt then
            for _, rec in pairs(Fight.killRangeAt) do
                if (type(rec) == "table") and (rec.round == prev) and ((nowN - (rec.at or nowN)) < full) then
                    rec.round = Fight.rounds
                end
            end
        end
        Fight.afterBonus = false
    end
end

local function markSummon(skill, turns, caster, sid)
    if not (skill and skill.attr == ATTR.SUMMON) then return end
    local fact = (Espers.lookup and Espers.lookup(skill.name)) or nil
    local stay = turns or (fact and fact.turns)
    local prev = Fight.esperOut
    local same = prev and ((prev.sid and (prev.sid == (sid or skill.id))) or (prev.name == (skill.name or "summon")))
    Fight.esperOut = {
        at = (same and prev.at) or #(Fight.actions or {}),
        turns = stay,
        name = skill.name or "summon",
        told = false,
        unit = (fact and fact.unit) or (same and prev.unit) or nil,
        seen = same and prev.seen or false,
        acted = same and prev.acted or false,
        who = same and prev.who or nil,
        caster = caster or (same and prev.caster) or nil,
        sid = sid or skill.id or (same and prev.sid) or nil,
    }
    Fight.summoned = true
    Fight.claim = Fight.claim or {}
    Fight.claim.esper = true
end

--------------------------------------------------------------------------------
-- Echo. Each character's last turn by hand goes out again, every decide and
-- every action in it, Dualcast and all. Only a target that can no longer
-- take it changes. echo.lua keeps the tape. Everything here is on Known:
-- the main chunk has no locals left.
--------------------------------------------------------------------------------

-- Every Echo event: one line in UE4SS.log, and with Reporting on, a line in
-- the fight and a count in its report. The report part waits for the game
-- thread, since a hook may call this and the report reads the battle.
function Known.echoEvent(kind, text)
    text = tostring(text)
    log("echo: %s: %s", kind, text)
    if not (Known.report and Fight and Fight.active) then return end
    gameDelay(0, function()
        if not (Known.report and Fight and Fight.active) then return end
        Known.repRun(function()
            if not Known.report.fight then Known.repBegin() end
            Known.report:echo(kind, text)
        end)
    end)
end

-- EchoKeep: the tape is echo.txt in the mod folder, written each time a turn
-- or a wheel is kept, and read once at launch.
Known.echoPath = DIR .. "/echo.txt"
-- Fight numbers start over each launch, so a kept turn's fight is tagged with the launch too.
Known.echoLaunch = tostring(os.time())
function Known.echoSave()
    if not (cfg.EchoKeep and Known.echo and Known.echoTape) then return end
    local ok, err = pcall(function()
        local f, why = io.open(Known.echoPath, "w")
        if not f then error(why or "could not open") end
        f:write(Known.echo.encode(Known.echoTape))
        f:close()
    end)
    if not ok then log("echo: tape not saved: %s", tostring(err)) end
end
function Known.echoLoad()
    if not (cfg.EchoKeep and Known.echo) then return end
    local f = io.open(Known.echoPath, "r")
    if not f then
        log("echo: no tape saved yet")
        return
    end
    local text = f:read("a")
    f:close()
    local tape, why = Known.echo.decode(text)
    if not tape then
        log("echo: tape not read (%s); starting empty. The file is replaced at the next turn kept.", tostring(why))
        return
    end
    Known.echoTape = tape
    log("echo: tape loaded: %s", Known.echo.summary(tape))
end

-- A decide, read into plain data. Only the decide's own value is read.
function Known.echoRead(v)
    local out = {
        cmdType = num(v.CmdType) or 0,
        notConsume = v.isNotConsume and true or false,
        calcOrder = v.doCalcOrder ~= false,
        command = num(v.CommandId) or -1,
        keys = {}, entries = {},
    }
    local list = v.cmdDecideDataList
    if list and list.ForEach then
        list:ForEach(function(_, e)
            local d = unwrap(e)
            if not d then return end
            local entry = {
                id = num(d.actionId), unit = num(d.actionUnitUniqueId),
                item = d.isUseItem and true or false, all = d.IsAll and true or false,
                pCat = d.ParentActionKey and num(d.ParentActionKey.Category) or 1,
                pId = d.ParentActionKey and num(d.ParentActionKey.ID) or 0,
                params = {}, targets = {},
            }
            if d.ParameterList and d.ParameterList.ForEach then
                d.ParameterList:ForEach(function(_, x)
                    local n = num(x)
                    if n then entry.params[#entry.params + 1] = n end
                end)
            end
            local raw = d.targetUnitUniqueIdList
            if raw and raw.ForEach then
                raw:ForEach(function(_, x)
                    local n = num(unwrap(x))
                    if n and (n >= 0) then entry.targets[#entry.targets + 1] = { id = n } end
                end)
            end
            if entry.id then out.entries[#out.entries + 1] = entry end
        end)
    end
    if v.actionKeys and v.actionKeys.ForEach then
        v.actionKeys:ForEach(function(_, e)
            local k = unwrap(e)
            if k then out.keys[#out.keys + 1] = { num(k.Category) or 0, num(k.ID) or 0 } end
        end)
    end
    return out
end

-- The unit a decide names, for telling one turn from the next.
function Known.echoActor(v)
    local actor = nil
    local list = v.cmdDecideDataList
    if list and list.ForEach then
        list:ForEach(function(_, e)
            if actor then return end
            local d = unwrap(e)
            if d then actor = num(d.actionUnitUniqueId) end
        end)
    end
    return actor
end

-- Friend or foe, for a fallen unit too.
function Known.echoRelation(id)
    local bfl = battleLib()
    if not (bfl and bfl:IsValid()) then return nil end
    for _, alive in ipairs({ true, false }) do
        local ok, p = pcall(function() return bfl:GetBattleUnitParameter(id, alive) end)
        if ok and p and p.IsValid and p:IsValid() then
            local okR, rel = pcall(function() return p:GetRelation() end)
            if okR and num(rel) then return num(rel) end
        end
    end
    return nil
end

function Known.echoName(id, isItem)
    if isItem then
        local row = ItemIdx and ItemIdx[id] or nil
        return (row and row.name) or ("item " .. tostring(id))
    end
    local row = skillOf(id)
    return (row and row.name) or ("command " .. tostring(id))
end

-- A command the player picked from that unit's menu, or on the wheel, goes
-- on the tape. The game closes the menu before the decide arrives, so the
-- mark is the last menu's unit, not an open menu. A command the game made for
-- a unit whose status takes the turn, and a summon's turn, are not kept.
-- Only while Echo is the mode, with auto battle on or off. In any other
-- mode nothing is taped, and the tape is left as it was.
function Known.echoKeep(v, uid, onWheel)
    local E, tape = Known.echo, Known.echoTape
    if not cfg.Echo then return end
    if not (E and tape and uid and (uid >= 0)) then return end
    if not (onWheel or (Menu.actor == uid)) then
        Known.echoEvent("skipped", string.format("%s: no menu of theirs was open (last menu %s)", Fight.nameOf(uid), tostring(Menu.actor)))
        return
    end
    if outOfControl(uid) then
        Known.echoEvent("skipped", Fight.nameOf(uid) .. ": not under your control")
        return
    end
    -- A summoned unit's turns are not taped. An ally who joined after the
    -- fight began is taped like anyone else.
    if Fight.isSummon and Fight.isSummon(uid) then
        Known.echoEvent("skipped", Fight.nameOf(uid) .. ": a summon")
        return
    end
    local d = Known.echoRead(v)
    if #d.entries == 0 then return end
    d.fight = Known.echoLaunch .. ":" .. tostring(Fight.number)
    for _, e in ipairs(d.entries) do
        for _, t in ipairs(e.targets) do
            if t.id == uid then
                t.side = "self"
            elseif Fight.seenFoe and Fight.seenFoe[t.id] then
                t.side = "foe"
                t.name = Fight.nameOf(t.id)
            else
                local rel = Known.echoRelation(t.id)
                if rel == REL.ENEMY then
                    t.side = "foe"
                    t.name = Fight.nameOf(t.id)
                elseif rel == REL.FRIEND then
                    t.side = "ally"
                    t.name = Fight.nameOf(t.id)
                else
                    t.side = "?"
                end
            end
        end
    end
    local who = Fight.nameOf(uid)
    if onWheel then
        Known.echoEvent("skipped", string.format("wheel, %s by %s: the wheel is never taped", E.describe(d, Known.echoName), who))
        return
    end
    local tapes, what = Known.echoTapes(d)
    if not tapes then
        Known.echoEvent("skipped", string.format("%s: %s is not taped; the last turn on record stays", who, tostring(what)))
        return
    end
    local aims = {}
    for _, e in ipairs(d.entries) do
        for _, t in ipairs(e.targets) do aims[#aims + 1] = tostring(t.name or t.side) end
    end
    local at = (#aims > 0) and (" -> " .. table.concat(aims, ", ")) or ""
    do
        -- A normal-phase command starts the turn. Another phase right after
        -- the same unit's command carries it on.
        local prev = Known.echoPrev
        local streak = ((d.cmdType or 0) ~= 0) and prev and (prev.actor == uid) and true or false
        local keepTo = nil
        if streak and (not prev.hand) and Known.echoRun and (Known.echoRun.who == who) then keepTo = Known.echoRun.n end
        local n = E.note(tape, who, d, streak, keepTo)
        Known.echoEvent("kept", string.format("%s's turn, decide %d%s: %s%s", who, n or 0,
            streak and " (same turn)" or " (new turn)", E.describe(d, Known.echoName), at))
    end
    Known.echoSave()
end

-- A raise, by the same marks the ledger uses for a hand command: the row's
-- revive effect or fallen-ally target, its known use, or the item book.
function Known.echoRaise(e)
    if e.item then
        if Items.listed and (Items.listed(Known.echoName(e.id, true)) == "revive") then return true end
        local irow = ItemIdx and ItemIdx[e.id] or nil
        local srow = irow and irow.skillId and skillOf(irow.skillId) or nil
        if not srow then return false end
        local ok, kind = pcall(classify, srow)
        return ok and (kind == "revive")
    end
    local row = skillOf(e.id)
    if not row then return false end
    local info = knownOf(row)
    if info and ((info.use == "revive") or (info.use == "lb-revive")) then return true end
    local ok, kind = pcall(classify, row)
    return ok and (kind == "revive")
end

-- Items, raises, Limit Bursts, and Esper calls are never taped: each is for
-- the moment it was used, not a move to repeat. They stay the player's. nil and the action's name when the decide
-- holds one, true when it can go on the tape.
function Known.echoTapes(d)
    for _, e in ipairs((d and d.entries) or {}) do
        if e.item then return nil, Known.echoName(e.id, true) end
        if Known.echoRaise(e) then return nil, Known.echoName(e.id, false) end
        local row = skillOf(e.id)
        if row and (row.attr == ATTR.SUMMON) then return nil, Known.echoName(e.id, false) end
        if row and limitSkill(row) then return nil, Known.echoName(e.id, false) end
    end
    return true
end

-- Does this unit still hold every skill in the turn: the command and each
-- pick under it. A Vision or a
-- skill change can take one away, and Echo never sends a skill the unit
-- does not hold. An All cast is held through its base spell. A basic attack
-- the bar does not list is held when the game says the unit can use it, as
-- the planner allows. nil and the missing skill's name when one is gone.
function Known.echoHeld(uid, d)
    local held, any = {}, false
    for _, id in ipairs(equippedIds(uid) or {}) do
        held[id] = true
        any = true
    end
    -- No list read at all is a read that failed, not an empty bar.
    if not any then return true end
    for _, e in ipairs((d and d.entries) or {}) do
        if not e.item then
            local row = skillOf(e.id)
            local base = (row and row.multicastOf) or e.id
            if not (held[e.id] or held[base]) then
                local fight = row and (row.attr == ATTR.FIGHT) and (activation(uid, e.id) == true)
                if not fight then return nil, Known.echoName(e.id, false) end
            end
        end
    end
    return true
end

-- The ids an entry may take now, best first. A foe the party is already
-- hitting comes first. An ally is the standing one lowest on HP.
function Known.echoLook(uid, wheel)
    local look = {}
    look.valid = function(e, side)
        local rel = (side == "foe") and REL.ENEMY or REL.FRIEND
        local skillId = e.id
        if e.item then
            local irow = ItemIdx and ItemIdx[e.id] or nil
            skillId = irow and irow.skillId or nil
        end
        local ids = {}
        if skillId then ids = targetsFor(uid, { id = skillId }, rel) end
        if #ids == 0 then ids = (side == "foe") and members(REL.ENEMY) or friendIds() end
        local out, hp = {}, {}
        for _, id in ipairs(ids) do
            local r = hpRatio(id)
            -- Down is no HP read, as the report marks it.
            local up = (r ~= nil) and (r > 0)
            local keep
            if side == "foe" then
                -- On the wheel every foe waits at 0 HP for the finisher, so
                -- the game's own list is the check there.
                keep = (up or wheel) and (Known.echoRelation(id) ~= REL.FRIEND)
            else
                -- Raises are never taped, so an ally target is a standing ally.
                keep = up and (Known.echoRelation(id) ~= REL.ENEMY) and not (Fight.isSummon and Fight.isSummon(id))
            end
            if keep then
                out[#out + 1] = id
                hp[id] = r or 0
            end
        end
        if side == "foe" then
            local focus = Fight.building
            for i, id in ipairs(out) do
                if id == focus then
                    table.remove(out, i)
                    table.insert(out, 1, id)
                    break
                end
            end
        else
            table.sort(out, function(a, b) return hp[a] < hp[b] end)
        end
        return out
    end
    look.ally = function(name)
        for _, id in ipairs(friendIds()) do
            if Fight.nameOf(id) == name then return id end
        end
        return nil
    end
    return look
end

-- Can this unit pay for the whole decide now: MP and a seal. Items and
-- Limit Bursts are never taped. nil and why when it can't.
function Known.echoPays(uid, d)
    local _, skills = Known.echo.uses(d)
    local need = 0
    for _, s in ipairs(skills) do
        local row = skillOf(s.id)
        local base = (row and row.multicastOf) or s.id
        local name = Known.echoName(s.id, false)
        need = need + (skillCost(uid, base, s.all) or 0)
        if s.top and sealed(uid, base) then return nil, name .. " can't be used now" end
    end
    local mp = stat(uid, PARAM.MP, false)
    if mp and (need > mp) then return nil, string.format("MP %d of %d", math.floor(mp), math.floor(need)) end
    return true
end

-- The decide, built as the player sent it.
function Known.echoSend(d)
    local cls = StaticFindObject("/Script/mucha.CPP_BtlCmdDecideDelegateVal")
    local disp = FindFirstOf("CPP_MuchaEventDispatcher")
    if not (cls and cls:IsValid() and disp and disp:IsValid()) then
        log("could not build a command")
        return false
    end
    local obj = StaticConstructObject(cls, disp)
    obj.CmdType = d.cmdType
    obj.isNotConsume = d.notConsume
    obj.doCalcOrder = d.calcOrder
    obj.CommandId = d.command
    for i, e in ipairs(d.entries) do
        obj.cmdDecideDataList[i] = { actionId = e.id, actionUnitUniqueId = e.unit }
        local row = obj.cmdDecideDataList[i]
        row.actionId = e.id
        row.actionUnitUniqueId = e.unit
        row.isUseItem = e.item and true or false
        row.IsAll = e.all and true or false
        row.ParentActionKey.Category = e.pCat
        row.ParentActionKey.ID = e.pId
        for j, tid in ipairs(e.targets or {}) do row.targetUnitUniqueIdList[j] = tid end
        for j, p in ipairs(e.params or {}) do row.ParameterList[j] = p end
    end
    for i, k in ipairs(d.keys or {}) do
        obj.actionKeys[i] = { Category = k[1], ID = k[2] }
        obj.actionKeys[i].Category = k[1]
        obj.actionKeys[i].ID = k[2]
    end
    Menu.byMod = true
    Menu.byEcho = true
    local ok, err = pcall(function()
        disp:ExecuteEvent({ TagName = FName("Delegate.Battle.Cmd.Decide") }, obj)
    end)
    if not ok then
        Menu.byMod, Menu.byEcho = false, false
        log("echo: send failed: %s", tostring(err))
        return false
    end
    return true
end

-- The targets an echo changed. In the fight the turn was kept in, that is a
-- retarget. In a later fight the old targets are gone anyway.
function Known.echoChanges(changes, who, rec)
    local here = Known.echoLaunch .. ":" .. tostring(Fight.number)
    local kind = (rec and (rec.fight == here)) and "retarget" or "new fight target"
    Known.echoNewTold = Known.echoNewTold or {}
    for _, c in ipairs(changes or {}) do
        -- A turn from another fight changes targets every time it goes out.
        -- That is said once per action, per character, per fight.
        local key = here .. ":" .. tostring(who) .. ":" .. tostring(c.id)
        local quiet = (kind == "new fight target") and Known.echoNewTold[key]
        if kind == "new fight target" then Known.echoNewTold[key] = true end
        if not quiet then
            local from = (type(c.from) == "number") and ("unit " .. c.from) or tostring(c.from)
            local to
            if c.group then
                local names = {}
                for _, id in ipairs(c.group) do names[#names + 1] = Fight.nameOf(id) end
                to = table.concat(names, ", ")
            else
                to = Fight.nameOf(c.to)
            end
            Known.echoEvent(kind, string.format("%s %s: %s %s can't take it, %s instead", who,
                Known.echoName(c.id, false), c.side, from, to))
        end
    end
end

-- This menu's turn from the tape, or the menu is left to the player.
function Known.echoTurn(uid, serial)
    local E, tape = Known.echo, Known.echoTape
    if not (E and tape) then return end
    if outOfControl(uid) then return end
    local finishing = false
    pcall(function() finishing = inFinishPhase() end)
    if finishing then return end
    local who = Fight.nameOf(uid)
    local function yours(why)
        if Menu.echoTold == serial then return end
        Menu.echoTold = serial
        Known.echoEvent("handed back", string.format("%s: %s", who, tostring(why)))
        showToast("Echo: " .. who .. "'s turn is yours")
    end
    local turn = E.turn(tape, who)
    -- A turn taped before items and raises were left off is dropped.
    if turn then
        for _, rec in ipairs(turn) do
            local tapes, what = Known.echoTapes(rec)
            if not tapes then
                tape.turns[who] = nil
                Known.echoSave()
                Known.echoEvent("dropped", string.format("%s: the turn on record used %s, which is not taped", who, tostring(what)))
                turn = nil
                break
            end
        end
    end
    if not turn then return yours("nothing recorded") end
    -- The normal phase starts the turn over. Another phase right after this
    -- unit's command takes the turn's next part.
    local phase = currentPhase()
    local run = Known.echoRun
    local prev = Known.echoPrev
    local n = 1
    if (phase ~= 0) and run and (run.who == who) and prev and (prev.actor == uid) then n = run.n + 1 end
    local step = E.step(n, #turn)
    local rec = turn[step]
    local was = rec.entries[1] and rec.entries[1].unit
    local held, gone = Known.echoHeld(uid, rec)
    if not held then return yours(tostring(gone) .. " is no longer equipped") end
    local d, why = E.aim(rec, uid, was, Known.echoLook(uid))
    if not d then return yours(why) end
    -- The command goes out in the phase the menu is in, as the mod's own sends do.
    d.cmdType = phase
    local changes = why or {}
    local pays, whyNot = Known.echoPays(uid, d)
    if not pays then return yours(whyNot) end
    if (not Menu.open) or (Menu.serial ~= serial) or Menu.decided then return end
    local aims = {}
    for _, e in ipairs(d.entries) do
        for _, tid in ipairs(e.targets) do aims[#aims + 1] = Fight.nameOf(tid) end
    end
    local line = string.format("%s %d/%d p%d: %s -> %s", who, step, #turn, phase, E.describe(d, Known.echoName),
        (#aims > 0) and table.concat(aims, ", ") or "no target")
    if Menu.armPace then Menu.armPace("the first planned command") end
    if not cfg.Submit then
        Known.echoEvent("not sent", line .. " (Submit is false)")
        return
    end
    Known.echoWhy = string.format("echo %d/%d of %s's turn", step, #turn, who)
    local sent = Known.echoSend(d)
    Known.echoWhy = nil
    if not sent then
        Known.echoEvent("failed", line)
        return yours("the send failed")
    end
    Known.echoRun = { who = who, n = n }
    Known.echoEvent("sent", line)
    Known.echoChanges(changes, who, rec)
end

-- In Echo the Resonance wheel is always the player's. It is never taped.
function Known.echoWheelTurn()
    Fight.wheelLeft = "Echo leaves the wheel to you"
    Known.echoEvent("handed back", "wheel: the wheel is always yours in Echo")
    showToast("Echo: the wheel is yours")
end

local function act(serial)
    if not cfg.Enabled then return end
    if (not Menu.open) or (Menu.serial ~= serial) or Menu.sub or Menu.decided then return end
    local uid = currentActor()
    if uid < 0 then uid = Menu.actor end
    if uid < 0 then return end
    pcall(ensureBattle)
    if Fight.orderFresh and applyPendingOrder then pcall(applyPendingOrder) end
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
        Fight.hitLanded = false
        Fight.stance = {}
        Fight.stanceEnded = {}
        Fight.escapeSent = nil
        Fight.escapeTold = nil
        Fight.noEscape = nil
        Fight.claim = Fight.claim or {}
        Fight.claim.cure = {}
        Fight.claim.lb = false
        Fight.claim.lbBreak = false
        Fight.lbRead, Fight.lbTold, Fight.lbRows = {}, {}, {}
        Fight.claim.guard = false
        Fight.guardOn = {}
        Fight.veil = nil
        Fight.claim.hone = {}
        Fight.claim.esper = false
        Fight.esperOut = nil
        Fight.esperGateWhy, Fight.esperHoldLine = nil, nil
        Fight.summonLive = false
        Fight.debuffOn, Fight.debuffSeen = {}, {}
        Fight.debuffIds = {}
        Fight.kitOn, Fight.luckToss = {}, {}
        if Fight.claim then Fight.claim.kit = {} end
        if Fight.warn then
            local ids = {}
            for id, rec in pairs(Fight.warn) do
                if not rec.settled then ids[#ids + 1] = id end
            end
            for _, id in ipairs(ids) do settleWarn(id) end
        end
        Fight.warn = {}
        Fight.risk = {}
        local line = "party restored. ledger cleared"
        log("%s", line)
        appendLog("  " .. line)
    end
    pcall(noteMp, uid)
    local actorName = unitName(uid)
    -- The summoned unit is not a party member. Its name often does not match
    -- the skill that called it, so the field's summon mark counts too.
    if (Espers.lookup and Espers.lookup(actorName)) or (Fight.isSummon and Fight.isSummon(uid, actorName)) then
        if Fight.esperOut then Fight.esperOut.acted = true end
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
    -- Log only: when the last debuff's status shows on its enemy, and when it
    -- goes. Nothing reads this but the log.
    pcall(function()
        local watch = Fight.debuffWatch
        if not watch then return end
        local set = statuses(watch.target)
        local up = false
        for id in pairs(watch.ids) do
            if set[id] then up = true end
        end
        local since = #(Fight.actions or {}) - watch.at
        local line = nil
        if up and (not watch.seen) then
            watch.seen = true
            line = string.format("debuff %s seen on %s, %d commands after the cast", watch.name, watch.foe, since)
        elseif watch.seen and (not up) then
            line = string.format("debuff %s gone from %s, %d commands after the cast", watch.name, watch.foe, since)
            Fight.debuffWatch = nil
        elseif (not watch.seen) and (since >= 12) then
            line = string.format("debuff %s not seen on %s in %d commands", watch.name, watch.foe, since)
            Fight.debuffWatch = nil
        end
        if line then
            log("%s", line)
            appendLog("  " .. line)
        end
    end)
    -- The last heal spell's target: what it restored per point of power. A
    -- hit or the top of the bar can only make this read low, so the most seen
    -- in the fight is kept.
    pcall(function()
        local probe = Fight.healProbe
        Fight.healProbe = nil
        if not probe then return end
        local now = stat(probe.target, PARAM.HP, false)
        if not (now and now > probe.hp) then return end
        local rate = (now - probe.hp) / probe.power
        Fight.healRate = Fight.healRate or {}
        local had = Fight.healRate[probe.uid]
        if (not had) or (rate > had) then
            Fight.healRate[probe.uid] = rate
            if not had then
                local line = string.format("%s heals %.2f HP per power (%s restored %d)",
                    Fight.nameOf(probe.uid), rate, probe.name, math.floor(now - probe.hp))
                log("%s", line)
                appendLog("  " .. line)
            end
        end
    end)
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
                    -- A miss counts once per skill, so two different skills must
                    -- miss before the kind is ruled out. One skill that does
                    -- nothing tells about that skill, not every skill of its kind.
                    -- TUNE: if fights show physical or magic turns wasted on an
                    -- enemy that blocks them, lower this to one skill again.
                    Fight.kindMissBy = Fight.kindMissBy or {}
                    Fight.kindMissBy[id] = Fight.kindMissBy[id] or {}
                    local by = Fight.kindMissBy[id][probe.kind] or {}
                    Fight.kindMissBy[id][probe.kind] = by
                    local n = Fight.kindMiss[id][probe.kind] or 0
                    local sid = probe.sid or "?"
                    if not by[sid] then
                        by[sid] = true
                        n = n + 1
                    end
                    Fight.kindMiss[id][probe.kind] = n
                    -- The same skill twice for no HP on this enemy: the skill is
                    -- dropped against it while its status list stays the same.
                    -- One zero can be a dodge. Darkness hits the Cursed Slates
                    -- for 0 but its row lists no element, so only this memory
                    -- catches it.
                    -- TUNE: if fights show a skill shelved that would have
                    -- landed, raise the count. If one keeps being retried on a
                    -- foe whose statuses flicker, key the stamp on fewer statuses.
                    if probe.sid then
                        Fight.skillZero = Fight.skillZero or {}
                        Fight.skillZero[id] = Fight.skillZero[id] or {}
                        -- Two zeros count only under the same status list. A new
                        -- list starts the count again.
                        local stamp = statusStamp(id)
                        local rec = Fight.skillZero[id][probe.sid]
                        if (type(rec) ~= "table") or (rec.stamp ~= stamp) then rec = { n = 0, stamp = stamp } end
                        rec.n = rec.n + 1
                        Fight.skillZero[id][probe.sid] = rec
                        if rec.n == 2 then
                            local line = string.format("%s takes no damage from %s, dropped against it while its status holds", unitName(id), probe.name or tostring(probe.sid))
                            log("%s", line)
                            appendLog("  " .. line)
                        end
                    end
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
                    if Fight.kindMissBy and Fight.kindMissBy[id] then Fight.kindMissBy[id][probe.kind] = nil end
                    if probe.sid and Fight.skillZero and Fight.skillZero[id] then Fight.skillZero[id][probe.sid] = nil end
                    Fight.kindHit[id] = Fight.kindHit[id] or {}
                    Fight.kindHit[id][probe.kind] = true
                end
                -- A summon hits on its own, so with one out a drop is not this
                -- kind's. It neither lands the kind nor clears the misses.
            end
        end
    end)
    if cfg.Echo then
        local okEcho, errEcho = pcall(Known.echoTurn, uid, serial)
        if not okEcho then log("echo failed: %s", tostring(errEcho)) end
        return
    end
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
    if Menu.armPace then Menu.armPace("the first planned command") end
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
    -- Log only: is this debuff's status already on the enemy it goes to?
    if choice.reason and choice.reason:find(" debuff ", 1, true) then
        pcall(function()
            local row = skillOf(choice.id)
            local function sorted(set)
                local ids = {}
                for id in pairs(set or {}) do ids[#ids + 1] = id end
                table.sort(ids)
                return table.concat(ids, ",")
            end
            for _, tid in ipairs(choice.targets or {}) do
                local set = statuses(tid)
                local still = "no"
                for id in pairs((row and row.enemyStatus) or {}) do
                    if set[id] then still = "yes" end
                end
                local line = string.format("debuff check %s on %s: its status %s, on the enemy now %s, still up %s",
                    choice.name, unitName(tid), sorted(row and row.enemyStatus), sorted(set), still)
                log("%s", line)
                appendLog("  " .. line)
                if row and next(row.enemyStatus or {}) then
                    Fight.debuffWatch = { target = tid, foe = unitName(tid), name = choice.name,
                        ids = row.enemyStatus, at = #(Fight.actions or {}), seen = false }
                end
            end
        end)
    end
    -- Log only: a healer who hits with a heal's MP in hand while someone is under half.
    if (choice.kind == "damage") and (not choice.isItem) and (phase ~= PHASE_FINISH) then
        pcall(function()
            local kit = unitKit(uid)
            if not (kit and ((kit.healScore or 0) > 0) and ((kit.healCost or 0) > 0) and ((mpNow or 0) >= kit.healCost)) then
                return
            end
            local bits, hurt = {}, false
            for _, id in ipairs(friendIds()) do
                local ratio = hpRatio(id)
                if ratio and (ratio > 0) then
                    if ratio < 0.50 then hurt = true end
                    local claimed = Fight.claim and Fight.claim.heal and Fight.claim.heal[id]
                    bits[#bits + 1] = string.format("%s %d%%%s", unitName(id), math.floor(ratio * 100 + 0.5),
                        claimed and " claimed" or "")
                end
            end
            if hurt then appendLog(string.format("  healer %s hits with %d MP: %s", who, mpNow or 0, table.concat(bits, ", "))) end
        end)
    end
    -- The target's HP before a one-target heal spell goes out, to learn how
    -- much this caster restores.
    Fight.healProbe = nil
    if (choice.kind == "heal") and (not choice.isItem) and (choice.attr == ATTR.MAGIC) and (not choice.isAll)
        and choice.targets and (#choice.targets == 1) then
        local row = skillOf(choice.id)
        local hpNow = stat(choice.targets[1], PARAM.HP, false)
        if row and hpNow and (hpNow > 0) and ((row.power or 0) > 0) and (row.calc ~= Health.FIXED) then
            Fight.healProbe = { uid = uid, target = choice.targets[1], hp = hpNow, power = row.power, name = choice.name }
        end
    end
    Known.repRun(Known.repDecide, uid, choice, phase)
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
    -- A hit with no element, watched by its kind. An element is learned from
    -- the hit row itself, so one dead Fire does not retire every magic spell.
    if probeHp and next(probeHp) then
        local kind = kindOf(choice)
        local el = choice.known and choice.known.element
        if kind and (not el) then
            Fight.hitProbe = { kind = kind, hp = probeHp, sid = choice.id, name = choice.name, summon = Fight.summoned and true or false }
        end
    end
    if ((choice.kind == "revive") or (choice.itemUse == "revive")) and choice.targets then
        Fight.raisedRound = Fight.raisedRound or {}
        for _, tid in ipairs(choice.targets) do
            Fight.raisedRound[tid] = Fight.rounds or 0
            -- Up from the raise on: a fall before the next menu sees them up
            -- is still a fall right after a raise (the sim's raise cycle).
            local was = Fight.prev and Fight.prev[tid]
            if was and was.side == "ally" and (was.hp or 0) <= 0 then was.hp = 1; was.raised = true end
        end
    end
    -- Each ally a heal was sent to, with their HP now. Until a hit takes
    -- them below it, they count as handled: the raise hold and the critical
    -- line ask "healed since the last hit", not "healed this round", whose
    -- end the planner and the game see at different moments.
    if (choice.kind == "heal") or (choice.itemUse == "hp") or (choice.itemUse == "both") then
        Fight.healMark = Fight.healMark or {}
        local ids = choice.targets or {}
        -- A party heal reaches every living ally, whatever its target list says.
        if choice.isAll or (choice.reason and choice.reason:find("party heal", 1, true)) then ids = friendIds() end
        Fight.healAt = Fight.healAt or {}
        for _, tid in ipairs(ids) do
            local hpNow = stat(tid, PARAM.HP, false)
            if hpNow and hpNow > 0 then Fight.healMark[tid] = hpNow end
            Fight.healAt[tid] = #(Fight.actions or {})
        end
    end
    if choice.attr == ATTR.FINISH then Fight.resonanceSent = true end
    if (choice.kind == "damage") and (not choice.isItem) and (choice.attr ~= ATTR.SUMMON) then
        Fight.hitsSince = (Fight.hitsSince or 0) + 1
    end
    if phase == 0 and choice.kind == "damage" and not choice.isItem then
        Fight.line = true
        local reason = choice.reason or ""
        if (not reason:find("^setup")) and (choice.attr ~= ATTR.SUMMON) then
            -- Any hit opens what waits for the first hit. Only a paid one ends the
            -- opening setup, so a free Attack doesn't cost the next ally their turn.
            Fight.hitLanded = true
            if (choice.cost or 0) > 0 then Fight.chipped = true end
        end
    end
    local limitCast = choice.attr == ATTR.LB
    if choice.known and limitSkill({ known = choice.known }) then limitCast = true end
    -- noteHand records a barrier the player sent. A command the mod sent
    -- skips noteHand, so the same record is written here. Without it the
    -- next ally casts the barrier again while the status still shows.
    if choice.known and choice.known.use == "lb-guard" then
        local indexed = skillOf(choice.id)
        Fight.veil = { map = (indexed and indexed.friendStatus) or {}, seen = false, round = Fight.rounds or 0 }
    end
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
    if choice.attr == ATTR.SUMMON then
        markSummon(choice, choice.esperTurns, uid, choice.id)
        if Fight.esperOut then Fight.esperOut.caster, Fight.esperOut.sid = uid, choice.id end
    end
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
    if not Fight.active then
        -- The game's own Auto sent the fight's first command (an Esuna after
        -- an opening blind) before the mod saw the fight. Any read of the
        -- battle while that command plays crashed the game at a boss start,
        -- in this hook and on the next tick alike, with Turbo on or off.
        -- With the mod off it did not crash. So the mod stays idle, as it is
        -- through the opening, and the fight is set up when the next command
        -- menu opens. This one command is not recorded.
        if not Fight.waitMenu then
            Fight.waitMenu = true
            log("fight waits for the next command menu: the game sent the opening command")
        end
        return
    end
    pcall(function() noteChanges(livingSnapshot()) end)
    pcall(settleGauges)
    -- A pick from an open menu belongs to that menu's ally. A command with no
    -- menu is one the game made for the unit whose turn it is, such as an
    -- ally whose status takes the turn. A wheel pick names its caster below.
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
    -- The wheel's last menu can be another ally's, so a wheel pick, like an
    -- echo, goes by the unit its command names. The hits agree with it
    -- (seen 2026-11-11: Zantetsuken named unit 0, Rain, after Jake's menu).
    if actorId and (actorId >= 0) and (Known.echoNow or onWheel or not Menu.fromMenu) then uid = actorId end
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
    if (not Known.echoNow) and Known.echoKeep then
        local okKeep, errKeep = pcall(Known.echoKeep, v, uid, onWheel)
        if not okKeep then log("echo: turn not kept: %s", tostring(errKeep)) end
    end
    -- A command from a friend who was not in the opening party is the summoned
    -- unit acting. The ally list can omit that unit until this command.
    if Fight.esperOut and uid and (uid >= 0) and Fight.openIds and (not Fight.openIds[uid]) then
        Fight.esperOut.acted = true
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
    local line = string.format("%s %s p%d: %s", Known.echoNow and "echo" or "player", who, phase, name)
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
    -- For the report. This is a game hook, so nothing is read here: the timer
    -- or the next menu turn records it.
    if Known.report then
        Fight.repHand = Fight.repHand or {}
        Fight.repHand[#Fight.repHand + 1] = { uid = uid, id = actionId, name = name, kind = kind, targets = targets, phase = phase,
            echo = Known.echoNow and true or nil, echoWhy = Known.echoWhy,
            isItem = isItem, cost = skill and skill.cost, attr = skill and skill.attr, dmgType = skill and skill.dmgType }
    end
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
            for _, id in ipairs(targets) do markDebuff(id, info.effect, skill and skill.enemyStatus) end
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
    if skill and (skill.attr == ATTR.SUMMON) then markSummon(skill, nil, uid, skill.id) end
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
    if (phase == 0) and (kind == "damage") and (not isItem) then
        Fight.line = true
        Fight.hitLanded = true
        if cost > 0 then Fight.chipped = true end
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

-- Copy a UE id list inside the caller. The list itself is not kept.
local function copyIdList(list)
    local out = {}
    if not list then return out end
    if list.ForEach then
        pcall(function()
            list:ForEach(function(_, e)
                local n = num(e)
                if n then out[#out + 1] = n end
            end)
        end)
        return out
    end
    if type(list) == "table" then
        for _, e in ipairs(list) do
            local n = num(e)
            if n then out[#out + 1] = n end
        end
    end
    return out
end

function settleWarn(id)
    if not (Fight and Fight.warn) then return end
    local rec = Fight.warn[id]
    if (not rec) or rec.settled then return end
    rec.settled = true
    if rec.reached or rec.sawFront then
        Fight.warnLand = (Fight.warnLand or 0) + 1
    elseif rec.broke then
        Fight.warnCancel = (Fight.warnCancel or 0) + 1
    end
end

-- phase "broke" runs before the list is read, so a break is on the record
-- when that id leaves the list. phase "reached" runs after, so a record
-- opened on the arrival turn still counts as the slot. A later break does
-- not turn that land into a cancel.
local function noteWarnTimeline(current, phase)
    if not (Fight and Fight.warn) then return end
    if phase ~= "reached" then
        for id, rec in pairs(Fight.warn) do
            if (not rec.settled) and broken(id) then rec.broke = true end
        end
    end
    if phase == "broke" then return end
    local first = current and current[1]
    if not first then return end
    for id, rec in pairs(Fight.warn) do
        if (not rec.settled) and (not rec.broke) and ((id ~= first) or (not broken(first))) and Known.brace then
            Known.brace.noteFront(rec, id, first)
        end
    end
end

-- Game thread, while a party menu is open. The risk object is not kept.
local GONE_FOE = -1
-- Who cast this skill most recently, by the commands this fight has sent.
local function lastCasterOf(sid, friends)
    local row = sid and skillOf(sid)
    local skill = row and row.name
    if not skill then return nil end
    local who = nil
    if Fight.last and (Fight.last.skill == skill) then
        who = Fight.last.who
    else
        for _, name in ipairs(Fight.castOrder or {}) do
            local rec = Fight.casts and Fight.casts[name]
            if rec and rec.n and rec.n[skill] then who = name end
        end
    end
    if not who then return nil end
    for fid in pairs(friends) do
        if Fight.nameOf(fid) == who then return fid end
    end
    return nil
end

function readRisk(hitsOnly)
    clearFoeKeep()
    if Fight then Fight.stampCache = {} end
    if not Fight then return end
    -- The last skill's hit list. Numbers only; the skill object is not kept.
    -- Reads before the fight is open sit in hitHold until ensureBattle.
    pcall(function()
        local vm = FindFirstOf("CPP_BtlVoiceManager")
        if not (vm and vm.IsValid and vm:IsValid()) then return end
        local skillObj = unwrap(vm.m_pSkillObj)
        if not (skillObj and skillObj.IsValid and skillObj:IsValid()) then return end
        local list = skillObj.m_DamageVariationDataList
        if not (list and list.ForEach) then return end
        local friends = {}
        for _, fid in ipairs(friendIds()) do friends[fid] = true end
        if Fight.seenAlly then
            for fid in pairs(Fight.seenAlly) do friends[fid] = true end
        end
        if Fight.summons then
            for fid in pairs(Fight.summons) do friends[fid] = nil end
        end
        local function actorId(v)
            local n = num(v)
            if n then return n end
            local obj = unwrap(v)
            if not obj then return nil end
            n = num(obj.m_UniqueId)
            if n then return n end
            local ok, got = pcall(function() return obj:GetUniqueId() end)
            return ok and num(got) or nil
        end
        local casts = {}
        local dealt = nil
        list:ForEach(function(i, e)
            if i > 128 then return true end
            local d = unwrap(e)
            if not d then return end
            local from = actorId(d.pActionUnit)
            local to = actorId(d.pTargetUnit)
            local row = unwrap(d.unitParameterVariationData)
            if not from or not to or not row then return end
            -- A body the game has removed reads as unit 0, which is a party slot.
            -- A hit from the party that isn't out of control was on that foe.
            -- The caster can read as unit 0 too, so the skill's last caster is the name.
            local goneFoe = false
            if (from == 0) and (to == 0) and (num(row.variationParameter) == PARAM.HP) and (num(row.VariationType) == 1)
                and ((num(row.VariationValue) or 0) > 0) then
                from = lastCasterOf(num(row.SkillId), friends) or from
            end
            if (friends[from] or (Fight.summons and Fight.summons[from]))
                and (num(row.variationParameter) == PARAM.HP) and (num(row.VariationType) == 1)
                and ((num(row.VariationValue) or 0) > 0) and (unwrap(row.isMiss) ~= true) then
                local hitKey = table.concat({ tostring(from), tostring(num(row.SkillId)), tostring(num(row.VariationValue)),
                    tostring(num(row.beforeVariationValue)), tostring(num(row.afterVariationValue)) }, ":")
                Fight.hitPrint = Fight.hitPrint or {}
                if (to == 0) and not outOfControl(from) then
                    -- The same hit, read again after its target went.
                    if Fight.hitPrint[hitKey] then return end
                    goneFoe = true
                    to = GONE_FOE
                elseif not friends[to] then
                    Fight.hitPrint[hitKey] = true
                end
            end
            -- What really hit hard. Each hit counts once, and one cast's hits on
            -- one enemy add up before they go in the book.
            if Fight.esperOut and Fight.isSummon and not (Fight.summons and Fight.summons[from]) then
                Fight.isSummon(from)
            end
            -- The row's unsummon effect is the unit leaving. The friend list
            -- can miss that unit for the whole call, so the effect is the end.
            if Fight.esperOut then
                local sidLeave = num(row.SkillId)
                local skLeave = sidLeave and skillOf(sidLeave)
                local leaves = false
                if skLeave then
                    if skLeave.effect == EFF.UNSUMMON then leaves = true end
                    if not leaves then
                        for _, e in ipairs(skLeave.effects or {}) do
                            if e.type == EFF.UNSUMMON then leaves = true end
                        end
                    end
                end
                if leaves then
                    local mark = Fight.esperOut
                    local function mine(id)
                        if not id then return false end
                        if Fight.summons and Fight.summons[id] then return true end
                        if mark.who and (mark.who == id) then return true end
                        if mark.name and (unitName(id) == mark.name) and not (Fight.openIds and Fight.openIds[id]) then
                            return true
                        end
                        return false
                    end
                    if mine(from) or mine(to) then
                        mark.left = true
                        mark.acted = true
                        if Fight.summons then
                            if from then Fight.summons[from] = nil end
                            if to then Fight.summons[to] = nil end
                            if mark.who then Fight.summons[mark.who] = nil end
                        end
                    end
                end
            end
            local fromSummon = Fight.summons and Fight.summons[from]
            if fromSummon then friends[from] = nil end
            if Known.measure and (friends[from] or fromSummon) and (not friends[to]) and not (Fight.summons and Fight.summons[to]) then
                pcall(function()
                    local value = num(row.VariationValue)
                    -- A miss reads as no HP change at all. It still counts as a cast.
                    local missed = unwrap(row.isMiss) == true
                    local res = num(row.resistance)
                    local sidEarly = num(row.SkillId)
                    if missed then
                        value = 0
                    else
                        if (num(row.variationParameter) ~= PARAM.HP) or (num(row.VariationType) ~= 1) then return end
                        -- The row's resistance, for every character. A guarded
                        -- hit with no resistance is the guard, not the element.
                        -- A veil ate the hit, so it is not the foe's element.
                        -- Zero is a real result, so it is not combined with and/or.
                        local guarded = unwrap(row.isDefence) == true
                        local veil = unwrap(row.isVeilDefence) == true
                        local raw = nil
                        if (not veil) and ((not guarded) or (res ~= nil and res ~= 0)) then raw = value or 0 end
                        local lesson = (not veil) and (not goneFoe) and Known.measure.lesson and Known.measure.lesson(res, false, raw)
                        if lesson then
                            local sk = sidEarly and skillOf(sidEarly)
                            local key = sk and sk.element
                            if (not key) and sk then
                                if sk.dmgType == 1 then key = "physical" end
                                if sk.dmgType == 2 then key = "magic" end
                            end
                            if key and Known.measure.noteFoe then
                                Fight.learned = Fight.learned or {}
                                if Known.measure.noteFoe(Fight.learned, to, key, lesson, statusStamp(to)) then
                                    local word = (lesson == "weak" and "is weak to")
                                        or (lesson == "half" and "halves")
                                        or (lesson == "absorb" and "absorbs")
                                        or (lesson == "reflect" and "reflects")
                                        or "nulls"
                                    local line = string.format("%s %s %s", unitName(to), word, key)
                                    log("%s", line)
                                    appendLog("  " .. line)
                                end
                            end
                        end
                        if (not value) or (value <= 0) then return end
                    end
                    local sid = num(row.SkillId)
                    Fight.dealtBook = Fight.dealtBook or Known.measure.new()
                    -- Two misses look alike, so the command count tells them apart.
                    local sig = table.concat({ tostring(from), tostring(to), tostring(sid), tostring(value),
                        tostring(num(row.beforeVariationValue)), tostring(num(row.afterVariationValue)),
                        missed and tostring(#(Fight.actions or {})) or "" }, ":")
                    if not Known.measure.fresh(Fight.dealtBook, sig) then return end
                    dealt = dealt or {}
                    -- What a summon does belongs to the Esper and to whoever called it.
                    local byFrom, bySid = from, sid
                    if fromSummon then
                        local out = Fight.esperOut
                        if out then out.acted = true end
                        if not (out and out.caster and out.sid) then return end
                        byFrom, bySid = out.caster, out.sid
                    end
                    local key = tostring(byFrom) .. ":" .. tostring(bySid) .. ":" .. tostring(to)
                    local rec = dealt[key]
                    local mult = num(row.damageMultiplier)
                    if not rec then
                        rec = {
                            from = byFrom, sid = bySid, to = to, raw = 0,
                            res = num(row.resistance), mult = mult,
                            onBreak = unwrap(row.isOnBreak) == true,
                        }
                        dealt[key] = rec
                    elseif (rec.mult == nil) and (mult ~= nil) then
                        rec.mult = mult
                    end
                    rec.raw = rec.raw + value
                end)
            end
            -- Every hit record, for the report: the numbers on this row only.
            if Known.report and Known.report.fight then
                Known.repRun(function()
                    local fromFriend, toFriend = friends[from] and true or false, friends[to] and true or false
                    local sidR = num(row.SkillId)
                    local sk = sidR and skillOf(sidR)
                    Known.report:hit({ from = from, to = to, skill = sidR, skillName = (sk and sk.name) or tostring(sidR),
                        fromName = fromFriend and Fight.nameOf(from) or unitName(from), toName = (goneFoe and "a fallen foe") or (toFriend and Fight.nameOf(to)) or unitName(to),
                        fromFriend = fromFriend, toFriend = toFriend, param = num(row.variationParameter), vtype = num(row.VariationType),
                        value = num(row.VariationValue), before = num(row.beforeVariationValue), after = num(row.afterVariationValue),
                        breakValue = num(row.breakDamageValue), miss = unwrap(row.isMiss) == true, defended = unwrap(row.isDefence) == true,
                        onBreak = unwrap(row.isOnBreak) == true, trigger = unwrap(row.isTriggeredBreak) == true })
                end)
            end
            if Fight.summons and Fight.summons[from] then return end
            if not friends[to] then return end
            if not keepFoe(from) then return end
            if num(row.variationParameter) ~= PARAM.HP then return end
            if num(row.VariationType) ~= 1 then return end
            if unwrap(row.isMiss) == true then return end
            local value = num(row.VariationValue)
            local before = num(row.beforeVariationValue)
            local after = num(row.afterVariationValue)
            -- A killing hit's HP change stops at 0. VariationValue is the
            -- full hit, so a 900 on 500 HP counts as 900.
            local spent = nil
            if before and after and (before > after) then spent = before - after end
            local dmg = value
            if spent and ((not dmg) or (spent > dmg)) then dmg = spent end
            if (not dmg) or (dmg <= 0) then return end
            local sid = num(row.SkillId) or 0
            local defended = unwrap(row.isDefence) == true
            local dtype = num(row.DamageType) or 0
            local key = tostring(from) .. ":" .. tostring(sid) .. ":" .. tostring(to)
            local rec = casts[key]
            if not rec then
                rec = {
                    from = from, sid = sid, to = to, dmg = 0, maxHit = 0,
                    defended = defended, open = not defended, dtype = dtype,
                }
                casts[key] = rec
            end
            rec.dmg = rec.dmg + dmg
            if dmg > rec.maxHit then rec.maxHit = dmg end
            if defended then rec.defended = true else rec.open = true end
            if dtype ~= 0 then rec.dtype = dtype end
        end)
        -- A cast still landing shows up over several reads. It goes in the book
        -- as one cast, once a read brings nothing new.
        if dealt then
            Fight.dealtOpen = Fight.dealtOpen or {}
            for key, rec in pairs(dealt) do
                local open = Fight.dealtOpen[key]
                if open then open.raw = open.raw + rec.raw else Fight.dealtOpen[key] = rec end
            end
        elseif Fight.dealtOpen then
            for _, rec in pairs(Fight.dealtOpen) do
                local row = skillOf(rec.sid)
                local factor = Known.measure.hitFactor(rec.res, rec.mult, rec.onBreak)
                local est = row and ((row.power or 0) * factor) or nil
                Known.measure.noteCast(Fight.dealtBook, rec.from, rec.sid, rec.raw > 0)
                Known.measure.add(Fight.dealtBook, rec.from, rec.sid, rec.to, rec.raw, est, rec.onBreak)
            end
            Fight.dealtOpen = nil
        end
        local book = Fight.hitSeen
        if not Fight.active then
            Fight.hitHold = Fight.hitHold or {}
            book = Fight.hitHold
        else
            Fight.hitSeen = Fight.hitSeen or {}
            book = Fight.hitSeen
        end
        for _, rec in pairs(casts) do
            local foe = book[rec.from]
            if not foe then
                foe = {}
                book[rec.from] = foe
            end
            local sk = foe[rec.sid]
            if not sk then
                sk = { cast = 0, hit = 0, castOpen = 0, castGuard = 0, dtype = rec.dtype }
                foe[rec.sid] = sk
            end
            if rec.dmg > (sk.cast or 0) then sk.cast = rec.dmg end
            sk.total = (sk.total or 0) + rec.dmg
            sk.castTo = sk.castTo or {}
            if rec.dmg > (sk.castTo[rec.to] or 0) then sk.castTo[rec.to] = rec.dmg end
            -- The same hit at full size. A hit taken through a guard would make
            -- the next warning read as safe, and that ally would stop guarding.
            if Known.brace and Known.statusMap then
                local share = Known.brace.through(Fight.statusNow and Fight.statusNow[rec.to], rec.dtype, Known.statusMap())
                share = share * ((Fight.braced and Fight.braced[rec.to]) or 1)
                local full = (share > 0) and (rec.dmg / share) or rec.dmg
                sk.fullTo = sk.fullTo or {}
                if full > (sk.fullTo[rec.to] or 0) then sk.fullTo[rec.to] = full end
                Fight.borne = Fight.borne or {}
                if full > (Fight.borne[rec.to] or 0) then Fight.borne[rec.to] = full end
            end
            if rec.maxHit > (sk.hit or 0) then sk.hit = rec.maxHit end
            if rec.dtype ~= 0 then sk.dtype = rec.dtype end
            if rec.defended and not rec.open then
                if rec.dmg > (sk.castGuard or 0) then sk.castGuard = rec.dmg end
            elseif rec.dmg > (sk.castOpen or 0) then
                sk.castOpen = rec.dmg
            end
        end
    end)
    if hitsOnly then return end
    local ids = {}
    local ok = pcall(function()
        local tl = FindFirstOf("CPP_VM_BtlTimeLine")
        if not (tl and tl.IsValid and tl:IsValid()) then return end
        ids = copyIdList(tl.RiskUnitUniqueIdList)
    end)
    if not ok then return end
    Fight.risk = ids
    Fight.warn = Fight.warn or {}
    local seen = {}
    for _, id in ipairs(ids) do
        seen[id] = true
        if keepFoe(id) then
            local rec = Fight.warn[id]
            -- A settled record is the previous warning. This appearance is the next one.
            if (not rec) or rec.settled then
                rec = { broke = false, reached = false, settled = false, fresh = Fight.warnDraining or nil }
                Fight.warn[id] = rec
            end
            if broken(id) then rec.broke = true end
        end
    end
    local gone = {}
    for id, rec in pairs(Fight.warn) do
        if (not rec.settled) and (not seen[id]) then gone[#gone + 1] = id end
    end
    for _, id in ipairs(gone) do settleWarn(id) end
end

-- Party menu or a decide, on the game thread. The Timeline hook only
-- copies ids. Walking the hit list or the warning list inside that hook
-- runs while the game is swapping the turn order.
applyPendingOrder = function()
    if not Fight then return end
    if not Fight.active then
        readRisk()
        return
    end
    local pending = Fight.orderPending
    Fight.orderPending = nil
    Fight.orderFresh = false
    if type(pending) == "table" and (#pending > 0) then
        Fight.warnDraining = true
        for i = 1, #pending do
            local snap = pending[i]
            noteWarnTimeline(snap.current, "broke")
            readRisk()
            noteWarnTimeline(snap.current, "reached")
        end
        Fight.warnDraining = nil
        for _, rec in pairs(Fight.warn or {}) do rec.fresh = nil end
    else
        readRisk()
    end
end

function flushWarn()
    if not Fight then return end
    Fight.warn = Fight.warn or {}
    local ids = {}
    for id, rec in pairs(Fight.warn) do
        if not rec.settled then ids[#ids + 1] = id end
    end
    for _, id in ipairs(ids) do
        if broken(id) then
            local rec = Fight.warn[id]
            if rec then rec.broke = true end
        end
        settleWarn(id)
    end
    local line = string.format("warned: %d cancelled by a break, %d landed",
        Fight.warnCancel or 0, Fight.warnLand or 0)
    appendLog("  " .. line)
    log("%s", line)
end

local function hookTimeline()
    -- Copy the ids here. Holding this parameter and reading it later crashed
    -- the game (HandleUpdateRisk, twice).
    RegisterHook("/Script/mucha.CPP_VM_BtlTimeLine:HandleUpdateTimeline", function(_, delval)
        pcall(function()
            local row = delval:get()
            local current = copyIdList(row and row.currentTimelines)
            local nxt = copyIdList(row and row.nextTimelines)
            local extra = copyIdList(row and row.additionalTurnTimelines)
            row = nil
            if not Fight then return end
            Fight.order = { current = current, next = nxt, extra = extra }
            local q = Fight.orderPending or {}
            if #q >= 32 then table.remove(q, 1) end
            q[#q + 1] = { current = current, next = nxt, extra = extra }
            Fight.orderPending = q
            Fight.orderFresh = true
        end)
    end)
end

-- Log only: exactly what the game sends for a command the player picks by hand,
-- to learn how a two-action turn works. Decides nothing.
function Menu.traceHand(v)
    if not Reporting then return end
    local function line(text)
        log("%s", text)
        if Fight then appendLog("  " .. text) end
    end
    Menu.handSerial = (Menu.handSerial or 0) + 1
    Menu.traceLeft = 4
    line(string.format("hand %d: type %s, command %s, notConsume %s, calcOrder %s, sub %s",
        Menu.handSerial, tostring(num(v.CmdType)), tostring(num(v.CommandId)),
        tostring(v.isNotConsume), tostring(v.doCalcOrder), tostring(Menu.sub)))
    local count = 0
    if v.cmdDecideDataList and v.cmdDecideDataList.ForEach then
        v.cmdDecideDataList:ForEach(function(_, e)
            local d = unwrap(e)
            if not d then return end
            count = count + 1
            local id = num(d.actionId)
            local row = (id and (not d.isUseItem)) and skillOf(id) or nil
            local function ids(list)
                local out = {}
                if list and list.ForEach then
                    list:ForEach(function(_, x) out[#out + 1] = tostring(num(unwrap(x))) end)
                end
                return table.concat(out, ",")
            end
            line(string.format("  action %d: %s id %s, unit %s, item %s, all %s, parent %s/%s, targets [%s], params [%s], attr %s, effect %s, cost %s, target %s",
                count, (row and row.name) or "?", tostring(id), tostring(num(d.actionUnitUniqueId)),
                tostring(d.isUseItem), tostring(d.IsAll),
                tostring(d.ParentActionKey and num(d.ParentActionKey.Category)), tostring(d.ParentActionKey and num(d.ParentActionKey.ID)),
                ids(d.targetUnitUniqueIdList), ids(d.ParameterList),
                tostring(row and row.attr), tostring(row and row.effect), tostring(row and row.cost), tostring(row and row.target)))
        end)
    end
    local keys = {}
    if v.actionKeys and v.actionKeys.ForEach then
        v.actionKeys:ForEach(function(_, e)
            local k = unwrap(e)
            if k then keys[#keys + 1] = tostring(num(k.Category)) .. "/" .. tostring(num(k.ID)) end
        end)
    end
    line(string.format("  actions %d, keys [%s]", count, table.concat(keys, " ")))
end

local function hookDecide()
    RegisterHook("/Script/mucha.CPP_BtlDelEventCmd:OnExecuteDecideCommand", function(_, value)
        -- No game reads inside a hook beyond its own value: the risk list and
        -- the hit walk run on the game thread right after it returns. The row
        -- walk is the same. A lookup from here only schedules it.
        hookDepth = hookDepth + 1
        local okBody, errBody = pcall(function()
            if applyPendingOrder and Fight and Fight.orderFresh then gameDelay(0, applyPendingOrder) end
            pcall(function()
                local v = value:get()
                local fromMod = (Menu.byMod == true)
                local echoed = (Menu.byEcho == true)
                Menu.byMod = false
                Menu.byEcho = false
                local actorNow = nil
                pcall(function() actorNow = Known.echoActor(v) end)
                Menu.fromMenu = Menu.open and (not Menu.decided) and true or false
                learn(v)
                if not fromMod then
                    local okTrace, errTrace = pcall(Menu.traceHand, v)
                    if not okTrace then log("hand trace failed: %s", tostring(errTrace)) end
                end
                Menu.decided = true
                Menu.sub = false
                -- An echo is the player's turn sent again: the same ledger, but
                -- not taped a second time.
                if (not fromMod) or echoed then
                    Known.echoNow = echoed
                    local okNote, errNote = pcall(noteHand, v)
                    Known.echoNow = nil
                    if not okNote then log("player command was not recorded: %s", tostring(errNote)) end
                end
                Known.echoPrev = { actor = actorNow, hand = not fromMod }
            end)
        end)
        hookDepth = hookDepth - 1
        if not okBody then log("hook error: %s", tostring(errBody)) end
    end)
end

local function hookMenu()
    -- Any cancel while the wheel is up ends the mod's part in it. See
    -- Known.skipWheel.
    pcall(function()
        RegisterHook("/Script/mucha.CPP_VM_BtlCmd:CancelCommand", function()
            if Fight and Fight.wheelUp then Fight.wheelCancelled = true end
        end)
    end)
    RegisterHook("/Script/mucha.CPP_MuchaEventDispatcher:ExecuteEvent", function(_, tag)
        local ok, name = pcall(function() return tag:get().TagName:ToString() end)
        if not ok then return end
        if name == "Delegate.Battle.Cmd.List.Begin" then
            -- The fight is up. Read the rows after this hook returns, before
            -- the command is chosen.
            rowsAllowed = true
            queueRowWalk()
            if applyPendingOrder and Fight and Fight.orderFresh then gameDelay(0, applyPendingOrder) end
            local actor = currentActor()
            Menu.sub = (actor == Menu.actor) and (not Menu.decided)
            if (Menu.traceLeft or 0) > 0 then
                Menu.traceLeft = Menu.traceLeft - 1
                pcall(log, "  menu opens: actor %s, same actor %s, undecided %s", tostring(actor), tostring(actor == Menu.actor), tostring(not Menu.decided))
            end
            Menu.actor = actor
            Menu.decided = false
            -- The game's own opening command is done. See noteHand.
            if Fight and Fight.waitMenu then
                Fight.waitMenu = nil
                gameDelay(0, function() pcall(ensureBattle) end)
            end
            -- A menu after the fight was set up: the turn before it is done.
            if Fight and Fight.active and Menu.armPace then Menu.armPace("a command menu") end
            Menu.open = true
            Menu.serial = Menu.serial + 1
            gameDelay(0, function() if Menu.keepPace then Menu.keepPace() end end)
            if Menu.sub then return end
            scheduleAct()
        elseif name == "Delegate.Battle.Cmd.List.End" then
            Menu.open = false
            gameDelay(0, function() if Menu.keepPace then Menu.keepPace() end end)
        end
    end)
end

-- SkipScenes. A Limit Burst, a Vision finish (the finish-blow attribute),
-- an Esper summon, or a skill by the unit that call put on the field is
-- the scene. Once the cinematic manager allows a skip, the battle input
-- skip and the sequence skip reaction end it and hand the camera back.
-- The sequence player is never stopped, and a movie widget is never
-- closed from here. Cutting either one leaves the battle waiting on a
-- scene that is already gone. The look runs only after one of those
-- skills begins. A story scene is left alone. A scene that never allows
-- a skip is left to play.
local Scene = { want = nil, allow = false, quietId = nil, quietUntil = 0, told = {} }

local function live(obj)
    return type(obj) == "userdata" and obj.IsValid and obj:IsValid()
end

function Scene.same(a, b)
    if not (live(a) and live(b)) then return false end
    if a == b then return true end
    local okA, na = pcall(function() return a:GetFullName() end)
    local okB, nb = pcall(function() return b:GetFullName() end)
    return okA and okB and type(na) == "string" and na == nb
end

-- EMovieScenePlayerStatus::Playing is 1.
local function sequencePlaying(actor)
    if not live(actor) then return false end
    local ok, on = pcall(function()
        local player = actor.SequencePlayer
        if not live(player) then player = actor:GetSequencePlayer() end
        if not live(player) then return false end
        local flag = player:IsPlaying()
        if type(flag) == "boolean" then return flag end
        if num(flag) == 1 then return true end
        return num(player.Status) == 1
    end)
    return ok and on == true
end

local function jobSkillId(job)
    local skill = job.m_pSkill
    if not live(skill) then return nil end
    local ok, id = pcall(function() return skill:GetSkillId() end)
    if not ok then return nil end
    return num(id)
end

local function findSceneJob(skillId)
    local ok, found = pcall(function() return FindAllOf("CPP_BtlJobSkill") end)
    if not (ok and type(found) == "table") then return nil end
    local jobs = {}
    for _, job in ipairs(found) do
        if live(job) and sequencePlaying(job.m_pLevelSequenceActor) then
            jobs[#jobs + 1] = job
        end
    end
    if #jobs == 0 then return nil end
    for _, job in ipairs(jobs) do
        if jobSkillId(job) == skillId then return job end
    end
    if #jobs == 1 then
        local id = jobSkillId(jobs[1])
        if id and id ~= skillId then return nil end
        return jobs[1]
    end
    return nil
end

-- eBtlSequenceEventType::OtherSkipResetParameter is 120. The sequence uses
-- it when a scene is skipped, and IsPlaySkipReaction keeps the hit.
function Scene.player(actor)
    if not live(actor) then return nil end
    local player = actor.SequencePlayer
    if live(player) then return player end
    local ok, got = pcall(function() return actor:GetSequencePlayer() end)
    if ok and live(got) then return got end
    return nil
end

local function askSkip(job)
    local ok, err = pcall(function()
        local cls = StaticFindObject("/Script/mucha.CPP_MuchaDelegateValue")
        if not live(cls) then error("could not build a scene skip") end
        local obj = StaticConstructObject(cls, job)
        if not live(obj) then error("could not build a scene skip") end
        job:OnSkipSkill(obj)
    end)
    if not ok then
        log("scene skip failed: %s", tostring(err))
        return false
    end
    return true
end

function Scene.press()
    local okMgr, mgr = pcall(function() return FindFirstOf("CPP_BtlManager") end)
    if not (okMgr and live(mgr)) then return false end
    local input = mgr.m_pBtlInput
    if not live(input) then return false end
    local ok, err = pcall(function() input:OnSkipSkill({}) end)
    if not ok then
        if not Scene.told.press then
            Scene.told.press = true
            log("scene skip failed: %s", tostring(err))
        end
        return false
    end
    return true
end

function Scene.director(job)
    local event = job.m_pSequencerEvent
    local player = Scene.player(job.m_pLevelSequenceActor)
    if not (live(event) and player) then return nil, nil end
    local okFound, found = pcall(function() return FindAllOf("CPP_BtlLevelSequenceDirector") end)
    if not (okFound and type(found) == "table") then return nil, nil end
    local director = nil
    for _, d in ipairs(found) do
        if live(d) and Scene.same(d.Player, player) then
            director = d
            break
        end
    end
    if (not director) and (#found == 1) and live(found[1]) then director = found[1] end
    if not director then return nil, nil end
    return director, event
end

function Scene.react(job)
    local director, event = Scene.director(job)
    if not director then return false end
    local ok, err = pcall(function()
        director:BattleSequencerEvent(event, {
            EventType = 120,
            Other_SkipResetParameter_IsPlaySkipReaction = true,
        })
    end)
    if not ok then
        if not Scene.told.reaction then
            Scene.told.reaction = true
            log("scene skip failed: %s", tostring(err))
        end
        return false
    end
    return true
end

function Scene.allowed()
    if Scene.allow then return true end
    local ok, mgr = pcall(function() return FindFirstOf("CPP_UI_BtlCinematicManager") end)
    if not (ok and live(mgr)) then return false end
    return mgr.bAllowSkip == true
end

local function watchScene(skillId, name)
    if Scene.want == skillId then return end
    if Scene.quietId == skillId and os.clock() < Scene.quietUntil then return end
    Scene.want = skillId
    Scene.allow = false
    -- A watched scene stays at normal speed. Turbo resumes when it ends.
    Menu.pace.scene = true
    if Menu.keepPace then Menu.keepPace() end
    -- askedAt is the tick the game's own skip was sent. Nothing is sent
    -- until the cinematic manager allows it, and the player is never cut
    -- if that skip does not finish the scene.
    local ticks, askedAt, seen, quiet = 0, nil, false, 0
    -- reportOnly: a scene held for turbo is not news in UE4SS.log.
    local function finish(text, reportOnly)
        if Scene.want == skillId then Scene.want = nil end
        Scene.quietId = skillId
        Scene.quietUntil = os.clock() + 0.5
        if Menu.pace.scene then
            Menu.pace.scene = false
            if Menu.keepPace then Menu.keepPace() end
        end
        if not reportOnly then log("%s", text) end
        appendLog("  " .. text)
    end
    local function step(left)
        if Scene.want ~= skillId then return end
        -- Turbo alone only holds the scene at normal speed. Nothing is skipped.
        local watchOnly = not cfg.SkipScenes
        if watchOnly and not cfg.Turbo then
            if Menu.pace.scene then
                Menu.pace.scene = false
                if Menu.keepPace then Menu.keepPace() end
            end
            return
        end
        local job = nil
        local okJob, got = pcall(findSceneJob, skillId)
        if okJob then job = got end
        local still = job and live(job) and (
            sequencePlaying(job.m_pLevelSequenceActor) or sequencePlaying(job.m_pSoundSequenceActor))
        if still then
            seen = true
            ticks = ticks + 1
            quiet = 0
            local matched = jobSkillId(job) == skillId
            if (not watchOnly) and (not askedAt) and Scene.allowed() and (matched or ticks >= 3) then
                askedAt = ticks
                Scene.press()
                askSkip(job)
                Scene.react(job)
            end
        elseif askedAt then
            quiet = quiet + 1
            if quiet >= 8 then
                finish(string.format("scene skip: %s", name))
                return
            end
        elseif watchOnly then
            -- The scene played and stopped, or no scene began within three
            -- seconds. Either way turbo goes back on.
            -- TUNE: if reports show a Limit sped up because its scene began
            -- late, raise the 30. If summoned units' plain hits drag, lower it.
            quiet = quiet + 1
            if (seen and quiet >= 2) or ((not seen) and quiet >= 30) then
                finish(string.format("turbo held for %s", name), true)
                return
            end
        elseif seen then
            -- The scene played and stopped before the game allowed a skip.
            -- Nothing is left to skip, so turbo goes back on now, not at the
            -- end of the watch.
            quiet = quiet + 1
            if quiet >= 2 then
                finish(string.format("scene skip: %s not allowed", name))
                return
            end
        end
        if Scene.want ~= skillId then return end
        if left > 0 then
            gameDelay(100, function() step(left - 1) end)
            return
        end
        if watchOnly then
            finish(string.format("turbo held for %s", name), true)
        elseif askedAt and not still then
            finish(string.format("scene skip: %s", name))
        elseif askedAt then
            finish(string.format("scene skip failed: %s still playing", name))
        elseif seen then
            finish(string.format("scene skip: %s not allowed", name))
        else
            finish(string.format("scene skip failed: %s had no sequence", name))
        end
    end
    step(200)
end

local function considerScene(skillId, actorId)
    if not (cfg.SkipScenes or cfg.Turbo) or not skillId then return end
    pcall(buildSkillIndex, true)
    local row = skillOf(skillId)
    local scene = row and (row.attr == ATTR.LB or row.attr == ATTR.FINISH or row.attr == ATTR.SUMMON)
    -- The summon intro is the summon skill. The attack after it belongs to
    -- the unit that call put on the field.
    if not scene and actorId and Fight then
        local mark = Fight.esperOut
        local summoned = Fight.summons and Fight.summons[actorId]
        if (not summoned) and mark and (mark.who == actorId) then summoned = true end
        if (not summoned) and mark and (not mark.who) then
            local catalog = catalogOf(actorId)
            summoned = catalog and mark.unit and (catalog == mark.unit)
                and not (Fight.openIds and Fight.openIds[actorId])
        end
        scene = summoned and true or false
    end
    if not scene then return end
    watchScene(skillId, (row and row.name) or tostring(skillId))
end

-- Turbo uses the same watch to hold a scene at normal speed, without a skip.
local function hookScenes()
    if not (cfg.SkipScenes or cfg.Turbo) then return end
    RegisterHook("/Script/mucha.CPP_VM_BtlMsg:HandleBeginSkill", function(_, delval)
        if not (cfg.SkipScenes or cfg.Turbo) then return end
        local id, actor = nil, nil
        pcall(function()
            local row = delval:get()
            id = num(row and row.SkillId)
            actor = num(row and row.actionUnitUniqueId)
            row = nil
        end)
        if not id then return end
        gameDelay(0, function() considerScene(id, actor) end)
    end)
    RegisterHook("/Script/mucha.CPP_UI_BtlCinematicManager:HandleSkipAllow", function(_, value)
        if not cfg.SkipScenes then return end
        local allow = false
        pcall(function()
            local row = value:get()
            allow = row and row.isAllow and true or false
            row = nil
        end)
        Scene.allow = allow
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

-- The wheel's skip, as a hand skip sends it: CancelCommand on the battle
-- command menu (seen 2026-11-10; the game then clears the command stack).
-- Nothing in the battle is read here. Ticks are resonanceWatch's 400 ms:
-- the call waits for the wheel to take input. It goes once. Any cancel,
-- the player's or this one, ends the mod's part in that wheel (see
-- hookMenu), so a late call can't land on the next command menu.
-- TUNE: if the first call comes before the wheel takes input, raise 3.
function Known.skipWheel()
    Fight.wheelTicks = (Fight.wheelTicks or 0) + 1
    if Fight.wheelTicks ~= 3 then return end
    local vm, from = nil, nil
    pcall(function()
        local lib = StaticFindObject("/Script/mucha.Default__CPP_BFL_UI_Btl")
        if lib and lib:IsValid() then
            local got = lib:FindBtlCmdVM()
            if got and got.IsValid and got:IsValid() then vm, from = got, "FindBtlCmdVM" end
        end
    end)
    if not vm then
        pcall(function()
            for _, o in ipairs(FindAllOf("CPP_VM_BtlCmd") or {}) do
                if o:IsValid() and ((not vm) or o.bDisplayCmd == true) then vm, from = o, "object list" end
            end
        end)
    end
    if not vm then
        local line = "wheel skip: no command menu found"
        log("%s", line)
        appendLog("  " .. line)
        return
    end
    vm:CancelCommand()
    Fight.wheelSkips = (Fight.wheelSkips or 0) + 1
    local line = string.format("wheel skip: CancelCommand sent (menu from %s)", from)
    log("%s", line)
    appendLog("  " .. line)
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
        if Fight.wheelCancelled and (Fight.wheelSkips or 0) == 0 then
            log("wheel skipped by hand")
            appendLog("  wheel skipped by hand")
        end
        Fight.wheelUp, Fight.wheelCancelled = nil, nil
        Fight.resonanceSent = false
        Fight.resonanceMiss = false
        Fight.resonanceWait = false
        Fight.wheelLogged = false
        if Fight.wheelLeft and Fight.wheelSkip and (Fight.wheelSkips or 0) > 0 then
            local line = string.format("wheel skipped (%d call%s)", Fight.wheelSkips, (Fight.wheelSkips == 1) and "" or "s")
            log("%s", line)
            appendLog("  " .. line)
        end
        Fight.wheelLeft, Fight.wheelSkip = nil, nil
        Fight.wheelTicks, Fight.wheelSkips = 0, 0
        return
    end
    Fight.wheelUp = true
    if Fight.resonanceSent then return end
    -- A cancel while the wheel is up, by hand or by the mod: the wheel is
    -- done. Nothing more is picked or sent for it.
    if Fight.wheelCancelled then
        Fight.wheelLate = (Fight.wheelLate or 0) + 1
        if Fight.wheelLate == 10 then
            log("wheel still up 4 s after a cancel; the wheel is yours")
            appendLog("  wheel still up 4 s after a cancel; the wheel is yours")
        end
        return
    end
    Fight.wheelLate = 0
    -- A wheel left to the player is not read again. A skip ends the battle,
    -- and a read while the game takes it down crashed the game.
    -- A wheel already decided: -1 leaves it to the player untouched; a
    -- level gap skips it.
    if Fight.wheelLeft then
        if Fight.wheelSkip then
            local okSkip, errSkip = pcall(Known.skipWheel)
            if not okSkip then log("wheel skip failed: %s", tostring(errSkip)) end
        end
        return
    end
    if cfg.Echo then
        local okEcho, errEcho = pcall(Known.echoWheelTurn)
        if not okEcho then log("echo wheel failed: %s", tostring(errEcho)) end
        return
    end
    if (tonumber(cfg.ResonanceLevelGap) or 0) < 0 then
        Fight.wheelLeft = "ResonanceLevelGap is -1"
        local line = "wheel left to you: " .. Fight.wheelLeft
        log("%s", line)
        appendLog("  " .. line)
        return
    end
    if not Fight.resonanceWait then
        Fight.resonanceWait = true
        return
    end
    pcall(buildSkillIndex)
    local bestUid, bestChoice, bestScore = nil, nil, -1e9
    local careUid, careChoice = nil, nil
    local names = {}
    local wheelNotes, wheelFoes = {}, nil
    local standing, hurting = {}, false
    for _, uid in ipairs(friendIds()) do
        local ratio = hpRatio(uid)
        local down = (Fight.unitDown and Fight.unitDown(uid)) or (ratio == nil) or (ratio <= 0)
        if down then hurting = true end
        if (not down) and not outOfControl(uid) then
            names[#names + 1] = unitName(uid)
            standing[#standing + 1] = uid
            local okW, w = pcall(worldOf, uid, Fight.boss, Fight.summoned)
            if okW and w then
                for _, a in ipairs(w.allies or {}) do
                    if a.exposed then hurting = true end
                end
                local skills = {}
                local okS, got = pcall(finishList, uid)
                if okS and type(got) == "table" then skills = got end
                local okPick, choice = pcall(pickFinish, uid, skills, w)
                if okPick and choice then
                    local caring = choice.reason and choice.reason:find("resonance heal", 1, true)
                    if caring then
                        careUid, careChoice = uid, choice
                    elseif (choice.score or 0) > bestScore then
                        bestUid, bestChoice, bestScore = uid, choice, choice.score or 0
                    end
                end
                if not Fight.wheelLogged then
                    pcall(function()
                        wheelFoes = wheelFoes or w.enemies
                        local rows = {}
                        for _, s in ipairs(skills) do
                            rows[#rows + 1] = string.format("%s %s%s", tostring(s.name), tostring(s.kind),
                                s.wheelScore and string.format(" %.0f", s.wheelScore) or "")
                        end
                        local picked = (okPick and choice) and string.format(", pick %s", choice.name) or ""
                        wheelNotes[#wheelNotes + 1] = string.format("%s %d%% vision %s: %s%s", unitName(uid),
                            math.floor((ratio or 0) * 100 + 0.5), tostring(visionIdOf(uid) or "?"),
                            (#rows > 0) and table.concat(rows, ", ") or "no rows", picked)
                    end)
                end
            end
        elseif not Fight.wheelLogged then
            wheelNotes[#wheelNotes + 1] = unitName(uid) .. " can't act"
        end
    end
    if not Fight.wheelLogged then
        Fight.wheelLogged = true
        pcall(function()
            local foes = {}
            for _, u in ipairs(wheelFoes or {}) do
                foes[#foes + 1] = string.format("%s %d%%", tostring(u.name), math.floor((u.hp or 0) * 100 + 0.5))
            end
            Fight.repWheelOpen = (Fight.repWheelOpen or 0) + 1
            local line = string.format("wheel. foes %s. %s", table.concat(foes, ", "), table.concat(wheelNotes, ". "))
            log("%s", line)
            appendLog("  " .. line)
        end)
    end
    -- ResonanceLevelGap 1 or more: a fight whose every foe is that many
    -- levels under every standing ally gets no pick, and the wheel is
    -- skipped, unless it is a boss or an ally is down or exposed (the
    -- wheel's heal case). -1 is handled above: the wheel is the player's.
    -- TUNE: if under-level fights drag on without the finisher, raise the gap.
    local why = nil
    pcall(function()
        local gap = tonumber(cfg.ResonanceLevelGap) or 0
        if (gap >= 1) and (not Fight.boss) and (not hurting) and Espers.outLeveled and (#standing > 0) then
            local foes = {}
            for i, u in ipairs(wheelFoes or {}) do foes[i] = Known.foeLevel(u.id) or false end
            local all = true
            for _, uid in ipairs(standing) do
                if not Espers.outLeveled(Known.allyLevel(uid), foes, gap) then all = false end
            end
            if all then why = string.format("every foe is %d or more levels under", gap) end
        end
    end)
    if why then
        Fight.wheelLeft, Fight.wheelSkip = why, true
        local line = string.format("wheel skip: %s", why)
        log("%s", line)
        appendLog("  " .. line)
        return
    end
    if careChoice then
        bestUid, bestChoice = careUid, careChoice
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
    Fight.repWheelSent = (Fight.repWheelSent or 0) + 1
    local who = unitName(bestUid)
    local line = string.format("resonance %s by %s -> %s", bestChoice.name, who, bestChoice.reason)
    log("%s", line)
    appendLog("  " .. line)
    -- The hit list never holds a wheel skill, so the report measures it by HP.
    Known.repRun(function()
        Known.report:field(Known.repSnap())
        Known.report:wheel(bestChoice.name, who)
    end)
    rememberCast(who, bestChoice.name)
    Fight.actions[#Fight.actions + 1] = line
    Fight.last = { who = who, skill = bestChoice.name }
end

local absent = 0
gameLoop(400, resonanceWatch)
gameLoop(700, function()
    -- The row walk is not started here. This timer runs from launch, including
    -- while a save is loading, and that walk crashed the game.
    if not Fight.active then return end
    local u = FindFirstOf("CPP_BtlUnit")
    if u and u:IsValid() then
        absent = 0
        -- A fall between turns is noted here too, so the last one before
        -- the battle ends, such as a wipe, still reaches the log.
        pcall(function() noteChanges(livingSnapshot()) end)
        if Growth.field then pcall(Growth.field) end
        -- The report opens on the timer too, so a fight's first commands count
        -- even when the player sends them by hand.
        if Known.report and Fight.active then
            Known.repRun(function()
                if not Known.report.fight then Known.repBegin() end
                Known.repHandFlush()
                local snapNow = Known.repSnap()
                Known.report:field(snapNow)
                Known.repCards(snapNow)
                -- The hit list holds only the latest skill, so a menu alone misses
                -- casts. Every tick catches them, and a wipe's killing blow.
                if readRisk then pcall(readRisk, true) end
            end)
        end
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
    if Fight and Fight.active then appendLog("  switch: " .. msg) end
    showToast(msg)
    if cfg.Enabled then scheduleAct() end
end

-- No Mercy or Echo.
local function pressBasic()
    cfg.Echo = not cfg.Echo
    saveState()
    local msg = cfg.Echo and "AutoBattle: Echo Mode" or "AutoBattle: No Mercy!"
    log(msg)
    if Fight and Fight.active then appendLog("  switch: " .. msg) end
    showToast(msg)
end

local function inFight()
    return battleUp()
end

-- The large field map. On only works on the field. Off works anywhere.
function Known.pressMap()
    local mm = Known.minimap
    if not (mm and cfg.LargeMap) then return end
    local ok, err = pcall(mm.toggle, mm.fraction(cfg.MapSize), not inFight())
    if not ok then log("large map failed: %s", tostring(err)) end
end

-- The left trigger and the middle mouse button. Both are used by the game in
-- some menus and on its world map, so they only act while the field HUD is in front.
function Known.pressMapField(what)
    if not (cfg.LargeMap and Known.minimap) then return end
    if inFight() then return end
    if Known.minimap.fieldActive() then
        Known.pressMap()
    else
        log("large map: %s left to the open menu", what)
    end
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
    if not inFight() then
        -- On the field the left trigger is the large map. In a menu it stays with the game.
        if leftRose then Known.pressMapField("left trigger") end
        return
    end
    if leftRose and cfg.Enabled then pressBasic() end
    if rightRose then pressAuto() end
end

loadConfig()
pcall(Known.echoLoad)

bind("TakeOverKey", pressAuto)
bind("MenuKey", pressBasic)
if cfg.LargeMap then
    bind("MapKey", Known.pressMap)
    if Key.MIDDLE_MOUSE_BUTTON then
        RegisterKeyBind(Key.MIDDLE_MOUSE_BUTTON, function()
            ExecuteInGameThread(function() Known.pressMapField("middle mouse button") end)
        end)
    end
    log("large map on. %s toggles it. On the field the left trigger and the middle mouse button toggle it.", tostring(cfg.MapKey))
end
-- A conversation resets the map's scale. While the large map is on, it is
-- read every frame and made large again. A new area's HUD is looked for less often.
gameLoop(16, function()
    local mm = Known.minimap
    if mm and mm.isOn() then mm.hold() end
end)
gameLoop(1000, function()
    local mm = Known.minimap
    if mm and mm.isOn() then mm.keep(mm.fraction(cfg.MapSize), not inFight()) end
end)
-- A toggle. Ten times a second still catches a press, in a fight or out of one.
gameLoop(100, pollTriggers)

local okHook, errHook = pcall(function()
    hookDecide()
    hookMenu()
    hookTimeline()
end)
if not okHook then log("hook failed: %s", tostring(errHook)) end

local okScene, errScene = pcall(hookScenes)
if not okScene then log("scene skip failed: %s", tostring(errScene)) end
if cfg.SkipScenes then log("scene skip on") end

if cfg.LevelGate then log("level gate on") end
if cfg.Turbo then
    log("turbo on")
    pcall(Menu.hookPace)
    -- Often enough that a menu open does not spend a beat at the action rate.
    gameLoop(16, function() if Menu.keepPace then Menu.keepPace() end end)
end

log("loaded. planner v1.1. %s. %s toggles auto battle. %s switches No Mercy and Echo; now %s. In a fight, while auto battle is on, the left trigger switches the mode. The right trigger toggles auto battle. Submit=%s.",
    cfg.Enabled and "on" or "off",
    cfg.TakeOverKey,
    cfg.MenuKey,
    cfg.Echo and "Echo" or "No Mercy",
    tostring(cfg.Submit))

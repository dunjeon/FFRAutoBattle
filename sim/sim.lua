-- FFR:AutoBattle battle sim. A stand-in for the game and for UE4SS, so the
-- real Scripts/main.lua can be loaded unchanged and played against fights.
--
-- The model is a simple turn-based battle, not the game's formulas. It is
-- here to exercise the planner's rules: the field, the gauge, the heal and
-- cure lines, items, raises, summons, Limit Bursts, the bonus phase, the
-- Resonance wheel, and statuses that take a turn. Numbers are invented and
-- only roughly balanced. Do not tune the planner's lines from them.
--
-- The game facts the planner relies on are copied from the design doc:
-- the live break ratio stays full, a weakness is x3 stagger, every living
-- enemy broken at once opens the bonus phase and then the wheel, a status
-- that takes the turn has no menu, and the game decides for a confused ally.

local Sim = {}

local ATTR = { FIGHT = 1, ABILITY = 3, MAGIC = 4, LB = 5, ITEM = 6, SUMMON = 7, FINISH = 9, ESCAPE = 16 }
local EFF = { DAMAGE = 1, PARAM = 2, CURE = 19, REVIVE = 20, DEFEND = 26, ANALYZE = 29, COVER = 41 }
local TGT = { SELF = 0, SINGLE = 1, GROUP = 2, ALL = 4 }
local REL = { FRIEND = 1, ENEMY = 2 }
local ST = {
    POISON = 1, BLIND = 2, SLEEP = 3, SILENCE = 4, PARALYSIS = 5, CONFUSE = 6,
    PETRIFY = 7, CHARM = 8, STOP = 9, BERSERK = 10, DOOM = 11, SLOW = 12,
    PROTECT = 25, SHELL = 27, HASTE = 30, BREAK = 89,
}
Sim.ATTR, Sim.EFF, Sim.TGT, Sim.REL, Sim.ST = ATTR, EFF, TGT, REL, ST

-- Statuses that take the turn with no menu, and the ones the game plays for.
local NO_TURN = { [ST.SLEEP] = true, [ST.PARALYSIS] = true, [ST.PETRIFY] = true, [ST.STOP] = true }
local GAME_PLAYS = { [ST.CONFUSE] = true, [ST.CHARM] = true, [ST.BERSERK] = true }
local BAD = {}
for id = 1, 12 do BAD[id] = true end
-- Esuna clears these. Doom and berserk need something stronger.
local ESUNA = {
    [ST.POISON] = true, [ST.BLIND] = true, [ST.SLEEP] = true, [ST.SILENCE] = true,
    [ST.PARALYSIS] = true, [ST.CONFUSE] = true, [ST.PETRIFY] = true, [ST.CHARM] = true,
    [ST.SLOW] = true, [ST.STOP] = true,
}

--------------------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------------------

local function title(name)
    return (name:gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end))
end

-- A UE array: integer slots and ForEach.
local ArrMeta = { __index = { ForEach = function(self, fn) for i = 1, #self do fn(i, self[i]) end end } }
local function Arr(t) return setmetatable(t or {}, ArrMeta) end

local function FNameOf(s) return { s = s, ToString = function(self) return self.s end } end

local function valid() return true end

--------------------------------------------------------------------------------
-- Skill and item rows. One catalog for the whole run, like the game's tables.
--------------------------------------------------------------------------------

Sim.skills = {}      -- id -> row
Sim.skillByName = {} -- lower name -> row
Sim.items = {}       -- id -> item row
Sim.itemByName = {}
local nextSkill, nextItem = 1000, 5000

-- spec: name, attr, effect, cost, power, stagger, target, rel, heal, mp,
-- calc, status, revive, hits, element(sim only), lbGauges, summonTurns
function Sim.addSkill(spec)
    local key = spec.name:lower()
    if Sim.skillByName[key] then return Sim.skillByName[key] end
    nextSkill = nextSkill + 1
    local row = {
        ID = spec.id or nextSkill,
        Name = spec.name,
        Cost = spec.cost or 0,
        skillAttrType = spec.attr or ATTR.MAGIC,
        skillEffectType = spec.effect or EFF.DAMAGE,
        parameterVariationType = (spec.heal or spec.mp) and 0 or -1,
        parameterType = spec.mp and 2 or (spec.heal and 1 or 0),
        TargetType = spec.target or TGT.SINGLE,
        defaultTargetRelation = spec.rel or REL.ENEMY,
        magnification = spec.power or 0,
        damageCalcType = spec.calc or 0,
        breakDamageValue = spec.stagger or 0,
        hitCount = spec.hits or 1,
        defaultTargetState = spec.revive and 2 or 0,
        statusCondition = spec.status or 0,
        sim = spec,
    }
    Sim.skills[row.ID] = row
    Sim.skillByName[key] = row
    return row
end

function Sim.addItem(name, skillSpec, rare)
    nextItem = nextItem + 1
    skillSpec.name = skillSpec.name or (name .. " (item)")
    skillSpec.attr = ATTR.ITEM
    local s = Sim.addSkill(skillSpec)
    local row = { ID = nextItem, Name = name, SkillId = s.ID, Rare = rare and true or false, skill = s }
    Sim.items[row.ID] = row
    Sim.itemByName[name:lower()] = row
    return row
end

--------------------------------------------------------------------------------
-- Clock and timers. UE4SS game-thread timers on a fake clock.
--------------------------------------------------------------------------------

local timers, now = {}, 0
local function schedule(ms, fn, every)
    timers[#timers + 1] = { at = now + ms, fn = fn, every = every }
end
function Sim.advance(ms, stop)
    local target = now + ms
    while true do
        local bestI, best = nil, nil
        for i, t in ipairs(timers) do
            if t.at <= target and ((not best) or t.at < best.at) then bestI, best = i, t end
        end
        if not best then break end
        table.remove(timers, bestI)
        now = best.at
        if best.every then schedule(best.every, best.fn, best.every) end
        best.fn()
        if stop and stop() then return true end
    end
    now = target
    return stop and stop() or false
end

--------------------------------------------------------------------------------
-- The battle state
--------------------------------------------------------------------------------

local B = nil -- current battle
Sim.hooks = {}
Sim.modLog = {}
Sim.echo = false

local function unitById(id)
    if not B then return nil end
    return B.units[id]
end

local function living(side)
    local out = {}
    if not B then return out end
    for _, u in pairs(B.units) do
        if u.side == side and not u.dead and not u.gone then out[#out + 1] = u end
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

local function has(u, st) return u.statuses[st] ~= nil end

--------------------------------------------------------------------------------
-- UE4SS objects the planner calls
--------------------------------------------------------------------------------

local function paramFor(u)
    local p = {}
    p.IsValid = valid
    p.GetDuplicationUnitName = function() return u.name end
    p.GetUnitId = function() return u.unitId end
    p.GetUniqueId = function() return u.id end
    p.GetRelation = function() return (u.side == "enemy") and REL.ENEMY or REL.FRIEND end
    p.isDead = function() return u.dead end
    p.GetHitPoint = function() return u.hp end
    p.GetParameterByType = function(_, kind)
        if kind == 1 then return u.hp end
        if kind == 2 then return u.mp end
        if kind == 4 then return u.lb or 0 end
        return 0
    end
    p.GetMaxParameterByType = function(_, kind)
        if kind == 1 then return u.maxHp end
        if kind == 2 then return u.maxMp end
        if kind == 4 then return u.lbMax or 200 end
        return 0
    end
    -- The doc: the live break ratio stays full after a hit.
    p.GetBreakPointRatio = function() return 1.0 end
    p.GetLimitBurstPoint = function() return u.lb or 0 end
    local function skillList(t)
        for _, id in ipairs(u.skillIds or {}) do t[#t + 1] = id end
    end
    p.GetActiveSkillListWithVision = function(_, t) skillList(t) end
    p.GetActiveSkillList = function(_, t) skillList(t) end
    p.GetActionList = function() end
    return p
end

local function legalTargets(uid, skillId, relation)
    local s = Sim.skills[skillId]
    local out = {}
    if not s then return out end
    if relation == REL.FRIEND then
        local wantDead = (s.skillEffectType == EFF.REVIVE) or (s.defaultTargetState == 2)
        for _, u in pairs(B.units) do
            if u.side == "ally" and not u.gone then
                if wantDead and u.dead then out[#out + 1] = u.id end
                if (not wantDead) and (not u.dead) then out[#out + 1] = u.id end
            end
        end
    else
        for _, u in ipairs(living("enemy")) do out[#out + 1] = u.id end
    end
    table.sort(out)
    return out
end

local function sealed(u, s)
    if s.skillAttrType == ATTR.MAGIC and has(u, ST.SILENCE) then return true end
    if s.skillAttrType == ATTR.LB then
        local need = (s.sim.lbGauges or 1) * 100
        if (u.lb or 0) < need then return true end
    end
    if s.skillAttrType == ATTR.FINISH and (not B or B.phase ~= 2) then return true end
    return false
end

local function owns(u, id)
    for _, sid in ipairs(u.skillIds or {}) do if sid == id then return true end end
    return false
end

local BFL = { IsValid = valid }
function BFL:GetBattleUnitParameter(uid, aliveOnly)
    local u = unitById(uid)
    if not u or u.gone then return nil end
    if aliveOnly and u.dead then return nil end
    return paramFor(u)
end
function BFL:GetStatusConditionList(t, uid)
    local u = unitById(uid)
    if not u then return end
    for id in pairs(u.statuses) do t[#t + 1] = id end
end
function BFL:GetBattleUnitListByRelation(t, rel)
    local side = (rel == REL.ENEMY) and "enemy" or "ally"
    for _, u in ipairs(living(side)) do t[#t + 1] = u.id end
end
function BFL:GetAllBattleUnitPararmeterList(t)
    if not B then return end
    for id, u in pairs(B.units) do if not u.gone then t[#t + 1] = id end end
end
function BFL:GetSkillTargetUnitUniqueIdList(t, uid, skillId, relation)
    for _, id in ipairs(legalTargets(uid, skillId, relation)) do t[#t + 1] = id end
end
function BFL:GetDefaultSkillTargetUnitUniqueId(uid, skillId)
    local s = Sim.skills[skillId]
    local rel = s and s.defaultTargetRelation or REL.ENEMY
    return legalTargets(uid, skillId, rel)[1] or -1
end
function BFL:CanUnitActivateSkill(uid, id)
    local u = unitById(uid)
    local s = Sim.skills[id]
    if not (u and s) then return false end
    if s.skillAttrType == ATTR.FIGHT and (not owns(u, id)) then return true end
    if not owns(u, id) then return false end
    return not sealed(u, s)
end
function BFL:IsEnableCommand(uid, id)
    local u = unitById(uid)
    local s = Sim.skills[id]
    if not (u and s) then return false end
    if s.skillAttrType == ATTR.ESCAPE and B and B.boss then return false end
    return BFL.CanUnitActivateSkill(self, uid, id) and (u.mp >= (s.Cost or 0) or s.skillAttrType == ATTR.LB)
end
function BFL:GetUnitLimitBurstPoint(uid) local u = unitById(uid) return u and u.lb or 0 end
function BFL:GetLimitBurstPointOneGauge() return 100 end
function BFL:GetLimitBurstPointMaxGaugeNum() return 2 end
function BFL:GetUnitLimitBurstPointGaugeNum(uid) local u = unitById(uid) return u and math.floor((u.lb or 0) / 100) or 0 end
function BFL:IsBossBattle() return B and B.boss or false end
function BFL:IsFinishPhase() return B and B.phase == 2 or false end
function BFL:GetConsumableItemList(t)
    if not B then return end
    for id, n in pairs(B.bag) do if n > 0 then t[#t + 1] = id end end
end

local SKILL_LIB = { IsValid = valid }
function SKILL_LIB:GetSkillCost(id)
    local s = Sim.skills[id]
    if not s then return 0 end
    if s.skillAttrType == ATTR.LB then return s.sim.lbGauges or 1 end
    return s.Cost or 0
end

local ITEM_LIB = { IsValid = valid }
function ITEM_LIB:GetAllItemIdListByType()
    local out = {}
    if B then for id in pairs(B.bag) do out[#out + 1] = id end end
    return out
end
function ITEM_LIB:GetInventoryItemNum(id) return (B and B.bag[id]) or 0 end
function ITEM_LIB:GetItemName(id)
    local row = Sim.items[id]
    return FNameOf(row and row.Name or "")
end
function ITEM_LIB:IsAbleRecoverHitPoint(id)
    local row = Sim.items[id]
    return row and row.skill.sim.heal and true or false
end
function ITEM_LIB:IsAbleRecoverMagicPoint(id)
    local row = Sim.items[id]
    return row and row.skill.sim.mp and true or false
end

local SUBSYSTEM = { IsValid = valid, CurrentActionUnitUniqueId = -1, BtlPhaseType = 0 }
local BTL_UNIT = { IsValid = valid }
local DECIDE_CLASS = { IsValid = valid }

local function newDecide()
    local list = setmetatable({}, {
        __index = ArrMeta.__index,
        __newindex = function(t, k, v)
            v.ParentActionKey = v.ParentActionKey or { Category = 1, ID = 0 }
            v.targetUnitUniqueIdList = v.targetUnitUniqueIdList or Arr()
            v.ParameterList = v.ParameterList or Arr()
            rawset(t, k, v)
        end,
    })
    return {
        IsValid = valid, CmdType = 0, isNotConsume = false, doCalcOrder = true, CommandId = -1,
        cmdDecideDataList = list, actionKeys = Arr(),
    }
end

local function fireHooks(path, ...)
    for _, fn in ipairs(Sim.hooks[path] or {}) do fn(nil, ...) end
end

local DISP = { IsValid = valid }
function DISP:ExecuteEvent(tag, obj)
    local name = tag.TagName:ToString()
    fireHooks("/Script/mucha.CPP_MuchaEventDispatcher:ExecuteEvent", { get = function() return tag end })
    if name == "Delegate.Battle.Cmd.Decide" then Sim.onDecide(obj, true) end
end

-- The planner only reads a DataTable that is a real userdata. Pure Lua
-- cannot make one, so a temp file handle is borrowed and given the table's
-- methods. Four are made once for the whole run.
local function asUserdata(t)
    local u = io.tmpfile()
    debug.setmetatable(u, { __index = t, __newindex = t })
    return u
end

local function tableRows(struct, rows)
    return asUserdata {
        IsValid = valid,
        GetRowStruct = function()
            return { IsValid = valid, GetFName = function() return FNameOf(struct) end }
        end,
        ForEachRow = function(_, fn)
            local ids = {}
            for id in pairs(rows) do ids[#ids + 1] = id end
            table.sort(ids)
            for _, id in ipairs(ids) do fn(tostring(id), rows[id]) end
        end,
    }
end

-- Installs the UE4SS globals. Called before each load of main.lua.
function Sim.install()
    timers, now = {}, 0
    Sim.hooks, Sim.modLog = {}, {}
    _G.print = function(s)
        s = tostring(s):gsub("\n$", "")
        Sim.modLog[#Sim.modLog + 1] = s
        if B then B.modLines[#B.modLines + 1] = s end
        if Sim.echo then io.stdout:write(s, "\n") end
    end
    _G.RegisterHook = function(path, fn)
        Sim.hooks[path] = Sim.hooks[path] or {}
        table.insert(Sim.hooks[path], fn)
    end
    _G.RegisterKeyBind = function() end
    _G.Key = setmetatable({}, { __index = function(_, k) return k end })
    _G.FName = FNameOf
    _G.FText = function(s) return s end
    _G.ExecuteInGameThread = function(fn) fn() end
    _G.ExecuteInGameThreadWithDelay = function(ms, fn) schedule(ms, fn) end
    _G.LoopInGameThreadWithDelay = function(ms, fn)
        -- The trigger poll needs a pad. The sim has none, so it is left off.
        if ms < 50 then return end
        schedule(ms, fn, ms)
    end
    _G.LoopAsync = function(ms, fn) schedule(ms, function() fn() end, ms) end
    _G.ExecuteWithDelay = function(ms, fn) schedule(ms, fn) end
    _G.StaticFindObject = function(path)
        if path:find("CPP_BFL_Battle", 1, true) then return BFL end
        if path:find("CPP_BFL_Skill", 1, true) then return SKILL_LIB end
        if path:find("CPP_BFL_Item", 1, true) then return ITEM_LIB end
        if path:find("CPP_BtlCmdDecideDelegateVal", 1, true) then return DECIDE_CLASS end
        return nil
    end
    _G.StaticConstructObject = function(cls)
        if cls == DECIDE_CLASS then return newDecide() end
        error("the sim has no UMG")
    end
    _G.FindFirstOf = function(name)
        if name == "CPP_UI_BattleSubsystem" then return SUBSYSTEM end
        if name == "CPP_MuchaEventDispatcher" then return DISP end
        if name == "CPP_BtlUnit" then return (B and B.active) and BTL_UNIT or nil end
        return nil
    end
    Sim.tables = Sim.tables or {
        tableRows("SKILL_EFFECT_DATA", {}),
        tableRows("SKILL_DATA", Sim.skills),
        tableRows("CONSUMABLES_ITEM_DATA", Sim.items),
        tableRows("VISION_ITEM_DATA", {}),
    }
    _G.FindAllOf = function(name)
        if name ~= "DataTable" then return {} end
        return Sim.tables
    end
end

--------------------------------------------------------------------------------
-- Battle model
--------------------------------------------------------------------------------

-- party: list of { name, maxHp, maxMp, atk, mag, spd, skills = {names}, hp, mp, dead, statuses }
-- foes: list of { name, card, hp, atk, spd, statusChance, statusList }
function Sim.newBattle(opts)
    B = {
        units = {}, bag = {}, boss = opts.boss or false, phase = 0, active = true,
        round = 0, lastProgress = 0, events = {}, modLines = {}, violations = {}, stats = {
            commands = 0, modCommands = 0, gameCommands = 0, playerCommands = 0, stalls = 0,
            items = {}, falls = 0, raises = 0, draws = 0, heals = 0, ethers = 0,
            bonus = 0, finish = 0, finishByMod = 0, cures = 0, cureMiss = 0, wasted = 0,
        },
        roundHeals = {}, roundEthers = 0, passActed = {}, pot = opts.pot or false, rules = opts.rules or {},
        focusHealer = opts.focusHealer or false, easy = opts.easy or false,
    }
    for i, m in ipairs(opts.party) do
        local id = i - 1
        local ids = {}
        for _, n in ipairs(m.skills) do
            local row = Sim.skillByName[n:lower()]
            if row then ids[#ids + 1] = row.ID end
        end
        B.units[id] = {
            id = id, unitId = 100 + id, side = "ally", name = m.name, member = m,
            maxHp = m.maxHp, hp = m.hp or m.maxHp, maxMp = m.maxMp, mp = m.mp or m.maxMp,
            atk = m.atk, mag = m.mag, spd = m.spd, skillIds = ids, statuses = {},
            lb = m.lb or 0, lbMax = 200, dead = (m.hp or m.maxHp) <= 0,
            healer = m.healer,
        }
        local u = B.units[id]
        if u.dead then u.hp = 0 end
        for st, n in pairs(m.statuses or {}) do u.statuses[st] = n end
    end
    local seen = {}
    for i, f in ipairs(opts.foes) do
        local id = 7 + i
        local name = f.name
        seen[name] = (seen[name] or 0) + 1
        B.units[id] = {
            id = id, unitId = 900 + id, side = "enemy", name = name, card = f.card,
            maxHp = f.hp, hp = f.hp, maxMp = 0, mp = 0, atk = f.atk, mag = f.atk, spd = f.spd,
            statuses = {}, gauge = (f.card and tonumber(f.card.gauge)) or 100, poured = 0,
            brokenFor = 0, turns = 0, statusChance = f.statusChance or 0, statusList = f.statusList,
        }
    end
    -- Duplicate names get the game's letter suffix: GoblinB, GoblinC.
    local count = {}
    for i = 1, #opts.foes do
        local u = B.units[7 + i]
        if seen[u.name] > 1 then
            count[u.name] = (count[u.name] or 0) + 1
            u.name = u.name .. string.char(65 + count[u.name])
        end
    end
    for name, n in pairs(opts.bag or {}) do
        local row = Sim.itemByName[name:lower()]
        if row then B.bag[row.ID] = n end
    end
    return B
end

function Sim.battle() return B end

local function event(fmt, ...)
    B.events[#B.events + 1] = string.format(fmt, ...)
end

local function violate(kind, fmt, ...)
    local text = string.format(fmt, ...)
    B.violations[#B.violations + 1] = { kind = kind, text = text, round = B.round }
end
Sim.violate = function(kind, fmt, ...) violate(kind, fmt, ...) end

local function card(u) return u.card end

local function elementOf(row)
    return row and row.sim and row.sim.element or nil
end

-- Element factor for stagger (the planner's x3) and for damage.
local function factors(row, foe)
    local el = elementOf(row)
    local c = card(foe)
    if not el or not c then return 1, 1 end
    if c.absorb and c.absorb[el] then return 0, -1 end
    if c.no and c.no[el] then return 0, 0 end
    if c.half and c.half[el] then return 0.5, 0.5 end
    if c.weak and c.weak[el] then return 3, 1.5 end
    return 1, 1
end

local function hurt(u, amount, src)
    if u.dead or u.gone then return end
    amount = math.max(0, math.floor(amount + 0.5))
    if u.defending then amount = math.floor(amount / 2) end
    u.hp = u.hp - amount
    if u.side == "enemy" and amount > 0 then B.lastProgress = B.round end
    if u.side == "ally" then u.lb = math.min(u.lbMax or 200, (u.lb or 0) + math.floor(amount * 60 / u.maxHp)) end
    if u.statuses[ST.SLEEP] then u.statuses[ST.SLEEP] = nil end
    if u.hp <= 0 then
        u.hp = 0
        u.dead = true
        u.statuses = {}
        if u.side == "ally" and not u.summon then
            B.stats.falls = B.stats.falls + 1
            event("%s fell (%s)", u.name, src or "?")
        end
        if u.side == "enemy" then event("%s defeated", u.name) end
    end
end

local function heal(u, amount)
    if u.dead or u.gone then return end
    u.hp = math.min(u.maxHp, u.hp + math.floor(amount + 0.5))
end

-- Hits on an enemy: damage, stagger, break.
local function strike(actor, row, foe, scale)
    if foe.dead then return end
    local spec = row.sim
    local magic = (row.skillAttrType == ATTR.MAGIC) or spec.magic
    local stagF, dmgF = factors(row, foe)
    local c = card(foe)
    local power = (row.magnification or 0)
    if power <= 0 and row.skillAttrType == ATTR.FIGHT then power = 100 end
    local base = (magic and actor.mag or actor.atk) * power / 100 * (scale or 1)
    if (not magic) and actor.statuses and actor.statuses[ST.BLIND] and math.random() < 0.5 then
        event("%s %s missed (blind)", actor.name, row.Name)
        return
    end
    if c and c.evade and (not foe.statuses[ST.BREAK]) and (not magic) then
        event("%s %s evaded", actor.name, row.Name)
        return
    end
    if foe.statuses[ST.BREAK] then base = base * 2 end
    base = base * (0.9 + math.random() * 0.2)
    if dmgF < 0 then
        heal(foe, base)
    else
        hurt(foe, base * dmgF, actor.name)
    end
    if foe.side == "enemy" and (not foe.statuses[ST.BREAK]) and stagF > 0 then
        local br = row.breakDamageValue or 0
        if br <= 0 and row.skillAttrType == ATTR.FIGHT then br = 25 end
        foe.poured = foe.poured + br * stagF * (row.hitCount or 1)
        if (not foe.dead) and foe.poured >= foe.gauge then
            foe.statuses[ST.BREAK] = 1
            foe.brokenFor = 2
            -- The game's logs: a break gives the next ally turn the bonus (p1).
            B.bonusNext = true
            B.lastProgress = B.round
            event("%s broke", foe.name)
        end
    end
    -- A counter card answers the kind of hit it is marked for.
    if c and c.counter and (not foe.dead) and (not foe.statuses[ST.BREAK]) and actor.side == "ally" then
        local phys = not magic
        local yes = (c.counter == "hit") or (c.counter == "physical" and phys) or (c.counter == "magic" and magic)
        if yes then hurt(actor, foe.atk * 1.2, foe.name .. " counter") end
    end
end

-- Haste and Slow cancel each other, as in the classic games. FFR is not confirmed.
local function applyStatus(u, st, turns)
    if u.dead then return end
    if st == ST.HASTE and u.statuses[ST.SLOW] then u.statuses[ST.SLOW] = nil return end
    if st == ST.SLOW and u.statuses[ST.HASTE] then u.statuses[ST.HASTE] = nil return end
    u.statuses[st] = turns or 3
end

local function cure(u, row)
    local listed = row.statusCondition or 0
    local cleared = 0
    for st in pairs(u.statuses) do
        local ok = false
        if listed > 0 then ok = (st == listed)
        elseif row.sim.remedy then ok = BAD[st] and true or false
        else ok = ESUNA[st] or false end
        if ok then u.statuses[st] = nil cleared = cleared + 1 end
    end
    return cleared
end

-- Resolves one command, from the planner, the player, or the game.
local function resolve(actor, row, targets, isAll, isItem, item)
    local spec = row.sim
    local eff = row.skillEffectType
    local list = {}
    for _, tid in ipairs(targets) do
        local t = unitById(tid)
        if t then list[#list + 1] = t end
    end
    if isAll and row.defaultTargetRelation == REL.ENEMY then list = living("enemy") end
    if row.skillAttrType ~= ATTR.ITEM and row.skillAttrType ~= ATTR.LB then
        actor.mp = actor.mp - (row.Cost or 0)
    end
    if row.skillAttrType == ATTR.LB then
        actor.lb = math.max(0, (actor.lb or 0) - (spec.lbGauges or 1) * 100)
    end
    if row.skillAttrType == ATTR.ESCAPE then
        B.fled = true
        event("%s led the escape", actor.name)
        return
    end
    if row.skillAttrType == ATTR.SUMMON then
        local id = 7
        B.units[id] = {
            id = id, unitId = 700, side = "ally", summon = true, name = spec.esper or row.Name,
            maxHp = 1500, hp = 1500, maxMp = 500, mp = 500, atk = actor.mag * 1.3, mag = actor.mag * 1.3,
            spd = 20, skillIds = {}, statuses = {}, life = spec.summonTurns or 3, element = spec.element,
            row = row,
        }
        event("%s summoned %s", actor.name, B.units[id].name)
        return
    end
    if eff == EFF.REVIVE then
        for _, t in ipairs(list) do
            if t.dead then
                t.dead = false
                t.hp = math.floor(t.maxHp * 0.25)
                B.stats.raises = B.stats.raises + 1
            end
        end
        return
    end
    if eff == EFF.CURE then
        for _, t in ipairs(list) do cure(t, row) end
        return
    end
    if eff == EFF.DEFEND then actor.defending = true return end
    if eff == EFF.ANALYZE then return end
    if eff == EFF.COVER then
        if row.TargetType == TGT.ALL then
            B.multiCover = { by = actor.id, left = 3 }
        else
            for _, t in ipairs(list) do t.coveredBy = { by = actor.id, left = 3 } end
        end
        return
    end
    if spec.provoke then
        B.provoke = { by = actor.id, left = 3 }
        return
    end
    if row.defaultTargetRelation == REL.FRIEND then
        for _, t in ipairs(list) do
            if spec.heal then
                local amount = (row.damageCalcType == 3) and row.magnification or ((actor.mag or 60) * row.magnification / 100)
                if spec.full then amount = t.maxHp end
                heal(t, amount)
            end
            if spec.mp then
                local amount = (row.damageCalcType == 3) and row.magnification or 60
                if spec.full then amount = t.maxMp end
                t.mp = math.min(t.maxMp, t.mp + amount)
            end
            if (row.statusCondition or 0) > 0 then applyStatus(t, row.statusCondition, spec.turns or 4) end
            if spec.raiseAll then
                for _, a in pairs(B.units) do
                    if a.side == "ally" and a.dead and not a.summon then
                        a.dead = false
                        a.hp = math.floor(a.maxHp * 0.5)
                        B.stats.raises = B.stats.raises + 1
                    end
                end
            end
        end
        return
    end
    -- Enemy side: damage, debuff, or both.
    for _, t in ipairs(list) do
        if (row.statusCondition or 0) > 0 then
            local ail = t.card and t.card.ail
            local names = { [1] = "poison", [2] = "blind", [4] = "silence", [6] = "confuse", [8] = "charm", [12] = "slow" }
            local nm = names[row.statusCondition]
            if not (ail and nm and ail[nm]) then applyStatus(t, row.statusCondition, 3) end
        end
        if (row.magnification or 0) > 0 or (row.breakDamageValue or 0) > 0 or row.skillAttrType == ATTR.FIGHT then
            strike(actor, row, t, (B.phase == 1) and 1.5 or 1)
        end
        if spec.debuff then t.debuffed = t.debuffed or {} t.debuffed[spec.debuff] = true end
    end
end

--------------------------------------------------------------------------------
-- Commands: checking and applying what the planner sends
--------------------------------------------------------------------------------

local PREMIUM = { "elixir", "megalixir", "x-potion", "turbo ether", "x-ether", "phoenix pinion", "tent", "scroll" }

-- The heal kit the doc calls the healer: best heal row power.
local function healPower(u)
    local best = 0
    for _, id in ipairs(u.skillIds or {}) do
        local s = Sim.skills[id]
        if s and s.sim.heal and s.skillAttrType ~= ATTR.ITEM and s.skillAttrType ~= ATTR.LB then best = math.max(best, s.magnification) end
    end
    return best
end

local function fieldThreat()
    for _, f in ipairs(living("enemy")) do
        -- The planner judges a break by its own count, as the doc says, so
        -- any living danger card is a threat here.
        if f.card and f.card.danger and f.card.danger[1] then return true end
    end
    return false
end

local function anyBad(u)
    for st in pairs(u.statuses) do if NO_TURN[st] or GAME_PLAYS[st] then return true end end
    return false
end

local function check(actor, row, targets, isAll, isItem, item, byMod)
    local spec = row.sim
    local tag = byMod and "planner" or "game"
    -- "One per round" is judged per round as the planner counts it: the
    -- round ends once every living ally who can take a turn has had one.
    if B.phase ~= 2 and actor.side == "ally" and not actor.summon then
        B.passActed = B.passActed or {}
        if B.passDone then
            B.passActed, B.roundHeals, B.roundEthers, B.passDone = {}, {}, 0, false
        end
        B.passActed[actor.id] = true
    end
    if byMod and B.menu and B.menu.uid ~= actor.id and B.phase ~= 2 then
        violate("wrong actor", "%s sent %s for %s", tag, row.Name, actor.name)
    end
    if B.phase == 2 and byMod and row.skillAttrType ~= ATTR.FINISH then
        violate("wheel", "normal %s sent on the Resonance wheel", row.Name)
    end
    if isItem then
        if not item or (B.bag[item.ID] or 0) <= 0 then
            violate("illegal", "%s used %s with none in the bag", actor.name, item and item.Name or "?")
            return false
        end
        local low = item.Name:lower()
        for _, p in ipairs(PREMIUM) do
            if low:find(p, 1, true) then violate("premium item", "%s used %s", actor.name, item.Name) end
        end
        if B.pot then violate("pot item", "%s used %s in a Pot fight", actor.name, item.Name) end
    else
        if not owns(actor, row.ID) and row.skillAttrType ~= ATTR.FIGHT then
            violate("illegal", "%s cast %s, not on the bar", actor.name, row.Name)
            return false
        end
        if row.skillAttrType ~= ATTR.LB and (row.Cost or 0) > actor.mp then
            violate("illegal", "%s cast %s (%d MP) with %d MP", actor.name, row.Name, row.Cost, actor.mp)
            return false
        end
        if sealed(actor, row) then
            violate("illegal", "%s cast %s while it is sealed", actor.name, row.Name)
            return false
        end
    end
    local eff = row.skillEffectType
    for _, tid in ipairs(targets) do
        local t = unitById(tid)
        if not t then
            violate("illegal", "%s %s at missing unit %s", actor.name, row.Name, tostring(tid))
            return false
        end
        if t.summon and (not isAll) and row.defaultTargetRelation == REL.FRIEND and (spec.heal or eff == EFF.REVIVE or eff == EFF.CURE) then
            violate("summon target", "%s spent %s on the summon %s", actor.name, row.Name, t.name)
        end
        if eff == EFF.REVIVE and not t.dead then
            violate("wasted revive", "%s spent %s on living %s", actor.name, row.Name, t.name)
            B.stats.wasted = B.stats.wasted + 1
        end
        if eff ~= EFF.REVIVE and (not spec.raiseAll) and t.dead and t.side == "ally" then
            violate("dead target", "%s spent %s on fallen %s", actor.name, row.Name, t.name)
        end
        if row.defaultTargetRelation == REL.ENEMY and t.side == "ally" and byMod then
            violate("wrong side", "%s aimed %s at ally %s", actor.name, row.Name, t.name)
        end
        if row.defaultTargetRelation == REL.FRIEND and t.side == "enemy" and byMod then
            violate("wrong side", "%s aimed %s at enemy %s", actor.name, row.Name, t.name)
        end
        -- A single heal on an ally already healed this round, and above every
        -- heal line the doc has (65% is the highest), is an overheal.
        if spec.heal and t.side == "ally" and byMod and (not t.dead) and (not isAll) then
            if B.roundHeals[t.id] and (t.hp / t.maxHp) >= 0.65 then
                violate("overheal", "%s healed %s again this round at %d%%", actor.name, t.name, math.floor(t.hp * 100 / t.maxHp))
            end
            B.roundHeals[t.id] = true
        end
        if eff == EFF.CURE and t.side == "ally" and byMod then
            local any = false
            for st in pairs(t.statuses) do if BAD[st] then any = true end end
            if not any then violate("empty cure", "%s cured %s with no bad status", actor.name, t.name) end
        end
    end
    -- Quality measures, not rules.
    if byMod and isItem and eff == EFF.REVIVE then
        for _, a in ipairs(living("ally")) do
            if (a.id ~= actor.id) and (not a.summon) and (not anyBad(a)) then
                for _, id in ipairs(a.skillIds or {}) do
                    local r = Sim.skills[id]
                    if r and r.skillEffectType == EFF.REVIVE and r.skillAttrType ~= ATTR.ITEM
                        and r.skillAttrType ~= ATTR.LB and (r.Cost or 0) <= a.mp and not sealed(a, r) then
                        B.stats.pdWhileRaise = (B.stats.pdWhileRaise or 0) + 1
                        break
                    end
                end
            end
        end
    end
    if byMod and (not isItem) and row.defaultTargetRelation == REL.ENEMY and (row.magnification or 0) > 0
        and row.skillAttrType ~= ATTR.LB and row.skillAttrType ~= ATTR.SUMMON and B.phase == 0 then
        local could = false
        for _, id in ipairs(actor.skillIds or {}) do
            local r = Sim.skills[id]
            if r and r.defaultTargetRelation == REL.ENEMY and (r.magnification or 0) > 0 and r.skillAttrType ~= ATTR.LB
                and r.skillAttrType ~= ATTR.SUMMON and (r.Cost or 0) <= actor.mp and not sealed(actor, r) then
                for _, f in ipairs(living("enemy")) do
                    if select(1, factors(r, f)) >= 3 then could = true end
                end
            end
        end
        if could then
            B.stats.weakChance = (B.stats.weakChance or 0) + 1
            local t = unitById(targets[1] or -1)
            if t and t.side == "enemy" and select(1, factors(row, t)) >= 3 then
                B.stats.weakUsed = (B.stats.weakUsed or 0) + 1
            end
        end
    end
    -- Take it Easy: the planner sends the free basic Attack at an enemy, and nothing else.
    if B.easy and byMod then
        local t = unitById(targets[1] or -1)
        if isItem or row.skillAttrType ~= ATTR.FIGHT or (row.Cost or 0) > 0 or row.defaultTargetRelation ~= REL.ENEMY
            or (t and t.side ~= "enemy") then
            violate("easy mode", "%s sent %s in Take it Easy", actor.name, isItem and item.Name or row.Name)
        end
    end
    if row.skillAttrType == ATTR.ESCAPE and byMod then
        B.stats.escapes = (B.stats.escapes or 0) + 1
        if (B.round - (B.lastProgress or 0)) < 4 then
            violate("early escape", "%s escaped while enemies were still losing HP", actor.name)
        end
    end
    if spec.mp and isItem and byMod then
        B.roundEthers = B.roundEthers + 1
        B.stats.ethers = B.stats.ethers + 1
        if B.roundEthers > 1 then violate("second ether", "%s drank a second Ether this round", actor.name) end
    end
    if (spec.provoke or eff == EFF.COVER) and byMod then
        B.stats.draws = B.stats.draws + 1
        -- One draw at a time: each one pulls the hits onto the caster.
        -- Counted in passes of the party, as the planner counts its rounds.
        if B.lastDraw and ((B.passes or 0) - B.lastDraw) < 2 then
            violate("stacked draw", "%s cast %s while another draw was still up", actor.name, row.Name)
        end
        B.lastDraw = B.passes or 0
        local mine = healPower(actor)
        local best = 0
        for _, a in ipairs(living("ally")) do
            if a.id ~= actor.id and not a.summon then best = math.max(best, healPower(a)) end
        end
        if mine > 0 and mine > best then violate("healer draws", "%s, the healer, cast %s", actor.name, row.Name) end
        local healerLow = false
        for _, a in ipairs(living("ally")) do
            if not a.summon and healPower(a) > 0 and (a.hp / a.maxHp) < 0.65 then healerLow = true end
        end
        if (not fieldThreat()) and (not healerLow) then
            violate("calm draw", "%s cast %s on a calm field", actor.name, row.Name)
        end
    end
    return true
end

-- obj is a CPP_BtlCmdDecideDelegateVal. byMod is true when the planner sent it.
function Sim.onDecide(obj, byMod)
    fireHooks("/Script/mucha.CPP_BtlDelEventCmd:OnExecuteDecideCommand", { get = function() return obj end })
    local d = obj.cmdDecideDataList[1]
    if not d then return end
    local actor = unitById(d.actionUnitUniqueId)
    if not actor then return end
    local isItem = d.isUseItem and true or false
    local item, row = nil, nil
    if isItem then
        item = Sim.items[d.actionId]
        row = item and item.skill
    else
        row = Sim.skills[d.actionId]
    end
    if not row then
        if byMod then violate("illegal", "%s sent unknown action %s", actor.name, tostring(d.actionId)) end
        if B.menu then B.menu.done = true end
        return
    end
    local targets = {}
    for i = 1, #d.targetUnitUniqueIdList do targets[#targets + 1] = d.targetUnitUniqueIdList[i] end
    B.stats.commands = B.stats.commands + 1
    if byMod then B.stats.modCommands = B.stats.modCommands + 1 end
    local ok = check(actor, row, targets, d.IsAll, isItem, item, byMod)
    if ok then
        if isItem then B.bag[item.ID] = B.bag[item.ID] - 1 B.stats.items[item.Name] = (B.stats.items[item.Name] or 0) + 1 end
        resolve(actor, row, targets, d.IsAll, isItem, item)
        -- The planner's clock, read after the command lands: an ally whose
        -- status takes the turn is not waited on, unless it already went.
        if B.phase ~= 2 and actor.side == "ally" and not actor.summon then
            local actors, went = 0, 0
            for _, a in ipairs(living("ally")) do
                if (not a.summon) and ((not anyBad(a)) or B.passActed[a.id]) then
                    actors = actors + 1
                    if B.passActed[a.id] then went = went + 1 end
                end
            end
            B.passDone = (actors > 0) and (went >= actors)
            if B.passDone then B.passes = (B.passes or 0) + 1 end
        end
        if row.skillAttrType == ATTR.FINISH and byMod then B.stats.finishByMod = B.stats.finishByMod + 1 end
        if row.skillEffectType == EFF.CURE then B.stats.cures = B.stats.cures + 1 end
        if row.sim.heal and not isItem then B.stats.heals = B.stats.heals + 1 end
    end
    if B.menu then B.menu.done = true end
end

-- A command the sim makes itself: the player on the wheel, the game for a
-- confused ally, or the baseline policy.
local function sendAs(actor, row, targets, isAll, isItem, item)
    local obj = newDecide()
    obj.cmdDecideDataList[1] = { actionId = isItem and item.ID or row.ID, actionUnitUniqueId = actor.id }
    local d = obj.cmdDecideDataList[1]
    d.isUseItem = isItem and true or false
    d.IsAll = isAll and true or false
    for i, t in ipairs(targets) do d.targetUnitUniqueIdList[i] = t end
    Sim.onDecide(obj, false)
end

--------------------------------------------------------------------------------
-- Turns
--------------------------------------------------------------------------------

local function enemyTurn(foe)
    foe.turns = foe.turns + 1
    -- A slowed enemy loses every other turn.
    if foe.statuses[ST.SLOW] then
        foe.statuses[ST.SLOW] = foe.statuses[ST.SLOW] - 1
        if foe.statuses[ST.SLOW] <= 0 then foe.statuses[ST.SLOW] = nil end
        if foe.turns % 2 == 0 then
            event("%s lost the turn (slow)", foe.name)
            return
        end
    end
    if foe.statuses[ST.BREAK] then
        foe.brokenFor = foe.brokenFor - 1
        if foe.brokenFor <= 0 then
            foe.statuses[ST.BREAK] = nil
            foe.poured = 0
            event("%s recovered from the break", foe.name)
        end
        return
    end
    local allies = {}
    for _, a in ipairs(living("ally")) do if not a.summon then allies[#allies + 1] = a end end
    if #allies == 0 then return end
    local c = foe.card
    local atk = foe.atk
    if foe.debuffed and foe.debuffed.attack then atk = atk * 0.75 end
    if c and c.danger and c.danger[1] and (foe.turns % 3 == 0) then
        event("%s used %s", foe.name, c.danger[1])
        for _, a in ipairs(allies) do
            local dmg = atk * 1.8
            if a.statuses[ST.PROTECT] or a.statuses[ST.SHELL] then dmg = dmg * 0.6 end
            hurt(a, dmg, foe.name .. " " .. c.danger[1])
        end
        return
    end
    -- Single hit. Provoke pulls it, Cover takes it.
    local target = allies[math.random(#allies)]
    if B.focusHealer then
        for _, a in ipairs(allies) do if a.healer and math.random() < 0.6 then target = a end end
    end
    if B.provoke and unitById(B.provoke.by) and not unitById(B.provoke.by).dead then
        target = unitById(B.provoke.by)
    end
    local cover = target.coveredBy or B.multiCover
    if cover and cover.by ~= target.id then
        local c2 = unitById(cover.by)
        if c2 and not c2.dead then target = c2 end
    end
    local dmg = atk * (0.85 + math.random() * 0.3)
    if target.statuses[ST.PROTECT] then dmg = dmg * 0.7 end
    hurt(target, dmg, foe.name)
    if (not target.dead) and foe.statusChance > 0 and math.random() < foe.statusChance then
        local list = foe.statusList or { ST.POISON }
        local st = list[math.random(#list)]
        applyStatus(target, st, (st == ST.DOOM) and 4 or 3)
        event("%s put status %d on %s", foe.name, st, target.name)
    end
end

local function tickAlly(u)
    u.defending = false
    if u.statuses[ST.POISON] then hurt(u, u.maxHp * 0.06, "poison") end
    if u.statuses[ST.DOOM] then
        u.statuses[ST.DOOM] = u.statuses[ST.DOOM] - 1
        if u.statuses[ST.DOOM] <= 0 then hurt(u, u.hp + 1, "doom") end
    end
    for st, n in pairs(u.statuses) do
        if st ~= ST.POISON and st ~= ST.DOOM and st ~= ST.BREAK and st ~= ST.PETRIFY and st ~= ST.BERSERK and type(n) == "number" then
            u.statuses[st] = n - 1
            if u.statuses[st] <= 0 then u.statuses[st] = nil end
        end
    end
    if u.coveredBy then
        u.coveredBy.left = u.coveredBy.left - 1
        if u.coveredBy.left <= 0 then u.coveredBy = nil end
    end
    if B.multiCover and B.multiCover.by == u.id then
        B.multiCover.left = B.multiCover.left - 1
        if B.multiCover.left <= 0 then B.multiCover = nil end
    end
    if B.provoke and B.provoke.by == u.id then
        B.provoke.left = B.provoke.left - 1
        if B.provoke.left <= 0 then B.provoke = nil end
    end
end

local function anyStatus(u, set)
    for st in pairs(u.statuses) do if set[st] then return st end end
    return nil
end

-- Opens the command menu for one ally and waits for the planner.
local function menuTurn(u, phase, policy)
    SUBSYSTEM.CurrentActionUnitUniqueId = u.id
    SUBSYSTEM.BtlPhaseType = phase
    B.phase = phase
    B.menu = { uid = u.id, done = false }
    if policy then
        policy(u, phase)
    else
        fireHooks("/Script/mucha.CPP_MuchaEventDispatcher:ExecuteEvent",
            { get = function() return { TagName = FNameOf("Delegate.Battle.Cmd.List.Begin") } end })
        Sim.advance(1500, function() return B.menu.done end)
        if not B.menu.done then
            B.stats.stalls = B.stats.stalls + 1
            violate("stall", "no command for %s (p%d)", u.name, phase)
        end
        fireHooks("/Script/mucha.CPP_MuchaEventDispatcher:ExecuteEvent",
            { get = function() return { TagName = FNameOf("Delegate.Battle.Cmd.List.End") } end })
    end
    B.menu = nil
    Sim.advance(100)
end

local function finisherOf(u)
    for _, id in ipairs(u.skillIds or {}) do
        local s = Sim.skills[id]
        if s and s.skillAttrType == ATTR.FINISH then return s end
    end
    return nil
end

local function gameAttack(u, pool)
    local attack = Sim.skillByName["attack"]
    local t = pool[math.random(#pool)]
    B.stats.gameCommands = B.stats.gameCommands + 1
    SUBSYSTEM.CurrentActionUnitUniqueId = u.id
    sendAs(u, attack, { t.id }, false)
end

local function allBroken()
    local foes = living("enemy")
    if #foes == 0 then return false end
    for _, f in ipairs(foes) do if not f.statuses[ST.BREAK] then return false end end
    return true
end

local function over()
    local a, e = 0, 0
    for _, u in pairs(B.units) do
        if not u.dead and not u.gone then
            if u.side == "ally" and not u.summon then a = a + 1 end
            if u.side == "enemy" then e = e + 1 end
        end
    end
    if B.fled then return "fled" end
    if e == 0 then return "win" end
    if a == 0 then return "loss" end
    return nil
end

local function bonusPhase(policy)
    B.stats.sweeps = (B.stats.sweeps or 0) + 1
    B.bonusNext = false
    event("sweep: every enemy broken")
    for _, u in ipairs(living("ally")) do
        if over() then return end
        if not u.summon and not anyStatus(u, NO_TURN) and not anyStatus(u, GAME_PLAYS) then
            menuTurn(u, 1, policy)
        end
    end
    if over() then return end
    -- The Resonance wheel.
    B.phase = 2
    SUBSYSTEM.BtlPhaseType = 2
    B.stats.finish = B.stats.finish + 1
    B.menu = { uid = -1, done = false }
    if not policy then
        Sim.advance(2500, function() return B.menu.done end)
    end
    if not B.menu.done then
        -- The player picks on the wheel.
        local who, fin = nil, nil
        for _, u in ipairs(living("ally")) do
            if not u.summon then
                local f = finisherOf(u)
                if f and not fin then who, fin = u, f end
            end
        end
        if fin then
            B.stats.playerCommands = B.stats.playerCommands + 1
            local foes = living("enemy")
            if #foes > 0 then sendAs(who, fin, { foes[1].id }, true) end
        else
            for _, f in ipairs(living("enemy")) do hurt(f, f.maxHp * 0.25, "resonance") end
        end
    end
    B.menu = nil
    B.phase = 0
    SUBSYSTEM.BtlPhaseType = 0
    for _, f in ipairs(living("enemy")) do
        f.statuses[ST.BREAK] = nil
        f.poured = 0
        f.brokenFor = 0
    end
    Sim.advance(800)
end

-- Plays the battle to the end. policy is nil for the planner, or a function
-- for the baseline. Returns "win", "loss", or "timeout".
function Sim.play(maxRounds, policy)
    Sim.advance(800)
    maxRounds = maxRounds or 40
    for round = 1, maxRounds do
        B.round = round
        local order = {}
        for _, u in pairs(B.units) do
            if not u.dead and not u.gone then order[#order + 1] = u end
        end
        for _, u in ipairs(order) do u.init = (u.spd or 10) + math.random() * 6 end
        table.sort(order, function(a, b) return a.init > b.init end)
        for _, u in ipairs(order) do
            local done = over()
            if done then
                -- The units stay on screen a moment after the last blow.
                Sim.advance(1500)
                B.active = false
                Sim.advance(2000)
                return done
            end
            if (not u.dead) and (not u.gone) then
                if u.side == "enemy" then
                    enemyTurn(u)
                elseif u.summon then
                    for _, f in ipairs(living("enemy")) do
                        local row = u.row
                        strike(u, row, f, 0.8)
                    end
                    u.life = u.life - 1
                    if u.life <= 0 then
                        u.gone = true
                        u.dead = true
                        event("%s left", u.name)
                    end
                else
                    tickAlly(u)
                    if not u.dead then
                        local slow = u.statuses[ST.SLOW] and (round % 2 == 0)
                        if anyStatus(u, NO_TURN) or slow then
                            if slow and not anyStatus(u, NO_TURN) then B.stats.slowLost = (B.stats.slowLost or 0) + 1 end
                            event("%s lost the turn", u.name)
                        elseif anyStatus(u, GAME_PLAYS) then
                            local st = anyStatus(u, GAME_PLAYS)
                            local pool = {}
                            if st == ST.BERSERK then pool = living("enemy")
                            elseif st == ST.CHARM then
                                for _, a in ipairs(living("ally")) do if not a.summon then pool[#pool + 1] = a end end
                            else
                                for _, a in pairs(B.units) do if not a.dead and not a.gone and not a.summon then pool[#pool + 1] = a end end
                            end
                            if #pool > 0 then gameAttack(u, pool) end
                        else
                            local bonus = B.bonusNext and 1 or 0
                            B.bonusNext = false
                            if bonus == 1 then B.stats.bonus = B.stats.bonus + 1 end
                            menuTurn(u, bonus, policy)
                            -- A hasted ally acts again every other round.
                            if u.statuses[ST.HASTE] and (round % 2 == 1) and (not u.dead) and (not over())
                                and not anyStatus(u, NO_TURN) and not anyStatus(u, GAME_PLAYS) then
                                B.stats.hasteTurns = (B.stats.hasteTurns or 0) + 1
                                menuTurn(u, 0, policy)
                            end
                        end
                    end
                end
            end
            if allBroken() and not over() then bonusPhase(policy) end
        end
    end
    B.active = false
    Sim.advance(2000)
    return over() or "timeout"
end

-- Carries the party state out of a battle, for the next fight in a session.
function Sim.partyAfter()
    local out = {}
    for id = 0, 3 do
        local u = B.units[id]
        if u then
            local st = {}
            for k, v in pairs(u.statuses) do if BAD[k] and k ~= ST.DOOM then st[k] = v end end
            out[#out + 1] = { hp = u.hp, mp = u.mp, dead = u.dead, lb = u.lb, statuses = st }
        end
    end
    return out
end

-- The baseline the doc asks for: attack with the strongest payable skill.
function Sim.baseline(u, phase)
    local best, bestP = nil, -1
    for _, id in ipairs(u.skillIds or {}) do
        local s = Sim.skills[id]
        if s and s.defaultTargetRelation == REL.ENEMY and s.skillAttrType ~= ATTR.SUMMON
            and s.skillAttrType ~= ATTR.FINISH and s.skillAttrType ~= ATTR.LB
            and (s.magnification or 0) > 0 and (s.Cost or 0) <= u.mp and not sealed(u, s) then
            if s.magnification > bestP then best, bestP = s, s.magnification end
        end
    end
    best = best or Sim.skillByName["attack"]
    local foes = living("enemy")
    if #foes == 0 then return end
    local isAll = (best.TargetType == TGT.ALL or best.TargetType == TGT.GROUP)
    local ids = {}
    if isAll then for _, f in ipairs(foes) do ids[#ids + 1] = f.id end else ids = { foes[math.random(#foes)].id } end
    sendAs(u, best, ids, isAll)
end

return Sim

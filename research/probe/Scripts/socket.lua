-- Planner 2, Phase 2: the socket. The only file that talks to the game.
--
-- observe() returns a Snapshot: a plain Lua table with no game objects in it.
-- Every value comes from a read v0.1.36 already makes in the game, or one the
-- probe confirmed (research/game-surface.md). Each section says where it
-- came from in `src`.
--
-- The socket never reaches for UE4SS globals itself. new(env) takes:
--   env.FindFirstOf, env.FindAllOf, env.StaticFindObject
-- so the same code runs in the game, in the probe, and in tests against a
-- fake game. Hook-fed values (the Timeline) are pushed in with
-- socket:noteTimeline(); hook parameters are read inside the hook only.
--
-- send() is not here yet: v0.1.36 sends; planner 2 runs in shadow first.

local M = {}

-- eUnitParameterType (mucha_enums.hpp)
local P_HP, P_MP, P_BREAK, P_LB, P_AGI = 1, 2, 3, 4, 9
local REL_FRIEND, REL_ENEMY = 1, 2

local function unwrap(v)
    if type(v) == "userdata" or (type(v) == "table" and type(rawget(v, "get")) == "function") then
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

local function valid(o)
    if type(o) ~= "userdata" and type(o) ~= "table" then return false end
    local ok, v = pcall(function() return o:IsValid() end)
    return ok and v == true
end

-- Calls fn(outTable) and returns everything it put in the out-param table
-- or returned, unwrapped. The same helper v0.1.36 uses.
local function fill(fn)
    local t = {}
    local ok, ret = pcall(fn, t)
    if not ok then return nil end
    local res = {}
    for _, v in pairs(t) do v = unwrap(v); if v ~= nil then res[#res + 1] = v end end
    if type(ret) == "table" then
        for _, v in pairs(ret) do v = unwrap(v); if v ~= nil then res[#res + 1] = v end end
    elseif ret ~= nil then
        ret = unwrap(ret); if ret ~= nil then res[#res + 1] = ret end
    end
    return res
end

local function idOf(v)
    local n = num(v)
    if n then return n end
    v = unwrap(v)
    if type(v) ~= "userdata" and type(v) ~= "table" then return nil end
    for _, f in ipairs({ "SkillId", "skillId", "ID", "Id", "id" }) do
        local ok, x = pcall(function() return v[f] end)
        if ok and num(x) then return num(x) end
    end
    return nil
end

function M.new(env)
    local S = { env = env, timeline = nil, libs = {}, itemIds = env.itemIds }

    local function lib(path)
        local o = S.libs[path]
        if not valid(o) then
            local ok, x = pcall(function() return env.StaticFindObject(path) end)
            o = ok and x or nil
            S.libs[path] = o
        end
        return valid(o) and o or nil
    end
    local function battle() return lib("/Script/mucha.Default__CPP_BFL_Battle") end
    local function skills() return lib("/Script/mucha.Default__CPP_BFL_Skill") end
    local function items() return lib("/Script/mucha.Default__CPP_BFL_Item") end
    local function first(class)
        local ok, o = pcall(function() return env.FindFirstOf(class) end)
        return (ok and valid(o)) and o or nil
    end

    local function unitIdOf(u)
        u = unwrap(u)
        if not valid(u) then return nil end
        local ok, n = pcall(function() return num(u.m_UniqueId) end)
        if ok and n then return n end
        ok, n = pcall(function() return num(u:GetUniqueId()) end)
        if ok and n then return n end
        return nil
    end

    local function paramOf(uid, aliveOnly)
        local b = battle()
        if not b then return nil end
        local ok, p = pcall(function() return b:GetBattleUnitParameter(uid, aliveOnly) end)
        if ok and valid(p) then return p end
        return nil
    end

    local function stat(p, kind, maximum)
        local ok, v = pcall(function()
            if maximum then return p:GetMaxParameterByType(kind) end
            return p:GetParameterByType(kind, false)
        end)
        return ok and num(v) or nil
    end

    -- GetBattleUnitListByRelation(out units, relation, isAliveOnly,
    -- bIncludeUnselectable): ACPP_BtlUnit objects (C++ header dump).
    local function unitIds(relation)
        local b = battle()
        if not b then return {} end
        local ids, seen = {}, {}
        local list = fill(function(t) b:GetBattleUnitListByRelation(t, relation, false, true) end) or {}
        for _, v in ipairs(list) do
            local n = num(v) or unitIdOf(v)
            if n and not seen[n] then seen[n] = true; ids[#ids + 1] = n end
        end
        return ids
    end

    local function statuses(uid)
        local set = {}
        local b = battle()
        if not b then return set end
        for _, v in ipairs(fill(function(t) b:GetStatusConditionList(t, uid) end) or {}) do
            local n = num(v)
            if n then set[n] = true end
        end
        return set
    end

    local function unit(uid, side)
        local p = paramOf(uid, false)
        local u = { uid = uid, side = side, statuses = statuses(uid) }
        if not p then u.missing = true; return u end
        local ok, id = pcall(function() return num(p:GetUnitId()) end)
        u.unitId = ok and id or nil
        local okN, nm = pcall(function() return p:GetDuplicationUnitName() end)
        if okN and nm ~= nil then
            if type(nm) ~= "string" then pcall(function() nm = nm:ToString() end) end
            if type(nm) == "string" then u.name = nm end
        end
        u.hp, u.maxHp = stat(p, P_HP), stat(p, P_HP, true)
        u.mp, u.maxMp = stat(p, P_MP), stat(p, P_MP, true)
        u.gauge, u.maxGauge = stat(p, P_BREAK), stat(p, P_BREAK, true)
        u.lb, u.maxLb = stat(p, P_LB), stat(p, P_LB, true)
        u.agi = stat(p, P_AGI)
        u.alive = (u.hp or 0) > 0
        u.broken = u.statuses[89] == true or ((u.gauge or 1) <= 0 and side == "foe")
        return u
    end

    -- The skill ids on a unit's bar, from every list v0.1.36 tries.
    local function bar(uid)
        local found, order = {}, {}
        local function add(v)
            local id = idOf(v)
            if id and id > 0 and not found[id] then found[id] = true; order[#order + 1] = id end
        end
        local p = paramOf(uid, true) or paramOf(uid, false)
        local b, sk = battle(), skills()
        local unitId = nil
        if p then
            local ok, v = pcall(function() return num(p:GetUnitId()) end)
            unitId = ok and v or nil
        end
        local probes = {}
        if p then
            probes[#probes + 1] = function(t) p:GetActiveSkillListWithVision(t) end
            probes[#probes + 1] = function(t) p:GetActiveSkillList(t) end
        end
        if b then
            probes[#probes + 1] = function(t) b:GetActiveSkillListWithVision(t, uid) end
            probes[#probes + 1] = function(t) b:GetEquipSkills(t, unitId or uid) end
        end
        if sk then probes[#probes + 1] = function(t) sk:GetEquipSkills(t, unitId or uid) end end
        for _, probe in ipairs(probes) do
            for _, v in ipairs(fill(probe) or {}) do add(v) end
        end
        local out = {}
        for _, id in ipairs(order) do
            local e = { id = id }
            if b then
                -- CanUnitActivateSkill(unit, actionId, IsItem, hierarchySkills,
                -- IsAll): five arguments (C++ header dump). Two returned nothing.
                local ok, v = pcall(function() return b:CanUnitActivateSkill(uid, id, false, {}, false) end)
                if ok and type(v) == "boolean" then e.canActivate = v end
                -- IsEnableCommand answered false for every skill at menu time
                -- (probe v1.1), so it is logged only, never used as a rule.
                ok, v = pcall(function() return b:IsEnableCommand(uid, id) end)
                if ok and type(v) == "boolean" then e.enabled = v end
            end
            if sk and unitId then
                local ok, v = pcall(function() return sk:GetSkillCost(id, unitId, false) end)
                if ok and num(v) then e.cost = num(v) end
            end
            out[#out + 1] = e
        end
        return out
    end

    -- Consumables and their counts. v0.8 read GetConsumableItemList into a Lua
    -- table and got nothing in game. Now: ask the count of every consumable
    -- id the caller knows (S.itemIds, from data.lua's items), plus any id the
    -- game's lists hand back, with the count calls v0.1.36 uses.
    local function bag()
        local out = {}
        local b, it = battle(), items()
        local ids = {}
        for _, id in ipairs(S.itemIds or {}) do ids[id] = true end
        local function take(list)
            for _, v in ipairs(list or {}) do
                local id = idOf(v)
                if id and id > 0 then ids[id] = true end
            end
        end
        if b then take(fill(function(t) b:GetConsumableItemList(t) end)) end
        if it then
            take(fill(function(t) it:GetConsumableItemList(t) end))
            take(fill(function(t) it:GetInventoryItemIdListByConsumableType(t, 1) end))
        end
        if not it then return out end
        for id in pairs(ids) do
            local ok, v = pcall(function() return it:GetInventoryItemNum(id) end)
            local count = ok and num(v) or nil
            if count == nil then
                ok, v = pcall(function() return it:GetConsumableItemNum(id) end)
                count = ok and num(v) or nil
            end
            if count and count > 0 then out[id] = count end
        end
        return out
    end

    -- The last skill's per-hit records (UCPP_BtlSkill.m_DamageVariationDataList).
    local HIT = { "VariationType", "VariationValue", "beforeVariationValue", "afterVariationValue",
                  "breakDamageValue", "beforeBreakPoint", "afterBreakPoint", "hitNum", "resistance",
                  "DamageType", "damageMultiplier", "SkillId", "addEffectId", "variationParameter" }
    local HITB = { "isCritical", "isMiss", "isDefence", "isVeilDefence", "isTriggeredBreak", "isOnBreak",
                   "isInstantDeath", "IsReprieveActivated" }
    local function hits()
        local vm = first("CPP_BtlVoiceManager")
        if not vm then return nil end
        local ok, skill = pcall(function() return unwrap(vm.m_pSkillObj) end)
        if not (ok and valid(skill)) then return nil end
        local out = {}
        pcall(function()
            skill.m_DamageVariationDataList:ForEach(function(i, e)
                if i > 64 then return true end
                local d = unwrap(e)
                if not d then return end
                local h = { from = unitIdOf(d.pActionUnit), to = unitIdOf(d.pTargetUnit) }
                pcall(function() h.lb = num(d.LimitBurstPoint) end)
                local okU, u = pcall(function() return d.unitParameterVariationData end)
                if okU and u then
                    for _, f in ipairs(HIT) do pcall(function() h[f] = num(u[f]) end) end
                    for _, f in ipairs(HITB) do
                        pcall(function() local v = unwrap(u[f]); if v == true then h[f] = true end end)
                    end
                    local el = {}
                    pcall(function() u.elementList:ForEach(function(_, x) el[#el + 1] = num(x) end) end)
                    h.elements = el
                end
                out[#out + 1] = h
            end)
        end)
        return out
    end

    local function risk()
        local vm = first("CPP_VM_BtlTimeLine")
        if not vm then return nil end
        local ids = {}
        pcall(function() vm.RiskUnitUniqueIdList:ForEach(function(_, x) ids[#ids + 1] = num(x) end) end)
        return ids
    end

    -- Called from the HandleUpdateTimeline hook, with the hook's own value,
    -- inside the hook. Copies the id lists out; keeps nothing from the game.
    function S:noteTimeline(delval)
        local v = unwrap(delval)
        local function ids(arr)
            local out = {}
            pcall(function() arr:ForEach(function(_, x) out[#out + 1] = num(x) end) end)
            return out
        end
        local okA, cur = pcall(function() return ids(v.currentTimelines) end)
        local okB, nxt = pcall(function() return ids(v.nextTimelines) end)
        local okC, ext = pcall(function() return ids(v.additionalTurnTimelines) end)
        self.timeline = { current = okA and cur or {}, next = okB and nxt or {}, extra = okC and ext or {} }
    end

    function S:observe()
        local snap = { src = {} }
        local ss = first("CPP_UI_BattleSubsystem")
        snap.actor = ss and num(ss.CurrentActionUnitUniqueId) or -1
        snap.phase = ss and num(ss.BtlPhaseType) or 0
        local b = battle()
        if b then
            local ok, v = pcall(function() return b:IsBossBattle() end)
            snap.boss = ok and v == true
            ok, v = pcall(function() return b:IsFinishPhase() end)
            snap.finish = ok and v == true
        end
        snap.party, snap.foes, snap.units = {}, {}, {}
        for _, id in ipairs(unitIds(REL_FRIEND)) do
            local u = unit(id, "ally")
            snap.party[#snap.party + 1] = u
            snap.units[id] = u
        end
        for _, id in ipairs(unitIds(REL_ENEMY)) do
            local u = unit(id, "foe")
            snap.foes[#snap.foes + 1] = u
            snap.units[id] = u
        end
        -- Fallen allies: the living list leaves them out. Every unit param,
        -- by side (GetAllBattleUnitPararmeterList; ids in the sim, params in
        -- the game).
        snap.dead = {}
        if b then
            local seen = {}
            for _, u in ipairs(snap.party) do seen[u.uid] = true end
            for _, v in ipairs(fill(function(t) b:GetAllBattleUnitPararmeterList(t, false) end) or {}) do
                local id = num(v)
                local p = nil
                if id then p = paramOf(id, false)
                else
                    p = unwrap(v)
                    local okU, uid = pcall(function() return num(p:GetUniqueId()) end)
                    id = okU and uid or nil
                end
                if id and p and not seen[id] then
                    local okR, rel = pcall(function() return num(p:GetRelation()) end)
                    if okR and rel == REL_FRIEND then
                        local u = unit(id, "ally")
                        if not u.alive then snap.dead[#snap.dead + 1] = u; snap.units[id] = u end
                    end
                end
            end
        end
        snap.src.units = "read"
        if snap.units[snap.actor] then snap.bar = bar(snap.actor); snap.src.bar = "read" end
        snap.bag = bag(); snap.src.bag = "read"
        snap.bagNames = {}
        local it = items()
        if it then
            for id in pairs(snap.bag) do
                local okN, nm = pcall(function() return it:GetItemName(id) end)
                if okN and nm ~= nil then
                    if type(nm) ~= "string" then pcall(function() nm = nm:ToString() end) end
                    if type(nm) == "string" then snap.bagNames[id] = nm end
                end
            end
        end
        snap.hits = hits(); snap.src.hits = snap.hits and "read" or "none"
        snap.risk = risk(); snap.src.risk = snap.risk and "read" or "none"
        snap.timeline = self.timeline; snap.src.timeline = self.timeline and "hook" or "none"
        return snap
    end

    -- Send one command the way v0.1.x does for a skill it has no learned
    -- template for (Scripts/main.lua send()): a CPP_BtlCmdDecideDelegateVal
    -- through the dispatcher's Delegate.Battle.Cmd.Decide.
    --   cmd = { actor, id, targets = {uid...}, isAll, isItem, phase }
    function S:send(cmd)
        local okC, cls = pcall(function() return env.StaticFindObject("/Script/mucha.CPP_BtlCmdDecideDelegateVal") end)
        local disp = first("CPP_MuchaEventDispatcher")
        if not (okC and valid(cls) and disp and env.StaticConstructObject) then return false, "no command class" end
        local commandId = cmd.id
        local b = battle()
        if b and not cmd.isItem then
            local ok, enabled = pcall(function() return b:IsEnableCommand(cmd.actor, cmd.id) end)
            if ok and enabled == false then commandId = -1 end
        end
        local okO, obj = pcall(function() return env.StaticConstructObject(cls, disp) end)
        if not (okO and obj) then return false, "construct failed" end
        local okF, err = pcall(function()
            obj.CmdType = cmd.phase or 0
            obj.isNotConsume = false
            obj.doCalcOrder = true
            obj.CommandId = commandId
            obj.cmdDecideDataList[1] = { actionId = cmd.id, actionUnitUniqueId = cmd.actor }
            local d = obj.cmdDecideDataList[1]
            d.actionId = cmd.id
            d.actionUnitUniqueId = cmd.actor
            d.isUseItem = cmd.isItem and true or false
            d.IsAll = cmd.isAll and true or false
            d.ParentActionKey.Category = 1
            d.ParentActionKey.ID = cmd.id
            for i, tid in ipairs(cmd.targets or {}) do d.targetUnitUniqueIdList[i] = tid end
            obj.actionKeys[1] = { Category = 1, ID = cmd.id }
            obj.actionKeys[1].Category = 1
            obj.actionKeys[1].ID = cmd.id
        end)
        if not okF then return false, "fill failed: " .. tostring(err) end
        local okS, errS = pcall(function()
            disp:ExecuteEvent({ TagName = env.FName("Delegate.Battle.Cmd.Decide") }, obj)
        end)
        if not okS then return false, "send failed: " .. tostring(errS) end
        return true
    end

    -- One log line for a Snapshot.
    function M.describe(snap)
        local parts = { string.format("actor %s phase %s boss %s finish %s", tostring(snap.actor),
            tostring(snap.phase), tostring(snap.boss), tostring(snap.finish)) }
        local function us(list)
            local o = {}
            for _, u in ipairs(list) do
                o[#o + 1] = string.format("%d:%s/%s g%s/%s", u.uid, tostring(u.hp), tostring(u.maxHp),
                    tostring(u.gauge), tostring(u.maxGauge))
            end
            return table.concat(o, " ")
        end
        parts[#parts + 1] = "party " .. us(snap.party)
        parts[#parts + 1] = "foes " .. us(snap.foes)
        local nb, nbag = 0, 0
        for _ in pairs(snap.bar or {}) do nb = nb + 1 end
        for _ in pairs(snap.bag or {}) do nbag = nbag + 1 end
        parts[#parts + 1] = string.format("bar %d bag %d hits %d risk [%s]", nb, nbag,
            snap.hits and #snap.hits or -1, table.concat(snap.risk or {}, ","))
        if snap.timeline then
            parts[#parts + 1] = "order [" .. table.concat(snap.timeline.current, ",") .. "] extra ["
                .. table.concat(snap.timeline.extra, ",") .. "]"
        end
        return table.concat(parts, " | ")
    end

    return S
end

return M

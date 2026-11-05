-- FFRProbe. Research only, not shipped. Read-only: it never sends a command,
-- never writes a game value, and never calls a game function that is not a
-- getter the main mod already calls.
--
-- What it does in a fight:
--   * At every decide (ally or enemy command) and every ally menu, it walks
--     the reflected properties of every battle unit, its parameter object,
--     the battle subsystem, and any class named in watch.lua, and logs the
--     values that changed since the last walk. The stagger gauge and the
--     Timeline should show up as values that move with hits and turns.
--   * It logs HP and MP of every unit at each decide, with the command id,
--     so enemy damage per action can be read off (research R3).
--   * It logs every event tag the game's dispatcher fires, once per tag
--     per fight plus a count at the end.
-- F7 writes probe_schema.txt: every property and function, with parameters,
-- of the live battle objects and the CPP_BFL_* libraries.
--
-- Output: probe_log.txt and probe_schema.txt in this mod's folder.

local TAG = "[FFRProbe] "

local function modDir()
    local info = debug and debug.getinfo and debug.getinfo(1, "S")
    local src = ((info and info.source) or ""):gsub("^@", ""):gsub("\\", "/")
    return src:match("^(.*)/Scripts/[^/]+$") or "ue4ss/Mods/FFRProbe"
end
local DIR = modDir()

local W = { classes = {}, follow = {}, skip = {}, schemaKey = "F7", maxDepth = 3, maxArray = 16 }
do
    local ok, t = pcall(dofile, DIR .. "/Scripts/watch.lua")
    if ok and type(t) == "table" then
        for k, v in pairs(t) do W[k] = v end
    else
        print(TAG .. "watch.lua not loaded: " .. tostring(t) .. "\n")
    end
end

do
    local set = {}
    for _, n in ipairs(W.followProps or {}) do set[n] = true end
    W.followProps = set
end

-- Planner 2's socket (research/planner2/socket.lua), run as a shadow: it
-- only reads. Its Snapshot is logged at each party menu.
local Sock, SockLib = nil, nil
do
    local ok, lib = pcall(dofile, DIR .. "/Scripts/socket.lua")
    if ok and type(lib) == "table" then
        SockLib = lib
        Sock = lib.new({ FindFirstOf = FindFirstOf, FindAllOf = FindAllOf, StaticFindObject = StaticFindObject })
    end
end

-- Planner 2 in shadow: scores the open menu and logs its top three; never
-- sends. Built once data.lua's books exist (buildData).
local Shadow = { P = nil, E = nil, D = nil, L = nil, top = nil, topActor = nil,
                 fightParty = nil, seen = {}, tally = { n = 0, top1 = 0, top3 = 0, none = 0 } }

local P = { lines = {}, fight = 0, seq = 0, prev = nil, noisy = {}, streak = {},
            tags = {}, tagOrder = {}, active = false, lastWalk = 0 }

local function out(fmt, ...)
    local line = (select("#", ...) > 0) and string.format(fmt, ...) or tostring(fmt)
    local f = io.open(DIR .. "/probe_log.txt", "a")
    if f then f:write(line .. "\n"); f:close() end
end

local function say(fmt, ...)
    local line = (select("#", ...) > 0) and string.format(fmt, ...) or tostring(fmt)
    print(TAG .. line .. "\n")
end

local function clock() return os.clock() end

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

local function fname(x)
    local ok, s = pcall(function() return x:GetFName():ToString() end)
    return ok and s or "?"
end

local function valid(o)
    if type(o) ~= "userdata" and type(o) ~= "table" then return false end
    local ok, v = pcall(function() return o:IsValid() end)
    return ok and v == true
end

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

--------------------------------------------------------------------------------
-- Game reads the main mod already makes (known safe)
--------------------------------------------------------------------------------

local bfl
local function battleLib()
    if not valid(bfl) then bfl = StaticFindObject("/Script/mucha.Default__CPP_BFL_Battle") end
    return valid(bfl) and bfl or nil
end

-- An ACPP_BtlUnit's unique id: the m_UniqueId field, else GetUniqueId().
local function unitIdOf(u)
    u = unwrap(u)
    if not valid(u) then return nil end
    local ok, n = pcall(function() return num(u.m_UniqueId) end)
    if ok and n then return n end
    ok, n = pcall(function() return num(u:GetUniqueId()) end)
    if ok and n then return n end
    return nil
end

local function unitIds(relation)
    local lib = battleLib()
    if not lib then return {} end
    -- GetBattleUnitListByRelation(out units, relation, isAliveOnly,
    -- bIncludeUnselectable) returns ACPP_BtlUnit objects (C++ header dump).
    local ids, seen = {}, {}
    local list = fill(function(t) lib:GetBattleUnitListByRelation(t, relation, false, true) end) or {}
    for _, v in ipairs(list) do
        local n = num(v)
        if not n then n = unitIdOf(v) end
        if n and not seen[n] then seen[n] = true; ids[#ids + 1] = n end
    end
    return ids
end

local function paramOf(uid)
    local lib = battleLib()
    if not lib then return nil end
    local ok, p = pcall(function() return lib:GetBattleUnitParameter(uid, true) end)
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

local function breakRatio(p)
    local ok, r = pcall(function() return p:GetBreakPointRatio() end)
    return ok and num(r) or nil
end

local function subsystem()
    local ok, ss = pcall(function() return FindFirstOf("CPP_UI_BattleSubsystem") end)
    if ok and valid(ss) then return ss end
    return nil
end

--------------------------------------------------------------------------------
-- Reflection walk
--------------------------------------------------------------------------------

local NUMERIC = {
    IntProperty = true, Int8Property = true, Int16Property = true, Int64Property = true,
    UInt16Property = true, UInt32Property = true, UInt64Property = true,
    FloatProperty = true, DoubleProperty = true, ByteProperty = true, EnumProperty = true,
}

-- Own and inherited properties of a UStruct, cached by struct name.
local propCache = {}
local function propsOf(struct)
    local key = fname(struct)
    local okFull, full = pcall(function() return struct:GetFullName() end)
    if okFull and full then key = full end
    if propCache[key] then return propCache[key] end
    local list = {}
    local s, guard = struct, 0
    while s and valid(s) and guard < 32 do
        pcall(function()
            s:ForEachProperty(function(prop)
                local kind = "?"
                pcall(function() kind = prop:GetClass():GetFName():ToString() end)
                list[#list + 1] = { name = fname(prop), kind = kind, prop = prop }
            end)
        end)
        local ok, sup = pcall(function() return s:GetSuperStruct() end)
        s = ok and sup or nil
        guard = guard + 1
    end
    propCache[key] = list
    return list
end

local function classOf(o)
    local ok, c = pcall(function() return o:GetClass() end)
    if ok and valid(c) then return c end
    return nil
end

local function followClass(o)
    local c = classOf(o)
    if not c then return false end
    local ok, full = pcall(function() return c:GetFullName() end)
    full = ok and full or ""
    if full:find("/Script/mucha", 1, true) then return true end
    local n = fname(c)
    for _, pat in ipairs(W.follow) do
        if n:find(pat) then return true end
    end
    return false
end

local walkStruct

local function skipName(name)
    for _, pat in ipairs(W.skip) do
        if name:find(pat) then return true end
    end
    return false
end

-- Read one property value into flat[path]. Containers recurse.
local function readProp(container, p, path, flat, depth, seen)
    if skipName(p.name) then return end
    local ok, v = pcall(function() return container[p.name] end)
    if not ok then return end
    if NUMERIC[p.kind] then
        local n = num(v)
        if n then flat[path] = n end
    elseif p.kind == "BoolProperty" then
        v = unwrap(v)
        if type(v) == "boolean" then flat[path] = v and 1 or 0 end
    elseif p.kind == "StructProperty" and depth < W.maxDepth then
        local okS, st = pcall(function() return p.prop:GetStruct() end)
        if okS and st then walkStruct(v, st, path, flat, depth + 1, seen) end
    elseif p.kind == "ArrayProperty" and depth < W.maxDepth then
        local okI, inner = pcall(function() return p.prop:GetInner() end)
        local innerKind = "?"
        if okI and inner then pcall(function() innerKind = inner:GetClass():GetFName():ToString() end) end
        local okN, count = pcall(function() return v:GetArrayNum() end)
        if not okN or type(count) ~= "number" then return end
        flat[path .. "#"] = count
        local i = 0
        pcall(function()
            v:ForEach(function(_, e)
                i = i + 1
                if i > W.maxArray then return true end
                local ev = unwrap(e)
                local ep = path .. "[" .. i .. "]"
                if NUMERIC[innerKind] then
                    local n = num(ev)
                    if n then flat[ep] = n end
                elseif innerKind == "BoolProperty" then
                    if type(ev) == "boolean" then flat[ep] = ev and 1 or 0 end
                elseif innerKind == "StructProperty" then
                    local okS, st = pcall(function() return inner:GetStruct() end)
                    if okS and st then walkStruct(ev, st, ep, flat, depth + 1, seen) end
                end
            end)
        end)
    elseif p.kind == "ObjectProperty" and depth < W.maxDepth and W.followProps[p.name] then
        -- v0.3: links are followed only by name (watch.lua followProps).
        -- Following every link crashed the game in v0.1.
        v = unwrap(v)
        if valid(v) and not seen[v] and followClass(v) then
            seen[v] = true
            walkStruct(v, classOf(v), path, flat, depth + 1, seen)
        end
    end
end

walkStruct = function(container, struct, path, flat, depth, seen)
    if container == nil or not struct then return end
    for _, p in ipairs(propsOf(struct)) do
        readProp(container, p, path .. "." .. p.name, flat, depth, seen)
    end
end

local function walkObject(o, root, flat, seen)
    if not valid(o) then return end
    seen[o] = true
    walkStruct(o, classOf(o), root, flat, 0, seen)
end

--------------------------------------------------------------------------------
-- Snapshot and diff
--------------------------------------------------------------------------------

local function roots()
    local list = {}
    local function add(name, o) if valid(o) then list[#list + 1] = { name = name, obj = o } end end
    for _, rel in ipairs({ { 1, "ally" }, { 2, "foe" } }) do
        for _, uid in ipairs(unitIds(rel[1])) do
            add(string.format("%s%d.param", rel[2], uid), paramOf(uid))
        end
    end
    add("subsystem", subsystem())
    for _, cls in ipairs(W.classes) do
        local ok, all = pcall(function() return FindAllOf(cls) end)
        if ok and type(all) == "table" then
            for i, o in ipairs(all) do add(cls .. "#" .. i, o) end
        end
    end
    return list
end

local function snapshot()
    local flat, seen = {}, {}
    for _, r in ipairs(roots()) do
        pcall(walkObject, r.obj, r.name, flat, seen)
    end
    return flat
end

local function fmtv(v)
    if v == nil then return "nil" end
    if math.type and math.type(v) == "integer" then return tostring(v) end
    return string.format("%.4g", v)
end

-- A key that changed on six walks in a row is noise (timers, positions).
-- It is logged once as noisy and then left out.
local function diff(label)
    local now = snapshot()
    P.seq = P.seq + 1
    local prev = P.prev
    P.prev = now
    if not prev then
        local n = 0
        for _ in pairs(now) do n = n + 1 end
        out("walk %d %s: first walk, %d values", P.seq, label, n)
        return
    end
    local changes = {}
    for k, v in pairs(now) do
        local was = prev[k]
        if was ~= v then
            P.streak[k] = (P.streak[k] or 0) + 1
            if P.streak[k] == 6 and not P.noisy[k] then
                P.noisy[k] = true
                out("  noisy %s", k)
            end
            if not P.noisy[k] then changes[#changes + 1] = k end
        else
            P.streak[k] = 0
        end
    end
    for k, was in pairs(prev) do
        if now[k] == nil and not P.noisy[k] then changes[#changes + 1] = k end
    end
    table.sort(changes)
    out("walk %d %s: %d changed", P.seq, label, #changes)
    for _, k in ipairs(changes) do
        out("  %s %s -> %s", k, fmtv(prev[k]), fmtv(now[k]))
    end
end

local function vitals(label)
    local parts = {}
    for _, rel in ipairs({ { 1, "ally" }, { 2, "foe" } }) do
        for _, uid in ipairs(unitIds(rel[1])) do
            local p = paramOf(uid)
            if p then
                -- eUnitParameterType: 1 HP, 2 MP, 3 BreakPoint, 4 LimitBurstPoint, 9 Agility.
                parts[#parts + 1] = string.format("%s%d hp %s/%s mp %s bp %s/%s ratio %s lb %s agi %s", rel[2], uid,
                    fmtv(stat(p, 1, false)), fmtv(stat(p, 1, true)), fmtv(stat(p, 2, false)),
                    fmtv(stat(p, 3, false)), fmtv(stat(p, 3, true)), fmtv(breakRatio(p)),
                    fmtv(stat(p, 4, false)), fmtv(stat(p, 9, false)))
            end
        end
    end
    out("vitals %s | %s", label, table.concat(parts, " | "))
end

local function idList(arr)
    local ids = {}
    pcall(function()
        arr:ForEach(function(_, e)
            local n = num(e)
            if n then ids[#ids + 1] = tostring(n) end
        end)
    end)
    return table.concat(ids, ",")
end

-- Per-hit records of the last skill: CPP_BtlVoiceManager.m_pSkillObj
-- (UCPP_BtlSkill).m_DamageVariationDataList, each an
-- FBTL_EFFECT_UNIT_PARAMETER_VARIATION_DATA. Named fields only. Logged once
-- per distinct list. Answers R1 (stagger before/after), R3 (damage), R9
-- (elementList), R10 (resistance).
local HIT_FIELDS = {
    "variationParameter", "VariationType", "VariationValue", "beforeVariationValue",
    "afterVariationValue", "breakDamageValue", "beforeBreakPoint", "afterBreakPoint",
    "chainNum", "hitNum", "resistance", "DamageType", "damageMultiplier",
    "isCritical", "isMiss", "isDefence", "isVeilDefence", "isTriggeredBreak", "isOnBreak",
    "SkillId", "addEffectId", "isInstantDeath", "IsReprieveActivated",
}
local lastHits = nil
local function readHits(label)
    local okV, vm = pcall(function() return FindFirstOf("CPP_BtlVoiceManager") end)
    if not (okV and valid(vm)) then return end
    local okS, skill = pcall(function() return unwrap(vm.m_pSkillObj) end)
    if not (okS and valid(skill)) then return end
    local rows = {}
    pcall(function()
        skill.m_DamageVariationDataList:ForEach(function(i, e)
            if i > 32 then return true end
            local d = unwrap(e)
            if not d then return end
            local parts = {
                "from " .. tostring(unitIdOf(d.pActionUnit)),
                "to " .. tostring(unitIdOf(d.pTargetUnit)),
            }
            pcall(function() parts[#parts + 1] = "lb " .. fmtv(num(d.LimitBurstPoint)) end)
            local okU, u = pcall(function() return d.unitParameterVariationData end)
            if okU and u then
                for _, f in ipairs(HIT_FIELDS) do
                    local okF, v = pcall(function() return u[f] end)
                    if okF then
                        v = unwrap(v)
                        if type(v) == "boolean" then
                            if v then parts[#parts + 1] = f end
                        elseif num(v) then
                            parts[#parts + 1] = f .. "=" .. fmtv(num(v))
                        end
                    end
                end
                local okE, el = pcall(function() return idList(u.elementList) end)
                if okE then parts[#parts + 1] = "elements=[" .. el .. "]" end
            end
            rows[#rows + 1] = table.concat(parts, " ")
        end)
    end)
    local sig = table.concat(rows, "\n")
    if #rows == 0 or sig == lastHits then return end
    lastHits = sig
    out("hits (%s), %d:", label, #rows)
    for _, r in ipairs(rows) do out("  hit %s", r) end
end

--------------------------------------------------------------------------------
-- Fight tracking and hooks
--------------------------------------------------------------------------------

local function inBattle()
    local ok, u = pcall(function() return FindFirstOf("CPP_BtlUnit") end)
    return ok and valid(u)
end

local crumbs = 0
-- v1.5: a crumb before every step, every time, with the clock, so a crash
-- names the step (or shows the probe was idle). One short line each.
local function step(name)
    if crumbs > 0 or W.allCrumbs ~= false then out("  step %s %s", name, os.date("%H:%M:%S")) end
end

-- Declared here, set after buildData (v1.3).
local dataBuilt = false
local buildDataOnce

local shadowPending = false
local function shadowRun()
    if not Sock or W.snapshot == false then return end
    step("shadow observe")
                local okS, snap = pcall(function() return Sock:observe() end)
                if okS and snap then
                    out("snap %s", SockLib.describe(snap))
                    if Shadow.P then
                        local okP, err = pcall(function()
                            for _, h in ipairs(snap.hits or {}) do
                                local sig = table.concat({ tostring(h.from), tostring(h.to), tostring(h.SkillId),
                                    tostring(h.hitNum), tostring(h.beforeVariationValue), tostring(h.beforeBreakPoint) }, ":")
                                if not Shadow.seen[sig] then
                                    Shadow.seen[sig] = true
                                    Shadow.E.learn(Shadow.L, Shadow.D, h)
                                end
                            end
                            if not Shadow.fightParty then
                                Shadow.fightParty = {}
                                for _, u in ipairs(snap.party) do Shadow.fightParty[u.uid] = true end
                            end
                            local summons = {}
                            for _, u in ipairs(snap.party) do
                                if not Shadow.fightParty[u.uid] then summons[u.uid] = true end
                            end
                            local world = { snap = snap, data = Shadow.D, attr = { FinishBlow = 9, LimitBurst = 5 },
                                            summons = summons, seenRes = Shadow.L.seenRes }
                            step("shadow plan")
                            local top, info = Shadow.P.plan(world, Shadow.L, W.tactic or "balanced", 999)
                            Shadow.top, Shadow.topActor = {}, snap.actor
                            Shadow.ranked = #top
                            out("shadow actor %s: %d options, %d kept", tostring(snap.actor), info.options, info.kept)
                            local why, shown = {}, 0
                            for _, o in ipairs(info.dropped or {}) do why[o.why or "?"] = (why[o.why or "?"] or 0) + 1 end
                            for r, n in pairs(why) do out("  shadow dropped %d: %s", n, r) end
                            local me = snap.units[snap.actor]
                            for _, o in ipairs(info.dropped or {}) do
                                if shown < 4 then
                                    shown = shown + 1
                                    out("  shadow e.g. #%s %s: cost %s mp %s activate %s enabled %s", tostring(o.id), tostring(o.why),
                                        tostring(o.cost), tostring(me and me.mp), tostring(o.bar and o.bar.canActivate),
                                        tostring(o.bar and o.bar.enabled))
                                end
                            end
                            for i, e in ipairs(top) do
                                Shadow.top[i] = e.option.id
                                if i <= 3 then out("  shadow %d. %s", i, Shadow.P.explain(e, nil)) end
                            end
                        end)
                        if not okP then out("shadow error: %s", tostring(err)) end
                    end
                else out("snap error: %s", tostring(snap)) end
            end

local function beginFight()
    P.active = true
    P.fight = P.fight + 1
    P.seq, P.prev, P.noisy, P.streak, P.tags, P.tagOrder = 0, nil, {}, {}, {}, {}
    crumbs = W.crumbs or 6
    lastHits = nil
    Shadow.fightParty, Shadow.top, Shadow.topActor = nil, nil, nil
    Shadow.tally = { n = 0, top1 = 0, top3 = 0, none = 0 }
    out("")
    out("==== fight %d at %s ====", P.fight, os.date("%Y-%m-%d %H:%M:%S"))
    say("fight %d", P.fight)
end

local function endFight()
    if not P.active then return end
    P.active = false
    if Shadow.P then
        local t = Shadow.tally
        out("shadow tally: %d party commands compared, top choice agreed %d, in top three %d, in top ten %d, not offered %d",
            t.n, t.top1, t.top3, t.top10 or 0, t.none)
    end
    out("---- fight %d tags ----", P.fight)
    for _, t in ipairs(P.tagOrder) do out("  tag %s x%d", t, P.tags[t]) end
    out("==== fight %d end ====", P.fight)
end

local pending = false
-- v0.4: a breadcrumb goes to the log before each step of the first few
-- walks of a fight, so a crash names its step. Hits are read only after a
-- decide. The generic value walk runs only when watch.lua sets walk = true.


-- The danger list from the Timeline view model (a long-lived object), read
-- in the game thread, never from a hook parameter. Logged when it changes.
local lastRisk = nil
local function readRisk()
    local okV, vm = pcall(function() return FindFirstOf("CPP_VM_BtlTimeLine") end)
    if not (okV and valid(vm)) then return end
    local okR, risk = pcall(function() return idList(vm.RiskUnitUniqueIdList) end)
    local okS, sk = pcall(function() return num(vm.ActionSkillId) end)
    if not okR then return end
    local line = string.format("risk [%s] skill %s", risk, tostring(okS and sk or nil))
    if line ~= lastRisk then lastRisk = line; out("%s", line) end
end

local function inGame(ms, fn)
    if ExecuteInGameThreadWithDelay then
        ExecuteInGameThreadWithDelay(ms, fn)
    else
        ExecuteWithDelay(ms, function() ExecuteInGameThread(fn) end)
    end
end

local function walkSoon(label, withHits)
    if pending then return end
    pending = true
    inGame(50, function()
        pending = false
        if not P.active then return end
        local ok, err = pcall(function()
            if withHits and W.hits ~= false then step("hits"); readHits(label) end
            if W.vitals ~= false then step("vitals"); vitals(label) end
            if W.risk ~= false then step("risk"); readRisk() end
            if W.walk then step("walk"); diff(label) end
            step("done")
        end)
        if not ok then out("walk error: %s", tostring(err)) end
        if crumbs > 0 then crumbs = crumbs - 1 end
    end)
end

local function decideLabel(value)
    local label = "decide"
    pcall(function()
        local v = value:get()
        local ss = subsystem()
        local actor = ss and num(ss.CurrentActionUnitUniqueId) or nil
        local ids = {}
        v.cmdDecideDataList:ForEach(function(_, e)
            local d = unwrap(e)
            if d then
                local tg = {}
                if d.ParameterList and d.ParameterList.ForEach then
                    d.ParameterList:ForEach(function(_, x) local n = num(x); if n then tg[#tg + 1] = n end end)
                end
                ids[#ids + 1] = string.format("%s%s->%s", d.isUseItem and "item " or "",
                    tostring(num(d.actionId)), table.concat(tg, ","))
            end
        end)
        label = string.format("decide actor %s %s", tostring(actor), table.concat(ids, " "))
    end)
    return label
end

RegisterHook("/Script/mucha.CPP_BtlDelEventCmd:OnExecuteDecideCommand", function(_, value)
    if not P.active and inBattle() then beginFight() end
    if not P.active then return end
    local label = decideLabel(value)
    out("%s", label)
    if Shadow.top then
        pcall(function()
            local v = value:get()
            local sent = nil
            v.cmdDecideDataList:ForEach(function(i, e)
                if i == 1 then local d = unwrap(e); sent = d and num(d.actionId) end
            end)
            local ss = subsystem()
            local actor = ss and num(ss.CurrentActionUnitUniqueId) or nil
            if sent and actor == Shadow.topActor then
                local rank = nil
                for i, id in ipairs(Shadow.top) do if id == sent and not rank then rank = i end end
                local t = Shadow.tally
                t.n = t.n + 1
                if rank == 1 then t.top1 = t.top1 + 1 end
                if rank and rank <= 3 then t.top3 = t.top3 + 1 end
                if not rank then t.none = t.none + 1 end
                if rank and rank <= 10 then t.top10 = (t.top10 or 0) + 1 end
                out("shadow compare: v0.1 sent %s, shadow rank %s of %s", tostring(sent), tostring(rank or "-"),
                    tostring(Shadow.ranked or "?"))
                Shadow.top = nil
            end
        end)
    end
    walkSoon(label, true)
end)

RegisterHook("/Script/mucha.CPP_MuchaEventDispatcher:ExecuteEvent", function(_, tag)
    local ok, name = pcall(function() return tag:get().TagName:ToString() end)
    if not ok or type(name) ~= "string" then return end
    if not P.active then
        if not name:find("Battle", 1, true) or not inBattle() then return end
        beginFight()
    end
    if not P.tags[name] then
        P.tags[name] = 0
        P.tagOrder[#P.tagOrder + 1] = name
        out("tag first %s (walk %d)", name, P.seq)
    end
    P.tags[name] = P.tags[name] + 1
    if name == "Delegate.Battle.Cmd.List.Begin" then
        if not dataBuilt and W.data ~= false then
            inGame(30, function()
                if P.active then buildDataOnce() end
            end)
        end
        if not shadowPending then
            shadowPending = true
            inGame(60, function()
                shadowPending = false
                if not P.active then return end
                local ok, err = pcall(shadowRun)
                if not ok then out("shadow error: %s", tostring(err)) end
            end)
        end
        walkSoon("menu")
    else
        for _, pat in ipairs(W.walkOnTags or {}) do
            if name:find(pat) then walkSoon("tag " .. name); break end
        end
    end
end)

-- Seen hooked by FFR-Vision-Studio's runtime tools. Marks each shared turn.
pcall(function()
    RegisterHook("/Script/mucha.CPP_UI_BattleSubsystem:HandleBeginTurn", function()
        if not P.active then return end
        out("turn begin (walk %d)", P.seq)
        if P.dumpAll then P.dumpAll() end
        walkSoon("turn", true)
    end)
end)

-- The Timeline (from the C++ header dump). The view model receives a
-- CPP_BtlTimelineUpdateDelVal with unit unique ids for this round, the next
-- round, and bonus turns. RiskUnitUniqueIdList on the same view model is
-- likely the "!" danger warning. Read only; GetTurnVM is never called.

pcall(function()
    RegisterHook("/Script/mucha.CPP_VM_BtlTimeLine:HandleUpdateTimeline", function(_, delval)
        if not P.active then return end
        step("timeline hook")
        pcall(function()
            local v = delval:get()
            if Sock then pcall(function() Sock:noteTimeline(v) end) end
            out("timeline current [%s] next [%s] extra [%s]", idList(v.currentTimelines),
                idList(v.nextTimelines), idList(v.additionalTurnTimelines))
        end)
    end)
end)

-- v0.5: no HandleUpdateRisk hook. v0.3 and v0.4 kept that hook's parameter
-- and read it 50 ms later; both crashed the game as the first command menu
-- took focus. The risk list is read from the view model object in vitals.

-- Phase 1: build planner 2's books (data.lua) from the live DataTables once,
-- 20 s after load, and log the summary and a few spot checks. Same row walk
-- v0.1.x already does for skills. Breadcrumbs before each step.
local function liveSource()
    local byStruct = nil
    local function index()
        byStruct = {}
        local ok, all = pcall(function() return FindAllOf("DataTable") end)
        if not ok or type(all) ~= "table" then return end
        for _, dt in ipairs(all) do
            pcall(function()
                if not valid(dt) then return end
                local st = dt:GetRowStruct()
                if not valid(st) then return end
                local n = fname(st)
                byStruct[n] = byStruct[n] or {}
                local list = byStruct[n]
                list[#list + 1] = function(cb)
                    dt:ForEachRow(function(key, row) cb(key, row) end)
                end
            end)
        end
    end
    local function val(v)
        v = unwrap(v)
        return v
    end
    return {
        tables = function(struct)
            if not byStruct then out("data: indexing tables"); index() end
            out("data: walking %s", struct)
            return byStruct[struct]
        end,
        get = function(row, field)
            local ok, v = pcall(function() return row[field] end)
            if not ok then return nil end
            return val(v)
        end,
        each = function(list, cb)
            pcall(function() list:ForEach(function(i, e) cb(i, val(e)) end) end)
        end,
        pairs = function(map, cb)
            pcall(function() map:ForEach(function(k, v) cb(val(k), val(v)) end) end)
        end,
        text = function(v)
            v = unwrap(v)
            if type(v) == "string" then return v end
            local ok, s = pcall(function() return v:ToString() end)
            return ok and s or nil
        end,
    }
end

local function buildData()
    local ok, data = pcall(dofile, DIR .. "/Scripts/data.lua")
    if not (ok and type(data) == "table") then out("data: data.lua not loaded: %s", tostring(data)); return end
    out("data: building from live tables")
    local okB, D, report = pcall(data.build, liveSource())
    if not okB then out("data: build failed: %s", tostring(D)); return end
    for _, l in ipairs(data.describe(report)) do out("%s", l) end
    pcall(function()
        local function m(n) return dofile(DIR .. "/Scripts/" .. n .. ".lua") end
        local E, R, O, T, S = m("effects"), m("rules"), m("options"), m("tactics"), m("score")
        Shadow.P = S.new({ effects = E, rules = R, options = O, tactics = T })
        Shadow.E, Shadow.D, Shadow.L = E, D, E.newLearner()
        out("data: shadow planner ready")
    end)
    if Sock then
        local ids = {}
        for id in pairs(D.items) do ids[#ids + 1] = id end
        Sock.itemIds = ids
        out("data: socket knows %d consumable ids", #ids)
    end
    local function s(id)
        local k = D.skills[id]
        if not k then return "missing" end
        return string.format("element %s stagger %s power %s hits %s cost %s pierceReflect %s effects %d",
            tostring(k.element), tostring(k.stagger), tostring(k.power), tostring(k.hits),
            tostring(k.cost), tostring(k.pierceReflect), #(k.effects or {}))
    end
    out("data check 220100: %s (offline: thunder 5)", s(220100))
    out("data check 408050: %s (offline: dark 8)", s(408050))
    local r = D.statuses[32]
    out("data check Reflect 32: esuna %s dispel %s stacks %s", tostring(r and r.esuna), tostring(r and r.dispel), tostring(r and r.stacks))
    local ex = D.difficulty.Expert
    out("data check Expert gauge %s hp %s", tostring(ex and ex.gauge), tostring(ex and ex.hp))
    local u = D.units[1001]
    local el = {}
    if u then for e, res in pairs(u.elements) do el[#el + 1] = e .. "=" .. tostring(res) end end
    table.sort(el)
    out("data check unit 1001: maxBreak %s elements %s", tostring(u and u.maxBreak), table.concat(el, ","))
    local it = D.items[1]
    out("data check item 1: skill %s", tostring(it and it.skill))
end

-- v1.3: the build runs at the first party menu of the first fight, never on
-- a timer. v1.2's 20 s timer fired while a save was loading and the table
-- walk crashed the game.
buildDataOnce = function()
    if dataBuilt or W.data == false then return end
    dataBuilt = true
    local ok, err = pcall(buildData)
    if not ok then out("data: error %s", tostring(err)) end
end

LoopAsync(1000, function()
    ExecuteInGameThread(function()
        if P.active and not inBattle() then endFight() end
    end)
    return false
end)

--------------------------------------------------------------------------------
-- Schema dump (F7)
--------------------------------------------------------------------------------

local function schemaOf(cls, lines, done)
    if not valid(cls) then return end
    local full = fname(cls)
    pcall(function() full = cls:GetFullName() end)
    if done[full] then return end
    done[full] = true
    local chain = {}
    local s, guard = cls, 0
    while s and valid(s) and guard < 32 do
        chain[#chain + 1] = fname(s)
        local ok, sup = pcall(function() return s:GetSuperStruct() end)
        s = ok and sup or nil
        guard = guard + 1
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "class " .. full
    lines[#lines + 1] = "  chain " .. table.concat(chain, " < ")
    for _, p in ipairs(propsOf(cls)) do
        lines[#lines + 1] = string.format("  prop %s %s", p.kind, p.name)
    end
    s, guard = cls, 0
    while s and valid(s) and guard < 32 do
        local owner = fname(s)
        pcall(function()
            s:ForEachFunction(function(fn)
                local params = {}
                pcall(function()
                    fn:ForEachProperty(function(prop)
                        local kind = "?"
                        pcall(function() kind = prop:GetClass():GetFName():ToString() end)
                        params[#params + 1] = kind .. " " .. fname(prop)
                    end)
                end)
                lines[#lines + 1] = string.format("  func %s::%s(%s)", owner, fname(fn), table.concat(params, ", "))
            end)
        end)
        local ok, sup = pcall(function() return s:GetSuperStruct() end)
        s = ok and sup or nil
        guard = guard + 1
        if s and fname(s) == "Object" then break end
    end
end

-- Loaded DataTables whose row struct is in W.tables: the struct's fields with
-- their kinds, and the first W.sampleRows rows flattened. Answers R8, R9
-- (is there an `element` field on SKILL_DATA?), R14, R15.
local function dumpTables(lines)
    local want = {}
    for _, n in ipairs(W.tables or {}) do want[n] = true end
    local okAll, tables = pcall(function() return FindAllOf("DataTable") end)
    if not okAll or type(tables) ~= "table" then
        lines[#lines + 1] = "no DataTables found"
        return
    end
    local seenStruct, all = {}, {}
    for _, dt in ipairs(tables) do
        pcall(function()
            if not valid(dt) then return end
            local st = dt:GetRowStruct()
            if not valid(st) then return end
            local sname = fname(st)
            all[#all + 1] = fname(dt) .. " : " .. sname
            if not want[sname] then return end
            local tname = "?"
            pcall(function() tname = dt:GetFullName() end)
            lines[#lines + 1] = ""
            lines[#lines + 1] = string.format("table %s rows of %s", tname, sname)
            if not seenStruct[sname] then
                seenStruct[sname] = true
                for _, p in ipairs(propsOf(st)) do
                    lines[#lines + 1] = string.format("  field %s %s", p.kind, p.name)
                end
            end
            local n = 0
            dt:ForEachRow(function(key, row)
                n = n + 1
                if n > (W.sampleRows or 3) then return true end
                local flat = {}
                walkStruct(row, st, "", flat, 0, {})
                local keys = {}
                for k in pairs(flat) do keys[#keys + 1] = k end
                table.sort(keys)
                local parts = {}
                for _, k in ipairs(keys) do parts[#parts + 1] = k:sub(2) .. "=" .. fmtv(flat[k]) end
                local rk = "?"
                pcall(function() rk = tostring(unwrap(key):ToString()) end)
                lines[#lines + 1] = string.format("  row %s: %s", rk, table.concat(parts, " "))
            end)
        end)
    end
    table.sort(all)
    lines[#lines + 1] = ""
    lines[#lines + 1] = string.format("loaded tables (%d):", #all)
    for _, s in ipairs(all) do lines[#lines + 1] = "  " .. s end
end

local function dumpSchema()
    local lines = { "FFRProbe schema at " .. os.date("%Y-%m-%d %H:%M:%S") }
    local done = {}
    pcall(dumpTables, lines)
    for _, lib in ipairs(W.libraries or {}) do
        local ok, cls = pcall(function() return StaticFindObject("/Script/mucha." .. lib) end)
        if ok and valid(cls) then schemaOf(cls, lines, done)
        else lines[#lines + 1] = "missing library " .. lib end
    end
    for _, r in ipairs(roots()) do
        schemaOf(classOf(r.obj), lines, done)
    end
    local f = io.open(DIR .. "/probe_schema.txt", "w")
    if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
    say("schema written, %d lines", #lines)
end

local key = W.schemaKey and Key and Key[W.schemaKey]
if key then
    RegisterKeyBind(key, function()
        ExecuteInGameThread(function()
            local ok, err = pcall(dumpSchema)
            if not ok then say("schema failed: %s", tostring(err)) end
        end)
    end)
end

-- Every loaded DataTable, every row, every field, one file a table. It reads
-- row[name], the read the main mod already uses, with field names generated
-- from the C++ header dump. It starts at the first turn of the first fight and
-- writes one table every fifth of a second. Read-only.
do
    local started = false
    local okF, Fields = pcall(dofile, DIR .. "/Scripts/fields.lua")
    if not okF then Fields = {} end
    local function fieldsOf(struct)
        local out, n = {}, struct
        local guard = 0
        while n and Fields[n] and guard < 8 do
            for _, f in ipairs(Fields[n]) do out[#out + 1] = f end
            n = Fields[n].base
            guard = guard + 1
        end
        return out
    end
    -- The element type inside TArray<X> or the value type inside TMap<K, V>.
    local function innerOf(ty)
        local a = ty:match("^TArray<%s*(.-)%s*>$")
        if a then return a end
        return ty:match("^TMap<.-,%s*(.-)%s*>$")
    end
    local flat
    flat = function(v, ty, path, w, depth)
        if depth > 6 then return end
        v = unwrap(v)
        local t = type(v)
        if t == "number" or t == "string" or t == "boolean" then
            w(path, tostring(v))
            return
        end
        if v == nil then return end
        if Fields[ty] then
            for _, f in ipairs(fieldsOf(ty)) do
                local ok, sub = pcall(function() return v[f[1]] end)
                if ok then flat(sub, f[2], path .. "." .. f[1], w, depth + 1) end
            end
            return
        end
        local inner = innerOf(ty)
        if inner then
            local ok = pcall(function()
                local i = 0
                v:ForEach(function(a, b)
                    i = i + 1
                    if i > 256 then return true end
                    if b ~= nil and ty:find("^TMap") then
                        local k = unwrap(a)
                        flat(b, inner, path .. "[" .. tostring(k) .. "]", w, depth + 1)
                    else
                        flat(b or a, inner, path .. "[" .. i .. "]", w, depth + 1)
                    end
                end)
            end)
            if ok then return end
        end
        local okS, text = pcall(function() return v:ToString() end)
        if okS and text then w(path, tostring(text)) end
    end
    P.dumpAll = function()
        if started or not W.dumpAll then return end
        started = true
        inGame(500, function()
            local ok, tables = pcall(function() return FindAllOf("DataTable") end)
            if not ok or type(tables) ~= "table" then return end
            local queue, i, done = {}, 0, 0
            -- A table that was being read when the game went down is marked to
            -- skip, and a finished one isn't read again. Each launch carries on.
            local donePath, skipPath, nowPath = DIR .. "/dump_done.txt", DIR .. "/dump_skip.txt", DIR .. "/dump_now.txt"
            local function linesOf(path)
                local set, f = {}, io.open(path, "r")
                if f then
                    for line in f:lines() do set[line] = true end
                    f:close()
                end
                return set
            end
            local function note(path, mode, text)
                local f = io.open(path, mode)
                if f then
                    f:write(text)
                    f:flush()
                    f:close()
                end
            end
            for name in pairs(linesOf(nowPath)) do
                note(skipPath, "a", name .. "\n")
                os.remove(DIR .. "/gamedata_" .. name .. ".txt")
                say("dump: skipping %s, it was being read at the last stop", name)
            end
            os.remove(nowPath)
            local finished, skipped = linesOf(donePath), linesOf(skipPath)
            for _, dt in ipairs(tables) do
                local okN, name = pcall(fname, dt)
                if okN and name and (not finished[name]) and (not skipped[name]) then queue[#queue + 1] = dt end
            end
            say("dump: %d tables left", #queue)
            local function nextTable()
                i = i + 1
                local dt = queue[i]
                if not dt then
                    say("dump: done, %d written", done)
                    return
                end
                local okT, err = pcall(function()
                    if not valid(dt) then return end
                    local st = dt:GetRowStruct()
                    if not valid(st) then return end
                    local sname = fname(st)
                    note(nowPath, "w", fname(dt) .. "\n")
                    local f = io.open(DIR .. "/gamedata_" .. fname(dt) .. ".txt", "w")
                    if not f then return end
                    f:write("struct ", sname, "\n")
                    local w = function(k, v) f:write("  ", k, " = ", v, "\n") end
                    dt:ForEachRow(function(key, row)
                        f:write("row ", tostring(key), "\n")
                        pcall(flat, row, "F" .. sname, "", w, 0)
                    end)
                    f:close()
                    note(donePath, "a", fname(dt) .. "\n")
                    os.remove(nowPath)
                    done = done + 1
                end)
                if not okT then say("dump: table failed: %s", tostring(err)) end
                inGame(200, nextTable)
            end
            nextTable()
        end)
    end
end

say("loaded. probe v1.8 (dump). schema key %s", tostring(W.schemaKey))

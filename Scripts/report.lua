-- battle_report.txt: everything a fight can tell us, so a fight isn't replayed
-- to answer a question it could have answered. This file only writes. It does
-- not touch the game, and it never picks a command. main.lua hands it plain
-- numbers and names. Lines stay in memory until the fight is over, then go to
-- disk at once. A crash loses the fight it happened in, and no earlier one.

local M = {}

-- The file holds this many fights. A finished fight drops the oldest.
M.KEEP_FIGHTS = 5

local function pct(cur, max)
    if not cur or not max or max <= 0 then return nil end
    return math.floor(100 * cur / max + 0.5)
end

local function sortedKeys(t)
    local out = {}
    for k in pairs(t or {}) do out[#out + 1] = k end
    table.sort(out, function(a, b) return tostring(a) < tostring(b) end)
    return out
end

local function setText(t)
    local keys = sortedKeys(t)
    for i, k in ipairs(keys) do keys[i] = tostring(k) end
    return (#keys > 0) and table.concat(keys, ",") or "-"
end

function M.new(path, clock)
    local R = { path = path, clock = clock or function() return os.date("%H:%M:%S") end, pending = {} }

    function R:write(lines)
        local pending = self.pending
        if type(lines) == "table" then
            for _, l in ipairs(lines) do pending[#pending + 1] = l end
        else
            pending[#pending + 1] = tostring(lines)
        end
    end

    -- The one disk write for a fight. A file that won't open keeps the lines for the next try.
    function R:flush()
        if #self.pending == 0 then return end
        local f = io.open(self.path, "a")
        if not f then return end
        f:write(table.concat(self.pending, "\n"), "\n")
        f:close()
        self.pending = {}
        pcall(self.trim, self)
    end

    -- Keeps the newest fights. A fight starts at its == battle line, when it has one.
    function R:trim(keep)
        keep = keep or M.KEEP_FIGHTS
        local f = io.open(self.path, "r")
        if not f then return end
        local text = f:read("a")
        f:close()
        if not text then return end
        local heads, at = {}, 1
        while true do
            local found = text:find("=== FIGHT", at, true)
            if not found then break end
            if (found == 1) or (text:sub(found - 1, found - 1) == "\n") then heads[#heads + 1] = found end
            at = found + 1
        end
        if #heads <= keep then return end
        local first = #heads - keep + 1
        local cut = heads[first]
        local from = heads[first - 1] or 1
        local chunk = text:sub(from, cut - 1)
        local mark, seek = nil, 1
        while true do
            local found = chunk:find("\n%d%d:%d%d:%d%d == battle ", seek)
            if not found then break end
            mark, seek = found + 1, found + 1
        end
        if mark then cut = from + mark - 1 end
        local out = io.open(self.path, "w")
        if out then out:write(text:sub(cut)); out:close() end
    end

    function R:note(line)
        if type(line) ~= "string" or line == "" then return end
        self:write(string.format("%s %s", self.clock(), (line:gsub("^%s+", ""))))
    end

    function R:begin(info)
        self.fight = {
            info = info, started = self.clock(), startClock = os.time(), cmds = 0, who = {}, whoOrder = {},
            foes = {}, foeOrder = {}, kinds = {}, flags = {}, flagOrder = {}, hits = {}, hitSeen = {},
            wheels = 0, last = nil, falls = 0, raises = 0, firstFall = nil, cardSeen = {}, barSeen = {},
            breaks = {}, open = {}, total = 0, onBroken = 0, triggers = 0, lastCmd = nil, lastNow = nil,
            hpTotal = 0, hpOnBroken = 0, drops = {},
        }
        self:write({ "", string.format("=== FIGHT %s, boss %s, %s, started %s ===", tostring(info.number),
            tostring(info.boss), tostring(info.difficulty or "difficulty unread"), self.fight.started) })
    end

    local function ally(F, name)
        if not F.who[name] then
            F.who[name] = { turns = 0, skills = {}, order = {}, mpSpent = 0, hpLow = 100, mpLow = nil, falls = 0,
                dealt = 0, staggered = 0, healed = 0, overheal = 0, hitsTaken = 0, dmgTaken = 0, kinds = {} }
            F.whoOrder[#F.whoOrder + 1] = name
        end
        return F.who[name]
    end

    local function foe(F, name)
        if not F.foes[name] then
            F.foes[name] = { hpLow = 100, gaugeLow = nil, gaugeMax = nil, breaks = 0, appeared = 0, rows = {},
                byFactor = {}, damage = 0, stagger = 0, gaugeSeen = {}, hpLost = 0, moves = {}, moveOrder = {} }
            F.foeOrder[#F.foeOrder + 1] = name
        end
        return F.foes[name]
    end

    function R:flag(kind, text)
        local F = self.fight
        if not F or self.quiet then return end
        if not F.flags[kind] then
            F.flags[kind] = { n = 0, examples = {} }
            F.flagOrder[#F.flagOrder + 1] = kind
        end
        local rec = F.flags[kind]
        rec.n = rec.n + 1
        if #rec.examples < 6 then rec.examples[#rec.examples + 1] = text end
    end

    -- A stagger opens when a gauge empties and closes when it fills or the body goes.
    local function openBreak(F, id, u, was, snap)
        local others = {}
        for oid, o in pairs(snap.foes) do
            if oid ~= id then others[#others + 1] = string.format("%s %s%%", tostring(o.name), tostring(pct(o.gauge, o.maxGauge))) end
        end
        table.sort(others)
        local taken = "unknown"
        if F.lastNow then
            taken = (" " .. F.lastNow .. " "):find(" " .. tostring(u.name) .. " ", 1, true) and "yes" or "no, it had acted or wasn't due"
        end
        local b = { at = F.cmds, foe = tostring(u.name), by = F.lastCmd or "?", hpBefore = pct(was.hp, was.maxHp), cmds = 0, kinds = {}, skills = {}, order = {},
            hits = 0, dmg = 0, hpLost = 0, sweep = false, taken = taken, others = others, limitUnused = 0, offTask = 0 }
        F.breaks[#F.breaks + 1] = b
        F.open[id] = b
    end

    -- HP an enemy really lost between two readings. It counts what the hit
    -- records can't see, such as a Resonance, an esper, or the last blow.
    local function hpDrop(F, id, name, lost)
        if (not lost) or (lost <= 0) then return end
        F.hpTotal = F.hpTotal + lost
        foe(F, tostring(name)).hpLost = foe(F, tostring(name)).hpLost + lost
        F.drops[#F.drops + 1] = { lost = lost, foe = tostring(name), at = F.cmds, by = F.lastCmd or "?" }
        local b = F.open[id]
        if b then
            b.hpLost = b.hpLost + lost
            F.hpOnBroken = F.hpOnBroken + lost
        end
    end

    local function closeBreak(F, id, u)
        local b = F.open[id]
        if not b then return end
        if u then b.hpAfter = pct(u.hp, u.maxHp) end
        F.open[id] = nil
    end

    local function unitLine(u)
        return string.format("%s hp %s/%s (%s%%) mp %s/%s lb %s gauge %s/%s st[%s]%s", tostring(u.name), tostring(u.hp),
            tostring(u.maxHp), tostring(pct(u.hp, u.maxHp)), tostring(u.mp), tostring(u.maxMp), tostring(u.lb),
            tostring(u.gauge), tostring(u.maxGauge), setText(u.statuses), u.down and " DOWN" or "")
    end

    -- A new reading of the field: what changed since the last one, unit by unit.
    function R:field(snap)
        local F = self.fight
        if not F or not snap then return end
        local prev = F.last
        local lines = {}
        local function compare(list, isFoe)
            for id, u in pairs(list) do
                local was = prev and (isFoe and prev.foes or prev.allies)[id]
                local bits = {}
                if not was then
                    if prev then bits[#bits + 1] = "appeared" end
                    if isFoe then foe(F, tostring(u.name)).appeared = foe(F, tostring(u.name)).appeared + 1 end
                else
                    if u.hp ~= was.hp then bits[#bits + 1] = string.format("hp %s>%s", tostring(was.hp), tostring(u.hp)) end
                    if u.mp ~= was.mp then bits[#bits + 1] = string.format("mp %s>%s", tostring(was.mp), tostring(u.mp)) end
                    if u.gauge ~= was.gauge then bits[#bits + 1] = string.format("gauge %s>%s", tostring(was.gauge), tostring(u.gauge)) end
                    if u.lb ~= was.lb and not isFoe then bits[#bits + 1] = string.format("lb %s>%s", tostring(was.lb), tostring(u.lb)) end
                    for st in pairs(u.statuses or {}) do
                        if not (was.statuses or {})[st] then bits[#bits + 1] = "+st" .. tostring(st) end
                    end
                    for st in pairs(was.statuses or {}) do
                        if not (u.statuses or {})[st] then bits[#bits + 1] = "-st" .. tostring(st) end
                    end
                end
                if isFoe then
                    local rec = foe(F, tostring(u.name))
                    local p = pct(u.hp, u.maxHp)
                    if p and p < rec.hpLow then rec.hpLow = p end
                    if was and was.hp and u.hp then hpDrop(F, id, u.name, was.hp - u.hp) end
                    if u.gauge and ((rec.gaugeLow == nil) or u.gauge < rec.gaugeLow) then rec.gaugeLow = u.gauge end
                    if u.maxGauge then rec.gaugeSeen[u.maxGauge] = true; rec.gaugeMax = u.maxGauge end
                    if was and (was.gauge or 0) > 0 and (u.gauge or 0) <= 0 then
                        rec.breaks = rec.breaks + 1
                        bits[#bits + 1] = "BROKE"
                        openBreak(F, id, u, was, snap)
                    elseif F.open[id] then
                        F.open[id].hpAfter = pct(u.hp, u.maxHp)
                        if (u.gauge or 0) > 0 then
                            bits[#bits + 1] = "gauge back"
                            closeBreak(F, id, u)
                        end
                    end
                else
                    local rec = ally(F, tostring(u.name))
                    local p = pct(u.hp, u.maxHp)
                    if p and p < rec.hpLow then rec.hpLow = p end
                    if u.mp and ((rec.mpLow == nil) or u.mp < rec.mpLow) then rec.mpLow = u.mp end
                    if was and (not was.down) and u.down then
                        rec.falls = rec.falls + 1
                        F.falls = F.falls + 1
                        F.firstFall = F.firstFall or F.cmds
                        bits[#bits + 1] = "FELL"
                    end
                    if was and was.down and (not u.down) then bits[#bits + 1] = "UP" end
                end
                if #bits > 0 then lines[#lines + 1] = "    " .. tostring(u.name) .. ": " .. table.concat(bits, " ") end
            end
        end
        compare(snap.allies, false)
        compare(snap.foes, true)
        if prev then
            for id, was in pairs(prev.foes) do
                if not snap.foes[id] then
                    lines[#lines + 1] = "    " .. tostring(was.name) .. ": gone (hp was " .. tostring(was.hp) .. ")"
                    hpDrop(F, id, was.name, was.hp)
                    closeBreak(F, id, nil)
                end
            end
        end
        -- Every enemy on the field staggered at once is a sweep.
        local any, all = false, true
        for _, u in pairs(snap.foes) do
            any = true
            if (u.gauge or 0) > 0 then all = false end
        end
        if any and all then
            for _, b in pairs(F.open) do b.sweep = true end
        end
        table.sort(lines)
        if #lines > 0 then
            table.insert(lines, 1, string.format("%s  changed since command %d:", self.clock(), F.cmds))
            self:write(lines)
        end
        F.last = snap
    end

    -- A hit record from the game, once each.
    function R:hit(h)
        local F = self.fight
        if not F then return end
        local sig = table.concat({ tostring(h.from), tostring(h.to), tostring(h.skill), tostring(h.param), tostring(h.value),
            tostring(h.before), tostring(h.after), tostring(h.breakValue) }, ":")
        if F.hitSeen[sig] then return end
        F.hitSeen[sig] = true
        self:write(string.format("%s  hit %s > %s: %s, param %s type %s value %s (%s>%s) break %s%s%s%s", self.clock(),
            tostring(h.fromName), tostring(h.toName), tostring(h.skillName), tostring(h.param), tostring(h.vtype), tostring(h.value),
            tostring(h.before), tostring(h.after), tostring(h.breakValue), h.miss and " MISS" or "", h.defended and " DEFENDED" or "",
            h.crit and " CRIT" or ""))
        local v = tonumber(h.value) or 0
        if h.trigger then F.triggers = F.triggers + 1 end
        if h.fromFriend and (not h.toFriend) and h.param == 1 and h.vtype == 1 and v > 0 then
            F.total = F.total + v
            if h.onBreak then
                F.onBroken = F.onBroken + v
                for i = #F.breaks, 1, -1 do
                    local b = F.breaks[i]
                    if b.foe == tostring(h.toName) then
                        b.hits = b.hits + 1
                        b.dmg = b.dmg + v
                        break
                    end
                end
            end
        end
        if (not h.fromFriend) and h.toFriend and (h.param == 1) and (h.vtype == 1) then
            local rec = foe(F, tostring(h.fromName))
            local name = tostring(h.skillName)
            if not rec.moves[name] then
                rec.moves[name] = { hits = 0, worst = 0, kills = 0 }
                rec.moveOrder[#rec.moveOrder + 1] = name
            end
            local m = rec.moves[name]
            m.hits = m.hits + 1
            if v > m.worst then m.worst = v end
            if (h.after == 0) and (h.before or 0) > 0 then m.kills = m.kills + 1 end
        end
        if h.param == 1 and v > 0 then
            if h.vtype == 1 then
                if h.fromFriend then
                    ally(F, tostring(h.fromName)).dealt = ally(F, tostring(h.fromName)).dealt + v
                    foe(F, tostring(h.toName)).damage = foe(F, tostring(h.toName)).damage + v
                elseif h.toFriend then
                    local a = ally(F, tostring(h.toName))
                    a.hitsTaken = a.hitsTaken + 1
                    a.dmgTaken = a.dmgTaken + v
                end
            elseif h.vtype == 0 and h.fromFriend then
                local a = ally(F, tostring(h.fromName))
                a.healed = a.healed + v
                if h.before and h.after and (h.after - h.before) < v then a.overheal = a.overheal + (v - (h.after - h.before)) end
            end
        end
        local b = tonumber(h.breakValue) or 0
        if b > 0 and h.fromFriend then
            ally(F, tostring(h.fromName)).staggered = ally(F, tostring(h.fromName)).staggered + b
            foe(F, tostring(h.toName)).stagger = foe(F, tostring(h.toName)).stagger + b
        end
    end

    -- One command. rec comes from main.lua; the field is the last reading.
    function R:decide(rec)
        local F = self.fight
        if not F then return end
        -- The player's own turns count, but aren't flagged: the flags judge the mod.
        self.quiet = rec.byHand and true or false
        F.cmds = F.cmds + 1
        local n = F.cmds
        local a = ally(F, tostring(rec.who))
        a.turns = a.turns + 1
        if not a.skills[rec.name] then a.skills[rec.name] = 0; a.order[#a.order + 1] = rec.name end
        a.skills[rec.name] = a.skills[rec.name] + 1
        a.mpSpent = a.mpSpent + (rec.cost or 0)
        local kind = rec.kind or "other"
        F.kinds[kind] = (F.kinds[kind] or 0) + 1
        F.lastCmd = tostring(rec.who) .. " " .. tostring(rec.name)
        F.lastNow = rec.now
        a.kinds[kind] = (a.kinds[kind] or 0) + 1
        if kind == "revive" then F.raises = F.raises + 1 end
        local targets = {}
        for _, t in ipairs(rec.targets or {}) do
            local tx = tostring(t.name)
            if t.factor then tx = tx .. " x" .. tostring(t.factor) end
            if t.pct then tx = tx .. " at " .. tostring(t.pct) .. "%" end
            targets[#targets + 1] = tx
        end
        local lines = {
            string.format("%s #%d%s round %s phase %s %s mp %s lb %s: %s (id %s, %s, attr %s, dmg %s, cost %s) -> %s", self.clock(), n, rec.byHand and " BY HAND" or "",
                tostring(rec.round), tostring(rec.phase), tostring(rec.who), tostring(rec.mp), tostring(rec.lb), tostring(rec.name),
                tostring(rec.id), kind, tostring(rec.attr), tostring(rec.dmgType), tostring(rec.cost), table.concat(targets, ", ")),
            "    why: " .. tostring(rec.reason),
        }
        if rec.could and #rec.could > 0 then lines[#lines + 1] = "    could pay: " .. table.concat(rec.could, "; ") end
        if rec.next then lines[#lines + 1] = "    order: " .. tostring(rec.next) end
        if rec.risk and rec.risk ~= "" then lines[#lines + 1] = "    warned: " .. tostring(rec.risk) end
        if rec.claims and rec.claims ~= "" then lines[#lines + 1] = "    claimed: " .. tostring(rec.claims) end
        local snap = F.last
        if snap then
            local us = {}
            for _, id in ipairs(sortedKeys(snap.allies)) do us[#us + 1] = "    " .. unitLine(snap.allies[id]) end
            for _, id in ipairs(sortedKeys(snap.foes)) do us[#us + 1] = "    " .. unitLine(snap.foes[id]) end
            for _, l in ipairs(us) do lines[#lines + 1] = l end
        end
        self:write(lines)

        -- The turns worth a second look, counted for the report.
        local tag = string.format("#%d %s %s", n, tostring(rec.who), tostring(rec.name))
        if rec.multicastSweep then
            self:flag("every gauge low, Multicast in reach, single-target spell or other used", tag .. ", could cast " .. tostring(rec.multicastSweep) .. " on All")
        end
        if rec.multicastHeal then
            self:flag("most of the party hurt, Multicast heal in reach", tag .. ", could cast " .. tostring(rec.multicastHeal) .. " on All")
        end
        -- What this command did with any stagger that's open.
        if next(F.open) then
            local isLimit = rec.attr == 5
            local critical = false
            if snap then
                for _, u in pairs(snap.allies) do
                    local p = pct(u.hp, u.maxHp)
                    if u.down or (p and p < 30) then critical = true end
                end
            end
            for _, b in pairs(F.open) do
                b.cmds = b.cmds + 1
                b.kinds[kind] = (b.kinds[kind] or 0) + 1
                if not b.skills[rec.name] then b.skills[rec.name] = 0; b.order[#b.order + 1] = rec.name end
                b.skills[rec.name] = b.skills[rec.name] + 1
                if rec.limitReady and (not isLimit) and (kind == "damage" or kind == "throw" or kind == "buff" or kind == "debuff") then
                    b.limitUnused = b.limitUnused + 1
                    self:flag("Limit ready during a stagger, not used", tag .. ", had " .. tostring(rec.limitReady))
                end
                if (kind ~= "damage") and (kind ~= "throw") and (not critical) then
                    b.offTask = b.offTask + 1
                    self:flag("stagger open, nobody critical, turn wasn't a hit", tag .. " (" .. kind .. ") during " .. b.foe)
                end
                if (kind == "damage") and rec.value and rec.bestValue and rec.bestValue > 0 and rec.value < rec.bestValue * 0.5 then
                    self:flag("stagger open, hit under half the best payable", tag .. ", best was " .. tostring(rec.bestName))
                end
            end
        end
        local low, lowName, down = 100, nil, 0
        if snap then
            for _, u in pairs(snap.allies) do
                if u.down then down = down + 1 else
                    local p = pct(u.hp, u.maxHp)
                    if p and p < low then low, lowName = p, u.name end
                end
            end
        end
        local isHit = kind == "damage"
        local caring = (kind == "heal") or (kind == "revive") or (kind == "cure") or rec.itemHeal
        for _, t in ipairs(rec.targets or {}) do
            if isHit and t.factor then
                local key = tostring(t.factor)
                local fr = foe(F, tostring(t.name))
                fr.byFactor[key] = (fr.byFactor[key] or 0) + 1
                if t.factor == 0 then self:flag("hit that can't land", tag .. " on " .. tostring(t.name)) end
                if t.factor < 3 and t.weakPaid then
                    self:flag("weakness on the bar, hit something else", tag .. " x" .. key .. " on " .. tostring(t.name) .. ", could pay " .. tostring(t.weakPaid))
                end
            end
            if (kind == "heal") and t.pct and t.pct >= 65 and not rec.isAll then
                self:flag("heal on an ally at 65% or more", tag .. " on " .. tostring(t.name) .. " at " .. t.pct .. "%")
            end
        end
        if (low < 30) and (not caring) then
            if rec.canHeal then
                self:flag("no heal with an ally under 30%, heal payable", tag .. ", " .. tostring(lowName) .. " at " .. low .. "%")
            else
                self:flag("not a heal with an ally under 30%", tag .. ", " .. tostring(lowName) .. " at " .. low .. "%")
            end
        end
        for _, s in ipairs(rec.short or {}) do
            self:flag("short of MP for a " .. tostring(s.need) .. ", Ether in the bag",
                tag .. ", wanted " .. tostring(s.what) .. (s.spent and " (Ether already spent this round)" or ""))
        end
        if (down > 0) and (not caring) and rec.canRaise then
            self:flag("no raise with an ally down, raise payable", tag .. ", " .. down .. " down")
        end
        if isHit and (rec.cost or 0) > 0 and rec.mp and rec.maxMp and rec.mp - rec.cost < rec.maxMp * 0.1 and rec.isHealer then
            self:flag("healer spent down to 10% MP on a hit", tag)
        end
        if kind == "support" or kind == "buff" then
            F.supportRun = F.supportRun or {}
            local r = (F.supportRun[rec.who] or 0) + 1
            F.supportRun[rec.who] = r
            if r == 3 then self:flag("three support turns in a row", tag) end
        else
            if F.supportRun then F.supportRun[rec.who] = 0 end
        end
    end

    function R:finish(extra)
        local F = self.fight
        if not F then return end
        local snap = F.last
        local up, downN, foesUp = 0, 0, {}
        if snap then
            for _, u in pairs(snap.allies) do if u.down then downN = downN + 1 else up = up + 1 end end
            for _, u in pairs(snap.foes) do
                if (u.hp or 0) > 0 then foesUp[#foesUp + 1] = string.format("%s %s%% gauge %s/%s", tostring(u.name), tostring(pct(u.hp, u.maxHp)), tostring(u.gauge), tostring(u.maxGauge)) end
            end
        end
        local lines = { "", string.format("--- REPORT fight %s, boss %s, %s", tostring(F.info.number), tostring(F.info.boss), tostring(F.info.difficulty or "difficulty unread")) }
        lines[#lines + 1] = string.format("    length: %d commands, %d rounds, about %d seconds", F.cmds, tonumber(extra and extra.rounds) or 0, os.time() - F.startClock)
        lines[#lines + 1] = string.format("    damage logged: %d total, %.0f per command, %d (%d%%) on staggered bodies", F.total, F.total / math.max(F.cmds, 1), F.onBroken, F.total > 0 and math.floor(100 * F.onBroken / F.total + 0.5) or 0)
        lines[#lines + 1] = string.format("    damage by HP readings: %d total, %.0f per command, %d (%d%%) on staggered bodies", F.hpTotal, F.hpTotal / math.max(F.cmds, 1), F.hpOnBroken, F.hpTotal > 0 and math.floor(100 * F.hpOnBroken / F.hpTotal + 0.5) or 0)
        table.sort(F.drops, function(a, b) return a.lost > b.lost end)
        for i = 1, math.min(#F.drops, 8) do
            local d = F.drops[i]
            lines[#lines + 1] = string.format("      drop %d on %s, after #%d %s", d.lost, d.foe, d.at, d.by)
        end
        local sweeps = 0
        for _, b in ipairs(F.breaks) do if b.sweep then sweeps = sweeps + 1 end end
        lines[#lines + 1] = string.format("    staggers: %d seen on the gauge, %d in the hit records, %d of them sweeps", #F.breaks, F.triggers, sweeps)
        for _, b in ipairs(F.breaks) do
            local list = {}
            for _, s in ipairs(b.order) do list[#list + 1] = s .. " x" .. b.skills[s] end
            lines[#lines + 1] = string.format("      after #%d %s on %s: HP %s%%>%s%%, %d commands, %d hits, %d damage, %d by HP, sweep %s, its turn taken: %s; other gauges: %s; Limit left unused %d, off-task turns %d; used: %s",
                b.at, b.by, b.foe, tostring(b.hpBefore), tostring(b.hpAfter), b.cmds, b.hits, b.dmg, b.hpLost, b.sweep and "yes" or "no", b.taken,
                (#b.others > 0) and table.concat(b.others, ", ") or "-", b.limitUnused, b.offTask, (#list > 0) and table.concat(list, ", ") or "nothing")
        end
        lines[#lines + 1] = string.format("    at the last reading: %d allies up, %d down; foes up: %s", up, downN, (#foesUp > 0) and table.concat(foesUp, "; ") or "none read")
        lines[#lines + 1] = string.format("    falls %d, first after command %s; raises %d; wheels opened %d, sent %d",
            F.falls, tostring(F.firstFall), F.raises, tonumber(extra and extra.wheelOpen) or 0, tonumber(extra and extra.wheelSent) or 0)
        local mix = {}
        for _, k in ipairs(sortedKeys(F.kinds)) do mix[#mix + 1] = k .. " " .. F.kinds[k] end
        lines[#lines + 1] = "    turns by kind: " .. table.concat(mix, ", ")
        lines[#lines + 1] = "    party:"
        for _, name in ipairs(F.whoOrder) do
            local a = F.who[name]
            local list = {}
            for _, s in ipairs(a.order) do list[#list + 1] = s .. " x" .. a.skills[s] end
            lines[#lines + 1] = string.format("      %s: %d turns, MP spent %d, lowest MP %s, lowest HP %d%%, falls %d, damage logged %d, stagger logged %d, healed %d (overheal %d), hits taken %d for %d",
                name, a.turns, a.mpSpent, tostring(a.mpLow), a.hpLow, a.falls, a.dealt, math.floor((a.staggered or 0) + 0.5), a.healed, a.overheal, a.hitsTaken, a.dmgTaken)
            if #list > 0 then lines[#lines + 1] = "        " .. table.concat(list, ", ") end
        end
        lines[#lines + 1] = "    enemies:"
        for _, name in ipairs(F.foeOrder) do
            local e = F.foes[name]
            local fac = {}
            for _, k in ipairs(sortedKeys(e.byFactor)) do fac[#fac + 1] = "x" .. k .. " " .. e.byFactor[k] end
            lines[#lines + 1] = string.format("      %s: lowest HP %d%%, lowest gauge %s of %s (gauges seen %s), breaks %d, appeared %d, HP lost %d, damage logged %d, stagger logged %d; hits sent by fit: %s",
                name, e.hpLow, tostring(e.gaugeLow), tostring(e.gaugeMax), setText(e.gaugeSeen), e.breaks, e.appeared, e.hpLost, e.damage, math.floor((e.stagger or 0) + 0.5), (#fac > 0) and table.concat(fac, ", ") or "-")
            if #e.moveOrder > 0 then
                local list = {}
                for _, mv in ipairs(e.moveOrder) do
                    local m = e.moves[mv]
                    list[#list + 1] = string.format("%s %d hits, worst %d%s", mv, m.hits, m.worst, (m.kills > 0) and string.format(", %d kills", m.kills) or "")
                end
                lines[#lines + 1] = "        its moves: " .. table.concat(list, "; ")
            end
        end
        if #F.flagOrder > 0 then
            lines[#lines + 1] = "    worth a look:"
            for _, kind in ipairs(F.flagOrder) do
                local rec = F.flags[kind]
                lines[#lines + 1] = string.format("      %s: %d (%s)", kind, rec.n, table.concat(rec.examples, "; "))
            end
        else
            lines[#lines + 1] = "    worth a look: nothing flagged"
        end
        for _, l in ipairs((extra and extra.lines) or {}) do lines[#lines + 1] = "    " .. l end
        lines[#lines + 1] = "--- END REPORT"
        self:write(lines)
        self.fight = nil
    end

    return R
end

return M

-- Echo. Each character's last turn by hand, sent again as the player sent it.
-- A turn starts with a command in the normal phase. A command the same
-- character sends right after it in another phase (a stagger bonus action)
-- belongs to the same turn. Every action in each one is kept: a Dualcast
-- keeps its picks. The game does not send the enemy's turns through the
-- decide hook, so "another unit acted" can't mark the end of a turn.
-- Only a target can change, when the one the player chose can no longer
-- take it. Items, raises, Limit Bursts, Esper calls, and the Resonance
-- wheel are never taped: main.lua leaves them to the player.
--
-- The tape lives for the launch and carries from fight to fight. A turn is
-- kept by the character's name, since unit ids belong to one fight.
-- This file does not touch the game, and it does not name a fight, a
-- character, a skill, or a Vision.
--
-- A decide, as plain data:
--   { cmdType, notConsume, calcOrder, command, keys = { {cat, id}, ... },
--     entries = { { id, unit, item, all, pCat, pId, params = {...},
--                   targets = { { id, side, name }, ... } }, ... } }
-- side is "self", "ally", "foe", or "?" when the game did not say.

local M = {}

function M.new()
    return { turns = {} }
end

local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = copy(x) end
    return out
end
M.copy = copy

-- A hand decide from one character. streak: true when it carries on that
-- character's turn. keepTo: when an echo sent the first part of the turn and
-- the player sent this part by hand, the turn is cut to what went out first.
function M.note(tape, who, decide, streak, keepTo)
    if not (tape and who and decide and decide.entries and #decide.entries > 0) then return nil end
    local turn = tape.turns[who]
    if streak and turn then
        keepTo = tonumber(keepTo)
        if keepTo and (keepTo >= 1) then
            for i = #turn, keepTo + 1, -1 do turn[i] = nil end
        end
        turn[#turn + 1] = copy(decide)
    else
        turn = { copy(decide) }
        tape.turns[who] = turn
    end
    return #turn
end

function M.turn(tape, who)
    local turn = tape and who and tape.turns[who]
    if type(turn) ~= "table" or #turn == 0 then return nil end
    return turn
end

-- Which decide of the turn goes out on this menu. n counts the menus this
-- character has had in a row. More menus than the player sent start the turn over.
function M.step(n, count)
    n = tonumber(n) or 1
    count = tonumber(count) or 0
    if count < 1 then return nil end
    if n < 1 then n = 1 end
    return ((n - 1) % count) + 1
end

local function has(list, id)
    for _, x in ipairs(list or {}) do
        if x == id then return true end
    end
    return false
end

-- The decide for this menu. actor: the unit that sends it now. was: the unit
-- that sent it by hand. look.valid(entry, side) lists the ids the game lets
-- this entry take, best first. look.ally(name) is that ally's unit now.
-- Returns the decide and the targets it changed, or nil and why.
-- A change is { id = action id, side, from = recorded name, or id, to = new id }.
-- A self target following the caster, and an ally found by name, are not changes.
function M.aim(decide, actor, was, look)
    if not (decide and decide.entries and actor) then return nil, "nothing recorded" end
    look = look or {}
    local out = copy(decide)
    local changes = {}
    for _, e in ipairs(out.entries) do
        if (e.unit == nil) or (e.unit == was) then e.unit = actor end
        local recorded = e.targets or {}
        local ids = {}
        local side = nil
        for _, t in ipairs(recorded) do
            if t.side ~= "self" then side = side or t.side end
        end
        -- An All cast, or an action the player sent at several targets (a
        -- group skill), takes every target the game allows now.
        local others = 0
        for _, t in ipairs(recorded) do
            if t.side ~= "self" then others = others + 1 end
        end
        if (e.all or (others > 1)) and side and (side ~= "?") then
            ids = (look.valid and look.valid(e, side)) or {}
            if #ids == 0 then return nil, "no target for " .. tostring(e.id) end
            local gone = {}
            for _, t in ipairs(recorded) do
                if (t.side == side) and not has(ids, t.id) then gone[#gone + 1] = tostring(t.name or t.id) end
            end
            if #gone > 0 then
                changes[#changes + 1] = { id = e.id, side = side, from = table.concat(gone, ", "), group = ids }
            end
        else
            for _, t in ipairs(recorded) do
                local id = nil
                if t.side == "self" then
                    id = actor
                elseif (t.side == "ally") or (t.side == "foe") then
                    local valid = (look.valid and look.valid(e, t.side)) or {}
                    local want = t.id
                    if t.side == "ally" then want = look.ally and look.ally(t.name) or nil end
                    if want and has(valid, want) and not has(ids, want) then
                        id = want
                    else
                        for _, v in ipairs(valid) do
                            if not has(ids, v) then id = v break end
                        end
                        id = id or valid[1]
                        if id ~= nil then
                            changes[#changes + 1] = { id = e.id, side = t.side,
                                from = t.name or t.id, to = id }
                        end
                    end
                    if id == nil then return nil, "no target for " .. tostring(e.id) end
                else
                    id = t.id
                end
                ids[#ids + 1] = id
            end
        end
        e.targets = ids
    end
    return out, changes
end

-- What a decide spends: MP rows and items, so the caller can ask the game.
-- top: an action under the menu itself, not under another action in it.
function M.uses(decide)
    local items, skills = {}, {}
    local inside = {}
    for _, e in ipairs((decide and decide.entries) or {}) do inside[e.id] = true end
    for _, e in ipairs((decide and decide.entries) or {}) do
        if e.item then
            items[e.id] = (items[e.id] or 0) + 1
        else
            skills[#skills + 1] = { id = e.id, all = e.all and true or false, top = not inside[e.pId] }
        end
    end
    return items, skills
end

-- One line for the log. nameOf(id) names a skill or item row.
function M.describe(decide, nameOf)
    local bits = {}
    for _, e in ipairs((decide and decide.entries) or {}) do
        local name = (nameOf and nameOf(e.id, e.item)) or tostring(e.id)
        if e.all then name = name .. " (all)" end
        bits[#bits + 1] = name
    end
    return table.concat(bits, " + ")
end

-- Across sessions. The tape is written as a Lua table and read back with
-- no access to anything but its own text. A file that does not read, or
-- does not hold a tape, gives nil and why, and the caller starts empty.
M.VERSION = 1

local function literal(v, out)
    local t = type(v)
    if t == "number" then
        out[#out + 1] = (v == math.floor(v)) and string.format("%d", v) or string.format("%.17g", v)
    elseif t == "boolean" then
        out[#out + 1] = v and "true" or "false"
    elseif t == "string" then
        out[#out + 1] = string.format("%q", v)
    elseif t == "table" then
        out[#out + 1] = "{"
        local n = #v
        for i = 1, n do
            literal(v[i], out)
            out[#out + 1] = ","
        end
        local keys = {}
        for k in pairs(v) do
            if not ((type(k) == "number") and (k >= 1) and (k <= n) and (k == math.floor(k))) then keys[#keys + 1] = k end
        end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        for _, k in ipairs(keys) do
            out[#out + 1] = "["
            literal(k, out)
            out[#out + 1] = "]="
            literal(v[k], out)
            out[#out + 1] = ","
        end
        out[#out + 1] = "}"
    else
        out[#out + 1] = "nil"
    end
end

function M.encode(tape)
    local out = {}
    literal({ version = M.VERSION, turns = (tape and tape.turns) or {} }, out)
    return "-- FFR:AutoBattle Echo tape. Delete this file to clear it.\nreturn " .. table.concat(out) .. "\n"
end

local function decideOk(d)
    if type(d) ~= "table" or type(d.entries) ~= "table" or #d.entries == 0 then return false end
    for _, e in ipairs(d.entries) do
        if type(e) ~= "table" or type(e.id) ~= "number" then return false end
        if (e.targets ~= nil) and (type(e.targets) ~= "table") then return false end
        for _, t in ipairs(e.targets or {}) do
            if type(t) ~= "table" then return false end
        end
    end
    return true
end

function M.decode(text)
    if type(text) ~= "string" or text == "" then return nil, "empty" end
    local chunk, err = load(text, "echo tape", "t", {})
    if not chunk then return nil, tostring(err) end
    local ok, got = pcall(chunk)
    if not ok then return nil, tostring(got) end
    if type(got) ~= "table" then return nil, "no tape in the file" end
    if got.version ~= M.VERSION then return nil, "tape version " .. tostring(got.version) end
    local tape = M.new()
    for who, turn in pairs(got.turns or {}) do
        if (type(who) == "string") and (type(turn) == "table") and (#turn > 0) then
            local good = true
            for _, d in ipairs(turn) do
                if not decideOk(d) then good = false end
            end
            if good then tape.turns[who] = turn end
        end
    end
    -- A wheel saved by an older build is not read: the wheel is the player's.
    return tape
end

-- For the log: who has a turn.
function M.summary(tape)
    local names = {}
    for who in pairs((tape and tape.turns) or {}) do names[#names + 1] = who end
    table.sort(names)
    return string.format("%d turn%s (%s)", #names, (#names == 1) and "" or "s",
        (#names > 0) and table.concat(names, ", ") or "nobody")
end

return M

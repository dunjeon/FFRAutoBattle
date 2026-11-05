-- FFRProbe, dump only. No fight hooks and no battle objects. 20 seconds after
-- launch it writes every loaded DataTable to gamedata_<table>.txt, one table
-- every fifth of a second. It reads only numbers, text, enums, and the structs
-- and lists made of them; object links are left alone. A table that was being
-- read when the game went down is skipped next launch, and a finished one
-- isn't read again. Installed as FFRProbe/Scripts/main.lua.

local function modDir()
    local info = debug and debug.getinfo and debug.getinfo(1, "S")
    local src = ((info and info.source) or ""):gsub("^@", ""):gsub("\\", "/")
    return src:match("^(.*)/Scripts/[^/]+$") or "ue4ss/Mods/FFRProbe"
end
local DIR = modDir()
local function say(fmt, ...) print("[FFRProbe] " .. string.format(fmt, ...) .. "\n") end

local okF, Fields = pcall(dofile, DIR .. "/Scripts/fields.lua")
if not okF then
    say("fields.lua failed: %s", tostring(Fields))
    return
end

local function unwrap(v)
    if type(v) == "userdata" or (type(v) == "table" and type(rawget(v, "get")) == "function") then
        local ok, inner = pcall(function() return v:get() end)
        if ok and inner ~= nil then return inner end
    end
    return v
end

local SCALAR = { int32 = true, int16 = true, int8 = true, int64 = true, uint8 = true, uint16 = true, uint32 = true,
    uint64 = true, float = true, double = true, bool = true }
local TEXT = { FName = true, FText = true, FString = true }

local function fieldsOf(struct)
    local out, n, guard = {}, struct, 0
    while n and Fields[n] and guard < 8 do
        for _, f in ipairs(Fields[n]) do out[#out + 1] = f end
        n = Fields[n].base
        guard = guard + 1
    end
    return out
end

local function isEnum(ty) return ty:match("^e[A-Z]") ~= nil or ty:match("^E[A-Z]") ~= nil end

local flat
flat = function(v, ty, path, w, depth)
    if depth > 6 then return end
    if SCALAR[ty] or isEnum(ty) then
        v = unwrap(v)
        local t = type(v)
        if t == "number" or t == "boolean" then w(path, tostring(v)) end
        return
    end
    if TEXT[ty] then
        v = unwrap(v)
        if type(v) == "string" then
            w(path, v)
            return
        end
        local ok, text = pcall(function() return v:ToString() end)
        if ok and text then w(path, tostring(text)) end
        return
    end
    if Fields[ty] then
        v = unwrap(v)
        for _, f in ipairs(fieldsOf(ty)) do
            local ok, sub = pcall(function() return v[f[1]] end)
            if ok then flat(sub, f[2], path .. "." .. f[1], w, depth + 1) end
        end
        return
    end
    local inner = ty:match("^TArray<%s*(.-)%s*>$")
    if inner and (SCALAR[inner] or TEXT[inner] or isEnum(inner) or Fields[inner]) then
        v = unwrap(v)
        pcall(function()
            local i = 0
            v:ForEach(function(_, e)
                i = i + 1
                if i > 256 then return true end
                flat(e, inner, path .. "[" .. i .. "]", w, depth + 1)
            end)
        end)
        return
    end
    local mapV = ty:match("^TMap<.-,%s*(.-)%s*>$")
    if mapV and (SCALAR[mapV] or TEXT[mapV] or isEnum(mapV)) then
        v = unwrap(v)
        pcall(function()
            v:ForEach(function(a, b)
                flat(b, mapV, path .. "[" .. tostring(unwrap(a)) .. "]", w, depth + 1)
            end)
        end)
    end
end

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
local function nameOf(o)
    local ok, n = pcall(function() return o:GetFName():ToString() end)
    return ok and n or nil
end

local donePath, skipPath, nowPath = DIR .. "/dump_done.txt", DIR .. "/dump_skip.txt", DIR .. "/dump_now.txt"

local function inGame(ms, fn)
    if ExecuteInGameThreadWithDelay then
        ExecuteInGameThreadWithDelay(ms, fn)
    else
        ExecuteWithDelay(ms, function() ExecuteInGameThread(fn) end)
    end
end

local function start()
    local ok, tables = pcall(function() return FindAllOf("DataTable") end)
    if not ok or type(tables) ~= "table" then
        say("dump: no tables yet")
        return
    end
    for name in pairs(linesOf(nowPath)) do
        note(skipPath, "a", name .. "\n")
        os.remove(DIR .. "/gamedata_" .. name .. ".txt")
        say("dump: skipping %s, it was being read at the last stop", name)
    end
    os.remove(nowPath)
    local finished, skipped = linesOf(donePath), linesOf(skipPath)
    local queue, i, done = {}, 0, 0
    for _, dt in ipairs(tables) do
        local name = nameOf(dt)
        if name and (not finished[name]) and (not skipped[name]) then queue[#queue + 1] = dt end
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
            if not dt:IsValid() then return end
            local st = dt:GetRowStruct()
            if not (st and st:IsValid()) then return end
            local name, sname = nameOf(dt), nameOf(st)
            note(nowPath, "w", name .. "\n")
            local f = io.open(DIR .. "/gamedata_" .. name .. ".txt", "w")
            if not f then return end
            f:write("struct ", sname, "\n")
            local w = function(k, v) f:write("  ", k, " = ", v, "\n") end
            dt:ForEachRow(function(key, row)
                f:write("row ", tostring(key), "\n")
                pcall(flat, row, "F" .. sname, "", w, 0)
            end)
            f:close()
            note(donePath, "a", name .. "\n")
            os.remove(nowPath)
            done = done + 1
        end)
        if not okT then say("dump: table failed: %s", tostring(err)) end
        inGame(200, nextTable)
    end
    nextTable()
end

inGame(20000, start)
say("loaded. probe v2.0 (dump only)")

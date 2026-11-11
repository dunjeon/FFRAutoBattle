-- How fast a fight runs when Turbo is on. The marks and the command-select
-- speed come from the battle general row. This file does not touch the
-- battle libraries, and it does not name a fight.

local M = {}

-- The fastest mark on the battle speed button. A missing list is nil.
function M.fastest(marks)
    local best = nil
    if type(marks) ~= "table" then return nil end
    for i = 1, #marks do
        local n = tonumber(marks[i])
        if n and (n > 0) and ((not best) or (n > best)) then best = n end
    end
    return best
end

-- Actions run at four times the fastest mark, past the last button.
-- The command menu uses the game's command-select speed, so the plan still
-- has the wait it has now. A scene the skip is watching stays at 1, the
-- unsped rate, the same way the game holds a Limit, a Vision finish, and a
-- summon at normal speed. Returns nil when the marks were not read.
function M.rate(marks, command, menuOpen, scene)
    if scene then return 1 end
    if menuOpen then
        local c = tonumber(command)
        if c and (c > 0) then return c end
        return 1
    end
    local fast = M.fastest(marks)
    if not fast then return nil end
    return fast * 4
end

-- The game put its own speed back over the rate turbo holds. The battle
-- speed manager writes the world speed itself after a hit pause and a
-- sequence, and turbo only wrote when its own rate changed, so the game's
-- mark won. A slow under 1, a hit pause, is the game's to keep.
function M.taken(now, rate)
    now, rate = tonumber(now), tonumber(rate)
    if not (now and rate) then return false end
    if math.abs(now - rate) < 0.01 then return false end
    return now >= 0.99
end

return M

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

-- Actions run at twice the fastest mark, past the last button.
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
    return fast * 2
end

return M

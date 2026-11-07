-- Experience at the end of a fight, per character.
-- A monster at or above that character's level keeps the game's own payout.
-- When every monster is under that character, the gain is 0.
-- This file does not name a fight, a character, or a Vision, and it does not
-- touch the battle libraries.

local M = {}

-- true: leave the game's exp. false: the gain is 0. nil: do not touch it.
function M.keeps(level, mobs)
    if type(level) ~= "number" then return nil end
    if type(mobs) ~= "table" or #mobs == 0 then return nil end
    for i = 1, #mobs do
        local mob = mobs[i]
        if type(mob) ~= "table" or type(mob.level) ~= "number" then return nil end
        if mob.level >= level then return true end
    end
    return false
end

function M.apply(before, after, keeps)
    if type(before) ~= "number" or type(after) ~= "number" then return after end
    if keeps ~= false then return after end
    if after <= before then return after end
    return before
end

-- The result row when the gain is 0. A kept payout is left as the game wrote it.
function M.row(beforeLevel, beforeExp, afterLevel, afterExp, keeps)
    if keeps ~= false then
        return { afterExp = afterExp, afterLevel = afterLevel, clear = false }
    end
    return { afterExp = beforeExp, afterLevel = beforeLevel, clear = true }
end

return M

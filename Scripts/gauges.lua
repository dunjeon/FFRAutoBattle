-- Working-gauge rise, for a gauge the game gives no live reading of. The planner
-- calls this. This file does not name a fight, a character, or a Vision.
-- The hits poured were not enough to break it, so it is larger than that.

local M = {}

function M.rise(book, poured)
    local base = tonumber(book) or 0
    if base < 1 then base = 100 end
    local filled = tonumber(poured) or 0
    if filled < 0 then filled = 0 end
    local proved = math.floor(filled + 0.5) + 1
    if proved < (base + 1) then proved = base + 1 end
    return proved
end

return M

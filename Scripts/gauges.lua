-- Working-gauge rise. The planner calls this when the live BreakPoint was
-- missing and the book called a break the game did not give. The working
-- gauge is the stagger this fight has already poured, plus one, and at least
-- one past the book's size. It does not invent a larger gauge from a ratio.

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

-- Working-gauge rise. The planner calls this. This file does not name a
-- fight, a character, or a Vision, and it does not touch the battle libraries.
--
-- A missed bonus used to set the gauge to the poured stagger divided by 0.72.
-- That jump could more than double the book and pull equal gauges onto the
-- adds plan. One release now stops at a quarter over the book. If the hits
-- already poured are higher than that, the gauge is that stagger plus one,
-- so the count is not instantly full again.

local ROOM = 0.25

local M = {}

function M.rise(book, poured)
    local base = tonumber(book) or 0
    if base < 1 then base = 100 end
    local filled = tonumber(poured) or 0
    if filled < 0 then filled = 0 end
    local cap = base + math.floor((base * ROOM) + 0.5)
    if cap < (base + 1) then cap = base + 1 end
    local guess = math.floor((filled / 0.72) + 0.5)
    if guess < (base + 1) then guess = base + 1 end
    local proved = math.floor(filled + 0.5) + 1
    if proved < (base + 1) then proved = base + 1 end
    local grown = guess
    if grown > cap then grown = cap end
    if grown < proved then grown = proved end
    return grown
end

return M

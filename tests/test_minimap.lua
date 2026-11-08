-- lua5.4 tests/test_minimap.lua
local M = dofile("Scripts/minimap.lua")
local fails = 0
local function check(ok, msg)
    print((ok and "ok   " or "FAIL ") .. msg)
    if not ok then fails = fails + 1 end
end
local function near(a, b) return a and math.abs(a - b) < 1e-9 end

local view = { x = 1920, y = 1080 }
check(near(M.scaleFor({ x = 272, y = 272 }, view, 0.8, 1), 0.8 * 1080 / 272), "a square map fills the screen height")
check(near(M.scaleFor({ x = 272, y = 136 }, { x = 400, y = 1080 }, 0.8, 1), 0.8 * 400 / 272), "a narrow screen limits by width")
check(near(M.scaleFor({ x = 544, y = 544 }, view, 0.8, 2), 2 * 0.8 * 1080 / 544), "the current scale is carried")
check(M.scaleFor({ x = 2000, y = 2000 }, view, 0.8, 1) == 1, "a map already larger is not shrunk")
check(M.scaleFor(nil, view, 0.8, 1) == nil, "no size means the caller's fallback")
check(M.scaleFor({ x = 0, y = 272 }, view, 0.8, 1) == nil, "an unmeasured map means the fallback")
check(M.scaleFor({ x = 272, y = 272 }, nil, 0.8, 1) == nil, "no screen size means the fallback")

check(M.fraction(80) == 0.8, "MapSize is a percent")
check(M.fraction("95") == 0.95, "MapSize read from the ini as text")
check(M.fraction(nil) == 0.8, "a missing MapSize is 80")
check(M.fraction(5) == 0.8, "too small falls back")
check(M.fraction(150) == 0.8, "too large falls back")

check(M.isOn() == false, "starts off")

local saved = { scale = 1, set = 3.2 }
check(M.rescale(saved, 3.2) == nil, "a map still at its large scale is left alone")
local base, big = M.rescale(saved, 1)
check(base == 1 and near(big, 3.2), "a reset to the old scale is raised again")
base, big = M.rescale(saved, 1.5)
check(base == 1.5 and near(big, 4.8), "a new game scale keeps the same ratio")
check(M.rescale(saved, nil) == nil, "an unread scale is left alone")
check(M.rescale({ scale = 0, set = 3 }, 1) == nil, "a broken record is left alone")

os.exit(fails == 0 and 0 or 1)

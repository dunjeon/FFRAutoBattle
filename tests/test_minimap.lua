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

check(M.pressCounts(true, true), "a press with the field in front before and now is the map's")
check(not M.pressCounts(false, true), "a press as a menu closes is the menu's")
check(not M.pressCounts(true, false), "a press as a menu opens is the menu's")
check(not M.pressCounts(nil, true), "no read before the press is not in front")
check(not M.pressCounts(true, nil), "an unread field is not in front")

local function fresh()
    return { down = false, armed = false, ready = true, idle = 2 }
end

local g = fresh()
check(M.gesture(true, true, true, g) == nil and g.armed, "a press on the field arms and does not toggle")
check(M.gesture(true, true, true, g) == nil and g.armed, "holding the trigger does not toggle")
check(M.gesture(false, true, true, g) == "toggle" and not g.armed, "letting go on the field toggles")
check(M.gesture(true, true, true, g) == nil and M.gesture(false, true, true, g) == "toggle", "a second pull toggles again")

g = fresh()
check(M.gesture(true, false, false, g) == nil and not g.armed, "a press in a menu does not arm")
check(M.gesture(false, true, true, g) == "ignore", "letting go on the field after a menu press does not toggle")

g = fresh()
check(M.gesture(true, true, false, g) == nil and not g.armed and not g.ready, "a press as a menu opens does not arm")
check(M.gesture(false, true, true, g) == "ignore", "letting go after that press does not toggle")

g = fresh()
check(M.gesture(true, false, true, g) == nil and not g.armed, "a press as a menu closes does not arm")
check(M.gesture(false, true, true, g) == "ignore", "letting go after a menu-close press does not toggle")

-- Held on the field, kept down through the menu, let go after it closes.
g = fresh()
local toggled = false
local function pull(down, was, front)
    local act = M.gesture(down, was, front, g)
    if act == "toggle" then toggled = true end
    return act
end
check(pull(true, true, true) == nil, "the hold starts on the field")
check(pull(true, true, true) == nil, "the hold stays down")
check(pull(true, true, false) == nil, "the menu opens while the trigger is held")
check(pull(true, false, false) == nil, "the menu stays open")
check(pull(true, false, true) == nil, "the menu closes and the trigger is still held")
check(pull(false, true, true) == "ignore" and not toggled, "letting go after that hold does not toggle")

-- The menu stopped reporting the trigger, then the field read it down again.
g = fresh()
toggled = false
check(pull(true, true, true) == nil, "a held trigger is armed on the field")
check(pull(false, true, false) == "ignore", "the menu hides the trigger")
check(pull(false, false, true) == nil and not g.ready, "one up read on the field does not arm the next press")
check(pull(true, true, true) == nil and not g.armed, "the trigger reading down again is not a new press")
check(pull(false, true, true) == "ignore" and not toggled and g.ready, "letting go of that hold does not toggle")
check(pull(true, true, true) == nil and g.armed, "a new press after letting go on the field arms")
check(pull(false, true, true) == "toggle", "letting go of the new press toggles")

-- After a menu the trigger must be up on the field for two polls.
g = fresh()
toggled = false
check(pull(false, true, false) == nil and not g.ready, "a menu clears a ready trigger")
check(pull(false, false, true) == nil and not g.ready, "one poll up on the field is not ready yet")
check(pull(true, true, true) == nil and not g.armed, "a press on that next poll does not arm")
check(pull(false, true, true) == "ignore", "that press lets go without toggling")
g = fresh()
check(M.gesture(false, true, false, g) == nil, "the menu is open again")
check(M.gesture(false, false, true, g) == nil and not g.ready, "the first poll back on the field")
check(M.gesture(false, true, true, g) == nil and g.ready, "the second poll up on the field is ready")
check(M.gesture(true, true, true, g) == nil and g.armed, "a press then arms")
check(M.gesture(false, true, true, g) == "toggle", "and letting go toggles")

g = fresh()
check(M.gesture(nil, true, true, g) == nil and not g.down, "an unread trigger changes nothing")
check(M.gesture(false, true, nil, g) == nil and not g.ready, "an unread field is not in front")
check(M.gesture(true, true, nil, g) == nil and not g.armed, "a press with the field unread does not arm")

-- A menu seen only while the trigger was unread still clears the hold.
g = fresh()
check(M.gesture(true, true, true, g) == nil and g.armed, "a pull on the field arms")
check(M.gesture(nil, true, false, g) == nil and not g.armed and not g.ready, "a menu with the trigger unread clears the arm")
check(M.gesture(nil, false, true, g) == nil and g.down, "the menu closes, the trigger still unread")
check(M.gesture(false, true, true, g) == "ignore", "letting go after that menu does not toggle")

-- An unread trigger on the field keeps the hold.
g = fresh()
check(M.gesture(true, true, true, g) == nil and g.armed, "a pull on the field arms again")
check(M.gesture(nil, true, true, g) == nil and g.armed, "an unread poll on the field keeps the arm")
check(M.gesture(false, true, true, g) == "toggle", "letting go then toggles")

-- fieldActive, with the game's FindAllOf stood in for.
local function hud(name, active, alive)
    local w = { alive = (alive ~= false), active = active }
    function w:IsValid() return self.alive end
    function w:GetFName() return { ToString = function() return name end } end
    function w:IsActivated()
        if self.active == nil then error("cannot ask") end
        return self.active
    end
    return w
end
local function withHuds(list)
    FindAllOf = function() return list end
    return dofile("Scripts/minimap.lua")
end
check(withHuds({ hud("WBP_FieldLayout_C_1", true) }).fieldActive() == true, "an active field HUD is in front")
check(withHuds({ hud("WBP_FieldLayout_C_1", false) }).fieldActive() == false, "a deactivated field HUD (a menu) is not in front")
check(withHuds(nil).fieldActive() == false, "no field HUD at all (a loading screen) is not in front")
check(withHuds({}).fieldActive() == false, "an empty HUD list is not in front")
check(withHuds({ hud("Default__WBP_FieldLayout_C", true) }).fieldActive() == false, "only the class default is not a live HUD")
check(withHuds({ hud("WBP_FieldLayout_C_1", true, false) }).fieldActive() == false, "a HUD that is gone is not in front")
check(withHuds({ hud("WBP_FieldLayout_C_1", nil) }).fieldActive() == true, "a live HUD that cannot be asked still counts, so the button works")
FindAllOf = function() error("no UE4SS") end
check(dofile("Scripts/minimap.lua").fieldActive() == true, "a HUD list that cannot be read still counts")

-- A load while the trigger is held: the old HUD is gone, then a new one is built.
local list = { hud("WBP_FieldLayout_C_1", true) }
local MM = withHuds(list)
g = fresh()
check(MM.gesture(true, true, MM.fieldActive(), g) == nil and g.armed, "a pull on the field arms")
list[1].alive = false
local loadFront = MM.fieldActive()
check(loadFront == false, "the loading screen is not in front")
check(MM.gesture(true, true, loadFront, g) == nil and not g.armed, "the load clears the hold")
FindAllOf = function() return { hud("WBP_FieldLayout_C_2", true) } end
for _ = 1, 10 do loadFront = MM.fieldActive() end
check(loadFront == true, "the new area's HUD is found within ten reads")
check(MM.gesture(false, false, loadFront, g) == "ignore", "letting go after the load does not toggle")
FindAllOf = nil

os.exit(fails == 0 and 0 or 1)

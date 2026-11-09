-- The large field map. One press moves the field minimap to the middle of the
-- screen and draws it larger. The next press puts it back in its corner.
-- Nothing here touches a fight, a save, or a pak file.
--
-- The game's field HUD (WBP_FieldLayout) holds WBP_MiniMapLayout in a
-- full-screen overlay slot set to the right edge, at the top. Inside it,
-- WBP_MiniMap wraps the map in ScaleBox_0, set to a user-given scale. The large
-- map sets that slot to the centre and raises that scale. The scale is a layout
-- scale, so the game redraws the map at the larger size and it stays sharp.

local M = {}

-- Slate alignment values: Fill 0, Left/Top 1, Center 2, Right/Bottom 3.
local CENTER = 2

-- The scale that makes a map of size `desired` fill `fraction` of the screen.
-- desired and view are {x, y} in the same units. `current` is the scale the
-- map is drawn at now, so desired already includes it. Returns nil when a
-- size is missing, so the caller can use its own fallback.
function M.scaleFor(desired, view, fraction, current)
    if type(desired) ~= "table" or type(view) ~= "table" then return nil end
    local dx, dy = tonumber(desired.x), tonumber(desired.y)
    local vx, vy = tonumber(view.x), tonumber(view.y)
    local f = tonumber(fraction)
    local cur = tonumber(current) or 1
    if not (dx and dy and vx and vy and f) then return nil end
    if dx <= 0 or dy <= 0 or vx <= 0 or vy <= 0 or f <= 0 or cur <= 0 then return nil end
    local k = math.min(f * vx / dx, f * vy / dy)
    -- A map already larger than asked is not shrunk.
    if k < 1 then k = 1 end
    return cur * k
end

-- MapSize in config.ini is a percent of the screen. Out of range falls back.
function M.fraction(percent)
    local p = tonumber(percent)
    if not p or p < 20 or p > 100 then return 0.8 end
    return p / 100
end

-- Game glue below. It reads UE4SS globals only when called.

local state = { on = false, touched = {}, lib = nil }

local function valid(o)
    return o ~= nil and o.IsValid and o:IsValid()
end

local function addr(o)
    local ok, a = pcall(function() return o:GetAddress() end)
    if ok and a then return tostring(a) end
    return tostring(o)
end

local function isDefault(o)
    local ok, name = pcall(function() return o:GetFName():ToString() end)
    return ok and type(name) == "string" and name:find("^Default__") ~= nil
end

-- Every live field minimap. A loaded map can leave an old one behind, and a
-- second one costs nothing to resize too.
local function layouts()
    local out = {}
    local ok, all = pcall(function() return FindAllOf("WBP_MiniMapLayout_C") end)
    if not (ok and type(all) == "table") then return out end
    for _, w in ipairs(all) do
        pcall(function()
            if not valid(w) or isDefault(w) then return end
            local map = w.WBP_MiniMap
            local box = valid(map) and map.ScaleBox_0 or nil
            local slot = w.Slot
            if not (valid(box) and valid(slot)) then return end
            out[#out + 1] = { layout = w, box = box, slot = slot, key = addr(w) }
        end)
    end
    return out
end

local function viewSize()
    local lib = state.lib
    if not valid(lib) then
        lib = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary")
        if not valid(lib) then return nil end
        state.lib = lib
    end
    local pc = FindFirstOf("PlayerController")
    if not valid(pc) then return nil end
    local world = pc:GetWorld()
    if not valid(world) then return nil end
    local size = lib:GetViewportSize(world)
    local scale = lib:GetViewportScale(world)
    if not (size and scale and scale > 0) then return nil end
    -- Pixels to the same units as a widget's desired size.
    return { x = size.X / scale, y = size.Y / scale }
end

-- When the game puts its own scale back on a map that was made large, as it
-- does after a conversation, that scale is the new normal one. The map is
-- raised by the same ratio as before. Returns the new normal scale and the
-- large one, or nil when the map is still as it was set.
function M.rescale(saved, current)
    local cur, set, base = tonumber(current), tonumber(saved and saved.set), tonumber(saved and saved.scale)
    if not (cur and set and base) or cur <= 0 or base <= 0 then return nil end
    if math.abs(cur - set) < 1e-4 then return nil end
    return cur, cur * (set / base)
end

local function enlarge(e, fraction)
    local saved = state.touched[e.key]
    if saved then
        local base, target = M.rescale(saved, e.box.UserSpecifiedScale)
        if target then
            saved.scale = base
            saved.set = target
            e.box:SetUserSpecifiedScale(target)
        end
        -- A new HUD can sit at the old one's address. Turning the map off
        -- restores the widget that is live now, not the one that is gone.
        saved.widget = e.layout
        saved.box = e.box
        if e.slot.HorizontalAlignment ~= CENTER then e.slot:SetHorizontalAlignment(CENTER) end
        if e.slot.VerticalAlignment ~= CENTER then e.slot:SetVerticalAlignment(CENTER) end
        return
    end
    saved = {
        h = e.slot.HorizontalAlignment,
        v = e.slot.VerticalAlignment,
        scale = e.box.UserSpecifiedScale,
    }
    local okSize, desired = pcall(function()
        local d = e.layout:GetDesiredSize()
        return { x = d.X, y = d.Y }
    end)
    local okView, view = pcall(viewSize)
    local target = M.scaleFor(okSize and desired or nil, okView and view or nil, fraction, saved.scale)
    -- The map is 256 units plus its frame. A 1080-unit screen is the usual case.
    if not target then target = (tonumber(saved.scale) or 1) * (fraction * 1080 / 272) end
    e.slot:SetHorizontalAlignment(CENTER)
    e.slot:SetVerticalAlignment(CENTER)
    e.box:SetUserSpecifiedScale(target)
    saved.widget = e.layout
    saved.box = e.box
    saved.set = target
    state.touched[e.key] = saved
end

local function restoreAll()
    for key, saved in pairs(state.touched) do
        pcall(function()
            local w = saved.widget
            if not valid(w) then return end
            local slot = w.Slot
            local map = w.WBP_MiniMap
            local box = valid(map) and map.ScaleBox_0 or nil
            if valid(slot) then
                slot:SetHorizontalAlignment(saved.h)
                slot:SetVerticalAlignment(saved.v)
            end
            if valid(box) then box:SetUserSpecifiedScale(saved.scale) end
        end)
        state.touched[key] = nil
    end
end

-- Every frame while the large map is on. A conversation puts the game's own
-- scale back from inside the game's code, where no hook reaches. Only the maps
-- already made large are read here, one number each, so it costs little and
-- the map is small for a frame at most.
function M.hold()
    if not state.on then return end
    for _, saved in pairs(state.touched) do
        local box = saved.box
        if valid(box) then
            local base, target = M.rescale(saved, box.UserSpecifiedScale)
            if target then
                saved.scale = base
                saved.set = target
                box:SetUserSpecifiedScale(target)
            end
        end
    end
end

-- A loaded area builds a new field HUD, and a conversation puts the game's
-- own scale back. While the large map is on, both are made large again,
-- until the player presses again.
function M.keep(fraction, onField)
    if not state.on then return end
    if not onField then return end
    for _, e in ipairs(layouts()) do pcall(enlarge, e, fraction) end
end

-- Returns "on", "off", or nil when there was no field map to change.
-- onField is false in a fight. Turning it off works anywhere, so a large map
-- is never stuck on screen.
function M.toggle(fraction, onField)
    if state.on then
        restoreAll()
        state.on = false
        return "off"
    end
    if not onField then return nil end
    local found = layouts()
    if #found == 0 then return nil end
    for _, e in ipairs(found) do pcall(enlarge, e, fraction) end
    if next(state.touched) == nil then return nil end
    state.on = true
    return "on"
end

function M.isOn() return state.on end

-- True while the field HUD is the screen in front. A menu opened on the field
-- deactivates it, so a pad button that also switches menu tabs is left to the
-- menu. If the game cannot be asked, the answer is true, so the button still works.
function M.fieldActive()
    local ok, all = pcall(function() return FindAllOf("WBP_FieldLayout_C") end)
    if not (ok and type(all) == "table") then return true end
    local asked = false
    for _, w in ipairs(all) do
        local okW, on = pcall(function()
            if not valid(w) or isDefault(w) then return nil end
            return w:IsActivated()
        end)
        if okW and type(on) == "boolean" then
            asked = true
            if on then return true end
        end
    end
    return not asked
end

return M

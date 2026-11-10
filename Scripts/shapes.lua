-- Commands that hold picks. The game lists them in its general skill table
-- (hierarchicalSkills). Choosing one opens a list, and the picks go to the
-- game in the same decide, each under that command as its parent.
--
-- The table does not say how many picks a command holds or which kinds fit.
-- That is learned from a decide the player sent by hand, and kept in
-- shapes.txt so it is known in the next session too. This file does not
-- name a command, a skill, or a character, and it does not touch the game.

local M = {}

-- A hand decide, read into a shape. items: the decide's entries in order,
-- each { actionId, pCat, pId }. keys: the decide's action keys, each
-- { category, id }. isParent(id) is true for a command the game lists.
-- attrOf(id) is the row's attribute. Returns nil when the first entry is
-- not such a command, or when nothing sits under it.
function M.read(items, keys, command, isParent, attrOf)
    if type(items) ~= "table" or #items < 2 then return nil end
    local parent = items[1]
    local pid = parent and tonumber(parent.actionId)
    if not (pid and isParent and isParent(pid)) then return nil end
    local attrs, picks, childCat = {}, 0, nil
    for i = 2, #items do
        local it = items[i]
        if tonumber(it.pId) ~= pid then return nil end
        local a = attrOf and attrOf(tonumber(it.actionId))
        if a == nil then return nil end
        attrs[a] = true
        picks = picks + 1
        childCat = childCat or tonumber(it.pCat)
    end
    keys = keys or {}
    local prefix = {}
    for i = 1, #keys - picks do prefix[#prefix + 1] = { keys[i][1], keys[i][2] } end
    local keyCat = (#keys > 0) and tonumber(keys[#keys][1]) or nil
    return {
        parent = pid, picks = picks, attrs = attrs,
        command = tonumber(command) or -1,
        pCat = tonumber(parent.pCat) or 1, pId = tonumber(parent.pId) or 0,
        childCat = childCat or 1, keyCat = keyCat or 1, prefix = prefix,
    }
end

-- A second hand cast of the same command adds the kinds it showed. A
-- different count means the game changed it, so the new one stands.
function M.merge(old, new)
    if not old then return new end
    if not new then return old end
    if old.picks ~= new.picks then return new end
    for a in pairs(old.attrs or {}) do new.attrs[a] = true end
    return new
end

function M.same(a, b)
    return (a ~= nil) and (b ~= nil) and (M.encode(a) == M.encode(b))
end

local function sortedKeys(set)
    local out = {}
    for k in pairs(set or {}) do out[#out + 1] = k end
    table.sort(out)
    return out
end

-- One line of shapes.txt, after "<parent id>=". No ; or # in it, so the
-- config reader keeps all of it.
function M.encode(s)
    local prefix = {}
    for _, k in ipairs(s.prefix or {}) do prefix[#prefix + 1] = tostring(k[1]) .. "/" .. tostring(k[2]) end
    return string.format("picks:%d attrs:%s command:%d parent:%d/%d child:%d keycat:%d prefix:%s",
        s.picks, table.concat(sortedKeys(s.attrs), ","), s.command, s.pCat, s.pId, s.childCat, s.keyCat,
        table.concat(prefix, ","))
end

function M.decode(id, text)
    local pid = tonumber(id)
    if not (pid and type(text) == "string") then return nil end
    local f = {}
    for k, v in text:gmatch("(%a+):(%S*)") do f[k] = v end
    local picks = tonumber(f.picks)
    if not (picks and picks >= 1) then return nil end
    local attrs = {}
    for a in (f.attrs or ""):gmatch("%-?%d+") do attrs[tonumber(a)] = true end
    if next(attrs) == nil then return nil end
    local pCat, pId = (f.parent or ""):match("^(%-?%d+)/(%-?%d+)$")
    local prefix = {}
    for c, i in (f.prefix or ""):gmatch("(%-?%d+)/(%-?%d+)") do prefix[#prefix + 1] = { tonumber(c), tonumber(i) } end
    return {
        parent = pid, picks = picks, attrs = attrs,
        command = tonumber(f.command) or -1,
        pCat = tonumber(pCat) or 1, pId = tonumber(pId) or 0,
        childCat = tonumber(f.child) or 1, keyCat = tonumber(f.keycat) or 1, prefix = prefix,
    }
end

-- True when a skill of this attribute was seen under the command.
function M.fits(shape, attr)
    return (shape ~= nil) and (attr ~= nil) and (shape.attrs[attr] == true)
end

-- The decide for a command and its picks, in the order the hand decide
-- had them. picks: each { id, menuId, isAll, targets }. Returns the entries
-- and the action keys.
function M.build(shape, uid, picks)
    local entries = {
        { actionId = shape.parent, unit = uid, isAll = false, targets = { uid }, pCat = shape.pCat, pId = shape.pId },
    }
    local keys = {}
    for _, k in ipairs(shape.prefix or {}) do keys[#keys + 1] = { k[1], k[2] } end
    for _, p in ipairs(picks or {}) do
        entries[#entries + 1] = {
            actionId = p.id, unit = uid, isAll = p.isAll and true or false,
            targets = p.targets or {}, pCat = shape.childCat, pId = shape.parent,
        }
        keys[#keys + 1] = { shape.keyCat, p.menuId or p.id }
    end
    return entries, keys
end

return M

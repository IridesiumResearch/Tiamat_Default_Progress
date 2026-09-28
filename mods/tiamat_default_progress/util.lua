-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- Small helpers with no opinion about the game.

local U = {}

--- Units in one item of loose material: an item is a block's worth.
U.UNITS = 27

--- Whether `name` is a qualified id, `"mod:thing"`.
function U.qualified(name)
    return type(name) == "string" and #name <= 128 and string.match(name, "^[%a_][%w_]*:[%w_]+$") ~= nil
end

--- Whether `uuid` looks like a player: a UUID in hex.
function U.player(uuid)
    return type(uuid) == "string" and #uuid <= 64 and string.match(uuid, "^%x+$") ~= nil
end

--- A whole number in lo..hi as an integer, or nil. `20` and `20.0` alike.
function U.whole(n, lo, hi)
    local i = type(n) == "number" and math.tointeger(n) or nil
    if i and i >= lo and i <= hi then return i end
    return nil
end

--- A numeric material id for a qualified block or item id, or nil when nothing
--- registered it. `game.get_block_id` errors on an unknown id, which is right
--- for a typo in this mod's own names and wrong for a block another mod may or
--- may not have registered.
function U.material(id)
    if not U.qualified(id) then return nil end
    local ok, material = pcall(game.get_block_id, id)
    if ok then return material end
    return nil
end

--- Another mod's exports, or nil when it is not loaded.
function U.exports(id)
    local ok, exports = pcall(game.exports, id)
    if ok and type(exports) == "table" then return exports end
    return nil
end

--- A sorted copy of a table's keys.
function U.sorted_keys(t)
    local keys = {}
    for key in pairs(t) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

--- A deep copy of plain data: tables, strings, numbers, booleans.
function U.copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = U.copy(v) end
    return out
end

--- Whether `text` starts with `prefix`.
function U.starts(text, prefix)
    return string.sub(text, 1, #prefix) == prefix
end

--- The short name of a qualified id or a dotted node id, spaces for underscores.
function U.friendly(id)
    local short = string.match(id, "[:%.]([^:%.]+)$") or id
    return (string.gsub(short, "_", " "))
end

--- The same, with a capital: a name for a screen.
function U.title(id)
    local name = U.friendly(id)
    return string.upper(string.sub(name, 1, 1)) .. string.sub(name, 2)
end

--- How many of a mask's 27 bits are set: the cells of a carved block.
function U.cells(mask)
    local n = 0
    for bit = 0, 26 do
        if (mask >> bit) & 1 == 1 then n = n + 1 end
    end
    return n
end

return U

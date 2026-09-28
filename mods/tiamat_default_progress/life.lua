-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- What Life tells this mod: the survival discoveries, and who is a ghost.
--
-- Life keeps the creatures, the food, death and sleep, and says when each
-- happens (`on_kill`, `on_eat`, `on_death`, `on_sleep`). Each is a discovery
-- here: the first kill of each kind of creature and the first taste of each
-- food as families, `kill:*` and `eat:*`, named from what Life reports, so
-- this mod keeps no list of Life's creatures or foods; a first death and a
-- first night slept through once each.
--
-- Without Life none of it is registered, and nobody is a ghost.

local C = tdp.config
local I = tdp.insight
local U = tdp.util

local L = {}

L.api = U.exports(C.life)
if L.api and L.api.version ~= 1 then L.api = nil end

--- Whether a player is a ghost (died in an Adventure world), who may touch nothing.
function L.ghost(uuid)
    return L.api ~= nil and type(L.api.is_ghost) == "function" and L.api.is_ghost(uuid) == true
end

-- Life's own answer to the world's mode, where it gives one; the world
-- option config.lua read is the same answer without it.
if L.api and type(L.api.mode) == "function" then
    local mode = L.api.mode()
    if type(mode) == "string" then C.mode = mode end
end

--- A qualified id as a family member: `mod:thing` becomes `mod.thing`.
local function member(id)
    return (string.gsub(id, ":", "."))
end

if L.api then
    local S = C.survival
    assert(I.register{ id = "kill:*", insight = S.kill, group = "creatures", label = "%s, hunted" })
    assert(I.register{ id = "eat:*", insight = S.eat, group = "food", label = "%s, tasted" })
    assert(I.register{ id = "life.death", insight = S.death, group = "survival", label = "A first death" })
    assert(I.register{ id = "life.sleep", insight = S.sleep, group = "survival", label = "A night slept through" })

    local function listen(name, fn)
        if type(L.api[name]) ~= "function" then return end
        local ok, why = L.api[name](fn)
        if not ok then game.log("tiamat_default_progress: Life refused " .. name .. ": " .. tostring(why)) end
    end
    listen("on_kill", function(uuid, kind)
        if type(kind) == "string" then I.discover(uuid, "kill:" .. member(kind)) end
    end)
    listen("on_eat", function(uuid, material)
        if type(material) == "string" then I.discover(uuid, "eat:" .. member(material)) end
    end)
    listen("on_death", function(uuid) I.discover(uuid, "life.death") end)
    listen("on_sleep", function(uuid) I.discover(uuid, "life.sleep") end)
end

return L

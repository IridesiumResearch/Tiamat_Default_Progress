-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- Exploration: the first time a player stands in a biome, and the first time
-- they are so deep.
--
-- The engine says when a player's feet cross into another block
-- (`register_on_player_move`), and that is the whole of it: what the world's
-- `biome_under` calls the block they are in now, and how far under the
-- ground it is. Nothing is polled; a player standing still costs nothing.
--
-- The world names its biomes (`biomes()`), so a discovery carries the name a
-- player knows it by and the Discoveries view can show what is left to find;
-- and it measures depth from the ground as generated (`depth_under`), so a
-- mountain's roots are not counted as deep and a valley's floor is not
-- shallow. A world without either still works: biomes are titled from their
-- ids, and depth is counted down from `depth_zero`. Without the world mod
-- there are no biomes to find; the depths still count.

local C = tdp.config
local I = tdp.insight
local U = tdp.util

local E = {}

local world = U.exports(C.world)
local function exported(name)
    return world and type(world[name]) == "function" and world[name] or nil
end
local biome_under = exported("biome_under")
local depth_under = exported("depth_under")

--- Every biome there is to find, as `{ id, name }` in the world's order,
--- or nil when the world does not list them.
E.biomes = nil
do
    local list = exported("biomes") and world.biomes()
    if type(list) == "table" then
        E.biomes = {}
        for _, biome in ipairs(list) do
            if type(biome.id) == "string" and type(biome.name) == "string" and biome.findable ~= false then
                E.biomes[#E.biomes + 1] = { id = biome.id, name = biome.name }
            end
        end
    end
end

local names = {}
for _, biome in ipairs(E.biomes or {}) do names[biome.id] = biome.name end
assert(I.register{ id = "biome:*", insight = C.biome_insight, group = "biomes", names = names })

--- How many biomes there are to find.
function E.biome_count()
    return E.biomes and #E.biomes or C.biome_count
end

--- How far under the ground a place is, in blocks.
local function depth(x, y, z)
    local down = depth_under and depth_under(x, y, z)
    if type(down) == "number" then return down end
    return C.depth_zero - y
end

tdp.on_move(function(event)
    local uuid, x, y, z = event.player, event.x, event.y, event.z
    if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then return end
    if biome_under then
        local biome = biome_under(x, y, z)
        if type(biome) == "string" and string.match(biome, "^[%w_]+$") then
            I.discover(uuid, "biome:" .. biome)
        end
    end
    local down = depth(x, y, z)
    for _, band in ipairs(C.depths) do
        if down >= band.blocks then
            I.discover(uuid, "depth." .. band.blocks)
        end
    end
end)

return E

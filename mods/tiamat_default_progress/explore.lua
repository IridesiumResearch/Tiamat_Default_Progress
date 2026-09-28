-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- Exploration: the first time a player stands in a biome, and the first time
-- they are so deep.
--
-- The engine says when a player's feet cross into another block (engine ask
-- 3, landed as `register_on_player_move`), and that is the whole of it: what
-- the world's `biome_under` calls the block they are in now, and how far
-- down it is. Nothing is polled; a player standing still costs nothing.
--
-- Without the world mod there are no biomes to find; the depths still count.

local C = tdp.config
local I = tdp.insight
local U = tdp.util

local world = U.exports(C.world)
local biome_under = world and type(world.biome_under) == "function" and world.biome_under or nil

tdp.on_move(function(event)
    local uuid, x, y, z = event.player, event.x, event.y, event.z
    if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then return end
    if biome_under then
        local biome = biome_under(x, y, z)
        if type(biome) == "string" and string.match(biome, "^[%w_]+$") then
            I.discover(uuid, "biome:" .. biome)
        end
    end
    local down = C.depth_zero - y
    for _, depth in ipairs(C.depths) do
        if down >= depth.blocks then
            I.discover(uuid, "depth." .. depth.blocks)
        end
    end
end)

return {}

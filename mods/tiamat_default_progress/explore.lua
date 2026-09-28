-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- Exploration: the first time a player stands in a biome, and the first time
-- they are so deep.
--
-- The engine says nothing when a player moves (engine ask 3), so each player
-- is looked at every `explore_every` ticks: where their body is, what the
-- world's `biome_under` calls that place, and how far down it is. At most
-- ONE player is looked at a tick, round-robin, so fifty players cost fifty
-- ticks a sweep rather than fifty looks in one tick. Two engine calls and one
-- export call a look.
--
-- Without the world mod there are no biomes to find; the depths still count.

local C = tdp.config
local I = tdp.insight
local U = tdp.util

local world = U.exports(C.world)
local biome_under = world and type(world.biome_under) == "function" and world.biome_under or nil

local players = {}     -- uuids, in the order they joined
local next_look = {}   -- uuid -> the tick of their next look
local cursor = 1
local tick = 0

tdp.on_join(function(event)
    for _, uuid in ipairs(players) do
        if uuid == event.player then return end
    end
    players[#players + 1] = event.player
    next_look[event.player] = tick
end)

tdp.on_leave(function(event)
    for i, uuid in ipairs(players) do
        if uuid == event.player then
            table.remove(players, i)
            break
        end
    end
    next_look[event.player] = nil
end)

--- Looks at one player now: their biome and their depth.
local function look(uuid)
    local body = game.player_entity(uuid)
    local e = body and game.entity(body)
    if not e then return end
    local x, y, z = math.floor(e.pos.x), math.floor(e.pos.y), math.floor(e.pos.z)
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
end

tdp.on_tick(function(dt)
    tick = tick + (math.tointeger(dt) or 1)
    local n = #players
    if n == 0 then return end
    -- The next player who is due, starting where the last look left off.
    for _ = 1, n do
        if cursor > n then cursor = 1 end
        local uuid = players[cursor]
        cursor = cursor + 1
        if tick >= next_look[uuid] then
            next_look[uuid] = tick + C.explore_every
            look(uuid)
            return
        end
    end
end)

return {}

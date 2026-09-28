-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- The per-player record, and the only file that touches `game.storage`.
--
-- Storage holds scalars, so a record is one key per fact:
--
--     p:<uuid>:insight   integer
--     p:<uuid>:path      "" | "<path id>"
--     p:<uuid>:forked    the clock when they last chose a door
--     n:<uuid>:<node>    true when unlocked
--     d:<uuid>:<disc>    true when discovered
--     s:<uuid>:<mask>    true when a carved shape has been studied
--     m:<uuid>:<node>    true when a node's payback has been paid
--     t:<uuid>:<source>  insight earned from a source, for ever (the pacing
--                        ledger: what paid, measured in real play)
--     clock              ticks the world has run, written now and then
--
-- Every read other mods make — `has` above all, which a gated recipe asks on
-- the tick — is answered from a cache, one table per player, built the first
-- time that player is asked about and written through on every change. It
-- is built from four prefix reads, `keys("n:<uuid>:")` and the rest, so a
-- player's record costs their own keys and nobody else's (engine ask 1,
-- landed). The engine saves only the keys that changed (ask 2, landed), so
-- one key per fact costs what it touches.

local S = {}

local cache = {}   -- uuid -> record

local FAMILIES = {
    n = "nodes",
    d = "found",
    s = "shapes",
    m = "paid",
}

local function int(value)
    return type(value) == "number" and math.tointeger(value) or nil
end

local function blank()
    return { insight = 0, path = nil, forked = nil, nodes = {}, found = {}, shapes = {}, paid = {}, tally = {} }
end

--- Builds a player's record from storage.
local function load(uuid)
    local record = blank()
    record.insight = int(game.storage.get("p:" .. uuid .. ":insight")) or 0
    local path = game.storage.get("p:" .. uuid .. ":path")
    record.path = (type(path) == "string" and path ~= "") and path or nil
    record.forked = int(game.storage.get("p:" .. uuid .. ":forked"))
    local tally = "t:" .. uuid .. ":"
    for _, key in ipairs(game.storage.keys(tally)) do
        local n = int(game.storage.get(key))
        if n then record.tally[string.sub(key, #tally + 1)] = n end
    end
    for letter, family in pairs(FAMILIES) do
        local prefix = letter .. ":" .. uuid .. ":"
        for _, key in ipairs(game.storage.keys(prefix)) do
            local name = string.sub(key, #prefix + 1)
            if name ~= "" and game.storage.get(key) == true then
                record[family][name] = true
            end
        end
    end
    return record
end

--- A player's record, from the cache or storage. Read-only to every other
--- file: they change it through the setters below.
function S.record(uuid)
    local record = cache[uuid]
    if record == nil then
        record = load(uuid)
        cache[uuid] = record
    end
    return record
end

--- Forgets a player's cached record (they left); storage keeps it.
function S.forget(uuid)
    cache[uuid] = nil
end

function S.set_insight(uuid, amount)
    S.record(uuid).insight = amount
    game.storage.set("p:" .. uuid .. ":insight", amount)
end

function S.set_path(uuid, path)
    S.record(uuid).path = path
    game.storage.set("p:" .. uuid .. ":path", path or "")
end

function S.set_forked(uuid, tick)
    S.record(uuid).forked = tick
    game.storage.set("p:" .. uuid .. ":forked", tick)
end

local function flag(prefix, family)
    return function(uuid, name, on)
        on = on ~= false
        S.record(uuid)[family][name] = on or nil
        game.storage.set(prefix .. ":" .. uuid .. ":" .. name, on or nil)
    end
end

S.set_node = flag("n", "nodes")
S.set_found = flag("d", "found")
S.set_shape = flag("s", "shapes")
S.set_paid = flag("m", "paid")

--- Adds `n` to what a player has had from `source`.
function S.add_tally(uuid, source, n)
    local record = S.record(uuid)
    local total = (record.tally[source] or 0) + n
    record.tally[source] = total
    game.storage.set("t:" .. uuid .. ":" .. source, total)
end

--- Wipes a player's whole record.
function S.reset(uuid)
    local record = S.record(uuid)
    for source in pairs(record.tally) do
        game.storage.set("t:" .. uuid .. ":" .. source, nil)
    end
    for letter, family in pairs(FAMILIES) do
        for name in pairs(record[family]) do
            game.storage.set(letter .. ":" .. uuid .. ":" .. name, nil)
        end
    end
    for _, key in ipairs({ "insight", "path", "forked" }) do
        game.storage.set("p:" .. uuid .. ":" .. key, nil)
    end
    cache[uuid] = blank()
end

-- The clock ----------------------------------------------------------------------
--
-- The engine hands a mod no tick count, and the repath cooldown has to
-- survive a restart, so the mod keeps its own: counted every tick, written
-- every `clock_every` ticks. A crash loses at most that many ticks, which
-- shortens a twenty-minute cooldown by five seconds.

-- Read on first use rather than at load: the world is not open while mods load.
local clock = nil
local unsaved = 0

function S.now()
    if clock == nil then clock = int(game.storage.get("clock")) or 0 end
    return clock
end

tdp.on_tick(function(dt)
    local step = math.tointeger(dt) or 1
    clock = S.now() + step
    unsaved = unsaved + step
    if unsaved >= tdp.config.clock_every then
        unsaved = 0
        game.storage.set("clock", clock)
    end
end)

tdp.on_leave(function(event)
    S.forget(event.player)
end)

return S

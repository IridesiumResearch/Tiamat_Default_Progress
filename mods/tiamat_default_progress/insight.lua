-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- Insight, the currency: one whole number per player, never negative.
--
-- Every change goes through `award` — earning, spending, a penalty, an
-- operator's grant — which clamps, writes storage, updates the cache and the
-- HUD. Nothing else in the mod touches a player's insight.
--
-- Discoveries are the once-per-player half of earning: a registry of fixed
-- values this mod and others fill while mods load, and `discover`, which is
-- idempotent. A discovery id ending in `:*` is a FAMILY: the world's biomes
-- are `biome:*`, so any biome the world names is a discovery the first time
-- a player stands in it, without this mod keeping a list of names the world
-- may rename. A family may carry `names`, member to display name, which the
-- world's `biomes()` fills; a member it does not name is titled from its id.

local C = tdp.config
local S = tdp.store
local U = tdp.util

local I = {}

local defs = {}         -- id -> { id, insight, label, group }
local families = {}     -- prefix ("biome") -> { insight, label, group }
local order = {}        -- ids in registration order, for the Discoveries view
local subscribers = {}  -- fn(uuid, id, amount)

-- The HUD -------------------------------------------------------------------------

local flashes = {}      -- uuid -> { text, until }

--- Sends a player's HUD values: their insight, and a line just earned.
function I.show(uuid)
    local record = S.record(uuid)
    local flash = flashes[uuid]
    game.set_hud(uuid, {
        insight = record.insight,
        flash = flash and flash.text or nil,
    })
end

--- Puts a line on the player's HUD for a few seconds.
function I.flash(uuid, text)
    flashes[uuid] = { text = string.sub(text, 1, 64), ends = S.now() + C.flash_ticks }
    I.show(uuid)
end

tdp.on_tick(function()
    local now = S.now()
    for uuid, flash in pairs(flashes) do
        if now >= flash.ends then
            flashes[uuid] = nil
            I.show(uuid)
        end
    end
end)

tdp.on_join(function(event) I.show(event.player) end)
tdp.on_leave(function(event) flashes[event.player] = nil end)

-- Awards ---------------------------------------------------------------------------

--- Changes a player's insight by `amount` (negative to spend), clamped to
--- 0..max. Answers the new total. `reason`, when given, goes on the HUD.
function I.award(uuid, amount, reason)
    local record = S.record(uuid)
    local total = record.insight + amount
    if total < 0 then total = 0 end
    if total > C.max_insight then total = C.max_insight end
    if total ~= record.insight then
        S.set_insight(uuid, total)
    end
    if reason and amount > 0 then
        I.flash(uuid, string.format("+%d  %s", amount, reason))
    else
        I.show(uuid)
    end
    return total
end

function I.of(uuid)
    return S.record(uuid).insight
end

-- Discoveries ------------------------------------------------------------------------

--- `{ id, insight, label?, group? }`. An id ending in `:*` registers a family.
function I.register(spec)
    if not tdp.loading() then return nil, "discoveries are registered while mods load" end
    if type(spec) ~= "table" then return nil, "a discovery is a table" end
    local id = spec.id
    if type(id) ~= "string" or #id > 96 or not string.match(id, "^[%w_][%w_%.:]*%*?$") then
        return nil, "a discovery id is letters, digits, underscores, dots and colons"
    end
    local amount = U.whole(spec.insight, 0, 10000)
    if not amount then return nil, "insight is a whole number, 0 to 10000" end
    if spec.label ~= nil and type(spec.label) ~= "string" then return nil, "a label is a string" end
    local group = type(spec.group) == "string" and string.sub(spec.group, 1, 32) or "other"
    local family = string.match(id, "^(.+):%*$")
    if family then
        if families[family] then return nil, "discovery " .. id .. " is already registered" end
        local names = {}
        if type(spec.names) == "table" then
            for key, name in pairs(spec.names) do
                if type(key) == "string" and type(name) == "string" then names[key] = string.sub(name, 1, 48) end
            end
        end
        families[family] = { insight = amount, label = spec.label, group = group, names = names }
        return true
    end
    if string.find(id, "*", 1, true) then return nil, "only a family ends in :*" end
    if defs[id] then return nil, "discovery " .. id .. " is already registered" end
    defs[id] = { id = id, insight = amount, label = string.sub(spec.label or U.title(id), 1, 64), group = group }
    order[#order + 1] = id
    return true
end

--- A discovery's record — `{ id, insight, label, group }` — by id, for a
--- family's member too, or nil.
function I.def(id)
    if type(id) ~= "string" then return nil end
    local def = defs[id]
    if def then return def end
    local family, member = string.match(id, "^(.-):(.+)$")
    local f = family and families[family]
    if not f or #id > 96 or not string.match(member, "^[%w_%.]+$") then return nil end
    local name = f.names[member] or U.title(member)
    return {
        id = id, insight = f.insight, group = f.group,
        label = string.sub(f.label and string.format(f.label, name) or name, 1, 64),
    }
end

--- Records that a player found `id`. Answers `true` the first time, `false`
--- every time after, and `nil, why` for a discovery nobody registered.
function I.discover(uuid, id)
    local def = I.def(id)
    if not def then return nil, "no discovery " .. tostring(id) end
    local record = S.record(uuid)
    if record.found[id] then return false end
    S.set_found(uuid, id)
    if def.insight > 0 then
        I.award(uuid, def.insight, def.label)
        game.chat_to(uuid, string.format("Discovered: %s (+%d insight)", def.label, def.insight))
    else
        game.chat_to(uuid, "Discovered: " .. def.label)
    end
    for _, fn in ipairs(subscribers) do
        fn(uuid, id, def.insight)
    end
    return true
end

function I.on_discover(fn)
    if not tdp.loading() then return nil, "subscribe while mods load" end
    if type(fn) ~= "function" then return nil, "a subscriber is a function" end
    subscribers[#subscribers + 1] = fn
    return true
end

--- Every registered discovery, in the order it was registered.
function I.list()
    local out = {}
    for i, id in ipairs(order) do out[i] = defs[id] end
    return out
end

--- The families, as `{ prefix, insight, group }`, sorted by prefix.
function I.families()
    local out = {}
    for _, prefix in ipairs(U.sorted_keys(families)) do
        out[#out + 1] = { prefix = prefix, insight = families[prefix].insight, group = families[prefix].group }
    end
    return out
end

-- This mod's own ---------------------------------------------------------------------

for _, spec in ipairs(C.discoveries) do
    assert(I.register(spec))
end
for _, depth in ipairs(C.depths) do
    assert(I.register{
        id = "depth." .. depth.blocks, insight = depth.insight, group = "depths",
        label = string.format("%d blocks down", depth.blocks),
    })
end

return I

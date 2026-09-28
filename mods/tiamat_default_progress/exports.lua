-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- What other mods may call: the table `game.exports("tiamat_default_progress")`
-- answers to a mod that lists this one in `depends` or `optional_depends`.
-- docs/exports.md is the list, and changes in the same commit as this file.
--
-- The readers this is built for: Craft asks `has` through its gate; the
-- path mods register their paths and nodes and read `effects_of`; any mod
-- that sees a player do something new reports it with `discover` or `award`.
--
-- # Every function here runs in THIS mod's sandbox
--
-- An error in one would disable this mod because another passed it the wrong
-- thing, so none of them raise: they check what they are given and answer
-- `nil` and a reason. Each is also run under `pcall`, so a fault of this
-- mod's own is logged and answered the same way. A callback passed IN is the
-- caller's, and faults on the caller (the engine's rule), so none is wrapped.
--
-- Bump `version` when a change would break a reader, and only then.

local U = tdp.util
local S = tdp.store
local I = tdp.insight
local N = tdp.nodes
local F = tdp.fork
local R = tdp.research

--- `fn` under pcall: a fault here is logged and answered as `nil, why`.
local function safe(name, fn)
    return function(...)
        local result = table.pack(pcall(fn, ...))
        if not result[1] then
            game.log("tiamat_default_progress: export " .. name .. " failed: " .. tostring(result[2]))
            return nil, "tiamat_default_progress could not do that"
        end
        return table.unpack(result, 2, result.n)
    end
end

--- A node as plain data another mod may keep.
local function public_node(node)
    local requires, effects = {}, {}
    for i, r in ipairs(node.requires) do requires[i] = r end
    for i, e in ipairs(node.effects) do effects[i] = { e[1], e[2] } end
    return {
        id = node.id, path = node.path, tier = node.tier, cost = node.cost,
        requires = requires, label = node.label, text = node.text, effects = effects,
    }
end

local NOT_A_PLAYER = "a player is a UUID in hex"

return {
    version = 1,

    -- The question ---------------------------------------------------------------

    --- Whether a player holds a node. A node of the other path is never held.
    has = safe("has", function(uuid, node)
        if not U.player(uuid) or type(node) ~= "string" then return false end
        return N.has(uuid, node)
    end),

    --- The player's side of the Fork: a path id, or nil before it.
    path = safe("path", function(uuid)
        if not U.player(uuid) then return nil end
        return S.record(uuid).path
    end),

    --- A player's insight.
    insight = safe("insight", function(uuid)
        if not U.player(uuid) then return nil, NOT_A_PLAYER end
        return I.of(uuid)
    end),

    --- Every node a player holds would change `prefix`'s numbers by this much:
    --- `{ ["craft.mould_pours"] = 2 }`. Read it when the number is used.
    effects_of = safe("effects_of", function(uuid, prefix)
        if not U.player(uuid) then return nil, NOT_A_PLAYER end
        if prefix ~= nil and type(prefix) ~= "string" then return nil, "a prefix is a string" end
        return N.effects_of(uuid, prefix)
    end),

    -- Earning --------------------------------------------------------------------

    --- Gives (or, negative, takes) insight: a milestone, a reward. Answers the
    --- new total. `reason` goes on the player's HUD.
    award = safe("award", function(uuid, amount, reason)
        if not U.player(uuid) then return nil, NOT_A_PLAYER end
        local n = U.whole(amount, -1000000, 1000000)
        if not n then return nil, "an amount is a whole number" end
        if reason ~= nil and type(reason) ~= "string" then return nil, "a reason is a string" end
        return I.award(uuid, n, reason and string.sub(reason, 1, 48), "milestone")
    end),

    --- `{ id, insight, label?, group? }`, while mods load. An id ending in
    --- `:*` is a family: any `<prefix>:<name>` is then a discovery.
    register_discovery = safe("register_discovery", function(spec) return I.register(spec) end),

    --- A player found something: `true` the first time, `false` after.
    discover = safe("discover", function(uuid, id)
        if not U.player(uuid) then return nil, NOT_A_PLAYER end
        return I.discover(uuid, id)
    end),

    --- Whether a player has found something.
    discovered = safe("discovered", function(uuid, id)
        if not U.player(uuid) or type(id) ~= "string" then return false end
        return S.record(uuid).found[id] == true
    end),

    --- `{ id, name?, inputs, ticks, insight }`: a study at the research table,
    --- `id` qualified with your mod's id. A Craft recipe that makes nothing.
    register_study = safe("register_study", function(spec) return R.register(spec) end),

    -- The graph ------------------------------------------------------------------

    --- `{ id, tier, cost?, requires?, label?, text?, effects?, on_unlock? }`,
    --- while mods load. `id` is `<path>.<name>`.
    register_node = safe("register_node", function(spec) return N.register(spec) end),

    --- Spends a player's insight on a node: `true`, or `nil` and why.
    unlock = safe("unlock", function(uuid, node)
        if not U.player(uuid) then return nil, NOT_A_PLAYER end
        return N.unlock(uuid, node)
    end),

    --- Whether a player could unlock a node now: `true`, or `nil` and why.
    can_unlock = safe("can_unlock", function(uuid, node)
        if not U.player(uuid) then return nil, NOT_A_PLAYER end
        return N.can(uuid, node)
    end),

    --- Every usable node, by tier, as plain data.
    nodes = safe("nodes", function()
        local out = {}
        for i, node in ipairs(N.list()) do out[i] = public_node(node) end
        return out
    end),

    -- The Fork -------------------------------------------------------------------

    --- `{ id, label?, door, recipe?, sentence?, refusal?, on_choose? }`, while
    --- mods load.
    register_path = safe("register_path", function(spec) return F.register_path(spec) end),

    --- Every path, as `{ id, label, door }`.
    paths = safe("paths", function()
        local out = {}
        for i, path in ipairs(F.list()) do out[i] = { id = path.id, label = path.label, door = path.door } end
        return out
    end),

    -- Subscribers ----------------------------------------------------------------

    --- `fn(uuid, node)` whenever a player gains a node.
    on_unlock = safe("on_unlock", function(fn) return N.on_unlock(fn) end),
    --- `fn(uuid, discovery, insight)` the first time a player finds something.
    on_discover = safe("on_discover", function(fn) return I.on_discover(fn) end),
    --- `fn(uuid, path)` when a player chooses at the Fork.
    on_fork = safe("on_fork", function(fn) return F.on_fork(fn) end),
    --- `fn(uuid, old, new)` when a player changes path (a world with `repath`).
    on_repath = safe("on_repath", function(fn) return F.on_repath(fn) end),
}

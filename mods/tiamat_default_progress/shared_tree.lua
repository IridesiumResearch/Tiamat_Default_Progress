-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- The shared tree, tiers 0 to 2: what every player climbs before the Fork.
--
-- **Shared nodes refine; they do not gate.** A player with no insight can
-- smelt bronze; a player who researched smelts it better. That keeps Craft's
-- loop whole and gives insight a use long before the Fork. What each node
-- does is its `effects` (config.lua), integer deltas Craft reads live
-- through `effects_of` when it performs a recipe, burns fuel or charges wear
-- (sibling ask C2). Two exceptions, both deliberate:
--
-- - `shared.keystone` gates the Keystone recipe in every world, because the
--   Keystone IS the Fork (fork.lua);
-- - a world made with `shared_gates` on gates three families of Craft's own
--   recipes behind kiln lore, bellows and tempering: a slower game, led by
--   research (sibling ask C1).

local C = tdp.config
local N = tdp.nodes
local S = tdp.store
local I = tdp.insight
local K = tdp.craft

for _, spec in ipairs(C.shared) do
    local ok, why = N.register(spec, game.mod_id)
    if not ok then error("shared node " .. tostring(spec.id) .. ": " .. why) end
end

-- Paybacks: the first time a node's lesson is used, a little back.
K.on_crafted(function(uuid, recipe_id)
    for _, payback in ipairs(C.paybacks) do
        if recipe_id == payback.recipe and N.has(uuid, payback.node) and not S.record(uuid).paid[payback.node] then
            S.set_paid(uuid, payback.node)
            local node = N.node(payback.node)
            I.award(uuid, payback.insight, node and node.label or payback.node)
        end
    end
end)

-- The shared gates, in a world that asked for them. Craft's own recipes are
-- registered by now (it loads first), so they can be read and gated here —
-- through `set_requires`, which Craft does not export yet (sibling ask C1).
-- Until it does, the option is logged as waiting and changes nothing.
local function gated(recipe, gate)
    if gate.recipes then
        for _, id in ipairs(gate.recipes) do
            if id == recipe.id then return true end
        end
        return false
    end
    if gate.heat and recipe.heat ~= gate.heat then return false end
    if gate.station and recipe.station ~= gate.station then return false end
    return true
end

if C.shared_gates and K.api then
    if type(K.api.set_requires) ~= "function" then
        game.log("tiamat_default_progress: shared_gates is on, and waits on Craft's set_requires (sibling ask C1)")
    else
        local prefix = C.craft .. ":"
        local n = 0
        for _, recipe in ipairs(K.api.recipes() or {}) do
            if tdp.util.starts(recipe.id, prefix) and recipe.requires == nil then
                for _, gate in ipairs(C.gates) do
                    if gated(recipe, gate) then
                        if K.api.set_requires(recipe.id, gate.node) then n = n + 1 end
                        break
                    end
                end
            end
        end
        game.log(string.format("tiamat_default_progress: shared_gates: %d of Craft's recipes gated", n))
    end
end

return {}

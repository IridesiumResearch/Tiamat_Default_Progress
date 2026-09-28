-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- Everything said to and heard from Craft, in one place.
--
-- Craft owns recipes, stations and their job loops; this mod owns what a
-- player knows. So Craft is TOLD: this mod answers its gate (every recipe
-- that `requires` a node asks `has`), and registers the research table, the
-- studies and the Keystone into its registry. And Craft TELLS: `on_first`
-- is the first time a player made something (a discovery), `on_crafted` is
-- every recipe made (a study finishing), `on_tool_broken` a tool worn out.
--
-- Without Craft all of it is skipped: no research table, no Keystone, and
-- nodes can still be bought with insight from wherever else it came.

local C = tdp.config
local I = tdp.insight
local N = tdp.nodes

local K = {}

--- Craft's exports, or nil when Craft is not loaded.
K.api = tdp.util.exports(C.craft)
if K.api and K.api.version ~= 1 then
    game.log("tiamat_default_progress: Craft's exports are version " .. tostring(K.api.version)
        .. ", not 1; working without Craft")
    K.api = nil
end

local crafted = {}   -- fn(uuid, recipe_id, outputs)

--- Runs `fn(uuid, recipe_id, outputs)` after every recipe Craft makes.
function K.on_crafted(fn)
    crafted[#crafted + 1] = fn
end

--- Registers a recipe into Craft, logging (not raising) a refusal. Answers
--- whether Craft took it.
function K.register(spec)
    if not K.api then return false end
    local ok, why = K.api.register(spec)
    if not ok then
        game.log("tiamat_default_progress: Craft refused recipe " .. tostring(spec.id) .. ": " .. tostring(why))
        return false
    end
    return true
end

--- The discoveries a Craft `on_first` event is, by `C.firsts`.
local function discoveries_of(event)
    local out = {}
    for pattern, id in pairs(C.firsts) do
        local prefix = string.match(pattern, "^(.*)%*$")
        if pattern == event or (prefix and tdp.util.starts(event, prefix)) then
            out[#out + 1] = id
        end
    end
    table.sort(out)
    return out
end

if K.api then
    local ok, why = K.api.set_gate(function(uuid, node) return N.has(uuid, node) end)
    if not ok then
        game.log("tiamat_default_progress: could not answer Craft's gate: " .. tostring(why))
    end

    K.api.on_first(function(uuid, event)
        if type(event) ~= "string" then return end
        if event == C.root_event then N.grant(uuid, C.root) end
        for _, id in ipairs(discoveries_of(event)) do
            I.discover(uuid, id)
        end
    end)

    K.api.on_crafted(function(uuid, recipe_id, outputs)
        if type(recipe_id) ~= "string" then return end
        for _, fn in ipairs(crafted) do
            fn(uuid, recipe_id, outputs)
        end
    end)

    K.api.on_tool_broken(function(uuid)
        I.discover(uuid, C.worn_out)
    end)
end

return K

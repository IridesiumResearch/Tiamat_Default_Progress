-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- A stand-in for the magic mod: a path with a door and a recipe for it,
-- nodes of its own — good ones, and one of each kind the graph must refuse —
-- a discovery, and subscribers. `m ...` in chat asks it what it sees.

game.register_block{ id = "attunement_stone" }
local p = game.exports("tiamat_default_progress")
assert(p and p.version == 1, "progress exports version 1")

local chosen, forks, repaths = {}, {}, {}
assert(p.register_path{
    id = "magic", label = "The Attuned", door = "schism_magic:attunement_stone",
    recipe = { inputs = { { "tiamat_default_craft:silver_ingot", count = 4 } } },
    on_choose = function(uuid) chosen[#chosen + 1] = uuid end,
} == true)
-- Refused, not raised.
assert(p.register_path{ id = "magic", door = "schism_magic:attunement_stone" } == nil, "twice")
assert(p.register_path{ id = "shared", door = "schism_magic:attunement_stone" } == nil, "shared is not a path")
assert(p.register_path{ id = "odd", door = "not qualified" } == nil, "a door is qualified")
assert(p.register_path("nonsense") == nil)

assert(p.register_node{ id = "magic.attune", tier = 3, requires = { "shared.fork" }, label = "Attunement",
    effects = { { "magic.mana_max", 10 } } } == true)
assert(p.register_node{ id = "magic.focus", tier = 4, requires = "magic.attune", cost = 150 } == true)
-- Each of these is registered, and disabled when the graph is validated.
assert(p.register_node{ id = "magic.stray", tier = 3 } == true)
assert(p.register_node{ id = "magic.loop_a", tier = 3, requires = { "shared.fork", "magic.loop_b" } } == true)
assert(p.register_node{ id = "magic.loop_b", tier = 3, requires = { "magic.loop_a" } } == true)
assert(p.register_node{ id = "magic.after_loop", tier = 4, requires = { "magic.loop_a" } } == true)
assert(p.register_node{ id = "magic.dangling", tier = 3, requires = { "shared.fork", "magic.nowhere" } } == true)
assert(p.register_node{ id = "shared.leans", tier = 2, requires = { "magic.attune" } } == true)
assert(p.register_node{ id = "ghost.node", tier = 1 } == true)
-- These are refused at once.
assert(p.register_node{ id = "badid", tier = 1 } == nil)
assert(p.register_node{ id = "magic.high", tier = 9 } == nil)
assert(p.register_node{ id = "magic.attune", tier = 3 } == nil)
assert(p.register_node{ id = "magic.fx", tier = 3, effects = { { "x", 0.5 } } } == nil)

assert(p.register_discovery{ id = "magic.first_spark", insight = 6, label = "A first spark", group = "magic" } == true)
assert(p.register_discovery{ id = "magic.first_spark", insight = 6 } == nil)
assert(p.register_study{ id = "schism_magic:study_herb", inputs = { { "tiamat_default_craft:plank", count = 1 } },
    ticks = 100, insight = 3 } ~= false)
assert(p.on_fork(function(uuid, path) forks[#forks + 1] = path end) == true)
assert(p.on_repath(function(uuid, old, new) repaths[#repaths + 1] = old .. ">" .. new end) == true)
assert(p.on_unlock("nope") == nil)
assert(not pcall(function() p.version = 2 end), "the exports are read-only")

game.register_on_chat(function(e)
    local word, rest = string.match(e.text, "^m (%S+)%s*(.*)$")
    if not word then return end
    local say
    if word == "has" then
        say = tostring(p.has(e.player, rest))
    elseif word == "effects" then
        local fx = p.effects_of(e.player, rest ~= "" and rest or nil)
        local keys = {}
        for k in pairs(fx) do keys[#keys + 1] = k end
        table.sort(keys)
        for i, k in ipairs(keys) do keys[i] = k .. "=" .. fx[k] end
        say = table.concat(keys, " ")
    elseif word == "nodes" then
        local list = p.nodes()
        local ids = {}
        for i, n in ipairs(list) do ids[i] = n.id end
        say = #list .. " " .. table.concat(ids, " ")
    elseif word == "chosen" then
        say = string.format("%d|%s|%s", #chosen, table.concat(forks, " "), table.concat(repaths, " "))
    elseif word == "spark" then
        say = tostring(p.discover(e.player, "magic.first_spark"))
    elseif word == "award" then
        say = tostring(p.award(e.player, tonumber(rest), "a test"))
    elseif word == "unlock" then
        local ok, why = p.unlock(e.player, rest)
        say = tostring(ok) .. " " .. tostring(why)
    elseif word == "path" then
        say = tostring(p.path(e.player))
    elseif word == "late" then
        local ok, why = p.register_node{ id = "magic.late", tier = 3, requires = "shared.fork" }
        say = tostring(ok) .. " " .. tostring(why)
    elseif word == "bad" then
        say = tostring(p.has("not hex", "shared.firecraft")) .. " " .. tostring(p.award(e.player, 1.5))
    end
    game.chat_to(e.player, say or "?")
    return false
end)

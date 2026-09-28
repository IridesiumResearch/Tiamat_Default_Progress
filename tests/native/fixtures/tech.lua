-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- A stand-in for the tech mod: the other door, with a refusal of its own,
-- and one node behind the Fork.

game.register_block{ id = "analytical_engine" }
local p = game.exports("tiamat_default_progress")
assert(p.register_path{
    id = "tech", label = "The Engineers", door = "schism_tech:analytical_engine",
    sentence = "The engine turns once, for you alone. This binds you.",
    refusal = "The dials mean nothing to you.",
} == true)
assert(p.register_path{ id = "tech2", door = "schism_tech:analytical_engine" } == nil, "one door, one path")
assert(p.register_node{ id = "tech.steam", tier = 3, requires = "shared.fork", label = "Steam" } == true)

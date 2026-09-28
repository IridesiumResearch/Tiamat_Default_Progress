-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- Tiamat Default Progress: the climb. This file only decides load order.
--
-- Every file below is loaded exactly once and hangs what it exports off the
-- `tdp` global, which the sandbox shares between a mod's own files. The
-- engine's `require` is confined to this directory and does not cache, so a
-- file required twice would run twice; nothing but this file calls it.
--
-- Order matters: config, helpers and the hook fan-out first (everything
-- subscribes to them), then the player record, insight and the graph that
-- everything else reads, then what registers into them and into Craft, then
-- the screens that show all of it, and last the export, which has to be
-- built whole before the registration window closes.

tdp = {}

-- The host reports a failed load as "errored in init.lua" and nothing more,
-- so say which file and what the error was before letting it through.
local function load(name)
    local ok, result = pcall(require, name)
    if not ok then
        game.log(string.format("tiamat_default_progress: %s.lua failed: %s", name, tostring(result)))
        error(result, 0)
    end
    return result
end

tdp.config = load("config")
tdp.util = load("util")
load("hooks")                       -- one engine registration per hook, many subscribers
tdp.store = load("store")           -- the per-player record, cached; the clock
tdp.insight = load("insight")       -- earning and spending; discoveries; the HUD values
tdp.nodes = load("nodes")           -- the graph: register, validate, has, unlock, effects
tdp.craft = load("craft")           -- the gate, and what Craft tells this mod
load("shared_tree")                 -- tiers 0 to 2, and the shared gates
tdp.research = load("research")     -- the research table and the studies
tdp.fork = load("fork")             -- paths, the Keystone, the doors, the lock
load("explore")                     -- biomes and depths, one player a tick
tdp.screens = load("screens")       -- the Research tab, or a dialog
load("commands")                    -- `progress`, and the operator's words

game.register_hud_script("hud.lua")

-- What other mods may call. One export per mod, built whole first.
game.export(load("exports"))

game.log(string.format("tiamat_default_progress ready: %d nodes, %d studies, %s",
    tdp.nodes.count(), #tdp.research.list(), tdp.craft.api and "with Craft" or "without Craft"))

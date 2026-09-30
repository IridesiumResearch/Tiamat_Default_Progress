-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- Every number a designer might want to turn, in one place: what insight
-- each thing is worth, what each node costs and does, what the research
-- table studies and how long it takes. Insight is a whole number; time is
-- TICKS, 20 to a second; quantities are UNITS, 27 to a block and to an item.
--
-- Nothing here shapes the world, so nothing here is a `game.register_setting`.
-- The two rules that must be the same for every player in a world — whether
-- a path may be changed, whether the shared tree gates crafting — are world
-- options, in mod.toml.

local C = {}

-- The mods this one names. Their ids are looked up by name, never copied.
C.world = "tiamat_default_world"
C.craft = "tiamat_default_craft"
C.life = "tiamat_default_life"
C.ui = "tiamat_default_ui"

-- Chat words for testing and for the operator (commands.lua). `progress`
-- alone is for anyone; its subcommands are for operators. This switch
-- removes the subcommands altogether.
C.dev_commands = true

-- The world's mode, from Life: "Default", "Creative" or "Adventure". In a
-- Creative world every shared node is held; the Fork still binds.
C.mode = "Default"
do
    local chosen = game.world_option(C.life .. ":mode")
    if type(chosen) == "string" then C.mode = chosen end
end

-- The two world options (mod.toml). Read once; they never change for a world.
C.repath = game.world_option(game.mod_id .. ":repath") == true
C.shared_gates = game.world_option(game.mod_id .. ":shared_gates") == true

-- The node graph ---------------------------------------------------------------

-- What a node costs when it does not say (Schism's curve), by tier.
C.tier_cost = { [0] = 0, 20, 50, 100, 200, 400, 800, 1500 }
C.max_tier = 7

-- The limits a node registered by another mod is held to.
C.max_requires = 8
C.max_effects = 8
C.max_cost = 100000

-- Insight -------------------------------------------------------------------------

-- The most insight a player can hold. Nothing reaches it in play; it keeps a
-- bad `award` from another mod from overflowing anything.
C.max_insight = 10000000

-- Discoveries: once per player, fixed values. `group` is what the
-- Discoveries view files them under.
C.discoveries = {
    -- First making (Craft's `on_first`, mapped by `C.firsts` below).
    { id = "make.fire", insight = 5, label = "Fire, made by your own hand", group = "making" },
    { id = "make.fireset", insight = 8, label = "Rock cracked by fire", group = "making" },
    { id = "make.smelt_copper", insight = 10, label = "Copper, smelted", group = "making" },
    { id = "make.smelt_tin", insight = 8, label = "Tin, smelted", group = "making" },
    { id = "make.bronze", insight = 12, label = "Bronze, alloyed", group = "making" },
    { id = "make.cast", insight = 10, label = "A first casting", group = "making" },
    { id = "make.wash_tin", insight = 8, label = "Tin washed from gravel", group = "making" },
    { id = "make.wash_gold", insight = 10, label = "Gold washed from gravel", group = "making" },
    { id = "make.bloom", insight = 12, label = "An iron bloom", group = "making" },
    { id = "make.iron_bar", insight = 10, label = "Wrought iron", group = "making" },
    { id = "make.forge", insight = 10, label = "A first forging", group = "making" },
    { id = "make.worn_out", insight = 7, label = "A tool worn to nothing", group = "making" },
    -- First station.
    { id = "station.workbench", insight = 4, label = "A workbench", group = "stations" },
    { id = "station.chest", insight = 4, label = "A chest", group = "stations" },
    { id = "station.kiln", insight = 4, label = "A kiln", group = "stations" },
    { id = "station.bloomery", insight = 4, label = "A bloomery", group = "stations" },
    { id = "station.anvil", insight = 4, label = "A stone anvil", group = "stations" },
    { id = "station.sluice", insight = 4, label = "A sluice", group = "stations" },
    { id = "station.torch", insight = 4, label = "A torch", group = "stations" },
}

-- Craft's `on_first` events (its docs/exports.md), and the discovery each one
-- is. A name ending in `*` matches any event that starts with what comes
-- before it; an event may match more than one line (the first iron bar is
-- also the first forging). Craft keeps these names frozen.
C.firsts = {
    ["fire:lit"] = "make.fire",
    ["fireset:*"] = "make.fireset",
    ["smelt:copper"] = "make.smelt_copper",
    ["smelt:tin"] = "make.smelt_tin",
    ["smelt:bronze"] = "make.bronze",
    ["cast:*"] = "make.cast",
    ["wash:tin"] = "make.wash_tin",
    ["wash:gold"] = "make.wash_gold",
    ["bloom:iron"] = "make.bloom",
    ["forge:iron_bar"] = "make.iron_bar",
    ["forge:*"] = "make.forge",
    ["craft:tiamat_default_craft:workbench"] = "station.workbench",
    ["craft:tiamat_default_craft:chest"] = "station.chest",
    ["fire:kiln"] = "station.kiln",
    ["craft:tiamat_default_craft:bloomery"] = "station.bloomery",
    ["craft:tiamat_default_craft:stone_anvil"] = "station.anvil",
    ["craft:tiamat_default_craft:sluice"] = "station.sluice",
    ["craft:tiamat_default_craft:torch"] = "station.torch",
}

-- The first tool a player wears out (Craft's `on_tool_broken`).
C.worn_out = "make.worn_out"

-- Survival, from Life (life.lua): the first kill of each kind of creature,
-- the first taste of each food, a first death, a first night slept through.
C.survival = { kill = 2, eat = 1, death = 5, sleep = 5 }

-- Exploration (explore.lua). Every biome the world's `biome_under` names is a
-- discovery the first time a player stands in it, worth `biome_insight`.
C.biome_insight = 3
-- How many biomes there are to find, for a world that does not list them
-- with `biomes()`. Only the Discoveries view's "of N" reads it.
C.biome_count = 55

-- Depth: the first time a player is this many blocks under the ground — as
-- the world's `depth_under` measures it, or below `depth_zero` without it.
-- The world's ore levels, so a player sees the ore as they pass it.
C.depth_zero = 0
C.depths = {
    { blocks = 60, insight = 5 },
    { blocks = 200, insight = 8 },
    { blocks = 420, insight = 10 },
    { blocks = 750, insight = 15 },
    { blocks = 1200, insight = 20 },
    { blocks = 2000, insight = 30 },
}

-- Research (research.lua) -------------------------------------------------------

-- The research table, as a Craft station: one input, one output that
-- nothing is ever put in (a study makes insight, not a thing).
C.table_slots = { input = 1, output = 2 }

-- The studies: what the table eats, how long it takes, what it pays. A study
-- recipe's id is `tiamat_default_progress:<id>`.
C.studies = {
    { id = "study_rock", name = "Study rock", input = { "#rock", units = 27 }, ticks = 300, insight = 2 },
    { id = "study_copper", name = "Study copper", input = { "tiamat_default_craft:copper_ingot", count = 1 }, ticks = 600, insight = 10 },
    { id = "study_tin", name = "Study tin", input = { "tiamat_default_craft:tin_ingot", count = 1 }, ticks = 600, insight = 10 },
    -- Iron is bloomed and wrought, never an ingot.
    { id = "study_iron", name = "Study iron", input = { "tiamat_default_craft:iron_bloom", count = 1 }, ticks = 600, insight = 10 },
    { id = "study_bronze", name = "Study bronze", input = { "tiamat_default_craft:bronze_ingot", count = 1 }, ticks = 600, insight = 12 },
    { id = "study_wrought_iron", name = "Study wrought iron", input = { "tiamat_default_craft:iron_bar", count = 1 }, ticks = 900, insight = 20 },
    { id = "study_silver", name = "Study silver", input = { "tiamat_default_craft:silver_ingot", count = 1 }, ticks = 1200, insight = 25 },
    { id = "study_gold", name = "Study gold", input = { "tiamat_default_craft:gold_ingot", count = 1 }, ticks = 1200, insight = 30 },
    { id = "study_lead", name = "Study lead", input = { "tiamat_default_craft:lead_ingot", count = 1 }, ticks = 1200, insight = 20 },
    { id = "study_crystal", name = "Study crystal", input = { "tiamat_default_world:crystal", units = 27 }, ticks = 1200, insight = 30 },
    { id = "study_metal", name = "Study the old metal", input = { "tiamat_default_world:metal", units = 27 }, ticks = 1200, insight = 30 },
    { id = "study_diamond", name = "Study diamond", input = { "tiamat_default_world:diamond", units = 9 }, ticks = 3000, insight = 60 },
    { id = "study_orichalcum", name = "Study orichalcum", input = { "tiamat_default_world:orichalcum", units = 9 }, ticks = 6000, insight = 80 },
}

-- A carved shape, studied from the hand: each distinct 27-cell mask once,
-- up to `shape_cap` of them.
C.shape_insight = 8
C.shape_cap = 20

-- The shared tree (shared_tree.lua) -----------------------------------------------
--
-- A node may carry `icon = "icons/<name>.png"`, a picture in this mod's
-- directory for its tile on the Research tab; none are drawn yet.
--
-- Shared nodes REFINE: a player with no insight can still make bronze. What
-- a node does is `effects`, integer deltas read live by the mod that owns
-- the number (Craft, through `effects_of`); nothing about an effect is ever
-- stored, so retuning one here needs no migration.

C.shared = {
    { id = "shared.firecraft", tier = 0, cost = 0, label = "Firecraft",
      text = "Fire, kept. The root of everything else.", auto = true },
    { id = "shared.fire_setting", tier = 1, cost = 10, requires = { "shared.firecraft" }, label = "Fire-setting",
      text = "A fire against rock cracks it in 400 ticks rather than 600.",
      effects = { { "craft.fireset_ticks", -200 } } },
    { id = "shared.charcoal_clamp", tier = 1, cost = 15, requires = { "shared.firecraft" }, label = "Charcoal clamp",
      text = "A log gives a third more charcoal.",
      effects = { { "craft.charcoal_yield", 3 } } },
    { id = "shared.kiln_lore", tier = 1, cost = 20, requires = { "shared.charcoal_clamp" }, label = "Kiln lore",
      text = "Fuel lasts a quarter as long again in any heat station you light: a kiln, a bloomery, and the rest.",
      effects = { { "craft.fuel_percent", 25 } } },
    { id = "shared.placer_eye", tier = 1, cost = 20, label = "A placer eye",
      text = "The sluice turns up a gold flake every sixth wash, not every ninth.",
      effects = { { "craft.sluice_gold_period", -3 } } },
    { id = "shared.bronze_casting", tier = 1, cost = 20, requires = { "shared.kiln_lore" }, label = "Bronze casting",
      text = "Pour hotter, lose less: a mould takes six pours before it cracks, not four.",
      effects = { { "craft.mould_pours", 2 } } },
    { id = "shared.hafting", tier = 1, cost = 15, label = "Hafting",
      text = "Wooden and bronze tools last a quarter as long again.",
      effects = { { "craft.uses_percent.wood", 25 }, { "craft.uses_percent.bronze", 25 } } },
    { id = "shared.roasting", tier = 2, cost = 40, requires = { "shared.kiln_lore" }, label = "Roasting",
      text = "Roast before you smelt: an ingot of copper, tin or iron takes 18 units of ore, not 27.",
      effects = { { "craft.smelt_ore_units", -9 } } },
    { id = "shared.bellows_craft", tier = 2, cost = 50, requires = { "shared.kiln_lore" }, label = "Bellows",
      text = "A bloomery brings its bloom in 1,800 ticks, not 2,400.",
      effects = { { "craft.bloom_ticks", -600 } } },
    { id = "shared.tempering", tier = 2, cost = 50, requires = { "shared.hafting", "shared.bellows_craft" }, label = "Tempering",
      text = "Iron tools last half as long again.",
      effects = { { "craft.uses_percent.iron", 50 } } },
    { id = "shared.stonewright", tier = 2, cost = 40, label = "Stonewright",
      text = "One strike fewer at the anvil, and a chisel wears half as fast.",
      effects = { { "craft.anvil_strikes", -1 }, { "craft.chisel_wear_percent", -50 } } },
    { id = "shared.keystone", tier = 2, cost = 50, requires = { "shared.roasting", "shared.tempering" }, label = "The Keystone",
      text = "How to make the Keystone: the one thing the shared tree forbids until you know it, because it is the Fork." },
    { id = "shared.fork", tier = 2, cost = 0, requires = { "shared.keystone" }, label = "The Fork",
      text = "Set when you choose a door. Every path's third tier asks for it.", auto = true },
}

-- The root is given the first time a player makes fire (Craft's "fire:lit").
C.root = "shared.firecraft"
C.root_event = "fire:lit"

-- A node that pays back: the first time a player makes `recipe` after
-- unlocking `node`, `insight` more.
C.paybacks = {
    { node = "shared.charcoal_clamp", recipe = "tiamat_default_craft:charcoal", insight = 5 },
}

-- With `shared_gates` on, these Craft recipes need their node first: Craft's
-- own, gated from here through its `set_requires`. A gate names a heat, a
-- station, or a Lua pattern the recipe id must match.
C.gates = {
    { node = "shared.kiln_lore", heat = 2 },
    { node = "shared.bellows_craft", station = "bloomery" },
    { node = "shared.tempering", pattern = "iron_[%w_]*head$" },
}

-- The Fork (fork.lua) ----------------------------------------------------------

-- The Keystone, made at the workbench once `shared.keystone` is held.
C.keystone_station = "workbench"
C.keystone_inputs = {
    { "tiamat_default_world:orichalcum", units = 27 },
    { "tiamat_default_craft:gold_ingot", count = 9 },
    { "tiamat_default_craft:iron_frame", count = 1 },
}
C.keystone_ticks = 200

-- A path's door is made where the Keystone is.
C.door_station = "workbench"
C.door_ticks = 200

-- The sentence a door says when a path does not supply one.
C.sentence = "This binds you. The other door closes."
C.refusal = "This door is not yours."

-- Who hears that somebody chose, in blocks.
C.fork_radius = 32

-- Changing path, when the world allows it: not within this many ticks of the
-- last choice, and at the cost of half one's insight (numerator over
-- denominator of what is KEPT) and every node of the path abandoned.
C.repath_cooldown = 24000
C.repath_keep = { 1, 2 }

-- The screen and the HUD ------------------------------------------------------

C.research_key = "KeyG"
C.tab_order = 40
C.flash_ticks = 60     -- how long a discovery's name stays on the HUD

-- Every change to a player's insight as one line in the server's log, with
-- the clock, the source and the amount: a playtest's pacing, read from the
-- log (docs/pacing.md says how).
C.pacing_log = true

-- How often the world's clock is written to storage, in ticks.
C.clock_every = 100

-- A mod loaded with a table `tdp_overrides` before this file (the test
-- harness does) may change any of the above.
if type(tdp_overrides) == "table" then
    for key, value in pairs(tdp_overrides) do C[key] = value end
end

return C

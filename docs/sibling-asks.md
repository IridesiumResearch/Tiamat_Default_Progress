<!-- SPDX-FileCopyrightText: Iridesium -->
<!-- SPDX-License-Identifier: GPL-3.0-only -->

# Asks of the sibling mods

What this mod needs from the OTHER default mods — Craft, Life, the world and
the interface — as `docs/engine-asks.md` holds what it needs from the
engine. Each says what was wanted, what stands in for it today, and the
smallest change that would answer it. Newest first within each mod.

## Tiamat Default Craft

### C5. A recipe that makes nothing (2026-09-28): OPEN, blocks research

**Wanted.** `register` accepting `outputs = {}` for a recipe whose product is
not a thing: a study at the research table, which makes insight, heard
through `on_crafted`.

**Today.** Craft refuses it ("outputs is a list"), so every study is logged
as refused and the research table takes nothing; insight comes from
discoveries and milestones alone. The table itself, its station and its
recipe are registered and work.

**Smallest change.** Allow an empty `outputs` list (and skip the output
step of `perform` for it). A `conserve` recipe could still refuse it.

### C4. The Keystone's iron frame (2026-09-28): OPEN

**Wanted.** Craft step 10's `iron_frame` keeps that id: the Keystone is
27 units of orichalcum, 9 gold ingots and one `tiamat_default_craft:iron_frame`.

### C3. The first-event names, frozen (2026-09-28): OPEN

**Wanted.** The `on_first` events this mod listens for (`config.lua`,
`C.firsts`) listed and kept in Craft's `docs/exports.md`: `fire:lit`,
`fireset:*`, `smelt:copper`, `smelt:tin`, `smelt:bronze`, `cast:*`,
`fire:kiln`, and, when they land, `wash:tin`, `wash:gold`, `bloom:iron`,
`forge:iron_bar`, `forge:*`, and the recipes `bloomery`, `stone_anvil`,
`sluice` and `torch`. The first seven are in Craft's exports today.

### C2. Reading the effects (2026-09-28): OPEN

**Wanted.** Craft asks `effects_of(uuid, "craft.")` when it performs a
recipe, burns fuel, pours a mould, washes gravel or charges wear, and adds
each delta to its own number: `craft.fireset_ticks`, `craft.charcoal_yield`,
`craft.fuel_percent`, `craft.sluice_gold_period`, `craft.mould_pours`,
`craft.uses_percent.<wood|bronze|iron>`, `craft.smelt_ore_units`,
`craft.bloom_ticks`, `craft.anvil_strikes`, `craft.chisel_wear_percent`.

**Today.** The shared tree's nodes are bought, held and answered by
`effects_of`; until Craft reads them they change nothing.

**Smallest change.** One `effects_of` read at each of those places, with
the missing export (Progress absent) read as no effects.

### C1. Gating a recipe from outside (2026-09-28): OPEN

**Wanted.** `set_requires(recipe_id, node)`, so a world made with
`shared_gates` on can put kiln lore in front of every heat-2 recipe,
bellows in front of the bloomery and tempering in front of the iron heads.

**Today.** The option is logged as waiting and changes nothing.

**Smallest change.** Set the recipe record's `requires` if it has none;
the gate already answers it.

## Tiamat Default Life

### L8. A stat another mod can add (2026-09-28): OPEN, for magic

**Wanted.** `add_stat(id, { max, regen, hud })`, so magic's mana bar (and
tech's charge) is drawn by Life's HUD beside hunger rather than by a second
HUD of magic's own.

### L7. Mode and ghosts, readable (2026-09-28): OPEN

**Wanted.** `mode()` and `is_ghost(uuid)` exported, so a door refuses a
ghost without this mod re-deriving it.

**Today.** The mode is read from Life's world option; ghosts are not seen,
and a ghost could choose at a door.

### L6. Survival events (2026-09-28): OPEN

**Wanted.** `on_kill(fn(uuid, creature))`, `on_death(fn(uuid))`,
`on_eat(fn(uuid, material))`, `on_sleep(fn(uuid))`, for the survival
discoveries (the brief's §3.1: about 51 insight).

**Today.** None of them are discoveries yet.

## Tiamat Default World

### W6. Depth from the surface (2026-09-28): OPEN, nice to have

**Wanted.** How far under the ground a place is, or the world's own depth
bands, exported.

**Today.** A depth is counted down from y = 0 (`C.depth_zero`), which is
right under the sea and wrong under a mountain.

### W5. The biome list (2026-09-28): OPEN

**Wanted.** `biomes()`: every biome id with its display name.

**Today.** A biome is a discovery of the family `biome:*`, named from its id
the first time `biome_under` answers it, and the Discoveries view counts
"of 55" from a number in `config.lua`. With the list, the view could show
the biomes not yet found, under their real names.

## Tiamat Default UI

### U5. A tooltip on a button (2026-09-28): OPEN

**Wanted.** A `hover` text on a button, so a locked node can say what it
requires without a status line.

### U4. `scroll` on a tab (2026-09-28): ANSWERED

The interface copies another mod's tree by FIELD, not by type, so a
`scroll` passes; the Research tab's body is one.

<!-- SPDX-FileCopyrightText: Iridesium -->
<!-- SPDX-License-Identifier: GPL-3.0-only -->

# Asks of the sibling mods

What this mod needs from the OTHER default mods — Craft, Life, the world and
the interface — as `docs/engine-asks.md` holds what it needs from the
engine. Each says what was wanted, what stands in for it today, and the
smallest change that would answer it. Newest first within each mod.

## Tiamat Default Craft

All five answered by Craft on 2026-09-28 (its `docs/sibling-asks.md`), and
its three asks back (P1 to P3) answered here the same day.

### C1 to C5: ANSWERED 2026-09-28

- **C5, a recipe that makes nothing:** accepted; the thirteen studies
  register, and a study made is heard in `on_crafted`.
- **C4, the iron frame:** `tiamat_default_craft:iron_frame`, as asked.
- **C3, the first events:** frozen in Craft's `docs/exports.md`. The names
  `C.firsts` listens for are all among them: `smelt:bronze`, `fire:kiln`,
  `bloom:iron`, `wash:gold`, `craft:tiamat_default_craft:stone_anvil`.
- **C2, the effects:** read where each number is used, through a function
  this mod hands Craft with `set_effects` (P1 below), under the keys this
  mod's nodes already name.
- **C1, gating from outside:** `set_requires(recipe_id, node)`, which
  `shared_gates` now uses.

### Craft's asks of this mod: ANSWERED 2026-09-28

- **P1, hand in `effects_of`:** `craft.lua` calls `set_effects` beside
  `set_gate`.
- **P2, `study_iron` named an ingot that does not exist:** it studies an
  iron bloom; wrought iron is `study_wrought_iron`.
- **P3, the charcoal clamp's sentence:** "A log gives a third more
  charcoal", which is how Craft reads the node's 3.

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

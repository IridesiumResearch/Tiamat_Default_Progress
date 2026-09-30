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

### L6 to L8: ANSWERED 2026-09-28 (Life f405783)

- **L6, survival events:** `on_kill`, `on_eat`, `on_death` and `on_sleep`.
  `life.lua` makes each a discovery: the families `kill:*` and `eat:*`,
  named from what Life reports, and `life.death` and `life.sleep`.
- **L7, mode and ghosts:** `mode()` is read at load; a ghost touching a
  door hears that the dead choose nothing.
- **L8, `add_stat`:** there for magic's mana and tech's charge; nothing in
  this mod uses it.

## Tiamat Default World

### W5 and W6: ANSWERED 2026-09-28 (World 0e5db57)

`biomes()`, `depth_under(x, y, z)` and `depth_band(x, y, z)`. This mod
uses the first two, and falls back where a world lacks them:

- **W5, the biome list:** a biome discovery carries the world's own name,
  and the Discoveries view lists every findable biome, found or not, "of"
  their number. Without it, names come from ids and the count from
  `C.biome_count`.
- **W6, depth from the surface:** depth bands are counted by
  `depth_under`, the ground as generated. Without it (or before the world
  has a seed), down from `C.depth_zero`.

## Tiamat Default UI

### U5. A tooltip on a button: ANSWERED 2026-09-28 (engine 2655837, UI 998b384)

A `tooltip` on any dialog node (the engine), copied through from another
mod's tab (the UI), and `ui.widgets.tip(widget, text)` for a widget built
with the UI's own read-only builders. Every node button here carries one —
what the node does and what it needs — on the Research tab and in the plain
dialog alike. This mod builds its own widget tables, so it needs no `tip`.

### U4. `scroll` on a tab (2026-09-28): ANSWERED

The interface copies another mod's tree by FIELD, not by type, so a
`scroll` passes; the Research tab's body is one.

## Asks of this mod

What the other mods have asked of Progress, and the answers. Newest first.

### P-S2, a study-insight effect (Science): ANSWERED 2026-09-30

Studies read the effect key `progress.study_percent`, summed over every
node the player holds, when they pay: `insight * (100 + percent) // 100`.
Science's Difference Engine carries its bonus as
`science.study_bonus_percent`; under `progress.study_percent` it pays.

### P-M1 and P-S1, a branch label and a reveal rule (Magic, Science): ANSWERED 2026-09-30

- `register_node{ branch = "FIRE" }`: within a tier, the Research tab
  groups a path's nodes by branch, in registration order, each group under
  a small name.
- `register_path{ branches = { FIRE = "The Fire" } }` names the codes.
- `reveal = "near"` on a node, or on the path for all its nodes: shown only
  once all but one of its requirements are held. A held node always shows.
  The rest are counted in one line ("12 more, not yet in sight"), so a
  hundred-node path shows its frontier and the step past it.
- Checked against both paths as they stand: Magic's 97 and Science's 107
  nodes validate on a real server with nothing disabled, and a tier of 15
  to 25 tiles is rows of six, centred, in the tab's scroll.

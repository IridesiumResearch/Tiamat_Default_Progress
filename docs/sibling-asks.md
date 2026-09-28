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

### W5 and W6: BUILT, not yet committed in World (2026-09-28)

`biomes()`, `depth_under(x, y, z)` and `depth_band(x, y, z)` are in the
world's working tree and its `docs/exports.md`. This mod uses the first two
where they exist and falls back where they do not, so it is right before
and after World commits:

- **W5, the biome list:** a biome discovery carries the world's own name,
  and the Discoveries view lists every findable biome, found or not, "of"
  their number. Without it, names come from ids and the count from
  `C.biome_count`.
- **W6, depth from the surface:** depth bands are counted by
  `depth_under`, the ground as generated. Without it, down from
  `C.depth_zero`.

## Tiamat Default UI

### U5. A tooltip on a button: LANDED IN THE ENGINE (2655837); one line in the UI

A `tooltip` on any dialog node. Every node button here carries one — what
the node does and what it needs — and the plain dialog shows it. The UI
copies another mod's tree by a list of fields (`screen.lua`,
`WIDGET_FIELDS`), which does not have `tooltip` yet, so on the Research
tab it is dropped until the UI adds it (its engine ask 15 says it will).

### U4. `scroll` on a tab (2026-09-28): ANSWERED

The interface copies another mod's tree by FIELD, not by type, so a
`scroll` passes; the Research tab's body is one.

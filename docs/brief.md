<!-- SPDX-FileCopyrightText: Iridesium -->
<!-- SPDX-License-Identifier: GPL-3.0-only -->

# Brief

From the designer's two-path design ("Schism", an early version, 2026-09-27),
the parts this mod owns. The engine facts it rests on: registries freeze at
load, so both trees' content is always loaded and the exclusivity is a
per-player rule kept in `game.storage` against the UUID; everything that
reaches the world is integers; the engine holds no recipes and no stats.

## Insight

The currency. Earned three ways:

- **First discoveries** — a fixed table: first time mining each ore, cooking
  each dish, killing each mob, visiting each biome, carving a 27-cell shape,
  reaching a depth. Deterministic and finite, roughly 400 insight in all.
  Ores this mod sees itself (`on_dig_complete` names the material); dishes,
  kills and biomes are reported by Craft, Life and World through
  `grant_insight`, which is an ask to each of them.
- **Research jobs** — the research table is a processing station whose fuel
  is materials and whose output is insight: "study copper" costs 27 copper
  and 600 ticks for 10; "study glimmer" costs 9 glimmer and 6 000 ticks for
  60. A container with fixed slot roles and a job record kept in storage,
  advanced in `on_tick` from a list, never from a world scan.
- **Milestones** — first bronze tool, first iron, first bred animal, reported
  by the mods that see them.

## The node graph

```lua
node{ id = "shared.bronze",  tier = 1, path = "shared", cost = 20, requires = {"shared.kiln"} }
node{ id = "magic.attune",   tier = 3, path = "magic",  cost = 80, requires = {"shared.fork"} }
node{ id = "tech.steam",     tier = 3, path = "tech",   cost = 80, requires = {"shared.fork"} }
```

Costs rise by tier: T1 about 20, T2 50, T3 100, T4 200, T5 400, T6 800,
T7 1 500, four to six nodes a tier. A full path is about 15 000 insight;
exploration supplies about 400; the rest is research, which costs
materials, which costs mining. The climb is one tunable table. Path mods
register their own nodes at load; this mod owns the shared ones and the
graph.

## The Fork

End of tier 2. Two blocks, both craftable from one rare input, a Keystone
(27 glimmer, 27 gold, an iron frame — about two hours of deep mining):

- **Attunement Stone** (Keystone, silver, living wood) — touch it:
  `path = "magic"`, and a mana bar appears.
- **Analytical Engine** (Keystone, brass gears, glass) — activate it:
  `path = "tech"`.

A dialog with a confirmation and one sentence: *"This binds you. The other
door closes."* One Keystone per player is the practical limit long before the
lock matters. On a shared world, a magic player at an Analytical Engine hears
*"The dials mean nothing to you."* Shared stations stay shared; trade is the
bridge. A server option `allow_repath`, off by default; on, abandoning a
path wipes its nodes and costs a large insight penalty.

```lua
player = { path = nil | "magic" | "tech", insight = 0, unlocked = { [node_id] = true } }
```

## The research UI

A dialog: a scroll of tier rows, each node a button with its cost, greyed
when locked, with a progress bar for the insight pool. Path nodes render only
for the player's path, or both dimmed before the Fork.

## Done when

Both doors exist and nothing is behind them: insight is earned and spent,
the graph gates Craft's recipes through `has`, the Fork binds and refuses,
and a bot script plays the climb headlessly so the pacing is measured rather
than guessed (`crates/bot` in the engine is for exactly this).

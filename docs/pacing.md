<!-- SPDX-FileCopyrightText: Iridesium -->
<!-- SPDX-License-Identifier: GPL-3.0-only -->

# Pacing

How fast the climb goes: insight earned by source over a player's first
three hours, and when each shared node came within reach.

**Two kinds of number live here, and only one is a measurement.**

- **The model** (below) is written by `cargo run --manifest-path
  tests/native/Cargo.toml --bin pacing`: a timeline of what one player
  does and when — a guess at Craft's loop from Craft's own timings, in
  `tests/native/src/bin/pacing.rs` — played through the mod in the
  engine's real VM, buying the cheapest shared node whenever it can. It
  checks the arithmetic of `config.lua` against a plausible climb. It
  does not say how long the climb really takes.
- **A measurement** is a real session's ledger. Every change to a
  player's insight is kept per source (`t:<uuid>:<source>`), shown to
  them by `progress sources`, and logged by the server as a line
  `tiamat_default_progress: pacing t=<tick> player=<id> source=<source>
  delta=<n> total=<n>` while `pacing_log` is on. A playtest's log is
  the table below with real minutes in it.
- **The pacing bot** measures the exploring half for real:
  `python tools/pacing/run.py --minutes N` walks the engine's `bot`
  across a fresh world on a real server with the default mods, and
  writes "Measured: walking" at the end of this file. Craft's loop
  wants blocks placed by numeric id, which a bot script cannot look up
  by name, so that half is a person's session for now.

## The model

| Minute | found_biomes | found_creatures | found_depths | found_food | found_making | found_stations | found_survival | payback | study | Earned | Spent | Nodes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | 3 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 3 | 0 | 0 |
| 10 | 6 | 0 | 0 | 0 | 13 | 4 | 0 | 0 | 0 | 23 | 10 | 1 |
| 20 | 6 | 0 | 0 | 0 | 23 | 12 | 0 | 5 | 0 | 46 | 40 | 3 |
| 30 | 6 | 0 | 5 | 0 | 51 | 16 | 0 | 5 | 0 | 83 | 80 | 5 |
| 40 | 6 | 2 | 5 | 0 | 61 | 16 | 0 | 5 | 20 | 115 | 100 | 6 |
| 50 | 9 | 2 | 13 | 1 | 68 | 16 | 0 | 5 | 40 | 154 | 140 | 7 |
| 60 | 9 | 2 | 13 | 1 | 68 | 16 | 5 | 5 | 62 | 181 | 180 | 8 |
| 70 | 9 | 4 | 13 | 1 | 68 | 20 | 5 | 5 | 86 | 211 | 180 | 8 |
| 80 | 9 | 4 | 13 | 1 | 100 | 20 | 5 | 5 | 110 | 267 | 230 | 9 |
| 90 | 9 | 4 | 13 | 1 | 100 | 28 | 5 | 5 | 150 | 315 | 280 | 10 |
| 100 | 9 | 4 | 13 | 2 | 100 | 28 | 5 | 5 | 190 | 356 | 330 | 11 |
| 110 | 9 | 4 | 23 | 2 | 100 | 28 | 5 | 5 | 230 | 406 | 330 | 11 |
| 120 | 9 | 4 | 23 | 2 | 110 | 28 | 5 | 5 | 280 | 466 | 330 | 11 |
| 130 | 9 | 4 | 23 | 2 | 110 | 28 | 5 | 5 | 335 | 521 | 330 | 11 |
| 140 | 9 | 4 | 38 | 2 | 110 | 28 | 5 | 5 | 390 | 591 | 330 | 11 |
| 150 | 9 | 6 | 38 | 2 | 110 | 28 | 5 | 5 | 445 | 648 | 330 | 11 |
| 160 | 9 | 6 | 38 | 2 | 110 | 28 | 5 | 5 | 500 | 703 | 330 | 11 |
| 170 | 9 | 6 | 58 | 2 | 110 | 28 | 5 | 5 | 555 | 778 | 330 | 11 |
| 180 | 9 | 6 | 58 | 2 | 110 | 28 | 5 | 5 | 610 | 833 | 330 | 11 |

## When each shared node was bought

| Minute | Node |
|---|---|
| 6 | `shared.fire_setting` |
| 12 | `shared.charcoal_clamp` |
| 20 | `shared.hafting` |
| 26 | `shared.kiln_lore` |
| 30 | `shared.placer_eye` |
| 35 | `shared.bronze_casting` |
| 50 | `shared.stonewright` |
| 60 | `shared.roasting` |
| 75 | `shared.bellows_craft` |
| 85 | `shared.tempering` |
| 95 | `shared.keystone` |

## Reading it

Written by hand, after the model's tables; the model keeps this section
when it rewrites the tables above.

- **The shared tree is learned in about an hour and a half**, the Keystone
  last, at minute 95 — long before the Keystone can be MADE, which wants
  orichalcum from two thousand blocks down. So the node is never what a
  player waits on; the mining is. That is the brief's intent.
- **About half of it is paid by studies.** Discoveries had paid 223 by
  the third hour against a tree of 330; the brief meant the tree to be
  affordable "from doing alone". In the model it is not quite, because the
  stand-in world has three biomes where the real one has fifty-five
  (another 150 or so to find), and Life's creatures and foods are a handful
  here. A real session will say which way this falls.
- **After the tree, studies are everything.** Gold and silver at a study
  every five minutes pay about 330 an hour; a path's tier 3 (about 500)
  is an hour and a half of that, and a full path of about 15,000 is some
  forty-five hours. That is the brief's shape — the table is the climb —
  but whether forty-five hours is the right length is a question for real
  play, not for this model.
- **Measured, walking pays little.** Thirty minutes of the bot walking a
  real world (the table at the end) found four biomes — three in the
  first thirteen minutes, then none in seventeen as the spiral widened
  over ground of the same biome — and one survival first: 17 insight. The
  Spindle's biomes are laid out kilometres apart, so the brief's "about
  165 from biomes" is many hours of travel, not an afternoon. If
  exploration is meant to carry the shared tree, `biome_insight` (3) is
  the number to turn; that is the designer's call, and nothing has been
  turned.
- **Nothing in `config.lua` has been changed on the model's say-so.** The
  brief asks for the pacing to be measured, not guessed; the model is the
  guess to measure against. After a playtest, `progress sources` (or the
  server log's `pacing` lines) gives the real version of the first table.

## Measured: walking

Written by `python tools/pacing/run.py --minutes 30` on 2026-09-29: the pacing
bot (`tools/pacing/walk.lua`) walking an outward square spiral from the
world's spawn on a real server with the default mods and a fresh world.
Minutes are the server's clock. Exploration only — Craft's loop is a
person's session for now (see the top of this file).

| Minute | found_biomes | found_survival | Total |
|---|---|---|---|
| 0.0 | 3 | 0 | 3 |
| 0.3 | 3 | 0 | 3 |
| 0.5 | 3 | 0 | 3 |
| 1.0 | 3 | 0 | 3 |
| 1.6 | 6 | 0 | 6 |
| 2.4 | 9 | 0 | 9 |
| 3.2 | 9 | 0 | 9 |
| 3.8 | 9 | 0 | 9 |
| 4.1 | 9 | 0 | 9 |
| 5.4 | 9 | 0 | 9 |
| 6.7 | 9 | 0 | 9 |
| 7.3 | 9 | 0 | 9 |
| 7.4 | 9 | 0 | 9 |
| 9.1 | 9 | 0 | 9 |
| 11.5 | 9 | 5 | 14 |
| 12.9 | 12 | 5 | 17 |
| 15.3 | 12 | 5 | 17 |
| 15.6 | 12 | 5 | 17 |
| 15.8 | 12 | 5 | 17 |
| 19.8 | 12 | 5 | 17 |
| 20.6 | 12 | 5 | 17 |
| 21.2 | 12 | 5 | 17 |
| 21.3 | 12 | 5 | 17 |
| 21.7 | 12 | 5 | 17 |
| 21.9 | 12 | 5 | 17 |
| 22.3 | 12 | 5 | 17 |
| 23.1 | 12 | 5 | 17 |
| 24.0 | 12 | 5 | 17 |
| 24.8 | 12 | 5 | 17 |
| 25.8 | 12 | 5 | 17 |
| 25.9 | 12 | 5 | 17 |
| 26.4 | 12 | 5 | 17 |
| 27.8 | 12 | 5 | 17 |
| 30.1 | 12 | 5 | 17 |
| 30.1 | 12 | 5 | 17 |

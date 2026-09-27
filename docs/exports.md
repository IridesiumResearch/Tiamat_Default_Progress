<!-- SPDX-FileCopyrightText: Iridesium -->
<!-- SPDX-License-Identifier: GPL-3.0-only -->

# Exports

What this mod offers other mods, which is what `LICENSE.EXCEPTION` names as
the interface an independent work may use: everything offered through
`game.export`, the hooks, events and chat words it accepts, the data formats
it reads and writes, and the identifiers it registers.

Planned, and to be documented as each lands:

- `has(uuid, node) -> boolean` — whether a player holds a node of the graph.
  What every gated recipe, station and ability asks. A node on the other path
  is never held.
- `path(uuid) -> nil | "magic" | "tech"` — the player's side of the Fork.
- `grant_insight(uuid, amount, why)` — how a sibling reports a discovery it
  saw: Craft's first dish, Life's first kill, World's first biome.
- `node{ id, tier, path, cost, requires }` — how a path mod registers its
  own nodes into the graph at load.

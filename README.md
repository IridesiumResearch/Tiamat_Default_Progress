<!-- SPDX-FileCopyrightText: Iridesium -->
<!-- SPDX-License-Identifier: GPL-3.0-only -->

# Tiamat Default Progress

The climb, for the [Tiamat](https://github.com/IridesiumResearch/Tiamat-Voxel-Game)
voxel engine: the mod that turns "you can make things" into "you are
climbing". It keeps one number per player — **insight** — earned by doing
new things and by studying materials at a research table; a **node graph**
insight is spent on; and **the Fork**, where a player binds themselves to one
of two doors and the other closes.

It ships **no doors of its own.** Magic and tech register themselves as
paths later, and until one does the Fork is a locked room the player can see
into. What it does ship is the whole *shared* tree (tiers 0 to 2) as
**refinements** — research that makes Craft's loop better, never research
that blocks it — and the contract the two trees will be built on.

Written against the engine's public Lua API and nothing else. The rules that
shape it are in [`AGENTS.md`](AGENTS.md) (vendored from the engine's `api/`),
and [`stubs/game.lua`](stubs/game.lua) is the API itself. The design is
[`docs/brief.md`](docs/brief.md). This repository sits beside the engine and
its siblings, and the engine's `bundle.toml` pins the commit a release
carries.

## Where it is

Built in the brief's order (§12):

| Step | What | State |
|---|---|---|
| 1 | Scaffold, manifest, world options, hook fan-out, the per-player record | **done** |
| 2 | Insight and the node graph: award, register, validate, `has`, `unlock`; operator words | **done** |
| 3 | The shared tree, with its effects, and `effects_of` | **done** |
| 4 | Exploration and discoveries; Craft's firsts | **done** |
| 5 | The research table and the studies, through Craft's registry | **done** |
| 6 | The Research tab (or dialog), discoveries, studies, the HUD | **done** |
| 7 | The Fork: paths, the Keystone, doors, the lock, repath, modes (`0.1.0`) | **done** |
| 8 | `shared_gates` wiring; the pacing bot and `docs/pacing.md` (`0.2.0`) | gates, the ledger, the model and the walking bot **done**; the tuning waits on a real session of Craft's loop |

Today a player earns insight from the first time their feet reach each of
the world's biomes and each depth band under the ground, from Craft's firsts (their first
fire, bronze, casting, workbench, worn-out tool…), from Life's (each kind
of creature hunted, each food tasted, a first death, a night slept
through), and from studies at the research table. They spend it in the Research tab (the interface's screen,
or G without it) on the shared tree: fire-setting, the charcoal clamp, kiln
lore, roasting, bellows, tempering, the Keystone — each of which Craft reads
where its number is used: a fire cracks rock sooner, a mould lasts longer. The Keystone recipe opens
only to a player who has learned it; a door made with it binds them to its
path, and every node of the other path is refused them for ever — unless the
world was made with `repath` on. Other mods register paths, nodes,
discoveries and studies, and ask `has`.

## Layout

```
mods/tiamat_default_progress/
  mod.toml          the manifest and the two world options
  init.lua          load order only
  config.lua        every number: tier costs, discoveries, studies, the shared tree, the Fork
  util.lua          small helpers
  hooks.lua         one engine registration per hook, many subscribers
  store.lua         the per-player record, cached; the clock
  insight.lua       earning and spending; discoveries; the HUD values
  life.lua          survival discoveries, ghosts, the mode, from Life
  nodes.lua         the graph: register, validate, has, unlock, effects_of
  craft.lua         the gate, and what Craft tells this mod
  shared_tree.lua   tiers 0 to 2, paybacks, the shared gates
  research.lua      the research table, the studies, shapes from the hand
  fork.lua          paths, the Keystone, the doors, the lock, repath
  explore.lua       biomes and depths, as a player's feet arrive
  screens.lua       the Research tab, or a dialog
  commands.lua      `progress`, and the operator's words
  exports.lua       what other mods may call
  hud.lua           the client's HUD script: insight, and what just earned some
  textures/         placeholders, drawn by tools/make_textures.py
tools/pacing/       the pacing bot (walk.lua) and its runner (run.py)
tests/native/       the mod in the engine's real VM, with stand-ins around it; the pacing model
docs/               the brief, the exports, the pacing, and the asks of the engine and the siblings
```

## Try it

Check it without starting a server, from the engine checkout:

```sh
cargo run -p server -- --check-mods <a directory holding this mod and its siblings>
```

The pacing model — one player's first three hours, played through the mod
— rewrites the tables in `docs/pacing.md`:

```sh
cargo run --manifest-path tests/native/Cargo.toml --bin pacing
```

The pacing bot walks a fresh world on a real server with the default mods
and writes what exploring paid into `docs/pacing.md` (it needs the engine's
`server` and `bot` built):

```sh
python tools/pacing/run.py --minutes 30
```

The native check runs the mod through the engine's real VM with a fake
server around it, stand-ins for the world, Craft and the interface, and
fixture mods for the two paths. It needs the engine checked out beside this
repository as `../Tiamat`:

```sh
cargo run --manifest-path tests/native/Cargo.toml
```

In a world: `progress` in chat says where you stand, and `progress sources`
where your insight came from. The tree, your insight and your discoveries
are the Research tab of the inventory, and G opens the inventory on it;
insight shows on the HUD only for the moment it is earned. Operators have
`progress grant <node>`,
`progress insight <n>`, `progress path <id|none>` and `progress reset`.

## Your editor

Any editor with the Lua language server reads `.luarc.json` and gets
completion, signatures and types for every `game.*` call from `stubs/game.lua`.
The stubs are kept in step with the engine by its CI, so when you update the
engine, copy its `api/stubs/game.lua` over yours.

## Licence

GPL-3.0-only, © Iridesium, with an Additional Permission under GPLv3 §7 in
`LICENSE.EXCEPTION` (version 1.0, 24 September 2026): a mod that interacts
with Tiamat Default Progress only through its exports, the engine's scripting API or
the network protocol is an independent work and may be licensed however
its author likes. Copying or adapting this mod's code or assets is not
covered by that permission and stays under the GPL. `docs/exports.md`
lists the exports; the engine's `MOD-LICENSING.md` has the plain-language
version and a matrix of what needs which permission. Third-party assets
are listed in `docs/assets.md` with their own licences. Contributions are
taken under the Developer Certificate of Origin with authors retaining
copyright; see `CONTRIBUTING.md`.

<!-- SPDX-FileCopyrightText: Iridesium -->
<!-- SPDX-License-Identifier: GPL-3.0-only -->

# Exports

What Tiamat Default Progress (`tiamat_default_progress`) deliberately offers
other mods. This is the document `LICENSE.EXCEPTION` names as "the Exports":
a mod that reaches this one only through what is listed here, the engine's
scripting API or the network protocol is an independent work. A mod that
copies or adapts this mod's code or assets is not, and stays under the GPL.

An interface this mod offers in fact is an export whether or not it is listed
here, so this file changes in the same commit as any change to one.

## The exported table

`game.exports("tiamat_default_progress")` answers it to a mod that lists this
one in `depends` or `optional_depends`. Source:
`mods/tiamat_default_progress/exports.lua`.

None of the functions raise: anything malformed answers `nil` (or `false`
for a yes-or-no question) and a reason a person can read. The tables they
answer are plain data, and yours to keep. `uuid` is always a player's UUID
in hex, as every hook event reports it.

### The question

| Field | Shape | What it does |
|---|---|---|
| `version` | integer, `1` | Bumped only when a change would break a reader. |
| `has(uuid, node)` | a node id | Whether the player holds the node. Unknown or disabled nodes are `false`; a node of the OTHER path is `false`, always; in a Creative world every shared node is `true`. A table lookup: safe to ask on the tick. |
| `path(uuid)` | | The player's side of the Fork, a path id, or `nil` before it. |
| `insight(uuid)` | | The player's insight. |
| `effects_of(uuid, prefix?)` | `"craft."` | The summed effects of every node the player holds, for keys starting with `prefix` (all of them without one): `{ ["craft.mould_pours"] = 2 }`. Read it when the number is used; nothing about an effect is stored, so retuning one needs no migration. |

### Earning

| Field | Shape | What it does |
|---|---|---|
| `award(uuid, amount, reason?)` | a whole number, negative to take; a short string | Gives or takes insight, clamped at 0. Answers the new total. `reason` is shown on the player's HUD. For milestones: a first bred animal, a first spell. |
| `register_discovery(spec)` | `{ id, insight, label?, group? }` | A once-per-player discovery worth `insight`. An id ending in `:*` registers a FAMILY: any `<prefix>:<name>` is then a discovery, labelled from the name. |
| `discover(uuid, id)` | | The player found it: `true` the first time (insight paid, one line of chat, the HUD), `false` after. |
| `discovered(uuid, id)` | | Whether they have. |
| `register_study(spec)` | `{ id, name?, inputs, ticks, insight }` | A study at the research table: a Craft recipe at the table that makes nothing, `id` qualified with your mod's id and `inputs` in Craft's form. `insight` is paid when Craft says it was made. Needs Craft. |

### The graph

| Field | Shape | What it does |
|---|---|---|
| `register_node(spec)` | `{ id, tier, cost?, requires?, label?, text?, effects?, branch?, reveal?, icon?, on_unlock? }` | A node. `id` is `<path>.<name>`, the path `shared` or one registered with `register_path`. `tier` 0..7; `cost` in insight, the tier's default when left out (0, 20, 50, 100, 200, 400, 800, 1500). `requires` a node id or a list of up to 8. `effects` up to 8 `{ "mod.key", whole number }`. `on_unlock(uuid)` runs in your sandbox when a player gains it. `branch` (up to 32 bytes) is the group the Research tab shows it under within its tier, in the order your nodes were registered; `reveal` is `"always"` or `"near"` — shown only once all but one of its `requires` are held — and when left out the path's `reveal` decides. `icon` is the node's picture on its Research tile: the content hash, 64 hex characters, that `game.content_hash("icons/athanor.png")` answers for a file in YOUR mod's directory (a PNG or JPEG; square, shown about 40 pixels across). A node without one has an empty frame. |
| `unlock(uuid, node)` | | Spends the player's insight on a node: `true`, or `nil` and why. Nothing is taken unless it is learned. |
| `can_unlock(uuid, node)` | | Whether they could, now: `true`, or `nil` and why. |
| `nodes()` | | Every usable node, by tier, as `{ id, path, tier, cost, requires, label, text, effects, branch, reveal, icon }`. |

**The graph is validated once, when mods have finished loading** — so a
node may require one a mod loading after it registers. A node that requires
one nobody registered, is part of a cycle, is shared and requires a path
node, names a path nobody registered, or is a path node of tier 3 or more
that does not (through its requirements) require `shared.fork`, is disabled
and logged, with everything that requires it. Nothing else is: not the mod,
and not the registering mod's other nodes.

### The Fork

| Field | Shape | What it does |
|---|---|---|
| `register_path(spec)` | `{ id, label?, door, recipe?, sentence?, refusal?, on_choose?, branches?, reveal? }` | A path. `id` is a word (`"magic"`); `door` is your block, which a player uses (the place control, nothing in hand) to choose; `recipe = { inputs = { ... } }` makes the door at the workbench, with the Keystone added and `shared.keystone` required; `sentence` is the confirmation's line (default "This binds you. The other door closes."); `refusal` what the door says to a player of the other path; `on_choose(uuid)` runs in your sandbox when a player chooses you (magic sets its mana there). `branches = { FIRE = "The Fire" }` names your nodes' branch codes on the Research tab (a code with no name is shown as itself); `reveal` is the default for your nodes, `"always"` (the default) or `"near"`. |
| `paths()` | | Every path, as `{ id, label, door }`. |

A door offers its path to a player who holds `shared.keystone` and has no
path. Choosing sets their path and gives them `shared.fork`, which every
tier-3 path node requires. A player of the other path hears the door's
`refusal` — unless the world was made with `repath` on, when the door offers
to take them (not within twenty minutes of their last choice), at the cost
of every node of the path they leave and half their insight. Shared nodes
are never taken.

### Subscribers

All while mods load, each `fn` running in your sandbox:

| Field | Called with |
|---|---|
| `on_unlock(fn)` | `fn(uuid, node)` whenever a player gains a node, bought or given |
| `on_discover(fn)` | `fn(uuid, discovery, insight)` the first time a player finds something |
| `on_fork(fn)` | `fn(uuid, path)` when a player chooses at the Fork |
| `on_repath(fn)` | `fn(uuid, old, new)` when a player changes path |

**Registration** — every `register_*` and the subscribers — is while mods
load, in your `init.lua`. After that they answer `nil, "... while mods load"`.

## Identifiers it registers

All are namespaced `tiamat_default_progress:` by the engine.

- **Blocks:** `research_table` — on an engine with whole blocks, ONE PIECE:
  any tool takes it whole and a chisel cannot cut it, and its cells are a
  table's (a top on four legs). With `models/research_table.glb` in this
  mod's directory it is drawn as that model. On an engine without them it
  is a plain block, and the server's log says so.
- **Items:** `keystone`.
- **Nodes:** the shared tree — `shared.firecraft` (tier 0, given with a
  player's first fire), `shared.fire_setting`, `shared.charcoal_clamp`,
  `shared.kiln_lore`, `shared.placer_eye`, `shared.bronze_casting`,
  `shared.hafting` (tier 1), `shared.roasting`, `shared.bellows_craft`,
  `shared.tempering`, `shared.stonewright`, `shared.keystone`, and
  `shared.fork` (tier 2, given at the Fork). Their costs and effects are in
  `config.lua`; the effect keys are `craft.fireset_ticks`,
  `craft.charcoal_yield`, `craft.fuel_percent`, `craft.sluice_gold_period`,
  `craft.mould_pours`, `craft.uses_percent.wood`, `.bronze` and `.iron`,
  `craft.smelt_ore_units`, `craft.bloom_ticks`, `craft.anvil_strikes` and
  `craft.chisel_wear_percent`, each an integer delta on Craft's own number.
- **Effect keys this mod reads:** `progress.study_percent`, summed over
  every node a player holds, raises what each study pays by that many per
  cent (rounded down). Science's Difference Engine is the first to use it.
- **Discoveries:** `make.*` (twelve firsts of making), `station.*` (seven
  first stations), `depth.60` … `depth.2000`, and the family `biome:*`;
  with Life, the families `kill:*` (a creature's short id) and `eat:*` (a
  food's qualified id with its colon a dot), `life.death` and `life.sleep`.
- **Into Craft:** the station `tiamat_default_progress:research_table`; the
  recipes `research_table`, `keystone`, `door_<path>` for each path that
  gives a recipe, and the studies `study_rock`, `study_copper`, `study_tin`,
  `study_iron`, `study_bronze`, `study_wrought_iron`, `study_silver`,
  `study_gold`, `study_lead`, `study_crystal`, `study_metal`,
  `study_diamond`, `study_orichalcum`; and Craft's gate, answered by `has`.
- **Action:** `research` (default key G): the Research screen.
- **Tab:** `tiamat_default_progress:research` on the interface's screen.
- **Sound:** `chime`, bound to this mod's cue `fork`.
- **World options:** `repath` (may a player change path) and `shared_gates`
  (does the shared tree gate Craft's bronze and iron recipes), both off.

## Commands it accepts

Chat words, said by a player and swallowed. `progress` (or `/progress`),
for anyone: insight, path and nodes known; `progress sources`, for anyone:
where their insight came from and went, per source; `progress where`, for
anyone: `at <x> <y> <z> t=<clock>`, the block their feet were last in and
the clock the ledger is timed by (the pacing bot finds its feet with it).
Each answers as the chat hook's refusal reason, so the engine says it to
the speaker alone. For operators: `progress grant
<node>`, `progress insight <n>`, `progress path <id|none>`, `progress reset`.
A sentence that only begins with the word is chat.

## Data it stores or sends

None for other mods. `game.storage` is private to this mod: per player,
`p:<uuid>:insight`, `p:<uuid>:path`, `p:<uuid>:forked`, `n:<uuid>:<node>`,
`d:<uuid>:<discovery>`, `s:<uuid>:<mask>` (studied shapes),
`m:<uuid>:<node>` (paybacks paid) and `t:<uuid>:<source>` (insight moved by
each source, signed: the pacing ledger); and `clock`, the ticks the world
has run. With `pacing_log` on (the default) every change to a player's
insight is also one line in the server's log:
`tiamat_default_progress: pacing t=<tick> player=<first 12 hex> source=<source> delta=<n> total=<n>`.
The sources are `found_<group>` (a discovery), `study`, `shape`,
`payback`, `milestone` (another mod's `award`), `spent`, `repath` and
`operator`.
Its HUD script is sent `insight` and, for a few seconds after an award,
`flash`.

## What it reads from other mods

Not exports, listed so the direction is clear: Craft's recipe registry,
`set_requires`, gate and effects (this mod hands it `has` and
`effects_of`), and subscribers (`on_first`, `on_crafted`,
`on_tool_broken`); the world's `biome_under`, `biomes` and `depth_under`;
the interface's `add_tab`, `open`, `redraw` and theme colours; and Life's
`mode`, `is_ghost`, `on_kill`, `on_eat`, `on_death` and `on_sleep` (its
world option `mode` without it).

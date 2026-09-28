<!-- SPDX-FileCopyrightText: Iridesium -->
<!-- SPDX-License-Identifier: GPL-3.0-only -->

> **Kept as written (draft 1, 2026-09-28).** The code follows the engine and
> the siblings where they disagree with this text, and a few things moved as
> it was built: Craft names the first bronze `smelt:bronze` and a kiln's
> first firing `fire:kiln`, so those are what §3.1 listens for; a biome is a
> discovery of the family `biome:*`, named from whatever the world's
> `biome_under` answers, rather than a list of 55 (sibling ask W5); a carved
> shape is studied from the hand, at once, since Craft never takes a carved
> stack as an ingredient; the export that awards insight is `award` (the
> earlier plan called it `grant_insight`); and the Craft side of the mod is
> one file, `craft.lua`. Until Craft accepts a recipe that makes nothing
> (sibling ask C5) its registry refuses the studies, and until it exports
> `set_requires` (C1) the `shared_gates` option changes nothing. The
> pacing bot of §10 and step 8 is not built yet. `docs/engine-asks.md` and
> `docs/sibling-asks.md` keep the current state.

# Tiamat_default_progress — build prompt

*Draft 1, 2026-09-28. A brief for an AI coding assistant and the person supervising it. Design and plan only. Companion to `Tiamat_default_craft-PROMPT.md` (draft 2.1) and the long plan `schism_design.md`; read both first, then the engine's `api/AGENTS.md` and `api/stubs/game.lua`. Every engine fact here was audited against the stubs; the stubs win.*

---

## 0. One paragraph

`tiamat_default_progress` is Schism's `schism_progress`: the mod that turns "you can make things" into "you are climbing". It keeps one integer per player — **insight** — earned by doing new things and by studying materials at a research table; a **node graph** that insight is spent on; and the **Fork**, where a player binds themselves to one of two doors and the other closes. It ships **no doors of its own**: magic and tech register themselves as paths later, and until they exist the Fork is a locked room the player can see into. What it does ship is the whole *shared* tree (T0–T2) as **refinements** — research that makes the craft loop better, never research that blocks it — and the contract the two trees will be built on.

---

## 0.1 Where it sits

| Mod | Role in the climb |
|---|---|
| `tiamat_default_world` | biomes (55) and depth: the *exploration* insight sources; `biome_under` and `climate` exports |
| `tiamat_default_life` | hunger, creatures, death, modes: *survival* insight sources (through asks — Life exports no events yet) |
| `tiamat_default_ui` | the Research tab lives in its inventory screen via `add_tab` |
| `tiamat_default_craft` | the recipe registry this mod gates and refines; `on_first`/`on_crafted` are the *making* insight sources; the research table is a Craft station |
| **this mod** | insight, nodes, research, the Fork, the per-player path lock |
| `…_magic`, `…_tech` (later) | register a path, their T3–T7 nodes, and their Fork door block |

Load order: `optional_depends` on all four. It must load and pass tests on a bare engine (everything degrades: no biomes → no exploration insight; no Craft → no research table, nodes still buyable with insight from nowhere, which the test harness uses).

---

## 1. Repository shape and manifest

Same skeleton as the siblings (`mods/tiamat_default_progress/`, vendored `AGENTS.md` + `stubs/game.lua`, `tests/native`, `tools/`, `docs/exports.md`, `docs/engine-asks.md`, `docs/sibling-asks.md`).

```
mods/tiamat_default_progress/
  mod.toml
  init.lua          load order only
  config.lua        tier costs, discovery values, research yields, timings
  hooks.lua         one engine registration per hook, fan-out
  store.lua         the per-player record: read/write/encode (§4)
  insight.lua       earning: discoveries, milestones, research completion
  nodes.lua         the graph: register, validate, has(), unlock()
  shared_tree.lua   the T0–T2 refinement nodes this mod ships (§6)
  research.lua      the research table station + study recipes, via Craft's registry
  fork.lua          paths, the Keystone, the two door blocks, the lock, repath
  explore.lua       biome / depth / first-sight polling
  screens.lua       Research tab (UI present) or plain dialog (absent)
  hud.lua           insight counter + "new discovery" toast
  textures/, sounds/, tools/make_textures.py
```

```toml
id = "tiamat_default_progress"
name = "Tiamat Default Progress"
version = "0.1.0"
description = "Insight, research, the shared tree and the Fork."
license = "GPL-3.0-only"
depends = ["core >=0.1"]
optional_depends = ["tiamat_default_world", "tiamat_default_ui", "tiamat_default_life", "tiamat_default_craft"]

[[world_option]]
id = "repath"
name = "Changing path"
description = "May a player abandon their chosen path and take the other? Costs every path node and half their insight."
default = 0                       # checkbox; off = the Schism default, the choice is final

[[world_option]]
id = "shared_gates"
name = "Shared tree gates crafting"
description = "Off: the shared tree only improves recipes. On: bronze and iron recipes need their node first (a slower, research-led game)."
default = 0
```

World options are read with `game.world_option("tiamat_default_progress:repath")` and never change for a world — exactly right for rules that must be the same for every player in it. No `[theme]`.

---

## 2. Engine facts this design rests on

Everything from the craft prompt's §2 applies. The ones that bite here:

| Need | Fact | Consequence |
|---|---|---|
| Per-player persistent record | `game.storage` is scalars only, keyed by string, saved with the world. `keys()` lists them. | One key per fact: `p:<uuid>:insight`, `p:<uuid>:path`, `n:<uuid>:<node>` = `true`, `d:<uuid>:<discovery>` = `true`. No table encoding needed; `keys()` with a prefix scan rebuilds a player's view on join. Numbers are integers. |
| Registries freeze at load | Nodes, paths and discoveries must all be registered during `init.lua` — from this mod *and from magic/tech*, which load after it. | `register_node`/`register_path` are exports that accept calls during the other mod's `init.lua`; the graph is **validated on the first tick**, not at register time, so out-of-order `requires` across mods resolve. |
| Where is a player? | `game.player_entity(uuid)` → entity id; `game.entity(id).pos` in blocks. World's `biome_under(x,y,z)` export. | `explore.lua` polls each connected player every 40 ticks (2 s): biome id and depth band. Cheap: two calls per player. |
| What did they just do? | Craft exports `on_first(uuid, event)` and `on_crafted`. Life exports nothing about kills, deaths, eating. | Making-insight is complete; survival-insight waits on Life asks (§11). |
| Blocks with state | none; containers + storage + material swaps | The research table is a Craft **station** (container + job loop) — this mod registers it into Craft's registry and never writes its own job loop. The Fork doors are plain blocks driven by `on_use`. |
| One callback per hook per mod; 20 Hz tick; no timers | | `hooks.lua` fan-out. Research jobs tick inside Craft, not here. |
| Dialogs and tabs | UI `add_tab{ id, label, order, build(player), on_event }`; widgets `progress{permille}`, `scroll`, `button`, `label`; nothing scrolls past ~530×260 at 800×600 — **except the `scroll` widget exists** in the engine list. | The Research tab is a `scroll` of tier rows. Verify `scroll` passes the UI mod's field whitelist (`screen.lua:156-160`); if not, page by tier with two buttons. |
| Chat & HUD | `chat_to`, `set_hud(uuid, ≤32 scalars)`, one HUD script per mod | Insight total and a discovery flash on the HUD; the sentence in chat. |
| Determinism | no floats, no `math.random` | Insight arithmetic is integer; costs are a table; nothing is rolled. |

---

## 3. Insight — the currency

One integer per player, never negative. Three sources, in the proportions Schism set (≈400 from exploration and discovery, the rest from research), tuned so the shared tree is affordable from *doing* alone and the path trees need the table.

### 3.1 Discoveries (once per player, fixed values)

Registered with `progress.register_discovery{ id, insight, label }`. Fired by `progress.discover(uuid, id)` — idempotent, stored, chats the label once, flashes the HUD. This mod registers these; other mods add their own.

| Group | Source of the event | Count | Each | Total |
|---|---|---|---|---|
| **First sight of a biome** | `explore.lua` polling `biome_under`; one discovery per biome id, labels from World's catalogue names | 55 | 3 | 165 |
| **Depth** | `explore.lua`: first time below 60, 200, 420, 750, 1 200, 2 000 blocks (World's ore levels — you *see* the ore as you pass it) | 6 | 5,8,10,15,20,30 | 88 |
| **First making** | Craft `on_first`: `fire:lit`, `fireset:*` (one, any), `smelt:copper`, `smelt:tin`, `alloy:bronze`, `cast:*` (first any), `wash:tin`, `wash:gold`, `bloom:iron`, `forge:iron_bar`, `forge:*` (first any), `tool_broken` (first) | 12 | 5–15 | 110 |
| **First station** | Craft `on_crafted` for `workbench`, `chest`, `kiln`, `bloomery`, `stone_anvil`, `sluice`, `torch` | 7 | 4 | 28 |
| **Survival** *(pending Life asks)* | first kill of each creature (16 × 2), first death (5), first night survived outdoors (5), first eat of each food (9 × 1) | 31 | | 51 |
| | | | **≈ 440** | |

### 3.2 Research (repeatable, costs materials and time)

The **research table** is a Craft station: `craft.register_station{ id = "research_table", slots = {input=1, output=2}, heat = false, block = "tiamat_default_progress:research_table" }` (4 planks + 1 chest-worth of cord + 9 units of `wet_clay` for the tablets; placeable after the workbench). **Study recipes** are ordinary Craft recipes whose outputs are empty and whose completion this mod hears through `craft.on_crafted`:

```lua
progress.register_study{ id = "study.copper", inputs = { {"tiamat_default_craft:copper_ingot", count = 1} }, ticks = 600, insight = 10 }
-- wraps: craft.register{ id = "study.copper", station = "research_table", inputs = ..., ticks = 600, outputs = {} }
```

Study yields are set so the material's *rarity* is the price. This mod ships:

| Study | Costs | Ticks | Insight |
|---|---|---|---|
| a rock (any `#rock` block, 27 units) | 27 units | 300 | 2 |
| copper / tin / iron ingot | 1 | 600 | 10 |
| bronze ingot | 1 | 600 | 12 |
| wrought iron bar | 1 | 900 | 20 |
| silver / gold / lead ingot | 1 | 1 200 | 25 / 30 / 20 |
| crystal, `metal` (27 units) | 27 units | 1 200 | 30 |
| diamond (9 units) | 9 units | 3 000 | 60 |
| orichalcum (9 units) | 9 units | 6 000 | 80 |
| a chiselled shape (any shaped stack) | 1 | 600 | 8 (once per distinct 27-bit mask, up to 20 masks) |

The last row is the UI's shape crafter earning its keep and a quiet nod to Schism's glyphs. `#rock` is Craft's group. Yields are in `config.lua`.

### 3.3 Milestones

`progress.award(uuid, amount, reason)` is exported for any mod; this mod uses it for node unlocks that pay back (e.g. `shared.charcoal_clamp` awards 5 on first charcoal *after* unlock — a reward for using what you learned). Magic and tech will use it for their own milestones.

---

## 4. The player record and `has()`

```
p:<uuid>:insight   integer
p:<uuid>:path      "" | "<path id>"
p:<uuid>:forked    tick of the Fork, for the repath cooldown
n:<uuid>:<node>    true when unlocked
d:<uuid>:<disc>    true when discovered
s:<uuid>:<mask>    true when a shape has been studied
```

`progress.has(uuid, node_id) → bool` is the single question every gated thing asks. Rules, in order: unknown node → `false`; node's `path` is `"shared"` → `n:` key; node's `path` ≠ the player's `p:path` → **`false`, always** (the lock); else `n:` key. A hot in-memory cache per connected player is rebuilt from `keys()` on join and written through on every change, so `has()` is a table lookup on the tick.

Operators (`game.is_operator`) get a `/progress` chat command: `grant <node>`, `insight <n>`, `path <id>`, `reset` — for testing and for admins on a shared world.

---

## 5. Nodes

```lua
progress.register_node{
  id       = "shared.bronze_casting",     -- "<path>.<name>"; the prefix must be a registered path or "shared"
  tier     = 1,                           -- 0..7
  cost     = 20,                          -- insight; nil = the tier's default from config
  requires = { "shared.kiln_lore" },      -- all must be has()
  label    = "Bronze casting",
  text     = "Pour hotter, lose less: bronze pours in a mould twice more before it cracks.",
  effects  = { { "craft.mould_pours", 2 } },   -- data for the owning mod; this mod stores nothing about it
  on_unlock = function(uuid) end,         -- optional; runs in the registering mod's sandbox
}
```

Tier defaults (Schism's curve): T0 free, T1 20, T2 50, T3 100, T4 200, T5 400, T6 800, T7 1 500. Each tier 4–6 nodes. Unlock is `progress.unlock(uuid, node)`: has all `requires`, insight ≥ cost, path matches → subtract, set key, fire `on_unlock` and the `on_unlock` subscriber list, chat one line.

**Validation on the first tick**: every `requires` names a registered node; no cycles; a `shared.*` node never requires a path node; a path node's tier ≥ 3 requires (transitively) `shared.fork`. A bad graph logs every fault and disables **only the faulty nodes**, never the mod.

---

## 6. The shared tree this mod ships (T0–T2)

**Design rule: shared nodes refine, they do not gate** — unless the world was made with `shared_gates = on`. A new player can smelt bronze with zero insight; a player who researched can smelt it better. This keeps Craft's loop intact and gives insight a use before the Fork. Each node's `effects` are read by Craft (through `progress.effects_of(uuid, "craft.*")` — Craft asks this mod for the player's active modifiers when it performs a recipe or charges wear). Where Craft's draft 2.1 has no hook for an effect, it is listed as a Craft ask (§11).

| Node | Tier | Cost | Requires | Effect (read by) |
|---|---|---|---|---|
| `shared.firecraft` | 0 | 0 | — | auto-unlocked on `fire:lit`; the tree's root, so the tab is never empty |
| `shared.fire_setting` | 1 | 10 | firecraft | fire-setting 600 → 400 ticks (Craft `fire.fireset_ticks`) |
| `shared.charcoal_clamp` | 1 | 15 | firecraft | charcoal burn 27 log → 12 (from 9) (Craft recipe yield override) |
| `shared.kiln_lore` | 1 | 20 | charcoal_clamp | kiln fuel lasts +25 % |
| `shared.placer_eye` | 1 | 20 | — | sluice: gold flake every 6th wash (from 9th) |
| `shared.bronze_casting` | 1 | 20 | kiln_lore | mould survives 6 pours (from 4) |
| `shared.hafting` | 1 | 15 | — | wood and bronze tool `uses` +25 % |
| `shared.roasting` | 2 | 40 | kiln_lore | copper/tin/iron ore → ingot at 18 units instead of 27 (roast-then-smelt; the real yield trick) |
| `shared.bellows_craft` | 2 | 50 | kiln_lore | bloomery bloom in 1 800 ticks (from 2 400) |
| `shared.tempering` | 2 | 50 | hafting, bellows_craft | iron tool `uses` +50 % |
| `shared.stonewright` | 2 | 40 | — | anvil strikes −1 each; chisel wear halved (the shape crafter's node) |
| `shared.keystone` | 2 | 50 | roasting, tempering | **unlocks the Keystone recipe** — the one shared node that gates, in every world, because it *is* the Fork |
| `shared.fork` | 2 | 0 | keystone | set by the Fork itself, never bought; every T3 path node requires it |

With `shared_gates = on`, three more gates apply: `shared.kiln_lore` gates every heat-2 recipe, `shared.bellows_craft` gates the bloomery, `shared.tempering` gates iron tool heads. Implemented as `requires` on Craft's recipes through `craft.set_requires(recipe_id, node)` (Craft ask C1) — applied at load only when the option is on.

Sum of the shared tree: **≈ 300 insight**, so a player who explores and makes can finish it without the table; the table is for the path trees.

---

## 7. The Fork

### 7.1 Paths

Magic and tech are not in this mod. They register:

```lua
progress.register_path{
  id    = "magic",
  label = "The Attuned",
  door  = "tiamat_default_magic:attunement_stone",   -- the block a player touches
  recipe = { inputs = { {"tiamat_default_progress:keystone", 1}, {"tiamat_default_craft:silver_ingot", 4}, {"tiamat_default_world:ironwood_log", 27, units=true} } },
  sentence = "This binds you. The other door closes.",
  on_choose = function(uuid) end,        -- magic sets mana_max = 10 here
}
```

This mod registers the door's `on_use` (through its one hook): a confirmation dialog with the path's sentence, a **Yes / Not yet** pair, and — if the player is already on another path — the refusal line the path supplied (`"The dials mean nothing to you."`). On yes: `p:path` set, `shared.fork` set, `on_choose`, `on_fork` subscribers, a `cue` and a chat line to everyone within 32 blocks. With **one path installed**, the Fork has one door (Schism §1). With **none**, the Keystone can be made and held, the Research tab shows the Fork row greyed with "No door has been built in this world yet." — honest, and it lets Craft + Progress ship before either tree.

### 7.2 The Keystone

`tiamat_default_progress:keystone` — 27 units of orichalcum + 27 units of gold ingot-equivalent (9 gold ingots) + 1 `iron_frame` (Craft step 10) at the workbench, `requires = "shared.keystone"`. Roughly Schism's two hours of deep mining: orichalcum is at 2 000 blocks and needs iron. One per player in practice, and the doors consume it.

### 7.3 Repath

Off by default (world option). When on: touching the *other* door after the Fork offers "Abandon the <path> and take this door? Every <path> node is lost and half your insight with it." Cooldown: not within 24 000 ticks (20 min) of the last Fork. On yes: every `n:<uuid>:<other path>.*` key cleared, insight halved (integer), `p:path` swapped, `on_repath` subscribers (magic wipes mana, tech wipes charge). Never wipes shared nodes.

### 7.4 Modes

Life's world option `tiamat_default_life:mode`: in `creative`, `has()` answers `true` for every *shared* node and the Fork still applies (a creative magic player is still not a tech player — the lock is the game's identity, not a difficulty). Ghosts cannot touch a door.

---

## 8. Screens and HUD

- **Research tab** (`ui.add_tab{ id = "tiamat_default_progress:research", label = "Research", order = 40 }`): header row = insight total as a big label + a `progress` bar to the cheapest affordable node; body = a `scroll` of tier rows, each node a `button` — bright when affordable, dim when locked (hover text = `requires`), ticked when owned; path nodes appear only for the player's path, and before the Fork *both* trees are listed dimmed under a "Beyond the Fork" heading so the choice is visible long before it is made. Bottom buttons: **Discoveries** (a second view: the 55 biomes as a grid of dots, lit when seen — the exploration log) and **Studies** (what the table can study, with yields).
- Without the UI mod: the same tree in a plain `show_dialog` on action `tiamat_default_progress:research`, default key **G**.
- **HUD**: `hud.lua` draws the insight number top-right and, for 3 s after a discovery, its label. Values via `set_hud`: `insight`, `flash_id`, `flash_until`.
- **Chat**: one line per discovery and per unlock; nothing else.

---

## 9. Code rules

The craft prompt's §9 applies verbatim (fan-out, lazy id resolution, storage scalars, integer maths, exports never raise, degrade when siblings are absent). Additions:

1. `has()` is called on hot paths by other mods; it must be a cache lookup, never a `keys()` scan. Rebuild on join and on every write.
2. `register_*` exports accept calls from other mods' `init.lua` and defer validation to the first tick.
3. Every award goes through one function that clamps at 0, writes storage, updates the cache and the HUD. No other code touches `p:insight`.
4. `explore.lua` polls at most one player per tick (round-robin) so 50 players cost 50 ticks per sweep, not one.
5. Never store node *effects*: the owning mod reads `effects_of` live, so retuning a node's numbers in config never needs a migration.

---

## 10. Tests (`tests/native`)

- Load alone and with every sibling combination. Graph validation: a cycle, a dangling `requires`, a shared node requiring a path node — each disables only the bad node and logs it.
- Insight: award, clamp at 0, persistence across a save/load, cache rebuild on join equals storage.
- Discoveries: fire twice, count once; biome discovery from a scripted position via a stubbed `biome_under`; depth bands in order.
- Study: a stub Craft registry receives the station and recipes; `on_crafted("study.copper")` awards 10.
- Unlock: refuses without prereqs, without insight, on the wrong path; subtracts exactly once.
- Fork: no path registered → door absent, Keystone craftable; one path → one door; two → both; choosing sets `shared.fork`; other door refuses with the path's sentence; repath off → refused; repath on → other-path nodes gone, insight halved, cooldown enforced.
- `shared_gates` on → the three Craft gates are applied at load; off → none.
- Creative mode → shared `has()` true, path lock still holds.
- Determinism: full suite twice → identical storage dump.
- **Pacing bot** (`crates/bot`): a script that plays Craft's loop headlessly for a scripted hour and logs insight earned per source. This is how the tier costs get tuned — Schism's "measured, not guessed". Its output is a table in `docs/pacing.md`.

---

## 11. Asks

**`docs/sibling-asks.md`**

- **Craft** C1: `craft.set_requires(recipe_id, node)` and a gate signature that passes the recipe record — `set_gate(fn(uuid, recipe) → bool)` — so this mod can gate by recipe id, not only by a `requires` the recipe author wrote. C2: `craft.set_modifier(key, fn(uuid) → integer)` or an agreed `progress.effects_of(uuid, prefix)` read at `perform`/wear/fire-set time, for every effect in §6 (`fire.fireset_ticks`, recipe yield override, fuel duration, mould pours, sluice gold period, tool uses, bloom ticks, anvil strikes, chisel wear). C3: `on_first` event ids as listed in §3.1, frozen in Craft's `docs/exports.md`. C4: the `iron_frame` in step 10 is the Keystone's frame; keep its id.
- **Life** L6: `on_kill(fn(uuid, creature_id))`, `on_death(fn(uuid))`, `on_eat(fn(uuid, material))`, `on_sleep` — the survival discoveries. L7: read access to the player's mode (`is_ghost(uuid)`, `mode()`), so doors refuse ghosts without this mod re-deriving it. L8: `add_stat(id, {max, regen, hud})` — the mana bar magic will need at the Fork; deciding now avoids magic owning a second HUD.
- **World** W5: a stable list of biome ids and display names in the exports (`biomes()`), so the discovery log does not hard-code 55 strings that World may rename.
- **UI** U4: confirm the `scroll` widget passes the tab whitelist; U5: a `hover`/tooltip text field on `button`, for `requires` lists.

**`docs/engine-asks.md`**

1. `game.storage` prefix scan (`keys(prefix)`) — `keys()` returns every key in the world; with 50 players × 100 nodes it is a 5 000-key walk on every join.
2. A per-player storage namespace, or at least a documented key-count ceiling.
3. `register_on_player_move` or a position-change event, so exploration does not poll.

---

## 12. Build order

1. Scaffold, manifest, world options, `hooks.lua`, `store.lua` (keys, cache, encode). **Tests: load, persistence, cache.**
2. `insight.lua` + `nodes.lua`: award, register, validate, `has`, `unlock`; operator commands. **Tests: insight, unlock, graph validation.**
3. `shared_tree.lua`: the §6 nodes with effects data; `effects_of` export. **Tests: effects_of answers per unlock.**
4. `explore.lua` + discoveries; Craft `on_first` subscriptions. **Tests: discoveries.**
5. `research.lua`: station + studies through Craft's registry. **Tests: study.**
6. `screens.lua` + `hud.lua`: Research tab / dialog, discoveries grid, HUD. **Manual: fits at 800×600.**
7. `fork.lua`: paths, Keystone, doors, lock, repath, modes. **Tests: fork.** ← ships as `0.1.0`: the shared tree is live, the Fork waits for a door.
8. `shared_gates` option wiring; pacing bot and `docs/pacing.md`; tune `config.lua` from its numbers. `0.2.0`.

---

## 13. Numbers a designer will turn (`config.lua`)

Tier default costs; every discovery value; every study's ticks and yield; the shape-study cap (20); each shared node's cost and effect magnitude; Keystone recipe; repath cooldown and penalty (½); HUD flash duration; explore poll interval (40 ticks); depth bands.

---

## 14. Out of scope

Any path content (magic, tech). Mana, charge, spells, machines. Achievements as a UI beyond the discoveries grid. Trading between paths (Schism's "trade is the bridge" is just inventories — no code). Per-node *world* effects (a node that changes terrain). Server-wide research (every record is per player; a "shared research" option is a later world option, not v1).

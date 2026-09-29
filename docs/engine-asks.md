<!-- SPDX-FileCopyrightText: Iridesium -->
<!-- SPDX-License-Identifier: GPL-3.0-only -->

# Engine asks from the Progress mod

What this mod has needed from the engine, found by planning and building
it. Each entry says what was wanted, why the mod cannot do it, and the
smallest engine change that would. Newest first. Landed items stay here,
marked, as the record; the open ones are copied, without the history, to the
engine's `docs/engine-asks/tiamat_default_progress.md`, so the engine side
finds every mod's open asks in one place.

Numbered as the brief (`docs/brief.md` §11) numbered them.

## Where these stand (2026-09-28)

| Item | State | In this mod |
|---|---|---|
| 4 a bot that can play a station | Landed, engine ff0bbda. | the pacing bot walks a real world and reads its ledger (`tools/pacing/`). |
| 3 a position-change event | Landed, engine cbbbc5e. | `explore.lua` hears `register_on_player_move`; the round-robin poll is gone. |
| 2 a per-player storage namespace, or a key ceiling | Landed, engine cbbbc5e. | one key per fact stays: the save now writes only the keys that changed. |
| 1 `keys(prefix)` | Landed, engine cbbbc5e. | a player's record is four prefix reads (`store.lua`). |

Nothing is open.

## 4. A bot that can play a station: LANDED 2026-09-28 (engine ff0bbda)

**Wanted.** Three calls on the `bot` script API: `bot.use(x, y, z)` (the
place control on a block with nothing to place, as a player's right-click
reaches `register_on_use`), `bot.press(form, name)` (a button in a dialog
a mod showed it), and `bot.heard()` (the chat lines sent to it since the
last call, so a script can read what a mod said back).

**Why the mod cannot.** The brief's pacing is to be measured by a bot
playing Craft's loop without a screen. The bot can join, chat, move, dig,
place and press action keys, and nothing more: it cannot light a fire,
open a kiln or read "Discovered: ..." back, so it cannot play the loop or
see what it earned. Today the pacing is a model (`docs/pacing.md`) and a
ledger a person's session fills; with these three, a script could play the
first hours and read `progress sources` at the end.

**Smallest change.** Three commands on the bot's existing channel: a use
message the client already sends, a dialog event it already sends, and a
queue of the chat it already receives.

**Landed** as `bot.use`, `bot.press` and `bot.heard`. The pacing bot
(`tools/pacing/walk.lua`, run by `tools/pacing/run.py`) walks a fresh world
and reads its ledger back through `bot.heard`; its first run found the
join-time placement that paid a new player every depth band at once. It
plays exploration only: placing a campfire or a kiln wants the block's
numeric id, which a script has no way to look up by name.

## 3. A position-change event: LANDED 2026-09-28 (engine cbbbc5e)

**Wanted.** `game.register_on_player_move(fn(uuid, pos))`, fired when a
player crosses into another block (or chunk), or any event that says a
player moved.

**Why the mod cannot.** A biome or a depth is discovered by being there, and
nothing tells a mod where a player is except asking. So every connected
player is polled every two seconds, one player a tick, round-robin — two
engine calls and one export call a look, whether anybody moved or not.

**Smallest change.** A hook fired on a block-coordinate change of a
player's feet; the engine already knows when that happens.

**Landed** as `game.register_on_player_move(fn(e))`, `e = { player, x, y,
z, domain, from }`, once per block the feet cross into, after the body has
moved; the first event after a join has no `from`. `explore.lua` discovers
from it and polls nothing.

## 2. A per-player storage namespace, or a documented ceiling: LANDED 2026-09-28 (engine cbbbc5e)

**Wanted.** Either `game.storage` scoped to a player (`game.player_storage(uuid)`)
or a stated limit on how many keys a mod may keep.

**Why the mod cannot.** Storage takes scalars, so a player's record is one
key per fact: a node held, a discovery made. Fifty players with a hundred
nodes and a hundred discoveries each is ten thousand keys, and nothing says
whether that is fine.

**Smallest change.** A number in the stubs, or a namespace.

**Landed** as the ceiling removed: the save had rewritten a mod's whole
bag whenever one key changed, and now writes only the keys that changed. A
prefix is the namespace, read back with `keys(prefix)`.

## 1. `keys(prefix)`: LANDED 2026-09-28 (engine cbbbc5e)

**Wanted.** `game.storage.keys(prefix)`, answering only the keys that start
with a prefix.

**Why the mod cannot.** `keys()` answers every key the mod has, so building
one player's record on join walks every player's keys — 5,000 of them for
fifty players with a hundred nodes. The walk is paid once per player per
session and the record is cached after, but it grows with the world.

**Smallest change.** A prefix argument; storage is already keyed by string.

**Landed** as `game.storage.keys(prefix)`, the keys under a prefix, in
order. A player's record is built from four of them.

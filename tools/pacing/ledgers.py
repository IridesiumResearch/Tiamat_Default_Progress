# SPDX-FileCopyrightText: Iridesium
# SPDX-License-Identifier: GPL-3.0-only
"""Measures what real play paid: the ledgers kept in played worlds.

Every change to a player's insight is kept per source in the world's own
storage (`t:<uuid>:<source>`, see insight.lua), so a world somebody played
is a measurement whether or not `pacing_log` was on. This opens each
world's `world.sqlite` READ-ONLY, reads this mod's ledger, insight and
nodes for every player in it, and writes one row a player into
docs/pacing.md under "Measured: playtests".

The worlds' directory defaults to the client's own (`%APPDATA%/tiamat/worlds`
on Windows, `~/.local/share/tiamat/worlds` elsewhere). Run from the
repository root:

    python tools/pacing/ledgers.py [worlds directory]
"""
import argparse
import datetime
import os
import sqlite3
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PACING = ROOT / "docs" / "pacing.md"
HEADING = "## Measured: playtests"
BEFORE = "## Measured: walking"
MOD = "tiamat_default_progress"


def default_worlds():
    if os.name == "nt" and os.environ.get("APPDATA"):
        return Path(os.environ["APPDATA"]) / "tiamat" / "worlds"
    return Path.home() / ".local" / "share" / "tiamat" / "worlds"


def number(blob):
    """A storage scalar: a tag byte, then a little-endian f64 for a number."""
    if isinstance(blob, (bytes, bytearray)) and len(blob) == 9:
        return struct.unpack("<d", blob[1:9])[0]
    return None


def players(path):
    """{uuid: {"tally": {source: n}, "insight": n, "nodes": [id]}} for one world."""
    db = sqlite3.connect(f"file:{path.as_posix()}?mode=ro", uri=True)
    try:
        rows = db.execute("select key, value from mod_storage where mod_id = ?", (MOD,)).fetchall()
    except sqlite3.DatabaseError:
        return {}
    finally:
        db.close()
    out = {}
    for key, value in rows:
        parts = key.split(":", 2)
        if len(parts) < 3:
            continue
        kind, uuid, rest = parts
        p = out.setdefault(uuid, {"tally": {}, "insight": 0, "nodes": []})
        if kind == "t" and number(value) is not None:
            p["tally"][rest] = int(number(value))
        elif kind == "p" and rest == "insight" and number(value) is not None:
            p["insight"] = int(number(value))
        elif kind == "n":
            p["nodes"].append(rest)
    return {u: p for u, p in out.items() if p["tally"]}


def table(found, where):
    sources = sorted({s for _, _, p in found for s in p["tally"] if s != "spent"})
    out = [HEADING, "",
           f"Written by `python tools/pacing/ledgers.py` on {datetime.date.today()}: the ledger",
           f"every played world keeps, read from the saves in `{where}`, one row",
           "a player, oldest first. The date is when the world was last saved.",
           "No minutes: a world does not record how long it was played, so these",
           "say what a session reached, not how fast. `firecraft` is given by the",
           "first fire, never bought.", ""]
    out.append("| World | Saved | " + " | ".join(sources) + " | Earned | Held | Nodes |")
    out.append("|---|---|" + "---|" * (len(sources) + 3))
    for name, when, p in found:
        cells = [str(p["tally"].get(s, 0)) for s in sources]
        earned = sum(p["tally"].get(s, 0) for s in sources)
        nodes = ", ".join(f"`{n.removeprefix('shared.')}`" for n in sorted(p["nodes"])) or "—"
        out.append(f"| {name} | {when} | " + " | ".join(cells) + f" | {earned} | {p['insight']} | {nodes} |")
    return "\n".join(out) + "\n"


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("worlds", nargs="?", type=Path, default=default_worlds())
    args = ap.parse_args()
    if not args.worlds.is_dir():
        sys.exit(f"no worlds directory at {args.worlds}")

    found = []
    for db in sorted(args.worlds.glob("*/world.sqlite"), key=lambda p: p.stat().st_mtime):
        when = datetime.date.fromtimestamp(db.stat().st_mtime).isoformat()
        for _, p in sorted(players(db).items()):
            found.append((db.parent.name, when, p))
    if not found:
        sys.exit(f"no world under {args.worlds} holds a {MOD} ledger")

    where = "%APPDATA%/tiamat/worlds" if args.worlds == default_worlds() and os.name == "nt" else args.worlds
    section = table(found, where)
    text = PACING.read_text(encoding="utf-8") if PACING.exists() else ""
    at = text.find(HEADING)
    if at >= 0:
        after = text.find("\n## ", at + len(HEADING))
        text = text[:at] + section + (text[after + 1:] if after >= 0 else "")
    elif text.find(BEFORE) >= 0:
        at = text.find(BEFORE)
        text = text[:at] + section + "\n" + text[at:]
    else:
        text = text.rstrip("\n") + "\n\n" + section
    PACING.write_text(text, encoding="utf-8", newline="\n")
    print(section)
    print(f"wrote {PACING.relative_to(ROOT)}: {len(found)} player(s)")


if __name__ == "__main__":
    main()

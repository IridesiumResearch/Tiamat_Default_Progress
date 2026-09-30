# SPDX-FileCopyrightText: Iridesium
# SPDX-License-Identifier: GPL-3.0-only
"""Measures what exploring pays: the pacing bot, on a real server.

Starts a throwaway server on loopback with the engine checkout's mods
(`../Tiamat/game`, where this mod and its siblings are linked) and a fresh
world, runs `tools/pacing/walk.lua` through the engine's `bot` for as many
minutes of the server's clock as asked, stops the server, and writes what
the bot's `progress sources` said, leg by leg, into docs/pacing.md under
"Measured: walking". The server's own `pacing` log lines are kept in the
scratch directory; the world generated there is deleted when the run ends.

Build the engine's `server` and `bot` first (`cargo build -p server -p bot`
in the engine). Run from the repository root:

    python tools/pacing/run.py --minutes 20
"""
import argparse
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ENGINE = ROOT.parent / "Tiamat"
PACING = ROOT / "docs" / "pacing.md"
HEADING = "## Measured: walking"

LINE = re.compile(r"^pacing-bot t=(-?\d+) (.+?) (Insight by source: .*|No insight yet\.|\(no answer\))$")


def ledger(text):
    """`Insight by source: a +1, b -2.` as {source: n}."""
    out = {}
    body = text.removeprefix("Insight by source: ").rstrip(".")
    for part in body.split(", "):
        m = re.match(r"^(\S+) ([+-]\d+)$", part)
        if m:
            out[m.group(1)] = int(m.group(2))
    return out


def table(rows, minutes, when):
    sources = sorted({s for _, _, l in rows for s in l})
    out = [HEADING, "",
           f"Written by `python tools/pacing/run.py --minutes {minutes}` on {when}: the pacing",
           "bot (`tools/pacing/walk.lua`) walking an outward square spiral from the",
           "world's spawn on a real server with the default mods and a fresh world.",
           "Minutes are the server's clock. Exploration only — Craft's loop is a",
           "person's session for now (see the top of this file).", ""]
    out.append("| Minute | " + " | ".join(sources) + " | Total |")
    out.append("|---|" + "---|" * (len(sources) + 1))
    start = rows[0][0] if rows else 0
    for t, _, l in rows:
        cells = [str(l.get(s, 0)) for s in sources]
        out.append(f"| {(t - start) / 1200:.1f} | " + " | ".join(cells) + f" | {sum(l.values())} |")
    return "\n".join(out) + "\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--minutes", type=int, default=20, help="minutes of the server's clock to walk")
    ap.add_argument("--port", type=int, default=47891)
    ap.add_argument("--engine", type=Path, default=ENGINE)
    args = ap.parse_args()

    exe = ".exe" if sys.platform == "win32" else ""
    server = args.engine / "target" / "debug" / f"server{exe}"
    bot = args.engine / "target" / "debug" / f"bot{exe}"
    for binary in (server, bot):
        if not binary.exists():
            sys.exit(f"{binary} is missing: cargo build -p server -p bot in {args.engine}")

    scratch = Path(tempfile.mkdtemp(prefix="tdp-pacing-"))
    (scratch / "server.toml").write_text(
        f'bind_addr = "127.0.0.1:{args.port}"\n'
        f'world_path = "{(scratch / "world").as_posix()}"\n'
        f'mods_path = "{(args.engine / "game").as_posix()}"\n'
        "max_players = 2\nview_distance = 4\n")
    script = scratch / "walk.lua"
    script.write_text(f"MINUTES = {args.minutes}\n" + (ROOT / "tools" / "pacing" / "walk.lua").read_text())

    log = open(scratch / "server.log", "w", encoding="utf-8", errors="replace")
    proc = subprocess.Popen([str(server), "--config", "server.toml"], cwd=scratch, stdout=log, stderr=subprocess.STDOUT)
    try:
        deadline = time.time() + 300
        while "server listening" not in (scratch / "server.log").read_text(encoding="utf-8", errors="replace"):
            if proc.poll() is not None or time.time() > deadline:
                sys.exit(f"the server did not start; its log is {scratch / 'server.log'}")
            time.sleep(1)
        print(f"server up in {scratch}; walking {args.minutes} minutes", flush=True)
        run = subprocess.run([str(bot), "run", str(script), "--server", f"127.0.0.1:{args.port}"],
                             capture_output=True, text=True, errors="replace",
                             timeout=args.minutes * 60 * 3 + 600)
    finally:
        proc.terminate()
        proc.wait(timeout=60)
        log.close()
        # The world is a hundred megabytes of terrain nobody will open again;
        # the logs beside it are what a run leaves behind.
        shutil.rmtree(scratch / "world", ignore_errors=True)

    (scratch / "bot.log").write_text(run.stdout + run.stderr, encoding="utf-8")
    rows = []
    for raw in run.stdout.splitlines():
        m = LINE.match(raw.strip())
        if m and m.group(3).startswith("Insight by source"):
            rows.append((int(m.group(1)), m.group(2), ledger(m.group(3))))
    print(run.stdout[-2000:])
    if run.returncode != 0 or not rows:
        sys.exit(f"the bot did not finish cleanly; see {scratch / 'bot.log'}")

    section = table(rows, args.minutes, time.strftime("%Y-%m-%d"))
    text = PACING.read_text(encoding="utf-8") if PACING.exists() else ""
    at = text.find(HEADING)
    if at >= 0:
        after = text.find("\n## ", at + len(HEADING))
        text = text[:at] + section + (text[after + 1:] if after >= 0 else "")
    else:
        text = text.rstrip("\n") + "\n\n" + section
    PACING.write_text(text, encoding="utf-8", newline="\n")
    print(f"wrote {PACING.relative_to(ROOT)}; the logs are in {scratch}")


if __name__ == "__main__":
    main()

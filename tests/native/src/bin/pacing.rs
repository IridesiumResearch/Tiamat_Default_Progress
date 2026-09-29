// SPDX-FileCopyrightText: Iridesium
// SPDX-License-Identifier: GPL-3.0-only
//
// The pacing model: one player's first three hours, as a timeline of what
// they do and when, played through the mod in the engine's real VM with the
// same stand-ins the checks use. The player buys the cheapest shared node
// they can afford whenever they can. What comes out is a table of insight by
// source over time, and when each tier and the Keystone came within reach,
// written to docs/pacing.md.
//
// A MODEL, not a measurement: the timeline is a guess at how long Craft's
// loop takes, written from Craft's own timings. The measurement is a real
// session's ledger (`progress sources`, and the `pacing` lines in the
// server's log); this is what to compare it against. Run from the
// repository root:
//
//     cargo run --manifest-path tests/native/Cargo.toml --bin pacing

#[allow(dead_code)]
#[path = "../rig.rs"]
mod rig;

use std::fmt::Write as _;

use rig::{MOD, PLAYER, Rig, Setup};

const MAGIC: &str = include_str!("../../fixtures/magic.lua");
const TECH: &str = include_str!("../../fixtures/tech.lua");

/// One thing the player does, at a minute of play.
enum Step {
    /// Chat, as Craft's or Life's stand-in hears it.
    Say(&'static str),
    /// The player's feet arrive somewhere.
    Move(i32, i32, i32),
    /// A study at the research table, made.
    Study(&'static str),
}
use Step::{Move, Say, Study};

/// The shared tree, in the order the player would look at it.
const SHARED: &[&str] = &[
    "shared.fire_setting", "shared.charcoal_clamp", "shared.hafting", "shared.kiln_lore", "shared.placer_eye",
    "shared.bronze_casting", "shared.stonewright", "shared.roasting", "shared.bellows_craft", "shared.tempering",
    "shared.keystone",
];

fn timeline() -> Vec<(u32, Step)> {
    let mut t = vec![
        // The first hour: fire, the bench, the kiln, copper and tin, bronze.
        (0, Move(100, 64, 100)),
        (3, Say("c first fire:lit")),
        (6, Say("c first craft:tiamat_default_craft:workbench")),
        (8, Say("c first fireset:stone")),
        (10, Move(-40, 64, 100)),
        (12, Say("c first craft:tiamat_default_craft:chest")),
        (15, Say("c first fire:kiln")),
        (18, Say("c make tiamat_default_craft:charcoal")),
        (20, Say("c first smelt:copper")),
        (24, Say("c first craft:tiamat_default_craft:sluice")),
        (25, Say("c first wash:tin")),
        (26, Say("c first smelt:tin")),
        (28, Move(-40, -55, 100)),
        (30, Say("c first smelt:bronze")),
        (32, Say("c first cast:bronze_pick")),
        (40, Say("l kill cow")),
        (41, Say("l eat tiamat_default_life:raw_meat")),
        (45, Say("c broke")),
        (48, Move(1200, 64, 100)),
        (50, Move(1200, -195, 100)),
        (55, Say("l sleep")),
        // The second: iron.
        (65, Say("l kill cave_rat")),
        (70, Say("c first craft:tiamat_default_craft:bloomery")),
        (75, Say("c first bloom:iron")),
        (80, Say("c first forge:iron_bar")),
        (85, Say("c first craft:tiamat_default_craft:stone_anvil")),
        (90, Say("c first craft:tiamat_default_craft:torch")),
        (95, Say("l eat tiamat_default_life:bread")),
        (110, Move(1200, -415, 100)),
        (115, Say("c first wash:gold")),
        // The third: deep, for gold and silver.
        (140, Move(1200, -745, 100)),
        (150, Say("l kill bat")),
        (170, Move(1200, -1195, 100)),
    ];
    // Studies: a copper ingot every five minutes once there is copper, a
    // bronze one once there is bronze, iron once there is iron, and gold
    // and silver in the third hour.
    for m in (35..60).step_by(5) {
        t.push((m, Study("study_copper")));
    }
    for m in (60..120).step_by(5) {
        t.push((m, Study(if m < 85 { "study_bronze" } else { "study_wrought_iron" })));
    }
    for m in (120..=180).step_by(5) {
        t.push((m, Study(if m % 10 == 0 { "study_gold" } else { "study_silver" })));
    }
    t.sort_by_key(|(m, _)| *m);
    t
}

/// The ledger as `(source, amount)`, from `progress sources`.
fn ledger(r: &mut Rig) -> Vec<(String, i64)> {
    let line = r.ask("progress sources");
    let Some(body) = line.strip_prefix("Insight by source: ") else { return Vec::new() };
    body.trim_end_matches('.')
        .split(", ")
        .filter_map(|part| {
            let (source, n) = part.rsplit_once(' ')?;
            Some((source.to_owned(), n.parse().ok()?))
        })
        .collect()
}

fn main() {
    let mut r = Rig::new(Setup {
        world: true,
        craft: true,
        life: true,
        fixtures: vec![("schism_magic".into(), MAGIC.into()), ("schism_tech".into(), TECH.into())],
        ..Setup::default()
    });
    r.join(PLAYER);
    r.tick(1);

    let mut bought: Vec<(u32, &str)> = Vec::new();
    let mut rows: Vec<(u32, Vec<(String, i64)>, usize)> = Vec::new();
    let mut minute = 0;
    let mut steps = timeline().into_iter().peekable();
    while minute <= 180 {
        while let Some((m, _)) = steps.peek() {
            if *m > minute {
                break;
            }
            let (_, step) = steps.next().unwrap();
            match step {
                Say(text) => r.say(text),
                Move(x, y, z) => r.moved(PLAYER, (x, y, z), Some((x, y + 1, z))),
                Study(id) => r.say(&format!("c make {MOD}:{id}")),
            }
        }
        // Buy the cheapest shared node there is insight for, while any.
        loop {
            let mut best: Option<&str> = None;
            for id in SHARED {
                if bought.iter().any(|(_, b)| b == id) {
                    continue;
                }
                if r.ask(&format!("m unlock {id}")) == "true nil" {
                    best = Some(id);
                    break;
                }
            }
            match best {
                Some(id) => bought.push((minute, id)),
                None => break,
            }
        }
        if minute % 10 == 0 {
            rows.push((minute, ledger(&mut r), bought.len()));
        }
        r.tick(20); // a second of play each minute stands in for the minute
        minute += 1;
    }
    r.heard(PLAYER);

    // The table.
    let mut sources: Vec<String> = rows.iter().flat_map(|(_, l, _)| l.iter().map(|(s, _)| s.clone())).collect();
    sources.sort();
    sources.dedup();
    let earned: Vec<&String> = sources.iter().filter(|s| *s != "spent").collect();

    let mut out = String::new();
    let _ = writeln!(out, "<!-- SPDX-FileCopyrightText: Iridesium -->");
    let _ = writeln!(out, "<!-- SPDX-License-Identifier: GPL-3.0-only -->\n");
    let _ = writeln!(out, "# Pacing\n");
    let _ = writeln!(
        out,
        "How fast the climb goes: insight earned by source over a player's first\n\
         three hours, and when each shared node came within reach.\n\n\
         **Two kinds of number live here, and only one is a measurement.**\n\n\
         - **The model** (below) is written by `cargo run --manifest-path\n  \
         tests/native/Cargo.toml --bin pacing`: a timeline of what one player\n  \
         does and when — a guess at Craft's loop from Craft's own timings, in\n  \
         `tests/native/src/bin/pacing.rs` — played through the mod in the\n  \
         engine's real VM, buying the cheapest shared node whenever it can. It\n  \
         checks the arithmetic of `config.lua` against a plausible climb. It\n  \
         does not say how long the climb really takes.\n\
         - **A measurement** is a real session's ledger. Every change to a\n  \
         player's insight is kept per source (`t:<uuid>:<source>`), shown to\n  \
         them by `progress sources`, and logged by the server as a line\n  \
         `tiamat_default_progress: pacing t=<tick> player=<id> source=<source>\n  \
         delta=<n> total=<n>` while `pacing_log` is on. A playtest's log is\n  \
         the table below with real minutes in it.\n\
         - **The pacing bot** measures the exploring half for real:\n  \
         `python tools/pacing/run.py --minutes N` walks the engine's `bot`\n  \
         across a fresh world on a real server with the default mods, and\n  \
         writes \"Measured: walking\" at the end of this file. Craft's loop\n  \
         wants blocks placed by numeric id, which a bot script cannot look up\n  \
         by name, so that half is a person's session for now.\n"
    );
    let _ = writeln!(out, "## The model\n");
    let _ = write!(out, "| Minute |");
    for s in &earned {
        let _ = write!(out, " {s} |");
    }
    let _ = writeln!(out, " Earned | Spent | Nodes |");
    let _ = write!(out, "|---|");
    for _ in &earned {
        let _ = write!(out, "---|");
    }
    let _ = writeln!(out, "---|---|---|");
    for (m, l, nodes) in &rows {
        let get = |s: &str| l.iter().find(|(k, _)| k == s).map_or(0, |(_, n)| *n);
        let _ = write!(out, "| {m} |");
        let mut total = 0;
        for s in &earned {
            let n = get(s);
            total += n;
            let _ = write!(out, " {n} |");
        }
        let _ = writeln!(out, " {total} | {} | {nodes} |", -get("spent"));
    }
    let _ = writeln!(out, "\n## When each shared node was bought\n");
    let _ = writeln!(out, "| Minute | Node |");
    let _ = writeln!(out, "|---|---|");
    for (m, id) in &bought {
        let _ = writeln!(out, "| {m} | `{id}` |");
    }
    let not_bought: Vec<&&str> = SHARED.iter().filter(|id| !bought.iter().any(|(_, b)| b == *id)).collect();
    if !not_bought.is_empty() {
        let list: Vec<String> = not_bought.iter().map(|id| format!("`{id}`")).collect();
        let _ = writeln!(out, "\nNot reached in three hours: {}.", list.join(", "));
    }

    let path = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../docs/pacing.md");
    let old = std::fs::read_to_string(&path).unwrap_or_default();
    // Keep what a person wrote after the model's tables: the reading of it.
    let tail = old.find("\n## Reading it").map(|i| old[i..].to_owned()).unwrap_or_default();
    std::fs::write(&path, format!("{out}{tail}")).expect("docs/pacing.md written");
    print!("{out}");
}

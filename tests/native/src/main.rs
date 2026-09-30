// SPDX-FileCopyrightText: Iridesium
// SPDX-License-Identifier: GPL-3.0-only
//
// The mod, run for real: the engine's script VM with a fake server around it
// (rig.rs), stand-ins for the world, Craft and the interface below it, and
// fixture mods above it that use its exports the way the magic and tech mods
// will — including the calls they must be refused.

// The rig carries fakes not every test reads.
#[allow(dead_code)]
mod rig;

use rig::{MOD, OTHER, PLAYER, Rig, Setup, hex};
use tiamat_core::script::{ChatEvent, ScriptVm};

const MAGIC: &str = include_str!("../fixtures/magic.lua");
const TECH: &str = include_str!("../fixtures/tech.lua");

fn paths() -> Vec<(String, String)> {
    vec![("schism_magic".into(), MAGIC.into()), ("schism_tech".into(), TECH.into())]
}

fn op(r: &Rig, player: [u8; 32]) {
    r.huds.operators.lock().unwrap().push(player);
}

fn main() {
    load_alone();
    graph();
    insight_and_persistence();
    discoveries();
    research();
    unlocking();
    fork();
    one_door();
    repath();
    shared_gates();
    creative();
    interface();
    survival();
    determinism();
    println!("progress native check: all passed");
}

/// On a bare engine: loads, keeps a record, and the plain dialog works.
fn load_alone() {
    let mut r = Rig::new(Setup::default());
    r.join(PLAYER);
    r.tick(1);
    assert_eq!(r.ask("progress"), "Insight 0. Path: none yet. Nodes known: 0.");

    // A sentence that only starts with the word is chat.
    let out = r.vm.chat(&ChatEvent { player: PLAYER, text: "progress is slow".into() });
    assert!(out.allowed, "a sentence is let through");

    // The research key opens a dialog when there is no interface.
    r.action(PLAYER, &format!("{MOD}:research"));
    let (form, tree) = r.last_dialog().expect("a dialog");
    assert_eq!(form, format!("{MOD}:research"));
    assert!(tree.contains("No door has been built in this world yet."), "{tree}");
    assert!(tree.contains("Firecraft") && tree.contains("Beyond the Fork"));
    assert!(tree.contains("Charcoal clamp (15 insight). A log gives a third more charcoal. Needs Firecraft."), "a node's price, lesson and needs are on hover");
    r.press(PLAYER, "research", "node:shared.hafting");
    assert!(r.last_dialog().unwrap().1.contains("Hafting needs 15 insight; you have 0"));
    r.press(PLAYER, "research", "view:studies");
    assert!(r.last_dialog().unwrap().1.contains("There is no research table without Craft."));

    // Without Craft, the research table says why it does nothing.
    assert!(r.use_block(PLAYER, "research_table"));
    assert_eq!(r.said(), "A research table wants Craft's stations, and Craft is not in this world.");
    assert_eq!(r.ask("progress sources"), "No insight yet.");

    // The operator's words are the operator's.
    assert_eq!(r.ask("progress insight 40"), "progress insight is for operators");
    op(&r, PLAYER);
    assert_eq!(r.ask("progress insight 40"), "insight 40");
    r.press(PLAYER, "research", "node:shared.hafting");
    assert_eq!(r.said(), "Learned: Hafting");
    assert!(r.last_dialog().unwrap().1.contains("Learned Hafting."));
    assert_eq!(r.ask("progress"), "Insight 25. Path: none yet. Nodes known: 1.");
    assert_eq!(r.stored(&format!("p:{}:insight", hex(PLAYER))).as_deref(), Some("Number(25.0)"));
    assert!(r.hud(PLAYER).contains("25"), "the HUD has the number: {}", r.hud(PLAYER));
    println!("load alone: ok");
}

/// Nodes from other mods, validated when mods have loaded: each bad one is
/// disabled and nothing else.
fn graph() {
    let mut r = Rig::new(Setup { fixtures: paths(), ..Setup::default() });
    r.join(PLAYER);
    r.tick(1);
    let nodes = r.ask("m nodes");
    assert!(nodes.starts_with("17 shared.firecraft shared.fire_setting"), "{nodes}");
    assert!(nodes.ends_with("shared.fork magic.attune tech.steam magic.focus magic.deep"), "{nodes}");
    for bad in ["magic.stray", "magic.loop_a", "magic.loop_b", "magic.after_loop", "magic.dangling", "shared.leans", "ghost.node"] {
        assert!(!nodes.contains(bad), "{bad} is disabled");
        assert_eq!(r.ask(&format!("m has {bad}")), "false");
    }
    assert_eq!(r.ask("m late"), "nil nodes are registered while mods load");
    assert_eq!(r.ask("m bad"), "false nil");
    assert_eq!(r.ask("m unlock magic.stray"), "nil there is no such thing to learn");
    r.assert_healthy("the graph");
    println!("graph: ok");
}

/// Awards clamp at zero, persist, and the cache rebuilt on a new session is
/// what storage says.
fn insight_and_persistence() {
    let setup = Setup { fixtures: paths(), ..Setup::default() };
    let mut r = Rig::new(setup.clone());
    r.join(PLAYER);
    r.tick(1);
    assert_eq!(r.ask("m award -50"), "0");
    assert_eq!(r.ask("m award 30"), "30");
    assert_eq!(r.ask("m award -12"), "18");
    op(&r, PLAYER);
    r.say("progress grant shared.hafting");
    assert_eq!(r.ask("m spark"), "true");
    assert_eq!(r.ask("m spark"), "false");
    assert_eq!(r.ask("progress"), "Insight 24. Path: none yet. Nodes known: 1.");
    r.tick(120);
    r.leave(PLAYER);

    // The same world, opened again.
    let storage = r.storage.clone();
    let mut again = Rig::with_storage(setup, storage);
    again.join(PLAYER);
    again.tick(1);
    assert_eq!(again.ask("progress"), "Insight 24. Path: none yet. Nodes known: 1.");
    assert_eq!(again.ask("m spark"), "false", "a discovery is kept");
    assert_eq!(again.ask("m has shared.hafting"), "true");
    assert!(again.stored("clock").is_some(), "the clock is kept");
    println!("insight and persistence: ok");
}

/// Biomes and depths from where a player's feet arrive; firsts from Craft.
fn discoveries() {
    let mut r = Rig::new(Setup { world: true, craft: true, ..Setup::default() });
    r.join(PLAYER);
    r.tick(200);
    assert!(r.heard(PLAYER).is_empty(), "nothing is polled: standing still, nobody has been anywhere");
    // The engine's first placement of a joining body is not where they
    // stand: it can be far under the ground. Nothing is discovered there.
    r.moved(PLAYER, (-40, -3000, 100), None);
    assert!(r.heard(PLAYER).is_empty(), "no jackpot on join");
    r.moved(PLAYER, (100, 64, 100), Some((-40, -3000, 100)));
    assert_eq!(r.heard(PLAYER), vec!["Discovered: Temperate Woodlands (+3 insight)"], "the world's own name");
    r.moved(PLAYER, (101, 64, 100), Some((100, 64, 100)));
    assert!(r.heard(PLAYER).is_empty(), "once");
    r.moved(PLAYER, (-51, 64, 100), Some((101, 64, 100)));
    assert_eq!(r.heard(PLAYER), vec!["Discovered: The Taiga (+3 insight)"]);
    r.moved(PLAYER, (-51, -55, 100), Some((-51, 64, 100)));
    assert_eq!(r.heard(PLAYER), vec!["Discovered: 60 blocks down (+5 insight)"], "65 under the ground, by the world's measure");
    r.moved(PLAYER, (-51, -250, 100), Some((-51, 64, 100)));
    assert_eq!(r.heard(PLAYER), vec!["Discovered: 200 blocks down (+8 insight)"]);
    assert!(r.ask("progress where").starts_with("at -51 -250 100 t="), "where the feet are, for the pacing bot");

    // Craft's firsts: the root of the tree comes with the first fire.
    r.say("c first fire:lit");
    assert_eq!(r.heard(PLAYER), vec!["Learned: Firecraft", "Discovered: Fire, made by your own hand (+5 insight)"]);
    r.say("c first forge:iron_bar");
    assert_eq!(r.heard(PLAYER), vec!["Discovered: A first forging (+10 insight)", "Discovered: Wrought iron (+10 insight)"]);
    r.say("c first forge:iron_pick_head");
    assert!(r.heard(PLAYER).is_empty(), "the first forging was the bar");
    r.say("c make tiamat_default_craft:stick");
    assert_eq!(r.said(), "made", "a recipe no discovery names is nothing");
    r.say("c broke");
    assert_eq!(r.said(), "Discovered: A tool worn to nothing (+7 insight)");
    r.say("c broke");
    assert!(r.heard(PLAYER).is_empty());
    assert_eq!(r.ask("progress"), "Insight 51. Path: none yet. Nodes known: 1.");

    // The Discoveries view.
    r.action(PLAYER, &format!("{MOD}:research"));
    r.press(PLAYER, "research", "view:discoveries");
    let tree = r.last_dialog().unwrap().1;
    assert!(tree.contains("Biomes: 2 of 3") && tree.contains("The Taiga") && tree.contains("Savanna") && tree.contains("Wrought iron"), "{tree}");
    assert!(!tree.contains("The Dunes"), "a biome this world does not hold is not listed");
    println!("discoveries: ok");
}

/// The research table and its studies go into Craft; a study made pays.
fn research() {
    let mut r = Rig::new(Setup { world: true, craft: true, fixtures: paths(), ..Setup::default() });
    r.join(PLAYER);
    r.tick(1);
    assert_eq!(r.ask("c stations"), "hand tiamat_default_progress:research_table workbench");
    assert_eq!(
        r.ask("c recipe tiamat_default_progress:study_copper"),
        "tiamat_default_progress:study_copper at tiamat_default_progress:research_table, \
         tiamat_default_craft:copper_ingot -> 0, 600 ticks, requires nil"
    );
    assert_eq!(
        r.ask("c recipe tiamat_default_progress:research_table"),
        "tiamat_default_progress:research_table at workbench, tiamat_default_craft:plank+tiamat_default_craft:cord\
         +tiamat_default_world:wet_clay -> 1, 100 ticks, requires nil"
    );
    assert!(r.ask("c recipe schism_magic:study_herb").starts_with("schism_magic:study_herb at"), "another mod's study");
    assert_eq!(r.ask("c make tiamat_default_progress:study_copper"), "made");
    assert_eq!(r.ask("c make tiamat_default_progress:study_orichalcum"), "made");
    assert_eq!(r.ask("c make schism_magic:study_herb"), "made");
    assert_eq!(r.ask("progress"), "Insight 93. Path: none yet. Nodes known: 0.");
    assert!(r.hud(PLAYER).contains("Study orichalcum") || r.hud(PLAYER).contains("Study herb"), "{}", r.hud(PLAYER));

    // The table is Craft's to open, as every station is.
    assert!(!r.use_block(PLAYER, "research_table"), "left to Craft");
    assert_eq!(r.ask("progress sources"), "Insight by source: study +93.");

    // A carved shape, from the hand: once per mask.
    r.hold_shape(PLAYER, "tiamat_default_world:stone", 0b111, 2);
    r.action(PLAYER, &format!("{MOD}:research"));
    r.press(PLAYER, "research", "shape");
    assert!(r.last_dialog().unwrap().1.contains("The shape is understood."));
    assert_eq!(r.units(PLAYER, "tiamat_default_world:stone"), 3, "one of the two was used");
    r.press(PLAYER, "research", "shape");
    assert!(r.last_dialog().unwrap().1.contains("you have studied that shape already"));
    assert_eq!(r.ask("progress"), "Insight 101. Path: none yet. Nodes known: 0.");
    assert_eq!(r.ask("progress sources"), "Insight by source: shape +8, study +93.");
    println!("research: ok");
}

/// Prerequisites, the price and the lock; effects summed per player.
fn unlocking() {
    let mut r = Rig::new(Setup { craft: true, fixtures: paths(), ..Setup::default() });
    r.join(PLAYER);
    r.join(OTHER);
    r.tick(1);
    op(&r, PLAYER);
    r.say("progress insight 100");
    assert_eq!(r.ask("m unlock shared.fire_setting"), "nil Fire-setting needs Firecraft first");
    assert_eq!(r.ask("m unlock shared.firecraft"), "nil Firecraft is not learned; it comes");
    assert_eq!(r.ask("m unlock shared.fork"), "nil The Fork is not learned; it comes");
    r.say("c first fire:lit");
    assert_eq!(r.ask("m unlock shared.fire_setting"), "true nil");
    assert_eq!(r.ask("m unlock shared.fire_setting"), "nil you know Fire-setting already");
    assert_eq!(r.ask("progress"), "Insight 95. Path: none yet. Nodes known: 2.", "10 spent, 5 found");
    assert_eq!(r.ask("m unlock magic.attune"), "nil Attunement lies beyond the Fork");
    assert_eq!(r.ask("m unlock shared.stonewright"), "true nil");
    assert_eq!(r.ask("m effects craft."), "craft.anvil_strikes=-1 craft.chisel_wear_percent=-50 craft.fireset_ticks=-200");
    assert_eq!(r.ask("m effects"), "craft.anvil_strikes=-1 craft.chisel_wear_percent=-50 craft.fireset_ticks=-200");
    assert_eq!(r.ask("c effect craft.fireset_ticks"), "-200", "Craft reads them through set_effects");
    assert_eq!(r.ask("c effect craft.mould_pours"), "0");
    r.say("progress insight 10");
    assert_eq!(r.ask("m unlock shared.hafting"), "nil Hafting needs 15 insight; you have 10");
    assert_eq!(r.ask("progress"), "Insight 10. Path: none yet. Nodes known: 3.", "nothing taken for a refusal");

    // Another player's record is theirs.
    r.heard(OTHER);
    r.say_as(OTHER, "m effects");
    assert_eq!(r.heard(OTHER), vec![""]);

    // The payback: first charcoal after the clamp.
    r.say("progress insight 15");
    assert_eq!(r.ask("m unlock shared.charcoal_clamp"), "true nil");
    r.say("c make tiamat_default_craft:charcoal");
    r.say("c make tiamat_default_craft:charcoal");
    assert_eq!(r.ask("progress"), "Insight 5. Path: none yet. Nodes known: 4.", "paid once");
    assert_eq!(
        r.ask("progress sources"),
        "Insight by source: found_making +5, operator +60, payback +5, spent -65.",
        "the ledger: what paid, what was spent, and the operator's hand"
    );
    println!("unlocking: ok");
}

/// Two doors: the Keystone opens one, the choice closes the other.
fn fork() {
    let mut r = Rig::new(Setup { world: true, craft: true, fixtures: paths(), ..Setup::default() });
    r.join(PLAYER);
    r.join(OTHER);
    r.tick(1);
    op(&r, PLAYER);

    // The Keystone is gated by its node, in every world.
    assert_eq!(
        r.ask("c recipe tiamat_default_progress:keystone"),
        "tiamat_default_progress:keystone at workbench, tiamat_default_world:orichalcum+tiamat_default_craft:gold_ingot\
         +tiamat_default_craft:iron_frame -> 1, 200 ticks, requires shared.keystone"
    );
    assert_eq!(
        r.ask("c recipe tiamat_default_progress:door_magic"),
        "tiamat_default_progress:door_magic at workbench, tiamat_default_progress:keystone\
         +tiamat_default_craft:silver_ingot -> 1, 200 ticks, requires shared.keystone"
    );
    assert_eq!(r.ask("c recipe tiamat_default_progress:door_tech"), "no recipe", "tech gave no recipe");
    assert_eq!(r.ask("c make tiamat_default_progress:keystone"), "refused");
    assert!(r.use_block(PLAYER, "schism_magic:attunement_stone"));
    assert_eq!(r.said(), "The door is shut to you. Learn the Keystone first.");

    r.say("progress grant shared.keystone");
    assert_eq!(r.said(), "Learned: The Keystone");
    assert_eq!(r.ask("c make tiamat_default_progress:keystone"), "made");

    // The door asks first; "not yet" changes nothing.
    assert!(r.use_block(PLAYER, "schism_magic:attunement_stone"));
    let (form, tree) = r.last_dialog().unwrap();
    assert_eq!(form, format!("{MOD}:fork"));
    assert!(tree.contains("This binds you. The other door closes.") && tree.contains("The Attuned"), "{tree}");
    r.press(PLAYER, "fork", "no");
    assert_eq!(r.ask("m path"), "nil");

    assert!(r.use_block(PLAYER, "schism_magic:attunement_stone"));
    r.heard(OTHER);
    r.press(PLAYER, "fork", "yes");
    assert_eq!(r.said(), "You have chosen: The Attuned. The other door is closed to you.");
    assert_eq!(r.heard(OTHER), vec!["Somebody near you has chosen: The Attuned."]);
    assert_eq!(r.ask("m path"), "magic");
    assert_eq!(r.ask("m has shared.fork"), "true");
    assert_eq!(r.ask("m chosen"), "1|magic|");

    // The path's own nodes open; the other's never do.
    assert_eq!(r.ask("m has magic.attune"), "false");
    r.say("progress insight 300");
    assert_eq!(r.ask("m unlock magic.attune"), "true nil");
    assert_eq!(r.ask("m effects magic."), "magic.mana_max=10");
    let before = r.ask("progress");
    assert_eq!(r.ask("c make tiamat_default_progress:study_copper"), "made");
    let after = r.ask("progress");
    let insight = |line: &str| line.split_whitespace().nth(1).unwrap().trim_end_matches('.').parse::<i64>().unwrap();
    assert_eq!(insight(&after) - insight(&before), 12, "a study pays 20 per cent more with the node that says so");
    assert_eq!(r.ask("m unlock tech.steam"), "nil Steam belongs to the other path");
    assert_eq!(r.ask("progress grant tech.steam"), "Steam is tech's; take that path first");
    assert!(r.use_block(PLAYER, "schism_tech:analytical_engine"));
    assert_eq!(r.said(), "The dials mean nothing to you.");
    assert!(r.use_block(PLAYER, "schism_magic:attunement_stone"));
    assert_eq!(r.said(), "You are already of The Attuned.");

    // The tree shows your path, and not the other.
    r.action(PLAYER, &format!("{MOD}:research"));
    let tree = r.last_dialog().unwrap().1;
    assert!(tree.contains("The Attuned (your path)") && !tree.contains("The Engineers"), "{tree}");

    // Somebody else, without the Keystone, is shut out.
    r.say_as(OTHER, "m has magic.attune");
    assert_eq!(r.heard(OTHER), vec!["false"]);
    assert!(r.use_block(OTHER, "schism_tech:analytical_engine"));
    assert_eq!(r.heard(OTHER), vec!["The door is shut to you. Learn the Keystone first."]);
    println!("fork: ok");
}

/// No path: the Fork is a locked room. One path: one door, and both listed
/// before the choice only when there are two.
fn one_door() {
    let mut r = Rig::new(Setup { craft: true, ..Setup::default() });
    r.join(PLAYER);
    r.tick(1);
    op(&r, PLAYER);
    r.say("progress grant shared.keystone");
    assert_eq!(r.ask("c make tiamat_default_progress:keystone"), "made", "a Keystone with no door to take it");

    let mut r = Rig::new(Setup { craft: true, fixtures: vec![("schism_magic".into(), MAGIC.into())], ..Setup::default() });
    r.join(PLAYER);
    r.tick(1);
    r.action(PLAYER, &format!("{MOD}:research"));
    let tree = r.last_dialog().unwrap().1;
    assert!(tree.contains("The Attuned") && !tree.contains("No door has been built"), "{tree}");

    let mut r = Rig::new(Setup { craft: true, fixtures: paths(), ..Setup::default() });
    r.join(PLAYER);
    r.tick(1);
    r.action(PLAYER, &format!("{MOD}:research"));
    let tree = r.last_dialog().unwrap().1;
    assert!(tree.contains("The Attuned") && tree.contains("The Engineers"), "both, before the choice: {tree}");
    // A path's nodes by branch, and only those in sight: the Deep needs two
    // things not held, so it waits.
    assert!(tree.contains("The Fire") && tree.contains("Menstrua") && tree.contains("The Focus"), "{tree}");
    assert!(!tree.contains("The Deep") && tree.contains("1 more, not yet in sight."), "{tree}");
    println!("one door: ok");
}

/// With `repath` on, the other door takes you back, at a price and not at once.
fn repath() {
    let setup = Setup {
        craft: true,
        options: vec!["repath"],
        prelude: "tdp_overrides = { repath_cooldown = 100 }".into(),
        fixtures: paths(),
        ..Setup::default()
    };
    let mut r = Rig::new(setup);
    r.join(PLAYER);
    r.tick(1);
    op(&r, PLAYER);
    r.say("progress grant shared.keystone");
    r.say("progress path magic");
    r.say("progress insight 300");
    assert_eq!(r.ask("m unlock magic.attune"), "true nil");
    assert!(r.use_block(PLAYER, "schism_tech:analytical_engine"));
    assert_eq!(r.said(), "Not yet: you chose only 0 seconds ago.");
    r.tick(100);
    assert!(r.use_block(PLAYER, "schism_tech:analytical_engine"));
    let tree = r.last_dialog().unwrap().1;
    assert!(tree.contains("Abandon The Attuned and take this door?"), "{tree}");
    r.press(PLAYER, "fork", "yes");
    assert_eq!(r.said(), "You have turned to The Engineers. What you knew of the other is gone.");
    assert_eq!(r.ask("m path"), "tech");
    assert_eq!(r.ask("m has magic.attune"), "false");
    assert_eq!(r.ask("m has shared.keystone"), "true", "shared nodes are never touched");
    assert_eq!(r.ask("progress"), "Insight 100. Path: The Engineers. Nodes known: 2.", "half of 200 kept");
    assert_eq!(r.ask("m chosen"), "1|magic|magic>tech");
    assert!(!r.storage.dump().contains(&format!("n:{}:magic.attune", hex(PLAYER))), "the old path's keys are gone");
    println!("repath: ok");
}

/// With `shared_gates` on, three families of Craft's recipes need a node.
fn shared_gates() {
    let mut r = Rig::new(Setup { craft: true, options: vec!["shared_gates"], ..Setup::default() });
    r.join(PLAYER);
    r.tick(1);
    for (recipe, node) in [
        ("tiamat_default_craft:bronze_ingot", "shared.kiln_lore"),
        ("tiamat_default_craft:iron_bloom", "shared.bellows_craft"),
        ("tiamat_default_craft:iron_pick_head", "shared.tempering"),
        ("tiamat_default_craft:first_iron_hammer_head", "shared.tempering"),
        ("tiamat_default_craft:stick", "nil"),
    ] {
        assert!(r.ask(&format!("c recipe {recipe}")).ends_with(&format!("requires {node}")), "{recipe}");
    }
    assert_eq!(r.ask("c make tiamat_default_craft:bronze_ingot"), "refused");
    op(&r, PLAYER);
    r.say("progress grant shared.kiln_lore");
    assert_eq!(r.ask("c make tiamat_default_craft:bronze_ingot"), "made");

    let mut r = Rig::new(Setup { craft: true, ..Setup::default() });
    r.join(PLAYER);
    r.tick(1);
    assert!(r.ask("c recipe tiamat_default_craft:bronze_ingot").ends_with("requires nil"), "off: nothing gated");
    println!("shared gates: ok");
}

/// A Creative world holds every shared node; the Fork still binds.
fn creative() {
    let mut r = Rig::new(Setup { craft: true, mode: Some("Creative".into()), fixtures: paths(), ..Setup::default() });
    r.join(PLAYER);
    r.tick(1);
    assert_eq!(r.ask("m has shared.tempering"), "true");
    assert_eq!(r.ask("c make tiamat_default_progress:keystone"), "made");
    assert!(r.use_block(PLAYER, "schism_magic:attunement_stone"));
    r.press(PLAYER, "fork", "yes");
    assert_eq!(r.ask("m path"), "magic");
    assert_eq!(r.ask("m has tech.steam"), "false");
    assert_eq!(r.ask("m has magic.attune"), "false", "a path's nodes are still bought");
    println!("creative: ok");
}

/// With the interface, Research is a tab on its screen.
fn interface() {
    let mut r = Rig::new(Setup { craft: true, ui: true, ..Setup::default() });
    r.join(PLAYER);
    r.tick(1);
    assert_eq!(r.ask("ui tab"), "tiamat_default_progress:research Research 40");
    r.action(PLAYER, &format!("{MOD}:research"));
    assert_eq!(r.ask("ui opened"), "tiamat_default_progress:research");
    assert!(r.last_dialog().is_none(), "no dialog of its own");
    assert_eq!(r.ask("ui has Insight 0"), "yes");
    assert_eq!(r.ask("ui press node:shared.hafting"), "true");
    assert_eq!(r.ask("ui has Hafting needs 15 insight"), "yes");
    assert_eq!(r.ask("ui press view:studies"), "true");
    assert_eq!(r.ask("ui has Study copper"), "yes");
    assert_eq!(r.ask("ui press nonsense"), "false");
    println!("interface: ok");
}

/// Life's events are discoveries; a ghost touches no door.
fn survival() {
    let mut r = Rig::new(Setup { craft: true, life: true, fixtures: paths(), ..Setup::default() });
    r.join(PLAYER);
    r.tick(1);
    r.say("l kill cave_rat");
    assert_eq!(r.said(), "Discovered: Cave rat, hunted (+2 insight)");
    r.say("l kill cave_rat");
    assert!(r.heard(PLAYER).is_empty(), "each kind once");
    r.say("l kill cow");
    r.say("l eat tiamat_default_life:raw_meat");
    r.say("l die");
    r.say("l sleep");
    assert_eq!(
        r.heard(PLAYER),
        vec![
            "Discovered: Cow, hunted (+2 insight)",
            "Discovered: Raw meat, tasted (+1 insight)",
            "Discovered: A first death (+5 insight)",
            "Discovered: A night slept through (+5 insight)",
        ]
    );
    assert_eq!(r.ask("progress"), "Insight 15. Path: none yet. Nodes known: 0.");
    r.action(PLAYER, &format!("{MOD}:research"));
    r.press(PLAYER, "research", "view:discoveries");
    let tree = r.last_dialog().unwrap().1;
    assert!(tree.contains("Cave rat, hunted") && tree.contains("Raw meat, tasted") && tree.contains("A first death"), "{tree}");

    op(&r, PLAYER);
    r.say("progress grant shared.keystone");
    r.say("l ghost");
    assert!(r.use_block(PLAYER, "schism_magic:attunement_stone"));
    assert_eq!(r.said(), "Your hand passes through the door. The dead choose nothing.");
    assert_eq!(r.ask("m path"), "nil");
    println!("survival: ok");
}

/// The same play twice gives the same storage, key for key.
fn determinism() {
    fn play() -> String {
        let mut r = Rig::new(Setup { world: true, craft: true, fixtures: paths(), ..Setup::default() });
        r.join(PLAYER);
        r.join(OTHER);
        op(&r, PLAYER);
        r.tick(1);
        r.say("c first fire:lit");
        r.say("c make tiamat_default_progress:study_gold");
        r.say("progress insight 400");
        for node in ["shared.fire_setting", "shared.charcoal_clamp", "shared.kiln_lore", "shared.roasting"] {
            r.say(&format!("m unlock {node}"));
        }
        r.moved(OTHER, (2000, -500, 0), Some((2000, 64, 0)));
        r.moved(PLAYER, (-5, 10, 0), Some((0, 64, 0)));
        r.tick(200);
        r.say("progress grant shared.keystone");
        r.use_block(PLAYER, "schism_magic:attunement_stone");
        r.press(PLAYER, "fork", "yes");
        r.tick(150);
        r.storage.dump()
    }
    let a = play();
    let b = play();
    assert_eq!(a, b);
    assert!(a.contains("p:") && a.contains("clock"), "{a}");
    println!("determinism: ok");
}

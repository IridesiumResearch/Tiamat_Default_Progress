// SPDX-FileCopyrightText: Iridesium
// SPDX-License-Identifier: GPL-3.0-only
//
// The fake server the mod runs in.
//
// Nothing is mocked at the Lua level: the mod's own files load through
// `EngineVm::load_mod`, and its hooks fire through the same trait the server
// calls. What is faked is the world around it — a player body, an inventory,
// the world's containers, the tool in each hand, storage, a map of blocks and
// fluid, each player's chat — and each fake keeps the engine's rules where the
// mod leans on them: a container slot holds one stack, capped at ninety
// items; a take matches material, cut and detail exactly; a tool nobody
// registered is refused.

use std::{
    collections::{BTreeMap, HashMap},
    path::PathBuf,
    sync::{Arc, Mutex},
};

use tiamat_core::{
    BlockPos, MaterialId,
    ent::{self, Entity, EntityId, Owner, Transform},
    fluid::{self, Fluid, FluidId},
    hud::{self, Values},
    identity::PlayerUuid,
    inventory::{self, Shape, Stack, StackKey, stack_capacity},
    light::{Light, LightSource},
    particle::{self, BadgeRequest, EmitRequest},
    phys::Abilities,
    modload::WorldOptionValue,
    proto,
    script::{
        ActionEvent, ChatEvent, DialogEvent, EngineVm, JoinEvent, LeaveEvent, MoveEvent, ScriptVm, UseAim, UseEvent,
        VmLimits,
        WorldEdit,
    },
    sight::{self, Looked, Reading, Sighting, Skip, Surface},
    sound::{self, LoopRequest, PlayRequest},
    storage,
    ui::host::{self as uihost, ShowRequest},
};

pub const MOD: &str = "tiamat_default_progress";
pub const PLAYER: [u8; 32] = [7; 32];
pub const OTHER: [u8; 32] = [9; 32];

pub fn hex(player: [u8; 32]) -> String {
    player.iter().map(|b| format!("{b:02x}")).collect()
}

// --- Storage -------------------------------------------------------------------

#[derive(Default)]
pub struct Storage(pub Mutex<BTreeMap<(String, String), storage::Value>>);

impl storage::Access for Storage {
    fn get(&self, mod_id: &str, key: &str) -> Option<storage::Value> {
        self.0.lock().unwrap().get(&(mod_id.into(), key.into())).cloned()
    }
    fn set(&self, mod_id: &str, key: &str, value: Option<storage::Value>) {
        let mut map = self.0.lock().unwrap();
        match value {
            Some(v) => {
                map.insert((mod_id.into(), key.into()), v);
            }
            None => {
                map.remove(&(mod_id.into(), key.into()));
            }
        }
    }
    fn keys(&self, mod_id: &str, prefix: &str) -> Vec<String> {
        self.0
            .lock()
            .unwrap()
            .keys()
            .filter(|(m, k)| m == mod_id && k.starts_with(prefix))
            .map(|(_, k)| k.clone())
            .collect()
    }
}

impl Storage {
    /// This mod's storage as one sorted string, for comparing two runs.
    pub fn dump(&self) -> String {
        self.0
            .lock()
            .unwrap()
            .iter()
            .filter(|((m, _), _)| m == MOD)
            .map(|((_, k), v)| format!("{k}={v:?}"))
            .collect::<Vec<_>>()
            .join("\n")
    }
}

// --- Inventory -------------------------------------------------------------------

/// Each player's views, consolidated per material, cut and detail as the
/// engine reports them; and which stack is in the hand.
#[derive(Default)]
pub struct Inventory {
    pub views: Mutex<HashMap<([u8; 32], String), Vec<Stack>>>,
    pub held: Mutex<HashMap<[u8; 32], (MaterialId, Option<String>)>>,
}

fn same(a: &Stack, material: MaterialId, shape: Option<Shape>, detail: Option<&str>) -> bool {
    a.material == material && a.shape == shape && a.detail.as_deref() == detail
}

impl Inventory {
    pub fn units_of(&self, player: [u8; 32], material: MaterialId) -> u32 {
        self.views
            .lock()
            .unwrap()
            .get(&(player, "player:main".into()))
            .map(|v| v.iter().filter(|s| s.material == material).map(|s| s.units).sum())
            .unwrap_or(0)
    }
    pub fn stacks(&self, player: [u8; 32]) -> Vec<Stack> {
        self.views.lock().unwrap().get(&(player, "player:main".into())).cloned().unwrap_or_default()
    }
    pub fn put(&self, player: [u8; 32], stack: Stack) {
        inventory::Access::give(self, player, "player:main", None, stack);
    }
    pub fn clear(&self, player: [u8; 32]) {
        self.views.lock().unwrap().remove(&(player, "player:main".into()));
        self.held.lock().unwrap().remove(&player);
    }
}

impl inventory::Access for Inventory {
    fn contents(&self, player: [u8; 32], view: &str) -> Vec<Stack> {
        self.views.lock().unwrap().get(&(player, view.to_owned())).cloned().unwrap_or_default()
    }
    /// The view is kept consolidated, so a named slot lands where any give
    /// would: nothing here reads slot positions in a player's view.
    /// Answers the units that did not go in: none, since the view grows.
    fn give(&self, player: [u8; 32], view: &str, _slot: Option<usize>, stack: Stack) -> u32 {
        let mut views = self.views.lock().unwrap();
        let list = views.entry((player, view.to_owned())).or_default();
        if let Some(existing) = list.iter_mut().find(|s| same(s, stack.material, stack.shape, stack.detail.as_deref())) {
            existing.units += stack.units;
        } else {
            list.push(stack);
        }
        0
    }
    /// Slot positions are not kept, and nothing here reads one.
    fn slot(&self, _: [u8; 32], _: &str, _: usize) -> Option<Stack> {
        None
    }
    fn held(&self, player: [u8; 32]) -> Option<Stack> {
        let (material, detail) = self.held.lock().unwrap().get(&player).cloned()?;
        self.views
            .lock()
            .unwrap()
            .get(&(player, "player:main".into()))?
            .iter()
            .find(|s| s.material == material && s.detail == detail)
            .cloned()
    }
    fn take(
        &self,
        player: [u8; 32],
        view: &str,
        _slot: Option<usize>,
        which: StackKey<'_>,
        units: u32,
    ) -> u32 {
        let mut views = self.views.lock().unwrap();
        let Some(list) = views.get_mut(&(player, view.to_owned())) else { return 0 };
        let mut got = 0;
        for stack in list.iter_mut() {
            if which.matches(stack) {
                let take = units.saturating_sub(got).min(stack.units);
                stack.units -= take;
                got += take;
            }
        }
        list.retain(|s| s.units > 0);
        got
    }
}

// --- Containers -------------------------------------------------------------------

#[derive(Default)]
pub struct Boxes {
    pub slots: Mutex<BTreeMap<String, Vec<Option<Stack>>>>,
    pub holders: Mutex<HashMap<String, [u8; 32]>>,
}

impl Boxes {
    /// Puts a stack straight into a slot (one-based), replacing what was there.
    pub fn set(&self, name: &str, slot: usize, stack: Option<Stack>) {
        let mut all = self.slots.lock().unwrap();
        let list = all.get_mut(name).unwrap_or_else(|| panic!("no container {name}"));
        list[slot - 1] = stack;
    }
    pub fn get(&self, name: &str, slot: usize) -> Option<Stack> {
        self.slots.lock().unwrap().get(name).and_then(|l| l.get(slot - 1).cloned().flatten())
    }
    pub fn exists(&self, name: &str) -> bool {
        self.slots.lock().unwrap().contains_key(name)
    }
}

impl inventory::Containers for Boxes {
    fn ensure(&self, name: &str, slots: usize) -> bool {
        let mut all = self.slots.lock().unwrap();
        if all.contains_key(name) {
            return false;
        }
        all.insert(name.to_owned(), vec![None; slots]);
        true
    }
    fn open(&self, name: &str, player: [u8; 32]) -> bool {
        if !self.exists(name) {
            return false;
        }
        let mut holders = self.holders.lock().unwrap();
        match holders.get(name) {
            Some(p) if *p != player => false,
            _ => {
                holders.insert(name.to_owned(), player);
                true
            }
        }
    }
    fn close(&self, name: &str, player: [u8; 32]) -> bool {
        let mut holders = self.holders.lock().unwrap();
        if holders.get(name) == Some(&player) {
            holders.remove(name);
            return true;
        }
        false
    }
    fn slots(&self, name: &str) -> Vec<Option<Stack>> {
        self.slots.lock().unwrap().get(name).cloned().unwrap_or_default()
    }
    fn give(&self, name: &str, slot: Option<usize>, stack: Stack) -> u32 {
        let mut all = self.slots.lock().unwrap();
        let Some(list) = all.get_mut(name) else { return 0 };
        let cap = stack_capacity(stack.shape);
        let mut left = stack.units;
        let indices: Vec<usize> = match slot {
            // Zero-based here: the engine has already taken one off the
            // mod's one-based slot.
            Some(s) if s < list.len() => vec![s],
            Some(_) => return 0,
            // Onto matching stacks first, then into empty slots, in slot order.
            None => {
                let mut matching: Vec<usize> = (0..list.len())
                    .filter(|i| list[*i].as_ref().is_some_and(|s| same(s, stack.material, stack.shape, stack.detail.as_deref())))
                    .collect();
                matching.extend((0..list.len()).filter(|i| list[*i].is_none()));
                matching
            }
        };
        for i in indices {
            if left == 0 {
                break;
            }
            match &mut list[i] {
                Some(existing) if same(existing, stack.material, stack.shape, stack.detail.as_deref()) => {
                    let room = cap.saturating_sub(existing.units).min(left);
                    existing.units += room;
                    left -= room;
                }
                Some(_) => {}
                empty @ None => {
                    let put = cap.min(left);
                    *empty = Some(Stack { units: put, ..stack.clone() });
                    left -= put;
                }
            }
        }
        stack.units - left
    }
    fn take(
        &self,
        name: &str,
        slot: Option<usize>,
        which: StackKey<'_>,
        units: u32,
    ) -> u32 {
        let mut all = self.slots.lock().unwrap();
        let Some(list) = all.get_mut(name) else { return 0 };
        let indices: Vec<usize> = match slot {
            // Zero-based here: the engine has already taken one off the
            // mod's one-based slot.
            Some(s) if s < list.len() => vec![s],
            Some(_) => return 0,
            None => (0..list.len()).collect(),
        };
        let mut got = 0;
        for i in indices {
            if let Some(stack) = &mut list[i]
                && which.matches(stack)
            {
                let take = units.saturating_sub(got).min(stack.units);
                stack.units -= take;
                got += take;
                if stack.units == 0 {
                    list[i] = None;
                }
            }
        }
        got
    }
    fn remove(&self, name: &str) -> Vec<Stack> {
        if self.holders.lock().unwrap().contains_key(name) {
            return Vec::new();
        }
        self.slots.lock().unwrap().remove(name).unwrap_or_default().into_iter().flatten().collect()
    }
    fn holder(&self, name: &str) -> Option<[u8; 32]> {
        self.holders.lock().unwrap().get(name).copied()
    }
    fn names(&self, prefix: &str) -> Vec<String> {
        self.slots.lock().unwrap().keys().filter(|n| n.starts_with(prefix)).cloned().collect()
    }
}

// --- Tools -------------------------------------------------------------------

/// The tool in each player's hand, and every `set_tool` call, so a test can
/// count them: the engine cancels a dig on every call, so the mod must not
/// make one it does not need.
#[derive(Default)]
pub struct Tools {
    pub hand: Mutex<HashMap<[u8; 32], Option<String>>>,
    pub calls: Mutex<Vec<String>>,
    pub known: Mutex<Vec<String>>,
}

impl tiamat_core::dig::Tools for Tools {
    fn tool(&self, player: [u8; 32]) -> Option<String> {
        self.hand.lock().unwrap().get(&player).cloned().flatten()
    }
    fn set_tool(&self, player: [u8; 32], tool: Option<&str>) -> bool {
        if let Some(t) = tool
            && !self.known.lock().unwrap().iter().any(|k| k == t)
        {
            return false;
        }
        self.calls.lock().unwrap().push(tool.unwrap_or("-").to_owned());
        self.hand.lock().unwrap().insert(player, tool.map(str::to_owned));
        true
    }
}

// --- HUD, chat and operators ------------------------------------------------------

#[derive(Default)]
pub struct Huds {
    pub values: Mutex<HashMap<[u8; 32], Values>>,
    pub operators: Mutex<Vec<[u8; 32]>>,
    pub chat: Mutex<Vec<([u8; 32], String)>>,
}

impl hud::Access for Huds {
    fn set_hud(&self, mod_id: &str, player: [u8; 32], values: Values) -> bool {
        if mod_id == MOD {
            self.values.lock().unwrap().insert(player, values);
        }
        true
    }
    fn is_operator(&self, player: [u8; 32]) -> bool {
        self.operators.lock().unwrap().contains(&player)
    }
    fn chat_to(&self, player: [u8; 32], text: &str) -> bool {
        self.chat.lock().unwrap().push((player, text.to_owned()));
        true
    }
}

// --- Dialogs, sounds, particles -----------------------------------------------------

#[derive(Default)]
pub struct Dialogs {
    pub shown: Mutex<Vec<ShowRequest>>,
    pub closed: Mutex<Vec<(String, String)>>,
}

impl uihost::Access for Dialogs {
    fn show(&self, request: &ShowRequest) -> bool {
        tiamat_core::ui::check(&request.tree, tiamat_core::ui::Limits::default())
            .expect("every tree the mod sends passes the engine's checker");
        self.shown.lock().unwrap().push(request.clone());
        true
    }
    fn close(&self, player: &str, form: &str) -> bool {
        self.closed.lock().unwrap().push((player.to_owned(), form.to_owned()));
        true
    }
}

#[derive(Default)]
pub struct Sounds {
    pub plays: Mutex<Vec<String>>,
    pub time: Mutex<f32>,
}

impl sound::Access for Sounds {
    fn play(&self, request: &PlayRequest) -> u32 {
        self.plays.lock().unwrap().push(request.sound.clone());
        1
    }
    fn start_loop(&self, _: &LoopRequest) -> u32 {
        1
    }
    fn time_of_day(&self) -> f32 {
        *self.time.lock().unwrap()
    }
    fn stop_loop(&self, _: &sound::StopRequest) -> u32 {
        0
    }
    fn set_time_of_day(&self, fraction: f32) -> bool {
        *self.time.lock().unwrap() = fraction.rem_euclid(1.0);
        true
    }
}

#[derive(Default)]
pub struct Particles(pub Mutex<Vec<EmitRequest>>);

impl particle::Access for Particles {
    fn emit(&self, request: &EmitRequest) -> u32 {
        self.0.lock().unwrap().push(request.clone());
        1
    }
    fn show_over(&self, _: &BadgeRequest) -> u32 {
        1
    }
}

// --- The world -----------------------------------------------------------------

#[derive(Default)]
pub struct World {
    pub blocks: Mutex<HashMap<(i32, i32, i32), (MaterialId, u32)>>,
    pub fluids: Mutex<HashMap<(i32, i32, i32), u32>>,
    pub edits: Mutex<Vec<(BlockPos, String)>>,
    pub aimed: Mutex<Option<(i32, i32, i32)>>,
    pub names: Mutex<HashMap<String, MaterialId>>,
}

impl World {
    pub fn put(&self, x: i32, y: i32, z: i32, material: MaterialId) {
        self.blocks.lock().unwrap().insert((x, y, z), (material, 0x7FF_FFFF));
    }
    pub fn apply(&self, pos: BlockPos, block: &str) {
        self.edits.lock().unwrap().push((pos, block.to_owned()));
        let key = (pos.x, pos.y, pos.z);
        if block == "engine:air" {
            self.blocks.lock().unwrap().insert(key, (MaterialId(0), 0));
        } else if let Some(material) = self.names.lock().unwrap().get(block) {
            self.blocks.lock().unwrap().insert(key, (*material, 0x7FF_FFFF));
        } else {
            panic!("the mod wrote a block nobody registered: {block}");
        }
    }
}

impl sight::Access for World {
    fn line_of_sight(&self, _: &str, _: [f64; 3], _: [f64; 3]) -> Sighting {
        Sighting::Clear
    }
    fn looking_at(&self, uuid: [u8; 32]) -> Option<Looked> {
        let (x, y, z) = (*self.aimed.lock().unwrap())?;
        if uuid != PLAYER {
            return None;
        }
        let Reading::Single { material, occupancy } = self.block_at("", BlockPos { x, y, z }) else { return None };
        (occupancy != 0).then(|| Looked::Block {
            domain: "overworld".into(),
            cell: tiamat_core::SubNodePos { x: x * 3 + 1, y: y * 3 + 2, z: z * 3 + 1 },
            material,
            face: [0, 1, 0],
        })
    }
    fn surface_at(&self, domain: &str, column: [i32; 2], from: i32, depth: u32, _: Skip) -> Option<Surface> {
        for y in (from - depth as i32..=from).rev() {
            if let Reading::Single { material, occupancy } = self.block_at(domain, BlockPos { x: column[0], y, z: column[1] })
                && occupancy != 0
            {
                return Some(Surface { y, material, occupancy, fluid: None });
            }
        }
        None
    }
    fn block_at(&self, _: &str, pos: BlockPos) -> Reading {
        match self.blocks.lock().unwrap().get(&(pos.x, pos.y, pos.z)) {
            Some((material, occupancy)) => Reading::Single { material: *material, occupancy: *occupancy },
            None => Reading::Single { material: MaterialId(0), occupancy: 0 },
        }
    }
}

impl fluid::Access for World {
    fn fluid_at(&self, _: &str, pos: BlockPos) -> Fluid {
        match self.fluids.lock().unwrap().get(&(pos.x, pos.y, pos.z)) {
            Some(volume) => Fluid::new(FluidId(1), *volume),
            None => Fluid::EMPTY,
        }
    }
    fn set_fluid_at(&self, _: &str, pos: BlockPos, fluid: Fluid) -> bool {
        let mut fluids = self.fluids.lock().unwrap();
        if fluid.volume() == 0 {
            fluids.remove(&(pos.x, pos.y, pos.z));
        } else {
            fluids.insert((pos.x, pos.y, pos.z), fluid.volume());
        }
        true
    }
    /// The world's water is the one fluid here, number 1.
    fn fluid_id(&self, name: &str) -> Option<FluidId> {
        (name == "tiamat_default_world:water").then_some(FluidId(1))
    }
}

impl LightSource for World {
    fn light_at(&self, _: &str, _: BlockPos) -> Light {
        Light::DAYLIGHT
    }
}

impl WorldEdit for World {
    fn set_block(&self, _: &str, pos: BlockPos, block: &str) -> bool {
        self.apply(pos, block);
        true
    }
    fn set_partial(&self, _: &str, pos: BlockPos, block: &str, _: u32) -> bool {
        self.apply(pos, block);
        true
    }
    fn merge_partial(&self, _: &str, pos: BlockPos, block: &str, _: u32) -> bool {
        self.apply(pos, block);
        true
    }
}

// --- Entities: the player's body --------------------------------------------------

#[derive(Clone)]
pub struct Entities(pub Arc<Mutex<HashMap<u64, Entity>>>);

impl Entities {
    fn new() -> Self {
        let mut map = HashMap::new();
        for (id, who) in [(1, PLAYER), (2, OTHER)] {
            let mut body = Entity::at(Transform::from_world(100.5, 64.0, 100.5), "engine:player");
            body.owner = Some(Owner(PlayerUuid::from_bytes(who)));
            body.on_ground = true;
            map.insert(id, body);
        }
        Self(Arc::new(Mutex::new(map)))
    }
}

impl ent::Access for Entities {
    fn spawn(&self, entity: Entity) -> Option<EntityId> {
        let mut map = self.0.lock().unwrap();
        let id = map.keys().max().copied().unwrap_or(0) + 1;
        map.insert(id, entity);
        Some(EntityId(id))
    }
    fn despawn(&self, id: EntityId) -> bool {
        self.0.lock().unwrap().remove(&id.0).is_some()
    }
    fn get(&self, id: EntityId) -> Option<Entity> {
        self.0.lock().unwrap().get(&id.0).cloned()
    }
    fn patch(&self, id: EntityId, patch: &ent::Patch) -> bool {
        match self.0.lock().unwrap().get_mut(&id.0) {
            Some(entity) => patch.apply(entity),
            None => false,
        }
    }
    fn player(&self, uuid: [u8; 32]) -> Option<EntityId> {
        match uuid {
            PLAYER => Some(EntityId(1)),
            OTHER => Some(EntityId(2)),
            _ => None,
        }
    }
    fn within(&self, centre: [f64; 3], radius: f64, _: Option<&str>) -> Vec<EntityId> {
        let mut near: Vec<(u64, f64)> = self
            .0
            .lock()
            .unwrap()
            .iter()
            .map(|(id, e)| {
                let p = e.transform.to_world();
                let d = (0..3).map(|i| (p[i] - centre[i]) * (p[i] - centre[i])).sum::<f64>();
                (*id, d)
            })
            .filter(|(_, d)| *d <= radius * radius)
            .collect();
        near.sort_by(|a, b| a.1.total_cmp(&b.1).then(a.0.cmp(&b.0)));
        near.into_iter().map(|(id, _)| EntityId(id)).collect()
    }
    fn move_player(&self, _: [u8; 32], _: [f64; 3]) -> bool {
        true
    }
    fn select_slot(&self, _: [u8; 32], _: u16) -> bool {
        true
    }
    fn shove_player(&self, _: [u8; 32], _: [f32; 3]) -> bool {
        true
    }
    fn transfer(&self, _: EntityId, _: &str, _: [f64; 3]) -> bool {
        false
    }
    fn set_abilities(&self, _: [u8; 32], _: Option<Abilities>) -> bool {
        true
    }
}

// --- The mods around this one ------------------------------------------------------

/// A stand-in for the world: the blocks this mod names, `biome_under`
/// answering by where you stand — west of 0 is taiga, east of 1000 savanna,
/// the woodland between — `biomes()` naming them (and a fourth not in this
/// world), and `depth_under` ten blocks deeper than `-y`, as a ground at
/// y = 10 would be.
pub const WORLD: &str = r##"
for _, id in ipairs({ "orichalcum", "crystal", "metal", "diamond", "wet_clay", "stone" }) do
    game.register_block{ id = id }
end
game.export{
    version = 1,
    biome_under = function(x, y, z)
        if x < 0 then return "taiga" end
        if x >= 1000 then return "savanna" end
        return "temperate_woodlands"
    end,
    biomes = function()
        return {
            { id = "temperate_woodlands", name = "Temperate Woodlands", findable = true },
            { id = "taiga", name = "The Taiga", findable = true },
            { id = "savanna", name = "Savanna", findable = true },
            { id = "dunes", name = "The Dunes", findable = false },
        }
    end,
    depth_under = function(x, y, z) return 10 - y end,
}
"##;

/// A stand-in for Craft's exports, as this mod uses them — including the
/// two this mod asked of it, `set_requires` (C1) and a recipe that
/// makes nothing (C5), both landed in Craft since, and `set_effects` (its
/// ask P1 of this mod). `c effect <key>` reads an effect the way Craft does;
/// the rest of `c ...` in chat drives it: `c first <event>` is Craft
/// noticing a first, `c make <recipe>` making one through the gate, `c broke`
/// a tool wearing out, `c recipe <id>` and `c stations` what was registered.
pub const CRAFT: &str = r##"
for _, id in ipairs({ "copper_ingot", "tin_ingot", "iron_ingot", "bronze_ingot", "iron_bar", "silver_ingot",
    "gold_ingot", "lead_ingot", "plank", "cord", "iron_frame", "charcoal", "iron_bloom" }) do
    game.register_item{ id = id }
end
local loading = true
local stations = { workbench = { id = "workbench" }, hand = { id = "hand" } }
local recipes, order, requires = {}, {}, {}
local gate, effects
local subs = { first = {}, crafted = {}, broken = {} }
local firsts = {}
local function add(r) recipes[r.id] = r; order[#order + 1] = r.id end
-- Craft's own, for the shared gates to find.
add{ id = "tiamat_default_craft:bronze_ingot", station = "kiln", heat = 2 }
add{ id = "tiamat_default_craft:iron_bloom", station = "bloomery", heat = 3 }
add{ id = "tiamat_default_craft:iron_pick_head", station = "anvil", heat = 0 }
add{ id = "tiamat_default_craft:first_iron_hammer_head", station = "anvil", heat = 0 }
add{ id = "tiamat_default_craft:stick", station = "hand", heat = 0 }
add{ id = "tiamat_default_craft:charcoal", station = "hand", heat = 0 }
local function sub(list) return function(fn)
    if type(fn) ~= "function" then return nil, "a subscriber is a function" end
    list[#list + 1] = fn
    return true
end end
game.export{
    version = 1,
    register_station = function(spec)
        if not loading then return nil, "stations are registered while mods load" end
        if stations[spec.id] then return nil, "station " .. spec.id .. " is already registered" end
        stations[spec.id] = { id = spec.id, input = spec.slots.input, output = spec.slots.output, block = spec.block }
        return true
    end,
    register = function(spec)
        if not loading then return nil, "recipes are registered while mods load" end
        if not stations[spec.station] then return nil, "no station " .. tostring(spec.station) end
        if recipes[spec.id] then return nil, "recipe " .. spec.id .. " is already registered" end
        local inputs = {}
        for i, e in ipairs(spec.inputs) do inputs[i] = tostring(e[1]) end
        add{ id = spec.id, station = spec.station, heat = spec.heat or 0, requires = spec.requires,
            outputs = #spec.outputs, inputs = table.concat(inputs, "+"), ticks = spec.ticks or 0 }
        return true
    end,
    recipes = function()
        local out = {}
        for i, id in ipairs(order) do
            local r = recipes[id]
            out[i] = { id = id, station = r.station, heat = r.heat, requires = requires[id] or r.requires }
        end
        return out
    end,
    set_gate = function(fn)
        if gate then return nil, "a gate is already set" end
        gate = fn
        return true
    end,
    set_effects = function(fn)
        if effects then return nil, "effects are already set" end
        effects = fn
        return true
    end,
    set_requires = function(id, node)
        if not recipes[id] then return nil, "no recipe" end
        requires[id] = node
        return true
    end,
    on_first = sub(subs.first),
    on_crafted = sub(subs.crafted),
    on_tool_broken = sub(subs.broken),
}
local function first(player, event)
    if firsts[player .. event] then return end
    firsts[player .. event] = true
    for _, fn in ipairs(subs.first) do fn(player, event) end
end
game.register_on_tick(function() loading = false end)
game.register_on_chat(function(e)
    local word, rest = string.match(e.text, "^c (%S+)%s*(.*)$")
    if not word then return end
    if word == "first" then
        first(e.player, rest)
    elseif word == "make" then
        local r = recipes[rest]
        local node = r and (requires[rest] or r.requires)
        if not r then
            game.chat_to(e.player, "no recipe")
        elseif node and gate and gate(e.player, node) == false then
            game.chat_to(e.player, "refused")
        else
            for _, fn in ipairs(subs.crafted) do fn(e.player, rest, {}) end
            first(e.player, "craft:" .. rest)
            game.chat_to(e.player, "made")
        end
    elseif word == "effect" then
        local fx = effects and effects(e.player, "craft.") or {}
        game.chat_to(e.player, tostring(fx[rest] or 0))
    elseif word == "broke" then
        for _, fn in ipairs(subs.broken) do fn(e.player, "tiamat_default_craft:bronze_pick") end
    elseif word == "recipe" then
        local r = recipes[rest]
        game.chat_to(e.player, r and string.format("%s at %s, %s -> %d, %d ticks, requires %s", r.id, r.station,
            tostring(r.inputs), r.outputs or -1, r.ticks or 0, tostring(requires[rest] or r.requires)) or "no recipe")
    elseif word == "stations" then
        local ids = {}
        for id in pairs(stations) do ids[#ids + 1] = id end
        table.sort(ids)
        game.chat_to(e.player, table.concat(ids, " "))
    end
    return false
end)
"##;

/// A stand-in for the interface: it keeps the tab it is given, and `ui ...`
/// in chat asks it — `ui has <text>` whether the tab's tree shows a text,
/// `ui press <name>` a button pressed on the tab, `ui opened` which tabs
/// were opened.
pub const UI: &str = r##"
local tab
local opened = {}
game.export{
    version = 1,
    theme = { colours = {} },
    add_tab = function(spec)
        if tab then return nil, "one tab here" end
        tab = spec
        return true
    end,
    open = function(player, id) opened[#opened + 1] = id return true end,
    redraw = function() end,
}
local function texts(node, out)
    if type(node) ~= "table" then return end
    if type(node.text) == "string" then out[#out + 1] = node.text end
    if type(node.children) == "table" then
        for _, child in ipairs(node.children) do texts(child, out) end
    end
end
game.register_on_chat(function(e)
    local word, rest = string.match(e.text, "^ui (%S+)%s*(.*)$")
    if not word then return end
    if word == "has" then
        local out = {}
        texts(tab.build(e.player), out)
        local found = false
        for _, t in ipairs(out) do
            if string.find(t, rest, 1, true) then found = true end
        end
        game.chat_to(e.player, found and "yes" or "no")
    elseif word == "press" then
        game.chat_to(e.player, tostring(tab.on_event(e.player, { kind = "pressed", name = rest })))
    elseif word == "opened" then
        game.chat_to(e.player, table.concat(opened, " "))
    elseif word == "tab" then
        game.chat_to(e.player, tab and (tab.id .. " " .. tab.label .. " " .. tostring(tab.order)) or "none")
    end
    return false
end)
"##;

/// A stand-in for Life, as this mod uses it: the mode, ghosts, and the
/// survival events, which `l ...` in chat raises — `l kill <kind>`,
/// `l eat <food>`, `l die`, `l sleep`, and `l ghost` to make the speaker one.
pub const LIFE: &str = r##"
local subs = { kill = {}, eat = {}, death = {}, sleep = {} }
local ghosts = {}
local function sub(list) return function(fn) list[#list + 1] = fn return true end end
game.export{
    version = 1,
    mode = function() return game.world_option("tiamat_default_life:mode") or "Default" end,
    is_ghost = function(uuid) return ghosts[uuid] == true end,
    on_kill = sub(subs.kill), on_eat = sub(subs.eat), on_death = sub(subs.death), on_sleep = sub(subs.sleep),
}
game.register_on_chat(function(e)
    local word, rest = string.match(e.text, "^l (%S+)%s*(.*)$")
    if not word then return end
    local fire = function(list, ...) for _, fn in ipairs(list) do fn(e.player, ...) end end
    if word == "kill" then fire(subs.kill, rest)
    elseif word == "eat" then fire(subs.eat, rest)
    elseif word == "die" then fire(subs.death)
    elseif word == "sleep" then fire(subs.sleep)
    elseif word == "ghost" then ghosts[e.player] = true end
    return false
end)
"##;

// --- The rig -----------------------------------------------------------------

/// Which of the world around the mod to load.
#[derive(Default, Clone)]
pub struct Setup {
    /// Lua run before init.lua, e.g. `tdp_overrides = { ... }`.
    pub prelude: String,
    /// The stand-in world (biomes).
    pub world: bool,
    /// The stand-in Craft.
    pub craft: bool,
    /// The stand-in interface.
    pub ui: bool,
    /// The stand-in Life.
    pub life: bool,
    /// Life's world option, "Default", "Creative" or "Adventure".
    pub mode: Option<String>,
    /// This mod's own world options that are on: "repath", "shared_gates".
    pub options: Vec<&'static str>,
    /// Mods that load after this one and use its exports: `(id, source)`.
    pub fixtures: Vec<(String, String)>,
}

pub struct Rig {
    pub vm: EngineVm,
    pub storage: Arc<Storage>,
    pub inventory: Arc<Inventory>,
    pub boxes: Arc<Boxes>,
    pub huds: Arc<Huds>,
    pub dialogs: Arc<Dialogs>,
    pub sounds: Arc<Sounds>,
    pub entities: Entities,
    pub materials: HashMap<String, MaterialId>,
}

impl Rig {
    pub fn new(setup: Setup) -> Self {
        Self::with_storage(setup, Arc::new(Storage::default()))
    }

    /// A rig over storage another run left behind: the same world, reopened.
    pub fn with_storage(setup: Setup, storage: Arc<Storage>) -> Self {
        let dir = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../mods").join(MOD);
        let mut vm = EngineVm::create(VmLimits::default()).unwrap();

        let inventory = Arc::new(Inventory::default());
        let boxes = Arc::new(Boxes::default());
        let tools = Arc::new(Tools::default());
        let huds = Arc::new(Huds::default());
        let dialogs = Arc::new(Dialogs::default());
        let sounds = Arc::new(Sounds::default());
        let particles = Arc::new(Particles::default());
        let world = Arc::new(World::default());
        let entities = Entities::new();

        vm.set_storage_access(storage.clone());
        vm.set_entity_access(Arc::new(entities.clone()));
        vm.set_inventory_access(inventory.clone());
        vm.set_container_access(boxes.clone());
        vm.set_tools_access(tools.clone());
        vm.set_hud_access(huds.clone());
        vm.set_dialog_access(dialogs.clone());
        vm.set_sound_access(sounds.clone());
        vm.set_particle_access(particles.clone());
        vm.set_sight_access(world.clone());
        vm.set_fluid_access(world.clone());
        vm.set_light_source(world.clone());
        vm.set_world_edit(world.clone());

        let mut options = Vec::new();
        if let Some(mode) = &setup.mode {
            options.push(("tiamat_default_life:mode".to_owned(), WorldOptionValue::Choice(mode.clone())));
        }
        for id in &setup.options {
            options.push((format!("{MOD}:{id}"), WorldOptionValue::Toggle(true)));
        }
        if !options.is_empty() {
            vm.set_world_options(&options);
        }

        let mut after = Vec::new();
        for (on, id, source) in [
            (setup.world, "tiamat_default_world", WORLD),
            (setup.ui, "tiamat_default_ui", UI),
            (setup.life, "tiamat_default_life", LIFE),
            (setup.craft, "tiamat_default_craft", CRAFT),
        ] {
            if on {
                vm.load_mod(id, source, &dir).unwrap_or_else(|err| panic!("stand-in `{id}` failed to load: {err}"));
                after.push(id.to_owned());
            }
        }
        vm.note_dependencies(MOD, &after);
        let init = format!("{}\n{}", setup.prelude, std::fs::read_to_string(dir.join("init.lua")).unwrap());
        vm.load_mod(MOD, &init, &dir).expect("the mod loads");
        for (id, source) in &setup.fixtures {
            let mut deps = after.clone();
            deps.push(MOD.to_owned());
            vm.note_dependencies(id, &deps);
            vm.load_mod(id, source, &dir).unwrap_or_else(|err| panic!("fixture `{id}` failed to load: {err}"));
        }
        vm.freeze().unwrap();
        assert!(vm.faulted_mods().is_empty(), "faulted at load: {:?}", vm.faulted_mods());

        let materials: HashMap<String, MaterialId> = vm.registered_blocks().into_iter().collect();
        *world.names.lock().unwrap() = materials.clone();
        Rig { vm, storage, inventory, boxes, huds, dialogs, sounds, entities, materials }
    }

    pub fn material(&self, id: &str) -> MaterialId {
        let id = if id.contains(':') { id.to_owned() } else { format!("{MOD}:{id}") };
        *self.materials.get(&id).unwrap_or_else(|| panic!("no material {id}"))
    }

    pub fn assert_healthy(&self, after: &str) {
        assert!(self.vm.faulted_mods().is_empty(), "faulted after {after}: {:?}", self.vm.faulted_mods());
    }

    pub fn tick(&mut self, n: u32) {
        for _ in 0..n {
            let faults = self.vm.tick(1).expect("the tick itself");
            assert!(faults.is_empty(), "mod faulted in tick: {faults:?}");
        }
        self.assert_healthy("ticks");
    }

    pub fn join(&mut self, player: [u8; 32]) {
        let _ = self.vm.player_join(&JoinEvent { player, name: "someone".into() });
        self.assert_healthy("join");
    }

    pub fn leave(&mut self, player: [u8; 32]) {
        let _ = self.vm.player_leave(&LeaveEvent { player, name: "someone".into() });
        self.assert_healthy("leave");
    }

    /// A player says `text`. A refusal's reason reaches the speaker as a
    /// line of chat, as the server delivers it — which is how a chat
    /// command's reply arrives. (A bare refusal's "a mod refused that
    /// message" is left out: the stand-ins answer with `chat_to` and then
    /// refuse, and that line is the engine's, not anything under test.)
    pub fn say_as(&mut self, player: [u8; 32], text: &str) {
        let out = self.vm.chat(&ChatEvent { player, text: text.into() });
        if let (false, Some(line)) = (out.allowed, out.reason.clone()) {
            self.huds.chat.lock().unwrap().push((player, line));
        }
        self.assert_healthy(text);
    }

    pub fn say(&mut self, text: &str) {
        self.say_as(PLAYER, text);
    }

    /// Everything said to a player since the last call, oldest first.
    pub fn heard(&self, player: [u8; 32]) -> Vec<String> {
        let mut chat = self.huds.chat.lock().unwrap();
        let (mine, rest): (Vec<_>, Vec<_>) = chat.drain(..).partition(|(p, _)| *p == player);
        *chat = rest;
        mine.into_iter().map(|(_, t)| t).collect()
    }

    /// The last thing said to the player, clearing what they heard.
    pub fn said(&self) -> String {
        self.heard(PLAYER).pop().unwrap_or_default()
    }

    /// Says `text` as the player and answers the last line they heard back.
    pub fn ask(&mut self, text: &str) -> String {
        self.heard(PLAYER);
        self.say(text);
        self.said()
    }

    pub fn give(&self, player: [u8; 32], id: &str, units: u32) {
        let material = self.material(id);
        self.inventory.put(player, Stack::new(material, units).unwrap());
    }

    /// Puts a carved stack in the player's hand: `count` items of `mask`.
    pub fn hold_shape(&self, player: [u8; 32], id: &str, mask: u32, count: u32) {
        let material = self.material(id);
        let cells = mask.count_ones();
        let stack = Stack { shape: Shape::new(mask), ..Stack::new(material, count * cells).unwrap() };
        assert!(stack.shape.is_some(), "a mask with cells");
        self.inventory.put(player, stack);
        self.inventory.held.lock().unwrap().insert(player, (material, None));
    }

    pub fn units(&self, player: [u8; 32], id: &str) -> u32 {
        self.inventory.units_of(player, self.material(id))
    }

    /// Stands a player's body at a place, in blocks.
    pub fn place(&self, player: [u8; 32], x: f64, y: f64, z: f64) {
        let id = if player == PLAYER { 1 } else { 2 };
        let mut map = self.entities.0.lock().unwrap();
        map.get_mut(&id).unwrap().transform = Transform::from_world(x, y, z);
    }

    /// The engine saying a player's feet crossed into the block at `x, y, z`,
    /// from the one they were in before (none the first time).
    pub fn moved(&mut self, player: [u8; 32], to: (i32, i32, i32), from: Option<(i32, i32, i32)>) {
        let pos = |(x, y, z): (i32, i32, i32)| BlockPos { x, y, z };
        let out = self.vm.player_move(&MoveEvent {
            player,
            domain: "overworld".into(),
            block: pos(to),
            from: from.map(pos),
        });
        assert!(out.faults.is_empty(), "faulted in a move: {:?}", out.faults);
        self.assert_healthy("a move");
    }

    /// The player uses (the place control, nothing in hand) a block of
    /// `material`. Answers whether somebody handled it.
    pub fn use_block(&mut self, player: [u8; 32], material: &str) -> bool {
        let aim = UseAim { cell: tiamat_core::SubNodePos { x: 301, y: 193, z: 301 }, material: self.material(material) };
        let out = self.vm.use_block(&UseEvent { player, domain: "overworld".into(), aim: Some(aim), held: None });
        assert!(out.faults.is_empty(), "faulted in use: {:?}", out.faults);
        !out.allowed
    }

    /// A button pressed on one of this mod's dialogs.
    pub fn press(&mut self, player: [u8; 32], form: &str, name: &str) {
        let _ = self.vm.dialog_event(&DialogEvent {
            player,
            mod_id: MOD.into(),
            form: format!("{MOD}:{form}"),
            event: proto::DialogEvent::Pressed { name: name.into(), click: proto::Press::Left },
        });
        self.assert_healthy("a press");
    }

    pub fn action(&mut self, player: [u8; 32], id: &str) {
        let _ = self.vm.action(&ActionEvent { player, id: id.into(), pressed: true });
        self.assert_healthy("an action");
    }

    /// The last dialog shown or updated: its form and its tree's debug text.
    pub fn last_dialog(&self) -> Option<(String, String)> {
        self.dialogs.shown.lock().unwrap().last().map(|r| (r.form.clone(), format!("{:?}", r.tree)))
    }

    /// This mod's HUD values for a player, as debug text.
    pub fn hud(&self, player: [u8; 32]) -> String {
        self.huds.values.lock().unwrap().get(&player).map(|v| format!("{v:?}")).unwrap_or_default()
    }

    /// One of this mod's stored values, as debug text.
    pub fn stored(&self, key: &str) -> Option<String> {
        self.storage.0.lock().unwrap().get(&(MOD.to_owned(), key.to_owned())).map(|v| format!("{v:?}"))
    }
}

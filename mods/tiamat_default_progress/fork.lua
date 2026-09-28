-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- The Fork: the end of the shared tree, where a player binds themselves to
-- one path and the other door closes.
--
-- **This mod ships no doors.** A path is registered by the mod that IS the
-- path — magic, tech — from its own init.lua:
--
--     register_path{ id, label, door, recipe?, sentence?, refusal?, on_choose? }
--
-- `door` is that mod's block; touching it (the use control, nothing in
-- hand) is the choice. `recipe`, when given, is what the door is made of at
-- the workbench, and the Keystone is added to it here. With one path
-- installed the Fork has one door; with none, the Keystone can still be made
-- and held, and the Research tab says that no door has been built yet.
--
-- The choice is kept per player (`p:<uuid>:path`), and `has` refuses every
-- node of the other path for ever after — unless the world was made with
-- `repath` on, when the other door offers to take the player back at the
-- cost of that path's every node and half their insight.

local C = tdp.config
local U = tdp.util
local S = tdp.store
local N = tdp.nodes
local I = tdp.insight
local K = tdp.craft

local F = {}

F.paths = {}      -- id -> record
local listed = {} -- ids in registration order
local subscribers = { fork = {}, repath = {} }

-- The Keystone -----------------------------------------------------------------

F.keystone = game.mod_id .. ":keystone"
game.register_item{
    id = "keystone",
    name = "Keystone",
    description = "Orichalcum and gold in an iron frame. The way through either door at the Fork.",
    texture = "textures/keystone.png",
}

K.register{
    id = F.keystone, name = "Keystone", station = C.keystone_station,
    inputs = C.keystone_inputs, ticks = C.keystone_ticks,
    outputs = { { F.keystone, count = 1 } },
    requires = "shared.keystone",
}

game.register_sound{ id = "chime", file = "sounds/ping.wav", gain = 0.8, pitch_variance = 0.05 }
game.bind_sound("fork", "chime")

-- Paths ------------------------------------------------------------------------

--- Registers a path. Answers `true`, or `nil` and why.
function F.register_path(spec)
    if not tdp.loading() then return nil, "paths are registered while mods load" end
    if type(spec) ~= "table" then return nil, "a path is a table" end
    local id = spec.id
    if type(id) ~= "string" or #id > 32 or not string.match(id, "^[%a_][%w_]*$") or id == "shared" then
        return nil, "a path id is a word: magic"
    end
    if F.paths[id] then return nil, "path " .. id .. " is already registered" end
    if not U.qualified(spec.door) then return nil, "door is a qualified block id" end
    for _, other in pairs(F.paths) do
        if other.door == spec.door then return nil, "that door is already " .. other.id .. "'s" end
    end
    for _, key in ipairs({ "label", "sentence", "refusal" }) do
        if spec[key] ~= nil and type(spec[key]) ~= "string" then return nil, key .. " is a string" end
    end
    if spec.on_choose ~= nil and type(spec.on_choose) ~= "function" then return nil, "on_choose is a function" end
    if spec.recipe ~= nil and (type(spec.recipe) ~= "table" or type(spec.recipe.inputs) ~= "table") then
        return nil, "recipe is { inputs = { ... } }"
    end

    local path = {
        id = id,
        label = spec.label and string.sub(spec.label, 1, 48) or U.title(id),
        door = spec.door,
        sentence = spec.sentence and string.sub(spec.sentence, 1, 200) or C.sentence,
        refusal = spec.refusal and string.sub(spec.refusal, 1, 200) or C.refusal,
        on_choose = spec.on_choose,
    }

    if spec.recipe then
        -- The door is made of what its path says, and the Keystone.
        local inputs = { { F.keystone, count = 1 } }
        for i, entry in ipairs(spec.recipe.inputs) do
            if i > 15 then break end
            inputs[#inputs + 1] = entry
        end
        local ok, why = K.api and K.api.register{
            id = game.mod_id .. ":door_" .. id, name = path.label .. " door", station = C.door_station,
            inputs = inputs, ticks = C.door_ticks,
            outputs = { { spec.door, count = 1 } },
            requires = "shared.keystone",
        }
        if K.api and not ok then return nil, "Craft refused the door's recipe: " .. tostring(why) end
    end

    F.paths[id] = path
    listed[#listed + 1] = id
    return true
end

--- Every path, in the order registered.
function F.list()
    local out = {}
    for i, id in ipairs(listed) do out[i] = F.paths[id] end
    return out
end

function F.path_of(uuid)
    return S.record(uuid).path
end

local function subscribe(list, fn)
    if not tdp.loading() then return nil, "subscribe while mods load" end
    if type(fn) ~= "function" then return nil, "a subscriber is a function" end
    list[#list + 1] = fn
    return true
end

function F.on_fork(fn) return subscribe(subscribers.fork, fn) end
function F.on_repath(fn) return subscribe(subscribers.repath, fn) end

-- The choice ---------------------------------------------------------------------

local function where(uuid)
    local body = game.player_entity(uuid)
    local e = body and game.entity(body)
    return e and e.pos or nil
end

--- Tells everybody near `uuid` what they did.
local function announce(uuid, line)
    local pos = where(uuid)
    if not pos then return end
    game.cue{ cue = "fork", pos = pos, radius = C.fork_radius }
    for _, id in ipairs(game.entities_in_radius(pos, C.fork_radius)) do
        local e = game.entity(id)
        if e and e.owner and e.owner ~= uuid then
            game.chat_to(e.owner, line)
        end
    end
end

--- Binds a player to a path. Nothing is checked: the door checks.
function F.choose(uuid, id)
    local path = F.paths[id]
    S.set_path(uuid, id)
    S.set_forked(uuid, S.now())
    N.grant(uuid, "shared.fork", true)
    game.chat_to(uuid, "You have chosen: " .. path.label .. ". The other door is closed to you.")
    if path.on_choose then path.on_choose(uuid) end
    for _, fn in ipairs(subscribers.fork) do fn(uuid, id) end
    announce(uuid, "Somebody near you has chosen: " .. path.label .. ".")
    I.show(uuid)
end

--- Takes a player from their path to another: every node of the old path
--- gone, insight cut, the clock reset. Shared nodes are never touched.
function F.repath(uuid, id)
    local record = S.record(uuid)
    local old = record.path
    if old then
        local prefix = old .. "."
        for _, node in ipairs(U.sorted_keys(record.nodes)) do
            if U.starts(node, prefix) then N.revoke(uuid, node) end
        end
    end
    local keep = record.insight * C.repath_keep[1] // C.repath_keep[2]
    I.award(uuid, keep - record.insight, nil, "repath")
    S.set_path(uuid, id)
    S.set_forked(uuid, S.now())
    local path = F.paths[id]
    game.chat_to(uuid, "You have turned to " .. path.label .. ". What you knew of the other is gone.")
    if path.on_choose then path.on_choose(uuid) end
    for _, fn in ipairs(subscribers.repath) do fn(uuid, old, id) end
    announce(uuid, "Somebody near you has turned to " .. path.label .. ".")
end

-- The doors ------------------------------------------------------------------------

local pending = {}   -- uuid -> { path, kind = "choose" | "repath" }

local function confirm(uuid, path, kind)
    pending[uuid] = { path = path.id, kind = kind }
    local text = kind == "repath"
        and string.format("Abandon %s and take this door? Every node of it is lost, and half your insight with it.",
            F.paths[S.record(uuid).path].label)
        or path.sentence
    game.show_dialog{
        player = uuid,
        form = "fork",
        compact = true,
        tree = {
            type = "container", direction = "column", gap = 10, padding = 14, children = {
                { type = "label", text = path.label, style = { text_size = 22 } },
                { type = "label", text = text },
                { type = "container", direction = "row", gap = 10, children = {
                    { type = "button", name = "yes", text = kind == "repath" and "Turn" or "Yes" },
                    { type = "button", name = "no", text = "Not yet" },
                } },
            },
        },
    }
end

local door_of = nil   -- material -> path id, resolved once mods have loaded

local function door_path(material)
    if door_of == nil then
        door_of = {}
        for id, path in pairs(F.paths) do
            local m = U.material(path.door)
            if m then door_of[m] = id end
        end
    end
    return door_of[material]
end

--- What a player touching a door hears, as the choice it would be: `"choose"`,
--- `"repath"`, or `nil` and why not.
function F.door_verdict(uuid, id)
    local record = S.record(uuid)
    local path = F.paths[id]
    if tdp.life.ghost(uuid) then return nil, "Your hand passes through the door. The dead choose nothing." end
    if record.path == id then return nil, "You are already of " .. path.label .. "." end
    if record.path ~= nil then
        if not C.repath then return nil, path.refusal end
        local since = S.now() - (record.forked or 0)
        if since < C.repath_cooldown then
            return nil, string.format("Not yet: you chose only %d seconds ago.", since // 20)
        end
        return "repath"
    end
    if not N.has(uuid, "shared.keystone") then
        return nil, "The door is shut to you. Learn the Keystone first."
    end
    return "choose"
end

tdp.on_use(function(event)
    local id = event.material and door_path(event.material)
    if not id then return end
    local kind, why = F.door_verdict(event.player, id)
    if not kind then
        game.chat_to(event.player, why)
    else
        confirm(event.player, F.paths[id], kind)
    end
    return ""
end)

tdp.on_dialog("fork", function(event)
    local choice = pending[event.player]
    if event.kind == "closed" then
        pending[event.player] = nil
        return
    end
    if event.kind ~= "pressed" then return end
    pending[event.player] = nil
    game.close_dialog{ player = event.player, form = "fork" }
    if event.name ~= "yes" or not choice then return end
    -- Asked again: somebody may have chosen, or the clock moved, since the
    -- dialog opened.
    local kind, why = F.door_verdict(event.player, choice.path)
    if kind ~= choice.kind then
        if why then game.chat_to(event.player, why) end
        return
    end
    if kind == "choose" then
        F.choose(event.player, choice.path)
    else
        F.repath(event.player, choice.path)
    end
end)

tdp.on_leave(function(event) pending[event.player] = nil end)

return F

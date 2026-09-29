-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- One of each engine hook for the whole mod, with subscribers.
--
-- The engine keeps ONE callback per hook per mod: a second registration is
-- refused. So every file that wants a tick, a use or a chat word subscribes
-- here, and this file holds the engine's single registration of each.

local ticks = {}
local starts = {}
local words = {}
local actions = {}
local joins = {}
local leaves = {}
local moves = {}
local dialogs = {}
local uses = {}

-- Whether the registration window is still open. The engine closes its own
-- when the last mod's init.lua returns; this mod's registries close the
-- moment the running world first does anything, which is the first hook
-- called. The world's seed is nil until then in every VM, which covers a
-- call from a mod that loads after this one and registers from its own init.
local started = false

--- Whether mods are still loading.
function tdp.loading()
    return not started and game.world_seed == nil
end

-- The first thing the running world does closes the window and runs every
-- `on_start` subscriber once: the graph is validated there, when every mod
-- that will register a node has.
local function start()
    if started then return end
    started = true
    for _, fn in ipairs(starts) do
        fn()
    end
end

--- Runs `fn()` once, when mods have finished loading.
function tdp.on_start(fn)
    starts[#starts + 1] = fn
end

--- Runs `fn(dt_ticks)` every tick, after everything subscribed before it.
---@param fn fun(dt_ticks: integer)
function tdp.on_tick(fn)
    ticks[#ticks + 1] = fn
end

--- Runs `fn(player, rest)` when a player says `word` (case-insensitive), alone
--- or followed by more words. The message is swallowed unless `fn` answers
--- `false`, which is how a word lets a sentence that only starts with it
--- through to chat. A string `fn` answers is its reply, said to the speaker
--- alone by the engine; answering nothing swallows the line with the
--- engine's own "a mod refused that message".
---@param word string
---@param fn fun(player: string, rest: string): boolean?
function tdp.on_chat(word, fn)
    assert(not words[word], "chat word registered twice: " .. word)
    words[word] = fn
end

--- Runs `fn(event)` when a player presses or releases the qualified action `id`.
function tdp.on_action(id, fn)
    actions[id] = actions[id] or {}
    local list = actions[id]
    list[#list + 1] = fn
end

function tdp.on_join(fn)
    joins[#joins + 1] = fn
end

function tdp.on_leave(fn)
    leaves[#leaves + 1] = fn
end

--- Runs `fn(event)` when a player's feet cross into another block:
--- `{ player, x, y, z, domain, from? }`.
function tdp.on_move(fn)
    moves[#moves + 1] = fn
end

--- Runs `fn(event)` for events from the dialog this mod showed as `form`
--- (unqualified; the engine reports it qualified).
function tdp.on_dialog(form, fn)
    dialogs[game.mod_id .. ":" .. form] = fn
end

--- Runs `fn(event)` when a player USES a block: the place control with nothing
--- to place. Answer a string or `false` to handle it; the first to do so stops
--- the rest.
function tdp.on_use(fn)
    uses[#uses + 1] = fn
end

game.register_on_tick(function(dt_ticks)
    start()
    for _, fn in ipairs(ticks) do
        fn(dt_ticks)
    end
end)

game.register_on_chat(function(event)
    start()
    local first, rest = string.match(event.text, "^%s*(%S+)%s*(.*)$")
    if first == nil then return end
    local fn = words[string.lower(first)]
    if fn == nil then return end
    local verdict = fn(event.player, rest)
    if verdict == false then return end
    if type(verdict) == "string" and verdict ~= "" then return verdict end
    return false
end)

game.register_on_action(function(event)
    start()
    local list = actions[event.id]
    if list == nil then return end
    for _, fn in ipairs(list) do
        fn(event)
    end
end)

game.register_on_player_join(function(event)
    start()
    for _, fn in ipairs(joins) do
        fn(event)
    end
end)

game.register_on_player_leave(function(event)
    for _, fn in ipairs(leaves) do
        fn(event)
    end
end)

game.register_on_player_move(function(event)
    start()
    for _, fn in ipairs(moves) do
        fn(event)
    end
end)

game.register_on_dialog_event(function(event)
    start()
    local fn = dialogs[event.form]
    if fn then fn(event) end
end)

game.register_on_use(function(event)
    start()
    for _, fn in ipairs(uses) do
        local verdict = fn(event)
        if verdict ~= nil and verdict ~= true then
            return verdict
        end
    end
end)

return {}

-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- The node graph: what insight is spent on.
--
--     register{ id, tier, cost?, requires?, label?, text?, effects?, on_unlock? }
--
-- A node's id is `<path>.<name>`, and the path is "shared" or one a path mod
-- registered (fork.lua). This mod registers the shared tree; the magic and
-- tech mods register their own nodes from their own init.lua, which runs
-- AFTER this one — so nothing about `requires` can be checked when a node is
-- registered. The graph is validated once, when mods have finished loading
-- (`tdp.on_start`): a node naming one that does not exist, a cycle, a shared
-- node leaning on a path, a path's third tier not reaching the Fork. Every
-- fault is logged, and only the faulty nodes (and whatever needs them) are
-- disabled: never the mod, and never another mod's good nodes.
--
-- `has(uuid, node)` is the one question every gated thing asks, and it is a
-- table lookup: unknown or disabled is `false`; a shared node is the
-- player's `n:` key (every shared node is held in a Creative world); a path
-- node is `false`, always, unless it is on the player's own path — that is
-- the lock — and then it is the `n:` key.

local C = tdp.config
local S = tdp.store
local U = tdp.util
local I = tdp.insight

local N = {}

local nodes = {}        -- id -> record
local order = {}        -- ids in registration order
local subscribers = {}  -- fn(uuid, node_id)
local validated = false

local creative = C.mode == "Creative"

--- Registers a node. Answers `true`, or `nil` and why.
function N.register(spec, owner)
    if not tdp.loading() then return nil, "nodes are registered while mods load" end
    if type(spec) ~= "table" then return nil, "a node is a table" end
    local id = spec.id
    if type(id) ~= "string" or #id > 64 or not string.match(id, "^[%a_][%w_]*%.[%w_]+$") then
        return nil, "a node id is <path>.<name>: shared.bronze_casting"
    end
    if nodes[id] then return nil, "node " .. id .. " is already registered" end
    local tier = U.whole(spec.tier, 0, C.max_tier)
    if not tier then return nil, "tier is a whole number, 0 to " .. C.max_tier end
    local cost = spec.cost == nil and C.tier_cost[tier] or U.whole(spec.cost, 0, C.max_cost)
    if not cost then return nil, "cost is a whole number of insight" end

    local requires = {}
    if spec.requires ~= nil then
        if type(spec.requires) == "string" then
            requires = { spec.requires }
        elseif type(spec.requires) == "table" and #spec.requires <= C.max_requires then
            for i, r in ipairs(spec.requires) do
                if type(r) ~= "string" or #r > 64 then return nil, "requires lists node ids" end
                requires[i] = r
            end
        else
            return nil, "requires is a node id or a list of at most " .. C.max_requires
        end
    end

    local effects = {}
    if spec.effects ~= nil then
        if type(spec.effects) ~= "table" or #spec.effects > C.max_effects then
            return nil, "effects is a list of at most " .. C.max_effects
        end
        for i, e in ipairs(spec.effects) do
            local key, value = type(e) == "table" and e[1], type(e) == "table" and e[2]
            local n = U.whole(value, -1000000, 1000000)
            if type(key) ~= "string" or #key > 64 or not n then
                return nil, "an effect is { \"mod.key\", whole number }"
            end
            effects[i] = { key, n }
        end
    end
    if spec.on_unlock ~= nil and type(spec.on_unlock) ~= "function" then
        return nil, "on_unlock is a function"
    end

    nodes[id] = {
        id = id,
        path = string.match(id, "^([^%.]+)%."),
        tier = tier,
        cost = cost,
        requires = requires,
        label = type(spec.label) == "string" and string.sub(spec.label, 1, 48) or U.title(id),
        text = type(spec.text) == "string" and string.sub(spec.text, 1, 200) or "",
        effects = effects,
        on_unlock = spec.on_unlock,
        auto = spec.auto == true,
        owner = owner,
    }
    order[#order + 1] = id
    return true
end

function N.node(id)
    return type(id) == "string" and nodes[id] or nil
end

--- Every usable node, by tier and then in the order registered: a stable
--- order for a screen.
function N.list()
    local out = {}
    for i, id in ipairs(order) do
        local node = nodes[id]
        if not node.broken then out[#out + 1] = { node = node, at = i } end
    end
    table.sort(out, function(a, b)
        if a.node.tier ~= b.node.tier then return a.node.tier < b.node.tier end
        return a.at < b.at
    end)
    for i, entry in ipairs(out) do out[i] = entry.node end
    return out
end

function N.count()
    return #order
end

-- Validation --------------------------------------------------------------------

local function fault(node, why)
    if node.broken then return end
    node.broken = why
    game.log(string.format("tiamat_default_progress: node %s is disabled: %s", node.id, why))
end

--- Checks the whole graph, once every mod has registered. Disables what is
--- wrong and says why in the log; answers how many nodes were disabled.
function N.validate()
    local paths = tdp.fork and tdp.fork.paths or {}
    for _, id in ipairs(order) do
        local node = nodes[id]
        if node.path ~= "shared" and not paths[node.path] then
            fault(node, "no path " .. node.path .. " is registered")
        end
        for _, r in ipairs(node.requires) do
            local need = nodes[r]
            if not need then
                fault(node, "it requires " .. r .. ", which nobody registered")
            elseif node.path == "shared" and need.path ~= "shared" then
                fault(node, "a shared node requires a path node, " .. r)
            end
        end
    end

    -- Cycles: a depth-first walk, colouring what is on the current stack.
    local state = {}
    local function walk(id, stack)
        if state[id] == "done" then return end
        if state[id] == "open" then
            for i = #stack, 1, -1 do
                fault(nodes[stack[i]], "it is part of a cycle through " .. id)
                if stack[i] == id then break end
            end
            return
        end
        state[id] = "open"
        stack[#stack + 1] = id
        for _, r in ipairs(nodes[id].requires) do
            if nodes[r] then walk(r, stack) end
        end
        stack[#stack] = nil
        state[id] = "done"
    end
    for _, id in ipairs(order) do walk(id, {}) end

    -- What needs a disabled node is disabled too, until nothing changes.
    local changed = true
    while changed do
        changed = false
        for _, id in ipairs(order) do
            local node = nodes[id]
            if not node.broken then
                for _, r in ipairs(node.requires) do
                    if nodes[r] and nodes[r].broken then
                        fault(node, "it requires " .. r .. ", which is disabled")
                        changed = true
                        break
                    end
                end
            end
        end
    end

    -- A path's third tier and above stands behind the Fork.
    local reaches = {}
    local function reaches_fork(id)
        if reaches[id] ~= nil then return reaches[id] end
        reaches[id] = false
        local node = nodes[id]
        if id == "shared.fork" then
            reaches[id] = true
        else
            for _, r in ipairs(node.requires) do
                if nodes[r] and reaches_fork(r) then reaches[id] = true break end
            end
        end
        return reaches[id]
    end
    for _, id in ipairs(order) do
        local node = nodes[id]
        if not node.broken and node.path ~= "shared" and node.tier >= 3 and not reaches_fork(id) then
            fault(node, "a path node of tier 3 or more must require shared.fork")
        end
    end

    validated = true
    local broken = 0
    for _, id in ipairs(order) do
        if nodes[id].broken then broken = broken + 1 end
    end
    return broken
end

tdp.on_start(function() N.validate() end)

-- The question ----------------------------------------------------------------------

--- Whether a player holds a node.
function N.has(uuid, id)
    local node = nodes[id]
    if node == nil or node.broken then return false end
    local record = S.record(uuid)
    if node.path == "shared" then
        return creative or record.nodes[id] == true
    end
    if record.path ~= node.path then return false end
    return record.nodes[id] == true
end

--- Whether a player could unlock a node now: `true`, or `nil` and why.
function N.can(uuid, id)
    local node = nodes[id]
    if node == nil or node.broken then return nil, "there is no such thing to learn" end
    if N.has(uuid, id) then return nil, "you know " .. node.label .. " already" end
    if node.auto then return nil, node.label .. " is not learned; it comes" end
    local record = S.record(uuid)
    if node.path ~= "shared" then
        if record.path == nil then return nil, node.label .. " lies beyond the Fork" end
        if record.path ~= node.path then return nil, node.label .. " belongs to the other path" end
    end
    for _, r in ipairs(node.requires) do
        if not N.has(uuid, r) then
            return nil, node.label .. " needs " .. (nodes[r] and nodes[r].label or r) .. " first"
        end
    end
    if record.insight < node.cost then
        return nil, string.format("%s needs %d insight; you have %d", node.label, node.cost, record.insight)
    end
    return true
end

--- Gives a player a node without asking anything: an auto node arriving, an
--- operator's grant. Tells the node's owner and the subscribers.
function N.grant(uuid, id, quiet)
    local node = nodes[id]
    if node == nil or node.broken then return nil, "no such node" end
    if S.record(uuid).nodes[id] then return false end
    S.set_node(uuid, id)
    if not quiet then
        game.chat_to(uuid, "Learned: " .. node.label)
    end
    if node.on_unlock then node.on_unlock(uuid) end
    for _, fn in ipairs(subscribers) do
        fn(uuid, id)
    end
    I.show(uuid)
    return true
end

--- Spends a player's insight on a node. `true`, or `nil` and why; nothing is
--- taken unless it is learned.
function N.unlock(uuid, id)
    local ok, why = N.can(uuid, id)
    if not ok then return nil, why end
    local node = nodes[id]
    I.award(uuid, -node.cost, nil, "spent")
    return N.grant(uuid, id)
end

--- Takes a node back (a repath, an operator's reset). Nothing is refunded.
function N.revoke(uuid, id)
    if S.record(uuid).nodes[id] then S.set_node(uuid, id, false) end
end

function N.on_unlock(fn)
    if not tdp.loading() then return nil, "subscribe while mods load" end
    if type(fn) ~= "function" then return nil, "a subscriber is a function" end
    subscribers[#subscribers + 1] = fn
    return true
end

--- The effects of every node a player holds, summed per key, for the keys
--- that start with `prefix` (all of them when it is nil). Read live by the
--- mod that owns each number, so nothing about an effect is ever stored.
function N.effects_of(uuid, prefix)
    local out = {}
    for _, id in ipairs(order) do
        local node = nodes[id]
        if #node.effects > 0 and N.has(uuid, id) then
            for _, e in ipairs(node.effects) do
                if prefix == nil or U.starts(e[1], prefix) then
                    out[e[1]] = (out[e[1]] or 0) + e[2]
                end
            end
        end
    end
    return out
end

function N.validated()
    return validated
end

return N

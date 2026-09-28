-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- The Research screen: a tab on the interface's screen when that mod is
-- here, a plain dialog on the `research` action (G) when it is not. One tree
-- serves both.
--
-- Three views. The TREE: insight at the top with a bar toward the cheapest
-- node the player could learn next, and a scroll of tier rows, one node a
-- row — bright when it can be learned, dim when it cannot, marked when it is
-- known — and under them the paths, "Beyond the Fork": both, dimmed, before
-- the choice, so it is seen long before it is made; only one's own after.
-- DISCOVERIES: what has been found and what is left, the biomes as a count
-- and a list. STUDIES: what the research table takes and pays, and the
-- carved shape in the hand.
--
-- Pressing a node learns it, or says in the status line why not.

local C = tdp.config
local U = tdp.util
local S = tdp.store
local I = tdp.insight
local N = tdp.nodes
local F = tdp.fork
local R = tdp.research

local M = {}

local ui = U.exports(C.ui)
if ui and ui.version ~= 1 then ui = nil end

M.tab = game.mod_id .. ":research"

local views = {}    -- uuid -> "tree" | "discoveries" | "studies"
local status = {}   -- uuid -> the last thing the screen said
local open = {}     -- uuid -> true while the plain dialog is open

-- Colours: the interface's when it is here, plain otherwise.
local INK = { 232, 222, 200, 255 }
local DIM = { 140, 132, 120, 255 }
local GOOD = { 150, 210, 140, 255 }
local ACCENT = { 214, 180, 110, 255 }
if ui and type(ui.theme) == "table" and type(ui.theme.colours) == "table" then
    local colours = ui.theme.colours
    if type(colours.ink) == "table" then INK = colours.ink end
    if type(colours.muted) == "table" then DIM = colours.muted end
    if type(colours.accent) == "table" then ACCENT = colours.accent end
end

local ROW = 28

-- Builders --------------------------------------------------------------------------

local function label(text, colour, size)
    return { type = "label", text = text, style = { text_colour = colour or INK, text_size = size } }
end

local function row(children, size)
    return { type = "container", direction = "row", gap = 8, align = "center", size = size or ROW, children = children }
end

local function button(name, text, colour, width)
    return { type = "button", name = name, text = text, size = width,
        style = { text_colour = colour or INK } }
end

local function heading(text)
    return label(text, ACCENT, 18)
end

--- The cheapest node a player could learn but for insight, or nil.
local function next_node(uuid)
    local best
    for _, node in ipairs(N.list()) do
        local ok, why = N.can(uuid, node.id)
        local short = not ok and string.find(why or "", "insight; you have", 1, true)
        if (ok or short) and node.cost > 0 and (best == nil or node.cost < best.cost) then
            best = node
        end
    end
    return best
end

local function node_row(uuid, node, dimmed)
    local known = N.has(uuid, node.id)
    local ok = not dimmed and N.can(uuid, node.id)
    local colour = known and GOOD or (ok and INK or DIM)
    local state
    if known then
        state = "known"
    elseif node.auto then
        state = "comes of itself"
    else
        state = node.cost .. " insight"
    end
    return row({
        button("node:" .. node.id, node.label, colour, 190),
        label(state, colour),
        { type = "spacer", grow = 1 },
    })
end

local function tree_view(uuid)
    local body = {}
    local nodes = N.list()
    for tier = 0, C.max_tier do
        local shared = {}
        for _, node in ipairs(nodes) do
            if node.tier == tier and node.path == "shared" then shared[#shared + 1] = node end
        end
        if #shared > 0 then
            body[#body + 1] = heading("Tier " .. tier)
            for _, node in ipairs(shared) do body[#body + 1] = node_row(uuid, node) end
        end
    end

    body[#body + 1] = heading("Beyond the Fork")
    local paths = F.list()
    local mine = S.record(uuid).path
    if #paths == 0 then
        body[#body + 1] = label("No door has been built in this world yet.", DIM)
    end
    for _, path in ipairs(paths) do
        if mine == nil or mine == path.id then
            local own = {}
            for _, node in ipairs(nodes) do
                if node.path == path.id then own[#own + 1] = node end
            end
            body[#body + 1] = label(path.label .. (mine == path.id and " (your path)" or ""), mine and GOOD or DIM)
            if #own == 0 then
                body[#body + 1] = label("Nothing is written here yet.", DIM)
            end
            for _, node in ipairs(own) do
                body[#body + 1] = node_row(uuid, node, mine == nil)
            end
        end
    end
    return body
end

local function mark(found)
    return found and "found" or "-"
end

local function discoveries_view(uuid)
    local record = S.record(uuid)
    local body = {}
    local groups, order = {}, {}
    for _, def in ipairs(I.list()) do
        if not groups[def.group] then
            groups[def.group] = {}
            order[#order + 1] = def.group
        end
        local list = groups[def.group]
        list[#list + 1] = def
    end
    for _, group in ipairs(order) do
        body[#body + 1] = heading(U.title(group))
        for _, def in ipairs(groups[group]) do
            local found = record.found[def.id] == true
            body[#body + 1] = row({
                label(def.label, found and GOOD or DIM),
                { type = "spacer", grow = 1 },
                label(found and ("+" .. def.insight) or mark(false), found and GOOD or DIM),
            }, 22)
        end
    end

    -- The biomes, from whatever the world has named so far.
    local seen = {}
    for _, id in ipairs(U.sorted_keys(record.found)) do
        local name = string.match(id, "^biome:(.+)$")
        if name then seen[#seen + 1] = U.title(name) end
    end
    body[#body + 1] = heading(string.format("Biomes: %d of %d", #seen, C.biome_count))
    for i = 1, #seen, 3 do
        body[#body + 1] = row({
            label(seen[i], GOOD), label(seen[i + 1] or "", GOOD), label(seen[i + 2] or "", GOOD),
        }, 22)
    end
    if #seen == 0 then
        body[#body + 1] = label("None yet. Walk.", DIM)
    end
    return body
end

local function studies_view(uuid)
    local body = { heading("At the research table") }
    local list = R.list()
    if #list == 0 then
        body[#body + 1] = label(tdp.craft.api and "The table takes nothing yet." or "There is no research table without Craft.", DIM)
    end
    for _, study in ipairs(list) do
        local input = study.inputs[1] or {}
        local amount = input.count and ("x" .. input.count) or (input.units and (input.units .. " units")) or ""
        body[#body + 1] = row({
            label(study.name, INK),
            { type = "spacer", grow = 1 },
            label(string.format("%s %s, %ds", U.friendly(tostring(input[1])), amount, study.ticks // 20), DIM),
            label("+" .. study.insight, GOOD),
        }, 22)
    end
    local shapes = 0
    for _ in pairs(S.record(uuid).shapes) do shapes = shapes + 1 end
    body[#body + 1] = heading("Shapes")
    body[#body + 1] = row({
        button("shape", "Study the carving in your hand", shapes < C.shape_cap and INK or DIM, 260),
        label(string.format("+%d, %d of %d", C.shape_insight, shapes, C.shape_cap), DIM),
    })
    return body
end

--- The whole tree for a player.
function M.build(uuid)
    local view = views[uuid] or "tree"
    local record = S.record(uuid)
    local target = next_node(uuid)
    local permille = 1000
    if target then permille = math.min(1000, record.insight * 1000 // target.cost) end

    local body
    if view == "discoveries" then
        body = discoveries_view(uuid)
    elseif view == "studies" then
        body = studies_view(uuid)
    else
        body = tree_view(uuid)
    end

    local function tab_button(name, text)
        return button("view:" .. name, text, view == name and ACCENT or INK)
    end
    return {
        type = "container", direction = "column", gap = 6, padding = 6, grow = 1, children = {
            row({
                label(string.format("Insight %d", record.insight), ACCENT, 20),
                { type = "progress", permille = permille, grow = 1 },
                label(target and string.format("next: %s, %d", target.label, target.cost) or "", DIM),
            }, 30),
            row({
                tab_button("tree", "Tree"),
                tab_button("discoveries", "Discoveries"),
                tab_button("studies", "Studies"),
                { type = "spacer", grow = 1 },
                label(record.path and F.paths[record.path] and F.paths[record.path].label or "", GOOD),
            }, 30),
            label(status[uuid] or "", DIM),
            { type = "scroll", grow = 1, children = {
                { type = "container", direction = "column", gap = 4, children = body },
            } },
        },
    }
end

--- A press on the screen. Answers whether it changed anything.
function M.press(uuid, name)
    if type(name) ~= "string" then return false end
    local view = string.match(name, "^view:(%a+)$")
    if view then
        views[uuid] = view
        status[uuid] = nil
        return true
    end
    local id = string.match(name, "^node:(.+)$")
    if id then
        local ok, why = N.unlock(uuid, id)
        status[uuid] = ok and ("Learned " .. N.node(id).label .. ".") or why
        return true
    end
    if name == "shape" then
        local ok, why = R.study_shape(uuid)
        status[uuid] = ok and "The shape is understood." or why
        return true
    end
    return false
end

--- Redraws the screen for a player if it is open.
function M.redraw(uuid)
    if ui then
        ui.redraw(uuid)
    elseif open[uuid] then
        game.update_dialog{ player = uuid, form = "research", tree = M.build(uuid) }
    end
end

--- Opens the screen.
function M.open(uuid)
    if ui and ui.open(uuid, M.tab) then return end
    open[uuid] = true
    game.show_dialog{ player = uuid, form = "research", tree = M.build(uuid) }
end

if ui then
    local ok, why = ui.add_tab{
        id = M.tab,
        label = "Research",
        order = C.tab_order,
        build = function(player) return M.build(player) end,
        on_event = function(player, event)
            if event.kind ~= "pressed" then return false end
            return M.press(player, event.name)
        end,
    }
    if not ok then
        game.log("tiamat_default_progress: the interface refused the Research tab: " .. tostring(why))
        ui = nil
    end
end

game.register_action{
    id = "research",
    default_key = C.research_key,
    description = "Research: insight, the tree and the Fork",
}

tdp.on_action(game.mod_id .. ":research", function(event)
    if event.pressed then M.open(event.player) end
end)

tdp.on_dialog("research", function(event)
    if event.kind == "closed" then
        open[event.player] = nil
        return
    end
    if event.kind == "pressed" and M.press(event.player, event.name) then
        M.redraw(event.player)
    end
end)

tdp.on_leave(function(event)
    views[event.player], status[event.player], open[event.player] = nil, nil, nil
end)

-- Whatever changes what the screen shows redraws it.
N.on_unlock(function(uuid) M.redraw(uuid) end)
I.on_discover(function(uuid) M.redraw(uuid) end)

return M

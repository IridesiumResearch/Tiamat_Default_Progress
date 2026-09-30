-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- The Research screen: a tab on the interface's screen when that mod is
-- here, a plain dialog on the `research` action (G) when it is not. One tree
-- serves both.
--
-- Everything centred. Three views. The TREE: insight at the top with a bar
-- toward the cheapest node the player could learn next (its price on
-- hover), and a scroll of tiers, each a small mark in the display face over
-- a row of square tiles — a frame for the node's picture, its name, and on
-- hover its price, what it does and what it needs; bright when it can be
-- learned, dim when it cannot, green when it is known — and under them the
-- paths, "Beyond the Fork": both, dimmed, before the choice, so it is seen
-- long before it is made; only one's own after.
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
local E = tdp.explore

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

-- The interface's display face (Cinzel), for the small tier marks; nil
-- without the interface, which draws them in the client's own face.
local DISPLAY = ui and type(ui.theme) == "table" and type(ui.theme.font) == "string" and ui.theme.font or nil

-- A node tile: its picture in a square frame (the node's `icon`; an empty
-- frame for a node without one), its name under it, and everything else —
-- what it costs, what it does, what it needs — on hover.
local TILE_W, TILE_H, PICTURE, TILE_GAP = 80, 98, 44, 8

-- Builders --------------------------------------------------------------------------

local function label(text, colour, size)
    return { type = "label", text = text, style = { text_colour = colour or INK, text_size = size } }
end

local function row(children, size)
    return { type = "container", direction = "row", gap = 8, align = "center", size = size or ROW, children = children }
end

--- A row of `children` in the middle of the width: spacers either side.
local function centred(children, size, gap)
    local out = { { type = "spacer", grow = 1 } }
    for _, child in ipairs(children) do out[#out + 1] = child end
    out[#out + 1] = { type = "spacer", grow = 1 }
    return { type = "container", direction = "row", gap = gap or 8, align = "center", size = size or ROW, children = out }
end

local function button(name, text, colour, width, tooltip)
    return { type = "button", name = name, text = text, size = width, tooltip = tooltip,
        style = { text_colour = colour or INK } }
end

--- At most 256 bytes, the engine's cap on a tooltip, cut on a character
--- boundary rather than through one.
local function capped(text)
    if #text <= 256 then return text end
    local cut = 253
    while cut > 0 and (string.byte(text, cut + 1) or 0) & 0xC0 == 0x80 do cut = cut - 1 end
    return string.sub(text, 1, cut) .. "..."
end

--- What hovers over a node: its name and state or price, what it does, and
--- what it needs first.
local function node_tip(uuid, node)
    local state
    if N.has(uuid, node.id) then
        state = "known"
    elseif node.auto then
        state = "comes of itself"
    else
        state = node.cost .. " insight"
    end
    local parts = { node.label .. " (" .. state .. ").", node.text }
    if #node.requires > 0 then
        local names = {}
        for i, r in ipairs(node.requires) do
            local need = N.node(r)
            names[i] = need and need.label or r
        end
        parts[#parts + 1] = "Needs " .. table.concat(names, ", ") .. "."
    end
    return capped(table.concat(parts, " "))
end

--- A section's heading: the display face, small, muted, out of the way.
local function heading(text)
    return centred({ { type = "label", text = text,
        style = { font = DISPLAY, text_size = 13, text_colour = DIM } } }, 18)
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

-- Tile colours: known, learnable now, and not yet.
local TILE = {
    known = { background = { 44, 66, 44, 255 }, border = { 120, 180, 110, 255 } },
    ready = { background = { 58, 50, 36, 255 }, border = ACCENT },
    locked = { background = { 30, 28, 26, 255 }, border = { 70, 66, 60, 255 } },
}

--- A content hash as the 32 bytes of the older spelling. The engine takes
--- the hex too, but the interface copies a tab's `hash` only as a list, so
--- this is the spelling that reaches the screen either way.
local function hash_bytes(hex)
    local out = {}
    for i = 1, 64, 2 do out[#out + 1] = tonumber(string.sub(hex, i, i + 1), 16) end
    return out
end

local function node_tile(uuid, node, dimmed)
    local known = N.has(uuid, node.id)
    local ready = not known and not dimmed and N.can(uuid, node.id)
    local look = known and TILE.known or (ready and TILE.ready or TILE.locked)
    local colour = known and GOOD or (ready and INK or DIM)
    local tip = node_tip(uuid, node)
    return {
        type = "container", direction = "column", align = "center", gap = 4, padding = 4,
        size = TILE_W, cross_size = TILE_H, tooltip = tip,
        style = { background = look.background, border = look.border },
        children = {
            -- The node's picture, framed; an empty frame for a node without one.
            { type = "container", size = PICTURE, cross_size = PICTURE, padding = 2, tooltip = tip,
              style = { border = look.border },
              children = node.icon and { { type = "image", hash = hash_bytes(node.icon), grow = 1 } } or nil },
            { type = "button", name = "node:" .. node.id, text = node.label, grow = 1, tooltip = tip,
              style = { text_colour = colour, text_size = 11 } },
        },
    }
end

--- A tier's nodes as centred rows of tiles, six to a row.
local function tile_rows(uuid, nodes, dimmed, body)
    for i = 1, #nodes, 6 do
        local tiles = {}
        for j = i, math.min(i + 5, #nodes) do tiles[#tiles + 1] = node_tile(uuid, nodes[j], dimmed) end
        body[#body + 1] = centred(tiles, TILE_H, TILE_GAP)
    end
end

local TIER_MARK = { [0] = "I", "II", "III", "IV", "V", "VI", "VII", "VIII" }

--- A branch's name under a tier: smaller still than the tier's mark.
local function branch_mark(text)
    return centred({ { type = "label", text = text,
        style = { font = DISPLAY, text_size = 11, text_colour = DIM } } }, 14)
end

--- A path's nodes: by tier, and within a tier by branch in the order the
--- path registered them, each branch under its name. Only the nodes the
--- player can see (`N.visible`: a path may reveal a node only once all but
--- one of its requirements are held), and a count of the rest.
local function path_section(uuid, path, own, dimmed, body)
    local hidden = 0
    for tier = 0, C.max_tier do
        local shown, order, by_branch = 0, {}, {}
        for _, node in ipairs(own) do
            if node.tier == tier then
                if N.visible(uuid, node.id) then
                    local key = node.branch or ""
                    if not by_branch[key] then
                        by_branch[key] = {}
                        order[#order + 1] = key
                    end
                    local list = by_branch[key]
                    list[#list + 1] = node
                    shown = shown + 1
                else
                    hidden = hidden + 1
                end
            end
        end
        if shown > 0 then
            body[#body + 1] = heading("Tier " .. TIER_MARK[tier])
            for _, key in ipairs(order) do
                if key ~= "" then body[#body + 1] = branch_mark(path.branches[key] or key) end
                tile_rows(uuid, by_branch[key], dimmed, body)
            end
        end
    end
    if hidden > 0 then
        body[#body + 1] = centred({ label(string.format("%d more, not yet in sight.", hidden), DIM, 12) }, 18)
    end
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
            body[#body + 1] = heading("Tier " .. TIER_MARK[tier])
            tile_rows(uuid, shared, false, body)
        end
    end

    body[#body + 1] = heading("Beyond the Fork")
    local paths = F.list()
    local mine = S.record(uuid).path
    if #paths == 0 then
        body[#body + 1] = centred({ label("No door has been built in this world yet.", DIM) }, 22)
    end
    for _, path in ipairs(paths) do
        if mine == nil or mine == path.id then
            local own = {}
            for _, node in ipairs(nodes) do
                if node.path == path.id then own[#own + 1] = node end
            end
            body[#body + 1] = centred({ label(path.label .. (mine == path.id and " (your path)" or ""),
                mine and GOOD or DIM) }, 22)
            if #own == 0 then
                body[#body + 1] = centred({ label("Nothing is written here yet.", DIM) }, 22)
            end
            path_section(uuid, path, own, mine == nil, body)
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

    -- The biomes: every one the world lists, found or not, or else those
    -- found so far.
    local cells, found = {}, 0
    if E.biomes then
        for _, biome in ipairs(E.biomes) do
            local seen = record.found["biome:" .. biome.id] == true
            if seen then found = found + 1 end
            cells[#cells + 1] = label(biome.name, seen and GOOD or DIM)
        end
    else
        for _, id in ipairs(U.sorted_keys(record.found)) do
            local def = string.match(id, "^biome:") and I.def(id)
            if def then
                found = found + 1
                cells[#cells + 1] = label(def.label, GOOD)
            end
        end
    end
    body[#body + 1] = heading(string.format("Biomes: %d of %d", found, E.biome_count()))
    for i = 1, #cells, 3 do
        body[#body + 1] = row({ cells[i], cells[i + 1] or label(""), cells[i + 2] or label("") }, 22)
    end
    if #cells == 0 then
        body[#body + 1] = label("None yet. Walk.", DIM)
    end

    -- Creatures hunted and foods tasted: families Life names as they come.
    for _, family in ipairs({ { "kill:", "Creatures" }, { "eat:", "Food" } }) do
        local found_here = {}
        for _, id in ipairs(U.sorted_keys(record.found)) do
            local def = U.starts(id, family[1]) and I.def(id)
            if def then found_here[#found_here + 1] = row({ label(def.label, GOOD) }, 22) end
        end
        if #found_here > 0 then
            body[#body + 1] = heading(family[2])
            for _, r in ipairs(found_here) do body[#body + 1] = r end
        end
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
    local path = record.path and F.paths[record.path] and F.paths[record.path].label
    return {
        type = "container", direction = "column", gap = 6, padding = 6, grow = 1, children = {
            centred({
                { type = "label", text = string.format("Insight %d", record.insight),
                  style = { font = DISPLAY, text_size = 18, text_colour = ACCENT } },
                { type = "progress", permille = permille, size = 160,
                  tooltip = target and string.format("Next: %s, %d insight", target.label, target.cost)
                      or "Nothing left to learn here." },
            }, 28),
            centred({
                tab_button("tree", "Tree"),
                tab_button("discoveries", "Discoveries"),
                tab_button("studies", "Studies"),
            }, 28),
            centred({ label(status[uuid] or (path and ("Your path: " .. path)) or "", DIM) }, 20),
            { type = "scroll", grow = 1, children = {
                { type = "container", direction = "column", gap = 6, children = body },
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

--- Opens the screen: the interface's, on the Research tab, when the
--- interface is here — never a panel of this mod's own beside it.
function M.open(uuid)
    if ui then
        ui.open(uuid, M.tab)
        return
    end
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

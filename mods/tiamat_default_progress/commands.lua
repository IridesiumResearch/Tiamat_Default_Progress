-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- Chat words. `progress` alone, for anyone, says where a player stands, and
-- `progress sources` where their insight came from and went (the pacing
-- ledger, docs/pacing.md); `progress where` gives the block their feet are
-- in and the clock, for the pacing bot. The other subcommands are for
-- operators —
-- testing, and an admin putting a shared world right:
--
--     progress grant <node>     give a node, without cost or prerequisites
--     progress insight <n>      set insight to n
--     progress path <id|none>   bind to a path (or to none), without a door
--     progress reset            forget everything this mod knows of you
--
-- `/progress` is the same word.

local C = tdp.config
local U = tdp.util
local S = tdp.store
local I = tdp.insight
local N = tdp.nodes
local F = tdp.fork

local SUBCOMMANDS = { grant = true, insight = true, path = true, reset = true }

local function summary(uuid)
    local record = S.record(uuid)
    local known = 0
    for _, node in ipairs(N.list()) do
        if N.has(uuid, node.id) then known = known + 1 end
    end
    local path = record.path and F.paths[record.path] and F.paths[record.path].label or "none yet"
    return string.format("Insight %d. Path: %s. Nodes known: %d.", record.insight, path, known)
end

--- Where a player's insight has come from, and gone: the pacing ledger.
local function sources(uuid)
    local tally = S.record(uuid).tally
    local parts = {}
    for _, source in ipairs(U.sorted_keys(tally)) do
        parts[#parts + 1] = string.format("%s %+d", source, tally[source])
    end
    if #parts == 0 then return "No insight yet." end
    return "Insight by source: " .. table.concat(parts, ", ") .. "."
end

--- A command's reply is what it returns: the hook hands it back to the
--- engine, which says it to the speaker alone — one line, and not the
--- engine's "a mod refused that message" that a bare `false` would bring.
local function command(player, rest)
    local word, arg = string.match(rest, "^(%S*)%s*(.-)%s*$")
    if word == "" then return summary(player) end
    if word == "sources" then return sources(player) end
    if word == "where" then
        -- For a script finding its feet (the pacing bot): the block, and the
        -- clock the ledger is timed by.
        local x, y, z = tdp.explore.where(player)
        if not x then return "nowhere yet" end
        return string.format("at %d %d %d t=%d", x, y, z, S.now())
    end
    -- A sentence that only starts with the word is chat.
    if not (C.dev_commands and SUBCOMMANDS[word]) then return false end
    if not game.is_operator(player) then
        return "progress " .. word .. " is for operators"
    end
    if word == "grant" then
        local node = N.node(arg)
        if not node or node.broken then return "no node " .. arg end
        if node.path ~= "shared" and S.record(player).path ~= node.path then
            return node.label .. " is " .. node.path .. "'s; take that path first"
        end
        N.grant(player, arg, true)
        return "Learned: " .. node.label
    elseif word == "insight" then
        local n = U.whole(tonumber(arg), 0, C.max_insight)
        if not n then return "progress insight <whole number>" end
        I.award(player, n - S.record(player).insight, nil, "operator")
        return "insight " .. S.record(player).insight
    elseif word == "path" then
        if arg == "none" then
            S.set_path(player, nil)
            N.revoke(player, "shared.fork")
            return "no path"
        elseif F.paths[arg] then
            F.choose(player, arg)
            return "path " .. arg
        end
        return "no path " .. arg
    elseif word == "reset" then
        S.reset(player)
        I.show(player)
        return "forgotten"
    end
end

tdp.on_chat("progress", command)
tdp.on_chat("/progress", command)

return {}

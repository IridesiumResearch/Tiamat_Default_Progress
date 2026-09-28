-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- Chat words. `progress` alone, for anyone, says where a player stands, and
-- `progress sources` where their insight came from and went (the pacing
-- ledger, docs/pacing.md). The other subcommands are for operators —
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

local function command(player, rest)
    local word, arg = string.match(rest, "^(%S*)%s*(.-)%s*$")
    if word == "" then
        game.chat_to(player, summary(player))
        return
    end
    if word == "sources" then
        game.chat_to(player, sources(player))
        return
    end
    -- A sentence that only starts with the word is chat.
    if not (C.dev_commands and SUBCOMMANDS[word]) then return false end
    if not game.is_operator(player) then
        game.chat_to(player, "progress " .. word .. " is for operators")
        return
    end
    if word == "grant" then
        local node = N.node(arg)
        if not node or node.broken then
            game.chat_to(player, "no node " .. arg)
            return
        end
        if node.path ~= "shared" and S.record(player).path ~= node.path then
            game.chat_to(player, node.label .. " is " .. node.path .. "'s; take that path first")
            return
        end
        N.grant(player, arg)
    elseif word == "insight" then
        local n = U.whole(tonumber(arg), 0, C.max_insight)
        if not n then
            game.chat_to(player, "progress insight <whole number>")
            return
        end
        I.award(player, n - S.record(player).insight, nil, "operator")
        game.chat_to(player, "insight " .. S.record(player).insight)
    elseif word == "path" then
        if arg == "none" then
            S.set_path(player, nil)
            N.revoke(player, "shared.fork")
            game.chat_to(player, "no path")
        elseif F.paths[arg] then
            F.choose(player, arg)
        else
            game.chat_to(player, "no path " .. arg)
        end
    elseif word == "reset" then
        S.reset(player)
        I.show(player)
        game.chat_to(player, "forgotten")
    end
end

tdp.on_chat("progress", command)
tdp.on_chat("/progress", command)

return {}

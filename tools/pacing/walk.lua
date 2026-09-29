-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- The pacing bot: a player who walks.
--
-- Joins a real server running the default mods, finds its feet, and walks
-- an outward square spiral from wherever the world set it down, for
-- MINUTES of the server's clock. Every leg it asks `progress sources` and
-- prints the answer with the clock, so the runner (tools/pacing/run.py)
-- can table what exploring actually pays: the real world's biomes at the
-- real spacing, the real walk between them, and nothing modelled.
--
-- It measures EXPLORATION only. Craft's loop wants blocks found and placed
-- by id, which a script cannot look up; that half of the pacing is a
-- person's session (`progress sources`) until a bot can play it.
--
-- The runner writes `MINUTES = n` above this file before running it.

MINUTES = MINUTES or 10
local LEG = 48          -- blocks the spiral grows by every second turn
local TICKS = MINUTES * 60 * 20

--- Says `text` and answers the first line heard back that matches `pattern`.
local function ask(text, pattern)
    bot.heard()
    bot.chat(text)
    for _ = 1, 20 do
        bot.sleep_ticks(2)
        for _, line in ipairs(bot.heard()) do
            local found = { string.match(line, pattern) }
            if #found > 0 then return table.unpack(found) end
        end
    end
end

local function where()
    local x, y, z, t = ask("progress where", "^at (%-?%d+) (%-?%d+) (%-?%d+) t=(%d+)$")
    if x then return tonumber(x), tonumber(y), tonumber(z), tonumber(t) end
end

local function report(label)
    local line = ask("progress sources", "^(Insight by source: .*)$") or ask("progress sources", "^(No insight yet%.)$")
    local _, _, _, t = where()
    print(string.format("pacing-bot t=%d %s %s", t or -1, label, line or "(no answer)"))
end

bot.join("pacer")

-- Wait to be set down: the world moves a joining player to its spawn, and
-- until the feet have moved once there is nowhere to stand.
local x, y, z, start
for _ = 1, 60 do
    bot.sleep_ticks(20)
    x, y, z, start = where()
    if x then break end
end
bot.assert(x ~= nil, "the bot was set down somewhere")
print(string.format("pacing-bot start at %d %d %d t=%d, walking %d minutes", x, y, z, start, MINUTES))
report("start")

-- An outward square spiral: east, north, west, south, each pair of legs
-- LEG longer than the last.
-- `bot.move_to` walks for about ten seconds and returns wherever it got, so
-- a leg is walked in stretches until the corner is reached, or until three
-- stretches in a row gain nothing (a cliff, the sea) and the bot turns.
local function walk_to(tx, tz)
    local stuck = 0
    while stuck < 3 do
        local px, _, pz, now = where()
        if not px or (now and now - start >= TICKS) then return end
        if math.abs(tx - px) + math.abs(tz - pz) <= 2 then return end
        bot.move_to(tx, 0, tz)
        local qx, _, qz = where()
        if qx and math.abs(qx - px) + math.abs(qz - pz) < 2 then stuck = stuck + 1 else stuck = 0 end
    end
end

local DIRS = { { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 } }
local length, turn = LEG, 0
local cx, cz = x, z
while true do
    local _, _, _, now = where()
    if now and now - start >= TICKS then break end
    local d = DIRS[turn % 4 + 1]
    cx, cz = cx + d[1] * length, cz + d[2] * length
    walk_to(cx, cz)
    turn = turn + 1
    if turn % 2 == 0 then length = length + LEG end
    report(string.format("leg %d", turn))
end

report("end")
bot.disconnect()

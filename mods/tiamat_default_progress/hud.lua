-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- The insight HUD: the number in the top-right corner, and under it for a
-- few seconds the name of whatever just earned some.
--
-- This runs on the PLAYER's machine, once a frame, in the engine's HUD
-- sandbox. Everything it knows arrives in `state.values`, set by insight.lua
-- with `game.set_hud`: `insight`, and `flash` while there is a line to show.
-- The server decides when the line goes; this only draws.

local INK = { 232, 222, 200, 255 }
local GOLD = { 214, 180, 110, 255 }
local SHADOW = { 0, 0, 0, 150 }

local RIGHT = 250   -- from the right edge to the text's left edge
local TOP = 24

local function text(x, y, words, size, colour)
    hud.text{ anchor = "top_right", x = x - 2, y = y + 2, text = words, size = size, colour = SHADOW }
    hud.text{ anchor = "top_right", x = x, y = y, text = words, size = size, colour = colour }
end

hud.on_draw(function(state)
    local values = state.values
    if values == nil or values.insight == nil then return end
    text(RIGHT, TOP, "Insight " .. tostring(values.insight), 22, GOLD)
    if values.flash then
        text(RIGHT, TOP + 30, tostring(values.flash), 16, INK)
    end
end)

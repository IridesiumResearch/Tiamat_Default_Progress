-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- The research table and the studies: insight bought with materials and time.
--
-- The table is a Craft STATION — a container with an input slot and an
-- output slot — and every study is an ordinary Craft recipe at it whose
-- outputs are nothing. Craft's job loop runs the study (its ticks, its
-- container, its rollback); this mod only hears `on_crafted` for the study's
-- recipe id and pays the insight. It never writes a job loop of its own.
--
-- What a study costs is the material's rarity: a block of rock is 2, a
-- sliver of orichalcum 80 (config.lua). Other mods add studies of their own
-- through the `register_study` export, while mods load.
--
-- A carved shape is studied from the hand instead (`study_shape`): Craft
-- never takes a carved stack as an ingredient — somebody's particular thing
-- is not melted down — so the Studies view offers it, once per distinct
-- mask, up to `shape_cap` of them.

local C = tdp.config
local U = tdp.util
local S = tdp.store
local I = tdp.insight
local K = tdp.craft
local N = tdp.nodes

local R = {}

R.station = game.mod_id .. ":research_table"
R.block = game.register_block{
    id = "research_table",
    name = "Research table",
    description = "Clay tablets on a plank bench. Put a material in and it is studied for insight.",
    hardness = 0.8,
    textures = { all = "textures/research_table.png" },
}

local studies = {}   -- recipe id -> { id, name, insight, ticks, inputs }
local listed = {}    -- recipe ids in registration order

--- Registers a study: `{ id, name?, inputs, ticks, insight }`, `id` qualified
--- with the registering mod's id. A Craft recipe at the research table that
--- makes nothing; `insight` is paid when Craft says it was made.
function R.register(spec)
    if not tdp.loading() then return nil, "studies are registered while mods load" end
    if type(spec) ~= "table" then return nil, "a study is a table" end
    if not U.qualified(spec.id) then return nil, "a study id is qualified: my_mod:study_thing" end
    if studies[spec.id] then return nil, "study " .. spec.id .. " is already registered" end
    local insight = U.whole(spec.insight, 1, 100000)
    if not insight then return nil, "insight is a whole number" end
    local ticks = U.whole(spec.ticks, 0, 20 * 60 * 60)
    if not ticks then return nil, "ticks is a whole number" end
    if not K.api then return nil, "there is no research table without Craft" end
    local name = type(spec.name) == "string" and string.sub(spec.name, 1, 48) or U.title(spec.id)
    local ok, why = K.api.register{
        id = spec.id, name = name, station = R.station,
        inputs = spec.inputs, ticks = ticks, outputs = {},
    }
    if not ok then return nil, why end
    studies[spec.id] = { id = spec.id, name = name, insight = insight, ticks = ticks, inputs = spec.inputs }
    listed[#listed + 1] = spec.id
    return true
end

--- Every study, as `{ id, name, insight, ticks, inputs }`, in registration order.
function R.list()
    local out = {}
    for i, id in ipairs(listed) do out[i] = studies[id] end
    return out
end

if K.api then
    local ok, why = K.api.register_station{
        id = R.station,
        name = "Research table",
        slots = C.table_slots,
        block = R.station,
    }
    if not ok then
        game.log("tiamat_default_progress: Craft refused the research table: " .. tostring(why))
    else
        -- The table itself, at the workbench.
        K.register{
            id = game.mod_id .. ":research_table", name = "Research table", station = "workbench",
            inputs = {
                { C.craft .. ":plank", count = 4 },
                { C.craft .. ":cord", count = 1 },
                { C.world .. ":wet_clay", units = 9 },
            },
            ticks = 100,
            outputs = { { R.station, count = 1 } },
        }
        local refused, why = 0, nil
        for _, study in ipairs(C.studies) do
            local done, reason = R.register{
                id = game.mod_id .. ":" .. study.id, name = study.name,
                inputs = { study.input }, ticks = study.ticks, insight = study.insight,
            }
            if not done then refused, why = refused + 1, why or reason end
        end
        if refused > 0 then
            game.log(string.format("tiamat_default_progress: Craft refused %d of %d studies (%s): "
                .. "a study is a recipe that makes nothing, which this Craft does not take", refused, #C.studies, tostring(why)))
        end
    end
end

K.on_crafted(function(uuid, recipe_id)
    local study = studies[recipe_id]
    if study then
        -- Nodes may raise what studies pay (Science's Difference Engine):
        -- `progress.study_percent`, summed over what the player holds.
        local percent = N.effects_of(uuid, "progress.study_percent")["progress.study_percent"] or 0
        local pay = study.insight * (100 + percent) // 100
        if pay > 0 then I.award(uuid, pay, study.name, "study") end
    end
end)

-- Using the table: Craft opens it, as it opens every station's block. In a
-- world without Craft, the table says why it does nothing.
tdp.on_use(function(event)
    if K.api or event.material ~= R.block then return end
    game.chat_to(event.player, "A research table wants Craft's stations, and Craft is not in this world.")
    return ""
end)

-- Shapes -----------------------------------------------------------------------

--- Studies the carved block a player holds: `true` and the insight, or `nil`
--- and why. One of the stack is used up.
function R.study_shape(uuid)
    local held = game.held(uuid)
    if not (held and held.shape) then return nil, "hold a carved block to study its shape" end
    local mask = held.shape
    local record = S.record(uuid)
    local key = string.format("%d", mask)
    if record.shapes[key] then return nil, "you have studied that shape already" end
    local n = 0
    for _ in pairs(record.shapes) do n = n + 1 end
    if n >= C.shape_cap then return nil, "you have learned all the shapes can teach" end
    local took = game.take(uuid, { material = held.material, count = 1, shape = mask, detail = held.detail })
    if took <= 0 then return nil, "the carving moved" end
    S.set_shape(uuid, key)
    I.award(uuid, C.shape_insight, "A shape of " .. U.cells(mask) .. " cells", "shape")
    return true, C.shape_insight
end

return R

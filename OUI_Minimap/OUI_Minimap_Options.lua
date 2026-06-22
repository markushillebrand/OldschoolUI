-- ===========================================================================
--  OldschoolUI Minimap -- options page (Core RegisterModule + build()).
-- ===========================================================================
local _, ns = ...
local OUI = OldschoolUI
if not (OUI and OUI.RegisterModule) then return end

local function MM() return ns.MM end
local function DB()
    local m = ns.MM
    return (m and m.db and m.db.profile) or {}
end
local function Refresh()
    if ns.MM then ns.MM:OptionsRefresh() end
end

local function Toggle(page, label, key, tip)
    page:AddRow(OUI.Widgets.Toggle(page, {
        label = label, tooltip = tip,
        get = function() return DB()[key] and true or false end,
        set = function(v) DB()[key] = v; Refresh() end,
    }))
end
local function Slider(page, label, key, min, max, step, dflt, tip)
    page:AddRow(OUI.Widgets.Slider(page, {
        label = label, tooltip = tip, min = min, max = max, step = step,
        get = function() local v = DB()[key]; if v == nil then v = dflt end; return v end,
        set = function(v) DB()[key] = v; Refresh() end,
    }))
end
local function Drop(page, label, key, values, order, tip)
    page:AddRow(OUI.Widgets.Dropdown(page, {
        label = label, tooltip = tip, values = values, order = order,
        get = function() return DB()[key] end,
        set = function(v) DB()[key] = v; Refresh() end,
    }))
end

local SHAPE_VALUES = {
    round = "Round", square = "Square", parallelogram = "Parallelogram",
    triangle = "Triangle", trapezoid = "Trapezoid",
}
local SHAPE_ORDER = { "round", "square", "parallelogram", "triangle", "trapezoid" }

local EDGE_VALUES = { auto = "Auto (per shape)", TOP = "Top", BOTTOM = "Bottom", LEFT = "Left", RIGHT = "Right" }
local EDGE_ORDER  = { "auto", "TOP", "BOTTOM", "LEFT", "RIGHT" }

local CLOCK_VALUES = { auto = "Server time", ["12h"] = "12-hour", ["24h"] = "24-hour" }
local CLOCK_ORDER  = { "auto", "12h", "24h" }

OUI:RegisterModule("OUI_Minimap", {
    category    = "Main Modules", order = 10,
    title       = "Minimap",
    description = "Minimap shape, size, button bin and info elements. /ouimove to reposition.",
    build = function(page)
        -- Shape ----------------------------------------------------------------
        Drop(page, "Shape", "shape", SHAPE_VALUES, SHAPE_ORDER)
        Toggle(page, "Rounded corners", "rounded",
            "Round the corners of non-round shapes (square, triangle, trapezoid, parallelogram).")
        Toggle(page, "Triangle points down", "triDown",
            "Only applies to the triangle shape: flip so the point faces down (wide base on top).")
        Slider(page, "Width", "width", 100, 320, 2, 140)
        Slider(page, "Height", "height", 100, 320, 2, 140)

        -- Border (addon-level override of the suite-global border) -------------
        Toggle(page, "Override border", "bOverride",
            "Use a custom border colour and size for the minimap instead of the UI-wide default.")
        page:AddRow(OUI.Widgets.ColorSwatch(page, {
            label = "Border Colour", hasAlpha = true,
            get = function() local c = DB().bcol or { 0, 0, 0, 0.9 }; return c[1], c[2], c[3], c[4] end,
            set = function(r, g, b, a) DB().bcol = { r, g, b, a or 1 }; Refresh() end,
        }))
        Slider(page, "Border Size", "bsize", 0, 4, 1, 1)

        -- Button bin -----------------------------------------------------------
        Drop(page, "Button Edge", "btnEdge", EDGE_VALUES, EDGE_ORDER,
            "Which edge the collected addon buttons and pinned extras attach to. Auto picks the best edge per shape.")
        Slider(page, "Bin Button Size", "binBtnSize", 16, 40, 1, 24)
        Slider(page, "Buttons Per Row", "binPerRow", 1, 12, 1, 6)

        -- Info elements --------------------------------------------------------
        local POS, POSORDER = MM().INFO_POS_NAMES, MM().INFO_POS_ORDER
        Toggle(page, "Show Zone Text", "showZone")
        Drop(page, "Zone Position", "zonePos", POS, POSORDER)
        Toggle(page, "Show Clock", "showClock")
        Drop(page, "Clock Format", "clockFormat", CLOCK_VALUES, CLOCK_ORDER)
        Drop(page, "Clock Position", "clockPos", POS, POSORDER)
        Toggle(page, "Show Coordinates", "showCoords")
        Drop(page, "Coordinates Position", "coordsPos", POS, POSORDER)
        Toggle(page, "Show Mail Indicator", "showMail")
        Drop(page, "Mail Position", "mailPos", POS, POSORDER)

        -- Indicator buttons (shown in the pinned row) + visibility -------------
        Toggle(page, "Show Tracking Button", "showTracking")
        Toggle(page, "Show Friends Button", "showFriends")
        Toggle(page, "Show Group Finder Button", "showLFG")
        Toggle(page, "Fade out unless hovered", "mouseFade",
            "Fade the whole minimap when you're not hovering it (always shown in combat).")
        Slider(page, "Faded opacity (%)", "mouseFadeAlpha", 0, 100, 5, 0)
    end,
})

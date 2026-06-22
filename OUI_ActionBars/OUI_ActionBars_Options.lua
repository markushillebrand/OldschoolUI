-- ===========================================================================
--  OldschoolUI -- Action Bars options
--  Registered against the OldschoolUI options system (RegisterModule + build).
-- ===========================================================================
local _, ns = ...
local OUI = OldschoolUI
if not (OUI and OUI.RegisterModule) then return end

local L  = OUI.L
local Lf = OUI.Lf
local AB = ns.AB

local function DB() return (AB and AB.db and AB.db.profile) or {} end
local function ApplyAll() if AB then AB:ApplyAll() end end
local function ApplyBar(k) if AB then AB:ApplyBar(k) end end
local function Recolor()  if AB then AB:RefreshColors() end end

local SHAPE_VALUES  = { square = "Square", rounded = "Rounded", round = "Round" }
local SHAPE_ORDER   = { "square", "rounded", "round" }
local ANCHOR_VALUES = { TOPLEFT = "Top-Left", TOPRIGHT = "Top-Right",
                        BOTTOMLEFT = "Bottom-Left", BOTTOMRIGHT = "Bottom-Right" }
local ANCHOR_ORDER  = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }
local VIS_VALUES    = { always = "Always", combat = "In Combat", ooc = "Out of Combat",
                        mouseover = "Mouseover", never = "Never" }
local VIS_ORDER     = { "always", "combat", "ooc", "mouseover", "never" }

-- per-bar label composed from already-localised parts, so the widget's own L()
-- pass leaves the finished string untouched.
local function rowLabel(bar, suffix) return L(bar.label) .. ": " .. L(suffix) end

-- ---- per-bar row block (shown for the picked bar) --------------------------
local function BarRows(page, bar)
    local key, count, defCols = bar.key, bar.count, bar.defCols
    local needsMenu = (key == "Bar6" or key == "Bar7" or key == "Bar8")
    page:AddRow(OUI.Widgets.Toggle(page, {
        label = rowLabel(bar, "Enabled"),
        tooltip = needsMenu and L("Requires activation in the Blizzard interface menu (Action Bars).") or nil,
        get = function() local c = DB().bars and DB().bars[key]; return c and c.enabled or false end,
        set = function(v) DB().bars[key].enabled = v; ApplyBar(key) end,
    }))
    page:AddRow(OUI.Widgets.Slider(page, {
        label = rowLabel(bar, "Columns"),
        tooltip = Lf("Buttons per row. 1 = vertical column, %d = single horizontal row.", count),
        min = 1, max = count, step = 1,
        get = function() return DB().bars[key].cols or defCols end,
        set = function(v) DB().bars[key].cols = v; ApplyBar(key) end,
    }))
    page:AddRow(OUI.Widgets.Dropdown(page, {
        label = rowLabel(bar, "Anchor corner"),
        tooltip = "Corner that button 1 sits in; the grid fills out from there.",
        values = ANCHOR_VALUES, order = ANCHOR_ORDER,
        get = function() return DB().bars[key].anchor or "TOPLEFT" end,
        set = function(v) DB().bars[key].anchor = v; ApplyBar(key) end,
    }))
    page:AddRow(OUI.Widgets.Slider(page, {
        label = rowLabel(bar, "Scale"),
        min = 0.5, max = 2.0, step = 0.05,
        get = function() return DB().bars[key].scale or 1.0 end,
        set = function(v) DB().bars[key].scale = v; ApplyBar(key) end,
    }))
    page:AddRow(OUI.Widgets.Dropdown(page, {
        label = rowLabel(bar, "Visibility"),
        values = VIS_VALUES, order = VIS_ORDER,
        get = function() return DB().bars[key].visibility or "always" end,
        set = function(v) DB().bars[key].visibility = v end,
    }))
end

local selectedBar = nil
local function BarPickValues()
    local vals, order = {}, {}
    for _, bar in ipairs(ns.BARS or {}) do vals[bar.key] = bar.label; order[#order + 1] = bar.key end
    return vals, order
end

local function buildGeneral(page)
    page:AddRow(OUI.Widgets.Dropdown(page, {
        label = "Button Shape", values = SHAPE_VALUES, order = SHAPE_ORDER,
        tooltip = "Icon mask applied to every button.",
        get = function() return DB().buttonShape or "square" end,
        set = function(v) DB().buttonShape = v; ApplyAll() end,
    }))
    page:AddRow(OUI.Widgets.Slider(page, {
        label = "Button Size", min = 20, max = 50, step = 1,
        get = function() return DB().buttonSize or 36 end,
        set = function(v) DB().buttonSize = v; ApplyAll() end,
    }))
    page:AddRow(OUI.Widgets.Slider(page, {
        label = "Button Spacing", min = 0, max = 12, step = 1,
        get = function() return DB().spacing or 4 end,
        set = function(v) DB().spacing = v; ApplyAll() end,
    }))
    page:AddRow(OUI.Widgets.Toggle(page, {
        label = "Out-of-range colouring",
        tooltip = "Tint an ability when the target is out of range.",
        get = function() return DB().outOfRangeColoring and true or false end,
        set = function(v) DB().outOfRangeColoring = v; Recolor() end,
    }))
    page:AddRow(OUI.Widgets.ColorSwatch(page, {
        label = "Out-of-range colour",
        get = function() local c = DB().outOfRangeColor or { 0.8, 0.15, 0.15 }; return c[1], c[2], c[3] end,
        set = function(r, g, b) DB().outOfRangeColor = { r, g, b }; Recolor() end,
    }))
    page:AddRow(OUI.Widgets.Slider(page, {
        label = "Faded opacity (%)",
        tooltip = "Opacity for bars faded out by their visibility mode (In Combat / Out of Combat / Mouseover). 0 = hidden.",
        min = 0, max = 100, step = 5,
        get = function() return math.floor((DB().fadeAlpha or 0) * 100 + 0.5) end,
        set = function(v) DB().fadeAlpha = v / 100 end,
    }))
    -- special bars (toggle; position with /ouimove)
    for _, info in ipairs(ns.EXTRA or {}) do
        local key = info.key
        page:AddRow(OUI.Widgets.Toggle(page, {
            label = L(info.label) .. " " .. L("(special)"),
            get = function() local c = DB().extras and DB().extras[key]; return c and c.enabled or false end,
            set = function(v) DB().extras[key].enabled = v; if AB then AB:ApplyExtra(info) end end,
        }))
    end
end

local function buildBars(page)
    local vals, order = BarPickValues()
    if not selectedBar then selectedBar = order[1] end
    page:AddRow(OUI.Widgets.Dropdown(page, {
        label = "Bar", values = vals, order = order,
        tooltip = "Pick a bar to configure; its settings appear below.",
        get = function() return selectedBar end,
        set = function(v) selectedBar = v; if OUI.RefreshOptionsBody then OUI.RefreshOptionsBody() end end,
    }))
    local bar
    for _, b in ipairs(ns.BARS or {}) do if b.key == selectedBar then bar = b break end end
    if bar then BarRows(page, bar) end
end

OUI:RegisterModule("OUI_ActionBars", {
    category    = "Main Modules", order = 20,
    title       = "Action Bars",
    description = "Action bars 1-8 plus pet, stance and special bars. "
               .. "Use /ouimove to drag bars, or /ouiab for quick commands.",
    tabs = {
        { title = "General", build = buildGeneral },
        { title = "Bars",    build = buildBars },
    },
})

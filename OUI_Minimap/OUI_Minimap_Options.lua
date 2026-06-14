-------------------------------------------------------------------------------
--  OUI_Minimap_Options.lua
--  Config page for the minimap module, rewritten against the OldschoolUI
--  options API (RegisterModule + page:AddRow + OUI.Widgets). Single scrollable
--  page under the "Better UI Module" category. All labels/tooltips are English
--  literals routed through L() by the widget system (deDE in the core locale).
--  Settings are written into the minimap addon's AceDB profile and applied live
--  via OUI._minimapApply (the main module's ApplyMinimap), exposed in
--  OnInitialize so it is available regardless of the enabled state.
-------------------------------------------------------------------------------
local _, ns = ...
local OUI = OldschoolUI
if not (OUI and OUI.RegisterModule) then return end

local function DB()
    local db = OUI._minimapDB
    return (db and db.profile and db.profile.minimap) or {}
end
local function Cfg(k)    return DB()[k] end
local function Set(k, v) DB()[k] = v end
local function Apply()       if OUI._minimapApply then OUI._minimapApply() end end
-- Button backgrounds / sizes / grouping need a cache-wiping full rebuild.
local function FullRebuild() if OUI._minimapFullRebuild then OUI._minimapFullRebuild() end end
local function VisUpdate()   if OUI.RequestVisibilityUpdate then OUI.RequestVisibilityUpdate() end end
-- Sliders fire set() continuously while dragging; coalesce the (heavy) re-apply.
local _pending
local function Debounce(fn)
    if _pending then return end
    _pending = true
    C_Timer.After(0.1, function() _pending = false; fn() end)
end
local function L(s)       return (OUI.L and OUI.L(s)) or s end

-- Accent section header with a divider line, stacked as a normal row.
local function Header(page, text)
    local row = CreateFrame("Frame", nil, page)
    row:SetHeight(20)
    local fs = OUI._label(row, 12, OUI.ACCENT.r, OUI.ACCENT.g, OUI.ACCENT.b)
    fs:SetPoint("BOTTOMLEFT", 0, 5)
    fs:SetText(string.upper(L(text)))
    OUI.RegAccent({ type = "font", obj = fs })
    local p = OUI._palette
    local div = OUI._tex(row, "ARTWORK", p.BRD[1], p.BRD[2], p.BRD[3], 1)
    div:SetPoint("BOTTOMLEFT", 0, 0); div:SetPoint("BOTTOMRIGHT", 0, 0); div:SetHeight(1)
    page:AddRow(row, 8)
end

-- Convenience builders bound to a page.
local function Toggle(page, label, key, tip)
    page:AddRow(OUI.Widgets.Toggle(page, {
        label = label, tooltip = tip,
        get = function() return Cfg(key) and true or false end,
        set = function(v) Set(key, v); Apply() end,
    }))
end
-- Toggle for button settings that need a cache-wiping rebuild.
local function RebuildToggle(page, label, key, tip)
    page:AddRow(OUI.Widgets.Toggle(page, {
        label = label, tooltip = tip,
        get = function() return Cfg(key) and true or false end,
        set = function(v) Set(key, v); FullRebuild() end,
    }))
end
local function Slider(page, label, key, min, max, step, dflt, tip)
    page:AddRow(OUI.Widgets.Slider(page, {
        label = label, tooltip = tip, min = min, max = max, step = step,
        get = function() local v = Cfg(key); if v == nil then v = dflt end; return v end,
        set = function(v) Set(key, v); Debounce(Apply) end,
    }))
end
-- Slider for button sizes (need a cache-wiping rebuild to re-snapshot).
local function RebuildSlider(page, label, key, min, max, step, dflt, tip)
    page:AddRow(OUI.Widgets.Slider(page, {
        label = label, tooltip = tip, min = min, max = max, step = step,
        get = function() local v = Cfg(key); if v == nil then v = dflt end; return v end,
        set = function(v) Set(key, v); Debounce(FullRebuild) end,
    }))
end
-- Scale stored as a float (1.15) but shown/edited as a percent (115).
local function ScaleSlider(page, label, key, tip)
    page:AddRow(OUI.Widgets.Slider(page, {
        label = label, tooltip = tip, min = 50, max = 200, step = 5,
        get = function() return math.floor((Cfg(key) or 1) * 100 + 0.5) end,
        set = function(v) Set(key, v / 100); Debounce(Apply) end,
    }))
end

OUI:RegisterModule("OUI_Minimap", {
    category    = "Better UI Module", order = 10,
    title       = "Minimap",
    description = "Reskins the minimap: shape, border, clock, zone text, coordinates, indicator and addon buttons, and conditional visibility.",
    build = function(page)
        local W = OUI.Widgets

        ------------------------------------------------------------- GENERAL
        Header(page, "General")
        Toggle(page, "Enable", "enabled",
            "Apply the OldschoolUI minimap skin. Disabling may require a /reload to fully restore the default minimap.")
        page:AddRow(W.Segmented(page, {
            label    = "Shape",
            segments = { { value = "square", text = "Square" }, { value = "circle", text = "Circle" } },
            get = function() return Cfg("shape") or "square" end,
            set = function(v) Set("shape", v); Apply() end,
        }))
        Toggle(page, "Rotate Minimap", "rotateMinimap",
            "Rotate the minimap instead of the player arrow.")
        RebuildSlider(page, "Map Size", "mapSize", 100, 280, 4, 140,
            "Width and height of the minimap window in pixels.")
        Toggle(page, "Zoom with Mouse Wheel", "scrollZoom",
            "Scroll over the minimap to zoom in and out (zoom buttons are hidden).")
        Toggle(page, "Middle-Click Opens Micro Menu", "openMicroMenuOnMiddleClick",
            "Middle-click the minimap to open the micro menu.")
        Toggle(page, "Lock Position", "lock",
            "Lock the minimap so it cannot be dragged. Use /ouimove to reposition while unlocked.")

        ------------------------------------------------------------- BORDER
        Header(page, "Border")
        Slider(page, "Border Size", "borderSize", 0, 8, 1, 1)
        Toggle(page, "Use Class Color", "useClassColor",
            "Tint the minimap border with your class color.")
        page:AddRow(W.ColorSwatch(page, {
            label = "Border Color", hasAlpha = true,
            tooltip = "Custom border color (ignored while Use Class Color is on).",
            get = function() local p = DB(); return p.borderR or 0, p.borderG or 0, p.borderB or 0, p.borderA or 1 end,
            set = function(r, g, b, a)
                local p = DB(); p.borderR, p.borderG, p.borderB, p.borderA = r, g, b, a or 1; Apply()
            end,
        }))

        ------------------------------------------------------------- CLOCK
        Header(page, "Clock")
        Toggle(page, "Show Clock", "showClock")
        Toggle(page, "Clock Inside Minimap", "clockInside",
            "Anchor the clock inside the minimap instead of below it.")
        page:AddRow(W.Dropdown(page, {
            label  = "Time Format",
            values = { auto = "Automatic", ["12h"] = "12-Hour", ["24h"] = "24-Hour" },
            order  = { "auto", "12h", "24h" },
            get = function() return Cfg("clockFormat") or "auto" end,
            set = function(v) Set("clockFormat", v); Apply() end,
        }))
        ScaleSlider(page, "Clock Scale (%)", "clockScale")
        Slider(page, "Clock Offset X", "clockOffsetX", -60, 60, 1, 0)
        Slider(page, "Clock Offset Y", "clockOffsetY", -60, 60, 1, 0)

        ------------------------------------------------------------- ZONE TEXT
        Header(page, "Zone Text")
        Toggle(page, "Hide Zone Text", "hideZoneText")
        Toggle(page, "Zone Text Inside Minimap", "zoneInside",
            "Anchor the zone name inside the minimap instead of below it.")
        ScaleSlider(page, "Zone Text Scale (%)", "locationScale")
        Slider(page, "Zone Text Offset X", "locationOffsetX", -60, 60, 1, 0)
        Slider(page, "Zone Text Offset Y", "locationOffsetY", -60, 60, 1, 0)

        ------------------------------------------------------------- COORDINATES
        Header(page, "Coordinates")
        Toggle(page, "Show Coordinates Below Map", "coordsBelow",
            "Always show player coordinates centered below the minimap (otherwise they appear on mouseover).")
        Slider(page, "Coordinate Decimals", "coordPrecision", 0, 2, 1, 0)

        ------------------------------------------------------------- INDICATORS
        Header(page, "Indicators")
        Toggle(page, "Hide Tracking Button", "hideTrackingButton")
        Toggle(page, "Hide Calendar", "hideGameTime")
        Toggle(page, "Hide Mail Icon", "hideMail")
        Toggle(page, "Hide Raid Difficulty", "hideRaidDifficulty")
        Toggle(page, "Extra Buttons on Mouseover Only", "mouseoverExtraBtns",
            "Friends and group buttons only appear while the mouse is over the minimap.")
        page:AddRow(W.Toggle(page, {
            label = "Hide Friends Button",
            get = function() local p = DB(); return p.hideExtraBtns and p.hideExtraBtns.friendsOnline or false end,
            set = function(v)
                local p = DB(); p.hideExtraBtns = p.hideExtraBtns or {}; p.hideExtraBtns.friendsOnline = v; Apply()
            end,
        }))
        page:AddRow(W.Toggle(page, {
            label = "Hide Group Button",
            get = function() local p = DB(); return p.hideExtraBtns and p.hideExtraBtns.groupButton or false end,
            set = function(v)
                local p = DB(); p.hideExtraBtns = p.hideExtraBtns or {}; p.hideExtraBtns.groupButton = v; Apply()
            end,
        }))

        ------------------------------------------------------------- ADDON BUTTONS
        Header(page, "Addon Buttons")
        RebuildToggle(page, "Hide Addon Compartment", "hideAddonCompartment",
            "Hide the Blizzard addon-compartment button on the minimap.")
        RebuildToggle(page, "Hide Addon Buttons", "hideAddonButtons",
            "Hide third-party addon minimap buttons entirely.")
        RebuildToggle(page, "Button Backgrounds", "btnBackgrounds",
            "Draw a dark backing behind grouped minimap buttons.")
        RebuildToggle(page, "Free-Move Buttons", "freeMoveBtns",
            "Let ungrouped buttons be dragged freely instead of auto-stacking.")
        RebuildSlider(page, "Interactable Button Size", "interactableBtnSize", 14, 32, 1, 21)
        RebuildSlider(page, "Addon Button Size", "addonBtnSize", 14, 40, 1, 24)

        ------------------------------------------------------------- VISIBILITY
        Header(page, "Visibility")
        local visOrder = {}
        for _, k in ipairs(OUI.VIS_ORDER) do
            if k ~= "---" then visOrder[#visOrder + 1] = k end
        end
        page:AddRow(W.Dropdown(page, {
            label  = "Minimap Visibility",
            values = OUI.VIS_VALUES, order = visOrder,
            tooltip = "When the whole minimap is shown.",
            get = function() return Cfg("visibility") or "always" end,
            set = function(v) Set("visibility", v); VisUpdate(); Apply() end,
        }))
        for _, item in ipairs(OUI.VIS_OPT_ITEMS) do
            page:AddRow(W.Checkbox(page, {
                label = item.label, tooltip = item.tooltip,
                get = function() return Cfg(item.key) and true or false end,
                set = function(v) Set(item.key, v); VisUpdate() end,
            }))
        end
    end,
})

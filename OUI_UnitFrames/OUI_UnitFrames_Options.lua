-- ===========================================================================
--  OldschoolUI -- Unit Frames options
-- ===========================================================================
local _, ns = ...
local OUI = OldschoolUI
if not (OUI and OUI.RegisterModule) then return end

local L  = OUI.L
local UF = ns.UF
local function DB() return (UF and UF.db and UF.db.profile) or {} end

-- boss1-5 share one config block; everything else is per unit
local OPT_UNITS = {
    { key = "player",       label = "Player" },
    { key = "target",       label = "Target" },
    { key = "focus",        label = "Focus" },
    { key = "pet",          label = "Pet" },
    { key = "targettarget", label = "Target of Target" },
    { key = "focustarget",  label = "Focus Target" },
    { key = "boss",         label = "Boss (1-5)", group = true },
}

local function repKey(o) return o.group and "boss1" or o.key end

local function uGet(o, field, default)
    local v = DB().units[repKey(o)][field]
    if v == nil then return default end
    return v
end
local function uSet(o, field, val)
    if o.group then
        for i = 1, 5 do DB().units["boss" .. i][field] = val; UF:ApplyUnit("boss" .. i) end
    else
        DB().units[o.key][field] = val; UF:ApplyUnit(o.key)
    end
end

-- global setters that fan out to every unit (uniform auras / cast / indicators)
local function allGet(field, default)
    local v = DB().units.player[field]
    if v == nil then return default end
    return v
end
local function allSet(field, val)
    for _, u in ipairs(ns.UNITS) do
        DB().units[u.key][field] = val; UF:ApplyUnit(u.key)
    end
end

local HT_VALUES = { value = "Value", percent = "Percent", both = "Both", none = "None" }
local HT_ORDER  = { "value", "percent", "both", "none" }

local function rl(o, suffix) return L(o.label) .. ": " .. L(suffix) end

OUI:RegisterModule("OUI_UnitFrames", {
    category    = "Main Modules", order = 25,
    title       = "Unit Frames",
    description = "Player, target, focus, pet and boss frames. Use /ouimove to drag them, or /ouiuf for quick commands.",
    build = function(page)
        -- -------- global -------------------------------------------------
        page:AddRow(OUI.Widgets.Toggle(page, {
            label = "Test mode (preview all frames)",
            tooltip = "Show every enabled frame, including boss1-5, with placeholder data so you can position them.",
            get = function() return UF and UF.testMode or false end,
            set = function(v) if UF then UF:SetTestMode(v) end end,
        }))

        page:AddRow(OUI.Widgets.Toggle(page, {
            label = "Hide Blizzard Unit Frames",
            tooltip = "Hide the default player / target / focus / pet frames that OUI replaces.",
            get = function() return UF and UF.db.profile.hideBlizzard ~= false end,
            set = function(v)
                if UF then UF.db.profile.hideBlizzard = v; UF:HideBlizzardFrames() end
            end,
        }))

        -- uniform aura settings (applied to all frames)
        page:AddRow(OUI.Widgets.Toggle(page, {
            label = "Auras: show buffs",
            get = function() return allGet("showBuffs", true) end,
            set = function(v) allSet("showBuffs", v); if UF then UF:ApplyAll() end end,
        }))
        page:AddRow(OUI.Widgets.Toggle(page, {
            label = "Auras: show debuffs",
            get = function() return allGet("showDebuffs", true) end,
            set = function(v) allSet("showDebuffs", v); if UF then UF:ApplyAll() end end,
        }))
        page:AddRow(OUI.Widgets.Toggle(page, {
            label = "Auras: show stack count",
            get = function() return allGet("auraShowCount", true) end,
            set = function(v) allSet("auraShowCount", v); if UF then UF:ApplyAll() end end,
        }))
        page:AddRow(OUI.Widgets.Toggle(page, {
            label = "Auras: hide remaining time",
            tooltip = "Hide the cooldown countdown numbers on buff/debuff icons.",
            get = function() return allGet("hideAuraTime", false) end,
            set = function(v) allSet("hideAuraTime", v); if UF then UF:ApplyAll() end end,
        }))
        page:AddRow(OUI.Widgets.Slider(page, {
            label = "Aura icon size", min = 12, max = 40, step = 1,
            get = function() return allGet("auraSize", 22) end,
            set = function(v) allSet("auraSize", v); if UF then UF:ApplyAll() end end,
        }))
        page:AddRow(OUI.Widgets.Slider(page, {
            label = "Auras per row", min = 4, max = 12, step = 1,
            get = function() return allGet("auraPerRow", 8) end,
            set = function(v) allSet("auraPerRow", v); if UF then UF:ApplyAll() end end,
        }))
        page:AddRow(OUI.Widgets.Slider(page, {
            label = "Aura rows", min = 1, max = 4, step = 1,
            get = function() return allGet("auraRows", 1) end,
            set = function(v) allSet("auraRows", v); if UF then UF:ApplyAll() end end,
        }))
        page:AddRow(OUI.Widgets.Dropdown(page, {
            label = "Aura position",
            values = { BELOW = "Below frame", ABOVE = "Above frame" }, order = { "BELOW", "ABOVE" },
            get = function() return allGet("auraAnchor", "BELOW") end,
            set = function(v) allSet("auraAnchor", v); if UF then UF:ApplyAll() end end,
        }))
        page:AddRow(OUI.Widgets.Slider(page, {
            label = "Aura offset", min = 0, max = 40, step = 1,
            tooltip = "Gap between the frame and the aura rows.",
            get = function() return allGet("auraOffset", 4) end,
            set = function(v) allSet("auraOffset", v); if UF then UF:ApplyAll() end end,
        }))
        page:AddRow(OUI.Widgets.Toggle(page, {
            label = "Show cast bars",
            get = function() return allGet("showCast", true) end,
            set = function(v) allSet("showCast", v); if UF then UF:ApplyAll() end end,
        }))
        page:AddRow(OUI.Widgets.Toggle(page, {
            label = "Show raid target icon",
            get = function() return allGet("showRaidIcon", true) end,
            set = function(v) allSet("showRaidIcon", v); if UF then UF:ApplyAll() end end,
        }))
        page:AddRow(OUI.Widgets.Toggle(page, {
            label = "Show threat colouring",
            get = function() return allGet("showThreat", true) end,
            set = function(v) allSet("showThreat", v); if UF then UF:ApplyAll() end end,
        }))

        -- -------- per-unit ----------------------------------------------
        for _, o in ipairs(OPT_UNITS) do
            page:AddRow(OUI.Widgets.Toggle(page, {
                label = rl(o, "Enabled"),
                get = function() return uGet(o, "enabled", true) end,
                set = function(v) uSet(o, "enabled", v) end,
            }))
            page:AddRow(OUI.Widgets.Slider(page, {
                label = rl(o, "Width"), min = 80, max = 320, step = 1,
                get = function() return uGet(o, "width", 181) end,
                set = function(v) uSet(o, "width", v) end,
            }))
            page:AddRow(OUI.Widgets.Slider(page, {
                label = rl(o, "Health height"), min = 12, max = 80, step = 1,
                get = function() return uGet(o, "healthHeight", 46) end,
                set = function(v) uSet(o, "healthHeight", v) end,
            }))
            page:AddRow(OUI.Widgets.Slider(page, {
                label = rl(o, "Power height"), min = 0, max = 20, step = 1,
                get = function() return uGet(o, "powerHeight", 6) end,
                set = function(v) uSet(o, "powerHeight", v) end,
            }))
            page:AddRow(OUI.Widgets.Slider(page, {
                label = rl(o, "Scale"), min = 0.5, max = 2.0, step = 0.05,
                get = function() return uGet(o, "scale", 1.0) end,
                set = function(v) uSet(o, "scale", v) end,
            }))
            page:AddRow(OUI.Widgets.Dropdown(page, {
                label = rl(o, "Health text"), values = HT_VALUES, order = HT_ORDER,
                get = function() return uGet(o, "healthText", "percent") end,
                set = function(v) uSet(o, "healthText", v) end,
            }))
            page:AddRow(OUI.Widgets.Slider(page, {
                label = rl(o, "Portrait size"), min = 0, max = 64, step = 1,
                tooltip = "0 hides the portrait.",
                get = function() return uGet(o, "portraitSize", 0) end,
                set = function(v) uSet(o, "portraitSize", v) end,
            }))
            page:AddRow(OUI.Widgets.Dropdown(page, {
                label = rl(o, "Portrait side"),
                values = { LEFT = "Left", RIGHT = "Right" }, order = { "LEFT", "RIGHT" },
                get = function() return uGet(o, "portraitSide", "LEFT") end,
                set = function(v) uSet(o, "portraitSide", v) end,
            }))
            page:AddRow(OUI.Widgets.Toggle(page, {
                label = rl(o, "3D portrait"),
                get = function() return uGet(o, "portrait3D", false) end,
                set = function(v) uSet(o, "portrait3D", v) end,
            }))
            page:AddRow(OUI.Widgets.Toggle(page, {
                label = rl(o, "Range fade"),
                tooltip = "Dim the frame when the unit is out of range (friendly units only).",
                get = function() return uGet(o, "rangeFade", false) end,
                set = function(v) uSet(o, "rangeFade", v) end,
            }))
        end
    end,
})

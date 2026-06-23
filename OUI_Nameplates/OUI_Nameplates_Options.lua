-------------------------------------------------------------------------------
--  OUI_Nameplates_Options.lua
--  Config page for the nameplate module, written against the OldschoolUI
--  options API (RegisterModule + page:AddRow + OUI.Widgets). A focused rewrite
--  of the full options set: the settings users actually
--  reach for, grouped by section. Niche per-slot offsets, the deferred class-
--  power display, and the text-slot element pickers are intentionally omitted
--  for now and can be layered in later. All labels are English literals routed
--  through L() by the widget system (deDE in the core locale).
--  Settings are written into the nameplate addon's shared `ns.db.profile`; most
--  apply on the next plate update, with layout refreshers nudged immediately.
-------------------------------------------------------------------------------
local _, ns = ...
local OUI = OldschoolUI
if not (OUI and OUI.RegisterModule) then return end

local function DB()     return (ns.db and ns.db.profile) or {} end
local function Cfg(k)    return DB()[k] end
local function Set(k, v) DB()[k] = v end
local function L(s)      return (OUI.L and OUI.L(s)) or s end

-- Enemy health-bar width is stored as an offset on top of this base constant;
-- the slider presents the absolute on-screen width (BAR_W + offset).
local BAR_W = ns.BAR_W or 150

-- Re-apply. ns.RefreshAllSettings() bumps the appearance generation and re-runs
-- plate:SetUnit() on every live plate, which re-applies the full appearance
-- (bar size, texture, colors, name/cast text, auras) immediately. A few frame-
-- geometry refreshers live outside that appearance path, so nudge them too.
-- RefreshAllSettings() re-runs plate:SetUnit() on every live plate (core +
-- auras + extras), which re-applies the full appearance immediately. Friendly
-- plates are handled separately below.
local function Apply()
    if ns.RefreshAllSettings then
        ns.RefreshAllSettings()
    else
        for _, fn in ipairs({ "RefreshBorder", "RefreshBorderColor" }) do
            if ns[fn] then pcall(ns[fn]) end
        end
    end
    -- Friendly plates live in their own table (ns.friendlyPlates) with a
    -- separate apply path that RefreshAllSettings does not touch. Re-evaluate
    -- the friendly system (handles show/hide + name-only mode) and re-style
    -- each live friendly plate via its own SetUnit (size, color, text, offset).
    if ns.UpdateFriendlyNameplateSystem then pcall(ns.UpdateFriendlyNameplateSystem) end
    if ns.RefreshClassPower then pcall(ns.RefreshClassPower) end
    if ns.friendlyPlates then
        for _, plate in pairs(ns.friendlyPlates) do
            if plate.unit and plate.nameplate then
                pcall(plate.SetUnit, plate, plate.unit, plate.nameplate)
            end
        end
    end
end
local _pending
local function Debounce()
    if _pending then return end
    _pending = true
    C_Timer.After(0.1, function() _pending = false; Apply() end)
end

-- Accent section header with a divider line.
local function Header(page, text)
    local row = CreateFrame("Frame", nil, page)
    row:SetHeight(20)
    local fs = OUI._label(row, 12, OUI.ACCENT.r, OUI.ACCENT.g, OUI.ACCENT.b)
    fs:SetPoint("BOTTOMLEFT", 0, 5)
    fs:SetText(string.upper(L(text)))
    OUI.RegAccent({ type = "font", obj = fs })
    local pal = OUI._palette
    local div = OUI._tex(row, "ARTWORK", pal.BRD[1], pal.BRD[2], pal.BRD[3], 1)
    div:SetPoint("BOTTOMLEFT", 0, 0); div:SetPoint("BOTTOMRIGHT", 0, 0); div:SetHeight(1)
    page:AddRow(row, 8)
end

-- ---- convenience builders bound to a page ----------------------------------
local function Toggle(page, label, key, tip)
    page:AddRow(OUI.Widgets.Toggle(page, {
        label = label, tooltip = tip,
        get = function() return Cfg(key) and true or false end,
        set = function(v) Set(key, v); Apply() end,
    }))
end
local function Slider(page, label, key, min, max, step, dflt, tip)
    page:AddRow(OUI.Widgets.Slider(page, {
        label = label, tooltip = tip, min = min, max = max, step = step,
        get = function() local v = Cfg(key); if v == nil then v = dflt end; return v end,
        set = function(v) Set(key, v); Debounce() end,
    }))
end
-- For settings stored as a 0-1 float or a 1.0-based multiplier: shown/edited as
-- a percentage, stored divided by 100 (e.g. alpha 0.4 <-> 40, scale 1.0 <-> 100).
local function FloatSlider(page, label, key, minp, maxp, stepp, dfltFloat, tip)
    page:AddRow(OUI.Widgets.Slider(page, {
        label = label, tooltip = tip, min = minp, max = maxp, step = stepp,
        get = function() local v = Cfg(key); if v == nil then v = dfltFloat end; return math.floor(v * 100 + 0.5) end,
        set = function(v) Set(key, v / 100); Debounce() end,
    }))
end
local function Dropdown(page, label, key, values, order, dflt, tip)
    page:AddRow(OUI.Widgets.Dropdown(page, {
        label = label, tooltip = tip, values = values, order = order,
        get = function() return Cfg(key) or dflt end,
        set = function(v) Set(key, v); Apply() end,
    }))
end
-- Color stored as a {r,g,b[,a]} sub-table.
local function Color(page, label, key, tip)
    page:AddRow(OUI.Widgets.ColorSwatch(page, {
        label = label, tooltip = tip,
        get = function() local c = Cfg(key) or {}; return c.r or 1, c.g or 1, c.b or 1 end,
        set = function(r, g, b)
            local c = Cfg(key); if type(c) ~= "table" then c = {}; Set(key, c) end
            c.r, c.g, c.b = r, g, b; Debounce()
        end,
    }))
end

-- Slot positions for aura groups.
local SLOT_VALUES = { top = "Top", bottom = "Bottom", left = "Left", right = "Right",
                      topleft = "Top Left", topright = "Top Right", none = "None" }
local SLOT_ORDER  = { "top", "bottom", "left", "right", "topleft", "topright", "none" }

local POS_VALUES = { LEFT = "Left", RIGHT = "Right", TOP = "Top" }
local POS_ORDER  = { "LEFT", "RIGHT", "TOP" }

-- ---- tab builders ----------------------------------------------------------
local function buildGeneral(page)
    ---------------------------------------------------------------- HEALTH BAR
    Header(page, "Health Bar")
    Dropdown(page, "Bar Texture", "healthBarTexture",
        ns.healthBarTextureNames or { none = "None" },
        ns.healthBarTextureOrder or { "none" }, "none")
    page:AddRow(OUI.Widgets.Slider(page, {
        label = "Bar Width", min = 20, max = 320, step = 2,
        get = function() return BAR_W + (Cfg("healthBarWidth") or 6) end,
        set = function(v) Set("healthBarWidth", v - BAR_W); Debounce() end,
    }))
    Slider(page, "Bar Height", "healthBarHeight", 4, 40, 1, 17)
    Dropdown(page, "Border Style", "borderStyle",
        { line = "Line", frame = "Frame", ["frame-simple"] = "Frame (simple)",
          ["frame-colorless"] = "Frame (colorless)", none = "None" },
        { "line", "frame", "frame-simple", "frame-colorless", "none" }, "line",
        "Line = thin pixel border. Frame styles are decorative; 'colorless' is tinted by Border Color.")
    Toggle(page, "Show Border", "showBorder")
    Slider(page, "Border Size", "borderSize", 0, 4, 1, 1)
    Color(page, "Border Color", "borderColor")
    FloatSlider(page, "Background Opacity (%)", "bgAlpha", 0, 100, 5, 1.0,
        "Opacity of the health bar background.")
    Slider(page, "Nameplate Y Offset", "nameplateYOffset", -40, 40, 1, 0)

    ------------------------------------------------------------ ENEMY COLORS
    Header(page, "Enemy Colors")
    Color(page, "Hostile", "hostile")
    Color(page, "Neutral", "neutral")
    Color(page, "Tapped", "tapped")
    Toggle(page, "Show Enemy Pets", "showEnemyPets")

    --------------------------------------------------------------- NAME TEXT
    Header(page, "Name Text")
    Slider(page, "Name Text Size", "enemyNameTextSize", 6, 24, 1, 11)

    ----------------------------------------------------------------- CASTBAR
    Header(page, "Cast Bar")
    Slider(page, "Cast Bar Height", "castBarHeight", 6, 40, 1, 17)
    Toggle(page, "Show Cast Icon", "showCastIcon")
    Toggle(page, "Show Cast Timer", "showCastTimer")
    Slider(page, "Cast Name Size", "castNameSize", 6, 20, 1, 10)
    Color(page, "Cast Bar Color", "castBar")
    Color(page, "Uninterruptible Color", "castBarUninterruptible")

    --------------------------------------------------------- TARGET & FOCUS
    Header(page, "Target & Focus")
    Toggle(page, "Target Color", "targetColorEnabled",
        "Tint your current target's nameplate.")
    Color(page, "Target Color", "target")
    Toggle(page, "Focus Color", "focusColorEnabled",
        "Tint your focus target's nameplate.")
    Color(page, "Focus Color", "focus")

    ------------------------------------------------------------------ THREAT
    Header(page, "Threat")
    Toggle(page, "Tank Threat Coloring", "tankHasAggroEnabled",
        "Color enemy nameplates by your threat as a tank.")
    Color(page, "Tank: Has Aggro", "tankHasAggro")
    Color(page, "Tank: Losing Aggro", "tankLosingAggro")
    Color(page, "Tank: No Aggro", "tankNoAggro")
    Color(page, "DPS: Gaining Aggro", "dpsNearAggro")
    Color(page, "DPS: Has Aggro", "dpsHasAggro")

    ---------------------------------------------------------------- FRIENDLY
    Header(page, "Friendly")
    Toggle(page, "Show Friendly Players", "showFriendlyPlayers")
    Toggle(page, "Name Only (Friendly Players)", "friendlyNameOnly")
    Toggle(page, "Class-Color Friendly Players", "classColorFriendly")
    Toggle(page, "Show Friendly NPCs", "showFriendlyNPCs")
    Slider(page, "Friendly Bar Width", "friendlyHealthBarWidth", 20, 240, 2, 110)
    Slider(page, "Friendly Bar Height", "friendlyHealthBarHeight", 4, 40, 1, 8)
    Color(page, "Friendly Bar Color", "friendlyBarColor")
    Slider(page, "Friendly Name Y Offset", "friendlyNameOnlyYOffset", -40, 40, 1, -8)

    ------------------------------------------------------------------ EXTRAS
    Header(page, "Extras")
    Toggle(page, "Show Raid Marker", "showRaidMarker")
    Slider(page, "Raid Marker Size", "raidMarkerSize", 8, 48, 1, 22)
    Dropdown(page, "Raid Marker Position", "raidMarkerPos", POS_VALUES, POS_ORDER, "LEFT")
    Toggle(page, "Show Level", "showLevel")
    Slider(page, "Level Text Size", "levelTextSize", 6, 20, 1, 10)
    Toggle(page, "Show Absorb Shield", "showAbsorb")
    Color(page, "Absorb Color", "absorbColor")
    Toggle(page, "Pandemic Glow", "pandemicGlow",
        "Glow your debuffs while they are in the pandemic (refresh) window.")
    Color(page, "Pandemic Glow Color", "pandemicGlowColor")
end

local function buildClassPower(page)
    Header(page, "Class Power")
    Toggle(page, "Show Class Power", "showClassPower",
        "Show your secondary resource (combo points, chi, holy power, runes, ...) above the enemy nameplate.")
    Toggle(page, "On Target Only", "classPowerTargetOnly",
        "Only on your current target instead of every attackable enemy.")
    Slider(page, "Class Power Height", "classPowerHeight", 3, 14, 1, 5)
end

local function buildAuras(page)
    Header(page, "Auras")
    Toggle(page, "Show All Debuffs", "showAllDebuffs",
        "Show all debuffs rather than only your own.")
    Slider(page, "Max Debuffs", "maxDebuffs", 1, 12, 1, 5)
    Slider(page, "Max Buffs", "maxBuffs", 1, 10, 1, 4)
    Slider(page, "Max CC", "maxCC", 1, 8, 1, 3)
    Slider(page, "Debuff Icon Size", "debuffIconSize", 12, 48, 1, 26)
    Slider(page, "Buff Icon Size", "buffIconSize", 12, 48, 1, 24)
    Slider(page, "CC Icon Size", "ccIconSize", 12, 48, 1, 24)
    Dropdown(page, "Debuff Position", "debuffSlot", SLOT_VALUES, SLOT_ORDER, "top")
    Dropdown(page, "Buff Position", "buffSlot", SLOT_VALUES, SLOT_ORDER, "left")
    Dropdown(page, "CC Position", "ccSlot", SLOT_VALUES, SLOT_ORDER, "right")
    Slider(page, "Aura Spacing", "auraSpacing", 0, 10, 1, 2)
    Slider(page, "Aura Duration Text Size", "auraDurationTextSize", 6, 20, 1, 11)
    Slider(page, "Aura Stack Text Size", "auraStackTextSize", 6, 20, 1, 11)
end

OUI:RegisterModule("OUI_Nameplates", {
    category    = "Better UI Module", order = 20,
    title       = "Nameplates",
    description = "Health bars, reaction colors, name/cast text, auras, target & focus effects, threat coloring, and friendly nameplates.",
    tabs = {
        { title = "General",     build = buildGeneral },
        { title = "Class Power", build = buildClassPower },
        { title = "Auras",       build = buildAuras },
    },
})

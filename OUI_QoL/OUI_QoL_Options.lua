-------------------------------------------------------------------------------
--  OUI_QoL_Options.lua -- config page for Quality of Life (OUI options API)
-------------------------------------------------------------------------------
local _, ns = ...
local OUI = OldschoolUI
if not (OUI and OUI.RegisterModule) then return end

local function DB()  return (ns.db and ns.db.profile) or {} end
local function Cfg(k) return DB()[k] end
local function Set(k, v) DB()[k] = v end
local function L(s) return (OUI.L and OUI.L(s)) or s end

local function Apply() if ns.RefreshSettings then ns.RefreshSettings() end end

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
        set = function(v) Set(key, v); Apply() end,
    }))
end

local function Dropdown(page, label, key, values, order, dflt, tip)
    page:AddRow(OUI.Widgets.Dropdown(page, {
        label = label, tooltip = tip, values = values, order = order,
        get = function() return Cfg(key) or dflt end,
        set = function(v) Set(key, v); Apply() end,
    }))
end

-- Colour swatch whose default (when no custom colour stored) is the suite
-- background ink (for backgrounds) or the accent colour (for text).
local function Swatch(page, label, key, kind)
    page:AddRow(OUI.Widgets.ColorSwatch(page, {
        label = label, hasAlpha = true,
        get = function()
            local c = Cfg(key)
            if c then return c[1], c[2], c[3], c[4] or 1 end
            if kind == "bg" then
                local ink = (OUI._palette and OUI._palette.INK) or { 0.078, 0.067, 0.043 }
                return ink[1], ink[2], ink[3], 0.9
            end
            local a = OUI.ACCENT or {}
            return a.r or 1, a.g or 0.8, a.b or 0.3, 1
        end,
        set = function(r, g, b, a) Set(key, { r, g, b, a or 1 }); Apply() end,
    }))
end

local function buildGeneral(page)
    Toggle(page, "Suppress Lua Errors", "suppressLuaErrors",
        "Hide Lua error popups (same as the Display Lua Errors option).")
    Toggle(page, "Hide Screenshot Message", "hideScreenshotMsg",
        "Suppress the on-screen 'screenshot captured' confirmation.")
    Toggle(page, "Skip Cinematics", "skipCinematics",
        "Automatically skip in-game cinematics and movies.")
    Toggle(page, "Announce Instance Reset", "announceInstanceReset",
        "Post a group message when you reset instances.")
    Toggle(page, "Hide Blizzard Party Panel", "hidePartyPanel",
        "Hide the default party/raid-manager frames (use with OUI unit frames).")
end

local function buildInventory(page)
    Toggle(page, "Auto Repair", "autoRepair",
        "Automatically repair all gear when visiting a repair vendor.")
    Toggle(page, "Use Guild Bank Funds", "autoRepairGuild",
        "Pay repairs from the guild bank when available.")
    Toggle(page, "Quick Loot", "quickLoot",
        "Instantly loot everything (hold the auto-loot modifier to bypass).")
    Toggle(page, "Auto Open Containers", "autoOpenContainers",
        "Automatically open right-click-to-open items in your bags.")
    Toggle(page, "Auto-Fill Delete Confirmation", "autoFillDelete",
        "Pre-fill the 'type DELETE' box when deleting valuable items.")
end

local function buildInfo(page)
    Toggle(page, "FPS Counter", "showFPS",
        "Show a frames-per-second readout (/ouimove to move).")
    Toggle(page, "Home Latency (ms)", "showLocalMS",
        "Show your home (local) latency in the FPS container.")
    Toggle(page, "World Latency (ms)", "showWorldMS",
        "Show your world latency in the FPS container.")
    Slider(page, "FPS Container Scale", "fpsScale", 0.5, 2, 0.1, 1,
        "Resize the FPS / latency container.")
    Toggle(page, "Override FPS Background", "fpsBgOverride",
        "Use a custom background colour instead of the OUI default.")
    Swatch(page, "FPS Background Colour", "fpsBgColor", "bg")
    Toggle(page, "Override FPS Text Colour", "fpsTextOverride",
        "Use a custom text colour instead of the accent colour.")
    Swatch(page, "FPS Text Colour", "fpsTextColor", "text")

    Toggle(page, "Secondary Stats", "showSecondaryStats",
        "Show Crit / Haste / Mastery on screen (/ouimove to move).")
    Slider(page, "Stats Container Scale", "statsScale", 0.5, 2, 0.1, 1,
        "Resize the secondary-stats container.")
    Toggle(page, "Override Stats Background", "statsBgOverride",
        "Use a custom background colour instead of the OUI default.")
    Swatch(page, "Stats Background Colour", "statsBgColor", "bg")
    Toggle(page, "Override Stats Text Colour", "statsTextOverride",
        "Use a custom text colour instead of the accent colour.")
    Swatch(page, "Stats Text Colour", "statsTextColor", "text")

    Toggle(page, "Low Durability Warning", "lowDurabilityWarn",
        "Warn when your lowest-durability item drops below the threshold.")
    Slider(page, "Durability Threshold (%)", "lowDurabilityPct", 5, 50, 5, 20,
        "Show the warning when equipment falls to or below this percentage.")
end

local function buildCursor(page)
    Toggle(page, "Cursor Circle", "cursorCircle",
        "Show a ring that follows your mouse cursor.")
    Dropdown(page, "Ring Style", "cursorStyle",
        ns.CURSOR_RING_NAMES, ns.CURSOR_RING_ORDER, "normal",
        "Thickness of the cursor ring.")
    Slider(page, "Ring Size", "cursorSize", 16, 96, 4, 32,
        "Diameter of the cursor ring in pixels.")
    Dropdown(page, "Ring Colour Mode", "cursorColorMode",
        { accent = "Accent", class = "Class", custom = "Custom" },
        { "accent", "class", "custom" }, "accent",
        "Accent colour, your class colour, or a custom colour.")
    page:AddRow(OUI.Widgets.ColorSwatch(page, {
        label = L("Custom Ring Colour"),
        get = function() local c = Cfg("cursorColor") or { 1, 1, 1 }; return c[1], c[2], c[3] end,
        set = function(r, g, b) Set("cursorColor", { r, g, b }); Apply() end,
    }))
    Toggle(page, "Only in Dungeons / Raids", "cursorInstanceOnly",
        "Only show the cursor ring inside party or raid instances.")
    Toggle(page, "Cursor Trail", "cursorTrail",
        "Leave a fading trail of dots behind the cursor.")
    Slider(page, "Trail Size", "cursorTrailSize", 8, 48, 2, 24,
        "Size of the trail dots in pixels.")
    Toggle(page, "GCD Ring", "cursorGCD",
        "Show a global-cooldown spinner around the cursor (uses the ring style/colour).")
    Slider(page, "GCD Ring Size", "cursorGCDSize", 24, 96, 4, 44,
        "Diameter of the GCD ring in pixels.")
    Toggle(page, "Cast Ring", "cursorCast",
        "Show a cast/channel progress ring around the cursor (grey when non-interruptible).")
    Slider(page, "Cast Ring Size", "cursorCastSize", 24, 96, 4, 40,
        "Diameter of the cast ring in pixels.")
end

local function buildTracker(page)
    Toggle(page, "Bloodlust Tracker", "bloodlustTracker",
        "Show an icon with the remaining Bloodlust/Heroism lockout timer (/ouimove to move).")
    Slider(page, "Bloodlust Icon Size", "bloodlustSize", 24, 80, 4, 40,
        "Size of the Bloodlust tracker icon.")
    Header(page, "Auto Combat Logging")
    Toggle(page, "Auto Combat Logging", "autoLog",
        "Automatically start/stop the combat log based on the instance you enter.")
    Toggle(page, "Log Raids", "logRaid", "Log normal and heroic raids.")
    Toggle(page, "Log LFR", "logLFR", "Log Raid Finder.")
    Toggle(page, "Log Heroic Dungeons", "logHeroicDungeon", "Log heroic 5-man dungeons.")
    Toggle(page, "Log Scenarios", "logScenario", "Log scenarios.")
    Toggle(page, "Log Challenge Modes", "logChallenge", "Log challenge-mode dungeons.")
    Toggle(page, "Delay Stop (30s)", "logDelayStop",
        "Keep logging for 30s after leaving, to capture wrap-up events.")
end

local function buildTools(page)
    Toggle(page, "Enable Frame Mover", "shifter",
        "Shift+drag Blizzard windows to move them permanently; Ctrl+drag for a temporary move. Use /ouiqolreset to reset.")
    Header(page, "Trainer")
    Toggle(page, "Trainer: Train All Button", "trainAllButton",
        "Add a 'Train All' button to the class trainer.")
end

OUI:RegisterModule("OUI_QoL", {
    category    = "QoL Functions", order = 10,
    title       = "Quality of Life",
    description = "Lightweight convenience tweaks.",
    tabs = {
        { title = "General",             build = buildGeneral },
        { title = "Inventory & Vendor",  build = buildInventory },
        { title = "Info Displays",       build = buildInfo },
        { title = "Cursor",              build = buildCursor },
        { title = "Tracker & Logging",   build = buildTracker },
        { title = "Tools",               build = buildTools },
    },
})

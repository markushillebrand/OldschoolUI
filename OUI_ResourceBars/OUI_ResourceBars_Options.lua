-- ===========================================================================
--  OldschoolUI — Resource Bars options
--  Registered against the OldschoolUI options system (RegisterModule + build).
-- ===========================================================================
local _, ns = ...
local OUI = OldschoolUI
if not (OUI and OUI.RegisterModule) then return end

local function DB() return (ns.db and ns.db.profile) or {} end
local function Refresh()
    if ns.RB then
        ns.RB:ApplyTextures(); ns.RB:ApplySkin()
        ns.RB:ApplyBlizzCast(); ns.RB:UpdateCombatFade()
        ns.RB:Relayout(); ns.RB:RefreshAll()
    end
end

local TEXT_VALUES = { value = "Absolute", percent = "Percent", both = "Both", none = "Off" }
local TEXT_ORDER  = { "value", "percent", "both", "none" }

local function Toggle(page, label, key, tip)
    page:AddRow(OUI.Widgets.Toggle(page, {
        label = label, tooltip = tip,
        get = function() return DB()[key] and true or false end,
        set = function(v) DB()[key] = v; Refresh() end,
    }))
end
local function TextMode(page, label, key, tip)
    page:AddRow(OUI.Widgets.Dropdown(page, {
        label = label, tooltip = tip, values = TEXT_VALUES, order = TEXT_ORDER,
        get = function() return DB()[key] or "value" end,
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

OUI:RegisterModule("OUI_ResourceBars", {
    category    = "Main Modules", order = 30,
    title       = "Resource Bars",
    description = "Player health, power and secondary class-resource bars. Use /ouirb unlock to reposition.",
    build = function(page)
        Toggle(page, "Show Health Bar", "showHealth")
        Toggle(page, "Show Power Bar", "showPower")
        Toggle(page, "Show Secondary Resource", "showSecond",
            "The class-resource display (Holy Power, Chi, Combo Points, Soul Shards, Eclipse, runes, ...).")
        Toggle(page, "Show Cast Bar", "showCast",
            "A player cast/channel bar shown just below the main bars while casting.")

        TextMode(page, "Health Text", "healthText",
            "What the health bar text shows: absolute value, percent, both, or nothing.")
        TextMode(page, "Power Text", "powerText")
        TextMode(page, "Secondary Text", "secText")

        Slider(page, "Width", "width", 120, 400, 4, 220)
        Slider(page, "Bar Height", "rowHeight", 8, 40, 1, 18)
        Slider(page, "Secondary Height", "secHeight", 6, 30, 1, 14)
        Slider(page, "Cast Bar Height", "castHeight", 8, 30, 1, 16)
        Slider(page, "Spacing", "spacing", 0, 12, 1, 3)

        -- Textures. The suite-wide default lives in General; here we override it
        -- for this addon (all bars), or per individual bar type.
        Toggle(page, "Override texture for all bars", "texOverrideAll")
        page:AddRow(OUI.Widgets.Dropdown(page, {
            label = "All Bars Texture",
            tooltip = "Applies to every bar in this module when enabled, overriding the UI-wide default. Per-bar overrides below still take precedence.",
            values = OUI.BAR_TEXTURE_NAMES, order = OUI.BAR_TEXTURE_ORDER,
            get = function() return DB().texAll or "flat" end,
            set = function(v) DB().texAll = v; Refresh() end,
        }))

        local function TexBlock(label, suffix)
            Toggle(page, "Override " .. label .. " Texture", "texOverride" .. suffix)
            page:AddRow(OUI.Widgets.Dropdown(page, {
                label = label .. " Texture",
                values = OUI.BAR_TEXTURE_NAMES, order = OUI.BAR_TEXTURE_ORDER,
                get = function() return DB()["tex" .. suffix] or "flat" end,
                set = function(v) DB()["tex" .. suffix] = v; Refresh() end,
            }))
        end
        TexBlock("Health", "Health")
        TexBlock("Power", "Power")
        TexBlock("Secondary", "Secondary")
        TexBlock("Cast", "Cast")

        -- Borders. Same 3-tier model: suite-wide default in General, this addon's
        -- "all bars" override, then per bar type. Each scope sets colour + size.
        local function BorderBlock(label, suffix, toggleLabel)
            Toggle(page, toggleLabel or ("Override " .. label .. " Border"), "bOverride" .. suffix)
            page:AddRow(OUI.Widgets.ColorSwatch(page, {
                label = label .. " Border Colour", hasAlpha = true,
                get = function()
                    local c = DB()["bcol" .. suffix] or { 0, 0, 0, 0.9 }
                    return c[1], c[2], c[3], c[4]
                end,
                set = function(r, g, b, a) DB()["bcol" .. suffix] = { r, g, b, a or 1 }; Refresh() end,
            }))
            Slider(page, label .. " Border Size", "bsize" .. suffix, 0, 4, 1, 1)
        end
        BorderBlock("All Bars", "All", "Override border for all bars")
        BorderBlock("Health", "Health")
        BorderBlock("Power", "Power")
        BorderBlock("Secondary", "Secondary")
        BorderBlock("Cast", "Cast")

        -- Custom fill colours (override the default green/token/palette per bar).
        local function ColBlock(label, suffix, tip)
            Toggle(page, "Custom " .. label .. " Colour", "colOverride" .. suffix, tip)
            page:AddRow(OUI.Widgets.ColorSwatch(page, {
                label = label .. " Colour",
                get = function() local c = DB()["col" .. suffix] or { 1, 1, 1 }; return c[1], c[2], c[3] end,
                set = function(r, g, b) DB()["col" .. suffix] = { r, g, b }; Refresh() end,
            }))
        end
        ColBlock("Health", "Health")
        ColBlock("Power", "Power")
        ColBlock("Secondary", "Secondary",
            "Applies to pip/bar/segment resources. Eclipse keeps its lunar/solar tint.")

        -- Combat fade.
        Toggle(page, "Fade out of combat", "combatFade",
            "Dim the whole stack when you're not in combat. Always full while unlocked.")
        Slider(page, "Out-of-combat opacity (%)", "fadeAlpha", 0, 100, 5, 25)

        -- Low-resource alerts (pulse the bar red below the threshold).
        Toggle(page, "Low health alert", "lowHealthAlert",
            "Pulse the health bar red when health drops to/below the threshold.")
        Slider(page, "Low health threshold (%)", "lowHealthPct", 5, 90, 5, 35)
        Toggle(page, "Low mana alert", "lowPowerAlert",
            "Pulse the power bar red when mana drops to/below the threshold (mana users only).")
        Slider(page, "Low mana threshold (%)", "lowPowerPct", 5, 90, 5, 25)
    end,
})

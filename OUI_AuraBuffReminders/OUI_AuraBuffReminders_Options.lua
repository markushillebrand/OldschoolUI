-------------------------------------------------------------------------------
--  OldschoolUI -- Aura & Buff Reminders : Options
-------------------------------------------------------------------------------

local OUI = OldschoolUI
if not (OUI and OUI.RegisterModule) then return end

local L = OUI.L or function(s) return s end

local function ABR() return OUI.ABR end
local function DB() local a = ABR(); return a and a.db and a.db.profile end

-- local section header (matches the Bags options pattern)
local function Header(page, text)
    local row = CreateFrame("Frame", nil, page)
    row:SetSize(280, 22)
    local fs = row:CreateFontString(nil, "OVERLAY")
    fs:SetFont((OUI.GetFontPath and OUI.GetFontPath()) or STANDARD_TEXT_FONT, 13, "")
    fs:SetPoint("LEFT", 2, 0)
    fs:SetText(L(text))
    if OUI.ACCENT then fs:SetTextColor(OUI.ACCENT.r, OUI.ACCENT.g, OUI.ACCENT.b) end
    return row
end

local SOUND_VALUES = {
    { value = "none",         text = L("None") },
    { value = "ready_check",  text = L("Ready Check") },
    { value = "raid_warning", text = L("Raid Warning") },
    { value = "map_ping",     text = L("Map Ping") },
    { value = "auction",      text = L("Auction") },
}

local STRATA_VALUES = {
    { value = "BACKGROUND", text = "BACKGROUND" },
    { value = "LOW",        text = "LOW" },
    { value = "MEDIUM",     text = "MEDIUM" },
    { value = "HIGH",       text = "HIGH" },
}

local _, PLAYER_CLASS = UnitClass("player")

OUI:RegisterModule("OUI_AuraBuffReminders", {
    title = L("Aura & Buff Reminders"),
    build = function(page)
        local function refresh() local a = ABR(); if a then a:Refresh() end end

        page:AddRow(OUI.Widgets.Toggle(page, {
            label   = L("Enable reminders"),
            tooltip = L("Show clickable icons for missing raid buffs, auras, and consumables."),
            get = function() local d = DB(); return d and d.enabled end,
            set = function(v) local d = DB(); if d then d.enabled = v; refresh() end end,
        }))

        -- ---- Display -------------------------------------------------------
        page:AddRow(Header(page, "Display"))
        page:AddRow(OUI.Widgets.Slider(page, {
            label = L("Icon size"), min = 16, max = 80, step = 1,
            get = function() local d = DB(); return d and d.iconSize or 40 end,
            set = function(v) local d = DB(); if d then d.iconSize = v; refresh() end end,
        }))
        page:AddRow(OUI.Widgets.Slider(page, {
            label = L("Icon spacing"), min = 0, max = 30, step = 1,
            get = function() local d = DB(); return d and d.spacing or 8 end,
            set = function(v) local d = DB(); if d then d.spacing = v; refresh() end end,
        }))
        page:AddRow(OUI.Widgets.Slider(page, {
            label = L("Scale"), min = 0.5, max = 2.0, step = 0.05,
            get = function() local d = DB(); return d and d.scale or 1 end,
            set = function(v) local d = DB(); if d then d.scale = v; local a = ABR(); if a then a:ApplyAnchor() end end end,
        }))
        page:AddRow(OUI.Widgets.Slider(page, {
            label = L("Opacity"), min = 0.1, max = 1.0, step = 0.05,
            get = function() local d = DB(); return d and d.opacity or 1 end,
            set = function(v) local d = DB(); if d then d.opacity = v; local a = ABR(); if a then a:ApplyAnchor() end end end,
        }))
        page:AddRow(OUI.Widgets.Dropdown(page, {
            label = L("Frame strata"), values = STRATA_VALUES,
            get = function() local d = DB(); return d and d.strata or "MEDIUM" end,
            set = function(v) local d = DB(); if d then d.strata = v; local a = ABR(); if a then a:ApplyAnchor() end end end,
        }))

        -- ---- Text ----------------------------------------------------------
        page:AddRow(Header(page, "Text"))
        page:AddRow(OUI.Widgets.Toggle(page, {
            label = L("Show spell name under icon"),
            get = function() local d = DB(); return d and d.showText end,
            set = function(v) local d = DB(); if d then d.showText = v; refresh() end end,
        }))
        page:AddRow(OUI.Widgets.Slider(page, {
            label = L("Text size"), min = 6, max = 24, step = 1,
            get = function() local d = DB(); return d and d.textSize or 12 end,
            set = function(v) local d = DB(); if d then d.textSize = v; refresh() end end,
        }))
        page:AddRow(OUI.Widgets.ColorSwatch(page, {
            label = L("Text color"),
            get = function() local d = DB(); local c = d and d.textColor or {}; return c.r or 1, c.g or 1, c.b or 1 end,
            set = function(r, g, b) local d = DB(); if d then d.textColor = { r = r, g = g, b = b }; refresh() end end,
        }))

        -- ---- Alert sound ---------------------------------------------------
        page:AddRow(Header(page, "Alert sound"))
        page:AddRow(OUI.Widgets.Dropdown(page, {
            label = L("Sound on new reminder"), values = SOUND_VALUES,
            get = function() local d = DB(); return d and d.sound or "none" end,
            set = function(v)
                local d = DB(); if not d then return end
                d.sound = v
                local a = ABR()
                local id = a and a.SOUNDS and a.SOUNDS[v]
                if id then PlaySound(id, "Master") end
            end,
        }))

        -- ---- Visibility ----------------------------------------------------
        page:AddRow(Header(page, "Visibility"))
        page:AddRow(OUI.Widgets.Toggle(page, {
            label   = L("Show raid buffs outside instances"),
            tooltip = L("By default raid-buff reminders only appear inside dungeons and raids."),
            get = function() local d = DB(); return d and d.showNonInstanced and d.showNonInstanced.raidBuffs end,
            set = function(v) local d = DB(); if d then d.showNonInstanced.raidBuffs = v; refresh() end end,
        }))
        page:AddRow(OUI.Widgets.Toggle(page, {
            label   = L("Show self auras outside instances"),
            get = function() local d = DB(); return d and d.showNonInstanced and d.showNonInstanced.selfAuras end,
            set = function(v) local d = DB(); if d then d.showNonInstanced.selfAuras = v; refresh() end end,
        }))
        page:AddRow(OUI.Widgets.Toggle(page, {
            label   = L("Show class kits outside instances"),
            get = function() local d = DB(); return d and d.showNonInstanced and d.showNonInstanced.classKits end,
            set = function(v) local d = DB(); if d then d.showNonInstanced.classKits = v; refresh() end end,
        }))
        page:AddRow(OUI.Widgets.Toggle(page, {
            label   = L("Show pet reminders outside instances"),
            get = function() local d = DB(); return d and d.showNonInstanced and d.showNonInstanced.pets end,
            set = function(v) local d = DB(); if d then d.showNonInstanced.pets = v; refresh() end end,
        }))
        page:AddRow(OUI.Widgets.Toggle(page, {
            label   = L("Show consumables outside instances"),
            get = function() local d = DB(); return d and d.showNonInstanced and d.showNonInstanced.consumables end,
            set = function(v) local d = DB(); if d then d.showNonInstanced.consumables = v; refresh() end end,
        }))

        -- ---- Per-reminder toggles (player's class only) --------------------
        local a = ABR()
        if a and a.DEFS then
            local shownHeader = false
            for _, def in ipairs(a.DEFS) do
                if not def.class or def.class == PLAYER_CLASS then
                    if not shownHeader then
                        page:AddRow(Header(page, "Reminders"))
                        shownHeader = true
                    end
                    local key = def.key
                    page:AddRow(OUI.Widgets.Toggle(page, {
                        label = (a.DefLabel and a.DefLabel(def)) or def.name,
                        get = function() local d = DB(); return d and d.enabled_keys and d.enabled_keys[key] ~= false end,
                        set = function(v) local d = DB(); if d then d.enabled_keys[key] = v; refresh() end end,
                    }))
                end
            end
        end
    end,
})

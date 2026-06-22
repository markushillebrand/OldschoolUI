-- ===========================================================================
--  OldschoolUI -- Raid Frames options
-- ===========================================================================
local _, ns = ...
local OUI = OldschoolUI
if not (OUI and OUI.RegisterModule) then return end

local RF = ns.RF
local function DB() return (RF and RF.db and RF.db.profile) or {} end

-- which template the layout sliders edit (module-local UI state)
local editKey = "medium"

local function curKey()
    if DB().uniformLayout then return "all" end
    return editKey
end
local function T() local d = DB().templates; return d and d[curKey()] end
local function tGet(field, default)
    local t = T(); local v = t and t[field]
    if v == nil then return default end
    return v
end
local function tSet(field, val)
    local t = T(); if not t then return end
    t[field] = val
    if RF then RF:ApplyLayout(); if RF.testMode then RF:LayoutPreview() end end
end

local function sGet(field, default)
    local v = DB()[field]; if v == nil then return default end; return v
end
local function sSet(field, val)
    DB()[field] = val
    if RF then RF:ApplyLayout(); RF:RefreshAll(); if RF.testMode then RF:LayoutPreview() end end
end

OUI:RegisterModule("OUI_RaidFrames", {
    category    = "Main Modules", order = 35,
    title       = "Raid Frames",
    description = "Party and raid member frames. Three layout templates auto-switch by group size (10 / 25 / 40). Use /ouimove to drag, or /ouirf for quick commands.",
    build = function(page)
        -- -------- preview + template picker -----------------------------
        page:AddRow(OUI.Widgets.Toggle(page, {
            label = "Preview (placeholder members)",
            tooltip = "Show fake members so you can lay the frames out. The 10/25/40 switcher above the preview picks which template you edit.",
            get = function() return RF and RF.testMode or false end,
            set = function(v) if RF then RF:SetTestMode(v) end end,
        }))
        page:AddRow(OUI.Widgets.Toggle(page, {
            label = "One configuration for all sizes",
            tooltip = "ON: a single layout applies to 10/25/40 (the per-size templates are ignored). OFF: each raid size uses its own template below.",
            get = function() return DB().uniformLayout or false end,
            set = function(v)
                DB().uniformLayout = v
                if RF then RF:ApplyLayout(); if RF.testMode then RF:LayoutPreview() end end
                if C_Timer and C_Timer.After then
                    C_Timer.After(0, function() OUI:SelectModule("OUI_RaidFrames") end)
                end
            end,
        }))
        if not DB().uniformLayout then
            page:AddRow(OUI.Widgets.Dropdown(page, {
                label = "Edit template",
                tooltip = "Each group-size bracket has its own layout: 10 (<=10 players), 25 (11-25), 40 (>25).",
                values = { small = "10 players", medium = "25 players", large = "40 players" },
                order = { "small", "medium", "large" },
                get = function() return editKey end,
                set = function(v)
                    editKey = v
                    if RF then RF:SetPreviewTemplate(v) end
                end,
            }))
        end

        -- -------- per-template layout -----------------------------------
        page:AddRow(OUI.Widgets.Slider(page, {
            label = "Frame width", min = 40, max = 220, step = 1,
            get = function() return tGet("width", 100) end,
            set = function(v) tSet("width", v) end,
        }))
        page:AddRow(OUI.Widgets.Slider(page, {
            label = "Frame height", min = 20, max = 120, step = 1,
            get = function() return tGet("height", 50) end,
            set = function(v) tSet("height", v) end,
        }))
        page:AddRow(OUI.Widgets.Slider(page, {
            label = "Power bar height", min = 0, max = 16, step = 1,
            get = function() return tGet("powerHeight", 7) end,
            set = function(v) tSet("powerHeight", v) end,
        }))
        page:AddRow(OUI.Widgets.Slider(page, {
            label = "Units per column", min = 1, max = 40, step = 1,
            tooltip = "How many members stack in one column before a new column starts.",
            get = function() return tGet("unitsPerColumn", 5) end,
            set = function(v) tSet("unitsPerColumn", v) end,
        }))
        page:AddRow(OUI.Widgets.Slider(page, {
            label = "Max columns", min = 1, max = 8, step = 1,
            get = function() return tGet("maxColumns", 5) end,
            set = function(v) tSet("maxColumns", v) end,
        }))
        page:AddRow(OUI.Widgets.Slider(page, {
            label = "Row spacing", min = 0, max = 24, step = 1,
            get = function() return tGet("rowSpacing", 4) end,
            set = function(v) tSet("rowSpacing", v) end,
        }))
        page:AddRow(OUI.Widgets.Slider(page, {
            label = "Column spacing", min = 0, max = 24, step = 1,
            get = function() return tGet("columnSpacing", 8) end,
            set = function(v) tSet("columnSpacing", v) end,
        }))
        page:AddRow(OUI.Widgets.Dropdown(page, {
            label = "Grow direction (rows)",
            values = { TOP = "Down", BOTTOM = "Up" }, order = { "TOP", "BOTTOM" },
            get = function() return tGet("point", "TOP") end,
            set = function(v) tSet("point", v) end,
        }))
        page:AddRow(OUI.Widgets.Dropdown(page, {
            label = "Grow direction (columns)",
            values = { LEFT = "Right", RIGHT = "Left" }, order = { "LEFT", "RIGHT" },
            get = function() return tGet("columnAnchor", "LEFT") end,
            set = function(v) tSet("columnAnchor", v) end,
        }))
        page:AddRow(OUI.Widgets.Slider(page, {
            label = "Template scale", min = 50, max = 150, step = 1,
            get = function() return math.floor((tGet("scale", 1.0)) * 100 + 0.5) end,
            set = function(v) tSet("scale", v / 100) end,
        }))

        -- -------- shared display ----------------------------------------
        page:AddRow(OUI.Widgets.Toggle(page, {
            label = "Enabled",
            get = function() return sGet("enabled", true) end,
            set = function(v) sSet("enabled", v) end,
        }))
        page:AddRow(OUI.Widgets.Toggle(page, {
            label = "Hide Blizzard Party/Raid Frames",
            tooltip = "Hide the default party frames and compact raid frames OUI replaces.",
            get = function() return sGet("hideBlizzard", true) end,
            set = function(v) DB().hideBlizzard = v; if RF then RF:HideBlizzardParty() end end,
        }))
        page:AddRow(OUI.Widgets.Toggle(page, {
            label = "Show player",
            get = function() return sGet("showPlayer", true) end,
            set = function(v) sSet("showPlayer", v) end,
        }))
        page:AddRow(OUI.Widgets.Toggle(page, {
            label = "Show when solo",
            get = function() return sGet("showSolo", false) end,
            set = function(v) sSet("showSolo", v) end,
        }))
        page:AddRow(OUI.Widgets.Toggle(page, {
            label = "Show power bar",
            get = function() return sGet("showPower", true) end,
            set = function(v) sSet("showPower", v) end,
        }))
        page:AddRow(OUI.Widgets.Dropdown(page, {
            label = "Health text",
            values = { none = "None", percent = "Percent", deficit = "Deficit" },
            order = { "none", "percent", "deficit" },
            get = function() return sGet("healthText", "none") end,
            set = function(v) sSet("healthText", v) end,
        }))
        page:AddRow(OUI.Widgets.Toggle(page, {
            label = "Show role icon",
            get = function() return sGet("showRole", true) end,
            set = function(v) sSet("showRole", v) end,
        }))
        page:AddRow(OUI.Widgets.Toggle(page, {
            label = "Show leader / assistant icon",
            get = function() return sGet("showLeader", true) end,
            set = function(v) sSet("showLeader", v) end,
        }))
        page:AddRow(OUI.Widgets.Toggle(page, {
            label = "Show raid target marker",
            get = function() return sGet("showRaidIcon", true) end,
            set = function(v) sSet("showRaidIcon", v) end,
        }))
        page:AddRow(OUI.Widgets.Toggle(page, {
            label = "Show threat colouring",
            get = function() return sGet("showThreat", true) end,
            set = function(v) sSet("showThreat", v) end,
        }))
        page:AddRow(OUI.Widgets.Toggle(page, {
            label = "Fade out-of-range members",
            get = function() return sGet("rangeFade", true) end,
            set = function(v) sSet("rangeFade", v) end,
        }))
        page:AddRow(OUI.Widgets.Slider(page, {
            label = "Out-of-range opacity", min = 10, max = 100, step = 5,
            get = function() return math.floor((sGet("fadeAlpha", 0.45)) * 100 + 0.5) end,
            set = function(v) sSet("fadeAlpha", v / 100) end,
        }))

        -- -------- auras -------------------------------------------------
        page:AddRow(OUI.Widgets.Toggle(page, {
            label = "Show debuffs",
            get = function() return sGet("showDebuffs", true) end,
            set = function(v) sSet("showDebuffs", v) end,
        }))
        page:AddRow(OUI.Widgets.Toggle(page, {
            label = "Debuffs: only class-dispellable",
            tooltip = "Only show debuffs your class can remove (Magic / Curse / Poison / Disease).",
            get = function() return sGet("debuffsDispellableOnly", false) end,
            set = function(v) sSet("debuffsDispellableOnly", v) end,
        }))
        page:AddRow(OUI.Widgets.Slider(page, {
            label = "Max debuffs", min = 1, max = 6, step = 1,
            get = function() return sGet("maxDebuffs", 3) end,
            set = function(v) sSet("maxDebuffs", v) end,
        }))
        page:AddRow(OUI.Widgets.Toggle(page, {
            label = "Show buffs",
            get = function() return sGet("showBuffs", false) end,
            set = function(v) sSet("showBuffs", v) end,
        }))
        page:AddRow(OUI.Widgets.Toggle(page, {
            label = "Buffs: only my own",
            get = function() return sGet("buffsOwnOnly", true) end,
            set = function(v) sSet("buffsOwnOnly", v) end,
        }))
        page:AddRow(OUI.Widgets.Slider(page, {
            label = "Max buffs", min = 1, max = 6, step = 1,
            get = function() return sGet("maxBuffs", 3) end,
            set = function(v) sSet("maxBuffs", v) end,
        }))
        page:AddRow(OUI.Widgets.Slider(page, {
            label = "Aura icon size", min = 10, max = 32, step = 1,
            get = function() return sGet("auraSize", 18) end,
            set = function(v) sSet("auraSize", v) end,
        }))
        page:AddRow(OUI.Widgets.Toggle(page, {
            label = "Auras: hide remaining time",
            tooltip = "Hide the cooldown countdown numbers on buff/debuff icons.",
            get = function() return sGet("hideAuraTime", false) end,
            set = function(v) sSet("hideAuraTime", v) end,
        }))
    end,
})

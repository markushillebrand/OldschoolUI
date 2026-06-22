-- ===========================================================================
--  OldschoolUI -- Blizzard Skin options
-- ===========================================================================
local _, ns = ...
local OUI = OldschoolUI
if not (OUI and OUI.RegisterModule) then return end

local BS = ns.BS
local function DB() return (BS and BS.db and BS.db.profile) or {} end

OUI:RegisterModule("OUI_BlizzardSkin", {
    category    = "Main Modules", order = 40,
    title       = "Blizzard Skin",
    description = "Themes stock Blizzard frames to match the suite. "
               .. "Tooltips first; menus, popups and dialogs follow.",
    build = function(page)
        page:AddRow(OUI.Widgets.Toggle(page, {
            label = "Reskin tooltips",
            tooltip = "Dark background and themed border on game tooltips.",
            get = function() return DB().reskinTooltips ~= false end,
            set = function(v) DB().reskinTooltips = v end,
        }))
        page:AddRow(OUI.Widgets.Toggle(page, {
            label = "Reskin menus & dialogs",
            tooltip = "Dark theme for context menus, static popups and the game menu.",
            get = function() return DB().reskinFrames ~= false end,
            set = function(v) DB().reskinFrames = v end,
        }))
        page:AddRow(OUI.Widgets.Toggle(page, {
            label = "Custom character pane",
            tooltip = "Replace Blizzard's character window with the OldschoolUI character pane (character key).",
            get = function() return DB().customCharacterSheet ~= false end,
            set = function(v) DB().customCharacterSheet = v end,
        }))
        page:AddRow(OUI.Widgets.Toggle(page, {
            label = "Accent-coloured border",
            tooltip = "Use the suite accent colour for the tooltip border instead of neutral dark.",
            get = function() return DB().accentBorders and true or false end,
            set = function(v) DB().accentBorders = v end,
        }))
        page:AddRow(OUI.Widgets.Toggle(page, {
            label = "Class-coloured names",
            tooltip = "Colour player names in tooltips by their class.",
            get = function() return DB().classColorNames ~= false end,
            set = function(v) DB().classColorNames = v end,
        }))
        page:AddRow(OUI.Widgets.Toggle(page, {
            label = "Show player titles",
            tooltip = "Include the player's selected title on the tooltip name line.",
            get = function() return DB().showPlayerTitles and true or false end,
            set = function(v) DB().showPlayerTitles = v end,
        }))
        page:AddRow(OUI.Widgets.Toggle(page, {
            label = "Show item level",
            tooltip = "Append the item level for equippable items.",
            get = function() return DB().showItemLevel ~= false end,
            set = function(v) DB().showItemLevel = v end,
        }))
        page:AddRow(OUI.Widgets.Toggle(page, {
            label = "Show spell ID",
            tooltip = "Append the numeric spell id to spell tooltips.",
            get = function() return DB().showSpellID and true or false end,
            set = function(v) DB().showSpellID = v end,
        }))
        page:AddRow(OUI.Widgets.Slider(page, {
            label = "Tooltip font scale (%)",
            tooltip = "Scale tooltip text. 100 leaves Blizzard's sizing untouched.",
            min = 80, max = 150, step = 5,
            get = function() return math.floor((DB().tooltipFontScale or 1.0) * 100 + 0.5) end,
            set = function(v) DB().tooltipFontScale = v / 100 end,
        }))
    end,
})

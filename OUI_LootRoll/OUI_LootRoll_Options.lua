-------------------------------------------------------------------------------
--  OUI_LootRoll_Options.lua
--  Config page for the custom loot roll bars, rewritten against the OldschoolUI
--  options API (RegisterModule + page:AddRow + OUI.Widgets). Single scrollable
--  page under the "QoL Functions" category. All labels/tooltips are English
--  literals routed through L() by the widget system (deDE in the core locale).
-------------------------------------------------------------------------------
local _, ns = ...
local OUI = OldschoolUI
if not (OUI and OUI.RegisterModule) then return end
local LR = ns.LR

local function DB()    return ns.LR_GetSettings and ns.LR_GetSettings() or {} end
local function Cfg(k)  return DB()[k] end
local function Set(k, v) DB()[k] = v end
local function Apply() if LR and LR.Rebuild then LR.Rebuild() end end
local function L(s)    return (OUI.L and OUI.L(s)) or s end

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

local W = OUI.Widgets

local function buildGeneral(page)
    page:AddRow(W.Toggle(page, {
        label   = "Enable",
        tooltip = "Replace Blizzard's default loot roll frame with OldschoolUI bars. Toggling off requires a /reload to restore Blizzard's frame.",
        get = function() return Cfg("enabled") ~= false end,
        set = function(v) Set("enabled", v) end,
    }))
    page:AddRow(W.Segmented(page, {
        label    = "Growth Direction",
        segments = { { value = "DOWN", text = "Down" }, { value = "UP", text = "Up" } },
        get = function() return Cfg("growth") or "DOWN" end,
        set = function(v) Set("growth", v); Apply() end,
    }))
    page:AddRow(W.Toggle(page, {
        label   = "Disenchant Button",
        tooltip = "Show the Disenchant roll button when available.",
        get = function() return Cfg("showDisenchant") ~= false end,
        set = function(v) Set("showDisenchant", v); Apply() end,
    }))
    page:AddRow(W.Toggle(page, {
        label   = "Roll Counts",
        tooltip = "Show how many players chose Need / Greed / Disenchant / Pass on each button (via the loot history).",
        get = function() return Cfg("showRollCounts") ~= false end,
        set = function(v) Set("showRollCounts", v); Apply() end,
    }))
    page:AddRow(W.Toggle(page, {
        label   = "Quality Border",
        tooltip = "Color each bar's border by item quality.",
        get = function() return Cfg("qualityBorder") ~= false end,
        set = function(v) Set("qualityBorder", v); Apply() end,
    }))
    page:AddRow(W.Toggle(page, {
        label   = "Auto-Confirm BoP",
        tooltip = "Automatically confirm the bind-on-pickup / bind-on-account popup when you Need or Greed such an item.",
        get = function() return Cfg("autoConfirmBoP") == true end,
        set = function(v) Set("autoConfirmBoP", v) end,
    }))
    page:AddRow(W.Toggle(page, {
        label   = "Minimap Button",
        tooltip = "Show a loot-roll button on the minimap (under the calendar) that opens the session window.",
        get = function() return Cfg("minimapButton") ~= false end,
        set = function(v) Set("minimapButton", v); if ns.LR_RefreshMinimapButton then ns.LR_RefreshMinimapButton() end end,
    }))
    page:AddRow(Header(page, "Size"))
    page:AddRow(W.Slider(page, { label = "Width", min = 200, max = 500, step = 2,
        get = function() return Cfg("width") or 328 end,
        set = function(v) Set("width", v); Apply() end }))
    page:AddRow(W.Slider(page, { label = "Height", min = 18, max = 48, step = 1,
        get = function() return Cfg("height") or 28 end,
        set = function(v) Set("height", v); Apply() end }))
    page:AddRow(W.Slider(page, { label = "Spacing", min = 0, max = 16, step = 1,
        get = function() return Cfg("spacing") or 4 end,
        set = function(v) Set("spacing", v); Apply() end }))
    page:AddRow(W.Slider(page, { label = "Scale", min = 0.5, max = 2.0, step = 0.05,
        get = function() return Cfg("scale") or 1.0 end,
        set = function(v) Set("scale", v); Apply() end }))
end

local function buildSession(page)
    page:AddRow(W.Button(page, { label = "Open Session Window", width = 200,
        onClick = function() if ns.LR_ToggleSession then ns.LR_ToggleSession() end end }))
    page:AddRow(W.Toggle(page, {
        label   = "Show Others' Rolls",
        tooltip = "Show individual rolls of other players in the session window.",
        get = function() return Cfg("showOthersRolls") ~= false end,
        set = function(v) Set("showOthersRolls", v); if ns.LR_OnSessionChanged then ns.LR_OnSessionChanged() end end,
    }))
end

local function buildBonus(page)
    page:AddRow(W.Button(page, { label = "Open Bonus Roll History", width = 200,
        onClick = function() if ns.LR_ToggleBonusHistory then ns.LR_ToggleBonusHistory() end end }))
    page:AddRow(W.Slider(page, { label = "History Rows", min = 5, max = 50, step = 1,
        tooltip = "How many recent bonus rolls the history window shows.",
        get = function() return Cfg("bonusMaxShow") or 20 end,
        set = function(v) Set("bonusMaxShow", v) end }))
    page:AddRow(W.Toggle(page, {
        label   = "Bonus Roll Reminder",
        tooltip = "When a bonus roll becomes available, announce it (chat + raid warning + sound) if the current boss still has an un-obtained wishlist item at the current difficulty.",
        get = function() return Cfg("bonusReminder") == true end,
        set = function(v) Set("bonusReminder", v) end,
    }))
    page:AddRow(W.Toggle(page, {
        label   = "Use Blizzard's Bonus-Roll Button",
        tooltip = "Show Blizzard's own bonus-roll frame instead of the OUI panel. Leave this on if the OUI roll button isn't working. (/ouibonus log shows debug info.)",
        get = function() return Cfg("useNativeBonusRoll") ~= false end,
        set = function(v) Set("useNativeBonusRoll", v) end,
    }))
    page:AddRow(W.Toggle(page, {
        label   = "Auto-Ignore Others",
        tooltip = "Automatically decline bonus rolls when the current boss has no open wishlist item at the current difficulty. Only active while your wishlist has at least one open wish.",
        get = function() return Cfg("bonusAutoIgnore") == true end,
        set = function(v) Set("bonusAutoIgnore", v) end,
    }))
    page:AddRow(W.Toggle(page, {
        label   = "Wish Item Drop Hint",
        tooltip = "When a wishlist item drops in a group loot roll, announce it and suggest waiting for the roll result before spending a bonus roll.",
        get = function() return Cfg("wishlistDropHint") ~= false end,
        set = function(v) Set("wishlistDropHint", v) end,
    }))
end

local function buildWishlist(page)
    page:AddRow(W.Toggle(page, {
        label   = "Usable Items Only",
        tooltip = "In the item browser, only show loot your character can actually use (class/spec filter). Turn off to see every drop.",
        get = function() return Cfg("wishlistUsableOnly") ~= false end,
        set = function(v) Set("wishlistUsableOnly", v) end,
    }))
    page:AddRow(W.Button(page, { label = "Open Wishlist", width = 200,
        onClick = function() if ns.LR_ToggleWishlist then ns.LR_ToggleWishlist() end end }))
    page:AddRow(W.Button(page, { label = "Add Items (Browse Raids)...", width = 200,
        onClick = function() if ns.LR_ToggleWishlistBrowser then ns.LR_ToggleWishlistBrowser() end end }))
end

OUI:RegisterModule("OUI_LootRoll", {
    category    = "QoL Functions", order = 10,
    title       = "Loot Roll",
    description = "Custom group loot roll bars: countdown, roll tally, disenchant button, mover.",
    tabs = {
        { title = "General",       build = buildGeneral },
        { title = "Session",       build = buildSession },
        { title = "Bonus Rolls",   build = buildBonus },
        { title = "Loot Wishlist", build = buildWishlist },
    },
})

SLASH_OUILROPTS1 = "/ouilropts"
SlashCmdList["OUILROPTS"] = function()
    if InCombatLockdown and InCombatLockdown() then return end
    OUI:SelectPage("OUI_LootRoll")
end

-------------------------------------------------------------------------------
--  OUI_Friends_Options.lua
--  Config page for the friends module (OldschoolUI options API). Settings write
--  into ns.db.profile and re-apply immediately. Labels via L() (deDE in core).
-------------------------------------------------------------------------------
local _, ns = ...
local OUI = OldschoolUI
if not (OUI and OUI.RegisterModule) then return end

local function DB()     return (ns.db and ns.db.profile) or {} end
local function Cfg(k)    return DB()[k] end
local function Set(k, v) DB()[k] = v end
local function L(s)      return (OUI.L and OUI.L(s)) or s end

local function Apply()
    if ns.RefreshSettings then ns.RefreshSettings() end
end
local _pending
local function Debounce()
    if _pending then return end
    _pending = true
    C_Timer.After(0.1, function() _pending = false; Apply() end)
end

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
        set = function(v) Set(key, v); Debounce() end,
    }))
end
local function FloatSlider(page, label, key, minp, maxp, stepp, dfltFloat, tip)
    page:AddRow(OUI.Widgets.Slider(page, {
        label = label, tooltip = tip, min = minp, max = maxp, step = stepp,
        get = function() local v = Cfg(key); if v == nil then v = dfltFloat end; return math.floor(v * 100 + 0.5) end,
        set = function(v) Set(key, v / 100); Debounce() end,
    }))
end
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

OUI:RegisterModule("OUI_Friends", {
    category    = "Better UI Module", order = 26,
    title       = "Friends",
    description = "A clean friends panel with class icons, faction icons and realm grouping.",
    build = function(page)
        ---------------------------------------------------------------- GENERAL
        Header(page, "General")
        Toggle(page, "Enable Friends panel", "enabled")
        Toggle(page, "Replace Blizzard Friends Frame", "replaceBlizzard",
            "Open this panel instead of the default frame when the Friends button is used.")
        Toggle(page, "Open on login", "autoShow")
        Toggle(page, "Show offline friends", "showOffline")
        Toggle(page, "Auto-accept friend invites", "autoAcceptFriendInvites",
            "Automatically accept incoming Battle.net friend requests.")

        ------------------------------------------------------------- APPEARANCE
        Header(page, "Appearance")
        Color(page, "Background Color", "bgColor")
        Toggle(page, "Show Border", "showBorder")
        Color(page, "Border Color", "borderColor")
        Toggle(page, "Accent Header Line", "accentHeader")
        FloatSlider(page, "Scale (%)", "scale", 50, 200, 5, 1.0)
        Slider(page, "Width", "width", 220, 520, 10, 320)
        Slider(page, "Height", "height", 200, 800, 20, 420)

        ----------------------------------------------------------------- LIST
        Header(page, "List")
        Toggle(page, "Show Ignored Tab", "showIgnoredTab")
        Toggle(page, "Show Who Tab", "showWhoTab")
        Toggle(page, "Class-Colored Names", "classColorNames")
        Toggle(page, "Show Class Icons", "showClassIcons")
        Toggle(page, "Show Faction Icons", "showFactionIcons")
        Toggle(page, "Group by Realm", "groupByRealm",
            "Group friends under collapsible realm headers.")
    end,
})

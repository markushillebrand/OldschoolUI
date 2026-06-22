-------------------------------------------------------------------------------
--  OUI_Chat_Options.lua
--  Config page for the chat module, written against the OldschoolUI options API
--  (RegisterModule + page:AddRow + OUI.Widgets). Settings write into the chat
--  addon's shared `ns.db.profile` and re-apply immediately. All labels are
--  English literals routed through L() (deDE in the core locale).
-------------------------------------------------------------------------------
local _, ns = ...
local OUI = OldschoolUI
if not (OUI and OUI.RegisterModule) then return end

local function DB()     return (ns.db and ns.db.profile) or {} end
local function Cfg(k)    return DB()[k] end
local function Set(k, v) DB()[k] = v end
local function L(s)      return (OUI.L and OUI.L(s)) or s end

local function Apply()
    if ns.ApplyAll then ns.ApplyAll() end
    if ns.RefreshSidebar then ns.RefreshSidebar() end
    if ns.RefreshCopyButtons then ns.RefreshCopyButtons() end
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
local function Dropdown(page, label, key, values, order, dflt, tip)
    page:AddRow(OUI.Widgets.Dropdown(page, {
        label = label, tooltip = tip, values = values, order = order,
        get = function() return Cfg(key) or dflt end,
        set = function(v) Set(key, v); Apply() end,
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

local OUTLINE_VALUES = { [""] = "None", OUTLINE = "Outline", THICKOUTLINE = "Thick" }
local OUTLINE_ORDER  = { "", "OUTLINE", "THICKOUTLINE" }
local EDITPOS_VALUES = { BOTTOM = "Bottom", TOP = "Top" }
local EDITPOS_ORDER  = { "BOTTOM", "TOP" }
local VIS_VALUES     = { always = "Always", mouseover = "Mouseover", never = "Never" }
local VIS_ORDER      = { "always", "mouseover", "never" }
local SIDE_VALUES    = { LEFT = "Left", RIGHT = "Right" }
local SIDE_ORDER     = { "LEFT", "RIGHT" }

local function buildGeneral(page)
    Toggle(page, "Enable chat skinning", "enabled")
    Toggle(page, "Hide Blizzard chat buttons", "hideDefaultButtons",
        "Hide the default chat menu, channel, quick-join and voice buttons.")
    Header(page, "Appearance")
    Toggle(page, "Show Background", "showBackground")
    Color(page, "Background Color", "bgColor")
    Toggle(page, "Show Border", "showBorder")
    Color(page, "Border Color", "borderColor")
    Toggle(page, "Text Shadow", "shadow")
    Toggle(page, "Use Suite Outline", "useSuiteOutline",
        "Follow the suite-wide font outline. Turn off to pick one below.")
    Dropdown(page, "Outline", "outline", OUTLINE_VALUES, OUTLINE_ORDER, "")
    Toggle(page, "Override Font Size", "useGlobalFontSize",
        "Force one font size on all chat windows instead of their own.")
    Slider(page, "Font Size", "fontSize", 8, 24, 1, 13)
end

local function buildWindow(page)
    Toggle(page, "Style Tabs", "styleTabs")
    Toggle(page, "Style Edit Box", "styleEditBox")
    Dropdown(page, "Edit Box Position", "editBoxPosition", EDITPOS_VALUES, EDITPOS_ORDER, "BOTTOM")
    Header(page, "Idle Fade")
    Toggle(page, "Enable Idle Fade", "idleFadeEnabled")
    Slider(page, "Fade Delay (s)", "idleFadeDelay", 1, 60, 1, 15)
    Slider(page, "Fade Strength (%)", "idleFadeStrength", 0, 99, 1, 40,
        "How much to fade when idle. 0 = no fade, 99 = almost invisible.")
    Toggle(page, "Stay Visible in Combat", "fadeStayInCombat")
end

local function buildTools(page)
    Toggle(page, "Show Copy Button", "showCopyButton",
        "A hover button to copy the chat. /ouicopy also works.")
    Toggle(page, "Clickable URLs", "clickableURLs",
        "Make links in incoming messages clickable (opens a copy popup).")
    Header(page, "History")
    Toggle(page, "Persist Chat History", "persistChatHistory",
        "Restore recent scrollback after a /reload or relog. /ouichatwipe clears it.")
    Slider(page, "Max History Lines", "persistChatHistoryMaxLines", 20, 500, 10, 100)
end

local function buildSidebar(page)
    Toggle(page, "Enable Sidebar", "sidebarEnabled")
    Dropdown(page, "Visibility", "sidebarVisibility", VIS_VALUES, VIS_ORDER, "mouseover")
    Dropdown(page, "Side", "sidebarSide", SIDE_VALUES, SIDE_ORDER, "LEFT")
    Slider(page, "Icon Size", "sidebarIconSize", 12, 40, 1, 20)
    Slider(page, "Icon Spacing", "sidebarSpacing", 0, 16, 1, 6)
    Toggle(page, "Sidebar Background", "sidebarBg")
    Toggle(page, "Button: Copy Chat", "sidebarShowCopy")
    Toggle(page, "Button: Friends", "sidebarShowFriends")
    Toggle(page, "Button: Guild", "sidebarShowGuild")
    Toggle(page, "Button: Calendar", "sidebarShowCalendar")
    Toggle(page, "Button: Dungeon Finder", "sidebarShowLFD")
end

OUI:RegisterModule("OUI_Chat", {
    category    = "Better UI Module", order = 25,
    title       = "Chat",
    description = "Chat skinning, idle fade, copy & clickable URLs, persistent history and a sidebar.",
    tabs = {
        { title = "General",        build = buildGeneral },
        { title = "Window & Input", build = buildWindow },
        { title = "Tools",          build = buildTools },
        { title = "Sidebar",        build = buildSidebar },
    },
})

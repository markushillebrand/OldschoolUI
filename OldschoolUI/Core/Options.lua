-- OldschoolUI / Core / Options.lua  (Pass 3, part 1)
-- Options panel shell: header, sidebar (3 categories), content area, footer.
-- RegisterModule / SelectModule, open/close, minimap button, escape, slash.
-- Tab-ready: each module currently renders one page; per-module tabs come later.

local OUI = OldschoolUI
local L   = OUI.L
local P   = OUI._palette
local Tex, Lbl, Border, Hover = OUI._tex, OUI._label, OUI._border, OUI._hover
local INK, ROW, BRD, BRD2, DIM, TXT = P.INK, P.ROW, P.BRD, P.BRD2, P.DIM, P.TXT
local function A() return OUI.ACCENT.r, OUI.ACCENT.g, OUI.ACCENT.b end

-- Category render order (English keys; localized at render).
local CATEGORY_ORDER = { "Main Modules", "Better UI Module", "QoL Functions" }

local modules, moduleOrder = {}, {}

function OUI:RegisterModule(folder, config)
    config = config or {}
    config.folder   = folder
    config.category = config.category or "Main Modules"
    config.order    = config.order or 100
    if not modules[folder] then moduleOrder[#moduleOrder + 1] = folder end
    modules[folder] = config
    if OUI._panelBuilt then OUI._RebuildSidebar() end
end

-- ---------------------------------------------------------------------
local mainFrame, sidebar, content, activeFolder, searchBox
local entries = {}

local function SelectModule(folder)
    local cfg = modules[folder]; if not cfg then return end
    activeFolder = folder
    for f, e in pairs(entries) do
        local on = (f == folder)
        e.bar:SetShown(on)
        e.bg:SetShown(on)
        e.lbl:SetTextColor(on and TXT[1] or DIM[1], on and TXT[2] or DIM[2], on and TXT[3] or DIM[3])
    end
    content.title:SetText(L(cfg.title or folder))
    content.desc:SetText(L(cfg.description or ""))
    content.body:Reset()
    if cfg.build then cfg.build(content.body) end
    if content.scroll then content.scroll:SetVerticalScroll(0) end
end
OUI.SelectModule = function(_, folder) SelectModule(folder) end

-- ---- sidebar ----
local function ClearSidebar()
    for _, e in pairs(entries) do e.frame:Hide(); e.frame:SetParent(nil) end
    wipe(entries)
    if sidebar._headers then for _, h in ipairs(sidebar._headers) do h:Hide(); h:SetParent(nil) end end
    sidebar._headers = {}
end

local function RebuildSidebar()
    ClearSidebar()
    local y = -8
    for _, cat in ipairs(CATEGORY_ORDER) do
        local list = {}
        for _, folder in ipairs(moduleOrder) do
            if modules[folder].category == cat then list[#list + 1] = folder end
        end
        if #list > 0 then
            table.sort(list, function(a, b)
                local ca, cb = modules[a], modules[b]
                if ca.order ~= cb.order then return ca.order < cb.order end
                return L(ca.title or a) < L(cb.title or b)
            end)
            local hdr = Lbl(sidebar, 11, 0.494, 0.447, 0.337)
            hdr:SetPoint("TOPLEFT", 14, y); hdr:SetText(string.upper(L(cat)))
            sidebar._headers[#sidebar._headers + 1] = hdr
            y = y - 20
            for _, folder in ipairs(list) do
                local cfg = modules[folder]
                local e = CreateFrame("Button", nil, sidebar)
                e:SetPoint("TOPLEFT", 0, y); e:SetPoint("TOPRIGHT", 0, y); e:SetHeight(26)
                e.bg  = Tex(e, "BACKGROUND", ROW[1], ROW[2], ROW[3], 1); e.bg:SetAllPoints(); e.bg:Hide()
                e.bar = Tex(e, "ARTWORK", A()); e.bar:SetPoint("TOPLEFT"); e.bar:SetPoint("BOTTOMLEFT"); e.bar:SetWidth(3); e.bar:Hide()
                OUI.RegAccent({ type = "solid", obj = e.bar, a = 1 })
                e.lbl = Lbl(e, 13, DIM[1], DIM[2], DIM[3]); e.lbl:SetPoint("LEFT", 14, 0)
                e.lbl:SetText(L(cfg.title or folder))
                if cfg.disabled then e.lbl:SetTextColor(0.369, 0.337, 0.247) end
                Hover(e)
                e:SetScript("OnClick", function() SelectModule(folder) end)
                entries[folder] = { frame = e, bg = e.bg, bar = e.bar, lbl = e.lbl, title = L(cfg.title or folder) }
                y = y - 26
            end
            y = y - 8
        end
    end
end
OUI._RebuildSidebar = RebuildSidebar

local function ApplySearch(q)
    q = (q or ""):lower()
    for _, e in pairs(entries) do
        e.frame:SetShown(q == "" or e.title:lower():find(q, 1, true) ~= nil)
    end
end

-- ---- content page object (body) ----
local function MakeBody(parent)
    local b = CreateFrame("Frame", nil, parent)
    b._rows = {}
    function b:Reset()
        for _, r in ipairs(self._rows) do r:Hide() end
        wipe(self._rows); self._cursor = 0
        self:SetHeight(1)
    end
    function b:AddRow(row, gap)
        row:SetParent(self); row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, self._cursor or 0)
        row:SetPoint("RIGHT", 0, 0)
        row:Show()
        self._rows[#self._rows + 1] = row
        self._cursor = (self._cursor or 0) - (row:GetHeight() + (gap or 14))
        self:SetHeight(-self._cursor + 8)
        return row
    end
    b._cursor = 0
    return b
end

-- ---- panel shell ----
local function BuildPanel()
    if mainFrame then return end
    local f = CreateFrame("Frame", "OldschoolUIPanel", UIParent)
    f:SetSize(720, 480); f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH"); f:EnableMouse(true); f:SetClampedToScreen(true)
    f:SetMovable(true)
    Tex(f, "BACKGROUND", INK[1], INK[2], INK[3], 0.98):SetAllPoints()
    Border(f, BRD2[1], BRD2[2], BRD2[3], 1)
    table.insert(UISpecialFrames, "OldschoolUIPanel")  -- Escape closes

    -- header
    local hb = CreateFrame("Frame", nil, f); hb:SetPoint("TOPLEFT"); hb:SetPoint("TOPRIGHT"); hb:SetHeight(46)
    Tex(hb, "BACKGROUND", 0.102, 0.086, 0.063, 1):SetAllPoints()
    local sep = Tex(hb, "ARTWORK", BRD[1], BRD[2], BRD[3], 1); sep:SetPoint("BOTTOMLEFT"); sep:SetPoint("BOTTOMRIGHT"); sep:SetHeight(1)
    local med = Tex(hb, "ARTWORK", A()); med:SetSize(24, 24); med:SetPoint("LEFT", 16, 0)
    OUI.RegAccent({ type = "solid", obj = med, a = 1 })
    local mo = Lbl(hb, 15, INK[1], INK[2], INK[3]); mo:SetPoint("CENTER", med, "CENTER"); mo:SetText("O")
    local title = Lbl(hb, 16, TXT[1], TXT[2], TXT[3]); title:SetPoint("LEFT", med, "RIGHT", 10, 0); title:SetText("OldschoolUI")
    local ver = Lbl(hb, 11, 0.494, 0.447, 0.337); ver:SetPoint("LEFT", title, "RIGHT", 6, -1); ver:SetText(OUI.VERSION ~= "@".."project-version".."@" and OUI.VERSION or "dev")
    hb:EnableMouse(true); hb:RegisterForDrag("LeftButton")
    hb:SetScript("OnDragStart", function() f:StartMoving() end)
    hb:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    local close = CreateFrame("Button", nil, hb); close:SetSize(28, 28); close:SetPoint("RIGHT", -10, 0)
    local cx = Lbl(close, 18, DIM[1], DIM[2], DIM[3]); cx:SetPoint("CENTER"); cx:SetText("X")
    Hover(close); close:SetScript("OnClick", function() OUI:Hide() end)

    -- footer
    local fb = CreateFrame("Frame", nil, f); fb:SetPoint("BOTTOMLEFT"); fb:SetPoint("BOTTOMRIGHT"); fb:SetHeight(44)
    Tex(fb, "BACKGROUND", 0.102, 0.086, 0.063, 1):SetAllPoints()
    local fsep = Tex(fb, "ARTWORK", BRD[1], BRD[2], BRD[3], 1); fsep:SetPoint("TOPLEFT"); fsep:SetPoint("TOPRIGHT"); fsep:SetHeight(1)
    local reload = OUI.Widgets.Button(fb, { label = "Reload UI", width = 120, primary = true, onClick = function() ReloadUI() end })
    reload:SetPoint("RIGHT", -14, 0)
    local reset = OUI.Widgets.Button(fb, { label = "Reset Theme", width = 120, onClick = function() OUI.ResetTheme() end })
    reset:SetPoint("RIGHT", reload, "LEFT", -10, 0)

    -- sidebar
    sidebar = CreateFrame("Frame", nil, f); sidebar:SetPoint("TOPLEFT", 0, -46); sidebar:SetPoint("BOTTOMLEFT", 0, 44); sidebar:SetWidth(192)
    Tex(sidebar, "BACKGROUND", 0.086, 0.071, 0.047, 1):SetAllPoints()
    local sbsep = Tex(sidebar, "ARTWORK", BRD[1], BRD[2], BRD[3], 1); sbsep:SetPoint("TOPRIGHT"); sbsep:SetPoint("BOTTOMRIGHT"); sbsep:SetWidth(1)
    sidebar._headers = {}

    -- search box (top of sidebar)
    local sbBox = CreateFrame("Frame", nil, sidebar); sbBox:SetPoint("TOPLEFT", 12, -10); sbBox:SetPoint("TOPRIGHT", -12, -10); sbBox:SetHeight(26)
    Tex(sbBox, "BACKGROUND", ROW[1], ROW[2], ROW[3], 1):SetAllPoints(); Border(sbBox, BRD[1], BRD[2], BRD[3], 1)
    searchBox = CreateFrame("EditBox", nil, sbBox); searchBox:SetPoint("LEFT", 9, 0); searchBox:SetPoint("RIGHT", -8, 0); searchBox:SetHeight(24)
    searchBox:SetFontObject("GameFontHighlightSmall"); searchBox:SetAutoFocus(false); searchBox:SetTextColor(TXT[1], TXT[2], TXT[3])
    searchBox:SetScript("OnTextChanged", function(self) ApplySearch(self:GetText()) end)
    searchBox:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    -- shift the category list below the search box
    local sbBelow = CreateFrame("Frame", nil, sidebar); sbBelow:SetPoint("TOPLEFT", 0, -46); sbBelow:SetPoint("BOTTOMRIGHT", 0, 0)
    sbBelow._headers = {}
    sidebar = sbBelow  -- entries anchor under the search box

    -- content
    content = CreateFrame("Frame", nil, f); content:SetPoint("TOPLEFT", 192, -46); content:SetPoint("BOTTOMRIGHT", 0, 44)
    content.title = Lbl(content, 18, A()); content.title:SetPoint("TOPLEFT", 20, -18)
    OUI.RegAccent({ type = "font", obj = content.title })
    content.desc = Lbl(content, 12, DIM[1], DIM[2], DIM[3]); content.desc:SetPoint("TOPLEFT", 20, -42)
    content.desc:SetPoint("RIGHT", -20, 0); content.desc:SetJustifyH("LEFT")
    local cdiv = Tex(content, "ARTWORK", BRD[1], BRD[2], BRD[3], 1); cdiv:SetPoint("TOPLEFT", 20, -58); cdiv:SetPoint("TOPRIGHT", -20, -58); cdiv:SetHeight(1)
    local scroll = CreateFrame("ScrollFrame", "OldschoolUIContentScroll", content, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 20, -74); scroll:SetPoint("BOTTOMRIGHT", -26, 14)
    content.scroll = scroll
    content.body = MakeBody(scroll)
    content.body:SetPoint("TOPLEFT", 0, 0)
    scroll:SetScrollChild(content.body)
    scroll:HookScript("OnSizeChanged", function(_, w) if w and w > 0 then content.body:SetWidth(w) end end)
    content.body:SetWidth((scroll:GetWidth() or 0) > 0 and scroll:GetWidth() or 460)

    mainFrame = f
    OUI._panelBuilt = true
    RebuildSidebar()
    if moduleOrder[1] then SelectModule(activeFolder or moduleOrder[1]) end
end

-- ---- public open/close ----
function OUI:Show() BuildPanel(); mainFrame:Show() end
function OUI:Hide() if mainFrame then mainFrame:Hide() end end
function OUI:Toggle() if mainFrame and mainFrame:IsShown() then self:Hide() else self:Show() end end
function OUI:IsShown() return mainFrame and mainFrame:IsShown() end
function OUI:SelectPage(folder) BuildPanel(); SelectModule(folder); mainFrame:Show() end

-- ---- minimap button ----
function OUI.CreateMinimapButton()
    if OUI._mmb then return OUI._mmb end
    local b = CreateFrame("Button", "OldschoolUIMinimapButton", Minimap)
    b:SetSize(26, 26); b:SetFrameStrata("MEDIUM"); b:SetFrameLevel(8)
    Tex(b, "BACKGROUND", INK[1], INK[2], INK[3], 1):SetAllPoints()
    OUI._accentBorder(b)
    local o = Lbl(b, 14, A()); o:SetPoint("CENTER"); o:SetText("O")
    OUI.RegAccent({ type = "font", obj = o })
    local function reposition(ang)
        local r = math.rad(ang)
        b:ClearAllPoints()
        b:SetPoint("CENTER", Minimap, "CENTER", math.cos(r) * 80, math.sin(r) * 80)
    end
    reposition((OUI.db and OUI.db.global.minimapAngle) or 210)
    b:RegisterForDrag("LeftButton"); b:SetMovable(true)
    b:SetScript("OnDragStart", function()
        b:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition(); local s = Minimap:GetEffectiveScale()
            cx, cy = cx / s, cy / s
            local ang = math.deg(math.atan2(cy - my, cx - mx))
            if OUI.db then OUI.db.global.minimapAngle = ang end
            reposition(ang)
        end)
    end)
    b:SetScript("OnDragStop", function() b:SetScript("OnUpdate", nil) end)
    b:SetScript("OnClick", function() OUI:Toggle() end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("OldschoolUI", A())
        GameTooltip:AddLine(L("Left-click to open"), DIM[1], DIM[2], DIM[3])
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    OUI._mmb = b
    return b
end

function OUI:_InitOptions()
    OUI.CreateMinimapButton()
end

-- ---- slash ----
SLASH_OLDSCHOOLUI1 = "/oui"
SLASH_OLDSCHOOLUI2 = "/oldschoolui"
SlashCmdList["OLDSCHOOLUI"] = function() OUI:Toggle() end

-- ---------------------------------------------------------------------
-- Built-in General module (global settings) -- makes the panel useful now.
-- ---------------------------------------------------------------------
OUI:RegisterModule("General", {
    category = "Main Modules", order = 0,
    title = "General", description = "Theme, accent colour, language and panel scale.",
    build = function(page)
        page:AddRow(OUI.Widgets.Dropdown(page, {
            label = "Theme",
            values = { OldschoolUI = "OldschoolUI", Classic = "Classic", Horde = "Horde",
                       Alliance = "Alliance", ["Faction (Auto)"] = "Faction (Auto)",
                       Dark = "Dark", ["Class Colored"] = "Class Colored", ["Custom Color"] = "Custom Color" },
            order = OUI.THEME_ORDER,
            get = OUI.GetActiveTheme, set = OUI.SetActiveTheme,
        }))
        page:AddRow(OUI.Widgets.ColorSwatch(page, {
            label = "Accent colour",
            get = function() return OUI.GetAccentColor() end,
            set = function(r, g, b) OUI.SetAccentColor(r, g, b) end,
        }))
        page:AddRow(OUI.Widgets.Slider(page, {
            label = "Panel scale", min = 80, max = 130, step = 1,
            get = function() return ((OUI.db and OUI.db.global.uiScale) or 100) end,
            set = function(v)
                if OUI.db then OUI.db.global.uiScale = v end
                if OldschoolUIPanel then OldschoolUIPanel:SetScale(v / 100) end
            end,
        }))
    end,
})

-- OldschoolUI / Core / Options.lua  (Config-menu redesign)
-- Options panel shell, refined upstream look, fully accent-driven:
--   * wider window, scrollable content + scrollable sidebar
--   * header accent sweep gradient + "O" emblem
--   * spaced small-caps section labels (sentence case, muted -- not all-caps)
--   * per-module "O" glyph enable toggle (grey=off, accent=on); takes effect on
--     reload; an in-UI banner appears whenever a flag differs from load state
--   * footer: [Reset module][Reload UI][Move frames]  /  [CurseForge][Done]
-- Public API preserved: RegisterModule / SelectModule / Show / Hide / Toggle /
-- IsShown / SelectPage / CreateMinimapButton / _InitGameMenuButton / _InitOptions.

local OUI = OldschoolUI
local L   = OUI.L
local P   = OUI._palette
local Tex, Lbl, Border, Hover = OUI._tex, OUI._label, OUI._border, OUI._hover
local INK, ROW, BRD, BRD2, DIM, TXT = P.INK, P.ROW, P.BRD, P.BRD2, P.DIM, P.TXT
local function A() return OUI.ACCENT.r, OUI.ACCENT.g, OUI.ACCENT.b end

-- CurseForge project (id-based redirect; no other socials by design).
local CURSEFORGE_URL = "https://www.curseforge.com/projects/1574573"

-- Category render order (English keys; localized at render).
local CATEGORY_ORDER = { "Main Modules", "Better UI Module", "QoL Functions" }

local modules, moduleOrder = {}, {}

function OUI:RegisterModule(folder, config)
    config = config or {}
    config.folder   = folder
    config.category = config.category or "Main Modules"
    config.order    = config.order or 100
    -- Consistent design language: every module shows a tab bar. Single-page
    -- modules are wrapped into one default tab ("General" -> deDE "Allgemein").
    if not config.tabs and config.build then
        config.tabs = { { title = config.tabTitle or "General", build = config.build } }
    end
    if not modules[folder] then moduleOrder[#moduleOrder + 1] = folder end
    modules[folder] = config
    if OUI._panelBuilt then OUI._RebuildSidebar() end
end

-- ---------------------------------------------------------------------
local mainFrame, sidebar, content, activeFolder, searchBox, reloadBanner
local entries = {}

-- A module is toggleable unless it is the built-in core/General page.
local function IsToggleable(cfg) return cfg and not cfg.core and cfg.folder ~= "General" end

-- ---- reload banner ----
local function RefreshReloadBanner()
    if not reloadBanner then return end
    reloadBanner:SetShown(OUI.AnyModuleNeedsReload and OUI:AnyModuleNeedsReload())
end
OUI._RefreshReloadBanner = RefreshReloadBanner

-- ---- per-entry "O" glyph (enable toggle) colour ----
local function RenderEntryToggle(e)
    if not e.tog then return end
    local on = OUI:IsModuleEnabled(e.folder)
    if on then e.tog._o:SetTextColor(A())
    else e.tog._o:SetTextColor(DIM[1], DIM[2], DIM[3]) end
end

-- ---- module selection (with optional per-module tabs) ----
local activeTab = 1

local function BuildBody(cfg)
    content.body:Reset()
    if cfg.tabs then
        local tab = cfg.tabs[activeTab] or cfg.tabs[1]
        if tab and tab.build then tab.build(content.body) end
    elseif cfg.build then
        cfg.build(content.body)
    end
    if content.scroll then content.scroll:SetVerticalScroll(0) end
end

-- Tab bar: a row of text tabs with an accent underline on the active one.
-- Always shown (single-page modules render one "General" tab) for a consistent
-- design language across every module.
local function RenderTabBar(cfg)
    for _, b in ipairs(content._tabBtns) do b:Hide() end
    if not (cfg.tabs and #cfg.tabs >= 1) then content.tabbar:Hide(); return end
    content.tabbar:Show()
    local x = 0
    for i, tab in ipairs(cfg.tabs) do
        local b = content._tabBtns[i]
        if not b then
            b = CreateFrame("Button", nil, content.tabbar)
            b:SetHeight(26)
            b._t = Lbl(b, 13, DIM[1], DIM[2], DIM[3]); b._t:SetPoint("LEFT", 8, 0)
            b._ul = Tex(b, "ARTWORK", A()); b._ul:SetPoint("BOTTOMLEFT", 8, 0); b._ul:SetPoint("BOTTOMRIGHT", -8, 0); b._ul:SetHeight(2)
            OUI.RegAccent({ type = "solid", obj = b._ul, a = 1 })
            Hover(b)
            content._tabBtns[i] = b
        end
        b._t:SetText(L(tab.title or ("Tab " .. i)))
        local w = (b._t:GetStringWidth() or 40) + 18
        b:SetWidth(w); b:ClearAllPoints(); b:SetPoint("LEFT", x, 0)
        local idx = i
        b:SetScript("OnClick", function() activeTab = idx; RenderTabBar(cfg); BuildBody(cfg) end)
        local on = (i == activeTab)
        if on then
            b._t:SetTextColor(A())
            if OUI.AccentLuminance() < 0.50 then
                b._t:SetShadowColor(0.98, 0.95, 0.85, 0.85); b._t:SetShadowOffset(0.8, -0.8)
            else
                b._t:SetShadowColor(0, 0, 0, 0); b._t:SetShadowOffset(0, 0)
            end
        else
            b._t:SetTextColor(DIM[1], DIM[2], DIM[3]); b._t:SetShadowColor(0, 0, 0, 0)
        end
        b._ul:SetShown(on)
        b:Show()
        x = x + w + 10
    end
end

local function SelectModule(folder)
    local cfg = modules[folder]; if not cfg then return end
    if folder ~= activeFolder then activeTab = 1 end
    activeFolder = folder
    for f, e in pairs(entries) do
        local on = (f == folder)
        e.bar:SetShown(on)
        e.bg:SetShown(on)
        e.lbl:SetTextColor(on and TXT[1] or DIM[1], on and TXT[2] or DIM[2], on and TXT[3] or DIM[3])
    end
    content.title:SetText(L(cfg.title or folder))
    content.desc:SetText(L(cfg.description or ""))
    local hasTabs = cfg.tabs and #cfg.tabs >= 1
    if content.scroll then
        content.scroll:ClearAllPoints()
        content.scroll:SetPoint("BOTTOMRIGHT", -26, 14)
        content.scroll:SetPoint("TOPLEFT", 20, hasTabs and -138 or -108)
    end
    RenderTabBar(cfg)
    BuildBody(cfg)
    RefreshReloadBanner()
end
OUI.SelectModule = function(_, folder) SelectModule(folder) end

-- Rebuild the active module's current tab in place (used by element-picker
-- dropdowns that swap which element's settings are shown below them).
function OUI.RefreshOptionsBody()
    if activeFolder and modules[activeFolder] then BuildBody(modules[activeFolder]) end
end

-- ---- sidebar ----
local function ClearSidebar()
    for _, e in pairs(entries) do e.frame:Hide(); e.frame:SetParent(nil) end
    wipe(entries)
    if sidebar._headers then for _, h in ipairs(sidebar._headers) do h:Hide(); h:SetParent(nil) end end
    sidebar._headers = {}
end

local function RebuildSidebar()
    ClearSidebar()
    local y = -6
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
            local hdr = Lbl(sidebar, 11, A())
            hdr:SetPoint("TOPLEFT", 16, y); hdr:SetText(L(cat))
            OUI.RegAccent({ type = "font", obj = hdr })
            OUI.ApplyAccentGlow(hdr)
            sidebar._headers[#sidebar._headers + 1] = hdr
            y = y - 22
            for _, folder in ipairs(list) do
                local cfg = modules[folder]
                local e = CreateFrame("Button", nil, sidebar)
                e:SetPoint("TOPLEFT", 0, y); e:SetPoint("TOPRIGHT", 0, y); e:SetHeight(28)
                e.folder = folder
                e.bg  = Tex(e, "BACKGROUND", ROW[1], ROW[2], ROW[3], 1); e.bg:SetAllPoints(); e.bg:Hide()
                e.bar = Tex(e, "ARTWORK", A()); e.bar:SetPoint("TOPLEFT"); e.bar:SetPoint("BOTTOMLEFT"); e.bar:SetWidth(3); e.bar:Hide()
                OUI.RegAccent({ type = "solid", obj = e.bar, a = 1 })
                e.lbl = Lbl(e, 13, DIM[1], DIM[2], DIM[3]); e.lbl:SetPoint("LEFT", 16, 0)
                e.lbl:SetText(L(cfg.title or folder))
                if cfg.disabled then e.lbl:SetTextColor(0.369, 0.337, 0.247) end
                Hover(e)
                e:SetScript("OnClick", function() SelectModule(folder) end)

                -- per-module "O" glyph enable toggle (grey=off, accent=on)
                if IsToggleable(cfg) then
                    local tog = CreateFrame("Button", nil, e)
                    tog:SetSize(20, 20); tog:SetPoint("RIGHT", -10, 0)
                    tog._o = Lbl(tog, 14, A()); tog._o:SetPoint("CENTER"); tog._o:SetText("O")
                    Hover(tog)
                    tog:SetScript("OnClick", function()
                        OUI:SetModuleEnabled(folder, not OUI:IsModuleEnabled(folder))
                        RenderEntryToggle(e)
                        RefreshReloadBanner()
                    end)
                    tog:SetScript("OnEnter", function(self)
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        GameTooltip:SetText(L(cfg.title or folder), A())
                        GameTooltip:AddLine(OUI:IsModuleEnabled(folder) and L("Enabled") or L("Disabled"),
                            DIM[1], DIM[2], DIM[3])
                        GameTooltip:AddLine(L("Click to toggle. Takes effect after Reload UI."), DIM[1], DIM[2], DIM[3], true)
                        GameTooltip:Show()
                    end)
                    tog:SetScript("OnLeave", function() GameTooltip:Hide() end)
                    e.tog = tog
                    e.lbl:SetPoint("RIGHT", tog, "LEFT", -6, 0)
                    e.lbl:SetJustifyH("LEFT")
                end

                entries[folder] = { frame = e, bg = e.bg, bar = e.bar, lbl = e.lbl,
                                    tog = e.tog, folder = folder, title = L(cfg.title or folder) }
                RenderEntryToggle(entries[folder])
                y = y - 28
            end
            y = y - 10
        end
    end
    sidebar:SetHeight(-y + 6)
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

-- ---- a simple accent "ghost" icon button (header/footer) ----
local function GlyphButton(parent, glyph, size)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size or 28, size or 28)
    b._lbl = Lbl(b, 16, DIM[1], DIM[2], DIM[3]); b._lbl:SetPoint("CENTER"); b._lbl:SetText(glyph)
    Hover(b)
    return b
end

-- ---- CurseForge copy popup (Blizzard StaticPopup with a copyable edit box) ----
StaticPopupDialogs = StaticPopupDialogs or {}
StaticPopupDialogs["OUI_CURSEFORGE_URL"] = {
    text = "CurseForge",
    button1 = OKAY or "Okay",
    hasEditBox = true, editBoxWidth = 320,
    OnShow = function(self)
        local eb = self.editBox or (self.GetEditBox and self:GetEditBox())
        if eb then eb:SetText(CURSEFORGE_URL); eb:HighlightText(); eb:SetFocus() end
    end,
    EditBoxOnEnterPressed = function(self) self:GetParent():Hide() end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-- ---- Reset the currently selected module (uses its optional reset hook) ----
function OUI:ResetActiveModule()
    local cfg = activeFolder and modules[activeFolder]
    if cfg and cfg.reset then
        self:ShowConfirmPopup({
            title = L("Reset module"),
            message = L("Reset this module's settings to default?"),
            onConfirm = function()
                cfg.reset()
                if mainFrame and mainFrame:IsShown() then SelectModule(activeFolder) end
            end,
        })
    else
        self:ShowInfoPopup({ title = L("Reset module"),
            message = L("This module has no reset available.") })
    end
end

-- ---- panel shell ----
local function BuildPanel()
    if mainFrame then return end
    local f = CreateFrame("Frame", "OldschoolUIPanel", UIParent)
    f:SetSize(920, 680); f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG"); f:EnableMouse(true); f:SetClampedToScreen(true)
    f:SetMovable(true)
    Tex(f, "BACKGROUND", INK[1], INK[2], INK[3], 0.98):SetAllPoints()
    Border(f, BRD2[1], BRD2[2], BRD2[3], 1)
    table.insert(UISpecialFrames, "OldschoolUIPanel")  -- Escape closes

    -- header: smooth left-transparent -> right-gold sweep. Drawn on a white file
    -- texture with SetGradient applied directly (color textures ignore gradients,
    -- which is why the previous attempts washed out); keeps the left side dark so
    -- the logo and title stay legible.
    local hb = CreateFrame("Frame", nil, f); hb:SetPoint("TOPLEFT"); hb:SetPoint("TOPRIGHT"); hb:SetHeight(52)
    Tex(hb, "BACKGROUND", 0.102, 0.086, 0.063, 1):SetAllPoints()
    local sweep = hb:CreateTexture(nil, "BORDER")
    sweep:SetTexture("Interface\\Buttons\\WHITE8x8"); sweep:SetAllPoints()
    local function ApplySweep(r, g, b)
        if sweep.SetGradient and CreateColor then
            sweep:SetGradient("HORIZONTAL", CreateColor(r, g, b, 0), CreateColor(r, g, b, 0.34))
        elseif sweep.SetGradientAlpha then
            sweep:SetGradientAlpha("HORIZONTAL", r, g, b, 0, r, g, b, 0.34)
        end
    end
    ApplySweep(A())
    OUI.RegAccent({ type = "callback", fn = ApplySweep })
    local sep = Tex(hb, "ARTWORK", A()); sep:SetPoint("BOTTOMLEFT"); sep:SetPoint("BOTTOMRIGHT"); sep:SetHeight(1)
    OUI.RegAccent({ type = "solid", obj = sep, a = 1 })

    -- logo #2: filled accent disc with a cut-out "O". The O colour follows the
    -- accent luminance so it stays legible for light and dark accents alike.
    local med = hb:CreateTexture(nil, "ARTWORK")
    med:SetTexture("Interface\\Buttons\\WHITE8x8"); med:SetSize(30, 30); med:SetPoint("LEFT", 18, 0)
    med:SetVertexColor(A())
    local medMask = hb:CreateMaskTexture()
    medMask:SetTexture("Interface\\AddOns\\OldschoolUI\\media\\buttonmasks\\round",
        "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    medMask:SetAllPoints(med); med:AddMaskTexture(medMask)
    OUI.RegAccent({ type = "vertex", obj = med, a = 1 })
    local mo = Lbl(hb, 21, INK[1], INK[2], INK[3]); mo:SetPoint("CENTER", med, "CENTER"); mo:SetText("O")
    OUI.RegAccent({ type = "callback", obj = mo, fn = function(r, g, b)
        if OUI.AccentLuminance(r, g, b) > 0.55 then mo:SetTextColor(0.08, 0.07, 0.05)
        else mo:SetTextColor(0.97, 0.95, 0.88) end
    end })
    if OUI.AccentLuminance() > 0.55 then mo:SetTextColor(0.08, 0.07, 0.05) else mo:SetTextColor(0.97, 0.95, 0.88) end
    local title = Lbl(hb, 17, TXT[1], TXT[2], TXT[3]); title:SetPoint("LEFT", med, "RIGHT", 12, 0); title:SetText("OldschoolUI")
    local ver = Lbl(hb, 11, 0.494, 0.447, 0.337); ver:SetPoint("LEFT", title, "RIGHT", 6, -1)
    ver:SetText(OUI.VERSION ~= "@".."project-version".."@" and OUI.VERSION or "dev")
    hb:EnableMouse(true); hb:RegisterForDrag("LeftButton")
    hb:SetScript("OnDragStart", function() f:StartMoving() end)
    hb:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    local close = GlyphButton(hb, "X", 30); close:SetPoint("RIGHT", -12, 0)
    close:SetScript("OnClick", function() OUI:Hide() end)

    -- footer
    local fb = CreateFrame("Frame", nil, f); fb:SetPoint("BOTTOMLEFT"); fb:SetPoint("BOTTOMRIGHT"); fb:SetHeight(46)
    Tex(fb, "BACKGROUND", 0.102, 0.086, 0.063, 1):SetAllPoints()
    local fsep = Tex(fb, "ARTWORK", BRD[1], BRD[2], BRD[3], 1); fsep:SetPoint("TOPLEFT"); fsep:SetPoint("TOPRIGHT"); fsep:SetHeight(1)

    -- left cluster
    local resetMod = OUI.Widgets.Button(fb, { label = "Reset module", width = 158, height = 32,
        onClick = function() OUI:ResetActiveModule() end })
    resetMod:SetPoint("LEFT", 14, 0)
    local reload = OUI.Widgets.Button(fb, { label = "Reload UI", width = 124, height = 32,
        onClick = function() ReloadUI() end })
    reload:SetPoint("LEFT", resetMod, "RIGHT", 10, 0)
    local move = OUI.Widgets.Button(fb, { label = "Move Frames", width = 164, height = 32, onClick = function()
        OUI._reopenAfterLock = activeFolder or true
        OUI:Hide(); OUI:ToggleUnlock(true)
    end })
    move:SetPoint("LEFT", reload, "RIGHT", 10, 0)

    -- right cluster
    local done = OUI.Widgets.Button(fb, { label = "Done", width = 110, height = 32, primary = true,
        onClick = function() OUI:Hide() end })
    done:SetPoint("RIGHT", -14, 0)
    local cf = OUI.Widgets.Button(fb, { label = "CurseForge", width = 124, height = 32,
        tooltip = "Open the project page (copy link).",
        onClick = function() StaticPopup_Show("OUI_CURSEFORGE_URL") end })
    cf:SetPoint("RIGHT", done, "LEFT", -10, 0)

    -- sidebar
    sidebar = nil  -- (re)assigned to the scroll child below
    local sbCol = CreateFrame("Frame", nil, f)
    sbCol:SetPoint("TOPLEFT", 0, -52); sbCol:SetPoint("BOTTOMLEFT", 0, 46); sbCol:SetWidth(214)
    Tex(sbCol, "BACKGROUND", 0.086, 0.071, 0.047, 1):SetAllPoints()
    local sbsep = Tex(sbCol, "ARTWORK", BRD[1], BRD[2], BRD[3], 1)
    sbsep:SetPoint("TOPRIGHT"); sbsep:SetPoint("BOTTOMRIGHT"); sbsep:SetWidth(1)

    -- sidebar top: Edit Mode + Global Settings (stacked full-width to fit long
    -- localized labels) + search
    local editBtn = OUI.Widgets.Button(sbCol, { label = "Edit Mode", width = 190, height = 24,
        onClick = function() OUI._reopenAfterLock = activeFolder or true; OUI:Hide(); OUI:ToggleUnlock(true) end })
    editBtn:SetPoint("TOPLEFT", 12, -12)
    local globBtn = OUI.Widgets.Button(sbCol, { label = "Global Settings", width = 190, height = 24, primary = true,
        onClick = function() SelectModule("General") end })
    globBtn:SetPoint("TOPLEFT", editBtn, "BOTTOMLEFT", 0, -8)

    local sbBox = CreateFrame("Frame", nil, sbCol)
    sbBox:SetPoint("TOPLEFT", globBtn, "BOTTOMLEFT", 0, -10); sbBox:SetPoint("TOPRIGHT", -12, 0); sbBox:SetHeight(26)
    Tex(sbBox, "BACKGROUND", ROW[1], ROW[2], ROW[3], 1):SetAllPoints(); Border(sbBox, BRD[1], BRD[2], BRD[3], 1)
    searchBox = CreateFrame("EditBox", nil, sbBox); searchBox:SetPoint("LEFT", 9, 0); searchBox:SetPoint("RIGHT", -8, 0); searchBox:SetHeight(24)
    searchBox:SetFontObject("GameFontHighlightSmall"); searchBox:SetAutoFocus(false); searchBox:SetTextColor(TXT[1], TXT[2], TXT[3])
    local sPlace = Lbl(sbBox, 12, DIM[1], DIM[2], DIM[3]); sPlace:SetPoint("LEFT", 9, 0); sPlace:SetText(L("Search..."))
    local function UpdatePlaceholder() sPlace:SetShown((searchBox:GetText() or "") == "") end
    searchBox:SetScript("OnTextChanged", function(self) ApplySearch(self:GetText()); UpdatePlaceholder() end)
    searchBox:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)

    -- sidebar scrollable list (module entries anchor here)
    local sbScroll = CreateFrame("ScrollFrame", "OldschoolUISidebarScroll", sbCol, "UIPanelScrollFrameTemplate")
    sbScroll:SetPoint("TOPLEFT", 0, -114); sbScroll:SetPoint("BOTTOMRIGHT", -22, 6)
    local sbChild = CreateFrame("Frame", nil, sbScroll)
    sbChild:SetSize(192, 10); sbChild._headers = {}
    sbScroll:SetScrollChild(sbChild)
    sbScroll:HookScript("OnSizeChanged", function(_, w) if w and w > 0 then sbChild:SetWidth(w) end end)
    sidebar = sbChild

    -- content
    content = CreateFrame("Frame", nil, f); content:SetPoint("TOPLEFT", 214, -52); content:SetPoint("BOTTOMRIGHT", 0, 46)

    -- reload-required banner (top of content)
    reloadBanner = CreateFrame("Frame", nil, content)
    reloadBanner:SetPoint("TOPLEFT", 20, -14); reloadBanner:SetPoint("TOPRIGHT", -20, -14); reloadBanner:SetHeight(26)
    local rbBg = Tex(reloadBanner, "BACKGROUND", A()); rbBg:SetAllPoints(); rbBg:SetAlpha(0.16)
    OUI.RegAccent({ type = "solid", obj = rbBg, a = 0.16 })
    local rbBorder = Border(reloadBanner, A())
    OUI.RegAccent({ type = "callback", fn = function(r, g, b)
        if rbBorder and rbBorder.SetColor then rbBorder:SetColor(r, g, b, 1) end
    end })
    local rbBtn = OUI.Widgets.Button(reloadBanner, { label = "Reload UI", width = 96, height = 20, primary = true,
        onClick = function() ReloadUI() end })
    rbBtn:SetPoint("RIGHT", -6, 0)
    local rbTxt = Lbl(reloadBanner, 12, TXT[1], TXT[2], TXT[3]); rbTxt:SetPoint("LEFT", 10, 0)
    rbTxt:SetText(L("Reload required to apply"))
    reloadBanner:Hide()

    content.title = Lbl(content, 19, A()); content.title:SetPoint("TOPLEFT", 20, -52)
    OUI.RegAccent({ type = "font", obj = content.title })
    OUI.ApplyAccentGlow(content.title)
    content.desc = Lbl(content, 12, DIM[1], DIM[2], DIM[3]); content.desc:SetPoint("TOPLEFT", 20, -78)
    content.desc:SetPoint("RIGHT", -20, 0); content.desc:SetJustifyH("LEFT")
    local cdiv = Tex(content, "ARTWORK", BRD[1], BRD[2], BRD[3], 1); cdiv:SetPoint("TOPLEFT", 20, -96); cdiv:SetPoint("TOPRIGHT", -20, -96); cdiv:SetHeight(1)
    -- per-module tab bar (shown only for modules that declare tabs)
    content.tabbar = CreateFrame("Frame", nil, content)
    content.tabbar:SetPoint("TOPLEFT", 20, -104); content.tabbar:SetPoint("TOPRIGHT", -20, -104); content.tabbar:SetHeight(28)
    content._tabBtns = {}
    content.tabbar:Hide()
    local scroll = CreateFrame("ScrollFrame", "OldschoolUIContentScroll", content, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 20, -108); scroll:SetPoint("BOTTOMRIGHT", -26, 14)
    content.scroll = scroll
    content.body = MakeBody(scroll)
    content.body:SetPoint("TOPLEFT", 0, 0)
    scroll:SetScrollChild(content.body)
    scroll:HookScript("OnSizeChanged", function(_, w) if w and w > 0 then content.body:SetWidth(w) end end)
    content.body:SetWidth((scroll:GetWidth() or 0) > 0 and scroll:GetWidth() or 620)

    mainFrame = f
    OUI._panelBuilt = true
    RebuildSidebar()
    if moduleOrder[1] then SelectModule(activeFolder or moduleOrder[1]) end
end

-- ---- public open/close ----
function OUI:Show() BuildPanel(); RefreshReloadBanner(); mainFrame:Show() end
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

-- ESC / GameMenu button.
local gmBtn
function OUI._InitGameMenuButton()
    if gmBtn or not GameMenuFrame then return end
    local ar, ag, ab = A()
    gmBtn = CreateFrame("Button", "OUIGameMenuButton", UIParent)
    gmBtn:SetSize(126, 26)
    local bg = Tex(gmBtn, "BACKGROUND", 0.06, 0.06, 0.07); bg:SetAllPoints(); bg:SetAlpha(0.97)
    OUI._border(gmBtn, ar, ag, ab, 1)
    gmBtn._lbl = Lbl(gmBtn, 13, ar, ag, ab); gmBtn._lbl:SetPoint("CENTER")
    gmBtn._lbl:SetText("OldschoolUI")
    gmBtn:SetScript("OnEnter", function() gmBtn._lbl:SetTextColor(1, 1, 1) end)
    gmBtn:SetScript("OnLeave", function() gmBtn._lbl:SetTextColor(A()) end)
    gmBtn:SetScript("OnClick", function()
        if HideUIPanel then HideUIPanel(GameMenuFrame)
        elseif GameMenuFrame.Hide then GameMenuFrame:Hide() end
        OUI:Toggle()
    end)
    -- Strata/level are set ONCE here, at creation (outside any secure execution).
    -- They must NOT be set inside the GameMenu's OnShow: changing an insecure
    -- frame's strata/level re-sorts UIParent's DIALOG children, and GameMenuFrame is
    -- a DIALOG sibling -- that re-sort taints the menu mid-show and makes its
    -- Logout / Exit callbacks forbidden (ADDON_ACTION_FORBIDDEN: callback()).
    gmBtn:SetFrameStrata("DIALOG")
    gmBtn:SetFrameLevel(200)
    gmBtn:Hide()
    GameMenuFrame:HookScript("OnShow", function()
        -- Do NOTHING to any frame synchronously inside the secure ToggleGameMenu
        -- execution -- only schedule. Showing/positioning gmBtn one frame later runs
        -- in a normal, unrestricted context and cannot taint the menu. (Anchor to
        -- UIParent, never to GameMenuFrame, for the same reason.) The deferred read
        -- of GetHeight() also lands after the menu has laid out its buttons, so the
        -- button is placed correctly on the very first ESC instead of the second.
        C_Timer.After(0, function()
            if not (gmBtn and GameMenuFrame:IsShown()) then return end
            gmBtn:ClearAllPoints()
            local h = (GameMenuFrame.GetHeight and GameMenuFrame:GetHeight()) or 220
            gmBtn:SetPoint("CENTER", UIParent, "CENTER", 0, -(h / 2) - 22)
            gmBtn:Show()
        end)
    end)
    GameMenuFrame:HookScript("OnHide", function() if gmBtn then gmBtn:Hide() end end)
end

function OUI:_InitOptions()
    OUI.CreateMinimapButton()
    -- Taint log confirms the gmBtn is NOT involved in the GameMenu/Logout taint
    -- (that is a CloseSpecialWindows cascade from other addons). Re-enabled.
    OUI._InitGameMenuButton()
end

-- ---- slash ----
SLASH_OLDSCHOOLUI1 = "/oui"
SLASH_OLDSCHOOLUI2 = "/oldschoolui"
SlashCmdList["OLDSCHOOLUI"] = function() OUI:Toggle() end

-- ---------------------------------------------------------------------
-- Built-in General module (global settings).
-- ---------------------------------------------------------------------
OUI:RegisterModule("General", {
    category = "Main Modules", order = 0, core = true,
    title = "General", description = "Theme, accent colour, language and panel scale.",
    reset = function() if OUI.ResetTheme then OUI.ResetTheme() end end,
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
        page:AddRow(OUI.Widgets.Dropdown(page, {
            label = "Bar texture (all modules)",
            tooltip = "Default status-bar texture across the whole UI. Each module can override it for all of its bars, or per bar type.",
            values = OUI.BAR_TEXTURE_NAMES, order = OUI.BAR_TEXTURE_ORDER,
            get = function() return OUI.GetGlobalBarTextureKey() end,
            set = function(v) OUI.SetGlobalBarTexture(v) end,
        }))
        page:AddRow(OUI.Widgets.ColorSwatch(page, {
            label = "Border colour (all modules)", hasAlpha = true,
            tooltip = "Default bar border colour across the whole UI. Modules can override per addon or per bar type.",
            get = function() local c = OUI.GetGlobalBorderColor(); return c[1], c[2], c[3], c[4] end,
            set = function(r, g, b, a) OUI.SetGlobalBorderColor(r, g, b, a) end,
        }))
        page:AddRow(OUI.Widgets.Slider(page, {
            label = "Border size (all modules)", min = 0, max = 4, step = 1,
            get = function() return OUI.GetGlobalBorderSize() end,
            set = function(v) OUI.SetGlobalBorderSize(v) end,
        }))
        page:AddRow(OUI.Widgets.Slider(page, {
            label = "Class colour intensity (all modules)", min = 50, max = 150, step = 1,
            tooltip = "Brightness multiplier applied to all class colours. Modules can override locally.",
            get = function() return math.floor((OUI.GetColorIntensity() or 1) * 100 + 0.5) end,
            set = function(v) OUI.SetColorIntensity(v / 100) end,
        }))
        for _, tok in ipairs(OUI.CLASS_TOKENS) do
            local cname = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[tok]) or tok
            local prefix = (OUI.L and OUI.L("Class")) or "Class"
            page:AddRow(OUI.Widgets.ColorSwatch(page, {
                label = prefix .. ": " .. cname,
                tooltip = "Override the colour for this class across the whole UI. Right-click the swatch is not reset; use the default Blizzard colour by clearing in a future reset.",
                get = function()
                    local c = OUI.db and OUI.db.global.classColors[tok]
                    if c then return c.r or c[1], c.g or c[2], c.b or c[3] end
                    local rc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[tok]
                    if rc then return rc.r, rc.g, rc.b end
                    return 1, 1, 1
                end,
                set = function(r, g, b) OUI.SetClassColor(tok, r, g, b) end,
            }))
        end
    end,
})

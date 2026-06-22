-- OldschoolUI / Core / Widgets.lua  (Pass 2, part 1)
-- Angular widget factory: borders + toggle / checkbox / slider / button + popups.
-- Aesthetic: 0 corner radius, hard 1px edges, gold accent on ink, soft hover
-- (background lighten), active = accent fill + dark text. Cut-corner reserved
-- for cards/popups only (texture asset, applied later).
-- Labels localize via OUI.L; accent-coloured parts register via OUI.RegAccent.

local OUI = OldschoolUI
local L   = OUI.L
local RegAccent = OUI.RegAccent

-- ---- palette (panel-local; accent is live via OUI.ACCENT) ----
local INK  = {0.078, 0.067, 0.043}   -- #14110B panel
local ROW  = {0.122, 0.102, 0.071}   -- #1F1A12 control bg
local BRD  = {0.227, 0.192, 0.125}   -- #3A3120 line
local BRD2 = {0.353, 0.302, 0.188}   -- #5A4D30 emphasis line
local DIM  = {0.604, 0.561, 0.467}   -- #9A8F77 muted text
local TXT  = {0.925, 0.886, 0.800}   -- #ECE2CC text
local DANGER = {0.80, 0.27, 0.27}

local function A() return OUI.ACCENT.r, OUI.ACCENT.g, OUI.ACCENT.b end
local function Font() return OUI._localeFont or STANDARD_TEXT_FONT end

-- ---- low-level helpers ----
local WHITE8 = "Interface\\Buttons\\WHITE8x8"
local MASKDIR = "Interface\\AddOns\\OldschoolUI\\media\\buttonmasks\\"

-- A white texture clipped to a rounded mask shape; vertex-colour to tint.
-- (Masks need a real file texture -- SetColorTexture textures ignore them, which
--  is why the earlier pill attempt rendered flat.)
local function MaskedTex(parent, layer, maskName)
    local t = parent:CreateTexture(nil, layer or "ARTWORK")
    t:SetTexture(WHITE8)
    local m = parent:CreateMaskTexture()
    m:SetTexture(MASKDIR .. maskName, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    t:AddMaskTexture(m)
    return t, m
end

local function SolidTex(parent, layer, r, g, b, a)
    local t = parent:CreateTexture(nil, layer or "ARTWORK")
    t:SetColorTexture(r, g, b, a or 1)
    return t
end

local function Label(parent, size, r, g, b)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(Font(), size or 13, "")
    fs:SetTextColor(r or TXT[1], g or TXT[2], b or TXT[3])
    return fs
end

-- Crisp 1px pixel border (4 edges). Returns a table of the 4 textures so the
-- colour can be reset later; registers as an accent callback when accent=true.
local function PixelBorder(frame, r, g, b, a, accent)
    local th = 1
    local e = {}
    e.top    = SolidTex(frame, "BORDER", r, g, b, a)
    e.bottom = SolidTex(frame, "BORDER", r, g, b, a)
    e.left   = SolidTex(frame, "BORDER", r, g, b, a)
    e.right  = SolidTex(frame, "BORDER", r, g, b, a)
    e.top:SetPoint("TOPLEFT");     e.top:SetPoint("TOPRIGHT");     e.top:SetHeight(th)
    e.bottom:SetPoint("BOTTOMLEFT"); e.bottom:SetPoint("BOTTOMRIGHT"); e.bottom:SetHeight(th)
    e.left:SetPoint("TOPLEFT");    e.left:SetPoint("BOTTOMLEFT");   e.left:SetWidth(th)
    e.right:SetPoint("TOPRIGHT");   e.right:SetPoint("BOTTOMRIGHT"); e.right:SetWidth(th)
    function e:SetColor(nr, ng, nb, na)
        for _, k in ipairs({"top","bottom","left","right"}) do
            self[k]:SetColorTexture(nr, ng, nb, na or 1)
        end
    end
    function e:SetThickness(n)
        n = n or 1
        if n <= 0 then
            for _, k in ipairs({"top","bottom","left","right"}) do self[k]:Hide() end
            return
        end
        self.top:SetHeight(n); self.bottom:SetHeight(n)
        self.left:SetWidth(n); self.right:SetWidth(n)
        for _, k in ipairs({"top","bottom","left","right"}) do self[k]:Show() end
    end
    if accent then
        RegAccent({ type = "callback", fn = function(nr, ng, nb) e:SetColor(nr, ng, nb, a) end })
    end
    return e
end

-- Convenience: a 1px border in the live accent colour that follows theme changes.
local function AccentBorder(frame)
    local r, g, b = A()
    return PixelBorder(frame, r, g, b, 1, true)
end

-- Soft hover: a faint overlay that fades in on enter (background lighten).
local function AttachHover(frame, target)
    local hl = SolidTex(target or frame, "HIGHLIGHT", TXT[1], TXT[2], TXT[3], 0.06)
    hl:SetAllPoints(target or frame)
    return hl
end

local function Tooltip(frame, text)
    if not text then return end
    frame:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L(text), TXT[1], TXT[2], TXT[3], 1, true)
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- =====================================================================
--  Border system (5 built-ins)
-- =====================================================================
OUI._builtinBorders = {
    { key = "solid",  name = "Solid"           },
    { key = "glow",   name = "Glow",            edge = "media\\borders\\oui-glow"   },
    { key = "shadow", name = "Shadow",          edge = "media\\borders\\oui-glow"   },
    { key = "blizz",  name = "Blizzard",        edge = "media\\borders\\oui-blizz"  },
    { key = "dialog", name = "Blizzard Dialog", edge = "Interface\\DialogFrame\\UI-DialogBox-Border" },
}

function OUI.GetBorderTextureList()
    local out = {}
    for _, e in ipairs(OUI._builtinBorders) do out[#out+1] = { key = e.key, name = e.name } end
    return out  -- LSM enumeration intentionally omitted (lean)
end

local BASE = "Interface\\AddOns\\OldschoolUI\\"
local function ResolveBorderEdge(key)
    for _, e in ipairs(OUI._builtinBorders) do
        if e.key == key and e.edge then
            return (e.edge:find("Interface")) and e.edge or (BASE .. e.edge)
        end
    end
    return nil
end

-- Apply a border style to a frame. "solid"/nil -> pixel border; others -> backdrop edge.
function OUI.ApplyBorderStyle(frame, size, r, g, b, a, key)
    r, g, b, a = r or OUI.ACCENT.r, g or OUI.ACCENT.g, b or OUI.ACCENT.b, a or 1
    if not key or key == "" or key == "solid" then
        if frame._ouiBorder then frame._ouiBorder:SetColor(r, g, b, a)
        else frame._ouiBorder = PixelBorder(frame, r, g, b, a) end
        return frame._ouiBorder
    end
    local edge = ResolveBorderEdge(key)
    if not edge then return OUI.ApplyBorderStyle(frame, size, r, g, b, a, "solid") end
    if not frame.SetBackdrop then return end  -- needs BackdropTemplate
    frame:SetBackdrop({ edgeFile = edge, edgeSize = size or 12 })
    frame:SetBackdropBorderColor(r, g, b, a)
end

-- =====================================================================
--  Toggle  (true capsule pill: round end-caps + center rect, accent on)
-- =====================================================================
local function MakeToggle(parent, opts)
    opts = opts or {}
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(opts.width or 280, 24)

    local lbl = Label(row, 13); lbl:SetPoint("LEFT")
    lbl:SetText(L(opts.label or ""))

    local H = 22
    local btn = CreateFrame("Button", nil, row)
    btn:SetSize(46, H); btn:SetPoint("RIGHT")

    -- a capsule = two round caps (diameter = height -> fully semicircular ends)
    -- plus a center rectangle between the cap centres. Returns its 3 textures.
    local function capPart(layer, point)
        local t, m = MaskedTex(btn, layer, "round")
        t:SetSize(H, H); t:SetPoint(point); m:SetAllPoints(t)
        return t
    end
    local function capsule(layer)
        local lc = capPart(layer, "LEFT")
        local rc = capPart(layer, "RIGHT")
        local mid = btn:CreateTexture(nil, layer); mid:SetTexture(WHITE8)
        mid:SetPoint("TOPLEFT", H / 2, 0); mid:SetPoint("BOTTOMRIGHT", -H / 2, 0)
        return { lc, rc, mid }
    end

    local track = capsule("BACKGROUND")
    for _, t in ipairs(track) do t:SetVertexColor(0.24, 0.21, 0.15, 1) end
    local fill = capsule("BORDER")
    local function SetFill(show)
        local r, g, b = A()
        for _, t in ipairs(fill) do t:SetVertexColor(r, g, b, 1); t:SetShown(show) end
    end
    SetFill(false)

    -- round knob
    local knob, kMask = MaskedTex(btn, "OVERLAY", "round")
    knob:SetSize(H - 4, H - 4); kMask:SetSize(H - 4, H - 4)

    AttachHover(btn)
    Tooltip(btn, opts.tooltip)

    local function Render()
        local on = opts.get and opts.get() or false
        knob:ClearAllPoints(); kMask:ClearAllPoints()
        if on then
            knob:SetPoint("RIGHT", -2, 0)
            -- contrast against the accent fill: dark knob on light accents,
            -- cream knob on dark accents (keeps the switch readable for any theme)
            local r, g, b = A()
            local lum = 0.299 * r + 0.587 * g + 0.114 * b
            if lum > 0.62 then knob:SetVertexColor(0.10, 0.09, 0.07, 1)
            else knob:SetVertexColor(0.97, 0.95, 0.88, 1) end
            SetFill(true)
        else
            knob:SetPoint("LEFT", 2, 0)
            knob:SetVertexColor(0.62, 0.58, 0.49, 1)
            SetFill(false)
        end
        kMask:SetPoint("CENTER", knob, "CENTER")
    end
    btn:SetScript("OnClick", function()
        if opts.set then opts.set(not (opts.get and opts.get())) end
        Render()
    end)
    RegAccent({ type = "callback", fn = function() Render() end })
    Render()
    row.Render = Render
    return row
end

-- =====================================================================
--  Checkbox  (square box, accent check)
-- =====================================================================
local function MakeCheckbox(parent, opts)
    opts = opts or {}
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(opts.width or 280, 22)

    local box = CreateFrame("Button", nil, row)
    box:SetSize(18, 18); box:SetPoint("LEFT")
    box:SetNormalTexture(SolidTex(box, "BACKGROUND", ROW[1], ROW[2], ROW[3], 1))
    local brd = AccentBorder(box)
    local chk = box:CreateTexture(nil, "OVERLAY")
    chk:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    chk:SetPoint("CENTER"); chk:SetSize(18, 18)
    chk:SetVertexColor(A())
    RegAccent({ type = "vertex", obj = chk })
    AttachHover(box)
    Tooltip(box, opts.tooltip)

    local lbl = Label(row, 13); lbl:SetPoint("LEFT", box, "RIGHT", 8, 0)
    lbl:SetText(L(opts.label or ""))

    local function Render() chk:SetShown(opts.get and opts.get() or false) end
    box:SetScript("OnClick", function()
        if opts.set then opts.set(not (opts.get and opts.get())) end
        Render()
    end)
    Render()
    row.Render = Render
    return row
end

-- =====================================================================
--  Slider  (thin track, square thumb, value readout)
-- =====================================================================
local function MakeSlider(parent, opts)
    opts = opts or {}
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(opts.width or 280, 40)

    local lbl = Label(row, 13); lbl:SetPoint("TOPLEFT")
    lbl:SetText(L(opts.label or ""))
    local vbox = CreateFrame("Frame", nil, row)
    vbox:SetSize(46, 18); vbox:SetPoint("TOPRIGHT")
    SolidTex(vbox, "BACKGROUND", ROW[1], ROW[2], ROW[3], 1):SetAllPoints()
    local vbrd = PixelBorder(vbox, A())
    RegAccent({ type = "callback", fn = function(r, g, b) vbrd:SetColor(r, g, b, 1) end })
    local val = Label(vbox, 12, A()); val:SetPoint("CENTER")
    RegAccent({ type = "font", obj = val })

    local sl = CreateFrame("Slider", nil, row)
    sl:SetPoint("BOTTOMLEFT"); sl:SetPoint("BOTTOMRIGHT"); sl:SetHeight(14)
    sl:SetOrientation("HORIZONTAL")
    sl:SetMinMaxValues(opts.min or 0, opts.max or 100)
    sl:SetValueStep(opts.step or 1); sl:SetObeyStepOnDrag(true)

    local track = SolidTex(sl, "BACKGROUND", BRD[1], BRD[2], BRD[3], 1)
    track:SetPoint("LEFT"); track:SetPoint("RIGHT"); track:SetHeight(2)
    local fill = SolidTex(sl, "ARTWORK", A())
    fill:SetPoint("LEFT"); fill:SetHeight(2)

    local thumb = sl:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture(WHITE8); thumb:SetVertexColor(A()); thumb:SetSize(14, 14)
    local thMask = sl:CreateMaskTexture()
    thMask:SetTexture(MASKDIR .. "round", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    thMask:SetAllPoints(thumb); thumb:AddMaskTexture(thMask)
    sl:SetThumbTexture(thumb)
    RegAccent({ type = "callback", fn = function(r, g, b)
        fill:SetColorTexture(r, g, b, 1); thumb:SetVertexColor(r, g, b, 1)
    end })
    AttachHover(sl)
    Tooltip(sl, opts.tooltip)

    local function UpdateFill(v)
        local lo, hi = opts.min or 0, opts.max or 100
        local pct = (hi > lo) and ((v - lo) / (hi - lo)) or 0
        fill:SetWidth(math.max(1, sl:GetWidth() * pct))
        val:SetText(tostring(math.floor(v + 0.5)))
    end
    sl:SetScript("OnValueChanged", function(self, v)
        UpdateFill(v); if opts.set then opts.set(v) end
    end)
    sl:SetValue(opts.get and opts.get() or (opts.min or 0))
    UpdateFill(sl:GetValue())
    row.slider = sl
    return row
end

-- =====================================================================
--  Button  (outline or accent-fill; soft hover)
-- =====================================================================
local function MakeButton(parent, opts)
    opts = opts or {}
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(opts.width or 110, opts.height or 30)
    local bg  = SolidTex(btn, "BACKGROUND", ROW[1], ROW[2], ROW[3], opts.primary and 0 or 1)
    bg:SetAllPoints()
    local lbl = Label(btn, 13); lbl:SetPoint("CENTER"); lbl:SetText(L(opts.label or ""))
    btn._lbl = lbl

    if opts.primary then
        local fill = SolidTex(btn, "BORDER", A()); fill:SetAllPoints()
        RegAccent({ type = "solid", obj = fill, a = 1 })
        lbl:SetTextColor(INK[1], INK[2], INK[3])
    else
        AccentBorder(btn)
        lbl:SetTextColor(A())
        RegAccent({ type = "font", obj = lbl })
    end
    AttachHover(btn)
    Tooltip(btn, opts.tooltip)
    btn:SetScript("OnClick", function() if opts.onClick then opts.onClick() end end)
    return btn
end

-- =====================================================================
--  Popups  (reusable modal; sharp ink panel, accent title underline)
-- =====================================================================
local _popup
local function EnsurePopup()
    if _popup then return _popup end
    local p = CreateFrame("Frame", "OldschoolUIPopup", UIParent)
    p:SetSize(320, 160)
    p:SetPoint("CENTER")
    p:SetFrameStrata("FULLSCREEN_DIALOG")
    p:EnableMouse(true); p:Hide()
    SolidTex(p, "BACKGROUND", INK[1], INK[2], INK[3], 0.97):SetAllPoints()
    PixelBorder(p, BRD2[1], BRD2[2], BRD2[3], 1)

    p.title = Label(p, 14, A()); p.title:SetPoint("TOPLEFT", 14, -12)
    RegAccent({ type = "font", obj = p.title })
    local ul = SolidTex(p, "ARTWORK", A())
    ul:SetPoint("TOPLEFT", 14, -30); ul:SetPoint("TOPRIGHT", -14, -30); ul:SetHeight(1)
    RegAccent({ type = "solid", obj = ul, a = 1 })

    p.msg = Label(p, 12, DIM[1], DIM[2], DIM[3])
    p.msg:SetPoint("TOPLEFT", 14, -42); p.msg:SetPoint("TOPRIGHT", -14, -42)
    p.msg:SetJustifyH("LEFT"); p.msg:SetWordWrap(true)

    p.cancel = MakeButton(p, { label = "Cancel", width = 130 })
    p.cancel:SetPoint("BOTTOMLEFT", 14, 14)
    p.confirm = MakeButton(p, { label = "Confirm", width = 130, primary = true })
    p.confirm:SetPoint("BOTTOMRIGHT", -14, 14)
    _popup = p
    return p
end

function OUI:ShowConfirmPopup(opts)
    opts = opts or {}
    local p = EnsurePopup()
    p.title:SetText(L(opts.title or "Confirm"))
    p.msg:SetText(L(opts.message or "Are you sure?"))
    p.cancel._lbl:SetText(L(opts.cancelText or "Cancel"))
    p.confirm._lbl:SetText(L(opts.confirmText or "Confirm"))
    p.cancel:Show()
    p.cancel:SetScript("OnClick", function() p:Hide(); if opts.onCancel then opts.onCancel() end end)
    p.confirm:SetScript("OnClick", function() p:Hide(); if opts.onConfirm then opts.onConfirm() end end)
    p:Show()
    return p
end

function OUI:ShowInfoPopup(opts)
    opts = opts or {}
    local p = EnsurePopup()
    p.title:SetText(L(opts.title or "Information"))
    p.msg:SetText(L(opts.message or ""))
    p.confirm._lbl:SetText(L(opts.confirmText or "OK"))
    p.cancel:Hide()
    p.confirm:SetScript("OnClick", function() p:Hide(); if opts.onConfirm then opts.onConfirm() end end)
    p:Show()
    return p
end

-- ---- public factory table ----
OUI.Widgets = OUI.Widgets or {}
OUI.Widgets.Toggle   = MakeToggle
OUI.Widgets.Checkbox = MakeCheckbox
OUI.Widgets.Slider   = MakeSlider
OUI.Widgets.Button   = MakeButton

-- =====================================================================
--  Pass 2 part 2: Dropdown, Segmented, ColorSwatch, ShowContextMenu
-- =====================================================================

-- ---- Self-built context menu (sharp panel, soft hover, submenu flyout) ----
local MENU_W   = 168
local ITEM_H   = 24
local menuLevels = {}
local closer

local function HideMenusFrom(level)
    for i = #menuLevels, level, -1 do
        if menuLevels[i] then menuLevels[i]:Hide() end
    end
    if level <= 1 and closer then closer:Hide() end
end

local function EnsureCloser()
    if closer then return closer end
    closer = CreateFrame("Button", nil, UIParent)
    closer:SetFrameStrata("FULLSCREEN")
    closer:SetAllPoints(UIParent)
    closer:RegisterForClicks("AnyUp")
    closer:SetScript("OnClick", function() HideMenusFrom(1) end)
    closer:Hide()
    return closer
end

local function GetLevel(level)
    if menuLevels[level] then return menuLevels[level] end
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(30 + level * 10)
    f:EnableMouse(true)
    SolidTex(f, "BACKGROUND", INK[1], INK[2], INK[3], 0.98):SetAllPoints()
    PixelBorder(f, BRD2[1], BRD2[2], BRD2[3], 1)
    f._pool = {}
    menuLevels[level] = f
    return f
end

local function AcquireItem(f, idx)
    if f._pool[idx] then return f._pool[idx] end
    local b = CreateFrame("Button", nil, f)
    b:RegisterForClicks("AnyUp")
    b._hl = SolidTex(b, "HIGHLIGHT", TXT[1], TXT[2], TXT[3], 0.08); b._hl:SetAllPoints()
    b._line = SolidTex(b, "ARTWORK", BRD[1], BRD[2], BRD[3], 1)
    b._line:SetPoint("LEFT", 8, 0); b._line:SetPoint("RIGHT", -8, 0); b._line:SetHeight(1)
    b._lbl = Label(b, 12); b._lbl:SetPoint("LEFT", 10, 0)
    b._check = b:CreateTexture(nil, "OVERLAY"); b._check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    b._check:SetSize(14, 14); b._check:SetPoint("RIGHT", -8, 0); b._check:SetVertexColor(A())
    b._arrow = b:CreateTexture(nil, "OVERLAY"); b._arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    b._arrow:SetSize(16, 16); b._arrow:SetPoint("RIGHT", -4, 0); b._arrow:SetVertexColor(A())
    f._pool[idx] = b
    return b
end

local function BuildMenu(level, items, width, anchor, point)
    local f = GetLevel(level)
    width = width or MENU_W
    for _, b in ipairs(f._pool) do b:Hide() end
    local y, n = -4, 0
    for _, item in ipairs(items) do
        n = n + 1
        local b = AcquireItem(f, n)
        b:ClearAllPoints(); b:Show()
        if item.isSeparator then
            b:SetSize(width - 2, 7)
            b:SetPoint("TOPLEFT", 1, y)
            b._lbl:Hide(); b._check:Hide(); b._arrow:Hide(); b._hl:Hide(); b._line:Show()
            b:EnableMouse(false)
            b:SetScript("OnEnter", nil); b:SetScript("OnLeave", nil); b:SetScript("OnClick", nil)
            y = y - 7
        else
            b:SetSize(width - 2, ITEM_H)
            b:SetPoint("TOPLEFT", 1, y)
            b._line:Hide(); b._lbl:Show()
            b._lbl:SetText(L(item.text or ""))
            b._check:SetShown(item.checked and true or false)
            b._arrow:SetShown(item.submenu and true or false)
            if item.danger then b._lbl:SetTextColor(DANGER[1], DANGER[2], DANGER[3])
            elseif item.disabled then b._lbl:SetTextColor(BRD2[1], BRD2[2], BRD2[3])
            else b._lbl:SetTextColor(TXT[1], TXT[2], TXT[3]) end
            b._hl:Hide()
            b:EnableMouse(true)
            b:SetScript("OnEnter", function()
                if not item.disabled then b._hl:Show() end
                if item.submenu then BuildMenu(level + 1, item.submenu, item.submenuWidth or width, b, "RIGHT")
                else HideMenusFrom(level + 1) end
            end)
            b:SetScript("OnLeave", function() b._hl:Hide() end)
            b:SetScript("OnClick", function()
                if item.disabled or item.submenu then return end
                HideMenusFrom(1)
                if item.onClick then item.onClick() end
            end)
            y = y - ITEM_H
        end
    end
    f:SetSize(width, (-y) + 4)
    f:ClearAllPoints()
    if point == "RIGHT" then f:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 2, 2)
    else f:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2) end
    f:Show()
    return f
end

function OUI.ShowContextMenu(anchor, items, opts)
    opts = opts or {}
    EnsureCloser()
    HideMenusFrom(1)
    closer:Show()
    BuildMenu(1, items, opts.width or MENU_W, anchor, opts.point or "BOTTOM")
end

-- ---- Dropdown (sharp box, accent sort-arrow, opens a context menu) ----
local function MakeDropdown(parent, opts)
    opts = opts or {}
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(opts.width or 280, 26)
    local lbl = Label(row, 13); lbl:SetPoint("LEFT"); lbl:SetText(L(opts.label or ""))

    local ddW = opts.ddWidth or 170
    local dd = CreateFrame("Button", nil, row)
    dd:SetSize(ddW, 26); dd:SetPoint("RIGHT")
    SolidTex(dd, "BACKGROUND", ROW[1], ROW[2], ROW[3], 1):SetAllPoints()
    PixelBorder(dd, BRD2[1], BRD2[2], BRD2[3], 1)
    local sel = Label(dd, 13); sel:SetPoint("LEFT", 10, 0); sel:SetPoint("RIGHT", -24, 0); sel:SetJustifyH("LEFT")
    local arrow = dd:CreateTexture(nil, "OVERLAY")
    arrow:SetTexture("Interface\\Buttons\\UI-SortArrow"); arrow:SetSize(12, 12)
    arrow:SetPoint("RIGHT", -8, 0); arrow:SetTexCoord(0, 1, 1, 0); arrow:SetVertexColor(A())
    RegAccent({ type = "vertex", obj = arrow })
    AttachHover(dd); Tooltip(dd, opts.tooltip)

    local function Current() return opts.get and opts.get() end
    local function Render()
        local cur = Current()
        local txt = (opts.values and opts.values[cur]) or cur or ""
        sel:SetText(L(tostring(txt)))
    end
    dd:SetScript("OnClick", function()
        local order = opts.order
        if not order then
            order = {}
            for k in pairs(opts.values or {}) do order[#order + 1] = k end
            table.sort(order)
        end
        local items = {}
        for _, k in ipairs(order) do
            items[#items + 1] = {
                text = (opts.values and opts.values[k]) or k,
                checked = (k == Current()),
                onClick = function() if opts.set then opts.set(k) end; Render() end,
            }
        end
        OUI.ShowContextMenu(dd, items, { width = ddW })
    end)
    Render(); row.Render = Render
    return row
end

-- ---- Segmented (active = accent fill + dark text) ----
local function MakeSegmented(parent, opts)
    opts = opts or {}
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(opts.width or 280, 24)
    local lbl = Label(row, 13); lbl:SetPoint("LEFT"); lbl:SetText(L(opts.label or ""))

    local cont = CreateFrame("Frame", nil, row)
    cont:SetPoint("RIGHT"); cont:SetHeight(24)
    PixelBorder(cont, BRD2[1], BRD2[2], BRD2[3], 1)

    local segs, buttons, x = opts.segments or {}, {}, 0
    local function Render()
        local cur = opts.get and opts.get()
        for _, b in ipairs(buttons) do
            local on = (b._value == cur)
            b._fill:SetShown(on)
            if on then b._fill:SetColorTexture(A()); b._lbl:SetTextColor(INK[1], INK[2], INK[3])
            else b._lbl:SetTextColor(DIM[1], DIM[2], DIM[3]) end
        end
    end
    for i, seg in ipairs(segs) do
        local w = seg.width or 56
        local b = CreateFrame("Button", nil, cont)
        b:SetSize(w, 22); b:SetPoint("LEFT", x, 0); x = x + w
        local fill = SolidTex(b, "BACKGROUND", A()); fill:SetAllPoints(); fill:Hide()
        local lb = Label(b, 12); lb:SetPoint("CENTER"); lb:SetText(L(seg.text or seg.value))
        if i < #segs then
            local d = SolidTex(b, "OVERLAY", BRD[1], BRD[2], BRD[3], 1)
            d:SetPoint("RIGHT"); d:SetWidth(1); d:SetHeight(22)
        end
        b._value, b._fill, b._lbl = seg.value, fill, lb
        AttachHover(b)
        b:SetScript("OnClick", function() if opts.set then opts.set(seg.value) end; Render() end)
        RegAccent({ type = "callback", fn = function() Render() end })
        buttons[#buttons + 1] = b
    end
    cont:SetSize(x, 24)
    Render(); row.Render = Render
    return row
end

-- ---- ColorSwatch (opens the Blizzard colour picker; modern + classic paths) ----
local function MakeColorSwatch(parent, opts)
    opts = opts or {}
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(opts.width or 280, 22)
    local lbl = Label(row, 13); lbl:SetPoint("LEFT"); lbl:SetText(L(opts.label or ""))

    local sw = CreateFrame("Button", nil, row)
    sw:SetSize(26, 20); sw:SetPoint("RIGHT")
    local fill = SolidTex(sw, "ARTWORK", 1, 1, 1, 1); fill:SetAllPoints()
    PixelBorder(sw, TXT[1], TXT[2], TXT[3], 1)
    AttachHover(sw); Tooltip(sw, opts.tooltip)

    local function Render()
        local r, g, b
        if opts.get then r, g, b = opts.get() end
        if r then fill:SetColorTexture(r, g, b, 1) end
    end
    sw:SetScript("OnClick", function()
        local r, g, b, a
        if opts.get then r, g, b, a = opts.get() end
        r, g, b, a = r or 1, g or 1, b or 1, a or 1
        local function apply()
            local nr, ng, nb = ColorPickerFrame:GetColorRGB()
            local na = 1
            if opts.hasAlpha then
                if ColorPickerFrame.GetColorAlpha then na = ColorPickerFrame:GetColorAlpha()
                elseif OpacitySliderFrame then na = 1 - OpacitySliderFrame:GetValue() end
            end
            if opts.set then opts.set(nr, ng, nb, opts.hasAlpha and na or nil) end
            fill:SetColorTexture(nr, ng, nb, 1)
        end
        local function cancel()
            if opts.set then opts.set(r, g, b, opts.hasAlpha and a or nil) end
            fill:SetColorTexture(r, g, b, 1)
        end
        if ColorPickerFrame.SetupColorPickerAndShow then
            ColorPickerFrame:SetupColorPickerAndShow({
                r = r, g = g, b = b, opacity = a, hasOpacity = opts.hasAlpha or false,
                swatchFunc = apply, opacityFunc = apply, cancelFunc = cancel,
            })
        else
            ColorPickerFrame.func       = apply
            ColorPickerFrame.opacityFunc = apply
            ColorPickerFrame.cancelFunc = cancel
            ColorPickerFrame.hasOpacity = opts.hasAlpha or false
            ColorPickerFrame.opacity    = opts.hasAlpha and (1 - a) or 0
            ColorPickerFrame:SetColorRGB(r, g, b)
            ColorPickerFrame:Hide(); ColorPickerFrame:Show()
        end
    end)
    Render(); row.Render = Render
    return row
end

OUI.Widgets.Dropdown    = MakeDropdown
OUI.Widgets.Segmented   = MakeSegmented
OUI.Widgets.ColorSwatch = MakeColorSwatch

-- ---- shared low-level helpers + palette (used by Options.lua etc.) ----
OUI._tex     = SolidTex
OUI._label   = Label
OUI._border  = PixelBorder
OUI._accentBorder = AccentBorder
OUI._hover   = AttachHover
OUI._tooltip = Tooltip
OUI._palette = { INK = INK, ROW = ROW, BRD = BRD, BRD2 = BRD2, DIM = DIM, TXT = TXT, DANGER = DANGER }

-- Header sweep for module windows (Bags, character sheet, ...). Gives a window's
-- own title bar the same accent gradient + bottom rule as the config menu, and
-- registers them with the accent engine so colour changes apply live (no reload).
function OUI.StyleHeader(frame, opts)
    if not frame or frame._ouiHeaderStyled then return end
    frame._ouiHeaderStyled = true
    opts = opts or {}
    local intensity = opts.intensity or 0.30
    local sweep = frame:CreateTexture(nil, opts.layer or "BORDER", nil, opts.sublevel)
    sweep:SetTexture("Interface\\Buttons\\WHITE8x8"); sweep:SetAllPoints(frame)
    local function ApplySweep(r, g, b)
        if sweep.SetGradient and CreateColor then
            sweep:SetGradient("HORIZONTAL", CreateColor(r, g, b, 0), CreateColor(r, g, b, intensity))
        elseif sweep.SetGradientAlpha then
            sweep:SetGradientAlpha("HORIZONTAL", r, g, b, 0, r, g, b, intensity)
        end
    end
    ApplySweep(OUI.ACCENT.r, OUI.ACCENT.g, OUI.ACCENT.b)
    OUI.RegAccent({ type = "callback", obj = sweep, fn = ApplySweep })
    if opts.separator ~= false then
        local sep = frame:CreateTexture(nil, "ARTWORK")
        sep:SetTexture("Interface\\Buttons\\WHITE8x8")
        sep:SetVertexColor(OUI.ACCENT.r, OUI.ACCENT.g, OUI.ACCENT.b, 1)
        sep:SetPoint("BOTTOMLEFT", 0, opts.sepOffset or 0)
        sep:SetPoint("BOTTOMRIGHT", 0, opts.sepOffset or 0)
        sep:SetHeight(1)
        OUI.RegAccent({ type = "solid", obj = sep, a = 1 })
    end
    -- live accent (+ legibility glow) for the title font string, if given
    if opts.title then
        OUI.RegAccent({ type = "font", obj = opts.title })
        if OUI.ApplyAccentGlow then OUI.ApplyAccentGlow(opts.title) end
    end
    return sweep
end

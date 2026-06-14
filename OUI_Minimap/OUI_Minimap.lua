-- ===========================================================================
--  OldschoolUI Minimap -- shape/size skin, addon-button bin, info elements
--  (zone/clock/coords/mail) and square indicator buttons. /ouimm, /ouimove.
-- ===========================================================================
local ADDON, ns = ...
local OUI = OldschoolUI
local MM = LibStub("AceAddon-3.0"):NewAddon("OldschoolUIMinimap", "AceEvent-3.0")
ns.MM = MM

local FarmHudActive   -- defined in the MM5 section, used by ApplyShape

local MASK_DIR     = "Interface\\AddOns\\OldschoolUI\\media\\minimapmasks\\%s.tga"
local ROUND_NATIVE = "Textures\\MinimapMask"

-- Indicator-stack hooks consumed by our LootRoll dice button (it anchors below
-- OUI._minimapCalendarBtn and re-anchors when NotifyMinimapStack fires).
OUI._minimapStackListeners = OUI._minimapStackListeners or {}
if not OUI.RegisterMinimapStackListener then
    function OUI.RegisterMinimapStackListener(fn)
        if fn then OUI._minimapStackListeners[#OUI._minimapStackListeners + 1] = fn end
    end
    function OUI.NotifyMinimapStack()
        for _, fn in ipairs(OUI._minimapStackListeners) do pcall(fn) end
    end
end

-- Blizzard chrome we suppress for a clean custom shape. Globals are textures or
-- frames; MinimapCluster.* are the modern header/zone frames (the dark "location
-- frame" at the top and the surrounding border).
local HIDE_FRAMES = {
    "MinimapBorder", "MinimapBorderTop", "MinimapNorthTag",
    "MinimapCompassTexture", "MinimapBackdrop",
    "MinimapZoomIn", "MinimapZoomOut", "MiniMapWorldMapButton",
    "MinimapToggleButton",
    -- replaced by our own square indicator buttons:
    "GameTimeFrame", "MiniMapTrackingButton",
    "QueueStatusButton", "QueueStatusMinimapButton", "MiniMapLFGFrame",
}
local CLUSTER_CHROME = { "BorderTop", "ZoneTextButton", "NineSlice", "Tracking" }

local function killFrame(f)
    if not f or f._ouiKilled then return end
    f._ouiKilled = true
    if f.Hide then f:Hide() end
    if f.SetAlpha then f:SetAlpha(0) end
    -- frames re-show on zone changes; keep them hidden (textures have no OnShow)
    if f.HookScript then pcall(f.HookScript, f, "OnShow", function(s) s:Hide() end) end
end

function MM:SuppressChrome()
    for _, n in ipairs(HIDE_FRAMES) do killFrame(_G[n]) end
    if Minimap and Minimap.NineSlice then killFrame(Minimap.NineSlice) end
    if MinimapCluster then
        for _, k in ipairs(CLUSTER_CHROME) do killFrame(MinimapCluster[k]) end
    end
end

local defaults = {
    profile = {
        shape   = "round",      -- round | square | parallelogram | triangle | trapezoid
        triDown = false,        -- triangle points down (base on top)
        rounded = false,        -- rounded corners for non-round shapes
        width   = 140,
        height  = 140,
        point   = "TOPRIGHT", x = -22, y = -22,
        -- border (addon-level override of the suite-global border style)
        bOverride = false, bcol = { 0, 0, 0, 0.9 }, bsize = 1,
        -- button placement (MM2 consumes this); "auto" = best edge per shape
        btnEdge = "auto",       -- auto | TOP | BOTTOM | LEFT | RIGHT
        binBtnSize = 24,
        binPerRow  = 6,
        -- info elements (MM3)
        showZone = true, showClock = true, showCoords = true, showMail = true,
        clockFormat = "auto",   -- auto (server) | 12h | 24h
        zonePos = "TOP", coordsPos = "BOTTOMLEFT", clockPos = "BOTTOMRIGHT", mailPos = "TOPLEFT",
        -- mouseover extras + visibility (MM5)
        showTracking = true, showFriends = true, showLFG = true,
        mouseFade = false, mouseFadeAlpha = 0,
    },
}

-- ---------------------------------------------------------------------------
--  Shape -> mask, and the logically best button edge per shape
-- ---------------------------------------------------------------------------
local function MaskName(p)
    if p.shape == "round" then return nil end
    local n = p.shape
    if p.shape == "triangle" then n = p.triDown and "triangle-down" or "triangle-up" end
    if p.rounded then n = n .. "-round" end
    return n
end

-- The "best" edge to hang buttons/labels off, per shape. Triangles put it on
-- the wide base (opposite the point); everything else along the bottom.
local function DefaultEdge(p)
    if p.shape == "triangle" then
        return p.triDown and "TOP" or "BOTTOM"
    end
    return "BOTTOM"
end
function MM:ButtonEdge()
    local p = self.db.profile
    if p.btnEdge and p.btnEdge ~= "auto" then return p.btnEdge end
    return DefaultEdge(p)
end

-- ---------------------------------------------------------------------------
--  Border style (addon override -> suite-global), via the shared Core helpers
-- ---------------------------------------------------------------------------
function MM:BorderStyle()
    local p = self.db.profile
    if p.bOverride then return p.bcol, p.bsize end
    return OUI.GetGlobalBorderColor(), OUI.GetGlobalBorderSize()
end

-- ---------------------------------------------------------------------------
--  Apply skin: mask + size + suppress Blizzard chrome + our border
-- ---------------------------------------------------------------------------
function MM:ApplyShape()
    if FarmHudActive() then return end   -- let FarmHud own the minimap while shown
    local p = self.db.profile
    local name = MaskName(p)
    Minimap:SetMaskTexture(name and MASK_DIR:format(name) or ROUND_NATIVE)
    Minimap:SetSize(p.width, p.height)
    if MinimapCluster and MinimapCluster.SetSize then
        MinimapCluster:SetSize(p.width, p.height)
    end

    self:SuppressChrome()

    if OUI.PP and OUI.PP.CreateBorder then
        OUI.PP.CreateBorder(Minimap, 0, 0, 0, 0.9)
        local c, sz = self:BorderStyle()
        c = c or { 0, 0, 0, 0.9 }
        if OUI.PP.SetBorderColor then OUI.PP.SetBorderColor(Minimap, c[1], c[2], c[3], c[4] or 1) end
        if OUI.PP.SetBorderSize  then OUI.PP.SetBorderSize(Minimap, sz or 1) end
    end

    self:UpdatePosition()
    if self.bin then self:AnchorBin() end
end

-- Mouse-wheel zoom on the minimap (default UI only zooms via the +/- buttons).
function MM:SetupZoom()
    if Minimap._ouiZoom then return end
    Minimap._ouiZoom = true
    Minimap:EnableMouseWheel(true)
    Minimap:SetScript("OnMouseWheel", function(_, delta)
        if delta > 0 then
            if Minimap_ZoomIn then Minimap_ZoomIn()
            elseif MinimapZoomIn then MinimapZoomIn:Click() end
        else
            if Minimap_ZoomOut then Minimap_ZoomOut()
            elseif MinimapZoomOut then MinimapZoomOut:Click() end
        end
    end)
end

function MM:UpdatePosition()
    local p = self.db.profile
    local f = MinimapCluster or Minimap
    f:ClearAllPoints()
    f:SetPoint(p.point or "TOPRIGHT", UIParent, p.point or "TOPRIGHT", p.x or -22, p.y or -22)
end

-- ---------------------------------------------------------------------------
--  Mover integration (shared Core unlock overlay, /ouimove)
-- ---------------------------------------------------------------------------
function MM:RegisterMover()
    if not (OUI.RegisterUnlockElements and OUI.MakeUnlockElement) then return end
    OUI:RegisterUnlockElements({
        OUI.MakeUnlockElement({
            key     = "OUIMinimap",
            label   = "Minimap",
            getFrame = function() return MinimapCluster or Minimap end,
            getSize  = function() local p = self.db.profile; return p.width, p.height end,
            savePos  = function(_, _, _, x, y)
                local p = self.db.profile
                p.point, p.x, p.y = "CENTER", x, y
                self:UpdatePosition()
            end,
            applyPos = function() self:UpdatePosition() end,
        }),
    })
end

-- ---------------------------------------------------------------------------
--  Lifecycle
-- ---------------------------------------------------------------------------
function MM:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("OldschoolUIMinimapDB", defaults, true)
    ns.db = self.db
end

function MM:RefreshInfo()
    self:UpdateZone(); self:UpdateClock(); self:UpdateCoords(); self:UpdateMail()
end

-- Re-apply everything after an options change.
function MM:OptionsRefresh()
    self:ApplyShape()       -- mask/size/border/position + AnchorBin/PinExtras
    self:LayoutBin()        -- re-grid collected buttons (size/per-row)
    self:RepositionInfo()
    self:RefreshInfo()
end

function MM:OnEnterWorld()
    self:ApplyShape()
    self:RefreshInfo()
end

function MM:OnEnable()
    self:ApplyShape()
    self:SetupZoom()
    self:BuildBin()
    self:AnchorBin()
    self:BuildInfo()
    self:SetupHover()
    self:RegisterMover()
    if OUI.RegisterStyleListener then
        OUI.RegisterStyleListener(function() MM:ApplyShape() end)
    end
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnEnterWorld")
    for _, e in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" }) do
        self:RegisterEvent(e, "UpdateZone")
    end
    for _, e in ipairs({ "UPDATE_PENDING_MAIL", "MAIL_CLOSED", "MAIL_INBOX_UPDATE", "MAIL_SHOW" }) do
        self:RegisterEvent(e, "UpdateMail")
    end
    -- re-pin extras when the queue/LFG indicator appears or disappears
    for _, e in ipairs({ "LFG_UPDATE", "UPDATE_BATTLEFIELD_STATUS", "PVP_BRAWL_INFO_UPDATED" }) do
        self:RegisterEvent(e, "PinExtras")
    end
    -- live clock + coordinate updates
    if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(10, function() MM:UpdateClock() end) end
    local cf = CreateFrame("Frame")
    cf.t = 0
    cf:SetScript("OnUpdate", function(_, dt)
        cf.t = cf.t + dt
        if cf.t > 0.25 then cf.t = 0; MM:UpdateCoords() end
    end)
    self:RefreshInfo()
    -- collect addon buttons now and again as late-loading addons register theirs
    self:CollectButtons()
    if C_Timer and C_Timer.After then
        for _, d in ipairs({ 1, 3, 6, 10, 15 }) do
            C_Timer.After(d, function() MM:CollectButtons() end)
        end
    end
end

-- ---------------------------------------------------------------------------
--  Slash: quick shape testing without the options page (MM4 adds real options)
-- ---------------------------------------------------------------------------
-- ===========================================================================
--  MM2: addon minimap-button bin
--  Third-party minimap buttons (LibDBIcon etc.) anchor themselves on Blizzard's
--  round edge via angle math, so they ignore our shape. We collect them, block
--  their self-repositioning, and stack them in a flyout bin on the shape's edge.
-- ===========================================================================
local BIN_KEEP = {
    Minimap = true, MinimapCluster = true, MinimapBackdrop = true,
    MinimapZoomIn = true, MinimapZoomOut = true, MinimapZoomHitArea = true,
    MiniMapMailFrame = true, MiniMapMailBorder = true,
    GameTimeFrame = true, MiniMapTracking = true, MiniMapTrackingButton = true,
    MiniMapTrackingFrame = true, TimeManagerClockButton = true,
    MinimapZoneTextButton = true, MiniMapInstanceDifficulty = true,
    MiniMapWorldMapButton = true, QueueStatusButton = true,
    QueueStatusMinimapButton = true, MiniMapLFGFrame = true,
    MiniMapBattlefieldFrame = true, MiniMapVoiceChatFrame = true,
    GarrisonLandingPageMinimapButton = true, ExpansionLandingPageMinimapButton = true,
}

local PIN_PATTERNS = {
    "pin", "poi", "node", "handynotes", "gathermate", "tomtom",
    "questie", "waypoint", "blip", "worldmap", "scrollchild",
}

local function Collectable(f)
    if not f or f == Minimap then return false end
    if f:GetObjectType() ~= "Button" then return false end
    local name = f:GetName()
    if not name or BIN_KEEP[name] then return false end
    if name:find("OUIMinimap") then return false end
    local lname = name:lower()
    for _, pat in ipairs(PIN_PATTERNS) do
        if lname:find(pat) then return false end       -- map pins / note pools
    end
    if not f:IsMouseEnabled() then return false end
    local w = f:GetWidth() or 0
    if w < 20 or w > 48 then return false end           -- minimap-button sized
    return true
end

function MM:BuildBin()
    if self.bin then return end
    self.collected, self.binList = self.collected or {}, self.binList or {}

    local bin = CreateFrame("Frame", "OUIMinimapButtonBin", Minimap)
    bin:SetFrameStrata("MEDIUM"); bin:Hide()
    bin.bg = bin:CreateTexture(nil, "BACKGROUND")
    bin.bg:SetAllPoints(); bin.bg:SetColorTexture(0, 0, 0, 0.6)
    if OUI.PP and OUI.PP.CreateBorder then OUI.PP.CreateBorder(bin, 0, 0, 0, 0.9) end
    self.bin = bin

    local tg = CreateFrame("Button", "OUIMinimapBinToggle", Minimap)
    tg:SetSize(22, 22); tg:Hide()
    tg.tex = tg:CreateTexture(nil, "ARTWORK")
    tg.tex:SetPoint("TOPLEFT", 2, -2); tg.tex:SetPoint("BOTTOMRIGHT", -2, 2)
    tg.tex:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
    tg.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    tg.bg = tg:CreateTexture(nil, "BACKGROUND")
    tg.bg:SetAllPoints(); tg.bg:SetColorTexture(0, 0, 0, 0.6)
    if OUI.PP and OUI.PP.CreateBorder then OUI.PP.CreateBorder(tg, 0, 0, 0, 0.9) end
    tg:SetScript("OnClick", function()
        if bin:IsShown() then bin:Hide() else MM:LayoutBin(); bin:Show() end
    end)
    self.binToggle = tg
end

function MM:CollectButtons()
    if InCombatLockdown() then return end   -- avoid taint on reparent
    self:BuildBin()
    local found = false
    local function add(f)
        if f and f ~= self.bin and f ~= self.binToggle and not self.collected[f] then
            self.collected[f] = true
            self.binList[#self.binList + 1] = f
            -- block the addon's own angle-based repositioning, keep the original
            if not f._ouiSP then f._ouiSP = f.SetPoint; f.SetPoint = function() end end
            f:SetParent(self.bin)
            found = true
        end
    end

    -- 1) LibDBIcon-managed buttons -- the common, reliable source.
    local ldb = LibStub and LibStub("LibDBIcon-1.0", true)
    if ldb and ldb.GetButtonList then
        for _, bname in ipairs(ldb:GetButtonList()) do
            local b = (ldb.GetMinimapButton and ldb:GetMinimapButton(bname))
                or _G["LibDBIcon10_" .. bname]
            if b then add(b) end
        end
    end

    -- 2) conservative heuristic for legacy (non-LibDBIcon) buttons only.
    for _, f in ipairs({ Minimap:GetChildren() }) do
        if Collectable(f) then add(f) end
    end

    if found then self:LayoutBin() end
end

function MM:LayoutBin()
    local list, p = self.binList or {}, self.db.profile
    local n = #list
    if n == 0 then if self.binToggle then self.binToggle:Hide() end return end
    if self.binToggle then self.binToggle:Show() end

    local size, gap, pad = p.binBtnSize or 24, 2, 4
    local cols = math.min(p.binPerRow or 6, n)
    local rows = math.ceil(n / cols)
    self.bin:SetSize(cols * size + (cols - 1) * gap + pad * 2,
                     rows * size + (rows - 1) * gap + pad * 2)
    for i, f in ipairs(list) do
        local r, c = math.floor((i - 1) / cols), (i - 1) % cols
        local setp = f._ouiSP or f.SetPoint
        f:SetSize(size, size)
        f:ClearAllPoints()
        setp(f, "TOPLEFT", self.bin, "TOPLEFT", pad + c * (size + gap), -(pad + r * (size + gap)))
        f:Show()
    end
    self:AnchorBin()
end

-- Pin frequently-used buttons next to the toggle and grow them ALONG the
-- minimap edge: a horizontal row on top/bottom edges, a vertical column on
-- left/right edges. The LootRoll dice continues the chain via _minimapStack.
-- Our own square indicator buttons (calendar / tracking / friends / lfg),
-- styled like the bin buttons, shown in the pinned row with the toggle. These
-- replace Blizzard's round calendar/tracking/queue buttons (which we hide).
function MM:BuildIndicators()
    if self.ind then return end
    self.ind = {}
    local font = (OUI.GetFontPath and OUI.GetFontPath()) or STANDARD_TEXT_FONT

    local function mk(key)
        local b = CreateFrame("Button", "OUIMinimapInd" .. key, Minimap)
        b:RegisterForClicks("AnyUp")
        b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints(); b.bg:SetColorTexture(0, 0, 0, 0.6)
        if OUI.PP and OUI.PP.CreateBorder then OUI.PP.CreateBorder(b, 0, 0, 0, 0.9) end
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        self.ind[key] = b
        return b
    end
    local function icon(b, tex)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetPoint("TOPLEFT", 2, -2); b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        if tex then b.icon:SetTexture(tex) end
    end
    local function tip(b, label, fn)
        b:SetScript("OnEnter", function(self)
            if fn then fn(self) else
                GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                GameTooltip:AddLine(label, 1, 0.82, 0); GameTooltip:Show()
            end
        end)
    end

    local cal = mk("Calendar")
    cal.num = cal:CreateFontString(nil, "OVERLAY")
    cal.num:SetFont(font, 12, "OUTLINE"); cal.num:SetPoint("CENTER")
    cal:SetScript("OnClick", function() if ToggleCalendar then ToggleCalendar() end end)
    tip(cal, "Calendar")

    local tr = mk("Tracking")
    icon(tr, "Interface\\Minimap\\Tracking\\None")
    tr:SetScript("OnClick", function(self) MM:OpenTrackingMenu(self) end)
    tip(tr, "Tracking")

    local fr = mk("Friends")
    icon(fr, "Interface\\FriendsFrame\\Battlenet-BattlenetIcon")
    fr:SetScript("OnClick", function() if ToggleFriendsFrame then ToggleFriendsFrame() end end)
    tip(fr, "Friends", function(self) MM:ShowFriends(self) end)

    local lfg = mk("LFG")
    icon(lfg, "Interface\\Icons\\INV_Misc_GroupLooking")
    lfg:SetScript("OnClick", function()
        if PVEFrame_ToggleFrame then PVEFrame_ToggleFrame()
        elseif ToggleLFDParentFrame then ToggleLFDParentFrame() end
    end)
    tip(lfg, "Group Finder")
end

function MM:RefreshIndicators()
    if not self.ind then return end
    if self.ind.Calendar and self.ind.Calendar.num then
        self.ind.Calendar.num:SetText(date("%d"))
    end
    if self.ind.Tracking and self.ind.Tracking.icon then
        local t = GetTrackingTexture and GetTrackingTexture()
        self.ind.Tracking.icon:SetTexture(t or "Interface\\Minimap\\Tracking\\None")
    end
end

function MM:OpenTrackingMenu(anchor)
    if not (C_Minimap and C_Minimap.GetNumTrackingTypes) then return end
    self.trackDD = self.trackDD or CreateFrame("Frame", "OUIMinimapTrackDD", UIParent, "UIDropDownMenuTemplate")
    UIDropDownMenu_Initialize(self.trackDD, function()
        for i = 1, C_Minimap.GetNumTrackingTypes() do
            local info = C_Minimap.GetTrackingInfo(i)
            local name, active
            if type(info) == "table" then name, active = info.name, info.active
            else name = info; active = select(3, C_Minimap.GetTrackingInfo(i)) end
            local item = UIDropDownMenu_CreateInfo()
            item.text = name; item.checked = active
            item.isNotRadio = true; item.keepShownOnClick = true
            item.func = function()
                if C_Minimap.SetTracking then C_Minimap.SetTracking(i, not active) end
                MM:RefreshIndicators()
            end
            UIDropDownMenu_AddButton(item)
        end
    end, "MENU")
    ToggleDropDownMenu(1, nil, self.trackDD, anchor, 0, 0)
end

-- Pin the indicator buttons next to the toggle and grow them ALONG the edge:
-- a horizontal row on top/bottom, a vertical column on left/right. The LootRoll
-- dice continues the chain via _minimapStack.
function MM:PinExtras()
    if InCombatLockdown() or not self.binToggle then return end
    self:BuildIndicators()
    self:RefreshIndicators()
    local p = self.db.profile
    local size = p.binBtnSize or 24
    local edge = self:ButtonEdge()
    local horiz = (edge == "TOP" or edge == "BOTTOM")
    local gap, prev = 4, self.binToggle

    local order = {
        { self.ind.Calendar, true },
        { self.ind.Tracking, p.showTracking },
        { self.ind.Friends,  p.showFriends },
        { self.ind.LFG,      p.showLFG },
    }
    for _, e in ipairs(order) do
        local b, show = e[1], e[2]
        if b then
            if show then
                b:SetSize(size, size)
                b:ClearAllPoints()
                if horiz then b:SetPoint("LEFT", prev, "RIGHT", gap, 0)
                else            b:SetPoint("TOP", prev, "BOTTOM", 0, -gap) end
                b:Show()
                prev = b
            else
                b:Hide()
            end
        end
    end

    OUI._minimapCalendarBtn = self.ind.Calendar
    OUI._minimapStack = {
        frame    = prev,
        point    = horiz and "LEFT" or "TOP",
        relPoint = horiz and "RIGHT" or "BOTTOM",
        x        = horiz and gap or 0,
        y        = horiz and 0 or -gap,
    }
    if OUI.NotifyMinimapStack then OUI.NotifyMinimapStack() end
end

-- Anchor the toggle + bin to the shape's best edge (ButtonEdge override/default).
function MM:AnchorBin()
    if not (self.bin and self.binToggle) then return end
    local edge = self:ButtonEdge()
    local tg, bin = self.binToggle, self.bin
    tg:ClearAllPoints(); bin:ClearAllPoints()
    if edge == "TOP" then
        tg:SetPoint("BOTTOM", Minimap, "TOP", 0, 2)
        bin:SetPoint("BOTTOM", tg, "TOP", 0, 2)
    elseif edge == "LEFT" then
        tg:SetPoint("RIGHT", Minimap, "LEFT", -2, 0)
        bin:SetPoint("RIGHT", tg, "LEFT", -2, 0)
    elseif edge == "RIGHT" then
        tg:SetPoint("LEFT", Minimap, "RIGHT", 2, 0)
        bin:SetPoint("LEFT", tg, "RIGHT", 2, 0)
    else -- BOTTOM (default)
        tg:SetPoint("TOP", Minimap, "BOTTOM", 0, -2)
        bin:SetPoint("TOP", tg, "BOTTOM", 0, -2)
    end
    self:PinExtras()
end

-- ===========================================================================
--  MM3: own info elements (zone text, clock, coordinates, mail) replacing the
--  floating Blizzard cluster chrome. Overlaid on the minimap so they don't
--  collide with the external button bin.
-- ===========================================================================
local INFO_HIDE = {
    "MinimapZoneTextButton", "MinimapZoneText", "TimeManagerClockButton",
    "MiniMapMailFrame", "MiniMapMailBorder",
}

local INFO_POS = {
    TOP         = { "TOP", 0, -3, "CENTER" },
    BOTTOM      = { "BOTTOM", 0, 3, "CENTER" },
    TOPLEFT     = { "TOPLEFT", 4, -3, "LEFT" },
    TOPRIGHT    = { "TOPRIGHT", -4, -3, "RIGHT" },
    BOTTOMLEFT  = { "BOTTOMLEFT", 4, 3, "LEFT" },
    BOTTOMRIGHT = { "BOTTOMRIGHT", -4, 3, "RIGHT" },
}
MM.INFO_POS_ORDER = { "TOP", "BOTTOM", "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }
MM.INFO_POS_NAMES = {
    TOP = "Top", BOTTOM = "Bottom", TOPLEFT = "Top Left", TOPRIGHT = "Top Right",
    BOTTOMLEFT = "Bottom Left", BOTTOMRIGHT = "Bottom Right",
}

function MM:RepositionInfo()
    if not self.info then return end
    local p = self.db.profile
    local function place(fs, key, default)
        if not fs then return end
        local pos = INFO_POS[p[key] or default] or INFO_POS[default]
        fs:ClearAllPoints()
        fs:SetPoint(pos[1], Minimap, pos[1], pos[2], pos[3])
        if fs.SetJustifyH then fs:SetJustifyH(pos[4]) end
    end
    place(self.zoneText, "zonePos", "TOP")
    place(self.coords, "coordsPos", "BOTTOMLEFT")
    place(self.clock, "clockPos", "BOTTOMRIGHT")
    place(self.mail, "mailPos", "TOPLEFT")
end

function MM:BuildInfo()
    if self.info then return end
    self.info = true
    local font = (OUI.GetFontPath and OUI.GetFontPath()) or STANDARD_TEXT_FONT

    local function FS(size, layer)
        local fs = Minimap:CreateFontString(nil, layer or "OVERLAY")
        fs:SetFont(font, size or 11, "OUTLINE")
        return fs
    end

    self.zoneText = FS(12)
    self.coords   = FS(11)
    self.clock    = FS(11)

    -- mail indicator (own, so it reliably clears once mail is read)
    local mail = Minimap:CreateTexture(nil, "OVERLAY")
    mail:SetSize(20, 20)
    mail:SetTexture("Interface\\Minimap\\Tracking\\Mailbox")
    mail:Hide()
    self.mail = mail

    self:RepositionInfo()

    for _, fn in ipairs(INFO_HIDE) do
        local f = _G[fn]
        if f then
            if f.UnregisterAllEvents then f:UnregisterAllEvents() end
            if f.Hide then f:Hide() end
            if f.SetAlpha then f:SetAlpha(0) end
        end
    end
end

function MM:UpdateZone()
    if not self.zoneText then return end
    local p = self.db.profile
    if not p.showZone then self.zoneText:Hide(); return end
    self.zoneText:Show()
    self.zoneText:SetText(GetMinimapZoneText() or GetZoneText() or "")
    local pvp = GetZonePVPInfo and GetZonePVPInfo()
    local c = { 1, 1, 1 }
    if pvp == "sanctuary" then c = { 0.41, 0.8, 0.94 }
    elseif pvp == "arena" or pvp == "hostile" then c = { 0.9, 0.2, 0.2 }
    elseif pvp == "friendly" then c = { 0.2, 0.85, 0.2 }
    elseif pvp == "contested" then c = { 0.9, 0.7, 0.2 } end
    self.zoneText:SetTextColor(c[1], c[2], c[3])
end

function MM:UpdateClock()
    if not self.clock then return end
    local p = self.db.profile
    if not p.showClock then self.clock:Hide(); return end
    self.clock:Show()
    local txt
    if p.clockFormat == "24h" then
        txt = date("%H:%M")
    elseif p.clockFormat == "12h" then
        txt = date("%I:%M"):gsub("^0", "") .. date(" %p")
    else
        local h, m = GetGameTime()
        txt = string.format("%02d:%02d", h or 0, m or 0)
    end
    self.clock:SetText(txt)
end

function MM:UpdateCoords()
    if not self.coords then return end
    local p = self.db.profile
    if not p.showCoords then self.coords:Hide(); return end
    self.coords:Show()
    local x, y
    if C_Map and C_Map.GetBestMapForUnit then
        local m = C_Map.GetBestMapForUnit("player")
        if m and C_Map.GetPlayerMapPosition then
            local pos = C_Map.GetPlayerMapPosition(m, "player")
            if pos then x, y = pos:GetXY() end
        end
    elseif GetPlayerMapPosition then
        x, y = GetPlayerMapPosition("player")
    end
    if x and x > 0 then
        self.coords:SetText(string.format("%.1f, %.1f", x * 100, y * 100))
    else
        self.coords:SetText("--")
    end
end

function MM:UpdateMail()
    if not self.mail then return end
    if self.db.profile.showMail and HasNewMail() then self.mail:Show() else self.mail:Hide() end
end

-- ===========================================================================
--  MM5: mouseover extras (tracking + friends-on-hover), minimap visibility
--  (mouseover fade), and FarmHud compatibility.
-- ===========================================================================
local function FarmHudActive_impl()
    local fh = _G.FarmHud
    return fh and fh.IsShown and fh:IsShown()
end
FarmHudActive = FarmHudActive_impl

function MM:ShowFriends(anchor)
    GameTooltip:SetOwner(anchor, "ANCHOR_LEFT")
    GameTooltip:AddLine("Friends online", 1, 0.82, 0)
    local any = false
    if C_FriendList and C_FriendList.GetNumFriends then
        for i = 1, C_FriendList.GetNumFriends() do
            local info = C_FriendList.GetFriendInfoByIndex(i)
            if info and info.connected then
                any = true
                GameTooltip:AddDoubleLine(info.name or "?",
                    info.level and ("L" .. info.level) or "", 0.4, 0.9, 0.4, 0.7, 0.7, 0.7)
            end
        end
    end
    if BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendAccountInfo then
        for i = 1, BNGetNumFriends() do
            local acc = C_BattleNet.GetFriendAccountInfo(i)
            local g = acc and acc.gameAccountInfo
            if g and g.isOnline then
                any = true
                GameTooltip:AddDoubleLine(acc.accountName or "?",
                    g.characterName or "", 0.4, 0.7, 1, 0.7, 0.7, 0.7)
            end
        end
    end
    if not any then GameTooltip:AddLine("Nobody online", 0.6, 0.6, 0.6) end
    GameTooltip:Show()
end

-- Visibility: optionally fade the whole minimap when not hovered (always full in
-- combat or while unlocked). Yields to FarmHud while it is shown.
function MM:SetupHover()
    if self.hoverDriver then return end
    local f = CreateFrame("Frame")
    self.hoverDriver = f
    f.t = 0
    f:SetScript("OnUpdate", function(_, dt)
        f.t = f.t + dt
        if f.t < 0.1 then return end
        f.t = 0
        if FarmHudActive() then return end
        local p = MM.db.profile
        if not p.mouseFade then
            if MinimapCluster then MinimapCluster:SetAlpha(1) end
            return
        end
        local over = MouseIsOver(MinimapCluster) or (MM.bin and MM.bin:IsShown())
        local inCombat = (UnitAffectingCombat and UnitAffectingCombat("player")) or false
        local a = 1
        if p.locked and not over and not inCombat then a = (p.mouseFadeAlpha or 0) / 100 end
        if MinimapCluster then MinimapCluster:SetAlpha(a) end
    end)
end

local SHAPES = { "round", "square", "parallelogram", "triangle", "trapezoid" }
SLASH_OUIMM1 = "/ouimm"
SlashCmdList["OUIMM"] = function(msg)
    msg = (msg or ""):lower():gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    local cmd, arg = msg:match("^(%S*)%s*(.*)$")
    local p = MM.db.profile
    if cmd == "shape" and arg ~= "" then
        p.shape = arg; MM:ApplyShape()
        print("|cffd9a441[OUI Minimap]|r shape = " .. arg)
    elseif cmd == "round" then
        p.rounded = not p.rounded; MM:ApplyShape()
        print("|cffd9a441[OUI Minimap]|r rounded = " .. tostring(p.rounded))
    elseif cmd == "flip" then
        p.triDown = not p.triDown; MM:ApplyShape()
        print("|cffd9a441[OUI Minimap]|r triangle down = " .. tostring(p.triDown))
    elseif cmd == "size" then
        local w, h = arg:match("^(%d+)%s+(%d+)$")
        if w then p.width, p.height = tonumber(w), tonumber(h); MM:ApplyShape()
            print("|cffd9a441[OUI Minimap]|r size = " .. w .. "x" .. h)
        else print("|cffd9a441[OUI Minimap]|r usage: /ouimm size <w> <h>") end
    elseif cmd == "collect" then
        MM:CollectButtons()
        print("|cffd9a441[OUI Minimap]|r collected " .. #(MM.binList or {}) .. " buttons.")
    elseif cmd == "edge" and arg ~= "" then
        p.btnEdge = arg:upper(); MM:AnchorBin()
        print("|cffd9a441[OUI Minimap]|r button edge = " .. p.btnEdge .. " (use auto for per-shape default)")
    elseif cmd == "binsize" and arg ~= "" then
        p.binBtnSize = tonumber(arg) or p.binBtnSize; MM:LayoutBin()
        print("|cffd9a441[OUI Minimap]|r bin button size = " .. tostring(p.binBtnSize))
    else
        print("|cffd9a441[OUI Minimap]|r shapes: round square parallelogram triangle trapezoid")
        print("  /ouimm shape <name> | round | flip | size <w> <h>")
        print("  /ouimm collect | edge <auto|top|bottom|left|right> | binsize <px>")
    end
end

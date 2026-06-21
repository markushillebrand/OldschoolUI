-- ===========================================================================
--  OldschoolUI -- Blizzard Skin
--  Themed reskin of stock Blizzard frames so they match the suite look.
--  Clean-room: feature set understood from the source, implementation is our
--  own. All Blizzard frames are touched visual-only via hooksecurefunc /
--  HookScript + our own overlay textures and the Core pixel-border; we never
--  Hide/Show/SetParent or set protected attributes on Blizzard frames.
--
--  Stage 1: tooltips (GameTooltip + shared tooltips). Context menus, static
--  popups, the game (pause) menu, queue popup/status, keybind frame and the
--  LFG dialogs are added in later stages of this file.
-- ===========================================================================
local ADDON, ns = ...
local OUI = OldschoolUI
if not OUI then return end

local BS = LibStub("AceAddon-3.0"):NewAddon("OldschoolUIBlizzardSkin", "AceEvent-3.0")
ns.BS = BS

-- ---------------------------------------------------------------------------
--  Saved settings
-- ---------------------------------------------------------------------------
local defaults = {
    profile = {
        reskinTooltips   = true,    -- master toggle for the tooltip reskin
        reskinFrames     = true,    -- reskin menus, static popups, game menu, dialogs
        accentBorders    = false,   -- accent-coloured tooltip border (vs neutral dark)
        classColorNames  = true,    -- colour player names by class
        showPlayerTitles = false,   -- include the unit's title on its name line
        showItemLevel    = true,    -- append item level for equippable items
        showSpellID      = false,   -- append the spell id (debug-ish)
        tooltipFontScale = 1.0,     -- 1.0 = leave Blizzard sizing untouched
        customCharacterSheet = true, -- replace Blizzard's character pane with ours
    },
}

-- ---------------------------------------------------------------------------
--  Palette (module-local; accent stays live via OUI.ACCENT)
-- ---------------------------------------------------------------------------
local BG   = { 0.05, 0.05, 0.05 }   -- dark fill
local BG_A = 0.92
local BRD  = { 0.22, 0.22, 0.22 }   -- neutral dark border
local BRD_A = 1

local RAID_CC = RAID_CLASS_COLORS

local function ac() return OUI.ACCENT.r, OUI.ACCENT.g, OUI.ACCENT.b end
local function borderRGB()
    local p = BS.db and BS.db.profile
    if p and p.accentBorders then return ac() end
    return BRD[1], BRD[2], BRD[3]
end

-- ===========================================================================
--  Tooltips
-- ===========================================================================
-- Per-tooltip overlay state, weak-keyed so hidden/cleared tooltips can be
-- collected. We never store our refs directly on the Blizzard frame.
local ttState = setmetatable({}, { __mode = "k" })

local function ttOverlay(tt)
    local st = ttState[tt]
    if not st then
        st = {}
        st.bg = tt:CreateTexture(nil, "BACKGROUND", nil, -7)
        st.bg:SetAllPoints(tt)
        ttState[tt] = st
    end
    return st
end

function BS:SkinTooltipFonts(tt)
    local p = self.db.profile
    local scale = p.tooltipFontScale or 1.0
    if scale == 1.0 then return end
    local name = tt.GetName and tt:GetName()
    if not name then return end
    for i = 1, tt:NumLines() or 0 do
        for _, side in ipairs({ "Left", "Right" }) do
            local fs = _G[name .. "Text" .. side .. i]
            if fs then
                local f, sz, fl = fs:GetFont()
                if f and sz then fs:SetFont(f, sz * scale, fl) end
            end
        end
    end
end

-- Apply the dark fill + border + hide Blizzard's NineSlice. Safe to call on
-- every SharedTooltip_SetBackdropStyle pass (idempotent).
function BS:SkinTooltip(tt)
    local p = self.db and self.db.profile
    if not (tt and p and p.reskinTooltips) then return end
    if tt.IsForbidden and tt:IsForbidden() then return end
    -- Embedded tooltips (the reward block inside a quest tooltip) render inside
    -- a parent tooltip; a second bg+border there looks wrong, so leave them.
    if tt.IsEmbedded then return end

    local st = ttOverlay(tt)
    st.bg:SetColorTexture(BG[1], BG[2], BG[3], BG_A)
    st.bg:Show()
    if tt.NineSlice then tt.NineSlice:SetAlpha(0) end
    if OUI.PP and OUI.PP.CreateBorder then
        OUI.PP.CreateBorder(tt, BRD[1], BRD[2], BRD[3], BRD_A)
        OUI.PP.SetBorderColor(tt, borderRGB())
    end
    self:SkinTooltipFonts(tt)
end

-- ---- content additions (class colour, titles, item level, spell id) -------
function BS:OnTooltipUnit(tt)
    local p = self.db.profile
    if not (p.reskinTooltips and p.classColorNames) then return end
    local _, unit = tt:GetUnit()
    if not unit or not UnitIsPlayer(unit) then return end
    local name = tt.GetName and tt:GetName()
    local line = name and _G[name .. "TextLeft1"]
    if not line then return end
    local _, class = UnitClass(unit)
    local c = class and RAID_CC and RAID_CC[class]
    if not c then return end
    local label = (p.showPlayerTitles and UnitPVPName(unit)) or UnitName(unit)
    if label then line:SetText(label) end
    line:SetTextColor(c.r, c.g, c.b)
end

function BS:OnTooltipItem(tt)
    local p = self.db.profile
    if not (p.reskinTooltips and p.showItemLevel) then return end
    local _, link = tt:GetItem()
    if not link or not IsEquippableItem(link) then return end
    local _, _, _, ilvl = GetItemInfo(link)
    if ilvl and ilvl > 1 then
        tt:AddDoubleLine((OUI.L and OUI.L("Item Level")) or "Item Level", tostring(ilvl), 1, 1, 1, ac())
        tt:Show()
    end
end

function BS:OnTooltipSpell(tt)
    local p = self.db.profile
    if not (p.reskinTooltips and p.showSpellID) then return end
    local _, id = tt:GetSpell()
    if id then
        tt:AddLine("Spell ID: " .. id, ac())
        tt:Show()
    end
end

function BS:SetupTooltips()
    if self._ttHooked then return end
    self._ttHooked = true

    -- Primary entry: fires for GameTooltip and the other shared tooltips
    -- whenever their backdrop style is (re)applied, i.e. on show.
    if type(SharedTooltip_SetBackdropStyle) == "function" then
        hooksecurefunc("SharedTooltip_SetBackdropStyle", function(tt)
            BS:SkinTooltip(tt)
        end)
    end

    -- Fallback / belt-and-suspenders for the always-present tooltips.
    for _, tt in ipairs({ GameTooltip, ItemRefTooltip, ShoppingTooltip1, ShoppingTooltip2 }) do
        if tt and tt.HookScript then
            tt:HookScript("OnShow", function(self) BS:SkinTooltip(self) end)
        end
    end

    if GameTooltip and GameTooltip.HookScript then
        GameTooltip:HookScript("OnTooltipSetUnit",  function(self) BS:OnTooltipUnit(self) end)
        GameTooltip:HookScript("OnTooltipSetItem",  function(self) BS:OnTooltipItem(self) end)
        GameTooltip:HookScript("OnTooltipSetSpell", function(self) BS:OnTooltipSpell(self) end)
    end
end

-- ===========================================================================
--  Generic dark panel (menus, popups, dialogs, the game menu)
-- ===========================================================================
-- Our fill sits on the BORDER layer so it covers a frame's stock BACKGROUND
-- texture even when that texture isn't a hideable NineSlice. Weak-keyed; we
-- only add child textures + the Core border, never Hide/SetParent the frame.
local panelState = setmetatable({}, { __mode = "k" })
local gmBtnState = setmetatable({}, { __mode = "k" })
local borderOv     = setmetatable({}, { __mode = "k" })

-- Border edges anchored to the FRAME itself (not to the container), so the
-- container collapsing -- which layout-managed frames do to their children --
-- doesn't drag the edges with it. Re-snapped over a few frames because frames
-- like the game menu oscillate in size before their layout settles.
local function snapBorder(c, frame)
    local t, b, l, r = c._top, c._bottom, c._left, c._right
    if not (t and frame) then return end
    local e = 1
    local col = c._col
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    t:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0); t:SetHeight(e)
    b:ClearAllPoints()
    b:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    b:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0); b:SetHeight(e)
    l:ClearAllPoints()
    l:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -e)
    l:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, e); l:SetWidth(e)
    r:ClearAllPoints()
    r:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -e)
    r:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, e); r:SetWidth(e)
    for _, tx in ipairs({ t, b, l, r }) do
        tx:SetVertexColor(col[1], col[2], col[3], col[4]); tx:Show()
    end
end

function BS:BorderOverlay(frame)
    if not frame then return end
    local c = borderOv[frame]
    if not c then
        -- Container is a child of the frame (so it hides/shows with it), but the
        -- edge textures anchor to the frame's corners, which makes them immune to
        -- the container being collapsed by a layout-managed parent.
        c = CreateFrame("Frame", nil, frame)
        c:SetAllPoints(frame)
        c:SetFrameLevel((frame:GetFrameLevel() or 0) + 1)
        c:EnableMouse(false)
        local WHITE = "Interface\\Buttons\\WHITE8X8"
        local function mk()
            local tx = c:CreateTexture(nil, "OVERLAY", nil, 7)
            tx:SetTexture(WHITE)
            return tx
        end
        c._top, c._bottom, c._left, c._right = mk(), mk(), mk(), mk()
        c._col = { BRD[1], BRD[2], BRD[3], BRD_A }
        borderOv[frame] = c
    end
    c._col[1], c._col[2], c._col[3] = borderRGB()
    snapBorder(c, frame)
    -- re-snap for a few frames so the final (post-layout) size is captured
    c._ticks = 0
    c:SetScript("OnUpdate", function(self)
        self._ticks = (self._ticks or 0) + 1
        snapBorder(self, frame)
        if self._ticks >= 3 then self:SetScript("OnUpdate", nil) end
    end)
    return c
end

function BS:DarkPanel(frame, alpha)
    if not frame then return end
    if frame.IsForbidden and frame:IsForbidden() then return end
    local st = panelState[frame]
    if not st then
        st = {}
        st.bg = frame:CreateTexture(nil, "BORDER", nil, 0)
        st.bg:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
        st.bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
        panelState[frame] = st
    end
    st.bg:SetColorTexture(BG[1], BG[2], BG[3], alpha or 0.95)
    st.bg:SetAlpha(1)
    st.bg:Show()
    for _, k in ipairs({ "NineSlice", "Border", "Bg", "Background" }) do
        local r = frame[k]
        if r and r.SetAlpha then r:SetAlpha(0) end
    end
    -- border on a child overlay so it sits above the frame's own child frames
    self:BorderOverlay(frame)
end

local function framesEnabled() return BS.db and BS.db.profile and BS.db.profile.reskinFrames end

-- ===========================================================================
--  Context menus (MoP Classic uses the modern Menu manager)
-- ===========================================================================
-- The modern menu paints its own background texture, and its Compositor forbids
-- CreateTexture on the frame. So we recolour the menu's existing background
-- regions dark in place (SetColorTexture is allowed) and put the border on our
-- own child overlay. Pooled menus get re-themed by Blizzard on reuse, so we
-- recolour on every open rather than once.
function BS:SkinMenuFrame(m)
    if not (m and framesEnabled()) then return end
    if m.IsForbidden and m:IsForbidden() then return end
    for i = 1, select("#", m:GetRegions()) do
        local r = select(i, m:GetRegions())
        if r and r.IsObjectType and r:IsObjectType("Texture") then
            r:SetColorTexture(BG[1], BG[2], BG[3], 0.95)
        end
    end
    if m.NineSlice then m.NineSlice:SetAlpha(0) end
    self:BorderOverlay(m)
end

function BS:SetupContextMenus()
    if self._menuHooked then return end
    if not (_G.Menu and _G.Menu.GetManager) then return end
    local mgr = _G.Menu.GetManager()
    if not mgr then return end
    self._menuHooked = true

    -- The OpenMenu/OpenContextMenu post-hook runs INSIDE Blizzard's protected
    -- menu pipeline; touching Blizzard objects there would propagate taint to
    -- action buttons. Defer a frame so the secure run has finished first.
    local function onOpen(manager, _owner, desc)
        if not framesEnabled() then return end
        C_Timer.After(0, function()
            local m = manager.GetOpenMenu and manager:GetOpenMenu()
            if m then BS:SkinMenuFrame(m) end
            if desc and desc.AddMenuAcquiredCallback then
                desc:AddMenuAcquiredCallback(function(f)
                    C_Timer.After(0, function() BS:SkinMenuFrame(f) end)
                end)
            end
        end)
    end
    hooksecurefunc(mgr, "OpenMenu",        function(s, o, d) onOpen(s, o, d) end)
    hooksecurefunc(mgr, "OpenContextMenu", function(s, o, d) onOpen(s, o, d) end)
end

-- ===========================================================================
--  Static popups + the LFG ready popup
-- ===========================================================================
function BS:SetupStaticPopups()
    if self._popupHooked then return end
    self._popupHooked = true
    for i = 1, (STATICPOPUP_NUMDIALOGS or 4) do
        local pop = _G["StaticPopup" .. i]
        if pop and pop.HookScript then
            pop:HookScript("OnShow", function(self) if framesEnabled() then BS:DarkPanel(self, 0.96) end end)
        end
    end
    local rp = _G.LFGDungeonReadyPopup
    if rp and rp.HookScript then
        rp:HookScript("OnShow", function(self) if framesEnabled() then BS:DarkPanel(self, 0.96) end end)
    end
end

-- ===========================================================================
--  Game (pause) menu
-- ===========================================================================
local function stripTextures(frame, exclude)
    if not (frame and frame.GetRegions) then return end
    for i = 1, select("#", frame:GetRegions()) do
        local r = select(i, frame:GetRegions())
        if r and r.IsObjectType and r:IsObjectType("Texture") and not (exclude and exclude[r]) then
            r:SetAlpha(0)
        end
    end
end

-- collect the textures WE added to a frame (panel fill + Core border edges) so
-- a strip pass doesn't wipe our own overlay.
local function ourTextures(frame)
    local set = {}
    local st = panelState[frame]
    if st and st.bg then set[st.bg] = true end
    local bd = frame._ppBorder
    if bd then
        for _, k in ipairs({ "top", "bottom", "left", "right" }) do
            if bd[k] then set[bd[k]] = true end
        end
    end
    return set
end

function BS:SkinGameMenuButton(btn)
    if gmBtnState[btn] then return end
    gmBtnState[btn] = true
    local fs = btn.GetFontString and btn:GetFontString()
    stripTextures(btn, fs and { [fs] = true } or nil)
    -- Blizzard re-shows the Left/Middle/Right slices on state changes, so pin
    -- them hidden.
    for _, k in ipairs({ "Left", "Middle", "Right" }) do
        local t = btn[k]
        if t and t.SetAlpha then
            t:SetAlpha(0)
            hooksecurefunc(t, "SetAlpha", function(self, a) if a and a > 0 then self:SetAlpha(0) end end)
        end
    end
    -- inset dark body + border, sitting 2px inside the button edges
    local inset = CreateFrame("Frame", nil, btn)
    inset:SetPoint("TOPLEFT", 2, -2)
    inset:SetPoint("BOTTOMRIGHT", -2, 2)
    inset:SetFrameLevel(btn:GetFrameLevel())
    local body = inset:CreateTexture(nil, "BACKGROUND", nil, -6)
    body:SetAllPoints()
    body:SetColorTexture(0.1, 0.1, 0.1, 0.85)
    if OUI.PP and OUI.PP.CreateBorder then
        OUI.PP.CreateBorder(inset, BRD[1], BRD[2], BRD[3], BRD_A)
    end
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(inset)
    hl:SetColorTexture(OUI.ACCENT.r, OUI.ACCENT.g, OUI.ACCENT.b, 0.18)
    if fs then
        local f, sz, fl = fs:GetFont()
        if f then fs:SetFont(OUI.GetFontPath() or f, sz or 14, fl) end
    end
end

function BS:SkinGameMenu()
    local gm = _G.GameMenuFrame
    if not (gm and framesEnabled()) then return end
    -- our dark fill + Core border first, so we can exclude them from the strip
    self:DarkPanel(gm, 0.97)
    -- strip the stock parchment chrome (but never our own bg/border textures)
    stripTextures(gm, ourTextures(gm))
    if gm.NineSlice then gm.NineSlice:SetAlpha(0) end
    if gm.Border then gm.Border:SetAlpha(0) end
    -- header: strip its art, accent the title, nudge it inside
    local h = gm.Header
    if h then
        stripTextures(h)
        local ht = h.Text or (h.GetRegions and select(1, h:GetRegions()))
        if ht and ht.SetTextColor then
            ht:SetTextColor(ac())
            local f, sz = ht:GetFont()
            ht:SetFont(OUI.GetFontPath() or f, sz or 16, "")
        end
        h:ClearAllPoints()
        h:SetPoint("TOP", gm, "TOP", 0, -10)
    end
    -- pooled menu buttons
    if gm.buttonPool and gm.buttonPool.EnumerateActive then
        for b in gm.buttonPool:EnumerateActive() do self:SkinGameMenuButton(b) end
    end
end

function BS:SetupGameMenu()
    if self._gmHooked then return end
    local gm = _G.GameMenuFrame
    if not gm then return end
    self._gmHooked = true
    gm:HookScript("OnShow", function() BS:SkinGameMenu() end)
    if gm.InitButtons then hooksecurefunc(gm, "InitButtons", function() BS:SkinGameMenu() end) end
    self:SkinGameMenu()
end

-- ===========================================================================
--  Queue / keybind / LFG dialogs (many are LoadOnDemand)
-- ===========================================================================
local DIALOGS = {
    { "LFGDungeonReadyDialog",    0.96 },  -- dungeon/raid "ready" popup
    { "QuickKeybindFrame",        0.96 },  -- quick keybind mode
    { "LFGListInviteDialog",      0.96 },  -- premade group invite
    { "LFGListApplicationDialog", 0.96 },  -- application to a premade
    { "QueueStatusFrame",         0.96 },  -- the queue-eye status flyout
}

function BS:SkinDialog(frameName, alpha)
    local f = _G[frameName]
    if not (f and f.HookScript) then return false end
    self._dlgHooked = self._dlgHooked or setmetatable({}, { __mode = "k" })
    if self._dlgHooked[f] then return true end
    self._dlgHooked[f] = true
    f:HookScript("OnShow", function(self) if framesEnabled() then BS:DarkPanel(self, alpha or 0.96) end end)
    if f:IsShown() and framesEnabled() then BS:DarkPanel(f, alpha or 0.96) end
    return true
end

function BS:SetupDialogs()
    local allDone = true
    for _, d in ipairs(DIALOGS) do
        if not self:SkinDialog(d[1], d[2]) then allDone = false end
    end
    -- LoadOnDemand frames (group finder, keybind UI) appear only once their
    -- Blizzard addon loads; re-attempt on ADDON_LOADED until all are hooked.
    if not allDone and not self._dlgWaiting then
        self._dlgWaiting = true
        self:RegisterEvent("ADDON_LOADED", function()
            local done = true
            for _, d in ipairs(DIALOGS) do
                if not BS:SkinDialog(d[1], d[2]) then done = false end
            end
            if done then BS:UnregisterEvent("ADDON_LOADED"); BS._dlgWaiting = false end
        end)
    end
end


function BS:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("OldschoolUIBlizzardSkinDB", defaults, true)
end

function BS:OnEnable()
    self:SetupTooltips()
    self:SetupContextMenus()
    self:SetupStaticPopups()
    self:SetupGameMenu()
    self:SetupDialogs()
    -- The Menu manager is created around PLAYER_LOGIN, which can be after our
    -- OnEnable. Retry until the hook is installed (then stop).
    if not self._menuHooked then
        local tries = 0
        local function retry()
            if BS._menuHooked then return end
            BS:SetupContextMenus()
            tries = tries + 1
            if not BS._menuHooked and tries < 20 then C_Timer.After(0.5, retry) end
        end
        C_Timer.After(0.5, retry)
    end
    -- accent change → next tooltip show re-applies the border colour via the
    -- SharedTooltip hook, so no explicit refresh of transient tooltips needed.
end


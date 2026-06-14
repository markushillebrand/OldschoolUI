-- ===========================================================================
--  OldschoolUI Action Bars -- bar model, anchor-grid layout, button skinning,
--  paging, flyout, special bars and the options page.
--
--  MoP Classic note: the Stance and Pet bars ARE managed here, but carefully.
--  We never reparent/SetPoint the protected buttons in combat (deferred to
--  PLAYER_REGEN_ENABLED), we keep Blizzard's own controller alive so it keeps
--  populating the buttons (icons/cooldowns), and we only reclaim them into our
--  grid container after each stock update.
-- ===========================================================================
local ADDON, ns = ...
local OUI = OldschoolUI
local AB = LibStub("AceAddon-3.0"):NewAddon("OldschoolUIActionBars", "AceEvent-3.0")
ns.AB = AB

-- ---------------------------------------------------------------------------
--  Bar model (managed bars only). Each main bar owns 12 action buttons.
--  nativeActionPage is the Blizzard action-page a MultiBar maps to; keeping
--  the native page lets press-and-hold casting and keybinds flow through
--  Blizzard's own input path (wired up in AB2/AB3).
-- ---------------------------------------------------------------------------
local BARS = {
    { key = "MainBar", label = "Action Bar 1 (Main)", barID = 1, count = 12,
      blizzFrame = "MainMenuBar",        btnPrefix = "ActionButton",             nativeMainBar = true,  defCols = 12 },
    { key = "Bar2",    label = "Action Bar 2",        barID = 2, count = 12,
      blizzFrame = "MultiBarBottomLeft",  btnPrefix = "MultiBarBottomLeftButton",  nativeActionPage = 6,  defCols = 12 },
    { key = "Bar3",    label = "Action Bar 3",        barID = 3, count = 12,
      blizzFrame = "MultiBarBottomRight", btnPrefix = "MultiBarBottomRightButton", nativeActionPage = 5,  defCols = 12 },
    { key = "Bar4",    label = "Action Bar 4",        barID = 4, count = 12,
      blizzFrame = "MultiBarRight",       btnPrefix = "MultiBarRightButton",       nativeActionPage = 3,  defCols = 1  },
    { key = "Bar5",    label = "Action Bar 5",        barID = 5, count = 12,
      blizzFrame = "MultiBarLeft",        btnPrefix = "MultiBarLeftButton",        nativeActionPage = 4,  defCols = 1  },
    { key = "Bar6",    label = "Action Bar 6",        barID = 6, count = 12,
      blizzFrame = "MultiBar5",           btnPrefix = "MultiBar5Button",           nativeActionPage = 13, defCols = 12 },
    { key = "Bar7",    label = "Action Bar 7",        barID = 7, count = 12,
      blizzFrame = "MultiBar6",           btnPrefix = "MultiBar6Button",           nativeActionPage = 14, defCols = 12 },
    { key = "Bar8",    label = "Action Bar 8",        barID = 8, count = 12,
      blizzFrame = "MultiBar7",           btnPrefix = "MultiBar7Button",           nativeActionPage = 15, defCols = 12 },
    { key = "StanceBar", label = "Stance Bar",        barID = 9,  count = 10,
      blizzFrame = "StanceBar",           btnPrefix = "StanceButton",              aux = "stance", defCols = 10 },
    { key = "PetBar",    label = "Pet Bar",           barID = 10, count = 10,
      blizzFrame = "PetActionBar",        btnPrefix = "PetActionButton",           aux = "pet",
      visRule = "[petbattle][vehicleui][overridebar][possessbar]hide;[pet]show;hide", defCols = 10 },
}
ns.BARS = BARS

local BY_KEY = {}
for _, b in ipairs(BARS) do BY_KEY[b.key] = b end
ns.BAR_BY_KEY = BY_KEY

-- ---------------------------------------------------------------------------
--  Saved variables. Per-bar layout carries the anchor-grid model:
--    cols   = buttons per row
--    anchor = which corner button 1 sits in and the grid fills from
--             (TOPLEFT | TOPRIGHT | BOTTOMLEFT | BOTTOMRIGHT)
-- ---------------------------------------------------------------------------
local ANCHORS = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }
ns.ANCHORS = ANCHORS

local function defaultBars()
    local t = {}
    for _, b in ipairs(BARS) do
        t[b.key] = {
            enabled = (b.key == "MainBar" or b.aux ~= nil),   -- main bar + pet/stance on by default
            point = "CENTER", x = nil, y = nil,  -- nil => seed from Blizzard on first run
            cols = b.defCols,
            anchor = "TOPLEFT",
            scale = 1.0,
            visibility = "always",  -- always | combat | ooc | mouseover | never
        }
    end
    return t
end

-- ---------------------------------------------------------------------------
--  Special bars (AB4). EncounterBar is our own alternate-power bar; the others
--  are Blizzard-owned frames we reparent into a movable holder.
-- ---------------------------------------------------------------------------
local EXTRA = {
    { key = "EncounterBar",      label = "Encounter Bar",       encounter = true },
    { key = "ExtraActionButton", label = "Extra Action Button", frameName = "ExtraAbilityContainer", blizzMovable = true },
    { key = "QueueStatus",       label = "Queue Status",        frameName = "QueueStatusButton",     blizzMovable = true },
    { key = "MicroBar",          label = "Micro Menu",          frameName = "MicroMenuContainer",    blizzMovable = true },
    { key = "BagBar",            label = "Bag Bar",             frameName = "BagsBar",               blizzMovable = true },
    { key = "XPBar",             label = "XP Bar",              dataBar = "xp",  w = 240, h = 12, defOff = true },
    { key = "RepBar",            label = "Reputation Bar",      dataBar = "rep", w = 240, h = 12, defOff = true },
}
ns.EXTRA = EXTRA
local EXTRA_BY_KEY = {}
for _, e in ipairs(EXTRA) do EXTRA_BY_KEY[e.key] = e end

local function defaultExtras()
    local t = {}
    for _, e in ipairs(EXTRA) do t[e.key] = { enabled = not e.defOff, x = nil, y = nil } end
    return t
end

local defaults = {
    profile = {
        buttonSize = 36,
        spacing    = 4,
        buttonShape = "square",          -- square | rounded | round
        outOfRangeColoring = true,
        outOfRangeColor = { 0.8, 0.15, 0.15 },
        fadeAlpha  = 0,                  -- alpha for faded/hidden bar visibility modes
        bars       = defaultBars(),
        extras     = defaultExtras(),
    },
}

-- ---------------------------------------------------------------------------
--  Anchor-grid geometry. Given a button index (1..count) returns its x,y
--  offset from the container's TOPLEFT, honoring the chosen anchor corner so
--  e.g. a 3x4 grid anchored TOPLEFT puts btn1 top-left and btn12 bottom-right.
-- ---------------------------------------------------------------------------
function ns.GridDims(bar, cfg)
    local size = AB.db.profile.buttonSize
    local gap  = AB.db.profile.spacing
    local cols = math.max(1, math.min(cfg.cols or bar.defCols or 12, bar.count))
    local rows = math.ceil(bar.count / cols)
    local w = cols * size + (cols - 1) * gap
    local h = rows * size + (rows - 1) * gap
    return w, h, cols, rows, size, gap
end

-- Returns x (>=0, from container left) and y (<=0, from container top) for the
-- top-left corner of button `index` (1-based).
function ns.GridButtonOffset(bar, cfg, index)
    local w, h, cols, rows, size, gap = ns.GridDims(bar, cfg)
    local i = index - 1
    local row = math.floor(i / cols)
    local col = i % cols
    local anchor = cfg.anchor or "TOPLEFT"
    -- column position: left-anchored grows right, right-anchored grows left
    local cx
    if anchor == "TOPRIGHT" or anchor == "BOTTOMRIGHT" then
        cx = (cols - 1 - col) * (size + gap)
    else
        cx = col * (size + gap)
    end
    -- row position: top-anchored grows down, bottom-anchored grows up
    local ry
    if anchor == "BOTTOMLEFT" or anchor == "BOTTOMRIGHT" then
        ry = -((rows - 1 - row) * (size + gap))
    else
        ry = -(row * (size + gap))
    end
    return cx, ry, w, h
end

-- ---------------------------------------------------------------------------
--  Bar containers (empty in AB1; buttons added in AB2). Sized to the grid so
--  the mover overlay matches the eventual button block.
-- ---------------------------------------------------------------------------
AB.frames = {}

function AB:GetBarFrame(key)
    return self.frames[key]
end

function AB:BuildContainer(bar)
    if self.frames[bar.key] then return self.frames[bar.key] end
    local f = CreateFrame("Frame", "OUIActionBar_" .. bar.key, UIParent)
    f.barKey = bar.key
    self.frames[bar.key] = f
    return f
end

function AB:ApplyBar(key)
    local bar = BY_KEY[key]
    if not bar then return end
    local cfg = self.db.profile.bars[key]
    local f = self:BuildContainer(bar)

    local w, h = ns.GridDims(bar, cfg)
    f:SetSize(w, h)
    f:SetScale(cfg.scale or 1.0)

    f:ClearAllPoints()
    local x = cfg.x or 0
    local y = cfg.y or 0
    f:SetPoint("CENTER", UIParent, "CENTER", x, y)

    if cfg.enabled then
        self:LayoutBar(bar, cfg)
        self:SuppressBlizzBar(bar)
        self:SetupVisibility(f, true, bar.visRule)
        f:Show()
    else
        self:SetupVisibility(f, false)
        f:Hide()
    end
end

function AB:ApplyAll()
    for _, bar in ipairs(BARS) do self:ApplyBar(bar.key) end
end

-- ---------------------------------------------------------------------------
--  Seed default positions from the live Blizzard bars on first run (MoP: the
--  classic frames MainMenuBar / MultiBar* exist; there is no Edit Mode here,
--  so we just read each frame's center and convert to UIParent-centre coords).
-- ---------------------------------------------------------------------------
function AB:CaptureDefaults()
    local uiW, uiH = UIParent:GetSize()
    local uiScale = UIParent:GetEffectiveScale()
    for _, bar in ipairs(BARS) do
        local cfg = self.db.profile.bars[bar.key]
        if cfg.x == nil or cfg.y == nil then
            local f = _G[bar.blizzFrame]
            local cx, cy = f and f.GetCenter and f:GetCenter()
            if cx and cy and f:GetEffectiveScale() then
                local s = f:GetEffectiveScale()
                cfg.x = math.floor((cx * s / uiScale) - (uiW / 2) + 0.5)
                cfg.y = math.floor((cy * s / uiScale) - (uiH / 2) + 0.5)
            else
                -- fallback: stack near the bottom centre
                cfg.x = 0
                cfg.y = -300 + (bar.barID or 1) * 4
            end
        end
    end
end

-- ---------------------------------------------------------------------------
--  Core mover: one draggable overlay per managed bar.
-- ---------------------------------------------------------------------------
function AB:RegisterMovers()
    if not (OUI.RegisterUnlockElements and OUI.MakeUnlockElement) then return end
    local list = {}
    for _, bar in ipairs(BARS) do
        local key = bar.key
        list[#list + 1] = OUI.MakeUnlockElement({
            key   = "OUIActionBar_" .. key,
            label = bar.label,
            getFrame = function() return AB:GetBarFrame(key) end,
            getSize  = function()
                local b, c = BY_KEY[key], AB.db.profile.bars[key]
                local w, h = ns.GridDims(b, c)
                return w, h
            end,
            isHidden = function() return not AB.db.profile.bars[key].enabled end,
            savePos  = function(_, _, _, x, y)
                local c = AB.db.profile.bars[key]
                c.point, c.x, c.y = "CENTER", x, y
                AB:ApplyBar(key)
            end,
            applyPos = function() AB:ApplyBar(key) end,
        })
    end
    OUI:RegisterUnlockElements(list)
end

-- ---------------------------------------------------------------------------
--  AB2: button skinning, anchor-grid layout (reparent native buttons),
--  Blizzard-bar suppression and out-of-range / usable state colouring.
-- ---------------------------------------------------------------------------
local MASK = "Interface\\AddOns\\OldschoolUI\\media\\buttonmasks\\"

local function HideRegion(btn, key)
    local r = btn[key]
    if not r and btn.GetName and btn:GetName() then r = _G[btn:GetName() .. key] end
    if r and r.Hide then r:Hide(); if r.SetAlpha then r:SetAlpha(0) end end
end

local STRIP = { "BorderArt", "SlotArt", "SlotBackground", "RightDivider", "LeftDivider", "FloatingBG" }

function AB:SkinButton(btn, shape)
    if not btn then return end
    local icon = btn.icon

    -- strip Blizzard slot/border art
    local nt = btn.GetNormalTexture and btn:GetNormalTexture()
    if nt then nt:SetTexture(nil); nt:SetAlpha(0) end
    for _, k in ipairs(STRIP) do HideRegion(btn, k) end

    -- shape via a persistent MaskTexture on the icon. We never call SetMask("")
    -- (that corrupts on repeated shape switches) -- instead we keep one mask and
    -- just swap its texture: WHITE8X8 = square (no rounding), TempPortrait =
    -- round, the proven minimap rounded-rect = rounded.
    if icon then
        if btn.IconMask and icon.RemoveMaskTexture then
            pcall(icon.RemoveMaskTexture, icon, btn.IconMask)
        end
        if not btn._ouiMask and btn.CreateMaskTexture then
            btn._ouiMask = btn:CreateMaskTexture()
            btn._ouiMask:SetAllPoints(icon)
            icon:AddMaskTexture(btn._ouiMask)
        end
        if btn._ouiMask then
            local tex
            if shape == "round" then
                tex = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
            elseif shape == "rounded" then
                tex = "Interface\\AddOns\\OldschoolUI\\media\\minimapmasks\\square-round.tga"
            else
                tex = "Interface\\Buttons\\WHITE8X8"
            end
            btn._ouiMask:SetTexture(tex, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        end
    end
    if btn.cooldown and btn.cooldown.SetUseCircularEdge then
        pcall(btn.cooldown.SetUseCircularEdge, btn.cooldown, shape == "round")
    end

    -- border: rectangular Core border for square/rounded; round gets none for
    -- now (a matching round border comes in a later polish pass).
    if OUI.PP and OUI.PP.CreateBorder then OUI.PP.CreateBorder(btn, 0, 0, 0, 0.9) end
    if OUI.PP and OUI.PP.SetBorderSize then OUI.PP.SetBorderSize(btn, shape == "round" and 0 or 1) end
end

-- re-hide art Blizzard may have re-applied (cheap, runs in the state driver)
function AB:ReassertArt(btn)
    local nt = btn.GetNormalTexture and btn:GetNormalTexture()
    if nt and nt:GetAlpha() > 0 then nt:SetTexture(nil); nt:SetAlpha(0) end
end

local function ActionOf(btn)
    return btn.action or (btn.CalculateAction and btn:CalculateAction())
end

function AB:ColorButton(btn)
    local icon = btn.icon
    local action = ActionOf(btn)
    if not (icon and action) then return end
    local p = self.db.profile
    if p.outOfRangeColoring and IsActionInRange(action) == false then
        local c = p.outOfRangeColor
        icon:SetVertexColor(c[1], c[2], c[3]); return
    end
    local usable, oom = IsUsableAction(action)
    if oom then icon:SetVertexColor(0.5, 0.5, 1.0)
    elseif not usable then icon:SetVertexColor(0.4, 0.4, 0.4)
    else icon:SetVertexColor(1, 1, 1) end
end

-- reparent the bar's native buttons onto our container in anchor-grid order
function AB:LayoutBar(bar, cfg)
    if InCombatLockdown() then self._needLayout = true; return end
    local f = self:BuildContainer(bar)
    local size = self.db.profile.buttonSize
    local shape = self.db.profile.buttonShape
    self.skinned = self.skinned or {}
    for i = 1, bar.count do
        local btn = _G[bar.btnPrefix .. i]
        if btn then
            if bar.aux then self:PrepAuxButton(btn, bar.aux) end
            btn:SetParent(f)
            btn:ClearAllPoints()
            local cx, ry = ns.GridButtonOffset(bar, cfg, i)
            btn:SetPoint("TOPLEFT", f, "TOPLEFT", cx, ry)
            btn:SetSize(size, size)
            self:SkinButton(btn, shape)
            if not bar.aux then
                self:ColorButton(btn)
                if not btn._ouiTracked then
                    btn._ouiTracked = true
                    self.skinned[#self.skinned + 1] = btn
                end
            end
        end
    end
end

-- Pet/Stance buttons are Blizzard-protected and are populated (icons, cooldowns,
-- usability, form/autocast state) and shown/hidden by their own stock controller
-- (PetActionBar / StanceBar). We keep that controller alive so population keeps
-- working; we only reparent the buttons into our grid container and re-apply our
-- layout after each stock update (the modern controller may reparent/reposition
-- them on update). The stock frame itself is made invisible and inert.
local AUX_RELAYOUT_EVENTS = {
    stance = { "UPDATE_SHAPESHIFT_FORMS", "UPDATE_SHAPESHIFT_FORM", "PLAYER_ENTERING_WORLD" },
    pet    = { "PET_BAR_UPDATE", "PET_BAR_UPDATE_COOLDOWN", "PET_BAR_UPDATE_USABLE",
               "PET_UI_UPDATE", "PLAYER_ENTERING_WORLD" },
}

function AB:PrepAuxButton(btn, aux)
    if btn._ouiAuxPrepped then return end
    btn._ouiAuxPrepped = true
    if aux == "pet" then
        -- keep spellbook drag-drop onto pet slots working even though the stock
        -- bar frame is hidden (the secure mixin handler runs first; this is a
        -- fallback). Pet abilities are normally auto-assigned by Blizzard.
        btn:HookScript("OnReceiveDrag", function(self)
            if InCombatLockdown() then return end
            if GetCursorInfo() == "petaction" then PickupPetAction(self:GetID()) end
        end)
    end
end

-- Some Blizzard main-bar bits live in their own top-level frames, not under
-- MainMenuBar, so hiding the main bar leaves them on screen: the XP/reputation
-- status tracking bar and the action-bar page number with its up/down arrows.
-- We have our own XP/Rep data bars and drive paging natively, so suppress them.
local function ResolvePath(...)
    local cur = _G
    for i = 1, select("#", ...) do
        if type(cur) ~= "table" then return nil end
        cur = cur[(select(i, ...))]
        if cur == nil then return nil end
    end
    return cur
end

function AB:HideStray(frame, soft)
    if not frame or frame._ouiStray then return end
    frame._ouiStray = true
    if soft then
        -- protected children (page arrows): alpha + mouse only, never Hide()
        if frame.SetAlpha then frame:SetAlpha(0) end
        if frame.EnableMouse then frame:EnableMouse(false) end
        return
    end
    if frame.UnregisterAllEvents then pcall(frame.UnregisterAllEvents, frame) end
    if frame.SetAlpha then frame:SetAlpha(0) end
    if frame.EnableMouse then frame:EnableMouse(false) end
    local hide = frame.HideBase or frame.Hide
    if hide then pcall(hide, frame) end
    if frame.HookScript then frame:HookScript("OnShow", function(s) s:Hide() end) end
end

function AB:SuppressStrayBlizzFrames()
    if InCombatLockdown() then self._needStray = true; return end
    self:HideStray(_G.MainStatusTrackingBarContainer)
    self:HideStray(_G.MainMenuBarMaxLevelBar)
    -- page number + arrows (alpha-only: the arrows are protected)
    self:HideStray(ResolvePath("MainActionBar", "ActionBarPageNumber"), true)
    self:HideStray(ResolvePath("MainMenuBar", "ActionBarPageNumber"), true)
    self:HideStray(_G.ActionBarUpButton, true)
    self:HideStray(_G.ActionBarDownButton, true)
    self:HideStray(_G.MainMenuBarPageNumber, true)
end

-- re-apply our grid layout for an aux bar after the stock controller updates it
function AB:SetupAuxRelayout(bar)
    local flag = "_auxRelayout_" .. bar.key
    if self[flag] then return end
    self[flag] = true
    local f = CreateFrame("Frame")
    for _, e in ipairs(AUX_RELAYOUT_EVENTS[bar.aux] or {}) do f:RegisterEvent(e) end
    f:SetScript("OnEvent", function()
        if InCombatLockdown() then AB._needLayout = true; return end
        local cfg = AB.db.profile.bars[bar.key]
        if cfg and cfg.enabled then AB:LayoutBar(bar, cfg) end
    end)
end

-- hide the Blizzard bar frame (buttons are already reparented away). MoP: the
-- micro menu and bags are separate frames, so this does not touch them. For
-- pet/stance we keep the stock controller running (it populates the reparented
-- buttons) but make the stock frame invisible and inert, then relayout on its
-- updates so the buttons stay in our container.
function AB:SuppressBlizzBar(bar)
    local frame = _G[bar.blizzFrame]
    if bar.aux then
        if frame then
            frame:SetAlpha(0)
            if frame.EnableMouse then frame:EnableMouse(false) end
        end
        self:SetupAuxRelayout(bar)
        return
    end
    if not frame or frame._ouiSuppressed then return end
    frame._ouiSuppressed = true
    if frame.UnregisterAllEvents and bar.key ~= "MainBar" then frame:UnregisterAllEvents() end
    local hide = frame.HideBase or frame.Hide
    pcall(hide, frame)
    if frame.HookScript then frame:HookScript("OnShow", function(s) s:Hide() end) end
end

function AB:SetupStateDriver()
    if self.stateDriver then return end
    local f = CreateFrame("Frame"); self.stateDriver = f; f.t = 0
    for _, e in ipairs({ "ACTIONBAR_UPDATE_USABLE", "ACTIONBAR_UPDATE_COOLDOWN", "ACTIONBAR_SLOT_CHANGED" }) do
        f:RegisterEvent(e)
    end
    f:SetScript("OnEvent", function() AB:RefreshColors() end)
    -- range has no reliable event; poll lightly
    f:SetScript("OnUpdate", function(_, dt)
        f.t = f.t + dt; if f.t < 0.15 then return end; f.t = 0
        AB:RefreshColors()
    end)
end

function AB:RefreshColors()
    if not self.skinned then return end
    for _, btn in ipairs(self.skinned) do
        if btn:IsShown() then self:ColorButton(btn); self:ReassertArt(btn) end
    end
end

-- ---------------------------------------------------------------------------
--  AB3: paging. With approach A the native main-bar paging (class/stance/
--  stealth/form/bonus) is driven by Blizzard's controller on the reparented
--  buttons, so we add no secure paging snippets. We only step aside for
--  Blizzard's vehicle/override/possess bars and the pet battle UI: a secure
--  visibility driver hides our container in those states (combat-safe) and
--  shows it again afterwards, letting Blizzard's override UI take over.
-- ---------------------------------------------------------------------------
local VISIBILITY_RULE = "[petbattle][vehicleui][overridebar][possessbar]hide;show"

function AB:SetupVisibility(f, enabled, rule)
    if InCombatLockdown() then return end
    if enabled then
        RegisterStateDriver(f, "visibility", rule or VISIBILITY_RULE)
    else
        UnregisterStateDriver(f, "visibility")
    end
end


-- ---------------------------------------------------------------------------
--  AB4: special bars.
-- ---------------------------------------------------------------------------
function AB:GetExtraHolder(key)
    return self.extraFrames and self.extraFrames[key]
end

function AB:BuildExtraHolder(info)
    self.extraFrames = self.extraFrames or {}
    local h = self.extraFrames[info.key]
    if not h then
        h = CreateFrame("Frame", "OUIExtra_" .. info.key, UIParent)
        self.extraFrames[info.key] = h
    end
    return h
end

-- Our own alternate-power (encounter) bar; replaces Blizzard's ornate
-- PlayerPowerBarAlt, driven by the player's alternate power.
function AB:BuildEncounterBar(holder)
    holder:SetSize(220, 20)

    local function KillNative(f)
        if not f then return end
        f:UnregisterEvent("UNIT_POWER_BAR_SHOW")
        f:UnregisterEvent("UNIT_POWER_BAR_HIDE")
        f:Hide()
        if not f._ouiHideHooked then
            f._ouiHideHooked = true
            f:HookScript("OnShow", function(s) s:Hide() end)
        end
    end
    KillNative(_G.PlayerPowerBarAlt)
    KillNative(_G.UIWidgetPowerBarContainerFrame)

    local bar = self.encBar
    if not bar then
        bar = CreateFrame("StatusBar", "OUIEncounterPowerBar", holder)
        bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        bar:SetMinMaxValues(0, 1); bar:SetValue(0)
        local bg = bar:CreateTexture(nil, "BACKGROUND")
        bg:SetPoint("TOPLEFT", -1, 1); bg:SetPoint("BOTTOMRIGHT", 1, -1)
        bg:SetColorTexture(0, 0, 0, 0.9)
        local txt = bar:CreateFontString(nil, "OVERLAY")
        local fp = (OUI.GetFontPath and OUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF"
        txt:SetFont(fp, 12, "OUTLINE"); txt:SetPoint("CENTER")
        bar._txt = txt
        bar:Hide()
        self.encBar = bar
    end
    bar:SetParent(holder); bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", holder, "TOPLEFT", 1, -1)
    bar:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -1, 1)
    local a = OUI.ACCENT or {}
    bar:SetStatusBarColor(a.r or 0.05, a.g or 0.82, a.b or 0.62)

    local ALT = (Enum and Enum.PowerType and Enum.PowerType.Alternate) or 10
    local function Evaluate()
        local mx = UnitPowerMax("player", ALT) or 0
        if mx > 0 then
            local cur = UnitPower("player", ALT) or 0
            bar:SetMinMaxValues(0, mx); bar:SetValue(cur)
            if bar._txt then bar._txt:SetText(cur .. " / " .. mx) end
            if not bar:IsShown() then bar:Show() end
        elseif bar:IsShown() then
            bar:Hide()
        end
    end
    bar._eval = Evaluate

    if not self.encDriver then
        local drv = CreateFrame("Frame"); self.encDriver = drv
        drv:RegisterUnitEvent("UNIT_POWER_BAR_SHOW", "player")
        drv:RegisterUnitEvent("UNIT_POWER_BAR_HIDE", "player")
        drv:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
        drv:RegisterUnitEvent("UNIT_MAXPOWER", "player")
        drv:RegisterEvent("PLAYER_ENTERING_WORLD")
        drv:SetScript("OnEvent", function(_, ev)
            local b = AB.encBar
            if not (b and b._eval) then return end
            if ev == "UNIT_POWER_BAR_HIDE" then b:Hide() else b._eval() end
        end)
    end
    Evaluate()
end

-- AB4b: XP / reputation data bars (our own StatusBars).
function AB:BuildDataBar(info, holder)
    holder:SetSize(info.w or 240, info.h or 12)
    local bar = holder._bar
    if not bar then
        bar = CreateFrame("StatusBar", "OUIDataBar_" .. info.key, holder)
        bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        bar:SetAllPoints(holder)
        local bg = bar:CreateTexture(nil, "BACKGROUND")
        bg:SetPoint("TOPLEFT", -1, 1); bg:SetPoint("BOTTOMRIGHT", 1, -1)
        bg:SetColorTexture(0, 0, 0, 0.85)
        if OUI.PP and OUI.PP.CreateBorder then OUI.PP.CreateBorder(bar, 0, 0, 0, 0.9) end
        local txt = bar:CreateFontString(nil, "OVERLAY")
        local fp = (OUI.GetFontPath and OUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF"
        txt:SetFont(fp, 10, "OUTLINE"); txt:SetPoint("CENTER")
        bar._txt = txt
        holder._bar = bar
    end
    if info.dataBar == "xp" then self:WireXP(holder, bar) else self:WireRep(holder, bar) end
end

function AB:WireXP(holder, bar)
    local function maxLevel()
        if GetMaxLevelForPlayerExpansion then return GetMaxLevelForPlayerExpansion() end
        return MAX_PLAYER_LEVEL or 90
    end
    local function upd()
        local mx = UnitXPMax("player") or 0
        if mx == 0 or (IsXPUserDisabled and IsXPUserDisabled()) or UnitLevel("player") >= maxLevel() then
            holder:Hide(); return
        end
        holder:Show()
        local cur = UnitXP("player") or 0
        bar:SetMinMaxValues(0, mx); bar:SetValue(cur)
        local exh = GetXPExhaustion and GetXPExhaustion()
        if exh and exh > 0 then bar:SetStatusBarColor(0.0, 0.44, 0.87)   -- rested = blue
        else bar:SetStatusBarColor(0.60, 0.40, 0.85) end                 -- not rested = purple
        if bar._txt then bar._txt:SetText(("%d / %d  (%.0f%%)"):format(cur, mx, cur / mx * 100)) end
    end
    if not bar._drv then
        local d = CreateFrame("Frame"); bar._drv = d
        for _, e in ipairs({ "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "PLAYER_LEVEL_UP", "PLAYER_ENTERING_WORLD" }) do
            d:RegisterEvent(e)
        end
        d:SetScript("OnEvent", upd)
    end
    upd()
end

function AB:WireRep(holder, bar)
    local function upd()
        local name, standing, minv, maxv, val
        if C_Reputation and C_Reputation.GetWatchedFactionData then
            local d = C_Reputation.GetWatchedFactionData()
            if d and d.factionID and d.factionID ~= 0 then
                name, standing = d.name, d.reaction
                minv, maxv, val = d.currentReactionThreshold, d.nextReactionThreshold, d.currentStanding
            end
        elseif GetWatchedFactionInfo then
            name, standing, minv, maxv, val = GetWatchedFactionInfo()
        end
        if not name or name == "" then holder:Hide(); return end
        holder:Show()
        local range = (maxv or 0) - (minv or 0); if range <= 0 then range = 1 end
        bar:SetMinMaxValues(0, range); bar:SetValue((val or 0) - (minv or 0))
        local c = (FACTION_BAR_COLORS and FACTION_BAR_COLORS[standing]) or { r = 0.4, g = 0.6, b = 0.9 }
        bar:SetStatusBarColor(c.r, c.g, c.b)
        if bar._txt then bar._txt:SetText(("%s  %d / %d"):format(name, (val or 0) - (minv or 0), range)) end
    end
    if not bar._drv then
        local d = CreateFrame("Frame"); bar._drv = d
        d:RegisterEvent("UPDATE_FACTION"); d:RegisterEvent("PLAYER_ENTERING_WORLD")
        d:SetScript("OnEvent", upd)
    end
    upd()
end

-- Reparent a Blizzard-owned frame into our movable holder and keep it there.
function AB:GrabBlizzFrame(info, holder)
    if InCombatLockdown() then self._needLayout = true; return end
    local f = _G[info.frameName]
    if not f then return end
    f.ignoreInLayout = true
    f.ignoreFramePositionManager = true
    if f.SetIsLayoutFrame then pcall(f.SetIsLayoutFrame, f, false) end
    holder:SetSize(f:GetWidth() or 40, f:GetHeight() or 40)
    f:SetParent(holder); f:ClearAllPoints()
    f:SetPoint("CENTER", holder, "CENTER", 0, 0)
    if not f._ouiGrabHooked then
        f._ouiGrabHooked = true
        hooksecurefunc(f, "SetParent", function(_, p)
            if p ~= holder and not AB._regrab then
                AB._regrab = true; AB:GrabBlizzFrame(info, holder); AB._regrab = nil
            end
        end)
    end
    -- visual-only skin of the bar's buttons (mask + border). Skinning textures is
    -- non-protected, so this is taint-safe even on pet/stance buttons (we never
    -- reparent/SetPoint/state-drive the protected buttons themselves).
    if info.skin then
        local shape = self.db.profile.buttonShape
        for i = 1, info.skin.count do
            local btn = _G[info.skin.prefix .. i]
            if btn then self:SkinButton(btn, shape) end
        end
    end
end

function AB:ApplyExtra(info)
    local cfg = self.db.profile.extras[info.key]
    local h = self:BuildExtraHolder(info)
    h:ClearAllPoints()
    h:SetPoint("CENTER", UIParent, "CENTER", cfg.x or 0, cfg.y or 0)
    if cfg.enabled then
        if info.encounter then self:BuildEncounterBar(h)
        elseif info.dataBar then self:BuildDataBar(info, h)
        elseif info.blizzMovable then self:GrabBlizzFrame(info, h) end
        h:Show()
    else
        h:Hide()
    end
end

function AB:ApplyExtras()
    for _, info in ipairs(EXTRA) do self:ApplyExtra(info) end
end

function AB:CaptureExtraDefaults()
    local uiW, uiH = UIParent:GetSize()
    local uiScale = UIParent:GetEffectiveScale()
    for _, info in ipairs(EXTRA) do
        local cfg = self.db.profile.extras[info.key]
        if cfg.x == nil or cfg.y == nil then
            local f = (info.frameName and _G[info.frameName]) or _G.PlayerPowerBarAlt
            local cx, cy = f and f.GetCenter and f:GetCenter()
            if cx and cy and f:GetEffectiveScale() then
                local s = f:GetEffectiveScale()
                cfg.x = math.floor((cx * s / uiScale) - (uiW / 2) + 0.5)
                cfg.y = math.floor((cy * s / uiScale) - (uiH / 2) + 0.5)
            else
                cfg.x = 0; cfg.y = -260
            end
        end
    end
end

function AB:RegisterExtraMovers()
    if not (OUI.RegisterUnlockElements and OUI.MakeUnlockElement) then return end
    local list = {}
    for _, info in ipairs(EXTRA) do
        local key = info.key
        list[#list + 1] = OUI.MakeUnlockElement({
            key   = "OUIExtra_" .. key,
            label = info.label,
            getFrame = function() return AB:GetExtraHolder(key) end,
            getSize  = function()
                local h = AB:GetExtraHolder(key)
                return (h and h:GetWidth()) or 100, (h and h:GetHeight()) or 24
            end,
            isHidden = function() return not AB.db.profile.extras[key].enabled end,
            savePos  = function(_, _, _, x, y)
                local c = AB.db.profile.extras[key]
                c.x, c.y = x, y; AB:ApplyExtra(info)
            end,
            applyPos = function() AB:ApplyExtra(info) end,
        })
    end
    OUI:RegisterUnlockElements(list)
end


-- ---------------------------------------------------------------------------
--  AB5: flyout reskin (Blizzard's native SpellFlyout) + per-bar visibility/fade.
-- ---------------------------------------------------------------------------
function AB:SkinFlyout(flyout)
    if flyout.Background then
        for _, k in ipairs({ "End", "Start", "HorizontalMiddle", "VerticalMiddle" }) do
            if flyout.Background[k] then flyout.Background[k]:SetAlpha(0) end
        end
    end
    local shape = self.db.profile.buttonShape
    for i = 1, flyout:GetNumChildren() do
        local c = select(i, flyout:GetChildren())
        if c and c.icon then self:SkinButton(c, shape) end
    end
end

function AB:SetupFlyout()
    if self._flyoutHooked then return end
    local f = _G.SpellFlyout
    if not f then return end
    self._flyoutHooked = true
    f:HookScript("OnShow", function(fly) AB:SkinFlyout(fly) end)
end

-- per-bar visibility as an alpha layer (the AB3 state driver still hard-hides
-- for vehicle/petbattle). Modes: always | combat | ooc | mouseover | never.
function AB:UpdateVisibility()
    local p = self.db.profile
    local inC = (UnitAffectingCombat and UnitAffectingCombat("player")) or false
    local faded = p.fadeAlpha or 0
    for _, bar in ipairs(BARS) do
        local cfg = p.bars[bar.key]
        local f = self.frames[bar.key]
        if f and cfg.enabled then
            local mode = cfg.visibility or "always"
            local a = 1
            if mode == "combat" then a = inC and 1 or faded
            elseif mode == "ooc" then a = inC and faded or 1
            elseif mode == "mouseover" then a = (MouseIsOver(f) or inC) and 1 or faded
            elseif mode == "never" then a = 0 end
            f:SetAlpha(a)
        end
    end
end

function AB:SetupFadeDriver()
    if self.fadeDriver then return end
    local d = CreateFrame("Frame"); self.fadeDriver = d; d.t = 0
    d:SetScript("OnUpdate", function(_, dt)
        d.t = d.t + dt; if d.t < 0.1 then return end; d.t = 0
        AB:UpdateVisibility()
    end)
end


SLASH_OUIAB1 = "/ouiab"
SlashCmdList["OUIAB"] = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, arg, arg2 = msg:match("^(%S+)%s*(%S*)%s*(%S*)$")
    if cmd == "reset" then
        for _, bar in ipairs(BARS) do
            local c = AB.db.profile.bars[bar.key]
            c.x, c.y = nil, nil
        end
        AB:CaptureDefaults(); AB:ApplyAll()
        OUI:Print("|cffd9a441[OUI ActionBars]|r positions reset to Blizzard defaults.")
    elseif cmd == "shape" and (arg == "square" or arg == "rounded" or arg == "round") then
        AB.db.profile.buttonShape = arg
        AB:ApplyAll()
        OUI:Print("|cffd9a441[OUI ActionBars]|r shape: " .. arg)
    elseif cmd == "vis" then
        local valid = { always = true, combat = true, ooc = true, mouseover = true, never = true }
        local barKey
        for _, b in ipairs(BARS) do if b.key:lower() == arg then barKey = b.key end end
        if barKey and valid[arg2] then
            AB.db.profile.bars[barKey].visibility = arg2
            OUI:Print("|cffd9a441[OUI ActionBars]|r " .. barKey .. " visibility: " .. arg2)
        else
            OUI:Print("|cffd9a441[OUI ActionBars]|r /ouiab vis <barN> always|combat|ooc|mouseover|never")
        end
    elseif cmd == "cols" then
        local barKey
        for _, b in ipairs(BARS) do if b.key:lower() == arg then barKey = b.key end end
        local n = tonumber(arg2)
        if barKey and n and n >= 1 then
            AB.db.profile.bars[barKey].cols = math.floor(n); AB:ApplyBar(barKey)
            OUI:Print("|cffd9a441[OUI ActionBars]|r " .. barKey .. " cols: " .. math.floor(n) .. " (1 = vertical)")
        else
            OUI:Print("|cffd9a441[OUI ActionBars]|r /ouiab cols <barN|petbar|stancebar> <number>")
        end
    elseif cmd == "anchor" then
        local map = { tl = "TOPLEFT", tr = "TOPRIGHT", bl = "BOTTOMLEFT", br = "BOTTOMRIGHT" }
        local barKey
        for _, b in ipairs(BARS) do if b.key:lower() == arg then barKey = b.key end end
        if barKey and map[arg2] then
            AB.db.profile.bars[barKey].anchor = map[arg2]; AB:ApplyBar(barKey)
            OUI:Print("|cffd9a441[OUI ActionBars]|r " .. barKey .. " anchor: " .. map[arg2])
        else
            OUI:Print("|cffd9a441[OUI ActionBars]|r /ouiab anchor <barN|petbar|stancebar> tl|tr|bl|br")
        end
    elseif cmd == "enable" or cmd == "disable" then
        if InCombatLockdown() then OUI:Print("|cffd9a441[OUI ActionBars]|r not in combat."); return end
        local on = (cmd == "enable")
        local barKey, extraKey
        for _, b in ipairs(BARS) do if b.key:lower() == arg then barKey = b.key end end
        for _, e in ipairs(EXTRA) do if e.key:lower() == arg then extraKey = e.key end end
        if barKey then
            AB.db.profile.bars[barKey].enabled = on; AB:ApplyBar(barKey)
            OUI:Print("|cffd9a441[OUI ActionBars]|r " .. barKey .. " " .. cmd .. "d.")
        elseif extraKey then
            AB.db.profile.extras[extraKey].enabled = on; AB:ApplyExtra(EXTRA_BY_KEY[extraKey])
            OUI:Print("|cffd9a441[OUI ActionBars]|r " .. extraKey .. " " .. cmd .. "d.")
        else
            OUI:Print("|cffd9a441[OUI ActionBars]|r unknown bar: " .. tostring(arg))
        end
    else
        OUI:Print("|cffd9a441[OUI ActionBars]|r /ouimove move | /ouiab shape square|rounded|round | cols <barN> <n> | anchor <barN> tl|tr|bl|br | vis barN <mode> | enable|disable <mainbar|bar2..8|petbar|stancebar|encounterbar|extraactionbutton|queuestatus|microbar|bagbar|xpbar|repbar> | reset")
    end
end

-- ---------------------------------------------------------------------------
--  Lifecycle
-- ---------------------------------------------------------------------------
function AB:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("OldschoolUIActionBarsDB", defaults, true)
    ns.db = self.db
end

function AB:OnEnable()
    self:CaptureDefaults()
    self:CaptureExtraDefaults()
    self:ApplyAll()
    self:ApplyExtras()
    self:SuppressStrayBlizzFrames()
    self:RegisterMovers()
    self:RegisterExtraMovers()
    self:SetupStateDriver()
    self:SetupFlyout()
    self:SetupFadeDriver()
    self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
        if AB._needLayout then AB._needLayout = nil; AB:ApplyAll(); AB:ApplyExtras() end
        if AB._needStray then AB._needStray = nil; AB:SuppressStrayBlizzFrames() end
    end)
end

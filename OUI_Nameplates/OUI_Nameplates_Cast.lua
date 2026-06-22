-- ===========================================================================
--  OldschoolUI -- Nameplates  NP-2: cast bar
--  A cast/channel bar below each plate: spell icon, name, timer, spark, and a
--  non-interruptible state (grey + shield). Clean-room: own implementation.
-- ===========================================================================
local ADDON, ns = ...
local OUI = OldschoolUI
if not OUI then return end

local cfg       = ns.cfg
local fontPath  = ns.fontPath
local barWidth  = ns.barWidth
local barHeight = ns.barHeight
local barTexture = ns.barTexture
if not cfg then return end   -- core not present

local function castHeight() return cfg("castBarHeight") or 17 end

-- ---------------------------------------------------------------------------
--  Build the cast bar onto a plate (called from the core's CreatePlate)
-- ---------------------------------------------------------------------------
function ns.AttachCast(plate)
    if plate.cast then return end

    local cast = CreateFrame("StatusBar", nil, plate)
    cast:Hide()
    cast:SetMinMaxValues(0, 1)
    plate.cast = cast

    cast.bg = cast:CreateTexture(nil, "BACKGROUND")
    cast.bg:SetAllPoints()

    if OUI.PP and OUI.PP.CreateBorder then
        OUI.PP.CreateBorder(cast, 0.067, 0.067, 0.067, 1)
    end

    -- icon hanging off the left edge
    cast.iconFrame = CreateFrame("Frame", nil, cast)
    cast.iconFrame:SetPoint("TOPRIGHT", cast, "TOPLEFT", -1, 0)
    if OUI.PP and OUI.PP.CreateBorder then
        OUI.PP.CreateBorder(cast.iconFrame, 0.067, 0.067, 0.067, 1)
    end
    cast.icon = cast.iconFrame:CreateTexture(nil, "ARTWORK")
    cast.icon:SetPoint("TOPLEFT", 1, -1)
    cast.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    cast.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- spell name (left) + timer (right)
    cast.name = cast:CreateFontString(nil, "OVERLAY")
    cast.name:SetPoint("LEFT", 4, 0)
    cast.name:SetJustifyH("LEFT")

    cast.timer = cast:CreateFontString(nil, "OVERLAY")
    cast.timer:SetPoint("RIGHT", -4, 0)

    -- spark at the leading edge
    cast.spark = cast:CreateTexture(nil, "OVERLAY")
    cast.spark:SetBlendMode("ADD")
    cast.spark:SetColorTexture(1, 1, 1, 0.6)
    cast.spark:SetWidth(2)

    -- non-interruptible shield (a simple frame-tinted mark on the icon)
    cast.shield = cast.iconFrame:CreateTexture(nil, "OVERLAY")
    cast.shield:SetAllPoints(cast.iconFrame)
    cast.shield:SetColorTexture(0, 0, 0, 0.45)
    cast.shield:Hide()

    cast:SetScript("OnUpdate", function(self, elapsed)
        if not self.endTime then return end
        local now = GetTime() * 1000
        local total = self.endTime - self.startTime
        if total <= 0 then self:Hide(); return end
        if self.channeling then
            local remain = self.endTime - now
            if remain <= 0 then self:Hide(); return end
            self:SetValue(remain)
            if cfg("showCastTimer") then self.timer:SetText(string.format("%.1f", remain / 1000)) end
        else
            if now >= self.endTime then self:Hide(); return end
            self:SetValue(now - self.startTime)
            if cfg("showCastTimer") then self.timer:SetText(string.format("%.1f", (self.endTime - now) / 1000)) end
        end
        -- spark follows the fill edge
        local tex = self:GetStatusBarTexture()
        if tex then
            self.spark:ClearAllPoints()
            self.spark:SetPoint("CENTER", tex, self.channeling and "LEFT" or "RIGHT", 0, 0)
            self.spark:SetHeight(self:GetHeight())
        end
    end)
end

-- ---------------------------------------------------------------------------
--  Layout / style (called on set-unit and on settings refresh)
-- ---------------------------------------------------------------------------
local function styleCast(plate)
    local cast = plate.cast
    if not cast then return end
    local w, h = barWidth(), castHeight()
    cast:ClearAllPoints()
    cast:SetPoint("TOPLEFT", plate, "BOTTOMLEFT", 0, -3)
    cast:SetSize(w, h)
    cast:SetStatusBarTexture(barTexture())

    local bg = cfg("castBgColor")
    cast.bg:SetColorTexture(bg.r, bg.g, bg.b, cfg("castBgAlpha") or 0.9)

    cast.iconFrame:SetSize(h, h)
    cast.iconFrame:SetShown(cfg("showCastIcon") ~= false)

    local fp = fontPath()
    cast.name:SetFont(fp, cfg("castNameSize") or 10, "OUTLINE")
    cast.timer:SetFont(fp, cfg("castTimerSize") or 10, "OUTLINE")
    cast.name:SetTextColor(1, 1, 1)
    cast.timer:SetTextColor(1, 1, 1)
    -- keep the name clear of the timer
    cast.name:SetPoint("RIGHT", cast.timer, "LEFT", -4, 0)
end

local function colorCast(plate, notInterruptible)
    local cast = plate.cast
    local c = notInterruptible and cfg("castBarUninterruptible") or cfg("castBar")
    cast:SetStatusBarColor(c.r, c.g, c.b)
    cast.shield:SetShown(notInterruptible and cfg("showCastIcon") ~= false)
end

-- ---------------------------------------------------------------------------
--  Start / stop
-- ---------------------------------------------------------------------------
local function startCast(plate, channeling)
    local unit = plate.unit
    if not unit then return end
    local name, _, texture, startMS, endMS, _, _, notInterruptible
    if channeling then
        name, _, texture, startMS, endMS, _, notInterruptible = UnitChannelInfo(unit)
    else
        name, _, texture, startMS, endMS, _, _, notInterruptible = UnitCastingInfo(unit)
    end
    if not name then plate.cast:Hide(); return end

    styleCast(plate)
    local cast = plate.cast
    cast.channeling = channeling
    cast.startTime = startMS
    cast.endTime = endMS
    cast:SetMinMaxValues(0, endMS - startMS)
    cast:SetValue(channeling and (endMS - startMS) or 0)
    cast.name:SetText(name)
    if texture then cast.icon:SetTexture(texture) end
    colorCast(plate, notInterruptible)
    cast:Show()
end

local function stopCast(plate)
    if plate.cast then plate.cast.endTime = nil; plate.cast:Hide() end
end

-- re-evaluate when a plate (re)binds to a unit -- catch casts already running
function ns.CastOnSetUnit(plate)
    if not plate.cast then return end
    plate.cast:Hide()
    plate.cast.endTime = nil
    if UnitCastingInfo(plate.unit) then startCast(plate, false)
    elseif UnitChannelInfo(plate.unit) then startCast(plate, true) end
end

-- restyle live cast bars on options change
local _origRefresh = ns.RefreshAllSettings
function ns.RefreshAllSettings()
    if _origRefresh then _origRefresh() end
    for _, plate in pairs(ns.plates) do
        if plate.cast and plate.cast:IsShown() then styleCast(plate) end
    end
end

-- ---------------------------------------------------------------------------
--  Per-plate event handlers (dispatched by unit below)
-- ---------------------------------------------------------------------------
local HANDLERS = {
    UNIT_SPELLCAST_START         = function(p) startCast(p, false) end,
    UNIT_SPELLCAST_CHANNEL_START = function(p) startCast(p, true) end,
    UNIT_SPELLCAST_DELAYED       = function(p) if p.cast:IsShown() then startCast(p, false) end end,
    UNIT_SPELLCAST_CHANNEL_UPDATE= function(p) if p.cast:IsShown() then startCast(p, true) end end,
    UNIT_SPELLCAST_STOP          = stopCast,
    UNIT_SPELLCAST_CHANNEL_STOP  = stopCast,
    UNIT_SPELLCAST_FAILED        = stopCast,
    UNIT_SPELLCAST_INTERRUPTED   = stopCast,
    UNIT_SPELLCAST_INTERRUPTIBLE     = function(p) colorCast(p, false) end,
    UNIT_SPELLCAST_NOT_INTERRUPTIBLE = function(p) colorCast(p, true) end,
}

local dispatcher = CreateFrame("Frame")
for event in pairs(HANDLERS) do dispatcher:RegisterEvent(event) end
dispatcher:SetScript("OnEvent", function(_, event, unit)
    local plate = ns.platesByUnit[unit]
    if not (plate and plate.cast) then return end
    HANDLERS[event](plate)
end)

-- ===========================================================================
--  OldschoolUI — Resource Bars
--  Clean-room implementation (written from scratch for MoP Classic 5.5.x).
--
--  Shows three stacked player elements: a health bar, the primary power bar,
--  and — where the class/spec has one — a secondary class-resource display.
--  All maxima are read live from UnitPowerMax; nothing is hard-coded. The
--  secondary-resource model below is our own mapping, built from verified
--  in-client power-type data:
--      HolyPower 9, Chi 12, ComboPoints 4, ShadowOrbs 28, SoulShards 7,
--      DemonicFury 15, BurningEmbers 14, Eclipse/Balance 26, RunicPower 6.
--  Spec is resolved via C_SpecializationInfo.GetSpecialization() (the global
--  GetSpecialization / GetSpecializationInfo are nil on this client).
-- ===========================================================================
local ADDON, ns = ...
local RB  = LibStub("AceAddon-3.0"):NewAddon("OldschoolUIResourceBars", "AceEvent-3.0")
local OUI = OldschoolUI
ns.RB = RB

-- ---------------------------------------------------------------------------
--  Saved settings
-- ---------------------------------------------------------------------------
local defaults = {
    profile = {
        point      = "CENTER",
        x          = 0,
        y          = -170,
        width      = 220,
        rowHeight  = 18,
        secHeight  = 14,
        spacing    = 3,
        showHealth = true,
        showPower  = true,
        showSecond = true,
        healthText = "percent",   -- value | percent | both | none
        powerText  = "value",
        secText    = "value",
        showCast   = true,
        castHeight = 16,
        texOverrideAll = false, texAll = "flat",
        texOverrideHealth = false, texHealth = "flat",
        texOverridePower  = false, texPower  = "flat",
        texOverrideSecondary = false, texSecondary = "flat",
        texOverrideCast   = false, texCast   = "flat",
        bOverrideAll = false, bcolAll = { 0, 0, 0, 0.9 }, bsizeAll = 1,
        bOverrideHealth = false, bcolHealth = { 0, 0, 0, 0.9 }, bsizeHealth = 1,
        bOverridePower  = false, bcolPower  = { 0, 0, 0, 0.9 }, bsizePower  = 1,
        bOverrideSecondary = false, bcolSecondary = { 0, 0, 0, 0.9 }, bsizeSecondary = 1,
        bOverrideCast   = false, bcolCast   = { 0, 0, 0, 0.9 }, bsizeCast   = 1,
        combatFade = false, fadeAlpha = 25,   -- out-of-combat alpha %, when fade on
        colOverrideHealth = false, colHealth = { 0.25, 0.75, 0.30 },
        colOverridePower  = false, colPower  = { 0.30, 0.45, 0.85 },
        colOverrideSecondary = false, colSecondary = { 0.85, 0.70, 0.25 },
        lowHealthAlert = false, lowHealthPct = 35,
        lowPowerAlert  = false, lowPowerPct  = 25,
        locked     = true,
    },
}

-- ---------------------------------------------------------------------------
--  Power-type constants (verified MoP Classic Enum.PowerType values)
-- ---------------------------------------------------------------------------
local P_COMBO, P_RUNIC, P_SOUL = 4, 6, 7
local P_HOLY, P_CHI            = 9, 12
local P_EMBERS, P_FURY         = 14, 15
local P_ECLIPSE, P_ORBS        = 26, 28

-- Secondary-resource colours (our own palette).
local SEC_COLOR = {
    [P_HOLY]   = { 0.95, 0.90, 0.55 },
    [P_CHI]    = { 0.30, 0.90, 0.68 },
    [P_SOUL]   = { 0.62, 0.36, 0.78 },
    [P_ORBS]   = { 0.60, 0.42, 0.80 },
    [P_COMBO]  = { 0.90, 0.32, 0.30 },
    [P_FURY]   = { 0.66, 0.30, 0.76 },
    [P_EMBERS] = { 0.86, 0.46, 0.20 },
}
local ECLIPSE_LUNAR = { 0.40, 0.55, 0.92 }
local ECLIPSE_SOLAR = { 0.96, 0.86, 0.45 }
local RUNE_COLOR = {
    [1] = { 0.80, 0.10, 0.10 },   -- Blood
    [2] = { 0.20, 0.55, 0.90 },   -- Frost
    [3] = { 0.20, 0.80, 0.35 },   -- Unholy
    [4] = { 0.70, 0.30, 0.90 },   -- Death
}
local WHITE = "Interface\\Buttons\\WHITE8x8"

-- Format a bar's value text according to the chosen mode.
local function FormatText(cur, max, mode)
    if mode == "none" or not max or max <= 0 then return "" end
    cur = cur or 0
    local pct = math.floor(cur / max * 100 + 0.5)
    if mode == "percent" then
        return pct .. "%"
    elseif mode == "both" then
        return cur .. "  " .. pct .. "%"
    end
    return tostring(cur)   -- "value"
end

-- ---------------------------------------------------------------------------
--  Spec / secondary-resource resolution (our own model)
-- ---------------------------------------------------------------------------
local function ActiveSpec()
    local n = (GetNumSpecializations and GetNumSpecializations()) or 0
    local i = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization
              and C_SpecializationInfo.GetSpecialization()
    if i and i >= 1 and i <= n then return i end
    return nil   -- no specialization chosen (e.g. low level)
end

-- Returns a descriptor for the active secondary resource, or nil if the class/
-- spec has none. kind = "pips" | "bar" | "segments" | "eclipse" | "runes".
local function SecondaryResource()
    local _, class = UnitClass("player")
    local spec = ActiveSpec()

    if class == "PALADIN" then
        return { pt = P_HOLY, kind = "pips" }
    elseif class == "MONK" then
        return { pt = P_CHI, kind = "pips" }
    elseif class == "ROGUE" then
        return { pt = P_COMBO, kind = "pips" }
    elseif class == "DEATHKNIGHT" then
        return { kind = "runes" }
    elseif class == "PRIEST" then
        if spec == 3 then return { pt = P_ORBS, kind = "pips" } end   -- Shadow
    elseif class == "WARLOCK" then
        if spec == 1 then return { pt = P_SOUL, kind = "pips" }        -- Affliction
        elseif spec == 2 then return { pt = P_FURY, kind = "bar" }      -- Demonology
        elseif spec == 3 then return { pt = P_EMBERS, kind = "segments", segs = 4 } end -- Destruction
    elseif class == "DRUID" then
        if spec == 1 then return { pt = P_ECLIPSE, kind = "eclipse" }   -- Balance
        elseif spec == 2 then return { pt = P_COMBO, kind = "pips", catOnly = true } end -- Feral
    end
    return nil
end

-- ---------------------------------------------------------------------------
--  Small frame builders
-- ---------------------------------------------------------------------------
local function NewBar(parent)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetStatusBarTexture(WHITE)
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(bar)
    bg:SetTexture(WHITE)
    bg:SetVertexColor(0, 0, 0, 0.55)
    bar.bg = bg
    local txt = bar:CreateFontString(nil, "OVERLAY")
    txt:SetFont((OUI.GetFontPath and OUI.GetFontPath()) or STANDARD_TEXT_FONT, 11, "OUTLINE")
    txt:SetPoint("CENTER")
    bar.text = txt
    -- Low-resource alert: a red overlay that pulses while active.
    local alert = bar:CreateTexture(nil, "OVERLAY")
    alert:SetAllPoints(bar); alert:SetTexture(WHITE)
    alert:SetVertexColor(1, 0, 0, 1); alert:SetBlendMode("ADD"); alert:SetAlpha(0)
    bar.alert = alert
    local ag = alert:CreateAnimationGroup(); ag:SetLooping("BOUNCE")
    local a1 = ag:CreateAnimation("Alpha")
    a1:SetFromAlpha(0); a1:SetToAlpha(0.5); a1:SetDuration(0.5); a1:SetSmoothing("IN_OUT")
    bar.alertAnim = ag
    return bar
end

local function PowerColor(token)
    if OUI.GetPowerColor then
        local c = OUI.GetPowerColor(token)
        if c then return c.r or c[1], c.g or c[2], c.b or c[3] end
    end
    return 0.30, 0.45, 0.85
end

-- Resolve a bar's texture via the shared 3-tier model (type → addon-all → global).
local function BarTex(which)
    local p = RB.db.profile
    local scope = OUI.ResolveStyleScope(p, "tex", which)
    if scope == "type" then return OUI.GetBarTexturePath(p["tex" .. which])
    elseif scope == "all" then return OUI.GetBarTexturePath(p.texAll)
    else return OUI.GetBarTexturePath(nil) end
end

-- Resolve a bar's border (colour table + size) via the same 3-tier model.
local function BorderStyle(which)
    local p = RB.db.profile
    local scope = OUI.ResolveStyleScope(p, "b", which)
    if scope == "type" then return p["bcol" .. which], p["bsize" .. which]
    elseif scope == "all" then return p.bcolAll, p.bsizeAll
    else return OUI.GetGlobalBorderColor(), OUI.GetGlobalBorderSize() end
end

-- ---------------------------------------------------------------------------
--  Layout: build the container and its rows
-- ---------------------------------------------------------------------------
local container, healthBar, powerBar, secWidget, castFrame

local function BuildCastBar()
    local cf = CreateFrame("StatusBar", "OUIResourceCastBar", UIParent)
    cf:SetStatusBarTexture(WHITE)
    local bg = cf:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(cf); bg:SetTexture(WHITE); bg:SetVertexColor(0, 0, 0, 0.6)
    local font = (OUI.GetFontPath and OUI.GetFontPath()) or STANDARD_TEXT_FONT
    cf.icon = cf:CreateTexture(nil, "ARTWORK")
    cf.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    cf.name = cf:CreateFontString(nil, "OVERLAY")
    cf.name:SetFont(font, 11, "OUTLINE")
    cf.name:SetJustifyH("LEFT")
    cf.time = cf:CreateFontString(nil, "OVERLAY")
    cf.time:SetFont(font, 11, "OUTLINE")
    cf.time:SetJustifyH("RIGHT")
    cf:Hide()
    return cf
end

local function BuildSecondaryWidget(parent)
    local w = CreateFrame("Frame", nil, parent)
    w.pips, w.segDividers = {}, {}
    -- a StatusBar reused for bar / segments / eclipse kinds
    w.bar = NewBar(w)
    w.bar:SetAllPoints(w)
    -- eclipse needs a centre marker
    w.center = w:CreateTexture(nil, "OVERLAY")
    w.center:SetTexture(WHITE)
    w.center:SetVertexColor(1, 1, 1, 0.5)
    w.center:SetSize(1, 1)
    return w
end

local function Build()
    if container then return end
    local p = RB.db.profile

    container = CreateFrame("Frame", "OUIResourceBars", UIParent)
    container:SetSize(p.width, 1)
    container:SetPoint(p.point, UIParent, p.point, p.x, p.y)

    healthBar = NewBar(container)
    powerBar  = NewBar(container)
    secWidget = BuildSecondaryWidget(container)
    castFrame = BuildCastBar()

    RB:Relayout()
    RB:ApplyTextures()
    RB:ApplySkin()

    if not RB._moverRegistered and OUI.RegisterUnlockElements and OUI.MakeUnlockElement then
        RB._moverRegistered = true
        OUI:RegisterUnlockElements({ OUI.MakeUnlockElement({
            key = "OUIResourceBars", label = "Resource Bars", group = "Resource Bars", order = 100,
            getFrame = function() return container end,
            getSize  = function() return (container and container:GetWidth()) or RB.db.profile.width or 200, 60 end,
            isHidden = function() return false end,
            savePos  = function(_, _, _, x, y)
                local pr = RB.db and RB.db.profile
                if pr and x then
                    pr.point, pr.x, pr.y = "CENTER", x, y
                    if container then container:ClearAllPoints(); container:SetPoint("CENTER", UIParent, "CENTER", x, y) end
                end
            end,
            applyPos = function()
                local pr = RB.db and RB.db.profile
                if container and pr then
                    container:ClearAllPoints()
                    container:SetPoint(pr.point or "CENTER", UIParent, pr.point or "CENTER", pr.x or 0, pr.y or 0)
                end
            end,
        }) })
    end
end

function RB:Relayout()
    if not container then return end
    local p = RB.db.profile
    container:SetWidth(p.width)

    local rows, y = {}, 0
    if p.showHealth then rows[#rows + 1] = { healthBar, p.rowHeight } end
    if p.showPower  then rows[#rows + 1] = { powerBar,  p.rowHeight } end
    if p.showSecond and self._sec then rows[#rows + 1] = { secWidget, p.secHeight } end

    healthBar:Hide(); powerBar:Hide(); secWidget:Hide()
    for i, row in ipairs(rows) do
        local frame, h = row[1], row[2]
        frame:ClearAllPoints()
        frame:SetSize(p.width, h)
        frame:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -y)
        frame:Show()
        y = y + h + (i < #rows and p.spacing or 0)
    end
    container:SetHeight(math.max(y, 1))

    -- Cast bar sits as its own frame just below the container (shown only while
    -- casting), so the main stack never reflows when a cast starts/stops.
    if castFrame then
        local ch = p.castHeight
        castFrame:SetSize(p.width - ch - 2, ch)
        castFrame:ClearAllPoints()
        castFrame:SetPoint("TOPLEFT", container, "BOTTOMLEFT", ch + 2, -p.spacing)
        castFrame.icon:SetSize(ch, ch)
        castFrame.icon:ClearAllPoints()
        castFrame.icon:SetPoint("RIGHT", castFrame, "LEFT", -2, 0)
        castFrame.name:ClearAllPoints()
        castFrame.name:SetPoint("LEFT", castFrame, "LEFT", 4, 0)
        castFrame.name:SetPoint("RIGHT", castFrame, "RIGHT", -36, 0)
        castFrame.time:ClearAllPoints()
        castFrame.time:SetPoint("RIGHT", castFrame, "RIGHT", -3, 0)
    end
end

-- ---------------------------------------------------------------------------
--  Updates
-- ---------------------------------------------------------------------------
local function SetAlert(bar, on)
    if not (bar and bar.alertAnim) then return end
    if on then
        if not bar.alertAnim:IsPlaying() then bar.alertAnim:Play() end
    else
        bar.alertAnim:Stop()
        if bar.alert then bar.alert:SetAlpha(0) end
    end
end

function RB:UpdateHealth()
    if not (container and RB.db.profile.showHealth) then return end
    local cur, max = UnitHealth("player"), UnitHealthMax("player")
    healthBar:SetMinMaxValues(0, max > 0 and max or 1)
    healthBar:SetValue(cur)
    local p = RB.db.profile
    if p.colOverrideHealth and p.colHealth then
        healthBar:SetStatusBarColor(p.colHealth[1], p.colHealth[2], p.colHealth[3])
    else
        local g = OUI.GREEN or { r = 0.25, g = 0.75, b = 0.30 }
        healthBar:SetStatusBarColor(g.r or g[1], g.g or g[2], g.b or g[3])
    end
    healthBar.text:SetText(FormatText(cur, max, RB.db.profile.healthText))
    local pct = max > 0 and (cur / max * 100) or 100
    SetAlert(healthBar, p.lowHealthAlert and cur > 0 and pct <= (p.lowHealthPct or 35))
end

function RB:UpdatePower()
    if not (container and RB.db.profile.showPower) then return end
    local ptype, token = UnitPowerType("player")
    local cur, max = UnitPower("player", ptype), UnitPowerMax("player", ptype)
    powerBar:SetMinMaxValues(0, max > 0 and max or 1)
    powerBar:SetValue(cur)
    local p = RB.db.profile
    if p.colOverridePower and p.colPower then
        powerBar:SetStatusBarColor(p.colPower[1], p.colPower[2], p.colPower[3])
    else
        powerBar:SetStatusBarColor(PowerColor(token))
    end
    powerBar.text:SetText(FormatText(cur, max, RB.db.profile.powerText))
    local pct = max > 0 and (cur / max * 100) or 0
    -- Low-power alert only for mana-like resources (rage/energy starting low is normal).
    local manaLike = (ptype == 0)
    SetAlert(powerBar, p.lowPowerAlert and manaLike and max > 0 and pct <= (p.lowPowerPct or 25))
end

-- ---- secondary kinds -------------------------------------------------------
local function ClearPips(w)
    for _, pip in ipairs(w.pips) do pip:Hide() end
    if w.pipBgs then for _, bg in ipairs(w.pipBgs) do bg:Hide() end end
    for _, d in ipairs(w.segDividers) do d:Hide() end
    w.bar:Hide(); w.center:Hide()
end

local function LayoutPips(w, count, width, height)
    local gap = 2
    local pw = (width - gap * (count - 1)) / count
    w.pipBgs = w.pipBgs or {}
    for i = 1, count do
        local pip = w.pips[i]
        if not pip then
            local bg = w:CreateTexture(nil, "BACKGROUND")
            bg:SetTexture(WHITE); bg:SetVertexColor(0, 0, 0, 0.85)
            w.pipBgs[i] = bg
            pip = w:CreateTexture(nil, "ARTWORK")
            pip:SetTexture(WHITE)
            w.pips[i] = pip
        end
        pip:ClearAllPoints()
        pip:SetSize(pw, height)
        pip:SetPoint("LEFT", w, "LEFT", (i - 1) * (pw + gap), 0)
        pip:Show()
        local bg = w.pipBgs[i]
        bg:ClearAllPoints()
        bg:SetPoint("TOPLEFT", pip, "TOPLEFT", -1, 1)
        bg:SetPoint("BOTTOMRIGHT", pip, "BOTTOMRIGHT", 1, -1)
        bg:Show()
    end
end

function RB:UpdateSecondary()
    local sec = self._sec
    if not (container and sec and RB.db.profile.showSecond) then
        if secWidget then secWidget:Hide() end
        return
    end
    local w = secWidget
    ClearPips(w)

    if sec.kind == "runes" then
        local n = 6
        LayoutPips(w, n, w:GetWidth(), w:GetHeight())
        for i = 1, n do
            local pip = w.pips[i]
            local ready = true
            if GetRuneCooldown then
                local start, dur, isReady = GetRuneCooldown(i)
                ready = isReady or (start == 0) or (dur and dur <= 0)
            end
            local rt = GetRuneType and GetRuneType(i) or 1
            local c = RUNE_COLOR[rt] or RUNE_COLOR[1]
            if ready then pip:SetVertexColor(c[1], c[2], c[3], 1)
            else pip:SetVertexColor(c[1] * 0.25, c[2] * 0.25, c[3] * 0.25, 0.8) end
        end
        return
    end

    local cur = UnitPower("player", sec.pt) or 0
    local max = UnitPowerMax("player", sec.pt) or 0
    local col = SEC_COLOR[sec.pt] or { OUI.ACCENT.r, OUI.ACCENT.g, OUI.ACCENT.b }
    if RB.db.profile.colOverrideSecondary and RB.db.profile.colSecondary then
        col = RB.db.profile.colSecondary
    end

    if sec.kind == "pips" then
        local n = math.min(max > 0 and max or 0, 10)
        if sec.catOnly and not (UnitPowerType("player") == 3) then n = math.min(max, 10) end
        if n <= 0 then return end
        LayoutPips(w, n, w:GetWidth(), w:GetHeight())
        for i = 1, n do
            local pip = w.pips[i]
            if i <= cur then pip:SetVertexColor(col[1], col[2], col[3], 1)
            else pip:SetVertexColor(col[1] * 0.22, col[2] * 0.22, col[3] * 0.22, 0.85) end
        end

    elseif sec.kind == "bar" then
        w.bar:Show()
        w.bar:SetMinMaxValues(0, max > 0 and max or 1)
        w.bar:SetValue(cur)
        w.bar:SetStatusBarColor(col[1], col[2], col[3])
        w.bar.text:SetText(FormatText(cur, max, RB.db.profile.secText))

    elseif sec.kind == "segments" then
        w.bar:Show()
        w.bar:SetMinMaxValues(0, max > 0 and max or 1)
        w.bar:SetValue(cur)
        w.bar:SetStatusBarColor(col[1], col[2], col[3])
        local segs = sec.segs or 4
        local step = w:GetWidth() / segs
        for i = 1, segs - 1 do
            local d = w.segDividers[i]
            if not d then
                d = w:CreateTexture(nil, "OVERLAY")
                d:SetTexture(WHITE); d:SetVertexColor(0, 0, 0, 0.9)
                w.segDividers[i] = d
            end
            d:ClearAllPoints()
            d:SetSize(1, w:GetHeight())
            d:SetPoint("LEFT", w, "LEFT", i * step, 0)
            d:Show()
        end

    elseif sec.kind == "eclipse" then
        -- Balance power runs negative (lunar) .. positive (solar); centre at 0.
        w.bar:Show()
        local span = max > 0 and max or 100
        w.bar:SetMinMaxValues(0, 1)
        local frac = (cur + span) / (2 * span)         -- map -span..+span -> 0..1
        w.bar:SetValue(math.max(0, math.min(1, frac)))
        local dir = GetEclipseDirection and GetEclipseDirection()
        local c = (cur < 0 or dir == "moon") and ECLIPSE_LUNAR or ECLIPSE_SOLAR
        w.bar:SetStatusBarColor(c[1], c[2], c[3])
        w.center:Show()
        w.center:ClearAllPoints()
        w.center:SetSize(1, w:GetHeight())
        w.center:SetPoint("CENTER", w, "CENTER", 0, 0)
        -- Growth-direction indicator: arrows point the way the energy is moving.
        local arrowsL = (dir == "moon") and "<<<  " or ""
        local arrowsR = (dir == "sun")  and "  >>>" or ""
        local label = (RB.db.profile.secText == "none") and "" or tostring(cur)
        w.bar.text:SetText(arrowsL .. label .. arrowsR)
    end
end

-- ---------------------------------------------------------------------------
--  Secondary resource (re)resolution on spec / form change
-- ---------------------------------------------------------------------------
function RB:RefreshSecondary()
    self._sec = SecondaryResource()
    self:Relayout()
    self:UpdateSecondary()
end

-- ---------------------------------------------------------------------------
--  Cast bar
-- ---------------------------------------------------------------------------
-- Cast/channel info, nil-safe with the Classic-native fallback. Some clients
-- expose only CastingInfo()/ChannelInfo() (no unit arg); both share the modern
-- return layout: name, text, texture, startTimeMS, endTimeMS, isTradeSkill, ...
local function CastInfo()
    if UnitCastingInfo then return UnitCastingInfo("player") end
    if CastingInfo then return CastingInfo() end
end
local function ChanInfo()
    if UnitChannelInfo then return UnitChannelInfo("player") end
    if ChannelInfo then return ChannelInfo() end
end

local function StopCast()
    if not castFrame then return end
    castFrame:SetScript("OnUpdate", nil)
    castFrame:Hide()
end

local function CastOnUpdate(self)
    local now = GetTime()
    local dur = self._stop - self._start
    if dur <= 0 or now >= self._stop then StopCast(); return end
    local frac = (now - self._start) / dur
    if self._channel then frac = 1 - frac end
    self:SetValue(frac < 0 and 0 or frac > 1 and 1 or frac)
    self.time:SetText(string.format("%.1f", self._stop - now))
end

local function StartCast(channel)
    if not (castFrame and RB.db.profile.showCast) then return end
    local name, text, texture, startMs, endMs, notInterruptible
    if channel then
        name, text, texture, startMs, endMs, _, notInterruptible = ChanInfo()
    else
        name, text, texture, startMs, endMs, _, _, notInterruptible = CastInfo()
    end
    if not name or not startMs or not endMs then StopCast(); return end

    castFrame._start, castFrame._stop, castFrame._channel = startMs / 1000, endMs / 1000, channel
    castFrame.icon:SetTexture(texture)
    castFrame.name:SetText(text or name)
    if notInterruptible then
        castFrame:SetStatusBarColor(0.55, 0.55, 0.55)
    else
        castFrame:SetStatusBarColor(OUI.ACCENT.r, OUI.ACCENT.g, OUI.ACCENT.b)
    end
    castFrame:SetMinMaxValues(0, 1)
    castFrame:Show()
    castFrame:SetScript("OnUpdate", CastOnUpdate)
end

-- Only stop when nothing is actually casting/channelling (avoids a stray STOP
-- for a previous cast hiding a freshly started one).
local function MaybeStopCast()
    if not CastInfo() and not ChanInfo() then
        StopCast()
    end
end

function RB:UNIT_SPELLCAST_START(_, unit)          if unit == "player" then StartCast(false) end end
function RB:UNIT_SPELLCAST_DELAYED(_, unit)        if unit == "player" then StartCast(false) end end
function RB:UNIT_SPELLCAST_CHANNEL_START(_, unit)  if unit == "player" then StartCast(true) end end
function RB:UNIT_SPELLCAST_CHANNEL_UPDATE(_, unit) if unit == "player" then StartCast(true) end end
function RB:UNIT_SPELLCAST_STOP(_, unit)           if unit == "player" then MaybeStopCast() end end
function RB:UNIT_SPELLCAST_CHANNEL_STOP(_, unit)   if unit == "player" then MaybeStopCast() end end
function RB:UNIT_SPELLCAST_INTERRUPTED(_, unit)    if unit == "player" then StopCast() end end
function RB:UNIT_SPELLCAST_FAILED(_, unit)         if unit == "player" then MaybeStopCast() end end

-- ---------------------------------------------------------------------------
--  Movable container (own drag; lock state persisted)
-- ---------------------------------------------------------------------------
function RB:SetLocked(locked)
    RB.db.profile.locked = locked
    RB:UpdateCombatFade()
    if not container then return end
    if locked then
        container:EnableMouse(false)
        container:SetScript("OnDragStart", nil)
        container:SetScript("OnDragStop", nil)
        if container._dragHint then container._dragHint:Hide() end
    else
        container:EnableMouse(true)
        container:RegisterForDrag("LeftButton")
        container:SetMovable(true)
        container:SetScript("OnDragStart", function(f) f:StartMoving() end)
        container:SetScript("OnDragStop", function(f)
            f:StopMovingOrSizing()
            local p = RB.db.profile
            local point, _, _, x, y = f:GetPoint()
            p.point, p.x, p.y = point, math.floor(x + 0.5), math.floor(y + 0.5)
        end)
        if not container._dragHint then
            local h = container:CreateTexture(nil, "BACKGROUND")
            h:SetAllPoints(container); h:SetTexture(WHITE)
            h:SetVertexColor(OUI.ACCENT.r, OUI.ACCENT.g, OUI.ACCENT.b, 0.20)
            container._dragHint = h
        end
        container._dragHint:Show()
    end
end

-- ---------------------------------------------------------------------------
--  Lifecycle
-- ---------------------------------------------------------------------------
function RB:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("OldschoolUIResourceBarsDB", defaults, true)
    ns.db = self.db
end

function RB:ApplyTextures()
    if healthBar then healthBar:SetStatusBarTexture(BarTex("Health")) end
    if powerBar  then powerBar:SetStatusBarTexture(BarTex("Power")) end
    if secWidget and secWidget.bar then secWidget.bar:SetStatusBarTexture(BarTex("Secondary")) end
    if castFrame then castFrame:SetStatusBarTexture(BarTex("Cast")) end
end

-- 1px+ border around every bar, colour/size resolved via the 3-tier model.
-- Borders anchor to frame corners so they track size automatically.
function RB:ApplySkin()
    local function style(f, which)
        if not (f and OUI.PP and OUI.PP.CreateBorder) then return end
        OUI.PP.CreateBorder(f, 0, 0, 0, 0.9)
        local c, n = BorderStyle(which)
        c = c or { 0, 0, 0, 0.9 }
        if OUI.PP.SetBorderColor then OUI.PP.SetBorderColor(f, c[1], c[2], c[3], c[4] or 1) end
        if OUI.PP.SetBorderSize  then OUI.PP.SetBorderSize(f, n or 1) end
    end
    style(healthBar, "Health"); style(powerBar, "Power"); style(castFrame, "Cast")
    if secWidget then style(secWidget.bar, "Secondary") end
end

-- Hide the default Blizzard player cast bar while our own cast bar is enabled.
-- Reversible: the OnShow hook only hides when showCast is on, so disabling our
-- cast bar lets Blizzard's reappear on the next cast.
function RB:ApplyBlizzCast()
    local f = _G.CastingBarFrame or _G.PlayerCastingBarFrame
    if not f then return end
    if not f._ouiHook then
        f._ouiHook = true
        f:HookScript("OnShow", function(self)
            if RB.db and RB.db.profile.showCast then self:Hide() end
        end)
    end
    if RB.db and RB.db.profile.showCast and f:IsShown() then f:Hide() end
end

-- Dim the whole stack out of combat when enabled; always full while unlocked.
function RB:UpdateCombatFade()
    if not container then return end
    local p = RB.db.profile
    if not p.locked then container:SetAlpha(1); return end
    if not p.combatFade then container:SetAlpha(1); return end
    local inCombat = UnitAffectingCombat and UnitAffectingCombat("player")
    if InCombatLockdown and InCombatLockdown() then inCombat = true end
    container:SetAlpha(inCombat and 1 or ((p.fadeAlpha or 25) / 100))
end

function RB:RefreshAll()
    self:UpdateHealth()
    self:UpdatePower()
    self:UpdateSecondary()
end

function RB:OnEnable()
    if OUI.IsModuleEnabled and not OUI:IsModuleEnabled("OUI_ResourceBars") then return end
    Build()
    self:RefreshSecondary()
    self:SetLocked(self.db.profile.locked)
    self:ApplyBlizzCast()
    if OUI.RegisterStyleListener then
        OUI.RegisterStyleListener(function()
            RB:ApplyTextures(); RB:ApplySkin(); RB:RefreshAll()
        end)
    elseif OUI.RegisterBarTextureListener then
        OUI.RegisterBarTextureListener(function()
            RB:ApplyTextures(); RB:ApplySkin(); RB:RefreshAll()
        end)
    end

    self:RegisterEvent("PLAYER_ENTERING_WORLD", "RefreshAll")
    self:RegisterEvent("UNIT_HEALTH")
    self:RegisterEvent("UNIT_MAXHEALTH")
    self:RegisterEvent("UNIT_POWER_FREQUENT")
    self:RegisterEvent("UNIT_POWER_UPDATE")
    self:RegisterEvent("UNIT_MAXPOWER")
    self:RegisterEvent("UNIT_DISPLAYPOWER")
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "RefreshSecondary")
    self:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED", "RefreshSecondary")
    self:RegisterEvent("UPDATE_SHAPESHIFT_FORM", "UpdateSecondary")
    self:RegisterEvent("RUNE_POWER_UPDATE", "UpdateSecondary")
    self:RegisterEvent("RUNE_TYPE_UPDATE", "UpdateSecondary")

    self:RegisterEvent("UNIT_SPELLCAST_START")
    self:RegisterEvent("UNIT_SPELLCAST_DELAYED")
    self:RegisterEvent("UNIT_SPELLCAST_STOP")
    self:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
    self:RegisterEvent("UNIT_SPELLCAST_FAILED")
    self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
    self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_UPDATE")
    self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")

    self:RegisterEvent("PLAYER_REGEN_DISABLED", "UpdateCombatFade")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "UpdateCombatFade")

    self:RefreshAll()
    self:UpdateCombatFade()
end

-- AceEvent dispatches as self:EVENT(event, unit, ...); filter to the player.
function RB:UNIT_HEALTH(_, unit)       if unit == "player" then self:UpdateHealth() end end
function RB:UNIT_MAXHEALTH(_, unit)    if unit == "player" then self:UpdateHealth() end end
function RB:UNIT_POWER_FREQUENT(_, unit) if unit == "player" then self:UpdatePower(); self:UpdateSecondary() end end
function RB:UNIT_POWER_UPDATE(_, unit) if unit == "player" then self:UpdatePower(); self:UpdateSecondary() end end
function RB:UNIT_MAXPOWER(_, unit)     if unit == "player" then self:UpdatePower(); self:UpdateSecondary() end end
function RB:UNIT_DISPLAYPOWER(_, unit) if unit == "player" then self:UpdatePower() end end

-- ---------------------------------------------------------------------------
--  Slash: lock / unlock for positioning
-- ---------------------------------------------------------------------------
SLASH_OUIRB1 = "/ouirb"
SlashCmdList["OUIRB"] = function(msg)
    msg = (msg or ""):lower():gsub("%s+", "")
    if msg == "unlock" then RB:SetLocked(false); print("|cffd9a441[OUI ResourceBars]|r unlocked — drag to move, /ouirb lock when done.")
    elseif msg == "lock" then RB:SetLocked(true); print("|cffd9a441[OUI ResourceBars]|r locked.")
    elseif msg == "test" then
        if castFrame then
            castFrame._start, castFrame._stop, castFrame._channel = GetTime(), GetTime() + 3, false
            castFrame.icon:SetTexture("Interface\\Icons\\Spell_Arcane_StarFire")
            castFrame.name:SetText("Test Cast")
            castFrame:SetStatusBarColor(OUI.ACCENT.r, OUI.ACCENT.g, OUI.ACCENT.b)
            castFrame:SetMinMaxValues(0, 1)
            castFrame:Show()
            castFrame:SetScript("OnUpdate", CastOnUpdate)
            print("|cffd9a441[OUI ResourceBars]|r test cast (3s) — if you DON'T see a bar below the stack, the frame itself is hidden.")
        else
            print("|cffd9a441[OUI ResourceBars]|r castFrame is nil — cast bar was not built.")
        end
    else RB:SetLocked(not RB.db.profile.locked); print("|cffd9a441[OUI ResourceBars]|r " .. (RB.db.profile.locked and "locked." or "unlocked — drag to move.")) end
end

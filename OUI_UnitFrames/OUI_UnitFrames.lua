-- ===========================================================================
--  OldschoolUI -- Unit Frames
--  Clean-room implementation (written from scratch for MoP Classic 5.5.x).
--
--  UF1: bootstrap, a generic secure unit-frame factory, and the single-unit
--  frames (player, target, focus, pet, target-of-target, focus-target).
--  Each frame is a SecureUnitButton (left-click targets, right-click menu),
--  shown/hidden by RegisterUnitWatch, with a health bar, an optional power
--  bar, a name and a value/percent readout. Cast bars, portraits, auras and
--  boss frames arrive in later stages. Built on Core helpers (fonts, power /
--  class colours, bar textures, pixel borders, the shared mover).
-- ===========================================================================
local ADDON, ns = ...
local UF  = LibStub("AceAddon-3.0"):NewAddon("OldschoolUIUnitFrames", "AceEvent-3.0")
local OUI = OldschoolUI
ns.UF = UF

local WHITE = "Interface\\Buttons\\WHITE8X8"

-- ---------------------------------------------------------------------------
--  Unit model. defX/defY are starting positions relative to the screen centre.
-- ---------------------------------------------------------------------------
local UNITS = {
    { key = "player",       unit = "player",       label = "Player",            w = 181, h = 46, power = 6, defX = -260, defY = -180, cast = true, threat = true, auras = true, portrait = true },
    { key = "target",       unit = "target",       label = "Target",            w = 181, h = 46, power = 6, defX =  260, defY = -180, targetChange = true, cast = true, threat = true, auras = true, portrait = true },
    { key = "focus",        unit = "focus",        label = "Focus",             w = 181, h = 46, power = 6, defX = -430, defY = -110, focusChange = true, cast = true, threat = true, auras = true, portrait = true },
    { key = "pet",          unit = "pet",          label = "Pet",               w = 101, h = 25, power = 6, defX = -260, defY = -232, cast = true, threat = true, auras = true, portrait = true },
    { key = "targettarget", unit = "targettarget", label = "Target of Target",  w = 101, h = 25, power = 0, defX =  430, defY = -110, poll = true },
    { key = "focustarget",  unit = "focustarget",  label = "Focus Target",      w = 101, h = 25, power = 0, defX = -430, defY = -158, poll = true },
}

-- boss1-5: own movable frames, stacked on the right by default, auto show/hide
for i = 1, 5 do
    UNITS[#UNITS + 1] = {
        key = "boss" .. i, unit = "boss" .. i, label = "Boss " .. i,
        w = 160, h = 34, power = 6, defX = 420, defY = 150 - (i - 1) * 52,
        cast = true, threat = true, auras = true, portrait = true, boss = true,
    }
end
ns.UNITS = UNITS

local UNIT_BY_KEY = {}
for _, u in ipairs(UNITS) do UNIT_BY_KEY[u.key] = u end
ns.UNIT_BY_KEY = UNIT_BY_KEY

-- ---------------------------------------------------------------------------
--  Saved settings
-- ---------------------------------------------------------------------------
local function defaultUnits()
    local t = {}
    for _, u in ipairs(UNITS) do
        t[u.key] = {
            enabled      = true,
            x            = u.defX,
            y            = u.defY,
            width        = u.w,
            healthHeight = u.h,
            powerHeight  = (u.power > 0) and 6 or 0,
            scale        = 1.0,
            healthText   = "percent",   -- value | percent | both | none
            powerText    = "none",
            showCast     = true,
            castHeight   = 14,
            showRaidIcon = true,
            showThreat   = true,
            rangeFade    = false,
            fadeAlpha    = 0.45,
            showBuffs    = true,
            showDebuffs  = true,
            auraSize     = 22,
            auraPerRow   = 8,
            auraRows     = 1,
            auraGrow     = "DOWN",   -- DOWN | UP
            auraShowCount = true,
            hideAuraTime = false,
            auraAnchor   = "BELOW",  -- BELOW | ABOVE
            auraOffset   = 4,
            portraitSize = 0,        -- 0 = off
            portraitSide = "LEFT",   -- LEFT | RIGHT
            portrait3D   = false,
        }
    end
    return t
end

local defaults = {
    profile = {
        units = defaultUnits(),
        hideBlizzard = true,
    },
}

-- ---------------------------------------------------------------------------
--  Colours / textures
-- ---------------------------------------------------------------------------
local function BarTex()
    return (OUI.GetBarTexturePath and OUI.GetBarTexturePath(nil)) or WHITE
end

function UF:HealthColor(u)
    if UnitIsPlayer(u) then
        local _, class = UnitClass(u)
        return OUI.GetClassColor(class)
    end
    local react = UnitReaction(u, "player")
    local c = react and FACTION_BAR_COLORS and FACTION_BAR_COLORS[react]
    if c then return c.r, c.g, c.b end
    local g = OUI.GREEN or { r = 0.25, g = 0.75, b = 0.30 }
    return g.r, g.g, g.b
end

local function FmtValue(cur, max, mode)
    if mode == "none" then return "" end
    if not max or max <= 0 then return "" end
    if mode == "value" then
        return AbbreviateNumbers and AbbreviateNumbers(cur) or tostring(cur)
    elseif mode == "both" then
        local v = AbbreviateNumbers and AbbreviateNumbers(cur) or tostring(cur)
        return ("%s  %d%%"):format(v, math.floor(cur / max * 100 + 0.5))
    end
    return ("%d%%"):format(math.floor(cur / max * 100 + 0.5))   -- percent
end

-- ---------------------------------------------------------------------------
--  Cast bar helpers. UnitCastingInfo may be nil on some 5.5.x builds, so we
--  fall back to the no-arg player-only CastingInfo/ChannelInfo for the player.
-- ---------------------------------------------------------------------------
local function CastInfo(u)
    if UnitCastingInfo then return UnitCastingInfo(u) end
    if u == "player" and CastingInfo then return CastingInfo() end
end
local function ChanInfo(u)
    if UnitChannelInfo then return UnitChannelInfo(u) end
    if u == "player" and ChannelInfo then return ChannelInfo() end
end

local function CastOnUpdate(self)
    local now = GetTime()
    local dur = self._stop - self._start
    if dur <= 0 or now >= self._stop then self:SetScript("OnUpdate", nil); self:Hide(); return end
    local frac = (now - self._start) / dur
    if self._channel then frac = 1 - frac end
    self:SetValue(frac < 0 and 0 or (frac > 1 and 1 or frac))
    self.time:SetText(("%.1f"):format(self._stop - now))
end

-- ---------------------------------------------------------------------------
--  Aura helpers. Prefer the modern C_UnitAuras API, fall back to UnitAura.
--  Returns a normalised tuple: name, icon, count, debuffType, duration, expiration.
-- ---------------------------------------------------------------------------
local function GetAura(unit, index, filter)
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local d = C_UnitAuras.GetAuraDataByIndex(unit, index, filter)
        if not d then return nil end
        return d.name, d.icon, d.applications, d.dispelName, d.duration, d.expirationTime
    end
    if UnitAura then
        local name, icon, count, dtype, duration, expiration = UnitAura(unit, index, filter)
        return name, icon, count, dtype, duration, expiration
    end
end

local function MakeAuraIcon(parent, font)
    local b = CreateFrame("Frame", nil, parent)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints(b); b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints(b); b.cd:SetDrawEdge(false)
    b.count = b:CreateFontString(nil, "OVERLAY")
    b.count:SetFont(font, 10, "OUTLINE")
    b.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 1, 0)
    if OUI.PP and OUI.PP.CreateBorder then OUI.PP.CreateBorder(b, 0, 0, 0, 0.9) end
    return b
end

-- ---------------------------------------------------------------------------
--  Updates
-- ---------------------------------------------------------------------------
function UF:UpdateHealth(f)
    local u = f.unit
    if not UnitExists(u) then return end
    local cur, max = UnitHealth(u), UnitHealthMax(u)
    f.health:SetMinMaxValues(0, (max and max > 0) and max or 1)
    f.health:SetValue(cur or 0)
    f.health:SetStatusBarColor(self:HealthColor(u))
    if f.healthText then
        local cfg = self.db.profile.units[f.unitKey]
        f.healthText:SetText(FmtValue(cur or 0, max or 0, cfg.healthText or "percent"))
    end
end

function UF:UpdatePower(f)
    if not f.power then return end
    local u = f.unit
    if not UnitExists(u) then return end
    local cur, max = UnitPower(u), UnitPowerMax(u)
    f.power:SetMinMaxValues(0, (max and max > 0) and max or 1)
    f.power:SetValue(cur or 0)
    local _, token = UnitPowerType(u)
    local c = token and OUI.GetPowerColor and OUI.GetPowerColor(token)
    if c then f.power:SetStatusBarColor(c.r or c[1], c.g or c[2], c.b or c[3])
    else f.power:SetStatusBarColor(0.3, 0.4, 0.9) end
end

function UF:UpdateName(f)
    if not f.nameText then return end
    local u = f.unit
    f.nameText:SetText(UnitExists(u) and (UnitName(u) or "") or "")
end

function UF:UpdateRaidTarget(f)
    if not f.raidIcon then return end
    local cfg = self.db.profile.units[f.unitKey]
    local idx = (cfg.showRaidIcon ~= false) and UnitExists(f.unit) and GetRaidTargetIndex(f.unit) or nil
    if idx and SetRaidTargetIconTexture then
        SetRaidTargetIconTexture(f.raidIcon, idx)
        f.raidIcon:Show()
    else
        f.raidIcon:Hide()
    end
end

-- the threat status that matters for this frame: for target/focus it's whether
-- the PLAYER holds aggro on that unit; for player/pet it's their own status.
local function ThreatStatus(key, unit)
    if key == "target" or key == "focus" then
        return UnitThreatSituation("player", unit)
    end
    return UnitThreatSituation(unit)
end

function UF:UpdateThreat(f)
    if not (f._threat and OUI.PP and OUI.PP.SetBorderColor) then return end
    local cfg = self.db.profile.units[f.unitKey]
    local status = (cfg.showThreat ~= false) and UnitExists(f.unit) and ThreatStatus(f.unitKey, f.unit) or nil
    if status and status > 0 then
        local r, g, b = GetThreatStatusColor(status)
        OUI.PP.SetBorderColor(f, r, g, b, 1)
    else
        OUI.PP.SetBorderColor(f, 0, 0, 0, 0.9)
    end
end

function UF:UpdateAuras(f, group)
    if not group then return end
    local cfg = self.db.profile.units[f.unitKey]
    local on  = (group.filter == "HELPFUL") and cfg.showBuffs or cfg.showDebuffs
    if not on or not UnitExists(f.unit) then
        for _, b in ipairs(group.pool) do b:Hide() end
        group:Hide(); return 0
    end
    group:Show()
    local size = cfg.auraSize or 22
    local per  = cfg.auraPerRow or 8
    local max  = per * (cfg.auraRows or 1)
    local font = self._font or STANDARD_TEXT_FONT
    local shown, i = 0, 1
    local above = (cfg.auraAnchor == "ABOVE")
    while shown < max do
        local name, icon, count, dtype, duration, expiration = GetAura(f.unit, i, group.filter)
        if not name then break end
        shown = shown + 1
        local b = group.pool[shown]
        if not b then b = MakeAuraIcon(group, font); group.pool[shown] = b end
        b:SetSize(size, size)
        b.icon:SetTexture(icon)
        if cfg.auraShowCount ~= false and count and count > 1 then
            b.count:SetFont(font, math.max(7, math.floor(size * 0.42)), "OUTLINE")
            b.count:SetText(count); b.count:Show()
        else
            b.count:SetText(""); b.count:Hide()
        end
        if duration and duration > 0 and expiration and expiration > 0 then
            b.cd:SetCooldown(expiration - duration, duration); b.cd:Show()
            if b.cd.SetHideCountdownNumbers then
                b.cd:SetHideCountdownNumbers(cfg.hideAuraTime and true or false)
            end
        else
            b.cd:Hide()
        end
        if group.filter == "HARMFUL" and OUI.PP and OUI.PP.SetBorderColor then
            local c = DebuffTypeColor and DebuffTypeColor[dtype or "none"]
            if c then OUI.PP.SetBorderColor(b, c.r, c.g, c.b, 1)
            else OUI.PP.SetBorderColor(b, 0, 0, 0, 0.9) end
        end
        local col = (shown - 1) % per
        local row = math.floor((shown - 1) / per)
        b:ClearAllPoints()
        if above then
            b:SetPoint("BOTTOMLEFT", group, "BOTTOMLEFT", col * (size + 2), row * (size + 2))
        else
            b:SetPoint("TOPLEFT", group, "TOPLEFT", col * (size + 2), -row * (size + 2))
        end
        b:Show()
        i = i + 1
    end
    for j = shown + 1, #group.pool do group.pool[j]:Hide() end
    return math.ceil(shown / per)
end

-- update both aura groups and anchor them to the actual rows used, so an empty
-- debuff row never pushes the buff row down.
function UF:LayoutAuras(f)
    if not f.debuffs then return end
    local cfg  = self.db.profile.units[f.unitKey]
    local size = cfg.auraSize or 22
    local off  = cfg.auraOffset or 4
    local dRows = self:UpdateAuras(f, f.debuffs)
    self:UpdateAuras(f, f.buffs)
    local dH = dRows * (size + 2)
    f.debuffs:ClearAllPoints(); f.buffs:ClearAllPoints()
    if cfg.auraAnchor == "ABOVE" then
        f.debuffs:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, off)
        f.buffs:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, off + (dRows > 0 and (dH + 4) or 0))
    else
        f.debuffs:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -off)
        f.buffs:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -off - (dRows > 0 and (dH + 4) or 0))
    end
end

function UF:UpdatePortrait(f)
    if not f.portrait then return end
    local cfg = self.db.profile.units[f.unitKey]
    if (cfg.portraitSize or 0) > 0 and UnitExists(f.unit) then
        local p = f.portrait
        if cfg.portrait3D and p.model.SetUnit then
            p.model:SetUnit(f.unit)
            if p.model.SetPortraitZoom then p.model:SetPortraitZoom(1) end
            p.model:Show(); p.tex:Hide()
        else
            SetPortraitTexture(p.tex, f.unit)
            p.tex:Show(); p.model:Hide()
        end
        p:Show()
    else
        f.portrait:Hide()
    end
end

function UF:UpdateAll(f)
    if not UnitExists(f.unit) then return end
    self:UpdateHealth(f)
    self:UpdatePower(f)
    self:UpdateName(f)
    self:UpdateRaidTarget(f)
    self:UpdateThreat(f)
    self:UpdatePortrait(f)
    if f.debuffs then self:LayoutAuras(f) end
    if f.castbar then self:RefreshCast(f) end
end

-- start/refresh/stop the cast bar for a frame's unit
function UF:StartCast(f, channel)
    local cb = f.castbar
    if not cb then return end
    local cfg = self.db.profile.units[f.unitKey]
    if not (cfg and cfg.showCast) then cb:Hide(); return end
    local u = f.unit
    local name, text, texture, startMs, endMs, notInterruptible
    if channel then
        name, text, texture, startMs, endMs, _, notInterruptible = ChanInfo(u)
    else
        name, text, texture, startMs, endMs, _, _, notInterruptible = CastInfo(u)
    end
    if not name or not startMs or not endMs then cb:SetScript("OnUpdate", nil); cb:Hide(); return end
    cb._start, cb._stop, cb._channel = startMs / 1000, endMs / 1000, channel
    cb.icon:SetTexture(texture)
    cb.name:SetText(text or name)
    if notInterruptible then
        cb:SetStatusBarColor(0.55, 0.55, 0.55)
    else
        cb:SetStatusBarColor(OUI.ACCENT.r, OUI.ACCENT.g, OUI.ACCENT.b)
    end
    cb:SetMinMaxValues(0, 1)
    cb:Show()
    cb:SetScript("OnUpdate", CastOnUpdate)
end

-- only hide if nothing is actually casting (avoids a stray STOP for an old cast
-- hiding a freshly started one)
function UF:MaybeStopCast(f)
    local u = f.unit
    if not CastInfo(u) and not ChanInfo(u) then
        local cb = f.castbar
        if cb then cb:SetScript("OnUpdate", nil); cb:Hide() end
    end
end

-- re-evaluate cast state from scratch (used on target/focus swap)
function UF:RefreshCast(f)
    local u = f.unit
    if CastInfo(u) then self:StartCast(f, false)
    elseif ChanInfo(u) then self:StartCast(f, true)
    else local cb = f.castbar; if cb then cb:SetScript("OnUpdate", nil); cb:Hide() end end
end

-- ---------------------------------------------------------------------------
--  Frame factory
-- ---------------------------------------------------------------------------
function UF:BuildUnit(info)
    if self.frames[info.key] then return self.frames[info.key] end
    local f = CreateFrame("Button", "OUIUnitFrame_" .. info.key, UIParent, "SecureUnitButtonTemplate")
    self.frames[info.key] = f
    f.unitKey = info.key
    f.unit    = info.unit

    -- secure click behaviour + auto show/hide on unit existence
    f:SetAttribute("unit", info.unit)
    f:SetAttribute("*type1", "target")
    f:SetAttribute("*type2", "togglemenu")
    f:RegisterForClicks("AnyUp")
    RegisterUnitWatch(f)

    -- health bar
    local hb = CreateFrame("StatusBar", nil, f)
    hb:SetStatusBarTexture(BarTex())
    f.health = hb
    local bg = hb:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(hb); bg:SetTexture(WHITE); bg:SetVertexColor(0.12, 0.12, 0.12, 0.85)

    local font = (OUI.GetFontPath and OUI.GetFontPath()) or STANDARD_TEXT_FONT
    f.healthText = hb:CreateFontString(nil, "OVERLAY")
    f.healthText:SetFont(font, 11, "OUTLINE")
    f.healthText:SetPoint("RIGHT", hb, "RIGHT", -4, 0)
    f.healthText:SetJustifyH("RIGHT")
    f.nameText = hb:CreateFontString(nil, "OVERLAY")
    f.nameText:SetFont(font, 11, "OUTLINE")
    f.nameText:SetJustifyH("LEFT")
    if f.nameText.SetWordWrap then f.nameText:SetWordWrap(false) end  -- single line, truncates with "..."
    f.nameText:SetPoint("LEFT", hb, "LEFT", 4, 0)
    f.nameText:SetPoint("RIGHT", f.healthText, "LEFT", -4, 0)  -- stop before the readout

    -- power bar (optional)
    if info.power > 0 then
        local pb = CreateFrame("StatusBar", nil, f)
        pb:SetStatusBarTexture(BarTex())
        f.power = pb
        local pbg = pb:CreateTexture(nil, "BACKGROUND")
        pbg:SetAllPoints(pb); pbg:SetTexture(WHITE); pbg:SetVertexColor(0.12, 0.12, 0.12, 0.85)
    end

    if OUI.PP and OUI.PP.CreateBorder then OUI.PP.CreateBorder(f, 0, 0, 0, 0.9) end

    -- raid target marker (skull / cross / ...): top-centre of the health bar
    f.raidIcon = hb:CreateTexture(nil, "OVERLAY")
    f.raidIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    f.raidIcon:SetSize(16, 16)
    f.raidIcon:SetPoint("TOP", hb, "TOP", 0, 8)
    f.raidIcon:Hide()
    f._threat = info.threat and true or false

    -- portrait (2D), shown to the left of the frame when sized > 0
    if info.portrait then
        local p = CreateFrame("Frame", nil, f)
        p.tex = p:CreateTexture(nil, "ARTWORK")
        p.tex:SetAllPoints(p); p.tex:SetTexCoord(0.1, 0.9, 0.1, 0.9)
        p.model = CreateFrame("PlayerModel", nil, p)
        p.model:SetAllPoints(p)
        p.model:Hide()
        if OUI.PP and OUI.PP.CreateBorder then OUI.PP.CreateBorder(p, 0, 0, 0, 0.9) end
        p:Hide()
        f.portrait = p
    end

    -- aura groups (buffs + debuffs): plain anchor frames holding icon pools
    if info.auras then
        f.debuffs = CreateFrame("Frame", nil, f); f.debuffs.filter = "HARMFUL"; f.debuffs.pool = {}
        f.buffs   = CreateFrame("Frame", nil, f); f.buffs.filter   = "HELPFUL"; f.buffs.pool   = {}
    end

    -- cast bar (optional) -- a child below the frame, shown only while casting
    if info.cast then
        local cb = CreateFrame("StatusBar", nil, f)
        cb:SetStatusBarTexture(BarTex())
        f.castbar = cb
        local cbg = cb:CreateTexture(nil, "BACKGROUND")
        cbg:SetAllPoints(cb); cbg:SetTexture(WHITE); cbg:SetVertexColor(0, 0, 0, 0.7)
        cb.icon = cb:CreateTexture(nil, "ARTWORK")
        cb.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        cb.name = cb:CreateFontString(nil, "OVERLAY")
        cb.name:SetFont(font, 10, "OUTLINE"); cb.name:SetJustifyH("LEFT")
        cb.name:SetPoint("LEFT", cb, "LEFT", 4, 0)
        cb.name:SetPoint("RIGHT", cb, "RIGHT", -34, 0)
        cb.time = cb:CreateFontString(nil, "OVERLAY")
        cb.time:SetFont(font, 10, "OUTLINE"); cb.time:SetJustifyH("RIGHT")
        cb.time:SetPoint("RIGHT", cb, "RIGHT", -3, 0)
        if OUI.PP and OUI.PP.CreateBorder then OUI.PP.CreateBorder(cb, 0, 0, 0, 0.9) end
        cb:Hide()
    end

    -- events
    f:SetScript("OnEvent", function(self2, event)
        if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_TARGET_CHANGED"
           or event == "PLAYER_FOCUS_CHANGED" or event == "UNIT_PET" then
            UF:UpdateAll(self2)
        elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
            UF:UpdateHealth(self2)
        elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER" then
            UF:UpdatePower(self2)
        elseif event == "UNIT_NAME_UPDATE" then
            UF:UpdateName(self2)
        elseif event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_DELAYED" then
            UF:StartCast(self2, false)
        elseif event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
            UF:StartCast(self2, true)
        elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP"
            or event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED" then
            UF:MaybeStopCast(self2)
        elseif event == "UNIT_PORTRAIT_UPDATE" or event == "UNIT_MODEL_CHANGED" then
            UF:UpdatePortrait(self2)
        elseif event == "UNIT_AURA" then
            if self2.debuffs then UF:LayoutAuras(self2) end
        elseif event == "RAID_TARGET_UPDATE" then
            UF:UpdateRaidTarget(self2)
        elseif event == "UNIT_THREAT_SITUATION_UPDATE" or event == "UNIT_THREAT_LIST_UPDATE" then
            UF:UpdateThreat(self2)
        else
            UF:UpdateAll(self2)
        end
    end)
    f:RegisterUnitEvent("UNIT_HEALTH", info.unit)
    f:RegisterUnitEvent("UNIT_MAXHEALTH", info.unit)
    f:RegisterUnitEvent("UNIT_NAME_UPDATE", info.unit)
    if info.power > 0 then
        f:RegisterUnitEvent("UNIT_POWER_UPDATE", info.unit)
        f:RegisterUnitEvent("UNIT_MAXPOWER", info.unit)
        f:RegisterUnitEvent("UNIT_DISPLAYPOWER", info.unit)
    end
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("RAID_TARGET_UPDATE")
    if info.threat then
        f:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
        f:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
    end
    if info.auras then f:RegisterUnitEvent("UNIT_AURA", info.unit) end
    if info.portrait then
        f:RegisterUnitEvent("UNIT_PORTRAIT_UPDATE", info.unit)
        f:RegisterUnitEvent("UNIT_MODEL_CHANGED", info.unit)
    end
    if info.boss then f:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT") end
    if info.targetChange then f:RegisterEvent("PLAYER_TARGET_CHANGED") end
    if info.focusChange  then f:RegisterEvent("PLAYER_FOCUS_CHANGED")  end
    if info.key == "pet" then f:RegisterEvent("UNIT_PET") end
    if info.cast then
        for _, e in ipairs({
            "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_STOP",
            "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED",
            "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP",
        }) do
            f:RegisterUnitEvent(e, info.unit)
        end
    end

    -- derived units (tot/fot) get no reliable events: poll lightly
    if info.poll then
        f.pollT = 0
        f:SetScript("OnUpdate", function(self2, dt)
            self2.pollT = self2.pollT + dt
            if self2.pollT < 0.25 then return end
            self2.pollT = 0
            if UnitExists(self2.unit) then UF:UpdateAll(self2) end
        end)
    end

    return f
end

-- ---------------------------------------------------------------------------
--  Layout / apply
-- ---------------------------------------------------------------------------
function UF:ApplyUnit(key)
    local info = UNIT_BY_KEY[key]
    if not info then return end
    -- The unit frame is a SecureUnitButtonTemplate with RegisterUnitWatch, so
    -- building it (SetAttribute) and laying it out (SetSize/SetPoint/Show/
    -- Register/UnregisterUnitWatch) are all protected in combat. Defer to
    -- PLAYER_REGEN_ENABLED if we're locked down.
    if InCombatLockdown() then
        self._needApply = true
        return
    end
    local cfg = self.db.profile.units[key]
    local f = self:BuildUnit(info)

    local w  = cfg.width or info.w
    local hh = cfg.healthHeight or info.h
    local ph = cfg.powerHeight or 0
    if not f.power then ph = 0 end
    local total = hh + (ph > 0 and (ph + 1) or 0)

    f:SetSize(w, total)
    f:SetScale(cfg.scale or 1.0)
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", cfg.x or info.defX, cfg.y or info.defY)

    f.health:ClearAllPoints()
    f.health:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    f.health:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    f.health:SetHeight(hh)
    f.health:SetStatusBarTexture(BarTex())

    if f.power then
        if ph > 0 then
            f.power:Show()
            f.power:ClearAllPoints()
            f.power:SetPoint("TOPLEFT", f.health, "BOTTOMLEFT", 0, -1)
            f.power:SetPoint("TOPRIGHT", f.health, "BOTTOMRIGHT", 0, -1)
            f.power:SetHeight(ph)
            f.power:SetStatusBarTexture(BarTex())
        else
            f.power:Hide()
        end
    end

    if cfg.enabled then
        RegisterUnitWatch(f)
        self:UpdateAll(f)
    else
        UnregisterUnitWatch(f)
        f:Hide()
    end

    if not cfg.rangeFade then f:SetAlpha(1) end

    if f.portrait then
        local ps = cfg.portraitSize or 0
        if ps > 0 then
            f.portrait:SetSize(ps, ps)
            f.portrait:ClearAllPoints()
            if cfg.portraitSide == "RIGHT" then
                f.portrait:SetPoint("LEFT", f, "RIGHT", 3, 0)
            else
                f.portrait:SetPoint("RIGHT", f, "LEFT", -3, 0)
            end
        else
            f.portrait:Hide()
        end
    end

    if f.castbar then
        local ch = cfg.castHeight or 14
        f.castbar:ClearAllPoints()
        f.castbar:SetPoint("TOPLEFT", f, "BOTTOMLEFT", ch + 2, -3)
        f.castbar:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, -3)
        f.castbar:SetHeight(ch)
        f.castbar:SetStatusBarTexture(BarTex())
        f.castbar.icon:SetSize(ch, ch)
        f.castbar.icon:ClearAllPoints()
        f.castbar.icon:SetPoint("RIGHT", f.castbar, "LEFT", -2, 0)
    end

    if f.debuffs then
        local size = cfg.auraSize or 22
        local rows = cfg.auraRows or 1
        local per  = cfg.auraPerRow or 8
        f.debuffs:SetSize(per * (size + 2), rows * (size + 2))
        f.buffs:SetSize(per * (size + 2), rows * (size + 2))
        self:LayoutAuras(f)
    end
end

function UF:ApplyAll()
    for _, info in ipairs(UNITS) do self:ApplyUnit(info.key) end
end

-- ---------------------------------------------------------------------------
--  Test mode: force every enabled frame (incl. boss1-5) to show with
--  placeholder data so they can be positioned without a live target/encounter.
-- ---------------------------------------------------------------------------
function UF:FillTest(f, info)
    f.health:SetMinMaxValues(0, 100); f.health:SetValue(math.random(45, 95))
    f.health:SetStatusBarColor(0.25, 0.70, 0.35)
    if f.nameText then f.nameText:SetText(info.label) end
    if f.healthText then f.healthText:SetText("75%") end
    if f.power then
        f.power:SetMinMaxValues(0, 100); f.power:SetValue(math.random(30, 90))
        f.power:SetStatusBarColor(0.25, 0.40, 0.90)
    end
    if f.portrait and (self.db.profile.units[info.key].portraitSize or 0) > 0 then
        local cfg = self.db.profile.units[info.key]
        if cfg.portrait3D and f.portrait.model.SetUnit then
            f.portrait.model:SetUnit("player")
            if f.portrait.model.SetPortraitZoom then f.portrait.model:SetPortraitZoom(1) end
            f.portrait.model:Show(); f.portrait.tex:Hide()
        else
            SetPortraitTexture(f.portrait.tex, "player")
            f.portrait.tex:Show(); f.portrait.model:Hide()
        end
        f.portrait:Show()
    end
end

function UF:SetTestMode(on)
    if InCombatLockdown() then
        OUI:Print("|cffd9a441[OUI UnitFrames]|r test mode can't be toggled in combat.")
        return
    end
    self.testMode = on and true or false
    for _, info in ipairs(UNITS) do
        local f = self.frames[info.key]
        local cfg = self.db.profile.units[info.key]
        if f then
            if self.testMode and cfg.enabled then
                UnregisterUnitWatch(f)
                f:Show()
                self:FillTest(f, info)
            else
                if cfg.enabled then RegisterUnitWatch(f) else f:Hide() end
                if UnitExists(f.unit) then self:UpdateAll(f) end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
--  Shared mover: one draggable overlay per unit frame
-- ---------------------------------------------------------------------------
function UF:RegisterMovers()
    if not (OUI.RegisterUnlockElements and OUI.MakeUnlockElement) then return end
    local list = {}
    for _, info in ipairs(UNITS) do
        local key = info.key
        list[#list + 1] = OUI.MakeUnlockElement({
            key      = "OUIUnitFrame_" .. key,
            label    = info.label,
            getFrame = function() return UF.frames[key] end,
            getSize  = function()
                local f = UF.frames[key]
                if f then return f:GetSize() end
                return info.w, info.h
            end,
            isHidden = function() return not UF.db.profile.units[key].enabled end,
            savePos  = function(_, _, _, x, y)
                local c = UF.db.profile.units[key]
                c.x, c.y = x, y
                UF:ApplyUnit(key)
            end,
            applyPos = function() UF:ApplyUnit(key) end,
        })
    end
    OUI:RegisterUnlockElements(list)
end

-- ---------------------------------------------------------------------------
--  Lifecycle
-- ---------------------------------------------------------------------------
function UF:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("OldschoolUIUnitFramesDB", defaults, true)
    self.frames = {}
    self._font = (OUI.GetFontPath and OUI.GetFontPath()) or STANDARD_TEXT_FONT
end

-- range check: UnitInRange is authoritative for group/friendly units. For
-- everyone else it can't be determined without protected APIs (CheckInteractDistance
-- is forbidden), so we don't fade those. Returns true when in range or unknown.
local function UnitRange(unit)
    local inRange, checked = UnitInRange(unit)
    if checked then return inRange and true or false end
    return true
end

function UF:SetupRangeTicker()
    if self._rangeTicker then return end
    local t = CreateFrame("Frame"); self._rangeTicker = t; t.acc = 0
    t:SetScript("OnUpdate", function(_, dt)
        t.acc = t.acc + dt
        if t.acc < 0.2 then return end
        t.acc = 0
        if UF.testMode then return end
        for _, info in ipairs(UNITS) do
            local f = UF.frames[info.key]
            local cfg = UF.db.profile.units[info.key]
            if f and cfg.enabled and cfg.rangeFade and UnitExists(f.unit) then
                f:SetAlpha(UnitRange(f.unit) and 1 or (cfg.fadeAlpha or 0.45))
            end
        end
    end)
end

-- ---------------------------------------------------------------------------
--  Suppress the Blizzard default unit frames OUI replaces (taint-safe).
--  Unregister + Hide + keep-hidden OnShow hook; deferred out of combat.
-- ---------------------------------------------------------------------------
local BLIZZ_UNIT_FRAMES = {
    player = "PlayerFrame",
    target = "TargetFrame",
    focus  = "FocusFrame",
    pet    = "PetFrame",
}

local function killBlizzFrame(name)
    local f = _G[name]
    if not f then return end
    if not f._ouiKilled then
        f._ouiKilled = true
        if f.UnregisterAllEvents then f:UnregisterAllEvents() end
        f:HookScript("OnShow", function(s)
            if UF.db and UF.db.profile.hideBlizzard and not InCombatLockdown() then s:Hide() end
        end)
    end
    f:Hide()
end

function UF:HideBlizzardFrames()
    if InCombatLockdown() then
        self._needBlizzHide = true
        return
    end
    if not self.db.profile.hideBlizzard then return end
    for key, frameName in pairs(BLIZZ_UNIT_FRAMES) do
        local cfg = self.db.profile.units[key]
        if cfg and cfg.enabled then killBlizzFrame(frameName) end
    end
end

function UF:OnEnable()
    self:ApplyAll()
    self:HideBlizzardFrames()
    self:RegisterMovers()
    self:SetupRangeTicker()
    -- re-run any layout that was deferred because we were in combat
    if not self._combatWatcher then
        local cw = CreateFrame("Frame")
        self._combatWatcher = cw
        cw:RegisterEvent("PLAYER_REGEN_ENABLED")
        cw:RegisterEvent("PLAYER_ENTERING_WORLD")
        cw:SetScript("OnEvent", function()
            if UF._needApply then UF._needApply = nil; UF:ApplyAll() end
            if UF._needBlizzHide then UF._needBlizzHide = nil end
            UF:HideBlizzardFrames()
        end)
    end
    if OUI.RegisterStyleListener then
        OUI.RegisterStyleListener(function()
            for _, info in ipairs(UNITS) do
                local f = UF.frames[info.key]
                if f then
                    f.health:SetStatusBarTexture(BarTex())
                    if f.power then f.power:SetStatusBarTexture(BarTex()) end
                    if f.castbar then f.castbar:SetStatusBarTexture(BarTex()) end
                end
            end
        end)
    end
end

-- ---------------------------------------------------------------------------
--  Slash
-- ---------------------------------------------------------------------------
SLASH_OUIUF1 = "/ouiuf"
SlashCmdList["OUIUF"] = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, arg = msg:match("^(%S+)%s*(%S*)$")
    if cmd == "unlock" or cmd == "move" then
        if OUI.ToggleUnlock then OUI:ToggleUnlock(true) end
        OUI:Print("|cffd9a441[OUI UnitFrames]|r unlocked — drag the frames, /ouiuf lock when done.")
    elseif cmd == "lock" then
        if OUI.ToggleUnlock then OUI:ToggleUnlock(false) end
        OUI:Print("|cffd9a441[OUI UnitFrames]|r locked.")
    elseif cmd == "test" then
        UF:SetTestMode(not UF.testMode)
        OUI:Print("|cffd9a441[OUI UnitFrames]|r test mode " .. (UF.testMode and "ON" or "OFF") .. ".")
    elseif cmd == "enable" or cmd == "disable" then
        local info = UNIT_BY_KEY[arg]
        if info then
            UF.db.profile.units[arg].enabled = (cmd == "enable")
            UF:ApplyUnit(arg)
            OUI:Print("|cffd9a441[OUI UnitFrames]|r " .. info.label .. " " .. cmd .. "d.")
        else
            OUI:Print("|cffd9a441[OUI UnitFrames]|r unit: player|target|focus|pet|targettarget|focustarget")
        end
    else
        OUI:Print("|cffd9a441[OUI UnitFrames]|r /ouiuf unlock|lock | enable|disable <unit> · or /ouimove")
    end
end

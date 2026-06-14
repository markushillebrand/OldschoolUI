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
    { key = "player",       unit = "player",       label = "Player",            w = 181, h = 46, power = 6, defX = -260, defY = -180, cast = true },
    { key = "target",       unit = "target",       label = "Target",            w = 181, h = 46, power = 6, defX =  260, defY = -180, targetChange = true, cast = true },
    { key = "focus",        unit = "focus",        label = "Focus",             w = 181, h = 46, power = 6, defX = -430, defY = -110, focusChange = true, cast = true },
    { key = "pet",          unit = "pet",          label = "Pet",               w = 101, h = 25, power = 6, defX = -260, defY = -232, cast = true },
    { key = "targettarget", unit = "targettarget", label = "Target of Target",  w = 101, h = 25, power = 0, defX =  430, defY = -110, poll = true },
    { key = "focustarget",  unit = "focustarget",  label = "Focus Target",      w = 101, h = 25, power = 0, defX = -430, defY = -158, poll = true },
}
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
        }
    end
    return t
end

local defaults = {
    profile = {
        units = defaultUnits(),
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

function UF:UpdateAll(f)
    if not UnitExists(f.unit) then return end
    self:UpdateHealth(f)
    self:UpdatePower(f)
    self:UpdateName(f)
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
end

function UF:ApplyAll()
    for _, info in ipairs(UNITS) do self:ApplyUnit(info.key) end
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
end

function UF:OnEnable()
    self:ApplyAll()
    self:RegisterMovers()
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

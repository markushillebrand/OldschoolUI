-------------------------------------------------------------------------------
--  OUI_QoL_Cursor.lua -- cursor circle that follows the mouse (clean-room).
--  Shares the OUI_QoL addon namespace/DB. QL-4a: circle only.
-------------------------------------------------------------------------------
local _, ns = ...
local OUI = OldschoolUI

local floor = math.floor
local GetCursorPosition = GetCursorPosition

local MEDIA = "Interface\\AddOns\\OldschoolUI\\media\\cursor\\"
local RING = {
    thin   = MEDIA .. "ring_thin.tga",
    light  = MEDIA .. "ring_light.tga",
    normal = MEDIA .. "ring_normal.tga",
    heavy  = MEDIA .. "ring_heavy.tga",
    thick  = MEDIA .. "ring_thick.tga",
}
-- Exposed for the options dropdown.
ns.CURSOR_RING_NAMES = {
    thin = "Thin", light = "Light", normal = "Normal", heavy = "Heavy", thick = "Thick",
}
ns.CURSOR_RING_ORDER = { "thin", "light", "normal", "heavy", "thick" }

-- Colour: accent | class | custom.
local function cursorColor()
    local p = ns.db.profile
    local mode = p.cursorColorMode or "accent"
    if mode == "class" then
        local _, cls = UnitClass("player")
        local c = cls and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
        if c then return c.r, c.g, c.b end
        return 1, 1, 1
    elseif mode == "custom" then
        local col = p.cursorColor or { 1, 1, 1 }
        return col[1], col[2], col[3]
    end
    local a = OUI.ACCENT or {}
    return a.r or 1, a.g or 0.8, a.b or 0.3
end

local function inInstanceContent()
    local _, itype, diff = GetInstanceInfo()
    if (tonumber(diff) or 0) == 0 then return false end
    return itype == "party" or itype == "raid"
end

local circle, tex, lastX, lastY

local function cursorVisible()
    local p = ns.db.profile
    if not p.cursorCircle then return false end
    if p.cursorInstanceOnly and not inInstanceContent() then return false end
    return true
end

local function applyCursor()
    if not circle then return end
    local p = ns.db.profile
    local size = p.cursorSize or 32
    circle:SetSize(size, size)
    tex:SetTexture(RING[p.cursorStyle or "normal"] or RING.normal)
    tex:SetVertexColor(cursorColor())
    if cursorVisible() then circle:Show() else circle:Hide() end
end
ns.RefreshCursor = applyCursor

-- ---------------------------------------------------------------------------
--  Cursor trail (soft dots that fade behind the cursor)
-- ---------------------------------------------------------------------------
local TRAIL_POOL = 120
local TRAIL_LIFE = 0.5
local TRAIL_DENSITY = 0.01
local DOT = MEDIA .. "dot.tga"

local trailFrame, trailFree, trailActive
local trailTimer, lastTCX, lastTCY = 0, 0, 0

local function trailEnabled()
    local p = ns.db.profile
    if not p.cursorTrail then return false end
    if p.cursorInstanceOnly and not inInstanceContent() then return false end
    return true
end

local function spawnDot(cx, cy, s)
    local d = trailFree[#trailFree]
    if not d then return end
    trailFree[#trailFree] = nil
    local r, g, b = cursorColor()
    local sz = ns.db.profile.cursorTrailSize or 24
    d:SetVertexColor(r, g, b)
    d:SetSize(sz, sz)
    d:ClearAllPoints()
    d:SetPoint("CENTER", trailFrame, "BOTTOMLEFT", cx / s, cy / s)
    d:SetAlpha(1)
    d:Show()
    trailActive[#trailActive + 1] = { tex = d, life = TRAIL_LIFE, size = sz }
end

local function trailOnUpdate(_, elapsed)
    if trailEnabled() then
        local s = UIParent:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        trailTimer = trailTimer + elapsed
        local dx, dy = cx - lastTCX, cy - lastTCY
        if trailTimer >= TRAIL_DENSITY and (dx * dx + dy * dy) >= 4 then
            trailTimer = 0
            lastTCX, lastTCY = cx, cy
            spawnDot(cx, cy, s)
        end
    end
    for i = #trailActive, 1, -1 do
        local e = trailActive[i]
        e.life = e.life - elapsed
        if e.life <= 0 then
            e.tex:Hide()
            trailFree[#trailFree + 1] = e.tex
            trailActive[i] = trailActive[#trailActive]
            trailActive[#trailActive] = nil
        else
            local pct = e.life / TRAIL_LIFE
            e.tex:SetAlpha(pct)
            e.tex:SetSize(e.size * pct, e.size * pct)
        end
    end
end

local function buildTrail()
    if trailFrame then return end
    trailFrame = CreateFrame("Frame", "OUIQoLCursorTrail", UIParent)
    trailFrame:SetAllPoints(UIParent)
    trailFrame:SetFrameStrata("TOOLTIP")
    trailFrame:SetFrameLevel(9998)
    trailFrame:EnableMouse(false)
    trailFree, trailActive = {}, {}
    for _ = 1, TRAIL_POOL do
        local d = trailFrame:CreateTexture(nil, "ARTWORK")
        d:SetTexture(DOT)
        d:SetBlendMode("ADD")
        d:Hide()
        trailFree[#trailFree + 1] = d
    end
    trailFrame:SetScript("OnUpdate", trailOnUpdate)
end

local function applyTrail()
    if ns.db.profile.cursorTrail then
        buildTrail()
    elseif trailActive then
        for i = #trailActive, 1, -1 do
            trailActive[i].tex:Hide()
            trailFree[#trailFree + 1] = trailActive[i].tex
            trailActive[i] = nil
        end
    end
end

-- ---------------------------------------------------------------------------
--  GCD ring (Cooldown-swipe spinner around the cursor)
-- ---------------------------------------------------------------------------
local GCD_SPELL = 61304
local function getGCD()
    if C_Spell and C_Spell.GetSpellCooldown then
        local info = C_Spell.GetSpellCooldown(GCD_SPELL)
        if info then return info.startTime, info.duration end
    elseif GetSpellCooldown then
        local s, d = GetSpellCooldown(GCD_SPELL)
        return s, d
    end
end

local gcdFrame, gcdSwipe, gcdLastX, gcdLastY

local function gcdVisible()
    local p = ns.db.profile
    if not p.cursorGCD then return false end
    if p.cursorInstanceOnly and not inInstanceContent() then return false end
    return true
end

local function buildGCD()
    if gcdFrame then return end
    gcdFrame = CreateFrame("Frame", "OUIQoLCursorGCD", UIParent)
    gcdFrame:SetFrameStrata("TOOLTIP")
    gcdFrame:SetFrameLevel(9990)
    gcdFrame:EnableMouse(false)
    gcdFrame:SetSize(44, 44)
    gcdFrame:SetPoint("CENTER")
    gcdSwipe = CreateFrame("Cooldown", nil, gcdFrame, "CooldownFrameTemplate")
    gcdSwipe:SetAllPoints()
    gcdSwipe:SetHideCountdownNumbers(true)
    gcdSwipe:SetDrawEdge(false)
    gcdSwipe:SetDrawBling(false)
    gcdSwipe:SetReverse(true)
    gcdFrame:SetScript("OnUpdate", function(self)
        local s = UIParent:GetEffectiveScale()
        local x, y = GetCursorPosition()
        x, y = floor(x / s + 0.5), floor(y / s + 0.5)
        if x ~= gcdLastX or y ~= gcdLastY then
            gcdLastX, gcdLastY = x, y
            self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
        end
    end)
    gcdFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    gcdFrame:SetScript("OnEvent", function(_, _, unit)
        if unit ~= "player" or not gcdVisible() then return end
        local s, d = getGCD()
        if s and d and d > 0 and d <= 1.6 then
            gcdSwipe:SetSwipeTexture(RING[ns.db.profile.cursorStyle or "normal"] or RING.normal)
            gcdSwipe:SetSwipeColor(cursorColor())
            gcdSwipe:SetCooldown(s, d)
        end
    end)
end

local function applyGCD()
    if ns.db.profile.cursorGCD then buildGCD() end
    if not gcdFrame then return end
    local size = ns.db.profile.cursorGCDSize or 44
    gcdFrame:SetSize(size, size)
    gcdSwipe:SetSwipeTexture(RING[ns.db.profile.cursorStyle or "normal"] or RING.normal)
    gcdSwipe:SetSwipeColor(cursorColor())
    if gcdVisible() then gcdFrame:Show() else gcdFrame:Hide() end
end

-- ---------------------------------------------------------------------------
--  Cast ring (player cast / channel progress around the cursor)
-- ---------------------------------------------------------------------------
local function castingInfo()
    if UnitCastingInfo then return UnitCastingInfo("player") end
    if CastingInfo then return CastingInfo() end
end
local function channelInfo()
    if UnitChannelInfo then return UnitChannelInfo("player") end
    if ChannelInfo then return ChannelInfo() end
end

local castFrame, castSwipe, castLastX, castLastY

local function castVisible()
    local p = ns.db.profile
    if not p.cursorCast then return false end
    if p.cursorInstanceOnly and not inInstanceContent() then return false end
    return true
end

local function startCast(start, dur, notInterruptible)
    if not (start and dur and dur > 0) then return end
    castSwipe:SetSwipeTexture(RING[ns.db.profile.cursorStyle or "normal"] or RING.normal)
    if notInterruptible then
        castSwipe:SetSwipeColor(0.6, 0.6, 0.6, 1)
    else
        castSwipe:SetSwipeColor(cursorColor())
    end
    castSwipe:SetCooldown(start, dur)
end

local function buildCast()
    if castFrame then return end
    castFrame = CreateFrame("Frame", "OUIQoLCursorCast", UIParent)
    castFrame:SetFrameStrata("TOOLTIP")
    castFrame:SetFrameLevel(9988)
    castFrame:EnableMouse(false)
    castFrame:SetSize(40, 40)
    castFrame:SetPoint("CENTER")
    castSwipe = CreateFrame("Cooldown", nil, castFrame, "CooldownFrameTemplate")
    castSwipe:SetAllPoints()
    castSwipe:SetHideCountdownNumbers(true)
    castSwipe:SetDrawEdge(false)
    castSwipe:SetDrawBling(false)
    castSwipe:SetReverse(true)
    castFrame:SetScript("OnUpdate", function(self)
        local s = UIParent:GetEffectiveScale()
        local x, y = GetCursorPosition()
        x, y = floor(x / s + 0.5), floor(y / s + 0.5)
        if x ~= castLastX or y ~= castLastY then
            castLastX, castLastY = x, y
            self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
        end
    end)
    for _, e in ipairs({
        "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_STOP",
        "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
        "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP",
    }) do
        castFrame:RegisterUnitEvent(e, "player")
    end
    castFrame:SetScript("OnEvent", function(_, event, unit)
        if unit ~= "player" or not castVisible() then return end
        if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_DELAYED" then
            local name, _, _, sMS, eMS, _, _, notInt = castingInfo()
            if name then startCast(sMS * 0.001, (eMS - sMS) * 0.001, notInt) end
        elseif event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
            local name, _, _, sMS, eMS, _, notInt = channelInfo()
            if name then startCast(sMS * 0.001, (eMS - sMS) * 0.001, notInt) end
        else
            castSwipe:SetCooldown(0, 0)
        end
    end)
end

local function applyCast()
    if ns.db.profile.cursorCast then buildCast() end
    if not castFrame then return end
    castFrame:SetSize(ns.db.profile.cursorCastSize or 40, ns.db.profile.cursorCastSize or 40)
    if castVisible() then castFrame:Show() else castFrame:Hide() end
end

function ns.RefreshCursor()
    applyCursor()
    applyTrail()
    applyGCD()
    applyCast()
end

function ns.SetupCursor()
    if circle then applyCursor(); return end
    circle = CreateFrame("Frame", "OUIQoLCursor", UIParent)
    circle:SetFrameStrata("TOOLTIP")
    circle:SetFrameLevel(9999)
    circle:SetClampedToScreen(false)
    circle:EnableMouse(false)
    circle:SetSize(32, 32)
    circle:SetPoint("CENTER")
    tex = circle:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints()
    tex:SetTexture(RING.normal)
    circle:SetScript("OnUpdate", function()
        local s = UIParent:GetEffectiveScale()
        local x, y = GetCursorPosition()
        x, y = floor(x / s + 0.5), floor(y / s + 0.5)
        if x ~= lastX or y ~= lastY then
            lastX, lastY = x, y
            circle:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
        end
    end)
    applyCursor()

    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    ev:SetScript("OnEvent", applyCursor)

    applyTrail()
    applyGCD()
    applyCast()
end

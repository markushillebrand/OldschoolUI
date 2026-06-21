-------------------------------------------------------------------------------
--  OUI_QoL_Bloodlust.lua -- icon showing the player's Bloodlust/Heroism
--  lockout (Sated/Exhaustion/etc.) debuff with its remaining timer.
--  Shares the OUI_QoL addon namespace/DB. Movable via /ouimove.
-------------------------------------------------------------------------------
local _, ns = ...
local OUI = OldschoolUI
local floor = math.floor

-- Every lust variant's lockout debuff (MoP-relevant only).
local SATED = {
    57723,  -- Exhaustion (Heroism)
    57724,  -- Sated (Bloodlust)
    80354,  -- Temporal Displacement (Time Warp)
    95809,  -- Insanity (Ancient Hysteria)
}

local function findSated()
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        for i = 1, #SATED do
            local a = C_UnitAuras.GetPlayerAuraBySpellID(SATED[i])
            if a then return a.icon, a.expirationTime, a.duration end
        end
    end
    for i = 1, 40 do
        local name, icon, _, _, duration, expiration, _, _, _, spellId = UnitDebuff("player", i)
        if not name then break end
        for j = 1, #SATED do
            if spellId == SATED[j] then return icon, expiration, duration end
        end
    end
end

local frame, iconTex, swipe, timeText, lastShown

local function fmtTime(s)
    if s >= 60 then return floor(s / 60) .. "m" end
    return floor(s + 0.5) .. "s"
end

local function update()
    if not frame then return end
    if not ns.db.profile.bloodlustTracker then frame:Hide(); return end
    local icon, expiration, duration = findSated()
    if icon and expiration and expiration > GetTime() then
        iconTex:SetTexture(icon)
        if duration and duration > 0 then swipe:SetCooldown(expiration - duration, duration) end
        frame:Show()
    else
        frame:Hide()
    end
end

local function placeFrame()
    local p = ns.db.profile.bloodlustPos or {}
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", p.x or 0, p.y or -120)
end

function ns.RefreshBloodlust()
    if not frame then return end
    local sz = ns.db.profile.bloodlustSize or 40
    frame:SetSize(sz, sz)
    update()
end

function ns.SetupBloodlust()
    if frame then ns.RefreshBloodlust(); return end
    frame = CreateFrame("Frame", "OUIQoLBloodlust", UIParent)
    frame:SetSize(40, 40)
    placeFrame()
    iconTex = frame:CreateTexture(nil, "ARTWORK")
    iconTex:SetAllPoints()
    iconTex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    if OUI.PP and OUI.PP.CreateBorder then OUI.PP.CreateBorder(frame, 0, 0, 0, 1) end
    swipe = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    swipe:SetAllPoints()
    swipe:SetHideCountdownNumbers(true)
    timeText = frame:CreateFontString(nil, "OVERLAY")
    timeText:SetFont((OUI.GetFontPath and OUI.GetFontPath()) or STANDARD_TEXT_FONT, 13, "OUTLINE")
    timeText:SetPoint("CENTER")

    frame:SetScript("OnUpdate", function(self, e)
        self._t = (self._t or 0) + e
        if self._t < 0.25 then return end
        self._t = 0
        local _, expiration = findSated()
        if expiration then
            local rem = expiration - GetTime()
            if rem > 0 then timeText:SetText(fmtTime(rem)) else timeText:SetText("") end
        end
    end)

    local ev = CreateFrame("Frame")
    ev:RegisterUnitEvent("UNIT_AURA", "player")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:SetScript("OnEvent", update)

    if OUI.RegisterUnlockElements and OUI.MakeUnlockElement then
        OUI:RegisterUnlockElements({ OUI.MakeUnlockElement({
            key      = "OUIQoL_Bloodlust",
            label    = (OUI.L and OUI.L("Bloodlust Tracker")) or "Bloodlust Tracker",
            group    = "QoL",
            getFrame = function() return frame end,
            getSize  = function() return frame:GetWidth(), frame:GetHeight() end,
            isHidden = function() return not ns.db.profile.bloodlustTracker end,
            savePos  = function(_, _, _, x, y)
                ns.db.profile.bloodlustPos = { x = floor(x + 0.5), y = floor(y + 0.5) }
                placeFrame()
            end,
            applyPos = function() placeFrame() end,
        }) })
    end

    ns.RefreshBloodlust()
end

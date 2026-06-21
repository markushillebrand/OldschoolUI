-- ===========================================================================
--  OldschoolUI -- Nameplates  NP-5: extras
--  Raid-target marker, level + elite/rare classification text, and an absorb
--  shield overlay on the health bar. Clean-room: own implementation.
-- ===========================================================================
local ADDON, ns = ...
local OUI = OldschoolUI
if not OUI then return end

local cfg      = ns.cfg
local fontPath = ns.fontPath
if not cfg then return end

-- ---------------------------------------------------------------------------
--  Attach extra elements to a plate
-- ---------------------------------------------------------------------------
function ns.AttachExtras(plate)
    if plate._extras then return end
    plate._extras = true

    plate.raidIcon = plate:CreateTexture(nil, "OVERLAY")
    plate.raidIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    plate.raidIcon:Hide()

    plate.levelText = plate:CreateFontString(nil, "OVERLAY")

    plate.absorb = plate.health:CreateTexture(nil, "ARTWORK", nil, 1)
    plate.absorb:Hide()
end

-- ---------------------------------------------------------------------------
--  Raid-target marker
-- ---------------------------------------------------------------------------
local function updateRaidMarker(plate)
    local t = plate.raidIcon
    if not (t and plate.unit) then return end
    local idx = cfg("showRaidMarker") and GetRaidTargetIndex(plate.unit)
    if not idx then t:Hide(); return end
    SetRaidTargetIconTexture(t, idx)
    local sz, pos = cfg("raidMarkerSize") or 22, cfg("raidMarkerPos") or "LEFT"
    t:SetSize(sz, sz)
    t:ClearAllPoints()
    if pos == "RIGHT" then
        t:SetPoint("LEFT", plate, "RIGHT", 4, 0)
    elseif pos == "TOP" then
        t:SetPoint("BOTTOM", plate.name, "TOP", 0, 2)
    else -- LEFT
        t:SetPoint("RIGHT", plate, "LEFT", -4, 0)
    end
    t:Show()
end

-- ---------------------------------------------------------------------------
--  Level + classification
-- ---------------------------------------------------------------------------
local function updateLevel(plate)
    local fs = plate.levelText
    if not (fs and plate.unit) then return end
    if not cfg("showLevel") then fs:Hide(); return end
    local unit = plate.unit
    local level = UnitLevel(unit)
    local txt = (level and level > 0) and tostring(level) or "??"

    local cls = UnitClassification(unit)
    if cls == "worldboss" then txt = txt .. "B"
    elseif cls == "rareelite" then txt = txt .. "R+"
    elseif cls == "elite" then txt = txt .. "+"
    elseif cls == "rare" then txt = txt .. "R" end

    fs:SetFont(fontPath(), cfg("levelTextSize") or 10, "OUTLINE")
    local r, g, b = 0.9, 0.9, 0.9
    local col = (level and level > 0) and (GetCreatureDifficultyColor or GetQuestDifficultyColor)
    if col then
        local ok, c = pcall(col, level)
        if ok and c then r, g, b = c.r, c.g, c.b end
    end
    fs:SetTextColor(r, g, b)
    fs:SetText(txt)
    fs:ClearAllPoints()
    fs:SetPoint("RIGHT", plate.name, "LEFT", -3, 0)
    fs:Show()
end

-- ---------------------------------------------------------------------------
--  Absorb shield overlay
-- ---------------------------------------------------------------------------
function ns.UpdateAbsorb(plate)
    local t = plate.absorb
    if not (t and plate.unit) then return end
    if not cfg("showAbsorb") then t:Hide(); return end
    local unit = plate.unit
    local absorb = (UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(unit)) or 0
    local maxhp = UnitHealthMax(unit) or 0
    if absorb <= 0 or maxhp <= 0 then t:Hide(); return end

    local hp = UnitHealth(unit) or 0
    local barW = plate.health:GetWidth()
    if not barW or barW <= 0 then barW = ns.barWidth() end
    local startX = barW * (hp / maxhp)
    local absW = barW * (absorb / maxhp)
    local avail = barW - startX
    if absW > avail then absW = avail end
    if absW <= 0 then t:Hide(); return end

    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", plate.health, "TOPLEFT", startX, 0)
    t:SetPoint("BOTTOMLEFT", plate.health, "BOTTOMLEFT", startX, 0)
    t:SetWidth(absW)
    local ac = cfg("absorbColor")
    t:SetColorTexture(ac.r, ac.g, ac.b, ac.a or 0.45)
    t:Show()
end

-- ---------------------------------------------------------------------------
--  Combined update (called on bind + options refresh)
-- ---------------------------------------------------------------------------
function ns.UpdateExtras(plate)
    updateRaidMarker(plate)
    updateLevel(plate)
    ns.UpdateAbsorb(plate)
end

local _origRefresh = ns.RefreshAllSettings
function ns.RefreshAllSettings()
    if _origRefresh then _origRefresh() end
    for _, plate in pairs(ns.plates) do
        if plate.unit and plate._extras then ns.UpdateExtras(plate) end
    end
end

-- ---------------------------------------------------------------------------
--  Events
-- ---------------------------------------------------------------------------
local ew = CreateFrame("Frame")
ew:RegisterEvent("RAID_TARGET_UPDATE")
ew:RegisterEvent("UNIT_ABSORB_AMOUNT_CHANGED")
ew:RegisterEvent("UNIT_HEALTH")
ew:RegisterEvent("UNIT_MAXHEALTH")
ew:RegisterEvent("UNIT_LEVEL")
ew:RegisterEvent("UNIT_CLASSIFICATION_CHANGED")
ew:SetScript("OnEvent", function(_, evt, unit)
    if evt == "RAID_TARGET_UPDATE" then
        for _, plate in pairs(ns.plates) do
            if plate.unit and plate._extras then updateRaidMarker(plate) end
        end
        return
    end
    local plate = ns.platesByUnit[unit]
    if not (plate and plate._extras) then return end
    if evt == "UNIT_LEVEL" or evt == "UNIT_CLASSIFICATION_CHANGED" then
        updateLevel(plate)
    else
        ns.UpdateAbsorb(plate)
    end
end)

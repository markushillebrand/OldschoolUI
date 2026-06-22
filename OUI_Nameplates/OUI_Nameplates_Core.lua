-- ===========================================================================
--  OldschoolUI -- Nameplates  (clean-room rewrite)
--  NP-1 Core: plate lifecycle, custom health bar, name/level text, reaction +
--  threat colouring, target/focus highlight, CVar setup.
--  Cast bar, auras, friendly plates and extras arrive in later phases. Written
--  fresh against the MoP Classic 5.5.x nameplate driver; the behaviour mirrors
--  the original module but the implementation is our own.
-- ===========================================================================
local ADDON, ns = ...
local OUI = OldschoolUI
if not OUI then return end

local NP = LibStub("AceAddon-3.0"):NewAddon("OldschoolUINameplates", "AceEvent-3.0")
ns.NP = NP

-- ---------------------------------------------------------------------------
--  Defaults (settings contract shared with the options page)
-- ---------------------------------------------------------------------------
local BAR_W = 150
ns.BAR_W = BAR_W

local defaults = {
    profile = {
        -- bars
        healthBarTexture = "none",
        healthBarHeight  = 17,
        healthBarWidth   = 6,          -- offset added to BAR_W
        bgColor   = { r = 0.12, g = 0.12, b = 0.12 },
        bgAlpha   = 1.0,
        showBorder = true,
        borderSize = 1,
        borderColor = { r = 0.067, g = 0.067, b = 0.067 },
        -- reaction colours
        hostile = { r = 0.39, g = 0.11, b = 0.09 },
        neutral = { r = 0.81, g = 0.72, b = 0.19 },
        tapped  = { r = 0.50, g = 0.50, b = 0.50 },
        caster  = { r = 0.231, g = 0.510, b = 0.965 },
        miniboss = { r = 0.518, g = 0.243, b = 0.984 },
        -- target / focus
        target = { r = 0.459, g = 0.890, b = 0.580 },
        targetColorEnabled = false,
        -- class power (secondary resource on the target plate)
        showClassPower = true,
        classPowerTargetOnly = true,
        classPowerHeight = 5,
        focus = { r = 0.051, g = 0.820, b = 0.620 },
        focusColorEnabled = true,
        hoverColor = { r = 1, g = 1, b = 1 },
        hoverAlpha = 0.3,
        -- threat
        tankHasAggroEnabled = false,
        tankHasAggro   = { r = 0.05, g = 0.82, b = 0.62 },
        tankLosingAggro = { r = 0.81, g = 0.72, b = 0.19 },
        tankNoAggro    = { r = 1.00, g = 0.22, b = 0.17 },
        dpsNearAggro   = { r = 0.81, g = 0.72, b = 0.19 },
        dpsHasAggro    = { r = 1.00, g = 0.50, b = 0.00 },
        enemyInCombat  = { r = 0.800, g = 0.137, b = 0.137 },
        -- text
        font = (OUI.GetFontPath and OUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF",
        enemyNameTextSize = 11,
        textSlotTop = "enemyName",
        textSlotRight = "healthPercent",
        -- cast bar
        castBar = { r = 0.70, g = 0.40, b = 0.90 },
        castBarUninterruptible = { r = 0.45, g = 0.45, b = 0.45 },
        castBarHeight = 17,
        castBgColor = { r = 0.1, g = 0.1, b = 0.1 },
        castBgAlpha = 0.9,
        castNameSize = 10,
        castTimerSize = 10,
        showCastIcon = true,
        showCastTimer = true,
        castbarIconInWidth = false,
        -- auras (NP-3)
        showAllDebuffs = false,        -- false = only the player's own debuffs
        maxDebuffs = 5,
        debuffIconSize = 26,
        auraSpacing = 2,
        auraDurationTextSize = 11,
        auraDurationTextColor = { r = 1, g = 1, b = 1 },
        auraStackTextSize = 11,
        auraStackTextColor = { r = 1, g = 1, b = 1 },
        debuffYOffset = 4,
        pandemicGlow = false,
        pandemicGlowColor = { r = 1.0, g = 0.800, b = 0.329 },
        debuffSlot = "top",
        buffSlot = "left",
        ccSlot = "right",
        buffIconSize = 24,
        ccIconSize = 24,
        maxBuffs = 4,
        maxCC = 3,
        -- extras (NP-5)
        showRaidMarker = true,
        raidMarkerSize = 22,
        raidMarkerPos = "LEFT",
        showLevel = true,
        levelTextSize = 10,
        showAbsorb = true,
        absorbColor = { r = 0.882, g = 0.902, b = 1.0, a = 0.45 },
        -- visibility / sizing CVars
        showEnemyPets = false,
        showFriendlyNPCs = false,
        showFriendlyPlayers = true,
        classColorFriendly = true,
        friendlyNameOnly = true,
        friendlyNameOnlyYOffset = -8,
        friendlyHealthBarWidth = 110,
        friendlyHealthBarHeight = 8,
        friendlyBarColor = { r = 0.314, g = 0.800, b = 0.408 },
        nameplateOverlapV = 1.10,
        nameplateYOffset = 0,
    },
}
ns.defaults = defaults

-- ---------------------------------------------------------------------------
--  Small helpers
-- ---------------------------------------------------------------------------
local function P() return ns.db and ns.db.profile or defaults.profile end
local function cfg(k) local p = P(); local v = p[k]; if v == nil then v = defaults.profile[k] end; return v end
local function fontPath() return cfg("font") or "Fonts\\FRIZQT__.TTF" end

local function barTexture()
    local key = cfg("healthBarTexture")
    if (not key or key == "none") and OUI.GetBarTexturePath then return OUI.GetBarTexturePath() end
    if OUI.GetBarTexturePath and key and key ~= "none" then
        -- let the suite resolve a named texture; fall back to its default
        return OUI.GetBarTexturePath(key) or OUI.GetBarTexturePath()
    end
    return "Interface\\Buttons\\WHITE8x8"
end

local function barWidth()  return BAR_W + (cfg("healthBarWidth") or 6) end
local function barHeight() return cfg("healthBarHeight") or 17 end

-- expose helpers for sibling phase modules (cast, auras, friendly)


ns.cfg, ns.fontPath = cfg, fontPath
ns.barWidth, ns.barHeight, ns.barTexture = barWidth, barHeight, barTexture

-- ---------------------------------------------------------------------------
--  Colour resolution
-- ---------------------------------------------------------------------------
local function reactionColor(unit)
    if UnitIsTapDenied and UnitIsTapDenied(unit) then return cfg("tapped") end
    local reaction = UnitReaction("player", unit)
    if not reaction then return cfg("hostile") end
    if reaction <= 3 then return cfg("hostile")
    elseif reaction == 4 then return cfg("neutral")
    else return cfg("hostile") end   -- friendly handled by the friendly module later
end

-- MoP Classic: the GetSpecialization global is nil; use C_SpecializationInfo
-- and never pass nil into GetSpecializationRole.
local function playerRole()
    local spec
    if C_SpecializationInfo and C_SpecializationInfo.GetSpecialization then
        spec = C_SpecializationInfo.GetSpecialization()
    elseif GetSpecialization then
        spec = GetSpecialization()
    end
    if spec and GetSpecializationRole then return GetSpecializationRole(spec) end
    return nil
end

-- Threat-aware colour for hostile units. Returns nil to fall back to reaction.
local function threatColor(unit)
    if not UnitAffectingCombat("player") then return nil end
    if not (UnitCanAttack and UnitCanAttack("player", unit)) then return nil end
    local status = UnitThreatSituation("player", unit)
    if status == nil then return nil end
    local tank = (playerRole() == "TANK")
    if cfg("tankHasAggroEnabled") and tank then
        if status >= 2 then return cfg("tankHasAggro")        -- securely tanking
        elseif status == 1 then return cfg("tankLosingAggro")
        else return cfg("tankNoAggro") end
    else
        if status >= 2 then return cfg("dpsHasAggro")         -- pulled aggro
        elseif status == 1 then return cfg("dpsNearAggro")
        else return nil end
    end
end

local function unitColor(plate)
    local unit = plate.unit
    if not unit then return cfg("hostile") end
    if cfg("targetColorEnabled") and UnitIsUnit(unit, "target") then return cfg("target") end
    if cfg("focusColorEnabled") and UnitIsUnit(unit, "focus") then return cfg("focus") end
    return threatColor(unit) or reactionColor(unit)
end

-- ---------------------------------------------------------------------------
--  Hide / restore Blizzard's default plate elements
-- ---------------------------------------------------------------------------
local hidden = CreateFrame("Frame")
hidden:Hide()
local storedParent = {}

-- This client keeps the cast bar inside uf.CastBarsContainer (uf.castBar is nil)
-- and the health bar inside uf.HealthBarsContainer. Reparent the lot offscreen.
local SUPPRESS = { "healthBar", "HealthBarsContainer", "CastBarsContainer", "name", "AurasFrame" }

local function suppressBlizzard(nameplate)
    local uf = nameplate.UnitFrame
    if not uf then return end
    for _, key in ipairs(SUPPRESS) do
        local el = uf[key]
        if el and el.GetParent and el:GetParent() ~= hidden then
            storedParent[el] = el:GetParent()
            el:SetParent(hidden)
        end
    end
    -- The driver re-shows the cast bar container on each cast; keep it hidden
    -- while we own the plate (parented offscreen).
    local cbc = uf.CastBarsContainer
    if cbc then
        if not cbc._ouiHidden then
            cbc._ouiHidden = true
            cbc:HookScript("OnShow", function(s) if s:GetParent() == hidden then s:Hide() end end)
        end
        cbc:Hide()
    end
    if uf.SetAlpha then uf:SetAlpha(0) end
end

local function restoreBlizzard(nameplate)
    local uf = nameplate.UnitFrame
    if not uf then return end
    for _, key in ipairs(SUPPRESS) do
        local el = uf[key]
        if el and storedParent[el] then
            el:SetParent(storedParent[el])
            storedParent[el] = nil
        end
    end
    if uf.SetAlpha then uf:SetAlpha(1) end
end

ns.suppressBlizzard = suppressBlizzard
ns.restoreBlizzard = restoreBlizzard

-- ---------------------------------------------------------------------------
--  Plate object
-- ---------------------------------------------------------------------------
local plates = {}          -- nameplate frame -> our plate
ns.plates = plates
local platesByUnit = {}    -- unit token -> our plate (for cast/aura dispatch)
ns.platesByUnit = platesByUnit

local function CreatePlate()
    local f = CreateFrame("Frame", nil, UIParent)
    f:Hide()

    -- background
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()

    -- health bar
    f.health = CreateFrame("StatusBar", nil, f)
    f.health:SetPoint("TOPLEFT", 1, -1)
    f.health:SetPoint("BOTTOMRIGHT", -1, 1)
    f.health:SetMinMaxValues(0, 1)

    -- border (suite pixel border)
    if OUI.PP and OUI.PP.CreateBorder then
        OUI.PP.CreateBorder(f, 0.067, 0.067, 0.067, 1)
    end

    -- name (top) + health% (right)
    f.name = f:CreateFontString(nil, "OVERLAY")
    f.name:SetPoint("BOTTOM", f, "TOP", 0, 2)

    f.hpText = f:CreateFontString(nil, "OVERLAY")
    f.hpText:SetPoint("RIGHT", f.health, "RIGHT", -2, 0)

    -- highlight on mouseover
    f.highlight = f.health:CreateTexture(nil, "OVERLAY")
    f.highlight:SetAllPoints(f.health)
    f.highlight:SetColorTexture(1, 1, 1, 0.25)
    f.highlight:Hide()

    if ns.AttachCast then ns.AttachCast(f) end
    if ns.AttachAuras then ns.AttachAuras(f) end
    if ns.AttachExtras then ns.AttachExtras(f) end
    if ns.AttachClassPower then ns.AttachClassPower(f) end

    return f
end

local function stylePlate(plate)
    local w, h = barWidth(), barHeight()
    plate:SetSize(w, h)
    plate.health:SetStatusBarTexture(barTexture())

    local bg = cfg("bgColor")
    plate.bg:SetColorTexture(bg.r, bg.g, bg.b, cfg("bgAlpha") or 1)

    local fp = fontPath()
    plate.name:SetFont(fp, cfg("enemyNameTextSize") or 11, "OUTLINE")
    plate.hpText:SetFont(fp, (cfg("enemyNameTextSize") or 11) - 1, "OUTLINE")

    if OUI.PP and OUI.PP.SetBorderColor then
        local bc = cfg("borderColor")
        OUI.PP.SetBorderColor(plate, bc.r, bc.g, bc.b, cfg("showBorder") ~= false and 1 or 0)
    end
end

local function shortValue(v)
    if v >= 1e6 then return string.format("%.1fm", v / 1e6)
    elseif v >= 1e3 then return string.format("%.0fk", v / 1e3)
    else return tostring(v) end
end

local function updateHealth(plate)
    local unit = plate.unit
    if not unit then return end
    local cur, max = UnitHealth(unit), UnitHealthMax(unit)
    if max and max > 0 then
        plate.health:SetMinMaxValues(0, max)
        plate.health:SetValue(cur)
        if cfg("textSlotRight") == "healthPercent" then
            plate.hpText:SetText(string.format("%d%%", math.floor(cur / max * 100 + 0.5)))
        else
            plate.hpText:SetText(shortValue(cur))
        end
    end
end

local function updateColor(plate)
    local c = unitColor(plate)
    if c then plate.health:SetStatusBarColor(c.r, c.g, c.b) end
end

local function updateName(plate)
    local unit = plate.unit
    if not unit then return end
    local name = UnitName(unit) or ""
    local level = UnitLevel(unit)
    if level and level > 0 and UnitClassification(unit) ~= "normal" then
        name = name
    end
    plate.name:SetText(name)
    plate.name:SetTextColor(1, 1, 1)
end

local function updateTargetHighlight(plate)
    -- brighten the border on the current target
    if not (OUI.PP and OUI.PP.SetBorderColor) then return end
    local unit = plate.unit
    if unit and UnitIsUnit(unit, "target") then
        local a = OUI.ACCENT
        OUI.PP.SetBorderColor(plate, a.r, a.g, a.b, 1)
    else
        local bc = cfg("borderColor")
        OUI.PP.SetBorderColor(plate, bc.r, bc.g, bc.b, cfg("showBorder") ~= false and 1 or 0)
    end
end

local function plateSetUnit(plate, unit, nameplate)
    plate.unit = unit
    plate.nameplate = nameplate
    plate:SetParent(nameplate)
    plate:ClearAllPoints()
    plate:SetPoint("CENTER", nameplate, "CENTER", 0, cfg("nameplateYOffset") or 0)
    plate:SetFrameStrata("BACKGROUND")
    stylePlate(plate)
    updateHealth(plate)
    updateColor(plate)
    updateName(plate)
    updateTargetHighlight(plate)
    if ns.CastOnSetUnit then ns.CastOnSetUnit(plate) end
    if ns.UpdateAuras then ns.UpdateAuras(plate) end
    if ns.UpdateExtras then ns.UpdateExtras(plate) end
    if ns.UpdateClassPower then ns.UpdateClassPower(plate) end
    plate:Show()
end

-- ---------------------------------------------------------------------------
--  Lifecycle
-- ---------------------------------------------------------------------------
local function onAdded(unit)
    if not unit then return end
    local nameplate = C_NamePlate.GetNamePlateForUnit(unit)
    if not nameplate then return end
    -- friendly units are owned by the friendly module (NP-4); hostile/neutral
    -- attackable plates are handled here.
    if not (UnitCanAttack and UnitCanAttack("player", unit)) then
        if ns.OnFriendlyAdded then ns.OnFriendlyAdded(unit, nameplate) end
        return
    end

    suppressBlizzard(nameplate)
    local plate = plates[nameplate]
    if not plate then
        plate = CreatePlate()
        plates[nameplate] = plate
    end
    plateSetUnit(plate, unit, nameplate)
    platesByUnit[unit] = plate
end

local function onRemoved(unit)
    platesByUnit[unit] = nil
    if ns.OnFriendlyRemoved then ns.OnFriendlyRemoved(unit) end
    local nameplate = unit and C_NamePlate.GetNamePlateForUnit(unit)
    if nameplate then
        local plate = plates[nameplate]
        if plate then plate.unit = nil; plate:Hide() end
        restoreBlizzard(nameplate)
    end
end

local function forEachPlate(fn)
    for nameplate, plate in pairs(plates) do
        if plate.unit and plate:IsShown() then fn(plate) end
    end
end

-- Accessors consumed by sibling files (e.g. the class-power module) that drive
-- their own events but need to reach the live plate objects held here.
function ns.ForEachPlate(fn) return forEachPlate(fn) end
function ns.PlateForNameplate(np) return plates[np] end

-- ---------------------------------------------------------------------------
--  CVars
-- ---------------------------------------------------------------------------
local function applyCVars()
    local function set(c, v) pcall(SetCVar, c, v) end
    set("nameplateShowAll", 1)
    set("nameplateShowEnemies", 1)
    set("nameplateShowEnemyPets", cfg("showEnemyPets") and 1 or 0)
    set("nameplateShowFriends", cfg("showFriendlyPlayers") ~= false and 1 or 0)
    set("nameplateShowFriendlyNPCs", cfg("showFriendlyNPCs") and 1 or 0)
    set("nameplateOverlapV", cfg("nameplateOverlapV") or 1.10)
    set("nameplateMinAlpha", 0.6)
    set("nameplateMaxAlpha", 1)
    set("nameplateMaxDistance", 60)
    set("ShowClassColorInNameplate", 1)
end

-- ---------------------------------------------------------------------------
--  Public refreshers (consumed by the options page)
-- ---------------------------------------------------------------------------
function ns.RefreshAllSettings()
    forEachPlate(function(plate)
        stylePlate(plate)
        updateHealth(plate)
        updateColor(plate)
        updateName(plate)
        updateTargetHighlight(plate)
    end)
    applyCVars()
end

-- stubs for refreshers the options page nudges (implemented in later phases)
for _, name in ipairs({
    "RefreshHoverEffect", "ApplyAbsorbStyleAll", "RefreshHitboxSize",
    "RefreshStackingBounds", "RefreshNameplateYOffset", "RefreshFriendlyNameOnlyOffset",
    "UpdateFriendlyNameplateSystem", "RefreshBorder", "RefreshBorderColor",
}) do
    ns[name] = ns[name] or function() end
end

-- ---------------------------------------------------------------------------
--  Event driver
-- ---------------------------------------------------------------------------
local driver = CreateFrame("Frame")
driver:RegisterEvent("NAME_PLATE_UNIT_ADDED")
driver:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
driver:RegisterEvent("UNIT_HEALTH")
driver:RegisterEvent("UNIT_MAXHEALTH")
driver:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
driver:RegisterEvent("UNIT_FACTION")
driver:RegisterEvent("PLAYER_TARGET_CHANGED")
driver:SetScript("OnEvent", function(_, event, unit)
    if event == "NAME_PLATE_UNIT_ADDED" then
        onAdded(unit)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        onRemoved(unit)
    elseif event == "PLAYER_TARGET_CHANGED" then
        forEachPlate(function(plate) updateColor(plate); updateTargetHighlight(plate) end)
    elseif unit then
        local nameplate = C_NamePlate.GetNamePlateForUnit(unit)
        local plate = nameplate and plates[nameplate]
        if plate and plate.unit == unit then
            if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then updateHealth(plate)
            else updateColor(plate) end
        end
    end
end)

-- ---------------------------------------------------------------------------
--  Lifecycle
-- ---------------------------------------------------------------------------
function NP:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("OldschoolUINameplatesDB", defaults, true)
    ns.db = self.db
end

function NP:OnEnable()
    if OUI.IsModuleEnabled and not OUI:IsModuleEnabled("OUI_Nameplates") then return end
    applyCVars()
    -- Suppress Blizzard's plate elements from the driver's own OnNamePlateAdded,
    -- which runs AFTER Blizzard sets up (and event-registers) the cast bar. Doing
    -- it on our own NAME_PLATE_UNIT_ADDED can race Blizzard's setup, leaving its
    -- cast bar alive -- the cause of the doubled cast bar.
    if NamePlateDriverFrame and not self._driverHooked then
        self._driverHooked = true
        hooksecurefunc(NamePlateDriverFrame, "OnNamePlateAdded", function(_, unit)
            if unit and unit ~= "preview" and UnitCanAttack and UnitCanAttack("player", unit) then
                local np = C_NamePlate.GetNamePlateForUnit(unit)
                if np then suppressBlizzard(np) end
            end
        end)
    end
    -- adopt any plates that already exist
    if C_NamePlate and C_NamePlate.GetNamePlates then
        for _, np in ipairs(C_NamePlate.GetNamePlates()) do
            if np.namePlateUnitToken then onAdded(np.namePlateUnitToken) end
        end
    end
end


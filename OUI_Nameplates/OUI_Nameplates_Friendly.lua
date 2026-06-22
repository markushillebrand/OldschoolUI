-- ===========================================================================
--  OldschoolUI -- Nameplates  NP-4: friendly plates
--  Custom plates for friendly players (and optionally NPCs). Two modes:
--    * name-only (default) -- just a class-coloured name, no bar
--    * full plate          -- a small health bar + name
--  Clean-room: own implementation.
-- ===========================================================================
local ADDON, ns = ...
local OUI = OldschoolUI
if not OUI then return end

local cfg      = ns.cfg
local fontPath = ns.fontPath
if not cfg then return end

ns.friendlyPlates = ns.friendlyPlates or {}   -- nameplate frame -> our plate
ns.friendlyByUnit = ns.friendlyByUnit or {}   -- unit token      -> our plate

-- ---------------------------------------------------------------------------
--  Colour resolution
-- ---------------------------------------------------------------------------
local function unitColor(unit)
    if cfg("classColorFriendly") and UnitIsPlayer(unit) then
        local _, classFile = UnitClass(unit)
        local c = classFile and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[classFile]
        if c then return c.r, c.g, c.b end
    end
    local fb = cfg("friendlyBarColor")
    return fb.r, fb.g, fb.b
end

-- ---------------------------------------------------------------------------
--  Plate object
-- ---------------------------------------------------------------------------
local function FriendlySetUnit(self, unit, nameplate)
    self.unit = unit
    self.nameplate = nameplate
    self:SetParent(nameplate)
    self:ClearAllPoints()

    local r, g, b = unitColor(unit)
    self.name:SetFont(fontPath(), 11, "OUTLINE")
    self.name:SetText(UnitName(unit) or "")
    self.name:SetTextColor(r, g, b)

    if cfg("friendlyNameOnly") then
        self.bg:Hide()
        self.health:Hide()
        if OUI.PP and OUI.PP.SetBorderColor then OUI.PP.SetBorderColor(self, 0, 0, 0, 0) end
        self:SetSize(120, 12)
        self:SetPoint("CENTER", nameplate, "CENTER", 0, cfg("friendlyNameOnlyYOffset") or -8)
        self.name:ClearAllPoints()
        self.name:SetPoint("CENTER", self, "CENTER", 0, 0)
    else
        local w = cfg("friendlyHealthBarWidth") or 110
        local h = cfg("friendlyHealthBarHeight") or 8
        self:SetSize(w, h)
        self:SetPoint("CENTER", nameplate, "CENTER", 0, cfg("nameplateYOffset") or 0)
        self.bg:Show()
        self.health:Show()
        self.health:SetStatusBarTexture(ns.barTexture())
        self.health:SetStatusBarColor(r, g, b)
        self.health:SetMinMaxValues(0, math.max(UnitHealthMax(unit) or 1, 1))
        self.health:SetValue(UnitHealth(unit) or 0)
        if OUI.PP and OUI.PP.SetBorderColor then
            local bc = cfg("borderColor")
            OUI.PP.SetBorderColor(self, bc.r, bc.g, bc.b, cfg("showBorder") ~= false and 1 or 0)
        end
        self.name:ClearAllPoints()
        self.name:SetPoint("BOTTOM", self, "TOP", 0, 2)
    end

    self:Show()
end

local function CreateFriendlyPlate()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(120, 12)
    f:SetFrameStrata("BACKGROUND")

    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(0, 0, 0, 0.6)

    f.health = CreateFrame("StatusBar", nil, f)
    f.health:SetAllPoints()
    f.health:SetStatusBarTexture(ns.barTexture())

    if OUI.PP and OUI.PP.CreateBorder then OUI.PP.CreateBorder(f, 0.067, 0.067, 0.067, 1) end

    f.name = f:CreateFontString(nil, "OVERLAY")

    f.SetUnit = FriendlySetUnit
    return f
end

-- ---------------------------------------------------------------------------
--  Add / remove (called from the core lifecycle)
-- ---------------------------------------------------------------------------
function ns.OnFriendlyAdded(unit, nameplate)
    local isPlayer = UnitIsPlayer(unit)
    local want = (isPlayer and cfg("showFriendlyPlayers") ~= false)
              or (not isPlayer and cfg("showFriendlyNPCs"))
    if not want then
        if ns.friendlyPlates[nameplate] then ns.OnFriendlyRemoved(unit) end
        return
    end

    ns.suppressBlizzard(nameplate)
    local plate = ns.friendlyPlates[nameplate]
    if not plate then
        plate = CreateFriendlyPlate()
        ns.friendlyPlates[nameplate] = plate
    end
    plate.SetUnit(plate, unit, nameplate)
    ns.friendlyByUnit[unit] = plate
end

function ns.OnFriendlyRemoved(unit)
    local plate = ns.friendlyByUnit[unit]
    ns.friendlyByUnit[unit] = nil
    if not plate then return end
    plate.unit = nil
    plate:Hide()
    if plate.nameplate then
        ns.friendlyPlates[plate.nameplate] = nil
        ns.restoreBlizzard(plate.nameplate)
    end
end

-- ---------------------------------------------------------------------------
--  Full re-evaluation (called by the options page on toggle)
-- ---------------------------------------------------------------------------
function ns.UpdateFriendlyNameplateSystem()
    -- pick up friendly plates that should now be owned (or released)
    for _, np in ipairs(C_NamePlate.GetNamePlates() or {}) do
        local unit = np.namePlateUnitToken or (np.UnitFrame and np.UnitFrame.unit)
        if unit and UnitExists(unit) and not (UnitCanAttack and UnitCanAttack("player", unit)) then
            ns.OnFriendlyAdded(unit, np)
        end
    end
    -- restyle the ones we already own
    for nameplate, plate in pairs(ns.friendlyPlates) do
        if plate.unit then plate.SetUnit(plate, plate.unit, nameplate) end
    end
end

-- ---------------------------------------------------------------------------
--  Health / name events for full-mode bars
-- ---------------------------------------------------------------------------
local fw = CreateFrame("Frame")
fw:RegisterEvent("UNIT_HEALTH")
fw:RegisterEvent("UNIT_MAXHEALTH")
fw:RegisterEvent("UNIT_NAME_UPDATE")
fw:SetScript("OnEvent", function(_, evt, unit)
    local plate = ns.friendlyByUnit[unit]
    if not (plate and plate.unit) then return end
    if evt == "UNIT_NAME_UPDATE" then
        plate.SetUnit(plate, unit, plate.nameplate)
    elseif not cfg("friendlyNameOnly") and plate.health:IsShown() then
        plate.health:SetMinMaxValues(0, math.max(UnitHealthMax(unit) or 1, 1))
        plate.health:SetValue(UnitHealth(unit) or 0)
    end
end)

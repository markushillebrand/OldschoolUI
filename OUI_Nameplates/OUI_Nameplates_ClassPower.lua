-- ===========================================================================
--  OldschoolUI -- Nameplates  NP-6: class power (secondary resource)
--  Shows the player's secondary resource (combo points, chi, holy power,
--  shadow orbs, soul shards, burning embers, demonic fury, eclipse, runes)
--  as a compact row above the target's health bar.
--
--  Resource detection mirrors our ResourceBars model (our own code): spec via
--  C_SpecializationInfo.GetSpecialization(), power maxima read live from
--  UnitPowerMax -- nothing hard-coded. Power-type constants are the verified
--  MoP Classic Enum.PowerType values.
-- ===========================================================================
local ADDON, ns = ...
local OUI = OldschoolUI
if not OUI then return end

local cfg = ns.cfg
if not cfg then return end

local floor = math.floor

-- ---------------------------------------------------------------------------
--  Power-type constants (verified MoP Classic Enum.PowerType values)
-- ---------------------------------------------------------------------------
local P_COMBO, P_RUNIC, P_SOUL = 4, 6, 7
local P_HOLY,  P_CHI           = 9, 12
local P_EMBERS, P_FURY         = 14, 15
local P_ECLIPSE, P_ORBS        = 26, 28

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

-- ---------------------------------------------------------------------------
--  Spec / secondary-resource resolution (our own model, shared with RB)
-- ---------------------------------------------------------------------------
local function ActiveSpec()
    local n = (GetNumSpecializations and GetNumSpecializations()) or 0
    local i = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization
              and C_SpecializationInfo.GetSpecialization()
    if i and i >= 1 and i <= n then return i end
    return nil
end

-- kind = "pips" | "segments" | "bar" | "eclipse" | "runes"
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
        if spec == 3 then return { pt = P_ORBS, kind = "pips" } end
    elseif class == "WARLOCK" then
        if spec == 1 then return { pt = P_SOUL, kind = "pips" }
        elseif spec == 2 then return { pt = P_FURY, kind = "bar" }
        elseif spec == 3 then return { pt = P_EMBERS, kind = "segments", segs = 4 } end
    elseif class == "DRUID" then
        if spec == 1 then return { pt = P_ECLIPSE, kind = "eclipse" }
        elseif spec == 2 then return { pt = P_COMBO, kind = "pips", catOnly = true } end
    end
    return nil
end

local function inCatForm()
    -- Cat is form index 2 for Druids on MoP. GetShapeshiftForm() is enough here.
    return (GetShapeshiftForm and GetShapeshiftForm() == 2) or false
end

-- ---------------------------------------------------------------------------
--  Widget construction
-- ---------------------------------------------------------------------------
local function rowHeight() return cfg("classPowerHeight") or 5 end

local function makeCell(w)
    local cell = CreateFrame("Frame", nil, w)
    cell.bg = cell:CreateTexture(nil, "BACKGROUND")
    cell.bg:SetAllPoints(cell)
    cell.bg:SetTexture(WHITE)
    cell.bg:SetVertexColor(0.05, 0.05, 0.05, 0.85)
    cell.tex = cell:CreateTexture(nil, "ARTWORK")
    cell.tex:SetPoint("TOPLEFT", cell, "TOPLEFT", 1, -1)
    cell.tex:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -1, 1)
    cell.tex:SetTexture(WHITE)
    return cell
end

local function ensureCells(w, n)
    w.cells = w.cells or {}
    for i = #w.cells + 1, n do
        w.cells[i] = makeCell(w)
    end
end

local function layoutCells(w, n)
    local total = w:GetWidth()
    if not total or total <= 0 then
        total = (w._plate and w._plate.health and w._plate.health:GetWidth()) or 120
    end
    local gap = 2
    local cw = (total - gap * (n - 1)) / n
    if cw < 1 then cw = 1 end
    local h = rowHeight()
    for i = 1, n do
        local cell = w.cells[i]
        cell:ClearAllPoints()
        cell:SetSize(cw, h)
        cell:SetPoint("LEFT", w, "LEFT", (i - 1) * (cw + gap), 0)
    end
end

local function ensureBar(w)
    if w.bar then return w.bar end
    local b = CreateFrame("StatusBar", nil, w)
    b:SetAllPoints(w)
    b:SetStatusBarTexture(WHITE)
    b:SetMinMaxValues(0, 1)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints(b)
    b.bg:SetTexture(WHITE)
    b.bg:SetVertexColor(0.05, 0.05, 0.05, 0.85)
    w.bar = b
    return b
end

local function hideCells(w)
    if w.cells then for _, c in ipairs(w.cells) do c:Hide() end end
end
local function hideBar(w)
    if w.bar then w.bar:Hide() end
end

-- ---------------------------------------------------------------------------
--  Renderers
-- ---------------------------------------------------------------------------
local function renderPips(w, pt, maxOverride)
    hideBar(w)
    local max = maxOverride or (UnitPowerMax("player", pt) or 0)
    if max <= 0 then return false end
    local cur = UnitPower("player", pt) or 0
    local col = SEC_COLOR[pt] or { 0.9, 0.9, 0.4 }
    ensureCells(w, max)
    for i = 1, max do
        local cell = w.cells[i]
        cell.tex:SetVertexColor(col[1], col[2], col[3])
        cell.tex:SetAlpha(i <= cur and 1 or 0.18)
        cell:Show()
    end
    for i = max + 1, #w.cells do w.cells[i]:Hide() end
    layoutCells(w, max)
    return true
end

local function renderSegments(w, pt, segs)
    hideBar(w)
    local max = UnitPowerMax("player", pt) or 0
    if max <= 0 or segs <= 0 then return false end
    local cur = UnitPower("player", pt) or 0
    local per = max / segs
    local filled = per > 0 and floor(cur / per + 0.0001) or 0
    local col = SEC_COLOR[pt] or { 0.86, 0.46, 0.20 }
    ensureCells(w, segs)
    for i = 1, segs do
        local cell = w.cells[i]
        cell.tex:SetVertexColor(col[1], col[2], col[3])
        cell.tex:SetAlpha(i <= filled and 1 or 0.18)
        cell:Show()
    end
    for i = segs + 1, #w.cells do w.cells[i]:Hide() end
    layoutCells(w, segs)
    return true
end

local function renderRunes(w)
    hideBar(w)
    ensureCells(w, 6)
    for i = 1, 6 do
        local cell = w.cells[i]
        local rtype = (GetRuneType and GetRuneType(i)) or 1
        local col = RUNE_COLOR[rtype] or RUNE_COLOR[1]
        local ready = true
        if GetRuneCooldown then
            local _, _, isReady = GetRuneCooldown(i)
            ready = isReady ~= false
        end
        cell.tex:SetVertexColor(col[1], col[2], col[3])
        cell.tex:SetAlpha(ready and 1 or 0.18)
        cell:Show()
    end
    for i = 7, #w.cells do w.cells[i]:Hide() end
    layoutCells(w, 6)
    return true
end

local function renderBar(w, pt)
    hideCells(w)
    local max = UnitPowerMax("player", pt) or 0
    if max <= 0 then return false end
    local cur = UnitPower("player", pt) or 0
    local b = ensureBar(w)
    local col = SEC_COLOR[pt] or { 0.66, 0.30, 0.76 }
    b:SetStatusBarColor(col[1], col[2], col[3])
    b:SetMinMaxValues(0, max)
    b:SetValue(cur)
    b:Show()
    return true
end

local function renderEclipse(w, pt)
    hideCells(w)
    local max = UnitPowerMax("player", pt) or 0
    if max <= 0 then return false end
    local cur = UnitPower("player", pt) or 0
    local b = ensureBar(w)
    -- Direction: prefer the API, fall back to the sign of the value.
    local dir = GetEclipseDirection and GetEclipseDirection() or nil
    local col
    if dir == "moon" or cur < 0 then
        col = ECLIPSE_LUNAR
    elseif dir == "sun" or cur > 0 then
        col = ECLIPSE_SOLAR
    else
        col = { 0.6, 0.6, 0.6 }
    end
    b:SetStatusBarColor(col[1], col[2], col[3])
    b:SetMinMaxValues(0, max)
    b:SetValue(math.abs(cur))
    b:Show()
    return true
end

-- ---------------------------------------------------------------------------
--  Public: attach + update
-- ---------------------------------------------------------------------------
function ns.AttachClassPower(plate)
    if plate._cpow then return end
    -- only meaningful for classes/specs that have a secondary resource; the
    -- widget is created lazily but cheaply on every plate and stays hidden
    -- otherwise.
    local w = CreateFrame("Frame", nil, plate)
    w._plate = plate
    w:SetPoint("BOTTOMLEFT", plate.health, "TOPLEFT", 0, 3)
    w:SetPoint("BOTTOMRIGHT", plate.health, "TOPRIGHT", 0, 3)
    w:SetHeight(rowHeight())
    w:Hide()
    plate._cpow = w
end

function ns.UpdateClassPower(plate)
    local w = plate and plate._cpow
    if not w then return end

    if not cfg("showClassPower") then w:Hide(); return end
    local unit = plate.unit
    if not unit then w:Hide(); return end

    -- target-only (default) vs. all attackable enemy plates
    if cfg("classPowerTargetOnly") ~= false then
        if not UnitIsUnit(unit, "target") then w:Hide(); return end
    end

    local res = SecondaryResource()
    if not res then w:Hide(); return end
    if res.catOnly and not inCatForm() then w:Hide(); return end

    w:SetHeight(rowHeight())

    local ok
    if res.kind == "runes" then
        ok = renderRunes(w)
    elseif res.kind == "pips" then
        ok = renderPips(w, res.pt)
    elseif res.kind == "segments" then
        ok = renderSegments(w, res.pt, res.segs or 4)
    elseif res.kind == "bar" then
        ok = renderBar(w, res.pt)
    elseif res.kind == "eclipse" then
        ok = renderEclipse(w, res.pt)
    end

    if ok then w:Show() else w:Hide() end
end

-- ---------------------------------------------------------------------------
--  Event driver (own frame; resolves the relevant plate via core accessors)
-- ---------------------------------------------------------------------------
local function refreshTarget()
    if not C_NamePlate then return end
    local np = C_NamePlate.GetNamePlateForUnit("target")
    local plate = np and ns.PlateForNameplate and ns.PlateForNameplate(np)
    if plate then ns.UpdateClassPower(plate) end
end

local function refreshAll()
    if ns.ForEachPlate then
        ns.ForEachPlate(function(p) ns.UpdateClassPower(p) end)
    end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_TARGET_CHANGED")
ev:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
ev:RegisterEvent("UNIT_DISPLAYPOWER")
ev:RegisterEvent("UNIT_POWER_FREQUENT")
ev:RegisterEvent("UNIT_POWER_UPDATE")
ev:RegisterEvent("UNIT_MAXPOWER")
ev:RegisterEvent("RUNE_POWER_UPDATE")
ev:RegisterEvent("RUNE_TYPE_UPDATE")
ev:SetScript("OnEvent", function(_, event, unit)
    if event == "UNIT_POWER_FREQUENT" or event == "UNIT_POWER_UPDATE"
       or event == "UNIT_MAXPOWER" then
        if unit == "player" then
            if cfg("classPowerTargetOnly") ~= false then refreshTarget() else refreshAll() end
        end
    elseif event == "RUNE_POWER_UPDATE" or event == "RUNE_TYPE_UPDATE" then
        if cfg("classPowerTargetOnly") ~= false then refreshTarget() else refreshAll() end
    else
        -- target change, spec change, displaypower swap, world enter:
        -- re-evaluate every plate (resource type or visibility may change).
        refreshAll()
    end
end)

-- Options page nudges this after toggling settings.
function ns.RefreshClassPower()
    refreshAll()
end

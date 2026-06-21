-- ===========================================================================
--  OldschoolUI -- Nameplates  NP-3: auras (debuffs + buffs + crowd control)
--  Slot-based aura display: debuffs (top, player-filtered), buffs (left) and
--  crowd-control (right, matched against a curated CC spell set). Each icon has
--  a cooldown swipe, stack count, countdown number, and optional pandemic glow.
--  Clean-room: own implementation.
-- ===========================================================================
local ADDON, ns = ...
local OUI = OldschoolUI
if not OUI then return end

local cfg      = ns.cfg
local fontPath = ns.fontPath
if not cfg then return end

-- Curated crowd-control spell set (MoP). Factual data; extend as needed.
local CC_SET = {
    [118]=true,[61305]=true,[28272]=true,[28271]=true,[61721]=true,[61780]=true, -- Polymorph variants
    [51514]=true,                       -- Hex
    [5782]=true,[6358]=true,            -- Fear, Seduction
    [8122]=true,                        -- Psychic Scream
    [605]=true,                         -- Mind Control
    [20066]=true,                       -- Repentance
    [853]=true,                         -- Hammer of Justice
    [2637]=true,                        -- Hibernate
    [3355]=true,[19386]=true,[19503]=true, -- Freezing Trap, Wyvern Sting, Scatter Shot
    [2094]=true,[6770]=true,[1833]=true,[408]=true,[1776]=true, -- Blind, Sap, Cheap Shot, Kidney Shot, Gouge
    [33786]=true,[339]=true,[22570]=true,[5211]=true,[9005]=true, -- Cyclone, Entangling Roots, Maim, Bash, Pounce
    [710]=true,                         -- Banish
    [5246]=true,[7922]=true,            -- Intimidating Shout, Charge stun
    [107570]=true,[46968]=true,[105593]=true, -- Storm Bolt, Shockwave, Fist of Justice
    [31661]=true,[44572]=true,[82691]=true,[122]=true, -- Dragon's Breath, Deep Freeze, Ring of Frost, Frost Nova
    [115078]=true,[119381]=true,        -- Paralysis, Leg Sweep
    [24394]=true,                       -- Intimidation
    [113724]=true,                      -- Ring of Peace (silence-ish)
}

-- ---------------------------------------------------------------------------
--  Slot configuration
-- ---------------------------------------------------------------------------
local function sizeOf(slot)
    if slot == "buff" then return cfg("buffIconSize") or 24
    elseif slot == "cc" then return cfg("ccIconSize") or 24
    else return cfg("debuffIconSize") or 26 end
end
local function maxOf(slot)
    if slot == "buff" then return cfg("maxBuffs") or 4
    elseif slot == "cc" then return cfg("maxCC") or 3
    else return cfg("maxDebuffs") or 5 end
end
local function sideOf(slot)
    if slot == "buff" then return cfg("buffSlot") or "left"
    elseif slot == "cc" then return cfg("ccSlot") or "right"
    else return cfg("debuffSlot") or "top" end
end
local function spacing() return cfg("auraSpacing") or 2 end

-- ---------------------------------------------------------------------------
--  Aura scan
-- ---------------------------------------------------------------------------
local function scan(unit, filter, cb)
    if AuraUtil and AuraUtil.ForEachAura then
        AuraUtil.ForEachAura(unit, filter, 40, function(a) return cb(a) end, true)
    elseif C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for i = 1, 40 do
            local a = C_UnitAuras.GetAuraDataByIndex(unit, i, filter)
            if not a then break end
            if cb(a) then break end
        end
    else
        for i = 1, 40 do
            local name, icon, count, _, duration, expiration, source, _, _, spellId = UnitAura(unit, i, filter)
            if not name then break end
            if cb({ icon = icon, applications = count, duration = duration, expirationTime = expiration,
                    sourceUnit = source, spellId = spellId,
                    isFromPlayerOrPlayerPet = (source == "player") }) then break end
        end
    end
end

local function pack(a)
    return {
        icon = a.icon,
        count = a.applications or a.charges or 0,
        duration = a.duration or 0,
        expiration = a.expirationTime or 0,
    }
end

-- ---------------------------------------------------------------------------
--  Icon button
-- ---------------------------------------------------------------------------
local function makeIcon(parent)
    local b = CreateFrame("Frame", nil, parent)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1); b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if OUI.PP and OUI.PP.CreateBorder then OUI.PP.CreateBorder(b, 0.067, 0.067, 0.067, 1) end
    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints(b.icon); b.cd:SetDrawEdge(false)
    if b.cd.SetHideCountdownNumbers then b.cd:SetHideCountdownNumbers(true) end
    b.dur = b:CreateFontString(nil, "OVERLAY"); b.dur:SetPoint("CENTER", 0, 0)
    b.stack = b:CreateFontString(nil, "OVERLAY"); b.stack:SetPoint("BOTTOMRIGHT", 1, -1)
    b.glow = b:CreateTexture(nil, "BACKGROUND")
    b.glow:SetPoint("TOPLEFT", -2, 2); b.glow:SetPoint("BOTTOMRIGHT", 2, -2); b.glow:Hide()
    return b
end

-- ---------------------------------------------------------------------------
--  Attach the three slot containers + a shared countdown ticker
-- ---------------------------------------------------------------------------
function ns.AttachAuras(plate)
    if plate.auraSlots then return end
    plate.auraSlots = {}
    for _, slot in ipairs({ "debuff", "buff", "cc" }) do
        local c = CreateFrame("Frame", nil, plate)
        c.icons = {}
        c._slot = slot
        plate.auraSlots[slot] = c
    end

    plate._auraTick = CreateFrame("Frame", nil, plate)
    plate._auraTick:SetScript("OnUpdate", function(self, elapsed)
        self._acc = (self._acc or 0) + elapsed
        if self._acc < 0.1 then return end
        self._acc = 0
        local now = GetTime()
        local pandemic, gc = cfg("pandemicGlow"), cfg("pandemicGlowColor")
        for _, c in pairs(plate.auraSlots) do
            for _, b in ipairs(c.icons) do
                if b:IsShown() and b._expiration and b._expiration > 0 then
                    local remain = b._expiration - now
                    b.dur:SetText(remain <= 0 and "" or (remain >= 60 and string.format("%dm", remain / 60) or string.format("%d", remain + 0.5)))
                    if pandemic and c._slot == "debuff" and b._duration and b._duration > 0 and remain > 0 and remain <= b._duration * 0.3 then
                        b.glow:SetColorTexture(gc.r, gc.g, gc.b, 0.9); b.glow:Show()
                    else
                        b.glow:Hide()
                    end
                else
                    b.dur:SetText(""); b.glow:Hide()
                end
            end
        end
    end)
end

-- ---------------------------------------------------------------------------
--  Layout a slot's icons by side (top / left / right)
-- ---------------------------------------------------------------------------
local function positionSlot(plate, slot, count)
    local c = plate.auraSlots[slot]
    local sz, gap, side = sizeOf(slot), spacing(), sideOf(slot)
    local total = math.max(count * sz + (count - 1) * gap, 1)
    c:ClearAllPoints()
    c:SetSize(total, sz)
    if side == "top" then
        c:SetPoint("BOTTOM", plate.name, "TOP", 0, cfg("debuffYOffset") or 4)
    elseif side == "left" then
        c:SetPoint("RIGHT", plate, "LEFT", -gap, 0)
    else -- right
        c:SetPoint("LEFT", plate, "RIGHT", gap, 0)
    end
    local fp = fontPath()
    for i, b in ipairs(c.icons) do
        if i <= count then
            b:SetSize(sz, sz)
            b:ClearAllPoints()
            b:SetPoint("LEFT", c, "LEFT", (i - 1) * (sz + gap), 0)
            b.dur:SetFont(fp, cfg("auraDurationTextSize") or 11, "OUTLINE")
            b.stack:SetFont(fp, cfg("auraStackTextSize") or 11, "OUTLINE")
            local dc = cfg("auraDurationTextColor"); b.dur:SetTextColor(dc.r, dc.g, dc.b)
            local sc = cfg("auraStackTextColor"); b.stack:SetTextColor(sc.r, sc.g, sc.b)
            b:Show()
        else
            b:Hide()
        end
    end
end

local function populate(plate, slot, list)
    local c = plate.auraSlots[slot]
    local n = #list
    for i = #c.icons + 1, n do c.icons[i] = makeIcon(c) end
    positionSlot(plate, slot, n)
    for i = 1, n do
        local d, b = list[i], c.icons[i]
        b.icon:SetTexture(d.icon)
        b._expiration, b._duration = d.expiration, d.duration
        b.stack:SetText((d.count and d.count > 1) and d.count or "")
        if d.duration > 0 and d.expiration > 0 then b.cd:SetCooldown(d.expiration - d.duration, d.duration)
        else b.cd:Clear() end
    end
    for i = n + 1, #c.icons do c.icons[i]:Hide() end
    c:SetShown(n > 0)
end

-- ---------------------------------------------------------------------------
--  Update (scan + distribute)
-- ---------------------------------------------------------------------------
function ns.UpdateAuras(plate)
    local unit = plate.unit
    if not (plate.auraSlots and unit) then return end
    local maxD, maxB, maxC = maxOf("debuff"), maxOf("buff"), maxOf("cc")
    local playerOnly = not cfg("showAllDebuffs")

    local debuffs, ccs, buffs = {}, {}, {}
    scan(unit, "HARMFUL", function(a)
        if a.spellId and CC_SET[a.spellId] then
            if #ccs < maxC then ccs[#ccs + 1] = pack(a) end
        else
            local mine = a.isFromPlayerOrPlayerPet or a.sourceUnit == "player"
            if (not playerOnly or mine) and #debuffs < maxD then debuffs[#debuffs + 1] = pack(a) end
        end
        return #ccs >= maxC and #debuffs >= maxD
    end)
    scan(unit, "HELPFUL", function(a)
        if #buffs < maxB then buffs[#buffs + 1] = pack(a) end
        return #buffs >= maxB
    end)

    populate(plate, "debuff", debuffs)
    populate(plate, "buff", buffs)
    populate(plate, "cc", ccs)
end

-- ---------------------------------------------------------------------------
--  Events + options refresh
-- ---------------------------------------------------------------------------
local _origRefresh = ns.RefreshAllSettings
function ns.RefreshAllSettings()
    if _origRefresh then _origRefresh() end
    for _, plate in pairs(ns.plates) do
        if plate.unit and plate.auraSlots then ns.UpdateAuras(plate) end
    end
end

local auraWatcher = CreateFrame("Frame")
auraWatcher:RegisterEvent("UNIT_AURA")
auraWatcher:SetScript("OnEvent", function(_, _, unit)
    local plate = ns.platesByUnit[unit]
    if plate then ns.UpdateAuras(plate) end
end)

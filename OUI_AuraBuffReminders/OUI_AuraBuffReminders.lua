-------------------------------------------------------------------------------
--  OldschoolUI -- Aura & Buff Reminders  (clean-room rewrite, MoP 5.5.x)
--  ABR-1: core engine
--    * movable anchor + Core /ouimove mover
--    * pool of clickable SecureActionButton reminder icons (click -> cast/use)
--    * Refresh registry of reminder definitions (raid buffs, self auras, ...)
--    * row layout, text labels, alert sound, instance gating
--    * combat-safe: all secure attr / show-hide / layout changes happen OOC;
--      icons configured pre-combat stay clickable, new ones appear after combat
-------------------------------------------------------------------------------

local OUI = OldschoolUI
if not OUI then return end

local L = OUI.L or function(s) return s end

local ABR = LibStub("AceAddon-3.0"):NewAddon("OldschoolUIAuraBuffReminders", "AceEvent-3.0")
OUI.ABR = ABR

local _, PLAYER_CLASS = UnitClass("player")

-------------------------------------------------------------------------------
--  SavedVariables defaults
-------------------------------------------------------------------------------
local defaults = {
    profile = {
        enabled       = true,
        iconSize      = 40,
        spacing       = 8,
        scale         = 1.0,
        opacity       = 1.0,
        strata        = "MEDIUM",
        point         = "CENTER",
        relPoint      = "CENTER",
        x             = 0,
        y             = 220,
        showText      = true,
        textSize      = 12,
        textColor     = { r = 1, g = 1, b = 1 },
        sound         = "none",   -- "none" | media key
        -- per-category instance gating: show even outside instances?
        showNonInstanced = {
            raidBuffs   = false,
            selfAuras   = true,
            classKits   = true,
            pets        = true,
            consumables = false,
        },
        -- per-reminder enable flags (keyed by def.key)
        enabled_keys = {
            -- raid buffs (only the player's own class matters)
            motw = true, bshout = true, cshout = false, fort = true, ai = true,
            kings = true, might = false, legacy = true, horn = true,
            -- self auras / forms
            shadowform = true,
            def_stance = false, berserk_stance = false, battle_stance = false,
            -- class kits
            pala_seal = true, rogue_poison = true, sham_shield = true, sham_imbue = true,
            -- pets / consumables / items
            pet = true, flask = true, food = true, healthstone = true,
        },
    },
}

-------------------------------------------------------------------------------
--  Reminder definitions  (MoP-valid spell IDs; verify in-game)
--    key       unique id, used for enable flags + sound de-dupe
--    class     only shown for this player class
--    spec      optional spec index gate (C_SpecializationInfo.GetSpecialization)
--    name      tooltip / label text
--    cast      spellID applied on click (type="spell")
--    buffs     aura IDs that satisfy the reminder (any present -> not missing)
--    check     "raid" (group-missing) | "self" (player missing a self aura)
-------------------------------------------------------------------------------
local DEFS = {
    -- ---- Raid buffs --------------------------------------------------------
    { key = "motw",   class = "DRUID",       name = "Mark of the Wild",      cast = 1126,   buffs = { 1126 },  check = "raid", cat = "raidBuffs" },
    { key = "bshout", class = "WARRIOR",     name = "Battle Shout",          cast = 6673,   buffs = { 6673 },  check = "raid", cat = "raidBuffs" },
    { key = "cshout", class = "WARRIOR",     name = "Commanding Shout",      cast = 469,    buffs = { 469 },   check = "raid", cat = "raidBuffs" },
    { key = "fort",   class = "PRIEST",      name = "Power Word: Fortitude", cast = 21562,  buffs = { 21562 }, check = "raid", cat = "raidBuffs" },
    { key = "ai",     class = "MAGE",        name = "Arcane Brilliance",     cast = 1459,   buffs = { 1459 },  check = "raid", cat = "raidBuffs" },
    { key = "kings",  class = "PALADIN",     name = "Blessing of Kings",     cast = 20217,  buffs = { 20217 }, check = "raid", cat = "raidBuffs" },
    { key = "might",  class = "PALADIN",     name = "Blessing of Might",     cast = 19740,  buffs = { 19740 }, check = "raid", cat = "raidBuffs" },
    { key = "legacy", class = "MONK",        name = "Legacy of the Emperor", cast = 115921, buffs = { 115921 },check = "raid", cat = "raidBuffs" },
    { key = "horn",   class = "DEATHKNIGHT", name = "Horn of Winter",        cast = 57330,  buffs = { 57330 }, check = "raid", cat = "raidBuffs" },
    { key = "motw",   class = "DRUID",       name = "Mark of the Wild",      cast = 1126,   buffs = { 1126 },   check = "raid", cat = "raidBuffs" },
    { key = "dintent",class = "WARLOCK",     name = "Dark Intent",           cast = 109773, buffs = { 109773 }, check = "raid", cat = "raidBuffs" },
    -- ---- Self auras / forms / stances --------------------------------------
    { key = "shadowform",     class = "PRIEST",  spec = 3, name = "Shadowform",        cast = 15473, buffs = { 15473 }, check = "self", cat = "selfAuras" },
    { key = "def_stance",     class = "WARRIOR", name = "Defensive Stance",  cast = 71,   buffs = { 71 },   check = "self", cat = "selfAuras" },
    { key = "berserk_stance", class = "WARRIOR", name = "Berserker Stance",  cast = 2458, buffs = { 2458 }, check = "self", cat = "selfAuras" },
    { key = "battle_stance",  class = "WARRIOR", name = "Battle Stance",     cast = 2457, buffs = { 2457 }, check = "self", cat = "selfAuras" },
    -- ---- Class kits --------------------------------------------------------
    { key = "pala_seal",    class = "PALADIN", name = "Seal",          cast = 20165, buffs = { 20165, 20154, 31801, 20164, 105361 }, check = "self",        cat = "classKits" },
    { key = "rogue_poison", class = "ROGUE",   name = "Lethal Poison", cast = 2823,  buffs = { 2823, 8679 },                        check = "self",        cat = "classKits" },
    { key = "sham_shield",  class = "SHAMAN",  name = "Shield",        cast = 324,   buffs = { 324, 52127, 974 },                   check = "self",        cat = "classKits" },
    { key = "sham_imbue",   class = "SHAMAN",  name = "Weapon Imbue",  cast = 8024,                                                 check = "weaponImbue", cat = "classKits" },
    -- ---- Pets --------------------------------------------------------------
    { key = "pet", class = "HUNTER",  name = "Call Pet",     cast = 883, check = "pet", cat = "pets" },
    { key = "pet", class = "WARLOCK", name = "Summon Demon", cast = 688, check = "pet", action = "none", cat = "pets" },
    -- ---- Consumables -------------------------------------------------------
    { key = "flask", name = "Flask", check = "consumable", cat = "consumables", action = "item",
      buffs = { 105689, 105691, 105693, 105694, 105696 },   -- MoP flasks: Agi/Int/Str/Spirit/Stam
      items = { 76087, 76084, 76088, 76085, 76086 },         -- MoP flask items (Int/Agi/Stam/Str/Spirit)
      icon  = "Interface\\Icons\\inv_alchemy_endlessflask_06" },
    { key = "food", name = "Well Fed", check = "wellfed", cat = "consumables", action = "none",
      icon = "Interface\\Icons\\inv_misc_food_15" },
    -- ---- Items -------------------------------------------------------------
    { key = "healthstone", class = "WARLOCK", name = "Healthstone", cast = 6201, check = "bagItem",
      items = { 5512 }, cat = "consumables" },
}

-------------------------------------------------------------------------------
--  Alert sounds (Blizzard built-in sound kits -- no bundled assets)
-------------------------------------------------------------------------------
local SOUNDS = {
    none         = nil,
    ready_check  = 8960,   -- SOUNDKIT.READY_CHECK
    raid_warning = 8959,   -- SOUNDKIT.RAID_WARNING
    map_ping     = 3175,   -- map ping
    auction      = 5274,   -- auction window open
}

-------------------------------------------------------------------------------
--  Helpers
-------------------------------------------------------------------------------
local function fontPath()
    return (OUI.GetFontPath and OUI.GetFontPath()) or STANDARD_TEXT_FONT
end

local function playerKnows(spellID)
    if not spellID then return false end
    if IsPlayerSpell and IsPlayerSpell(spellID) then return true end
    if IsSpellKnown and IsSpellKnown(spellID) then return true end
    return false
end

-- player has any of the given aura IDs
local function selfHasBuff(ids)
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        for i = 1, #ids do
            if C_UnitAuras.GetPlayerAuraBySpellID(ids[i]) then return true end
        end
    end
    for i = 1, 40 do
        local aura = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
            and C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        local sid = aura and aura.spellId
        if not aura then
            local name, _, _, _, _, _, _, _, _, sid2 = UnitBuff("player", i)
            if not name then break end
            sid = sid2
        end
        if sid then
            for j = 1, #ids do if sid == ids[j] then return true end end
        end
    end
    return false
end

-- a specific group unit has any of the aura IDs (helpful)
local function unitHasBuff(unit, ids)
    for i = 1, 40 do
        local aura = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
            and C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
        local sid = aura and aura.spellId
        if not aura then
            local name, _, _, _, _, _, _, _, _, sid2 = UnitBuff(unit, i)
            if not name then break end
            sid = sid2
        end
        if sid then
            for j = 1, #ids do if sid == ids[j] then return true end end
        end
    end
    return false
end

local function inRange(unit)
    if UnitInRange then
        local ok = UnitInRange(unit)
        return ok and true or false
    end
    return true
end

-------------------------------------------------------------------------------
--  Condition checks
-------------------------------------------------------------------------------
-- raid buff: player can cast it AND self or any in-range group member misses it
local function checkRaid(def)
    if not playerKnows(def.cast) then return false end
    if not selfHasBuff(def.buffs) then return true end
    local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    if n > 1 then
        local raid = IsInRaid and IsInRaid()
        local prefix = raid and "raid" or "party"
        local count = raid and n or (n - 1)
        for i = 1, count do
            local unit = prefix .. i
            if UnitExists(unit) and not UnitIsDeadOrGhost(unit) and inRange(unit) then
                if not unitHasBuff(unit, def.buffs) then return true end
            end
        end
    end
    return false
end

-- self aura: player can cast it and is missing it
local function checkSelf(def)
    if not playerKnows(def.cast) then return false end
    return not selfHasBuff(def.buffs)
end

-- shaman / any: main-hand weapon has no temporary imbue
local function checkWeaponImbue(def)
    if GetWeaponEnchantInfo then
        local hasMH = GetWeaponEnchantInfo()
        return not hasMH
    end
    return false
end

-- pet classes missing their pet (warlock with Grimoire of Sacrifice wants none)
local function checkPet(def)
    if UnitExists("pet") then return false end
    if PLAYER_CLASS == "WARLOCK" and selfHasBuff({ 108503 }) then return false end
    return true
end

-- no copy of the tracked item left in bags
local function checkBagItem(def)
    if not def.items then return false end
    for _, id in ipairs(def.items) do
        if (GetItemCount and GetItemCount(id) or 0) > 0 then return false end
    end
    return true
end

-- common MoP "Well Fed" food buffs (verify/extend in-game)
local WELLFED_IDS = {
    104264, 104267, 104271, 104272, 104273, 104280, 104283,
    125070, 124219, 124220, 124221, 124222, 124223, 124224,
}
local function checkWellfed(def)
    if selfHasBuff(WELLFED_IDS) then return false end
    -- name fallback (enUS): aura name carries the food, tooltip says Well Fed,
    -- so we also catch the generic case where the food name is unknown.
    for i = 1, 40 do
        local aura = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
            and C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        local nm = aura and aura.name
        if not aura then nm = UnitBuff("player", i) end
        if not nm then break end
        if type(nm) == "string" and nm:find("Well Fed") then return false end
    end
    return true
end

local CHECKERS = {
    raid        = checkRaid,
    self        = checkSelf,
    consumable  = function(def) return not selfHasBuff(def.buffs) end,
    weaponImbue = checkWeaponImbue,
    pet         = checkPet,
    bagItem     = checkBagItem,
    wellfed     = checkWellfed,
}

-------------------------------------------------------------------------------
--  Instance gating
-------------------------------------------------------------------------------
local function inInstance()
    local _, t = IsInInstance()
    return t == "party" or t == "raid" or t == "scenario"
end

function ABR:DefVisible(def)
    if inInstance() then return true end
    local g = self.db.profile.showNonInstanced
    return g and g[def.cat] or false
end

function ABR:DefEnabled(def)
    if def.class and def.class ~= PLAYER_CLASS then return false end
    if def.spec and C_SpecializationInfo and C_SpecializationInfo.GetSpecialization then
        local s = C_SpecializationInfo.GetSpecialization()
        if s and GetNumSpecializations and s <= GetNumSpecializations() and s ~= def.spec then
            return false
        end
    end
    local ek = self.db.profile.enabled_keys
    return ek and ek[def.key] ~= false
end

-------------------------------------------------------------------------------
--  Icon pool (SecureActionButton)
-------------------------------------------------------------------------------
local MAX_ICONS = 16

function ABR:AcquireIcon(i)
    if self.icons[i] then return self.icons[i] end
    local b = CreateFrame("Button", "OUIABRIcon" .. i, self.anchor, "SecureActionButtonTemplate")
    b:RegisterForClicks("AnyUp")
    b:SetAttribute("unit", "player")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    if OUI.PP and OUI.PP.CreateBorder then OUI.PP.CreateBorder(b, 0, 0, 0, 0.9) end
    b.label = b:CreateFontString(nil, "OVERLAY")
    b.label:SetPoint("TOP", b, "BOTTOM", 0, -2)
    b:SetScript("OnEnter", function(self)
        if not self._name then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self._name, 1, 1, 1)
        GameTooltip:AddLine(L("Click to apply."), 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.icons[i] = b
    return b
end

local function spellTex(id)
    return (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id))
        or (GetSpellTexture and GetSpellTexture(id))
end

-- label shown on the icon / toggle: prefer the client-localized spell name,
-- fall back to the def's literal (which deDE then translates).
function ABR.DefLabel(def)
    if def.cast and GetSpellInfo then
        local n = GetSpellInfo(def.cast)
        if n and n ~= "" then return n end
    end
    return def.name
end

-- configure an icon's secure action + visuals (OOC only)
function ABR:ConfigureIcon(b, def)
    local action = def.action or "spell"
    local tex

    if action == "item" then
        local chosen
        if def.items then
            for _, id in ipairs(def.items) do
                if (GetItemCount and GetItemCount(id) or 0) > 0 then chosen = id; break end
            end
        end
        if chosen then
            b:SetAttribute("type", "item")
            b:SetAttribute("item", "item:" .. chosen)
            b:SetAttribute("spell", nil)
            b:SetAttribute("macrotext", nil)
            tex = GetItemIcon and GetItemIcon(chosen)
        else
            b:SetAttribute("type", nil)
            b:SetAttribute("item", nil)
            b:SetAttribute("spell", nil)
            b:SetAttribute("macrotext", nil)
        end
        tex = tex or def.icon
    elseif action == "macro" then
        b:SetAttribute("type", "macro")
        b:SetAttribute("macrotext", def.macro)
        b:SetAttribute("spell", nil)
        b:SetAttribute("item", nil)
        tex = def.icon or (def.cast and spellTex(def.cast))
    elseif action == "none" then
        b:SetAttribute("type", nil)
        b:SetAttribute("spell", nil)
        b:SetAttribute("item", nil)
        b:SetAttribute("macrotext", nil)
        tex = def.icon or (def.cast and spellTex(def.cast))
    else -- spell
        b:SetAttribute("type", "spell")
        b:SetAttribute("spell", def.cast)
        b:SetAttribute("item", nil)
        b:SetAttribute("macrotext", nil)
        tex = def.cast and spellTex(def.cast)
    end

    b._name = L(ABR.DefLabel(def))
    b.icon:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
end

-------------------------------------------------------------------------------
--  Layout + visuals
-------------------------------------------------------------------------------
function ABR:ApplyAnchor()
    local p = self.db.profile
    self.anchor:ClearAllPoints()
    self.anchor:SetPoint(p.point or "CENTER", UIParent, p.relPoint or p.point or "CENTER", p.x or 0, p.y or 0)
    self.anchor:SetScale(p.scale or 1)
    self.anchor:SetAlpha(p.opacity or 1)
    self.anchor:SetFrameStrata(p.strata or "MEDIUM")
end

function ABR:AnchorExtent()
    local p = self.db.profile
    local sz = p.iconSize or 40
    local count = self._activeCount or 1
    if count < 1 then count = 1 end
    local w = count * sz + (count - 1) * (p.spacing or 8)
    return w, sz
end

function ABR:LayoutActive(active)
    local p = self.db.profile
    local sz, sp = p.iconSize or 40, p.spacing or 8
    local count = #active
    self._activeCount = count

    local totalW = count * sz + (count - 1) * sp
    local startX = -totalW / 2 + sz / 2

    local newKeys = {}
    for i, def in ipairs(active) do
        local b = self:AcquireIcon(i)
        b:SetSize(sz, sz)
        b:ClearAllPoints()
        b:SetPoint("CENTER", self.anchor, "CENTER", startX + (i - 1) * (sz + sp), 0)
        self:ConfigureIcon(b, def)
        if p.showText then
            b.label:SetFont(fontPath(), p.textSize or 12, "OUTLINE")
            local c = p.textColor or { r = 1, g = 1, b = 1 }
            b.label:SetTextColor(c.r, c.g, c.b)
            b.label:SetText(L(ABR.DefLabel(def)))
            b.label:Show()
        else
            b.label:Hide()
        end
        b:Show()
        newKeys[def.key] = true
    end
    for i = count + 1, MAX_ICONS do
        if self.icons[i] then self.icons[i]:Hide() end
    end

    -- alert sound for newly-appearing reminders
    local prev = self._shownKeys or {}
    if p.sound and p.sound ~= "none" then
        local id = SOUNDS[p.sound]
        for k in pairs(newKeys) do
            if not prev[k] and id then
                PlaySound(id, "Master")
                break
            end
        end
    end
    self._shownKeys = newKeys

    -- size anchor (so the mover reflects the actual extent)
    self.anchor:SetSize((totalW > 0 and totalW) or sz, sz)
end

function ABR:HideAll()
    for i = 1, MAX_ICONS do
        if self.icons[i] then self.icons[i]:Hide() end
    end
    self._activeCount = 0
    self._shownKeys = {}
end

-------------------------------------------------------------------------------
--  Refresh (combat-safe)
-------------------------------------------------------------------------------
function ABR:Refresh()
    if not self.db.profile.enabled then self:HideAll(); return end
    if InCombatLockdown() then self._dirty = true; return end
    self._dirty = false

    local active = {}
    for _, def in ipairs(DEFS) do
        if self:DefEnabled(def) and self:DefVisible(def) then
            local fn = CHECKERS[def.check]
            if fn and fn(def) then active[#active + 1] = def end
        end
    end
    self:LayoutActive(active)
end

function ABR:RequestRefresh()
    if self._pending then return end
    self._pending = true
    C_Timer.After(0.1, function()
        self._pending = false
        self:Refresh()
    end)
end

-------------------------------------------------------------------------------
--  Mover
-------------------------------------------------------------------------------
function ABR:RegisterMover()
    if not (OUI.RegisterUnlockElements and OUI.MakeUnlockElement) then return end
    OUI:RegisterUnlockElements({
        OUI.MakeUnlockElement({
            key      = "OUIAuraReminders",
            label    = "Aura & Buff Reminders",
            getFrame = function() return ABR.anchor end,
            getSize  = function() return ABR:AnchorExtent() end,
            isHidden = function() return not ABR.db.profile.enabled end,
            savePos  = function(_, _, _, cx, cy)
                local prof = ABR.db.profile
                prof.point, prof.relPoint = "CENTER", "CENTER"
                prof.x = cx
                prof.y = cy
                ABR:ApplyAnchor()
            end,
            applyPos = function() ABR:ApplyAnchor() end,
        }),
    })
end

-------------------------------------------------------------------------------
--  Lifecycle
-------------------------------------------------------------------------------
function ABR:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("OldschoolUIAuraBuffRemindersDB", defaults, true)
    self.icons = {}
    self._shownKeys = {}

    self.anchor = CreateFrame("Frame", "OUIAuraReminderAnchor", UIParent)
    self.anchor:SetSize(40, 40)
    self:ApplyAnchor()
end

function ABR:OnEnable()
    if OUI.IsModuleEnabled and not OUI:IsModuleEnabled("OUI_AuraBuffReminders") then return end
    self:RegisterMover()

    self:RegisterEvent("PLAYER_ENTERING_WORLD", "RequestRefresh")
    self:RegisterEvent("UNIT_AURA", function(_, unit)
        if unit == "player" or (unit and unit:match("^party")) or (unit and unit:match("^raid")) then
            self:RequestRefresh()
        end
    end)
    self:RegisterEvent("GROUP_ROSTER_UPDATE", "RequestRefresh")
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "RequestRefresh")
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "RequestRefresh")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
        if self._dirty then self:Refresh() end
    end)

    self:RequestRefresh()
end

-- expose for options
ABR.DEFS = DEFS
ABR.SOUNDS = SOUNDS

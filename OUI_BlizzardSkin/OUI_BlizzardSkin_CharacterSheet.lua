-- ===========================================================================
--  OldschoolUI -- Custom Character Sheet
--  Stage 2a: window, model, equip slots (read-only display + tooltips)
--  Stage 2c (tabs): Character / Reputation (Ruf) / Currency (Abzeichen)
--  Our own themed frames so the pane follows the suite theme directly, rather
--  than fighting Blizzard's PaperDollFrame layout.
-- ===========================================================================
local _, ns = ...
local OUI = OldschoolUI
if not OUI then return end

local BS = ns.BS
local L = OUI.L or function(s) return s end

-- palette / helpers ---------------------------------------------------------
local function ac() return OUI.ACCENT.r, OUI.ACCENT.g, OUI.ACCENT.b end
local function fontPath() return (OUI.GetFontPath and OUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF" end
local BG      = { 0.06, 0.06, 0.07, 0.97 }
local SLOT_BG = { 0.12, 0.12, 0.13, 0.9 }
local BRD     = { 0.22, 0.22, 0.22, 1 }
local ROW_BG  = { 0.10, 0.10, 0.12, 0.6 }

-- equipment slots -----------------------------------------------------------
local LEFT_SLOTS   = { "HeadSlot", "NeckSlot", "ShoulderSlot", "BackSlot", "ChestSlot", "ShirtSlot", "TabardSlot", "WristSlot" }
local RIGHT_SLOTS  = { "HandsSlot", "WaistSlot", "LegsSlot", "FeetSlot", "Finger0Slot", "Finger1Slot", "Trinket0Slot", "Trinket1Slot" }
local WEAPON_SLOTS = { "MainHandSlot", "SecondaryHandSlot" }
local SLOT_SIZE = 40
local SLOT_GAP  = 6

local CS = {}
ns.CharacterSheet = CS

-- ---------------------------------------------------------------------------
--  Quality helpers
-- ---------------------------------------------------------------------------
local function QualityColor(q)
    local t = BAG_ITEM_QUALITY_COLORS or ITEM_QUALITY_COLORS
    return q and t and t[q]
end

local function ItemLevelOf(slotID)
    local link = GetInventoryItemLink("player", slotID)
    if not link then return nil end
    local _, _, _, ilvl = GetItemInfo(link)
    return ilvl
end

-- ---------------------------------------------------------------------------
--  A single equipment slot button
-- ---------------------------------------------------------------------------
local function CreateSlot(parent, slotName)
    local ok, id, emptyTex = pcall(GetInventorySlotInfo, slotName)
    if not ok or not id then return nil end   -- slot not valid in this client
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(SLOT_SIZE, SLOT_SIZE)
    b._slotID = id
    b._empty = emptyTex

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(SLOT_BG[1], SLOT_BG[2], SLOT_BG[3], SLOT_BG[4])

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    if OUI.PP and OUI.PP.CreateBorder then
        OUI.PP.CreateBorder(b, BRD[1], BRD[2], BRD[3], BRD[4])
    end

    b.ilvl = b:CreateFontString(nil, "OVERLAY")
    b.ilvl:SetFont(fontPath(), 11, "OUTLINE")
    b.ilvl:SetPoint("BOTTOMRIGHT", -1, 1)

    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    b.hl:SetColorTexture(ac())
    b.hl:SetAlpha(0.18)

    b:SetScript("OnEnter", function(self)
        if not GetInventoryItemTexture("player", self._slotID) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetInventoryItem("player", self._slotID)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Interactive equip / unequip / swap (out of combat; hardware-event driven).
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnClick", function(self)
        if InCombatLockdown() then return end
        if IsModifiedClick and IsModifiedClick("CHATLINK") then
            local link = GetInventoryItemLink("player", self._slotID)
            if link and HandleModifiedItemClick then HandleModifiedItemClick(link) end
            return
        end
        PickupInventoryItem(self._slotID)
    end)
    b:SetScript("OnDragStart", function(self)
        if InCombatLockdown() then return end
        PickupInventoryItem(self._slotID)
    end)
    b:SetScript("OnReceiveDrag", function(self)
        if InCombatLockdown() then return end
        PickupInventoryItem(self._slotID)
    end)
    return b
end

local function UpdateSlot(b)
    if not b then return end
    local tex = GetInventoryItemTexture("player", b._slotID)
    if tex then
        b.icon:SetTexture(tex)
        b.icon:SetAlpha(1)
        local ilvl = ItemLevelOf(b._slotID)
        b.ilvl:SetText(ilvl and ilvl > 1 and tostring(ilvl) or "")
    else
        b.icon:SetTexture(b._empty)
        b.icon:SetAlpha(0.35)
        b.ilvl:SetText("")
    end
    if OUI.PP and OUI.PP.SetBorderColor then
        local q = GetInventoryItemQuality("player", b._slotID)
        local c = QualityColor(q)
        if c and q and q >= 2 then
            OUI.PP.SetBorderColor(b, c.r, c.g, c.b, 1)
        else
            OUI.PP.SetBorderColor(b, BRD[1], BRD[2], BRD[3], BRD[4])
        end
    end
end

function CS:UpdateAll()
    if not self.slots then return end
    for _, b in pairs(self.slots) do UpdateSlot(b) end
    self:UpdateStats()
end

-- ---------------------------------------------------------------------------
--  Generic mouse-wheel scroll list (row pool, no template dependency)
-- ---------------------------------------------------------------------------
local function MakeScrollList(parent, rowHeight, makeRow)
    local sf = CreateFrame("Frame", nil, parent)
    sf.rows = {}
    sf.offset = 0
    sf.rowHeight = rowHeight
    sf.data = {}
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, delta)
        self.offset = math.max(0, math.min(self.maxOffset or 0, self.offset - delta))
        self:Refresh()
    end)
    function sf:Refresh()
        local n = #self.data
        local h = self:GetHeight()
        if h <= 0 then h = 360 end
        local visible = math.max(1, math.floor(h / self.rowHeight))
        self.maxOffset = math.max(0, n - visible)
        if self.offset > self.maxOffset then self.offset = self.maxOffset end
        for i = 1, visible do
            local row = self.rows[i]
            if not row then
                row = makeRow(self)
                row:SetPoint("TOPLEFT", 0, -(i - 1) * self.rowHeight)
                row:SetPoint("TOPRIGHT", 0, -(i - 1) * self.rowHeight)
                row:SetHeight(self.rowHeight - 2)
                self.rows[i] = row
            end
            local d = self.data[i + self.offset]
            if d then row:SetData(d); row:Show() else row:Hide() end
        end
        for i = visible + 1, #self.rows do self.rows[i]:Hide() end
    end
    return sf
end

-- ---------------------------------------------------------------------------
--  Reputation rows + data  (Ruf)  -- respects collapse; headers are clickable
-- ---------------------------------------------------------------------------
-- Busy flags: faction/currency mutations fire UPDATE_FACTION /
-- CURRENCY_DISPLAY_UPDATE synchronously, which would re-enter our refresh and
-- recurse. Suppress the event handler while we mutate.
local repBusy, curBusy = false, false

local function ToggleFactionHeader(index, collapse)
    pcall(function()
        if collapse then
            if C_Reputation and C_Reputation.CollapseFactionHeader then C_Reputation.CollapseFactionHeader(index)
            elseif CollapseFactionHeader then CollapseFactionHeader(index) end
        else
            if C_Reputation and C_Reputation.ExpandFactionHeader then C_Reputation.ExpandFactionHeader(index)
            elseif ExpandFactionHeader then ExpandFactionHeader(index) end
        end
    end)
end

local function RepFactions()
    local out = {}
    local num = (C_Reputation and C_Reputation.GetNumFactions and C_Reputation.GetNumFactions())
             or (GetNumFactions and GetNumFactions()) or 0
    for i = 1, num do
        local d
        if C_Reputation and C_Reputation.GetFactionDataByIndex then
            local fd = C_Reputation.GetFactionDataByIndex(i)
            if fd then
                d = {
                    index = i, name = fd.name, isHeader = fd.isHeader,
                    isCollapsed = fd.isCollapsed, reaction = fd.reaction,
                    min = fd.currentReactionThreshold, max = fd.nextReactionThreshold,
                    value = fd.currentStanding,
                    hasRep = (not fd.isHeader) or fd.isHeaderWithRep,
                }
            end
        else
            local name, _, standing, barMin, barMax, barValue, _, _, isHeader, isCollapsed, hasRep = GetFactionInfo(i)
            if name then
                d = { index = i, name = name, isHeader = isHeader, isCollapsed = isCollapsed,
                      reaction = standing, min = barMin, max = barMax, value = barValue,
                      hasRep = (not isHeader) or hasRep }
            end
        end
        if d then out[#out + 1] = d end
    end
    return out
end

local function SetWatched(index)
    repBusy = true
    pcall(function()
        if C_Reputation and C_Reputation.SetWatchedFactionByIndex then C_Reputation.SetWatchedFactionByIndex(index)
        elseif SetWatchedFactionIndex then SetWatchedFactionIndex(index) end
    end)
    repBusy = false
end

local function RepRowMenu(row, d)
    if not d or d.isHeader then return end
    local idx = d.index
    if MenuUtil and MenuUtil.CreateContextMenu then
        MenuUtil.CreateContextMenu(row, function(_, root)
            root:CreateTitle(d.name or "")
            root:CreateButton(L("Show on reputation bar"), function() SetWatched(idx) end)
            root:CreateButton(L("Hide from reputation bar"), function() SetWatched(0) end)
        end)
    end
end

local function MakeRepRow(sf)
    local r = CreateFrame("Button", nil, sf)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local bg = r:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(ROW_BG[1], ROW_BG[2], ROW_BG[3], ROW_BG[4])
    r._bg = bg

    r.bar = CreateFrame("StatusBar", nil, r)
    r.bar:SetPoint("BOTTOMLEFT", 6, 2)
    r.bar:SetPoint("BOTTOMRIGHT", -6, 2)
    r.bar:SetHeight(6)
    r.bar:SetStatusBarTexture((OUI.GetBarTexturePath and OUI.GetBarTexturePath()) or "Interface\\Buttons\\WHITE8X8")

    r.arrow = r:CreateFontString(nil, "OVERLAY")
    r.arrow:SetFont(fontPath(), 12, "")
    r.arrow:SetPoint("LEFT", 5, 0)

    r.name = r:CreateFontString(nil, "OVERLAY")
    r.name:SetFont(fontPath(), 12, "")
    r.name:SetPoint("TOPLEFT", 18, -3)

    r.standing = r:CreateFontString(nil, "OVERLAY")
    r.standing:SetFont(fontPath(), 11, "")
    r.standing:SetPoint("TOPRIGHT", -6, -3)
    r.standing:SetTextColor(0.7, 0.7, 0.7)

    r:SetScript("OnClick", function(self, button)
        if self._isHeader then
            if button ~= "LeftButton" then return end
            repBusy = true
            ToggleFactionHeader(self._index, not self._collapsed)
            repBusy = false
            sf.data = RepFactions()
            sf:Refresh()
        elseif button == "RightButton" then
            RepRowMenu(self, self._data)
        end
    end)

    function r:SetData(d)
        self._data = d
        self._isHeader, self._index, self._collapsed = d.isHeader, d.index, d.isCollapsed
        self.name:SetText(d.name or "")
        if d.isHeader then
            self.arrow:SetText(d.isCollapsed and "+" or "-")
            self.arrow:Show()
            self.name:SetTextColor(ac())
            self.name:ClearAllPoints(); self.name:SetPoint("TOPLEFT", 18, -3)
            self.standing:SetText("")
            self.bar:Hide(); self._bg:SetAlpha(0)
            return
        end
        self.arrow:Hide()
        self.name:ClearAllPoints(); self.name:SetPoint("TOPLEFT", 10, -3)
        self._bg:SetAlpha(1)
        self.name:SetTextColor(0.9, 0.9, 0.9)
        local reaction = d.reaction
        local label = reaction and _G["FACTION_STANDING_LABEL" .. reaction] or ""
        self.standing:SetText(label)
        local minV, maxV, val = d.min or 0, d.max or 0, d.value or 0
        local range = maxV - minV
        self.bar:SetMinMaxValues(0, range > 0 and range or 1)
        self.bar:SetValue(range > 0 and (val - minV) or 1)
        local c = FACTION_BAR_COLORS and reaction and FACTION_BAR_COLORS[reaction]
        if c then self.bar:SetStatusBarColor(c.r, c.g, c.b) else self.bar:SetStatusBarColor(ac()) end
        self.bar:Show()
    end
    return r
end

-- ---------------------------------------------------------------------------
--  Currency rows + data  (Abzeichen)
-- ---------------------------------------------------------------------------
-- This client exposes C_CurrencyInfo.GetCurrencyListSize but NOT
-- GetCurrencyListInfo, so fall back to the legacy multi-return globals.
local function curSize()
    if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyListSize then return C_CurrencyInfo.GetCurrencyListSize() or 0 end
    if GetCurrencyListSize then return GetCurrencyListSize() or 0 end
    return 0
end

local function curIDFromIndex(i)
    local link
    if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyListLink then link = C_CurrencyInfo.GetCurrencyListLink(i)
    elseif GetCurrencyListLink then link = GetCurrencyListLink(i) end
    if not link then return nil end
    if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyIDFromLink then
        return C_CurrencyInfo.GetCurrencyIDFromLink(link)
    end
    local id = link:match("currency:(%d+)")
    return id and tonumber(id)
end

local function curInfo(i)
    local name, isHeader, isExpanded, count, icon, maximum
    if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyListInfo then
        local info = C_CurrencyInfo.GetCurrencyListInfo(i)
        if not info then return nil end
        name, isHeader, isExpanded = info.name, info.isHeader, info.isHeaderExpanded
        count, icon, maximum = info.quantity, info.iconFileID, info.maxQuantity
    elseif GetCurrencyListInfo then
        -- MoP legacy order: name, isHeader, isExpanded, isUnused, isWatched, count, icon, maximum
        name, isHeader, isExpanded, _, _, count, icon, maximum = GetCurrencyListInfo(i)
    else
        return nil
    end
    -- The legacy list reports an inflated maximum for some currencies
    -- (Justice/Valor: x100). C_CurrencyInfo.GetCurrencyInfo(id) carries the
    -- same values Blizzard's own UI shows, so prefer it when available.
    if not isHeader and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        local id = curIDFromIndex(i)
        if id then
            local ci = C_CurrencyInfo.GetCurrencyInfo(id)
            if ci then
                count   = ci.quantity   or count
                maximum = ci.maxQuantity or maximum
                icon    = ci.iconFileID or icon
            end
        end
    end
    return { name = name, isHeader = isHeader, expanded = isExpanded,
             quantity = count, icon = icon, max = maximum }
end

local function curExpand(i, expand)
    if C_CurrencyInfo and C_CurrencyInfo.ExpandCurrencyList then
        C_CurrencyInfo.ExpandCurrencyList(i, expand)
    elseif ExpandCurrencyList then
        ExpandCurrencyList(i, expand and 1 or 0)
    end
end

local function CurrencyList()
    local out = {}
    if curSize() == 0 then return out end
    curBusy = true
    pcall(function()
        local collapsed = {}
        local i = 1
        while i <= curSize() do
            local info = curInfo(i)
            if info and info.isHeader and info.expanded == false then
                collapsed[#collapsed + 1] = i
                curExpand(i, true)
            end
            i = i + 1
        end
        for idx = 1, curSize() do
            local info = curInfo(idx)
            if info and info.name and info.name ~= "" then
                out[#out + 1] = {
                    name = info.name, isHeader = info.isHeader,
                    quantity = info.quantity, icon = info.icon, maxQuantity = info.max,
                }
            end
        end
        for k = #collapsed, 1, -1 do curExpand(collapsed[k], false) end
    end)
    curBusy = false
    return out
end

local function MakeCurrencyRow(parent)
    local r = CreateFrame("Frame", nil, parent)
    local bg = r:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(ROW_BG[1], ROW_BG[2], ROW_BG[3], ROW_BG[4])
    r._bg = bg

    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(18, 18)
    r.icon:SetPoint("LEFT", 6, 0)
    r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    r.name = r:CreateFontString(nil, "OVERLAY")
    r.name:SetFont(fontPath(), 12, "")
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)

    r.count = r:CreateFontString(nil, "OVERLAY")
    r.count:SetFont(fontPath(), 12, "")
    r.count:SetPoint("RIGHT", -8, 0)
    r.count:SetTextColor(ac())

    function r:SetData(d)
        self.name:SetText(d.name or "")
        if d.isHeader then
            self.name:SetTextColor(ac())
            self.name:ClearAllPoints(); self.name:SetPoint("LEFT", 8, 0)
            self.icon:Hide(); self.count:SetText(""); self._bg:SetAlpha(0)
            return
        end
        self.name:ClearAllPoints(); self.name:SetPoint("LEFT", self.icon, "RIGHT", 6, 0)
        self._bg:SetAlpha(1)
        self.name:SetTextColor(0.9, 0.9, 0.9)
        if d.icon then self.icon:SetTexture(d.icon); self.icon:Show() else self.icon:Hide() end
        local q = d.quantity or 0
        if d.maxQuantity and d.maxQuantity > 0 then
            self.count:SetText(q .. " / " .. d.maxQuantity)
        else
            self.count:SetText(tostring(q))
        end
    end
    return r
end

-- ---------------------------------------------------------------------------
--  Tab bar
-- ---------------------------------------------------------------------------
local function MakeTab(parent, text)
    local t = CreateFrame("Button", nil, parent)
    t:SetHeight(24)
    local bg = t:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0.1, 0.1, 0.12, 0.9)
    t._bg = bg
    local hl = t:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(); hl:SetColorTexture(ac()); hl:SetAlpha(0.12)
    local label = t:CreateFontString(nil, "OVERLAY")
    label:SetFont(fontPath(), 12, "")
    label:SetPoint("CENTER")
    label:SetText(text)
    t._label = label
    local underline = t:CreateTexture(nil, "OVERLAY")
    underline:SetPoint("BOTTOMLEFT"); underline:SetPoint("BOTTOMRIGHT"); underline:SetHeight(2)
    underline:SetColorTexture(ac()); underline:Hide()
    t._underline = underline
    function t:SetActive(on)
        if on then self._label:SetTextColor(ac()); self._underline:Show()
        else self._label:SetTextColor(0.7, 0.7, 0.7); self._underline:Hide() end
    end
    t:SetActive(false)
    -- auto width from text
    t:SetWidth(math.max(70, label:GetStringWidth() + 28))
    return t
end

-- ---------------------------------------------------------------------------
--  Build the window
-- ---------------------------------------------------------------------------
-- ---------------------------------------------------------------------------
--  Stats panel  (MoP primary + secondary)  -- uses client-localized globals
-- ---------------------------------------------------------------------------
local function statName(g, fallback) return _G[g] or fallback end
local function pctv(v) return string.format("%.2f%%", v or 0) end
local function numv(v) return tostring(math.floor((v or 0) + 0.5)) end
local function call0(fn, ...) if type(fn) == "function" then local ok, a = pcall(fn, ...) if ok then return a end end end

-- combined attack power (base + positive + negative)
local function apTotal(fn)
    if type(fn) ~= "function" then return 0 end
    local ok, base, pos, neg = pcall(fn, "player")
    if not ok then return 0 end
    return (base or 0) + (pos or 0) + (neg or 0)
end
local function meleeAP()  return apTotal(UnitAttackPower) end
local function rangedAP() return apTotal(UnitRangedAttackPower) end
local function spellPower()
    local best = 0
    if GetSpellBonusDamage then
        for s = 1, 7 do local v = GetSpellBonusDamage(s) or 0 if v > best then best = v end end
    end
    return best
end
local function meleeHaste() return call0(GetMeleeHaste) or call0(GetHaste) or 0 end
local function expertiseVal()
    if GetExpertise then
        local e = GetExpertise()
        if e then return numv(e) end
    end
    if GetCombatRating and CR_EXPERTISE then return numv(GetCombatRating(CR_EXPERTISE)) end
    return "-"
end
local function hitMelee()
    if GetCombatRatingBonus and CR_HIT_MELEE then return pctv(GetCombatRatingBonus(CR_HIT_MELEE)) end
    return "-"
end
local function hitSpell()
    if GetCombatRatingBonus and CR_HIT_SPELL then return pctv(GetCombatRatingBonus(CR_HIT_SPELL)) end
    return "-"
end

-- Mastery: spec-specific name + description (mirrors Blizzard's mastery tooltip)
local function masterySpecLines()
    local out = {}
    local spec
    if C_SpecializationInfo and C_SpecializationInfo.GetSpecialization then
        spec = C_SpecializationInfo.GetSpecialization()
    elseif GetSpecialization then
        spec = GetSpecialization()
    end
    if spec and GetNumSpecializations and spec > GetNumSpecializations() then spec = nil end
    if spec and GetSpecializationMasterySpells then
        local id = GetSpecializationMasterySpells(spec)
        if id then
            local name = GetSpellInfo and GetSpellInfo(id)
            local desc
            if C_Spell and C_Spell.GetSpellDescription then desc = C_Spell.GetSpellDescription(id)
            elseif GetSpellDescription then desc = GetSpellDescription(id) end
            if name and name ~= "" then out[#out + 1] = { text = name, accent = true } end
            if desc and desc ~= "" then out[#out + 1] = { text = desc } end
        end
    end
    return out
end

-- Each row: primary id OR { label, get() -> string, tip } ; headers separate.
-- tip = short description shown on mouseover (localized).
local STAT_CATEGORIES = {
    { header = statName("STAT_CATEGORY_ATTRIBUTES", "Attributes"), rows = {
        { primary = 1 }, { primary = 2 }, { primary = 3 }, { primary = 4 }, { primary = 5 },
    } },
    { header = statName("MELEE", "Melee"), rows = {
        { label = statName("ATTACK_POWER", "Attack Power"), get = function() return numv(meleeAP()) end,
          tip = "Increases your melee damage." },
        { label = statName("STAT_CRITICAL_STRIKE", "Critical Strike"), get = function() return pctv(call0(GetCritChance)) end,
          tip = "Chance for your melee attacks to critically strike." },
        { label = statName("STAT_HASTE", "Haste"), get = function() return pctv(meleeHaste()) end,
          tip = "Increases your melee attack speed." },
        { label = statName("STAT_EXPERTISE", "Expertise"), get = expertiseVal,
          tip = "Reduces the chance for your attacks to be dodged or parried." },
        { label = statName("HIT_RATING", "Hit"), get = hitMelee,
          tip = "Reduces the chance for your melee attacks to miss." },
    } },
    { header = statName("RANGED_ATTACK", "Ranged"), rows = {
        { label = statName("ATTACK_POWER", "Attack Power"), get = function() return numv(rangedAP()) end,
          tip = "Increases your ranged damage." },
        { label = statName("STAT_CRITICAL_STRIKE", "Critical Strike"), get = function() return pctv(call0(GetRangedCritChance)) end,
          tip = "Chance for your ranged attacks to critically strike." },
        { label = statName("STAT_HASTE", "Haste"), get = function() return pctv(call0(GetRangedHaste)) end,
          tip = "Increases your ranged attack speed." },
    } },
    { header = statName("SPELL_STATS", "Spell"), rows = {
        { label = statName("STAT_SPELLPOWER", "Spell Power"), get = function() return numv(spellPower()) end,
          tip = "Increases the effect of your spells and abilities." },
        { label = statName("STAT_CRITICAL_STRIKE", "Critical Strike"), get = function()
              return pctv(GetSpellCritChance and GetSpellCritChance(2) or call0(GetCritChance)) end,
          tip = "Chance for your spells to critically strike." },
        { label = statName("STAT_HASTE", "Haste"), get = function() return pctv(call0(UnitSpellHaste, "player")) end,
          tip = "Increases your spell casting speed." },
        { label = statName("HIT_RATING", "Hit"), get = hitSpell,
          tip = "Reduces the chance for your spells to miss." },
    } },
    { header = statName("PLAYERSTAT_DEFENSES", "Defense"), rows = {
        { label = statName("ARMOR", "Armor"), get = function() return numv((select(2, UnitArmor("player")))) end,
          tip = "Reduces physical damage taken." },
        { label = statName("STAT_DODGE", "Dodge"), get = function() return pctv(call0(GetDodgeChance)) end,
          tip = "Chance to dodge incoming melee attacks." },
        { label = statName("STAT_PARRY", "Parry"), get = function() return pctv(call0(GetParryChance)) end,
          tip = "Chance to parry incoming melee attacks." },
        { label = statName("STAT_BLOCK", "Block"), get = function() return pctv(call0(GetBlockChance)) end,
          tip = "Chance to block incoming melee attacks with a shield." },
        { label = statName("STAT_MASTERY", "Mastery"), get = function()
              return pctv(call0(GetMasteryEffect) or call0(GetMastery)) end,
          tip = "Improves an effect specific to your specialization.", tipFn = masterySpecLines },
    } },
}

local function MakeStatLine(parent)
    local l = CreateFrame("Button", nil, parent)
    l:SetHeight(14)
    l.label = l:CreateFontString(nil, "OVERLAY")
    l.label:SetFont(fontPath(), 11, ""); l.label:SetPoint("LEFT", 4, 0); l.label:SetTextColor(0.6, 0.6, 0.6)
    l.value = l:CreateFontString(nil, "OVERLAY")
    l.value:SetFont(fontPath(), 11, ""); l.value:SetPoint("RIGHT", -4, 0); l.value:SetTextColor(0.95, 0.95, 0.95)
    l:SetScript("OnEnter", function(self)
        if not self._tipTitle then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self._tipTitle, 1, 1, 1)
        if self._tipValue then GameTooltip:AddLine(self._tipValue, ac()) end
        if self._tipText then GameTooltip:AddLine(self._tipText, 0.85, 0.85, 0.85, true) end
        if self._tipFn then
            local lines = self._tipFn()
            if lines and #lines > 0 then
                GameTooltip:AddLine(" ")
                for _, ln in ipairs(lines) do
                    if ln.accent then GameTooltip:AddLine(ln.text, ac())
                    else GameTooltip:AddLine(ln.text, 0.85, 0.85, 0.85, true) end
                end
            end
        end
        GameTooltip:Show()
    end)
    l:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return l
end

local function MakeStatHeader(parent)
    local h = parent:CreateFontString(nil, "OVERLAY")
    h:SetFont(fontPath(), 11, "OUTLINE")
    h:SetTextColor(ac())
    return h
end

function CS:UpdateItemLevel()
    if not self.ilvlText then return end
    local overall, equipped = 0, 0
    if GetAverageItemLevel then
        local a, b = GetAverageItemLevel()
        overall = math.floor((a or 0) + 0.5)
        equipped = math.floor((b or a or 0) + 0.5)
    end
    self.ilvlText:SetText(string.format("%s: %d", L("Item Level"), equipped))
end

function CS:UpdateStats()
    self:UpdateItemLevel()
    if not self.statLines then return end
    for _, line in ipairs(self.statLines) do
        local def = line._def
        if def.primary then
            local nm = statName("SPELL_STAT" .. def.primary .. "_NAME", "Stat" .. def.primary)
            line.label:SetText(nm)
            local ok, _, v = pcall(UnitStat, "player", def.primary)
            line.value:SetText(ok and tostring(v) or "-")
            line._tipTitle, line._tipValue, line._tipText = nm, (ok and tostring(v) or nil), nil
            line._tipFn = nil
        else
            line.label:SetText(def.label)
            local ok, val = pcall(def.get)
            local s = (ok and val) or "-"
            line.value:SetText(s)
            line._tipTitle, line._tipValue, line._tipText = def.label, s, def.tip and L(def.tip) or nil
            line._tipFn = def.tipFn
        end
    end
end


-- ---------------------------------------------------------------------------
--  Equipment Manager (gear sets) -- C_EquipmentSet with legacy global fallback
-- ---------------------------------------------------------------------------
local ES = C_EquipmentSet

local function EM_GetSets()
    local out = {}
    if ES and ES.GetEquipmentSetIDs then
        for _, id in ipairs(ES.GetEquipmentSetIDs()) do
            local name, icon = ES.GetEquipmentSetInfo(id)
            out[#out + 1] = { id = id, name = name, icon = icon, modern = true }
        end
    elseif GetNumEquipmentSets then
        for i = 1, GetNumEquipmentSets() do
            local name, icon = GetEquipmentSetInfo(i)
            out[#out + 1] = { id = i, name = name, icon = icon, modern = false }
        end
    end
    return out
end

local function EM_Use(s)
    if InCombatLockdown() then return end
    if s.modern then
        if ES and ES.UseEquipmentSet then ES.UseEquipmentSet(s.id) end
    elseif UseEquipmentSet then
        UseEquipmentSet(s.name)
    end
end

local function EM_Delete(s)
    if s.modern then
        if ES and ES.DeleteEquipmentSet then ES.DeleteEquipmentSet(s.id) end
    elseif DeleteEquipmentSet then
        DeleteEquipmentSet(s.name)
    end
end

local DEFAULT_SET_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local function EM_Create(name, icon)
    if not name or name == "" then return end
    icon = icon or DEFAULT_SET_ICON
    if ES and ES.CreateEquipmentSet then ES.CreateEquipmentSet(name, icon)
    elseif SaveEquipmentSet then SaveEquipmentSet(name, icon) end
end

-- Save current equipment into an existing set (optionally change its icon).
local function EM_Save(s, icon)
    if s.modern then
        if ES and ES.SaveEquipmentSet then ES.SaveEquipmentSet(s.id, icon) end
    elseif SaveEquipmentSet then
        SaveEquipmentSet(s.name, icon)
    end
end

local function EM_Rename(s, newName)
    if not newName or newName == "" then return end
    if s.modern then
        if ES and ES.ModifyEquipmentSet then ES.ModifyEquipmentSet(s.id, newName) end
    elseif ModifyEquipmentSet then
        ModifyEquipmentSet(s.name, newName)
    end
end

-- slot id -> localized slot name (for "missing slots" tooltip)
local SLOT_ID_NAME = {
    [1] = "HEADSLOT", [2] = "NECKSLOT", [3] = "SHOULDERSLOT", [5] = "CHESTSLOT", [6] = "WAISTSLOT",
    [7] = "LEGSSLOT", [8] = "FEETSLOT", [9] = "WRISTSLOT", [10] = "HANDSSLOT", [11] = "FINGER0SLOT",
    [12] = "FINGER1SLOT", [13] = "TRINKET0SLOT", [14] = "TRINKET1SLOT", [15] = "BACKSLOT",
    [16] = "MAINHANDSLOT", [17] = "SECONDARYHANDSLOT", [18] = "RANGEDSLOT", [19] = "TABARDSLOT",
}
local function slotDisplayName(id)
    local g = SLOT_ID_NAME[id]
    return (g and _G[g]) or ("Slot " .. tostring(id))
end

-- returns: isEquipped, numTotal, numEquipped, numInBags, numMissing, missingSlotNames{}
local function EM_SetInfo(s)
    local info
    if s.modern and ES and ES.GetEquipmentSetInfo then
        local _, _, _, isEquipped, total, equipped, inBags, missing = ES.GetEquipmentSetInfo(s.id)
        local missingNames = {}
        if (missing or 0) > 0 and ES.GetItemLocations then
            local locs = ES.GetItemLocations(s.id)
            if type(locs) == "table" then
                for slotID, loc in pairs(locs) do
                    if not loc or loc <= 0 or loc == 1 then
                        missingNames[#missingNames + 1] = slotDisplayName(slotID)
                    end
                end
            end
        end
        return isEquipped, total, equipped, inBags, missing, missingNames
    elseif GetEquipmentSetInfo then
        local _, _, _, isEquipped, total, equipped, inBags, missing = GetEquipmentSetInfo(s.id)
        return isEquipped, total, equipped, inBags, missing, {}
    end
end

-- ---------------------------------------------------------------------------
--  Icon picker dialog (used for create + edit)
-- ---------------------------------------------------------------------------
local ICON_CACHE
local function collectIcons()
    if ICON_CACHE then return ICON_CACHE end
    local t = {}
    if GetNumMacroIcons and GetMacroIconInfo then
        for i = 1, GetNumMacroIcons() do t[#t + 1] = GetMacroIconInfo(i) end
    elseif GetMacroIcons then
        GetMacroIcons(t)
    end
    if GetNumMacroItemIcons and GetMacroItemIconInfo then
        for i = 1, GetNumMacroItemIcons() do t[#t + 1] = GetMacroItemIconInfo(i) end
    elseif GetMacroItemIcons then
        local t2 = {}; GetMacroItemIcons(t2)
        for _, v in ipairs(t2) do t[#t + 1] = v end
    end
    if #t == 0 then t = { DEFAULT_SET_ICON } end
    ICON_CACHE = t
    return t
end

local PICK_COLS, PICK_ROWS, PICK_ICON, PICK_GAP = 10, 7, 28, 4
function CS:BuildIconPicker()
    if self.iconPicker then return self.iconPicker end
    local p = CreateFrame("Frame", "OUICharIconPicker", UIParent)
    p:SetSize(PICK_COLS * (PICK_ICON + PICK_GAP) + 28, 380)
    p:SetPoint("CENTER")
    p:SetFrameStrata("FULLSCREEN_DIALOG"); p:SetToplevel(true)
    p:EnableMouse(true); p:SetMovable(true); p:Hide()
    local bg = p:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(BG[1], BG[2], BG[3], 0.98)
    if OUI.PP and OUI.PP.CreateBorder then OUI.PP.CreateBorder(p, BRD[1], BRD[2], BRD[3], BRD[4]) end

    local tb = CreateFrame("Frame", nil, p); tb:SetPoint("TOPLEFT"); tb:SetPoint("TOPRIGHT"); tb:SetHeight(24)
    tb:EnableMouse(true); tb:RegisterForDrag("LeftButton")
    tb:SetScript("OnDragStart", function() p:StartMoving() end)
    tb:SetScript("OnDragStop", function() p:StopMovingOrSizing() end)
    local tbg = tb:CreateTexture(nil, "ARTWORK"); tbg:SetAllPoints(); tbg:SetColorTexture(0.1, 0.1, 0.12, 0.9)
    p.title = tb:CreateFontString(nil, "OVERLAY"); p.title:SetFont(fontPath(), 13, ""); p.title:SetPoint("LEFT", 10, 0); p.title:SetTextColor(ac())

    local eb = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
    eb:SetSize(p:GetWidth() - 44, 20); eb:SetPoint("TOPLEFT", 16, -34); eb:SetAutoFocus(false); eb:SetMaxLetters(32)
    eb:SetFontObject("ChatFontNormal")
    eb:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
    p.editBox = eb

    local grid = CreateFrame("Frame", nil, p)
    grid:SetPoint("TOPLEFT", 16, -62)
    grid:SetSize(PICK_COLS * (PICK_ICON + PICK_GAP), PICK_ROWS * (PICK_ICON + PICK_GAP))
    grid:EnableMouseWheel(true)
    p.offset = 0
    p.iconButtons = {}
    for i = 1, PICK_COLS * PICK_ROWS do
        local b = CreateFrame("Button", nil, grid)
        b:SetSize(PICK_ICON, PICK_ICON)
        local col, row = (i - 1) % PICK_COLS, math.floor((i - 1) / PICK_COLS)
        b:SetPoint("TOPLEFT", col * (PICK_ICON + PICK_GAP), -row * (PICK_ICON + PICK_GAP))
        b.tex = b:CreateTexture(nil, "ARTWORK"); b.tex:SetAllPoints(); b.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        if OUI.PP and OUI.PP.CreateBorder then OUI.PP.CreateBorder(b, BRD[1], BRD[2], BRD[3], BRD[4]) end
        b.sel = b:CreateTexture(nil, "OVERLAY"); b.sel:SetAllPoints(); b.sel:SetColorTexture(ac()); b.sel:SetAlpha(0.4); b.sel:Hide()
        b.hl = b:CreateTexture(nil, "HIGHLIGHT"); b.hl:SetAllPoints(); b.hl:SetColorTexture(1, 1, 1, 0.15)
        b:SetScript("OnClick", function(self) p.selectedIcon = self._icon; p:UpdateSelection() end)
        p.iconButtons[i] = b
    end
    grid:SetScript("OnMouseWheel", function(_, delta)
        local icons = collectIcons()
        local maxOffset = math.max(0, math.ceil(#icons / PICK_COLS) - PICK_ROWS)
        p.offset = math.min(maxOffset, math.max(0, p.offset - delta))
        p:RefreshIcons()
    end)

    local save = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    save:SetSize(90, 22); save:SetPoint("BOTTOMRIGHT", -16, 12); save:SetText(SAVE or L("Save"))
    save:SetScript("OnClick", function()
        if p.onAccept then p.onAccept(eb:GetText(), p.selectedIcon) end
        p:Hide()
    end)
    local cancel = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    cancel:SetSize(90, 22); cancel:SetPoint("RIGHT", save, "LEFT", -8, 0); cancel:SetText(CANCEL or L("Cancel"))
    cancel:SetScript("OnClick", function() p:Hide() end)

    function p:UpdateSelection()
        for _, b in ipairs(self.iconButtons) do
            b.sel:SetShown(b._icon ~= nil and b._icon == self.selectedIcon)
        end
    end
    function p:RefreshIcons()
        local icons = collectIcons()
        local start = self.offset * PICK_COLS
        for i, b in ipairs(self.iconButtons) do
            local icon = icons[start + i]
            if icon then b._icon = icon; b.tex:SetTexture(icon); b:Show() else b._icon = nil; b:Hide() end
        end
        self:UpdateSelection()
    end

    self.iconPicker = p
    return p
end

function CS:OpenIconPicker(opts)
    local p = self:BuildIconPicker()
    p.onAccept = opts.onAccept
    p.title:SetText(opts.title or L("Choose an icon"))
    p.editBox:SetText(opts.name or "")
    p.selectedIcon = opts.icon
    p.offset = 0
    if opts.icon then
        local icons = collectIcons()
        for idx, v in ipairs(icons) do
            if v == opts.icon then p.offset = math.max(0, math.floor((idx - 1) / PICK_COLS) - 2); break end
        end
    end
    p:RefreshIcons()
    p:Show(); p:Raise()
end

-- right-click context menu for a set (equip / update / edit / delete)
function CS:SetContextMenu(anchor, s)
    if MenuUtil and MenuUtil.CreateContextMenu then
        MenuUtil.CreateContextMenu(anchor, function(_, root)
            root:CreateTitle(s.name or "")
            root:CreateButton(L("Equip"), function() EM_Use(s) end)
            root:CreateButton(L("Update to current gear"), function() EM_Save(s, s.icon) end)
            root:CreateButton(L("Edit (rename / icon)"), function()
                CS:OpenIconPicker({
                    title = L("Edit equipment set"), name = s.name, icon = s.icon,
                    onAccept = function(name, icon)
                        if name and name ~= "" and name ~= s.name then EM_Rename(s, name) end
                        if icon and icon ~= s.icon then EM_Save(s, icon) end
                    end,
                })
            end)
            root:CreateButton(L("Delete"), function() EM_Delete(s) end)
        end)
    else
        EM_Delete(s)  -- fallback when the menu API is unavailable
    end
end

local EM_ICON, EM_GAP = 40, 6

function CS:RefreshEquipSets()
    local bar = self.emBar
    if not bar then return end
    bar.buttons = bar.buttons or {}
    for _, b in ipairs(bar.buttons) do b:Hide() end

    local w = bar:GetWidth()
    if not w or w < 60 then w = 540 end
    local perRow = math.max(1, math.floor(w / (EM_ICON + EM_GAP)))
    local function place(widget, cell)
        local col, row = cell % perRow, math.floor(cell / perRow)
        widget:ClearAllPoints()
        widget:SetPoint("TOPLEFT", bar, "TOPLEFT", col * (EM_ICON + EM_GAP), -row * (EM_ICON + EM_GAP))
    end

    local sets = EM_GetSets()
    for i, s in ipairs(sets) do
        local b = bar.buttons[i]
        if not b then
            b = CreateFrame("Button", nil, bar)
            b:SetSize(EM_ICON, EM_ICON)
            b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            b.tex = b:CreateTexture(nil, "ARTWORK")
            b.tex:SetAllPoints(); b.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            if OUI.PP and OUI.PP.CreateBorder then OUI.PP.CreateBorder(b, BRD[1], BRD[2], BRD[3], BRD[4]) end
            b.hl = b:CreateTexture(nil, "HIGHLIGHT")
            b.hl:SetAllPoints(); b.hl:SetColorTexture(ac()); b.hl:SetAlpha(0.2)
            b:SetScript("OnEnter", function(self)
                local set = self._set
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(set.name, 1, 1, 1)
                local equipped, total, numEq, inBags, missing, missingSlots = EM_SetInfo(set)
                if equipped then GameTooltip:AddLine(L("Currently equipped"), 0.3, 1, 0.3) end
                if total then
                    GameTooltip:AddLine(string.format("%s: %d/%d", L("Equipped"), numEq or 0, total), 0.8, 0.8, 0.8)
                    GameTooltip:AddLine(string.format("%s: %d", L("In bags"), inBags or 0), 0.8, 0.8, 0.8)
                    if (missing or 0) > 0 then
                        GameTooltip:AddLine(string.format("%s: %d", L("Missing"), missing), 1, 0.4, 0.4)
                        if missingSlots and #missingSlots > 0 then
                            GameTooltip:AddLine(table.concat(missingSlots, ", "), 1, 0.55, 0.55, true)
                        end
                    end
                end
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(L("Left-click: equip  |  Right-click: menu"), 0.6, 0.6, 0.6)
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            b:SetScript("OnClick", function(self, button)
                if button == "RightButton" then CS:SetContextMenu(self, self._set) else EM_Use(self._set) end
            end)
            bar.buttons[i] = b
        end
        b._set = s
        b.tex:SetTexture(s.icon or DEFAULT_SET_ICON)
        place(b, i - 1)   -- sets fill cells 0..N-1
        b:Show()
    end

    -- "+" save button trails after the last set
    bar.plus:SetSize(EM_ICON, EM_ICON)
    place(bar.plus, #sets)
end

function CS:Build()
    if self.frame then return self.frame end

    local f = CreateFrame("Frame", "OUICharacterFrame", UIParent)
    f:SetSize(560, 700)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:Hide()
    f:SetMovable(true)
    f:EnableMouse(true)
    self.frame = f

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(BG[1], BG[2], BG[3], BG[4])
    if OUI.PP and OUI.PP.CreateBorder then
        OUI.PP.CreateBorder(f, BRD[1], BRD[2], BRD[3], BRD[4])
    end

    -- title bar
    local title = CreateFrame("Frame", nil, f)
    title:SetPoint("TOPLEFT"); title:SetPoint("TOPRIGHT"); title:SetHeight(26)
    title:EnableMouse(true); title:RegisterForDrag("LeftButton")
    title:SetScript("OnDragStart", function() f:StartMoving() end)
    title:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    local tbg = title:CreateTexture(nil, "ARTWORK")
    tbg:SetAllPoints(); tbg:SetColorTexture(0.1, 0.1, 0.12, 0.9)
    local ttext = title:CreateFontString(nil, "OVERLAY")
    ttext:SetFont(fontPath(), 14, ""); ttext:SetPoint("LEFT", 10, 0)
    ttext:SetText(UnitName("player") or L("Character")); ttext:SetTextColor(ac())
    f._title = ttext

    local close = CreateFrame("Button", nil, title)
    close:SetSize(20, 20); close:SetPoint("RIGHT", -6, 0)
    local cx = close:CreateFontString(nil, "OVERLAY")
    cx:SetFont(fontPath(), 16, ""); cx:SetPoint("CENTER"); cx:SetText("x"); cx:SetTextColor(0.8, 0.8, 0.8)
    close:SetScript("OnEnter", function() cx:SetTextColor(ac()) end)
    close:SetScript("OnLeave", function() cx:SetTextColor(0.8, 0.8, 0.8) end)
    close:SetScript("OnClick", function() CS:Hide() end)

    -- tab bar (just under the title)
    local tabBar = CreateFrame("Frame", nil, f)
    tabBar:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 8, -4)
    tabBar:SetPoint("TOPRIGHT", title, "BOTTOMRIGHT", -8, -4)
    tabBar:SetHeight(24)

    -- body (below tab bar)
    local body = CreateFrame("Frame", nil, f)
    body:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT", -4, -6)
    body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 8)

    -- pages
    local charPage = CreateFrame("Frame", nil, body); charPage:SetAllPoints()
    local repPage  = CreateFrame("Frame", nil, body); repPage:SetAllPoints();  repPage:Hide()
    local curPage  = CreateFrame("Frame", nil, body); curPage:SetAllPoints();  curPage:Hide()
    local emPage   = CreateFrame("Frame", nil, body); emPage:SetAllPoints();   emPage:Hide()
    self.pages = { Character = charPage, Reputation = repPage, Currency = curPage, Equipment = emPage }

    -- ---- character page: model + slots ----
    local model = CreateFrame("PlayerModel", nil, charPage)
    model:SetPoint("TOP", 0, -8)
    model:SetSize(200, 280)
    model:SetUnit("player")
    self.model = model

    self.slots = {}
    do  -- left column
        local prev
        for _, name in ipairs(LEFT_SLOTS) do
            local b = CreateSlot(charPage, name)
            if b then
                if not prev then b:SetPoint("TOPLEFT", 4, -8)
                else b:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -SLOT_GAP) end
                self.slots[name] = b; prev = b
            end
        end
    end
    do  -- right column
        local prev
        for _, name in ipairs(RIGHT_SLOTS) do
            local b = CreateSlot(charPage, name)
            if b then
                if not prev then b:SetPoint("TOPRIGHT", -4, -8)
                else b:SetPoint("TOPRIGHT", prev, "BOTTOMRIGHT", 0, -SLOT_GAP) end
                self.slots[name] = b; prev = b
            end
        end
    end
    do  -- weapon row, centred under the model
        local prev
        for _, name in ipairs(WEAPON_SLOTS) do
            local b = CreateSlot(charPage, name)
            if b then
                if not prev then b:SetPoint("TOP", model, "BOTTOM", -(SLOT_SIZE / 2 + SLOT_GAP / 2), -8)
                else b:SetPoint("LEFT", prev, "RIGHT", SLOT_GAP, 0) end
                self.slots[name] = b; prev = b
            end
        end
    end

    -- ---- stats panel (below the slot columns) ----
    local stats = CreateFrame("Frame", nil, charPage)
    stats:SetPoint("TOPLEFT", 6, -(8 + #LEFT_SLOTS * (SLOT_SIZE + SLOT_GAP) + 4))
    stats:SetPoint("TOPRIGHT", -6, -(8 + #LEFT_SLOTS * (SLOT_SIZE + SLOT_GAP) + 4))
    stats:SetPoint("BOTTOM", 0, 6)

    -- item level header (full width, centered)
    self.ilvlText = stats:CreateFontString(nil, "OVERLAY")
    self.ilvlText:SetFont(fontPath(), 13, "OUTLINE")
    self.ilvlText:SetPoint("TOP", 0, -2)
    self.ilvlText:SetTextColor(ac())

    local colsTop = CreateFrame("Frame", nil, stats)
    colsTop:SetPoint("TOPLEFT", 0, -20); colsTop:SetPoint("TOPRIGHT", 0, -20); colsTop:SetPoint("BOTTOM", 0, 0)

    local leftCol = CreateFrame("Frame", nil, colsTop)
    leftCol:SetPoint("TOPLEFT", 0, 0); leftCol:SetPoint("BOTTOMRIGHT", colsTop, "BOTTOM", -8, 0)
    local rightCol = CreateFrame("Frame", nil, colsTop)
    rightCol:SetPoint("TOPLEFT", colsTop, "TOP", 8, 0); rightCol:SetPoint("BOTTOMRIGHT", 0, 0)

    self.statLines = {}
    local function buildColumn(col, cats)
        local prev
        for _, cat in ipairs(cats) do
            local hdr = MakeStatHeader(col)
            if not prev then hdr:SetPoint("TOPLEFT", 2, -2) else hdr:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -3) end
            hdr:SetText(cat.header)
            prev = hdr
            for _, def in ipairs(cat.rows) do
                local line = MakeStatLine(col)
                line:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", (prev == hdr) and -2 or 0, -1)
                line:SetPoint("RIGHT", col, "RIGHT", -2, 0)
                line._def = def
                self.statLines[#self.statLines + 1] = line
                prev = line
            end
        end
    end
    buildColumn(leftCol,  { STAT_CATEGORIES[1], STAT_CATEGORIES[2] })
    buildColumn(rightCol, { STAT_CATEGORIES[3], STAT_CATEGORIES[4], STAT_CATEGORIES[5] })

    -- ---- reputation page ----
    self.repList = MakeScrollList(repPage, 30, MakeRepRow)
    self.repList:SetPoint("TOPLEFT", 4, -2); self.repList:SetPoint("BOTTOMRIGHT", -4, 2)

    -- ---- currency page ----
    self.curList = MakeScrollList(curPage, 24, MakeCurrencyRow)
    self.curList:SetPoint("TOPLEFT", 4, -2); self.curList:SetPoint("BOTTOMRIGHT", -4, 2)

    -- ---- equipment manager page ----
    local emHdr = emPage:CreateFontString(nil, "OVERLAY")
    emHdr:SetFont(fontPath(), 12, "OUTLINE"); emHdr:SetPoint("TOPLEFT", 8, -8); emHdr:SetTextColor(ac())
    emHdr:SetText(L("Equipment Sets"))
    local emHint = emPage:CreateFontString(nil, "OVERLAY")
    emHint:SetFont(fontPath(), 10, ""); emHint:SetPoint("TOPLEFT", emHdr, "BOTTOMLEFT", 0, -2)
    emHint:SetTextColor(0.6, 0.6, 0.6)
    emHint:SetText(L("Left-click: equip  |  Right-click: menu"))

    local emBar = CreateFrame("Frame", nil, emPage)
    emBar:SetPoint("TOPLEFT", emHint, "BOTTOMLEFT", 0, -10)
    emBar:SetPoint("TOPRIGHT", emPage, "TOPRIGHT", -8, -40)
    emBar:SetPoint("BOTTOM", emPage, "BOTTOM", 0, 8)
    self.emBar = emBar

    local plus = CreateFrame("Button", nil, emPage)
    plus:SetSize(40, 40)
    plus:SetPoint("TOPLEFT", emBar, "TOPLEFT", 0, 0)
    local pbg = plus:CreateTexture(nil, "BACKGROUND")
    pbg:SetAllPoints(); pbg:SetColorTexture(SLOT_BG[1], SLOT_BG[2], SLOT_BG[3], SLOT_BG[4])
    if OUI.PP and OUI.PP.CreateBorder then OUI.PP.CreateBorder(plus, BRD[1], BRD[2], BRD[3], BRD[4]) end
    local px = plus:CreateFontString(nil, "OVERLAY")
    px:SetFont(fontPath(), 26, "OUTLINE"); px:SetPoint("CENTER"); px:SetText("+"); px:SetTextColor(ac())
    plus:SetScript("OnEnter", function()
        GameTooltip:SetOwner(plus, "ANCHOR_RIGHT")
        GameTooltip:SetText(L("Save current equipment as a set")); GameTooltip:Show()
    end)
    plus:SetScript("OnLeave", function() GameTooltip:Hide() end)
    plus:SetScript("OnClick", function()
        CS:OpenIconPicker({
            title = L("New equipment set"), name = "", icon = nil,
            onAccept = function(name, icon) EM_Create(name, icon) end,
        })
    end)
    emBar.plus = plus

    -- ---- tabs ----
    self.tabs = {}
    local order = {
        { key = "Character",  text = L("Character") },
        { key = "Equipment",  text = L("Equipment") },
        { key = "Reputation", text = L("Reputation") },
        { key = "Currency",   text = L("Tokens") },
    }
    local prev
    for _, t in ipairs(order) do
        local tab = MakeTab(tabBar, t.text)
        if not prev then tab:SetPoint("LEFT", 0, 0) else tab:SetPoint("LEFT", prev, "RIGHT", 4, 0) end
        tab:SetScript("OnClick", function() CS:SelectTab(t.key) end)
        self.tabs[t.key] = tab
        prev = tab
    end

    self:SelectTab("Character")
    self:RefreshEquipSets()
    return f
end

-- ---------------------------------------------------------------------------
--  Tab switching + per-page refresh
-- ---------------------------------------------------------------------------
function CS:SelectTab(key)
    if not self.pages then return end
    for k, page in pairs(self.pages) do
        page:SetShown(k == key)
        if self.tabs[k] then self.tabs[k]:SetActive(k == key) end
    end
    self.activeTab = key
    self:RefreshActive()
end

function CS:RefreshActive()
    local key = self.activeTab
    if key == "Character" then
        self:UpdateAll()
    elseif key == "Equipment" then
        self:RefreshEquipSets()
    elseif key == "Reputation" and self.repList then
        self.repList.data = RepFactions()
        self.repList.offset = 0
        self.repList:Refresh()
    elseif key == "Currency" and self.curList then
        self.curList.data = CurrencyList()
        self.curList.offset = 0
        self.curList:Refresh()
    end
end

-- ---------------------------------------------------------------------------
--  Show / hide / toggle
-- ---------------------------------------------------------------------------
function CS:Show()
    self:Build()
    if self.frame._title then self.frame._title:SetText(UnitName("player") or L("Character")) end
    if self.model then self.model:SetUnit("player") end
    self.frame:Show()
    self:RefreshActive()
end

function CS:Hide() if self.frame then self.frame:Hide() end end
function CS:Toggle() if self.frame and self.frame:IsShown() then self:Hide() else self:Show() end end

-- live updates while open
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
ev:RegisterEvent("PLAYER_AVG_ITEM_LEVEL_UPDATE")
ev:RegisterEvent("UPDATE_FACTION")
ev:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
ev:RegisterEvent("COMBAT_RATING_UPDATE")
ev:RegisterEvent("PLAYER_DAMAGE_DONE_MODS")
ev:RegisterEvent("EQUIPMENT_SETS_CHANGED")
ev:SetScript("OnEvent", function(_, event)
    if event == "EQUIPMENT_SETS_CHANGED" then
        if CS.frame and CS.frame:IsShown() then CS:RefreshEquipSets() end
        return
    end
    if repBusy or curBusy then return end
    if not (CS.frame and CS.frame:IsShown()) then return end
    if event == "UPDATE_FACTION" and CS.activeTab == "Reputation" then CS:RefreshActive()
    elseif event == "CURRENCY_DISPLAY_UPDATE" and CS.activeTab == "Currency" then CS:RefreshActive()
    elseif CS.activeTab == "Character" then CS:UpdateAll() end
end)

-- ---------------------------------------------------------------------------
--  Replace Blizzard's character pane (gated by the customCharacterSheet option)
-- ---------------------------------------------------------------------------
local function replaceEnabled()
    return BS and BS.db and BS.db.profile and BS.db.profile.customCharacterSheet ~= false
end

local TAB_MAP = {
    PaperDollFrame  = "Character",
    ReputationFrame = "Reputation",
    TokenFrame      = "Currency",
}

local origToggleCharacter = ToggleCharacter
function ToggleCharacter(tab)
    if not replaceEnabled() then return origToggleCharacter(tab) end
    local want = TAB_MAP[tab]
    if CS.frame and CS.frame:IsShown() then
        if want and CS.activeTab ~= want then
            CS:SelectTab(want)          -- already open: just switch to the asked-for tab
        else
            CS:Hide()
        end
    else
        CS:Show()
        if want then CS:SelectTab(want) end
    end
end

-- Safety net: suppress Blizzard's CharacterFrame if anything else shows it.
if CharacterFrame then
    CharacterFrame:HookScript("OnShow", function(self)
        if replaceEnabled() then self:Hide() end
    end)
end

-- test entry point / manual toggle
SLASH_OUICHAR1 = "/ouichar"
SlashCmdList["OUICHAR"] = function() CS:Toggle() end

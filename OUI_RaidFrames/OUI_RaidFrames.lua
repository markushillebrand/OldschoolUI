-- ===========================================================================
--  OldschoolUI -- Raid Frames
--  Clean-room implementation (written from scratch for MoP Classic 5.5.x).
--
--  RF1: bootstrap, a SecureGroupHeaderTemplate that auto-spawns one member
--  button per party/raid member (taint-safe), an insecure skin pass that adds
--  a health bar, optional power bar, name and border to each button, and a
--  unit->button dispatcher that drives health/power/name updates. The header
--  handles spawning, click-targeting and layout; everything visual is ours.
--  Indicators, range/threat, auras, options and the click-cast / buff-watch /
--  targeted-spell sub-systems arrive in later stages.
-- ===========================================================================
local ADDON, ns = ...
local RF  = LibStub("AceAddon-3.0"):NewAddon("OldschoolUIRaidFrames", "AceEvent-3.0")
local OUI = OldschoolUI
ns.RF = RF

local WHITE = "Interface\\Buttons\\WHITE8X8"

-- ---------------------------------------------------------------------------
--  Saved settings -- layout fields live PER TEMPLATE (small/medium/large),
--  everything else is shared across templates.
-- ---------------------------------------------------------------------------
local function tmpl(w, h, cols)
    return {
        width = w, height = h, powerHeight = 7,
        unitsPerColumn = 5, maxColumns = cols,
        rowSpacing = 4, columnSpacing = 8,
        point = "TOP",          -- members grow down within a column
        columnAnchor = "LEFT",  -- columns grow to the right
        scale = 1.0,
    }
end

local defaults = {
    profile = {
        enabled        = true,
        hideBlizzard   = true,
        x              = -360,        -- SHARED anchor (CENTER offset from UIParent centre)
        y              = 0,
        uniformLayout  = false,       -- true = one config ("all") for every raid size
        showPower      = true,
        healthText     = "none",     -- none | percent | deficit
        showPlayer     = true,
        showSolo       = false,
        showRole       = true,
        showLeader     = true,
        showRaidIcon   = true,
        showThreat     = true,
        rangeFade      = true,
        fadeAlpha      = 0.45,
        showDebuffs    = true,
        showBuffs      = false,
        buffsOwnOnly   = true,
        debuffsDispellableOnly = false,
        maxDebuffs     = 3,
        maxBuffs       = 3,
        auraSize       = 18,
        hideAuraTime   = false,
        templates = {
            small  = tmpl(120, 58, 2),   -- <=10  (5x2)
            medium = tmpl(100, 50, 5),   -- 11-25 (5x5)
            large  = tmpl(88,  42, 8),   -- >25   (5x8)
            all    = tmpl(100, 50, 8),   -- used when uniformLayout = true
        },
    },
}

local TEMPLATE_KEYS  = { "small", "medium", "large" }
local TEMPLATE_COUNT = { small = 10, medium = 25, large = 40 }
local TEMPLATE_LABEL = { small = "10", medium = "25", large = "40" }

-- which template the current group size maps to
function RF:ResolveTemplateKey()
    local n = GetNumGroupMembers and GetNumGroupMembers() or 0
    if not n or n < 1 then n = 1 end
    if n <= 10 then return "small"
    elseif n <= 25 then return "medium"
    else return "large" end
end

-- layout config for the LIVE header (group size, or "all" when uniform)
function RF:HeaderKey()
    if self.db.profile.uniformLayout then return "all" end
    return self:ResolveTemplateKey()
end

-- layout config shown in the PREVIEW (switcher size, or "all" when uniform)
function RF:PreviewLayoutKey()
    if self.db.profile.uniformLayout then return "all" end
    return self._previewTemplate or self:ResolveTemplateKey()
end

-- which template the options sliders / mover edit
function RF:EditTemplateKey()
    if self.db.profile.uniformLayout then return "all" end
    if self.testMode and self._previewTemplate then return self._previewTemplate end
    return self:ResolveTemplateKey()
end

function RF:T(key)
    return self.db.profile.templates[key or self:HeaderKey()]
end

-- 40-player extent of the biggest config -> the shared anchor box / mover overlay
function RF:AnchorExtent()
    local key = self.db.profile.uniformLayout and "all" or "large"
    local t = self.db.profile.templates[key]
    local upc  = t.unitsPerColumn or 5
    local cols = math.min(t.maxColumns or 8, math.ceil(40 / upc))
    local rows = math.min(40, upc)
    local w = cols * (t.width + t.columnSpacing) - t.columnSpacing
    local h = rows * (t.height + t.rowSpacing) - t.rowSpacing
    local sc = t.scale or 1
    return math.max(w * sc, 1), math.max(h * sc, 1)
end

function RF:EnsureAnchor()
    if not self.anchor then
        self.anchor = CreateFrame("Frame", "OUIRaidAnchor", UIParent)
    end
    return self.anchor
end

function RF:UpdateAnchor()
    local a = self:EnsureAnchor()
    -- SetSize/SetPoint on the (secure-adjacent) anchor is a protected action in
    -- combat or from a tainted path (e.g. /ouimove from chat) -> defer it.
    if InCombatLockdown() then
        self._needLayout = true
        return a
    end
    local w, h = self:AnchorExtent()
    a:SetSize(w, h)
    a:ClearAllPoints()
    -- positioned by its TOP-LEFT corner -> stable when width or template changes
    a:SetPoint("TOPLEFT", UIParent, "CENTER", self.db.profile.x or -360, self.db.profile.y or 0)
    return a
end

-- ---------------------------------------------------------------------------
--  Colours / text
-- ---------------------------------------------------------------------------
local function BarTex()
    return (OUI.GetBarTexturePath and OUI.GetBarTexturePath(nil)) or WHITE
end

local function HealthColor(u)
    local _, class = UnitClass(u)
    if class then return OUI.GetClassColor(class, RF.db and RF.db.profile) end
    local g = OUI.GREEN or { r = 0.25, g = 0.75, b = 0.30 }
    return g.r, g.g, g.b
end

local function HealthString(cur, max, mode)
    if mode == "none" or not max or max <= 0 then return "" end
    if mode == "deficit" then
        local d = max - cur
        return d > 0 and ("-" .. (AbbreviateNumbers and AbbreviateNumbers(d) or d)) or ""
    end
    return ("%d%%"):format(math.floor(cur / max * 100 + 0.5))
end

-- aura helpers (modern C_UnitAuras with UnitAura fallback)
local function GetAura(unit, index, filter)
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local d = C_UnitAuras.GetAuraDataByIndex(unit, index, filter)
        if not d then return nil end
        return d.name, d.icon, d.applications, d.dispelName, d.duration, d.expirationTime, d.sourceUnit
    end
    if UnitAura then
        return UnitAura(unit, index, filter)
    end
end

-- which debuff types the player's class can remove (max class capability, MoP)
local DISPEL_BY_CLASS = {
    PRIEST  = { Magic = true, Disease = true },
    PALADIN = { Magic = true, Poison = true, Disease = true },
    SHAMAN  = { Magic = true, Curse = true },
    DRUID   = { Magic = true, Curse = true, Poison = true },
    MAGE    = { Curse = true },
    MONK    = { Magic = true, Poison = true, Disease = true },
    WARLOCK = { Magic = true },
}
local MY_DISPELS
local function MyDispels()
    if MY_DISPELS == nil then
        local _, class = UnitClass("player")
        MY_DISPELS = DISPEL_BY_CLASS[class] or false
    end
    return MY_DISPELS
end

local function MakeAuraIcon(parent, font)
    local b = CreateFrame("Frame", nil, parent)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints(b); b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints(b); b.cd:SetDrawEdge(false)
    b.count = b:CreateFontString(nil, "OVERLAY")
    b.count:SetFont(font, 9, "OUTLINE")
    b.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 1, 0)
    if OUI.PP and OUI.PP.CreateBorder then OUI.PP.CreateBorder(b, 0, 0, 0, 0.9) end
    return b
end

-- ---------------------------------------------------------------------------
--  Per-button skin + updates
-- ---------------------------------------------------------------------------
function RF:StyleButton(btn)
    if btn._ouiStyled then return end
    btn._ouiStyled = true
    if btn.RegisterForClicks then btn:RegisterForClicks("AnyUp") end

    local hb = CreateFrame("StatusBar", nil, btn)
    hb:SetStatusBarTexture(BarTex())
    btn.health = hb
    local bg = hb:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(hb); bg:SetTexture(WHITE); bg:SetVertexColor(0.12, 0.12, 0.12, 0.9)

    local pb = CreateFrame("StatusBar", nil, btn)
    pb:SetStatusBarTexture(BarTex())
    btn.power = pb
    local pbg = pb:CreateTexture(nil, "BACKGROUND")
    pbg:SetAllPoints(pb); pbg:SetTexture(WHITE); pbg:SetVertexColor(0.12, 0.12, 0.12, 0.9)

    local font = self._font or STANDARD_TEXT_FONT
    btn.name = hb:CreateFontString(nil, "OVERLAY")
    btn.name:SetFont(font, 10, "OUTLINE")
    btn.name:SetPoint("LEFT", hb, "LEFT", 2, 0)
    btn.name:SetPoint("RIGHT", hb, "RIGHT", -2, 0)
    btn.name:SetJustifyH("LEFT")
    if btn.name.SetWordWrap then btn.name:SetWordWrap(false) end

    btn.htext = hb:CreateFontString(nil, "OVERLAY")
    btn.htext:SetFont(font, 9, "OUTLINE")
    btn.htext:SetPoint("BOTTOMRIGHT", hb, "BOTTOMRIGHT", -2, 1)
    btn.htext:SetJustifyH("RIGHT")

    if OUI.PP and OUI.PP.CreateBorder then OUI.PP.CreateBorder(btn, 0, 0, 0, 0.9) end

    -- indicators live on the health bar so they draw above the fill
    btn.roleBg = hb:CreateTexture(nil, "ARTWORK"); btn.roleBg:SetColorTexture(0, 0, 0, 0.7)
    btn.roleBg:SetSize(16, 16); btn.roleBg:SetPoint("TOPLEFT", hb, "TOPLEFT", 1, -1); btn.roleBg:Hide()
    btn.role = hb:CreateTexture(nil, "OVERLAY"); btn.role:SetDrawLayer("OVERLAY", 5)
    btn.role:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-ROLES")
    btn.role:SetSize(15, 15); btn.role:SetPoint("CENTER", btn.roleBg, "CENTER", 0, 0); btn.role:Hide()
    btn.leaderBg = hb:CreateTexture(nil, "ARTWORK"); btn.leaderBg:SetColorTexture(0, 0, 0, 0.7)
    btn.leaderBg:SetSize(16, 16); btn.leaderBg:SetPoint("TOPRIGHT", hb, "TOPRIGHT", -1, -1); btn.leaderBg:Hide()
    btn.leader = hb:CreateTexture(nil, "OVERLAY"); btn.leader:SetDrawLayer("OVERLAY", 5)
    btn.leader:SetSize(15, 15); btn.leader:SetPoint("CENTER", btn.leaderBg, "CENTER", 0, 0); btn.leader:Hide()
    btn.raidIcon = hb:CreateTexture(nil, "OVERLAY"); btn.raidIcon:SetDrawLayer("OVERLAY", 6)
    btn.raidIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    btn.raidIcon:SetSize(16, 16); btn.raidIcon:SetPoint("TOP", hb, "TOP", 0, 1); btn.raidIcon:Hide()
    btn.deadIcon = hb:CreateTexture(nil, "OVERLAY"); btn.deadIcon:SetDrawLayer("OVERLAY", 6)
    btn.deadIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    btn.deadIcon:SetSize(20, 20); btn.deadIcon:SetPoint("CENTER", hb, "CENTER", 0, 0); btn.deadIcon:Hide()
    if SetRaidTargetIconTexture then SetRaidTargetIconTexture(btn.deadIcon, 8) end  -- skull
    btn.status = hb:CreateFontString(nil, "OVERLAY"); btn.status:SetDrawLayer("OVERLAY", 7)
    btn.status:SetFont(font, 9, "OUTLINE"); btn.status:SetPoint("CENTER", hb, "CENTER", 0, 0); btn.status:Hide()

    -- aura icon pools
    btn._buffs, btn._debuffs, btn._auraFont = {}, {}, font

    -- mouseover unit tooltip (real members only; preview buttons have no unit)
    btn:SetScript("OnEnter", function(self)
        local u = self:GetAttribute("unit")
        if u and UnitExists(u) then
            GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
            GameTooltip:SetUnit(u)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    self:LayoutButton(btn)
end

function RF:LayoutButton(btn, t)
    local s = self.db.profile
    t = t or self:T()
    local ph = s.showPower and (t.powerHeight or 7) or 0
    btn.health:ClearAllPoints()
    btn.health:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
    btn.health:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, 0)
    btn.health:SetPoint("BOTTOM", btn, "BOTTOM", 0, ph > 0 and (ph + 1) or 0)
    btn.health:SetStatusBarTexture(BarTex())
    if ph > 0 then
        btn.power:Show()
        btn.power:ClearAllPoints()
        btn.power:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
        btn.power:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
        btn.power:SetHeight(ph)
        btn.power:SetStatusBarTexture(BarTex())
    else
        btn.power:Hide()
    end
end

function RF:UpdateButton(btn)
    local u = btn:GetAttribute("unit")
    if not u or not UnitExists(u) then return end
    local s = self.db.profile
    local cur, max = UnitHealth(u), UnitHealthMax(u)
    btn.health:SetMinMaxValues(0, (max and max > 0) and max or 1)
    btn.health:SetValue(cur or 0)
    if UnitIsConnected(u) and not UnitIsDeadOrGhost(u) then
        btn.health:SetStatusBarColor(HealthColor(u))
    else
        btn.health:SetStatusBarColor(0.4, 0.4, 0.4)
    end
    if btn.name then btn.name:SetText(UnitName(u) or "") end
    if btn.htext then btn.htext:SetText(HealthString(cur or 0, max or 0, s.healthText)) end
    if btn.power and btn.power:IsShown() then
        local pcur, pmax = UnitPower(u), UnitPowerMax(u)
        btn.power:SetMinMaxValues(0, (pmax and pmax > 0) and pmax or 1)
        btn.power:SetValue(pcur or 0)
        local _, token = UnitPowerType(u)
        local c = token and OUI.GetPowerColor and OUI.GetPowerColor(token)
        if c then btn.power:SetStatusBarColor(c.r or c[1], c.g or c[2], c.b or c[3])
        else btn.power:SetStatusBarColor(0.3, 0.4, 0.9) end
    end

    -- role
    if btn.role then
        local role = s.showRole and UnitGroupRolesAssigned and UnitGroupRolesAssigned(u)
        if role and role ~= "NONE" and GetTexCoordsForRoleSmallCircle then
            btn.role:SetTexCoord(GetTexCoordsForRoleSmallCircle(role)); btn.role:Show(); btn.roleBg:Show()
        else btn.role:Hide(); btn.roleBg:Hide() end
    end
    -- leader / assistant
    if btn.leader then
        if s.showLeader and UnitIsGroupLeader(u) then
            btn.leader:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon"); btn.leader:Show(); btn.leaderBg:Show()
        elseif s.showLeader and UnitIsGroupAssistant and UnitIsGroupAssistant(u) then
            btn.leader:SetTexture("Interface\\GroupFrame\\UI-Group-AssistantIcon"); btn.leader:Show(); btn.leaderBg:Show()
        else btn.leader:Hide(); btn.leaderBg:Hide() end
    end
    -- raid target marker
    if btn.raidIcon then
        local idx = s.showRaidIcon and GetRaidTargetIndex(u)
        if idx and SetRaidTargetIconTexture then SetRaidTargetIconTexture(btn.raidIcon, idx); btn.raidIcon:Show()
        else btn.raidIcon:Hide() end
    end
    -- dead -> skull overlay; offline -> text
    if btn.status then
        if not UnitIsConnected(u) then
            btn.status:SetText("Off"); btn.status:SetTextColor(0.6, 0.6, 0.6); btn.status:Show()
            if btn.deadIcon then btn.deadIcon:Hide() end
        elseif UnitIsDeadOrGhost(u) then
            btn.status:Hide()
            if btn.deadIcon then btn.deadIcon:Show() end
        else
            btn.status:Hide()
            if btn.deadIcon then btn.deadIcon:Hide() end
        end
    end
    -- threat border
    if OUI.PP and OUI.PP.SetBorderColor then
        local st = s.showThreat and UnitThreatSituation(u)
        if st and st > 0 then
            local tr, tg, tb = GetThreatStatusColor(st)
            OUI.PP.SetBorderColor(btn, tr, tg, tb, 1)
        else
            OUI.PP.SetBorderColor(btn, 0, 0, 0, 0.9)
        end
    end
    self:UpdateAuras(btn, u)
end

-- ---------------------------------------------------------------------------
--  Auras: debuffs grow left from bottom-right, buffs grow right from bottom-left
-- ---------------------------------------------------------------------------
function RF:UpdateAuras(btn, unit)
    local s = self.db.profile
    local size = s.auraSize or 18
    local hb = btn.health

    local function fill(pool, filter, maxN, show, accept)
        local shown = 0
        if show then
            local idx = 1
            while shown < maxN do
                local name, icon, count, dtype, duration, expiration, caster = GetAura(unit, idx, filter)
                if not name then break end
                if icon and (not accept or accept(dtype, caster)) then
                    shown = shown + 1
                    local a = pool[shown]
                    if not a then a = MakeAuraIcon(hb, btn._auraFont); pool[shown] = a end
                    a:SetSize(size, size)
                    a.icon:SetTexture(icon)
                    if count and count > 1 then a.count:SetText(count) else a.count:SetText("") end
                    if duration and duration > 0 and expiration and expiration > 0 then
                        a.cd:SetCooldown(expiration - duration, duration); a.cd:Show()
                        if a.cd.SetHideCountdownNumbers then
                            a.cd:SetHideCountdownNumbers(s.hideAuraTime and true or false)
                        end
                    else a.cd:Hide() end
                    if filter == "HARMFUL" and OUI.PP and OUI.PP.SetBorderColor then
                        local c = DebuffTypeColor and DebuffTypeColor[dtype or "none"]
                        if c then OUI.PP.SetBorderColor(a, c.r, c.g, c.b, 1)
                        else OUI.PP.SetBorderColor(a, 0.8, 0, 0, 1) end
                    end
                    a:Show()
                end
                idx = idx + 1
            end
        end
        for i = shown + 1, #pool do pool[i]:Hide() end
        return shown
    end

    local debuffAccept
    if s.debuffsDispellableOnly then
        debuffAccept = function(dtype) local md = MyDispels(); return md and dtype and md[dtype] end
    end
    local buffAccept
    if s.buffsOwnOnly then
        buffAccept = function(_, caster) return caster == "player" end
    end

    local nd = fill(btn._debuffs, "HARMFUL", s.maxDebuffs or 3, s.showDebuffs, debuffAccept)
    for i = 1, nd do
        local a = btn._debuffs[i]
        a:ClearAllPoints()
        a:SetPoint("BOTTOMRIGHT", hb, "BOTTOMRIGHT", -((i - 1) * (size + 1)) - 1, 1)
    end
    local nb = fill(btn._buffs, "HELPFUL", s.maxBuffs or 3, s.showBuffs, buffAccept)
    for i = 1, nb do
        local a = btn._buffs[i]
        a:ClearAllPoints()
        a:SetPoint("BOTTOMLEFT", hb, "BOTTOMLEFT", ((i - 1) * (size + 1)) + 1, 1)
    end
end

-- ---------------------------------------------------------------------------
--  Roster: scan header children, skin new buttons, build unit->button map
-- ---------------------------------------------------------------------------
function RF:RefreshRoster()
    if InCombatLockdown() then self._needRoster = true; return end
    local hdr = self.header
    if not hdr then return end
    wipe(self.unitMap)
    local i = 1
    while true do
        local btn = hdr:GetAttribute("child" .. i) or _G[hdr:GetName() .. "UnitButton" .. i]
        if not btn then break end
        self:StyleButton(btn)
        local u = btn:GetAttribute("unit")
        if u then
            self.unitMap[u] = self.unitMap[u] or {}
            self.unitMap[u][#self.unitMap[u] + 1] = btn
            self:UpdateButton(btn)
        end
        i = i + 1
    end
end

function RF:UpdateUnit(unit)
    local list = self.unitMap[unit]
    if not list then return end
    for _, btn in ipairs(list) do self:UpdateButton(btn) end
end

-- group size changed: if it crosses a template threshold, re-lay the header
function RF:OnRoster()
    local key = self:ResolveTemplateKey()
    if key ~= self._activeKey then
        self._activeKey = key
        self:ApplyLayout()
    else
        self:RefreshRoster()
    end
    self:HideBlizzardParty()
end

-- refresh every styled button (for non-unit events: roles, markers, ready check)
function RF:RefreshAll()
    local i = 1
    while true do
        local btn = _G["OUIRaidHeaderUnitButton" .. i]
        if not btn then break end
        if btn._ouiStyled then self:UpdateButton(btn) end
        i = i + 1
    end
end

function RF:SetupRangeTicker()
    if self._rangeTicker then return end
    local t = CreateFrame("Frame"); self._rangeTicker = t; t.acc = 0
    t:SetScript("OnUpdate", function(_, dt)
        t.acc = t.acc + dt
        if t.acc < 0.25 then return end
        t.acc = 0
        if not RF.db.profile.rangeFade then return end
        local fade = RF.db.profile.fadeAlpha or 0.45
        local i = 1
        while true do
            local btn = _G["OUIRaidHeaderUnitButton" .. i]
            if not btn then break end
            if btn._ouiStyled and btn:IsShown() then
                local u = btn:GetAttribute("unit")
                if u and UnitExists(u) then
                    btn:SetAlpha(UnitInRange(u) and 1 or fade)
                end
            end
            i = i + 1
        end
    end)
end

-- ---------------------------------------------------------------------------
--  Header build + layout
-- ---------------------------------------------------------------------------
local INIT_CONFIG = [=[
    local hdr = self:GetParent()
    self:SetWidth(hdr:GetAttribute("OUIButtonWidth") or 90)
    self:SetHeight(hdr:GetAttribute("OUIButtonHeight") or 40)
    self:SetAttribute("*type1", "target")
    self:SetAttribute("*type2", "togglemenu")
    self:SetAttribute("toggleForVehicle", true)
]=]

function RF:BuildHeader()
    if self.header then return self.header end
    local hdr = CreateFrame("Frame", "OUIRaidHeader", UIParent, "SecureGroupHeaderTemplate")
    self.header = hdr
    hdr:SetAttribute("template", "SecureUnitButtonTemplate")
    hdr:SetAttribute("initialConfigFunction", INIT_CONFIG)
    hdr:SetAttribute("groupFilter", "1,2,3,4,5,6,7,8")
    hdr:Show()
    return hdr
end

function RF:ApplyLayout()
    if InCombatLockdown() then self._needLayout = true; return end
    local s = self.db.profile
    local t = self.db.profile.templates[self:HeaderKey()]
    local hdr = self:BuildHeader()
    local anchor = self:UpdateAnchor()

    hdr:SetAttribute("OUIButtonWidth", t.width)
    hdr:SetAttribute("OUIButtonHeight", t.height)

    -- column anchor decides which way columns stack
    local colAnchor = t.columnAnchor or "LEFT"
    local yo = (t.point == "BOTTOM") and t.rowSpacing or -t.rowSpacing
    local colSp = (colAnchor == "LEFT") and t.columnSpacing or -t.columnSpacing

    hdr:SetAttribute("point", t.point or "TOP")
    hdr:SetAttribute("xOffset", 0)
    hdr:SetAttribute("yOffset", yo)
    hdr:SetAttribute("columnAnchorPoint", colAnchor)
    hdr:SetAttribute("columnSpacing", math.abs(t.columnSpacing or 8))
    hdr:SetAttribute("unitsPerColumn", t.unitsPerColumn or 5)
    hdr:SetAttribute("maxColumns", t.maxColumns or 8)
    hdr:SetAttribute("showPlayer", s.showPlayer ~= false)
    hdr:SetAttribute("showParty", true)
    hdr:SetAttribute("showRaid", true)
    hdr:SetAttribute("showSolo", s.showSolo or false)

    hdr:SetScale(t.scale or 1.0)
    hdr:ClearAllPoints()
    -- all sizes grow from the SAME top-left (the shared anchor box)
    hdr:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)

    -- existing buttons need the new size + relayout
    local i = 1
    while true do
        local btn = _G["OUIRaidHeaderUnitButton" .. i]
        if not btn then break end
        if btn._ouiStyled then btn:SetSize(t.width, t.height); self:LayoutButton(btn, t) end
        i = i + 1
    end

    if s.enabled then hdr:Show() else hdr:Hide() end
    self:RefreshRoster()
    if self.testMode then self:LayoutPreview() end
end

-- ---------------------------------------------------------------------------
--  Preview / test mode
--  The secure header only spawns buttons for real members, so the config
--  preview uses a parallel set of insecure look-alike buttons filled with
--  placeholder data (varied classes, roles, a leader, markers, a dead member
--  and a threat border) laid out with the same grid math.
-- ---------------------------------------------------------------------------
local PREVIEW_CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
    "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "MONK", "DRUID" }
local PREVIEW_ROLES = { "TANK", "HEALER", "DAMAGER" }

function RF:FillTestButton(btn, i)
    local s = self.db.profile
    local class = PREVIEW_CLASSES[((i - 1) % #PREVIEW_CLASSES) + 1]
    local r, g, b = OUI.GetClassColor(class, RF.db and RF.db.profile)
    local dead = (i % 9 == 0)
    btn.health:SetMinMaxValues(0, 100)
    btn.health:SetValue(dead and 0 or math.random(35, 100))
    if dead then btn.health:SetStatusBarColor(0.4, 0.4, 0.4) else btn.health:SetStatusBarColor(r, g, b) end
    if btn.power and btn.power:IsShown() then
        btn.power:SetMinMaxValues(0, 100); btn.power:SetValue(math.random(20, 100))
        btn.power:SetStatusBarColor(0.3, 0.4, 0.9)
    end
    btn.name:SetText("Member " .. i)
    btn.htext:SetText("")
    if btn.role then
        if s.showRole and GetTexCoordsForRoleSmallCircle then
            btn.role:SetTexCoord(GetTexCoordsForRoleSmallCircle(PREVIEW_ROLES[((i - 1) % 3) + 1])); btn.role:Show(); btn.roleBg:Show()
        else btn.role:Hide(); btn.roleBg:Hide() end
    end
    if btn.leader then
        if s.showLeader and i == 1 then
            btn.leader:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon"); btn.leader:Show(); btn.leaderBg:Show()
        else btn.leader:Hide(); btn.leaderBg:Hide() end
    end
    if btn.raidIcon then
        if s.showRaidIcon and i <= 3 and SetRaidTargetIconTexture then
            SetRaidTargetIconTexture(btn.raidIcon, i); btn.raidIcon:Show()
        else btn.raidIcon:Hide() end
    end
    if btn.status then
        if dead then btn.status:Hide(); if btn.deadIcon then btn.deadIcon:Show() end
        else btn.status:Hide(); if btn.deadIcon then btn.deadIcon:Hide() end end
    end
    if OUI.PP and OUI.PP.SetBorderColor then
        if s.showThreat and i == 2 then
            local tr, tg, tb = GetThreatStatusColor(3)
            OUI.PP.SetBorderColor(btn, tr, tg, tb, 1)
        else OUI.PP.SetBorderColor(btn, 0, 0, 0, 0.9) end
    end
    -- fake debuffs on a few members to preview the aura row
    local size = s.auraSize or 18
    local nd = (s.showDebuffs and (i % 3 == 0)) and math.min(s.maxDebuffs or 3, 2) or 0
    for k = 1, nd do
        local a = btn._debuffs[k]
        if not a then a = MakeAuraIcon(btn.health, btn._auraFont); btn._debuffs[k] = a end
        a:SetSize(size, size)
        a.icon:SetTexture("Interface\\Icons\\Spell_Shadow_ShadowWordPain")
        a.count:SetText(k == 1 and "2" or "")
        a.cd:Hide()
        if OUI.PP and OUI.PP.SetBorderColor then OUI.PP.SetBorderColor(a, 0.6, 0.1, 0.7, 1) end
        a:ClearAllPoints()
        a:SetPoint("BOTTOMRIGHT", btn.health, "BOTTOMRIGHT", -((k - 1) * (size + 1)) - 1, 1)
        a:Show()
    end
    for k = nd + 1, #btn._debuffs do btn._debuffs[k]:Hide() end
    for k = 1, #(btn._buffs or {}) do btn._buffs[k]:Hide() end
end

function RF:LayoutPreview()
    local s = self.db.profile
    local cntKey = self._previewTemplate or self:ResolveTemplateKey()
    local t = self.db.profile.templates[self:PreviewLayoutKey()]
    if not self.preview then
        self.preview = CreateFrame("Frame", "OUIRaidPreview", UIParent)
        self.previewBtns = {}
    end
    local anchor = self:UpdateAnchor()
    local c = self.preview
    c:SetScale(t.scale or 1.0)
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
    local upc   = t.unitsPerColumn or 5
    local cap   = TEMPLATE_COUNT[cntKey] or 25
    local count = math.min((t.maxColumns or 8) * upc, cap)
    local w, h  = t.width, t.height
    local rowSp = t.rowSpacing or 4
    local colSp = t.columnSpacing or 8
    for i = 1, count do
        local btn = self.previewBtns[i]
        if not btn then
            btn = CreateFrame("Button", "OUIRaidPreviewBtn" .. i, c)
            self.previewBtns[i] = btn
            self:StyleButton(btn)
        end
        btn:SetSize(w, h); self:LayoutButton(btn, t)
        local col = math.floor((i - 1) / upc)
        local row = (i - 1) % upc
        local xo = (t.columnAnchor == "RIGHT") and -(col * (w + colSp)) or (col * (w + colSp))
        local yo = (t.point == "BOTTOM") and (row * (h + rowSp)) or -(row * (h + rowSp))
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", c, "TOPLEFT", xo, yo)
        btn:Show()
        self:FillTestButton(btn, i)
    end
    for i = count + 1, #self.previewBtns do self.previewBtns[i]:Hide() end
    c:SetSize(1, 1)
    self:UpdatePreviewSwitcher()
end

function RF:SetTestMode(on)
    if InCombatLockdown() then
        OUI:Print("|cffd9a441[OUI RaidFrames]|r preview can't be toggled in combat.")
        return
    end
    self.testMode = on and true or false
    if self.testMode then
        if not self._previewTemplate then self._previewTemplate = self:ResolveTemplateKey() end
        if self.header then self.header:Hide() end
        self:LayoutPreview()
        self.preview:Show()
        if self._previewSwitcher then self._previewSwitcher:Show() end
    else
        if self.preview then self.preview:Hide() end
        if self._previewSwitcher then self._previewSwitcher:Hide() end
        if self.header and self.db.profile.enabled then self.header:Show() end
        self:RefreshRoster()
    end
end

function RF:SetPreviewTemplate(key)
    if not TEMPLATE_COUNT[key] then return end
    self._previewTemplate = key
    if self.testMode then self:LayoutPreview() end
end

-- 10 / 25 / 40 switcher shown above the preview
function RF:BuildPreviewSwitcher()
    if self._previewSwitcher then return self._previewSwitcher end
    local bar = CreateFrame("Frame", "OUIRaidPreviewSwitcher", UIParent)
    bar:SetSize(150, 22)
    bar._btns = {}
    local x = 0
    for _, key in ipairs(TEMPLATE_KEYS) do
        local b = CreateFrame("Button", nil, bar)
        b:SetSize(46, 20); b:SetPoint("LEFT", bar, "LEFT", x, 0); x = x + 50
        b._bg = b:CreateTexture(nil, "BACKGROUND"); b._bg:SetAllPoints(); b._bg:SetColorTexture(0.1, 0.1, 0.1, 0.9)
        if OUI.PP and OUI.PP.CreateBorder then OUI.PP.CreateBorder(b, 0, 0, 0, 0.9) end
        b._txt = b:CreateFontString(nil, "OVERLAY"); b._txt:SetFont(RF._font, 11, "OUTLINE")
        b._txt:SetPoint("CENTER"); b._txt:SetText(TEMPLATE_LABEL[key])
        b._key = key
        b:SetScript("OnClick", function() RF:SetPreviewTemplate(key) end)
        bar._btns[key] = b
    end
    self._previewSwitcher = bar
    return bar
end

function RF:UpdatePreviewSwitcher()
    if not self.testMode then return end
    local bar = self:BuildPreviewSwitcher()
    bar:ClearAllPoints()
    bar:SetPoint("BOTTOMLEFT", self.anchor or self.preview, "TOPLEFT", 0, 6)
    bar:Show()
    local active = self:EditTemplateKey()
    for key, b in pairs(bar._btns) do
        if key == active then
            local r, g, bl = OUI.ACCENT.r, OUI.ACCENT.g, OUI.ACCENT.b
            b._bg:SetColorTexture(r * 0.5, g * 0.5, bl * 0.5, 0.95)
            b._txt:SetTextColor(1, 1, 1)
        else
            b._bg:SetColorTexture(0.1, 0.1, 0.1, 0.9)
            b._txt:SetTextColor(0.7, 0.7, 0.7)
        end
    end
end

-- ---------------------------------------------------------------------------
--  Mover
-- ---------------------------------------------------------------------------
function RF:RegisterMover()
    if not (OUI.RegisterUnlockElements and OUI.MakeUnlockElement) then return end
    OUI:RegisterUnlockElements({
        OUI.MakeUnlockElement({
            key      = "OUIRaidHeader",
            label    = "Raid Frames",
            getFrame = function() return RF:EnsureAnchor() end,
            getSize  = function() return RF:AnchorExtent() end,
            isHidden = function() return not RF.db.profile.enabled end,
            savePos  = function(_, _, _, cx, cy)
                local w, h = RF:AnchorExtent()
                RF.db.profile.x = cx - w / 2   -- left edge
                RF.db.profile.y = cy + h / 2   -- top edge
                RF:ApplyLayout()
            end,
            applyPos = function() RF:ApplyLayout() end,
        }),
    })
end

-- ---------------------------------------------------------------------------
--  Suppress Blizzard party / raid frames OUI replaces (taint-safe, OOC only)
-- ---------------------------------------------------------------------------
local function killBlizz(name)
    local f = _G[name]
    if not f then return end
    if not f._ouiKilled then
        f._ouiKilled = true
        if f.UnregisterAllEvents then f:UnregisterAllEvents() end
        f:HookScript("OnShow", function(s)
            if RF.db and RF.db.profile.hideBlizzard and not InCombatLockdown() then s:Hide() end
        end)
    end
    f:Hide()
end

function RF:HideBlizzardParty()
    if InCombatLockdown() then self._needBlizzHide = true; return end
    if not self.db.profile.hideBlizzard then return end
    killBlizz("CompactRaidFrameManager")
    killBlizz("CompactRaidFrameContainer")
    killBlizz("CompactPartyFrame")
    killBlizz("PartyFrame")               -- modern MoP-Classic party container (MemberFrame1..5)
    for i = 1, 5 do killBlizz("PartyMemberFrame" .. i) end  -- legacy fallback
    if CompactRaidFrameManager_UpdateShown and not self._crfHook then
        self._crfHook = true
        hooksecurefunc("CompactRaidFrameManager_UpdateShown", function()
            if RF.db and RF.db.profile.hideBlizzard and not InCombatLockdown()
                and CompactRaidFrameManager then
                CompactRaidFrameManager:Hide()
            end
        end)
    end
end

-- ---------------------------------------------------------------------------
--  Lifecycle
-- ---------------------------------------------------------------------------
function RF:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("OldschoolUIRaidFramesDB", defaults, true)
    self.unitMap = {}
    self._font = (OUI.GetFontPath and OUI.GetFontPath()) or STANDARD_TEXT_FONT
end

function RF:OnEnable()
    if OUI.IsModuleEnabled and not OUI:IsModuleEnabled("OUI_RaidFrames") then return end
    self:ApplyLayout()
    self:HideBlizzardParty()
    self:RegisterMover()
    self:SetupRangeTicker()

    local d = CreateFrame("Frame"); self._disp = d
    for _, e in ipairs({
        "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_HEALTH_FREQUENT",
        "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER",
        "UNIT_NAME_UPDATE", "UNIT_CONNECTION", "UNIT_FLAGS", "UNIT_AURA",
        "UNIT_THREAT_SITUATION_UPDATE", "UNIT_THREAT_LIST_UPDATE",
    }) do pcall(d.RegisterEvent, d, e) end
    d:SetScript("OnEvent", function(_, _, unit) if unit then RF:UpdateUnit(unit) end end)

    self:RegisterEvent("GROUP_ROSTER_UPDATE", "OnRoster")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnRoster")
    self:RegisterEvent("PLAYER_ROLES_ASSIGNED", "RefreshAll")
    self:RegisterEvent("RAID_TARGET_UPDATE", "RefreshAll")
    self:RegisterEvent("READY_CHECK", "RefreshAll")
    self:RegisterEvent("READY_CHECK_FINISHED", "RefreshAll")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
        if RF._needLayout then RF._needLayout = nil; RF:ApplyLayout() end
        if RF._needRoster then RF._needRoster = nil; RF:RefreshRoster() end
        if RF._needBlizzHide then RF._needBlizzHide = nil end
        RF:HideBlizzardParty()
    end)

    if OUI.RegisterStyleListener then
        OUI.RegisterStyleListener(function()
            local i = 1
            while true do
                local btn = _G["OUIRaidHeaderUnitButton" .. i]
                if not btn then break end
                if btn.health then btn.health:SetStatusBarTexture(BarTex()) end
                if btn.power then btn.power:SetStatusBarTexture(BarTex()) end
                i = i + 1
            end
            RF:RefreshAll()
            if RF.testMode then RF:LayoutPreview() end
        end)
    end
end

-- ---------------------------------------------------------------------------
--  Slash
-- ---------------------------------------------------------------------------
SLASH_OUIRF1 = "/ouirf"
SlashCmdList["OUIRF"] = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "unlock" or msg == "move" then
        if OUI.ToggleUnlock then OUI:ToggleUnlock(true) end
    elseif msg == "lock" then
        if OUI.ToggleUnlock then OUI:ToggleUnlock(false) end
    elseif msg == "test" or msg == "preview" then
        RF:SetTestMode(not RF.testMode)
        OUI:Print("|cffd9a441[OUI RaidFrames]|r preview " .. (RF.testMode and "ON" or "OFF") .. ".")
    elseif msg == "preview 10" or msg == "10" then
        if not RF.testMode then RF:SetTestMode(true) end; RF:SetPreviewTemplate("small")
    elseif msg == "preview 25" or msg == "25" then
        if not RF.testMode then RF:SetTestMode(true) end; RF:SetPreviewTemplate("medium")
    elseif msg == "preview 40" or msg == "40" then
        if not RF.testMode then RF:SetTestMode(true) end; RF:SetPreviewTemplate("large")
    elseif msg == "solo" then
        RF.db.profile.showSolo = not RF.db.profile.showSolo
        RF:ApplyLayout()
        OUI:Print("|cffd9a441[OUI RaidFrames]|r show when solo: " .. tostring(RF.db.profile.showSolo))
    else
        OUI:Print("|cffd9a441[OUI RaidFrames]|r /ouirf unlock|lock | preview [10|25|40] | solo · or /ouimove")
    end
end

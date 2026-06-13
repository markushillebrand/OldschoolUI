-------------------------------------------------------------------------------
-- OldschoolUILootRoll.lua
--
-- Custom group-loot roll bars for MoP Classic. Replaces Blizzard's default
-- GroupLootFrame with stacked EUI-styled bars: item icon, quality-colored
-- border + name, a countdown status bar, Need / Greed / Disenchant / Pass
-- buttons, and a live per-button roll tally sourced from C_LootHistory
-- (locale-independent, unlike the old ElvUI chat-parse approach).
--
-- API generation matches MoP Classic 5.5 (interface 50504):
--   START_LOOT_ROLL(rollID, rollTime) / CANCEL_LOOT_ROLL(rollID)
--   GetLootRollItemInfo / GetLootRollItemLink / GetLootRollTimeLeft (ms)
--   RollOnLoot(rollID, 0=pass|1=need|2=greed|3=disenchant)
--   C_LootHistory.GetItem / GetPlayerInfo  (+ LOOT_HISTORY_ROLL_CHANGED)
-------------------------------------------------------------------------------
local addonName, ns = ...

local ELR = {}
ns.ELR = ELR
_G.OldschoolUILootRoll = ELR

local CreateFrame, UIParent = CreateFrame, UIParent
local GetLootRollItemInfo  = GetLootRollItemInfo
local GetLootRollItemLink  = GetLootRollItemLink
local GetLootRollTimeLeft  = GetLootRollTimeLeft
local RollOnLoot           = RollOnLoot
local SetDesaturation      = SetDesaturation
local IsModifiedClick      = IsModifiedClick
local DressUpItemLink      = DressUpItemLink
local ChatEdit_InsertLink  = ChatEdit_InsertLink
local ITEM_QUALITY_COLORS  = ITEM_QUALITY_COLORS
local C_LootHistory        = C_LootHistory
local C_Timer              = C_Timer
local GameTooltip          = GameTooltip
local hooksecurefunc       = hooksecurefunc
local format               = string.format
local wipe                 = wipe
local ipairs, pairs        = ipairs, pairs

-- Roll-type constants (match RollOnLoot / C_LootHistory rollType).
local ROLL_PASS, ROLL_NEED, ROLL_GREED, ROLL_DE = 0, 1, 2, 3

-- Button art (present in MoP).
local TEX = {
    need  = "Interface\\Buttons\\UI-GroupLoot-Dice-Up",
    needD = "Interface\\Buttons\\UI-GroupLoot-Dice-Down",
    needH = "Interface\\Buttons\\UI-GroupLoot-Dice-Highlight",
    greed = "Interface\\Buttons\\UI-GroupLoot-Coin-Up",
    greedD= "Interface\\Buttons\\UI-GroupLoot-Coin-Down",
    greedH= "Interface\\Buttons\\UI-GroupLoot-Coin-Highlight",
    de    = "Interface\\Buttons\\UI-GroupLoot-DE-Up",
    deD   = "Interface\\Buttons\\UI-GroupLoot-DE-Down",
    deH   = "Interface\\Buttons\\UI-GroupLoot-DE-Highlight",
    pass  = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
    passD = "Interface\\Buttons\\UI-GroupLoot-Pass-Down",
}

-------------------------------------------------------------------------------
-- DB
-------------------------------------------------------------------------------
local DEFAULTS = { profile = { lootRoll = {
    enabled        = true,
    width          = 328,
    height         = 28,
    growth         = "DOWN",   -- DOWN (default) | UP
    spacing        = 4,
    showDisenchant = true,
    showRollCounts = true,
    qualityBorder  = true,
    scale          = 1.0,
    position       = nil,
    -- Session / bonus-roll features
    showOthersRolls = true,    -- show individual other-player rolls in session view
    minimapButton   = true,    -- show the minimap loot-roll button (under calendar)
    autoConfirmBoP  = false,   -- auto-confirm Need/Greed on BoP / BoA items
    bonusReminder   = false,   -- announce when a wishlisted bonus roll is available
    bonusAutoIgnore = false,   -- auto-decline bonus rolls with no open wish here
    bonusMaxShow    = 20,      -- history rows shown in the window
    wishlistDropHint = true,   -- hint when a dropped roll item is on the wishlist
    wishlistUsableOnly = true,  -- only show items usable by the character in the browser
} } }

local _db
local function EnsureDB()
    if _db then return _db end
    local AceDB = LibStub and LibStub("AceDB-3.0", true)
    if not AceDB then return nil end
    _db = AceDB:New("OldschoolUILootRollDB", DEFAULTS)
    _G._ELR_DB = _db
    return _db
end
local function DB()
    local d = EnsureDB()
    if d and d.profile and d.profile.lootRoll then return d.profile.lootRoll end
    return DEFAULTS.profile.lootRoll
end
ns.LR_GetSettings = DB  -- exposed for EUI_LootRoll_BonusRolls / _Session
ELR.DB = DB

local function L(s) return (OldschoolUI and OldschoolUI.L and OldschoolUI.L(s)) or s end
local function FontPath()
    return (OldschoolUI and OldschoolUI.GetFontPath and OldschoolUI.GetFontPath()) or STANDARD_TEXT_FONT
end
local function SetFont(fs, size, flags)
    fs:SetFont(FontPath(), size or 12, flags or "OUTLINE")
end

-------------------------------------------------------------------------------
-- Anchor + mover
-------------------------------------------------------------------------------
local anchor
local bars = {}

local function ApplyAnchor()
    if not anchor then return end
    local db = DB()
    anchor:SetSize(db.width or 328, db.height or 28)
    anchor:ClearAllPoints()
    local pos = db.position
    if pos and pos.point then
        anchor:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
    else
        anchor:SetPoint("TOP", UIParent, "TOP", 0, -200)
    end
end

local function EnsureAnchor()
    if anchor then return anchor end
    anchor = CreateFrame("Frame", "OldschoolUILootRollAnchor", UIParent)
    ApplyAnchor()
    return anchor
end

-- Re-stack all visible bars from the anchor in the configured direction.
local function Restack()
    local db = DB()
    local down = (db.growth ~= "UP")
    local sp = db.spacing or 4
    local prev = EnsureAnchor()
    for _, b in ipairs(bars) do
        if b:IsShown() then
            b:SetScale(db.scale or 1)
            b:ClearAllPoints()
            if down then
                b:SetPoint("TOP", prev, prev == anchor and "BOTTOM" or "BOTTOM", 0, -sp)
            else
                b:SetPoint("BOTTOM", prev, prev == anchor and "TOP" or "TOP", 0, sp)
            end
            prev = b
        end
    end
end
ELR.Restack = Restack

-------------------------------------------------------------------------------
-- Bar widgets / scripts
-------------------------------------------------------------------------------
local function SetBorderColor(bar, r, g, b, a)
    for _, e in ipairs(bar._border) do e:SetColorTexture(r, g, b, a or 1) end
end

local function CountBtn(bar, rt)
    return (rt == ROLL_NEED and bar.needBtn)
        or (rt == ROLL_GREED and bar.greedBtn)
        or (rt == ROLL_DE and bar.deBtn)
        or (rt == ROLL_PASS and bar.passBtn) or nil
end
local function SetCount(bar, rt, n)
    local btn = CountBtn(bar, rt)
    if btn and btn._count then btn._count:SetText((n and n > 0) and n or "") end
end

local function EnableButton(btn, can)
    if not btn then return end
    if can then btn:Enable(); btn:SetAlpha(1) else btn:Disable(); btn:SetAlpha(0.25) end
    local nt = btn:GetNormalTexture()
    if nt then SetDesaturation(nt, not can) end
end

local _confirmHookInstalled = false
local _pendingRoll  -- { id = rollID, rt = rollType } of the most recent RollOnLoot, for the BoP confirm popup
local function RollBtn_OnClick(self)
    local bar = self._bar
    if bar and bar.rollID and not bar._sim then
        _pendingRoll = { id = bar.rollID, rt = self._rolltype }
        RollOnLoot(bar.rollID, self._rolltype)
    end
end
local function RollBtn_OnEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(self._tip or "")
    if self:IsEnabled() == false then GameTooltip:AddLine("|cffff3333" .. L("Can't Roll")) end
    local bar = self._bar
    if bar and bar.rolls then
        for name, rt in pairs(bar.rolls) do
            if rt == self._rolltype then GameTooltip:AddLine(name, 1, 1, 1) end
        end
    end
    GameTooltip:Show()
end
local function Btn_OnLeave() GameTooltip:Hide() end

local function Icon_OnEnter(self)
    local bar = self._bar
    if not bar.link then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
    GameTooltip:SetHyperlink(bar.link)
    GameTooltip:Show()
end
local function Icon_OnClick(self)
    local bar = self._bar
    if not bar.link then return end
    if IsModifiedClick("DRESSUP") then DressUpItemLink(bar.link)
    elseif IsModifiedClick("CHATLINK") then ChatEdit_InsertLink(bar.link) end
end

local function Status_OnUpdate(self)
    local bar = self._bar
    if not bar.rollID and not bar._sim then self:GetParent():Hide(); return end
    local t
    if bar._sim then
        t = bar._simLeft or 0
    else
        t = GetLootRollTimeLeft(bar.rollID) or 0
    end
    self:SetValue(t)
    if bar.timerFS then bar.timerFS:SetText(format("%d", (t / 1000) + 0.5)) end
    if bar.spark then
        local minv, maxv = self:GetMinMaxValues()
        local perc = (maxv > 0) and (t / maxv) or 0
        bar.spark:SetPoint("CENTER", self, "LEFT", perc * self:GetWidth(), 0)
    end
    if (not bar._sim) and t > 1000000000 then self:GetParent():Hide() end
end

local function MakeRollButton(bar, rolltype, ntex, dtex, htex, tip)
    local b = CreateFrame("Button", nil, bar)
    b._bar = bar
    b._rolltype = rolltype
    b._tip = tip
    b:SetNormalTexture(ntex)
    if dtex then b:SetPushedTexture(dtex) end
    if htex then b:SetHighlightTexture(htex) end
    b:SetScript("OnClick", RollBtn_OnClick)
    b:SetScript("OnEnter", RollBtn_OnEnter)
    b:SetScript("OnLeave", Btn_OnLeave)
    b:SetMotionScriptsWhileDisabled(true)
    local count = b:CreateFontString(nil, "OVERLAY")
    SetFont(count, 11)
    count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 2, -2)
    b._count = count
    return b
end

-- Build one bar and lay out its regions from the current DB sizing.
local function CreateBar()
    local db = DB()
    local H = db.height or 28
    local Wd = db.width or 328
    local btn = H - 8
    local icon = H - 4

    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(Wd, H)
    f:Hide()

    -- background + 1px border
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.04, 0.04, 0.04, 0.9)
    f._bg = bg
    f._border = {}
    do
        local top = f:CreateTexture(nil, "BORDER"); top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(1)
        local bot = f:CreateTexture(nil, "BORDER"); bot:SetPoint("BOTTOMLEFT"); bot:SetPoint("BOTTOMRIGHT"); bot:SetHeight(1)
        local lft = f:CreateTexture(nil, "BORDER"); lft:SetPoint("TOPLEFT"); lft:SetPoint("BOTTOMLEFT"); lft:SetWidth(1)
        local rgt = f:CreateTexture(nil, "BORDER"); rgt:SetPoint("TOPRIGHT"); rgt:SetPoint("BOTTOMRIGHT"); rgt:SetWidth(1)
        f._border = { top, bot, lft, rgt }
    end
    SetBorderColor(f, 0, 0, 0, 1)

    -- countdown status bar (sits behind the row)
    local status = CreateFrame("StatusBar", nil, f)
    status:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    status:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    status:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    status:SetStatusBarColor(0.8, 0.8, 0.8, 0.45)
    status:SetFrameLevel(f:GetFrameLevel())
    status._bar = f
    status:SetScript("OnUpdate", Status_OnUpdate)
    f.status = status

    local spark = status:CreateTexture(nil, "OVERLAY")
    spark:SetSize(12, H)
    spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    spark:SetBlendMode("ADD")
    f.spark = spark

    -- icon button
    local ib = CreateFrame("Button", nil, f)
    ib._bar = f
    ib:SetSize(icon, icon)
    ib:SetPoint("LEFT", f, "LEFT", 3, 0)
    ib:SetFrameLevel(status:GetFrameLevel() + 2)
    local itex = ib:CreateTexture(nil, "ARTWORK")
    itex:SetAllPoints()
    itex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    ib.icon = itex
    f.icon = itex
    ib:SetScript("OnEnter", Icon_OnEnter)
    ib:SetScript("OnLeave", Btn_OnLeave)
    ib:SetScript("OnClick", Icon_OnClick)
    f.iconBtn = ib

    -- roll buttons
    local need = MakeRollButton(f, ROLL_NEED, TEX.need, TEX.needD, TEX.needH, NEED or "Need")
    need:SetSize(btn, btn); need:SetPoint("LEFT", ib, "RIGHT", 5, 0)
    need:SetFrameLevel(status:GetFrameLevel() + 2)
    local greed = MakeRollButton(f, ROLL_GREED, TEX.greed, TEX.greedD, TEX.greedH, GREED or "Greed")
    greed:SetSize(btn, btn); greed:SetPoint("LEFT", need, "RIGHT", 2, 0)
    greed:SetFrameLevel(status:GetFrameLevel() + 2)
    local de = MakeRollButton(f, ROLL_DE, TEX.de, TEX.deD, TEX.deH, ROLL_DISENCHANT or "Disenchant")
    de:SetSize(btn, btn); de:SetPoint("LEFT", greed, "RIGHT", 2, 0)
    de:SetFrameLevel(status:GetFrameLevel() + 2)
    local pass = MakeRollButton(f, ROLL_PASS, TEX.pass, TEX.passD, nil, PASS or "Pass")
    pass:SetSize(btn, btn); pass:SetFrameLevel(status:GetFrameLevel() + 2)
    f.needBtn, f.greedBtn, f.deBtn, f.passBtn = need, greed, de, pass

    -- BoP/BoE + item name
    local bind = f:CreateFontString(nil, "OVERLAY")
    SetFont(bind, 11)
    bind:SetText("")
    f.bind = bind
    local name = f:CreateFontString(nil, "OVERLAY")
    SetFont(name, 12)
    name:SetJustifyH("LEFT")
    name:SetPoint("RIGHT", f, "RIGHT", -6, 0)
    f.name = name

    -- centered countdown seconds
    local tfs = f:CreateFontString(nil, "OVERLAY")
    SetFont(tfs, 11)
    tfs:SetPoint("RIGHT", f, "RIGHT", -6, 0)
    tfs:SetTextColor(1, 1, 1, 0.7)
    f.timerFS = tfs

    f.rolls = {}
    bars[#bars + 1] = f
    return f
end

-- Apply the DE-button visibility + re-anchor pass/bind/name to the current
-- layout. Called on create and whenever sizing/DE options change.
local function LayoutBar(f)
    local db = DB()
    local showDE = db.showDisenchant ~= false
    local lastBtn
    if showDE then
        f.deBtn:Show()
        lastBtn = f.deBtn
    else
        f.deBtn:Hide()
        lastBtn = f.greedBtn
    end
    f.passBtn:ClearAllPoints()
    f.passBtn:SetPoint("LEFT", lastBtn, "RIGHT", 2, 0)
    f.bind:ClearAllPoints()
    f.bind:SetPoint("LEFT", f.passBtn, "RIGHT", 5, 0)
    f.name:ClearAllPoints()
    f.name:SetPoint("LEFT", f.bind, "RIGHT", 3, 0)
    f.name:SetPoint("RIGHT", f.timerFS, "LEFT", -4, 0)
end

-- Pool: reuse a free bar (no active roll) or create a new one.
local function GetBar()
    for _, b in ipairs(bars) do
        if not b.rollID and not b._sim then LayoutBar(b); return b end
    end
    local b = CreateBar()
    LayoutBar(b)
    return b
end

-------------------------------------------------------------------------------
-- Roll handling
-------------------------------------------------------------------------------
local function ResetCounts(bar)
    SetCount(bar, ROLL_NEED, 0); SetCount(bar, ROLL_GREED, 0)
    SetCount(bar, ROLL_DE, 0); SetCount(bar, ROLL_PASS, 0)
end

local _wishHintSeen = {}
local function HandleStartRoll(rollID, rollTime)
    if not DB().enabled then return end
    local texture, name, _, quality, bop, canNeed, canGreed, canDisenchant = GetLootRollItemInfo(rollID)
    if not name then return end
    local bar = GetBar()
    bar.rollID = rollID
    bar._sim = false
    bar.rolls = wipe(bar.rolls or {})
    bar.icon:SetTexture(texture)
    bar.link = GetLootRollItemLink(rollID)

    -- Wish-item hint: if this dropped roll item is on the wishlist for the
    -- current difficulty, nudge the player once (and suggest waiting for the
    -- normal roll result before spending a bonus roll).
    if DB().wishlistDropHint and ns.LR_IsWanted and bar.link then
        if not _wishHintSeen[rollID] then
            local iid = tonumber(bar.link:match("item:(%d+)"))
            local bucket = ns.LR_CurrentBucket and ns.LR_CurrentBucket() or nil
            if iid and ns.LR_IsWanted(iid, bucket) and ns.LR_Announce then
                _wishHintSeen[rollID] = true
                ns.LR_Announce(
                    OldschoolUI.Lf("Wish item dropped: %1$s", bar.link),
                    (ns.LR_T and ns.LR_T("On your wishlist - consider waiting for the roll result before bonus-rolling."))
                        or "On your wishlist.")
            end
        end
    end

    local q = ITEM_QUALITY_COLORS[quality] or ITEM_QUALITY_COLORS[1]
    bar._q = q
    bar.name:SetText(name)
    bar.name:SetTextColor(q.r, q.g, q.b)
    if DB().qualityBorder then SetBorderColor(bar, q.r, q.g, q.b, 1) else SetBorderColor(bar, 0, 0, 0, 1) end
    bar.status:SetStatusBarColor(q.r, q.g, q.b, 0.45)
    bar.status:SetMinMaxValues(0, rollTime)
    bar.status:SetValue(rollTime)

    bar.bind:SetText(bop and L("BoP") or L("BoE"))
    bar.bind:SetTextColor(bop and 1 or 0.3, bop and 0.3 or 1, bop and 0.1 or 0.3)

    EnableButton(bar.needBtn, canNeed)
    EnableButton(bar.greedBtn, canGreed)
    EnableButton(bar.deBtn, canDisenchant)
    ResetCounts(bar)

    bar:Show()
    Restack()
end

local function HandleCancelRoll(rollID)
    for _, b in ipairs(bars) do
        if b.rollID == rollID then
            b.rollID = nil
            b.link = nil
            b:Hide()
        end
    end
    Restack()
end

-- Locale-independent roll tally via C_LootHistory.
local function UpdateCounts()
    if not (C_LootHistory and DB().showRollCounts) then return end
    local n = (C_LootHistory.GetNumItems and C_LootHistory.GetNumItems()) or 0
    for _, bar in ipairs(bars) do
        if bar.rollID and not bar._sim then
            local need, greed, de, pass = 0, 0, 0, 0
            wipe(bar.rolls)
            for i = 1, n do
                local rID, _, numP = C_LootHistory.GetItem(i)
                if rID == bar.rollID then
                    for p = 1, (numP or 0) do
                        local pname, _, rt = C_LootHistory.GetPlayerInfo(i, p)
                        if rt == ROLL_NEED then need = need + 1
                        elseif rt == ROLL_GREED then greed = greed + 1
                        elseif rt == ROLL_DE then de = de + 1
                        elseif rt == ROLL_PASS then pass = pass + 1 end
                        if pname and rt then bar.rolls[pname] = rt end
                    end
                    break
                end
            end
            SetCount(bar, ROLL_NEED, need); SetCount(bar, ROLL_GREED, greed)
            SetCount(bar, ROLL_DE, de); SetCount(bar, ROLL_PASS, pass)
        end
    end
end

-------------------------------------------------------------------------------
-- Suppress Blizzard's default group loot UI
-------------------------------------------------------------------------------
local function SuppressBlizzard()
    if UIParent.UnregisterEvent then
        UIParent:UnregisterEvent("START_LOOT_ROLL")
        UIParent:UnregisterEvent("CANCEL_LOOT_ROLL")
    end
    if _G.GroupLootContainer then
        _G.GroupLootContainer:Hide()
        if not ELR._gcHooked and _G.GroupLootContainer_AddFrame then
            ELR._gcHooked = true
            hooksecurefunc("GroupLootContainer_AddFrame", function()
                if DB().enabled and _G.GroupLootContainer then _G.GroupLootContainer:Hide() end
            end)
        end
    end
end

-------------------------------------------------------------------------------
-- Rebuild (after layout-affecting option changes)
-------------------------------------------------------------------------------
function ELR.Rebuild()
    local db = DB()
    for _, b in ipairs(bars) do
        b:SetSize(db.width or 328, db.height or 28)
        LayoutBar(b)
        if b._q then
            if db.qualityBorder then SetBorderColor(b, b._q.r, b._q.g, b._q.b, 1)
            else SetBorderColor(b, 0, 0, 0, 1) end
        end
    end
    if db.showRollCounts ~= false then
        if UpdateCounts then UpdateCounts() end
        for _, b in ipairs(bars) do
            if b._sim then
                SetCount(b, ROLL_NEED, 1); SetCount(b, ROLL_GREED, 2)
                SetCount(b, ROLL_PASS, 1); SetCount(b, ROLL_DE, 0)
            end
        end
    else
        for _, b in ipairs(bars) do
            SetCount(b, ROLL_NEED, 0); SetCount(b, ROLL_GREED, 0)
            SetCount(b, ROLL_DE, 0); SetCount(b, ROLL_PASS, 0)
        end
    end
    ApplyAnchor()
    Restack()
end

-------------------------------------------------------------------------------
-- Mover
-------------------------------------------------------------------------------
local function RegisterMover()
    if not (OldschoolUI and OldschoolUI.RegisterUnlockElements and OldschoolUI.MakeUnlockElement) then return end
    local MK = OldschoolUI.MakeUnlockElement
    OldschoolUI:RegisterUnlockElements({
        MK({
            key = "EUI_LootRoll", label = "Loot Roll", group = "Loot Roll", order = 650,
            noResize = true, noAnchorTo = true,
            getFrame = function() return EnsureAnchor() end,
            getSize  = function() return (DB().width or 328), (DB().height or 28) end,
            isHidden = function() return not DB().enabled end,
            savePos = function(_, point, relPoint, x, y)
                local db = DB()
                db.position = { point = point, relPoint = relPoint, x = x, y = y }
                if not OldschoolUI._unlockActive then ApplyAnchor() end
            end,
            loadPos  = function() return DB().position end,
            clearPos = function() DB().position = nil end,
            applyPos = function() ApplyAnchor() end,
        }),
    })
end

-------------------------------------------------------------------------------
-- Sim / preview  (/ouilr test)
-------------------------------------------------------------------------------
function ELR.StartSim()
    local bar = GetBar()
    bar._sim = true
    bar.rollID = -1
    bar._simLeft = 30000
    bar.icon:SetTexture("Interface\\Icons\\INV_Sword_39")
    bar.link = nil
    local q = ITEM_QUALITY_COLORS[4]
    bar._q = q
    bar.name:SetText(L("Sim Epic Sword"))
    bar.name:SetTextColor(q.r, q.g, q.b)
    if DB().qualityBorder then SetBorderColor(bar, q.r, q.g, q.b, 1) else SetBorderColor(bar, 0, 0, 0, 1) end
    bar.status:SetStatusBarColor(q.r, q.g, q.b, 0.45)
    bar.status:SetMinMaxValues(0, 30000)
    bar.status:SetValue(30000)
    bar.bind:SetText(L("BoP")); bar.bind:SetTextColor(1, 0.3, 0.1)
    EnableButton(bar.needBtn, true)
    EnableButton(bar.greedBtn, true)
    EnableButton(bar.deBtn, DB().showDisenchant ~= false)
    bar.rolls = { Sven = ROLL_NEED, Anja = ROLL_GREED, Tom = ROLL_PASS, Lena = ROLL_GREED }
    if DB().showRollCounts ~= false then
        SetCount(bar, ROLL_NEED, 1); SetCount(bar, ROLL_GREED, 2)
        SetCount(bar, ROLL_PASS, 1); SetCount(bar, ROLL_DE, 0)
    else
        SetCount(bar, ROLL_NEED, 0); SetCount(bar, ROLL_GREED, 0)
        SetCount(bar, ROLL_PASS, 0); SetCount(bar, ROLL_DE, 0)
    end
    bar:Show()
    Restack()
    if ELR._simTicker then ELR._simTicker:Cancel() end
    ELR._simTicker = C_Timer.NewTicker(0.1, function()
        if not bar._sim then return end
        bar._simLeft = (bar._simLeft or 0) - 100
        if bar._simLeft <= 0 then ELR.StopSim() end
    end)
    print("|cff66ccffOUI-LR|r "..L("Sim started. /ouilr stop to end."))
end

function ELR.StopSim()
    if ELR._simTicker then ELR._simTicker:Cancel(); ELR._simTicker = nil end
    for _, b in ipairs(bars) do
        if b._sim then b._sim = false; b.rollID = nil; b._simLeft = nil; b:Hide() end
    end
    Restack()
end

-------------------------------------------------------------------------------
-- Init
-------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(self, event, a, b)
    if event == "PLAYER_LOGIN" then
        EnsureDB()
        EnsureAnchor()
        if DB().enabled then
            SuppressBlizzard()
            self:RegisterEvent("START_LOOT_ROLL")
            self:RegisterEvent("CANCEL_LOOT_ROLL")
            if C_LootHistory then
                self:RegisterEvent("LOOT_HISTORY_ROLL_CHANGED")
                self:RegisterEvent("LOOT_HISTORY_ROLL_COMPLETE")
            end
        end
        -- Auto-confirm BoP/BoA roll prompts is independent of the custom bars.
        self:RegisterEvent("CONFIRM_LOOT_ROLL")
        -- MoP Classic raises the BoP/BoA bind confirmation as the
        -- "CONFIRM_LOOT_ROLL" StaticPopup (via RollOnLoot) rather than firing the
        -- event, so auto-confirm here using the roll we just sent, then dismiss
        -- the popup. We deliberately do NOT click the popup's Button1: its
        -- OnAccept reads dialog data that isn't populated when RollOnLoot raises
        -- it, which called ConfirmLootRoll(nil,nil) ("Usage: ...") and tainted
        -- Blizzard's StaticPopup click path. ConfirmLootRoll is insecure-callable.
        if not _confirmHookInstalled and type(StaticPopup_Show) == "function" then
            _confirmHookInstalled = true
            hooksecurefunc("StaticPopup_Show", function(which)
                if which ~= "CONFIRM_LOOT_ROLL" then return end
                if not DB().autoConfirmBoP then return end
                if _pendingRoll and ConfirmLootRoll then
                    ConfirmLootRoll(_pendingRoll.id, _pendingRoll.rt)
                    _pendingRoll = nil
                    if StaticPopup_Hide then StaticPopup_Hide("CONFIRM_LOOT_ROLL") end
                end
            end)
        end
        RegisterMover()
        return
    end
    if event == "CONFIRM_LOOT_ROLL" then
        -- a = rollID, b = rollType. The game raises this when Need/Greed-ing a
        -- Bind-on-Pickup / Bind-on-Account item. Confirm it automatically when
        -- the option is on (otherwise leave Blizzard's popup for the user).
        if DB().autoConfirmBoP and ConfirmLootRoll then
            ConfirmLootRoll(a, b)
        end
        return
    end
    if event == "START_LOOT_ROLL" then
        HandleStartRoll(a, b)
    elseif event == "CANCEL_LOOT_ROLL" then
        HandleCancelRoll(a)
    elseif event == "LOOT_HISTORY_ROLL_CHANGED" or event == "LOOT_HISTORY_ROLL_COMPLETE" then
        UpdateCounts()
    end
end)

SLASH_OUILR1 = "/ouilr"
SlashCmdList["OUILR"] = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "test" or msg == "sim" then
        ELR.StartSim()
    elseif msg == "stop" or msg == "off" then
        ELR.StopSim()
        print("|cff66ccffOUI-LR|r "..L("Sim stopped."))
    else
        print("|cff66ccffOUI-LR|r "..L("Commands: /ouilr test | stop"))
    end
end

-- ===========================================================================
--  OldschoolUI -- Bags (Bags1: bootstrap, window shell, open/close, mover)
--  Clean-room rewrite for MoP Classic 5.5.x.
-- ===========================================================================
local ADDON, ns = ...
local OUI = OldschoolUI
local Bags = LibStub("AceAddon-3.0"):NewAddon("OldschoolUIBags", "AceEvent-3.0")
ns.Bags = Bags

local PP    = OUI.PP
local WHITE = "Interface\\Buttons\\WHITE8X8"

-- ---------------------------------------------------------------------------
--  Saved settings
-- ---------------------------------------------------------------------------
local defaults = {
    profile = {
        bagScale              = 1,
        bagColumns            = 12,
        bagCatTitleSize       = 11,
        bagCountFontSize      = 14,
        itemlevelFontSize     = 12,
        showItemlevelInBags   = true,
        showQualityBorder     = true,
        showCategorySidebar   = true,
        hideEmptyCategories   = true,
        showUpgradeIndicator  = true,
        bagShowTrackRank      = false,
        itemlevelUseCustomColor = false,
        bagHideEmptyCategories = true,
        bagSidebarCollapsed   = false,
        bankSidebarCollapsed  = false,
        bagShowPinnedItems    = true,
        bagShowRecentItems    = true,
        bagPinnedInOneBag     = true,
        bagRecentInOneBag     = false,
        bagShowPinRecentTips  = true,
        bagShowSortIcon       = true,
        bagHideRandomize      = false,
        bagDefaultOneBag      = false,
        bagHideOneBagWarning  = false,
        bagHideAddCategory    = false,
        bagMoveNoShift        = true,   -- header drag moves the window (no shift needed)
        enableGoldTracking    = true,
        detachReagentBag      = false,
        sortMode              = "quality",   -- quality | name | itemlevel | type | none
        sortDir               = "desc",       -- desc | asc
        -- autosell: named rulesets, each with conditions (AND/OR/XOR) + a sell strategy
        autoSell = {
            enabled   = false,
            sellGray  = true,
            rulesets  = {},   -- { {name, logic, strategy={mode,keep}, conditions={ {field,op,value}, ... }}, ... }
        },
        -- persisted structures
        bagDisabledCategories = {},
        bagCategoryGroups     = {},
        bagVisualOrder        = {},
        pinned                = {},   -- [itemID] = true
        assign                = {},   -- [itemID] = categoryKey (manual override)
        recentItems           = {},   -- [itemID] = expireTime (epoch)
        recentMinutes         = 30,
        catOrder              = nil,  -- array of movable category keys (built on first use)
        showPinned            = true,
        showRecent            = true,
        -- window position (TOPLEFT offset)
        x = nil, y = nil,
        -- bank window
        bankColumns = 14,
        bankX = nil, bankY = nil,
    },
    global = {
        goldLog = {},   -- [realm] = { [name] = { gold=, class=, faction= } }
    },
}

-- ---------------------------------------------------------------------------
--  Shared visual constants
-- ---------------------------------------------------------------------------
local SLOT, SPACING = 34, 4
local HEADER_H, FOOTER_H = 35, 32
local PAD = 10
local SIDEBAR_W, SIDEBAR_GAP, CAT_BTN_H = 150, 8, 22
Bags.SLOT, Bags.SPACING = SLOT, SPACING

local function Font() return (OUI.GetFontPath and OUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF" end
local function L(s) return (OUI.L and OUI.L(s)) or s end

-- Category model (MoP-safe: numeric Enum.ItemClass IDs, locale-independent;
-- Midnight/retail classes like Profession/Housing are intentionally absent).
-- "all" and "junk" are special; junk is matched by quality 0, the rest by classID.
local IC = Enum and Enum.ItemClass or {}
local CAT_DEFS = {
    { key = "all",         name = "All",           icon = "Interface\\Icons\\INV_Misc_Bag_08", noMove = true },
    { key = "pinned",      name = "Pinned",        icon = "Interface\\Icons\\INV_Misc_Note_02", noMove = true, special = "pinned" },
    { key = "recent",      name = "Recent",        icon = "Interface\\Icons\\INV_Misc_PocketWatch_01", noMove = true, special = "recent" },
    { key = "equipment",   name = "Equipment",     icon = "Interface\\Icons\\INV_Chest_Plate01", types = { IC.Weapon or 2, IC.Armor or 4 }, movable = true },
    { key = "consumables", name = "Consumables",   icon = "Interface\\Icons\\INV_Potion_51",     types = { IC.Consumable or 0 }, movable = true },
    { key = "tradegoods",  name = "Trade Goods",   icon = "Interface\\Icons\\INV_Fabric_Silk_01", types = { IC.Reagent or 5, IC.Projectile or 6, IC.Tradegoods or 7, IC.ItemEnhancement or 8 }, movable = true },
    { key = "gems",        name = "Gems",          icon = "Interface\\Icons\\INV_Misc_Gem_01",   types = { IC.Gem or 3 }, movable = true },
    { key = "glyphs",      name = "Glyphs",        icon = "Interface\\Icons\\INV_Inscription_Tradeskill01", types = { IC.Glyph or 16 }, movable = true },
    { key = "quest",       name = "Quest",         icon = "Interface\\Icons\\INV_Misc_Note_01",  types = { IC.Questitem or 12 }, movable = true },
    { key = "recipes",     name = "Recipes",       icon = "Interface\\Icons\\INV_Scroll_03",     types = { IC.Recipe or 9 }, movable = true },
    { key = "junk",        name = "Junk",          icon = "Interface\\Icons\\INV_Misc_Coin_01",  isJunk = true, movable = true },
    { key = "misc",        name = "Miscellaneous", icon = "Interface\\Icons\\INV_Misc_QuestionMark", isCatchAll = true, movable = true },
}
local CAT_BY_KEY = {}
for _, c in ipairs(CAT_DEFS) do CAT_BY_KEY[c.key] = c end
Bags.CAT_DEFS, Bags.CAT_BY_KEY = CAT_DEFS, CAT_BY_KEY   -- shared with the bank file
-- default movable order (used to seed db.catOrder)
local DEFAULT_CAT_ORDER = {}
for _, c in ipairs(CAT_DEFS) do if c.movable then DEFAULT_CAT_ORDER[#DEFAULT_CAT_ORDER + 1] = c.key end end
-- classID -> category key lookup
local CLASS_TO_CAT = {}
for _, c in ipairs(CAT_DEFS) do
    if c.types then for _, t in ipairs(c.types) do CLASS_TO_CAT[t] = c.key end end
end

local SORT_MODES  = { "none", "quality", "name", "itemlevel", "type" }
local SORT_LABELS = { none = "Bag order", quality = "Quality", name = "Name", itemlevel = "Item level", type = "Type" }

-- ---------------------------------------------------------------------------
--  Window shell
-- ---------------------------------------------------------------------------
function Bags:BuildWindow()
    if self.win then return self.win end
    local f = CreateFrame("Frame", "OUIBagsFrame", UIParent)
    self.win = f
    f:SetFrameStrata("HIGH")   -- above WeakAuras (MEDIUM); options panel is raised to DIALOG
    f:SetToplevel(true)        -- clicking anywhere in the window raises it above the bank window
    f:SetSize(self.db.profile.bagColumns * (SLOT + SPACING) + PAD * 2, 400)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:Hide()
    f:SetMovable(true)

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0.06, 0.06, 0.07, 0.97)
    if PP and PP.CreateBorder then PP.CreateBorder(f, 0, 0, 0, 0.9) end

    -- header (drag handle)
    local header = CreateFrame("Frame", nil, f)
    header:SetPoint("TOPLEFT", PAD, -PAD)
    header:SetPoint("TOPRIGHT", -PAD, -PAD)
    header:SetHeight(HEADER_H)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function()
        -- bagMoveNoShift = move without holding shift; otherwise shift is required
        if Bags.db.profile.bagMoveNoShift or IsShiftKeyDown() then f:StartMoving() end
    end)
    header:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        Bags:SavePosition()
        Bags:Reposition()
    end)
    f.header = header

    f.title = header:CreateFontString(nil, "OVERLAY")
    f.title:SetFont(Font(), 15, "OUTLINE")
    f.title:SetPoint("LEFT", header, "LEFT", 2, 0)
    f.title:SetText("Bags")
    f.title:SetTextColor(OUI.ACCENT.r, OUI.ACCENT.g, OUI.ACCENT.b)

    -- sort button (visible in the window, mirrors the options dropdown)
    local sort = CreateFrame("Button", nil, header)
    sort:SetSize(118, 20)
    sort:SetPoint("LEFT", f.title, "RIGHT", 12, 0)
    sort.icon = sort:CreateTexture(nil, "ARTWORK")
    sort.icon:SetSize(12, 12); sort.icon:SetPoint("LEFT", 0, 0)
    sort.icon:SetTexture("Interface\\Buttons\\UI-SortArrow")
    sort.txt = sort:CreateFontString(nil, "OVERLAY")
    sort.txt:SetFont(Font(), 11, ""); sort.txt:SetPoint("LEFT", sort.icon, "RIGHT", 3, 0)
    sort.txt:SetJustifyH("LEFT"); sort.txt:SetTextColor(0.85, 0.85, 0.85)
    sort:SetScript("OnEnter", function(s)
        s.txt:SetTextColor(1, 1, 1)
        GameTooltip:SetOwner(s, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L("Sort order"))
        GameTooltip:AddLine(L("Click to change"), 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    sort:SetScript("OnLeave", function(s) s.txt:SetTextColor(0.85, 0.85, 0.85); GameTooltip:Hide() end)
    sort:SetScript("OnClick", function() Bags:OpenSortMenu() end)
    f.sortBtn = sort

    -- reorganize (merge stacks + compact into first bags)
    local reorg = CreateFrame("Button", nil, header)
    reorg:SetSize(20, 20); reorg:SetPoint("LEFT", sort, "RIGHT", 6, 0)
    reorg.icon = reorg:CreateTexture(nil, "ARTWORK")
    reorg.icon:SetAllPoints(); reorg.icon:SetTexture("Interface\\Buttons\\UI-RefreshButton")
    reorg.icon:SetVertexColor(0.85, 0.85, 0.85)
    reorg:SetScript("OnEnter", function(s)
        s.icon:SetVertexColor(1, 1, 1)
        GameTooltip:SetOwner(s, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L("Reorganize"))
        GameTooltip:AddLine(L("Merge stacks and fill the first bags."), 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    reorg:SetScript("OnLeave", function(s) s.icon:SetVertexColor(0.85, 0.85, 0.85); GameTooltip:Hide() end)
    reorg:SetScript("OnClick", function() Bags:Reorganize() end)
    f.reorgBtn = reorg

    -- close button
    local close = CreateFrame("Button", nil, header)
    close:SetSize(20, 20); close:SetPoint("RIGHT", header, "RIGHT", 0, 0)
    close._t = close:CreateFontString(nil, "OVERLAY")
    close._t:SetFont(Font(), 16, "OUTLINE"); close._t:SetPoint("CENTER"); close._t:SetText("x")
    close._t:SetTextColor(0.8, 0.8, 0.8)
    close:SetScript("OnEnter", function() close._t:SetTextColor(1, 0.3, 0.3) end)
    close:SetScript("OnLeave", function() close._t:SetTextColor(0.8, 0.8, 0.8) end)
    close:SetScript("OnClick", function() Bags:Close() end)

    -- search box
    local search = CreateFrame("EditBox", nil, header)
    search:SetSize(150, 20); search:SetPoint("RIGHT", close, "LEFT", -8, 0)
    search:SetAutoFocus(false); search:SetFont(Font(), 12, "")
    search:SetTextInsets(6, 18, 0, 0)
    local sbg = search:CreateTexture(nil, "BACKGROUND")
    sbg:SetAllPoints(); sbg:SetColorTexture(0.12, 0.12, 0.13, 0.9)
    if PP and PP.CreateBorder then PP.CreateBorder(search, 0, 0, 0, 0.9) end

    -- clear (x) button, shown only when there is text
    local clear = CreateFrame("Button", nil, search)
    clear:SetSize(16, 16); clear:SetPoint("RIGHT", search, "RIGHT", -3, 0)
    clear._t = clear:CreateFontString(nil, "OVERLAY")
    clear._t:SetFont(Font(), 13, "OUTLINE"); clear._t:SetPoint("CENTER"); clear._t:SetText("x")
    clear._t:SetTextColor(0.7, 0.7, 0.7)
    clear:SetScript("OnEnter", function() clear._t:SetTextColor(1, 0.4, 0.4) end)
    clear:SetScript("OnLeave", function() clear._t:SetTextColor(0.7, 0.7, 0.7) end)
    clear:SetScript("OnClick", function() search:SetText(""); search:ClearFocus() end)
    clear:Hide()
    search.clear = clear

    search:SetScript("OnEscapePressed", function(s) s:ClearFocus(); s:SetText("") end)
    search:SetScript("OnTextChanged", function(s)
        local t = (s:GetText() or "")
        Bags.searchText = t:lower()
        clear:SetShown(t ~= "")
        if Bags.RefreshInventory then Bags:RefreshInventory() end
    end)
    f.search = search

    -- body (item grid goes here in Bags2)
    local body = CreateFrame("Frame", nil, f)
    body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
    body:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -6)
    body:SetPoint("BOTTOM", f, "BOTTOM", 0, FOOTER_H + PAD)
    f.body = body

    f._placeholder = body:CreateFontString(nil, "OVERLAY")
    f._placeholder:SetFont(Font(), 12, "")
    f._placeholder:SetPoint("CENTER")
    f._placeholder:SetText("|cff888888(empty)|r")

    -- category sidebar (Bags3) -- lives at the left of the body area
    local sidebar = CreateFrame("Frame", nil, body)
    sidebar:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
    sidebar:SetWidth(SIDEBAR_W)
    sidebar:SetHeight(1)
    f.sidebar = sidebar
    self:BuildSidebar()

    -- footer (player gold)
    f.gold = f:CreateFontString(nil, "OVERLAY")
    f.gold:SetFont(Font(), 13, "OUTLINE")
    f.gold:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, PAD)
    f.gold:SetJustifyH("RIGHT")

    -- hover region over the gold text for the per-character breakdown tooltip
    local goldHover = CreateFrame("Button", nil, f)
    goldHover:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, PAD)
    goldHover:SetSize(160, 18)
    goldHover:SetScript("OnEnter", function(s) Bags:ShowGoldTooltip(s) end)
    goldHover:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.goldHover = goldHover

    -- manage (edit) mode toggle -- footer left
    local manage = CreateFrame("Button", nil, f)
    manage:SetSize(96, 18)
    manage:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, PAD)
    manage.hl = manage:CreateTexture(nil, "BACKGROUND")
    manage.hl:SetAllPoints(); manage.hl:SetColorTexture(OUI.ACCENT.r, OUI.ACCENT.g, OUI.ACCENT.b, 0.22); manage.hl:Hide()
    manage.icon = manage:CreateTexture(nil, "ARTWORK")
    manage.icon:SetSize(12, 12); manage.icon:SetPoint("LEFT", 2, 0)
    manage.icon:SetTexture("Interface\\GossipFrame\\BinderGossipIcon")
    manage.txt = manage:CreateFontString(nil, "OVERLAY")
    manage.txt:SetFont(Font(), 11, ""); manage.txt:SetPoint("LEFT", manage.icon, "RIGHT", 4, 0)
    manage.txt:SetText(L("Manage")); manage.txt:SetTextColor(0.8, 0.8, 0.8)
    manage:SetScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_TOP")
        GameTooltip:SetText(L("Manage items"))
        GameTooltip:AddLine(L("Click a slot to pin or assign a category."), 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    manage:SetScript("OnLeave", function() GameTooltip:Hide() end)
    manage:SetScript("OnClick", function() Bags:ToggleEditMode() end)
    f.manageBtn = manage

    self:ApplyScale()
    self:Reposition()
    return f
end

function Bags:ApplyScale()
    if self.win then self.win:SetScale(self.db.profile.bagScale or 1) end
end

function Bags:SavePosition()
    local f = self.win; if not f then return end
    -- store TOPLEFT offset from UIParent TOPLEFT, scale-normalised so the
    -- corner stays fixed regardless of window scale
    local rel = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
    self.db.profile.x = f:GetLeft() * rel - UIParent:GetLeft()
    self.db.profile.y = f:GetTop()  * rel - UIParent:GetTop()
end

function Bags:Reposition()
    if not self.win then return end
    self.win:ClearAllPoints()
    local p = self.db.profile
    if p.x and p.y then
        -- anchor by TOPLEFT so grid resizes grow down-right, never jumping
        -- off-screen near an edge (CENTER anchoring grew symmetrically)
        self.win:SetPoint("TOPLEFT", UIParent, "TOPLEFT", p.x, p.y)
    else
        self.win:SetPoint("CENTER", UIParent, "CENTER", 0, 0)  -- initial placement
    end
end

function Bags:UpdateGold()
    self:UpdateGoldLog()
    if not (self.win and self.win.gold) then return end
    self.win.gold:SetText(GetCoinTextureString and GetCoinTextureString(GetMoney() or 0) or tostring(GetMoney() or 0))
end

local function RealmKey()  return (GetRealmName and GetRealmName()) or "Realm" end
local function CharKey()   return (UnitName and UnitName("player")) or "Player" end

function Bags:UpdateGoldLog()
    local g = self.db.global.goldLog
    local realm = RealmKey()
    g[realm] = g[realm] or {}
    local _, class = UnitClass and UnitClass("player")
    g[realm][CharKey()] = {
        gold    = GetMoney and GetMoney() or 0,
        class   = class,
        faction = UnitFactionGroup and UnitFactionGroup("player") or nil,
    }
    if not self._sessionStartGold then self._sessionStartGold = GetMoney and GetMoney() or 0 end
end

-- builds the gold breakdown tooltip (this char highlighted, others listed, total + session delta)
function Bags:ShowGoldTooltip(anchor)
    GameTooltip:SetOwner(anchor, "ANCHOR_TOPRIGHT")
    GameTooltip:AddLine(L("Gold"))
    local realm = RealmKey()
    local chars = self.db.global.goldLog[realm] or {}
    -- sort by gold desc
    local list = {}
    for name, data in pairs(chars) do list[#list + 1] = { name = name, data = data } end
    table.sort(list, function(a, b) return (a.data.gold or 0) > (b.data.gold or 0) end)
    local total, me = 0, CharKey()
    for _, e in ipairs(list) do
        total = total + (e.data.gold or 0)
        local cc = e.data.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[e.data.class]
        local r, g, b = (cc and cc.r) or 0.9, (cc and cc.g) or 0.9, (cc and cc.b) or 0.9
        local label = e.name .. (e.name == me and "  *" or "")
        GameTooltip:AddDoubleLine(label, GetCoinTextureString(e.data.gold or 0), r, g, b, 1, 1, 1)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine(L("Realm total"), GetCoinTextureString(total), 1, 0.82, 0, 1, 1, 1)
    local delta = (GetMoney and GetMoney() or 0) - (self._sessionStartGold or (GetMoney and GetMoney() or 0))
    local sign = delta >= 0 and "+" or "-"
    local dcol = delta >= 0 and "|cff40ff40" or "|cffff4040"
    GameTooltip:AddDoubleLine(L("This session"), dcol .. sign .. GetCoinTextureString(math.abs(delta)) .. "|r", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

-- OneBag: highlight ALL bag-bar buttons while the window is open, clear on close
local BAG_BUTTONS = {
    "MainMenuBarBackpackButton",
    "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot", "CharacterBag3Slot",
    "CharacterReagentBag0Slot",
}
function Bags:UpdateBagBar(active)
    for _, name in ipairs(BAG_BUTTONS) do
        local b = _G[name]
        if b and b.SetChecked then b:SetChecked(active and true or false) end
    end
end

-- ---------------------------------------------------------------------------
--  Open / close
-- ---------------------------------------------------------------------------
function Bags:IsShown() return self.win and self.win:IsShown() end

function Bags:Open()
    self:BuildWindow()
    if self.win.search then self.win.search:SetText("") end  -- fresh search each open
    self.searchText = ""
    self.activeCategory = "all"                                -- start unfiltered
    self.editMode = false                                      -- start in normal use
    self.win:Show()
    self:UpdateGold()
    self:UpdateBagBar(true)
    if self.RefreshInventory then self:RefreshInventory() end
end

function Bags:Close()
    if self.win then self.win:Hide() end
    self:UpdateBagBar(false)
end

function Bags:Toggle()
    if self:IsShown() then self:Close() else self:Open() end
end

-- hide Blizzard container frames inside a hidden parent
function Bags:SuppressBlizzard()
    if self._blizzHidden then return end
    self._blizzHidden = CreateFrame("Frame")
    self._blizzHidden:Hide()
    for i = 1, 13 do
        local cf = _G["ContainerFrame" .. i]
        if cf then cf:SetParent(self._blizzHidden) end
    end
    if ContainerFrameCombinedBags then ContainerFrameCombinedBags:SetParent(self._blizzHidden) end
end

function Bags:HookBlizzard()
    if self._hooked then return end
    self._hooked = true
    -- Blizzard can fire ToggleAllBags + ToggleBackpack (and C_Container.ToggleAllBags)
    -- for a single click/keybind in the same frame -> debounce so one click = one toggle.
    local last = 0
    local function smart()
        local now = GetTime()
        if now - last < 0.1 then return end
        last = now
        Bags:Toggle()
    end
    Bags._smart = smart
    -- NEVER replace the global ToggleAllBags: it is referenced by Blizzard's
    -- secure code and overwriting it taints that path. Post-hook instead;
    -- Blizzard's own container frames stay invisible (SuppressBlizzard reparents them).
    if _G.ToggleAllBags then hooksecurefunc("ToggleAllBags", smart) end
    if C_Container and C_Container.ToggleAllBags then
        hooksecurefunc(C_Container, "ToggleAllBags", smart)
    end
    if _G.ToggleBackpack then hooksecurefunc("ToggleBackpack", smart) end
    if _G.ToggleBag then hooksecurefunc("ToggleBag", function() smart() end) end
    -- contextual openers (loot / vendor / mail) -> open only, never toggle
    if _G.OpenAllBags then hooksecurefunc("OpenAllBags", function() Bags:Open() end) end
    if _G.CloseAllBags then hooksecurefunc("CloseAllBags", function() Bags:Close() end) end
end

-- ---------------------------------------------------------------------------
--  Mover
-- ---------------------------------------------------------------------------
-- ===========================================================================
--  Bags2: slot factory + item scan + flat grid + render
-- ===========================================================================
local BAG_IDS = { 0, 1, 2, 3, 4 }   -- backpack + 4 bags (reagent handled later)

-- MoP Classic exposes some container fns under C_Container and some as globals;
-- use whichever is present so selling/moving works on every build.
local function ContainerUse(bag, slot)
    if C_Container and C_Container.UseContainerItem then C_Container.UseContainerItem(bag, slot)
    elseif UseContainerItem then UseContainerItem(bag, slot) end
end
local function ContainerPickup(bag, slot)
    if C_Container and C_Container.PickupContainerItem then C_Container.PickupContainerItem(bag, slot)
    elseif PickupContainerItem then PickupContainerItem(bag, slot) end
end

-- secure item buttons must never be created during combat (taint), so the
-- caller skips and PLAYER_REGEN_ENABLED replays a full refresh.
function Bags:GetSlot(idx)
    self.slots = self.slots or {}
    if self.slots[idx] then return self.slots[idx] end
    if InCombatLockdown() then return nil end
    local btn = self:_buildSlot(self.win.body)
    self.slots[idx] = btn
    return btn
end

function Bags:GetBankSlot(idx)
    self.bankSlots = self.bankSlots or {}
    if self.bankSlots[idx] then return self.bankSlots[idx] end
    if InCombatLockdown() then return nil end
    local btn = self:_buildSlot(self.bankWin.body, true)
    self.bankSlots[idx] = btn
    return btn
end

-- builds a fully decorated secure slot button parented under `body`
function Bags:_buildSlot(body, isBank)
    local holder = CreateFrame("Frame", nil, body)
    holder:SetSize(SLOT, SLOT)
    local btn = CreateFrame("ItemButton", nil, holder, "ContainerFrameItemButtonTemplate")
    btn:SetAllPoints(holder)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")
    btn._holder = holder
    -- The template's OnUpdate re-runs ContainerFrameItemButton_OnEnter every frame,
    -- which re-resolves the tooltip via SetBagItem and can blank it (flash, then a
    -- black frame) — for the bank's main container (-1) always, and intermittently
    -- elsewhere. We drive the tooltip ourselves from OnEnter using the static item
    -- link, so the template OnUpdate is removed on every slot.
    btn:SetScript("OnUpdate", nil)

    -- strip template decorations via methods only (writing properties taints)
    if btn.NewItemTexture then btn.NewItemTexture:SetAlpha(0); btn.NewItemTexture:Hide() end
    if btn.BattlepayItemTexture then btn.BattlepayItemTexture:SetAlpha(0); btn.BattlepayItemTexture:Hide() end
    if btn.flash then btn.flash:Hide() end
    if btn.newitemglowAnim then btn.newitemglowAnim:Stop() end
    if btn.NormalTexture then btn.NormalTexture:SetAlpha(0) end
    if btn.IconBorder then btn.IconBorder:SetAlpha(0) end
    if btn.icon then
        btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        btn.icon:ClearAllPoints(); btn.icon:SetAllPoints(btn)
        if btn.IconMask then btn.icon:RemoveMaskTexture(btn.IconMask); btn.IconMask:Hide(); btn.IconMask:SetTexture(nil) end
    end
    -- quality border on OVERLAY (the icon sits on ARTWORK and would cover a
    -- BORDER-layer pixel border, so draw our edges above it)
    local function edge(p) local t = btn:CreateTexture(nil, "OVERLAY", nil, 6); t:SetColorTexture(0.22, 0.22, 0.22, 1); return t end
    btn._qt = edge(); btn._qt:SetPoint("TOPLEFT"); btn._qt:SetPoint("TOPRIGHT"); btn._qt:SetHeight(1.5)
    btn._qb = edge(); btn._qb:SetPoint("BOTTOMLEFT"); btn._qb:SetPoint("BOTTOMRIGHT"); btn._qb:SetHeight(1.5)
    btn._ql = edge(); btn._ql:SetPoint("TOPLEFT"); btn._ql:SetPoint("BOTTOMLEFT"); btn._ql:SetWidth(1.5)
    btn._qr = edge(); btn._qr:SetPoint("TOPRIGHT"); btn._qr:SetPoint("BOTTOMRIGHT"); btn._qr:SetWidth(1.5)
    btn._qedges = { btn._qt, btn._qb, btn._ql, btn._qr }
    if btn.Count then
        btn.Count:SetFont(Font(), self.db.profile.bagCountFontSize or 11, "OUTLINE")
    end
    btn.ilvl = btn:CreateFontString(nil, "OVERLAY")
    btn.ilvl:SetFont(Font(), self.db.profile.itemlevelFontSize or 12, "OUTLINE")
    btn.ilvl:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    btn.ilvl:SetTextColor(1, 1, 1)

    -- own cooldown frame (template's $parentCooldown isn't reachable on a nil-named button)
    btn.cd = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
    btn.cd:SetAllPoints(btn)
    btn.cd:SetDrawEdge(false)
    if btn.cd.SetHideCountdownNumbers then btn.cd:SetHideCountdownNumbers(false) end
    -- keep the stack count readable above the swipe
    if btn.Count then btn.Count:SetParent(btn); btn.Count:SetDrawLayer("OVERLAY", 7) end

    -- pin marker (small star, top-right; shown when the item is pinned)
    btn._pin = btn:CreateTexture(nil, "OVERLAY", nil, 7)
    btn._pin:SetSize(11, 11); btn._pin:SetPoint("TOPRIGHT", -1, -1)
    btn._pin:SetTexture("Interface\\Common\\ReputationStar")
    btn._pin:SetTexCoord(0, 0.5, 0, 0.5); btn._pin:SetVertexColor(1, 0.82, 0.2)
    btn._pin:Hide()

    -- edit overlay: in manage mode it covers the slot (non-secure) so a click
    -- opens the assignment menu instead of using the item (taint-free)
    local ov = CreateFrame("Button", nil, btn._holder)
    ov:SetAllPoints(btn._holder)
    ov:SetFrameStrata("DIALOG")           -- above the HIGH window + secure button
    ov:SetFrameLevel(btn:GetFrameLevel() + 10)
    ov:EnableMouse(true); ov:RegisterForClicks("AnyUp")
    ov._tex = ov:CreateTexture(nil, "OVERLAY", nil, 5)
    ov._tex:SetAllPoints(); ov._tex:SetColorTexture(0.1, 0.1, 0.12, 0.35)
    ov._cog = ov:CreateTexture(nil, "OVERLAY", nil, 6)
    ov._cog:SetSize(14, 14); ov._cog:SetPoint("CENTER")
    ov._cog:SetTexture("Interface\\GossipFrame\\BinderGossipIcon")
    ov:SetScript("OnClick", function() Bags:OpenItemMenu(btn) end)
    ov:Hide()
    btn._edit = ov

    -- explicit tooltip: the nil-named template button doesn't reliably show one,
    -- so drive it ourselves from the live holder(bag)/button(slot) IDs
    btn:SetScript("OnEnter", function(b)
        local bag, slot = b._holder:GetID(), b:GetID()
        local info = C_Container.GetContainerItemInfo and C_Container.GetContainerItemInfo(bag, slot)
        if not info then GameTooltip:Hide(); return end
        local link = info.hyperlink
            or (C_Container.GetContainerItemLink and C_Container.GetContainerItemLink(bag, slot))
        -- Bank containers (-1 main bank, -3 reagent, 5-11 bank bags) can't be shown
        -- with SetBagItem(-1) and, worse, GameTooltip's own auto-refresh re-resolves
        -- SetInventoryItem/SetBagItem to empty a frame later (tooltip flashes then
        -- goes black). The item link is static and always resolves, so use it for
        -- the bank. Regular bags (0-4) keep SetBagItem (count + equip comparison).
        -- The static item link always resolves and, unlike SetBagItem/
        -- SetInventoryItem, is not re-resolved into an empty tooltip by
        -- GameTooltip's auto-refresh (which caused the flash-then-black). Use it
        -- for every slot; fall back to the container/inventory setters only when
        -- no link is available.
        GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
        local ok
        if link then
            ok = pcall(GameTooltip.SetHyperlink, GameTooltip, link)
        elseif bag == -1 and BankButtonIDToInvSlotID then
            ok = pcall(GameTooltip.SetInventoryItem, GameTooltip, "player", BankButtonIDToInvSlotID(slot))
        else
            ok = pcall(GameTooltip.SetBagItem, GameTooltip, bag, slot)
        end
        if (not ok) or GameTooltip:NumLines() == 0 then
            if bag == -1 and BankButtonIDToInvSlotID then
                GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
                pcall(GameTooltip.SetInventoryItem, GameTooltip, "player", BankButtonIDToInvSlotID(slot))
            else
                GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
                pcall(GameTooltip.SetBagItem, GameTooltip, bag, slot)
            end
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return btn
end

local function QualityColor(q)
    if q and q > 1 and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q] then
        local c = ITEM_QUALITY_COLORS[q]; return c.r, c.g, c.b
    end
    return 0.22, 0.22, 0.22
end

function Bags:SetQualityBorder(btn, r, g, b)
    if not btn._qedges then return end
    for _, e in ipairs(btn._qedges) do e:SetColorTexture(r, g, b, 1) end
end

local function GearItemLevel(link)
    if not link then return nil end
    local _, _, _, _, _, classID = GetItemInfoInstant(link)   -- classID is the 6th return
    if classID ~= (Enum.ItemClass and Enum.ItemClass.Weapon or 2)
        and classID ~= (Enum.ItemClass and Enum.ItemClass.Armor or 4) then return nil end
    return GetDetailedItemLevelInfo and GetDetailedItemLevelInfo(link) or nil
end

function Bags:RenderSlot(btn, bag, slot, info)
    btn:Show()
    btn._holder:SetID(bag)   -- secure template reads parent:GetID() as bag
    btn:SetID(slot)          -- and self:GetID() as slot
    local icon = info and info.iconFileID
    if SetItemButtonTexture then SetItemButtonTexture(btn, icon) end
    if btn.icon then btn.icon:SetShown(icon ~= nil) end
    if SetItemButtonCount then SetItemButtonCount(btn, (info and info.stackCount) or 0) end
    if SetItemButtonDesaturated then SetItemButtonDesaturated(btn, info and info.isLocked) end

    if self.db.profile.showQualityBorder then
        self:SetQualityBorder(btn, QualityColor(info and info.quality))
    else
        self:SetQualityBorder(btn, 0.22, 0.22, 0.22)
    end

    if btn.cd then
        local s, d, e = C_Container.GetContainerItemCooldown(bag, slot)
        if CooldownFrame_Set then
            CooldownFrame_Set(btn.cd, s, d, e)
        elseif s and d and d > 0 and (e == nil or e ~= 0) then
            btn.cd:SetCooldown(s, d)
        else
            btn.cd:Clear()
        end
    end

    if btn.ilvl then
        local lvl = self.db.profile.showItemlevelInBags and info and GearItemLevel(info.hyperlink)
        btn.ilvl:SetText(lvl and tostring(lvl) or "")
    end

    btn._itemID = info and info.itemID
    if btn._pin then btn._pin:SetShown(self:IsPinned(btn._itemID)) end
    if btn._edit then btn._edit:SetShown(self.editMode and info ~= nil) end
end

function Bags:ScanItems()
    local items = {}
    for _, bag in ipairs(BAG_IDS) do
        local n = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, n do
            items[#items + 1] = { bag = bag, slot = slot, info = C_Container.GetContainerItemInfo(bag, slot) }
        end
    end
    return items
end

function Bags:MatchesSearch(info)
    local q = self.searchText
    if not q or q == "" then return true end
    if not (info and info.hyperlink) then return false end
    local name = (GetItemInfo(info.hyperlink))
    return name and name:lower():find(q, 1, true) ~= nil or false
end

-- ===========================================================================
--  Bags3: category sidebar + filter + hide-empty
-- ===========================================================================
function Bags:SidebarOn()
    return self.db.profile.showCategorySidebar ~= false
end

function Bags:GridLeft()
    return self:SidebarOn() and (SIDEBAR_W + SIDEBAR_GAP) or 0
end

function Bags:ClassifyItem(info)
    if not info then return nil end
    local id = info.itemID
    local ov = id and self.db.profile.assign[id]
    if ov and CAT_BY_KEY[ov] and CAT_BY_KEY[ov].movable then return ov end   -- manual override
    if (info.quality or 1) == 0 then return "junk" end                       -- gray = junk
    local link = info.hyperlink
    local classID = link and select(6, GetItemInfoInstant(link)) or nil
    return (classID and CLASS_TO_CAT[classID]) or "misc"
end

function Bags:IsPinned(id)  return id and self.db.profile.pinned[id] and true or false end

function Bags:IsRecent(id)
    if not id then return false end
    local exp = self.db.profile.recentItems[id]
    return exp ~= nil and time() < exp
end

-- mark newly-acquired itemIDs as "recent". The first scan after login seeds a
-- baseline (nothing flagged); items appearing afterwards get a timed window.
function Bags:TrackRecent(items)
    local p = self.db.profile
    local now = time()
    local window = (p.recentMinutes or 30) * 60
    -- prune expired
    for id, exp in pairs(p.recentItems) do
        if now >= exp then p.recentItems[id] = nil end
    end
    local present = {}
    for _, it in ipairs(items) do
        if it.info and it.info.itemID then present[it.info.itemID] = true end
    end
    if not self._known then
        -- baseline: everything currently held is "not new"
        self._known = {}
        for id in pairs(present) do self._known[id] = true end
        return
    end
    for id in pairs(present) do
        if not self._known[id] then
            p.recentItems[id] = now + window     -- freshly acquired
            self._known[id] = true
        end
    end
end

-- ordered list of category keys for the sidebar: all, pinned, recent (when
-- enabled), then the movable categories in db.catOrder (seeded from default,
-- repaired so every movable key appears exactly once)
function Bags:CategoryOrder()
    local p = self.db.profile
    local order = p.catOrder
    if type(order) ~= "table" or #order == 0 then
        order = {}; for _, k in ipairs(DEFAULT_CAT_ORDER) do order[#order + 1] = k end
        p.catOrder = order
    end
    -- repair: drop unknowns/dupes, append any missing movable keys
    local seen, clean = {}, {}
    for _, k in ipairs(order) do
        if CAT_BY_KEY[k] and CAT_BY_KEY[k].movable and not seen[k] then
            seen[k] = true; clean[#clean + 1] = k
        end
    end
    for _, k in ipairs(DEFAULT_CAT_ORDER) do if not seen[k] then clean[#clean + 1] = k end end
    p.catOrder = clean

    local list = { "all" }
    if p.showPinned ~= false then list[#list + 1] = "pinned" end
    if p.showRecent ~= false then list[#list + 1] = "recent" end
    for _, k in ipairs(clean) do list[#list + 1] = k end
    return list
end

function Bags:BuildSidebar()
    local sb = self.win and self.win.sidebar
    if not sb or self._sidebarBuilt then return end
    self._sidebarBuilt = true
    self._catButtons = {}
    for _, def in ipairs(CAT_DEFS) do
        local b = CreateFrame("Button", nil, sb)
        b:SetSize(SIDEBAR_W, CAT_BTN_H)
        b._key = def.key
        b._movable = def.movable and true or false

        b.hl = b:CreateTexture(nil, "BACKGROUND")
        b.hl:SetAllPoints(); b.hl:SetColorTexture(OUI.ACCENT.r, OUI.ACCENT.g, OUI.ACCENT.b, 0.22)
        b.hl:Hide()
        b.hover = b:CreateTexture(nil, "BACKGROUND")
        b.hover:SetAllPoints(); b.hover:SetColorTexture(1, 1, 1, 0.06); b.hover:Hide()

        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetSize(16, 16); b.icon:SetPoint("LEFT", 3, 0)
        b.icon:SetTexture(def.icon); b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        b.cnt = b:CreateFontString(nil, "OVERLAY")
        b.cnt:SetFont(Font(), 11, ""); b.cnt:SetPoint("RIGHT", -4, 0)
        b.cnt:SetJustifyH("RIGHT"); b.cnt:SetTextColor(0.6, 0.6, 0.6)

        b.txt = b:CreateFontString(nil, "OVERLAY")
        b.txt:SetFont(Font(), 11, ""); b.txt:SetPoint("LEFT", b.icon, "RIGHT", 5, 0)
        b.txt:SetPoint("RIGHT", b.cnt, "LEFT", -4, 0)   -- stop before the count, never overlap
        b.txt:SetJustifyH("LEFT"); b.txt:SetWordWrap(false); b.txt:SetText(L(def.name))

        b:SetScript("OnEnter", function(self2) if not self2.hl:IsShown() then self2.hover:Show() end end)
        b:SetScript("OnLeave", function(self2) self2.hover:Hide() end)
        b:SetScript("OnClick", function(self2)
            if Bags._dragging then return end
            Bags.activeCategory = self2._key
            Bags:RefreshInventory()
        end)

        -- drag-reorder (movable categories only)
        if def.movable then
            b:RegisterForDrag("LeftButton")
            b:SetScript("OnDragStart", function(self2) Bags:StartCatDrag(self2) end)
            b:SetScript("OnDragStop",  function() Bags:StopCatDrag() end)
        end
        self._catButtons[def.key] = b
    end
end

-- drag a movable category button; on drop, reorder db.catOrder by cursor Y
function Bags:StartCatDrag(btn)
    self._dragging = btn
    btn:SetFrameLevel((self.win.sidebar:GetFrameLevel() or 1) + 10)
    btn.hover:Hide()
    btn:SetAlpha(0.85)
    btn:SetScript("OnUpdate", function(self2)
        local _, y = GetCursorPosition()
        local scale = self2:GetEffectiveScale()
        self2:ClearAllPoints()
        self2:SetPoint("TOP", UIParent, "BOTTOM", 0, y / scale)
        -- keep horizontal under the sidebar
        local sbLeft = Bags.win.sidebar:GetLeft() or 0
        self2:SetPoint("LEFT", UIParent, "LEFT", sbLeft, 0)
    end)
end

function Bags:StopCatDrag()
    local btn = self._dragging
    if not btn then return end
    btn:SetScript("OnUpdate", nil)
    btn:SetAlpha(1)
    -- determine drop index among the visible movable buttons by cursor Y
    local _, cy = GetCursorPosition()
    cy = cy / (self.win:GetEffectiveScale() or 1)
    local order = self.db.profile.catOrder or {}
    local target = nil
    for _, k in ipairs(order) do
        local ob = self._catButtons[k]
        if ob and ob ~= btn and ob:IsShown() then
            local top = ob:GetTop()
            if top and cy <= top and cy >= (top - CAT_BTN_H) then target = k; break end
            if top and cy > top then target = k; break end   -- above this button
        end
    end
    -- rebuild order with btn moved before target (or to end)
    local newOrder = {}
    local moved = btn._key
    local inserted = false
    for _, k in ipairs(order) do
        if k == moved then
            -- skip; we reinsert it
        else
            if k == target and not inserted then newOrder[#newOrder + 1] = moved; inserted = true end
            newOrder[#newOrder + 1] = k
        end
    end
    if not inserted then newOrder[#newOrder + 1] = moved end
    self.db.profile.catOrder = newOrder
    self._dragging = nil
    self:RefreshInventory()   -- re-lays out the sidebar
end

-- counts: key -> n. Lays out categories in CategoryOrder(); hides empty
-- (except All) when hide-empty is on. Highlights the active category.
function Bags:RefreshSidebar(counts)
    if not (self.win and self._catButtons) then return 0 end
    local on = self:SidebarOn()
    self.win.sidebar:SetShown(on)
    if not on then return 0 end
    counts = counts or {}
    local hideEmpty = self.db.profile.hideEmptyCategories ~= false
    local active = self.activeCategory or "all"
    local y, vis = 0, 0
    -- hide all first, then show the ordered set
    for _, b in pairs(self._catButtons) do b:Hide() end
    for _, key in ipairs(self:CategoryOrder()) do
        local b = self._catButtons[key]
        local n = counts[key] or 0
        local show = (key == "all") or (not hideEmpty) or (n > 0)
        if b and show then
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", self.win.sidebar, "TOPLEFT", 0, -y)
            b:SetFrameLevel((self.win.sidebar:GetFrameLevel() or 1) + 1)
            b:Show()
            b.cnt:SetText(key == "all" and "" or tostring(n))
            local on2 = (key == active)
            b.hl:SetShown(on2)
            b.txt:SetTextColor(on2 and 1 or 0.82, on2 and 1 or 0.82, on2 and 1 or 0.82)
            y = y + CAT_BTN_H; vis = vis + 1
        end
    end
    self.win.sidebar:SetHeight(math.max(y, 1))
    return vis
end

-- ---------------------------------------------------------------------------
--  Lightweight context menu (own implementation; reliable & taint-free)
-- ---------------------------------------------------------------------------
function Bags:EnsureMenu()
    if self._ctx then return self._ctx end
    local m = CreateFrame("Frame", "OUIBagsContextMenu", UIParent)
    m:SetFrameStrata("TOOLTIP"); m:SetClampedToScreen(true); m:Hide()
    m.bg = m:CreateTexture(nil, "BACKGROUND"); m.bg:SetAllPoints()
    m.bg:SetColorTexture(0.07, 0.07, 0.08, 0.98)
    if PP and PP.CreateBorder then PP.CreateBorder(m, 0, 0, 0, 1) end
    m.rows = {}
    local closer = CreateFrame("Button", nil, UIParent)
    closer:SetFrameStrata("FULLSCREEN_DIALOG"); closer:SetAllPoints(UIParent)
    closer:EnableMouse(true); closer:RegisterForClicks("AnyUp"); closer:Hide()
    closer:SetScript("OnClick", function() m:Hide() end)
    m:SetScript("OnHide", function() closer:Hide() end)
    m.closer = closer
    self._ctx = m
    return m
end

function Bags:ShowMenu(entries, anchor)
    local m = self:EnsureMenu()
    for _, r in ipairs(m.rows) do r:Hide() end
    local ROWH, WIDTH, y = 19, 172, 6
    for i, e in ipairs(entries) do
        local r = m.rows[i]
        if not r then
            r = CreateFrame("Button", nil, m); r:SetHeight(ROWH)
            r.hl = r:CreateTexture(nil, "BACKGROUND"); r.hl:SetAllPoints()
            r.hl:SetColorTexture(OUI.ACCENT.r, OUI.ACCENT.g, OUI.ACCENT.b, 0.25); r.hl:Hide()
            r.check = r:CreateTexture(nil, "ARTWORK"); r.check:SetSize(12, 12); r.check:SetPoint("LEFT", 4, 0)
            r.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
            r.txt = r:CreateFontString(nil, "OVERLAY"); r.txt:SetFont(Font(), 11, "")
            r.txt:SetPoint("LEFT", 18, 0); r.txt:SetPoint("RIGHT", -6, 0)
            r.txt:SetJustifyH("LEFT"); r.txt:SetWordWrap(false)
            r:SetScript("OnEnter", function(s) if s._sel then s.hl:Show() end end)
            r:SetScript("OnLeave", function(s) s.hl:Hide() end)
            m.rows[i] = r
        end
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", m, "TOPLEFT", 4, -y)
        r:SetPoint("TOPRIGHT", m, "TOPRIGHT", -4, -y)
        if e.isTitle then
            r._sel = false; r:EnableMouse(false); r.check:Hide()
            r.txt:SetTextColor(OUI.ACCENT.r, OUI.ACCENT.g, OUI.ACCENT.b)
            r.txt:SetText(e.text); r:SetScript("OnClick", nil)
        else
            r._sel = true; r:EnableMouse(true)
            r.check:SetShown(e.checked and true or false)
            r.txt:SetTextColor(0.9, 0.9, 0.9); r.txt:SetText(e.text)
            local fn = e.func
            r:SetScript("OnClick", function() m:Hide(); if fn then fn() end end)
        end
        r:Show()
        y = y + ROWH
    end
    m:SetSize(WIDTH, y + 6)
    m:ClearAllPoints()
    if anchor then
        m:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    else
        m:SetPoint("CENTER")
    end
    m.closer:Show(); m:Show()
end

function Bags:OpenItemMenu(btn)
    local id = btn and btn._itemID
    if not id then return end
    local p = self.db.profile
    local pinned = self:IsPinned(id)
    local name = (GetItemInfo and GetItemInfo(id)) or L("Item")
    local entries = {
        { text = name, isTitle = true },
        { text = pinned and L("Unpin item") or L("Pin item"),
          func = function() if pinned then p.pinned[id] = nil else p.pinned[id] = true end; Bags:RefreshInventory() end },
        { text = L("Assign to category"), isTitle = true },
    }
    for _, key in ipairs(DEFAULT_CAT_ORDER) do
        local def = CAT_BY_KEY[key]
        entries[#entries + 1] = { text = "   " .. L(def.name), checked = (p.assign[id] == key),
            func = function() p.assign[id] = key; Bags:RefreshInventory() end }
    end
    entries[#entries + 1] = { text = L("Reset to automatic"),
        func = function() p.assign[id] = nil; Bags:RefreshInventory() end }
    self:ShowMenu(entries, btn._holder)
end

function Bags:OpenSortMenu(anchor)
    local p = self.db.profile
    local cur, dir = p.sortMode or "quality", p.sortDir or "desc"
    local entries = { { text = L("Sort by"), isTitle = true } }
    for _, mode in ipairs(SORT_MODES) do
        entries[#entries + 1] = { text = L(SORT_LABELS[mode]), checked = (mode == cur),
            func = function() p.sortMode = mode; Bags:RefreshAll() end }
    end
    entries[#entries + 1] = { text = L("Direction"), isTitle = true }
    entries[#entries + 1] = { text = L("Descending"), checked = (dir == "desc"),
        func = function() p.sortDir = "desc"; Bags:RefreshAll() end }
    entries[#entries + 1] = { text = L("Ascending"), checked = (dir == "asc"),
        func = function() p.sortDir = "asc"; Bags:RefreshAll() end }
    self:ShowMenu(entries, anchor or (self.win and self.win.sortBtn))
end

-- refresh whichever windows are open + keep both sort buttons in sync
function Bags:RefreshAll()
    self:UpdateSortButton()
    if self.win and self.win:IsShown() then self:RefreshInventory() end
    if self.bankWin and self.bankWin:IsShown() and self.RefreshBank then self:RefreshBank() end
end

function Bags:SetEditMode(on)
    self.editMode = on and true or false
    if self.win and self.win.manageBtn then
        self.win.manageBtn.hl:SetShown(self.editMode)
        self.win.manageBtn.txt:SetTextColor(self.editMode and 1 or 0.8, self.editMode and 1 or 0.8,
                                            self.editMode and (OUI.ACCENT.b > 0.3 and 0.4 or 0.8) or 0.8)
    end
    self:RefreshInventory()
end

function Bags:ToggleEditMode() self:SetEditMode(not self.editMode) end

function Bags:ResizeToGrid(cols, rows)
    rows = math.max(rows, 1)
    local left = self:GridLeft()
    local w = left + cols * (SLOT + SPACING) - SPACING + PAD * 2
    local gridH = rows * (SLOT + SPACING) - SPACING
    local sideH = (self._sidebarVisible or 0) * CAT_BTN_H
    local bodyH = math.max(gridH, sideH, SLOT)
    local bodyTop = HEADER_H + PAD + 6
    local h = bodyTop + bodyH + FOOTER_H + PAD + 6
    self.win:SetSize(w, h)
end

-- ===========================================================================
--  Bags4: visible-order sorting (quality / name / item level / type)
--  Items keep their physical bag slot; only the DISPLAY order is sorted, so
--  no item is ever moved (taint-free). A full re-scan on BAG_UPDATE keeps the
--  slot mapping correct after swaps.
-- ===========================================================================
function Bags:UpdateSortButton()
    local mode = self.db.profile.sortMode or "quality"
    local dir  = self.db.profile.sortDir or "desc"
    local tex  = dir == "asc" and "Interface\\Buttons\\Arrow-Up-Up" or "Interface\\Buttons\\Arrow-Down-Up"
    for _, w in ipairs({ self.win, self.bankWin }) do
        local b = w and w.sortBtn
        if b then
            b.txt:SetText(L(SORT_LABELS[mode] or mode))
            if b.icon then b.icon:SetTexture(tex) end
        end
    end
end

function Bags:CycleSort()   -- kept for /ouibags; the header button uses the menu
    local cur = self.db.profile.sortMode or "quality"
    local i = 1
    for idx, m in ipairs(SORT_MODES) do if m == cur then i = idx; break end end
    self.db.profile.sortMode = SORT_MODES[(i % #SORT_MODES) + 1]
    self:UpdateSortButton()
    self:RefreshInventory()
end

function Bags:CompareItems(a, b, mode)
    if mode == "name" then
        if a.sName ~= b.sName then return a.sName < b.sName end
        return a.sQual > b.sQual
    elseif mode == "itemlevel" then
        if a.sIlvl ~= b.sIlvl then return a.sIlvl > b.sIlvl end
        if a.sQual ~= b.sQual then return a.sQual > b.sQual end
        return a.sName < b.sName
    elseif mode == "type" then
        if a.sClass ~= b.sClass then return a.sClass < b.sClass end
        if a.sSub   ~= b.sSub   then return a.sSub   < b.sSub   end
        if a.sQual  ~= b.sQual  then return a.sQual  > b.sQual  end
        return a.sName < b.sName
    else -- quality (default)
        if a.sQual ~= b.sQual then return a.sQual > b.sQual end
        if a.sIlvl ~= b.sIlvl then return a.sIlvl > b.sIlvl end
        return a.sName < b.sName
    end
end

function Bags:RefreshInventory()
    if not (self.win and self.win:IsShown()) then return end
    if InCombatLockdown() then self._needRefresh = true; return end
    local cols = self.db.profile.bagColumns or 12
    local items = self:ScanItems()

    -- split filled / empty, classify + count, gather sort keys for filled
    local counts, filled, empty = {}, {}, {}
    local p = self.db.profile
    self:TrackRecent(items)          -- mark newly-acquired itemIDs as recent
    for _, it in ipairs(items) do
        if it.info then
            local link = it.info.hyperlink
            local id   = it.info.itemID
            it.itemID  = id
            local k = self:ClassifyItem(it.info)
            it.categoryKey = k
            counts[k] = (counts[k] or 0) + 1
            if self:IsPinned(id) then counts.pinned = (counts.pinned or 0) + 1 end
            if self:IsRecent(id) then counts.recent = (counts.recent or 0) + 1 end
            it.sName  = (link and GetItemInfo(link)) or ""
            it.sQual  = it.info.quality or 0
            local _, _, _, _, _, cid, sid = link and GetItemInfoInstant(link)
            it.sClass = cid or 99
            it.sSub   = sid or 0
            it.sIlvl  = (link and GetDetailedItemLevelInfo and GetDetailedItemLevelInfo(link)) or 0
            filled[#filled + 1] = it
        else
            empty[#empty + 1] = it
        end
    end

    local mode = p.sortMode or "quality"
    local dir  = p.sortDir or "desc"
    if mode ~= "none" then
        table.sort(filled, function(a, b)
            if dir == "asc" then return Bags:CompareItems(b, a, mode) end
            return Bags:CompareItems(a, b, mode)
        end)
    end

    -- active category: reset to "all" if it became empty / sidebar off
    local active = self:SidebarOn() and (self.activeCategory or "all") or "all"
    local activeN = (active == "pinned" and (counts.pinned or 0))
                 or (active == "recent" and (counts.recent or 0))
                 or (active ~= "all" and (counts[active] or 0)) or 0
    if active ~= "all" and activeN == 0 then active = "all" end
    self.activeCategory = active

    self._sidebarVisible = self:RefreshSidebar(counts)
    self:UpdateSortButton()

    -- build render list: filtered filled, then empties (only in unfiltered "all" view)
    local search = self.searchText
    local hasSearch = search and search ~= ""
    local list = {}
    for _, it in ipairs(filled) do
        local pass = (not hasSearch) or self:MatchesSearch(it.info)
        if pass and active ~= "all" then
            if active == "pinned" then pass = self:IsPinned(it.itemID)
            elseif active == "recent" then pass = self:IsRecent(it.itemID)
            else pass = (it.categoryKey == active) end
        end
        if pass then list[#list + 1] = it end
    end
    if active == "all" and not hasSearch then
        for _, it in ipairs(empty) do list[#list + 1] = it end
    end

    local gridLeft = self:GridLeft()
    local idx = 0
    for _, it in ipairs(list) do
        idx = idx + 1
        local btn = self:GetSlot(idx)
        if btn then
            self:RenderSlot(btn, it.bag, it.slot, it.info)
            local col = (idx - 1) % cols
            local row = math.floor((idx - 1) / cols)
            btn._holder:ClearAllPoints()
            btn._holder:SetPoint("TOPLEFT", self.win.body, "TOPLEFT",
                gridLeft + col * (SLOT + SPACING), -row * (SLOT + SPACING))
            btn._holder:Show()
        end
    end
    if self.slots then
        for i = idx + 1, #self.slots do self.slots[i]._holder:Hide() end
    end
    self.win._placeholder:SetShown(idx == 0)
    self:ResizeToGrid(cols, math.ceil(math.max(idx, 1) / cols))
end

-- light updates (loop visible slots only)
function Bags:RefreshCooldowns()
    if not (self.slots and self:IsShown()) then return end
    for _, btn in ipairs(self.slots) do
        if btn._holder:IsShown() and btn.cd then
            local bag, slot = btn._holder:GetID(), btn:GetID()
            local s, d, e = C_Container.GetContainerItemCooldown(bag, slot)
            if CooldownFrame_Set then CooldownFrame_Set(btn.cd, s, d, e)
            elseif s and d and d > 0 then btn.cd:SetCooldown(s, d) end
        end
    end
end

function Bags:RefreshLocks()
    if not (self.slots and self:IsShown()) then return end
    for _, btn in ipairs(self.slots) do
        if btn._holder:IsShown() then
            local bag, slot = btn._holder:GetID(), btn:GetID()
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if SetItemButtonDesaturated then SetItemButtonDesaturated(btn, info and info.isLocked) end
        end
    end
end

function Bags:RefreshFonts()
    if not self.slots then return end
    local cs = self.db.profile.bagCountFontSize or 14
    local is = self.db.profile.itemlevelFontSize or 12
    for _, btn in ipairs(self.slots) do
        if btn.Count then btn.Count:SetFont(Font(), cs, "OUTLINE") end
        if btn.ilvl then btn.ilvl:SetFont(Font(), is, "OUTLINE") end
    end
end

function Bags:RebuildLayout()
    if self:IsShown() then self:RefreshInventory() end
end

-- ---------------------------------------------------------------------------
--  Lifecycle
-- ---------------------------------------------------------------------------
-- ===========================================================================
--  Bags6: auto-sell at merchant (named rulesets, AND/OR/XOR, sell strategies)
-- ===========================================================================
local function opCmp(op, a, b)
    if op == "lt" then return a < b
    elseif op == "le" then return a <= b
    elseif op == "eq" then return a == b
    elseif op == "ge" then return a >= b
    elseif op == "gt" then return a > b end
    return false
end

-- one condition vs item {ilvl, quality, classID, name, sellItem, sellStack}
local function condMatch(c, it)
    if c.field == "name" then
        local n = (it.name or ""):lower()
        local v = tostring(c.value or ""):lower()
        if v == "" then return false end
        if c.op == "contains"  then return n:find(v, 1, true) ~= nil
        elseif c.op == "ncontains" then return n:find(v, 1, true) == nil
        elseif c.op == "begins" then return n:sub(1, #v) == v
        elseif c.op == "ends"   then return n:sub(-#v) == v end
        return false
    end
    local a
    if c.field == "itemlevel" then a = it.ilvl
    elseif c.field == "quality" then a = it.quality
    elseif c.field == "itemtype" then a = it.classID
    elseif c.field == "sellitem" then a = it.sellItem
    elseif c.field == "sellstack" then a = it.sellStack end
    if a == nil then return false end
    return opCmp(c.op, a, c.value)
end

function Bags:RulesetMatches(rs, it)
    local conds = rs.conditions
    if not conds or #conds == 0 then return false end
    local m = 0
    for _, c in ipairs(conds) do if condMatch(c, it) then m = m + 1 end end
    local logic = rs.logic or "AND"
    if logic == "OR" then return m > 0
    elseif logic == "XOR" then return (m % 2) == 1
    else return m == #conds end   -- AND (all conditions)
end

-- strategy gate for non-keep modes (keep is resolved per-item afterwards).
-- full/partial only apply to stackable items; non-stackables fall through to sell.
local function strategyAllows(mode, count, maxStack)
    if mode == "fullonly" then return (maxStack <= 1) or (count >= maxStack)
    elseif mode == "partialonly" then return (maxStack > 1) and (count < maxStack)
    else return true end   -- "all"
end

function Bags:MerchantOpen()
    return self._merchantOpen or (MerchantFrame and MerchantFrame:IsShown()) or false
end

function Bags:AutoSell(verbose)
    local as = self.db.profile.autoSell
    if not as.enabled then
        if verbose then OUI:Print("|cffd9a441[Bags]|r " .. L("Auto-sell is disabled.")) end
        return
    end
    if InCombatLockdown() then return end

    local cand = {}          -- { {bag, slot, value}, ... }  -> sell whole stack
    local keepGroups = {}    -- itemID -> { keep=, list={ {bag,slot,count,value}, ... } }

    for _, bag in ipairs(BAG_IDS) do
        local n = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, n do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and not info.isLocked then
                local link, id = info.hyperlink, info.itemID
                local quality = info.quality or 1
                if not self:IsPinned(id) and quality < 4 then
                    local name, _, _, _, _, _, _, maxStack, _, _, sellPrice = GetItemInfo(link)
                    local classID = select(6, GetItemInfoInstant(link))
                    local ilvl = (GetDetailedItemLevelInfo and GetDetailedItemLevelInfo(link)) or 0
                    local count = info.stackCount or 1
                    maxStack = maxStack or 1
                    local it = {
                        ilvl = ilvl, quality = quality, classID = classID, name = name,
                        sellItem = sellPrice or 0, sellStack = (sellPrice or 0) * count,
                    }
                    -- decide: gray, or first matching ruleset
                    local sell, strat = false, nil
                    if as.sellGray and quality == 0 then sell, strat = true, { mode = "all" } end
                    if not sell then
                        for _, rs in ipairs(as.rulesets) do
                            if self:RulesetMatches(rs, it) then sell, strat = true, rs.strategy or { mode = "all" }; break end
                        end
                    end
                    if sell and (sellPrice or 0) > 0 then
                        local mode = strat.mode or "all"
                        if mode == "keep" then
                            local g = keepGroups[id] or { keep = strat.keep or 0, list = {} }
                            g.list[#g.list + 1] = { bag = bag, slot = slot, count = count, value = it.sellStack }
                            keepGroups[id] = g
                        elseif strategyAllows(mode, count, maxStack) then
                            cand[#cand + 1] = { bag = bag, slot = slot, value = it.sellStack }
                        end
                    end
                end
            end
        end
    end

    -- resolve keep-X groups: keep smallest stacks until kept >= X, sell the rest
    for _, g in pairs(keepGroups) do
        table.sort(g.list, function(a, b) return a.count < b.count end)
        local kept = 0
        for _, e in ipairs(g.list) do
            if kept < g.keep then kept = kept + e.count
            else cand[#cand + 1] = { bag = e.bag, slot = e.slot, value = e.value } end
        end
    end

    if verbose then
        OUI:Print(("|cffd9a441[Bags]|r " .. L("Auto-sell: %d matching item(s), %d ruleset(s), merchant open: %s")):format(
            #cand, #as.rulesets, tostring(self:MerchantOpen())))
    end
    if #cand == 0 then return end
    if not self:MerchantOpen() then
        if verbose then OUI:Print("|cffd9a441[Bags]|r " .. L("Open a merchant to sell.")) end
        return
    end
    local total, sold, i = 0, 0, 1
    local function step()
        if not Bags:MerchantOpen() then return end
        local e = cand[i]
        if e then
            ContainerUse(e.bag, e.slot)
            total = total + (e.value or 0); sold = sold + 1; i = i + 1
            C_Timer.After(0.2, step)
        elseif sold > 0 then
            OUI:Print(("|cffd9a441[Bags]|r " .. L("Sold %d items for %s")):format(sold, GetCoinTextureString(total)))
        end
    end
    step()
end

-- Reorganize: merge partial stacks of the same item (MoP has no native bag
-- sort). Only merges pairs whose combined count fits the max stack, so the
-- source empties completely into the target -> no leftover on the cursor.
function Bags:Reorganize()
    self:ReorganizeContainers(BAG_IDS, function() if Bags:IsShown() then Bags:RefreshInventory() end end)
end

function Bags:ReorganizeContainers(ids, onDone)
    if InCombatLockdown() then
        OUI:Print("|cffd9a441[Bags]|r " .. L("Cannot reorganize in combat."))
        return
    end
    if self._reorgRunning then return end

    -- gather partial stacks by itemID
    local byItem = {}
    for _, bag in ipairs(ids) do
        local n = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, n do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID and not info.isLocked then
                local maxStack = select(8, GetItemInfo(info.hyperlink)) or 1
                local count = info.stackCount or 1
                if maxStack > 1 and count < maxStack then
                    local g = byItem[info.itemID] or { max = maxStack, slots = {} }
                    g.slots[#g.slots + 1] = { bag = bag, slot = slot, count = count }
                    byItem[info.itemID] = g
                end
            end
        end
    end

    -- build moves: greedily combine partials that fully fit together
    local moves = {}
    for _, g in pairs(byItem) do
        local s = g.slots
        if #s >= 2 then
            table.sort(s, function(a, b) return a.count < b.count end)
            local used = {}
            for i = #s, 1, -1 do
                if not used[i] then
                    for j = 1, i - 1 do
                        if not used[j] and s[j].count + s[i].count <= g.max then
                            moves[#moves + 1] = { from = s[i], to = s[j] }
                            s[j].count = s[j].count + s[i].count
                            used[i] = true
                            break
                        end
                    end
                end
            end
        end
    end

    if #moves == 0 then
        OUI:Print("|cffd9a441[Bags]|r " .. L("Nothing to reorganize."))
        return
    end

    self._reorgRunning = true
    local i = 1
    local function step()
        local m = moves[i]
        if not m then
            self._reorgRunning = nil
            OUI:Print(("|cffd9a441[Bags]|r " .. L("Merged %d stacks.")):format(i - 1))
            if onDone then onDone() end
            return
        end
        if ClearCursor then ClearCursor() end
        ContainerPickup(m.from.bag, m.from.slot)   -- pick up the smaller stack
        ContainerPickup(m.to.bag, m.to.slot)       -- drop onto the target (fully merges)
        if ClearCursor then ClearCursor() end
        i = i + 1
        C_Timer.After(0.2, step)
    end
    step()
end

function Bags:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("OldschoolUIBagsDB", defaults, true)
    self.searchText = ""
    -- migrate old CENTER-offset positions: drop them once so the window
    -- re-centres under the new TOPLEFT anchoring (then user drags freely)
    if not self.db.profile._posV2 then
        self.db.profile.x, self.db.profile.y = nil, nil
        self.db.profile._posV2 = true
    end
    -- migrate old flat autosell rules into a single ruleset
    local as = self.db.profile.autoSell
    if as.rules and not as._migratedV2 then
        if #as.rules > 0 then
            as.rulesets = as.rulesets or {}
            table.insert(as.rulesets, {
                name = "Ruleset 1", logic = as.ruleLogic or "OR",
                strategy = { mode = "all", keep = 0 }, conditions = as.rules,
            })
        end
        as.rules, as.ruleLogic = nil, nil
        as._migratedV2 = true
    end
    as.rulesets = as.rulesets or {}
end

function Bags:OnEnable()
    self:SuppressBlizzard()
    self:HookBlizzard()
    self:RegisterEvent("PLAYER_MONEY", "UpdateGold")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function() Bags:UpdateGoldLog() end)
    self:RegisterEvent("MERCHANT_SHOW", function()
        Bags._merchantOpen = true
        C_Timer.After(0.1, function() Bags:AutoSell() end)
    end)
    self:RegisterEvent("MERCHANT_CLOSED", function() Bags._merchantOpen = false end)
    -- refresh hooks (consumed once the grid exists in Bags2)
    self:RegisterEvent("BAG_UPDATE_DELAYED", function()
        if Bags:IsShown() and Bags.RefreshInventory then Bags:RefreshInventory() end
        if Bags.bankWin and Bags.bankWin:IsShown() and Bags.RefreshBank then Bags:RefreshBank() end
    end)
    self:RegisterEvent("BAG_UPDATE_COOLDOWN", function() if Bags:IsShown() and Bags.RefreshCooldowns then Bags:RefreshCooldowns() end end)
    self:RegisterEvent("ITEM_LOCK_CHANGED", function() if Bags:IsShown() and Bags.RefreshLocks then Bags:RefreshLocks() end end)
    self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
        if Bags._needRefresh then Bags._needRefresh = nil; if Bags:IsShown() then Bags:RefreshInventory() end end
    end)
    -- item data streams in async; re-sort once it settles (debounced)
    self:RegisterEvent("GET_ITEM_INFO_RECEIVED", function()
        if not (Bags:IsShown()) or Bags._infoPending then return end
        Bags._infoPending = true
        C_Timer.After(0.25, function()
            Bags._infoPending = nil
            if Bags:IsShown() then Bags:RefreshInventory() end
        end)
    end)
    -- bank (Bags7)
    self:RegisterEvent("BANKFRAME_OPENED", function() if Bags.OnBankOpened then Bags:OnBankOpened() end end)
    self:RegisterEvent("BANKFRAME_CLOSED", function() if Bags.OnBankClosed then Bags:OnBankClosed() end end)
    self:RegisterEvent("PLAYERBANKSLOTS_CHANGED", function()
        if Bags.bankWin and Bags.bankWin:IsShown() and Bags.RefreshBank then Bags:RefreshBank() end
    end)
end

-- ---------------------------------------------------------------------------
--  Slash
-- ---------------------------------------------------------------------------
SLASH_OUIBAGS1 = "/ouibags"
SlashCmdList["OUIBAGS"] = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "unlock" or msg == "move" then
        Bags:Open()
        OUI:Print("|cffd9a441[Bags]|r Ziehe das Fenster am Titel-/Kopfbereich, um es zu verschieben.")
    elseif msg == "lock" then
        if OUI.ToggleUnlock then OUI:ToggleUnlock(false) end
    elseif msg == "bank" then
        Bags:ToggleBank()
    elseif msg == "sell" then
        Bags:AutoSell(true)
    elseif msg == "reorg" or msg == "cleanup" then
        Bags:Reorganize()
    elseif msg == "debug" then
        local shown = Bags.win and Bags.win:IsShown()
        local items = Bags:ScanItems()
        local filled = 0
        for _, it in ipairs(items) do if it.info then filled = filled + 1 end end
        local nslots = 0; if Bags.slots then for _ in pairs(Bags.slots) do nslots = nslots + 1 end end
        OUI:Print(("|cffd9a441[Bags debug]|r winShown=%s C_Container=%s scan=%d filled=%d slots=%d combat=%s"):format(
            tostring(shown), tostring(C_Container ~= nil), #items, filled, nslots, tostring(InCombatLockdown())))
        Bags:Open()
    else
        Bags:Toggle()
    end
end

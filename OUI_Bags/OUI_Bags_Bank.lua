-- ===========================================================================
--  OldschoolUI -- Bags7: player bank window (clean-room, MoP Classic 5.5.x)
--  Reuses the shared slot factory (Bags:_buildSlot) + RenderSlot + sort/search.
--  Warband bank is intentionally absent (retail). Reagent bank + category
--  sidebar follow in a later step.
-- ===========================================================================
local ADDON, ns = ...
local OUI  = OldschoolUI
local Bags = ns.Bags
if not Bags then return end

local PP    = OUI.PP
local function Font() return (OUI.GetFontPath and OUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF" end
local function L(s) return (OUI.L and OUI.L(s)) or s end

-- geometry (kept in sync with OUI_Bags.lua)
local SLOT, SPACING       = Bags.SLOT or 34, Bags.SPACING or 4
local HEADER_H, FOOTER_H  = 35, 32
local PAD                 = 10
local SIDEBAR_W, SIDEBAR_GAP, CAT_BTN_H = 150, 8, 22

-- bank container -1 + purchasable bank bags 5..11 (MoP; no Warband/reagent here)
local BANK_IDS = { -1, 5, 6, 7, 8, 9, 10, 11 }
Bags.BANK_IDS = BANK_IDS

-- ---------------------------------------------------------------------------
--  Window
-- ---------------------------------------------------------------------------
function Bags:BuildBankWindow()
    if self.bankWin then return self.bankWin end
    local f = CreateFrame("Frame", "OUIBankFrame", UIParent)
    f:SetSize(self.db.profile.bankColumns * (SLOT + SPACING) + PAD * 2, 400)
    f:EnableMouse(true); f:SetClampedToScreen(true); f:SetMovable(true)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)        -- clicking anywhere in the window raises it above the bag window
    f:Hide()

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0.06, 0.06, 0.07, 0.97)
    if PP and PP.CreateBorder then PP.CreateBorder(f, 0, 0, 0, 0.9) end

    -- header (drag handle)
    local header = CreateFrame("Frame", nil, f)
    header:SetPoint("TOPLEFT", PAD, -PAD); header:SetPoint("TOPRIGHT", -PAD, -PAD)
    header:SetHeight(HEADER_H); header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() f:StartMoving() end)
    header:SetScript("OnDragStop", function() f:StopMovingOrSizing(); Bags:BankSavePosition(); Bags:BankReposition() end)
    f.header = header

    f.title = header:CreateFontString(nil, "OVERLAY")
    f.title:SetFont(Font(), 15, "OUTLINE"); f.title:SetPoint("LEFT", header, "LEFT", 2, 0)
    f.title:SetText(L("Bank")); f.title:SetTextColor(OUI.ACCENT.r, OUI.ACCENT.g, OUI.ACCENT.b)

    -- sort button (shared sortMode)
    local sort = CreateFrame("Button", nil, header)
    sort:SetSize(118, 20); sort:SetPoint("LEFT", f.title, "RIGHT", 12, 0)
    sort.icon = sort:CreateTexture(nil, "ARTWORK"); sort.icon:SetSize(12, 12); sort.icon:SetPoint("LEFT", 0, 0)
    sort.icon:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
    sort.txt = sort:CreateFontString(nil, "OVERLAY"); sort.txt:SetFont(Font(), 11, "")
    sort.txt:SetPoint("LEFT", sort.icon, "RIGHT", 3, 0); sort.txt:SetJustifyH("LEFT"); sort.txt:SetTextColor(0.85, 0.85, 0.85)
    sort:SetScript("OnEnter", function(s) s.txt:SetTextColor(1, 1, 1) end)
    sort:SetScript("OnLeave", function(s) s.txt:SetTextColor(0.85, 0.85, 0.85) end)
    sort:SetScript("OnClick", function(s) Bags:OpenSortMenu(s) end)
    f.sortBtn = sort

    -- reorganize bank stacks
    local reorg = CreateFrame("Button", nil, header)
    reorg:SetSize(20, 20); reorg:SetPoint("LEFT", sort, "RIGHT", 6, 0)
    reorg.icon = reorg:CreateTexture(nil, "ARTWORK"); reorg.icon:SetAllPoints()
    reorg.icon:SetTexture("Interface\\Buttons\\UI-RefreshButton"); reorg.icon:SetVertexColor(0.85, 0.85, 0.85)
    reorg:SetScript("OnEnter", function(s)
        s.icon:SetVertexColor(1, 1, 1)
        GameTooltip:SetOwner(s, "ANCHOR_BOTTOM"); GameTooltip:SetText(L("Reorganize")); GameTooltip:Show()
    end)
    reorg:SetScript("OnLeave", function(s) s.icon:SetVertexColor(0.85, 0.85, 0.85); GameTooltip:Hide() end)
    reorg:SetScript("OnClick", function()
        Bags:ReorganizeContainers(BANK_IDS, function() if Bags.bankWin:IsShown() then Bags:RefreshBank() end end)
    end)

    -- close
    local close = CreateFrame("Button", nil, header)
    close:SetSize(20, 20); close:SetPoint("RIGHT", header, "RIGHT", 0, 0)
    close._t = close:CreateFontString(nil, "OVERLAY")
    close._t:SetFont(Font(), 16, "OUTLINE"); close._t:SetPoint("CENTER"); close._t:SetText("x"); close._t:SetTextColor(0.8, 0.8, 0.8)
    close:SetScript("OnEnter", function() close._t:SetTextColor(1, 0.3, 0.3) end)
    close:SetScript("OnLeave", function() close._t:SetTextColor(0.8, 0.8, 0.8) end)
    close:SetScript("OnClick", function() Bags:CloseBank() end)

    -- search
    local search = CreateFrame("EditBox", nil, header)
    search:SetSize(150, 20); search:SetPoint("RIGHT", close, "LEFT", -8, 0)
    search:SetAutoFocus(false); search:SetFont(Font(), 12, ""); search:SetTextInsets(6, 18, 0, 0)
    local sbg = search:CreateTexture(nil, "BACKGROUND"); sbg:SetAllPoints(); sbg:SetColorTexture(0.12, 0.12, 0.13, 0.9)
    if PP and PP.CreateBorder then PP.CreateBorder(search, 0, 0, 0, 0.9) end
    local clr = CreateFrame("Button", nil, search)
    clr:SetSize(16, 16); clr:SetPoint("RIGHT", search, "RIGHT", -3, 0)
    clr._t = clr:CreateFontString(nil, "OVERLAY"); clr._t:SetFont(Font(), 13, "OUTLINE"); clr._t:SetPoint("CENTER"); clr._t:SetText("x"); clr._t:SetTextColor(0.7, 0.7, 0.7)
    clr:SetScript("OnClick", function() search:SetText(""); search:ClearFocus() end); clr:Hide()
    search:SetScript("OnEscapePressed", function(s) s:ClearFocus(); s:SetText("") end)
    search:SetScript("OnTextChanged", function(s)
        local t = (s:GetText() or "")
        Bags.bankSearchText = t:lower(); clr:SetShown(t ~= "")
        if Bags.bankWin:IsShown() then Bags:RefreshBank() end
    end)
    f.search = search

    -- body
    local body = CreateFrame("Frame", nil, f)
    body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
    body:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -6)
    body:SetPoint("BOTTOM", f, "BOTTOM", 0, FOOTER_H + PAD)
    f.body = body
    f._placeholder = body:CreateFontString(nil, "OVERLAY")
    f._placeholder:SetFont(Font(), 12, ""); f._placeholder:SetPoint("CENTER"); f._placeholder:SetText("|cff888888(empty)|r")

    -- category sidebar (shares the suite-wide category model)
    local sidebar = CreateFrame("Frame", nil, body)
    sidebar:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
    sidebar:SetWidth(SIDEBAR_W); sidebar:SetHeight(1)
    f.sidebar = sidebar

    -- footer (free slots)
    f.info = f:CreateFontString(nil, "OVERLAY")
    f.info:SetFont(Font(), 12, "OUTLINE"); f.info:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, PAD); f.info:SetJustifyH("RIGHT")

    self.bankWin = f
    self:BuildBankSidebar()
    self:UpdateSortButton()
    self:BankReposition()
    f:SetScale(self.db.profile.bagScale or 1)
    return f
end

function Bags:BankSavePosition()
    local f = self.bankWin; if not f then return end
    local rel = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
    self.db.profile.bankX = f:GetLeft() * rel - UIParent:GetLeft()
    self.db.profile.bankY = f:GetTop() * rel - UIParent:GetTop()
end

function Bags:BankReposition()
    if not self.bankWin then return end
    self.bankWin:ClearAllPoints()
    local p = self.db.profile
    if p.bankX and p.bankY then
        self.bankWin:SetPoint("TOPLEFT", UIParent, "TOPLEFT", p.bankX, p.bankY)
    else
        self.bankWin:SetPoint("CENTER", UIParent, "CENTER", -180, 60)
    end
end

-- ---------------------------------------------------------------------------
--  Scan + render
-- ---------------------------------------------------------------------------
function Bags:ScanBank()
    local items = {}
    for _, bag in ipairs(BANK_IDS) do
        local n = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, n do
            items[#items + 1] = { bag = bag, slot = slot, info = C_Container.GetContainerItemInfo(bag, slot) }
        end
    end
    return items
end

-- bank category sidebar (no drag-reorder; shares the suite category order)
function Bags:BuildBankSidebar()
    local sb = self.bankWin and self.bankWin.sidebar
    if not sb or self._bankSidebarBuilt then return end
    self._bankSidebarBuilt = true
    self._bankCatButtons = {}
    for _, def in ipairs(self.CAT_DEFS) do
        local b = CreateFrame("Button", nil, sb)
        b:SetSize(SIDEBAR_W, CAT_BTN_H); b._key = def.key
        b.hl = b:CreateTexture(nil, "BACKGROUND"); b.hl:SetAllPoints()
        b.hl:SetColorTexture(OUI.ACCENT.r, OUI.ACCENT.g, OUI.ACCENT.b, 0.22); b.hl:Hide()
        b.hover = b:CreateTexture(nil, "BACKGROUND"); b.hover:SetAllPoints()
        b.hover:SetColorTexture(1, 1, 1, 0.06); b.hover:Hide()
        b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(16, 16); b.icon:SetPoint("LEFT", 3, 0)
        b.icon:SetTexture(def.icon); b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.cnt = b:CreateFontString(nil, "OVERLAY"); b.cnt:SetFont(Font(), 11, ""); b.cnt:SetPoint("RIGHT", -4, 0)
        b.cnt:SetJustifyH("RIGHT"); b.cnt:SetTextColor(0.6, 0.6, 0.6)
        b.txt = b:CreateFontString(nil, "OVERLAY"); b.txt:SetFont(Font(), 11, "")
        b.txt:SetPoint("LEFT", b.icon, "RIGHT", 5, 0); b.txt:SetPoint("RIGHT", b.cnt, "LEFT", -4, 0)
        b.txt:SetJustifyH("LEFT"); b.txt:SetWordWrap(false); b.txt:SetText(L(def.name))
        b:SetScript("OnEnter", function(s) if not s.hl:IsShown() then s.hover:Show() end end)
        b:SetScript("OnLeave", function(s) s.hover:Hide() end)
        b:SetScript("OnClick", function(s) Bags.bankActiveCategory = s._key; Bags:RefreshBank() end)
        self._bankCatButtons[def.key] = b
    end
end

function Bags:BankGridLeft()
    return self:SidebarOn() and (SIDEBAR_W + SIDEBAR_GAP) or 0
end

function Bags:RefreshBankSidebar(counts)
    if not (self.bankWin and self._bankCatButtons) then return 0 end
    local on = self:SidebarOn()
    self.bankWin.sidebar:SetShown(on)
    if not on then return 0 end
    counts = counts or {}
    local hideEmpty = self.db.profile.hideEmptyCategories ~= false
    local active = self.bankActiveCategory or "all"
    local y, vis = 0, 0
    for _, b in pairs(self._bankCatButtons) do b:Hide() end
    for _, key in ipairs(self:CategoryOrder()) do
        local b = self._bankCatButtons[key]
        local n = counts[key] or 0
        local show = (key == "all") or (not hideEmpty) or (n > 0)
        if b and show then
            b:ClearAllPoints(); b:SetPoint("TOPLEFT", self.bankWin.sidebar, "TOPLEFT", 0, -y)
            b:SetFrameLevel((self.bankWin.sidebar:GetFrameLevel() or 1) + 1); b:Show()
            b.cnt:SetText(key == "all" and "" or tostring(n))
            local on2 = (key == active)
            b.hl:SetShown(on2)
            b.txt:SetTextColor(on2 and 1 or 0.82, on2 and 1 or 0.82, on2 and 1 or 0.82)
            y = y + CAT_BTN_H; vis = vis + 1
        end
    end
    self.bankWin.sidebar:SetHeight(math.max(y, 1))
    return vis
end

function Bags:ResizeBank(cols, rows)
    rows = math.max(rows, 1)
    local left = self:BankGridLeft()
    local w = left + cols * (SLOT + SPACING) - SPACING + PAD * 2
    local gridH = rows * (SLOT + SPACING) - SPACING
    local sideH = (self._bankSidebarVisible or 0) * CAT_BTN_H
    local bodyTop = HEADER_H + PAD + 6
    local h = bodyTop + math.max(gridH, sideH, SLOT) + FOOTER_H + PAD + 6
    self.bankWin:SetSize(w, h)
end

local function bankNameMatch(info, q)
    if not q or q == "" then return true end
    if not info then return false end
    local name = GetItemInfo(info.hyperlink)
    return (name and name:lower():find(q, 1, true) ~= nil) or false
end

function Bags:RefreshBank()
    if not (self.bankWin and self.bankWin:IsShown()) then return end
    if InCombatLockdown() then self._bankNeedRefresh = true; return end
    local cols = self.db.profile.bankColumns or 14
    local items = self:ScanBank()

    local counts, filled, empty, free = {}, {}, {}, 0
    for _, it in ipairs(items) do
        if it.info then
            local link, id = it.info.hyperlink, it.info.itemID
            it.itemID = id
            local k = self:ClassifyItem(it.info); it.categoryKey = k
            counts[k] = (counts[k] or 0) + 1
            if self:IsPinned(id) then counts.pinned = (counts.pinned or 0) + 1 end
            if self:IsRecent(id) then counts.recent = (counts.recent or 0) + 1 end
            it.sName = (link and GetItemInfo(link)) or ""
            it.sQual = it.info.quality or 0
            local _, _, _, _, _, cid, sid = link and GetItemInfoInstant(link)
            it.sClass = cid or 99; it.sSub = sid or 0
            it.sIlvl = (link and GetDetailedItemLevelInfo and GetDetailedItemLevelInfo(link)) or 0
            filled[#filled + 1] = it
        else
            empty[#empty + 1] = it; free = free + 1
        end
    end

    local active = self:SidebarOn() and (self.bankActiveCategory or "all") or "all"
    local activeN = (active == "pinned" and (counts.pinned or 0))
                 or (active == "recent" and (counts.recent or 0))
                 or (active ~= "all" and (counts[active] or 0)) or 0
    if active ~= "all" and activeN == 0 then active = "all" end
    self.bankActiveCategory = active
    self._bankSidebarVisible = self:RefreshBankSidebar(counts)

    local mode = self.db.profile.sortMode or "quality"
    local dir  = self.db.profile.sortDir or "desc"
    if mode ~= "none" then
        table.sort(filled, function(a, b)
            if dir == "asc" then return Bags:CompareItems(b, a, mode) end
            return Bags:CompareItems(a, b, mode)
        end)
    end

    local q = self.bankSearchText
    local hasSearch = q and q ~= ""
    local list = {}
    for _, it in ipairs(filled) do
        local pass = (not hasSearch) or bankNameMatch(it.info, q)
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

    local gridLeft = self:BankGridLeft()
    self.bankSlots = self.bankSlots or {}
    local idx = 0
    for _, it in ipairs(list) do
        idx = idx + 1
        local btn = self:GetBankSlot(idx)
        if btn then
            self:RenderSlot(btn, it.bag, it.slot, it.info)
            local col = (idx - 1) % cols
            local row = math.floor((idx - 1) / cols)
            btn._holder:ClearAllPoints()
            btn._holder:SetPoint("TOPLEFT", self.bankWin.body, "TOPLEFT",
                gridLeft + col * (SLOT + SPACING), -row * (SLOT + SPACING))
            btn._holder:Show()
        end
    end
    for i = idx + 1, #self.bankSlots do self.bankSlots[i]._holder:Hide() end

    self.bankWin._placeholder:SetShown(idx == 0)
    self.bankWin.info:SetText(("%d %s"):format(free, L("free")))
    self:ResizeBank(cols, math.ceil(math.max(idx, 1) / cols))
end

-- ---------------------------------------------------------------------------
--  Open / close + Blizzard suppression
-- ---------------------------------------------------------------------------
function Bags:SuppressBank()
    if self._bankSuppressed then return end
    self._bankSuppressed = true
    local bf = _G.BankFrame
    if not bf then return end
    bf.ignoreFramePositionManager = true
    local function park(s)
        s:SetAlpha(0)
        s:EnableMouse(false)
        s:ClearAllPoints()
        s:SetPoint("TOPLEFT", UIParent, "TOPRIGHT", 600, 0)
        -- EnableMouse(false) on the frame does NOT disable its child buttons. The
        -- native main-bank slots (BankFrameItem1..N = container -1) stay mouse-aware
        -- at alpha 0; left in place they sit under the cursor over our window and
        -- clear our tooltip (flash, then black) — main bank only, since the bank
        -- bags 5-11 are separate containers. Disable their mouse as well.
        local n = _G.NUM_BANKGENERIC_SLOTS or 28
        for i = 1, n do
            local b = _G["BankFrameItem" .. i]
            if b then b:EnableMouse(false) end
        end
    end
    park(bf)
    bf:HookScript("OnShow", park)
end

function Bags:OpenBank()
    self:BuildBankWindow()
    if self.bankWin.search then self.bankWin.search:SetText("") end
    self.bankSearchText = ""
    self.bankActiveCategory = "all"
    self.bankWin:Show()
    self:RefreshBank()
end

function Bags:CloseBank()
    if self.bankWin then self.bankWin:Hide() end
    if CloseBankFrame then CloseBankFrame() end   -- tell the server we're done
end

function Bags:ToggleBank()
    if self.bankWin and self.bankWin:IsShown() then self:CloseBank() else self:OpenBank() end
end

function Bags:OnBankOpened()
    self:SuppressBank()
    self:OpenBank()
    -- also show the inventory so items can be moved between the two
    if not (self.win and self.win:IsShown()) then self._bankAutoOpenedBags = true; self:Open() end
end

function Bags:OnBankClosed()
    if self.bankWin then self.bankWin:Hide() end
    if self._bankAutoOpenedBags then self._bankAutoOpenedBags = nil; self:Close() end
end

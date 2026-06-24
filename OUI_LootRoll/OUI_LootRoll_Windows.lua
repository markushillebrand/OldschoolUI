-------------------------------------------------------------------------------
--  OUI_LootRoll_Windows.lua
--  Two toggle-able windows:
--    * Session window      -- this session's completed group rolls
--                             (item -> winner, who rolled what)
--    * Bonus-roll history  -- last X bonus rolls (boss, result) + gold/item ratio
--  Both are movable, closable, and live-refresh from the data layers via the
--  ns.LR_On* hooks. Read-only views; data lives in the Session / BonusRolls files.
-------------------------------------------------------------------------------

local addonName, ns = ...

local CreateFrame = CreateFrame
local UIParent    = UIParent
local date        = date
local floor       = math.floor
local min         = math.min

local MAX_ROWS = 18  -- visible rows (newest first)

local function Font()  return (OldschoolUI and OldschoolUI.GetFontPath and OldschoolUI.GetFontPath()) or STANDARD_TEXT_FONT end
local function L(s)    return (OldschoolUI and OldschoolUI.L and OldschoolUI.L(s)) or s end
local function Accent() return OldschoolUI.ACCENT or { r = 0.851, g = 0.643, b = 0.255 } end

-------------------------------------------------------------------------------
--  Shared window chrome
-------------------------------------------------------------------------------
local function AddButton(parent, label, w)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w or 70, 20)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(1, 1, 1, 0.06)
    b._bg = bg
    if OldschoolUI and OldschoolUI.PP and OldschoolUI.PP.CreateBorder then
        OldschoolUI.PP.CreateBorder(b, 1, 1, 1, OldschoolUI.DD_BRD_A or 0.2, 1)
    end
    local fs = b:CreateFontString(nil, "OVERLAY")
    fs:SetFont(Font(), 12, ""); fs:SetPoint("CENTER"); fs:SetText(label)
    fs:SetTextColor(0.9, 0.9, 0.9)
    b._label = fs
    b:SetScript("OnEnter", function(self) bg:SetColorTexture(1, 1, 1, 0.12) end)
    b:SetScript("OnLeave", function(self) bg:SetColorTexture(1, 1, 1, 0.06) end)
    return b
end

local function MakeWindow(globalName, titleText, w, h)
    local f = CreateFrame("Frame", globalName, UIParent)
    f:SetSize(w, h)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:Hide()
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); OldschoolUI.RegisterSkinBg(bg, 0.96)
    if OldschoolUI and OldschoolUI.PP and OldschoolUI.PP.CreateBorder then
        OldschoolUI.PP.CreateBorder(f, 1, 1, 1, OldschoolUI.DD_BRD_A or 0.2, 1)
    end

    local title = f:CreateFontString(nil, "OVERLAY")
    title:SetFont(Font(), 15, "")
    local g = Accent(); title:SetTextColor(g.r, g.g, g.b)
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText(titleText)
    f._title = title

    local sub = f:CreateFontString(nil, "OVERLAY")
    sub:SetFont(Font(), 12, ""); sub:SetTextColor(1, 1, 1, 0.7)
    sub:SetPoint("TOPLEFT", 12, -30)
    f._sub = sub

    local close = CreateFrame("Button", nil, f)
    close:SetSize(22, 22); close:SetPoint("TOPRIGHT", -6, -6)
    local cx = close:CreateFontString(nil, "OVERLAY")
    cx:SetFont(Font(), 16, ""); cx:SetPoint("CENTER"); cx:SetText("x")
    cx:SetTextColor(0.9, 0.6, 0.6)
    close:SetScript("OnEnter", function() cx:SetTextColor(1, 0.4, 0.4) end)
    close:SetScript("OnLeave", function() cx:SetTextColor(0.9, 0.6, 0.6) end)
    close:SetScript("OnClick", function() f:Hide() end)

    local clear = AddButton(f, L("Clear"), 60)
    clear:SetPoint("TOPRIGHT", -34, -8)
    f._clearBtn = clear

    -- Row pool (single formatted line per entry; hyperlinks render colored).
    f._rows = {}
    f._rowTop = -52
    f:SetHyperlinksEnabled(true)
    f:SetScript("OnHyperlinkEnter", function(self, link)
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:SetHyperlink(link); GameTooltip:Show()
    end)
    f:SetScript("OnHyperlinkLeave", function() GameTooltip:Hide() end)

    function f:GetRow(i)
        local row = self._rows[i]
        if not row then
            row = self:CreateFontString(nil, "OVERLAY")
            row:SetFont(Font(), 12, "")
            row:SetJustifyH("LEFT")
            row:SetPoint("TOPLEFT", 12, self._rowTop - (i - 1) * 17)
            row:SetPoint("RIGHT", self, "RIGHT", -12, 0)
            row:SetWordWrap(false)
            self._rows[i] = row
        end
        return row
    end

    function f:HideRowsFrom(n)
        for i = n, #self._rows do self._rows[i]:SetText("") end
    end

    function f:Toggle()
        if self:IsShown() then self:Hide() else self:Show(); if self._refresh then self:_refresh() end end
    end

    return f
end

-------------------------------------------------------------------------------
--  Session window
-------------------------------------------------------------------------------
local sessionWin

local function RollSummary(players)
    local need, greed, de, pass = 0, 0, 0, 0
    for _, p in ipairs(players) do
        if p.rt == 1 then need = need + 1
        elseif p.rt == 2 then greed = greed + 1
        elseif p.rt == 3 then de = de + 1
        elseif p.rt == 0 then pass = pass + 1 end
    end
    return ("N:%d G:%d D:%d P:%d"):format(need, greed, de, pass)
end

local function RefreshSession(self)
    local list = ns.LR_GetSession and ns.LR_GetSession() or {}
    local s = ns.LR_GetSettings and ns.LR_GetSettings() or nil
    local showOthers = not s or s.showOthersRolls ~= false
    self._sub:SetText(L("Completed rolls this session: ") .. #list)
    local shown = min(#list, MAX_ROWS)
    local idx = 0
    for i = #list, #list - shown + 1, -1 do
        idx = idx + 1
        local e = list[i]
        local item = e.link or L("Item")
        local winner = e.winner and ("|cff44ff44" .. e.winner .. "|r") or "|cff888888?|r"
        local tail = showOthers and ("   |cff777777" .. RollSummary(e.players or {}) .. "|r") or ""
        self:GetRow(idx):SetText(("%s  ->  %s%s"):format(item, winner, tail))
    end
    self:HideRowsFrom(idx + 1)
    if idx == 0 then self:GetRow(1):SetText("|cff777777" .. L("No completed rolls yet.") .. "|r") end
end

function ns.LR_ToggleSession()
    if not sessionWin then
        sessionWin = MakeWindow("OUI_LootRoll_SessionWindow", L("Loot Roll Session"), 460, 380)
        sessionWin._refresh = RefreshSession
        sessionWin._clearBtn:SetScript("OnClick", function()
            if ns.LR_ClearSession then ns.LR_ClearSession() end
        end)
        -- Shortcut to the bonus-roll history window.
        local bbtn = AddButton(sessionWin, L("Bonus Rolls"), 90)
        bbtn:SetPoint("TOPRIGHT", sessionWin._clearBtn, "TOPLEFT", -6, 0)
        bbtn:SetScript("OnClick", function()
            if ns.LR_ToggleBonusHistory then ns.LR_ToggleBonusHistory() end
        end)
        -- Shortcut to the loot wishlist window.
        local wbtn = AddButton(sessionWin, L("Wishlist"), 80)
        wbtn:SetPoint("TOPRIGHT", bbtn, "TOPLEFT", -6, 0)
        wbtn:SetScript("OnClick", function()
            if ns.LR_ToggleWishlist then ns.LR_ToggleWishlist() end
        end)
    end
    sessionWin:Toggle()
end

-------------------------------------------------------------------------------
--  Bonus-roll history window
-------------------------------------------------------------------------------
local bonusWin

local function RefreshBonus(self)
    local hist = ns.LR_GetBonusHistory and ns.LR_GetBonusHistory() or {}
    local s = ns.LR_GetSettings and ns.LR_GetSettings() or nil
    local cap = min(MAX_ROWS, (s and s.bonusMaxShow) or 20)
    local total, items, gold, cur, ratio = 0, 0, 0, 0, 0
    if ns.LR_GetBonusStats then
        total, items, gold, cur, ratio = ns.LR_GetBonusStats()
    end
    total = total or 0
    self._sub:SetText(("%s %d   |   %s %d%%   (%s %d  %s %d  %s %d)"):format(
        L("Rolls:"), total,
        L("Item ratio:"), floor((ratio or 0) * 100 + 0.5),
        L("items"), items or 0, L("gold"), gold or 0, L("currency"), cur or 0))
    local shown = min(#hist, cap)
    local idx = 0
    for i = #hist, #hist - shown + 1, -1 do
        idx = idx + 1
        local e = hist[i]
        local res
        if e.typ == "item" then res = e.link or ("|cffa335ee" .. L("Item") .. "|r")
        elseif e.typ == "money" then res = "|cffffd700" .. L("Gold") .. "|r"
        elseif e.typ == "currency" then res = "|cff00ccff" .. L("Currency") .. "|r"
        else res = e.typ or "?" end
        local when = e.t and date("%H:%M", e.t) or ""
        self:GetRow(idx):SetText(("|cff999999%s|r  %s  ->  %s")
            :format(when, e.boss or "?", res))
    end
    self:HideRowsFrom(idx + 1)
    if idx == 0 then self:GetRow(1):SetText("|cff777777" .. L("No bonus rolls recorded yet.") .. "|r") end
end

function ns.LR_ToggleBonusHistory()
    if not bonusWin then
        bonusWin = MakeWindow("OUI_LootRoll_BonusWindow", L("Bonus Roll History"), 460, 380)
        bonusWin._refresh = RefreshBonus
        bonusWin._clearBtn:SetScript("OnClick", function()
            if ns.LR_ClearBonusHistory then ns.LR_ClearBonusHistory() end
        end)
    end
    bonusWin:Toggle()
end

-------------------------------------------------------------------------------
--  Generic clickable button-row pool (shared by wishlist + browser)
-------------------------------------------------------------------------------
local function GetBtnRow(win, i, topY)
    win._brows = win._brows or {}
    local b = win._brows[i]
    if not b then
        b = CreateFrame("Button", nil, win)
        b:SetHeight(18)
        b:SetPoint("TOPLEFT", 12, topY - (i - 1) * 19)
        b:SetPoint("RIGHT", win, "RIGHT", -12, 0)
        local fs = b:CreateFontString(nil, "OVERLAY")
        fs:SetFont(Font(), 12, ""); fs:SetPoint("LEFT"); fs:SetJustifyH("LEFT")
        b._fs = fs
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.07)
        win._brows[i] = b
    end
    b:Show()
    return b
end

local function HideBtnRowsFrom(win, n)
    local rows = win._brows or {}
    for i = n, #rows do rows[i]:Hide(); rows[i]:SetScript("OnEnter", nil); rows[i]:SetScript("OnLeave", nil) end
end

local function DiffTag(diffs)
    local t = {}
    for _, b in ipairs(ns.LR_BUCKET_ORDER or {}) do
        if diffs[b] then t[#t + 1] = (b == "normal" and "N") or (b == "heroic" and "H") or "L" end
    end
    return #t > 0 and ("|cff44ff44[" .. table.concat(t, "") .. "]|r") or "|cff666666[ ]|r"
end

-- Render row-specs { {text=, onClick=, link=} ... } into the button-row pool
-- with mouse-wheel virtual scrolling. Returns total count and visible count.
local ROW_H = 19
local function RenderScrollList(win, specs, topY)
    win._scroll = win._scroll or 0
    local avail = (win:GetHeight() or 400) + topY - 14   -- topY is negative
    local maxRows = math.max(1, math.floor(avail / ROW_H))
    local n = #specs
    local maxScroll = math.max(0, n - maxRows)
    if win._scroll > maxScroll then win._scroll = maxScroll end
    if win._scroll < 0 then win._scroll = 0 end
    win._maxRows = maxRows
    win._lastCount = n
    if not win._wheelHooked then
        win._wheelHooked = true
        win:EnableMouseWheel(true)
        win:SetScript("OnMouseWheel", function(self, delta)
            local ms = math.max(0, (self._lastCount or 0) - (self._maxRows or 1))
            self._scroll = math.min(ms, math.max(0, (self._scroll or 0) - delta))
            if self._rerender then self._rerender() end
        end)
    end
    local shown = 0
    for i = 1, maxRows do
        local spec = specs[win._scroll + i]
        if not spec then break end
        shown = shown + 1
        local b = GetBtnRow(win, i, topY)
        b._fs:SetText(spec.text)
        b:SetScript("OnClick", spec.onClick)
        if spec.link then
            local lk = spec.link
            b:SetScript("OnEnter", function(self2)
                GameTooltip:SetOwner(self2, "ANCHOR_RIGHT"); GameTooltip:SetHyperlink(lk); GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        else
            b:SetScript("OnEnter", nil); b:SetScript("OnLeave", nil)
        end
    end
    HideBtnRowsFrom(win, shown + 1)
    return n, shown, maxRows
end

local function ScrollHint(n, scroll, shown)
    if n <= shown then return "" end
    return ("   |cff888888(%d-%d / %d)|r"):format(scroll + 1, scroll + shown, n)
end

-------------------------------------------------------------------------------
--  Wishlist window (open wishes + obtained, with date)
-------------------------------------------------------------------------------
local wishWin

local function RefreshWishlist(self)
    local list = ns.LR_WishlistGet and ns.LR_WishlistGet() or {}
    local open = 0
    for _, e in ipairs(list) do if not e.obtained then open = open + 1 end end
    local specs = {}
    for _, e in ipairs(list) do
        local who = e.boss and ("|cff999999" .. e.boss .. "|r ") or ""
        local state = e.obtained
            and ("|cff44ff44" .. L("got") .. " " .. date("%d.%m.", e.obtainedAt or 0) .. "|r")
            or  ("|cffffcc00" .. L("open") .. "|r")
        local id = e.itemID
        specs[#specs + 1] = {
            text = ("%s %s%s  %s"):format(DiffTag(e.diffs), who, e.link or e.itemName or e.itemID, state),
            link = e.link,
            onClick = function() if ns.LR_WishlistRemove then ns.LR_WishlistRemove(id) end end,
        }
    end
    if #specs == 0 then
        HideBtnRowsFrom(self, 1)
        self._sub:SetText(L("Open wishes: ") .. open .. "   |   " .. L("Click an entry to remove it."))
        self:GetRow(1):SetText("|cff777777" .. L("Wishlist is empty - add items via the browser.") .. "|r")
    else
        self:HideRowsFrom(1)
        local n, shown = RenderScrollList(self, specs, -52)
        self._sub:SetText(L("Open wishes: ") .. open .. "   |   " .. L("Click an entry to remove it.")
            .. ScrollHint(n, self._scroll, shown))
    end
end

function ns.LR_ToggleWishlist()
    if not wishWin then
        wishWin = MakeWindow("OUI_LootRoll_WishlistWindow", L("Loot Wishlist"), 480, 420)
        wishWin._refresh = RefreshWishlist
        wishWin._rerender = function() RefreshWishlist(wishWin) end
        wishWin._clearBtn:SetScript("OnClick", function()
            local list = ns.LR_WishlistGet and ns.LR_WishlistGet() or {}
            for i = #list, 1, -1 do if not list[i].obtained then ns.LR_WishlistRemove(list[i].itemID) end end
        end)
        -- shortcut button to the browser
        local bb = AddButton(wishWin, L("Add Items..."), 90)
        bb:SetPoint("TOPRIGHT", wishWin._clearBtn, "TOPLEFT", -6, 0)
        bb:SetScript("OnClick", function() if ns.LR_ToggleWishlistBrowser then ns.LR_ToggleWishlistBrowser() end end)
    end
    wishWin:Toggle()
end

-------------------------------------------------------------------------------
--  Wishlist browser (drill-down: raid -> boss -> loot; pick difficulties)
-------------------------------------------------------------------------------
local browserWin
local browser = { level = 0, raid = nil, boss = nil,
                  filters = { normal = true, heroic = true }, currentExpOnly = true }
local diffBtns = {}
local expBtn, usableBtn

local function AvailTag(av)
    if av.normal and av.heroic then return "|cffffd000[NH]|r" end
    if av.heroic then return "|cffff8040[H]|r" end
    return "|cff40b0ff[N]|r"
end

local function UsableOn()
    local s = ns.LR_GetSettings and ns.LR_GetSettings()
    return (not s) or s.wishlistUsableOnly ~= false
end

local function SetToggleVisual(btn, on)
    if not btn then return end
    btn._label:SetTextColor(on and 0.2 or 0.6, on and 0.9 or 0.6, on and 0.5 or 0.6)
    if btn._bg then btn._bg:SetColorTexture(1, 1, 1, on and 0.16 or 0.05) end
end

local function RenderBrowser()
    local self = browserWin
    if not self then return end
    for b, btn in pairs(diffBtns) do SetToggleVisual(btn, browser.filters[b]) end
    SetToggleVisual(expBtn, browser.currentExpOnly)
    SetToggleVisual(usableBtn, UsableOn())
    self._backBtn:SetShown(browser.level > 0)

    local TOP = -86
    local specs = {}
    local headSub = ""

    if browser.level == 0 then
        self._title:SetText(L("Loot Wishlist") .. " - " .. L("Raids"))
        headSub = L("Pick a raid.")
        local curTier = ns.LR_EJ_CurrentTierIndex and ns.LR_EJ_CurrentTierIndex() or 0
        for _, r in ipairs(ns.LR_EJ_GetRaids and ns.LR_EJ_GetRaids() or {}) do
            if (not browser.currentExpOnly) or r.tierIndex == curTier then
                local cap = r
                specs[#specs + 1] = {
                    text = "|cffffffff" .. (r.name or "?") .. "|r  |cff777777" .. (r.tier or "") .. "|r",
                    onClick = function() browser.raid = cap; browser.level = 1; self._scroll = 0; RenderBrowser() end,
                }
            end
        end
    elseif browser.level == 1 then
        self._title:SetText(browser.raid and browser.raid.name or L("Bosses"))
        headSub = L("Pick a boss.")
        for _, bo in ipairs(ns.LR_EJ_GetBosses and ns.LR_EJ_GetBosses(browser.raid.jid) or {}) do
            local cap = bo
            specs[#specs + 1] = {
                text = "|cffffffff" .. (bo.name or "?") .. "|r",
                onClick = function()
                    browser.boss = cap; browser.level = 2; self._scroll = 0
                    if ns.LR_EJ_GetLoot then ns.LR_EJ_GetLoot(cap.jeid, browser.raid.jid) end
                    RenderBrowser()
                    if C_Timer and C_Timer.After then
                        for _, delay in ipairs({ 0.3, 0.8, 1.6 }) do
                            C_Timer.After(delay, function()
                                if browserWin and browserWin:IsShown()
                                   and browser.level == 2 and browser.boss == cap then RenderBrowser() end
                            end)
                        end
                    end
                end,
            }
        end
    else
        self._title:SetText(browser.boss and browser.boss.name or L("Loot"))
        headSub = L("Click an item to add or remove it from the wishlist.")
        local loot = ns.LR_EJ_GetLoot and ns.LR_EJ_GetLoot(browser.boss.jeid, browser.raid.jid) or {}
        for _, it in ipairs(loot) do
            local av = it.avail or {}
            if (browser.filters.normal and av.normal) or (browser.filters.heroic and av.heroic) then
                local cap = it
                local has = ns.LR_WishlistHas and ns.LR_WishlistHas(it.itemID)
                local check = has and "|cff44ff44[x]|r" or "|cff666666[ ]|r"
                specs[#specs + 1] = {
                    text = ("%s %s %s"):format(check, AvailTag(av), it.link or it.name or it.itemID),
                    link = it.link,
                    onClick = function()
                        if ns.LR_WishlistHas and ns.LR_WishlistHas(cap.itemID) then
                            ns.LR_WishlistRemove(cap.itemID)
                        else
                            local addDiffs = {}
                            for _, bkt in ipairs(ns.LR_BUCKET_ORDER or {}) do
                                if browser.filters[bkt] and (cap.avail or {})[bkt] then addDiffs[bkt] = true end
                            end
                            if not next(addDiffs) then for k in pairs(cap.avail or {}) do addDiffs[k] = true end end
                            ns.LR_WishlistAdd({
                                itemID = cap.itemID, itemName = cap.name, link = cap.link, icon = cap.icon,
                                boss = browser.boss.name, jeid = browser.boss.jeid,
                                instance = browser.raid.name, diffs = addDiffs,
                            })
                        end
                        RenderBrowser()
                    end,
                }
            end
        end
        if #specs == 0 then
            local txt = (#loot > 0) and L("No items match the difficulty filter.")
                                     or L("Loading loot... (reopen if empty)")
            self:GetRow(1):SetText("|cff777777" .. txt .. "|r")
        end
    end

    if #specs == 0 then
        HideBtnRowsFrom(self, 1)
        if browser.level ~= 2 then self:HideRowsFrom(1) end
        self._sub:SetText(headSub)
    else
        self:HideRowsFrom(1)
        local n, shown = RenderScrollList(self, specs, TOP)
        self._sub:SetText(headSub .. ScrollHint(n, self._scroll, shown))
    end
end

function ns.LR_ToggleWishlistBrowser()
    if not browserWin then
        browserWin = MakeWindow("OUI_LootRoll_WishlistBrowser", L("Loot Wishlist"), 520, 470)
        browserWin._clearBtn:Hide()
        browserWin._rerender = RenderBrowser
        local back = AddButton(browserWin, "< " .. L("Back"), 60)
        back:SetPoint("TOPLEFT", 12, -52)
        back:SetScript("OnClick", function()
            if browser.level > 0 then browser.level = browser.level - 1; browserWin._scroll = 0; RenderBrowser() end
        end)
        browserWin._backBtn = back
        local prev
        for _, bkt in ipairs({ "normal", "heroic" }) do
            local btn = AddButton(browserWin, ns.LR_BucketLabel(bkt), 66)
            if prev then btn:SetPoint("LEFT", prev, "RIGHT", 6, 0)
            else btn:SetPoint("TOPLEFT", back, "TOPRIGHT", 12, 0) end
            btn:SetScript("OnClick", function()
                browser.filters[bkt] = (not browser.filters[bkt]) or nil
                RenderBrowser()
            end)
            diffBtns[bkt] = btn
            prev = btn
        end
        expBtn = AddButton(browserWin, L("Current Expansion"), 96)
        expBtn:SetPoint("LEFT", prev, "RIGHT", 10, 0)
        expBtn:SetScript("OnClick", function()
            browser.currentExpOnly = not browser.currentExpOnly
            browserWin._scroll = 0
            if browser.level == 0 then RenderBrowser() end
        end)
        usableBtn = AddButton(browserWin, L("Usable Only"), 104)
        usableBtn:SetPoint("LEFT", expBtn, "RIGHT", 10, 0)
        usableBtn:SetScript("OnClick", function()
            local s = ns.LR_GetSettings and ns.LR_GetSettings()
            if s then s.wishlistUsableOnly = not (s.wishlistUsableOnly ~= false) end
            RenderBrowser()
        end)
        browserWin._refresh = RenderBrowser
        ns.LR_EnsureEJ()
    end
    browserWin:Toggle()
end

-------------------------------------------------------------------------------
--  Live-refresh hooks (called by the data layers when data changes)
-------------------------------------------------------------------------------
ns.LR_OnSessionChanged = function()
    if sessionWin and sessionWin:IsShown() then RefreshSession(sessionWin) end
end
ns.LR_OnBonusRecorded = function()
    if bonusWin and bonusWin:IsShown() then RefreshBonus(bonusWin) end
end
ns.LR_OnWishlistChanged = function()
    if wishWin and wishWin:IsShown() then RefreshWishlist(wishWin) end
    if browserWin and browserWin:IsShown() and browser.level == 2 then RenderBrowser() end
end
ns.LR_OnEJLootReady = function()
    if browserWin and browserWin:IsShown() and browser.level == 2 then RenderBrowser() end
end

-------------------------------------------------------------------------------
--  Minimap button (anchored under the calendar / GameTimeFrame)
--  Parented to UIParent at HIGH strata so the minimap's own overlay/border
--  (and rectangular clip) can't hide or clip it; anchored live to the calendar
--  so it tracks wherever our Minimap module repositions GameTimeFrame.
-------------------------------------------------------------------------------
local minimapBtn
local _stackListenerDone

local function AnchorMinimapButton(b)
    b:ClearAllPoints()
    local stack = OldschoolUI and OldschoolUI._minimapStack
    if stack and stack.frame then
        b:ClearAllPoints()
        if stack.point then
            -- Minimap module directs exact anchor + growth direction.
            b:SetPoint(stack.point, stack.frame, stack.relPoint or "BOTTOM", stack.x or 0, stack.y or -4)
        elseif stack.square then
            -- legacy left-edge indicator stack
            b:SetPoint("TOPRIGHT", stack.frame, "TOPLEFT", 0, stack.y or 0)
        else
            b:SetPoint("TOP", stack.frame, "BOTTOM", 0, -4)
        end
        return
    end
    local q = OldschoolUI and OldschoolUI._minimapQueueBtn
    local cal = OldschoolUI and OldschoolUI._minimapCalendarBtn
    if q and q:IsShown() then
        -- While in a queue the LFG queue indicator occupies the slot below the
        -- calendar, so sit below it to avoid overlapping.
        b:SetPoint("TOP", q, "BOTTOM", 0, -4)
    elseif cal then
        -- Sit directly below the visible (custom) calendar indicator.
        b:SetPoint("TOP", cal, "BOTTOM", 0, -4)
    elseif GameTimeFrame then
        b:SetPoint("TOP", GameTimeFrame, "BOTTOM", 0, -2)
    elseif Minimap then
        b:SetPoint("TOPRIGHT", Minimap, "TOPRIGHT", -4, -28)
    else
        b:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -180, -40)
    end
end

local function CreateMinimapButton()
    if minimapBtn then return end
    local b = CreateFrame("Button", "OUI_LootRoll_MinimapButton", UIParent)
    b:SetSize(22, 22)  -- match the Minimap module's indicator buttons
    b:SetFrameStrata("HIGH")
    b:SetFrameLevel(200)

    -- Flat black background to match the minimap indicator buttons (no border,
    -- so all OldschoolUI minimap buttons share one consistent look).
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.8)

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", b, "TOPLEFT", 3, -3)
    icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -3, 3)
    icon:SetTexture("Interface\\Buttons\\UI-GroupLoot-Dice-Up")

    AnchorMinimapButton(b)
    b:SetScript("OnClick", function() if ns.LR_ToggleSession then ns.LR_ToggleSession() end end)
    b:SetScript("OnEnter", function(self)
        bg:SetColorTexture(0.15, 0.15, 0.15, 0.85)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(L("Loot Rolls"))
        GameTooltip:AddLine(L("Click to open the loot roll session window."), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function()
        bg:SetColorTexture(0, 0, 0, 0.8)
        GameTooltip:Hide()
    end)
    minimapBtn = b
end

function ns.LR_RefreshMinimapButton()
    local s = ns.LR_GetSettings and ns.LR_GetSettings() or nil
    local show = not s or s.minimapButton ~= false
    if show then
        CreateMinimapButton()
        if minimapBtn then AnchorMinimapButton(minimapBtn); minimapBtn:Show() end
        if not _stackListenerDone and OldschoolUI and OldschoolUI.RegisterMinimapStackListener then
            _stackListenerDone = true
            OldschoolUI.RegisterMinimapStackListener(function()
                if minimapBtn and minimapBtn:IsShown() then AnchorMinimapButton(minimapBtn) end
            end)
        end
    elseif minimapBtn then
        minimapBtn:Hide()
    end
end

local mmInit = CreateFrame("Frame")
mmInit:RegisterEvent("PLAYER_LOGIN")
mmInit:RegisterEvent("PLAYER_ENTERING_WORLD")
-- Re-anchor when the LFG queue indicator appears/disappears so we slot below it.
mmInit:RegisterEvent("LFG_UPDATE")
mmInit:RegisterEvent("LFG_QUEUE_STATUS_UPDATE")
mmInit:RegisterEvent("LFG_PROPOSAL_SHOW")
mmInit:RegisterEvent("LFG_PROPOSAL_DONE")
mmInit:RegisterEvent("LFG_PROPOSAL_FAILED")
mmInit:SetScript("OnEvent", function(_, event)
    if event == "LFG_UPDATE" or event == "LFG_QUEUE_STATUS_UPDATE"
       or event == "LFG_PROPOSAL_SHOW" or event == "LFG_PROPOSAL_DONE"
       or event == "LFG_PROPOSAL_FAILED" then
        -- Defer so the Minimap module's relayout (which shows/positions the
        -- queue button) has run before we read its visibility.
        if minimapBtn and C_Timer and C_Timer.After then
            C_Timer.After(0.05, function() if minimapBtn then AnchorMinimapButton(minimapBtn) end end)
        elseif minimapBtn then
            AnchorMinimapButton(minimapBtn)
        end
        return
    end
    -- re-run after the Minimap module's layout pass (ENTERING_WORLD) so the
    -- anchor tracks the final calendar position.
    ns.LR_RefreshMinimapButton()
    -- the custom calendar indicator may be created slightly later; re-anchor
    -- once it exists so we sit under the visible calendar, not a fallback spot.
    if C_Timer and C_Timer.After then
        C_Timer.After(1, function()
            if minimapBtn then AnchorMinimapButton(minimapBtn) end
        end)
        C_Timer.After(3, function()
            if minimapBtn then AnchorMinimapButton(minimapBtn) end
        end)
    end
end)

-------------------------------------------------------------------------------
--  Slash shortcuts
-------------------------------------------------------------------------------
SLASH_OUILRWIN1 = "/ouiloot"
SlashCmdList["OUILRWIN"] = function(msg)
    msg = (msg or ""):lower():gsub("%s+", "")
    if msg == "bonus" then ns.LR_ToggleBonusHistory()
    else ns.LR_ToggleSession() end
end

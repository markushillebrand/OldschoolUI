-- ===========================================================================
--  OldschoolUI -- Quality of Life  QL-1: core + general toggles
--  Lightweight, opt-in convenience tweaks. Clean-room rewrite; each feature is
--  a small, self-contained event/CVar hook gated on its own profile flag.
-- ===========================================================================
local ADDON, ns = ...
local OUI = OldschoolUI
if not OUI then return end

local QL = LibStub("AceAddon-3.0"):NewAddon("OldschoolUIQoL", "AceEvent-3.0")
ns.QL = QL

local defaults = {
    profile = {
        suppressLuaErrors    = false,
        hideScreenshotMsg    = true,
        skipCinematics       = false,
        announceInstanceReset = true,
        hidePartyPanel       = false,
        autoRepair           = true,
        autoRepairGuild      = true,
        quickLoot            = false,
        autoOpenContainers   = false,
        autoFillDelete       = true,
        -- info displays
        showFPS              = false,
        showLocalMS          = false,
        showWorldMS          = false,
        showSecondaryStats   = false,
        lowDurabilityWarn    = true,
        lowDurabilityPct     = 20,
        widgetsLocked        = true,
        fpsScale             = 1,
        fpsBgOverride        = false,
        fpsTextOverride      = false,
        statsScale           = 1,
        statsBgOverride      = false,
        statsTextOverride    = false,
        -- cursor circle (QL-4)
        cursorCircle         = false,
        cursorStyle          = "normal",
        cursorSize           = 32,
        cursorColorMode      = "accent",
        cursorInstanceOnly   = false,
        cursorTrail          = false,
        cursorTrailSize      = 24,
        cursorGCD            = false,
        cursorGCDSize        = 44,
        cursorCast           = false,
        cursorCastSize       = 40,
        -- QL-5..8
        bloodlustTracker     = false,
        bloodlustSize        = 40,
        autoLog              = false,
        logRaid              = true,
        logLFR               = false,
        logHeroicDungeon     = true,
        logScenario          = false,
        logChallenge         = true,
        logDelayStop         = true,
        shifter              = false,
        trainAllButton       = true,
    },
}

local floor, format = math.floor, string.format
local function cfg(k) return ns.db and ns.db.profile[k] end
ns.cfg = cfg

local function L(s) return (OUI.L and OUI.L(s)) or s end
local function fontPath() return (OUI.GetFontPath and OUI.GetFontPath()) or STANDARD_TEXT_FONT end
local function accentCol() local a = OUI.ACCENT or {}; return a.r or 1, a.g or 0.8, a.b or 0.3 end
local function msg(text) print("|cffD9A441OUI|r: " .. text) end

-- ---------------------------------------------------------------------------
--  Suppress Lua errors (drives the same CVar as Blizzard's "Display Lua
--  Errors" option, so it is fully reversible)
-- ---------------------------------------------------------------------------
local function applyLuaErrors()
    pcall(SetCVar, "scriptErrors", cfg("suppressLuaErrors") and "0" or "1")
end

-- ---------------------------------------------------------------------------
--  Hide the "screenshot captured" confirmation. The modern client can surface
--  it via ActionStatus_DisplayMessage, via UIErrorsFrame, or via the
--  ActionStatus frame directly -- we cover all three, each gated on the flag.
-- ---------------------------------------------------------------------------
local function isShotMsg(text)
    return text and (text == SCREENSHOT_SUCCESS or text == SCREENSHOT_FAILURE)
end

local function setupScreenshot()
    if QL._ssDone then return end
    QL._ssDone = true

    -- Source-level suppression where the text matches exactly (cleanest, no flash)
    if type(ActionStatus_DisplayMessage) == "function" then
        local orig = ActionStatus_DisplayMessage
        ActionStatus_DisplayMessage = function(text, ...)
            if cfg("hideScreenshotMsg") and isShotMsg(text) then return end
            return orig(text, ...)
        end
    end
    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        local orig = UIErrorsFrame.AddMessage
        UIErrorsFrame.AddMessage = function(self, msg, ...)
            if cfg("hideScreenshotMsg") and isShotMsg(msg) then return end
            return orig(self, msg, ...)
        end
    end

    -- Backstop (text-independent): on a screenshot, keep the ActionStatus frame
    -- hidden for a short window. A single Hide missed the first screenshot
    -- (the frame fades/holds over several frames); a brief ticker covers it and
    -- works regardless of which function set the message or its exact text.
    local f = CreateFrame("Frame")
    QL._ssFrame = f
    f:RegisterEvent("SCREENSHOT_SUCCEEDED")
    f:RegisterEvent("SCREENSHOT_FAILED")
    f:SetScript("OnEvent", function()
        if not cfg("hideScreenshotMsg") then return end
        if QL._ssTicker then QL._ssTicker:Cancel() end
        QL._ssTicker = C_Timer.NewTicker(0.03, function()
            if ActionStatus then ActionStatus:Hide() end
            if _G.ActionStatusText and _G.ActionStatusText.SetText then _G.ActionStatusText:SetText("") end
        end, 30)  -- ~0.9s, covers the show/fade/hold
    end)
end

-- ---------------------------------------------------------------------------
--  Skip cinematics / movies automatically
-- ---------------------------------------------------------------------------
local function setupCinematics()
    if QL._cinFrame then return end
    local f = CreateFrame("Frame")
    QL._cinFrame = f
    f:RegisterEvent("CINEMATIC_START")
    f:RegisterEvent("PLAY_MOVIE")
    f:SetScript("OnEvent", function(_, ev)
        if not cfg("skipCinematics") then return end
        if ev == "CINEMATIC_START" then
            if CanCancelScene and CanCancelScene() then pcall(CancelScene)
            else pcall(StopCinematic) end
        elseif ev == "PLAY_MOVIE" then
            if MovieFrame then MovieFrame:Hide() end
            if GameMovieFinished then pcall(GameMovieFinished) end
        end
    end)
end

-- ---------------------------------------------------------------------------
--  Announce instance resets to the group
-- ---------------------------------------------------------------------------
local resetPattern
local function buildResetPattern()
    local s = INSTANCE_RESET_SUCCESS or "%s has been reset."
    s = s:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1") -- escape magic chars
    s = s:gsub("%%%%s", "(.+)")                        -- the escaped %s -> capture
    resetPattern = "^" .. s .. "$"
end

local function onSystemMessage(_, msg)
    if not cfg("announceInstanceReset") or not msg then return end
    if not resetPattern then buildResetPattern() end
    if msg:match(resetPattern) then
        local chan = IsInRaid() and "RAID" or (IsInGroup() and "PARTY")
        if chan then SendChatMessage(msg, chan) end
    end
end

-- ---------------------------------------------------------------------------
--  Hide the Blizzard party / raid-manager panel (when OUI frames are in use)
-- ---------------------------------------------------------------------------
local function partyFrames()
    local t = { CompactRaidFrameManager, CompactRaidFrameContainer }
    for i = 1, 4 do t[#t + 1] = _G["PartyMemberFrame" .. i] end
    return t
end

local function applyHidePartyPanel()
    local on = cfg("hidePartyPanel")
    for _, f in ipairs(partyFrames()) do
        if f then
            if on and not f._ouiPartyHook then
                f._ouiPartyHook = true
                f:HookScript("OnShow", function(s)
                    if cfg("hidePartyPanel") and not InCombatLockdown() then s:Hide() end
                end)
            end
            if not InCombatLockdown() then
                if on then f:Hide() else f:Show() end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
--  Auto repair on vendor visit (optionally from guild bank funds)
-- ---------------------------------------------------------------------------
local function onMerchantShow()
    if not cfg("autoRepair") then return end
    if not (CanMerchantRepair and CanMerchantRepair()) then return end
    local cost, canRepair = GetRepairAllCost()
    if not (canRepair and cost and cost > 0) then return end

    local gw = GetGuildBankWithdrawMoney and GetGuildBankWithdrawMoney() or 0
    local useGuild = cfg("autoRepairGuild") and IsInGuild() and CanGuildBankRepair and CanGuildBankRepair()
        and (gw == -1 or cost <= gw)

    if not useGuild and (GetMoney() or 0) < cost then
        msg("|cffff6060" .. (L and L("Not enough money to repair.") or "Not enough money to repair.") .. "|r")
        return
    end

    RepairAllItems(useGuild)
    if useGuild then
        C_Timer.After(0.5, function()
            local rc = GetRepairAllCost()
            if rc and rc > 0 and (GetMoney() or 0) >= rc then RepairAllItems(false) end
        end)
    end
    local moneyStr = GetCoinTextureString and GetCoinTextureString(cost) or tostring(cost)
    msg((L and L("Repaired all items for ") or "Repaired all items for ") .. moneyStr
        .. (useGuild and " (" .. (L and L("guild bank") or "guild bank") .. ")" or ""))
end

-- ---------------------------------------------------------------------------
--  Quick loot: instantly loot everything on LOOT_READY (modifier bypasses)
-- ---------------------------------------------------------------------------
local function setupQuickLoot()
    if QL._lootFrame then return end
    local f = CreateFrame("Frame")
    QL._lootFrame = f
    f:RegisterEvent("LOOT_READY")
    f:SetScript("OnEvent", function()
        if not cfg("quickLoot") then return end
        if IsModifiedClick and IsModifiedClick("AUTOLOOTTOGGLE") then return end
        for i = GetNumLootItems(), 1, -1 do LootSlot(i) end
    end)
end

-- ---------------------------------------------------------------------------
--  Auto-open containers (right-click-to-open items in bags)
-- ---------------------------------------------------------------------------
local scanTip
local openFailed = {}
local opening = false

local function isOpenable(bag, slot)
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "OUIQoLScanTooltip", nil, "GameTooltipTemplate")
    end
    scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    local ok = pcall(scanTip.SetBagItem, scanTip, bag, slot)
    if not ok then return false end
    for i = 1, scanTip:NumLines() do
        local fs = _G["OUIQoLScanTooltipTextLeft" .. i]
        if fs and fs:GetText() == ITEM_OPENABLE then return true end
    end
    return false
end

local function autoOpenScan()
    if not cfg("autoOpenContainers") or opening or InCombatLockdown() then return end
    if not (C_Container and C_Container.GetContainerNumSlots) then return end
    for bag = 0, NUM_BAG_SLOTS do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID and not info.isLocked
                and not openFailed[info.itemID] and isOpenable(bag, slot) then
                opening = true
                local id, cnt = info.itemID, info.stackCount or 1
                C_Container.UseContainerItem(bag, slot)
                C_Timer.After(0.5, function()
                    local after = C_Container.GetContainerItemInfo(bag, slot)
                    if after and after.itemID == id and (after.stackCount or 1) >= cnt then
                        openFailed[id] = true -- couldn't open (needs a key, etc.)
                    end
                    opening = false
                    autoOpenScan()
                end)
                return
            end
        end
    end
end

-- ---------------------------------------------------------------------------
--  Auto-fill the "type DELETE" confirmation box
-- ---------------------------------------------------------------------------
local function setupDeleteFill()
    if QL._deleteHooked then return end
    QL._deleteHooked = true
    for i = 1, (STATICPOPUP_NUMDIALOGS or 4) do
        local popup = _G["StaticPopup" .. i]
        if popup and popup.Show then
            hooksecurefunc(popup, "Show", function(self)
                if not cfg("autoFillDelete") then return end
                if self.which ~= "DELETE_GOOD_ITEM" and self.which ~= "DELETE_GOOD_QUEST_ITEM" then return end
                local eb = self.editBox or self.EditBox or (self.GetEditBox and self:GetEditBox())
                if eb then eb:SetText(DELETE_ITEM_CONFIRM_STRING or "DELETE"); eb:SetFocus() end
            end)
        end
    end
end

-- ---------------------------------------------------------------------------
--  Register a widget with the suite-wide /ouimove unlock system.
--  Position is stored as a CENTER offset from the screen centre, and the
--  frame is anchored by its CENTER so growing/scaling stays put.
-- ---------------------------------------------------------------------------
local function placeWidget(f)
    local p = ns.db.profile[f._prefix .. "Pos"] or {}
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", p.x or f._defX or 0, p.y or f._defY or 0)
end

local function registerWidgetMover(f, label, isHiddenFn)
    OUI:RegisterUnlockElements({ OUI.MakeUnlockElement({
        key      = "OUIQoL_" .. f._prefix,
        label    = label,
        group    = "QoL",
        getFrame = function() return f end,
        getSize  = function() return f:GetWidth(), f:GetHeight() end,
        isHidden = isHiddenFn,
        savePos  = function(_, _, _, x, y)
            ns.db.profile[f._prefix .. "Pos"] = { x = floor(x + 0.5), y = floor(y + 0.5) }
            placeWidget(f) -- follow the drag live, don't wait for lock
        end,
        applyPos = function() placeWidget(f) end,
    }) })
end

-- ---------------------------------------------------------------------------
--  Styled info container (background + border, stacked text lines, scalable)
-- ---------------------------------------------------------------------------
local PAD = 6

local function resolveBG(prefix)
    local p = ns.db.profile
    local c = p[prefix .. "BgColor"]
    if p[prefix .. "BgOverride"] and c then return c[1], c[2], c[3], c[4] or 1 end
    local ink = (OUI._palette and OUI._palette.INK) or { 0.078, 0.067, 0.043 }
    return ink[1], ink[2], ink[3], 0.9
end

local function resolveText(prefix)
    local p = ns.db.profile
    local c = p[prefix .. "TextColor"]
    if p[prefix .. "TextOverride"] and c then return c[1], c[2], c[3], c[4] or 1 end
    local r, g, b = accentCol()
    return r, g, b, 1
end

local function makeContainer(name, prefix, defX, defY)
    local f = CreateFrame("Frame", name, UIParent)
    f._prefix = prefix
    f._defX, f._defY = defX, defY
    f._lines = {}
    f:SetSize(80, 28)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    if OUI.PP and OUI.PP.CreateBorder then
        OUI.PP.CreateBorder(f, 0, 0, 0, 0.9)
        local brd = (OUI._palette and OUI._palette.BRD) or { 0.227, 0.192, 0.125 }
        if OUI.PP.SetBorderColor then OUI.PP.SetBorderColor(f, brd[1], brd[2], brd[3], 1) end
    end
    placeWidget(f)
    return f
end

-- Lay out a vertical stack of strings inside a container, auto-sizing it.
-- "Size" is applied via the font scale (not SetScale) so the CENTER-anchored
-- container grows symmetrically and never drifts when resized.
local function setLines(f, lines, baseSize)
    local tr, tg, tb, ta = resolveText(f._prefix)
    local fp = fontPath()
    local scale = ns.db.profile[f._prefix .. "Scale"] or 1
    local fontSize = floor(baseSize * scale + 0.5)
    local lineH = fontSize + 4
    local maxW, y = 0, -PAD
    for i, text in ipairs(lines) do
        local fs = f._lines[i]
        if not fs then fs = f:CreateFontString(nil, "OVERLAY"); f._lines[i] = fs end
        fs:SetFont(fp, fontSize, "OUTLINE")
        fs:SetText(text)
        fs:SetTextColor(tr, tg, tb, ta)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
        fs:Show()
        local w = fs:GetStringWidth()
        if w > maxW then maxW = w end
        y = y - lineH
    end
    for i = #lines + 1, #f._lines do f._lines[i]:Hide() end
    local h = #lines * lineH - 4
    f:SetSize(maxW + PAD * 2, h + PAD * 2)
    f.bg:SetColorTexture(resolveBG(f._prefix))
end

-- ---------------------------------------------------------------------------
--  FPS / latency container (one value per line)
-- ---------------------------------------------------------------------------
local fpsFrame
local function buildFPS()
    if fpsFrame then return fpsFrame end
    local f = makeContainer("OUIQoLFPS", "fps", 0, -150)
    f._baseSize = 13
    f:SetScript("OnUpdate", function(self, elapsed)
        self._t = (self._t or 0) + elapsed
        if self._t < 1 then return end
        self._t = 0
        local lines = {}
        if cfg("showFPS") then lines[#lines + 1] = floor(GetFramerate() + 0.5) .. " fps" end
        if cfg("showLocalMS") or cfg("showWorldMS") then
            local _, _, lh, lw = GetNetStats()
            if cfg("showLocalMS") then lines[#lines + 1] = (lh or 0) .. " " .. L("ms (home)") end
            if cfg("showWorldMS") then lines[#lines + 1] = (lw or 0) .. " " .. L("ms (world)") end
        end
        self._lastLines = lines
        setLines(self, lines, self._baseSize)
    end)
    registerWidgetMover(f, L("FPS / Latency"),
        function() return not (cfg("showFPS") or cfg("showLocalMS") or cfg("showWorldMS")) end)
    fpsFrame = f
    return f
end

-- ---------------------------------------------------------------------------
--  Secondary stats container (Crit / Haste / Mastery, one per line)
-- ---------------------------------------------------------------------------
local statsFrame
local function buildStats()
    if statsFrame then return statsFrame end
    local f = makeContainer("OUIQoLStats", "stats", 0, -180)
    f._baseSize = 13
    f:SetScript("OnUpdate", function(self, elapsed)
        self._t = (self._t or 0) + elapsed
        if self._t < 0.5 then return end
        self._t = 0
        local crit = (GetCritChance and GetCritChance("player")) or 0
        local haste = (UnitSpellHaste and UnitSpellHaste("player")) or 0
        local mastery = (GetMasteryEffect and GetMasteryEffect()) or 0
        self._lastLines = {
            format("%s %.1f%%", L("Crit"), crit),
            format("%s %.1f%%", L("Haste"), haste),
            format("%s %.1f%%", L("Mastery"), mastery),
        }
        setLines(self, self._lastLines, self._baseSize)
    end)
    registerWidgetMover(f, L("Secondary Stats"),
        function() return not cfg("showSecondaryStats") end)
    statsFrame = f
    return f
end

-- ---------------------------------------------------------------------------
--  Low-durability warning
-- ---------------------------------------------------------------------------
local function minDurabilityPct()
    local lowest = 100
    for slot = 1, 18 do
        local cur, max = GetInventoryItemDurability(slot)
        if cur and max and max > 0 then
            local pct = cur / max * 100
            if pct < lowest then lowest = pct end
        end
    end
    return lowest
end

local durFrame
local function buildDur()
    if durFrame then return durFrame end
    local f = CreateFrame("Frame", "OUIQoLDur", UIParent)
    f._prefix, f._defX, f._defY, f._lines = "dur", 0, 200, {}
    f:SetSize(220, 24)
    local fs = f:CreateFontString(nil, "OVERLAY")
    fs:SetFont(fontPath(), 16, "OUTLINE")
    fs:SetPoint("CENTER")
    fs:SetTextColor(1, 0.3, 0.3)
    f._fs = fs
    placeWidget(f)
    registerWidgetMover(f, L("Low Durability Warning"), function() return not cfg("lowDurabilityWarn") end)
    durFrame = f
    return f
end

local function checkDurability()
    if not cfg("lowDurabilityWarn") then
        if durFrame then durFrame:Hide() end
        return
    end
    local f = buildDur()
    local pct = minDurabilityPct()
    if pct <= (cfg("lowDurabilityPct") or 20) then
        f._fs:SetText(format(L("Low Durability: %d%%"), floor(pct + 0.5)))
        f:Show()
    else
        f:Hide()
    end
end

-- ---------------------------------------------------------------------------
--  Re-apply widget visibility from settings
-- ---------------------------------------------------------------------------
local function restyle(f)
    if not f then return end
    if f._lastLines then
        setLines(f, f._lastLines, f._baseSize or 13)
    elseif f.bg then
        f.bg:SetColorTexture(resolveBG(f._prefix))
    end
end

local function refreshWidgets()
    if cfg("showFPS") or cfg("showLocalMS") or cfg("showWorldMS") then buildFPS():Show()
    elseif fpsFrame then fpsFrame:Hide() end

    if cfg("showSecondaryStats") then buildStats():Show()
    elseif statsFrame then statsFrame:Hide() end

    restyle(fpsFrame)
    restyle(statsFrame)
    checkDurability()
end

-- ---------------------------------------------------------------------------
--  Class trainer: "Train All" button (buys every available service)
-- ---------------------------------------------------------------------------
local function spawnTrainAll()
    if not cfg("trainAllButton") then return end
    if not (ClassTrainerFrame and ClassTrainerTrainButton) then return end
    if QL._trainBtn then return end
    local b = CreateFrame("Button", "OUIQoLTrainAll", ClassTrainerFrame, "MagicButtonTemplate")
    QL._trainBtn = b
    b:SetText(L("Train All"))
    b:SetHeight(ClassTrainerTrainButton:GetHeight() or 22)
    b:SetWidth(80)
    b:SetPoint("RIGHT", ClassTrainerTrainButton, "LEFT", -2, 0)
    b:SetScript("OnClick", function()
        if not GetNumTrainerServices then return end
        for i = 1, GetNumTrainerServices() do
            local _, _, available = GetTrainerServiceInfo(i)
            if available == "available" then BuyTrainerService(i) end
        end
    end)
    local function refresh()
        if not cfg("trainAllButton") then b:Hide(); return end
        b:Show()
    end
    if not QL._trainHooked and type(ClassTrainerFrame_Update) == "function" then
        QL._trainHooked = true
        hooksecurefunc("ClassTrainerFrame_Update", refresh)
    end
    refresh()
end

local function setupTrainAll()
    if QL._trainFrame then return end
    local f = CreateFrame("Frame")
    QL._trainFrame = f
    f:RegisterEvent("ADDON_LOADED")
    f:SetScript("OnEvent", function(_, _, addon)
        if addon == "Blizzard_TrainerUI" then spawnTrainAll() end
    end)
    if IsAddOnLoaded and IsAddOnLoaded("Blizzard_TrainerUI") then spawnTrainAll() end
end

-- ---------------------------------------------------------------------------
--  Apply / lifecycle
-- ---------------------------------------------------------------------------
function ns.RefreshSettings()
    applyLuaErrors()
    applyHidePartyPanel()
    refreshWidgets()
    if ns.RefreshCursor then ns.RefreshCursor() end
    if ns.RefreshBloodlust then ns.RefreshBloodlust() end
    if ns.RefreshAutoLogging then ns.RefreshAutoLogging() end
end

function QL:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("OldschoolUIQoLDB", defaults, true)
    ns.db = self.db
end

function QL:OnEnable()
    if OUI.IsModuleEnabled and not OUI:IsModuleEnabled("OUI_QoL") then return end
    setupScreenshot()
    setupCinematics()
    setupQuickLoot()
    setupDeleteFill()
    applyLuaErrors()
    -- build the info widgets up-front so they register with /ouimove
    buildFPS(); buildStats(); buildDur()
    self:RegisterEvent("CHAT_MSG_SYSTEM", onSystemMessage)
    self:RegisterEvent("MERCHANT_SHOW", onMerchantShow)
    self:RegisterEvent("BAG_UPDATE_DELAYED", autoOpenScan)
    self:RegisterEvent("PLAYER_LOGIN", function()
        applyHidePartyPanel()
    end)
    self:RegisterEvent("GROUP_ROSTER_UPDATE", applyHidePartyPanel)
    self:RegisterEvent("UPDATE_INVENTORY_DURABILITY", checkDurability)
    self:RegisterEvent("PLAYER_ENTERING_WORLD", checkDurability)
    applyHidePartyPanel()
    refreshWidgets()
    if ns.SetupCursor then ns.SetupCursor() end
    setupTrainAll()
    if ns.SetupBloodlust then ns.SetupBloodlust() end
    if ns.SetupAutoLogging then ns.SetupAutoLogging() end
    if ns.SetupShifter then ns.SetupShifter() end

    SLASH_OUIQOLRESET1 = "/ouiqolreset"
    SlashCmdList["OUIQOLRESET"] = function()
        if ns.ResetShifterPositions then ns.ResetShifterPositions() end
        msg(L("Frame mover positions reset. /reload to restore default placement."))
    end
end

-------------------------------------------------------------------------------
--  OUI_LootRoll_BonusRolls.lua
--  Character-specific bonus-roll history + gold/item ratio.
--
--  Bonus rolls (Elder Charm / Mogu Rune / Warforged Seal) are a MoP feature.
--  Availability is signalled by SPELL_CONFIRMATION_PROMPT (confirmType == bonus
--  roll); the result arrives via BONUS_ROLL_RESULT(typeIdentifier, itemLink,
--  quantity, ...) where typeIdentifier is "item" / "money" / "currency".
--  History is stored per-character in OldschoolUILootRollCharDB (declared
--  ## SavedVariablesPerCharacter in the TOC) -- never shared across characters.
-------------------------------------------------------------------------------

local addonName, ns = ...

local GetTime          = GetTime
local time             = time
local UnitName         = UnitName
local UnitExists       = UnitExists
local GetSpellInfo     = GetSpellInfo
local tinsert          = table.insert
local tremove          = table.remove

local MAX_HISTORY = 200  -- hard cap on stored entries (UI shows "last X")

-- Bonus-roll confirmation type (LE_SPELL_CONFIRMATION_PROMPT_TYPE_BONUS_ROLL).
local BONUS_ROLL_CONFIRM_TYPE = LE_SPELL_CONFIRMATION_PROMPT_TYPE_BONUS_ROLL
    or (Enum and Enum.SpellConfirmationPromptType and Enum.SpellConfirmationPromptType.BonusRoll)
    or 1

-------------------------------------------------------------------------------
--  Per-character store
-------------------------------------------------------------------------------
local function CDB()
    if type(OldschoolUILootRollCharDB) ~= "table" then OldschoolUILootRollCharDB = {} end
    local c = OldschoolUILootRollCharDB
    if type(c.bonusRolls) ~= "table" then c.bonusRolls = {} end
    return c
end

local function History()
    return CDB().bonusRolls
end

-- Account-wide settings (preferences) live on the lootRoll profile table.
local function S()
    return ns.LR_GetSettings and ns.LR_GetSettings() or nil
end

-------------------------------------------------------------------------------
--  Debug tracker (ring buffer) -- helps diagnose why our own roll button
--  doesn't fire. Inspect with /ouibonus log.
-------------------------------------------------------------------------------
local bonusLog = {}
local function LogBonus(fmt, ...)
    local line = select("#", ...) > 0 and fmt:format(...) or fmt
    bonusLog[#bonusLog + 1] = ("|cff888888[%s]|r %s"):format(date("%H:%M:%S"), line)
    if #bonusLog > 80 then table.remove(bonusLog, 1) end
end
ns.LR_LogBonus = LogBonus

-- snapshot of the native BonusRollFrame + its Roll button
local function LogNativeState(tag)
    local b = _G.BonusRollFrame
    if not b then LogBonus("%s BonusRollFrame=nil", tag); return end
    local shown = b.IsShown and b:IsShown()
    local reg   = b.IsEventRegistered and b:IsEventRegistered("SPELL_CONFIRMATION_PROMPT")
    local pt    = b.GetPoint and select(1, b:GetPoint())
    local alpha = b.GetAlpha and b:GetAlpha()
    local pf    = b.PromptFrame
    local rb    = pf and (pf.Roll or pf.RollButton or pf.rollButton)
    local rbName = rb and rb.GetName and rb:GetName()
    LogBonus("%s shown=%s reg=%s point=%s alpha=%.2f promptFrame=%s rollBtn=%s(%s) rbShown=%s",
        tag, tostring(shown), tostring(reg), tostring(pt), tonumber(alpha) or -1,
        tostring(pf ~= nil), tostring(rb ~= nil), tostring(rbName or "?"),
        tostring(rb and rb.IsShown and rb:IsShown()))
end

-- prefer Blizzard's own bonus-roll UI? (default true -- our panel is opt-in)
local function UseNativeRoll()
    local s = S()
    return (not s) or s.useNativeBonusRoll ~= false
end

-------------------------------------------------------------------------------
--  Boss context tracking
-------------------------------------------------------------------------------
local bonusRegDone      -- guard: register BonusRollFrame once
local bonusPosHooked    -- guard: position BonusRollFrame once
local lastBoss          -- name of the most recent encounter
local lastBossAt = 0    -- GetTime() when it was recorded
local BOSS_WINDOW = 120 -- seconds an encounter name stays "current"

local function CurrentBoss()
    -- Prefer a recent ENCOUNTER_END name; fall back to the current target
    -- (world bosses are tap-based and may not fire ENCOUNTER_END).
    if lastBoss and (GetTime() - lastBossAt) <= BOSS_WINDOW then
        return lastBoss
    end
    if UnitExists("target") then
        local n = UnitName("target")
        if n and n ~= "" then return n end
    end
    return lastBoss  -- may be nil
end

-------------------------------------------------------------------------------
--  Recording
-------------------------------------------------------------------------------
-- Add one bonus-roll result to the per-character history.
-- typ: "item" | "money" | "currency" (from BONUS_ROLL_RESULT typeIdentifier)
local function Record(typ, link, qty, currencyID)
    local hist = History()
    local entry = {
        t    = time(),                 -- wall-clock for display
        boss = CurrentBoss() or "?",
        typ  = typ or "?",
        link = link,                   -- itemLink (item) or nil
        qty  = tonumber(qty) or 0,
        cur  = currencyID,             -- currencyID (currency) or nil
    }
    tinsert(hist, entry)
    -- Trim oldest beyond the cap.
    while #hist > MAX_HISTORY do tremove(hist, 1) end

    if ns.LR_OnBonusRecorded then ns.LR_OnBonusRecorded(entry) end
end

-------------------------------------------------------------------------------
--  Stats
-------------------------------------------------------------------------------
-- Returns: total, items, gold, currency, itemRatio (0..1 of all rolls that
-- awarded an item). Optional limit = only the last N entries.
function ns.LR_GetBonusStats(limit)
    local hist = History()
    local n = #hist
    local from = 1
    if limit and limit > 0 and n > limit then from = n - limit + 1 end
    local total, items, gold, cur = 0, 0, 0, 0
    for i = from, n do
        local e = hist[i]
        total = total + 1
        if e.typ == "item" then items = items + 1
        elseif e.typ == "money" then gold = gold + 1
        elseif e.typ == "currency" then cur = cur + 1 end
    end
    local ratio = total > 0 and (items / total) or 0
    return total, items, gold, cur, ratio
end

-- Returns the history list (oldest..newest). Read-only; do not mutate.
function ns.LR_GetBonusHistory()
    return History()
end

function ns.LR_ClearBonusHistory()
    local c = CDB()
    wipe(c.bonusRolls)
    if ns.LR_OnBonusRecorded then ns.LR_OnBonusRecorded(nil) end
end

-------------------------------------------------------------------------------
--  Announcer (chat + raid warning + sound) -- shared by reminders & wishlist
-------------------------------------------------------------------------------
function ns.LR_Announce(msg, sub)
    if not msg then return end
    print("|cffD9A441OldschoolUI:|r " .. msg)
    if sub then print("|cffD9A441OldschoolUI:|r |cffaaaaaa" .. sub .. "|r") end
    if PlaySound then PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959) end
    if RaidNotice_AddMessage and RaidWarningFrame then
        RaidNotice_AddMessage(RaidWarningFrame, msg,
            ChatTypeInfo and ChatTypeInfo.RAID_WARNING or { r = 1, g = 0.5, b = 0 })
        if sub then
            RaidNotice_AddMessage(RaidWarningFrame, sub, { r = 0.7, g = 0.7, b = 0.7 })
        end
    end
end

-------------------------------------------------------------------------------
--  Bonus-roll reminder + auto-ignore (wishlist-driven)
-------------------------------------------------------------------------------
-- When a bonus roll becomes available:
--   * bonusReminder   -> if the current boss still has an un-obtained wish at
--                        the current difficulty, announce it (lists the items).
--   * bonusAutoIgnore -> if there is NO open wish for this boss/difficulty,
--                        decline the prompt. Guarded: only acts while the
--                        wishlist has at least one open wish overall.
local function HandleBonusPrompt(spellID, boss)
    local s = S(); if not s then return end
    local bucket = ns.LR_CurrentBucket and ns.LR_CurrentBucket() or nil
    local wanted = (ns.LR_WantedAtBoss and boss) and ns.LR_WantedAtBoss(boss, bucket) or {}
    local hasMatch = #wanted > 0

    if s.bonusAutoIgnore and not hasMatch
       and ns.LR_HasOpenWishes and ns.LR_HasOpenWishes() then
        if DeclineSpellConfirmationPrompt then DeclineSpellConfirmationPrompt(spellID) end
        return true   -- prompt was auto-declined; caller should not show the window
    end

    if s.bonusReminder and hasMatch then
        local names = {}
        for _, e in ipairs(wanted) do names[#names + 1] = e.link or e.itemName or tostring(e.itemID) end
        local head = boss
            and OldschoolUI.Lf("Bonus roll: wish item at %1$s!", boss)
            or  ns.LR_T("Bonus roll: wish item here!")
        ns.LR_Announce(head, table.concat(names, ", "))
    end
    return false
end
ns.LR_HandleBonusPrompt = HandleBonusPrompt
ns.LR_CurrentBoss = CurrentBoss

-------------------------------------------------------------------------------
--  Visible roll panel (secure click-forwarding to Blizzard's Roll button)
--
--  This client builds BonusRollFrame and its Roll button correctly (the button
--  is shown and functional) but never renders the frame visibly. We surface our
--  own panel and forward its click to Blizzard's native Roll button through a
--  SecureActionButton (type="click"). The actual AcceptSpellConfirmationPrompt
--  call therefore happens inside Blizzard's own secure handler -- we only
--  trigger its button, we never call the protected function ourselves.
-------------------------------------------------------------------------------
local rollPanel          -- our visible panel (lazy-built)
local rollExpiresAt = 0  -- GetTime() deadline for the countdown
local rollWiredTo        -- native Roll button our secure forward is wired to (set OOC)

local function FindNativeRollButton()
    local brf = _G.BonusRollFrame
    local pf  = brf and brf.PromptFrame
    return pf and (pf.Roll or pf.RollButton or pf.rollButton)
end

local function BuildRollPanel()
    if rollPanel then return rollPanel end
    local ACC  = OldschoolUI.ACCENT or { r = 0.85, g = 0.64, b = 0.25 }
    local font = (OldschoolUI.GetFontPath and OldschoolUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF"
    local LT   = ns.LR_T or function(s) return s end

    local f = CreateFrame("Frame", "OUIBonusRollPanel", UIParent)
    f:SetSize(230, 78)
    f:SetPoint("TOP", UIParent, "TOP", 0, -190)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:Hide()

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f)
    bg:SetColorTexture(0.06, 0.06, 0.07, 0.92)

    if OldschoolUI.PP and OldschoolUI.PP.CreateBorder then
        OldschoolUI.PP.CreateBorder(f, ACC.r, ACC.g, ACC.b, 1, 1)
    end

    local title = f:CreateFontString(nil, "OVERLAY")
    title:SetFont(font, 13, "OUTLINE")
    title:SetPoint("TOP", f, "TOP", 0, -8)
    title:SetTextColor(ACC.r, ACC.g, ACC.b)
    title:SetText(LT("Bonus Roll"))

    local timer = f:CreateFontString(nil, "OVERLAY")
    timer:SetFont(font, 11, "OUTLINE")
    timer:SetPoint("TOP", title, "BOTTOM", 0, -3)
    timer:SetTextColor(0.8, 0.8, 0.8)
    f.timer = timer

    -- Secure click-forwarding Roll button.
    local roll = CreateFrame("Button", "OUIBonusRollGo", f, "SecureActionButtonTemplate")
    roll:SetSize(200, 26)
    roll:SetPoint("BOTTOM", f, "BOTTOM", 0, 8)
    roll:RegisterForClicks("AnyUp", "AnyDown")

    local rbg = roll:CreateTexture(nil, "BACKGROUND")
    rbg:SetAllPoints(roll)
    rbg:SetColorTexture(ACC.r * 0.30, ACC.g * 0.30, ACC.b * 0.30, 0.95)
    local rtx = roll:CreateFontString(nil, "OVERLAY")
    rtx:SetFont(font, 13, "OUTLINE")
    rtx:SetPoint("CENTER")
    rtx:SetTextColor(1, 0.92, 0.7)
    rtx:SetText(LT("Roll"))
    if OldschoolUI.PP and OldschoolUI.PP.CreateBorder then
        OldschoolUI.PP.CreateBorder(roll, ACC.r, ACC.g, ACC.b, 1, 1)
    end
    roll:SetScript("OnEnter", function() rbg:SetColorTexture(ACC.r * 0.5, ACC.g * 0.5, ACC.b * 0.5, 1) end)
    roll:SetScript("OnLeave", function() rbg:SetColorTexture(ACC.r * 0.30, ACC.g * 0.30, ACC.b * 0.30, 0.95) end)
    roll:SetScript("PostClick", function()
        LogBonus("PostClick: our Roll button clicked (clickbutton=%s)",
            tostring(roll:GetAttribute("clickbutton")))
        f:Hide(); rollExpiresAt = 0
    end)
    f.roll = roll

    f:SetScript("OnUpdate", function(self)
        if rollExpiresAt <= 0 then return end
        local left = rollExpiresAt - GetTime()
        if left <= 0 then self:Hide(); rollExpiresAt = 0; return end
        self.timer:SetText(("%.0fs"):format(left))
    end)

    rollPanel = f
    return f
end

-- Pre-wire (OUT OF COMBAT) our secure forward button to the native Roll
-- button. SetAttribute is blocked in combat, and bonus-roll prompts almost
-- always arrive in combat -- so we wire ahead of time; the in-combat prompt
-- then only needs to :Show() the (already-wired) panel, and clicking forwards.
local function WireRollButton()
    if InCombatLockdown() then return false end
    local rb = FindNativeRollButton()
    if not rb then return false end
    local f = BuildRollPanel()
    if rollWiredTo ~= rb then
        f.roll:SetAttribute("type", "click")
        f.roll:SetAttribute("clickbutton", rb)
        rollWiredTo = rb
        LogBonus("WireRollButton: clickbutton pre-wired OOC to native Roll button")
    end
    return true
end
ns.LR_WireBonusRoll = WireRollButton

local function ShowRollPanel(duration)
    local f  = BuildRollPanel()
    local rb = FindNativeRollButton()
    local combat = InCombatLockdown()
    LogBonus("ShowRollPanel: nativeRollBtn=%s combat=%s preWired=%s",
        tostring(rb ~= nil), tostring(combat), tostring(rollWiredTo ~= nil))
    if not combat then
        -- OOC: wire now (covers the case where this prompt arrived out of combat)
        WireRollButton()
    elseif not rollWiredTo then
        -- in combat and never pre-wired -> can't SetAttribute now; button is inert
        LogBonus("  -> in combat & not pre-wired: button inert this prompt (native fallback advised)")
    end
    if not rb and not rollWiredTo then
        LogBonus("  -> ABORT: no native Roll button to forward to")
        return false
    end
    if InCombatLockdown() then
        -- f hosts the secure forward button as a child; :Show() on it in combat is
        -- a blocked protected action. Fall back to Blizzard's native frame.
        LogBonus("  -> in combat: custom panel can't Show (secure child); native fallback")
        ShowNativeRoll()
        return false
    end
    rollExpiresAt = GetTime() + ((duration and duration > 0) and duration or 30)
    f:Show()
    return true
end

local hidePending = false
local function HideRollPanel()
    rollExpiresAt = 0
    if not rollPanel then return end
    -- rollPanel hosts Blizzard's secure Roll button, so it is protected: hiding it
    -- in combat (or inside a secure execution) is BLOCKED. Defer to combat end.
    if InCombatLockdown() then hidePending = true; return end
    hidePending = false
    rollPanel:Hide()
end
ns.LR_HideBonusPanel = HideRollPanel

-- Taint-safe reskin of Blizzard's native BonusRollFrame so it matches OUI even for
-- in-combat prompts (where our own panel can't be shown). We add a STANDALONE
-- backdrop behind it (parented to UIParent, never a child of the secure frame),
-- dim the frame's own background chrome, and recolour the Roll/Pass buttons --
-- EXISTING regions/fonts only, no child frames on the secure frame/buttons, and
-- the structural pass runs OOC only. Blizzard keeps ownership of Show/Hide and the
-- secure Roll button.
local bonusBackdrop, nativeSkinned, nativeHooked
local function EnsureBonusBackdrop()
    if bonusBackdrop then return bonusBackdrop end
    local ACC = OldschoolUI.ACCENT or { r = 0.85, g = 0.64, b = 0.25 }
    local bd = CreateFrame("Frame", "OUIBonusRollBackdrop", UIParent)
    bd:Hide()
    local fill = bd:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints(bd)
    fill:SetColorTexture(0.06, 0.06, 0.07, 0.94)
    if OldschoolUI.PP and OldschoolUI.PP.CreateBorder then
        OldschoolUI.PP.CreateBorder(bd, ACC.r, ACC.g, ACC.b, 1, 1)
    end
    bonusBackdrop = bd
    return bd
end

local function PlaceBonusBackdrop()
    local b = _G.BonusRollFrame
    local bd = bonusBackdrop
    if not (b and bd and b:GetCenter()) then return end
    local cx, cy   = b:GetCenter()
    local ucx, ucy = UIParent:GetCenter()
    bd:ClearAllPoints()
    bd:SetPoint("CENTER", UIParent, "CENTER", cx - ucx, cy - ucy)
    bd:SetSize((b:GetWidth() or 230) + 14, (b:GetHeight() or 110) + 14)
    bd:SetFrameStrata(b:GetFrameStrata() or "DIALOG")
    bd:SetFrameLevel(math.max(0, (b:GetFrameLevel() or 1) - 1))
    bd:Show()
end

local function ReskinNativeBonusRoll()
    local b = _G.BonusRollFrame
    if not b then return end
    EnsureBonusBackdrop()
    -- keep the backdrop glued to the frame's lifecycle (hooks are taint-safe)
    if not nativeHooked then
        nativeHooked = true
        b:HookScript("OnShow", PlaceBonusBackdrop)
        b:HookScript("OnHide", function() if bonusBackdrop then bonusBackdrop:Hide() end end)
    end
    -- structural restyle: OOC only, once
    if nativeSkinned or InCombatLockdown() then
        if b:IsShown() then PlaceBonusBackdrop() end
        return
    end
    nativeSkinned = true
    local ACC = OldschoolUI.ACCENT or { r = 0.85, g = 0.64, b = 0.25 }
    -- dim the frame's own background/border chrome, keep ARTWORK/OVERLAY (coin,
    -- icon, glow). One-time layer dump helps us refine after a real raid prompt.
    if b.GetRegions then
        local n, layers = select("#", b:GetRegions()), {}
        for i = 1, n do
            local r = select(i, b:GetRegions())
            if r and r.IsObjectType and r:IsObjectType("Texture") then
                local layer = r.GetDrawLayer and r:GetDrawLayer() or "?"
                layers[#layers + 1] = layer
                if layer == "BACKGROUND" or layer == "BORDER" then r:SetAlpha(0) end
            end
        end
        LogBonus("ReskinNative: regions=%d layers=%s pf=%s", n,
            table.concat(layers, ","), tostring(b.PromptFrame ~= nil))
    end
    -- Roll / Pass buttons: existing slices + font only
    local function styleBtn(btn)
        if not btn then return end
        for _, k in ipairs({ "Left", "Middle", "Right" }) do
            local t = btn[k]; if t and t.SetAlpha then t:SetAlpha(0) end
        end
        if btn.SetNormalTexture then pcall(btn.SetNormalTexture, btn, nil) end
        local fs = btn.GetFontString and btn:GetFontString()
        if fs then fs:SetTextColor(ACC.r, ACC.g, ACC.b) end
    end
    local pf = b.PromptFrame
    if pf then
        styleBtn(pf.Roll or pf.RollButton or pf.rollButton)
        styleBtn(pf.PassButton or pf.Pass or pf.passButton)
    end
    if b:IsShown() then PlaceBonusBackdrop() end
end
ns.LR_ReskinNativeBonusRoll = ReskinNativeBonusRoll

-- Surface Blizzard's own bonus-roll frame (its native, fully-secure Roll
-- button) instead of our forwarding panel. The frame handles the prompt via
-- its own registration; we only make sure it is on-screen and never show ours.
local function ShowNativeRoll()
    HideRollPanel()
    ReskinNativeBonusRoll()
    local b = _G.BonusRollFrame
    if b then
        if not InCombatLockdown() then
            if b.ClearAllPoints and (not (b.GetPoint and b:GetPoint())) then
                b:ClearAllPoints()
                b:SetPoint("TOP", UIParent, "TOP", 0, -200)
            end
            if b.SetAlpha then b:SetAlpha(1) end
            if b.Show then b:Show() end
        end
        -- In combat we must NOT call Show()/SetPoint() on the secure BonusRollFrame
        -- ourselves -- that is a blocked protected action. It is registered for
        -- SPELL_CONFIRMATION_PROMPT (see PLAYER_LOGIN) so Blizzard's own secure
        -- handler shows it, and it is pre-anchored at login so it is visible.
    end
    LogNativeState("ShowNativeRoll")
end

-------------------------------------------------------------------------------
--  Bonus rolls are presented and accepted by Blizzard's own BonusRollFrame
--  (AcceptSpellConfirmationPrompt is a protected action only its secure code
--  may call). We only track results and run the reminder / auto-ignore step.
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
--  Events
-------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("ENCOUNTER_END")
ev:RegisterEvent("BONUS_ROLL_RESULT")
ev:RegisterEvent("BONUS_ROLL_FAILED")
ev:RegisterEvent("SPELL_CONFIRMATION_PROMPT")
ev:RegisterEvent("SPELL_CONFIRMATION_TIMEOUT")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        CDB()  -- ensure the store exists
        -- This client does not register Blizzard's BonusRollFrame for the prompt
        -- itself (verified: it stays unregistered, so no roll UI ever appears), so
        -- we subscribe its native handler. The roll is still accepted by Blizzard's
        -- own secure Roll button -- we never call AcceptSpellConfirmationPrompt.
        local brf = _G.BonusRollFrame
        if brf and brf.RegisterEvent and not bonusRegDone then
            bonusRegDone = true
            for _, e in ipairs({ "SPELL_CONFIRMATION_PROMPT", "SPELL_CONFIRMATION_TIMEOUT" }) do
                pcall(brf.RegisterEvent, brf, e)
            end
        end
        -- This client never anchors BonusRollFrame (GetPoint() == nil), so it is
        -- invisible even though it is shown and fully built. Give it a position
        -- when it appears. SetPoint is a visual-only op and doesn't touch the
        -- spellID the native Roll button passes to AcceptSpellConfirmationPrompt.
        if brf and brf.HookScript and not bonusPosHooked then
            bonusPosHooked = true
            local function placeBonus(self)
                if self.GetPoint and self:GetPoint() then return end
                if InCombatLockdown() then return end
                self:ClearAllPoints()
                self:SetPoint("TOP", UIParent, "TOP", 0, -200)
            end
            brf:HookScript("OnShow", placeBonus)
            placeBonus(brf)
        end
        -- Pre-wire our secure forward button now (OOC). The native Roll button
        -- may not exist until the first prompt, so retry shortly after login.
        WireRollButton()
        ReskinNativeBonusRoll()
        if C_Timer and C_Timer.After then
            C_Timer.After(3, WireRollButton)
            C_Timer.After(8, WireRollButton)
            C_Timer.After(3, ReskinNativeBonusRoll)
            C_Timer.After(8, ReskinNativeBonusRoll)
        end
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        -- Leaving combat is our chance to (re)wire for the NEXT bonus-roll
        -- prompt, since SetAttribute is blocked while in combat.
        WireRollButton()
        ReskinNativeBonusRoll()
        if hidePending then hidePending = false; if rollPanel then rollPanel:Hide() end end
        return
    end

    if event == "ENCOUNTER_END" then
        local _, encounterName = ...
        if type(encounterName) == "string" and encounterName ~= "" then
            lastBoss = encounterName
            lastBossAt = GetTime()
        end
        return
    end

    if event == "BONUS_ROLL_RESULT" then
        HideRollPanel()
        local typeIdentifier, itemLink, quantity, _, _, _, currencyID = ...
        LogBonus("BONUS_ROLL_RESULT type=%s qty=%s", tostring(typeIdentifier), tostring(quantity))
        Record(typeIdentifier, itemLink, quantity, currencyID)
        return
    end

    if event == "BONUS_ROLL_FAILED" then
        HideRollPanel()
        LogBonus("BONUS_ROLL_FAILED")
        Record("money", nil, 0)
        return
    end

    if event == "SPELL_CONFIRMATION_PROMPT" then
        local spellID, confirmType, duration = ...
        LogBonus("SPELL_CONFIRMATION_PROMPT spellID=%s confirmType=%s dur=%s (bonusType=%s)",
            tostring(spellID), tostring(confirmType), tostring(duration), tostring(BONUS_ROLL_CONFIRM_TYPE))
        if confirmType == BONUS_ROLL_CONFIRM_TYPE then
            LogNativeState("on prompt")
            -- reminder / auto-ignore first; if it auto-declined, don't show anything
            local declined = HandleBonusPrompt(spellID, CurrentBoss())
            LogBonus("auto-declined=%s useNative=%s", tostring(declined), tostring(UseNativeRoll()))
            if not declined then
                if UseNativeRoll() or InCombatLockdown() then
                    -- our panel hosts Blizzard's secure Roll button as a child, so
                    -- :Show() on it is a protected action and is BLOCKED in combat.
                    -- Bonus prompts almost always arrive in combat -> use the native
                    -- frame, which Blizzard's own secure handler shows.
                    ShowNativeRoll()
                else
                    local dur = tonumber(duration)
                    if dur and dur > 1000 then dur = dur / 1000 end  -- ms -> s
                    ShowRollPanel((dur and dur > 0) and dur or 30)
                end
            end
        end
        return
    end

    if event == "SPELL_CONFIRMATION_TIMEOUT" then
        LogBonus("SPELL_CONFIRMATION_TIMEOUT")
        HideRollPanel()
        return
    end
end)

-------------------------------------------------------------------------------
--  Test / inspection slash command
-------------------------------------------------------------------------------
SLASH_OUILRBONUS1 = "/ouibonus"
SlashCmdList["OUILRBONUS"] = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local p = function(s) print("|cffD9A441OldschoolUI BonusRoll:|r " .. s) end
    if msg == "check" then
        p("BonusRollFrame exists: " .. tostring(_G.BonusRollFrame ~= nil)
            .. (_G.BonusRollFrame and (", shown: " .. tostring(_G.BonusRollFrame:IsShown())) or ""))
        if _G.BonusRollFrame and _G.BonusRollFrame.IsEventRegistered then
            p("  registered for prompt: " .. tostring(_G.BonusRollFrame:IsEventRegistered("SPELL_CONFIRMATION_PROMPT")))
        end
        local b = _G.BonusRollFrame
        if b then
            p(("  alpha=%.2f scale=%.2f w=%d h=%d"):format(
                b.GetAlpha and b:GetAlpha() or -1,
                b.GetEffectiveScale and b:GetEffectiveScale() or -1,
                math.floor((b.GetWidth and b:GetWidth()) or 0),
                math.floor((b.GetHeight and b:GetHeight()) or 0)))
            local point, _, _, ox, oy = b.GetPoint and b:GetPoint()
            p("  point: " .. tostring(point) .. " x=" .. math.floor(ox or 0) .. " y=" .. math.floor(oy or 0))
            local pf = b.PromptFrame
            local rb = pf and (pf.Roll or pf.RollButton or pf.rollButton)
            p("  PromptFrame: " .. tostring(pf ~= nil)
                .. "  rollButton: " .. tostring(rb ~= nil)
                .. (rb and ("  shown=" .. tostring(rb:IsShown())) or ""))
        end
        p("AcceptSpellConfirmationPrompt: " .. tostring(AcceptSpellConfirmationPrompt ~= nil)
            .. "  Decline: " .. tostring(DeclineSpellConfirmationPrompt ~= nil))
        p("GetSpellConfirmationPromptsInfo: " .. tostring(GetSpellConfirmationPromptsInfo ~= nil))
        if GetSpellConfirmationPromptsInfo then
            local ok, prompts = pcall(GetSpellConfirmationPromptsInfo)
            if ok and type(prompts) == "table" then
                p(("active prompts: %d"):format(#prompts))
            end
        end
        p("BONUS_ROLL_CONFIRM_TYPE = " .. tostring(BONUS_ROLL_CONFIRM_TYPE))
        return
    end
    if msg == "log" or msg == "log clear" then
        if msg == "log clear" then
            wipe(bonusLog)
            p("debug log cleared.")
            return
        end
        if #bonusLog == 0 then
            p("debug log empty. Trigger a bonus roll, then run /ouibonus log.")
        else
            p(("debug log (%d lines, newest last):"):format(#bonusLog))
            for i = 1, #bonusLog do print("  " .. bonusLog[i]) end
        end
        LogNativeState("now")
        print("  " .. bonusLog[#bonusLog])
        return
    end
    if msg == "native" or msg == "panel off" then
        local s = S(); if s then s.useNativeBonusRoll = true end
        p("switched to Blizzard's native bonus-roll button.")
        return
    end
    if msg == "ourpanel" or msg == "panel on" then
        local s = S(); if s then s.useNativeBonusRoll = false end
        local wired = WireRollButton()
        p("switched to the OUI bonus-roll panel." ..
            (wired and " (button pre-wired)" or " (will wire out of combat)"))
        return
    end
    if msg == "test" then
        Record("item", "|cffa335ee|Hitem:0|h[Test Item]|h|r", 1)
        Record("money", nil, 0)
        p(ns.LR_T("added 2 fake entries (1 item, 1 gold)."))
        return
    end
    if msg == "panel" then
        -- visual-only: shows our panel for 15s (Roll button won't be wired to a
        -- live prompt, so clicking it does nothing -- this just checks look/pos)
        BuildRollPanel()
        rollExpiresAt = GetTime() + 15
        rollPanel:Show()
        p("panel shown (visual test, 15s)")
        return
    end
    local hist = History()
    local total, items, gold, cur, ratio = ns.LR_GetBonusStats()
    p(("%d rolls  |  items %d  gold %d  currency %d  |  item ratio %d%%")
        :format(total, items, gold, cur, math.floor(ratio * 100 + 0.5)))
    local show = math.min(#hist, 10)
    for i = #hist, #hist - show + 1, -1 do
        local e = hist[i]
        local res = e.typ == "item" and (e.link or "item")
            or (e.typ == "money" and "gold" or e.typ)
        p(("  %s  -  %s"):format(e.boss or "?", res))
    end
end

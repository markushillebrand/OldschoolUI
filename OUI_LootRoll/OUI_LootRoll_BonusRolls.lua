-------------------------------------------------------------------------------
--  EUI_LootRoll_BonusRolls.lua
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
local BONUS_ROLL_CONFIRM_TYPE = 1

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
--  Boss context tracking
-------------------------------------------------------------------------------
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
        return
    end

    if s.bonusReminder and hasMatch then
        local names = {}
        for _, e in ipairs(wanted) do names[#names + 1] = e.link or e.itemName or tostring(e.itemID) end
        local head = boss
            and OldschoolUI.Lf("Bonus roll: wish item at %1$s!", boss)
            or  ns.LR_T("Bonus roll: wish item here!")
        ns.LR_Announce(head, table.concat(names, ", "))
    end
end
ns.LR_HandleBonusPrompt = HandleBonusPrompt
ns.LR_CurrentBoss = CurrentBoss


-------------------------------------------------------------------------------
--  Events
-------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("ENCOUNTER_END")
ev:RegisterEvent("BONUS_ROLL_RESULT")
ev:RegisterEvent("BONUS_ROLL_FAILED")
ev:RegisterEvent("SPELL_CONFIRMATION_PROMPT")
ev:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        CDB()  -- ensure the store exists
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
        local typeIdentifier, itemLink, quantity, _, _, _, currencyID = ...
        Record(typeIdentifier, itemLink, quantity, currencyID)
        return
    end

    if event == "BONUS_ROLL_FAILED" then
        -- A roll that produced nothing still counts as a (non-item) outcome
        -- for the ratio. MoP normally awards gold on a miss, but guard anyway.
        Record("money", nil, 0)
        return
    end

    if event == "SPELL_CONFIRMATION_PROMPT" then
        -- Availability signal for the reminder / auto-ignore step.
        local spellID, confirmType = ...
        if confirmType == BONUS_ROLL_CONFIRM_TYPE then
            HandleBonusPrompt(spellID, CurrentBoss())
        end
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
    if msg == "clear" then
        ns.LR_ClearBonusHistory()
        p(ns.LR_T("history cleared."))
        return
    end
    if msg == "test" then
        Record("item", "|cffa335ee|Hitem:0|h[Test Item]|h|r", 1)
        Record("money", nil, 0)
        p(ns.LR_T("added 2 fake entries (1 item, 1 gold)."))
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

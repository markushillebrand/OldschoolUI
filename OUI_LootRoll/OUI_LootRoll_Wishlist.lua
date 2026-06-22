-------------------------------------------------------------------------------
--  OUI_LootRoll_Wishlist.lua
--  Loot wishlist: pre-pick items you want from raid bosses (via the Encounter
--  Journal, localized) per difficulty bucket (Normal / Heroic / LFR). Items are
--  auto-checked-off the moment the character receives them by ANY means
--  (roll, trade, quest, mail, ...), with a timestamp.
--
--  This drives the bonus-roll reminder: when a bonus roll becomes available
--  the reminder only fires if the current boss still has an un-obtained wish
--  at the current difficulty. It also powers the "wish item dropped" hint
--  raised from the loot-roll bars (see core HandleStartRoll).
--
--  Data is per-character in OldschoolUILootRollCharDB.wishlist.
-------------------------------------------------------------------------------

local addonName, ns = ...

local GetInstanceInfo = GetInstanceInfo
local GetItemCount    = GetItemCount
local GetItemInfo     = GetItemInfo
local time            = time
local tinsert         = table.insert
local tremove         = table.remove
local wipe            = wipe

-------------------------------------------------------------------------------
--  Difficulty buckets
-------------------------------------------------------------------------------
-- MoP raid difficultyIDs: 3=10N 4=25N 5=10H 6=25H 7=LFR (14/15/16 = later
-- Normal/Heroic/Mythic flex ids, mapped defensively in case the client uses them)
local DIFF_BUCKET = {
    [3] = "normal", [4] = "normal",
    [5] = "heroic", [6] = "heroic",
    [14] = "normal", [15] = "heroic", [16] = "heroic",
}
local BUCKET_ORDER = { "normal", "heroic" }
ns.LR_BUCKET_ORDER = BUCKET_ORDER

function ns.LR_BucketLabel(b)
    if b == "normal" then return ns.LR_T and ns.LR_T("Normal") or "Normal" end
    if b == "heroic" then return ns.LR_T and ns.LR_T("Heroic") or "Heroic" end
    return b
end

function ns.LR_CurrentBucket()
    local diffID = select(3, GetInstanceInfo())
    return diffID and DIFF_BUCKET[diffID] or nil
end

-- localization shim (the windows file owns L(); expose a tiny one here)
ns.LR_T = ns.LR_T or function(s)
    return (OldschoolUI and OldschoolUI.L and OldschoolUI.L(s)) or s
end

-------------------------------------------------------------------------------
--  Store
-------------------------------------------------------------------------------
local function WDB()
    if type(OldschoolUILootRollCharDB) ~= "table" then OldschoolUILootRollCharDB = {} end
    local c = OldschoolUILootRollCharDB
    if type(c.wishlist) ~= "table" then c.wishlist = {} end
    return c.wishlist
end

local function FindEntry(itemID)
    for _, e in ipairs(WDB()) do
        if e.itemID == itemID then return e end
    end
end

function ns.LR_WishlistGet() return WDB() end

-- entry: { itemID, itemName, link, icon, boss, jeid, instance, diffs={normal=..},
--          obtained, obtainedAt }
function ns.LR_WishlistAdd(info)
    if not info or not info.itemID then return end
    local e = FindEntry(info.itemID)
    if e then
        -- merge difficulty flags into the existing entry
        if info.diffs then for k, v in pairs(info.diffs) do e.diffs[k] = v and true or nil end end
        return e, false
    end
    e = {
        itemID    = info.itemID,
        itemName  = info.itemName,
        link      = info.link,
        icon      = info.icon,
        boss      = info.boss,
        jeid      = info.jeid,
        instance  = info.instance,
        diffs     = {},
        obtained  = false,
    }
    if info.diffs then for k, v in pairs(info.diffs) do e.diffs[k] = v and true or nil end end
    tinsert(WDB(), e)
    if ns.LR_OnWishlistChanged then ns.LR_OnWishlistChanged() end
    return e, true
end

function ns.LR_WishlistRemove(itemID)
    local list = WDB()
    for i = #list, 1, -1 do
        if list[i].itemID == itemID then tremove(list, i) end
    end
    if ns.LR_OnWishlistChanged then ns.LR_OnWishlistChanged() end
end

function ns.LR_WishlistHas(itemID) return FindEntry(itemID) ~= nil end

-- toggle a single difficulty flag on an entry (creates the entry if needed)
function ns.LR_WishlistToggleDiff(info, bucket)
    local e = FindEntry(info.itemID)
    if not e then
        e = select(1, ns.LR_WishlistAdd(info))
    end
    if not e then return end
    e.diffs[bucket] = (not e.diffs[bucket]) and true or nil
    -- if no difficulty remains, drop the entry entirely
    if not next(e.diffs) then ns.LR_WishlistRemove(e.itemID) end
    if ns.LR_OnWishlistChanged then ns.LR_OnWishlistChanged() end
    return e.diffs[bucket] and true or false
end

local function EntryMatchesBucket(e, bucket)
    if not next(e.diffs) then return true end        -- wanted at every difficulty
    if bucket and e.diffs[bucket] then return true end
    if not bucket then return true end               -- unknown context: don't suppress
    return false
end

-- is itemID still wanted (un-obtained) at the given difficulty bucket?
function ns.LR_IsWanted(itemID, bucket)
    local e = FindEntry(itemID)
    if e and not e.obtained and EntryMatchesBucket(e, bucket) then return e end
end

-- un-obtained wishes for a given boss at a difficulty bucket
function ns.LR_WantedAtBoss(bossName, bucket)
    local out = {}
    for _, e in ipairs(WDB()) do
        if not e.obtained and EntryMatchesBucket(e, bucket)
           and bossName and e.boss and e.boss == bossName then
            out[#out + 1] = e
        end
    end
    return out
end

-- any un-obtained wish at all (used to guard auto-ignore)
function ns.LR_HasOpenWishes()
    for _, e in ipairs(WDB()) do if not e.obtained then return true end end
    return false
end

-------------------------------------------------------------------------------
--  "Received by any means" detection -> mark obtained
-------------------------------------------------------------------------------
local function MarkObtained(itemID)
    local e = FindEntry(itemID)
    if e and not e.obtained then
        e.obtained = true
        e.obtainedAt = time()
        if ns.LR_OnWishlistChanged then ns.LR_OnWishlistChanged() end
        if ns.LR_Announce then
            ns.LR_Announce(ns.LR_T("Wish item obtained:") .. " " .. (e.link or e.itemName or "?"))
        end
        return true
    end
end
ns.LR_MarkObtained = MarkObtained

-- bag-scan: anything the character now carries counts as obtained, regardless
-- of how it got there (roll / trade / quest / mail / vendor).
local function ScanBags()
    local list = WDB()
    if #list == 0 then return end
    for _, e in ipairs(list) do
        if not e.obtained and e.itemID and GetItemCount(e.itemID) > 0 then
            MarkObtained(e.itemID)
        end
    end
end
ns.LR_ScanWishlistBags = ScanBags

local det = CreateFrame("Frame")
det:RegisterEvent("PLAYER_LOGIN")
det:RegisterEvent("BAG_UPDATE_DELAYED")
det:RegisterEvent("CHAT_MSG_LOOT")
det:SetScript("OnEvent", function(_, event, ...)
    if event == "CHAT_MSG_LOOT" then
        local msg = ...
        -- only the local player's own loot ("You receive...") should count for
        -- a chat-driven check; the bag scan handles everything else anyway.
        local link = msg and msg:match("|Hitem:%-?%d+.-|h.-|h|r")
        local itemID = link and tonumber(link:match("item:(%d+)"))
        if itemID and ns.LR_IsWanted and FindEntry(itemID) then
            -- defer to bag scan so trades/soulbound timing settle
            if C_Timer and C_Timer.After then C_Timer.After(0.3, ScanBags) else ScanBags() end
        end
        return
    end
    -- PLAYER_LOGIN / BAG_UPDATE_DELAYED
    ScanBags()
end)

-------------------------------------------------------------------------------
--  Encounter Journal access (localized raids / bosses / loot)
-------------------------------------------------------------------------------
local ejReady = false
local function EnsureEJ()
    if EncounterJournal then ejReady = true; return true end
    local loader = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
    if loader then pcall(loader, "Blizzard_EncounterJournal") end
    ejReady = EncounterJournal ~= nil
    return ejReady
end
ns.LR_EnsureEJ = EnsureEJ

-- list every raid instance across all tiers: { {jid, name, tier} ... }
function ns.LR_EJ_GetRaids()
    EnsureEJ()
    local out = {}
    if not (EJ_GetNumTiers and EJ_SelectTier and EJ_GetInstanceByIndex) then return out end
    local numTiers = EJ_GetNumTiers() or 0
    for t = 1, numTiers do
        pcall(EJ_SelectTier, t)
        local tierName = EJ_GetTierInfo and EJ_GetTierInfo(t) or ("Tier " .. t)
        local i = 1
        while true do
            local jid, name = EJ_GetInstanceByIndex(i, true)  -- isRaid = true
            if not jid then break end
            out[#out + 1] = { jid = jid, name = name, tier = tierName, tierIndex = t }
            i = i + 1
        end
    end
    return out
end

-- index of the newest tier (current expansion). On MoP Classic this is MoP.
function ns.LR_EJ_CurrentTierIndex()
    ns.LR_EnsureEJ()
    return (EJ_GetNumTiers and EJ_GetNumTiers()) or 0
end

-- bosses of a raid: { {jeid, name} ... }
function ns.LR_EJ_GetBosses(jid)
    EnsureEJ()
    local out = {}
    if not (EJ_SelectInstance and EJ_GetEncounterInfoByIndex) then return out end
    pcall(EJ_SelectInstance, jid)
    local i = 1
    while true do
        local name, _, jeid = EJ_GetEncounterInfoByIndex(i, jid)
        if not name then break end
        out[#out + 1] = { jeid = jeid, name = name }
        i = i + 1
    end
    return out
end

-- read one loot row defensively across API shapes
local function ReadLoot(i)
    if C_EncounterJournal and C_EncounterJournal.GetLootInfoByIndex then
        local t = C_EncounterJournal.GetLootInfoByIndex(i)
        if type(t) == "table" and t.itemID then
            return t.itemID, t.name, t.link, t.icon
        end
    end
    if EJ_GetLootInfoByIndex then
        -- legacy multi-return; scan for a numeric itemID and an item hyperlink
        local r = { EJ_GetLootInfoByIndex(i) }
        local itemID, link, name, icon
        for _, v in ipairs(r) do
            if type(v) == "number" and not itemID and v > 0 then itemID = v end
            if type(v) == "string" then
                if v:find("|Hitem:") then link = v
                elseif not name then name = v end
            end
        end
        return itemID, name, link, icon
    end
end

-- candidate EJ difficulty IDs per bucket (25 first, then 10, then flex)
local DIFF_EJID = { normal = { 4, 3, 14, 1 }, heroic = { 6, 5, 15, 2 } }

local function ApplyLootFilter(usableOnly)
    if usableOnly then
        if EJ_SetLootFilter then
            local _, _, classID = UnitClass("player")
            local specID = 0
            if GetSpecialization and GetSpecializationInfo then
                local s = GetSpecialization()
                if s then specID = GetSpecializationInfo(s) or 0 end
            end
            pcall(EJ_SetLootFilter, classID or 0, specID)
        end
    elseif EJ_ResetLootFilter then
        pcall(EJ_ResetLootFilter)
    end
    if EJ_SetSlotFilter then pcall(EJ_SetSlotFilter, 0) end
end

-- loot of a boss across difficulties: one entry per itemID, with availability:
--   { itemID, name, link, icon, avail = { normal=?, heroic=? } }
-- (Normal and Heroic may share an itemID or be distinct; either is handled.)
function ns.LR_EJ_GetLoot(jeid, jid, usableOnly)
    EnsureEJ()
    if usableOnly == nil then
        local s = ns.LR_GetSettings and ns.LR_GetSettings()
        usableOnly = (not s) or s.wishlistUsableOnly ~= false
    end
    local byID, order = {}, {}
    if not EJ_GetNumLoot then return order end
    local saved = EJ_GetDifficulty and EJ_GetDifficulty() or nil
    if jid and EJ_SelectInstance then pcall(EJ_SelectInstance, jid) end
    for _, bucket in ipairs(BUCKET_ORDER) do
        for _, dID in ipairs(DIFF_EJID[bucket]) do
            if EJ_SetDifficulty then pcall(EJ_SetDifficulty, dID) end
            if EJ_SelectEncounter then pcall(EJ_SelectEncounter, jeid) end
            ApplyLootFilter(usableOnly)
            local n = EJ_GetNumLoot() or 0
            if n > 0 then
                for i = 1, n do
                    local itemID, name, link, icon = ReadLoot(i)
                    if itemID then
                        local e = byID[itemID]
                        if not e then
                            e = { itemID = itemID, name = name, link = link, icon = icon, avail = {} }
                            byID[itemID] = e
                            order[#order + 1] = e
                        end
                        e.avail[bucket] = true
                    end
                end
                break  -- got this bucket's data; skip the remaining size variants
            end
        end
    end
    if saved and EJ_SetDifficulty then pcall(EJ_SetDifficulty, saved) end
    return order
end

-- let the UI refresh when EJ loot finishes loading asynchronously
local ejEv = CreateFrame("Frame")
ejEv:RegisterEvent("EJ_LOOT_DATA_RECIEVED")
ejEv:SetScript("OnEvent", function()
    if ns.LR_OnEJLootReady then ns.LR_OnEJLootReady() end
end)

-------------------------------------------------------------------------------
--  Debug
-------------------------------------------------------------------------------
SLASH_OUIWISH1 = "/ouiwish"
SlashCmdList["OUIWISH"] = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local p = function(s) print("|cffD9A441OldschoolUI Wishlist:|r " .. s) end
    if msg == "scan" then ScanBags(); p(ns.LR_T("bag scan done.")); return end
    if msg == "ejdump" then
        EnsureEJ()
        local raids = ns.LR_EJ_GetRaids()
        p(#raids .. " raids found.")
        local r = raids[#raids]
        if r then
            p("last raid: " .. (r.name or "?") .. " (" .. (r.tier or "?") .. ")")
            local bosses = ns.LR_EJ_GetBosses(r.jid)
            p("  bosses: " .. #bosses)
            if bosses[1] then
                local b1 = bosses[1]
                local loot = ns.LR_EJ_GetLoot(b1.jeid, r.jid)
                p("  first boss '" .. (b1.name or "?") .. "' loot rows: " .. #loot)
                if loot[1] then p("   e.g. " .. (loot[1].link or loot[1].name or loot[1].itemID)) end
                if #loot == 0 and C_Timer and C_Timer.After then
                    p("   (loot loads async - re-reading in 1.5s...)")
                    C_Timer.After(1.5, function()
                        local loot2 = ns.LR_EJ_GetLoot(b1.jeid, r.jid)
                        p("   retry loot rows: " .. #loot2)
                        if loot2[1] then p("    e.g. " .. (loot2[1].link or loot2[1].name or loot2[1].itemID)) end
                    end)
                end
            end
        end
        return
    end
    local list = WDB()
    p(#list .. " wishlist entries:")
    for _, e in ipairs(list) do
        local d = {}
        for _, b in ipairs(BUCKET_ORDER) do if e.diffs[b] then d[#d + 1] = b end end
        p(("  %s [%s] %s"):format(e.link or e.itemName or e.itemID,
            table.concat(d, "/"), e.obtained and ("OBTAINED " .. (date("%Y-%m-%d", e.obtainedAt or 0))) or "open"))
    end
end

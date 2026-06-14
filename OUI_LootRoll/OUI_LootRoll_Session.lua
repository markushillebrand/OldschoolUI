-------------------------------------------------------------------------------
--  OUI_LootRoll_Session.lua
--  In-memory record of this session's completed group loot rolls.
--  For each finished roll: the item, every player's roll type, and the winner.
--  Sourced from C_LootHistory; snapshotted on LOOT_HISTORY_ROLL_COMPLETE and
--  de-duplicated by rollID. Session = current play session (cleared on reload).
-------------------------------------------------------------------------------

local addonName, ns = ...

local C_LootHistory = C_LootHistory
local time          = time
local tinsert       = table.insert

local ROLL_PASS, ROLL_NEED, ROLL_GREED, ROLL_DE = 0, 1, 2, 3

local function L(s) return (OldschoolUI and OldschoolUI.L and OldschoolUI.L(s)) or s end

local session   = {}   -- list of completed rolls (oldest..newest)
local recorded  = {}   -- [rollID] = true (dedup within the session)

local function S()
    return ns.LR_GetSettings and ns.LR_GetSettings() or nil
end

-- Scan all current loot-history items and append any newly *completed* rolls.
-- Only DONE rolls are recorded, so rollType/winner are final (capturing earlier
-- froze empty data because LOOT_HISTORY_ROLL_CHANGED fires before players roll).
local function Capture()
    if not (C_LootHistory and C_LootHistory.GetNumItems) then return end
    local n = C_LootHistory.GetNumItems() or 0
    local added = false
    for i = 1, n do
        local rID, link, numP, isDone, winnerIdx = C_LootHistory.GetItem(i)
        if rID and isDone and not recorded[rID] then
            local players, winner = {}, nil
            for p = 1, (numP or 0) do
                local name, class, rt, roll, isWinner = C_LootHistory.GetPlayerInfo(i, p)
                if name then
                    tinsert(players, {
                        name = name, class = class,
                        rt = rt, roll = roll, won = isWinner and true or false,
                    })
                    if isWinner then winner = name end
                end
            end
            -- Fallback winner resolution via winnerIdx if no per-player flag hit.
            if not winner and winnerIdx and winnerIdx > 0 then
                local wn = C_LootHistory.GetPlayerInfo(i, winnerIdx)
                if wn then winner = wn end
            end
            recorded[rID] = true
            tinsert(session, {
                rollID = rID, link = link, players = players, winner = winner, t = time(),
            })
            added = true
        end
    end
    if added and ns.LR_OnSessionChanged then ns.LR_OnSessionChanged() end
end

-- Accessors for the (future) session window.
function ns.LR_GetSession()
    return session
end

function ns.LR_ClearSession()
    wipe(session)
    wipe(recorded)
    if ns.LR_OnSessionChanged then ns.LR_OnSessionChanged() end
end

-- Human-readable roll label (locale-aware via the core's translator if present).
function ns.LR_RollLabel(rt)
    local key = (rt == ROLL_NEED and "Need")
        or (rt == ROLL_GREED and "Greed")
        or (rt == ROLL_DE and "Disenchant")
        or (rt == ROLL_PASS and "Pass")
        or "?"
    return (OldschoolUI and OldschoolUI.L and OldschoolUI.L(key)) or key
end

-------------------------------------------------------------------------------
--  Events
-------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        if C_LootHistory then
            ev:RegisterEvent("LOOT_HISTORY_ROLL_COMPLETE")
            ev:RegisterEvent("LOOT_HISTORY_ROLL_CHANGED")
        end
        return
    end
    -- Both COMPLETE and CHANGED can carry the final winner/roll data depending
    -- on timing; Capture() is idempotent via the rollID dedup table.
    Capture()
end)

-------------------------------------------------------------------------------
--  Test / inspection slash command
-------------------------------------------------------------------------------
SLASH_OUILRSESSION1 = "/ouisession"
SlashCmdList["OUILRSESSION"] = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local p = function(s) print("|cffD9A441OldschoolUI Session:|r " .. s) end
    if msg == "clear" then ns.LR_ClearSession(); p(L("session cleared.")); return end
    if #session == 0 then p(L("no completed rolls recorded this session.")); return end
    p(L("%d completed roll(s) this session:"):format(#session))
    local show = math.min(#session, 10)
    for i = #session, #session - show + 1, -1 do
        local e = session[i]
        local parts = {}
        for _, pl in ipairs(e.players) do
            parts[#parts + 1] = pl.name .. "=" .. ns.LR_RollLabel(pl.rt)
        end
        p(L("  %s  ->  winner: %s  [%s]"):format(
            e.link or "item", e.winner or "?", table.concat(parts, ", ")))
    end
end

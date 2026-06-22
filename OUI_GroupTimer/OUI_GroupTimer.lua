-------------------------------------------------------------------------------
--  OldschoolUIGroupTimer.lua  —  M+ Timer overlay for OldschoolUI
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local GT = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME, "AceEvent-3.0")

-- Upvalues
local floor, min, max, abs = math.floor, math.min, math.max, math.abs
local format = string.format
local GetWorldElapsedTime = GetWorldElapsedTime
local GetTimePreciseSec = GetTimePreciseSec
local wipe = wipe

-- Constants
local PLUS_TWO_RATIO   = 0.8
local PLUS_THREE_RATIO = 0.6
local CHALLENGERS_PERIL_AFFIX_ID = 152

local COMPARE_NONE = "NONE"
local COMPARE_DUNGEON = "DUNGEON"
local COMPARE_LEVEL = "LEVEL"
local COMPARE_LEVEL_AFFIX = "LEVEL_AFFIX"

local function CopyTable(src)
    if type(src) ~= "table" then return src end
    local out = {}
    for key, value in pairs(src) do
        out[key] = type(value) == "table" and CopyTable(value) or value
    end
    return out
end


local function CalculateBonusTimers(maxTime, medalTimes)
    -- MoP: the two "good" thresholds are the two fastest medal times
    -- (e.g. Gold and Platinum/Diamond). The bar shows the best colour under
    -- the fastest medal time and the mid colour under the next.
    if type(medalTimes) == "table" and #medalTimes >= 2 then
        local sorted = {}
        for _, t in ipairs(medalTimes) do
            if type(t) == "number" and t > 0 then sorted[#sorted + 1] = t end
        end
        if #sorted >= 2 then
            table.sort(sorted)            -- ascending: fastest first
            return sorted[2], sorted[1]   -- plusTwoT (slower), plusThreeT (fastest)
        end
    end
    -- Fallback (no medal data available): ratio-based.
    return (maxTime or 0) * PLUS_TWO_RATIO, (maxTime or 0) * PLUS_THREE_RATIO
end

-------------------------------------------------------------------------------
-- Medal tiers (MoP Challenge Modes).
--
-- Classic MoP had Bronze/Silver/Gold; MoP Classic added Platinum/Diamond above
-- those. We support up to 5 tiers and are fully data-driven: the display uses
-- however many medal times the API (or /ouigt test) provides, mapping the
-- FASTEST time to the BEST medal. Name sets per tier count keep the mapping
-- correct whether the server exposes 3, 4 or 5 tiers.
-------------------------------------------------------------------------------
local MEDAL_NAME_SETS = {
    [2] = { "Gold", "Silver" },
    [3] = { "Gold", "Silver", "Bronze" },
    [4] = { "Platinum", "Gold", "Silver", "Bronze" },
    [5] = { "Diamond", "Platinum", "Gold", "Silver", "Bronze" },
}
local MEDAL_COLORS = {
    Diamond  = { 0.55, 0.90, 1.00 },
    Platinum = { 0.80, 0.92, 0.95 },
    Gold     = { 1.00, 0.84, 0.00 },
    Silver   = { 0.75, 0.76, 0.80 },
    Bronze   = { 0.80, 0.52, 0.25 },
}

-- Localize a medal name via a qualified key ("Medal: Gold") so it never collides
-- with other uses of the bare word (e.g. the "Diamond" raid marker -> "Raute").
-- Falls back to the bare English name when the locale has no entry.
local function LMedal(name)
    local key = "Medal: " .. name
    local t = OldschoolUI.L(key)
    if t == key then return name end
    return t
end

-- Ascending-by-time list of { time, name, color = {r,g,b} } from run.medalTimes.
local function GetMedalTiers(run)
    local times = {}
    if run and type(run.medalTimes) == "table" then
        for _, t in ipairs(run.medalTimes) do
            if type(t) == "number" and t > 0 then times[#times + 1] = t end
        end
    end
    if #times == 0 then return nil end
    table.sort(times)  -- ascending: fastest (best) first
    local names = MEDAL_NAME_SETS[#times] or MEDAL_NAME_SETS[5]
    local tiers = {}
    for i = 1, #times do
        local name = names[i] or ("Tier " .. i)
        local c = MEDAL_COLORS[name] or { 1, 1, 1 }
        tiers[i] = { time = times[i], name = name, color = { r = c[1], g = c[2], b = c[3] } }
    end
    return tiers
end

-- Best medal still earnable at `elapsed`: the fastest tier not yet exceeded.
-- Returns currentTier, nextLowerTier, secondsUntilDemotion (nil past the slowest).
local function GetAchievableMedal(tiers, elapsed)
    if not tiers then return nil end
    for i = 1, #tiers do
        if elapsed <= tiers[i].time then
            return tiers[i], tiers[i + 1], tiers[i].time - elapsed
        end
    end
    return nil
end

-- Database defaults
local DB_DEFAULTS = {
    profile = {
        enabled           = true,
        showAffixes       = true,
        showPlusTwoTimer  = true,
        showPlusThreeTimer = true,
        showDeaths        = true,
        showObjectives    = true,
        showObjectiveTimes = true,
        showEnemyBar      = true,
        showEnemyText     = true,
        scale             = 1.0,
        standaloneAlpha   = 0,
        showAccent        = false,
        showPreview       = false,
        enemyForcesPos    = "BOTTOM",
        enemyForcesPctPos = "LABEL",
        deathsInTitle     = false,
        deathTimeInTitle  = false,
        timerInBar        = false,
        showTimerBar      = true,
        showTimerBreakdown = false,
        alignAllText      = "RIGHT",
        titleUseAccent    = true,
        titleColor        = { r = 1, g = 1, b = 1 },
        titleSize         = 16,
        affixSize         = 12,
        thresholdSize     = 12,
        tickAlpha         = 1,
        objectivesSize    = 12,
        timerExpiredColor = { r = 0.9, g = 0.2, b = 0.2 },
        enemyForcesTextFormat = "PERCENT",
        showCompletedMilliseconds = true,
        objectiveCompareMode = "NONE",
        objectiveCompareDeltaOnly = false,
        showUpcomingSplitTargets = false,
        frameWidth        = 260,
        barWidth          = 210,
        barHeight         = 8,
        barHeightExpanded = 22,
        rowGap            = 6,
        objectiveGap      = 4,
        timerPlusTwoColor = { r = 0.3, g = 0.8, b = 1 },
        timerPlusThreeColor = { r = 0.4, g = 1, b = 0.4 },
        objectiveTextColor = { r = 0.9, g = 0.9, b = 0.9 },
        objectiveCompletedColor = { r = 0.3, g = 0.8, b = 0.3 },
        splitFasterColor  = { r = 0.4, g = 1, b = 0.4 },
        splitSlowerColor  = { r = 1, g = 0.45, b = 0.45 },
        deathTextColor    = { r = 0.93, g = 0.33, b = 0.33 },
        enemyBarUseAccent = true,
        enemyBarColor     = { r = 0.35, g = 0.55, b = 0.8 },
    },
}

-- State
local db
local updateTicker
local currentRun = {
    active        = false,
    mapID         = nil,
    mapName       = "",
    level         = 0,
    affixes       = {},
    maxTime       = 0,
    elapsed       = 0,
    completed     = false,
    deaths        = 0,
    deathTimeLost = 0,
    objectives    = {},
}

-- Per-player death tracking (reset each key).
-- Midnight removed CLEU, so we detect deaths by comparing the API death
-- count each tick and scanning the party for who is newly dead.
local playerDeaths = {}
local _prevDeathCount = 0
local _partyAlive = {}  -- [name] = true while alive, removed on death detection

local function ScanPartyAlive()
    wipe(_partyAlive)
    local prefix = IsInRaid() and "raid" or "party"
    local count = GetNumGroupMembers()
    for i = 1, count do
        local unit = (prefix == "party" and i == count) and "player" or (prefix .. i)
        local name = UnitName(unit)
        if name and not UnitIsDeadOrGhost(unit) then
            _partyAlive[name] = true
        end
    end
    if prefix == "party" then
        local name = UnitName("player")
        if name and not UnitIsDeadOrGhost("player") then
            _partyAlive[name] = true
        end
    end
end

local function CheckForNewDeaths(newDeathCount)
    if newDeathCount <= _prevDeathCount then
        _prevDeathCount = newDeathCount
        return
    end
    -- Death count went up -- find who is now dead that was alive last tick
    local prefix = IsInRaid() and "raid" or "party"
    local count = GetNumGroupMembers()
    for i = 1, count do
        local unit = (prefix == "party" and i == count) and "player" or (prefix .. i)
        local name = UnitName(unit)
        if name and _partyAlive[name] and UnitIsDeadOrGhost(unit) then
            playerDeaths[name] = (playerDeaths[name] or 0) + 1
            _partyAlive[name] = nil
        end
    end
    if prefix == "party" then
        local name = UnitName("player")
        if name and _partyAlive[name] and UnitIsDeadOrGhost("player") then
            playerDeaths[name] = (playerDeaths[name] or 0) + 1
            _partyAlive[name] = nil
        end
    end
    _prevDeathCount = newDeathCount
end

-- Helpers
local function FormatTime(seconds, withMilliseconds)
    if not seconds or seconds < 0 then seconds = 0 end
    local whole = floor(seconds)
    local m = floor(whole / 60)
    local s = floor(whole % 60)
    if withMilliseconds then
        local ms = floor(((seconds - whole) * 1000) + 0.5)
        if ms >= 1000 then
            whole = whole + 1
            m = floor(whole / 60)
            s = floor(whole % 60)
            ms = 0
        end
        return format("%02d:%02d.%03d", m, s, ms)
    end
    return format("%02d:%02d", m, s)
end

local function RoundToInt(value)
    if not value then return 0 end
    return floor(value + 0.5)
end

local function GetColor(tbl, fallbackR, fallbackG, fallbackB)
    if tbl then
        return tbl.r or fallbackR, tbl.g or fallbackG, tbl.b or fallbackB
    end
    return fallbackR, fallbackG, fallbackB
end

local function GetTimerBarFillColor(profile, elapsed, plusThreeTime, plusTwoTime, maxTime)
    if maxTime and maxTime > 0 and elapsed > plusTwoTime then
        -- +2 lost: solid #B059CC.
        return 0xB0 / 255, 0x59 / 255, 0xCC / 255
    elseif maxTime and maxTime > 0 and elapsed > plusThreeTime then
        -- +3 lost, +2 still on: match the +2 threshold color.
        return GetColor(profile and profile.timerPlusTwoColor, 0.3, 0.8, 1)
    end
    -- On for +3: match the +3 threshold color.
    return GetColor(profile and profile.timerPlusThreeColor, 0.4, 1, 0.4)
end

local function NormalizeAffixKey(affixes)
    local ids = {}
    for _, affixID in ipairs(affixes or {}) do
        ids[#ids + 1] = affixID
    end
    table.sort(ids)
    return table.concat(ids, "-")
end

local function GetScopeKey(run, mode)
    if not run or not run.mapID then return nil end

    if mode == COMPARE_DUNGEON then
        return tostring(run.mapID)
    elseif mode == COMPARE_LEVEL then
        return format("%s:%d", run.mapID, run.level or 0)
    elseif mode == COMPARE_LEVEL_AFFIX then
        return format("%s:%d:%s", run.mapID, run.level or 0, NormalizeAffixKey(run.affixes))
    end

    return nil
end

local function EnsureProfileStore(key)
    if not db or not db.profile then return nil end
    if not db.profile[key] then db.profile[key] = {} end
    return db.profile[key]
end

local function GetReferenceObjectiveTime(run, objectiveIndex, mode)
    if mode == COMPARE_NONE then return nil end

    local store = EnsureProfileStore("bestObjectiveSplits")
    if not store then return nil end

    -- Try exact scope first, then fall back to broader scopes.
    -- LEVEL_AFFIX -> LEVEL -> DUNGEON
    local tryOrder
    if mode == COMPARE_LEVEL_AFFIX then
        tryOrder = { COMPARE_LEVEL_AFFIX, COMPARE_LEVEL, COMPARE_DUNGEON }
    elseif mode == COMPARE_LEVEL then
        tryOrder = { COMPARE_LEVEL, COMPARE_DUNGEON }
    else
        tryOrder = { mode }
    end

    for _, tryMode in ipairs(tryOrder) do
        local scopeKey = GetScopeKey(run, tryMode)
        local scope = scopeKey and store[scopeKey]
        if scope and scope[objectiveIndex] then
            return scope[objectiveIndex]
        end
    end
    return nil
end

local function UpdateBestObjectiveSplits(run, objectiveIndex, elapsed)
    local store = EnsureProfileStore("bestObjectiveSplits")
    if not store then return end

    for _, mode in ipairs({ COMPARE_DUNGEON, COMPARE_LEVEL, COMPARE_LEVEL_AFFIX }) do
        local scopeKey = GetScopeKey(run, mode)
        if scopeKey then
            if not store[scopeKey] then store[scopeKey] = {} end
            local previous = store[scopeKey][objectiveIndex]
            if not previous or elapsed < previous then
                store[scopeKey][objectiveIndex] = elapsed
            end
        end
    end
end

local function UpdateObjectiveCompletion(obj, objectiveIndex)
    if not db or not db.profile or not obj or not obj.elapsed or obj.elapsed <= 0 then return end

    local compareMode = db.profile.objectiveCompareMode or COMPARE_NONE
    local reference = GetReferenceObjectiveTime(currentRun, objectiveIndex, compareMode)
    obj.referenceElapsed = reference
    obj.compareDelta = reference and (obj.elapsed - reference) or nil
    obj.isNewBest = reference == nil or obj.elapsed < reference

    UpdateBestObjectiveSplits(currentRun, objectiveIndex, obj.elapsed)
end

local function BuildSplitCompareText(referenceTime, currentTime, deltaOnly, fasterColor, slowerColor)
    if not referenceTime or not currentTime then return "" end

    local diff = currentTime - referenceTime
    local color = diff <= 0 and fasterColor or slowerColor
    local cR, cG, cB = GetColor(color, 0.4, 1, 0.4)
    local diffPrefix = diff < 0 and "-" or "+"
    local diffText = diff == 0 and "0:00" or FormatTime(abs(diff))
    local colorHex = format("|cff%02x%02x%02x", floor(cR * 255), floor(cG * 255), floor(cB * 255))

    if deltaOnly then
        return format("  %s(%s%s)|r", colorHex, diffPrefix, diffText)
    end

    return format("  |cff888888(%s, %s%s%s)|r", FormatTime(referenceTime), colorHex, diffPrefix, diffText)
end

local function FormatEnemyForcesText(enemyObj, formatId, compact)
    local rawCurrent = enemyObj.rawQuantity or enemyObj.quantity or 0
    local rawTotal = enemyObj.rawTotalQuantity or enemyObj.totalQuantity or 100
    local percent = enemyObj.percent or enemyObj.quantity or 0
    local remaining = max(0, rawTotal - rawCurrent)
    local suffix = compact and "" or " Enemy Forces"

    if formatId == "COUNT" then
        return format("%d/%d%s", RoundToInt(rawCurrent), RoundToInt(rawTotal), suffix)
    elseif formatId == "COUNT_PERCENT" then
        return format("%d/%d - %.2f%%%s", RoundToInt(rawCurrent), RoundToInt(rawTotal), percent, suffix)
    elseif formatId == "REMAINING" then
        if compact then
            return format("%d left", RoundToInt(remaining))
        end
        return format("%d remaining%s", RoundToInt(remaining), suffix)
    end

    return format("%.2f%%%s", percent, suffix)
end

-- Objective tracking
local function UpdateObjectives()
    local numCriteria = select(3, C_Scenario.GetStepInfo()) or 0
    local elapsed = currentRun.elapsed

    for i = 1, numCriteria do
        local info = C_ScenarioInfo.GetCriteriaInfo(i)
        if info then
            local obj = currentRun.objectives[i]
            if not obj then
                obj = {
                    name          = "",
                    completed     = false,
                    elapsed       = 0,
                    quantity      = 0,
                    totalQuantity = 0,
                    rawQuantity   = 0,
                    rawTotalQuantity = 0,
                    percent       = 0,
                    isWeighted    = false,
                }
                currentRun.objectives[i] = obj
            end

            -- Strip Blizzard's leading checkmark so completed objectives
            -- render as clean text. UTF-8 for U+2713 is 0xE2 0x9C 0x93.
            local rawName = info.description or ("Objective " .. i)
            rawName = rawName:gsub("^\226\156\147%s*", "")
            rawName = rawName:gsub("^%-%s*", "")
            obj.name = rawName
            local wasCompleted = obj.completed
            obj.completed = info.completed

            if obj.completed and not wasCompleted then
                -- On reload, already-completed objectives would get current elapsed.
                -- Use persisted split time if available (saved on first completion).
                local saved = db and db.profile._activeRunSplits and db.profile._activeRunSplits[i]
                if saved and saved > 0 then
                    obj.elapsed = saved
                else
                    obj.elapsed = elapsed
                    -- Persist for reload survival
                    if db and db.profile then
                        if not db.profile._activeRunSplits then db.profile._activeRunSplits = {} end
                        db.profile._activeRunSplits[i] = elapsed
                    end
                end
                UpdateObjectiveCompletion(obj, i)
            end

            obj.quantity = info.quantity or 0
            obj.totalQuantity = info.totalQuantity or 0
            obj.rawQuantity = info.quantity or 0
            obj.rawTotalQuantity = info.totalQuantity or 0
            if info.isWeightedProgress then
                obj.isWeighted = true
                currentRun._weightedObj = obj  -- cached for RenderEnemyForces
                -- Normalize weighted progress to a 0-100 percent value.
                -- Cache the parsed result keyed on the raw string -- skips
                -- the gsub/tonumber chain on every tick where quantityString
                -- hasn't actually changed (the common case).
                local rawQuantity = info.quantity or 0
                local quantityString = info.quantityString
                if quantityString and quantityString ~= "" then
                    if obj._lastQS == quantityString then
                        rawQuantity = obj._lastQSParsed or rawQuantity
                    else
                        local normalized = quantityString:gsub("%%", "")
                        if normalized:find(",") and not normalized:find("%.") then
                            normalized = normalized:gsub(",", ".")
                        end
                        local parsed = tonumber(normalized)
                        if parsed then rawQuantity = parsed end
                        obj._lastQS, obj._lastQSParsed = quantityString, parsed
                    end
                end

                obj.rawQuantity = rawQuantity
                if obj.totalQuantity and obj.totalQuantity > 0 then
                    local percent = (rawQuantity / obj.totalQuantity) * 100
                    obj.quantity = floor(percent * 100 + 0.5) / 100
                else
                    obj.quantity = rawQuantity
                end
                obj.percent = obj.quantity

                if obj.completed then
                    obj.quantity = 100
                    obj.percent = 100
                    if obj.rawTotalQuantity and obj.rawTotalQuantity > 0 then
                        obj.rawQuantity = obj.rawTotalQuantity
                    end
                end
            else
                obj.isWeighted = false
                obj.percent = 0
                if obj.totalQuantity == 0 then
                    obj.quantity = obj.completed and 1 or 0
                    obj.totalQuantity = 1
                end
            end
        end
    end

    for i = numCriteria + 1, #currentRun.objectives do
        currentRun.objectives[i] = nil
    end
end

-- Coalesced refresh
local _refreshTimer
local function NotifyRefresh()
    if _refreshTimer then return end
    _refreshTimer = C_Timer.After(0.05, function()
        _refreshTimer = nil
        if _G._OUIGT_StandaloneRefresh then _G._OUIGT_StandaloneRefresh() end
    end)
end

-- Elapsed time: read from GetWorldElapsedTime(1) each tick. The Blizzard
-- hook on ChallengeModeBlock.UpdateTime is the primary tick driver (once
-- per second, zero cost outside M+). An OnUpdate fallback on our own
-- standalone frame ensures ticks keep firing even when QT reparents
-- ObjectiveTrackerFrame to a hidden container (which silences the hook).
local _lastTickedSec = -1

local function OnTimerTick()
    if not currentRun.active then return end

    local elapsed = select(2, GetWorldElapsedTime(1))
    if not (elapsed and elapsed >= 0) then return end

    -- Deduplicate: only refresh the display once per whole second.
    local sec = floor(elapsed)
    if sec == _lastTickedSec then return end
    _lastTickedSec = sec

    currentRun.elapsed = elapsed

    local deathCount, timeLost = 0, 0
    if C_ChallengeMode.GetDeathCount then
        deathCount, timeLost = C_ChallengeMode.GetDeathCount()
    end
    currentRun.deaths = deathCount or 0
    currentRun.deathTimeLost = timeLost or 0

    -- Detect per-player deaths, then refresh alive snapshot for next tick
    CheckForNewDeaths(deathCount or 0)
    ScanPartyAlive()

    UpdateObjectives()
    NotifyRefresh()
end

-- Primary driver: hook Blizzard's ChallengeModeBlock.UpdateTime (1/sec).
do
    local block = (ScenarioObjectiveTracker and ScenarioObjectiveTracker.ChallengeModeBlock)
        or (ScenarioBlocksFrame and ScenarioBlocksFrame.ChallengeModeBlock)
    if block and block.UpdateTime then
        hooksecurefunc(block, "UpdateTime", function()
            OnTimerTick()
        end)
    end
end

-- Fallback driver: OnUpdate on the standalone frame, throttled to 1/sec.
-- Only runs while the frame is shown (active M+ key). Ensures the timer
-- stays accurate even when the hook is silenced by QT's reparent-to-hidden.
local _onUpdateAccum = 0
local function OnUpdateFallback(_, dt)
    _onUpdateAccum = _onUpdateAccum + dt
    if _onUpdateAccum < 1 then return end
    _onUpdateAccum = 0
    OnTimerTick()
end

local _timerLoopWanted = false
local function StartTimerLoop()
    _timerLoopWanted = true
    if standaloneFrame then
        _onUpdateAccum = 0
        standaloneFrame:SetScript("OnUpdate", OnUpdateFallback)
    end
end
local function StopTimerLoop()
    _timerLoopWanted = false
    if standaloneFrame then
        standaloneFrame:SetScript("OnUpdate", nil)
    end
end

-- Hide Blizzard's ObjectiveTrackerFrame whenever our M+ timer is enabled
-- and we're in an active challenge mode. Permanent hooksecurefunc on Show:
-- every time Blizzard tries to show it during M+, we re-hide it. No
-- SetParent (avoids tainting the secure scenario tree), no recursion into
-- children (avoids the invisible-click-catcher pattern).
local _trackerHookInstalled = false
local function InstallTrackerHook()
    if _trackerHookInstalled then return end
    local otf = _G.ObjectiveTrackerFrame
    if not otf then return end
    _trackerHookInstalled = true
    hooksecurefunc(otf, "Show", function()
        if not (db and db.profile and db.profile.enabled) then return end
        -- Hide during active challenge AND after it completes but before
        -- the player has left the dungeon instance. Blizzard's end-of-run
        -- fanfare flips IsChallengeModeActive() back to false while the
        -- user is still inside -- without the completed + party gate the
        -- tracker pops back up for the last seconds before zone-out.
        local active = C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive
                       and C_ChallengeMode.IsChallengeModeActive()
        local completedInInstance = currentRun and currentRun.completed
        if completedInInstance then
            local _, iType = GetInstanceInfo()
            completedInInstance = (iType == "party")
        end
        if active or completedInInstance then
            otf:Hide()
        end
    end)
end

-- Force a re-evaluation now (used at run start / option change). If we're
-- in M+ and the addon is enabled, tracker hides; otherwise nothing happens.
local function ApplyTrackerVisibility()
    InstallTrackerHook()
    local otf = _G.ObjectiveTrackerFrame
    if not otf then return end
    if db and db.profile and db.profile.enabled
       and C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive
       and C_ChallengeMode.IsChallengeModeActive() then
        otf:Hide()
    end
end

local function SuppressBlizzardMPlus()
    ApplyTrackerVisibility()
    if _G._OUI_SetTrackerSuppressed then _G._OUI_SetTrackerSuppressed("MythicPlus", true) end
end
local function UnsuppressBlizzardMPlus()
    if _G._OUI_SetTrackerSuppressed then _G._OUI_SetTrackerSuppressed("MythicPlus", false) end
end

-- Run lifecycle
local function StartRun()
    local mapID = C_ChallengeMode.GetActiveChallengeMapID()
    if not mapID then return end
    _lastTickedSec = -1  -- reset dedup so the first tick always fires

    local mapName, _, timeLimit = C_ChallengeMode.GetMapUIInfo(mapID)
    -- MoP Challenge Modes have no keystone level or affixes; a run is graded
    -- purely by clear time against the medal thresholds (Bronze..Diamond).
    local medalTimes = (C_ChallengeMode.GetChallengeModeMapTimes
        and C_ChallengeMode.GetChallengeModeMapTimes(mapID)) or {}
    local numMedals  = (C_ChallengeMode.GetNumMedals
        and C_ChallengeMode.GetNumMedals(mapID)) or #medalTimes

    currentRun.active        = true
    currentRun.completed     = false
    currentRun.mapID         = mapID
    currentRun.mapName       = mapName or "Unknown"
    currentRun.level         = 0
    currentRun.maxTime       = (timeLimit and timeLimit > 0 and timeLimit)
        or medalTimes[1] or 0
    currentRun.medalTimes    = medalTimes
    currentRun.numMedals     = numMedals or 0
    currentRun.elapsed       = 0
    currentRun.deaths        = 0
    currentRun.deathTimeLost = 0
    wipe(playerDeaths)
    _prevDeathCount = 0
    ScanPartyAlive()
    currentRun.affixes       = {}
    currentRun.affixNames    = {}
    currentRun.preciseStart = GetTimePreciseSec and GetTimePreciseSec() or nil
    currentRun.preciseCompletedElapsed = nil
    currentRun._lastDungeonComplete = false
    currentRun._weightedObj = nil  -- populated by UpdateObjectives
    wipe(currentRun.objectives)

    StartTimerLoop()
    OnTimerTick()  -- prime the display immediately

    SuppressBlizzardMPlus()
    NotifyRefresh()
end

local function CompleteRun()
    currentRun.completed = true
    currentRun.active = false

    StopTimerLoop()

    -- Use C_ChallengeMode.GetChallengeCompletionInfo() as the authoritative
    -- completion time (milliseconds). GetWorldElapsedTime can return secret
    -- or stale values after depletion, producing "99:99" display.
    local completionInfo = C_ChallengeMode and C_ChallengeMode.GetChallengeCompletionInfo
        and C_ChallengeMode.GetChallengeCompletionInfo()
    if completionInfo and completionInfo.time and completionInfo.time > 0 then
        currentRun.elapsed = completionInfo.time / 1000
    else
        local elapsedTime = select(2, GetWorldElapsedTime(1))
        currentRun.elapsed = elapsedTime or currentRun.elapsed
    end
    if currentRun.preciseStart and GetTimePreciseSec then
        currentRun.preciseCompletedElapsed = max(0, GetTimePreciseSec() - currentRun.preciseStart)
    end
    UpdateObjectives()
    if db and db.profile then db.profile._activeRunSplits = nil end
    if _G._OUIGT_RecordCM then _G._OUIGT_RecordCM(currentRun) end
    NotifyRefresh()
end

local function ResetRun()
    _lastTickedSec = -1
    currentRun.active    = false
    currentRun.completed = false
    currentRun.mapID     = nil
    currentRun.mapName   = ""
    currentRun.level     = 0
    currentRun.maxTime   = 0
    currentRun.elapsed   = 0
    currentRun.deaths    = 0
    currentRun.deathTimeLost = 0
    wipe(playerDeaths)
    _prevDeathCount = 0
    wipe(_partyAlive)
    currentRun.preciseStart = nil
    currentRun.preciseCompletedElapsed = nil
    currentRun._lastDungeonComplete = false
    wipe(currentRun.affixes)
    wipe(currentRun.objectives)
    if db and db.profile then db.profile._activeRunSplits = nil end

    StopTimerLoop()

    UnsuppressBlizzardMPlus()
    NotifyRefresh()
end

local function CheckForActiveRun()
    local mapID = C_ChallengeMode.GetActiveChallengeMapID()
    if mapID then StartRun() end
end

-- Preview data
local PREVIEW_RUN = {
    active        = true,
    completed     = false,
    mapID         = 2648,
    mapName       = "The Rookery",
    level         = 12,
    maxTime       = 1920,
    elapsed       = 1380,
    deaths        = 2,
    deathTimeLost = 10,
    affixes       = {},
    preciseCompletedElapsed = nil,
    _previewAffixNames = { "Tyrannical", "Xal'atath's Bargain: Ascendant" },
    _previewAffixIDs = { 9, 152 },
    objectives    = {
        { name = "Kyrioss",                 completed = true,  elapsed = 510,  quantity = 1,     totalQuantity = 1,   rawQuantity = 1, rawTotalQuantity = 1, percent = 0, isWeighted = false },
        { name = "Stormguard Gorren",       completed = true,  elapsed = 1005, quantity = 1,     totalQuantity = 1,   rawQuantity = 1, rawTotalQuantity = 1, percent = 0, isWeighted = false },
        { name = "Lua Error Monstrosity",   completed = false, elapsed = 0,    quantity = 0,     totalQuantity = 1,   rawQuantity = 0, rawTotalQuantity = 1, percent = 0, isWeighted = false },
        { name = "|cffff3333OldschoolUI|r",    completed = false, elapsed = 0,    quantity = 0,     totalQuantity = 1,   rawQuantity = 0, rawTotalQuantity = 1, percent = 0, isWeighted = false },
        { name = "Enemy Forces",            completed = false, elapsed = 0,    quantity = 78.42, totalQuantity = 100, rawQuantity = 188, rawTotalQuantity = 240, percent = 78.42, isWeighted = true },
    },
}

_G._OUIGT_Apply = function()
    -- Re-apply scale + center-anchored position so a Scale slider drag
    -- doesn't make the frame "fly" rightward (TOPLEFT-anchor scaling).
    -- Use the _G hook because the local ApplyStandalonePosition isn't in
    -- scope at this point in the file.
    if _G._OUIGT_ApplyStandalonePosition then
        _G._OUIGT_ApplyStandalonePosition()
    end
    if _G._OUIGT_StandaloneRefresh then _G._OUIGT_StandaloneRefresh() end
end

-- Preset system removed. Users tweak settings directly.

-- Reset the current profile back to defaults.
-- Used by the module's "Reset" button in the OldschoolUI options panel.
_G._OUIGT_ResetProfile = function()
    if not db or not db.profile then return false end

    -- Clear every key in the current profile
    for key in pairs(db.profile) do
        db.profile[key] = nil
    end

    -- Repopulate with DB defaults
    for key, value in pairs(DB_DEFAULTS.profile) do
        db.profile[key] = type(value) == "table" and CopyTable(value) or value
    end

    if _G._OUIGT_StandaloneRefresh then
        _G._OUIGT_StandaloneRefresh()
    end
    return true
end

-- Standalone frame
local standaloneFrame
local standaloneCreated = false

-- Font helpers
local FALLBACK_FONT = "Fonts/FRIZQT__.TTF"
local FONT_OPTIONS = {
    { key = nil,                          label = "OldschoolUI Default" },
    { key = "Fonts/FRIZQT__.TTF",         label = "Fritz Quadrata" },
    { key = "Fonts/ARIALN.TTF",           label = "Arial Narrow" },
    { key = "Fonts/MORPHEUS.TTF",         label = "Morpheus" },
    { key = "Fonts/SKURRI.TTF",           label = "Skurri" },
    { key = "Fonts/FRIZQT___CYR.TTF",     label = "Fritz Quadrata (Cyrillic)" },
    { key = "Fonts/ARHei.TTF",            label = "AR Hei (CJK)" },
}
local function SFont()
    if OldschoolUI and OldschoolUI.GetFontPath then
        local p = OldschoolUI.GetFontPath("groupTimer")
        if p and p ~= "" then return p end
    end
    return FALLBACK_FONT
end
-- _OUIGT_GetFontOptions removed: font dropdown deleted from options page.
local function SOutline()
    if OldschoolUI.GetFontOutlineFlag then return OldschoolUI.GetFontOutlineFlag("groupTimer") end
    return ""
end
local function SetFS(fs, size, flags)
    if not fs then return end
    local p = SFont()
    flags = flags or SOutline()
    fs:SetFont(p, size, flags)
    if not fs:GetFont() then fs:SetFont(FALLBACK_FONT, size, flags) end
end
local function ApplyShadow(fs)
    if not fs then return end
    if OldschoolUI.GetFontUseShadow and OldschoolUI.GetFontUseShadow("groupTimer") then
        fs:SetShadowColor(0, 0, 0, 0.8); fs:SetShadowOffset(1, -1)
    else
        fs:SetShadowOffset(0, 0)
    end
end

-- SetText with skip-if-unchanged. Avoids the per-tick SetText call (and
-- the implicit re-measure / re-layout) when the string hasn't changed.
local function SetTextDiff(fs, text)
    if not fs then return end
    text = text or ""
    if fs._lastText == text then return end
    fs:SetText(text)
    fs._lastText = text
end

local function SetFittedText(fs, text, maxWidth, preferredSize, minSize)
    if not fs then return end
    text = text or ""
    preferredSize = preferredSize or 10
    minSize = minSize or 8
    local outline = SOutline()
    SetFS(fs, preferredSize, outline)
    ApplyShadow(fs)
    fs:SetText(text)

    for size = preferredSize, minSize, -1 do
        SetFS(fs, size, outline)
        ApplyShadow(fs)
        fs:SetText(text)
        if not maxWidth or fs:GetStringWidth() <= maxWidth then
            return
        end
    end
end

local function GetAccentColor()
    if OldschoolUI.GetAccentColor then
        local r, g, b = OldschoolUI.GetAccentColor()
        if r then return r, g, b end
    end
    return 0.85, 0.64, 0.25
end

local function StripDefeated(name)
    if not name then return name end
    name = name:gsub("[Dd]efeated", "")
    return name:match("^%s*(.-)%s*$") or name
end

local objRows = {}
local function GetObjRow(parent, idx)
    if objRows[idx] then return objRows[idx] end
    local nameFS = parent:CreateFontString(nil, "OVERLAY")
    nameFS:SetWordWrap(false)
    nameFS:SetNonSpaceWrap(false)
    local timeFS = parent:CreateFontString(nil, "OVERLAY")
    timeFS:SetWordWrap(false)
    timeFS:SetNonSpaceWrap(false)
    local entry = { name = nameFS, time = timeFS }
    objRows[idx] = entry
    return entry
end

local function CreateStandaloneFrame()
    if standaloneCreated then return standaloneFrame end
    standaloneCreated = true

    local f = CreateFrame("Frame", "OldschoolUIGroupTimerStandalone", UIParent, "BackdropTemplate")
    f:SetSize(260, 200)
    -- Default position: top of quest tracker, or right-side fallback
    local otf = _G.ObjectiveTrackerFrame
    if otf and otf:GetTop() then
        f:SetPoint("TOPRIGHT", otf, "TOPRIGHT", 0, 0)
    else
        f:SetPoint("RIGHT", UIParent, "RIGHT", -100, 0)
    end
    f:SetFrameStrata("MEDIUM")
    f:SetFrameLevel(10)
    f:SetClampedToScreen(true)

    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    f:SetBackdropColor(0.05, 0.04, 0.08, 0.85)
    f:SetBackdropBorderColor(0.15, 0.15, 0.15, 0.6)

    f._accent = f:CreateTexture(nil, "BORDER")
    f._accent:SetWidth(2)
    f._accent:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
    f._accent:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)

    f._titleFS = f:CreateFontString(nil, "OVERLAY")
    f._titleFS:SetWordWrap(false)
    f._titleFS:SetJustifyV("MIDDLE")

    f._affixFS = f:CreateFontString(nil, "OVERLAY")
    f._affixFS:SetWordWrap(true)

    f._timerFS = f:CreateFontString(nil, "OVERLAY")
    f._timerFS:SetJustifyH("CENTER")
    f._timerFS:SetWordWrap(false)
    f._timerFS:SetNonSpaceWrap(false)
    f._timerDetailFS = f:CreateFontString(nil, "OVERLAY")
    f._timerDetailFS:SetWordWrap(false)
    f._timerDetailFS:SetNonSpaceWrap(false)
    f._barBg = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    f._barFill = f:CreateTexture(nil, "ARTWORK")
    f._seg3 = f:CreateTexture(nil, "OVERLAY")
    f._seg2 = f:CreateTexture(nil, "OVERLAY")
    f._threshFS = f:CreateFontString(nil, "OVERLAY")
    f._threshFS:SetWordWrap(false)
    f._threshFS2 = f:CreateFontString(nil, "OVERLAY")
    f._threshFS2:SetWordWrap(false)
    f._deathFS = f:CreateFontString(nil, "OVERLAY")
    f._deathFS:SetWordWrap(false)
    f._deathHit = CreateFrame("Frame", nil, f)
    f._deathHit:SetFrameLevel(f:GetFrameLevel() + 5)
    f._deathHit:EnableMouse(true)

    -- Custom two-column death tooltip
    local deathTT = CreateFrame("Frame", nil, UIParent)
    deathTT:SetFrameStrata("TOOLTIP")
    deathTT:SetFrameLevel(200)
    deathTT:Hide()
    local ttBg = deathTT:CreateTexture(nil, "BACKGROUND")
    ttBg:SetAllPoints()
    ttBg:SetColorTexture(0.067, 0.067, 0.067, 0.90)
    OldschoolUI.MakeBorder(deathTT, 1, 1, 1, 0.15, OldschoolUI.PanelPP)
    deathTT._rows = {}

    local TT_PAD   = 8
    local TT_ROW_H = 14
    local TT_GAP   = 3
    local TT_FONT  = OldschoolUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF"

    local function EnsureRows(n)
        for i = #deathTT._rows + 1, n do
            local nameFS = deathTT:CreateFontString(nil, "OVERLAY")
            nameFS:SetFont(TT_FONT, 10, "")
            nameFS:SetJustifyH("LEFT")
            local countFS = deathTT:CreateFontString(nil, "OVERLAY")
            countFS:SetFont(TT_FONT, 10, "")
            countFS:SetJustifyH("RIGHT")
            deathTT._rows[i] = { name = nameFS, count = countFS }
        end
    end

    f._deathHit:SetScript("OnEnter", function(self)
        local deaths = playerDeaths
        if not next(deaths) and currentRun.deaths and currentRun.deaths > 0 then
            deaths = { [UnitName("player") or "You"] = currentRun.deaths }
        end
        if not next(deaths) then return end

        local list = {}
        for name, count in pairs(deaths) do
            list[#list + 1] = { name = name, count = count }
        end
        table.sort(list, function(a, b)
            if a.count ~= b.count then return a.count > b.count end
            return a.name < b.name
        end)

        EnsureRows(#list)

        -- Hide all rows first
        for i = 1, #deathTT._rows do
            deathTT._rows[i].name:Hide()
            deathTT._rows[i].count:Hide()
        end

        -- Measure max name width for tooltip sizing
        local maxNameW = 0
        local maxCountW = 0
        for i, entry in ipairs(list) do
            local row = deathTT._rows[i]
            local classFile = select(2, UnitClass(entry.name))
            local color = classFile and (RAID_CLASS_COLORS[classFile] or RAID_CLASS_COLORS["PRIEST"])
            local short = Ambiguate and Ambiguate(entry.name, "short") or entry.name
            local colored = color and color:WrapTextInColorCode(short) or short
            row.name:SetText(colored)
            row.name:SetTextColor(1, 1, 1, 0.80)
            row.count:SetText(entry.count)
            row.count:SetTextColor(1, 1, 1, 0.80)
            local nw = row.name:GetStringWidth() or 0
            local cw = row.count:GetStringWidth() or 0
            if nw > maxNameW then maxNameW = nw end
            if cw > maxCountW then maxCountW = cw end
        end

        local ttW = TT_PAD + maxNameW + 12 + maxCountW + TT_PAD
        local ttH = TT_PAD + #list * TT_ROW_H + (#list - 1) * TT_GAP + TT_PAD

        deathTT:SetSize(ttW, ttH)

        -- Position rows
        for i, entry in ipairs(list) do
            local row = deathTT._rows[i]
            local yOff = -TT_PAD - (i - 1) * (TT_ROW_H + TT_GAP)
            row.name:ClearAllPoints()
            row.name:SetPoint("TOPLEFT", deathTT, "TOPLEFT", TT_PAD, yOff)
            row.count:ClearAllPoints()
            row.count:SetPoint("TOPRIGHT", deathTT, "TOPRIGHT", -TT_PAD, yOff)
            row.name:Show()
            row.count:Show()
        end

        -- Anchor tooltip above the death text
        local right = (self._align or "LEFT") == "RIGHT"
        deathTT:ClearAllPoints()
        if right then
            deathTT:SetPoint("BOTTOMRIGHT", self, "TOPRIGHT", 0, 4)
        else
            deathTT:SetPoint("BOTTOMLEFT", self, "TOPLEFT", 0, 4)
        end
        deathTT:Show()
    end)
    f._deathHit:SetScript("OnLeave", function()
        deathTT:Hide()
    end)
    f._enemyFS = f:CreateFontString(nil, "OVERLAY")
    f._enemyFS:SetWordWrap(false)
    f._enemyBarBg = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    f._enemyBarFill = f:CreateTexture(nil, "ARTWORK")
    f._previewFS = f:CreateFontString(nil, "OVERLAY")
    f._previewFS:SetWordWrap(false)

    -- Hidden until RenderStandalone() shows it
    f:Hide()

    -- Apply saved scale and position immediately so the frame never flashes at default
    if db and db.profile then
        f:SetScale(db.profile.scale or 1.0)
        if db.profile.standalonePos then
            local pos = db.profile.standalonePos
            local cx, cy = pos.centerX, pos.centerY
            if not cx then
                -- Legacy TOPLEFT-stored position; will be migrated to center
                -- on the first ApplyStandalonePosition / drag-save call.
                f:ClearAllPoints()
                f:SetPoint(pos.point or "TOPLEFT", UIParent, pos.relPoint or "BOTTOMLEFT",
                    pos.x or 0, pos.y or 0)
            else
                f:ClearAllPoints()
                f:SetPoint("CENTER", UIParent, "CENTER", cx, cy)
            end
        end
    end

    standaloneFrame = f
    -- If a run is already active (e.g. /reload mid-key), wire up the
    -- OnUpdate fallback now that the frame exists.
    if _timerLoopWanted then
        _onUpdateAccum = 0
        f:SetScript("OnUpdate", OnUpdateFallback)
    end
    return f
end

local function RenderStandalone()
    if not db or not db.profile.enabled then
        if standaloneFrame then standaloneFrame:Hide() end
        return
    end

    local p = db.profile
    local isPreview = false
    local run = currentRun
    if not run.active and not run.completed then
        if p.showPreview then
            run = PREVIEW_RUN
            isPreview = true
        else
            if standaloneFrame then standaloneFrame:Hide() end
            return
        end
    end

    local f = CreateStandaloneFrame()
    local PAD = 12
    local ALIGN_PAD = 0
    local TBAR_PAD = 0
    local configuredTimerBarH = p.barHeight or 8
    local expandedH = p.barHeightExpanded or 22
    local TBAR_H = p.timerInBar and max(configuredTimerBarH, expandedH) or configuredTimerBarH
    local ENEMY_BAR_H = p.barHeight or 8
    local ROW_GAP = p.rowGap or 6
    local OBJ_GAP = p.objectiveGap or 4

    f:SetWidth(p.frameWidth or 260)

    -- Scale ownership lives in ApplyStandalonePosition (called from
    -- _OUIGT_Apply on slider changes). Don't SetScale here -- doing so on
    -- every render can race the anchor and visually shift the frame.
    local alpha = p.standaloneAlpha or 0.85
    f:SetBackdropColor(0.05, 0.04, 0.08, alpha)
    f:SetBackdropBorderColor(0.15, 0.15, 0.15, min(alpha, 0.6))

    local aR, aG, aB = GetAccentColor()
    if p.showAccent then
        f._accent:SetColorTexture(aR, aG, aB, 0.9)
        f._accent:Show()
    else
        f._accent:Hide()
    end

    local frameW = f:GetWidth()
    local innerW = frameW - PAD * 2
    local y = -PAD

    local function ContentPad(align)
        if align == "LEFT" or align == "RIGHT" then return PAD + ALIGN_PAD end
        return PAD
    end

    local _gAlign = (p.alignAllText == "LEFT") and "LEFT" or "RIGHT"
    local function _ra() return _gAlign end

    -- Title
    local titleAlign = _ra(p.titleAlign or "CENTER")
    local tR, tG, tB
    if p.titleUseAccent ~= false then
        tR, tG, tB = aR, aG, aB
    elseif p.titleColor then
        tR, tG, tB = p.titleColor.r or 1, p.titleColor.g or 1, p.titleColor.b or 1
    else
        tR, tG, tB = 1, 1, 1
    end
    local titleText = format("|cff%02x%02x%02x%s|r",
        floor(tR * 255), floor(tG * 255), floor(tB * 255),
        run.mapName or "Challenge Mode")
    f._titleFS:SetJustifyH(titleAlign)
    f._titleFS:SetTextColor(1, 1, 1)
    local titleMax = p.titleSize or 13
    local titleMin = max(8, titleMax - 3)
    SetFittedText(f._titleFS, titleText, innerW, titleMax, titleMin)
    f._titleFS:ClearAllPoints()
    f._titleFS:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
    f._titleFS:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, y)
    f._titleFS:Show()
    local titleH = f._titleFS:GetStringHeight() or titleMax
    y = y - titleH - 2 - ROW_GAP

    -- Affixes removed for MoP (Challenge Modes have no affixes).
    f._affixFS:Hide()

    -- Deaths (toggle removed; always on when there are deaths)
    if run.deaths > 0 and not p.deathsInTitle then
        local deathAlign = _ra(p.deathAlign or "LEFT")
        local dPad = ContentPad(deathAlign)
        SetFS(f._deathFS, 12)
        ApplyShadow(f._deathFS)
        local dR, dG, dB = GetColor(p.deathTextColor, 0.93, 0.33, 0.33)
        f._deathFS:SetTextColor(dR, dG, dB)
        f._deathFS:SetText(format("%d Death%s  -%s",
            run.deaths, run.deaths ~= 1 and "s" or "", FormatTime(run.deathTimeLost)))
        f._deathFS:ClearAllPoints()
        f._deathFS:SetPoint("TOPLEFT", f, "TOPLEFT", dPad, y - 5)
        f._deathFS:SetPoint("TOPRIGHT", f, "TOPRIGHT", -dPad, y - 5)
        f._deathFS:SetJustifyH(deathAlign)
        f._deathFS:Show()
        -- Position hit frame over the actual text, not the full row
        local textW = f._deathFS:GetStringWidth() or 0
        local textH = f._deathFS:GetStringHeight() or 12
        f._deathHit:ClearAllPoints()
        f._deathHit:SetSize(textW, textH)
        if deathAlign == "RIGHT" then
            f._deathHit:SetPoint("TOPRIGHT", f._deathFS, "TOPRIGHT", 0, 0)
        else
            f._deathHit:SetPoint("TOPLEFT", f._deathFS, "TOPLEFT", 0, 0)
        end
        f._deathHit._align = deathAlign
        f._deathHit:Show()
        y = y - (f._deathFS:GetStringHeight() or 12) - ROW_GAP - 5
    else
        f._deathFS:Hide()
        f._deathHit:Hide()
    end

    -- Timer colours
    local elapsed = run.elapsed or 0
    local maxTime = run.maxTime or 0
    local timeLeft = max(0, maxTime - elapsed)
    local plusTwoT, plusThreeT = CalculateBonusTimers(maxTime, run.medalTimes)
    local completedElapsed = run.preciseCompletedElapsed or elapsed
    local timerBarR, timerBarG, timerBarB = GetTimerBarFillColor(p, run.completed and completedElapsed or elapsed, plusThreeT, plusTwoT, maxTime)

    -- Build timer text per user-selected display mode.
    --   REMAINING        -> "11:37"   (or "+OT" when overtime)
    --   REMAINING_TOTAL  -> "11:37 / 33:00"
    --   ELAPSED          -> "21:23"
    --   ELAPSED_DETAIL   -> "21:23 (11:37 / 33:00)"
    local timerText
    local timerDetailText
    if run.completed then
        -- Completed run: freeze the clock at the final elapsed seconds
        -- but preserve the user's chosen display mode so "/33:00" doesn't
        -- vanish on completion.
        local mode = p.timerDisplayMode or "REMAINING_TOTAL"
        local elaStr = FormatTime(run.elapsed or completedElapsed or 0)
        local maxStr = FormatTime(maxTime)
        if mode == "REMAINING_TOTAL" then
            timerText = elaStr .. " / " .. maxStr
        elseif mode == "ELAPSED_DETAIL" then
            timerText = elaStr
            timerDetailText = " (" .. elaStr .. " / " .. maxStr .. ")"
        else
            timerText = elaStr
        end
    else
        local mode = p.timerDisplayMode or "REMAINING_TOTAL"
        local elaStr = FormatTime(elapsed)
        local maxStr = FormatTime(maxTime)
        local remStr = FormatTime(timeLeft)
        if mode == "REMAINING_TOTAL" then
            timerText = elaStr .. " / " .. maxStr
        elseif mode == "ELAPSED" then
            timerText = remStr
        elseif mode == "ELAPSED_DETAIL" then
            timerText = remStr
            timerDetailText = " (" .. elaStr .. " / " .. maxStr .. ")"
        else
            timerText = elaStr
        end
    end

    local tR, tG, tB = 1, 1, 1
    local depleted = (run.completed and completedElapsed > maxTime)
        or ((not run.completed) and timeLeft <= 0 and maxTime > 0)
    if depleted then
        tR, tG, tB = GetColor(p.timerExpiredColor, 0.9, 0.2, 0.2)
    end

    local underBarMode = (p.enemyForcesPos == "UNDER_BAR")

    -- Threshold text
    local _barW_for_thresh = math.min(p.barWidth or 210, innerW - TBAR_PAD * 2)
    if _barW_for_thresh < 60 then _barW_for_thresh = 60 end

    local function RenderThresholdText()
        -- Medal status line (Variant C): "Current: <medal> -- M:SS until <next
        -- lower>". Uses the data-driven medal tiers; _threshFS2 unused.
        f._threshFS2:Hide()
        local tiers = GetMedalTiers(run)
        if not tiers or maxTime <= 0 then
            f._threshFS:Hide()
            return
        end
        local refElapsed = (run.completed and completedElapsed) or elapsed
        local cur, nextLower, toDemo = GetAchievableMedal(tiers, refElapsed)
        local txt
        local SEP = "  \194\183  "  -- middle dot, kept outside L() for stable keys
        if cur then
            local c = cur.color
            local medalCol = format("|cff%02x%02x%02x%s|r",
                floor(c.r * 255), floor(c.g * 255), floor(c.b * 255),
                LMedal(cur.name))
            if run.completed then
                txt = OldschoolUI.Lf("Achieved: %1$s", medalCol)
            elseif nextLower then
                txt = OldschoolUI.Lf("Current: %1$s", medalCol) .. SEP ..
                    OldschoolUI.Lf("%1$s until %2$s", FormatTime(toDemo),
                        LMedal(nextLower.name))
            else
                txt = OldschoolUI.Lf("Current: %1$s", medalCol) .. SEP ..
                    OldschoolUI.Lf("%1$s left", FormatTime(toDemo))
            end
        else
            txt = "|cff999999" .. OldschoolUI.L("No medal (out of time)") .. "|r"
        end
        SetFS(f._threshFS, p.thresholdSize or 12)
        ApplyShadow(f._threshFS)
        f._threshFS:SetTextColor(1, 1, 1)
        f._threshFS:SetText(txt)
        f._threshFS:ClearAllPoints()
        f._threshFS:SetJustifyH("CENTER")
        if underBarMode then
            f._threshFS:SetPoint("BOTTOM", f._barBg, "TOP", 0, 3)
        else
            f._threshFS:SetPoint("TOP", f._barBg, "BOTTOM", 0, -3)
        end
        f._threshFS:Show()
        y = y - (p.thresholdSize or 12) - ROW_GAP
    end

    -- Enemy forces (toggle removed; always rendered)
    local function RenderEnemyForces()
        -- Use cached ref (set by UpdateObjectives) instead of re-finding
        -- the weighted objective on every render.
        local enemyObj = run._weightedObj
        if not enemyObj then
            for _, obj in ipairs(run.objectives) do
                if obj.isWeighted then enemyObj = obj; break end
            end
        end
        if not enemyObj then
            f._enemyFS:Hide(); f._enemyBarBg:Hide(); f._enemyBarFill:Hide()
            if f._enemyBarText then f._enemyBarText:Hide() end
            return
        end

        local objAlign = _ra(p.objectiveAlign or "LEFT")
        local ePad = ContentPad(objAlign)
        local pctRaw = min(100, max(0, enemyObj.quantity))
        local pctPos = p.enemyForcesPctPos or "LABEL"
        local showEnemyText = p.showEnemyText ~= false

        local enemyTextFormat = p.enemyForcesTextFormat or "PERCENT"
        local hideLabel = p.hideEnemyForcesLabel == true
        local label
        if pctPos == "LABEL" then
            -- compact=true skips the " Enemy Forces" suffix baked into
            -- FormatEnemyForcesText, so percent/count text shows alone.
            label = FormatEnemyForcesText(enemyObj, enemyTextFormat, hideLabel)
        elseif hideLabel then
            label = ""
        else
            label = "Enemy Forces"
        end

        SetFS(f._enemyFS, p.objectivesSize or 12)
        ApplyShadow(f._enemyFS)
        if enemyObj.completed then
            f._enemyFS:SetTextColor(GetColor(p.objectiveCompletedColor, 0.3, 0.8, 0.3))
        else
            f._enemyFS:SetTextColor(GetColor(p.objectiveTextColor, 0.9, 0.9, 0.9))
        end
        f._enemyFS:SetText(label)
        if hideLabel and pctPos ~= "LABEL" then
            f._enemyFS:Hide()
        else
            f._enemyFS:Show()
        end

        local function RenderEnemyBar()
            local besideRoom = (not enemyObj.completed and pctPos == "BESIDE") and 62 or 0
            local barW = math.min(p.barWidth or 210, innerW - TBAR_PAD * 2) - besideRoom
            if barW < 60 then barW = 60 end
            f._enemyBarBg:ClearAllPoints()
            if objAlign == "RIGHT" then
                f._enemyBarBg:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(PAD + TBAR_PAD), y)
            elseif objAlign == "CENTER" then
                f._enemyBarBg:SetPoint("TOP", f, "TOP", 0, y)
            else
                f._enemyBarBg:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + TBAR_PAD, y)
            end
            f._enemyBarBg:SetSize(barW, ENEMY_BAR_H)
            f._enemyBarBg:SetColorTexture(0.12, 0.12, 0.12, 0.9)
            f._enemyBarBg:Show()

            local eR, eG, eB
            if enemyObj.completed then
                eR, eG, eB = GetColor(p.objectiveCompletedColor, 0.3, 0.8, 0.3)
            elseif p.enemyBarUseAccent ~= false then
                eR, eG, eB = GetAccentColor()
            else
                eR, eG, eB = GetColor(p.enemyBarColor, 0.35, 0.55, 0.8)
            end

            local epct = enemyObj.completed and 1 or min(1, max(0, pctRaw / 100))
            local eFillW = max(1, barW * epct)
            f._enemyBarFill:ClearAllPoints()
            f._enemyBarFill:SetPoint("TOPLEFT", f._enemyBarBg, "TOPLEFT", 0, 0)
            f._enemyBarFill:SetSize(eFillW, ENEMY_BAR_H)
            f._enemyBarFill:SetColorTexture(eR, eG, eB, 0.8)
            f._enemyBarFill:Show()

            if not f._enemyBarText then
                f._enemyBarText = f:CreateFontString(nil, "OVERLAY")
                f._enemyBarText:SetWordWrap(false)
            end
            if pctPos == "BAR" then
                SetFS(f._enemyBarText, p.objectivesSize or 12)
                ApplyShadow(f._enemyBarText)
                -- In-bar percent is always white for readability over the
                -- accent-filled bar regardless of completion / user colors.
                f._enemyBarText:SetTextColor(1, 1, 1)
                f._enemyBarText:SetText(FormatEnemyForcesText(enemyObj, enemyTextFormat, true))
                f._enemyBarText:ClearAllPoints()
                f._enemyBarText:SetPoint("CENTER", f._enemyBarBg, "CENTER", 0, 0)
                f._enemyBarText:Show()
            elseif pctPos == "BESIDE" then
                SetFS(f._enemyBarText, p.objectivesSize or 12)
                ApplyShadow(f._enemyBarText)
                if enemyObj.completed then
                    f._enemyBarText:SetTextColor(GetColor(p.objectiveCompletedColor, 0.3, 0.8, 0.3))
                else
                    f._enemyBarText:SetTextColor(GetColor(p.objectiveTextColor, 0.9, 0.9, 0.9))
                end
                f._enemyBarText:SetText(FormatEnemyForcesText(enemyObj, enemyTextFormat, true))
                f._enemyBarText:ClearAllPoints()
                if objAlign == "RIGHT" then
                    f._enemyBarText:SetPoint("RIGHT", f._enemyBarBg, "LEFT", -4, 0)
                else
                    f._enemyBarText:SetPoint("LEFT", f._enemyBarBg, "RIGHT", 4, 0)
                end
                f._enemyBarText:Show()
            else
                f._enemyBarText:Hide()
            end

            y = y - ENEMY_BAR_H - ROW_GAP
        end

        local function RenderEnemyLabel()
            if not showEnemyText then
                f._enemyFS:Hide()
                return
            end
            -- In under-bar mode, lift the enemy text up 2px to sit closer to the bar.
            local labelY = underBarMode and (y + 2) or y
            f._enemyFS:ClearAllPoints()
            f._enemyFS:SetPoint("TOPLEFT", f, "TOPLEFT", ePad, labelY)
            f._enemyFS:SetPoint("TOPRIGHT", f, "TOPRIGHT", -ePad, labelY)
            f._enemyFS:SetJustifyH(objAlign)
            f._enemyFS:Show()
            local trailingGap = underBarMode and (4 - 2 + 5) or 4
            y = y - (f._enemyFS:GetStringHeight() or 12) - trailingGap
        end

        if underBarMode then
            RenderEnemyBar()
            RenderEnemyLabel()
        else
            RenderEnemyLabel()
            RenderEnemyBar()
        end
    end

    -- Timer text (with optional inline detail rendered as one combined block)
    if not p.timerInBar then
        local timerAlign = _ra(p.timerAlign or "CENTER")
        SetFS(f._timerFS, p.timerTextSize or 20)
        ApplyShadow(f._timerFS)
        f._timerFS:SetTextColor(tR, tG, tB)
        SetTextDiff(f._timerFS, timerText)
        if timerAlign == "RIGHT" then
            f._timerFS:SetJustifyH("RIGHT")
        else
            f._timerFS:SetJustifyH("LEFT")
        end
        f._timerFS:ClearAllPoints()
        -- Fixed-width once per format change: MM:SS is always 5 chars, so
        -- width only re-measures when the string length changes (e.g. mode swap).
        local _timerSz = p.timerTextSize or 20
        local _fScale = f:GetEffectiveScale() or 1
        local _mainKey = #(timerText or "") .. "|" .. _timerSz .. "|" .. string.format("%.3f", _fScale)
        if f._timerFS._lastLen ~= _mainKey then
            f._timerFS._lastLen = _mainKey
            -- Measure with worst-case digits so SetWidth never clips the live text.
            local templ = (timerText or ""):gsub("%d", "9")
            f._timerFS:SetText(templ)
            -- Keep the SetTextDiff cache in sync with what we just wrote
            -- directly. Otherwise the cache still reflects the previous
            -- timerText, so the restore call below short-circuits and
            -- the "99:99" template stays visible (bug seen during the
            -- 10-second pre-start window where elapsed stays at 0).
            f._timerFS._lastText = templ
            -- +2px safety margin: subpixel rounding at non-default UI scales
            -- can otherwise clip the rightmost glyph and force a wrap.
            f._timerFS:SetWidth((f._timerFS:GetStringWidth() or 0) + 2)
            SetTextDiff(f._timerFS, timerText)
        end

        if timerDetailText then
            local _mode = (not run.completed) and (p.timerDisplayMode or "REMAINING_TOTAL") or nil
            local detailSize = (_mode == "REMAINING_TOTAL") and 20 or 12
            SetFS(f._timerDetailFS, detailSize)
            ApplyShadow(f._timerDetailFS)
            f._timerDetailFS:SetTextColor(1, 1, 1)
            f._timerDetailFS:SetText(timerDetailText)
            if timerAlign == "RIGHT" then
                f._timerDetailFS:SetJustifyH("RIGHT")
            else
                f._timerDetailFS:SetJustifyH("LEFT")
            end
            f._timerDetailFS:ClearAllPoints()
            -- Cache key includes font size: switching modes (12pt detail
            -- ↔ 20pt detail) must re-measure the templatized width, else
            -- the larger glyphs get clipped and the detail vanishes.
            local _detKey = #timerDetailText .. "|" .. detailSize
            if f._timerDetailFS._lastKey ~= _detKey then
                f._timerDetailFS._lastKey = _detKey
                local templ = timerDetailText:gsub("%d", "9")
                f._timerDetailFS:SetText(templ)
                f._timerDetailFS:SetWidth((f._timerDetailFS:GetStringWidth() or 0) + 2)
                f._timerDetailFS:SetText(timerDetailText)
            end

            local gap = 4
            local detailW = f._timerDetailFS:GetStringWidth() or 0
            if timerAlign == "RIGHT" then
                -- Main timer flush right; detail sits to the LEFT of main.
                f._timerFS:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(PAD + ALIGN_PAD), y)
                f._timerDetailFS:SetPoint("BOTTOMRIGHT", f._timerFS, "BOTTOMLEFT", -gap, 4)
            elseif timerAlign == "LEFT" then
                f._timerFS:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + ALIGN_PAD, y)
                f._timerDetailFS:SetPoint("BOTTOMLEFT", f._timerFS, "BOTTOMRIGHT", gap, 4)
            else
                f._timerFS:SetPoint("TOP", f, "TOP", -(detailW + gap) / 2, y)
                f._timerDetailFS:SetPoint("BOTTOMLEFT", f._timerFS, "BOTTOMRIGHT", gap, 4)
            end
            f._timerDetailFS:Show()
        else
            if timerAlign == "RIGHT" then
                f._timerFS:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(PAD + ALIGN_PAD), y)
            elseif timerAlign == "LEFT" then
                f._timerFS:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + ALIGN_PAD, y)
            else
                f._timerFS:SetPoint("TOP", f, "TOP", 0, y)
            end
            f._timerDetailFS:Hide()
        end

        f._timerFS:Show()
        local timerH = f._timerFS:GetStringHeight() or 20
        if timerH < 20 then timerH = 20 end
        y = y - timerH - ROW_GAP
    else
        f._timerFS:Hide()
        f._timerDetailFS:Hide()
    end

    if underBarMode then
        RenderThresholdText()
    end

    -- Timer bar
    if maxTime > 0 and p.showTimerBar ~= false then
        local barW = math.min(p.barWidth or 210, innerW - TBAR_PAD * 2)
        if barW < 60 then barW = 60 end

        f._barBg:ClearAllPoints()
        local _barAlign = _ra(p.timerAlign or "CENTER")
        if _barAlign == "RIGHT" then
            f._barBg:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(PAD + TBAR_PAD), y)
        elseif _barAlign == "LEFT" then
            f._barBg:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + TBAR_PAD, y)
        else
            f._barBg:SetPoint("TOP", f, "TOP", 0, y)
        end
        f._barBg:SetSize(barW, TBAR_H)
        f._barBg:SetColorTexture(0.12, 0.12, 0.12, 0.9)
        f._barBg:Show()

        local fillPct = min(1, elapsed / maxTime)
        local fillW = max(1, barW * fillPct)
        f._barFill:ClearAllPoints()
        f._barFill:SetPoint("TOPLEFT", f._barBg, "TOPLEFT", 0, 0)
        f._barFill:SetSize(fillW, TBAR_H)
        local _fillA = p.timerInBar and (p.barFillAlphaExpanded or 0.85) or 0.85
        f._barFill:SetColorTexture(timerBarR, timerBarG, timerBarB, _fillA)
        f._barFill:Show()

        -- Pixel-perfect 2-physical-pixel tick markers.
        local _PP = OldschoolUI and OldschoolUI.PP
        local _es = f:GetEffectiveScale()
        local _tickW = _PP and _PP.SnapForES(2, _es) or 2
        local function _snap(v) return _PP and _PP.SnapForES(v, _es) or v end

        local tickA = p.tickAlpha or 1
        local whiteTicks = p.tickWhite == true

        -- Medal ticks: one colored tick per medal tier at its target time.
        -- Missed tiers (elapsed past them) turn white. Pool grows as needed.
        f._medalTicks = f._medalTicks or {}
        local _tiers = GetMedalTiers(run)
        local _shown = 0
        if _tiers and maxTime > 0 then
            for _, tier in ipairs(_tiers) do
                if tier.time <= maxTime then
                    _shown = _shown + 1
                    local tk = f._medalTicks[_shown]
                    if not tk then
                        tk = f:CreateTexture(nil, "OVERLAY")
                        f._medalTicks[_shown] = tk
                    end
                    tk:ClearAllPoints()
                    tk:SetSize(_tickW, TBAR_H)
                    tk:SetPoint("TOPLEFT", f._barBg, "TOPLEFT",
                        _snap(barW * (tier.time / maxTime)) - _tickW / 2, 0)
                    if whiteTicks or elapsed > tier.time then
                        tk:SetColorTexture(1, 1, 1, tickA)
                    else
                        tk:SetColorTexture(tier.color.r, tier.color.g, tier.color.b, tickA)
                    end
                    tk:Show()
                end
            end
        end
        for i = _shown + 1, #f._medalTicks do f._medalTicks[i]:Hide() end
        -- Legacy two-tick elements are replaced by the medal pool.
        f._seg3:Hide()
        f._seg2:Hide()

        if p.timerInBar then
            if not f._barTimerFS then
                f._barTimerFS = f:CreateFontString(nil, "OVERLAY")
                f._barTimerFS:SetWordWrap(false)
            end
            SetFS(f._barTimerFS, 12)
            ApplyShadow(f._barTimerFS)
            local btc = p.timerBarTextColor
            if btc then
                f._barTimerFS:SetTextColor(btc.r or 1, btc.g or 1, btc.b or 1)
            else
                f._barTimerFS:SetTextColor(tR, tG, tB)
            end
            SetTextDiff(f._barTimerFS, timerText)
            f._barTimerFS:ClearAllPoints()
            if p.timerInBarLeftText then
                f._barTimerFS:SetPoint("LEFT", f._barBg, "LEFT", 5, 0)
            else
                f._barTimerFS:SetPoint("CENTER", f._barBg, "CENTER", 0, 0)
            end
            f._barTimerFS:Show()
        elseif f._barTimerFS then
            f._barTimerFS:Hide()
        end

        y = y - TBAR_H - ROW_GAP - 2
    else
        f._barBg:Hide(); f._barFill:Hide()
        f._seg3:Hide(); f._seg2:Hide()
        if f._medalTicks then for _, tk in ipairs(f._medalTicks) do tk:Hide() end end
        if f._barTimerFS then f._barTimerFS:Hide() end
    end

    if underBarMode then
        RenderEnemyForces()
    end

    if not underBarMode then
        RenderThresholdText()
    end

    -- Objectives
    local objIdx = 0
    if p.showObjectives then
        local objAlign = _ra(p.objectiveAlign or "LEFT")
        local oPad = ContentPad(objAlign)
        for i, obj in ipairs(run.objectives) do
            if not obj.isWeighted then
                objIdx = objIdx + 1
                local entry = GetObjRow(f, objIdx)
                local nameFS, timeFS = entry.name, entry.time
                local objSize = p.objectivesSize or 12
                SetFS(nameFS, objSize)
                ApplyShadow(nameFS)
                SetFS(timeFS, objSize)
                ApplyShadow(timeFS)

                local displayName = StripDefeated(obj.name) or ("Objective " .. i)
                if obj.totalQuantity and obj.totalQuantity > 1 then
                    displayName = format("%d/%d %s", obj.quantity or 0, obj.totalQuantity, displayName)
                end
                if obj.completed then
                    nameFS:SetTextColor(GetColor(p.objectiveCompletedColor, 0.3, 0.8, 0.3))
                else
                    nameFS:SetTextColor(GetColor(p.objectiveTextColor, 0.9, 0.9, 0.9))
                end
                local timeStr = ""
                if p.showObjectiveTimes ~= false and obj.completed and obj.elapsed and obj.elapsed > 0 then
                    local cR, cG, cB = GetColor(p.objectiveCompletedColor, 0.3, 0.8, 0.3)
                    timeStr = format("|cff%02x%02x%02x%s|r",
                        floor(cR * 255), floor(cG * 255), floor(cB * 255), FormatTime(obj.elapsed))
                end
                local compareSuffix = ""
                if obj.completed and obj.referenceElapsed then
                    compareSuffix = BuildSplitCompareText(obj.referenceElapsed, obj.elapsed, p.objectiveCompareDeltaOnly, p.splitFasterColor, p.splitSlowerColor)
                elseif (not obj.completed) and p.showUpcomingSplitTargets and (p.objectiveCompareMode or COMPARE_NONE) ~= COMPARE_NONE then
                    local target = GetReferenceObjectiveTime(run, i, p.objectiveCompareMode or COMPARE_NONE)
                    if target then
                        compareSuffix = "  |cff888888PB " .. FormatTime(target) .. "|r"
                    end
                end
                -- Timer/split text on the right FontString (never truncated).
                -- Boss name on the left FontString (truncated with "..." by
                -- WoW's engine if it exceeds the remaining width). No string
                -- reads required -- SetWidth + SetWordWrap(false) handles
                -- truncation at the C++ level, safe for secret values.
                local rightText = (timeStr ~= "" and ("  " .. timeStr) or "") .. compareSuffix
                local oInnerW = frameW - oPad * 2
                nameFS:ClearAllPoints()
                timeFS:ClearAllPoints()
                if rightText ~= "" then
                    timeFS:SetText(rightText)
                    timeFS:SetTextColor(1, 1, 1, 1)
                    timeFS:SetWidth(0)
                    local timeW = timeFS:GetStringWidth() or 0
                    if objAlign == "RIGHT" then
                        timeFS:SetPoint("TOPRIGHT", f, "TOPRIGHT", -oPad, y)
                        nameFS:SetPoint("TOPRIGHT", timeFS, "TOPLEFT", 0, 0)
                    else
                        timeFS:SetPoint("TOPRIGHT", f, "TOPRIGHT", -oPad, y)
                        nameFS:SetPoint("TOPLEFT", f, "TOPLEFT", oPad, y)
                    end
                    local nameMaxW = oInnerW - timeW
                    if nameMaxW < 20 then nameMaxW = 20 end
                    nameFS:SetWidth(nameMaxW)
                    timeFS:Show()
                else
                    timeFS:Hide()
                    if objAlign == "RIGHT" then
                        nameFS:SetPoint("TOPRIGHT", f, "TOPRIGHT", -oPad, y)
                    elseif objAlign == "CENTER" then
                        nameFS:SetPoint("TOP", f, "TOP", 0, y)
                    else
                        nameFS:SetPoint("TOPLEFT", f, "TOPLEFT", oPad, y)
                    end
                    nameFS:SetWidth(oInnerW)
                end
                nameFS:SetText(displayName)
                nameFS:SetJustifyH(objAlign)
                nameFS:Show()
                y = y - (nameFS:GetStringHeight() or 12) - OBJ_GAP
            end
        end
    end

    for i = objIdx + 1, #objRows do
        local e = objRows[i]
        if e then e.name:Hide(); e.time:Hide() end
    end

    if not underBarMode then
        if objIdx > 0 then y = y - 5 end
        RenderEnemyForces()
    end

    local totalH = abs(y) + PAD
    f:SetHeight(totalH)

    if isPreview then
        SetFS(f._previewFS, 8)
        f._previewFS:SetTextColor(0.5, 0.5, 0.5, 0.6)
        f._previewFS:SetText(OldschoolUI.L("PREVIEW"))
        f._previewFS:ClearAllPoints()
        f._previewFS:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, 4)
        f._previewFS:Show()
    elseif f._previewFS then
        f._previewFS:Hide()
    end

    f:Show()
end

_G._OUIGT_StandaloneRefresh = RenderStandalone
_G._OUIGT_GetStandaloneFrame = function()
    return CreateStandaloneFrame()
end

-- Forces a full rebuild by discarding the cached frame + its FontStrings
-- so the next RenderStandalone() re-creates them from scratch. Use when a
-- setting (e.g. text alignment) won't take effect via re-render alone.
_G._OUIGT_RebuildStandalone = function()
    if standaloneFrame then standaloneFrame:Hide() end
    standaloneFrame = nil
    standaloneCreated = false
    wipe(objRows)
    RenderStandalone()
end

-- One-time migration of legacy TOPLEFT-stored position into stable centerX/Y
-- offsets relative to UIParent center. Must run BEFORE SetScale so the
-- derived center reflects the unscaled frame; otherwise repeated calls
-- after SetScale would compute a different center each time and the frame
-- would drift.
local function _ensureCenterPos()
    local pos = db and db.profile and db.profile.standalonePos
    if not pos then return end
    if pos.centerX and pos.centerY then return end
    local f = standaloneFrame
    if not (f and f:GetCenter()) then return end
    -- Force scale 1.0 momentarily so GetCenter returns un-scaled coords.
    local prevScale = f:GetScale()
    f:SetScale(1.0)
    local cx, cy = f:GetCenter()
    local upX, upY = UIParent:GetCenter()
    pos.centerX = cx - upX
    pos.centerY = cy - upY
    -- Strip legacy keys so the migration only runs once.
    pos.point, pos.relPoint, pos.x, pos.y = nil, nil, nil, nil
    f:SetScale(prevScale)
end

local function ApplyStandalonePosition()
    if not db then return end
    if not standaloneFrame then return end
    _ensureCenterPos()
    local pos = db.profile.standalonePos
    local scale = db.profile.scale or 1.0

    -- SetPoint offsets are in the frame's OWN scaled coord space, so the
    -- effective on-screen offset = stored * scale. To keep the visual
    -- center pinned regardless of scale, divide the stored offset by scale.
    standaloneFrame:SetScale(scale)
    if pos and pos.centerX and pos.centerY then
        standaloneFrame:ClearAllPoints()
        standaloneFrame:SetPoint("CENTER", UIParent, "CENTER",
            pos.centerX / scale, pos.centerY / scale)
    end
end
_G._OUIGT_ApplyStandalonePosition = ApplyStandalonePosition

-- True only when every scenario objective is complete: Avoids false times being saved/missed runs due to completion on same tick
local function IsDungeonComplete()
    local numCriteria = select(3, C_Scenario.GetStepInfo()) or 0
    if numCriteria == 0 then return false end

    local seenAny = false
    for i = 1, numCriteria do
        local info = C_ScenarioInfo.GetCriteriaInfo(i)
        if info then
            seenAny = true
            if not info.completed then
                return false
            end
        end
    end

    return seenAny
end

-- Event-driven runtime. Zero polling. Lifecycle events handle start /
-- complete / reset; SCENARIO_CRITERIA_UPDATE handles the "all objectives
-- done" detection (no need for a per-tick poller). Multi-event detection
-- with GetInstanceInfo difficulty fallback (IsChallengeModeActive returns
-- false post-completion, so map-id alone isn't reliable).
local runtimeFrame = CreateFrame("Frame")

local function _isInChallengeMode()
    if C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive
       and C_ChallengeMode.IsChallengeModeActive() then
        return true
    end
    -- Fallback: difficulty 8 = Mythic Keystone. Reliable across the brief
    -- window where IsChallengeModeActive flips false but we're still in
    -- the dungeon (e.g. immediately after completion).
    local _, instanceType, difficulty = GetInstanceInfo()
    return instanceType == "party" and difficulty == 8
end

local function HandleRuntimeEvent(event)
    -- A simulated run (/ouigt test) is driven manually and is not backed by a
    -- real challenge map, so skip all real-run detection/teardown while it runs.
    if currentRun._sim then return end
    if not db or not db.profile.enabled then
        if currentRun.active or currentRun.completed then ResetRun() end
        return
    end

    local activeMapID = C_ChallengeMode.GetActiveChallengeMapID()
    if activeMapID then
        if not currentRun.active and not currentRun.completed then
            StartRun()
        end
        -- Pure event-driven completion check: criteria updates fire when
        -- bosses die and when the weighted enemy-forces tally crosses 100.
        if currentRun.active and event == "SCENARIO_CRITERIA_UPDATE" then
            if IsDungeonComplete() then CompleteRun() end
        end
    elseif (currentRun.active or currentRun.completed) and not _isInChallengeMode() then
        -- M+ cleared and we're no longer in a M+ instance. Salvage as
        -- completion if the last criteria update saw it complete.
        if currentRun.active and IsDungeonComplete() then
            CompleteRun()
        else
            ResetRun()
        end
    end
end

-- Always-on (low-frequency) events: enough to detect a key starting.
local _ALWAYS_EVENTS = {
    "PLAYER_ENTERING_WORLD", "CHALLENGE_MODE_START", "CHALLENGE_MODE_COMPLETED",
    "CHALLENGE_MODE_RESET", "WORLD_STATE_TIMER_START", "WORLD_STATE_TIMER_STOP",
}
-- High-frequency events: only needed during an active run. SCENARIO_CRITERIA_UPDATE
-- fires constantly in any scenario (pet battles, world quest scenarios, garrisons,
-- etc.); ZONE_CHANGED_NEW_AREA fires on every subzone crossing while questing.
-- Registering them only during a key keeps idle CPU at zero.
local _RUN_EVENTS = { "SCENARIO_CRITERIA_UPDATE", "ZONE_CHANGED_NEW_AREA" }

local function _registerRunEvents()
    for _, ev in ipairs(_RUN_EVENTS) do runtimeFrame:RegisterEvent(ev) end
end
local function _unregisterRunEvents()
    for _, ev in ipairs(_RUN_EVENTS) do runtimeFrame:UnregisterEvent(ev) end
end

for _, ev in ipairs(_ALWAYS_EVENTS) do runtimeFrame:RegisterEvent(ev) end
runtimeFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        ApplyStandalonePosition()
        -- API data isn't fully populated at PEW; retry once after 10s
        -- to catch a /reload mid-key.
        C_Timer.After(10, function() HandleRuntimeEvent("PLAYER_ENTERING_WORLD_DELAYED") end)
    end
    HandleRuntimeEvent(event)

    -- Toggle high-frequency event subscriptions based on whether we're
    -- actually in a key. Outside M+ we don't want to wake on every quest
    -- update or subzone change.
    if currentRun.active then
        _registerRunEvents()
    else
        _unregisterRunEvents()
    end
end)

-------------------------------------------------------------------------------
--  Heroic Dungeon / Raid run tracker (MT-2)
--  Own clock (GetTime), boss-kill snapshots, group death count. Independent of
--  the Challenge-Mode path above (which is API-driven). A run goes from the
--  first pull in the instance until the last boss dies; completion is detected
--  via a learned boss count per instance (finalised on zone-out the first time
--  the count is still unknown). Per-boss splits compare against the best time
--  EVER reached up to that boss index (not just the best overall run).
-------------------------------------------------------------------------------
local GR = { active = false, _groupGUIDs = {}, bosses = {} }
_G._OUIGT_GroupRun = GR  -- always available so the overlay can show the armed/ready state
local GR_Complete  -- forward (used by GR_BossKill)

local function GR_StatsStore(category, instKey)
    if not (db and db.profile) then return nil end
    db.profile.stats = db.profile.stats or {}
    local cat = db.profile.stats[category]
    if not cat then cat = {}; db.profile.stats[category] = cat end
    local s = cat[instKey]
    if not s then s = { runs = {}, bestSplits = {}, bossCount = 0 }; cat[instKey] = s end
    s.runs       = s.runs or {}
    s.bestSplits = s.bestSplits or {}
    s.bossCount  = s.bossCount or 0
    return s
end
_G._OUIGT_StatsStore = GR_StatsStore

-- ---------------------------------------------------------------------------
--  Encounter Journal: canonical boss list per dungeon. Knowing the bosses up
--  front gives us the boss count (no need to learn it over a first run), real
--  boss names in the statistics, and a reliable "last boss = run complete".
-- ---------------------------------------------------------------------------
local _ejBossCache = {}
local function GR_EnsureEJ()
    if EncounterJournal then return true end
    local loader = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
    if loader then pcall(loader, "Blizzard_EncounterJournal") end
    return EncounterJournal ~= nil
end

local function GR_FindJournalInstance(instName, isRaid)
    if not (EJ_GetNumTiers and EJ_SelectTier and EJ_GetInstanceByIndex) then return nil end
    for t = 1, (EJ_GetNumTiers() or 0) do
        pcall(EJ_SelectTier, t)
        local i = 1
        while true do
            local jid, name = EJ_GetInstanceByIndex(i, isRaid)
            if not jid then break end
            if name == instName then return jid end
            i = i + 1
        end
    end
    return nil
end

-- ordered boss names for a dungeon/raid by its in-game instance name (cached)
local function GR_JournalBosses(instName)
    if not instName then return nil end
    if _ejBossCache[instName] ~= nil then return _ejBossCache[instName] end
    GR_EnsureEJ()
    if not (EJ_SelectInstance and EJ_GetEncounterInfoByIndex) then return nil end
    local jid = GR_FindJournalInstance(instName, false) or GR_FindJournalInstance(instName, true)
    if not jid then _ejBossCache[instName] = false; return nil end
    local names = {}
    pcall(EJ_SelectInstance, jid)
    local i = 1
    while true do
        local name = EJ_GetEncounterInfoByIndex(i, jid)
        if not name then break end
        names[#names + 1] = name
        i = i + 1
    end
    _ejBossCache[instName] = (#names > 0) and names or false
    return _ejBossCache[instName] or nil
end
_G._OUIGT_JournalBosses = function(name) return GR_JournalBosses(name) end

-- seed a stats store with the journal boss list + count
local function GR_ApplyJournalBosses(store, instName)
    if not store or not instName then return end
    if store._journalApplied then return end
    local names = GR_JournalBosses(instName)
    if not names then return end
    store._journalApplied = true
    store.bossOrder = names
    store.bossCount = #names                    -- canonical full-clear count
    store.bossNames = store.bossNames or {}
    for i, n in ipairs(names) do
        if not store.bossNames[i] then store.bossNames[i] = n end
    end
end

-- category ("HEROIC"|"RAID"|nil), instance key, display name, difficultyID
-- Identify a specific raid lockout so a multi-day raid can be resumed only for
-- the SAME lock (same map + difficulty + saved-instance lock id). Falls back to
-- map:difficulty if the saved-instance lock id can't be resolved.
local function GR_LockKey(mapID, diffID, name)
    if GetNumSavedInstances and GetSavedInstanceInfo then
        for i = 1, (GetNumSavedInstances() or 0) do
            local iname, lockId, reset, idiff = GetSavedInstanceInfo(i)
            if iname and name and iname == name and (idiff == nil or idiff == diffID) then
                return format("%d:%d:%s", mapID, diffID or 0, tostring(lockId or reset or 0))
            end
        end
    end
    return format("%d:%d", mapID, diffID or 0)
end

local function GR_Context()
    if not GetInstanceInfo then return nil end
    local name, itype, diffID, _, _, _, _, mapID = GetInstanceInfo()
    mapID = mapID or 0
    if itype == "party" then
        if diffID == 8 then return nil end   -- Challenge Mode: handled by the CM engine
        return "HEROIC", format("%d:%d", mapID, diffID or 0), name, diffID, mapID
    elseif itype == "scenario" then
        return "HEROIC", format("%d:%d", mapID, diffID or 0), name, diffID, mapID
    elseif itype == "raid" then
        return "RAID", format("%d:%d", mapID, diffID or 0), name, diffID, mapID
    end
    return nil
end

local function GR_RefreshGroupGUIDs()
    wipe(GR._groupGUIDs)
    local pg = UnitGUID and UnitGUID("player")
    if pg then GR._groupGUIDs[pg] = true end
    local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    local raid = IsInRaid and IsInRaid()
    for i = 1, n do
        local u = (raid and "raid" or "party") .. i
        local g = UnitGUID and UnitGUID(u)
        if g then GR._groupGUIDs[g] = true end
    end
end

local function GR_Reset()
    GR.active = false
    GR.category, GR.instKey, GR.instName = nil, nil, nil
    GR.startTime, GR.elapsed, GR.deaths = 0, 0, 0
    wipe(GR.bosses)
end

local grFrame = CreateFrame("Frame")

local function GR_Start(category, instKey, instName, lockKey, resumeRec)
    GR.active   = true
    GR.category = category
    GR.instKey  = instKey
    GR.instName = instName
    GR.lockKey  = lockKey
    GR.player   = UnitGUID and UnitGUID("player")
    if resumeRec then
        -- multi-day raid: continue from the saved active time + snapshots
        GR.deaths  = resumeRec.deaths or 0
        wipe(GR.bosses)
        for i, b in ipairs(resumeRec.bosses or {}) do GR.bosses[i] = b end
        GR.elapsed   = resumeRec.elapsed or 0
        GR.startTime = GetTime() - GR.elapsed
        if db and db.profile and db.profile.suspended and lockKey then
            db.profile.suspended[lockKey] = nil  -- consume the suspended record
        end
    else
        GR.startTime = GetTime()
        GR.elapsed, GR.deaths = 0, 0
        wipe(GR.bosses)
    end
    GR_RefreshGroupGUIDs()
    GR._wasInRaidGroup = (IsInRaid and IsInRaid()) or false
    _G._OUIGT_LastRun = nil   -- a new run replaces any post-run review
    -- seed the run's own store here (stable instKey/difficulty): readable name +
    -- the journal boss list / count, so the name shows and completion is known
    local store = GR_StatsStore(category, instKey)
    if store then
        store.name = instName or store.name
        GR_ApplyJournalBosses(store, instName)
    end
    grFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    _G._OUIGT_GroupRun = GR
    if _G._OUIGT_StandaloneRefresh then _G._OUIGT_StandaloneRefresh() end
end

local function GR_BossKill(bossName)
    if not GR.active then return end
    local elapsed = GetTime() - GR.startTime
    GR.elapsed = elapsed
    local idx   = #GR.bosses + 1
    local store = GR_StatsStore(GR.category, GR.instKey)
    -- best time EVER reached up to this boss index (per-boss, across all runs)
    local prevBest = store and store.bestSplits[idx]
    local isBest   = (not prevBest) or elapsed < prevBest
    if store and isBest then store.bestSplits[idx] = elapsed end
    if store then
        store.name = GR.instName or store.name
        store.bossNames = store.bossNames or {}
        if bossName then store.bossNames[idx] = bossName end   -- real name per index
    end
    GR.bosses[idx] = {
        name    = bossName or ("Boss " .. idx),
        elapsed = elapsed,
        deaths  = GR.deaths,
        best    = prevBest,   -- best-ever-to-this-boss for delta display (nil = first ever)
        isBest  = isBest,
    }
    -- completion: learned boss count reached? (all bosses down = full clear)
    if store and store.bossCount > 0 and idx >= store.bossCount then
        GR_Complete(true)
    else
        if _G._OUIGT_StandaloneRefresh then _G._OUIGT_StandaloneRefresh() end
    end
end

GR_Complete = function(definitive)
    if not GR.active then return end
    GR.active = false
    grFrame:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    if not GR.elapsed or GR.elapsed <= 0 then GR.elapsed = GetTime() - GR.startTime end
    local store = GR_StatsStore(GR.category, GR.instKey)
    if store then
        local bossNames, splits = {}, {}
        for i, b in ipairs(GR.bosses) do bossNames[i] = b.name; splits[i] = b.elapsed end
        -- A definitive completion (dungeon/scenario reward, or all journal bosses
        -- down) is a full clear even when the journal boss count is unknown.
        local fullClear = definitive or (store.bossCount > 0 and #GR.bosses >= store.bossCount)
        local run = {
            total = GR.elapsed, deaths = GR.deaths, splits = splits, bossNames = bossNames,
            date = time(), completed = fullClear, bossCount = #GR.bosses, instName = GR.instName,
        }
        store.name = GR.instName or store.name
        if #GR.bosses > store.bossCount then store.bossCount = #GR.bosses end
        -- "best completion" only counts a FULL clear; per-boss bests update always
        if fullClear and (not store.best or GR.elapsed < (store.best.total or math.huge)) then
            store.best = { total = GR.elapsed, deaths = GR.deaths, splits = splits,
                           bossNames = bossNames, date = run.date }
        end
        table.insert(store.runs, 1, run)
        local CAP = (db and db.profile and db.profile.statsHistory) or 20
        while #store.runs > CAP do table.remove(store.runs) end
    end
    -- a resumed/suspended lock is now resolved
    if db and db.profile and db.profile.suspended and GR.lockKey then
        db.profile.suspended[GR.lockKey] = nil
    end
    -- snapshot for the post-run review overlay (shown until zone-out, so the
    -- group can read the result without opening the stats window)
    local snapBosses = {}
    for i, b in ipairs(GR.bosses) do
        snapBosses[i] = { name = b.name, elapsed = b.elapsed, best = b.best }
    end
    _G._OUIGT_LastRun = {
        category = GR.category, instKey = GR.instKey, instName = GR.instName,
        elapsed = GR.elapsed, deaths = GR.deaths, bosses = snapBosses,
    }
    _G._OUIGT_GroupRun = GR  -- keep for display until next run/reset
    if _G._OUIGT_StandaloneRefresh then _G._OUIGT_StandaloneRefresh() end
end

-- Multi-day raid: freeze the active time + snapshots under the raid lock so the
-- next pull in the SAME lockout resumes the timer.
local function GR_Suspend()
    if not GR.active then return end
    GR.active = false
    grFrame:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    GR.elapsed = GetTime() - GR.startTime
    if db and db.profile and GR.lockKey then
        db.profile.suspended = db.profile.suspended or {}
        local bcopy = {}
        for i, b in ipairs(GR.bosses) do bcopy[i] = b end
        db.profile.suspended[GR.lockKey] = {
            category = GR.category, instKey = GR.instKey, instName = GR.instName, lockKey = GR.lockKey,
            elapsed = GR.elapsed, deaths = GR.deaths, bosses = bcopy,
            player = GR.player or (UnitGUID and UnitGUID("player")), savedAt = time(),
        }
    end
    GR._promptPending = nil
    GR_Reset()
    if _G._OUIGT_StandaloneRefresh then _G._OUIGT_StandaloneRefresh() end
end

-- On leaving an unfinished raid: ask whether to continue it later (suspend) or
-- record it now as-is (finish).
local function GR_PromptContinue()
    if GR._promptPending or not GR.active then return end
    GR._promptPending = true
    if OldschoolUI.ShowConfirmPopup then
        OldschoolUI:ShowConfirmPopup({
            title       = GR.instName or "?",
            message     = "This raid isn't finished. Continue it later? Choose 'Finish now' to record it as-is.",
            confirmText = "Continue later",
            cancelText  = "Finish now",
            onConfirm   = function() GR_Suspend() end,
            onCancel    = function() GR._promptPending = nil; GR_Complete() end,
        })
    else
        GR_Suspend()  -- no popup available -> default to the non-destructive choice
    end
end

local function GR_Finalize()
    if not GR.active then return end
    if GR.category == "RAID" and #GR.bosses > 0 then
        local store = GR_StatsStore(GR.category, GR.instKey)
        local fullClear = store and store.bossCount > 0 and #GR.bosses >= store.bossCount
        if fullClear then GR_Complete() else GR_PromptContinue() end
    elseif #GR.bosses > 0 then
        GR_Complete()
    else
        grFrame:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        GR_Reset()
        if _G._OUIGT_StandaloneRefresh then _G._OUIGT_StandaloneRefresh() end
    end
end
_G._OUIGT_GR_Finalize = GR_Finalize

-- Record a completed Challenge-Mode run into the unified stats store so the
-- stats window covers all three categories with one schema.
_G._OUIGT_RecordCM = function(run)
    if not run or not run.mapID then return end
    local store = GR_StatsStore("CHALLENGE", tostring(run.mapID))
    if not store then return end
    local bossNames, splits = {}, {}
    for _, obj in ipairs(run.objectives or {}) do
        if obj and obj.elapsed and obj.elapsed > 0 then
            local n = #splits + 1
            splits[n]    = obj.elapsed
            bossNames[n] = (StripDefeated and StripDefeated(obj.name)) or obj.name or ("Objective " .. n)
            local prev = store.bestSplits[n]
            if not prev or obj.elapsed < prev then store.bestSplits[n] = obj.elapsed end
        end
    end
    store.name = run.mapName or store.name
    if #bossNames > store.bossCount then store.bossCount = #bossNames end
    local total = run.elapsed or 0
    if total > 0 and (not store.best or total < (store.best.total or math.huge)) then
        store.best = { total = total, deaths = run.deaths or 0, splits = splits,
                       bossNames = bossNames, date = time() }
    end
    table.insert(store.runs, 1, {
        total = total, deaths = run.deaths or 0, splits = splits, bossNames = bossNames,
        date = time(), completed = true, bossCount = #bossNames, instName = run.mapName,
    })
    local CAP = (db and db.profile and db.profile.statsHistory) or 20
    while #store.runs > CAP do table.remove(store.runs) end
end

grFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
grFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
grFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
grFrame:RegisterEvent("ENCOUNTER_END")
grFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
-- reliable dungeon/scenario completion (independent of boss-count guesses)
pcall(grFrame.RegisterEvent, grFrame, "LFG_COMPLETION_REWARD")
pcall(grFrame.RegisterEvent, grFrame, "SCENARIO_COMPLETED")
pcall(grFrame.RegisterEvent, grFrame, "PLAYER_UNGHOST")
pcall(grFrame.RegisterEvent, grFrame, "PLAYER_ALIVE")
grFrame:SetScript("OnEvent", function(_, event, ...)
    if not (db and db.profile and db.profile.enabled) then return end
    -- Challenge-Mode runs are tracked by the API path; never double-track.
    -- Only defer while a CM run is actually live (a stale `completed` display
    -- state must not block heroic/scenario/raid tracking).
    if currentRun._sim then return end
    if currentRun.active or _isInChallengeMode() then return end

    if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        local cat, key, name, diff, mapID = GR_Context()
        if not cat then
            -- A corpse run can drop you at a graveyard outside the instance,
            -- briefly clearing the instance context. Don't end the run while
            -- dead/ghost: the timer keeps running and resumes when you zone
            -- back in (the same-instKey guard below prevents a restart).
            if GR.active and not (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")) then
                GR_Finalize()
            end
            if not (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")) then
                _G._OUIGT_LastRun = nil   -- left the instance: drop the post-run review
            end
            GR._armed = nil
        else
            if GR.active and GR.instKey ~= key then GR_Finalize() end
            local lockKey = (cat == "RAID") and GR_LockKey(mapID, diff, name) or nil
            local resume
            if cat == "RAID" and lockKey and db.profile.suspended then
                local rec = db.profile.suspended[lockKey]
                local pg  = UnitGUID and UnitGUID("player")
                if rec and (not rec.player or rec.player == pg) then resume = rec end
            end
            GR._armed = { cat = cat, key = key, name = name, lockKey = lockKey, resume = resume }
            GR_RefreshGroupGUIDs()
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        if GR._armed and not GR.active then
            GR_Start(GR._armed.cat, GR._armed.key, GR._armed.name, GR._armed.lockKey, GR._armed.resume)
        end
    elseif event == "ENCOUNTER_END" then
        local _, encName, _, _, success = ...
        if GR.active and success == 1 then GR_BossKill(encName) end
    elseif event == "LFG_COMPLETION_REWARD" or event == "SCENARIO_COMPLETED" then
        if GR.active then GR_Complete(true) end   -- dungeon/scenario finished
    elseif event == "PLAYER_UNGHOST" or event == "PLAYER_ALIVE" then
        -- resurrected outside the run's instance -> the run was abandoned
        if GR.active and not GR_Context() then GR_Finalize() end
    elseif event == "GROUP_ROSTER_UPDATE" then
        local inRaid = IsInRaid and IsInRaid()
        if GR.active and GR.category == "RAID" and GR._wasInRaidGroup and not inRaid then
            GR_Finalize()  -- left the raid group mid-run -> suspend/finish prompt
        else
            if inRaid then GR._wasInRaidGroup = true end
            if GR.active or GR._armed then GR_RefreshGroupGUIDs() end
        end
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        if not GR.active then return end
        local _, sub, _, _, _, _, _, destGUID = CombatLogGetCurrentEventInfo()
        if sub == "UNIT_DIED" and destGUID and GR._groupGUIDs[destGUID] then
            GR.deaths = GR.deaths + 1
        end
    end
end)

-- /ouigt gr : inspect current group-run + quick stats (in-game verify helper)
_G._OUIGT_GroupRunDump = function()
    local p = function(s) print("|cffD9A441OUI GroupTimer:|r " .. s) end
    if GR.active then
        p(("active %s in %s  elapsed=%.0fs  bosses=%d  deaths=%d")
            :format(tostring(GR.category), tostring(GR.instName or GR.instKey),
                    (GetTime() - GR.startTime), #GR.bosses, GR.deaths))
        for i, b in ipairs(GR.bosses) do
            print(("   %d. %s  @%.0fs  (best %s)  deaths=%d")
                :format(i, b.name, b.elapsed, b.best and ("%.0fs"):format(b.best) or "-", b.deaths))
        end
    else
        p("no active heroic/raid run. Armed: " .. tostring(GR._armed and GR._armed.cat or "no"))
    end
end

-------------------------------------------------------------------------------
function GT:OnInitialize()
    db = LibStub("AceDB-3.0"):New("OldschoolUIGroupTimerDB", DB_DEFAULTS)
    _G._OUIGT_AceDB = db

    if db and db.profile then
        local pp = db.profile
        for key, value in pairs(DB_DEFAULTS.profile) do
            if pp[key] == nil then
                pp[key] = type(value) == "table" and CopyTable(value) or value
            end
        end
        -- showPreview is a transient options-panel state. /reload doesn't fire
        -- the OUI window's OnHide auto-off, so the saved value can persist
        -- as true across reloads. Force it off at every login.
        pp.showPreview = false
    end

    -- Season-based data purge: clear split records from previous seasons.
    C_Timer.After(2, function()
        if not db or not db.profile then return end
        local currentMaps = C_ChallengeMode.GetMapTable()
        if not currentMaps or #currentMaps == 0 then return end

        local validMapIDs = {}
        for _, mapID in ipairs(currentMaps) do
            validMapIDs[mapID] = true
        end

        if db.profile.bestObjectiveSplits then
            for scopeKey in pairs(db.profile.bestObjectiveSplits) do
                local mapIDStr = scopeKey:match("^(%d+)")
                local mapID = tonumber(mapIDStr)
                if mapID and not validMapIDs[mapID] then
                    db.profile.bestObjectiveSplits[scopeKey] = nil
                end
            end
        end
    end)

    -- runtimeFrame is now event-driven (registered above); no OnUpdate needed.
end

function GT:OnEnable()
    if OUI.IsModuleEnabled and not OUI:IsModuleEnabled("OUI_GroupTimer") then return end
    if not db or not db.profile.enabled then return end

    if OldschoolUI and OldschoolUI.RegisterUnlockElements and OldschoolUI.MakeUnlockElement then
        local MK = OldschoolUI.MakeUnlockElement
        OldschoolUI:RegisterUnlockElements({
            MK({
                key   = "EMT_GroupTimer",
                label = "Challenge Mode Timer",
                group = "Challenge Mode",
                order = 520,
                noResize = true,
                getFrame = function()
                    return _G._OUIGT_GetStandaloneFrame and _G._OUIGT_GetStandaloneFrame()
                end,
                getSize  = function()
                    local f = standaloneFrame
                    if f then return f:GetWidth(), f:GetHeight() end
                    return 260, 200
                end,
                isHidden = function()
                    return false
                end,
                savePos = function(_, point, relPoint, x, y)
                    -- Stored as delta in UIParent-logical units (matches the
                    -- migration in _ensureCenterPos). ApplyStandalonePosition
                    -- divides by profile.scale on apply; screen delta works
                    -- out to stored_UIlogical * UIParent:GetEffectiveScale().
                    --
                    -- f:GetCenter() returns coords in the frame's OWN scaled
                    -- units. At frame scale != 1 we must re-scale those to
                    -- UIParent-logical units before subtracting upX. Multiply
                    -- cx by (frame_effective / UIParent_effective) to land in
                    -- the same space as upX. Without this the stored offset
                    -- shrinks at larger scales and the frame snaps toward the
                    -- middle every time settings re-apply (e.g. Show Preview).
                    local f = standaloneFrame
                    if f and f:GetCenter() then
                        local cx, cy = f:GetCenter()
                        local upX, upY = UIParent:GetCenter()
                        local fes = f:GetEffectiveScale() or 1
                        local ues = UIParent:GetEffectiveScale() or 1
                        local ratio = fes / ues
                        db.profile.standalonePos = {
                            centerX = cx * ratio - upX,
                            centerY = cy * ratio - upY,
                        }
                    end
                    if f and not OldschoolUI._unlockActive then
                        local sx, sy = _centerPosFromSaved(db.profile.standalonePos)
                        if sx then
                            f:ClearAllPoints()
                            f:SetPoint("CENTER", UIParent, "CENTER", sx, sy)
                        end
                    end
                end,
                loadPos = function()
                    return db.profile.standalonePos
                end,
                clearPos = function()
                    db.profile.standalonePos = nil
                end,
                applyPos = function()
                    if standaloneFrame then ApplyStandalonePosition() end
                end,
            }),
        })
    end
end


-------------------------------------------------------------------------------
-- Simulation / debug commands (/ouigt)
--
-- Challenge Modes need a 5-player group, so this lets the timer + medal display
-- be developed solo. "/ouigt test" injects a fake run with a live clock and 5
-- medal thresholds; "/ouigt dump" prints what the real C_ChallengeMode API
-- returns on this client (to confirm the real medal count/times).
-------------------------------------------------------------------------------
do
    local simTicker
    -- Medal thresholds in seconds (order irrelevant; the renderer sorts).
    -- Diamond 6:00, Platinum 8:00, Gold 10:00, Silver 12:00, Bronze 14:00.
    local SIM_MEDALS = { 840, 720, 600, 480, 360 }
    -- The overall time limit equals the slowest medal (Bronze) in MoP.
    local SIM_MAX = 840

    local function StopSim()
        if simTicker then simTicker:Cancel(); simTicker = nil end
        if currentRun._sim then
            currentRun._sim = false
            ResetRun()
        end
        if _G._OUIGT_StandaloneRefresh then _G._OUIGT_StandaloneRefresh() end
    end

    local function StartSim()
        StopSim()
        wipe(currentRun.objectives)
        local mt = {}
        for i, v in ipairs(SIM_MEDALS) do mt[i] = v end
        currentRun._sim          = true
        currentRun.active        = true
        currentRun.completed     = false
        currentRun.mapID         = -1
        currentRun.mapName       = "Sim: Challenge Mode"
        currentRun.level         = 0
        currentRun.affixes       = {}
        currentRun.affixNames    = {}
        currentRun.maxTime       = SIM_MAX
        currentRun.medalTimes    = mt
        currentRun.numMedals     = #SIM_MEDALS
        currentRun.elapsed       = 0
        currentRun.deaths        = 0
        currentRun.deathTimeLost = 0
        currentRun.preciseStart  = nil
        if _G._OUIGT_StandaloneRefresh then _G._OUIGT_StandaloneRefresh() end
        simTicker = C_Timer.NewTicker(1, function()
            if not currentRun._sim then return end
            currentRun.elapsed = (currentRun.elapsed or 0) + 1
            if currentRun.elapsed > SIM_MAX + 30 then StopSim(); return end
            if _G._OUIGT_StandaloneRefresh then _G._OUIGT_StandaloneRefresh() end
        end)
        print("|cff66ccffOUI-GT|r Sim started (14:00 Bronze limit, 5 medals). /ouigt stop to end.")
    end

    local function DumpAPI()
        print("|cff66ccffOUI-GT|r Challenge Mode API dump:")
        local C = C_ChallengeMode
        if not C then print("  C_ChallengeMode not available"); return end
        local mapID = C.GetActiveChallengeMapID and C.GetActiveChallengeMapID()
        print("  active MapID:", tostring(mapID))
        if not mapID then
            local maps = C.GetMapTable and C.GetMapTable()
            if maps and maps[1] then mapID = maps[1]; print("  (none active; using first MapID)", mapID) end
        end
        if mapID then
            local name, _, timeLimit = C.GetMapUIInfo and C.GetMapUIInfo(mapID)
            print("  Name:", tostring(name), "Limit:", tostring(timeLimit))
            print("  GetNumMedals:", tostring(C.GetNumMedals and C.GetNumMedals(mapID)))
            local times = C.GetChallengeModeMapTimes and C.GetChallengeModeMapTimes(mapID)
            if type(times) == "table" then
                print("  GetChallengeModeMapTimes (#" .. #times .. "): " .. table.concat(times, ", "))
            else
                print("  GetChallengeModeMapTimes:", tostring(times))
            end
        end
    end

    SLASH_OUIGT1 = "/ouigt"
    SlashCmdList["OUIGT"] = function(msg)
        msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        if msg == "test" or msg == "sim" then
            StartSim()
        elseif msg == "stop" or msg == "off" then
            StopSim()
            print("|cff66ccffOUI-GT|r Sim stopped.")
        elseif msg == "dump" then
            DumpAPI()
        elseif msg == "stats" then
            if _G._OUIGT_ToggleStats then _G._OUIGT_ToggleStats() end
        elseif msg == "gr" then
            if _G._OUIGT_GroupRunDump then _G._OUIGT_GroupRunDump() end
        elseif msg == "where" then
            local name, itype, diffID, _, _, _, _, mapID = GetInstanceInfo()
            local cat = GR_Context and select(1, GR_Context())
            print(("|cff66ccffOUI-GT|r where: name=%s  type=%s  diff=%s  map=%s  -> category=%s")
                :format(tostring(name), tostring(itype), tostring(diffID), tostring(mapID), tostring(cat or "none (not tracked)")))
        else
            print("|cff66ccffOUI-GT|r Commands: /ouigt test | stop | dump | gr | stats | where")
        end
    end
end

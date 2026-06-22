-------------------------------------------------------------------------------
--  OUI_QoL_AutoLogging.lua -- toggles combat logging on zone transitions
--  based on instance type / difficulty. Forces advanced combat logging on.
--  Shares the OUI_QoL addon namespace/DB.
-------------------------------------------------------------------------------
local _, ns = ...

-- MoP difficulty IDs: 2 = Heroic 5-man, 7 = LFR, 8 = Challenge Mode,
-- 11/12 = Heroic/Normal Scenario; raids report zoneType == "raid".
local STOP_DELAY = 30

local function cfg(k, default)
    local v = ns.db and ns.db.profile[k]
    if v == nil then return default end
    return v
end

local function ensureAdvanced()
    if GetCVar and GetCVar("advancedCombatLogging") ~= "1" then
        SetCVar("advancedCombatLogging", 1)
    end
end

local function zoneShouldLog()
    if not cfg("autoLog", false) then return false end
    local _, zoneType, rawDiff = GetInstanceInfo()
    local diff = tonumber(rawDiff) or 0

    if zoneType == "raid" then
        if diff == 7 then return cfg("logLFR", false) end
        return cfg("logRaid", true)
    end
    if zoneType == "party" and diff == 2 then return cfg("logHeroicDungeon", true) end
    if diff == 8 then return cfg("logChallenge", true) end
    if zoneType == "scenario" then return cfg("logScenario", false) end
    return false
end

local wasLogging, stopTimer = false, nil

local function cancelStop()
    if stopTimer then stopTimer:Cancel(); stopTimer = nil end
end

local function applyLogging()
    local should = zoneShouldLog()
    if should then
        cancelStop()
        ensureAdvanced()
        if not LoggingCombat() then LoggingCombat(true) end
    elseif wasLogging and LoggingCombat() then
        if cfg("logDelayStop", true) then
            if not stopTimer then
                stopTimer = C_Timer.NewTimer(STOP_DELAY, function()
                    stopTimer = nil
                    if LoggingCombat() then LoggingCombat(false) end
                end)
            end
        else
            LoggingCombat(false)
        end
    end
    wasLogging = should
end
ns.RefreshAutoLogging = applyLogging

function ns.SetupAutoLogging()
    if ns._autoLogFrame then return end
    local f = CreateFrame("Frame")
    ns._autoLogFrame = f
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    f:RegisterEvent("PLAYER_DIFFICULTY_CHANGED")
    f:SetScript("OnEvent", function(_, event)
        if event == "ZONE_CHANGED_NEW_AREA" then
            C_Timer.After(2, applyLogging)
        else
            applyLogging()
        end
    end)
end

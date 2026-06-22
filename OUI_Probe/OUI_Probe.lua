-- ===========================================================================
--  OUI Probe — diagnostic API dumper
--  Standalone, no dependencies. Records the live values of the WoW APIs the
--  OldschoolUI rewrite needs (spec detection, power-type enum, per-resource
--  UnitPower/UnitPowerMax, legacy resource accessors) for whichever character
--  it is run on, accumulating into one SavedVariables table across characters.
--
--  Usage: log into a character, type /ouiprobe, then /reload (to flush the
--  SavedVariables to disk), and send the resulting OUI_Probe.lua file.
--
--  This is a throwaway diagnostic tool, not part of the addon suite.
-- ===========================================================================

OUIProbeDB = OUIProbeDB or {}

local f = CreateFrame("Frame")

-- Try a call safely; return a printable description of the result.
local function tryCall(fn, ...)
    if type(fn) ~= "function" then return nil, "absent" end
    local ok, a, b, c, d, e, g = pcall(fn, ...)
    if not ok then return nil, "error" end
    return { a, b, c, d, e, g }, "ok"
end

-- Snapshot which candidate APIs exist + what they return, so we learn the
-- correct spec-detection path for this client (global GetSpecialization is nil
-- on at least some MoP Classic builds; C_SpecializationInfo may hold it).
local function probeSpecAPIs()
    local out = {}

    local function note(label, present, value)
        out[label] = { present = present, value = value }
    end

    -- global candidates
    note("GetSpecialization", type(GetSpecialization),
        type(GetSpecialization) == "function" and (GetSpecialization()) or nil)
    note("GetNumSpecializations", type(GetNumSpecializations),
        type(GetNumSpecializations) == "function" and (GetNumSpecializations()) or nil)
    note("GetActiveSpecGroup", type(GetActiveSpecGroup),
        type(GetActiveSpecGroup) == "function" and (GetActiveSpecGroup()) or nil)
    note("GetActiveTalentGroup", type(GetActiveTalentGroup),
        type(GetActiveTalentGroup) == "function" and (GetActiveTalentGroup()) or nil)
    note("GetPrimaryTalentTree", type(GetPrimaryTalentTree),
        type(GetPrimaryTalentTree) == "function" and (GetPrimaryTalentTree()) or nil)
    note("GetSpecializationRole", type(GetSpecializationRole), nil)

    -- C_SpecializationInfo namespace
    if type(C_SpecializationInfo) == "table" then
        local csi = C_SpecializationInfo
        note("C_SpecializationInfo", "table", nil)
        note("C_SpecializationInfo.GetSpecialization", type(csi.GetSpecialization),
            type(csi.GetSpecialization) == "function" and (csi.GetSpecialization()) or nil)
        note("C_SpecializationInfo.GetActiveSpecGroup", type(csi.GetActiveSpecGroup),
            type(csi.GetActiveSpecGroup) == "function" and (csi.GetActiveSpecGroup()) or nil)
    else
        note("C_SpecializationInfo", type(C_SpecializationInfo), nil)
    end

    -- Resolve the active spec index by whichever method works, then pull its
    -- full info via GetSpecializationInfo(index).
    local idx
    if type(GetSpecialization) == "function" then idx = GetSpecialization() end
    if idx == nil and type(C_SpecializationInfo) == "table"
       and type(C_SpecializationInfo.GetSpecialization) == "function" then
        idx = C_SpecializationInfo.GetSpecialization()
    end
    out._activeIndex = idx

    if idx and type(GetSpecializationInfo) == "function" then
        local id, name, desc, icon, _, role = GetSpecializationInfo(idx)
        out._specInfo = { id = id, name = name, role = role }
    end
    return out
end

-- Dump Enum.PowerType (authoritative mapping for this client) if present.
local function dumpPowerEnum()
    if type(Enum) ~= "table" or type(Enum.PowerType) ~= "table" then return nil end
    local out = {}
    for k, v in pairs(Enum.PowerType) do
        if type(v) == "number" then out[k] = v end
    end
    return out
end

-- Probe UnitPower / UnitPowerMax for every plausible power index, recording any
-- with a nonzero current or max (i.e. resources this spec actually uses).
local function probePower()
    local out = {}
    for n = 0, 30 do
        local okC, cur = pcall(UnitPower, "player", n)
        local okM, max = pcall(UnitPowerMax, "player", n)
        cur = okC and cur or 0
        max = okM and max or 0
        if (type(cur) == "number" and cur ~= 0) or (type(max) == "number" and max ~= 0) then
            out[n] = { cur = cur, max = max }
        end
    end
    return out
end

-- Legacy / resource-specific accessors that may or may not exist in this build.
local function probeLegacy()
    local out = {}
    if type(GetComboPoints) == "function" then
        local ok, cp = pcall(GetComboPoints, "player", "target")
        out.GetComboPoints_target = ok and cp or "error"
        local ok2, cp2 = pcall(GetComboPoints, "player")
        out.GetComboPoints_self = ok2 and cp2 or "error"
    else
        out.GetComboPoints = "absent"
    end
    if type(GetEclipseDirection) == "function" then
        local ok, dir = pcall(GetEclipseDirection)
        out.GetEclipseDirection = ok and dir or "error"
    else
        out.GetEclipseDirection = "absent"
    end
    -- Old global power constants (existed in original MoP; may be gone now).
    for _, name in ipairs({
        "SPELL_POWER_ECLIPSE", "SPELL_POWER_SHADOW_ORBS", "SPELL_POWER_BURNING_EMBERS",
        "SPELL_POWER_DEMONIC_FURY", "SPELL_POWER_CHI", "SPELL_POWER_HOLY_POWER",
        "SPELL_POWER_SOUL_SHARDS",
    }) do
        out[name] = _G[name]  -- numeric value or nil
    end
    return out
end

local function runProbe(verbose)
    local name = UnitName("player") or "?"
    local locClass, classFile = UnitClass("player")
    local key = (classFile or "UNK") .. ":" .. name .. "-" .. (GetRealmName() or "?")

    local rec = {
        name        = name,
        realm       = GetRealmName(),
        class       = locClass,
        classFile   = classFile,
        level       = UnitLevel("player"),
        race        = select(1, UnitRace("player")),
        locale      = GetLocale(),
        clientBuild = select(2, GetBuildInfo()),
        spec        = probeSpecAPIs(),
        powerEnum   = dumpPowerEnum(),
        power       = probePower(),
        legacy      = probeLegacy(),
        stamp       = date and date("%Y-%m-%d %H:%M") or time(),
    }
    OUIProbeDB[key] = rec

    if verbose then
        local sp = rec.spec or {}
        local si = sp._specInfo or {}
        print("|cff33ff99[OUI Probe]|r " .. (classFile or "?") .. " / " ..
            (si.name or ("specIdx=" .. tostring(sp._activeIndex))) ..
            " (" .. tostring(si.role) .. ")")
        local used = {}
        for n, v in pairs(rec.power) do used[#used + 1] = n .. "(max " .. v.max .. ")" end
        table.sort(used)
        print("|cff33ff99[OUI Probe]|r active power indices: " ..
            (#used > 0 and table.concat(used, ", ") or "none"))
        print("|cff33ff99[OUI Probe]|r saved as '" .. key ..
            "'. Type /reload, then send the OUI_Probe.lua SavedVariables file.")
    end
end

f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
f:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
f:SetScript("OnEvent", function(_, event)
    -- Re-probe silently after world enter / spec swap so the saved record is
    -- always current; the verbose summary is reserved for the slash command.
    C_Timer.After(2, function() runProbe(false) end)
end)

SLASH_OUIPROBE1 = "/ouiprobe"
SlashCmdList["OUIPROBE"] = function() runProbe(true) end

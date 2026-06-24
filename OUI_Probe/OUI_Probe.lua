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

-- ===========================================================================
--  Taint scanner (/ouiprobe taint)
--  Walks the ESC-close chain (UISpecialFrames + the GameMenu/Logout globals)
--  and reports, per entry, whether the reference is still secure or has been
--  tainted -- and by which addon. Results are stored in OUIProbeDB.taint so they
--  survive a /reload and can be sent.
--
--  LIMITATION (told honestly): issecurevariable reports taint that PERSISTS at
--  the moment of scanning. The classic Logout failure is a *contextual*
--  CloseSpecialWindows cascade that only taints during the ESC keypress and
--  clears afterwards, so a chat-triggered scan may show everything "secure" even
--  though ESC->Logout just failed. This catches persistently-tainted frames/
--  globals; for the contextual cascade, `/console taintLog 2` stays authoritative.
-- ===========================================================================
local TAINT_GLOBALS = {
    "ToggleGameMenu", "CloseSpecialWindows", "CloseAllWindows", "CloseMenus",
    "GameMenuFrame", "UIParent", "Logout", "Quit", "ShowUIPanel", "HideUIPanel",
}

-- Returns "secure" | "TAINT:<addon>" | "TAINT:?" | "n/a"
local function checkVar(name, key)
    local ok, secure, addon
    if key ~= nil then ok, secure, addon = pcall(issecurevariable, name, key)
    else                ok, secure, addon = pcall(issecurevariable, name) end
    if not ok then return "n/a" end
    if secure then return "secure" end
    return "TAINT:" .. tostring(addon or "?")
end

local function scanTaint(verbose)
    local res = {
        stamp    = (date and date("%Y-%m-%d %H:%M:%S")) or time(),
        char     = (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?"),
        build    = select(2, GetBuildInfo()),
        combat   = InCombatLockdown() and true or false,
        globals  = {},
        specials = {},
        suspects = {},
    }
    for _, g in ipairs(TAINT_GLOBALS) do
        local v = checkVar(g)
        res.globals[g] = v
        if v:sub(1, 5) == "TAINT" then res.suspects[#res.suspects + 1] = g .. " = " .. v end
    end
    if type(UISpecialFrames) == "table" then
        for i = 1, #UISpecialFrames do
            local name  = UISpecialFrames[i]
            local frame = name and _G[name]
            local v     = name and checkVar(name) or "n/a"
            local shown = frame and frame.IsShown and frame:IsShown() or false
            res.specials[#res.specials + 1] =
                { idx = i, name = name, exists = frame ~= nil, shown = shown, taint = v }
            if type(v) == "string" and v:sub(1, 5) == "TAINT" then
                res.suspects[#res.suspects + 1] = ("UISpecialFrames[%d]=%s -> %s"):format(i, tostring(name), v)
            end
        end
    end
    OUIProbeDB.taint = OUIProbeDB.taint or {}
    OUIProbeDB.taint[res.char] = res

    if verbose then
        print("|cff33ff99[OUI Probe taint]|r " .. res.char .. " build " .. tostring(res.build) ..
            (res.combat and " |cffff8800(in combat)|r" or ""))
        for _, g in ipairs(TAINT_GLOBALS) do
            local v   = res.globals[g]
            local col = (v == "secure") and "|cff66ff66" or "|cffff4444"
            print(("   %s%s|r = %s"):format(col, g, tostring(v)))
        end
        if #res.suspects > 0 then
            print("|cffff4444  SUSPECTS (persistently tainted):|r")
            for _, s in ipairs(res.suspects) do print("   - " .. s) end
        else
            print("|cff66ff66  no PERSISTENT taint on the ESC chain right now.|r")
            print("   If ESC->Logout still fails, the cascade is contextual:")
            print("   /console taintLog 2  ->  reproduce  ->  read Logs/taint.log")
        end
        print(("  %d special frames scanned; saved to OUIProbeDB.taint['%s'].")
            :format(#res.specials, res.char))
        print("  /reload to flush, then send the OUI_Probe.lua SavedVariables file.")
    end
    return res
end

f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
f:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
f:SetScript("OnEvent", function(_, event)
    -- Re-probe silently after world enter / spec swap so the saved record is
    -- always current; the verbose summary is reserved for the slash command.
    C_Timer.After(2, function() runProbe(false) end)
end)

-- ===========================================================================
--  Frame structure dumper (/ouiprobe dump <GlobalFrameName>)
--  Walks a frame's regions + child frames (one level, plus grandchild names),
--  resolving the FIELD KEY each object is stored under on its parent (e.g.
--  MountJournal.MountDisplay) so reskins can target real names instead of
--  guessing. Saved to OUIProbeDB.frames so it survives /reload and can be sent.
-- ===========================================================================
local DUMP_DEFAULTS = {
    "CollectionsJournal", "MountJournal", "PetJournal",
    "MailFrame", "InboxFrame", "OpenMailFrame", "SendMailFrame",
}

-- which key on `parent` holds `obj` (Blizzard stores named subframes as keys)
local function fieldKey(parent, obj)
    local ok, res = pcall(function()
        for k, v in pairs(parent) do
            if v == obj and type(k) == "string" then return k end
        end
    end)
    return ok and res or nil
end

-- safe wrappers: GetChildren/GetRegions can raise on non-frame objects
local function safeChildren(obj)
    if not obj or not obj.GetChildren then return {} end
    local ok, res = pcall(function() return { obj:GetChildren() } end)
    return (ok and res) or {}
end
local function safeRegions(obj)
    if not obj or not obj.GetRegions then return {} end
    local ok, res = pcall(function() return { obj:GetRegions() } end)
    return (ok and res) or {}
end

local function regionInfo(parent, r)
    local layer = r.GetDrawLayer and select(1, r:GetDrawLayer())
    return {
        kind  = r.GetObjectType and r:GetObjectType(),
        key   = fieldKey(parent, r),
        gname = r.GetName and r:GetName() or nil,
        layer = layer,
        tex   = r.GetTexture and r:GetTexture() or nil,
        atlas = r.GetAtlas and r:GetAtlas() or nil,
        text  = r.GetText and r:GetText() or nil,
        shown = r.IsShown and r:IsShown() or nil,
    }
end

local function dumpOne(name, store)
    local f = _G[name]
    if not f or not f.GetObjectType then return false end
    local rec = { name = name, regions = {}, children = {} }
    for _, r in ipairs(safeRegions(f)) do
        if r then
            local ok, ri = pcall(regionInfo, f, r)
            if ok and ri then rec.regions[#rec.regions + 1] = ri end
        end
    end
    for _, c in ipairs(safeChildren(f)) do
        if c then
            local kids = {}
            for _, g in ipairs(safeChildren(c)) do
                if g then kids[#kids + 1] = fieldKey(c, g) or (g.GetObjectType and g:GetObjectType()) or "?" end
            end
            rec.children[#rec.children + 1] = {
                kind  = c.GetObjectType and c:GetObjectType(),
                key   = fieldKey(f, c),
                gname = c.GetName and c:GetName() or nil,
                shown = c.IsShown and c:IsShown() or nil,
                grand = kids,
            }
        end
    end
    store[name] = rec
    return rec
end

local function dumpFrame(arg)
    OUIProbeDB.frames = OUIProbeDB.frames or {}
    local list = (arg and arg ~= "") and { arg } or DUMP_DEFAULTS
    local hits = 0
    for _, name in ipairs(list) do
        local ok, rec = pcall(dumpOne, name, OUIProbeDB.frames)
        if not ok then rec = nil end
        if rec then
            hits = hits + 1
            print(("|cff33ff99[OUI dump]|r %s: %d regions, %d children")
                :format(name, #rec.regions, #rec.children))
            -- print the texture/border regions (the usual reskin targets)
            for _, r in ipairs(rec.regions) do
                if r.kind == "Texture" then
                    print(("   tex key=%s layer=%s name=%s atlas=%s")
                        :format(tostring(r.key), tostring(r.layer),
                                tostring(r.gname), tostring(r.atlas or r.tex)))
                end
            end
            for _, c in ipairs(rec.children) do
                print(("   child key=%s name=%s shown=%s")
                    :format(tostring(c.key), tostring(c.gname), tostring(c.shown)))
            end
        else
            print("|cffff8800[OUI dump]|r not found / not loaded: " .. name)
        end
    end
    print(("|cff33ff99[OUI dump]|r %d frame(s) saved to OUIProbeDB.frames. /reload, then send the file.")
        :format(hits))
end

SLASH_OUIPROBE1 = "/ouiprobe"
SlashCmdList["OUIPROBE"] = function(msg)
    msg = msg or ""
    local cmd, arg = msg:match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()
    if cmd == "taint" then
        scanTaint(true)
    elseif cmd == "dump" then
        dumpFrame(arg)            -- frame name is case-sensitive; don't lower it
    else
        runProbe(true)
    end
end

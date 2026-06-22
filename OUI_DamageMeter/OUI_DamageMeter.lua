-------------------------------------------------------------------------------
--  OldschoolUIDamageMeter.lua
--  A self-contained damage / healing meter for OldschoolUI.
--  Combat-log based (CombatLogGetCurrentEventInfo). No dependency on the
--  OldschoolUI module/options framework; uses OldschoolUI visual helpers when
--  present and degrades gracefully otherwise.
--
--  Scope: damage (DPS) + healing (HPS) modes; per-fight segments + overall;
--  per-spell breakdown (mouseover tooltip) and a click-through detail window
--  (per segment + overall); pet attribution; class-coloured bars; controls +
--  slash command. (Deathlog, info bar, threat -> later iterations.)
-------------------------------------------------------------------------------
local ADDON = "OldschoolUIDamageMeter"

local floor, max, format, sort = math.floor, math.max, string.format, table.sort
local tinsert, tremove, date = table.insert, table.remove, date
local band = bit and bit.band
local GetTime = GetTime
local CLGetInfo = CombatLogGetCurrentEventInfo

-- Header control-button icons.
local ICON_RESET  = "Interface\\Buttons\\UI-RotationRight-Button-Up"
local ICON_LOCK   = "Interface\\Buttons\\LockButton-Locked-Up"
local ICON_UNLOCK = "Interface\\Buttons\\LockButton-Unlocked-Up"
local ICON_SEG    = "Interface\\Icons\\INV_Misc_PocketWatch_01"
local ICON_MENU   = "Interface\\Icons\\INV_Misc_Note_01"
local ICON_DEATH  = "Interface\\Icons\\Ability_Rogue_FeignDeath"

-------------------------------------------------------------------------------
--  Combat-log flag constants (use globals if present, else standard values)
-------------------------------------------------------------------------------
local F_TYPE_PET      = COMBATLOG_OBJECT_TYPE_PET            or 0x00001000
local F_TYPE_GUARDIAN = COMBATLOG_OBJECT_TYPE_GUARDIAN       or 0x00002000
local F_TYPE_PLAYER   = COMBATLOG_OBJECT_TYPE_PLAYER         or 0x00000400
local F_AFF_MINE      = COMBATLOG_OBJECT_AFFILIATION_MINE    or 0x00000001
local F_AFF_PARTY     = COMBATLOG_OBJECT_AFFILIATION_PARTY   or 0x00000002
local F_AFF_RAID      = COMBATLOG_OBJECT_AFFILIATION_RAID    or 0x00000004
local F_AFF_GROUP     = F_AFF_MINE + F_AFF_PARTY + F_AFF_RAID
local F_TYPE_PETGUARD = F_TYPE_PET + F_TYPE_GUARDIAN

local DAMAGE_SUBEVENTS = {
    SWING_DAMAGE = true, RANGE_DAMAGE = true, SPELL_DAMAGE = true,
    SPELL_PERIODIC_DAMAGE = true, SPELL_BUILDING_DAMAGE = true,
    DAMAGE_SHIELD = true, DAMAGE_SPLIT = true,
}
local HEAL_SUBEVENTS = {
    SPELL_HEAL = true, SPELL_PERIODIC_HEAL = true,
}
local MISS_SUBEVENTS = {
    SWING_MISSED = true, SPELL_MISSED = true, RANGE_MISSED = true,
}

-------------------------------------------------------------------------------
--  SavedVariables / config
-------------------------------------------------------------------------------
-- Shared (single) settings:
local DEFAULTS = {
    barHeight    = 18,
    detailWidth  = 250,
    detailHeight = 298,
    deathWidth   = 300,
    deathHeight  = 324,
}

-- Per-window settings (each meter window has its own profile in db.windows):
local function NewProfile()
    return {
        mode    = "DAMAGE",            -- "DAMAGE" | "HEALING" | "TAKEN"
        segment = "CURRENT",           -- "CURRENT" | "OVERALL"
        point   = { "CENTER", 250, 0 },
        width   = 230,
        height  = 226,
        maxBars = 8,
        locked  = false,
        shown   = true,
    }
end

local db  -- assigned on ADDON_LOADED
local cdb -- per-character data store (segments/logs); assigned on ADDON_LOADED

local function ApplyDefaults()
    OldschoolUIDamageMeterDB = OldschoolUIDamageMeterDB or {}
    db = OldschoolUIDamageMeterDB
    -- Per-character data store (recorded segments/logs). Window settings stay
    -- in the account-wide db above; only the meter data is character-specific.
    OldschoolUIDamageMeterCharDB = OldschoolUIDamageMeterCharDB or {}
    cdb = OldschoolUIDamageMeterCharDB
    -- One-time migration: pull a pre-existing account-wide log into this
    -- character's store (the first character to log in after the update keeps
    -- the old data), then drop the shared copy so it's no longer account-wide.
    if cdb.log == nil and type(db.log) == "table" then
        cdb.log = db.log
    end
    db.log = nil
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then db[k] = v end
    end
    -- Migrate a legacy single-window layout into db.windows[1].
    if type(db.windows) ~= "table" or #db.windows == 0 then
        local p = NewProfile()
        if db.mode    then p.mode    = db.mode    end
        if db.segment then p.segment = db.segment end
        if type(db.point) == "table" then p.point = db.point end
        if db.width   then p.width   = db.width   end
        if db.height  then p.height  = db.height  end
        if db.maxBars then p.maxBars = db.maxBars end
        if db.locked  ~= nil then p.locked = db.locked end
        if db.shown   ~= nil then p.shown  = db.shown  end
        db.windows = { p }
    end
    -- Backfill any missing fields on existing profiles.
    for _, p in ipairs(db.windows) do
        for k, v in pairs(NewProfile()) do if p[k] == nil then p[k] = v end end
    end
end

-------------------------------------------------------------------------------
--  Data model
--  segment = { label, start, endTime, active, combatTime, actors, _enemy }
--  actor   = { guid, name, class, damage, healing, spells = { [name]={dmg,heal,hits} } }
--  overall = cumulative; fights = list of individual combat segments; current = active fight
-------------------------------------------------------------------------------
local MAX_FIGHTS = 30
local segIdCounter = 0

local function NewSegment(label)
    segIdCounter = segIdCounter + 1
    return { id = segIdCounter, label = label, start = nil, endTime = nil,
             active = false, combatTime = 0, actors = {} }
end

local overall = NewSegment(OldschoolUI.L("Total"))
local fights  = {}     -- list of individual fight segments (oldest..newest)
local current = nil    -- the active/last fight segment
local meters  = {}     -- meter window objects (each with its own profile + viewFight)

local petOwner = {}    -- [petGUID] = ownerGUID

local MAX_DEATHS = 50
local MAX_EVENTS = 50
local deaths     = {}  -- { kind, seq, name, class, timeStr, segId, src, spell, amount, overkill }
local brezzes    = {}  -- { kind, seq, timeStr, src, dst, segId }
local dispels    = {}  -- { src, target, spell, segId }
local lastHitOn  = {}  -- [guid] = { src, spell, amount, overkill } last incoming hit
local eventSeq   = 0   -- monotonic order for merging deaths + brezzes in the log
local RefreshDeaths    -- forward declaration (defined with the death window)

local function SegById(id)
    if not id then return nil end
    for _, f in ipairs(fights) do if f.id == id then return f end end
    return nil
end

local function ActorDuration(seg)
    if not seg or not seg.start then return 1 end
    local live = seg.active and (GetTime() - seg.start) or 0
    if seg == overall then
        return max(1, (seg.combatTime or 0) + live)
    end
    return max(1, (seg.endTime or GetTime()) - seg.start)
end

local function DeriveFightLabel(seg)
    local best, bestV = nil, 0
    if seg._enemy then
        for n, v in pairs(seg._enemy) do if v > bestV then best, bestV = n, v end end
    end
    return best or "Kampf"
end

local function SegmentLabel(seg)
    if seg == overall then return OldschoolUI.L("Total") end
    if seg.active and not seg.label then return DeriveFightLabel(seg) .. " *" end
    return seg.label or DeriveFightLabel(seg)
end

local function GetOrCreateActor(seg, guid, name, class)
    local a = seg.actors[guid]
    if not a then
        a = { guid = guid, name = name or "?", class = class,
              damage = 0, healing = 0, overheal = 0, taken = 0,
              spells = {}, taken_spells = {} }
        seg.actors[guid] = a
    else
        if name and a.name == "?" then a.name = name end
        if class and not a.class then a.class = class end
    end
    return a
end

local function EnsureSpellIn(tbl, spellName, spellID)
    local s = tbl[spellName]
    if not s then
        s = { id = spellID, dmg = 0, heal = 0, over = 0, hits = 0,
              crit = 0, critAmt = 0, dodge = 0, parry = 0, miss = 0 }
        tbl[spellName] = s
    elseif spellID and not s.id then
        s.id = spellID
    end
    return s
end

local function EnsureSpell(actor, spellName, spellID)
    return EnsureSpellIn(actor.spells, spellName, spellID)
end

-- targetName (optional): also accumulate a per-target breakdown on the actor,
-- so the detail window can split a player's output by the targets it hit.
local function ApplySpell(actor, key, subKey, spellName, spellID, amount, crit, over, targetName)
    actor[key] = actor[key] + amount
    local s = EnsureSpellIn(actor.spells, spellName, spellID)
    s[subKey] = s[subKey] + amount
    s.hits = s.hits + 1
    if crit then s.crit = s.crit + 1; s.critAmt = (s.critAmt or 0) + amount end
    if over and over > 0 then
        s.over = (s.over or 0) + over
        actor.overheal = (actor.overheal or 0) + over
    end
    if targetName then
        actor.byTarget = actor.byTarget or {}
        local t = actor.byTarget[targetName]
        if not t then t = { damage = 0, healing = 0, spells = {} }; actor.byTarget[targetName] = t end
        t[key] = (t[key] or 0) + amount
        local ts = EnsureSpellIn(t.spells, spellName, spellID)
        ts[subKey] = ts[subKey] + amount
        ts.hits = ts.hits + 1
        if crit then ts.crit = ts.crit + 1; ts.critAmt = (ts.critAmt or 0) + amount end
        if over and over > 0 then ts.over = (ts.over or 0) + over end
    end
end

local function ApplyMiss(actor, spellName, spellID, missType)
    local s = EnsureSpell(actor, spellName, spellID)
    if missType == "DODGE" then s.dodge = s.dodge + 1
    elseif missType == "PARRY" then s.parry = s.parry + 1
    else s.miss = s.miss + 1 end
end

-- key = "damage"|"healing"; subKey = "dmg"|"heal"; over = overheal (heals only)
local function AddAmount(guid, name, class, key, subKey, spellName, spellID, amount, crit, over, targetName)
    if amount <= 0 then return end
    ApplySpell(GetOrCreateActor(overall, guid, name, class), key, subKey, spellName, spellID, amount, crit, over, targetName)
    if current then
        ApplySpell(GetOrCreateActor(current, guid, name, class), key, subKey, spellName, spellID, amount, crit, over, targetName)
    end
end

local function AddMiss(guid, name, class, spellName, spellID, missType)
    ApplyMiss(GetOrCreateActor(overall, guid, name, class), spellName, spellID, missType)
    if current then
        ApplyMiss(GetOrCreateActor(current, guid, name, class), spellName, spellID, missType)
    end
end

-- Damage taken (group member as destination), split by mitigation type.
local function EnsureTakenSpell(actor, spellName, spellID)
    local t = actor.taken_spells[spellName]
    if not t then
        t = { id = spellID, amount = 0, hits = 0,
              dodge = 0, parry = 0, block = 0, absorb = 0, miss = 0 }
        actor.taken_spells[spellName] = t
    elseif spellID and not t.id then
        t.id = spellID
    end
    return t
end

local function ApplyTaken(actor, spellName, spellID, amount)
    actor.taken = actor.taken + amount
    local t = EnsureTakenSpell(actor, spellName, spellID)
    t.amount = t.amount + amount
    t.hits = t.hits + 1
end

local function ApplyTakenMiss(actor, spellName, spellID, missType)
    local t = EnsureTakenSpell(actor, spellName, spellID)
    if missType == "DODGE" then t.dodge = t.dodge + 1
    elseif missType == "PARRY" then t.parry = t.parry + 1
    elseif missType == "BLOCK" then t.block = t.block + 1
    elseif missType == "ABSORB" then t.absorb = t.absorb + 1
    else t.miss = t.miss + 1 end
end

local function AddTaken(guid, name, class, spellName, spellID, amount)
    if amount <= 0 then return end
    ApplyTaken(GetOrCreateActor(overall, guid, name, class), spellName, spellID, amount)
    if current then ApplyTaken(GetOrCreateActor(current, guid, name, class), spellName, spellID, amount) end
end

local function AddTakenMiss(guid, name, class, spellName, spellID, missType)
    ApplyTakenMiss(GetOrCreateActor(overall, guid, name, class), spellName, spellID, missType)
    if current then ApplyTakenMiss(GetOrCreateActor(current, guid, name, class), spellName, spellID, missType) end
end

-- Unified breakdown for tooltips/detail: returns sorted {name, value, entry} + total.
local function ActorBreakdown(a, mode)
    local list, tot = {}, 0
    if mode == "TAKEN" then
        for n, t in pairs(a.taken_spells or {}) do
            if t.amount > 0 then list[#list + 1] = { n, t.amount, t }; tot = tot + t.amount end
        end
    else
        local subKey = (mode == "HEALING") and "heal" or "dmg"
        for n, s in pairs(a.spells or {}) do
            local v = s[subKey]
            if v and v > 0 then list[#list + 1] = { n, v, s }; tot = tot + v end
        end
    end
    sort(list, function(x, y) return x[2] > y[2] end)
    return list, tot
end

local function ActorTotal(a, mode)
    if mode == "TAKEN" then return a.taken or 0 end
    return a[(mode == "HEALING") and "healing" or "damage"] or 0
end

-- Per-target list for an actor: sorted {targetName, value, targetRecord} + total.
-- (DAMAGE/HEALING only -- "taken" has no per-target split.)
local function ActorTargetList(a, mode)
    local list, tot = {}, 0
    local key = (mode == "HEALING") and "healing" or "damage"
    for tname, t in pairs(a.byTarget or {}) do
        local v = t[key] or 0
        if v > 0 then list[#list + 1] = { tname, v, t }; tot = tot + v end
    end
    sort(list, function(x, y) return x[2] > y[2] end)
    return list, tot
end

-- Spell breakdown within a single target record (mirrors ActorBreakdown).
local function TargetBreakdown(t, mode)
    local list, tot = {}, 0
    local subKey = (mode == "HEALING") and "heal" or "dmg"
    for n, s in pairs((t and t.spells) or {}) do
        local v = s[subKey]
        if v and v > 0 then list[#list + 1] = { n, v, s }; tot = tot + v end
    end
    sort(list, function(x, y) return x[2] > y[2] end)
    return list, tot
end

-------------------------------------------------------------------------------
--  Pet -> owner mapping
-------------------------------------------------------------------------------
local function MapUnitPet(petUnit, ownerUnit)
    local pg = UnitGUID(petUnit)
    local og = UnitGUID(ownerUnit)
    if pg and og then petOwner[pg] = og end
end

local function RescanPets()
    MapUnitPet("pet", "player")
    if IsInRaid() then
        for i = 1, 40 do MapUnitPet("raidpet" .. i, "raid" .. i) end
    else
        for i = 1, 4 do MapUnitPet("partypet" .. i, "party" .. i) end
    end
end

-- Resolve a combat-log source to the GUID we should credit (player, or the
-- owner of a group pet/guardian when known).
local function ResolveSource(guid, flags)
    if not guid then return nil end
    if band and flags and band(flags, F_TYPE_PETGUARD) > 0 then
        return petOwner[guid] or guid  -- unknown owner -> credit the pet itself
    end
    return guid
end

-------------------------------------------------------------------------------
--  Combat-log parser
-------------------------------------------------------------------------------
local function ResolveActor(guid, flags, fallbackName)
    local g = ResolveSource(guid, flags)
    if not g then return nil end
    local name, class = fallbackName, nil
    if GetPlayerInfoByGUID then
        local _, ec, _, _, _, pn = GetPlayerInfoByGUID(g)
        class = ec
        if pn and pn ~= "" then name = pn end
    end
    return g, name, class
end

local function ParseCLEU(_, sub, _, srcGUID, srcName, srcFlags, _, dstGUID, dstName, dstFlags, _, ...)
    -- Pet ownership: a group member summoning a pet/guardian.
    if sub == "SPELL_SUMMON" then
        if srcGUID and dstGUID and band and srcFlags and band(srcFlags, F_AFF_GROUP) > 0 then
            petOwner[dstGUID] = srcGUID
        end
        return
    end

    -- Death tracking: a group player died -> log time, segment, killing blow.
    if sub == "UNIT_DIED" or sub == "UNIT_DESTROYED" then
        if dstGUID and band and dstFlags
            and band(dstFlags, F_AFF_GROUP) > 0
            and band(dstFlags, F_TYPE_PLAYER) > 0 then
            local class
            if GetPlayerInfoByGUID then local _, ec = GetPlayerInfoByGUID(dstGUID); class = ec end
            local lh = lastHitOn[dstGUID]
            eventSeq = eventSeq + 1
            deaths[#deaths + 1] = {
                kind    = "death",
                seq     = eventSeq,
                name    = dstName or "?",
                class   = class,
                timeStr = date("%H:%M:%S"),
                segId   = current and current.id,
                src     = lh and lh.src,
                spell   = lh and lh.spell,
                amount  = lh and lh.amount,
                overkill = (lh and lh.overkill) or 0,
            }
            if #deaths > MAX_DEATHS then tremove(deaths, 1) end
            if RefreshDeaths then RefreshDeaths() end
        end
        return
    end

    -- Combat resurrection (battle rez) cast by a group member.
    if sub == "SPELL_RESURRECT" then
        if band and srcFlags and band(srcFlags, F_AFF_GROUP) > 0 then
            eventSeq = eventSeq + 1
            brezzes[#brezzes + 1] = {
                kind = "brez", seq = eventSeq, timeStr = date("%H:%M:%S"),
                src = srcName or "?", dst = dstName or "?", segId = current and current.id,
            }
            if #brezzes > MAX_EVENTS then tremove(brezzes, 1) end
            if RefreshDeaths then RefreshDeaths() end
        end
        return
    end

    -- Dispel / spellsteal by a group member.
    if sub == "SPELL_DISPEL" or sub == "SPELL_STOLEN" then
        if band and srcFlags and band(srcFlags, F_AFF_GROUP) > 0 then
            local extraName = select(5, ...)   -- param 16: extraSpellName
            dispels[#dispels + 1] = {
                src = srcName or "?", target = dstName or "?",
                spell = (type(extraName) == "string" and extraName) or "?",
                segId = current and current.id,
            }
            if #dispels > MAX_EVENTS then tremove(dispels, 1) end
        end
        return
    end

    local isDamage = DAMAGE_SUBEVENTS[sub]
    local isHeal   = HEAL_SUBEVENTS[sub]
    local isMiss   = MISS_SUBEVENTS[sub]
    if not (isDamage or isHeal or isMiss) then return end

    local srcGroup = (band and srcFlags and band(srcFlags, F_AFF_GROUP) > 0) or false
    local dstGroup = (band and dstFlags and band(dstFlags, F_AFF_GROUP) > 0) or false
    if not (srcGroup or dstGroup) then return end

    -- Extract the payload once (positions are 12+ in the full event).
    local spellName, spellID, amount, over, crit, missType, overkill
    if isDamage then
        if sub == "SWING_DAMAGE" then
            spellName = "Nahkampf"; amount = ...; overkill = select(2, ...); crit = select(7, ...)
        else
            spellID = select(1, ...); spellName = select(2, ...)
            amount = select(4, ...); overkill = select(5, ...); crit = select(10, ...)
        end
    elseif isHeal then
        spellID = select(1, ...); spellName = select(2, ...)
        amount = select(4, ...); over = select(5, ...); crit = select(7, ...)
    else -- miss
        if sub == "SWING_MISSED" then
            spellName = "Nahkampf"; missType = ...
        else
            spellID = select(1, ...); spellName = select(2, ...); missType = select(4, ...)
        end
    end
    spellName = spellName or "?"
    local critB = (crit == true) or (crit == 1)

    -- SOURCE side: damage / healing done by a group member.
    if srcGroup then
        local guid, name, class = ResolveActor(srcGUID, srcFlags, srcName)
        if guid then
            if isDamage and type(amount) == "number" then
                AddAmount(guid, name, class, "damage", "dmg", spellName, spellID, amount, critB, nil, dstName)
                if current and dstName and not dstGroup then
                    local e = current._enemy or {}; current._enemy = e
                    e[dstName] = (e[dstName] or 0) + amount
                end
            elseif isHeal and type(amount) == "number" then
                local ov  = (type(over) == "number" and over > 0) and over or 0
                local eff = amount - ov
                if eff > 0 then
                    AddAmount(guid, name, class, "healing", "heal", spellName, spellID, eff, critB, ov, dstName)
                end
            elseif isMiss and type(missType) == "string" then
                AddMiss(guid, name, class, spellName, spellID, missType)
            end
        end
    end

    -- DESTINATION side: damage taken by a group member (received / avoided).
    if dstGroup and (isDamage or isMiss) then
        local guid, name, class = ResolveActor(dstGUID, dstFlags, dstName)
        if guid then
            if isDamage and type(amount) == "number" then
                AddTaken(guid, name, class, spellName, spellID, amount)
                lastHitOn[dstGUID] = {
                    src = srcName, spell = spellName, amount = amount,
                    overkill = (type(overkill) == "number" and overkill > 0) and overkill or 0,
                }
            elseif isMiss and type(missType) == "string" then
                AddTakenMiss(guid, name, class, spellName, spellID, missType)
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Segment lifecycle
-------------------------------------------------------------------------------
local function StartCombat()
    if current and current.active then return end
    -- Begin a new fight segment; keep prior fights and the overall total.
    local seg = NewSegment(nil)
    seg.start  = GetTime()
    seg.active = true
    fights[#fights + 1] = seg
    while #fights > MAX_FIGHTS do table.remove(fights, 1) end
    current = seg
    if not overall.start then overall.start = GetTime() end
    overall.active = true
end

local SaveLog, LoadLog   -- forward declarations (persistence)

local function EndCombat()
    if not (current and current.active) then return end
    current.active  = false
    current.endTime = GetTime()
    current.label   = DeriveFightLabel(current)
    current._enemy  = nil   -- no longer needed; keep it out of saved data
    overall.active  = false
    if current.start then
        overall.combatTime = (overall.combatTime or 0) + (current.endTime - current.start)
    end
    SaveLog()
end

-- Persist the last MAX_FIGHTS segments + event logs across reloads/sessions.
function SaveLog()
    if not cdb then return end
    cdb.log = {
        v = 1,
        overall = overall, fights = fights,
        deaths = deaths, brezzes = brezzes, dispels = dispels,
        eventSeq = eventSeq, segIdCounter = segIdCounter,
    }
end

function LoadLog()
    local L = cdb and cdb.log
    if type(L) ~= "table" then return end
    if type(L.overall) == "table" then overall = L.overall end
    if type(L.fights)  == "table" then fights  = L.fights end
    if type(L.deaths)  == "table" then deaths  = L.deaths end
    if type(L.brezzes) == "table" then brezzes = L.brezzes end
    if type(L.dispels) == "table" then dispels = L.dispels end
    eventSeq     = tonumber(L.eventSeq) or eventSeq
    segIdCounter = tonumber(L.segIdCounter) or segIdCounter
    current = nil
    if overall then overall.active = false; overall._enemy = nil end
    for _, f in ipairs(fights) do f.active = false; f._enemy = nil end
end

local function ResetData()
    overall = NewSegment(OldschoolUI.L("Total"))
    fights  = {}
    current = nil
    for _, m in ipairs(meters) do m.viewFight = nil end
    wipe(petOwner)
    wipe(deaths)
    wipe(brezzes)
    wipe(dispels)
    wipe(lastHitOn)
    SaveLog()
    if RefreshDeaths then RefreshDeaths() end
end

-------------------------------------------------------------------------------
--  Visual helpers
-------------------------------------------------------------------------------
local FONT_FALLBACK = "Interface\\AddOns\\OldschoolUI\\media\\fonts\\Expressway.TTF"
local function FontPath()
    if OldschoolUI and OldschoolUI.GetFontPath then
        local ok, p = pcall(OldschoolUI.GetFontPath, "extras")
        if ok and p then return p end
    end
    return FONT_FALLBACK
end

-- Central accent colour (shared across the suite; the final rebrand swaps this).
local function Accent()
    if OldschoolUI and OldschoolUI.GetAccentColor then
        local r, g, b = OldschoolUI.GetAccentColor()
        if r then return r, g, b end
    end
    return 0.05, 0.82, 0.62
end
local function AccentHex()
    local r, g, b = Accent()
    return format("%02x%02x%02x", floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5))
end

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
local function BarTexture()
    if LSM then
        return LSM:Fetch("statusbar", "OldschoolUI", true)
            or LSM:Fetch("statusbar", "Blizzard")
            or "Interface\\TargetingFrame\\UI-StatusBar"
    end
    return "Interface\\TargetingFrame\\UI-StatusBar"
end

local function ClassColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 0.55, 0.55, 0.60
end

local function FormatNumber(n)
    if n >= 1e6 then return format("%.1fM", n / 1e6)
    elseif n >= 1e3 then return format("%.1fK", n / 1e3) end
    return format("%d", n)
end

local MELEE_ICON = "Interface\\ICONS\\INV_Sword_04"
local _iconCache = {}
local function SpellIcon(id)
    if not id then return MELEE_ICON end
    local c = _iconCache[id]
    if c ~= nil then return c end
    local tex
    if C_Spell and C_Spell.GetSpellTexture then tex = C_Spell.GetSpellTexture(id)
    elseif GetSpellTexture then tex = GetSpellTexture(id) end
    tex = tex or MELEE_ICON
    _iconCache[id] = tex
    return tex
end

-------------------------------------------------------------------------------
--  Window
-------------------------------------------------------------------------------
local activeMeter           -- meter whose menu is currently open

-- Forward declarations (referenced across the window section).
local ShowBarTooltip, OpenDetail, RefreshMeter, RefreshAll, CreateMeter, SpawnMeter, CloseMeter, ToggleSegMenu, RefreshDetail

-------------------------------------------------------------------------------
--  Per-spell tooltip (mouseover a bar in a meter window)
-------------------------------------------------------------------------------
function ShowBarTooltip(bar)
    local a = bar.actor
    if not a then return end
    local mode = bar._mode or "DAMAGE"
    GameTooltip:SetOwner(bar, "ANCHOR_RIGHT")
    GameTooltip:AddLine(a.name or "?")
    local list, tot = ActorBreakdown(a, mode)
    if #list == 0 then
        GameTooltip:AddLine(OldschoolUI.L("No data"), 0.7, 0.7, 0.7)
    else
        for i = 1, math.min(#list, 10) do
            local e = list[i]
            local pct = tot > 0 and (e[2] / tot * 100) or 0
            GameTooltip:AddDoubleLine(e[1],
                format("%s  %.0f%%  (%dx)", FormatNumber(e[2]), pct, e[3].hits or 0),
                1, 1, 1, 0.9, 0.9, 0.9)
        end
        GameTooltip:AddLine(OldschoolUI.L("Click: detail window"), 0.5, 0.7, 1)
    end
    GameTooltip:Show()
end

-------------------------------------------------------------------------------
--  Detail window: per-spell breakdown for one actor, per segment + overall
-------------------------------------------------------------------------------
local detailWin, detailBars
local detailGUID, detailSegIdx
local detailMode = "DAMAGE"   -- mode of the meter that opened the detail window
local detailView = "SPELLS"   -- "SPELLS" | "TARGETS"
local detailTarget            -- selected target name (nil = all targets / "Gesamt")
local DETAIL_MAXBARS = 12     -- initial row count (height basis)
local DETAIL_HARDCAP = 30     -- upper bound when enlarged
local detailMaxBars  = DETAIL_MAXBARS

local function DetailSegList()
    local list = { overall }
    for i = #fights, 1, -1 do list[#list + 1] = fights[i] end
    return list
end

local function ShowDetailTooltip(bar)
    if bar._isTarget then
        GameTooltip:SetOwner(bar, "ANCHOR_RIGHT")
        GameTooltip:AddLine(bar._target or "?")
        local modeTxt = (bar._mode == "HEALING") and OldschoolUI.L("Healing") or OldschoolUI.L("Damage")
        GameTooltip:AddDoubleLine(modeTxt, FormatNumber(bar._tval or 0), 1, 1, 1, 0.9, 0.9, 0.9)
        if bar._pct then GameTooltip:AddDoubleLine(OldschoolUI.L("Share"), format("%.0f%%", bar._pct), 1, 1, 1, 0.75, 0.75, 0.75) end
        GameTooltip:AddLine(OldschoolUI.L("Click: spell breakdown for this target"), 0.5, 0.7, 1)
        GameTooltip:Show()
        return
    end
    local s = bar._s
    if not s then return end
    GameTooltip:SetOwner(bar, "ANCHOR_RIGHT")
    GameTooltip:AddLine(bar._sname or "?")
    local hits = s.hits or 0
    GameTooltip:AddDoubleLine(OldschoolUI.L("Hits"), tostring(hits), 1, 1, 1, 1, 1, 1)
    if bar._mode == "TAKEN" then
        local amt = s.amount or 0
        GameTooltip:AddDoubleLine(OldschoolUI.L("Received"), FormatNumber(amt), 1, 1, 1, 0.9, 0.9, 0.9)
        if hits > 0 then GameTooltip:AddDoubleLine(OldschoolUI.L("Average"), FormatNumber(amt / hits), 1, 1, 1, 0.9, 0.9, 0.9) end
        if (s.dodge  or 0) > 0 then GameTooltip:AddDoubleLine(OldschoolUI.L("Dodged"), tostring(s.dodge),  1,1,1, 0.8,0.8,1) end
        if (s.parry  or 0) > 0 then GameTooltip:AddDoubleLine(OldschoolUI.L("Parried"),     tostring(s.parry),  1,1,1, 0.8,0.8,1) end
        if (s.block  or 0) > 0 then GameTooltip:AddDoubleLine(OldschoolUI.L("Blocked"),    tostring(s.block),  1,1,1, 0.8,0.8,1) end
        if (s.absorb or 0) > 0 then GameTooltip:AddDoubleLine(OldschoolUI.L("Absorbed"),  tostring(s.absorb), 1,1,1, 0.8,0.8,1) end
        if (s.miss   or 0) > 0 then GameTooltip:AddDoubleLine(OldschoolUI.L("Missed"),    tostring(s.miss),   1,1,1, 0.8,0.8,1) end
    else
        local subKey = (bar._mode == "HEALING") and "heal" or "dmg"
        local val = s[subKey] or 0
        GameTooltip:AddDoubleLine((bar._mode == "HEALING") and OldschoolUI.L("Healing") or OldschoolUI.L("Damage"),
            FormatNumber(val), 1, 1, 1, 0.9, 0.9, 0.9)
        if hits > 0 then
            GameTooltip:AddDoubleLine(OldschoolUI.L("Average"), FormatNumber(val / hits), 1, 1, 1, 0.9, 0.9, 0.9)
            GameTooltip:AddDoubleLine(OldschoolUI.L("Critical"),
                format("%d (%.0f%%)  %s", s.crit or 0, (s.crit or 0) / hits * 100, FormatNumber(s.critAmt or 0)),
                1, 1, 1, 1, 0.85, 0.4)
        end
        if bar._mode == "HEALING" and (s.over or 0) > 0 then
            local raw = val + s.over
            GameTooltip:AddDoubleLine("Overheal",
                format("%s (%.0f%%)", FormatNumber(s.over), raw > 0 and (s.over / raw * 100) or 0),
                1, 1, 1, 0.6, 0.8, 1)
            GameTooltip:AddDoubleLine(OldschoolUI.L("Indirect (incl. OH)"), FormatNumber(raw), 1, 1, 1, 0.6, 0.9, 0.7)
        end
        if (s.dodge or 0) > 0 then GameTooltip:AddDoubleLine(OldschoolUI.L("Dodged"), tostring(s.dodge), 1,1,1, 0.8,0.8,1) end
        if (s.parry or 0) > 0 then GameTooltip:AddDoubleLine(OldschoolUI.L("Parried"),     tostring(s.parry), 1,1,1, 0.8,0.8,1) end
        if (s.miss  or 0) > 0 then GameTooltip:AddDoubleLine(OldschoolUI.L("Missed"),    tostring(s.miss),  1,1,1, 0.8,0.8,1) end
    end
    GameTooltip:Show()
end

local function CreateDetailBar(parent)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetStatusBarTexture(BarTexture())
    bar:SetMinMaxValues(0, 1); bar:SetValue(0)
    bar:EnableMouse(true)
    bar:SetScript("OnEnter", function(self) if self._s or self._isTarget then ShowDetailTooltip(self) end end)
    bar:SetScript("OnLeave", function() GameTooltip:Hide() end)
    bar:SetScript("OnMouseUp", function(self)
        if self._isTarget and self._target then
            detailTarget = self._target
            detailView   = "SPELLS"
            if RefreshDetail then RefreshDetail() end
        end
    end)

    local bg = bar:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints()
    bg:SetTexture(BarTexture()); bg:SetVertexColor(0, 0, 0, 0.45)

    local icon = bar:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("LEFT", 1, 0); icon:SetSize(16, 16)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    bar.icon = icon

    -- right-aligned columns: value | pct | crit
    local cCrit = bar:CreateFontString(nil, "OVERLAY")
    cCrit:SetPoint("RIGHT", -4, 0); cCrit:SetWidth(40); cCrit:SetJustifyH("RIGHT")
    cCrit:SetFont(FontPath(), 11, ""); cCrit:SetShadowOffset(1, -1)
    cCrit:SetTextColor(1, 0.85, 0.4)
    bar.cCrit = cCrit

    local cPct = bar:CreateFontString(nil, "OVERLAY")
    cPct:SetPoint("RIGHT", -48, 0); cPct:SetWidth(34); cPct:SetJustifyH("RIGHT")
    cPct:SetFont(FontPath(), 11, ""); cPct:SetShadowOffset(1, -1)
    cPct:SetTextColor(0.75, 0.75, 0.75)
    bar.cPct = cPct

    local cVal = bar:CreateFontString(nil, "OVERLAY")
    cVal:SetPoint("RIGHT", -86, 0); cVal:SetWidth(58); cVal:SetJustifyH("RIGHT")
    cVal:SetFont(FontPath(), 11, ""); cVal:SetShadowOffset(1, -1)
    bar.cVal = cVal

    local left = bar:CreateFontString(nil, "OVERLAY")
    left:SetPoint("LEFT", icon, "RIGHT", 3, 0)
    left:SetPoint("RIGHT", cVal, "LEFT", -4, 0)
    left:SetJustifyH("LEFT")
    left:SetFont(FontPath(), 11, ""); left:SetShadowOffset(1, -1)
    bar.left = left
    return bar
end

local function EnsureDetailBar(i)
    local bar = detailBars[i]
    if bar then return bar end
    bar = CreateDetailBar(detailWin.body); bar:SetHeight(18)
    if i == 1 then
        bar:SetPoint("TOPLEFT", detailWin.body, "TOPLEFT", 0, 0)
        bar:SetPoint("TOPRIGHT", detailWin.body, "TOPRIGHT", 0, 0)
    else
        local prev = EnsureDetailBar(i - 1)
        bar:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -2)
        bar:SetPoint("TOPRIGHT", prev, "BOTTOMRIGHT", 0, -2)
    end
    detailBars[i] = bar
    return bar
end

function RefreshDetail()
    if not (detailWin and detailWin:IsShown()) then return end
    local segs = DetailSegList()
    if detailSegIdx > #segs then detailSegIdx = #segs end
    if detailSegIdx < 1 then detailSegIdx = 1 end
    local seg = segs[detailSegIdx]
    local a = seg and seg.actors[detailGUID]
    detailWin.seglabel:SetText(seg and SegmentLabel(seg) or "-")

    -- "taken" has no per-target split -> force the spell view.
    if detailMode == "TAKEN" then detailView = "SPELLS"; detailTarget = nil end
    local targetsView = (detailView == "TARGETS")

    local list, tot = {}, 0
    if a and targetsView then
        list, tot = ActorTargetList(a, detailMode)
    elseif a and detailTarget and a.byTarget and a.byTarget[detailTarget] then
        list, tot = TargetBreakdown(a.byTarget[detailTarget], detailMode)
    elseif a then
        list, tot = ActorBreakdown(a, detailMode)
    end
    local r, g, b = ClassColor(a and a.class)

    -- title: actor [ > target ]
    local titleTxt = (a and a.name) or "?"
    if not targetsView and detailTarget then titleTxt = titleTxt .. "  >  " .. detailTarget end
    detailWin.title:SetText(titleTxt)

    -- view-toggle button label
    if detailWin.viewBtn then
        if detailMode == "TAKEN" then
            detailWin.viewBtn:Hide()
        else
            detailWin.viewBtn:Show()
            local lbl
            if targetsView then lbl = OldschoolUI.L("Spells")
            elseif detailTarget then lbl = OldschoolUI.L("All targets")
            else lbl = OldschoolUI.L("Targets") end
            detailWin.viewBtn.text:SetText(lbl)
        end
    end

    for i = 1, detailMaxBars do
        local bar = EnsureDetailBar(i)
        local e = list[i]
        if e then
            local v = e[2]
            local pct = tot > 0 and (v / tot * 100) or 0
            bar:SetStatusBarColor(r, g, b)
            bar:SetValue(tot > 0 and (v / tot) or 0)
            bar.left:SetText(format("%d. %s", i, e[1]))
            bar.cVal:SetText(FormatNumber(v))
            bar.cPct:SetText(format("%.0f%%", pct))
            if targetsView then
                bar.icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")
                bar.cCrit:SetText("")
                bar._s = nil; bar._sname = nil
                bar._isTarget = true; bar._target = e[1]; bar._tval = v; bar._pct = pct
                bar._mode = detailMode
            else
                local s = e[3]
                bar.icon:SetTexture(SpellIcon(s.id))
                local critPct = (s.crit and s.hits and s.hits > 0) and (s.crit / s.hits * 100) or 0
                bar.cCrit:SetText(critPct > 0 and format("K%.0f%%", critPct) or "")
                bar._s = s; bar._sname = e[1]; bar._mode = detailMode
                bar._isTarget = nil; bar._target = nil
            end
            bar:Show()
        else
            bar._s = nil; bar._isTarget = nil
            bar:Hide()
        end
    end
    for i = detailMaxBars + 1, #detailBars do
        if detailBars[i] then detailBars[i]:Hide() end
    end

    local modeTxt = (detailMode == "TAKEN") and OldschoolUI.L("Received")
        or ((detailMode == "HEALING") and OldschoolUI.L("Healing") or OldschoolUI.L("Damage"))
    local scopeTxt = targetsView and OldschoolUI.L("by target")
        or (detailTarget or OldschoolUI.L("Total"))
    detailWin.total:SetText(format("%s (%s): %s", modeTxt, scopeTxt, FormatNumber(tot)))
end

local function RecalcDetailBars()
    if not (detailWin and detailWin.body) then return end
    local avail = detailWin.body:GetHeight()
    if not avail or avail <= 0 then return end
    local n = floor((avail + 2) / 20)
    if n < 1 then n = 1 elseif n > DETAIL_HARDCAP then n = DETAIL_HARDCAP end
    detailMaxBars = n
end

local function CreateDetailWindow()
    detailWin = CreateFrame("Frame", "OldschoolUIDamageMeterDetail", UIParent)
    detailWin:SetSize(db.detailWidth, db.detailHeight)
    detailWin:SetResizable(true)
    if detailWin.SetResizeBounds then
        pcall(detailWin.SetResizeBounds, detailWin, 180, 120, 600, 800)
    else
        if detailWin.SetMinResize then pcall(detailWin.SetMinResize, detailWin, 180, 120) end
        if detailWin.SetMaxResize then pcall(detailWin.SetMaxResize, detailWin, 600, 800) end
    end
    detailWin:SetFrameStrata("HIGH")
    detailWin:SetClampedToScreen(true)
    detailWin:SetMovable(true); detailWin:EnableMouse(true)
    detailWin:RegisterForDrag("LeftButton")
    detailWin:SetScript("OnDragStart", detailWin.StartMoving)
    detailWin:SetScript("OnDragStop", detailWin.StopMovingOrSizing)
    detailWin:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

    local bgt = detailWin:CreateTexture(nil, "BACKGROUND")
    bgt:SetAllPoints(); bgt:SetTexture("Interface\\Buttons\\WHITE8x8")
    bgt:SetVertexColor(0.05, 0.05, 0.06, 0.92)
    if OldschoolUI and OldschoolUI.PP and OldschoolUI.PP.CreateBorder then
        pcall(OldschoolUI.PP.CreateBorder, detailWin, 0, 0, 0, 1, 1, "OVERLAY", 7)
    end

    local title = detailWin:CreateFontString(nil, "OVERLAY")
    title:SetPoint("TOPLEFT", 6, -4); title:SetFont(FontPath(), 12, ""); title:SetShadowOffset(1, -1)
    detailWin.title = title

    local close = CreateFrame("Button", nil, detailWin)
    close:SetSize(16, 16); close:SetPoint("TOPRIGHT", -4, -4)
    local cfs = close:CreateFontString(nil, "OVERLAY"); cfs:SetAllPoints()
    cfs:SetFont(FontPath(), 13, ""); cfs:SetText("x"); cfs:SetJustifyH("CENTER")
    close:SetScript("OnClick", function() detailWin:Hide() end)

    local prev = CreateFrame("Button", nil, detailWin)
    prev:SetSize(16, 16); prev:SetPoint("TOPLEFT", 6, -22)
    local pfs = prev:CreateFontString(nil, "OVERLAY"); pfs:SetAllPoints()
    pfs:SetFont(FontPath(), 13, ""); pfs:SetText("<"); pfs:SetJustifyH("CENTER")
    prev:SetScript("OnClick", function() detailSegIdx = detailSegIdx + 1; RefreshDetail() end)

    local nxt = CreateFrame("Button", nil, detailWin)
    nxt:SetSize(16, 16); nxt:SetPoint("TOPRIGHT", -6, -22)
    local nfs = nxt:CreateFontString(nil, "OVERLAY"); nfs:SetAllPoints()
    nfs:SetFont(FontPath(), 13, ""); nfs:SetText(">"); nfs:SetJustifyH("CENTER")
    nxt:SetScript("OnClick", function() detailSegIdx = detailSegIdx - 1; RefreshDetail() end)

    local seglabel = detailWin:CreateFontString(nil, "OVERLAY")
    seglabel:SetPoint("CENTER", detailWin, "TOPLEFT", 125, -30)
    seglabel:SetFont(FontPath(), 11, ""); seglabel:SetTextColor(0.8, 0.8, 0.85)
    detailWin.seglabel = seglabel

    local body = CreateFrame("Frame", nil, detailWin)
    body:SetPoint("TOPLEFT", 4, -40)
    body:SetPoint("BOTTOMRIGHT", -4, 18)
    detailWin.body = body
    detailBars = {}

    -- resize grip (bottom-right corner)
    local dgrip = CreateFrame("Button", nil, detailWin)
    dgrip:SetSize(16, 16); dgrip:SetPoint("BOTTOMRIGHT", 0, 0)
    dgrip:SetFrameLevel(detailWin:GetFrameLevel() + 10)
    dgrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    dgrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    dgrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    dgrip:SetScript("OnMouseDown", function() detailWin:StartSizing("BOTTOMRIGHT") end)
    dgrip:SetScript("OnMouseUp", function()
        detailWin:StopMovingOrSizing()
        db.detailWidth  = floor(detailWin:GetWidth()  + 0.5)
        db.detailHeight = floor(detailWin:GetHeight() + 0.5)
        RecalcDetailBars(); RefreshDetail()
    end)

    detailWin:SetScript("OnSizeChanged", function() RecalcDetailBars(); RefreshDetail() end)
    RecalcDetailBars()

    local total = detailWin:CreateFontString(nil, "OVERLAY")
    total:SetPoint("BOTTOMLEFT", 6, 4); total:SetFont(FontPath(), 11, ""); total:SetTextColor(0.8, 0.8, 0.85)
    detailWin.total = total

    -- view toggle: Spells <-> Targets ("All targets" returns from a target drill-down)
    local viewBtn = CreateFrame("Button", nil, detailWin)
    viewBtn:SetSize(82, 16)
    viewBtn:SetPoint("BOTTOMRIGHT", detailWin, "BOTTOMRIGHT", -20, 3)
    local vbg = viewBtn:CreateTexture(nil, "BACKGROUND"); vbg:SetAllPoints()
    vbg:SetColorTexture(1, 1, 1, 0.06)
    local vtx = viewBtn:CreateFontString(nil, "OVERLAY"); vtx:SetAllPoints()
    vtx:SetFont(FontPath(), 11, ""); vtx:SetJustifyH("CENTER"); vtx:SetTextColor(0.8, 0.85, 1)
    vtx:SetText(OldschoolUI.L("Targets"))
    viewBtn.text = vtx
    viewBtn:SetScript("OnEnter", function(self) vbg:SetColorTexture(1, 1, 1, 0.14) end)
    viewBtn:SetScript("OnLeave", function(self) vbg:SetColorTexture(1, 1, 1, 0.06) end)
    viewBtn:SetScript("OnClick", function()
        if detailMode == "TAKEN" then return end
        if detailView == "TARGETS" then
            detailView = "SPELLS"; detailTarget = nil
        elseif detailTarget then
            detailTarget = nil
        else
            detailView = "TARGETS"
        end
        RefreshDetail()
    end)
    detailWin.viewBtn = viewBtn
end

function OpenDetail(actor, m)
    if not actor then return end
    detailGUID = actor.guid
    detailView = "SPELLS"; detailTarget = nil
    detailMode = (m and m.p and m.p.mode) or detailMode
    if not detailWin then CreateDetailWindow() end
    -- Start on the segment currently shown in the meter that was clicked.
    local vf  = m and m.viewFight
    local seg = m and m.p and m.p.segment
    if vf then
        local idx = 2
        for i = #fights, 1, -1 do
            if fights[i] == vf then break end
            idx = idx + 1
        end
        detailSegIdx = idx
    elseif seg == "OVERALL" then
        detailSegIdx = 1
    else
        detailSegIdx = 2
    end
    detailWin:Show()
    RefreshDetail()
end

local function CreateBar(m, parent, index)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetStatusBarTexture(BarTexture())
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(BarTexture())
    bg:SetVertexColor(0, 0, 0, 0.45)
    bar.bg = bg

    local left = bar:CreateFontString(nil, "OVERLAY")
    left:SetPoint("LEFT", 4, 0)
    left:SetFont(FontPath(), 11, "")
    left:SetShadowOffset(1, -1)
    bar.left = left

    local right = bar:CreateFontString(nil, "OVERLAY")
    right:SetPoint("RIGHT", -4, 0)
    right:SetFont(FontPath(), 11, "")
    right:SetShadowOffset(1, -1)
    bar.right = right

    bar._meter = m
    bar:EnableMouse(true)
    bar:SetScript("OnEnter", function(self) if self.actor then ShowBarTooltip(self) end end)
    bar:SetScript("OnLeave", function() GameTooltip:Hide() end)
    bar:SetScript("OnMouseUp", function(self) if self.actor then OpenDetail(self.actor, self._meter) end end)
    return bar
end

local function LayoutBars(m)
    local n = m.p.maxBars
    for i = 1, n do
        local bar = m.bars[i]
        if not bar then bar = CreateBar(m, m.body, i); m.bars[i] = bar end
        bar:SetHeight(db.barHeight)
        bar:ClearAllPoints()
        if i == 1 then
            bar:SetPoint("TOPLEFT", m.body, "TOPLEFT", 0, 0)
            bar:SetPoint("TOPRIGHT", m.body, "TOPRIGHT", 0, 0)
        else
            bar:SetPoint("TOPLEFT", m.bars[i - 1], "BOTTOMLEFT", 0, -2)
            bar:SetPoint("TOPRIGHT", m.bars[i - 1], "BOTTOMRIGHT", 0, -2)
        end
        bar:Hide()
    end
    -- hide any surplus bars from a previous larger maxBars
    for i = n + 1, #m.bars do if m.bars[i] then m.bars[i]:Hide() end end
end

local function SelectedSeg(m)
    if m.viewFight then
        for _, f in ipairs(fights) do
            if f == m.viewFight then return m.viewFight end
        end
        m.viewFight = nil  -- pinned fight rotated out -> fall back
    end
    if m.p.segment == "OVERALL" then return overall end
    return current
end

local _sortBuf = {}
local UpdateInfoBar     -- forward declaration (defined with the info bar), takes a meter
function RefreshMeter(m)
    if not (m.f and m.f:IsShown()) then return end
    local seg  = SelectedSeg(m)
    local mode = m.p.mode

    wipe(_sortBuf)
    local total = 0
    if seg then
        for _, a in pairs(seg.actors) do
            local v = ActorTotal(a, mode)
            if v > 0 then _sortBuf[#_sortBuf + 1] = a; total = total + v end
        end
        sort(_sortBuf, function(x, y) return ActorTotal(x, mode) > ActorTotal(y, mode) end)
    end

    local dur = ActorDuration(seg)
    local topVal = (_sortBuf[1] and ActorTotal(_sortBuf[1], mode)) or 1

    for i = 1, m.p.maxBars do
        local bar = m.bars[i]
        if not bar then break end
        local a = _sortBuf[i]
        if a then
            local v = ActorTotal(a, mode)
            local r, g, b = ClassColor(a.class)
            bar:SetStatusBarColor(r, g, b)
            bar:SetValue(v / topVal)
            bar.left:SetText(format("%d. %s", i, a.name or "?"))
            local perSec = v / dur
            local pct = total > 0 and (v / total * 100) or 0
            bar.right:SetText(format("%s (%s)  %.0f%%", FormatNumber(v), FormatNumber(perSec), pct))
            bar.actor = a
            bar._mode  = mode
            bar._meter = m
            bar:Show()
        else
            bar.actor = nil
            bar:Hide()
        end
    end

    -- header
    local modeTxt = (mode == "TAKEN") and "DTPS" or ((mode == "HEALING") and "HPS" or "DPS")
    local segTxt
    if m.viewFight and seg == m.viewFight then
        segTxt = SegmentLabel(seg)
    elseif m.p.segment == "OVERALL" then
        segTxt = OldschoolUI.L("Total")
    else
        segTxt = (seg and SegmentLabel(seg)) or "Aktueller Kampf"
    end
    m.title:SetText(format("|cff%s%s|r  |cffaaaaaa%s|r", AccentHex(), modeTxt, segTxt))
    m.total:SetText(format("%s  %s", FormatNumber(total), modeTxt))
    if UpdateInfoBar then UpdateInfoBar(m) end
end

function RefreshAll()
    for _, m in ipairs(meters) do RefreshMeter(m) end
end

local function SavePosition(m)
    local p, _, _, x, y = m.f:GetPoint()
    m.p.point = { p, floor(x + 0.5), floor(y + 0.5) }
end

local function ApplyPosition(m)
    m.f:ClearAllPoints()
    local p = m.p.point
    m.f:SetPoint(p[1] or "CENTER", UIParent, p[1] or "CENTER", p[2] or 0, p[3] or 0)
end

local function ApplyLock(m)
    m.f:SetMovable(not m.p.locked)
    m.f:EnableMouse(not m.p.locked)
    if m.lockBtn then m.lockBtn:SetIcon(m.p.locked and ICON_LOCK or ICON_UNLOCK, false) end
    if m.grip then if m.p.locked then m.grip:Hide() else m.grip:Show() end end
end

-- ── Options-page API ─────────────────────────────────────────────────────────
-- Called from OUI_DamageMeter_Options.lua so the config lives in the Core
-- options sidebar. These operate on the global defaults (db.*) and apply the
-- change to every open meter window.
function OldschoolUI_DM_GetLockedDefault()
    return (db and db.locked) and true or false
end
function OldschoolUI_DM_SetLockedAll(v)
    v = v and true or false
    if db then db.locked = v end
    for _, m in ipairs(meters) do m.p.locked = v; ApplyLock(m) end
end
function OldschoolUI_DM_GetMaxBars()
    return (db and db.maxBars) or 8
end
function OldschoolUI_DM_SetMaxBarsAll(n)
    n = math.floor((n or 8) + 0.5)
    if n < 1 then n = 1 end
    if db then db.maxBars = n end
    for _, m in ipairs(meters) do m.p.maxBars = n; LayoutBars(m); RefreshMeter(m) end
end
function OldschoolUI_DM_ResetAll()
    OldschoolUIDamageMeterDB = nil
    OldschoolUIDamageMeterCharDB = nil  -- also clear this character's recorded data
    ReloadUI()
end

local function MakeCtrlButton(parent, tip)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(16, 16)
    local tex = b:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    b.tex = tex
    b.SetIcon = function(_, path, trim)
        tex:SetTexture(path)
        if trim then tex:SetTexCoord(0.08, 0.92, 0.08, 0.92) else tex:SetTexCoord(0, 1, 0, 1) end
    end
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(tip); GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

-------------------------------------------------------------------------------
--  Death log window
-------------------------------------------------------------------------------
local deathWin, deathRows
local DEATH_MAXROWS = 18
local DEATH_HARDCAP = 40
local deathMaxRows  = DEATH_MAXROWS

local function CreateDeathRow(parent, i)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(16)
    row:SetPoint("TOPLEFT", 6, -26 - (i - 1) * 16)
    row:SetPoint("TOPRIGHT", -6, -26 - (i - 1) * 16)
    local fs = row:CreateFontString(nil, "OVERLAY")
    fs:SetPoint("LEFT", 2, 0); fs:SetPoint("RIGHT", -2, 0)
    fs:SetFont(FontPath(), 11, ""); fs:SetJustifyH("LEFT")
    row.fs = fs
    local line = row:CreateTexture(nil, "ARTWORK")
    line:SetTexture("Interface\\Buttons\\WHITE8x8"); line:SetVertexColor(1, 1, 1, 0.18)
    line:SetPoint("BOTTOMLEFT", 0, 1); line:SetPoint("BOTTOMRIGHT", 0, 1); line:SetHeight(1)
    line:Hide()
    row.line = line
    row:EnableMouse(true)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnEnter", function(self)
        local d = self._death
        if not d then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(d.name or "?")
        GameTooltip:AddDoubleLine(OldschoolUI.L("Killing Blow"),
            (d.spell and format("%s (%s)", d.spell, d.src or "?")) or "unbekannt",
            1, 1, 1, 0.9, 0.9, 0.9)
        if d.amount then
            GameTooltip:AddDoubleLine(OldschoolUI.L("Damage"), FormatNumber(d.amount), 1, 1, 1, 1, 0.5, 0.5)
        end
        if d.overkill and d.overkill > 0 then
            GameTooltip:AddDoubleLine(OldschoolUI.L("incl. past death"), FormatNumber(d.overkill), 1, 1, 1, 1, 0.4, 0.4)
        end
        GameTooltip:Show()
    end)
    return row
end

local function RecalcDeathRows()
    if not deathWin then return end
    local h = deathWin:GetHeight()
    if not h or h <= 0 then return end
    local n = floor((h - 36) / 16)
    if n < 1 then n = 1 elseif n > DEATH_HARDCAP then n = DEATH_HARDCAP end
    deathMaxRows = n
end

local function CreateDeathWindow()
    deathWin = CreateFrame("Frame", "OldschoolUIDamageMeterDeaths", UIParent)
    deathWin:SetSize(db.deathWidth, db.deathHeight)
    deathWin:SetResizable(true)
    if deathWin.SetResizeBounds then
        pcall(deathWin.SetResizeBounds, deathWin, 220, 120, 600, 800)
    else
        if deathWin.SetMinResize then pcall(deathWin.SetMinResize, deathWin, 220, 120) end
        if deathWin.SetMaxResize then pcall(deathWin.SetMaxResize, deathWin, 600, 800) end
    end
    deathWin:SetFrameStrata("HIGH")
    deathWin:SetClampedToScreen(true)
    deathWin:SetMovable(true); deathWin:EnableMouse(true)
    deathWin:RegisterForDrag("LeftButton")
    deathWin:SetScript("OnDragStart", function(self) self:StartMoving() end)
    deathWin:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    deathWin:SetPoint("CENTER", UIParent, "CENTER", 0, -60)

    local bg = deathWin:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    bg:SetVertexColor(0.05, 0.05, 0.06, 0.92)
    if OldschoolUI and OldschoolUI.PP and OldschoolUI.PP.CreateBorder then
        pcall(OldschoolUI.PP.CreateBorder, deathWin, 0, 0, 0, 1, 1, "OVERLAY", 7)
    end

    local title = deathWin:CreateFontString(nil, "OVERLAY")
    title:SetPoint("TOPLEFT", 6, -6); title:SetFont(FontPath(), 12, "")
    title:SetText(OldschoolUI.L("Death Log"))
    do local r, g, b = Accent(); title:SetTextColor(r, g, b) end

    local close = CreateFrame("Button", nil, deathWin)
    close:SetSize(16, 16); close:SetPoint("TOPRIGHT", -4, -5)
    local cfs = close:CreateFontString(nil, "OVERLAY")
    cfs:SetAllPoints(); cfs:SetFont(FontPath(), 12, ""); cfs:SetJustifyH("CENTER"); cfs:SetText("x")
    close:SetScript("OnClick", function() deathWin:Hide() end)

    local empty = deathWin:CreateFontString(nil, "OVERLAY")
    empty:SetPoint("TOPLEFT", 8, -28); empty:SetFont(FontPath(), 11, "")
    empty:SetTextColor(0.6, 0.6, 0.6); empty:SetText(OldschoolUI.L("No deaths recorded"))
    deathWin.empty = empty

    deathRows = {}
    for i = 1, DEATH_HARDCAP do
        deathRows[i] = CreateDeathRow(deathWin, i)
        deathRows[i]:Hide()
    end

    local dg = CreateFrame("Button", nil, deathWin)
    dg:SetSize(16, 16); dg:SetPoint("BOTTOMRIGHT", 0, 0)
    dg:SetFrameLevel(deathWin:GetFrameLevel() + 10)
    dg:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    dg:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    dg:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    dg:SetScript("OnMouseDown", function() deathWin:StartSizing("BOTTOMRIGHT") end)
    dg:SetScript("OnMouseUp", function()
        deathWin:StopMovingOrSizing()
        db.deathWidth  = floor(deathWin:GetWidth()  + 0.5)
        db.deathHeight = floor(deathWin:GetHeight() + 0.5)
        RecalcDeathRows(); RefreshDeaths()
    end)
    deathWin:SetScript("OnSizeChanged", function() RecalcDeathRows(); RefreshDeaths() end)
    RecalcDeathRows()
end

local _mergeBuf = {}
function RefreshDeaths()
    if not (deathWin and deathWin:IsShown()) then return end

    wipe(_mergeBuf)
    for _, d in ipairs(deaths)  do _mergeBuf[#_mergeBuf + 1] = d end
    for _, b in ipairs(brezzes) do _mergeBuf[#_mergeBuf + 1] = b end
    sort(_mergeBuf, function(x, y) return (x.seq or 0) > (y.seq or 0) end)

    if #_mergeBuf == 0 then deathWin.empty:Show() else deathWin.empty:Hide() end

    -- Flatten into render rows with a fight separator whenever the segment changes.
    local row, lastSeg, started = 0, nil, false
    for _, e in ipairs(_mergeBuf) do
        if row >= deathMaxRows then break end
        if (not started) or e.segId ~= lastSeg then
            started = true; lastSeg = e.segId
            row = row + 1
            local sep = deathRows[row]
            local sref = SegById(e.segId)
            sep.fs:SetText("|cffffd200" .. ((sref and SegmentLabel(sref)) or "Ausserhalb") .. "|r")
            sep.line:Show(); sep._death = nil; sep:EnableMouse(false)
            sep:Show()
            if row >= deathMaxRows then break end
        end
        row = row + 1
        local r = deathRows[row]
        r.line:Hide(); r:EnableMouse(true)
        if e.kind == "brez" then
            r.fs:SetText(format("|cff999999%s|r  |cff66ff66Brez|r %s -> %s",
                e.timeStr or "", e.src or "?", e.dst or "?"))
            r._death = nil
        else
            local cr, cg, cb = ClassColor(e.class)
            local who = format("|cff%02x%02x%02x%s|r",
                floor(cr * 255), floor(cg * 255), floor(cb * 255), e.name or "?")
            local how = e.spell and format("%s (%s)", e.spell, e.src or "?") or "unbekannt"
            r.fs:SetText(format("|cff999999%s|r  %s  |cffff6060<|r %s", e.timeStr or "", who, how))
            r._death = e
        end
        r:Show()
    end
    for i = row + 1, DEATH_HARDCAP do deathRows[i]:Hide() end
end

local function OpenDeathWindow()
    if not deathWin then CreateDeathWindow() end
    deathWin:Show()
    RefreshDeaths()
end

-------------------------------------------------------------------------------
--  Mode / action menu (hamburger)
-------------------------------------------------------------------------------
local MENU_ITEMS = {
    { mode = "DAMAGE",   label = OldschoolUI.L("Damage") },
    { mode = "HEALING",  label = OldschoolUI.L("Healing") },
    { mode = "TAKEN",    label = OldschoolUI.L("Damage taken") },
    { sep = true },
    { action = "SEGMENT", label = OldschoolUI.L("Select segment") .. " \226\150\184" },
    { action = "DEATHS",  label = OldschoolUI.L("Death Log") },
    { sep = true },
    { action = "NEWWIN",   label = OldschoolUI.L("New Window") },
    { action = "CLOSEWIN", label = OldschoolUI.L("Close Window") },
}
local modeMenu

local function BuildModeMenu()
    modeMenu = CreateFrame("Frame", "OldschoolUIDamageMeterModeMenu", UIParent)
    modeMenu:SetFrameStrata("DIALOG")
    modeMenu:EnableMouse(true)
    local bg = modeMenu:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    bg:SetVertexColor(0.05, 0.05, 0.06, 0.97)
    if OldschoolUI and OldschoolUI.PP and OldschoolUI.PP.CreateBorder then
        pcall(OldschoolUI.PP.CreateBorder, modeMenu, 0, 0, 0, 1, 1, "OVERLAY", 7)
    end
    local function paint(it)
        if it.action == "CLOSEWIN" then
            -- dim "close" when only one window is left
            local dim = (#meters <= 1)
            it.fs:SetTextColor(dim and 0.4 or 0.85, dim and 0.4 or 0.85, dim and 0.4 or 0.85)
            return
        end
        if not it.mode then it.fs:SetTextColor(0.85, 0.85, 0.85); return end
        local m = modeMenu._meter
        local on = m and it.mode == m.p.mode
        if on then local ar, ag, ab = Accent(); it.fs:SetTextColor(ar, ag, ab)
        else it.fs:SetTextColor(0.85, 0.85, 0.85) end
    end
    modeMenu.paint = paint
    modeMenu.items = {}
    local y = -4
    for _, def in ipairs(MENU_ITEMS) do
        if def.sep then
            local line = modeMenu:CreateTexture(nil, "ARTWORK")
            line:SetTexture("Interface\\Buttons\\WHITE8x8"); line:SetVertexColor(1, 1, 1, 0.15)
            line:SetPoint("TOPLEFT", 6, y - 3); line:SetPoint("TOPRIGHT", -6, y - 3); line:SetHeight(1)
            y = y - 8
        else
            local it = CreateFrame("Button", nil, modeMenu)
            it:SetSize(122, 16); it:SetPoint("TOPLEFT", 4, y)
            local fs = it:CreateFontString(nil, "OVERLAY")
            fs:SetPoint("LEFT", 4, 0); fs:SetFont(FontPath(), 11, ""); fs:SetText(def.label)
            it.fs = fs; it.mode = def.mode; it.action = def.action
            paint(it)
            it:SetScript("OnEnter", function(self)
                if not (self.action == "CLOSEWIN" and #meters <= 1) then
                    local ar, ag, ab = Accent(); self.fs:SetTextColor(ar, ag, ab)
                end
            end)
            it:SetScript("OnLeave", function(self)
                paint(self)
                if not modeMenu:IsMouseOver() then modeMenu:Hide() end
            end)
            it:SetScript("OnClick", function(self)
                local m = modeMenu._meter
                modeMenu:Hide()
                if self.mode then
                    if m then m.p.mode = self.mode; RefreshMeter(m) end
                    detailMode = self.mode; RefreshDetail()
                elseif self.action == "DEATHS" then
                    OpenDeathWindow()
                elseif self.action == "SEGMENT" then
                    if m then ToggleSegMenu(m, m.modeBtn) end
                elseif self.action == "NEWWIN" then
                    SpawnMeter(m)
                elseif self.action == "CLOSEWIN" then
                    if m then CloseMeter(m) end
                end
            end)
            modeMenu.items[#modeMenu.items + 1] = it
            y = y - 18
        end
    end
    modeMenu:SetSize(130, -y + 4)
    modeMenu:SetScript("OnShow", function(self)
        for _, it in ipairs(self.items) do paint(it) end
    end)
    modeMenu:SetScript("OnLeave", function(self)
        if not self:IsMouseOver() then self:Hide() end
    end)
end

local function ToggleModeMenu(m, anchor)
    if not modeMenu then BuildModeMenu() end
    if modeMenu:IsShown() then modeMenu:Hide(); return end
    modeMenu._meter = m
    activeMeter = m
    for _, it in ipairs(modeMenu.items) do modeMenu.paint(it) end
    modeMenu:ClearAllPoints()
    modeMenu:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, 0)
    modeMenu:Show()
end

-- Segment picker (opened by clicking the fight name in the header). Rebuilt each
-- open because the fight list changes over time.
local segMenu
function ToggleSegMenu(m, anchor)
    if not segMenu then
        segMenu = CreateFrame("Frame", "OldschoolUIDamageMeterSegMenu", UIParent)
        segMenu:SetFrameStrata("DIALOG")
        segMenu:EnableMouse(true)
        local bg = segMenu:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints()
        bg:SetTexture("Interface\\Buttons\\WHITE8x8"); bg:SetVertexColor(0.05, 0.05, 0.06, 0.97)
        if OldschoolUI and OldschoolUI.PP and OldschoolUI.PP.CreateBorder then
            pcall(OldschoolUI.PP.CreateBorder, segMenu, 0, 0, 0, 1, 1, "OVERLAY", 7)
        end
        segMenu.pool = {}; segMenu.seps = {}
        segMenu:SetScript("OnLeave", function(self) if not self:IsMouseOver() then self:Hide() end end)
    end
    if segMenu:IsShown() then segMenu:Hide(); return end

    local items = {
        { label = OldschoolUI.L("Current"), kind = "CURRENT" },
        { label = OldschoolUI.L("Total"),  kind = "OVERALL" },
        { sep = true },
    }
    for i = #fights, 1, -1 do
        items[#items + 1] = { label = SegmentLabel(fights[i]), kind = "FIGHT", seg = fights[i] }
    end

    for _, b in ipairs(segMenu.pool) do b:Hide() end
    for _, s in ipairs(segMenu.seps) do s:Hide() end

    local bi, si, y = 0, 0, -4
    for _, def in ipairs(items) do
        if def.sep then
            si = si + 1
            local line = segMenu.seps[si]
            if not line then
                line = segMenu:CreateTexture(nil, "ARTWORK")
                line:SetTexture("Interface\\Buttons\\WHITE8x8")
                segMenu.seps[si] = line
            end
            line:SetVertexColor(1, 1, 1, 0.15)
            line:ClearAllPoints()
            line:SetPoint("TOPLEFT", 6, y - 3); line:SetPoint("TOPRIGHT", -6, y - 3); line:SetHeight(1)
            line:Show()
            y = y - 8
        else
            bi = bi + 1
            local b = segMenu.pool[bi]
            if not b then
                b = CreateFrame("Button", nil, segMenu)
                b:SetHeight(16)
                local fs = b:CreateFontString(nil, "OVERLAY")
                fs:SetPoint("LEFT", 4, 0); fs:SetFont(FontPath(), 11, "")
                b.fs = fs
                b:SetScript("OnEnter", function(self) local ar, ag, ab = Accent(); self.fs:SetTextColor(ar, ag, ab) end)
                b:SetScript("OnLeave", function(self)
                    if self._on then local ar, ag, ab = Accent(); self.fs:SetTextColor(ar, ag, ab) else self.fs:SetTextColor(0.9, 0.9, 0.9) end
                    if not segMenu:IsMouseOver() then segMenu:Hide() end
                end)
                segMenu.pool[bi] = b
            end
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", 4, y); b:SetPoint("TOPRIGHT", -4, y)
            b.fs:SetText(def.label)
            local on
            if def.kind == "OVERALL" then on = (not m.viewFight) and m.p.segment == "OVERALL"
            elseif def.kind == "CURRENT" then on = (not m.viewFight) and m.p.segment ~= "OVERALL"
            else on = (m.viewFight == def.seg) end
            b._on = on
            if on then local ar, ag, ab = Accent(); b.fs:SetTextColor(ar, ag, ab) else b.fs:SetTextColor(0.9, 0.9, 0.9) end
            b:SetScript("OnClick", function()
                segMenu:Hide()
                if def.kind == "OVERALL" then m.p.segment = "OVERALL"; m.viewFight = nil
                elseif def.kind == "CURRENT" then m.p.segment = "CURRENT"; m.viewFight = nil
                else m.viewFight = def.seg; m.p.segment = "CURRENT" end
                RefreshMeter(m); RefreshDetail()
            end)
            b:Show()
            y = y - 18
        end
    end
    segMenu:SetSize(180, -y + 4)
    segMenu:ClearAllPoints()
    segMenu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, 0)
    segMenu:Show()
end

-------------------------------------------------------------------------------
--  Info bar: deaths / battle-rezzes / dispels / time-to-boss-death
-------------------------------------------------------------------------------
local function CountEvents(listTbl, seg)
    if seg == overall then return #listTbl end
    if not seg then return 0 end
    local n = 0
    for _, e in ipairs(listTbl) do if e.segId == seg.id then n = n + 1 end end
    return n
end

local function SegDPS(seg)
    if not seg then return 0 end
    local tot = 0
    for _, a in pairs(seg.actors) do tot = tot + (a.damage or 0) end
    local dur = ActorDuration(seg)
    return (dur and dur > 0) and (tot / dur) or 0
end

local function FindBossHP()
    for i = 1, 5 do
        local u = "boss" .. i
        if UnitExists(u) and not UnitIsDead(u) then
            local hp = UnitHealth(u)
            if hp and hp > 0 then return hp, UnitName(u) end
        end
    end
    if UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDead("target") then
        local hp = UnitHealth("target")
        if hp and hp > 0 then return hp, UnitName("target") end
    end
    return nil
end

local function FmtTime(s)
    s = floor(s + 0.5)
    if s >= 3600 then return format("%d:%02d:%02d", floor(s / 3600), floor((s % 3600) / 60), s % 60) end
    return format("%d:%02d", floor(s / 60), s % 60)
end

local INFO_TIP = { deaths = "Tode", brez = "Kampf-Wiederbelebungen",
                   dispel = "Entzauberungen", ttk = "Zeit bis Boss-Tod" }

local function InfoTooltip(w)
    local m = w._meter
    local seg = m and SelectedSeg(m)
    if not seg then return end
    GameTooltip:SetOwner(w, "ANCHOR_BOTTOM")
    GameTooltip:AddLine(INFO_TIP[w.kind] or "")
    local any = false
    if w.kind == "deaths" then
        for i = #deaths, 1, -1 do
            local d = deaths[i]
            if seg == overall or d.segId == seg.id then
                any = true
                local how = d.spell and format("%s (%s)", d.spell, d.src or "?") or "?"
                GameTooltip:AddDoubleLine(d.name or "?", how, 1, 0.5, 0.5, 0.9, 0.9, 0.9)
            end
        end
    elseif w.kind == "brez" then
        for i = #brezzes, 1, -1 do
            local e = brezzes[i]
            if seg == overall or e.segId == seg.id then
                any = true
                GameTooltip:AddDoubleLine(e.src or "?", "-> " .. (e.dst or "?"), 1, 1, 1, 0.6, 1, 0.6)
            end
        end
    elseif w.kind == "dispel" then
        for i = #dispels, 1, -1 do
            local e = dispels[i]
            if seg == overall or e.segId == seg.id then
                any = true
                GameTooltip:AddDoubleLine(e.src or "?",
                    format("%s @ %s", e.spell or "?", e.target or "?"), 1, 1, 1, 0.8, 0.8, 1)
            end
        end
    elseif w.kind == "ttk" then
        local hp, nm = FindBossHP()
        local dps = SegDPS(seg)
        if hp and dps > 0 then
            any = true
            GameTooltip:AddDoubleLine(nm or OldschoolUI.L("Target"), FormatNumber(hp) .. " HP", 1, 1, 1, 0.9, 0.9, 0.9)
            GameTooltip:AddDoubleLine(OldschoolUI.L("Group DPS"), FormatNumber(dps), 1, 1, 1, 0.9, 0.9, 0.9)
            GameTooltip:AddDoubleLine(OldschoolUI.L("Remaining"), FmtTime(hp / dps), 1, 1, 1, 1, 0.82, 0)
        end
    end
    if not any then GameTooltip:AddLine(OldschoolUI.L("none"), 0.6, 0.6, 0.6) end
    GameTooltip:Show()
end

local INFO_KINDS = {
    { kind = "deaths", icon = ICON_DEATH },
    { kind = "brez",   icon = "Interface\\Icons\\Spell_Nature_Reincarnation" },
    { kind = "dispel", icon = "Interface\\Icons\\Spell_Holy_DispelMagic" },
    { kind = "ttk",    icon = "Interface\\Icons\\INV_Misc_PocketWatch_02" },
}

local function CreateInfoBar(m)
    local bar = CreateFrame("Frame", nil, m.f)
    bar:SetPoint("TOPLEFT", 0, 0); bar:SetPoint("TOPRIGHT", 0, 0)
    bar:SetHeight(16)
    local prev
    for _, def in ipairs(INFO_KINDS) do
        local w = CreateFrame("Frame", nil, bar)
        w:SetSize(def.kind == "ttk" and 58 or 40, 16); w:EnableMouse(true)
        if prev then w:SetPoint("LEFT", prev, "RIGHT", 6, 0) else w:SetPoint("LEFT", 6, 0) end
        local ic = w:CreateTexture(nil, "ARTWORK")
        ic:SetSize(13, 13); ic:SetPoint("LEFT", 0, 0)
        ic:SetTexCoord(0.08, 0.92, 0.08, 0.92); ic:SetTexture(def.icon)
        local cnt = w:CreateFontString(nil, "OVERLAY")
        cnt:SetPoint("LEFT", ic, "RIGHT", 2, 0); cnt:SetFont(FontPath(), 11, "")
        cnt:SetTextColor(0.9, 0.9, 0.9); cnt:SetText("0")
        w.count = cnt; w.kind = def.kind; w._meter = m
        w:SetScript("OnEnter", InfoTooltip)
        w:SetScript("OnLeave", function() GameTooltip:Hide() end)
        bar[def.kind] = w
        prev = w
    end
    return bar
end

function UpdateInfoBar(m)
    if not (m and m.info) then return end
    local seg = SelectedSeg(m)
    m.info.deaths.count:SetText(CountEvents(deaths, seg))
    m.info.brez.count:SetText(CountEvents(brezzes, seg))
    m.info.dispel.count:SetText(CountEvents(dispels, seg))
    local hp = FindBossHP()
    local dps = SegDPS(seg)
    if hp and dps > 0 then
        m.info.ttk.count:SetText(FmtTime(hp / dps))
    else
        m.info.ttk.count:SetText("--")
    end
end

local function RecalcBars(m)
    if not (m.f and m.body) then return end
    local avail = m.body:GetHeight()
    if not avail or avail <= 0 then avail = (m.p.height or 210) - 38 end
    local n = floor((avail + 2) / (db.barHeight + 2))
    if n < 1 then n = 1 end
    if n ~= m.p.maxBars then
        m.p.maxBars = n
        LayoutBars(m)
    end
    RefreshMeter(m)
end

local meterFrameCount = 0
function CreateMeter(p)
    meterFrameCount = meterFrameCount + 1
    local m = { p = p, bars = {}, viewFight = nil }
    local f = CreateFrame("Frame", "OldschoolUIDamageMeterFrame" .. meterFrameCount, UIParent)
    m.f = f
    f:SetSize(p.width, p.height)
    f:SetResizable(true)
    if f.SetResizeBounds then
        pcall(f.SetResizeBounds, f, 160, 90, 600, 800)
    else
        if f.SetMinResize then pcall(f.SetMinResize, f, 160, 90) end
        if f.SetMaxResize then pcall(f.SetMaxResize, f, 600, 800) end
    end
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) if not p.locked then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePosition(m) end)

    local bgt = f:CreateTexture(nil, "BACKGROUND")
    bgt:SetAllPoints(); bgt:SetTexture("Interface\\Buttons\\WHITE8x8")
    bgt:SetVertexColor(0.05, 0.05, 0.06, 0.92)
    if OldschoolUI and OldschoolUI.PP and OldschoolUI.PP.CreateBorder then
        pcall(OldschoolUI.PP.CreateBorder, f, 0, 0, 0, 1, 1, "OVERLAY", 7)
    end

    -- info bar (top) + header row beneath it
    m.info = CreateInfoBar(m)

    local header = CreateFrame("Frame", nil, f)
    header:SetPoint("TOPLEFT", m.info, "BOTTOMLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", m.info, "BOTTOMRIGHT", 0, 0)
    header:SetHeight(20)
    m.header = header

    local titleBtn = CreateFrame("Button", nil, header)
    titleBtn:SetPoint("LEFT", 4, 0)
    titleBtn:SetPoint("RIGHT", header, "RIGHT", -76, 0)
    titleBtn:SetHeight(20)
    titleBtn:SetScript("OnClick", function(self) ToggleSegMenu(m, self) end)
    titleBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(OldschoolUI.L("Select segment")); GameTooltip:Show()
    end)
    titleBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    m.titleBtn = titleBtn

    m.title = titleBtn:CreateFontString(nil, "OVERLAY")
    m.title:SetPoint("LEFT", 2, 0)
    m.title:SetPoint("RIGHT", -2, 0)
    m.title:SetJustifyH("LEFT")
    m.title:SetFont(FontPath(), 12, "")
    m.title:SetShadowOffset(1, -1)

    -- control buttons (right side of header): mode/window menu, segment, lock, reset
    local resetBtn = MakeCtrlButton(header, OldschoolUI.L("Reset"))
    resetBtn:SetPoint("RIGHT", -4, 0)
    resetBtn:SetIcon(ICON_RESET, false)
    resetBtn:SetScript("OnClick", function() ResetData(); RefreshAll() end)
    m.resetBtn = resetBtn

    local lockBtn = MakeCtrlButton(header, "Sperren / Entsperren")
    lockBtn:SetPoint("RIGHT", resetBtn, "LEFT", -2, 0)
    lockBtn:SetScript("OnClick", function() p.locked = not p.locked; ApplyLock(m) end)
    m.lockBtn = lockBtn

    local segBtn = MakeCtrlButton(header, OldschoolUI.L("Segment: current fight / overall"))
    segBtn:SetPoint("RIGHT", lockBtn, "LEFT", -2, 0)
    segBtn:SetIcon(ICON_SEG, true)
    segBtn:SetScript("OnClick", function()
        m.viewFight = nil
        p.segment = (p.segment == "OVERALL") and "CURRENT" or "OVERALL"
        RefreshMeter(m)
    end)
    m.segBtn = segBtn

    local modeBtn = MakeCtrlButton(header, OldschoolUI.L("Mode / Window / Death Log"))
    modeBtn:SetPoint("RIGHT", segBtn, "LEFT", -2, 0)
    modeBtn:SetIcon(ICON_MENU, true)
    modeBtn:SetScript("OnClick", function(self) ToggleModeMenu(m, self) end)
    m.modeBtn = modeBtn

    -- footer total
    m.total = f:CreateFontString(nil, "OVERLAY")
    m.total:SetPoint("BOTTOMLEFT", 6, 4)
    m.total:SetFont(FontPath(), 11, "")
    m.total:SetTextColor(0.8, 0.8, 0.85)

    -- body (bars container)
    local body = CreateFrame("Frame", nil, f)
    body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 4, -2)
    body:SetPoint("BOTTOMRIGHT", -4, 16)
    m.body = body

    -- resize grip (bottom-right corner)
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", 0, 0)
    grip:SetFrameLevel(f:GetFrameLevel() + 10)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function()
        if not p.locked then f:StartSizing("BOTTOMRIGHT") end
    end)
    grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        p.width  = floor(f:GetWidth()  + 0.5)
        p.height = floor(f:GetHeight() + 0.5)
        RecalcBars(m)
    end)
    m.grip = grip

    f:SetScript("OnSizeChanged", function() RecalcBars(m) end)

    meters[#meters + 1] = m
    LayoutBars(m)
    ApplyPosition(m)
    ApplyLock(m)
    RecalcBars(m)
    return m
end

-- Spawn a brand-new meter window (from the OldschoolUI.L("New Window") menu entry).
function SpawnMeter(fromMeter)
    local p = NewProfile()
    if fromMeter and fromMeter.p then
        -- a fresh window defaults to a complementary mode + slight offset
        p.mode = (fromMeter.p.mode == "DAMAGE") and "HEALING" or "DAMAGE"
        local pt = fromMeter.p.point
        if type(pt) == "table" then
            p.point = { pt[1] or "CENTER", (pt[2] or 0) + 30, (pt[3] or 0) - 30 }
        end
    end
    db.windows[#db.windows + 1] = p
    local m = CreateMeter(p)
    m.f:Show(); p.shown = true
    RefreshMeter(m)
    return m
end

-- Close a meter window (keeps at least one window alive).
function CloseMeter(m)
    if #meters <= 1 then return end
    for i = #meters, 1, -1 do if meters[i] == m then tremove(meters, i) end end
    for i = #db.windows, 1, -1 do if db.windows[i] == m.p then tremove(db.windows, i) end end
    m.f:Hide()
    m.f:SetParent(nil)   -- orphan it; frames can't be destroyed, but it's gone from view
end

-------------------------------------------------------------------------------
--  Refresh ticker
-------------------------------------------------------------------------------
local _acc = 0
local function OnUpdate(_, dt)
    _acc = _acc + dt
    if _acc >= 0.5 then _acc = 0; RefreshAll(); RefreshDetail() end
end

-------------------------------------------------------------------------------
--  Public toggle + slash
-------------------------------------------------------------------------------
local function ToggleWindow(show)
    if #meters == 0 then return end
    if show == nil then show = not meters[1].f:IsShown() end
    for _, m in ipairs(meters) do
        m.p.shown = show
        if show then m.f:Show(); RefreshMeter(m) else m.f:Hide() end
    end
end

local function SetAllModes(mode)
    for _, m in ipairs(meters) do m.p.mode = mode end
    RefreshAll()
    detailMode = mode; RefreshDetail()
end

SLASH_OUIDM1 = "/ouidm"
SLASH_OUIDM2 = "/ouimeter"
SlashCmdList["OUIDM"] = function(msg)
    msg = (msg or ""):lower():gsub("%s+", "")
    if msg == "reset" then
        ResetData(); RefreshAll()
    elseif msg == "lock" then
        for _, m in ipairs(meters) do m.p.locked = true;  ApplyLock(m) end
    elseif msg == "unlock" then
        for _, m in ipairs(meters) do m.p.locked = false; ApplyLock(m) end
    elseif msg == "new" or msg == "neu" then
        SpawnMeter(meters[1])
    elseif msg == "heal" or msg == "healing" then
        SetAllModes("HEALING")
    elseif msg == "dmg" or msg == "damage" then
        SetAllModes("DAMAGE")
    elseif msg == "taken" or msg == "erhalten" then
        SetAllModes("TAKEN")
    else
        ToggleWindow()
    end
end

-------------------------------------------------------------------------------
--  Events
-------------------------------------------------------------------------------
local ef = CreateFrame("Frame")
ef:RegisterEvent("ADDON_LOADED")
ef:RegisterEvent("PLAYER_LOGIN")
ef:RegisterEvent("PLAYER_LOGOUT")
ef:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        ApplyDefaults()
        LoadLog()
        return
    end

    if event == "PLAYER_LOGOUT" then
        SaveLog()
        return
    end

    if event == "PLAYER_LOGIN" then
        if OUI.IsModuleEnabled and not OUI:IsModuleEnabled("OUI_DamageMeter") then return end
        if not db then ApplyDefaults() end
        for _, p in ipairs(db.windows) do
            local m = CreateMeter(p)
            if p.shown == false then m.f:Hide() end
        end
        self:SetScript("OnUpdate", OnUpdate)
        RescanPets()

        if OUI.RegisterUnlockElements and OUI.MakeUnlockElement then
            OUI:RegisterUnlockElements({ OUI.MakeUnlockElement({
                key = "OUIDamageMeter", label = "Damage Meter", group = "Damage Meter", order = 580,
                getFrame = function() return meters[1] and meters[1].f end,
                getSize  = function() local m = meters[1]
                    return (m and m.f and m.f:GetWidth()) or 200, (m and m.f and m.f:GetHeight()) or 120 end,
                isHidden = function() local m = meters[1]; return not (m and m.f and m.f:IsShown()) end,
                savePos  = function(_, _, _, x, y)
                    local m = meters[1]
                    if m and m.f then
                        m.f:ClearAllPoints(); m.f:SetPoint("CENTER", UIParent, "CENTER", x, y)
                        SavePosition(m)
                    end
                end,
                applyPos = function() local m = meters[1]; if m then ApplyPosition(m) end end,
            }) })
        end

        self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        self:RegisterEvent("PLAYER_REGEN_DISABLED")
        self:RegisterEvent("PLAYER_REGEN_ENABLED")
        self:RegisterEvent("GROUP_ROSTER_UPDATE")
        self:RegisterEvent("UNIT_PET")
        return
    end

    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        if CLGetInfo then ParseCLEU(CLGetInfo()) end
        return
    end

    if event == "PLAYER_REGEN_DISABLED" then
        StartCombat()
    elseif event == "PLAYER_REGEN_ENABLED" then
        EndCombat()
    elseif event == "GROUP_ROSTER_UPDATE" or event == "UNIT_PET" then
        RescanPets()
    end
end)

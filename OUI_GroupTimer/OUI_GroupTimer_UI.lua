-------------------------------------------------------------------------------
--  OUI_GroupTimer_UI.lua  --  Live run overlay + stats window + minimap button
--  (MT-3..5). Reads engine state via the _OUIGT_* bridge globals exposed by
--  OUI_GroupTimer.lua: _OUIGT_AceDB, _OUIGT_GroupRun, _OUIGT_StatsStore.
-------------------------------------------------------------------------------

local OUI = OldschoolUI
if not OUI then return end

local L      = OUI.L or function(s) return s end
local format = string.format
local floor, max = math.floor, math.max
local min = math.min

local CATEGORIES = { "CHALLENGE", "HEROIC", "RAID" }
local CAT_LABEL  = {
    CHALLENGE = "Challenge Mode",
    HEROIC    = "Heroic Dungeon",
    RAID      = "Raid",
}

local function Profile()
    local db = _G._OUIGT_AceDB
    return db and db.profile
end
local function Stats(category, instKey)
    if _G._OUIGT_StatsStore then return _G._OUIGT_StatsStore(category, instKey) end
end
local function StatsRoot()
    local p = Profile()
    return p and p.stats
end
local function Font()
    return (OUI.GetFontPath and OUI.GetFontPath()) or STANDARD_TEXT_FONT
end
local function Accent()
    if OUI.GetAccentColor then local r, g, b = OUI.GetAccentColor(); if r then return r, g, b end end
    local a = OUI.ACCENT or {}; return a.r or 0.85, a.g or 0.64, a.b or 0.25
end

local function FmtTime(s)
    s = max(0, floor((s or 0) + 0.5))
    local h = floor(s / 3600); local m = floor((s % 3600) / 60); local sec = s % 60
    if h > 0 then return format("%d:%02d:%02d", h, m, sec) end
    return format("%d:%02d", m, sec)
end

-- delta of cur vs best (best = best-ever-to-this-boss); nil best -> new best
local function FmtDelta(cur, best)
    if not best then return "|cffffd200" .. L("best") .. "|r" end
    local d = cur - best
    if d <= 0 then return "|cff44ff44-" .. FmtTime(-d) .. "|r" end
    return "|cffff5555+" .. FmtTime(d) .. "|r"
end

local function Border(f)
    if OUI.PP and OUI.PP.CreateBorder then
        local r, g, b = Accent()
        OUI.PP.CreateBorder(f, r, g, b, 1, 1)
    end
end

-------------------------------------------------------------------------------
--  MT-3  Live run overlay
-------------------------------------------------------------------------------
local live
local liveRows = {}
local barTicks, barLabels = {}, {}

local LIVE_W   = 230            -- overlay width
local BAR_PAD  = 8
local function BarWidth() return LIVE_W - BAR_PAD * 2 end

local function BuildLive()
    if live then return live end
    local f = CreateFrame("Frame", "OUIGroupTimerRun", UIParent)
    f:SetSize(LIVE_W, 130)
    local p = Profile()
    local pos = p and p.runPos
    if pos and pos.x then
        f:SetPoint("CENTER", UIParent, "CENTER", pos.x, pos.y)
    else
        f:SetPoint("TOP", UIParent, "TOP", 0, -260)
    end
    f:SetFrameStrata("MEDIUM")

    local bg = f:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints()
    bg:SetColorTexture(0.06, 0.06, 0.07, 0.88)
    Border(f)

    -- header: instance name + category. Single line so a long name never wraps
    -- down into the clock (the overlap bug).
    local title = f:CreateFontString(nil, "OVERLAY")
    title:SetFont(Font(), 12, "OUTLINE")
    title:SetPoint("TOPLEFT", 8, -6); title:SetPoint("TOPRIGHT", -8, -6)
    title:SetJustifyH("LEFT"); title:SetWordWrap(false); title:SetMaxLines(1)
    local ar, ag, ab = Accent(); title:SetTextColor(ar, ag, ab)
    f.title = title

    local clock = f:CreateFontString(nil, "OVERLAY")
    clock:SetFont(Font(), 20, "OUTLINE"); clock:SetPoint("TOPLEFT", 8, -22)
    f.clock = clock

    local sub = f:CreateFontString(nil, "OVERLAY")
    sub:SetFont(Font(), 11, ""); sub:SetPoint("TOPRIGHT", -8, -28)
    sub:SetTextColor(0.8, 0.8, 0.85); sub:SetJustifyH("RIGHT"); f.sub = sub

    f.body = CreateFrame("Frame", nil, f)
    f.body:SetPoint("TOPLEFT", 8, -48); f.body:SetWidth(LIVE_W - 16); f.body:SetHeight(1)

    -- timer bar: track + fill + cursor + finish marker (ticks/labels pooled)
    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("TOPLEFT", f.body, "BOTTOMLEFT", 0, -8)
    bar:SetWidth(BarWidth()); bar:SetHeight(7)
    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints(); track:SetColorTexture(0.15, 0.14, 0.16, 1)
    local fill = bar:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT"); fill:SetPoint("BOTTOMLEFT"); fill:SetWidth(1)
    fill:SetColorTexture(ar, ag, ab, 0.8)
    local cursor = bar:CreateTexture(nil, "OVERLAY")
    cursor:SetColorTexture(1, 1, 1, 1); cursor:SetSize(2, 15)
    local finish = bar:CreateTexture(nil, "OVERLAY")
    finish:SetColorTexture(0.90, 0.50, 0.23, 1); finish:SetSize(3, 14)
    f.bar = bar; f.barFill = fill; f.barCursor = cursor; f.barFinish = finish

    live = f
    return f
end

local function LiveRow(i)
    if liveRows[i] then return liveRows[i] end
    local f = BuildLive()
    local r = CreateFrame("Frame", nil, f.body); r:SetHeight(14)
    if i == 1 then r:SetPoint("TOPLEFT", f.body, "TOPLEFT", 0, 0); r:SetPoint("TOPRIGHT", f.body, "TOPRIGHT", 0, 0)
    else local prev = LiveRow(i - 1); r:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -1); r:SetPoint("TOPRIGHT", prev, "BOTTOMRIGHT", 0, -1) end
    r.name = r:CreateFontString(nil, "OVERLAY"); r.name:SetFont(Font(), 11, "")
    r.name:SetPoint("LEFT", 0, 0); r.name:SetJustifyH("LEFT")
    r.val = r:CreateFontString(nil, "OVERLAY"); r.val:SetFont(Font(), 11, "")
    r.val:SetPoint("RIGHT", 0, 0); r.val:SetJustifyH("RIGHT")
    liveRows[i] = r
    return r
end

local function BarTick(i)
    if barTicks[i] then return barTicks[i] end
    local f = BuildLive()
    local t = f.bar:CreateTexture(nil, "ARTWORK")
    t:SetColorTexture(0.85, 0.64, 0.25, 1); t:SetSize(2, 13)
    barTicks[i] = t
    return t
end

local function BarLabel(i)
    if barLabels[i] then return barLabels[i] end
    local f = BuildLive()
    local fs = f:CreateFontString(nil, "OVERLAY")
    fs:SetFont(Font(), 11, ""); fs:SetJustifyH("CENTER"); fs:SetWidth(46)
    barLabels[i] = fs
    return fs
end

-- render the bar: a tick at each boss best-split, a finish marker at the best
-- total, a moving cursor at the current elapsed. Returns the height it used.
local function RenderBar(f, splits, bossCount, bestTotal, elapsed)
    local W = BarWidth()
    local maxSplit = 0
    for i = 1, bossCount or 0 do
        local s = splits and splits[i]
        if s and s > maxSplit then maxSplit = s end
    end
    local hi = max(bestTotal or 0, maxSplit, elapsed or 0, 1)
    local R  = hi * 1.04
    local fpct = max(0, min(1, (elapsed or 0) / R))
    f.barFill:SetWidth(max(1, fpct * W))
    f.barCursor:ClearAllPoints()
    f.barCursor:SetPoint("TOP", f.bar, "TOPLEFT", fpct * W, 4); f.barCursor:Show()
    if bestTotal and bestTotal > 0 then
        local pct = min(1, bestTotal / R)
        f.barFinish:ClearAllPoints()
        f.barFinish:SetPoint("TOP", f.bar, "TOPLEFT", pct * W, 4); f.barFinish:Show()
    else
        f.barFinish:Hide()
    end
    local showTimes = (bossCount or 0) <= 4
    for i = 1, bossCount or 0 do
        local s = splits and splits[i]
        local tick, lbl = BarTick(i), BarLabel(i)
        if s and s > 0 then
            local pct = min(1, s / R)
            tick:ClearAllPoints(); tick:SetPoint("TOP", f.bar, "TOPLEFT", pct * W, 3); tick:Show()
            lbl:ClearAllPoints(); lbl:SetPoint("TOP", f.bar, "TOPLEFT", pct * W - 23, -10)
            lbl:SetTextColor(0.81, 0.70, 0.47)
            if showTimes then lbl:SetText("B" .. i .. "\n|cff888888" .. FmtTime(s) .. "|r")
            else lbl:SetText(tostring(i)) end
            lbl:Show()
        else
            tick:Hide(); lbl:Hide()
        end
    end
    for i = (bossCount or 0) + 1, #barTicks do if barTicks[i] then barTicks[i]:Hide() end end
    for i = (bossCount or 0) + 1, #barLabels do if barLabels[i] then barLabels[i]:Hide() end end
    return 7 + (showTimes and 26 or 16)
end

-- best split per boss index, from the best full-clear splits or per-boss bests
local function StoreSplits(store, bossCount)
    local splits = {}
    local src = (store and store.best and store.best.splits) or (store and store.bestSplits)
    if src then for i = 1, bossCount or 0 do splits[i] = src[i] end end
    return splits
end

-- shared layout for ready / live / review states
local function LayoutLive(opts)
    local f = BuildLive(); f:Show()
    f.title:SetText((opts.instName or "?") .. "  |cff888888" .. (opts.category or "") .. "|r")
    f.clock:SetText(opts.clockGhost and ("|cff888888" .. FmtTime(0) .. "|r") or FmtTime(opts.elapsed or 0))
    f.sub:SetText(L("Deaths") .. ": " .. (opts.deaths or 0)
        .. (opts.bestTotal and ("   |cff888888" .. L("Best") .. " " .. FmtTime(opts.bestTotal) .. "|r") or ""))
    local rows = opts.rows or {}
    for i = 1, #rows do
        local r = LiveRow(i); r.name:SetText(rows[i].name); r.val:SetText(rows[i].val or ""); r:Show()
    end
    for i = #rows + 1, #liveRows do if liveRows[i] then liveRows[i]:Hide() end end
    f.body:SetHeight(max(1, #rows * 15))
    local barH = RenderBar(f, opts.splits, opts.bossCount or 0, opts.bestTotal, opts.elapsed or 0)
    f:SetHeight(48 + #rows * 15 + 8 + barH + 10)
end

local PREVIEW_BOSSES = {
    { name = "Stone Guard", elapsed = 54,  best = 62 },
    { name = "Feng",        elapsed = 150, best = 145 },
    { name = "Gara'jal",    elapsed = 228, best = 230 },
}

-- shown while unlock mode is active and no real run is in progress
local function PreviewLive()
    local rows, splits = {}, {}
    for i, b in ipairs(PREVIEW_BOSSES) do
        rows[i] = { name = format("%d. %s", i, b.name),
                    val = FmtTime(b.elapsed) .. "  " .. FmtDelta(b.elapsed, b.best) }
        splits[i] = b.best
    end
    LayoutLive({ instName = L("Group Timer"), category = L("Preview"),
        elapsed = 234, deaths = 1, bestTotal = 258,
        rows = rows, splits = splits, bossCount = 3 })
end

local function RefreshLive()
    local GR = _G._OUIGT_GroupRun
    local p = Profile()
    local unlocking = OUI and OUI._unlockActive
    if (p and p.showRunOverlay == false) and not unlocking then
        if live then live:Hide() end; return
    end

    -- 1) active run
    if GR and GR.active then
        local store = Stats(GR.category, GR.instKey)
        local best  = store and store.best
        local bossCount = (store and store.bossCount and store.bossCount > 0 and store.bossCount) or #GR.bosses
        local splits = StoreSplits(store, bossCount)
        local rows = {}
        for i = 1, #GR.bosses do
            local b = GR.bosses[i]
            rows[i] = { name = format("%d. %s", i, b.name),
                        val = FmtTime(b.elapsed) .. "  " .. FmtDelta(b.elapsed, b.best) }
        end
        LayoutLive({ instName = GR.instName, category = L(CAT_LABEL[GR.category] or ""),
            elapsed = GetTime() - (GR.startTime or GetTime()), deaths = GR.deaths or 0,
            bestTotal = best and best.total, rows = rows, splits = splits, bossCount = bossCount })
        return
    end

    -- 2) post-run review of the just-finished run (until zone-out)
    local last = _G._OUIGT_LastRun
    if last then
        local store = Stats(last.category, last.instKey)
        local best  = store and store.best
        local bossCount = (store and store.bossCount and store.bossCount > 0 and store.bossCount)
            or (last.bosses and #last.bosses) or 0
        local splits = StoreSplits(store, bossCount)
        local rows = {}
        for i = 1, #(last.bosses or {}) do
            local b = last.bosses[i]
            rows[i] = { name = format("%d. %s", i, b.name),
                        val = FmtTime(b.elapsed) .. "  " .. FmtDelta(b.elapsed, b.best) }
        end
        LayoutLive({ instName = last.instName,
            category = L(CAT_LABEL[last.category] or "") .. " |cff44ff44" .. L("done") .. "|r",
            elapsed = last.elapsed, deaths = last.deaths or 0, bestTotal = best and best.total,
            rows = rows, splits = splits, bossCount = bossCount })
        return
    end

    -- 3) ready: entered the instance, before the first pull (clock at 0:00)
    if GR and GR._armed then
        local a = GR._armed
        local store = Stats(a.cat, a.key)
        local best  = store and store.best
        local names = (store and (store.bossOrder or store.bossNames))
            or (_G._OUIGT_JournalBosses and _G._OUIGT_JournalBosses(a.name)) or {}
        local bossCount = (store and store.bossCount and store.bossCount > 0 and store.bossCount) or #names
        local splits = StoreSplits(store, bossCount)
        local rows = {}
        for i = 1, #names do rows[i] = { name = format("%d. %s", i, names[i]), val = "--" } end
        LayoutLive({ instName = a.name, category = L(CAT_LABEL[a.cat] or ""),
            elapsed = 0, clockGhost = true, deaths = 0, bestTotal = best and best.total,
            rows = rows, splits = splits, bossCount = bossCount })
        return
    end

    -- 4) unlock preview
    if unlocking then PreviewLive(); return end

    if live then live:Hide() end
end

-------------------------------------------------------------------------------
--  MT-4  Stats window
-------------------------------------------------------------------------------
local statsWin
local statsCategory = "HEROIC"
local statsInst                      -- selected instance key
local instRows, splitRows, runRows = {}, {}, {}

local function SortedInstances(category)
    local root = StatsRoot()
    local cat = root and root[category]
    local list = {}
    if cat then
        for key, s in pairs(cat) do
            local hasData = (s.runs and #s.runs > 0) or (s.bestSplits and next(s.bestSplits) ~= nil)
            if hasData then
                list[#list + 1] = { key = key, name = s.name or key, best = s.best and s.best.total, runs = s.runs and #s.runs or 0 }
            end
        end
    end
    table.sort(list, function(a, b) return (a.name or "") < (b.name or "") end)
    return list
end

local function RefreshStats()
    if not (statsWin and statsWin:IsShown()) then return end

    -- category tab highlight
    for _, cat in ipairs(CATEGORIES) do
        local tab = statsWin.tabs[cat]
        local on = (cat == statsCategory)
        tab.bg:SetColorTexture(on and 0.20 or 0.10, on and 0.16 or 0.10, on and 0.05 or 0.10, on and 0.95 or 0.6)
    end

    -- left: instance list
    local insts = SortedInstances(statsCategory)
    if statsInst and not (StatsRoot() and StatsRoot()[statsCategory] and StatsRoot()[statsCategory][statsInst]) then
        statsInst = nil
    end
    if not statsInst and insts[1] then statsInst = insts[1].key end
    for i = 1, 14 do
        local row = instRows[i]; local e = insts[i]
        if e then
            row:Show()
            row.label:SetText(e.name)
            row.val:SetText(e.best and FmtTime(e.best) or "-")
            local sel = (e.key == statsInst)
            row.bg:SetColorTexture(sel and 0.22 or 0, sel and 0.17 or 0, sel and 0.05 or 0, sel and 0.9 or 0)
            row._key = e.key
        else row:Hide() end
    end

    -- right: detail for selected instance
    local store = statsInst and StatsRoot() and StatsRoot()[statsCategory] and StatsRoot()[statsCategory][statsInst]
    local d = statsWin.detail
    if not store then
        d.head:SetText(L("No data"))
        d.summary:SetText("")
        for _, r in ipairs(splitRows) do r:Hide() end
        for _, r in ipairs(runRows) do r:Hide() end
        return
    end
    d.head:SetText(store.name or statsInst)
    local best = store.best
    if not best and store.runs then
        -- fallback for older entries: derive the best completed run on the fly
        for _, r in ipairs(store.runs) do
            if r.completed and (not best or (r.total or math.huge) < best.total) then
                best = { total = r.total, deaths = r.deaths }
            end
        end
    end
    d.summary:SetText(format("%s: %s    %s: %s",
        L("Best completion"), best and FmtTime(best.total) or "-",
        L("Deaths"), best and tostring(best.deaths or 0) or "-"))

    -- per-boss best splits ("time to <boss>"), with real names from the journal
    local bn    = (best and best.bossNames) or {}
    local order = store.bossOrder or {}
    local saved = store.bossNames or {}
    local count = store.bossCount or 0
    if count <= 0 then
        for i = 1, 12 do if store.bestSplits and store.bestSplits[i] then count = i end end
    end
    if count > 12 then count = 12 end
    for i = 1, 12 do
        local r = splitRows[i]
        if i <= count then
            local nm = saved[i] or order[i] or bn[i] or (L("Boss") .. " " .. i)
            local t  = store.bestSplits and store.bestSplits[i]
            r:Show()
            r.label:SetText(format("%d. %s", i, nm))
            r.val:SetText(t and FmtTime(t) or "--")
        else r:Hide() end
    end

    -- recent runs
    local runs = store.runs or {}
    for i = 1, 8 do
        local r = runRows[i]; local run = runs[i]
        if run then
            r:Show()
            r.label:SetText(date("%d.%m %H:%M", run.date or 0))
            r.val:SetText(FmtTime(run.total) .. "   |cffff8888" .. (run.deaths or 0) .. "|r")
        else r:Hide() end
    end
end
_G._OUIGT_RefreshStats = RefreshStats

local function BuildStats()
    if statsWin then return statsWin end
    local f = CreateFrame("Frame", "OUIGroupTimerStats", UIParent)
    f:SetSize(480, 540); f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH"); f:SetToplevel(true)
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true); f:Hide()

    local bg = f:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints()
    OldschoolUI.RegisterSkinBg(bg, 0.95); Border(f)

    local title = f:CreateFontString(nil, "OVERLAY")
    title:SetFont(Font(), 14, "OUTLINE"); title:SetPoint("TOP", 0, -8)
    local ar, ag, ab = Accent(); title:SetTextColor(ar, ag, ab)
    title:SetText(L("Group Timer") .. " - " .. L("Statistics"))

    local close = CreateFrame("Button", nil, f); close:SetSize(18, 18); close:SetPoint("TOPRIGHT", -4, -4)
    local cfs = close:CreateFontString(nil, "OVERLAY"); cfs:SetAllPoints(); cfs:SetFont(Font(), 15, "")
    cfs:SetText("x"); cfs:SetJustifyH("CENTER")
    close:SetScript("OnClick", function() f:Hide() end)

    -- category tabs
    f.tabs = {}
    local tw = 150
    for i, cat in ipairs(CATEGORIES) do
        local tab = CreateFrame("Button", nil, f); tab:SetSize(tw, 22)
        tab:SetPoint("TOPLEFT", 8 + (i - 1) * (tw + 4), -32)
        local tbg = tab:CreateTexture(nil, "BACKGROUND"); tbg:SetAllPoints(); tab.bg = tbg
        local tfs = tab:CreateFontString(nil, "OVERLAY"); tfs:SetAllPoints(); tfs:SetFont(Font(), 12, "")
        tfs:SetText(L(CAT_LABEL[cat])); tfs:SetJustifyH("CENTER")
        tab:SetScript("OnClick", function() statsCategory = cat; statsInst = nil; RefreshStats() end)
        f.tabs[cat] = tab
    end

    -- left instance list
    local listHdr = f:CreateFontString(nil, "OVERLAY"); listHdr:SetFont(Font(), 11, "")
    listHdr:SetPoint("TOPLEFT", 10, -62); listHdr:SetTextColor(ar, ag, ab); listHdr:SetText(L("Instances"))
    local listBody = CreateFrame("Frame", nil, f); listBody:SetPoint("TOPLEFT", 8, -78)
    listBody:SetSize(180, 440)
    for i = 1, 14 do
        local row = CreateFrame("Button", nil, listBody); row:SetSize(180, 20)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * 21)
        local rbg = row:CreateTexture(nil, "BACKGROUND"); rbg:SetAllPoints(); row.bg = rbg
        row.label = row:CreateFontString(nil, "OVERLAY"); row.label:SetFont(Font(), 11, "")
        row.label:SetPoint("LEFT", 4, 0); row.label:SetJustifyH("LEFT")
        row.val = row:CreateFontString(nil, "OVERLAY"); row.val:SetFont(Font(), 11, "")
        row.val:SetPoint("RIGHT", -4, 0); row.val:SetTextColor(0.8, 0.8, 0.85)
        row:SetScript("OnClick", function(self) statsInst = self._key; RefreshStats() end)
        instRows[i] = row
    end

    -- right detail
    local detail = CreateFrame("Frame", nil, f); detail:SetPoint("TOPLEFT", 198, -62)
    detail:SetPoint("BOTTOMRIGHT", -8, 8)
    f.detail = detail
    detail.head = detail:CreateFontString(nil, "OVERLAY"); detail.head:SetFont(Font(), 14, "OUTLINE")
    detail.head:SetPoint("TOPLEFT", 4, 0); detail.head:SetTextColor(ar, ag, ab)
    detail.summary = detail:CreateFontString(nil, "OVERLAY"); detail.summary:SetFont(Font(), 11, "")
    detail.summary:SetPoint("TOPLEFT", 4, -20); detail.summary:SetTextColor(0.85, 0.85, 0.9)

    local splitHdr = detail:CreateFontString(nil, "OVERLAY"); splitHdr:SetFont(Font(), 11, "")
    splitHdr:SetPoint("TOPLEFT", 4, -42); splitHdr:SetTextColor(ar, ag, ab); splitHdr:SetText(L("Best time to boss"))
    for i = 1, 12 do
        local r = CreateFrame("Frame", nil, detail); r:SetSize(260, 16)
        r:SetPoint("TOPLEFT", 4, -56 - (i - 1) * 17)
        r.label = r:CreateFontString(nil, "OVERLAY"); r.label:SetFont(Font(), 11, "")
        r.label:SetPoint("LEFT", 0, 0); r.label:SetJustifyH("LEFT")
        r.val = r:CreateFontString(nil, "OVERLAY"); r.val:SetFont(Font(), 11, "")
        r.val:SetPoint("RIGHT", 0, 0); r.val:SetTextColor(0.8, 0.85, 0.8)
        splitRows[i] = r
    end

    local runHdr = detail:CreateFontString(nil, "OVERLAY"); runHdr:SetFont(Font(), 11, "")
    runHdr:SetPoint("TOPLEFT", 4, -270); runHdr:SetTextColor(ar, ag, ab); runHdr:SetText(L("Recent runs"))
    for i = 1, 8 do
        local r = CreateFrame("Frame", nil, detail); r:SetSize(260, 16)
        r:SetPoint("TOPLEFT", 4, -284 - (i - 1) * 17)
        r.label = r:CreateFontString(nil, "OVERLAY"); r.label:SetFont(Font(), 11, "")
        r.label:SetPoint("LEFT", 0, 0); r.label:SetJustifyH("LEFT"); r.label:SetTextColor(0.8, 0.8, 0.85)
        r.val = r:CreateFontString(nil, "OVERLAY"); r.val:SetFont(Font(), 11, "")
        r.val:SetPoint("RIGHT", 0, 0)
        runRows[i] = r
    end

    statsWin = f
    return f
end

local function ToggleStats()
    local f = BuildStats()
    if f:IsShown() then f:Hide() else f:Show(); RefreshStats() end
end
_G._OUIGT_ToggleStats = ToggleStats

-------------------------------------------------------------------------------
--  MT-5  Minimap button (self-contained, no LibDBIcon dependency)
-------------------------------------------------------------------------------
local mmbtn

local function MM_Position()
    if not mmbtn then return end
    local p = Profile()
    local angle = math.rad((p and p.minimapAngle) or 200)
    local radius = 80
    mmbtn:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function MM_Tooltip()
    if not GameTooltip then return end
    GameTooltip:SetOwner(mmbtn, "ANCHOR_LEFT")
    local ar, ag, ab = Accent()
    GameTooltip:AddLine(L("Group Timer"), ar, ag, ab)
    local GR = _G._OUIGT_GroupRun
    if GR and GR.active then
        GameTooltip:AddLine(format("%s - %s", CAT_LABEL[GR.category] or "", GR.instName or "?"), 1, 1, 1)
        GameTooltip:AddDoubleLine(L("Time"), FmtTime(GetTime() - (GR.startTime or GetTime())), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine(L("Bosses"), tostring(#GR.bosses), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine(L("Deaths"), tostring(GR.deaths or 0), 1, 1, 1, 1, 0.6, 0.6)
    else
        GameTooltip:AddLine(L("No active run"), 0.7, 0.7, 0.7)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("|cff888888" .. L("Left-click: statistics") .. "|r")
    GameTooltip:Show()
end

local function BuildMinimapButton()
    if mmbtn or not Minimap then return end
    local p = Profile()
    if p and p.minimapHide then return end
    local b = CreateFrame("Button", "OUIGroupTimerMinimapButton", Minimap)
    b:SetSize(31, 31); b:SetFrameStrata("MEDIUM"); b:SetFrameLevel(8)
    b:RegisterForClicks("AnyUp"); b:RegisterForDrag("LeftButton")

    local overlay = b:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(53, 53); overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetPoint("TOPLEFT")

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(19, 19); icon:SetPoint("CENTER", 0, 1)
    icon:SetTexture("Interface\\Icons\\INV_Misc_PocketWatch_01")
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    b:SetScript("OnEnter", MM_Tooltip)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    b:SetScript("OnClick", function() ToggleStats() end)

    -- drag around the minimap edge
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            cx, cy = cx / scale, cy / scale
            local ang = math.deg(math.atan2(cy - my, cx - mx))
            local pr = Profile(); if pr then pr.minimapAngle = ang end
            MM_Position()
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

    mmbtn = b
    MM_Position()
end
_G._OUIGT_RebuildMinimapButton = function()
    local p = Profile()
    if mmbtn then mmbtn:SetShown(not (p and p.minimapHide)) end
    if not mmbtn then BuildMinimapButton() end
    MM_Position()
end

-------------------------------------------------------------------------------
--  Init: mover for the live overlay + minimap button + live ticker
-------------------------------------------------------------------------------
local init = CreateFrame("Frame")
init:RegisterEvent("PLAYER_LOGIN")
init:SetScript("OnEvent", function()
    local p = Profile()
    if not p or p.enabled == false then return end

    BuildLive()
    BuildMinimapButton()

    -- live-overlay mover
    if OUI.RegisterUnlockElements and OUI.MakeUnlockElement then
        local MK = OUI.MakeUnlockElement
        OUI:RegisterUnlockElements({
            MK({
                key = "OUIGroupTimerRun", label = "Group Timer (Run)", group = "Group Timer", order = 530,
                getFrame = function() return live end,
                getSize  = function() return live and live:GetWidth() or 220, live and live:GetHeight() or 120 end,
                isHidden = function() return false end,
                savePos  = function(_, _, _, x, y)
                    local pr = Profile()
                    if pr and x then pr.runPos = { x = x, y = y } end
                end,
                applyPos = function()
                    local pr = Profile(); local pos = pr and pr.runPos
                    if live and pos and pos.x then
                        live:ClearAllPoints(); live:SetPoint("CENTER", UIParent, "CENTER", pos.x, pos.y)
                    end
                end,
            }),
        })
    end

    -- live ticker (throttled ~5 fps); only does work while a run is active
    local acc = 0
    init:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 0.2 then return end
        acc = 0
        RefreshLive()
    end)
end)

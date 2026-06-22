-------------------------------------------------------------------------------
--  OUI_GroupTimer_Options.lua  --  Settings page for the Group Timer (MT-6)
-------------------------------------------------------------------------------

local OUI = OldschoolUI
if not (OUI and OUI.RegisterModule) then return end

local L = OUI.L or function(s) return s end
local W = OUI.Widgets

local function Header(page, text)
    local row = CreateFrame("Frame", nil, page); row:SetSize(280, 22)
    local fs = row:CreateFontString(nil, "OVERLAY")
    fs:SetFont((OUI.GetFontPath and OUI.GetFontPath()) or STANDARD_TEXT_FONT, 13, "")
    fs:SetPoint("LEFT", 2, 0); fs:SetText(L(text))
    if OUI.ACCENT then fs:SetTextColor(OUI.ACCENT.r, OUI.ACCENT.g, OUI.ACCENT.b) end
    return row
end
local function Note(page, text)
    local row = CreateFrame("Frame", nil, page); row:SetSize(280, 18)
    local fs = row:CreateFontString(nil, "OVERLAY")
    fs:SetFont((OUI.GetFontPath and OUI.GetFontPath()) or STANDARD_TEXT_FONT, 11, "")
    fs:SetPoint("LEFT", 2, 0); fs:SetWidth(360); fs:SetJustifyH("LEFT")
    fs:SetText(L(text)); fs:SetTextColor(0.6, 0.6, 0.6)
    return row
end

local function P() local db = _G._OUIGT_AceDB; return db and db.profile end
local function Apply() if _G._OUIGT_Apply then _G._OUIGT_Apply() end end

local function buildTimer(page)
    page:AddRow(W.Toggle(page, {
        label   = L("Enable Group Timer"),
        tooltip = L("Run timer for Challenge Mode, Heroic dungeons and raids: tracks per-boss splits, best times and deaths. (Toggling requires /reload.)"),
        get = function() local p = P(); return p and p.enabled ~= false end,
        set = function(v) local p = P(); if p then p.enabled = v end; Apply() end,
    }))
    page:AddRow(W.Slider(page, {
        label = L("Scale"), min = 0.5, max = 2.0, step = 0.05,
        get = function() local p = P(); return (p and p.scale) or 1 end,
        set = function(v) local p = P(); if p then p.scale = v end; Apply() end,
    }))
end

local function buildOverlay(page)
    page:AddRow(W.Toggle(page, {
        label   = L("Show run overlay"),
        tooltip = L("Show the live timer overlay during heroic/raid runs."),
        get = function() local p = P(); return p and p.showRunOverlay ~= false end,
        set = function(v) local p = P(); if p then p.showRunOverlay = v end end,
    }))
    page:AddRow(W.Toggle(page, {
        label = L("Show deaths"),
        get = function() local p = P(); return p and p.showDeaths ~= false end,
        set = function(v) local p = P(); if p then p.showDeaths = v end; Apply() end,
    }))
    page:AddRow(Note(page, "Move the run overlay with /ouimove."))
end

local function buildStats(page)
    page:AddRow(W.Slider(page, {
        label = L("History length"), min = 5, max = 50, step = 1,
        tooltip = L("How many recent runs to keep per instance."),
        get = function() local p = P(); return (p and p.statsHistory) or 20 end,
        set = function(v) local p = P(); if p then p.statsHistory = v end end,
    }))
    page:AddRow(W.Button(page, {
        label = L("Open statistics"), width = 160,
        onClick = function() if _G._OUIGT_ToggleStats then _G._OUIGT_ToggleStats() end end,
    }))
    page:AddRow(W.Button(page, {
        label = L("Clear statistics"), width = 160,
        onClick = function()
            if OUI.ShowConfirmPopup then
                OUI:ShowConfirmPopup({
                    title = L("Clear statistics"),
                    message = L("Delete all stored runs, best times and suspended raids?"),
                    confirmText = L("Clear"), cancelText = L("Cancel"),
                    onConfirm = function()
                        local p = P(); if p then p.stats = {}; p.suspended = {} end
                        if _G._OUIGT_RefreshStats then _G._OUIGT_RefreshStats() end
                    end,
                })
            end
        end,
    }))
end

local function buildChallenge(page)
    page:AddRow(W.Dropdown(page, {
        label   = L("Compare splits against"),
        tooltip = L("Compare each objective time against your stored best."),
        values  = { { value = "NONE", text = L("Off") }, { value = "DUNGEON", text = L("Best per dungeon") } },
        get = function() local p = P(); return (p and p.objectiveCompareMode) or "NONE" end,
        set = function(v) local p = P(); if p then p.objectiveCompareMode = v end; Apply() end,
    }))
    page:AddRow(W.Toggle(page, {
        label = L("Show Gold medal timer"),
        get = function() local p = P(); return p and p.showPlusThreeTimer ~= false end,
        set = function(v) local p = P(); if p then p.showPlusThreeTimer = v end; Apply() end,
    }))
    page:AddRow(W.Toggle(page, {
        label = L("Show Silver medal timer"),
        get = function() local p = P(); return p and p.showPlusTwoTimer ~= false end,
        set = function(v) local p = P(); if p then p.showPlusTwoTimer = v end; Apply() end,
    }))
    page:AddRow(W.ColorSwatch(page, {
        label = L("Gold threshold colour"),
        get = function() local p = P(); local c = (p and p.timerPlusThreeColor) or {}; return c.r or 0.2, c.g or 0.9, c.b or 0.2 end,
        set = function(r, g, b) local p = P(); if p then p.timerPlusThreeColor = { r = r, g = g, b = b } end; Apply() end,
    }))
    page:AddRow(W.ColorSwatch(page, {
        label = L("Silver threshold colour"),
        get = function() local p = P(); local c = (p and p.timerPlusTwoColor) or {}; return c.r or 0.9, c.g or 0.9, c.b or 0.3 end,
        set = function(r, g, b) local p = P(); if p then p.timerPlusTwoColor = { r = r, g = g, b = b } end; Apply() end,
    }))
    page:AddRow(W.Toggle(page, {
        label = L("Show deaths in title"),
        get = function() local p = P(); return p and p.deathsInTitle == true end,
        set = function(v) local p = P(); if p then p.deathsInTitle = v end; Apply() end,
    }))
    page:AddRow(Header(page, "Minimap"))
    page:AddRow(W.Toggle(page, {
        label   = L("Show minimap button"),
        get = function() local p = P(); return not (p and p.minimapHide) end,
        set = function(v)
            local p = P(); if p then p.minimapHide = not v end
            if _G._OUIGT_RebuildMinimapButton then _G._OUIGT_RebuildMinimapButton() end
        end,
    }))
end

OUI:RegisterModule("OUI_GroupTimer", {
    title = L("Group Timer"),
    tabs = {
        { title = "Timer",            build = buildTimer },
        { title = "Live run overlay", build = buildOverlay },
        { title = "Statistics",       build = buildStats },
        { title = "Challenge Mode",   build = buildChallenge },
    },
})

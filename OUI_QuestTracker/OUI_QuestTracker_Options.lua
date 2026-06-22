-------------------------------------------------------------------------------
--  OUI_QuestTracker_Options.lua  --  Settings page (QT-4)
-------------------------------------------------------------------------------

local ADDON, ns = ...
local OUI = OldschoolUI
if not (OUI and OUI.RegisterModule) then return end
local QT = ns.QT

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

local function P() return _G._OUIQT_DB end
local function Refresh() if _G._OUIQT_RefreshAll then _G._OUIQT_RefreshAll() end end

-- a row that captures the next key press as the quest-item hotkey
local function KeyCaptureRow(page)
    local row = CreateFrame("Frame", nil, page); row:SetSize(280, 26)
    local label = row:CreateFontString(nil, "OVERLAY")
    label:SetFont((OUI.GetFontPath and OUI.GetFontPath()) or STANDARD_TEXT_FONT, 12, "")
    label:SetPoint("LEFT", 2, 0); label:SetText(L("Quest-item key"))

    local btn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    btn:SetSize(150, 22); btn:SetPoint("LEFT", 150, 0)

    local function Label()
        local p = P()
        local k = p and p.questItemKey
        return (k and k ~= "") and k or L("Not set")
    end
    btn:SetText(Label())

    local capturing = false
    local function stop()
        capturing = false
        btn:EnableKeyboard(false)
        btn:SetText(Label())
    end
    btn:SetScript("OnClick", function(self)
        capturing = true
        self:EnableKeyboard(true)
        self:SetText(L("Press a key..."))
    end)
    btn:SetScript("OnKeyDown", function(self, key)
        if not capturing then return end
        if key == "ESCAPE" then
            local p = P(); if p then p.questItemKey = "" end
            stop()
        elseif key ~= "LSHIFT" and key ~= "RSHIFT" and key ~= "LCTRL"
           and key ~= "RCTRL" and key ~= "LALT" and key ~= "RALT" then
            local mod = ""
            if IsAltKeyDown()     then mod = "ALT-"   .. mod end
            if IsControlKeyDown() then mod = "CTRL-"  .. mod end
            if IsShiftKeyDown()   then mod = "SHIFT-" .. mod end
            local p = P(); if p then p.questItemKey = mod .. key end
            stop()
            if QT and QT.ApplyQuestItemBinding then QT.ApplyQuestItemBinding() end
            if QT and QT.RefreshQuestItem    then QT.RefreshQuestItem()    end
        end
    end)
    row._refresh = function() btn:SetText(Label()) end
    return row
end

local function buildGeneral(page)
    page:AddRow(W.Toggle(page, {
        label   = L("Enable Quest Tracker"),
        tooltip = L("Skinning, visibility control and quest QoL for the objective tracker."),
        get = function() local p = P(); return p and p.enabled ~= false end,
        set = function(v) local p = P(); if p then p.enabled = v end; Refresh() end,
    }))
    page:AddRow(W.Dropdown(page, {
        label  = L("Visibility"),
        values = {
            { value = "always",    text = L("Always") },
            { value = "combat",    text = L("In combat only") },
            { value = "mouseover", text = L("On mouseover") },
            { value = "instance",  text = L("In instances only") },
            { value = "never",     text = L("Hidden") },
        },
        get = function() local p = P(); return (p and p.visibility) or "always" end,
        set = function(v) local p = P(); if p then p.visibility = v end; Refresh() end,
    }))
    page:AddRow(W.Toggle(page, {
        label   = L("Hide in raid / arena"),
        get = function() local p = P(); return p and p.hideInRaid ~= false end,
        set = function(v) local p = P(); if p then p.hideInRaid = v end; Refresh() end,
    }))
end

local function buildAppearance(page)
    page:AddRow(W.Toggle(page, {
        label = L("Colour quest titles"),
        get = function() local p = P(); return p and p.skinHeaders ~= false end,
        set = function(v) local p = P(); if p then p.skinHeaders = v end; Refresh() end,
    }))
    page:AddRow(W.Toggle(page, {
        label   = L("Use suite accent for titles"),
        tooltip = L("Tie quest-title colour to the global accent colour."),
        get = function() local p = P(); return p and p.accentHeaders ~= false end,
        set = function(v) local p = P(); if p then p.accentHeaders = v end; Refresh() end,
    }))
    page:AddRow(W.ColorSwatch(page, {
        label = L("Title colour"),
        get = function() local p = P(); local c = (p and p.titleColor) or {}; return c.r or 0.85, c.g or 0.64, c.b or 0.25 end,
        set = function(r, g, b) local p = P(); if p then p.titleColor = { r = r, g = g, b = b } end; Refresh() end,
    }))
    page:AddRow(W.Slider(page, {
        label = L("Title font size"), min = 8, max = 20, step = 1,
        get = function() local p = P(); return (p and p.titleFontSize) or 12 end,
        set = function(v) local p = P(); if p then p.titleFontSize = v end; Refresh() end,
    }))
    page:AddRow(W.Slider(page, {
        label = L("Objective font size"), min = 8, max = 18, step = 1,
        get = function() local p = P(); return (p and p.objectiveFontSize) or 10 end,
        set = function(v) local p = P(); if p then p.objectiveFontSize = v end; Refresh() end,
    }))
    page:AddRow(Header(page, "Backdrop"))
    page:AddRow(W.Toggle(page, {
        label = L("Show backdrop"),
        get = function() local p = P(); return p and p.showBackdrop ~= false end,
        set = function(v) local p = P(); if p then p.showBackdrop = v end; Refresh() end,
    }))
    page:AddRow(W.ColorSwatch(page, {
        label = L("Backdrop colour"), hasAlpha = true,
        get = function() local p = P(); local c = (p and p.backdrop) or {}; return c.r or 0.035, c.g or 0.035, c.b or 0.035, c.a or 0.75 end,
        set = function(r, g, b, a) local p = P(); if p then p.backdrop = { r = r, g = g, b = b, a = a or 0.75 } end; Refresh() end,
    }))
    page:AddRow(W.Toggle(page, {
        label = L("Show top divider"),
        get = function() local p = P(); return p and p.showTopLine ~= false end,
        set = function(v) local p = P(); if p then p.showTopLine = v end; Refresh() end,
    }))
end

local function buildQoL(page)
    page:AddRow(W.Toggle(page, {
        label   = L("Auto-accept quests"),
        get = function() local p = P(); return p and p.autoAccept == true end,
        set = function(v) local p = P(); if p then p.autoAccept = v end end,
    }))
    page:AddRow(W.Toggle(page, {
        label   = L("Auto-turn-in quests"),
        tooltip = L("Auto-claims quests with a single reward; multi-reward quests are left to you."),
        get = function() local p = P(); return p and p.autoTurnIn == true end,
        set = function(v) local p = P(); if p then p.autoTurnIn = v end end,
    }))
    page:AddRow(W.Toggle(page, {
        label   = L("Hold Shift to skip auto-turn-in"),
        get = function() local p = P(); return p and p.autoTurnInShiftSkip ~= false end,
        set = function(v) local p = P(); if p then p.autoTurnInShiftSkip = v end end,
    }))
    page:AddRow(W.Toggle(page, {
        label   = L("Quest-item hotkey"),
        tooltip = L("Bind a key to use your current quest item."),
        get = function() local p = P(); return p and p.questItemHotkey == true end,
        set = function(v)
            local p = P(); if p then p.questItemHotkey = v end
            if QT and QT.ApplyQuestItemBinding then QT.ApplyQuestItemBinding() end
            if QT and QT.RefreshQuestItem    then QT.RefreshQuestItem()    end
        end,
    }))
    page:AddRow(KeyCaptureRow(page))
    page:AddRow(Note(page, "Set a key, then use the watched quest item with it (out of combat binding)."))
end

OUI:RegisterModule("OUI_QuestTracker", {
    title = L("Quest Tracker"),
    tabs = {
        { title = "General",         build = buildGeneral },
        { title = "Appearance",      build = buildAppearance },
        { title = "Quality of life", build = buildQoL },
    },
})

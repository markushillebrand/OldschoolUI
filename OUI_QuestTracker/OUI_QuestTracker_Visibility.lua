-------------------------------------------------------------------------------
--  OUI_QuestTracker_Visibility.lua  --  Visibility + themed backdrop
--
--  Drives WatchFrame visibility (always / combat / mouseover / instance / never)
--  composed with cross-module suppression and a hard raid/arena auto-hide, and
--  renders a themed backdrop sized to the tracker's real content.
--
--  Taint-safe: visibility is alpha-only (no Show/Hide on the possibly-protected
--  WatchFrame in combat); the backdrop is our own UIParent-parented frame
--  anchored to the tracker bounds, never a child. Hooks are HookScript /
--  hooksecurefunc only.
-------------------------------------------------------------------------------

local ADDON, ns = ...
local OUI = OldschoolUI
local QT = ns.QT
if not QT then return end

local After = (C_Timer and C_Timer.After) or function(_, f) if f then f() end end

local bg                      -- our backdrop frame
local hovering = false

local function Tracker() return _G.WatchFrame end

-------------------------------------------------------------------------------
--  Mode evaluation
-------------------------------------------------------------------------------
local function InInstance()
    local _, itype = GetInstanceInfo()
    return itype and itype ~= "none"
end

-- hard auto-hide: raid/arena (when hideInRaid is on)
local function HardHide()
    if QT.Cfg("hideInRaid") == false then return false end
    local _, itype = GetInstanceInfo()
    return itype == "raid" or itype == "arena"
end

-- target alpha for the active mode (mouseover resolved against `hovering`)
local function EvalAlpha()
    local mode = QT.Cfg("visibility") or "always"
    if mode == "never"     then return 0 end
    if mode == "combat"    then return (InCombatLockdown and InCombatLockdown()) and 1 or 0 end
    if mode == "instance"  then return InInstance() and 1 or 0 end
    if mode == "mouseover" then return hovering and 1 or 0 end
    return 1  -- always
end

-------------------------------------------------------------------------------
--  Backdrop frame (own frame anchored to the tracker bounds)
-------------------------------------------------------------------------------
local function EnsureBG()
    if bg then return bg end
    local wf = Tracker(); if not wf then return nil end
    bg = CreateFrame("Frame", "OUIQuestTrackerBG", UIParent)
    bg:SetFrameStrata(wf:GetFrameStrata() or "LOW")
    bg:SetFrameLevel(math.max(0, (wf:GetFrameLevel() or 1) - 1))
    bg:SetPoint("TOPLEFT",  wf, "TOPLEFT",  -6, -30)
    bg:SetPoint("TOPRIGHT", wf, "TOPRIGHT", 11, -30)
    bg:SetHeight(1)

    bg._tex = bg:CreateTexture(nil, "BACKGROUND")
    bg._tex:SetAllPoints()

    bg._line = bg:CreateTexture(nil, "OVERLAY")
    bg._line:SetPoint("TOPLEFT",  bg, "TOPLEFT",  0, 0)
    bg._line:SetPoint("TOPRIGHT", bg, "TOPRIGHT", 0, 0)
    bg._line:SetHeight(1)
    return bg
end

-------------------------------------------------------------------------------
--  Content measurement: the real quest lines aren't reliably reachable by name
--  on this client, so we walk the WatchFrame tree and find the lowest *visible*
--  FontString that actually carries text. Robust regardless of line nesting.
-------------------------------------------------------------------------------
local function ScanLowest(frame, low)
    if frame.GetRegions then
        for _, r in ipairs({ frame:GetRegions() }) do
            if r.GetText and r.IsShown and r:IsShown() then
                local t = r:GetText()
                if t and t ~= "" and r.GetBottom then
                    local b = r:GetBottom()
                    if b and (not low or b < low) then low = b end
                end
            end
        end
    end
    if frame.GetChildren then
        for _, c in ipairs({ frame:GetChildren() }) do
            if c.IsShown and c:IsShown() then low = ScanLowest(c, low) end
        end
    end
    return low
end

local function ResizeBG()
    local wf = Tracker()
    if not bg or not wf then return end
    if QT.Cfg("showBackdrop") == false then bg:Hide(); return end
    -- hide chrome during an active Challenge Mode (scenario blocks, not quests)
    if C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive and C_ChallengeMode.IsChallengeModeActive() then
        bg:Hide(); return
    end
    -- collapsed: keep a compact header bar so the tracker stays visible/clickable
    if QT._collapsed then
        bg:ClearAllPoints()
        bg:SetPoint("TOPLEFT",  wf, "TOPLEFT",  -6, 4)
        bg:SetPoint("TOPRIGHT", wf, "TOPRIGHT", 11, 4)
        bg:SetHeight(26)
        bg:Show()
        return
    end
    -- expanded: size to the real quest content
    local low = ScanLowest(wf, nil)
    if not low then bg:Hide(); return end
    local top = wf:GetTop()
    if not top then return end
    local h = (top - 30) - low + 15
    if h < 1 then h = 1 end
    bg:ClearAllPoints()
    bg:SetPoint("TOPLEFT",  wf, "TOPLEFT",  -6, -30)
    bg:SetPoint("TOPRIGHT", wf, "TOPRIGHT", 11, -30)
    bg:SetHeight(h)
    bg:Show()
end
QT.ResizeBGToContent = ResizeBG

local _resizePending = false
local function QueueResize()
    if _resizePending then return end
    _resizePending = true
    After(0.05, function() _resizePending = false; ResizeBG() end)
end

-------------------------------------------------------------------------------
--  Theme application (colour + top divider)
-------------------------------------------------------------------------------
function QT.ApplyBackdrop()
    local b = EnsureBG(); if not b then return end
    local c = QT.Cfg("backdrop") or {}
    b._tex:SetColorTexture(c.r or 0.035, c.g or 0.035, c.b or 0.035, c.a or 0.75)
    if QT.Cfg("showTopLine") == false then
        b._line:Hide()
    else
        local r, g, bb = QT.TitleColor()
        b._line:SetColorTexture(r, g, bb, 1)
        b._line:Show()
    end
    ResizeBG()
end

-------------------------------------------------------------------------------
--  Visibility (alpha-only, taint-free)
-------------------------------------------------------------------------------
local function UpdateVisibility()
    local wf = Tracker(); if not wf then return end
    EnsureBG()
    local a
    if HardHide() or QT.IsSuppressed() or QT.Cfg("enabled") == false then
        a = 0
    else
        a = EvalAlpha()
    end
    wf:SetAlpha(a)
    if bg then bg:SetAlpha(a) end
    if a > 0 then QueueResize() elseif bg then bg:Hide() end
end
QT.UpdateVisibility = UpdateVisibility

-------------------------------------------------------------------------------
--  Init
-------------------------------------------------------------------------------
local installed = false
function QT.InitVisibility()
    local wf = Tracker(); if not wf then return end
    EnsureBG()
    -- seed collapsed state from Blizzard's flag (tracker may start collapsed)
    if _G.WATCHFRAME_EXPANDED ~= nil then
        QT._collapsed = (_G.WATCHFRAME_EXPANDED == false)
    end
    QT.ApplyBackdrop()

    if not installed then
        installed = true
        -- track collapse / expand so the backdrop becomes a compact header bar
        if type(_G.WatchFrame_Collapse) == "function" then
            hooksecurefunc("WatchFrame_Collapse", function() QT._collapsed = true;  QueueResize() end)
        end
        if type(_G.WatchFrame_Expand) == "function" then
            hooksecurefunc("WatchFrame_Expand", function() QT._collapsed = false; QueueResize() end)
        end

        -- re-resize / re-hide BG as the tracker shows/hides
        wf:HookScript("OnShow", function() QueueResize() end)
        wf:HookScript("OnHide", function() if bg then bg:Hide() end end)

        local driver = CreateFrame("Frame")
        driver:RegisterEvent("PLAYER_ENTERING_WORLD")
        driver:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        driver:RegisterEvent("PLAYER_REGEN_DISABLED")
        driver:RegisterEvent("PLAYER_REGEN_ENABLED")
        driver:RegisterEvent("QUEST_LOG_UPDATE")
        driver:RegisterEvent("QUEST_WATCH_UPDATE")
        driver:SetScript("OnEvent", function(_, ev)
            if ev == "QUEST_LOG_UPDATE" or ev == "QUEST_WATCH_UPDATE" then
                QueueResize()
            else
                UpdateVisibility()
            end
        end)

        -- mouseover poll (only does work in mouseover mode)
        local acc = 0
        driver:SetScript("OnUpdate", function(_, dt)
            if QT.Cfg("visibility") ~= "mouseover" then return end
            acc = acc + dt; if acc < 0.1 then return end; acc = 0
            local over = (wf:IsMouseOver()) or (bg and bg:IsShown() and bg:IsMouseOver())
            if over ~= hovering then hovering = over; UpdateVisibility() end
        end)
    end

    UpdateVisibility()
end

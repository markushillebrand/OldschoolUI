-- ===========================================================================
--  OldschoolUI -- Blizzard Skin: Quest Log (WorldMap)
--  In MoP the quest log lives inside WorldMapFrame as QuestMapFrame (quest list +
--  details). The map itself (WorldMapFrame.ScrollContainer) must stay untouched --
--  darkening it would make it unusable -- so this skinner only touches the quest
--  panel (DetailsFrame / insets / QuestScrollFrame), the window border chrome, and
--  the dropdowns/search, leaving the map intact. Frame names verified via dumps.
-- ===========================================================================
local _, ns = ...
local OUI = OldschoolUI
if not OUI then return end
local BS = ns.BS
if not BS then return end

local function ac() return OUI.ACCENT.r, OUI.ACCENT.g, OUI.ACCENT.b end
local function framesEnabled() return BS.db and BS.db.profile and BS.db.profile.reskinFrames end

local built = false

-- dim parchment: any BACKGROUND texture, plus ARTWORK/BORDER "material/parchment"
-- textures by name (the quest-detail parchment is a faction Material atlas in
-- ARTWORK, which a layer-only pass misses). Never recurse into the map.
local function isParchName(nm)
    return nm and (nm:find("Material") or nm:find("Parch") or nm:find("Seal")
        or nm:find("Bg") or nm:find("Background") or nm:find("Stone"))
end
local function dimParchment(frame, depth)
    if not frame or (depth or 0) < 0 then return end
    local map = _G.WorldMapFrame and _G.WorldMapFrame.ScrollContainer
    if frame == map then return end
    if frame.GetRegions then
        for i = 1, select("#", frame:GetRegions()) do
            local r = select(i, frame:GetRegions())
            if r and r.IsObjectType and r:IsObjectType("Texture") and r.SetColorTexture then
                local layer = r.GetDrawLayer and select(1, r:GetDrawLayer())
                local nm = r.GetName and r:GetName()
                if layer == "BACKGROUND" or isParchName(nm) then
                    local br, bg, bb = OUI.GetSkinBg()
                    r:SetColorTexture(br, bg, bb, 0.96)
                end
            end
        end
    end
    if frame.GetChildren and (depth or 0) > 0 then
        for i = 1, select("#", frame:GetChildren()) do
            dimParchment(select(i, frame:GetChildren()), (depth or 0) - 1)
        end
    end
end

-- strip the decorative window ornaments (gold corners/edges in BorderFrame). It's
-- pure chrome -- the close/zoom buttons live on WorldMapFrame, not here.
local function stripOrnaments(frame, depth)
    if not frame or (depth or 0) < 0 then return end
    if frame.GetRegions then
        for i = 1, select("#", frame:GetRegions()) do
            local r = select(i, frame:GetRegions())
            if r and r.IsObjectType and r:IsObjectType("Texture") and r.SetAlpha then
                r:SetAlpha(0)
            end
        end
    end
    if frame.GetChildren and (depth or 0) > 0 then
        for i = 1, select("#", frame:GetChildren()) do
            stripOrnaments(select(i, frame:GetChildren()), (depth or 0) - 1)
        end
    end
end

local function skinQuestLog()
    if not framesEnabled() then return end
    local qm = _G.QuestMapFrame
    if not qm then return end

    if not built then
        built = true
        -- quest panel container + its insets -> dark (NOT the map)
        BS:DarkPanel(qm, 0.95)
        for _, k in ipairs({ "DetailsFrame", "LeftInset", "RightInset" }) do
            if qm[k] then BS:DarkPanel(qm[k], 0.92) end
        end
        if _G.QuestScrollFrame then BS:DarkPanel(_G.QuestScrollFrame, 0.92) end

        -- window border chrome around the map: strip the ornate gold corners/edges
        -- (pure decoration) and add a clean OUI border. The map stays untouched.
        local wmf = _G.WorldMapFrame
        if wmf and wmf.BorderFrame then
            stripOrnaments(wmf.BorderFrame, 3)
        end
        if wmf and OUI.PP and OUI.PP.CreateBorder then
            OUI.PP.CreateBorder(wmf, OUI.ACCENT.r, OUI.ACCENT.g, OUI.ACCENT.b, 0.5)
        end

        -- accent the quest-log title if present
        if _G.QuestLogTitleText and _G.QuestLogTitleText.SetTextColor then
            _G.QuestLogTitleText:SetTextColor(ac())
        end
    end

    -- re-applied each show / update: readable text + dark parchment + section bgs
    if ns.SkinFrameText then ns.SkinFrameText(qm, 12) end
    dimParchment(qm, 14)
    if ns.DarkenFrameBGs then ns.DarkenFrameBGs(qm, 12) end
end
ns.SkinQuestLog = skinQuestLog

-- The CLASSIC quest log is a SEPARATE window: QuestLogFrame (NOT the map's
-- QuestMapFrame). Own bg/parchment textures (QuestLogFrameBg/PageBg/InsetBg),
-- NineSlice chrome and a detail scroll. Skin it like our other std frames.
local QL_NATIVE_BGS = {
    "QuestLogFrameBg", "QuestLogFrameBookBg", "QuestLogFramePageBg", "QuestLogFrameInsetBg",
}
local function skinClassicQuestLog()
    if not framesEnabled() then return end
    local f = _G.QuestLogFrame
    if not f then return end
    -- HIDE the native parchment pieces every pass (Blizzard re-shows them on update).
    -- Their textures extend FAR past the frame (fstack: PageBg/BookBg bleed beyond the
    -- window), so solid-colouring them paints offset rectangles -> hide, don't recolour.
    for _, n in ipairs(QL_NATIVE_BGS) do
        local t = _G[n]
        if t and t.SetAlpha then t:SetAlpha(0) end
    end
    if not f._ouiPanel then
        f._ouiPanel = true
        if f.NineSlice then stripOrnaments(f.NineSlice, 1) end
        if _G.QuestLogFrameInset and _G.QuestLogFrameInset.NineSlice then
            stripOrnaments(_G.QuestLogFrameInset.NineSlice, 1)
        end
        BS:DarkPanel(f, 0.95)   -- ONE clean bg sized to the window
        if OUI.PP and OUI.PP.CreateBorder then
            OUI.PP.CreateBorder(f, OUI.ACCENT.r, OUI.ACCENT.g, OUI.ACCENT.b, 0.5)
        end
        if BS.MakeMovable then BS:MakeMovable(f, "questlog") end
    end
    -- NB: do NOT run DarkenFrameBGs here -- it would recolour PageBg/BookBg back on.
    if ns.SkinFrameText then ns.SkinFrameText(f, 8) end
end
ns.SkinClassicQuestLog = skinClassicQuestLog

-- Default the map to WINDOWED (panel) mode instead of fullscreen, like ElvUI. The
-- modern MoP map exposes Minimize()/MaximizeMinimizeFrame; do it once, guarded and
-- out of combat, and never fight the user if they maximise again.
-- Default the map to WINDOWED, ElvUI-style. Per the real WorldMapMixin source,
-- Minimize() does SetSize(minimizedWidth/Height)+UpdateUIPanelPositions+Synchronize.
-- It must run AFTER the map's own OnShow (which calls MaximizeUIPanel when maximized)
-- -> defer via C_Timer.After(0), out of combat, every open.
local function goWindowed()
    local wmf = _G.WorldMapFrame
    if not wmf then return end
    if InCombatLockdown and InCombatLockdown() then return end
    local maxed = (wmf.IsMaximized and wmf:IsMaximized()) or (wmf.isMaximized == true)
    if not maxed then return end
    if wmf.Minimize then
        pcall(function() wmf:Minimize() end)
    elseif wmf.BorderFrame and wmf.BorderFrame.MaximizeMinimizeFrame
        and wmf.BorderFrame.MaximizeMinimizeFrame.MinimizeButton then
        pcall(function() wmf.BorderFrame.MaximizeMinimizeFrame.MinimizeButton:Click() end)
    end
end
ns.WorldMapWindowed = goWindowed

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("ADDON_LOADED")          -- WorldMap may be LoD
loader:SetScript("OnEvent", function()
    -- classic quest log window (separate frame, opened via quest-log keybind)
    if _G.QuestLogFrame and not _G.QuestLogFrame._ouiHook then
        _G.QuestLogFrame._ouiHook = true
        _G.QuestLogFrame:HookScript("OnShow", skinClassicQuestLog)
        skinClassicQuestLog()
        if _G.QuestLog_Update and not ns._clUpdateHook then
            ns._clUpdateHook = true
            hooksecurefunc("QuestLog_Update", function()
                if framesEnabled() then C_Timer.After(0, skinClassicQuestLog) end
            end)
        end
        if _G.QuestLog_SetSelection and not ns._clSelHook then
            ns._clSelHook = true
            hooksecurefunc("QuestLog_SetSelection", function()
                if framesEnabled() then C_Timer.After(0, skinClassicQuestLog) end
            end)
        end
    end
    if not _G.QuestMapFrame then return end
    skinQuestLog()
    if C_Timer then C_Timer.After(0, goWindowed) end
    local wmf = _G.WorldMapFrame
    if wmf and not wmf._ouiWinHook then
        wmf._ouiWinHook = true
        wmf:HookScript("OnShow", function()
            if C_Timer then C_Timer.After(0, goWindowed) end
            skinQuestLog()
        end)
    end
    local qm = _G.QuestMapFrame
    if not qm._ouiHook then
        qm._ouiHook = true
        qm:HookScript("OnShow", skinQuestLog)
    end
    -- quest details rebuild on quest selection -> re-skin text/bgs
    if _G.QuestMapFrame_ShowQuestDetails and not ns._qlDetailHook then
        ns._qlDetailHook = true
        hooksecurefunc("QuestMapFrame_ShowQuestDetails", function()
            if framesEnabled() then C_Timer.After(0, skinQuestLog) end
        end)
    end
    if _G.QuestMapFrame_UpdateAll and not ns._qlUpdateHook then
        ns._qlUpdateHook = true
        hooksecurefunc("QuestMapFrame_UpdateAll", function()
            if framesEnabled() then C_Timer.After(0, skinQuestLog) end
        end)
    end
end)

-- ===========================================================================
--  OldschoolUI -- Chat  CH-1: core skinning
--  Themes the default chat frames (background, border, suite font + outline +
--  shadow), the tabs (flat look, accent on the selected tab), the edit box and
--  the dock manager. Clean-room rewrite of the original dev chat module.
-- ===========================================================================
local ADDON, ns = ...
local OUI = OldschoolUI
if not OUI then return end

local CH = LibStub("AceAddon-3.0"):NewAddon("OldschoolUIChat", "AceEvent-3.0")
ns.CH = CH

local defaults = {
    profile = {
        enabled = true,
        showBackground = true,
        bgColor = { r = 0.05, g = 0.05, b = 0.05, a = 0.55 },
        showBorder = true,
        borderColor = { r = 0.067, g = 0.067, b = 0.067 },
        useSuiteOutline = true,
        outline = "",                  -- "", "OUTLINE", "THICKOUTLINE"
        shadow = true,
        useGlobalFontSize = false,
        fontSize = 13,
        styleTabs = true,
        styleEditBox = true,
        editBoxPosition = "BOTTOM",     -- BOTTOM / TOP
        hideDefaultButtons = true,      -- hide Blizzard's chat menu/channel/voice buttons
        -- idle fade (CH-2)
        idleFadeEnabled = true,
        idleFadeDelay = 15,             -- seconds of inactivity before fading
        idleFadeStrength = 40,          -- 0-99; idle alpha = 1 - strength/100
        fadeStayInCombat = true,        -- stay fully visible while in combat
        -- text utilities (CH-3)
        showCopyButton = true,
        clickableURLs = true,
        -- persist history (CH-4)
        persistChatHistory = true,
        persistChatHistoryMaxLines = 100,
        -- sidebar (CH-4b)
        sidebarEnabled = true,
        sidebarVisibility = "mouseover",   -- always / mouseover / never
        sidebarSide = "LEFT",              -- LEFT / RIGHT
        sidebarIconSize = 20,
        sidebarSpacing = 6,
        sidebarBg = true,
        sidebarShowCopy = true,
        sidebarShowFriends = true,
        sidebarShowGuild = true,
        sidebarShowCalendar = true,
        sidebarShowLFD = true,
    },
}

local function cfg(k) return ns.db and ns.db.profile[k] end
ns.cfg = cfg

-- ---------------------------------------------------------------------------
--  Font / outline resolution (suite-driven by default)
-- ---------------------------------------------------------------------------
local function fontPath() return (OUI.GetFontPath and OUI.GetFontPath()) or STANDARD_TEXT_FONT end
local function outlineFlag()
    if cfg("useSuiteOutline") and OUI.GetFontOutlineFlag then return OUI.GetFontOutlineFlag() or "" end
    return cfg("outline") or ""
end

-- ---------------------------------------------------------------------------
--  Frame enumeration
-- ---------------------------------------------------------------------------
local function eachChatFrame(fn)
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local cf = _G["ChatFrame" .. i]
        if cf then fn(cf) end
    end
end
ns.eachChatFrame = eachChatFrame

-- ---------------------------------------------------------------------------
--  A themed backdrop drawn behind a frame (sibling, lower frame level so it
--  never sits over the frame's own text).
-- ---------------------------------------------------------------------------
local function ensureBackdrop(frame, pad)
    if frame._ouiBackdrop then return frame._ouiBackdrop end
    local bd = CreateFrame("Frame", nil, frame:GetParent() or UIParent)
    bd:SetFrameStrata(frame:GetFrameStrata())
    bd:SetFrameLevel(math.max(frame:GetFrameLevel() - 1, 0))
    bd.bg = bd:CreateTexture(nil, "BACKGROUND")
    bd.bg:SetAllPoints()
    if OUI.PP and OUI.PP.CreateBorder then OUI.PP.CreateBorder(bd, 0.067, 0.067, 0.067, 1) end
    bd:ClearAllPoints()
    bd:SetPoint("TOPLEFT", frame, "TOPLEFT", -pad, pad)
    bd:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", pad, -pad)
    frame._ouiBackdrop = bd
    return bd
end

local function styleBackdrop(bd, alphaBoost)
    local c = cfg("bgColor")
    bd.bg:SetColorTexture(c.r, c.g, c.b, math.min((c.a or 0.5) + (alphaBoost or 0), 1))
    if OUI.PP and OUI.PP.SetBorderColor then
        local b = cfg("borderColor")
        OUI.PP.SetBorderColor(bd, b.r, b.g, b.b, cfg("showBorder") and 1 or 0)
    end
end

-- ---------------------------------------------------------------------------
--  Chat frame
-- ---------------------------------------------------------------------------
local function SkinChatFrame(cf)
    -- font (keep the per-frame size unless a global size is forced)
    local _, sz = cf:GetFont()
    if not sz or sz < 1 then sz = 13 end
    if cfg("useGlobalFontSize") then sz = cfg("fontSize") or 13 end
    pcall(cf.SetFont, cf, fontPath(), sz, outlineFlag())
    if cfg("shadow") then
        cf:SetShadowColor(0, 0, 0, 1); cf:SetShadowOffset(1, -1)
    else
        cf:SetShadowColor(0, 0, 0, 0)
    end

    -- hide Blizzard's own background art, draw our own
    if cf.Background then cf.Background:SetAlpha(0) end
    local bd = ensureBackdrop(cf, 4)
    styleBackdrop(bd)
    -- only show the backdrop while the chat frame itself is visible, so hidden
    -- or undocked-but-empty frames don't leave black boxes behind.
    local function vis() return cf:IsShown() and cfg("showBackground") ~= false end
    bd:SetShown(vis())
    if not cf._ouiVisHook then
        cf._ouiVisHook = true
        cf:HookScript("OnShow", function() if cf._ouiBackdrop then cf._ouiBackdrop:SetShown(cfg("showBackground") ~= false) end end)
        cf:HookScript("OnHide", function() if cf._ouiBackdrop then cf._ouiBackdrop:Hide() end end)
    end

    cf._ouiSkinned = true
end

-- ---------------------------------------------------------------------------
--  Tab
-- ---------------------------------------------------------------------------
local function tabText(tab)
    return tab.Text or _G[(tab:GetName() or "") .. "Text"]
end

local function SkinTab(cf)
    local tab = _G[(cf:GetName() or "") .. "Tab"]
    if not tab then return end
    if not tab._ouiSkinned then
        -- flatten: drop the default tab textures, keep the label
        for i = 1, select("#", tab:GetRegions()) do
            local r = select(i, tab:GetRegions())
            if r and r.GetObjectType and r:GetObjectType() == "Texture" then
                pcall(r.SetTexture, r, nil); r:SetAlpha(0)
            end
        end
        tab:HookScript("OnEnter", function(self)
            if cf ~= SELECTED_CHAT_FRAME then local t = tabText(self); if t then t:SetTextColor(1, 1, 1) end end
        end)
        tab:HookScript("OnLeave", function() if ns.UpdateTabColors then ns.UpdateTabColors() end end)
        tab._ouiSkinned = true
    end
    local t = tabText(tab)
    if t then t:SetFont(fontPath(), 12, outlineFlag()) end
end

function ns.UpdateTabColors()
    eachChatFrame(function(cf)
        local tab = _G[(cf:GetName() or "") .. "Tab"]
        local t = tab and tabText(tab)
        if t then
            if cf == SELECTED_CHAT_FRAME then
                local a = OUI.ACCENT
                t:SetTextColor(a.r, a.g, a.b)
            else
                t:SetTextColor(0.7, 0.7, 0.7)
            end
        end
    end)
end

-- ---------------------------------------------------------------------------
--  Edit box
-- ---------------------------------------------------------------------------
local function SkinEditBox(cf)
    local eb = cf.editBox
    if not eb then return end
    local name = eb:GetName()
    if name then
        for _, suf in ipairs({ "Left", "Right", "Mid", "Middle" }) do
            local t = _G[name .. suf]
            if t and t.SetAlpha then t:SetAlpha(0) end
        end
    end
    eb:SetFont(fontPath(), 14, outlineFlag())

    if not eb._ouiBackdrop then
        local bd = CreateFrame("Frame", nil, eb)
        bd:SetFrameLevel(math.max(eb:GetFrameLevel() - 1, 0))
        bd.bg = bd:CreateTexture(nil, "BACKGROUND")
        bd.bg:SetAllPoints()
        bd:SetPoint("TOPLEFT", eb, "TOPLEFT", 2, -2)
        bd:SetPoint("BOTTOMRIGHT", eb, "BOTTOMRIGHT", -2, 2)
        if OUI.PP and OUI.PP.CreateBorder then OUI.PP.CreateBorder(bd, 0.067, 0.067, 0.067, 1) end
        eb._ouiBackdrop = bd
    end
    styleBackdrop(eb._ouiBackdrop, 0.2)
    eb._ouiBackdrop:SetShown(cfg("showBackground") ~= false)

    eb:ClearAllPoints()
    if cfg("editBoxPosition") == "TOP" then
        eb:SetPoint("BOTTOMLEFT", cf, "TOPLEFT", 0, 6)
        eb:SetPoint("BOTTOMRIGHT", cf, "TOPRIGHT", 0, 6)
    else
        eb:SetPoint("TOPLEFT", cf, "BOTTOMLEFT", 0, -6)
        eb:SetPoint("TOPRIGHT", cf, "BOTTOMRIGHT", 0, -6)
    end
end

-- ---------------------------------------------------------------------------
--  Dock manager (the bar the tabs dock onto)
-- ---------------------------------------------------------------------------
local function StyleDock()
    local dock = GeneralDockManager
    if not dock or dock._ouiSkinned then return end
    for i = 1, select("#", dock:GetRegions()) do
        local r = select(i, dock:GetRegions())
        if r and r.GetObjectType and r:GetObjectType() == "Texture" then r:SetAlpha(0) end
    end
    dock._ouiSkinned = true
end

-- ---------------------------------------------------------------------------
--  Hide Blizzard's default chat buttons (menu / channel / quick-join / voice /
--  the scroll up-down-bottom buttons and the floating scroll-to-bottom button)
-- ---------------------------------------------------------------------------
local GLOBAL_BUTTONS = {
    "ChatFrameMenuButton", "ChatFrameChannelButton", "QuickJoinToastButton",
    "ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton",
}

local function hideBtn(btn, forceShow)
    if type(btn) ~= "table" or not btn.HookScript then return end
    if not btn._ouiBtnHook then
        btn._ouiBtnHook = true
        btn:HookScript("OnShow", function(s)
            if cfg("hideDefaultButtons") ~= false then s:Hide() end
        end)
    end
    if cfg("hideDefaultButtons") ~= false then btn:Hide()
    elseif forceShow then btn:Show() end
end

local function hideBlizzardButtons()
    for _, name in ipairs(GLOBAL_BUTTONS) do hideBtn(_G[name], true) end
    eachChatFrame(function(cf)
        local n = cf:GetName() or ""
        -- named scroll buttons
        for _, suf in ipairs({ "ButtonFrameUpButton", "ButtonFrameDownButton",
                               "ButtonFrameBottomButton", "ButtonFrameMinimizeButton" }) do
            hideBtn(_G[n .. suf], false)
        end
        -- catch any other buttons docked into the chat's ButtonFrame
        local bf = _G[n .. "ButtonFrame"]
        if bf and bf.GetChildren then
            for i = 1, select("#", bf:GetChildren()) do
                local c = select(i, bf:GetChildren())
                if c and c.HookScript and c.Hide then hideBtn(c, false) end
            end
        end
        if cf.ScrollToBottomButton then hideBtn(cf.ScrollToBottomButton, false) end
    end)
end

-- ---------------------------------------------------------------------------
--  Apply everything
-- ---------------------------------------------------------------------------
function ns.ApplyAll()
    if not (ns.db and cfg("enabled")) then return end
    eachChatFrame(function(cf)
        SkinChatFrame(cf)
        if cfg("styleTabs") then SkinTab(cf) end
        if cfg("styleEditBox") then SkinEditBox(cf) end
    end)
    StyleDock()
    hideBlizzardButtons()
    ns.UpdateTabColors()
end
ns.SkinChatFrame = SkinChatFrame

-- ---------------------------------------------------------------------------
--  Lifecycle
-- ---------------------------------------------------------------------------
function CH:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("OldschoolUIChatDB", defaults, true)
    ns.db = self.db
end

function CH:OnEnable()
    if not cfg("enabled") then return end

    -- Restore history as early as possible (now, during the login phase) so the
    -- replayed scrollback sits above addon login messages rather than below.
    if ns.SetupChatHistory then ns.SetupChatHistory() end

    -- temporary windows (whispers etc.) created on demand
    if not CH._tempHook then
        CH._tempHook = true
        hooksecurefunc("FCF_OpenTemporaryWindow", function()
            local cf = _G["ChatFrame" .. (FCF_GetCurrentChatFrameID and FCF_GetCurrentChatFrameID() or 1)]
            if cf then
                SkinChatFrame(cf)
                if cfg("styleTabs") then SkinTab(cf) end
                if cfg("styleEditBox") then SkinEditBox(cf) end
            end
        end)
        if FCFDock_SelectWindow then
            hooksecurefunc("FCFDock_SelectWindow", function() C_Timer.After(0, ns.UpdateTabColors) end)
        end
        if FCF_SetChatWindowFontSize then
            hooksecurefunc("FCF_SetChatWindowFontSize", function() C_Timer.After(0, ns.ApplyAll) end)
        end
    end

    local function applyAndFade()
        ns.ApplyAll()
        if ns.StartChatFade then ns.StartChatFade() end
        if ns.SetupChatText then ns.SetupChatText() end
        if ns.SetupSidebar then ns.SetupSidebar() end
    end
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function() C_Timer.After(0.2, applyAndFade) end)
    C_Timer.After(0.5, applyAndFade)
end

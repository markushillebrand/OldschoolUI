-- ===========================================================================
--  OldschoolUI -- Blizzard Skin: standard frames
--  Generic reskin for the many Blizzard windows built on PortraitFrameTemplate
--  (Merchant, Group Finder / PVE, Dungeon & Raid Finder, Guild, Inspect,
--  Spellbook, Talents, Auction House, ...). They share the same chrome (Bg /
--  corners / borders / NineSlice / portrait), so one skinner handles them all:
--  hide the stock chrome, lay down our dark panel + Core border, dim inner
--  decorative art, accent the title, and plate the tabs. Non-secure frames -> no
--  taint. Field names confirmed via /ouiprobe dump.
-- ===========================================================================
local _, ns = ...
local OUI = OldschoolUI
if not OUI then return end
local BS = ns.BS
if not BS then return end

local function ac() return OUI.ACCENT.r, OUI.ACCENT.g, OUI.ACCENT.b end
local function framesEnabled() return BS.db and BS.db.profile and BS.db.profile.reskinFrames end

local done = setmetatable({}, { __mode = "k" })

-- portrait-template chrome, hidden by field key (exact keys from the dumps)
local CHROME_KEYS = {
    "Bg", "TitleBg", "portrait", "Portrait", "PortraitFrame", "PortraitContainer",
    "PortraitOverlay",
    "TopBorder", "BottomBorder", "LeftBorder", "RightBorder",
    "TopLeftCorner", "TopRightCorner", "BotLeftCorner", "BotRightCorner",
    "TopTileStreaks", "NineSlice",
}
local function hideChrome(f)
    if not f then return end
    local nm = f.GetName and f:GetName()
    for _, k in ipairs(CHROME_KEYS) do
        local r = f[k]
        if r and r.SetAlpha then r:SetAlpha(0) end
        -- some frames (CommunitiesFrame) name chrome globally: <Name>Bg etc.
        local g = nm and _G[nm .. k]
        if g and g.SetAlpha then g:SetAlpha(0) end
    end
end

local stripSeen = setmetatable({}, { __mode = "k" })
local SKIP_TYPES = { ModelScene = true, PlayerModel = true, Model = true,
                     DressUpModel = true, CinematicModel = true }
local function stripChrome(frame, depth)
    if not frame or (depth or 0) < 0 or stripSeen[frame] then return end
    stripSeen[frame] = true
    if frame.GetRegions then
        for i = 1, select("#", frame:GetRegions()) do
            local r = select(i, frame:GetRegions())
            if r and r.IsObjectType and r:IsObjectType("Texture") and r.SetAlpha then
                local layer = r.GetDrawLayer and select(1, r:GetDrawLayer())
                local nm = r.GetName and r:GetName()
                -- only dim true backgrounds; never icons/rings/active/highlight art
                -- (those live in BORDER/ARTWORK and dimming them blanks spell icons)
                local protected = nm and (nm:find("Icon") or nm:find("Ring")
                    or nm:find("Active") or nm:find("Highlight"))
                if layer == "BACKGROUND" and not protected then r:SetAlpha(0) end
            end
        end
    end
    if frame.GetChildren and (depth or 0) > 0 then
        for i = 1, select("#", frame:GetChildren()) do
            local c = select(i, frame:GetChildren())
            local t = c and c.GetObjectType and c:GetObjectType()
            if c and not SKIP_TYPES[t] and not (c.Icon or c.icon) then
                stripChrome(c, (depth or 0) - 1)
            end
        end
    end
end

-- bar fill colour: accent, slightly brighter on a dark skin bg, darker on light
local function barColor()
    local r, g, b = ac()
    local br, bg2, bb = OUI.GetSkinBg()
    local lum = 0.299 * br + 0.587 * bg2 + 0.114 * bb
    local f = (lum > 0.5) and 0.72 or 1.12
    return math.min(r * f, 1), math.min(g * f, 1), math.min(b * f, 1)
end

-- bar track colour: a visible step off the skin bg (lighter on dark, darker on
-- light) so the profession-bar field reads as a recessed bar, not blending away.
local function trackColor()
    local r, g, b = OUI.GetSkinBg()
    local lum = 0.299 * r + 0.587 * g + 0.114 * b
    local d = (lum > 0.5) and -0.10 or 0.10
    local function c(x) return math.max(0, math.min(1, x + d)) end
    return c(r), c(g), c(b), 1
end

-- hide the stock bar art (green 3-slice BG track + end caps); optionally the static
-- fill texture too (custom Frame bars have no live fill, real StatusBars do).
local function clearBarArt(frame, hideFill)
    if not frame or not frame.GetRegions then return end
    for i = 1, select("#", frame:GetRegions()) do
        local r = select(i, frame:GetRegions())
        if r and r.IsObjectType and r:IsObjectType("Texture") then
            local rn = (r.GetName and r:GetName()) or ""
            if rn:find("BG") or rn:find("Background")
                or rn:find("StatusBarLeft$") or rn:find("StatusBarRight$") then
                if r.SetAlpha then r:SetAlpha(0) end
            elseif hideFill and rn:find("StatusBarBar$") then
                if r.SetAlpha then r:SetAlpha(0) end
            end
        end
    end
end

local function ensureTrack(frame)
    if not frame._ouiTrack and frame.CreateTexture then
        local tr = frame:CreateTexture(nil, "BACKGROUND", nil, -8)  -- lowest, behind the fill
        tr:SetAllPoints(frame)
        frame._ouiTrack = tr
    end
    if frame._ouiTrack then
        frame._ouiTrack:SetColorTexture(trackColor())
        frame._ouiTrack:Show()
    end
end

-- Skin bar widgets to our CI. The profession skill bars are real StatusBar objects
-- (type=StatusBar, 95x16): give them a visible dark track (our own texture, since
-- the stock green BG slices proved unreliable) plus the native proportional fill
-- retextured to flat OUI + accent. Frames merely named …StatusBar (if any) get the
-- track + their static art cleared.
local function skinBars(frame, depth)
    if not frame or (depth or 0) < 0 then return end
    local nm = (frame.GetName and frame:GetName()) or ""
    local isBar = frame.GetObjectType and frame:GetObjectType() == "StatusBar"
    local isCustom = nm:find("StatusBar$")
    if isBar or isCustom then
        ensureTrack(frame)
        if isBar then
            local tex = OUI.GetBarTexturePath and OUI.GetBarTexturePath(nil)
            if tex and frame.SetStatusBarTexture then frame:SetStatusBarTexture(tex) end
            if frame.SetStatusBarColor then frame:SetStatusBarColor(barColor()) end
            clearBarArt(frame, false)   -- keep the live native fill
        else
            clearBarArt(frame, true)    -- custom frame: track + text only
        end
    end
    if frame.GetChildren and (depth or 0) > 0 then
        for i = 1, select("#", frame:GetChildren()) do
            skinBars(select(i, frame:GetChildren()), (depth or 0) - 1)
        end
    end
end

-- lighten dark Blizzard text (designed for light parchment) so it stays readable
-- on our dark panels. Only recolours text that is currently dark (keeps coloured /
-- already-light text untouched). Adaptive to the skin bg.
local function skinText(frame, depth)
    if not frame or (depth or 0) < 0 then return end
    local function fix(fs)
        if fs and fs.GetTextColor and fs.SetTextColor then
            local r, g, b = fs:GetTextColor()
            if r and (0.299 * r + 0.587 * g + 0.114 * b) < 0.40 then
                fs:SetTextColor(OUI.GetSkinTextColor())
            end
        end
    end
    if frame.GetObjectType and frame:GetObjectType() == "FontString" then fix(frame); return end
    if frame.GetRegions then
        for i = 1, select("#", frame:GetRegions()) do
            local r = select(i, frame:GetRegions())
            if r and r.GetObjectType and r:GetObjectType() == "FontString" then fix(r) end
        end
    end
    if frame.GetChildren and (depth or 0) > 0 then
        for i = 1, select("#", frame:GetChildren()) do
            skinText(select(i, frame:GetChildren()), (depth or 0) - 1)
        end
    end
end
ns.SkinFrameText = skinText

-- flatten light/parchment section backgrounds (named …BG/…Background) to dark,
-- used for dynamically-built sub-sections (e.g. EncounterJournal info bullets).
local function darkenBGs(frame, depth)
    if not frame or (depth or 0) < 0 then return end
    if frame.GetRegions then
        for i = 1, select("#", frame:GetRegions()) do
            local r = select(i, frame:GetRegions())
            if r and r.IsObjectType and r:IsObjectType("Texture") then
                local nm = r.GetName and r:GetName()
                if nm and (nm:find("BG") or nm:find("Background")) and r.SetColorTexture then
                    r:SetColorTexture(0.10, 0.10, 0.12, 0.85)
                end
            end
        end
    end
    if frame.GetChildren and (depth or 0) > 0 then
        for i = 1, select("#", frame:GetChildren()) do
            darkenBGs(select(i, frame:GetChildren()), (depth or 0) - 1)
        end
    end
end
ns.DarkenFrameBGs = darkenBGs

local function skinScroll(sb)
    if not sb or done[sb] then return end
    done[sb] = true
    local thumb = sb.GetThumbTexture and sb:GetThumbTexture()
    if thumb then thumb:SetColorTexture(ac()); thumb:SetAlpha(0.45) end
    local name = sb.GetName and sb:GetName()
    for _, k in ipairs({ "ScrollUpButton", "ScrollDownButton" }) do
        local b = sb[k] or (name and _G[name .. k])
        if b and b.GetRegions then
            for i = 1, select("#", b:GetRegions()) do
                local r = select(i, b:GetRegions())
                if r and r.SetAlpha then r:SetAlpha(0) end
            end
        end
    end
end

local function skinTab(tab)
    if not tab or done[tab] then return end
    done[tab] = true
    for _, k in ipairs({ "Left", "Middle", "Right",
                         "LeftDisabled", "MiddleDisabled", "RightDisabled",
                         "HighlightTexture" }) do
        if tab[k] and tab[k].SetAlpha then tab[k]:SetAlpha(0) end
    end
    if not tab._ouiBg then
        local bg = tab:CreateTexture(nil, "BACKGROUND")
        bg:SetPoint("TOPLEFT", 3, -2); bg:SetPoint("BOTTOMRIGHT", -3, 2)
        bg:SetColorTexture(0.06, 0.06, 0.07, 0.96)
        tab._ouiBg = bg
        local line = tab:CreateTexture(nil, "BORDER")
        line:SetPoint("BOTTOMLEFT", bg, "BOTTOMLEFT", 0, 0)
        line:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", 0, 0)
        line:SetHeight(2); line:SetColorTexture(ac())
    end
    local fs = tab.GetFontString and tab:GetFontString()
    if fs then fs:SetTextColor(ac()) end
    -- content (e.g. profession skill bars) is rebuilt on tab switch -> re-skin
    if not tab._ouiTabHook then
        tab._ouiTabHook = true
        tab:HookScript("OnClick", function(self)
            local p = self:GetParent()
            if p and framesEnabled() then
                local function pass()
                    skinBars(p, 7); skinText(p, 8); darkenBGs(p, 7); hideChrome(p)
                end
                C_Timer.After(0, pass); C_Timer.After(0.1, pass); C_Timer.After(0.35, pass)
            end
        end)
    end
end

-- ---------------------------------------------------------------------------
--  generic standard-frame skinner
-- ---------------------------------------------------------------------------
local function skinStd(frame, opts)
    if not frame or done[frame] then return end
    if frame.IsForbidden and frame:IsForbidden() then return end
    done[frame] = true
    opts = opts or {}
    local name = frame.GetName and frame:GetName()

    stripChrome(frame, opts.depth or 2)
    BS:DarkPanel(frame, 0.97)
    hideChrome(frame)

    local title = (name and _G[name .. "TitleText"]) or frame.TitleText
    if title and title.SetTextColor then title:SetTextColor(ac()) end

    -- content insets -> dark (by field key and by <Name><Key> global)
    for _, k in ipairs(opts.insets or { "Inset" }) do
        if frame[k] then BS:DarkPanel(frame[k], 0.9) end
        if name and _G[name .. k] then BS:DarkPanel(_G[name .. k], 0.9) end
    end

    -- tabs: <Name>Tab1..N and <Name>TabButton1..N (SpellBook uses TabButton)
    if name then
        for _, suf in ipairs({ "Tab", "TabButton" }) do
            local i = 1
            while _G[name .. suf .. i] do skinTab(_G[name .. suf .. i]); i = i + 1 end
        end
    end

    skinBars(frame, opts.barDepth or 6)
    skinText(frame, opts.textDepth or 8)
    darkenBGs(frame, opts.bgDepth or 6)

    if name and BS.MakeMovable then BS:MakeMovable(frame, name) end

    -- Blizzard re-shows NineSlice/portrait and rebuilds skill bars + text on tab
    -- switch -> re-hide chrome + re-skin bars/text/section-bgs on show.
    frame:HookScript("OnShow", function(self)
        if framesEnabled() then
            hideChrome(self)
            skinBars(self, opts.barDepth or 6)
            skinText(self, opts.textDepth or 8)
            darkenBGs(self, opts.bgDepth or 6)
        end
    end)
end
ns.SkinStdFrame = skinStd

-- ---------------------------------------------------------------------------
--  registry + LoadOnDemand-agnostic loader
-- ---------------------------------------------------------------------------
local FRAMES = {
    MerchantFrame       = { insets = { "Inset", "MoneyInset" } },
    PVEFrame            = {},
    LFDParentFrame      = { insets = { "Inset" } },
    RaidFinderFrame     = {},
    ScenarioFinderFrame = {},
    LFGListFrame        = {},
    GuildFrame          = {},
    CommunitiesFrame    = {},          -- the guild window in MoP is Communities
    EncounterJournal    = {},          -- Dungeon Journal (LoD)
    AchievementFrame    = {},          -- Achievements (LoD)
    InspectFrame        = {},
    SpellBookFrame      = {},
    PlayerTalentFrame   = {},
    AuctionHouseFrame   = { insets = { "MoneyFrameInset" } },
    ClassTrainerFrame   = {},
    TradeFrame          = { insets = { "Inset", "LeftInset" } },
}

local function trySkin()
    if not framesEnabled() then return end
    for name, opts in pairs(FRAMES) do
        if _G[name] then skinStd(_G[name], opts) end
    end
    -- EncounterJournal swaps its description text on encounter/instance click (not a
    -- tab/show), so hook the display fns once to re-lighten that text.
    if not ns._ejHooked and _G.EncounterJournal_DisplayEncounter then
        ns._ejHooked = true
        local function reText()
            if framesEnabled() and _G.EncounterJournal then
                C_Timer.After(0, function()
                    skinText(_G.EncounterJournal, 10)
                    darkenBGs(_G.EncounterJournal, 12)
                end)
            end
        end
        hooksecurefunc("EncounterJournal_DisplayEncounter", reText)
        if _G.EncounterJournal_DisplayInstance then
            hooksecurefunc("EncounterJournal_DisplayInstance", reText)
        end
        -- sections expand/collapse without a tab/display call -> throttled re-skin
        if _G.EncounterJournal and not _G.EncounterJournal._ouiEJUpdate then
            _G.EncounterJournal._ouiEJUpdate = true
            local acc = 0
            _G.EncounterJournal:HookScript("OnUpdate", function(self, e)
                acc = acc + (e or 0)
                if acc < 0.2 then return end
                acc = 0
                if framesEnabled() then skinText(self, 10); darkenBGs(self, 12) end
            end)
        end
    end
    -- profession skill bars are (re)built by SpellBook_UpdateProfTab; Blizzard
    -- re-applies their green atlas there, so a timer-based pass races it. Hook the
    -- update itself and re-skin right after it runs.
    if not ns._profHooked and _G.SpellBook_UpdateProfTab then
        ns._profHooked = true
        hooksecurefunc("SpellBook_UpdateProfTab", function()
            if framesEnabled() and _G.SpellBookFrame then
                skinBars(_G.SpellBookFrame, 8)                                  -- right after Blizzard's update
                C_Timer.After(0, function() skinBars(_G.SpellBookFrame, 8) end) -- and once more next frame
            end
        end)
    end
end
ns.SkinStdFrames = trySkin

-- Most of these frames do NOT exist at login (Merchant is built on MERCHANT_SHOW,
-- LoD UIs on open) -- so iterating at PLAYER_LOGIN/ADDON_LOADED skins nothing.
-- ShowUIPanel is called WITH the frame the moment it opens, which guarantees the
-- frame exists; hook it (post-hook, taint-safe -- reskinning textures is not a
-- protected action) and skin on first show. Keep the login/addon retry as a
-- fallback for anything shown via another path.
local function trySkinFrame(frame)
    if not framesEnabled() then return end
    -- skin the frame that just opened plus any sibling/sub-panel that now exists
    trySkin()
end
if ShowUIPanel then hooksecurefunc("ShowUIPanel", trySkinFrame) end
if ToggleFrame then hooksecurefunc("ToggleFrame", trySkinFrame) end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("ADDON_LOADED")          -- retry as LoD UIs load
loader:RegisterEvent("MERCHANT_SHOW")         -- Merchant builds here
loader:SetScript("OnEvent", function() trySkin() end)


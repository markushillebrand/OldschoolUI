-- ===========================================================================
--  OldschoolUI -- Blizzard Skin: Collections Journal
--  Themed reskin of the (LoadOnDemand) Blizzard_Collections UI: the journal
--  parent + its sub-tabs (Mounts / Pets / Toy Box / Heirlooms / Appearances)
--  wherever present on this client. Visual-only -- we strip stock art and
--  overlay our dark fill + Core border via BS:DarkPanel (which only touches the
--  named NineSlice/Border/Bg regions, so icons and 3D model scenes are left
--  intact). These are non-secure frames, so there is no taint risk here.
--
--  Field names on MoP Classic 5.5.x are accessed defensively (every lookup is
--  guarded); anything missing is simply skipped. Recycled list rows are left
--  for a screenshot-driven refinement pass.
-- ===========================================================================
local _, ns = ...
local OUI = OldschoolUI
if not OUI then return end
local BS = ns.BS
if not BS then return end

local function ac() return OUI.ACCENT.r, OUI.ACCENT.g, OUI.ACCENT.b end
local function framesEnabled() return BS.db and BS.db.profile and BS.db.profile.reskinFrames end

local done = setmetatable({}, { __mode = "k" })   -- per-object skinned guard

-- Set alpha 0 on a frame's DIRECT texture regions (used only for chrome that we
-- know holds no icons -- tabs, scrollbar buttons). Never call on a frame that
-- owns an icon/model as a direct region.
local function stripRegions(frame)
    if not frame or not frame.GetRegions then return end
    for i = 1, select("#", frame:GetRegions()) do
        local r = select(i, frame:GetRegions())
        if r and r.IsObjectType and r:IsObjectType("Texture") and r.SetAlpha then
            r:SetAlpha(0)
        end
    end
end

-- dark accent thumb + stripped arrows on a stock UIPanelScrollBar
local function skinScroll(sb)
    if not sb or done[sb] then return end
    done[sb] = true
    local name = sb.GetName and sb:GetName()
    for _, k in ipairs({ "ScrollUpButton", "ScrollDownButton" }) do
        local b = sb[k] or (name and _G[name .. k])
        if b then stripRegions(b) end
    end
    local thumb = sb.GetThumbTexture and sb:GetThumbTexture()
    if thumb then
        thumb:SetColorTexture(ac())
        thumb:SetAlpha(0.45)
    end
end

-- a HybridScrollFrame's scrollbar lives under a few possible field names
local function skinHybridScroll(sf)
    if not sf then return end
    skinScroll(sf.scrollBar or sf.ScrollBar or (sf.GetName and _G[(sf:GetName() or "") .. "ScrollBar"]))
end

-- Recursively dim BACKGROUND/BORDER-layer textures (decorative chrome: panel
-- backgrounds, ornate frame borders) while leaving ARTWORK/OVERLAY (icons,
-- selection glows) and 3D model scenes intact. Used on journal containers, never
-- on individual list rows.
local SKIP_TYPES = {
    ModelScene = true, PlayerModel = true, Model = true,
    DressUpModel = true, CinematicModel = true,
}
local stripSeen = setmetatable({}, { __mode = "k" })
local function stripChrome(frame, depth)
    if not frame or (depth or 0) < 0 or stripSeen[frame] then return end
    stripSeen[frame] = true
    if frame.GetRegions then
        for i = 1, select("#", frame:GetRegions()) do
            local r = select(i, frame:GetRegions())
            if r and r.IsObjectType and r:IsObjectType("Texture") and r.SetAlpha then
                local layer = r.GetDrawLayer and select(1, r:GetDrawLayer())
                if layer == "BACKGROUND" or layer == "BORDER" then r:SetAlpha(0) end
            end
        end
    end
    if frame.GetChildren and (depth or 0) > 0 then
        for i = 1, select("#", frame:GetChildren()) do
            local c = select(i, frame:GetChildren())
            local t = c and c.GetObjectType and c:GetObjectType()
            -- skip models, and skip icon-bearing buttons (list rows)
            if c and not SKIP_TYPES[t] and not (c.Icon or c.icon) then
                stripChrome(c, (depth or 0) - 1)
            end
        end
    end
end

-- Hide the standard PortraitFrameTemplate chrome by field key (portrait ring,
-- corners, edges, nine-slice, parchment bg) -- exact keys confirmed via
-- /ouiprobe dump. Covers CollectionsJournal and any frame using that template.
local CHROME_KEYS = {
    "Bg", "TitleBg", "portrait", "Portrait", "PortraitFrame", "PortraitContainer",
    "TopBorder", "BottomBorder", "LeftBorder", "RightBorder",
    "TopLeftCorner", "TopRightCorner", "BotLeftCorner", "BotRightCorner",
    "TopTileStreaks", "NineSlice",
}
local function hideChrome(f)
    if not f then return end
    for _, k in ipairs(CHROME_KEYS) do
        local r = f[k]
        if r and r.SetAlpha then r:SetAlpha(0) end
    end
end

-- bottom journal tabs: CollectionsJournalTab1..N
local function skinTab(tab)
    if not tab or done[tab] then return end
    done[tab] = true
    for _, k in ipairs({ "Left", "Middle", "Right",
                         "LeftDisabled", "MiddleDisabled", "RightDisabled",
                         "HighlightTexture" }) do
        if tab[k] and tab[k].SetAlpha then tab[k]:SetAlpha(0) end
    end
    -- dark plate so the (now art-less) tab is readable on the dark backdrop
    if not tab._ouiBg then
        local bg = tab:CreateTexture(nil, "BACKGROUND")
        bg:SetPoint("TOPLEFT", 2, -3)
        bg:SetPoint("BOTTOMRIGHT", -2, 6)
        bg:SetColorTexture(0.08, 0.08, 0.09, 0.95)
        tab._ouiBg = bg
        local top = tab:CreateTexture(nil, "BORDER")
        top:SetPoint("TOPLEFT", bg, "TOPLEFT", 0, 0)
        top:SetPoint("TOPRIGHT", bg, "TOPRIGHT", 0, 0)
        top:SetHeight(2)
        top:SetColorTexture(ac())
        tab._ouiTop = top
    end
    local fs = tab.GetFontString and tab:GetFontString()
    if fs then fs:SetTextColor(ac()) end
end

-- recolour a frame's direct FontString regions to the accent (headers/titles)
local function accentText(frame)
    if not frame or not frame.GetRegions then return end
    for i = 1, select("#", frame:GetRegions()) do
        local r = select(i, frame:GetRegions())
        if r and r.IsObjectType and r:IsObjectType("FontString") and r.SetTextColor then
            r:SetTextColor(ac())
        end
    end
end

-- ---------------------------------------------------------------------------
--  Sub-frame skinners (all defensive: skin what exists)
-- ---------------------------------------------------------------------------
local function skinMount(mj)
    if not mj or done[mj] then return end
    done[mj] = true
    stripChrome(mj, 2)
    BS:DarkPanel(mj, 0.95)
    -- exact keys (via /ouiprobe dump): LeftInset=list, ScrollBar, MountDisplay=model
    if mj.LeftInset then BS:DarkPanel(mj.LeftInset, 0.85) end
    if mj.RightInset then BS:DarkPanel(mj.RightInset, 0.85) end
    if mj.MountDisplay then BS:DarkPanel(mj.MountDisplay, 0.85) end
    skinScroll(mj.ScrollBar)
end

local function skinPet(pj)
    if not pj or done[pj] then return end
    done[pj] = true
    stripChrome(pj, 2)
    BS:DarkPanel(pj, 0.95)
    if pj.LeftInset then BS:DarkPanel(pj.LeftInset, 0.85) end
    if pj.RightInset then BS:DarkPanel(pj.RightInset, 0.85) end
    if pj.PetCardInset then BS:DarkPanel(pj.PetCardInset, 0.85) end
    skinScroll(pj.ScrollBar)
end

-- generic: Toy Box / Heirlooms / Wardrobe (Appearances)
local function skinGeneric(f)
    if not f or done[f] then return end
    done[f] = true
    stripChrome(f, 2)
    BS:DarkPanel(f, 0.95)
    -- the icon grid container carries ornate gear-corner art as DIRECT textures
    -- (the toy/heirloom icons live on child buttons, so this is safe)
    local grid = f.iconsFrame or f.IconsFrame
    if grid and grid.GetRegions then
        for i = 1, select("#", grid:GetRegions()) do
            local r = select(i, grid:GetRegions())
            if r and r.IsObjectType and r:IsObjectType("Texture") and r.SetAlpha then
                r:SetAlpha(0)
            end
        end
        BS:DarkPanel(grid, 0.85)
    end

    -- Wardrobe (Appearances): Items/Sets are separate sub-collection frames; Sets
    -- builds lazily on first open. Skin both if present, its own top tabs, and
    -- re-skin the active sub-frame whenever the tab is switched.
    local function skinSubs()
        for _, k in ipairs({ "ItemsCollectionFrame", "SetsCollectionFrame", "activeFrame" }) do
            local sub = f[k]
            if sub then stripChrome(sub, 3); BS:DarkPanel(sub, 0.9) end
        end
    end
    skinSubs()
    for _, tk in ipairs({ "ItemsTab", "SetsTab" }) do
        local tab = f[tk]
        if tab then
            skinTab(tab)
            if tab.HookScript then
                tab:HookScript("OnClick", function()
                    if framesEnabled() then C_Timer.After(0, skinSubs) end
                end)
            end
        end
    end
    for _, k in ipairs({ "BG", "Bg", "iconsFrame", "IconsFrame", "ScrollBox",
                         "RightInset", "BottomInset", "ModelScene" }) do
        if f[k] then BS:DarkPanel(f[k], 0.85) end
    end
    -- common HybridScroll fields
    skinHybridScroll(f.ScrollBox or f.iconsFrame or f.scrollFrame)
end

-- ---------------------------------------------------------------------------
--  Parent journal + dispatch
-- ---------------------------------------------------------------------------
local function hookShow(frame, fn)
    if not frame then return end
    frame:HookScript("OnShow", function(self)
        if framesEnabled() then fn(self) end
    end)
    if frame:IsShown() and framesEnabled() then fn(frame) end
end

local function skinCollections()
    local cj = _G.CollectionsJournal
    if not cj or done.parent then return end
    if cj.IsForbidden and cj:IsForbidden() then return end
    done.parent = true

    stripChrome(cj, 1)
    BS:DarkPanel(cj, 0.97)
    hideChrome(cj)        -- portrait ring + corners/edges/nine-slice (exact keys)
    BS:MakeMovable(cj, "collections", function()
        if ToggleCollectionsJournal then ToggleCollectionsJournal() end
    end)
    -- title -> accent
    local title = cj.TitleText or _G.CollectionsJournalTitleText
    if title and title.SetTextColor then title:SetTextColor(ac()) end
    -- bottom tabs (1..N)
    local i = 1
    while _G["CollectionsJournalTab" .. i] do
        skinTab(_G["CollectionsJournalTab" .. i]); i = i + 1
    end
    -- each tab page is built/shown lazily -> skin on first OnShow
    hookShow(_G.MountJournal,            skinMount)
    hookShow(_G.PetJournal,              skinPet)
    hookShow(_G.ToyBox,                  skinGeneric)
    hookShow(_G.HeirloomsJournal,        skinGeneric)
    hookShow(_G.WardrobeCollectionFrame, skinGeneric)
end
ns.SkinCollections = skinCollections

-- ---------------------------------------------------------------------------
--  LoadOnDemand loader (own frame, so we don't disturb BS's AceEvent handler)
-- ---------------------------------------------------------------------------
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" and name == "Blizzard_Collections" then
        if framesEnabled() then skinCollections() end
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        -- already loaded (rare) -> skin now; else wait for ADDON_LOADED
        local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded)("Blizzard_Collections")
        if loaded and framesEnabled() then skinCollections() end
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)

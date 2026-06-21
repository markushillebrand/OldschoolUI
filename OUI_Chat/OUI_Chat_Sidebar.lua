-- ===========================================================================
--  OldschoolUI -- Chat  CH-4b: sidebar
--  A small vertical bar of icon buttons next to the general chat frame. Opens
--  common MoP panels (copy chat, friends, guild, calendar, dungeon finder).
--  No portal flyout (that is a Retail-only feature). Clean-room rewrite.
-- ===========================================================================
local ADDON, ns = ...
local OUI = OldschoolUI
if not OUI then return end

local cfg = ns.cfg
if not cfg then return end

local function font() return (OUI.GetFontPath and OUI.GetFontPath()) or STANDARD_TEXT_FONT end

-- ---------------------------------------------------------------------------
--  Button definitions (key, icon, tooltip, action). MoP-safe globals only.
-- ---------------------------------------------------------------------------
local BUTTONS = {
    {
        key = "Copy", flag = "sidebarShowCopy",
        icon = "Interface\\ICONS\\INV_Misc_Note_01", tip = "Copy chat",
        action = function() if ns.OpenCopyChat then ns.OpenCopyChat() end end,
    },
    {
        key = "Friends", flag = "sidebarShowFriends",
        icon = "Interface\\ICONS\\INV_Misc_GroupLooking", tip = "Friends",
        action = function() if ToggleFriendsFrame then ToggleFriendsFrame() end end,
    },
    {
        key = "Guild", flag = "sidebarShowGuild",
        icon = "Interface\\ICONS\\INV_Shirt_GuildTabard_01", tip = "Guild",
        action = function()
            if IsInGuild and not IsInGuild() then
                if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("OldschoolUI: not in a guild.") end
                return
            end
            if ToggleGuildFrame then ToggleGuildFrame()
            elseif GuildFrame_Toggle then GuildFrame_Toggle() end
        end,
    },
    {
        key = "Calendar", flag = "sidebarShowCalendar",
        icon = "Interface\\ICONS\\INV_Misc_PocketWatch_01", tip = "Calendar",
        action = function() if ToggleCalendar then ToggleCalendar() end end,
    },
    {
        key = "LFD", flag = "sidebarShowLFD",
        icon = "Interface\\ICONS\\INV_Misc_Map_01", tip = "Dungeon Finder",
        action = function()
            if PVEFrame_ToggleFrame then PVEFrame_ToggleFrame()
            elseif ToggleLFDParentFrame then ToggleLFDParentFrame() end
        end,
    },
}

local sidebar

-- ---------------------------------------------------------------------------
--  Build
-- ---------------------------------------------------------------------------
local function makeIconButton(parent, def, size)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexture(def.icon)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if OUI.PP and OUI.PP.CreateBorder then OUI.PP.CreateBorder(b, 0.067, 0.067, 0.067, 1) end
    b:SetScript("OnClick", def.action)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(def.tip, 1, 1, 1)
        GameTooltip:Show()
        if OUI.PP and OUI.PP.SetBorderColor then
            local a = OUI.ACCENT or { r = 1, g = 1, b = 1 }
            OUI.PP.SetBorderColor(self, a.r, a.g, a.b, 1)
        end
    end)
    b:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        if OUI.PP and OUI.PP.SetBorderColor then OUI.PP.SetBorderColor(self, 0.067, 0.067, 0.067, 1) end
    end)
    return b
end

local function buildSidebar()
    if sidebar then return sidebar end
    local cf = ChatFrame1
    if not cf then return end
    local f = CreateFrame("Frame", "OUIChatSidebar", cf)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    if OUI.PP and OUI.PP.CreateBorder then OUI.PP.CreateBorder(f, 0.067, 0.067, 0.067, 1) end
    f.buttons = {}
    for _, def in ipairs(BUTTONS) do
        f.buttons[def.key] = makeIconButton(f, def, cfg("sidebarIconSize") or 20)
    end
    sidebar = f
    return f
end

-- ---------------------------------------------------------------------------
--  Layout (position, side, which buttons are shown)
-- ---------------------------------------------------------------------------
local function layoutSidebar()
    local f = sidebar
    local cf = ChatFrame1
    if not (f and cf) then return end
    local size = cfg("sidebarIconSize") or 20
    local gap = cfg("sidebarSpacing") or 6
    local side = cfg("sidebarSide") or "LEFT"

    -- which buttons are enabled, in order
    local shown = {}
    for _, def in ipairs(BUTTONS) do
        local b = f.buttons[def.key]
        if b and cfg(def.flag) ~= false then
            shown[#shown + 1] = b
        elseif b then
            b:Hide()
        end
    end

    local y = -4
    for _, b in ipairs(shown) do
        b:SetSize(size, size)
        b:ClearAllPoints()
        b:SetPoint("TOP", f, "TOP", 0, y)
        b.icon:Hide(); b.icon:Show()
        b:Show()
        y = y - (size + gap)
    end

    local h = math.max(#shown * (size + gap) - gap + 8, size + 8)
    f:SetSize(size + 8, h)
    f:ClearAllPoints()
    if side == "RIGHT" then
        f:SetPoint("TOPLEFT", cf, "TOPRIGHT", 6, 0)
    else
        f:SetPoint("TOPRIGHT", cf, "TOPLEFT", -6, 0)
    end

    f.bg:SetShown(cfg("sidebarBg") ~= false)
    if OUI.PP and OUI.PP.SetBorderColor then
        OUI.PP.SetBorderColor(f, 0.067, 0.067, 0.067, cfg("sidebarBg") ~= false and 1 or 0)
    end
    if f.bg.SetColorTexture then f.bg:SetColorTexture(0.05, 0.05, 0.05, 0.55) end
end

-- ---------------------------------------------------------------------------
--  Visibility (always / mouseover / never)
-- ---------------------------------------------------------------------------
local visDriver
local function ensureVisDriver()
    if visDriver then return end
    visDriver = CreateFrame("Frame")
    visDriver.alpha = 1
    visDriver:SetScript("OnUpdate", function(self, e)
        self.acc = (self.acc or 0) + e
        if self.acc < 0.05 then return end
        self.acc = 0
        if not sidebar then return end
        local mode = cfg("sidebarVisibility") or "mouseover"
        if mode ~= "mouseover" then return end
        local over = (ChatFrame1 and ChatFrame1:IsMouseOver(28, -34, -6, 40)) or sidebar:IsMouseOver(4, -4, -4, 4)
        local target = over and 1 or 0
        if math.abs(self.alpha - target) > 0.01 then
            self.alpha = self.alpha + ((target > self.alpha) and 1 or -1) * 0.15
            self.alpha = math.max(0, math.min(1, self.alpha))
            sidebar:SetAlpha(self.alpha)
        end
    end)
end

local function applyVisibility()
    local f = sidebar
    if not f then return end
    local mode = cfg("sidebarVisibility") or "mouseover"
    if mode == "never" then
        f:Hide()
        return
    end
    f:Show()
    if mode == "always" then
        f:SetAlpha(1)
        if visDriver then visDriver.alpha = 1 end
    else -- mouseover
        ensureVisDriver()
        visDriver.alpha = 0
        f:SetAlpha(0)
    end
end

-- ---------------------------------------------------------------------------
--  Public
-- ---------------------------------------------------------------------------
function ns.RefreshSidebar()
    if not cfg("sidebarEnabled") then
        if sidebar then sidebar:Hide() end
        return
    end
    buildSidebar()
    layoutSidebar()
    applyVisibility()
end

function ns.SetupSidebar()
    if not cfg("sidebarEnabled") then return end
    ns.RefreshSidebar()
end

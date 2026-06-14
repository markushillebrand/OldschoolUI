-- OldschoolUI / Core / Subsystems.lua
-- Shared support systems required by feature modules (first consumer: Minimap):
--   widget tooltips, SafeAtlas, font-style helpers, escape-close, pixel borders,
--   the visibility dispatcher (show/hide by condition), and mouseover targets.
-- Lean clean-room implementations matching the public API contract.

local OUI = OldschoolUI
local L   = OUI.L

-- =====================================================================
--  Widget tooltips
-- =====================================================================
local ANCHORS = { left = "ANCHOR_LEFT", right = "ANCHOR_RIGHT", top = "ANCHOR_TOP", bottom = "ANCHOR_BOTTOM" }

function OUI.ShowWidgetTooltip(owner, title, opts)
    if not owner then return end
    opts = opts or {}
    GameTooltip:SetOwner(owner, ANCHORS[opts.anchor] or "ANCHOR_RIGHT")
    GameTooltip:SetText(L(title or ""), 1, 1, 1, 1, true)
    if opts.lines then
        for _, ln in ipairs(opts.lines) do GameTooltip:AddLine(L(ln), nil, nil, nil, true) end
    end
    GameTooltip:Show()
end

function OUI.HideWidgetTooltip()
    GameTooltip:Hide()
end

function OUI.DisabledTooltip(owner, title, reason, opts)
    OUI.ShowWidgetTooltip(owner, title, opts)
    if reason then
        GameTooltip:AddLine(L(reason), 1, 0.3, 0.3, true)
        GameTooltip:Show()
    end
end

-- =====================================================================
--  SafeAtlas  (atlas with texture fallback, never errors on missing atlas)
-- =====================================================================
function OUI.SafeAtlas(region, atlas, fallbackTexture, useAtlasSize)
    if not (region and region.SetAtlas) then return end
    local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
    if info then
        region:SetAtlas(atlas, useAtlasSize)
        return true
    end
    if fallbackTexture and region.SetTexture then
        region:SetTexture(fallbackTexture)
        if region.Show then region:Show() end
    elseif region.Hide then
        if region.SetTexture then region:SetTexture(nil) end
        region:Hide()
    end
    return false
end

-- =====================================================================
--  Font-style helpers  (full font UI deferred; sensible defaults)
-- =====================================================================
function OUI.GetFontOutlineFlag(_addonKey) return "" end
function OUI.GetFontUseShadow(_addonKey)  return true end
OUI.EXPRESSWAY = OUI._localeFont or STANDARD_TEXT_FONT

-- =====================================================================
--  Escape-close
-- =====================================================================
function OUI.RegisterEscapeClose(frame)
    if not frame then return end
    local name = frame.GetName and frame:GetName()
    if name then
        for _, n in ipairs(UISpecialFrames) do if n == name then return end end
        table.insert(UISpecialFrames, name)
        return
    end
    -- Unnamed frame: close on ESC via keyboard passthrough.
    if frame._ouiEsc then return end
    frame._ouiEsc = true
    frame:EnableKeyboard(true)
    frame:SetPropagateKeyboardInput(true)
    frame:HookScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            self:Hide()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)
end

-- =====================================================================
--  Pixel borders  (frame-keyed; create once, recolor / resize later)
-- =====================================================================
OUI.PanelPP = 1
OUI.PP = OUI.PP or {}

function OUI.PP.CreateBorder(frame, r, g, b, a, _size)
    if not frame then return end
    if frame._ppBorder then return frame._ppBorder end
    frame._ppBorder = OUI._border(frame, r or 1, g or 1, b or 1, a or 0.3)
    return frame._ppBorder
end

function OUI.PP.GetBorders(frame)
    return frame and frame._ppBorder
end

function OUI.PP.SetBorderColor(frame, r, g, b, a)
    local bd = frame and frame._ppBorder
    if bd and bd.SetColor then bd:SetColor(r, g, b, a) end
end

function OUI.PP.SetBorderSize(frame, n)
    local bd = frame and frame._ppBorder
    if not bd then return end
    for _, k in ipairs({ "top", "bottom", "left", "right" }) do
        local t = bd[k]
        if t then if n and n <= 0 then t:Hide() else t:Show() end end
    end
end

function OUI.MakeBorder(frame, r, g, b, a, _size)
    return OUI.PP.CreateBorder(frame, r, g, b, a)
end

function OUI.PP.HideBorder(frame)
    local bd = frame and frame._ppBorder
    if not bd then return end
    for _, k in ipairs({ "top", "bottom", "left", "right" }) do
        if bd[k] then bd[k]:Hide() end
    end
end

function OUI.PP.ShowBorder(frame)
    local bd = frame and frame._ppBorder
    if not bd then return end
    for _, k in ipairs({ "top", "bottom", "left", "right" }) do
        if bd[k] then bd[k]:Show() end
    end
end

-- Pixel-perfect coordinate snapping: keep 1px borders/bars crisp at any UI
-- scale. PP.Scale snaps an offset to the physical pixel grid; Point/Size/Width
-- wrap SetPoint/SetSize/SetWidth with snapping.
OUI.PP.perfect = 1
OUI.PP.mult    = 1
local function RecalcPP()
    local ph
    if GetPhysicalScreenSize then local _; _, ph = GetPhysicalScreenSize() end
    OUI.PP.perfect = (ph and ph > 0) and (768 / ph) or 1
    local uiScale = (UIParent and UIParent:GetScale()) or 1
    if uiScale == 0 then uiScale = 1 end
    OUI.PP.mult = OUI.PP.perfect / uiScale
end
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:RegisterEvent("UI_SCALE_CHANGED")
    f:RegisterEvent("DISPLAY_SIZE_CHANGED")
    f:SetScript("OnEvent", RecalcPP)
    RecalcPP()
end

function OUI.PP.Scale(x)
    if x == 0 then return 0 end
    local m = OUI.PP.mult
    if m == 1 then return x end
    local pixels = x / m
    pixels = (x > 0) and math.floor(pixels) or math.ceil(pixels)
    return pixels * m
end

function OUI.PP.Point(obj, anchor, p1, p2, p3, p4)
    if not p1 then p1 = obj:GetParent() end
    if type(p1) == "number" then p1 = OUI.PP.Scale(p1) end
    if type(p2) == "number" then p2 = OUI.PP.Scale(p2) end
    if type(p3) == "number" then p3 = OUI.PP.Scale(p3) end
    if type(p4) == "number" then p4 = OUI.PP.Scale(p4) end
    obj:SetPoint(anchor, p1, p2, p3, p4)
end

function OUI.PP.Size(frame, w, h)
    frame:SetSize(OUI.PP.Scale(w), h and OUI.PP.Scale(h) or OUI.PP.Scale(w))
end

function OUI.PP.Width(frame, w)
    frame:SetWidth(OUI.PP.Scale(w))
end

-- =====================================================================
--  Visibility dispatcher  (conditional show/hide; returns "mouseover"/bool)
-- =====================================================================
OUI.VIS_VALUES = {
    never = "Never", always = "Always", mouseover = "Mouseover",
    in_combat = "In Combat", out_of_combat = "Out of Combat",
    in_raid = "In Raid Group", in_party = "In Party", solo = "Solo",
}
OUI.VIS_ORDER = { "never", "always", "mouseover", "in_combat", "out_of_combat", "---", "in_raid", "in_party", "solo" }

OUI.VIS_VALUES_CDM = {
    never = "Never", always = "Always",
    in_combat = "In Combat", out_of_combat = "Out of Combat",
    in_raid = "In Raid Group", in_party = "In Party", solo = "Solo",
}
OUI.VIS_ORDER_CDM = { "never", "always", "in_combat", "out_of_combat", "---", "in_raid", "in_party", "solo" }

OUI.VIS_OPT_ITEMS = {
    { key = "visOnlyInstances", label = "Only Show in Instances" },
    { key = "visHideMounted",   label = "Hide when Mounted" },
    { key = "visHideNoTarget",  label = "Hide without Target" },
    { key = "visHideNoEnemy",   label = "Hide without Enemy Target",
      tooltip = "This element will only show if you have an enemy targeted." },
}

function OUI.EvalVisibility(p)
    if not p then return true end
    -- Hard hide-conditions (checked first).
    if p.visOnlyInstances then
        local inInstance = IsInInstance and IsInInstance()
        if not inInstance then return false end
    end
    if p.visHideMounted and IsMounted and IsMounted() then return false end
    if p.visHideNoTarget and not UnitExists("target") then return false end
    if p.visHideNoEnemy and not (UnitExists("target") and UnitCanAttack("player", "target")) then return false end

    local v = p.visibility or "always"
    if v == "never"          then return false end
    if v == "mouseover"      then return "mouseover" end
    if v == "always"         then return true end
    if v == "in_combat"      then return (InCombatLockdown and InCombatLockdown()) and true or false end
    if v == "out_of_combat"  then return not (InCombatLockdown and InCombatLockdown()) end
    if v == "in_raid"        then return IsInRaid and IsInRaid() or false end
    if v == "in_party"       then return (IsInGroup and IsInGroup()) and not (IsInRaid and IsInRaid()) end
    if v == "solo"           then return not (IsInGroup and IsInGroup()) end
    return true
end

local visUpdaters = {}
function OUI.RegisterVisibilityUpdater(fn)
    if fn then visUpdaters[#visUpdaters + 1] = fn end
end
function OUI.RequestVisibilityUpdate()
    for _, fn in ipairs(visUpdaters) do pcall(fn) end
end

local visDisp = CreateFrame("Frame")
for _, ev in ipairs({
    "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
    "GROUP_ROSTER_UPDATE", "PLAYER_TARGET_CHANGED", "ZONE_CHANGED_NEW_AREA", "UNIT_AURA",
}) do visDisp:RegisterEvent(ev) end
visDisp:SetScript("OnEvent", function(_, ev, unit)
    if ev == "UNIT_AURA" and unit ~= "player" then return end
    OUI.RequestVisibilityUpdate()
end)

-- =====================================================================
--  Mouseover targets  (reveal on hover when predicate() is true)
-- =====================================================================
function OUI.RegisterMouseoverTarget(frame, predicate)
    if not frame then return end
    frame:HookScript("OnEnter", function(self) if predicate and predicate() then self:SetAlpha(1) end end)
    frame:HookScript("OnLeave", function(self) if predicate and predicate() then self:SetAlpha(0) end end)
end

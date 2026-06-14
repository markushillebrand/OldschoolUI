-------------------------------------------------------------------------------
--  OldschoolUI / Core / ModuleApi.lua
--  Cross-module Core API surface consumed by feature modules (first consumer:
--  Resource Bars). Clean-room implementations matching the public contracts:
--    - module navigation (ShowModule) + unlock-mode alias (ToggleUnlockMode)
--    - options show/hide callbacks (RegisterOnShow / RegisterOnHide)
--    - element visibility by option flags + alpha/mouse preserving toggle
--    - player unit/party frame lookup (+ cache invalidation)
--    - font/outline accessors and per-addon border helpers
--    - a green accent constant (replaces the legacy hard-coded brand green)
--  Advanced anchor-chain + height-match features are graceful-degrade stubs
--  here; they are fleshed out when the owning systems are ported.
-------------------------------------------------------------------------------
local OUI = OldschoolUI
if not OUI then return end

-- Neutral green accent (used by skinning modules for "good/ready" states).
OUI.GREEN = OUI.GREEN or { r = 0.18, g = 0.78, b = 0.52 }

-------------------------------------------------------------------------------
--  Module navigation / unlock alias
-------------------------------------------------------------------------------
function OUI:ShowModule(folder)
    if InCombatLockdown() then return end
    if folder and self.SelectPage then
        self:SelectPage(folder)
    elseif self.Show then
        self:Show()
    end
end

function OUI:ToggleUnlockMode()
    if self.ToggleUnlock then self:ToggleUnlock() end
end

-------------------------------------------------------------------------------
--  Options show/hide callbacks
--  Modules register here to react when the options window opens/closes (e.g.
--  suppressing transient bar auto-expand while the user is configuring).
-------------------------------------------------------------------------------
local _onShow, _onHide = {}, {}
function OUI:RegisterOnShow(fn) if fn then _onShow[#_onShow + 1] = fn end end
function OUI:RegisterOnHide(fn) if fn then _onHide[#_onHide + 1] = fn end end

local function fire(list)
    for _, fn in ipairs(list) do pcall(fn) end
end

-- Wrap the options window Show/Hide (defined in Core/Options.lua, loaded first)
-- so registered callbacks fire without those functions needing to know about us.
local _origShow, _origHide = OUI.Show, OUI.Hide
function OUI:Show(...)
    if _origShow then _origShow(self, ...) end
    fire(_onShow)
end
function OUI:Hide(...)
    if _origHide then _origHide(self, ...) end
    fire(_onHide)
end

-------------------------------------------------------------------------------
--  Element visibility
-------------------------------------------------------------------------------
-- Returns true when the element SHOULD BE HIDDEN given its visibility options.
function OUI.CheckVisibilityOptions(opts)
    if not opts then return false end
    if opts.visOnlyInstances and not IsInInstance() then return true end
    if opts.visHideMounted and IsMounted() then return true end
    if opts.visHideNoTarget and not UnitExists("target") then return true end
    if opts.visHideNoEnemy then
        if not (UnitExists("target") and UnitCanAttack("player", "target")) then
            return true
        end
    end
    return false
end

-- Per-frame restore data (weak-keyed so frames can be GC'd).
local _fd = setmetatable({}, { __mode = "k" })
local function FD(f)
    local d = _fd[f]; if not d then d = {}; _fd[f] = d end; return d
end

-- Show/hide a frame without re-parenting: preserve its alpha + mouse state.
function OUI.SetElementVisibility(frame, visible)
    if not frame then return end
    local d = FD(frame)
    if visible then
        frame:SetAlpha(d.restoreAlpha or 1)
        if frame.EnableMouse then frame:EnableMouse(d.restoreMouse or false) end
    else
        if frame:GetAlpha() > 0 then d.restoreAlpha = frame:GetAlpha() end
        if frame.IsMouseEnabled then d.restoreMouse = frame:IsMouseEnabled() end
        frame:SetAlpha(0)
        if frame.EnableMouse then frame:EnableMouse(false) end
    end
end

-------------------------------------------------------------------------------
--  Player unit / party frame lookup (for anchoring bars to the player frame)
-------------------------------------------------------------------------------
local _cachePlayer, _cacheParty
function OUI.InvalidateFrameCache()
    _cachePlayer, _cacheParty = nil, nil
end

function OUI.FindPlayerUnitFrame()
    if _cachePlayer and _cachePlayer:IsVisible() then return _cachePlayer end
    _cachePlayer = nil
    local pf = _G.PlayerFrame
    if pf and pf:IsVisible() then _cachePlayer = pf; return pf end
    return nil
end

function OUI.FindPlayerPartyFrame()
    if _cacheParty and _cacheParty:IsVisible() then return _cacheParty end
    _cacheParty = nil
    for i = 1, 5 do
        local f = _G["CompactPartyFrameMember" .. i] or _G["PartyMemberFrame" .. i]
        if f and f:IsVisible() then
            local u = f.unit or (f.GetAttribute and f:GetAttribute("unit"))
            if u and UnitExists(u) and UnitIsUnit(u, "player") then
                _cacheParty = f; return f
            end
        end
    end
    return nil
end

-------------------------------------------------------------------------------
--  Font / outline accessors
-------------------------------------------------------------------------------
function OUI.GetOutline()
    return (OUI.GetFontOutlineFlag and OUI.GetFontOutlineFlag()) or ""
end

function OUI.GetFont()
    local path = (OUI.GetFontPath and OUI.GetFontPath()) or STANDARD_TEXT_FONT
    return path, OUI.GetOutline()
end

-------------------------------------------------------------------------------
--  Per-addon border helpers
-------------------------------------------------------------------------------
local _borderDefaults = {}
function OUI.RegisterBorderDefaults(addonKey, defaults)
    _borderDefaults[addonKey] = defaults
end

-- Returns offsetX, offsetY, shiftX, shiftY (all 0 when nothing registered).
function OUI.GetBorderDefaults(addonKey, textureKey, sizeKey)
    if textureKey == "shadow" then textureKey = "glow" end
    local a = _borderDefaults[addonKey]
    if not a then return 0, 0, 0, 0 end
    local byTex = a[textureKey]
    local e = byTex and (byTex[sizeKey] or byTex.default)
    if not e then return 0, 0, 0, 0 end
    return e.offsetX or 0, e.offsetY or 0, e.shiftX or 0, e.shiftY or 0
end

function OUI.SetBorderStyleColor(borderFrame, r, g, b, a)
    local PP = OUI.PP
    if not PP or not borderFrame then return end
    a = a or 1
    if PP.GetBorders and PP.GetBorders(borderFrame) then
        if PP.SetBorderColor then PP.SetBorderColor(borderFrame, r, g, b, a) end
    end
end

-------------------------------------------------------------------------------
--  Misc / cross-module
-------------------------------------------------------------------------------
-- Registry of owners requesting the player cast bar be hidden. The actual
-- suppression effect is applied by the cast/unit-frame system once ported;
-- here we just track owners so that path can consult it.
local _castSuppressors = {}
OUI._playerCastBarSuppressors = _castSuppressors
function OUI.SetPlayerCastBarSuppressed(owner, suppressed)
    if not owner or owner == "" then return end
    _castSuppressors[owner] = suppressed or nil
end

-- "Smart" power-percent display is a unit-frame setting; default off until that
-- module is ported and can own the real value.
function OUI.IsSmartPowerPercent() return false end

-- Height-match: a bar can match its height to another element. Not yet ported;
-- returning nil means bars use their own configured height.
function OUI.GetHeightMatchTarget(barKey) return nil end

-------------------------------------------------------------------------------
--  Anchor-chain (graceful-degrade stubs)
--  The full system lets a movable element anchor to another and follow it.
--  Until it is ported, nothing is treated as anchored, so elements keep their
--  own saved positions and chain propagation is a no-op.
-------------------------------------------------------------------------------
function OUI.IsUnlockAnchored(unlockKey) return false end
function OUI.PropagateAnchorChain(unlockKey) end

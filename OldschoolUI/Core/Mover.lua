-- OldschoolUI / Core / Mover.lua  (LootRoll prerequisites)
-- Lean unlock/mover system + small compat shims (fonts, pixel border, constants).
-- Replaces the original 9.6k-line UnlockMode with a focused movable-anchor system.

local OUI = OldschoolUI
local L   = OUI.L
local P   = OUI._palette
local Tex, Lbl, Border = OUI._tex, OUI._label, OUI._border
local INK, TXT, DIM = P.INK, P.TXT, P.DIM
local function A() return OUI.ACCENT.r, OUI.ACCENT.g, OUI.ACCENT.b end

-- ---------------------------------------------------------------------
-- Compat shims used by ported modules
-- ---------------------------------------------------------------------

-- Fonts-lite: configured font path or sensible default. (Full font UI later.)
function OUI.GetFontPath(_key)
    local g = OUI.db and OUI.db.global
    return (g and g.fontPath) or OUI._localeFont or STANDARD_TEXT_FONT
end
function OUI.GetFontName(_key) return "Default" end

-- Pixel-border shim (modules call OUI.PP.CreateBorder(frame, r,g,b,a, size)).
OUI.PP = OUI.PP or {}
OUI.PP.CreateBorder = function(frame, r, g, b, a, _size)
    return OUI._border(frame, r or 1, g or 1, b or 1, a or 0.3)
end
OUI.DD_BRD_A = OUI.DD_BRD_A or 0.3

-- ---------------------------------------------------------------------
-- Unlock / mover
-- ---------------------------------------------------------------------
local elements = {}
local overlays = {}
OUI._unlockActive = false

-- Normalize an unlock-element definition. Lean: pass through with defaults.
function OUI.MakeUnlockElement(opts)
    opts = opts or {}
    return opts
end

local function ShowOverlay(el)
    local frame = el.getFrame and el.getFrame()
    if not frame then return end
    local ov = overlays[el]
    if not ov then
        ov = CreateFrame("Frame", nil, UIParent)
        ov:SetFrameStrata("FULLSCREEN")
        ov:EnableMouse(true); ov:SetMovable(true); ov:SetClampedToScreen(true)
        ov._bg = Tex(ov, "BACKGROUND", A()); ov._bg:SetAllPoints(); ov._bg:SetAlpha(0.22)
        OUI.RegAccent({ type = "callback", fn = function(r, g, b) ov._bg:SetColorTexture(r, g, b, 1) end })
        ov._brd = OUI._border(ov, select(1, A()), select(2, A()), select(3, A()), 1)
        OUI.RegAccent({ type = "callback", fn = function(r, g, b) ov._brd:SetColor(r, g, b, 1) end })
        ov._lbl = Lbl(ov, 12, TXT[1], TXT[2], TXT[3]); ov._lbl:SetPoint("CENTER")
        ov:RegisterForDrag("LeftButton")
        ov:SetScript("OnDragStart", function() ov:StartMoving() end)
        ov:SetScript("OnDragStop", function()
            ov:StopMovingOrSizing()
            local ux, uy = UIParent:GetCenter()
            local ox, oy = ov:GetCenter()
            if ux and ox then
                local x = math.floor((ox - ux) + 0.5)
                local y = math.floor((oy - uy) + 0.5)
                if el.savePos then el.savePos(el.getFrame and el.getFrame(), "CENTER", "CENTER", x, y) end
                ov:ClearAllPoints(); ov:SetPoint("CENTER", UIParent, "CENTER", x, y)
            end
        end)
        overlays[el] = ov
    end
    local w, h
    if el.getSize then w, h = el.getSize() end
    ov:SetSize(w or frame:GetWidth() or 100, h or frame:GetHeight() or 24)
    ov:ClearAllPoints(); ov:SetPoint("CENTER", frame, "CENTER")
    ov._lbl:SetText(L(el.label or el.key or "Move"))
    ov:Show()
    return ov
end

function OUI._RefreshUnlockOverlays()
    for _, el in ipairs(elements) do
        if el.isHidden and el.isHidden() then
            if overlays[el] then overlays[el]:Hide() end
        else
            ShowOverlay(el)
        end
    end
end

function OUI:RegisterUnlockElements(list)
    for _, el in ipairs(list or {}) do elements[#elements + 1] = el end
    if OUI._unlockActive then OUI._RefreshUnlockOverlays() end
end

function OUI:ToggleUnlock(on)
    if on == nil then on = not OUI._unlockActive end
    OUI._unlockActive = on
    if on then
        OUI._RefreshUnlockOverlays()
        OUI:Print(L("Unlock mode ON -- drag frames, then /ouimove again to lock."))
    else
        for el, ov in pairs(overlays) do
            ov:Hide()
            if el.applyPos then el.applyPos() end
        end
        OUI:Print(L("Unlock mode OFF -- positions saved."))
    end
end

SLASH_OLDSCHOOLUIMOVE1 = "/ouimove"
SlashCmdList["OLDSCHOOLUIMOVE"] = function() OUI:ToggleUnlock() end

-- Re-assert every registered element's saved position. Some Blizzard frames
-- (minimap cluster, bag bar, ...) are repositioned by Blizzard's own layout
-- pass late in login, after our modules first place them -- this puts them back.
function OUI:ReapplyMoverPositions()
    if OUI._unlockActive or InCombatLockdown() then return end
    for _, el in ipairs(elements) do
        if el.applyPos then pcall(el.applyPos) end
    end
end

local moverLogin = CreateFrame("Frame")
moverLogin:RegisterEvent("PLAYER_ENTERING_WORLD")
moverLogin:SetScript("OnEvent", function()
    if C_Timer and C_Timer.After then
        C_Timer.After(0.5, function() OUI:ReapplyMoverPositions() end)
        C_Timer.After(2.0, function() OUI:ReapplyMoverPositions() end)
    else
        OUI:ReapplyMoverPositions()
    end
end)

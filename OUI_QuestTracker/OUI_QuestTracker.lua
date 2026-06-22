-------------------------------------------------------------------------------
--  OUI_QuestTracker.lua  --  Core (clean-room rewrite for MoP Classic 5.5.x)
--
--  Blizzard's legacy WatchFrame stays the rendering engine; this module only
--  (a) skins its lines, (b) drives its visibility + a themed backdrop, and
--  (c) layers quest QoL (auto-accept / auto-turn-in / quest-item hotkey).
--  Feature files register their Init* + refresh hooks on the QT namespace; the
--  core wires them up once WatchFrame is present.
-------------------------------------------------------------------------------

local ADDON, ns = ...
local OUI = OldschoolUI
if not OUI then return end

local QT = {}
ns.QT = QT
OUI.QuestTracker = QT

local GT = LibStub("AceAddon-3.0"):NewAddon("OldschoolUIQuestTracker", "AceEvent-3.0")

-------------------------------------------------------------------------------
--  Saved settings
-------------------------------------------------------------------------------
local DEFAULTS = {
    profile = {
        enabled           = true,

        -- visibility: always | combat | mouseover | instance | never
        visibility        = "always",
        hideInRaid        = true,        -- hard auto-hide in raid/arena

        -- skinning
        skinHeaders       = true,        -- recolour quest-title lines
        accentHeaders     = true,        -- use the suite accent for titles/label
        titleFontSize     = 12,
        objectiveFontSize = 10,
        titleColor        = { r = 0.85, g = 0.64, b = 0.25 },

        -- backdrop (our own UIParent-parented frame, anchored to the tracker)
        showBackdrop      = true,
        backdrop          = { r = 0.035, g = 0.035, b = 0.035, a = 0.75 },
        showTopLine       = true,

        -- QoL
        autoAccept        = false,
        autoTurnIn        = false,
        autoTurnInShiftSkip = true,
        questItemHotkey   = false,
        questItemKey      = "",

        -- mover position (CENTER/CENTER offset; nil = Blizzard default)
        pos               = nil,
    },
}

local db
function QT.DB()
    if db then return db end
    return DEFAULTS.profile  -- safe fallback before AceDB is ready
end
function QT.Cfg(k) return QT.DB()[k] end
function QT.Set(k, v) QT.DB()[k] = v end

-- live title colour: suite accent when accentHeaders is on, else stored colour
function QT.TitleColor()
    if QT.Cfg("accentHeaders") ~= false and OUI.GetAccentColor then
        local r, g, b = OUI.GetAccentColor()
        if r then return r, g, b end
    end
    local c = QT.Cfg("titleColor") or {}
    return c.r or 0.85, c.g or 0.64, c.b or 0.25
end

function QT.Tracker() return _G.WatchFrame end

-------------------------------------------------------------------------------
--  Cross-module suppression. Other OUI modules (e.g. the Group Timer overlay)
--  call _OUI_SetTrackerSuppressed(key, true) to temporarily hide the tracker;
--  suppression stacks across callers.
-------------------------------------------------------------------------------
local suppressors = {}
function _G._OUI_SetTrackerSuppressed(key, on)
    if not key then return end
    suppressors[key] = on and true or nil
    if QT.UpdateVisibility then QT.UpdateVisibility() end
end
function QT.IsSuppressed() return next(suppressors) ~= nil end

-------------------------------------------------------------------------------
--  Init: wire up the feature files once WatchFrame exists.
-------------------------------------------------------------------------------
local function Init()
    if not _G.WatchFrame then return false end
    if QT.InitSkin       then QT.InitSkin()       end
    if QT.InitVisibility then QT.InitVisibility() end
    if QT.InitQoL        then QT.InitQoL()        end
    if QT.InitMover      then QT.InitMover()      end
    return true
end

-- /ouimove integration: let the WatchFrame be dragged like the suite's own
-- windows. Position is stored in the QT profile and re-anchored on login.
function QT.InitMover()
    local wf = _G.WatchFrame
    if not wf or QT._moverReg then return end
    if not (OUI.RegisterUnlockElements and OUI.MakeUnlockElement) then return end
    QT._moverReg = true

    -- Blizzard's UIParent position manager re-anchors WatchFrame on every layout
    -- pass, snapping our drag back. Take it out of management so our point holds.
    local function freeFromManager()
        wf:SetMovable(true)
        wf.ignoreFramePositionManager = true
        if UIPARENT_MANAGED_FRAME_POSITIONS then
            UIPARENT_MANAGED_FRAME_POSITIONS["WatchFrame"] = nil
        end
    end
    freeFromManager()

    local function apply()
        freeFromManager()
        local pos = QT.DB().trackerPos
        if pos and pos.x then
            wf:ClearAllPoints()
            wf:SetPoint("CENTER", UIParent, "CENTER", pos.x, pos.y)
        end
    end
    OUI:RegisterUnlockElements({ OUI.MakeUnlockElement({
        key = "OUIQuestTracker", label = "Quest Tracker", group = "Quest Tracker", order = 540,
        getFrame = function() return wf end,
        getSize  = function() return math.max(wf:GetWidth() or 0, 160), math.min(math.max(wf:GetHeight() or 0, 60), 320) end,
        isHidden = function() return false end,
        savePos  = function(_, _, _, x, y)
            QT.DB().trackerPos = { x = x, y = y }
            freeFromManager()
            wf:ClearAllPoints()
            wf:SetPoint("CENTER", UIParent, "CENTER", x, y)
        end,
        applyPos = apply,
    }) })
    apply()
end

function GT:OnInitialize()
    db = LibStub("AceDB-3.0"):New("OldschoolUIQuestTrackerDB", DEFAULTS)
    db = db.profile
    _G._OUIQT_DB = db
end

function GT:OnEnable()
    if OUI.IsModuleEnabled and not OUI:IsModuleEnabled("OUI_QuestTracker") then return end
    if not (db and db.enabled) then return end
    if not Init() then
        -- WatchFrame not ready yet -> retry on first world enter
        local f = CreateFrame("Frame")
        f:RegisterEvent("PLAYER_ENTERING_WORLD")
        f:SetScript("OnEvent", function(self)
            if Init() then self:UnregisterAllEvents() end
        end)
    end
end

-- profile-swap / options refresh
function QT.RefreshAll()
    if QT.RestyleAll      then QT.RestyleAll()      end
    if QT.UpdateVisibility then QT.UpdateVisibility() end
    if QT.ApplyBackdrop   then QT.ApplyBackdrop()   end
end
_G._OUIQT_RefreshAll = QT.RefreshAll

-------------------------------------------------------------------------------
--  Slash
-------------------------------------------------------------------------------
SLASH_OUIQT1 = "/ouiqt"
SlashCmdList["OUIQT"] = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "show" then
        QT.Set("enabled", true);  if QT.UpdateVisibility then QT.UpdateVisibility() end
    elseif msg == "hide" then
        QT.Set("enabled", false); if QT.UpdateVisibility then QT.UpdateVisibility() end
    elseif msg == "toggle" then
        QT.Set("enabled", not QT.Cfg("enabled")); if QT.UpdateVisibility then QT.UpdateVisibility() end
    else
        print("|cffD9A441OUI QuestTracker:|r /ouiqt show | hide | toggle")
    end
end

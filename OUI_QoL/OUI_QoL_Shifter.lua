-------------------------------------------------------------------------------
--  OUI_QoL_Shifter.lua -- Shift+drag to permanently reposition Blizzard panels,
--  Ctrl+drag for a temporary move that resets when the panel closes.
--  Shares the OUI_QoL addon namespace/DB.
-------------------------------------------------------------------------------
local _, ns = ...

-- Frames available at login (MoP-valid).
local PRELOADED = {
    "CharacterFrame", "FriendsFrame", "PVEFrame", "DressUpFrame", "BankFrame",
    "MailFrame", "GossipFrame", "MerchantFrame", "AddonList", "ChatConfigFrame",
    "ItemTextFrame", "TabardFrame", "GuildRegistrarFrame", "QuestLogFrame",
}

-- Load-on-demand frames keyed by the addon that creates them (MoP-valid).
local ADDON_FRAMES = {
    Blizzard_AchievementUI    = { "AchievementFrame" },
    Blizzard_AuctionUI        = { "AuctionFrame" },
    Blizzard_AuctionHouseUI   = { "AuctionHouseFrame" },
    Blizzard_BlackMarketUI    = { "BlackMarketFrame" },
    Blizzard_Calendar         = { "CalendarFrame" },
    Blizzard_Collections      = { "CollectionsJournal" },
    Blizzard_EncounterJournal = { "EncounterJournal" },
    Blizzard_GuildBankUI      = { "GuildBankFrame" },
    Blizzard_GuildUI          = { "GuildFrame" },
    Blizzard_InspectUI        = { "InspectFrame" },
    Blizzard_ItemSocketingUI  = { "ItemSocketingFrame" },
    Blizzard_MacroUI          = { "MacroFrame" },
    Blizzard_TalentUI         = { "PlayerTalentFrame" },
    Blizzard_TrainerUI        = { "ClassTrainerFrame" },
    Blizzard_TradeSkillUI     = { "TradeSkillFrame" },
    Blizzard_GuildControlUI   = { "GuildControlUI" },
}

local DRAG_HEADERS = {
    AchievementFrame = "AchievementFrameHeader",
}

local function enabled() return ns.db and ns.db.profile.shifter end

local function savedPos(name)
    local t = ns.db.profile.shifterPositions
    return t and t[name]
end

local function savePos(name, point, relPoint, x, y)
    ns.db.profile.shifterPositions = ns.db.profile.shifterPositions or {}
    ns.db.profile.shifterPositions[name] = { point = point, rel = relPoint, x = x, y = y }
end

local function applyPos(frame, name)
    local p = savedPos(name)
    if not p then return end
    frame:ClearAllPoints()
    frame:SetPoint(p.point, UIParent, p.rel or p.point, p.x or 0, p.y or 0)
end

local hooked = {}

local function hookFrame(frame, name)
    if not frame or hooked[name] then return end
    hooked[name] = true

    if not (InCombatLockdown() and frame:IsProtected()) then
        frame:SetMovable(true)
        frame:SetClampedToScreen(true)
    end

    local target = (DRAG_HEADERS[name] and _G[DRAG_HEADERS[name]]) or frame
    local mode  -- "save" | "temp" | nil

    target:HookScript("OnMouseDown", function(_, button)
        if not enabled() or button ~= "LeftButton" then return end
        if InCombatLockdown() and frame:IsProtected() then return end
        if IsShiftKeyDown() then mode = "save"
        elseif IsControlKeyDown() then mode = "temp"
        else return end
        frame:SetMovable(true)
        frame:StartMoving()
    end)

    target:HookScript("OnMouseUp", function(_, button)
        if button ~= "LeftButton" or not mode then return end
        frame:StopMovingOrSizing()
        local p, _, rp, x, y = frame:GetPoint(1)
        if p and mode == "save" then savePos(name, p, rp, x, y) end
        mode = nil
    end)

    -- restore on show (permanent positions only)
    frame:HookScript("OnShow", function(self) if enabled() then applyPos(self, name) end end)

    applyPos(frame, name)
end

local function hookAllPreloaded()
    for _, name in ipairs(PRELOADED) do
        local f = _G[name]
        if f then hookFrame(f, name) end
    end
end

function ns.ResetShifterPositions()
    ns.db.profile.shifterPositions = {}
end

function ns.SetupShifter()
    if ns._shifterFrame then hookAllPreloaded(); return end
    hookAllPreloaded()
    local ev = CreateFrame("Frame")
    ns._shifterFrame = ev
    ev:RegisterEvent("ADDON_LOADED")
    ev:SetScript("OnEvent", function(_, _, addon)
        local list = ADDON_FRAMES[addon]
        if not list then return end
        for _, fname in ipairs(list) do
            local f = _G[fname]
            if f then hookFrame(f, fname) end
        end
    end)
end

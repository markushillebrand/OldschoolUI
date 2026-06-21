-- ===========================================================================
--  OldschoolUI -- Chat  CH-2: idle fade
--  Fades the chat (frames, tabs, dock, backdrops) to a low alpha after a delay
--  of inactivity, and restores it on mouseover, edit-box focus, a new message,
--  or (optionally) while in combat. Clean-room rewrite.
-- ===========================================================================
local ADDON, ns = ...
local OUI = OldschoolUI
if not OUI then return end

local cfg = ns.cfg
local eachChatFrame = ns.eachChatFrame
if not (cfg and eachChatFrame) then return end

local FADE_SPEED = 3   -- alpha units per second while animating

local fade = { current = 1, target = 1, idle = 0 }

local function idleAlpha()
    local s = math.min(cfg("idleFadeStrength") or 40, 99)
    return 1 - (s / 100)
end

-- ---------------------------------------------------------------------------
--  Apply an alpha to every visible chat element
-- ---------------------------------------------------------------------------
local function applyAlpha(a)
    eachChatFrame(function(cf)
        if cf:IsShown() then cf:SetAlpha(a) end
        local tab = _G[(cf:GetName() or "") .. "Tab"]
        if tab then tab:SetAlpha(a) end
        if cf._ouiBackdrop and cf._ouiBackdrop:IsShown() then cf._ouiBackdrop:SetAlpha(a) end
        local eb = cf.editBox
        if eb and eb._ouiBackdrop then eb._ouiBackdrop:SetAlpha(a) end
    end)
    if GeneralDockManager then GeneralDockManager:SetAlpha(a) end
end

-- ---------------------------------------------------------------------------
--  "Is the player interacting with the chat right now?"
-- ---------------------------------------------------------------------------
local function editBoxActive()
    local active = false
    eachChatFrame(function(cf)
        local eb = cf.editBox
        if eb and eb:IsShown() and eb.HasFocus and eb:HasFocus() then active = true end
    end)
    return active
end

local function isOverChat()
    local sel = SELECTED_CHAT_FRAME
    -- pad the selected frame's hit area to cover the tabs (above) and the edit
    -- box (below) so hovering those keeps the chat visible.
    if sel and sel:IsShown() and sel:IsMouseOver(28, -34, -6, 6) then return true end
    if GeneralDockManager and GeneralDockManager:IsMouseOver() then return true end
    local over = false
    eachChatFrame(function(cf)
        if not over and cf:IsShown() and cf:IsMouseOver(4, -4, -4, 4) then over = true end
        local tab = _G[(cf:GetName() or "") .. "Tab"]
        if not over and tab and tab:IsShown() and tab:IsMouseOver() then over = true end
    end)
    return over
end

local function awake()
    return isOverChat()
        or editBoxActive()
        or (cfg("fadeStayInCombat") and InCombatLockdown())
end

-- ---------------------------------------------------------------------------
--  Reset to full visibility (new message / activity)
-- ---------------------------------------------------------------------------
local function resetIdle()
    fade.idle = 0
    fade.target = 1
end
ns.ChatActivity = resetIdle

-- ---------------------------------------------------------------------------
--  Driver
-- ---------------------------------------------------------------------------
local driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function(self, elapsed)
    self.acc = (self.acc or 0) + elapsed
    if self.acc < 0.05 then return end
    local step = self.acc; self.acc = 0

    if not cfg("idleFadeEnabled") then
        if fade.current ~= 1 then fade.current = 1; fade.target = 1; applyAlpha(1) end
        return
    end

    if awake() then
        fade.idle = 0
        fade.target = 1
    else
        fade.idle = fade.idle + step
        if fade.idle >= (cfg("idleFadeDelay") or 15) then
            fade.target = idleAlpha()
        end
    end

    if math.abs(fade.current - fade.target) > 0.01 then
        local dir = (fade.target > fade.current) and 1 or -1
        fade.current = fade.current + dir * step * FADE_SPEED
        if (dir > 0 and fade.current > fade.target) or (dir < 0 and fade.current < fade.target) then
            fade.current = fade.target
        end
        applyAlpha(fade.current)
    end
end)

-- ---------------------------------------------------------------------------
--  Activity hooks
-- ---------------------------------------------------------------------------
local function hookFrameActivity(cf)
    if cf._ouiFadeHook then return end
    cf._ouiFadeHook = true
    hooksecurefunc(cf, "AddMessage", resetIdle)
    if cf.editBox then
        cf.editBox:HookScript("OnEditFocusGained", resetIdle)
    end
end

function ns.StartChatFade()
    eachChatFrame(hookFrameActivity)
    if not ns._fadeTempHook then
        ns._fadeTempHook = true
        hooksecurefunc("FCF_OpenTemporaryWindow", function()
            local id = FCF_GetCurrentChatFrameID and FCF_GetCurrentChatFrameID() or 1
            local cf = _G["ChatFrame" .. id]
            if cf then hookFrameActivity(cf) end
        end)
    end
    fade.current, fade.target, fade.idle = 1, 1, 0
    applyAlpha(1)
    driver:Show()
end

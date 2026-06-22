-------------------------------------------------------------------------------
--  OUI_QuestTracker_QoL.lua  --  Quest quality-of-life (clean-room, MoP 5.5.x)
--
--    * auto-accept       (QUEST_DETAIL / gossip / greeting)
--    * auto-turn-in      (QUEST_PROGRESS / QUEST_COMPLETE / gossip / greeting)
--    * quest-item hotkey (SecureActionButton + SecureHandlerAttributeTemplate)
--    * SplashFrame OnHide guard (no-op unless the frame exists)
--
--  MoP Classic exposes the legacy gossip/quest API; modern C_* paths are used
--  when present and fall back to the classic globals otherwise. Quest accept /
--  turn-in functions are not combat-protected; the hotkey binding work IS, and
--  is therefore strictly gated behind InCombatLockdown + PLAYER_REGEN_ENABLED.
-------------------------------------------------------------------------------

local ADDON, ns = ...
local OUI = OldschoolUI
local QT = ns.QT
if not QT then return end

local After = (C_Timer and C_Timer.After) or function(_, f) if f then f() end end
local function Cfg(k) return QT.Cfg(k) end

-------------------------------------------------------------------------------
--  Auto-accept / auto-turn-in
-------------------------------------------------------------------------------
local function TurnInSingleReward()
    local n = (GetNumQuestChoices and GetNumQuestChoices()) or 0
    if n <= 1 then GetQuestReward(n) end   -- only auto-claim when there's no choice
end

local function GossipTurnIn()
    -- modern API first
    if C_GossipInfo and C_GossipInfo.GetActiveQuests and C_GossipInfo.SelectActiveQuest then
        local active = C_GossipInfo.GetActiveQuests()
        if active then
            for _, q in ipairs(active) do
                if q.questID and q.isComplete then C_GossipInfo.SelectActiveQuest(q.questID); return true end
            end
        end
        return false
    end
    -- classic positional API: complete flag is the 4th field of each entry
    if GetNumGossipActiveQuests and SelectGossipActiveQuest then
        local n = GetNumGossipActiveQuests() or 0
        if n > 0 then
            local data = { GetGossipActiveQuests() }
            local per = #data / n
            if per >= 1 and per == math.floor(per) then
                for i = 1, n do
                    if data[(i - 1) * per + 4] then SelectGossipActiveQuest(i); return true end
                end
            end
        end
    end
    return false
end

local function GossipAccept()
    if C_GossipInfo and C_GossipInfo.GetAvailableQuests and C_GossipInfo.SelectAvailableQuest then
        local avail = C_GossipInfo.GetAvailableQuests()
        if avail and avail[1] and avail[1].questID then
            C_GossipInfo.SelectAvailableQuest(avail[1].questID); return true
        end
        return false
    end
    if GetNumGossipAvailableQuests and SelectGossipAvailableQuest then
        if (GetNumGossipAvailableQuests() or 0) > 0 then SelectGossipAvailableQuest(1); return true end
    end
    return false
end

local function ShiftSkip()
    return Cfg("autoTurnInShiftSkip") and IsShiftKeyDown and IsShiftKeyDown()
end

local function InstallAutoQuests()
    local f = CreateFrame("Frame")
    f:RegisterEvent("QUEST_DETAIL")
    f:RegisterEvent("QUEST_PROGRESS")
    f:RegisterEvent("QUEST_COMPLETE")
    f:RegisterEvent("QUEST_GREETING")
    f:RegisterEvent("GOSSIP_SHOW")
    f:SetScript("OnEvent", function(_, event)
        if Cfg("enabled") == false then return end
        local accept  = Cfg("autoAccept")
        local turnIn  = Cfg("autoTurnIn")

        if event == "QUEST_DETAIL" then
            if accept then AcceptQuest() end

        elseif event == "QUEST_PROGRESS" then
            if turnIn and not ShiftSkip() and IsQuestCompletable and IsQuestCompletable() then
                CompleteQuest()
            end

        elseif event == "QUEST_COMPLETE" then
            if turnIn and not ShiftSkip() then TurnInSingleReward() end

        elseif event == "QUEST_GREETING" then
            -- multi-quest NPC (non-gossip): turn in completed, then accept
            if turnIn and not ShiftSkip() and GetNumActiveQuests and SelectActiveQuest then
                for i = 1, (GetNumActiveQuests() or 0) do
                    local _, isComplete = GetActiveTitle and GetActiveTitle(i)
                    -- some clients omit the complete flag here; selecting fires
                    -- QUEST_PROGRESS which then gates on IsQuestCompletable
                    if isComplete then SelectActiveQuest(i); return end
                end
            end
            if accept and GetNumAvailableQuests and SelectAvailableQuest then
                if (GetNumAvailableQuests() or 0) > 0 then SelectAvailableQuest(1) end
            end

        elseif event == "GOSSIP_SHOW" then
            if turnIn and not ShiftSkip() and GossipTurnIn() then return end
            if accept then GossipAccept() end
        end
    end)
end

-------------------------------------------------------------------------------
--  Quest-item hotkey
--
--  A hidden SecureActionButton whose "item" attribute tracks the current
--  watched quest item. A SecureHandlerAttributeTemplate snippet re-binds the
--  configured key to the button inside the restricted environment whenever the
--  item changes, so the key-flip never taints. All insecure binding work is
--  done out of combat only.
-------------------------------------------------------------------------------
local function ScanForQuestItem()
    local num = (GetNumQuestLogEntries and GetNumQuestLogEntries()) or 0
    for i = 1, num do
        local title, _, _, isHeader = GetQuestLogTitle and GetQuestLogTitle(i)
        if title and not isHeader and GetQuestLogSpecialItemInfo then
            local link = GetQuestLogSpecialItemInfo(i)
            if link then
                local name = link:match("%[(.-)%]")
                if name then return name end
            end
        end
    end
    return nil
end

local function InstallQuestItemHotkey()
    local btn = CreateFrame("Button", "OUI_QuestItemHotkeyBtn", UIParent,
        "SecureActionButtonTemplate, SecureHandlerAttributeTemplate")
    btn:SetSize(32, 32)
    btn:SetPoint("CENTER")
    btn:SetAlpha(0)
    btn:EnableMouse(false)
    btn:RegisterForClicks("AnyUp")
    QT.questItemBtn = btn

    local function InitSecure()
        btn:SetAttribute("type", "item")
        -- restricted-env: on item change, rebind the configured key to us
        btn:SetAttribute("_onattributechanged", [[
            if name == 'item' then
                self:ClearBindings()
                if value then
                    local k1, k2 = GetBindingKey('OUI_QUESTITEM')
                    if k1 then self:SetBindingClick(false, k1, self, 'LeftButton') end
                    if k2 then self:SetBindingClick(false, k2, self, 'LeftButton') end
                end
            end
        ]])
    end
    if InCombatLockdown() then
        local wait = CreateFrame("Frame")
        wait:RegisterEvent("PLAYER_REGEN_ENABLED")
        wait:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents(); InitSecure()
            if QT.ApplyQuestItemBinding then QT.ApplyQuestItemBinding() end
            if QT.RefreshQuestItem    then QT.RefreshQuestItem()    end
        end)
    else
        InitSecure()
    end

    _G["BINDING_NAME_OUI_QUESTITEM"] = "Use Quest Item"

    -- bind / unbind the configured key to the OUI_QUESTITEM action
    local applying = false
    function QT.ApplyQuestItemBinding()
        if InCombatLockdown() or applying then return end
        applying = true
        local ok, err = pcall(function()
            local key      = Cfg("questItemKey")
            local enabled  = Cfg("questItemHotkey")
            local old1, old2 = GetBindingKey("OUI_QUESTITEM")
            local changed = false

            -- clear stale bindings
            if old1 and (not enabled or old1 ~= key) then SetBinding(old1); changed = true end
            if old2 and (not enabled or old2 ~= key) then SetBinding(old2); changed = true end
            -- set the new binding
            if enabled and key and key ~= "" and old1 ~= key and old2 ~= key then
                SetBinding(key, "OUI_QUESTITEM"); changed = true
            end
            if changed then
                local set = GetCurrentBindingSet()
                if set and set >= 1 and set <= 2 then SaveBindings(set) end
            end
            -- nudge the secure snippet to re-evaluate
            local cur = btn:GetAttribute("item")
            btn:SetAttribute("item", nil)
            btn:SetAttribute("item", cur)
        end)
        applying = false
        if not ok and err then geterrorhandler()(err) end
    end

    -- refresh the tracked item attribute
    local cached, dirty = nil, true
    function QT.RefreshQuestItem()
        if InCombatLockdown() or not dirty then return end
        dirty = false
        local found = Cfg("questItemHotkey") and ScanForQuestItem() or nil
        if found ~= cached then
            cached = found
            btn:SetAttribute("item", found)
        end
    end

    local drv = CreateFrame("Frame")
    drv:RegisterEvent("QUEST_LOG_UPDATE")
    drv:RegisterEvent("QUEST_ACCEPTED")
    drv:RegisterEvent("QUEST_REMOVED")
    drv:RegisterEvent("QUEST_TURNED_IN")
    drv:RegisterEvent("UPDATE_BINDINGS")
    drv:RegisterEvent("PLAYER_REGEN_ENABLED")
    drv:SetScript("OnEvent", function(_, event)
        if InCombatLockdown() then return end
        if event == "PLAYER_REGEN_ENABLED" then
            QT.ApplyQuestItemBinding(); dirty = true; QT.RefreshQuestItem(); return
        elseif event == "UPDATE_BINDINGS" then
            local cur = btn:GetAttribute("item")
            btn:SetAttribute("item", nil); btn:SetAttribute("item", cur); return
        end
        dirty = true
        QT.RefreshQuestItem()
    end)

    After(1.5, function()
        if InCombatLockdown() then return end
        QT.ApplyQuestItemBinding(); QT.RefreshQuestItem()
    end)
end

-------------------------------------------------------------------------------
--  SplashFrame guard (retail-era frame; usually absent on MoP -> no-op)
-------------------------------------------------------------------------------
local function InstallSplashGuard()
    local sf = _G.SplashFrame
    if not sf or not sf.SetScript then return end
    sf:HookScript("OnHide", function()
        if _G.AlertFrame and _G.AlertFrame.SetAlertsEnabled then
            _G.AlertFrame:SetAlertsEnabled(true, "splashFrame")
        end
    end)
end

-------------------------------------------------------------------------------
function QT.InitQoL()
    InstallAutoQuests()
    InstallQuestItemHotkey()
    InstallSplashGuard()
end

-- ===========================================================================
--  OldschoolUI -- Friends  FR-1: core window + list
--  A clean, movable friends panel listing online WoW and Battle.net friends
--  with class-colored names, status and location. Clean-room rewrite of the
--  original dev friends module.
-- ===========================================================================
local ADDON, ns = ...
local OUI = OldschoolUI
if not OUI then return end

local FR = LibStub("AceAddon-3.0"):NewAddon("OldschoolUIFriends", "AceEvent-3.0")
ns.FR = FR

local defaults = {
    profile = {
        enabled = true,
        point = "CENTER", relPoint = "CENTER", x = 0, y = 0,
        width = 320, height = 420,
        scale = 1.0,
        bgColor = { r = 0.05, g = 0.05, b = 0.05, a = 0.92 },
        showBorder = true,
        borderColor = { r = 0.067, g = 0.067, b = 0.067 },
        showOffline = false,
        classColorNames = true,
        showClassIcons = true,
        showFactionIcons = true,
        accentHeader = true,
        groupByRealm = true,
        collapsedRealms = {},
        autoAcceptFriendInvites = false,
        autoShow = false,
        replaceBlizzard = true,
        showIgnoredTab = true,
        showWhoTab = true,
    },
}

local function cfg(k) return ns.db and ns.db.profile[k] end
ns.cfg = cfg

local function fontPath() return (OUI.GetFontPath and OUI.GetFontPath()) or STANDARD_TEXT_FONT end
local function L(s) return (OUI.L and OUI.L(s)) or s end

local ROW_H = 30

-- localized class name -> token, for class coloring
local CLASS_TOKEN = {}
do
    for token, name in pairs(LOCALIZED_CLASS_NAMES_MALE or {}) do CLASS_TOKEN[name] = token end
    for token, name in pairs(LOCALIZED_CLASS_NAMES_FEMALE or {}) do CLASS_TOKEN[name] = token end
end
local function classColor(localizedClass)
    local token = localizedClass and CLASS_TOKEN[localizedClass]
    local c = token and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[token]
    if c then return c.r, c.g, c.b end
    return 1, 0.82, 0
end

local STATUS_COLOR = {
    online = { 0.35, 0.85, 0.42 },
    afk    = { 0.95, 0.80, 0.30 },
    dnd    = { 0.85, 0.30, 0.30 },
    offline = { 0.45, 0.45, 0.45 },
}

local FACTION_ICON = {
    Alliance = "Interface\\PVPFrame\\PVP-Currency-Alliance",
    Horde    = "Interface\\PVPFrame\\PVP-Currency-Horde",
}

local function setClassIcon(tex, localizedClass)
    local token = localizedClass and CLASS_TOKEN[localizedClass]
    local co = token and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[token]
    if co then tex:SetTexCoord(co[1], co[2], co[3], co[4]); return true end
    return false
end

-- ---------------------------------------------------------------------------
--  Gather friends (WoW + Battle.net) into a unified, sorted list
-- ---------------------------------------------------------------------------
local function gather()
    local list = {}
    local showOff = cfg("showOffline")

    if C_FriendList and C_FriendList.GetNumFriends then
        for i = 1, C_FriendList.GetNumFriends() do
            local info = C_FriendList.GetFriendInfoByIndex(i)
            if info and (info.connected or showOff) then
                list[#list + 1] = {
                    online = info.connected and true or false,
                    name = info.name,
                    level = info.level,
                    class = info.className,
                    zone = info.area,
                    status = info.afk and "afk" or info.dnd and "dnd" or (info.connected and "online" or "offline"),
                    note = info.notes,
                    bnet = false,
                }
            end
        end
    end

    if BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendAccountInfo then
        for i = 1, BNGetNumFriends() do
            local acc = C_BattleNet.GetFriendAccountInfo(i)
            local g = acc and acc.gameAccountInfo
            local online = (g and g.isOnline) and true or false
            if acc and (online or showOff) then
                list[#list + 1] = {
                    online = online,
                    account = acc.accountName,
                    name = g and g.characterName,
                    level = g and (g.characterLevel or g.level),
                    class = g and g.className,
                    zone = g and g.areaName,
                    realm = g and g.realmName,
                    faction = g and g.factionName,
                    client = g and g.clientProgram,
                    bnetID = acc.bnetAccountID,
                    gameID = g and g.gameAccountID,
                    note = acc.note,
                    broadcast = acc.customMessage,
                    status = (acc.isAFK or (g and g.isGameAFK)) and "afk"
                          or (acc.isDND or (g and g.isGameBusy)) and "dnd"
                          or (online and "online" or "offline"),
                    bnet = true,
                }
            end
        end
    end

    table.sort(list, function(a, b)
        if a.online ~= b.online then return a.online end
        local an = (a.account or a.name or ""):lower()
        local bn = (b.account or b.name or ""):lower()
        return an < bn
    end)
    return list
end

-- Ignored / blocked list (characters via C_FriendList, BNet blocks best-effort)
local function gatherIgnored()
    local list = {}
    if C_FriendList and C_FriendList.GetNumIgnores then
        for i = 1, C_FriendList.GetNumIgnores() do
            local name = C_FriendList.GetIgnoreName(i)
            if name and name ~= "" and name ~= UNKNOWNOBJECT then
                list[#list + 1] = { name = name, ignored = true, bnet = false }
            end
        end
    end
    if BNGetNumBlocked and BNGetBlockedInfo then
        for i = 1, BNGetNumBlocked() do
            local ok, a1, a2 = pcall(BNGetBlockedInfo, i)
            if ok then
                -- account name + id ordering varies; pick the string + numeric id
                local nm = (type(a1) == "string" and a1) or (type(a2) == "string" and a2)
                local id = (type(a1) == "number" and a1) or (type(a2) == "number" and a2)
                if nm then list[#list + 1] = { account = nm, bnetID = id, ignored = true, bnet = true } end
            end
        end
    end
    table.sort(list, function(a, b)
        return ((a.account or a.name or ""):lower()) < ((b.account or b.name or ""):lower())
    end)
    return list
end

-- ---------------------------------------------------------------------------
--  Window
-- ---------------------------------------------------------------------------
local win
-- ---------------------------------------------------------------------------
--  FR-5: friend actions (whisper / invite / note / remove) + add-friend
-- ---------------------------------------------------------------------------
local function inviteName(e)
    local n = e.name
    if not n or n == "" then return nil end
    if e.bnet and e.realm and e.realm ~= "" then n = n .. "-" .. e.realm:gsub("%s+", "") end
    return n
end

local function actWhisper(e)
    if e.bnet and (not e.name or e.name == "") then
        if e.account and ChatFrame_SendBNetTell then ChatFrame_SendBNetTell(e.account) end
        return
    end
    local n = inviteName(e)
    if n and ChatFrame_SendTell then ChatFrame_SendTell(n) end
end

local function actInvite(e)
    local n = inviteName(e)
    if not n then return end
    if C_PartyInfo and C_PartyInfo.InviteUnit then C_PartyInfo.InviteUnit(n)
    elseif InviteUnit then InviteUnit(n) end
end

local function actRemove(e)
    if e.bnet then
        if e.bnetID and BNRemoveFriend then pcall(BNRemoveFriend, e.bnetID) end
    elseif e.name and C_FriendList and C_FriendList.RemoveFriend then
        pcall(C_FriendList.RemoveFriend, e.name)
    end
    ns.RefreshFriends()
end

local function actSetNote(e, note)
    if e.bnet then
        if e.bnetID and BNSetFriendNote then pcall(BNSetFriendNote, e.bnetID, note) end
    elseif e.name and C_FriendList and C_FriendList.SetFriendNotes then
        pcall(C_FriendList.SetFriendNotes, e.name, note)
    end
    ns.RefreshFriends()
end

local function addFriend(text)
    text = text and text:gsub("^%s+", ""):gsub("%s+$", "")
    if not text or text == "" then return end
    if text:find("#") or text:find("@") then
        if BNSendFriendInvite then pcall(BNSendFriendInvite, text) end
    elseif C_FriendList and C_FriendList.AddFriend then
        pcall(C_FriendList.AddFriend, text)
    end
end

local function actUnignore(e)
    if e.bnet then
        if e.bnetID and BNSetBlocked then pcall(BNSetBlocked, e.bnetID, false) end
    elseif e.name then
        if C_FriendList and C_FriendList.DelIgnore then pcall(C_FriendList.DelIgnore, e.name)
        elseif C_FriendList and C_FriendList.AddOrDelIgnore then pcall(C_FriendList.AddOrDelIgnore, e.name) end
    end
    ns.RefreshFriends()
end

local function addIgnore(text)
    text = text and text:gsub("^%s+", ""):gsub("%s+$", "")
    if not text or text == "" then return end
    if C_FriendList and C_FriendList.AddIgnore then pcall(C_FriendList.AddIgnore, text)
    elseif C_FriendList and C_FriendList.AddOrDelIgnore then pcall(C_FriendList.AddOrDelIgnore, text) end
end

-- /who search (results arrive via WHO_LIST_UPDATE)
local function runWho(filter)
    filter = filter and filter:gsub("^%s+", ""):gsub("%s+$", "")
    if SetWhoToUI then pcall(SetWhoToUI, 1) end
    if C_FriendList and C_FriendList.SendWho then pcall(C_FriendList.SendWho, filter or "")
    elseif SendWho then pcall(SendWho, filter or "") end
end

local function readWho()
    local results = {}
    local n = 0
    if C_FriendList and C_FriendList.GetNumWhoResults then n = C_FriendList.GetNumWhoResults()
    elseif GetNumWhoResults then n = GetNumWhoResults() end
    for i = 1, (n or 0) do
        if C_FriendList and C_FriendList.GetWhoInfo then
            local info = C_FriendList.GetWhoInfo(i)
            if info then
                results[#results + 1] = {
                    name = info.fullName, level = info.level, class = info.classStr,
                    race = info.raceStr, zone = info.area, guild = info.fullGuildName,
                    online = true, status = "online", who = true,
                }
            end
        elseif GetWhoInfo then
            local name, guild, level, race, class, zone = GetWhoInfo(i)
            results[#results + 1] = {
                name = name, level = level, class = class, race = race, zone = zone,
                guild = guild, online = true, status = "online", who = true,
            }
        end
    end
    return results
end
ns.ReadWho = readWho

StaticPopupDialogs["OUIFRIENDS_NOTE"] = {
    text = L("Note for %s:"), button1 = ACCEPT, button2 = CANCEL,
    hasEditBox = true, editBoxWidth = 260, maxLetters = 48,
    OnShow = function(self)
        local eb = self.EditBox or self.editBox
        local d = self.data
        if d and eb then eb:SetText(d.note or ""); eb:HighlightText() end
    end,
    OnAccept = function(self)
        local eb = self.EditBox or self.editBox
        local d = self.data
        if d and eb then actSetNote(d.e, eb:GetText()) end
    end,
    EditBoxOnEnterPressed = function(self)
        local p = self:GetParent(); local d = p.data
        if d then actSetNote(d.e, self:GetText()) end; p:Hide()
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}
StaticPopupDialogs["OUIFRIENDS_REMOVE"] = {
    text = L("Remove %s from your friends list?"), button1 = YES, button2 = NO,
    OnAccept = function(self) local d = self.data; if d then actRemove(d.e) end end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-- right-click context menu (custom, lightweight)
local menu
local function showContextMenu(e)
    if not menu then
        menu = CreateFrame("Frame", "OUIFriendsContextMenu", UIParent)
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetSize(160, 10)
        menu.bg = menu:CreateTexture(nil, "BACKGROUND")
        menu.bg:SetAllPoints()
        menu.bg:SetColorTexture(0.05, 0.05, 0.05, 0.96)
        if OUI.PP and OUI.PP.CreateBorder then OUI.PP.CreateBorder(menu, 0.067, 0.067, 0.067, 1) end
        menu.items = {}
        local c = CreateFrame("Button", nil, UIParent)
        c:SetAllPoints(UIParent)
        c:SetFrameStrata("FULLSCREEN")
        c:Hide()
        c:SetScript("OnClick", function() menu:Hide() end)
        c:SetScript("OnMouseDown", function() menu:Hide() end)
        menu.closer = c
        menu:SetScript("OnShow", function() menu.closer:Show() end)
        menu:SetScript("OnHide", function() menu.closer:Hide() end)
    end

    local actions
    if e.ignored then
        actions = { { text = L("Remove from Ignore"), fn = function() actUnignore(e) end } }
    elseif e.who then
        actions = { { text = L("Whisper"), fn = function() actWhisper(e) end } }
        actions[#actions + 1] = { text = L("Invite to Group"), fn = function() actInvite(e) end }
        actions[#actions + 1] = { text = L("Add Friend"), fn = function() addFriend(e.name); ns.RefreshFriends() end }
    else
        actions = { { text = L("Whisper"), fn = function() actWhisper(e) end } }
        if e.name and e.name ~= "" then
            actions[#actions + 1] = { text = L("Invite to Group"), fn = function() actInvite(e) end }
        end
        actions[#actions + 1] = { text = L("Edit Note"), fn = function()
            StaticPopup_Show("OUIFRIENDS_NOTE", e.name or e.account, nil, { e = e, note = e.note }) end }
        actions[#actions + 1] = { text = L("Remove Friend"), fn = function()
            StaticPopup_Show("OUIFRIENDS_REMOVE", e.name or e.account, nil, { e = e }) end }
    end

    for _, b in ipairs(menu.items) do b:Hide() end
    local y = -6
    for i, a in ipairs(actions) do
        local b = menu.items[i]
        if not b then
            b = CreateFrame("Button", nil, menu)
            b:SetHeight(20)
            b.t = b:CreateFontString(nil, "OVERLAY")
            b.t:SetFont(fontPath(), 12, "")
            b.t:SetPoint("LEFT", 8, 0)
            b.t:SetJustifyH("LEFT")
            b.hl = b:CreateTexture(nil, "HIGHLIGHT")
            b.hl:SetAllPoints()
            b.hl:SetColorTexture(1, 1, 1, 0.08)
            menu.items[i] = b
        end
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", 4, y)
        b:SetPoint("TOPRIGHT", -4, y)
        b.t:SetText(a.text)
        b.t:SetTextColor(1, 1, 1)
        b:SetScript("OnClick", function() a.fn(); menu:Hide() end)
        b:Show()
        y = y - 20
    end
    menu:SetHeight(-y + 6)
    menu:ClearAllPoints()
    local scale = menu:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cx / scale, cy / scale)
    menu:Show()
end

local function makeRow(parent)
    local r = CreateFrame("Button", nil, parent)
    r:SetHeight(ROW_H)

    r.arrow = r:CreateFontString(nil, "OVERLAY")
    r.arrow:SetFont(fontPath(), 12, "OUTLINE")
    r.arrow:SetPoint("LEFT", 6, 0)
    r.arrow:Hide()

    r.dot = r:CreateTexture(nil, "ARTWORK")
    r.dot:SetSize(8, 8)
    r.dot:SetPoint("LEFT", 4, 0)
    r.dot:SetColorTexture(1, 1, 1, 1)

    r.classIcon = r:CreateTexture(nil, "ARTWORK")
    r.classIcon:SetSize(16, 16)
    r.classIcon:SetPoint("LEFT", 16, 0)
    r.classIcon:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
    r.classIcon:Hide()

    r.faction = r:CreateTexture(nil, "ARTWORK")
    r.faction:SetSize(14, 14)
    r.faction:SetPoint("RIGHT", -4, 0)
    r.faction:Hide()

    r.name = r:CreateFontString(nil, "OVERLAY")
    r.name:SetFont(fontPath(), 12, "")
    r.name:SetPoint("TOPLEFT", 18, -3)
    r.name:SetJustifyH("LEFT")

    r.info = r:CreateFontString(nil, "OVERLAY")
    r.info:SetFont(fontPath(), 10, "")
    r.info:SetPoint("BOTTOMLEFT", 18, 3)
    r.info:SetJustifyH("LEFT")
    r.info:SetTextColor(0.6, 0.6, 0.6)

    r.hl = r:CreateTexture(nil, "HIGHLIGHT")
    r.hl:SetAllPoints()
    r.hl:SetColorTexture(1, 1, 1, 0.06)

    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r:SetScript("OnEnter", function(self)
        local e = self.entry
        if not e then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if e.bnet then
            GameTooltip:AddLine(e.account or "?", 0.51, 0.77, 1)
            if e.name and e.name ~= "" then
                local cr, cg, cb = classColor(e.class)
                local line = e.name
                if e.realm and e.realm ~= "" then line = line .. " - " .. e.realm end
                GameTooltip:AddLine(line, cr, cg, cb)
            end
        else
            local cr, cg, cb = classColor(e.class)
            GameTooltip:AddLine(e.name or "?", cr, cg, cb)
        end
        if e.level and e.level > 0 then
            GameTooltip:AddLine("Level " .. e.level .. (e.class and (" " .. e.class) or ""), 0.8, 0.8, 0.8)
        end
        if e.zone and e.zone ~= "" then GameTooltip:AddLine(e.zone, 0.6, 0.6, 0.6) end
        if e.broadcast and e.broadcast ~= "" then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(e.broadcast, 0.5, 0.77, 1, true)
        end
        if e.note and e.note ~= "" then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L("Note: ") .. e.note, 1, 0.82, 0, true)
        end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r:SetScript("OnClick", function(self, button)
        if self.isHeader then
            if self.realm then
                local col = ns.db.profile.collapsedRealms
                col[self.realm] = (not col[self.realm]) or nil
                ns.RefreshFriends()
            end
        elseif button == "RightButton" and self.entry then
            showContextMenu(self.entry)
        end
    end)

    return r
end

local function buildWindow()
    if win then return win end
    local f = CreateFrame("Frame", "OUIFriendsFrame", UIParent)
    f:SetSize(cfg("width") or 320, cfg("height") or 420)
    f:SetScale(cfg("scale") or 1)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:Hide()

    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    if OUI.PP and OUI.PP.CreateBorder then OUI.PP.CreateBorder(f, 0.067, 0.067, 0.067, 1) end

    -- header / drag handle
    local hd = CreateFrame("Frame", nil, f)
    hd:SetPoint("TOPLEFT", 0, 0)
    hd:SetPoint("TOPRIGHT", 0, 0)
    hd:SetHeight(26)
    hd:EnableMouse(true)
    hd:RegisterForDrag("LeftButton")
    f:SetMovable(true)
    hd:SetScript("OnDragStart", function() f:StartMoving() end)
    hd:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        local p, _, rp, x, y = f:GetPoint()
        ns.db.profile.point, ns.db.profile.relPoint, ns.db.profile.x, ns.db.profile.y = p, rp, x, y
    end)
    f.title = hd:CreateFontString(nil, "OVERLAY")
    f.title:SetFont(fontPath(), 13, "OUTLINE")
    f.title:SetPoint("LEFT", 10, 0)
    local a = OUI.ACCENT or { r = 1, g = 0.82, b = 0 }
    f.title:SetTextColor(a.r, a.g, a.b)
    f.title:SetText("Friends")

    local close = CreateFrame("Button", nil, hd)
    close:SetSize(22, 22)
    close:SetPoint("RIGHT", -4, 0)
    close.t = close:CreateFontString(nil, "OVERLAY")
    close.t:SetFont(fontPath(), 16, "OUTLINE")
    close.t:SetPoint("CENTER")
    close.t:SetText("x")
    close:SetScript("OnClick", function() f:Hide() end)
    close:SetScript("OnEnter", function() close.t:SetTextColor(1, 0.4, 0.4) end)
    close:SetScript("OnLeave", function() close.t:SetTextColor(1, 1, 1) end)

    f.accentLine = f:CreateTexture(nil, "ARTWORK")
    f.accentLine:SetPoint("TOPLEFT", 2, -26)
    f.accentLine:SetPoint("TOPRIGHT", -2, -26)
    f.accentLine:SetHeight(1)
    local ac = OUI.ACCENT or { r = 1, g = 0.82, b = 0 }
    f.accentLine:SetColorTexture(ac.r, ac.g, ac.b, 1)

    -- tab bar (Friends / Ignored)
    f.mode = "friends"
    local function makeTab(label, mode, xoff)
        local t = CreateFrame("Button", nil, f)
        t:SetSize(74, 18)
        t:SetPoint("TOPLEFT", xoff, -28)
        t.t = t:CreateFontString(nil, "OVERLAY")
        t.t:SetFont(fontPath(), 12, "")
        t.t:SetPoint("CENTER")
        t.t:SetText(label)
        t.mode = mode
        t.line = t:CreateTexture(nil, "ARTWORK")
        t.line:SetPoint("BOTTOMLEFT", 2, 0); t.line:SetPoint("BOTTOMRIGHT", -2, 0); t.line:SetHeight(2)
        t.line:SetColorTexture(ac.r, ac.g, ac.b, 1)
        t:SetScript("OnClick", function() f.setMode(mode) end)
        return t
    end
    f.tabs = { makeTab(L("Friends"), "friends", 6), makeTab(L("Ignored"), "ignored", 84),
        makeTab(L("Who"), "who", 162) }

    function f.refreshTabs()
        local x = 6
        for _, t in ipairs(f.tabs) do
            local vis = (t.mode == "friends")
                or (t.mode == "ignored" and cfg("showIgnoredTab") ~= false)
                or (t.mode == "who" and cfg("showWhoTab") ~= false)
            if vis then
                t:ClearAllPoints()
                t:SetPoint("TOPLEFT", x, -28)
                t:Show()
                x = x + 78
            else
                t:Hide()
            end
        end
        -- if the active tab got hidden, fall back to Friends
        if (f.mode == "ignored" and cfg("showIgnoredTab") == false)
            or (f.mode == "who" and cfg("showWhoTab") == false) then
            f.setMode("friends")
        end
    end

    function f.setMode(mode)
        f.mode = mode
        f.offset = 0
        if SetWhoToUI then pcall(SetWhoToUI, mode == "who" and 1 or 0) end
        if mode == "who" then f.whoResults = f.whoResults or {} end
        for _, t in ipairs(f.tabs) do
            local active = (t.mode == mode)
            t.t:SetTextColor(active and ac.r or 0.55, active and ac.g or 0.55, active and ac.b or 0.55)
            t.line:SetShown(active)
        end
        if f.addBox then
            local ph = (mode == "ignored" and L("Name to ignore"))
                or (mode == "who" and L("Search players..."))
                or L("Name or BattleTag#0000")
            f.addBox.ph:SetText(ph)
            f.addBox.ph:SetShown(f.addBox:GetText() == "" and not f.addBox:HasFocus())
        end
        ns.RefreshFriends()
    end

    -- list area
    local list = CreateFrame("Frame", nil, f)
    list:SetPoint("TOPLEFT", 4, -50)
    list:SetPoint("BOTTOMRIGHT", -4, 30)
    list:EnableMouseWheel(true)
    f.list = list
    f.rows = {}
    f.offset = 0

    list:SetScript("OnMouseWheel", function(_, delta)
        f.offset = math.max(0, f.offset - delta)
        ns.RefreshFriends()
    end)

    -- add-friend input strip
    local addBtn = CreateFrame("Button", nil, f)
    addBtn:SetSize(22, 20)
    addBtn:SetPoint("BOTTOMRIGHT", -6, 6)
    addBtn.bg = addBtn:CreateTexture(nil, "BACKGROUND")
    addBtn.bg:SetAllPoints()
    addBtn.bg:SetColorTexture(0.12, 0.12, 0.12, 1)
    addBtn.t = addBtn:CreateFontString(nil, "OVERLAY")
    addBtn.t:SetFont(fontPath(), 18, "OUTLINE")
    addBtn.t:SetPoint("CENTER", 0, -1)
    addBtn.t:SetText("+")
    local ac0 = OUI.ACCENT or { r = 1, g = 0.82, b = 0 }
    addBtn.t:SetTextColor(ac0.r, ac0.g, ac0.b)
    if OUI.PP and OUI.PP.CreateBorder then OUI.PP.CreateBorder(addBtn, 0.067, 0.067, 0.067, 1) end
    addBtn:SetScript("OnEnter", function() addBtn.t:SetTextColor(1, 1, 1) end)
    addBtn:SetScript("OnLeave", function() addBtn.t:SetTextColor(ac0.r, ac0.g, ac0.b) end)

    local ab = CreateFrame("EditBox", nil, f)
    ab:SetAutoFocus(false)
    ab:SetHeight(20)
    ab:SetPoint("BOTTOMLEFT", 6, 6)
    ab:SetPoint("BOTTOMRIGHT", -32, 6)
    ab:SetFont(fontPath(), 12, "")
    ab:SetTextInsets(5, 5, 0, 0)
    ab.bg = ab:CreateTexture(nil, "BACKGROUND")
    ab.bg:SetAllPoints()
    ab.bg:SetColorTexture(0.09, 0.09, 0.09, 1)
    if OUI.PP and OUI.PP.CreateBorder then OUI.PP.CreateBorder(ab, 0.067, 0.067, 0.067, 1) end
    ab.ph = ab:CreateFontString(nil, "OVERLAY")
    ab.ph:SetFont(fontPath(), 12, "")
    ab.ph:SetPoint("LEFT", 6, 0)
    ab.ph:SetTextColor(0.45, 0.45, 0.45)
    ab.ph:SetText(L("Name or BattleTag#0000"))
    local function updatePH() ab.ph:SetShown(ab:GetText() == "" and not ab:HasFocus()) end
    ab:SetScript("OnEditFocusGained", updatePH)
    ab:SetScript("OnEditFocusLost", updatePH)
    ab:SetScript("OnTextChanged", updatePH)
    ab:SetScript("OnEnterPressed", function(self)
        if f.mode == "who" then runWho(self:GetText())
        elseif f.mode == "ignored" then addIgnore(self:GetText())
        else addFriend(self:GetText()) end
        if f.mode ~= "who" then self:SetText("") end
        self:ClearFocus()
    end)
    ab:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    addBtn:SetScript("OnClick", function()
        if f.mode == "who" then runWho(ab:GetText())
        elseif f.mode == "ignored" then addIgnore(ab:GetText())
        else addFriend(ab:GetText()); ab:SetText("") end
        ab:ClearFocus()
    end)
    f.addBox = ab

    win = f
    f.refreshTabs()
    f.setMode("friends")
    return f
end

local function styleWindow()
    if not win then return end
    local c = cfg("bgColor")
    win.bg:SetColorTexture(c.r, c.g, c.b, c.a or 0.92)
    if OUI.PP and OUI.PP.SetBorderColor then
        local b = cfg("borderColor")
        OUI.PP.SetBorderColor(win, b.r, b.g, b.b, cfg("showBorder") ~= false and 1 or 0)
    end
    if win.accentLine then win.accentLine:SetShown(cfg("accentHeader") ~= false) end
end

-- ---------------------------------------------------------------------------
--  Build the flat display list (optionally grouped by realm with headers)
-- ---------------------------------------------------------------------------
local function buildDisplayList()
    local friends = gather()
    if not cfg("groupByRealm") then return friends end

    local myRealm = (GetRealmName and GetRealmName()) or "?"
    local groups, order = {}, {}
    for _, e in ipairs(friends) do
        local realm
        if e.bnet and (not e.name or e.name == "") then
            realm = "Battle.net"
        elseif e.bnet and e.realm and e.realm ~= "" then
            realm = e.realm
        else
            realm = myRealm
        end
        if not groups[realm] then groups[realm] = {}; order[#order + 1] = realm end
        table.insert(groups[realm], e)
    end

    table.sort(order, function(a, b)
        if a == b then return false end
        if a == myRealm then return true end
        if b == myRealm then return false end
        if a == "Battle.net" then return false end
        if b == "Battle.net" then return true end
        return a < b
    end)

    local collapsed = ns.db.profile.collapsedRealms or {}
    local display = {}
    for _, realm in ipairs(order) do
        local g = groups[realm]
        local on = 0
        for _, e in ipairs(g) do if e.online then on = on + 1 end end
        display[#display + 1] = { isHeader = true, realm = realm, count = #g, online = on, collapsed = collapsed[realm] }
        if not collapsed[realm] then
            for _, e in ipairs(g) do display[#display + 1] = e end
        end
    end
    return display
end

-- ---------------------------------------------------------------------------
--  Refresh / populate
-- ---------------------------------------------------------------------------
function ns.RefreshFriends()
    if not win or not win:IsShown() then return end
    local data
    if win.mode == "ignored" then
        data = gatherIgnored()
        win.title:SetText(string.format("%s  (%d)", L("Ignored"), #data))
    elseif win.mode == "who" then
        data = win.whoResults or {}
        win.title:SetText(string.format("%s  (%d)", L("Who"), #data))
    else
        data = buildDisplayList()
        local online = 0
        for _, e in ipairs(data) do if not e.isHeader and e.online then online = online + 1 end end
        win.title:SetText(string.format("%s  (%d online)", L("Friends"), online))
    end

    local listH = win.list:GetHeight()
    local visible = math.max(1, math.floor(listH / ROW_H))
    local maxOffset = math.max(0, #data - visible)
    if win.offset > maxOffset then win.offset = maxOffset end

    for i = 1, visible do
        local r = win.rows[i]
        if not r then
            r = makeRow(win.list)
            r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
            r:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_H)
            win.rows[i] = r
        end
        local e = data[win.offset + i]
        if not e then
            r:Hide()
        elseif e.isHeader then
            r.isHeader = true
            r.realm = e.realm
            r.entry = nil
            r.dot:Hide(); r.classIcon:Hide(); r.faction:Hide(); r.info:SetText("")
            r.arrow:SetText(e.collapsed and "+" or "-")
            r.arrow:Show()
            local a = OUI.ACCENT or { r = 1, g = 0.82, b = 0 }
            r.name:ClearAllPoints()
            r.name:SetPoint("LEFT", 20, 0)
            r.name:SetTextColor(a.r, a.g, a.b)
            r.name:SetText(string.format("%s  (%d)", e.realm, e.online))
            r:Show()
        else
            r.isHeader = false
            r.realm = nil
            r.entry = e
            r.arrow:Hide()

            if e.ignored then
                r.dot:Hide(); r.classIcon:Hide(); r.faction:Hide(); r.info:SetText("")
                r.name:ClearAllPoints()
                r.name:SetPoint("LEFT", 14, 0)
                r.name:SetTextColor(0.7, 0.55, 0.55)
                r.name:SetText(e.account or e.name or "?")
                r:Show()
            else
            r.dot:Show()
            local sc = STATUS_COLOR[e.status] or STATUS_COLOR.offline
            r.dot:SetColorTexture(sc[1], sc[2], sc[3], 1)

            -- primary name + color
            local primary, cr, cg, cb
            if e.bnet then
                if e.name and e.name ~= "" then
                    primary = e.name
                    if cfg("classColorNames") and e.class then cr, cg, cb = classColor(e.class)
                    else cr, cg, cb = 0.51, 0.77, 1 end
                else
                    primary = e.account or "?"
                    cr, cg, cb = 0.51, 0.77, 1
                end
            else
                primary = e.name or "?"
                if cfg("classColorNames") and e.class then cr, cg, cb = classColor(e.class)
                else cr, cg, cb = 1, 1, 1 end
            end
            r.name:SetTextColor(cr, cg, cb)
            r.name:SetText(primary)

            -- class icon
            local hasClassIcon = false
            if cfg("showClassIcons") ~= false and e.class then
                hasClassIcon = setClassIcon(r.classIcon, e.class)
            end
            r.classIcon:SetShown(hasClassIcon)
            r.name:ClearAllPoints()
            r.name:SetPoint("TOPLEFT", hasClassIcon and 36 or 18, -3)
            r.info:ClearAllPoints()
            r.info:SetPoint("BOTTOMLEFT", hasClassIcon and 36 or 18, 3)

            -- faction icon
            local fi = cfg("showFactionIcons") ~= false and e.faction and FACTION_ICON[e.faction]
            if fi then r.faction:SetTexture(fi); r.faction:Show() else r.faction:Hide() end

            -- info line (realm omitted here, it's the group header now)
            local parts = {}
            if e.who then
                if e.race and e.race ~= "" then parts[#parts + 1] = e.race end
                if e.zone and e.zone ~= "" then parts[#parts + 1] = e.zone end
                if e.guild and e.guild ~= "" then parts[#parts + 1] = "<" .. e.guild .. ">" end
            else
            if e.bnet and e.account and e.name and e.name ~= "" then parts[#parts + 1] = e.account end
            if e.level and e.level > 0 then parts[#parts + 1] = "L" .. e.level end
            if e.zone and e.zone ~= "" then parts[#parts + 1] = e.zone end
            if not cfg("groupByRealm") and e.realm and e.realm ~= "" then parts[#parts + 1] = e.realm end
            if e.bnet and (not e.name or e.name == "") and e.client and e.client ~= "" and e.client ~= "WoW" then
                parts[#parts + 1] = e.client
            end
            end
            r.info:SetText(table.concat(parts, "  -  "))
            r:Show()
            end
        end
    end
    -- hide surplus rows
    for i = visible + 1, #win.rows do win.rows[i]:Hide() end
end

function ns.ToggleFriends()
    local f = buildWindow()
    if f:IsShown() then f:Hide() else
        styleWindow()
        f:ClearAllPoints()
        f:SetPoint(cfg("point") or "CENTER", UIParent, cfg("relPoint") or "CENTER", cfg("x") or 0, cfg("y") or 0)
        f:Show()
        ns.RefreshFriends()
    end
end

function ns.RefreshSettings()
    if not win then return end
    win:SetScale(cfg("scale") or 1)
    win:SetSize(cfg("width") or 320, cfg("height") or 420)
    if win.refreshTabs then win.refreshTabs() end
    styleWindow()
    ns.RefreshFriends()
end

-- ---------------------------------------------------------------------------
--  Auto-accept Battle.net friend invites
-- ---------------------------------------------------------------------------
local function handleInvites()
    if not cfg("autoAcceptFriendInvites") then return end
    if not (BNGetNumFriendInvites and BNGetFriendInviteInfo and BNAcceptFriendInvite) then return end
    for i = BNGetNumFriendInvites(), 1, -1 do
        local ok, inviteID = pcall(BNGetFriendInviteInfo, i)
        if ok and inviteID then pcall(BNAcceptFriendInvite, inviteID) end
    end
end
ns.HandleInvites = handleInvites

-- ---------------------------------------------------------------------------
--  Lifecycle
-- ---------------------------------------------------------------------------
function FR:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("OldschoolUIFriendsDB", defaults, true)
    ns.db = self.db
end

function FR:OnEnable()
    if OUI.IsModuleEnabled and not OUI:IsModuleEnabled("OUI_Friends") then return end
    if not cfg("enabled") then return end

    if not FR._moverReg and OUI.RegisterUnlockElements and OUI.MakeUnlockElement then
        FR._moverReg = true
        OUI:RegisterUnlockElements({ OUI.MakeUnlockElement({
            key = "OUIFriends", label = "Friends", group = "Friends", order = 560,
            getFrame = function() return _G.OUIFriendsFrame end,
            getSize  = function() local f = _G.OUIFriendsFrame
                return (f and f:GetWidth()) or 320, (f and f:GetHeight()) or 420 end,
            isHidden = function() local f = _G.OUIFriendsFrame; return not (f and f:IsShown()) end,
            savePos  = function(_, _, _, x, y)
                ns.db.profile.point, ns.db.profile.relPoint = "CENTER", "CENTER"
                ns.db.profile.x, ns.db.profile.y = x, y
                local f = _G.OUIFriendsFrame
                if f then f:ClearAllPoints(); f:SetPoint("CENTER", UIParent, "CENTER", x, y) end
            end,
            applyPos = function()
                local f = _G.OUIFriendsFrame
                if f then f:ClearAllPoints()
                    f:SetPoint(ns.db.profile.point or "CENTER", UIParent,
                        ns.db.profile.relPoint or "CENTER", ns.db.profile.x or 0, ns.db.profile.y or 0) end
            end,
        }) })
    end

    -- each registration so an unsupported event can't abort the rest of setup.
    for _, ev in ipairs({
        "FRIENDLIST_UPDATE", "BN_FRIEND_INFO_CHANGED", "BN_FRIEND_LIST_SIZE_CHANGED",
        "IGNORELIST_UPDATE", "PLAYER_ENTERING_WORLD",
    }) do
        pcall(function() self:RegisterEvent(ev, function() ns.RefreshFriends() end) end)
    end
    for _, ev in ipairs({ "BN_FRIEND_INVITE_ADDED", "BN_FRIEND_INVITE_LIST_INITIALIZED" }) do
        pcall(function() self:RegisterEvent(ev, function() ns.HandleInvites() end) end)
    end
    pcall(function() self:RegisterEvent("WHO_LIST_UPDATE", function()
        if win and win.mode == "who" then win.whoResults = ns.ReadWho(); ns.RefreshFriends() end
    end) end)

    if cfg("autoShow") then
        C_Timer.After(1, function() if not (win and win:IsShown()) then ns.ToggleFriends() end end)
    end

    -- Replace the Blizzard Friends frame: route ToggleFriendsFrame (micro-menu
    -- button, OUI chat sidebar, etc.) to our window when enabled. Checked at call
    -- time so the option can be toggled live.
    if not ns._origToggleFriends and type(ToggleFriendsFrame) == "function" then
        ns._origToggleFriends = ToggleFriendsFrame
        ToggleFriendsFrame = function(...)
            if cfg("replaceBlizzard") then ns.ToggleFriends()
            else return ns._origToggleFriends(...) end
        end
    end

    SLASH_OUIFRIENDS1 = "/ouifriends"
    SLASH_OUIFRIENDS2 = "/ouifr"
    SlashCmdList["OUIFRIENDS"] = function() ns.ToggleFriends() end
end

-- ===========================================================================
--  OldschoolUI -- Blizzard Skin: Mail
--  Themed reskin of the stock Mail UI (MailFrame / InboxFrame / OpenMailFrame /
--  SendMailFrame). Base-UI frames (not LoadOnDemand), non-secure -> no taint.
--  Visual-only: dim BACKGROUND/BORDER chrome (icons/text kept), dark fill +
--  Core border via BS:DarkPanel, accent the tabs/buttons/title.
--
--  Field names guarded defensively for MoP Classic 5.5.x; use /ouiprobe dump
--  MailFrame (InboxFrame, OpenMailFrame, SendMailFrame) to refine.
-- ===========================================================================
local _, ns = ...
local OUI = OldschoolUI
if not OUI then return end
local BS = ns.BS
if not BS then return end

local function ac() return OUI.ACCENT.r, OUI.ACCENT.g, OUI.ACCENT.b end
local function framesEnabled() return BS.db and BS.db.profile and BS.db.profile.reskinFrames end

local done = setmetatable({}, { __mode = "k" })

-- dim BACKGROUND/BORDER chrome, keep ARTWORK/OVERLAY (icons) + models
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
            if c and not (c.Icon or c.icon) then stripChrome(c, (depth or 0) - 1) end
        end
    end
end

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

-- Set a readable body-text colour. SimpleHTML frames (the opened-mail body)
-- require an element type as arg #1; FontStrings/EditBoxes don't. All guarded.
local function setBodyText(obj)
    if not obj or not obj.SetTextColor then return end
    local r, g, b = OUI.GetSkinTextColor()
    if obj.GetObjectType and obj:GetObjectType() == "SimpleHTML" then
        for _, t in ipairs({ "P", "H1", "H2", "H3" }) do pcall(obj.SetTextColor, obj, t, r, g, b) end
    else
        pcall(obj.SetTextColor, obj, r, g, b)
    end
end

-- strip a button's stock slices + accent its label (existing regions only)
local function skinButton(name)
    local b = type(name) == "table" and name or _G[name]
    if not b or done[b] then return end
    done[b] = true
    for _, k in ipairs({ "Left", "Middle", "Right",
                         "LeftSeparator", "RightSeparator" }) do
        if b[k] and b[k].SetAlpha then b[k]:SetAlpha(0) end
    end
    if b.SetNormalTexture then pcall(b.SetNormalTexture, b, nil) end
    if b.GetNormalTexture and b:GetNormalTexture() then b:GetNormalTexture():SetAlpha(0) end
    local fs = b.GetFontString and b:GetFontString()
    if fs then fs:SetTextColor(ac()) end
end

local function skinTab(tab)
    if not tab or done[tab] then return end
    done[tab] = true
    for _, k in ipairs({ "Left", "Middle", "Right",
                         "LeftDisabled", "MiddleDisabled", "RightDisabled",
                         "HighlightTexture" }) do
        if tab[k] and tab[k].SetAlpha then tab[k]:SetAlpha(0) end
    end
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
    end
    local fs = tab.GetFontString and tab:GetFontString()
    if fs then fs:SetTextColor(ac()) end
end

local function skinEditBox(name)
    local e = _G[name]
    if not e or done[e] then return end
    done[e] = true
    for _, k in ipairs({ "Left", "Middle", "Right" }) do
        if e[k] and e[k].SetAlpha then e[k]:SetAlpha(0) end
    end
    local bg = e:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", -2, 0); bg:SetPoint("BOTTOMRIGHT", 2, 0)
    bg:SetColorTexture(0.08, 0.08, 0.09, 0.9)
end

local BUTTONS = {
    "OpenAllMail", "InboxPrevPageButton", "InboxNextPageButton",
    "SendMailMailButton", "SendMailCancelButton",
    "OpenMailReplyButton", "OpenMailDeleteButton", "OpenMailReturnButton",
    "OpenMailCancelButton", "OpenMailButton",
}
local EDITBOXES = {
    "SendMailNameEditBox", "SendMailSubjectEditBox",
}

local function skinMail()
    local mf = _G.MailFrame
    if not mf or done.main then return end
    if mf.IsForbidden and mf:IsForbidden() then return end
    done.main = true

    stripChrome(mf, 2)
    BS:DarkPanel(mf, 0.97)
    hideChrome(mf)        -- portrait ring + corners/edges/nine-slice (exact keys)
    BS:MakeMovable(mf, "mail", function()
        if HideUIPanel then HideUIPanel(_G.MailFrame) end
    end)
    -- mail body text is a dark embossed letter font -> unreadable on dark; lighten
    if _G.OpenMailBodyText then setBodyText(_G.OpenMailBodyText) end
    if _G.SendMailBodyEditBox then setBodyText(_G.SendMailBodyEditBox) end
    if _G.InvoiceTextFontNormal then setBodyText(_G.InvoiceTextFontNormal) end
    -- mail-specific bottom button-bar chrome
    for _, n in ipairs({ "MailFrameBtnCornerLeft", "MailFrameBtnCornerRight",
                         "MailFrameButtonBottomBorder" }) do
        if _G[n] then _G[n]:SetAlpha(0) end
    end
    if _G.InboxFrameBg then _G.InboxFrameBg:SetAlpha(0) end
    local title = _G.MailFrameTitleText or mf.TitleText
    if title and title.SetTextColor then title:SetTextColor(ac()) end

    -- tabs (Inbox / Send Mail)
    local i = 1
    while _G["MailFrameTab" .. i] do skinTab(_G["MailFrameTab" .. i]); i = i + 1 end

    -- inbox panel + its item rows (stripChrome keeps the item icons)
    if _G.InboxFrame then stripChrome(_G.InboxFrame, 3) end

    for _, n in ipairs(BUTTONS) do skinButton(n) end
    for _, n in ipairs(EDITBOXES) do skinEditBox(n) end

    -- OpenMailFrame / SendMailFrame are SEPARATE PortraitFrameTemplate windows.
    -- They re-show their nine-slice/parchment each time, so skin them on every
    -- OnShow, not once -- otherwise reading a mail shows the stock Blizzard frame.
    local function skinOpen()
        local of = _G.OpenMailFrame
        if not of then return end
        stripChrome(of, 3)
        BS:DarkPanel(of, 0.96)
        hideChrome(of)
        if _G.OpenMailBodyText then setBodyText(_G.OpenMailBodyText) end
        if _G.InvoiceTextFontNormal then setBodyText(_G.InvoiceTextFontNormal) end
        for _, n in ipairs(BUTTONS) do skinButton(n) end
    end
    local function skinSend()
        local sf = _G.SendMailFrame
        if not sf then return end
        stripChrome(sf, 3)
        -- the send body on this client is the modern ScrollingEditBox `MailEditBox`
        -- (confirmed via fstack), not SendMailBodyEditBox. Colour its inner EditBox.
        local box = _G.MailEditBox
        local be
        if box then
            if box.GetEditBox then be = box:GetEditBox() end            -- ScrollingEditBox
            if not be and box.GetObjectType and box:GetObjectType() == "EditBox" then be = box end
            if not be and box.ScrollBox and box.ScrollBox.GetScrollChild then be = box.ScrollBox:GetScrollChild() end
        end
        be = be or _G.SendMailBodyEditBox
        if be then
            setBodyText(be)
            if not be._ouiColorHook then
                be._ouiColorHook = true
                be:HookScript("OnTextChanged", function(self) setBodyText(self) end)
                be:HookScript("OnEditFocusGained", function(self) setBodyText(self) end)
            end
        end
        for _, n in ipairs(BUTTONS) do skinButton(n) end
        for _, n in ipairs(EDITBOXES) do skinEditBox(n) end
    end
    ns._skinOpenMail, ns._skinSendMail = skinOpen, skinSend
    skinOpen(); skinSend()
    if _G.OpenMailFrame then _G.OpenMailFrame:HookScript("OnShow", function() if framesEnabled() then skinOpen() end end) end
    if _G.SendMailFrame then _G.SendMailFrame:HookScript("OnShow", function() if framesEnabled() then skinSend() end end) end

    -- Blizzard re-sets the open-mail body colour on every mail update -> re-apply.
    if _G.OpenMail_Update and not done.openHook then
        done.openHook = true
        hooksecurefunc("OpenMail_Update", function()
            if framesEnabled() and _G.OpenMailBodyText then
                setBodyText(_G.OpenMailBodyText)
            end
        end)
    end
end
ns.SkinMail = skinMail

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("MAIL_SHOW")
loader:SetScript("OnEvent", function(self, event)
    if not framesEnabled() then return end
    -- MailFrame exists at login, but skin again on first MAIL_SHOW in case any
    -- child built lazily.
    skinMail()
end)

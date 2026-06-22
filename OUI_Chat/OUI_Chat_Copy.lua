-- ===========================================================================
--  OldschoolUI -- Chat  CH-3: text utilities
--  * Copy chat: a hover button (and /ouicopy) that opens a popup with the
--    active window's text in a selectable multi-line edit box.
--  * Clickable URLs: links in incoming messages become clickable; clicking one
--    opens a popup with the URL ready to copy.
--  Clean-room rewrite.
-- ===========================================================================
local ADDON, ns = ...
local OUI = OldschoolUI
if not OUI then return end

local cfg = ns.cfg
local eachChatFrame = ns.eachChatFrame
if not (cfg and eachChatFrame) then return end

local URL_PREFIX = "OUIChat"

local function font() return (OUI.GetFontPath and OUI.GetFontPath()) or STANDARD_TEXT_FONT end
local function accentHex()
    local a = OUI.ACCENT or { r = 1, g = 1, b = 1 }
    return string.format("%02x%02x%02x", math.floor(a.r * 255 + 0.5), math.floor(a.g * 255 + 0.5), math.floor(a.b * 255 + 0.5))
end

-- ---------------------------------------------------------------------------
--  Strip UI escape sequences down to plain readable text
-- ---------------------------------------------------------------------------
local function strip(text)
    if not text then return "" end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")   -- colour open
    text = text:gsub("|r", "")                     -- colour close
    text = text:gsub("|H.-|h(.-)|h", "%1")         -- hyperlink -> label
    text = text:gsub("|T.-|t", "")                 -- inline textures
    text = text:gsub("|A.-|a", "")                 -- atlas
    text = text:gsub("|K.-|k", "")                 -- protected values
    text = text:gsub("|n", "\n")
    text = text:gsub("||", "|")
    return text
end

local function readChat(cf)
    cf = cf or SELECTED_CHAT_FRAME
    if not (cf and cf.GetNumMessages) then return "" end
    local lines = {}
    for i = 1, cf:GetNumMessages() do
        local msg = cf:GetMessageInfo(i)
        if msg then lines[#lines + 1] = strip(msg) end
    end
    return table.concat(lines, "\n")
end

-- ---------------------------------------------------------------------------
--  Copy popup (shared by copy-chat and URL clicks)
-- ---------------------------------------------------------------------------
local popup
local function buildPopup()
    local f = CreateFrame("Frame", "OUIChatCopyPopup", UIParent)
    f:SetSize(560, 380)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)

    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(0.05, 0.05, 0.05, 0.96)
    if OUI.PP and OUI.PP.CreateBorder then OUI.PP.CreateBorder(f, 0.067, 0.067, 0.067, 1) end

    f.title = f:CreateFontString(nil, "OVERLAY")
    f.title:SetFont(font(), 13, "OUTLINE")
    f.title:SetPoint("TOPLEFT", 12, -10)
    local a = OUI.ACCENT or { r = 1, g = 1, b = 1 }
    f.title:SetTextColor(a.r, a.g, a.b)
    f.title:SetText("Copy")

    local close = CreateFrame("Button", nil, f)
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", -6, -6)
    close.t = close:CreateFontString(nil, "OVERLAY")
    close.t:SetFont(font(), 16, "OUTLINE")
    close.t:SetPoint("CENTER")
    close.t:SetText("x")
    close:SetScript("OnClick", function() f:Hide() end)
    close:SetScript("OnEnter", function() close.t:SetTextColor(1, 0.4, 0.4) end)
    close:SetScript("OnLeave", function() close.t:SetTextColor(1, 1, 1) end)

    local scroll = CreateFrame("ScrollFrame", "OUIChatCopyScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -32)
    scroll:SetPoint("BOTTOMRIGHT", -30, 12)

    local eb = CreateFrame("EditBox", nil, scroll)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFont(font(), 12, "")
    eb:SetWidth(508)
    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    scroll:SetScrollChild(eb)
    f.eb = eb

    popup = f
    return f
end

function ns.ShowCopyPopup(text, title)
    local f = popup or buildPopup()
    f.title:SetText(title or "Copy")
    f.eb:SetText(text or "")
    f.eb:HighlightText()
    f:Show()
    f.eb:SetFocus()
end

-- ---------------------------------------------------------------------------
--  Small themed button
-- ---------------------------------------------------------------------------
local function makeButton(parent, label, w, h)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(0.13, 0.13, 0.13, 1)
    if OUI.PP and OUI.PP.CreateBorder then OUI.PP.CreateBorder(b, 0.22, 0.22, 0.22, 1) end
    b.text = b:CreateFontString(nil, "OVERLAY")
    b.text:SetFont(font(), 12, "")
    b.text:SetPoint("CENTER")
    b.text:SetText(label)
    b:SetScript("OnEnter", function() b.bg:SetColorTexture(0.22, 0.22, 0.22, 1) end)
    b:SetScript("OnLeave", function() b.bg:SetColorTexture(0.13, 0.13, 0.13, 1) end)
    return b
end

-- ---------------------------------------------------------------------------
--  Compact URL popup (single line, auto-selected for Ctrl+C)
-- ---------------------------------------------------------------------------
local urlPopup
local function buildUrlPopup()
    local f = CreateFrame("Frame", "OUIChatURLPopup", UIParent)
    f:SetSize(360, 92)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)

    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(0.05, 0.05, 0.05, 0.96)
    if OUI.PP and OUI.PP.CreateBorder then OUI.PP.CreateBorder(f, 0.067, 0.067, 0.067, 1) end

    local a = OUI.ACCENT or { r = 1, g = 1, b = 1 }
    f.title = f:CreateFontString(nil, "OVERLAY")
    f.title:SetFont(font(), 13, "OUTLINE")
    f.title:SetPoint("TOPLEFT", 12, -9)
    f.title:SetTextColor(a.r, a.g, a.b)
    f.title:SetText("URL")

    local close = CreateFrame("Button", nil, f)
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", -6, -6)
    close.t = close:CreateFontString(nil, "OVERLAY")
    close.t:SetFont(font(), 16, "OUTLINE")
    close.t:SetPoint("CENTER")
    close.t:SetText("x")
    close:SetScript("OnClick", function() f:Hide() end)
    close:SetScript("OnEnter", function() close.t:SetTextColor(1, 0.4, 0.4) end)
    close:SetScript("OnLeave", function() close.t:SetTextColor(1, 1, 1) end)

    local ebbg = CreateFrame("Frame", nil, f)
    ebbg:SetPoint("TOPLEFT", 12, -32)
    ebbg:SetPoint("TOPRIGHT", -12, -32)
    ebbg:SetHeight(22)
    ebbg.bg = ebbg:CreateTexture(nil, "BACKGROUND")
    ebbg.bg:SetAllPoints()
    ebbg.bg:SetColorTexture(0.1, 0.1, 0.1, 1)
    if OUI.PP and OUI.PP.CreateBorder then OUI.PP.CreateBorder(ebbg, 0.067, 0.067, 0.067, 1) end

    local eb = CreateFrame("EditBox", nil, ebbg)
    eb:SetAutoFocus(false)
    eb:SetFont(font(), 12, "")
    eb:SetPoint("TOPLEFT", 5, -2)
    eb:SetPoint("BOTTOMRIGHT", -5, 2)
    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    eb:SetScript("OnEnterPressed", function() eb:HighlightText() end)
    f.eb = eb

    f.hint = f:CreateFontString(nil, "OVERLAY")
    f.hint:SetFont(font(), 11, "")
    f.hint:SetPoint("BOTTOMLEFT", 12, 10)
    f.hint:SetTextColor(0.6, 0.6, 0.6)
    f.hint:SetText("Strg+C zum Kopieren")

    local copyBtn = makeButton(f, "Kopieren (Strg+C)", 130, 20)
    copyBtn:SetPoint("BOTTOMRIGHT", -12, 8)
    copyBtn:SetScript("OnClick", function()
        eb:SetFocus()
        eb:HighlightText()
    end)
    copyBtn:HookScript("OnEnter", function() copyBtn.bg:SetColorTexture(0.22, 0.22, 0.22, 1) end)
    copyBtn:HookScript("OnLeave", function() copyBtn.bg:SetColorTexture(0.13, 0.13, 0.13, 1) end)

    urlPopup = f
    return f
end

function ns.ShowUrlPopup(url)
    url = url or ""
    local f = urlPopup or buildUrlPopup()
    local w = math.min(math.max(#url * 7 + 80, 280), 520)
    f:SetWidth(w)
    f.eb:SetText(url)
    f.eb:SetCursorPosition(0)
    f.eb:HighlightText()
    f:Show()
    f.eb:SetFocus()
end

-- ---------------------------------------------------------------------------
--  Copy button (per chat frame, subtle until hovered)
-- ---------------------------------------------------------------------------
local function attachCopyButton(cf)
    if cf._ouiCopyBtn then return end
    local b = CreateFrame("Button", nil, cf)
    b:SetSize(16, 16)
    b:SetPoint("TOPRIGHT", cf, "TOPRIGHT", -2, 14)
    b:SetFrameStrata(cf:GetFrameStrata())
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints()
    b.tex:SetTexture("Interface\\BUTTONS\\UI-GuildButton-PublicNote-Up")
    b:SetAlpha(0.30)
    b:SetScript("OnEnter", function(s) s:SetAlpha(1) end)
    b:SetScript("OnLeave", function(s) s:SetAlpha(0.30) end)
    b:SetScript("OnClick", function() ns.ShowCopyPopup(readChat(cf), "Copy chat") end)
    b:SetShown(cfg("showCopyButton") ~= false)
    cf._ouiCopyBtn = b
end

-- exposed for the sidebar / slash
function ns.OpenCopyChat()
    ns.ShowCopyPopup(readChat(), "Copy chat")
end

-- ---------------------------------------------------------------------------
--  Clickable URLs
-- ---------------------------------------------------------------------------
local URL_PATTERNS = {
    "(%a[%w%+%.%-]+://%S+)",                 -- scheme://rest
    "(www%.[%w_%.%-]+%.%a%a+/%S*)",          -- www.host.tld/path
    "(www%.[%w_%.%-]+%.%a%a+)",              -- www.host.tld
}

local function wrapURLs(text)
    if not text then return text end
    local out, pos, len = {}, 1, #text
    local repl = "|cff" .. accentHex() .. "|H" .. URL_PREFIX .. "url:"
    while pos <= len do
        local bestS, bestE, bestUrl
        for _, pat in ipairs(URL_PATTERNS) do
            local s, e, url = text:find(pat, pos)
            if s and (not bestS or s < bestS) then bestS, bestE, bestUrl = s, e, url end
        end
        if not bestS then
            out[#out + 1] = text:sub(pos)
            break
        end
        out[#out + 1] = text:sub(pos, bestS - 1)
        out[#out + 1] = repl .. bestUrl .. "|h[" .. bestUrl .. "]|h|r"
        pos = bestE + 1   -- advance past the inserted link; never re-scan inside it
    end
    return table.concat(out)
end

local CHAT_EVENTS = {
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
    "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_BN_WHISPER",
    "CHAT_MSG_BN_WHISPER_INFORM", "CHAT_MSG_CHANNEL", "CHAT_MSG_INSTANCE_CHAT",
    "CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_EMOTE", "CHAT_MSG_SYSTEM",
}

local function urlFilter(_, _, msg, ...)
    if cfg("clickableURLs") ~= false and msg and (msg:find("://", 1, true) or msg:find("www.", 1, true)) then
        return false, wrapURLs(msg), ...
    end
end

-- ---------------------------------------------------------------------------
--  Setup
-- ---------------------------------------------------------------------------
function ns.SetupChatText()
    eachChatFrame(attachCopyButton)
    if ns._textSetup then return end
    ns._textSetup = true

    hooksecurefunc("FCF_OpenTemporaryWindow", function()
        local id = FCF_GetCurrentChatFrameID and FCF_GetCurrentChatFrameID() or 1
        local cf = _G["ChatFrame" .. id]
        if cf then attachCopyButton(cf) end
    end)

    if ChatFrame_AddMessageEventFilter then
        for _, ev in ipairs(CHAT_EVENTS) do
            ChatFrame_AddMessageEventFilter(ev, urlFilter)
        end
    end

    -- Pre-empt SetItemRef: our link type is unknown to Blizzard's ItemRef
    -- handler, so a posthook is too late (the original would already have tried
    -- ItemRefTooltip:SetHyperlink() and errored). Wrap it instead and return
    -- early for our links; defer to the original for everything else.
    if not ns._setItemRefHooked then
        ns._setItemRefHooked = true
        local orig = SetItemRef
        function SetItemRef(link, text, button, chatFrame)
            if type(link) == "string" then
                local url = link:match("^" .. URL_PREFIX .. "url:(.+)$")
                if url then
                    url = url:match("%]%((.-)%)%s*$") or url   -- unwrap [label](url)
                    ns.ShowUrlPopup(url)
                    return
                end
            end
            return orig(link, text, button, chatFrame)
        end
    end

    SLASH_OUICOPY1 = "/ouicopy"
    SlashCmdList["OUICOPY"] = function() ns.ShowCopyPopup(readChat(), "Copy chat") end
end

-- keep copy buttons in sync with the toggle when options change
function ns.RefreshCopyButtons()
    eachChatFrame(function(cf)
        if cf._ouiCopyBtn then cf._ouiCopyBtn:SetShown(cfg("showCopyButton") ~= false) end
    end)
end

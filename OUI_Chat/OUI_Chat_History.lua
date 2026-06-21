-- ===========================================================================
--  OldschoolUI -- Chat  CH-4a: persistent history
--  Captures the General chat stream into per-character saved variables and
--  replays it (with a timestamp prefix) on the next login, so a /reload or
--  relog keeps your recent scrollback. The combat log is never tracked.
--  Clean-room rewrite.
-- ===========================================================================
local ADDON, ns = ...
local OUI = OldschoolUI
if not OUI then return end

local cfg = ns.cfg
if not cfg then return end

local restoring = false
local restored = false

local function persistEnabled() return cfg("persistChatHistory") ~= false end
local function maxLines() return cfg("persistChatHistoryMaxLines") or 100 end

local function store()
    OldschoolUIChatScrollDB = OldschoolUIChatScrollDB or {}
    OldschoolUIChatScrollDB.lines = OldschoolUIChatScrollDB.lines or {}
    return OldschoolUIChatScrollDB.lines
end

-- ---------------------------------------------------------------------------
--  Capture
-- ---------------------------------------------------------------------------
local function onAddMessage(_, msg, r, g, b)
    if restoring or not persistEnabled() then return end
    if type(msg) ~= "string" or msg == "" then return end
    local lines = store()
    lines[#lines + 1] = { msg = msg, r = r, g = g, b = b, t = time() }
    local maxN = maxLines()
    while #lines > maxN do table.remove(lines, 1) end
end

-- ---------------------------------------------------------------------------
--  Restore (once, on the first login of the session)
-- ---------------------------------------------------------------------------
local function restore()
    if restored or not persistEnabled() then return end
    restored = true
    local cf = ChatFrame1
    if not (cf and cf.AddMessage) then return end
    local lines = store()
    if #lines == 0 then return end

    restoring = true
    cf:AddMessage(" ")
    cf:AddMessage("|cff808080" .. string.rep("-", 6) .. " " .. date("%Y-%m-%d %H:%M") .. " " .. string.rep("-", 6) .. "|r")
    for _, e in ipairs(lines) do
        local stamp = "|cff707070[" .. date("%H:%M", e.t or time()) .. "]|r "
        cf:AddMessage(stamp .. e.msg, e.r, e.g, e.b)
    end
    restoring = false
end

-- ---------------------------------------------------------------------------
--  Wipe helper (used by options / slash)
-- ---------------------------------------------------------------------------
function ns.WipeChatHistory()
    OldschoolUIChatScrollDB = { lines = {} }
end

-- ---------------------------------------------------------------------------
--  Setup
-- ---------------------------------------------------------------------------
function ns.SetupChatHistory()
    if ns._historySetup then return end
    ns._historySetup = true
    if ChatFrame1 and ChatFrame1.AddMessage then
        hooksecurefunc(ChatFrame1, "AddMessage", onAddMessage)
    end
    -- restore right away (called early from OnEnable) so the scrollback lands
    -- above the addon login messages instead of below them.
    restore()

    SLASH_OUICHATWIPE1 = "/ouichatwipe"
    SlashCmdList["OUICHATWIPE"] = function()
        ns.WipeChatHistory()
        if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("OldschoolUI: chat history cleared.") end
    end
end

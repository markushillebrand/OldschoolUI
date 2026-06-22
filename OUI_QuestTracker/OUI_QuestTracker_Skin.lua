-------------------------------------------------------------------------------
--  OUI_QuestTracker_Skin.lua  --  WatchFrame line + header styling
--
--  Taint-free: we only hooksecurefunc("WatchFrame_SetLine", ...) -- Blizzard
--  calls it for every line on every WatchFrame update, after it has applied
--  its own defaults, so re-applying font size + title colour there is safe.
--  No SetScript on the tracker, no calls back into WatchFrame_Update.
-------------------------------------------------------------------------------

local ADDON, ns = ...
local QT = ns.QT
if not QT then return end

local abs = math.abs

-- Blizzard styles header lines to roughly (0.75, 0.61, 0). Used to recognise
-- headers for lines that existed before our hook was installed.
local function LooksLikeHeader(fs)
    if not fs or not fs.GetTextColor then return false end
    local r, g, b = fs:GetTextColor()
    return r and abs(r - 0.75) < 0.06 and abs(g - 0.61) < 0.06 and abs(b) < 0.06
end

local function StyleLine(line, isHeader)
    if not line or not line.text then return end
    local objSize   = tonumber(QT.Cfg("objectiveFontSize")) or 10
    local file, _, flags = line.text:GetFont()
    if isHeader then
        local titleSize = tonumber(QT.Cfg("titleFontSize")) or 12
        if file then line.text:SetFont(file, titleSize, flags) end
        if QT.Cfg("skinHeaders") ~= false then
            line.text:SetTextColor(QT.TitleColor())
        end
    else
        if file then line.text:SetFont(file, objSize, flags) end
    end
    if line.dash then
        local df, _, dflags = line.dash:GetFont()
        if df then line.dash:SetFont(df, objSize, dflags) end
    end
end

-- the "OBJECTIVES" header label
local function StyleTitle()
    local t = _G.WatchFrameTitle
    if not t or not t.GetFont then return end
    if QT.Cfg("skinHeaders") == false then return end
    local file, _, flags = t:GetFont()
    if file then t:SetFont(file, tonumber(QT.Cfg("titleFontSize")) or 12, flags) end
    if QT.Cfg("accentHeaders") ~= false then
        t:SetTextColor(QT.TitleColor())
    end
end

-- re-style everything currently rendered (option changes / profile swaps);
-- live updates go through the WatchFrame_SetLine hook
local function RestyleAll()
    local lines = _G.WatchFrameLines
    if lines and lines.GetChildren then
        for _, f in ipairs({ lines:GetChildren() }) do
            if f and f.text then
                local isHeader = f._ouiHeader
                if isHeader == nil then isHeader = LooksLikeHeader(f.text) end
                StyleLine(f, isHeader and true or false)
            end
        end
    end
    StyleTitle()
end
QT.RestyleAll = RestyleAll

local hooked = false
function QT.InitSkin()
    if not _G.WatchFrame then return end
    if not hooked and type(_G.WatchFrame_SetLine) == "function" then
        hooked = true
        hooksecurefunc("WatchFrame_SetLine", function(line, _anchor, _vo, isHeader)
            if not line then return end
            line._ouiHeader = isHeader and true or false
            StyleLine(line, isHeader and true or false)
        end)
    end
    RestyleAll()
end

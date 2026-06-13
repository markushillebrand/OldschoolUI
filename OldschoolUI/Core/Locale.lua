-- OldschoolUI / Core / Locale.lua
-- UI-text i18n only (no gameplay text). Translation is applied at the :SetText
-- boundary inside the widget builders, so English identity keys stay byte-stable
-- for search, page dispatch and unlock routing.

local OUI = OldschoolUI

local GetLocale     = GetLocale
local issecretvalue = issecretvalue
local type, tonumber, pairs, select = type, tonumber, pairs, select

local SUPPORTED = {
    enUS=true, deDE=true, esES=true, esMX=true, frFR=true, itIT=true,
    ptBR=true, ruRU=true, koKR=true, zhCN=true, zhTW=true,
}

local catalogs = {}    -- code -> { [enKey] = translated }
local active   = nil   -- active catalog (nil = English / identity)
local reverse  = {}    -- translated -> enKey

-- The translator. Identity when no catalog is active. Guards short-circuit
-- anything that must never be translated: non-strings, empty, secret combat
-- values, pure numbers, and letterless strings (hex colours, coordinates).
local function L(s)
    if not active then return s end
    if type(s) ~= "string" or s == "" then return s end
    if issecretvalue and issecretvalue(s) then return s end
    if tonumber(s) ~= nil then return s end
    if not s:find("%a") then return s end
    local v = active[s]
    return (type(v) == "string") and v or s
end
OUI.L = L

-- Positional-format helper (%1$s / %2$d) so translators can reorder placeholders.
function OUI.Lf(s, ...)
    local t = L(s)
    if type(t) ~= "string" or select("#", ...) == 0 then return t end
    return t:format(...)
end

-- Map a rendered (translated) string back to its English key, for the few
-- places that read a FontString back and compare against an English literal.
function OUI.EnKey(s)
    if type(s) ~= "string" then return s end
    return reverse[s] or s
end

-- Entry point each Locales/<code>.lua calls; returns the table to populate.
function OUI.RegisterLocale(code)
    local t = catalogs[code]
    if not t then t = {}; catalogs[code] = t end
    return t
end

-- System glyph fonts for scripts the bundled Latin font cannot render.
local function GlyphFont(locale)
    if     locale == "zhCN" then return "Fonts\\ARKai_T.ttf"
    elseif locale == "zhTW" then return "Fonts\\bLEI00D.ttf"
    elseif locale == "koKR" then return "Fonts\\2002.TTF"
    elseif locale == "ruRU" then return "Fonts\\FRIZQT___CYR.TTF" end
    return nil
end

local function Resolve()
    local client = GetLocale()
    if client == "enGB" then client = "enUS" end
    if not SUPPORTED[client] then client = "enUS" end

    local override = OUI.db and OUI.db.global and OUI.db.global.displayLocale
    if override == "auto" or not SUPPORTED[override or ""] then override = nil end

    local locale = override or client
    OUI.LOCALE      = locale
    OUI.IS_ENGLISH  = (locale == "enUS")
    OUI._localeFont = GlyphFont(locale)

    reverse = {}
    if locale == "enUS" then
        active = nil
    else
        local cat = catalogs[locale]
        if cat then
            for k, v in pairs(cat) do
                if v == true then cat[k] = k; v = k end   -- "keep English" sentinel
                if type(v) == "string" then reverse[v] = k end
            end
        end
        active = cat   -- nil when no file shipped for this locale
    end
end

-- Preliminary pass at file-load (SV not ready): resolves the CLIENT locale and
-- sets the glyph font early for any file that reads OUI._localeFont on its load.
Resolve()

-- Re-resolved by Bootstrap.OnInitialize, once the displayLocale override is readable.
OUI._InitLocale = Resolve

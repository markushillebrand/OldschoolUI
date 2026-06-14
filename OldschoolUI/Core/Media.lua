-------------------------------------------------------------------------------
--  OldschoolUI / Core / Media.lua
--  Shared media + color helpers used by skinning modules (nameplates, unit
--  frames, resource bars). Clean reimplementations of standard WoW power/
--  resource colors, a LibSharedMedia statusbar-texture resolver, and a glow
--  stub. Custom color overrides live in OUI.db.global.customColors.
-------------------------------------------------------------------------------
local OUI = OldschoolUI

-- ---------------------------------------------------------------------
-- Default colors (standard WoW values, MoP-relevant power/resource set)
-- ---------------------------------------------------------------------
OUI.DEFAULT_POWER_COLORS = {
    MANA          = { r = 0.00,  g = 0.55,  b = 1.00 },
    RAGE          = { r = 0.90,  g = 0.15,  b = 0.15 },
    FOCUS         = { r = 0.87,  g = 0.57,  b = 0.22 },
    ENERGY        = { r = 1.00,  g = 0.96,  b = 0.41 },
    RUNIC_POWER   = { r = 0.77,  g = 0.12,  b = 0.23 },
    HOLY_POWER    = { r = 0.95,  g = 0.90,  b = 0.60 },
    CHI           = { r = 0.71,  g = 1.00,  b = 0.92 },
    SOUL_SHARDS   = { r = 0.58,  g = 0.51,  b = 0.79 },
    BURNING_EMBERS= { r = 0.90,  g = 0.40,  b = 0.10 },
    DEMONIC_FURY  = { r = 0.64,  g = 0.21,  b = 0.93 },
    ECLIPSE       = { r = 0.30,  g = 0.52,  b = 0.90 },
    SHADOW_ORBS   = { r = 0.58,  g = 0.51,  b = 0.79 },
    COMBO_POINTS  = { r = 1.00,  g = 0.96,  b = 0.41 },
    RUNES         = { r = 0.55,  g = 0.00,  b = 0.00 },
}

OUI.DEFAULT_RESOURCE_COLORS = {
    ROGUE       = { r = 1.00, g = 0.96, b = 0.41 },
    DRUID       = { r = 1.00, g = 0.49, b = 0.04 },
    PALADIN     = { r = 0.96, g = 0.55, b = 0.73 },
    MONK        = { r = 0.00, g = 1.00, b = 0.60 },
    WARLOCK     = { r = 0.58, g = 0.51, b = 0.79 },
    MAGE        = { r = 0.25, g = 0.78, b = 0.92 },
    PRIEST      = { r = 0.58, g = 0.51, b = 0.79 },
    DEATHKNIGHT = { r = 0.77, g = 0.12, b = 0.23 },
}

-- Lazily-initialised custom override store under the account-wide profile.
function OUI.GetCustomColorsDB()
    local g = OUI.db and OUI.db.global
    if not g then return {} end
    g.customColors = g.customColors or {}
    return g.customColors
end

local function ColorCopy(c) if c then return { r = c.r, g = c.g, b = c.b } end end

-- Power color: custom override, else standard default, else nil.
function OUI.GetPowerColor(powerKey)
    if not powerKey then return nil end
    local db = OUI.GetCustomColorsDB()
    if db.power and db.power[powerKey] then return db.power[powerKey] end
    return ColorCopy(OUI.DEFAULT_POWER_COLORS[powerKey])
end

-- Class-resource color: custom override, else standard default, else nil.
function OUI.GetResourceColor(classToken)
    if not classToken then return nil end
    local db = OUI.GetCustomColorsDB()
    if db.resource and db.resource[classToken] then return db.resource[classToken] end
    return ColorCopy(OUI.DEFAULT_RESOURCE_COLORS[classToken])
end

-- ---------------------------------------------------------------------
-- Statusbar textures (LibSharedMedia-aware)
-- ---------------------------------------------------------------------
-- Resolve a texture path from a key->path table. Keys prefixed "sm:" are
-- fetched live from LibSharedMedia and cached back into the table.
function OUI.ResolveTexturePath(texTable, key, fallback)
    if not key then return fallback end
    local path = texTable and texTable[key]
    if path then return path end
    local smName = key:match("^sm:(.+)")
    if smName then
        local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
        if LSM then
            local fetched = LSM:Fetch("statusbar", smName)
            if fetched then
                if texTable then texTable[key] = fetched end
                return fetched
            end
        end
    end
    return fallback
end

-- Append LibSharedMedia statusbar textures into a module's runtime texture
-- table (names: key->label, order: ordered key list, castBarNames: optional
-- second label table, textures: key->path). Safe to call repeatedly; existing
-- keys are skipped. No-op when LibSharedMedia is absent.
local SM_TEX_BLACKLIST = {
    play_icon = true, stop_icon = true, user_icon = true, users_icon = true,
}
function OUI.AppendSharedMediaTextures(names, order, castBarNames, textures)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if not LSM then return end
    local smTextures = LSM:HashTable("statusbar")
    if not smTextures then return end
    if not (names and order and textures) then return end

    local sorted = {}
    for name in pairs(smTextures) do
        local key = "sm:" .. name
        if not textures[key] and not SM_TEX_BLACKLIST[name] then
            sorted[#sorted + 1] = name
        end
    end
    if #sorted == 0 then return end
    table.sort(sorted)

    order[#order + 1] = "---"
    for _, name in ipairs(sorted) do
        local key = "sm:" .. name
        textures[key] = smTextures[name]
        names[key]    = name
        order[#order + 1] = key
        if castBarNames then castBarNames[key] = name end
    end
end

-- ---------------------------------------------------------------------
-- Glow stub
-- ---------------------------------------------------------------------
-- A real glow engine (procedural ants / autocast shine / etc.) can be wired in
-- later (e.g. a free LibCustomGlow). For now these are safe no-ops so callers
-- never error; visual glows simply don't render yet.
if not OUI.Glows then
    local function noop() end
    OUI.Glows = {
        STYLES        = {},
        StartGlow     = noop, StopGlow     = noop, StopAllGlows = noop,
        StartButtonGlow = noop, StopButtonGlow = noop,
        StartProceduralAnts = noop, StopProceduralAnts = noop,
        StartAutoCastShine = noop, StopAutoCastShine = noop,
        StartShapeGlow = noop, StopShapeGlow = noop,
        StartFlipBookGlow = noop, StopFlipBookGlow = noop,
    }
end

-------------------------------------------------------------------------------
--  Shared status-bar texture registry
--  A single list of selectable bar textures used across modules, plus a global
--  default (OUI.db.global.barTexture). Modules read GetBarTexturePath(key) and
--  may register a listener to re-skin when the global default changes.
-------------------------------------------------------------------------------
do
    local BASE = "Interface\\AddOns\\OldschoolUI\\media\\textures\\"
    OUI.BAR_TEXTURES = {
        flat            = "Interface\\Buttons\\WHITE8x8",
        melli           = BASE .. "melli.tga",
        beautiful       = BASE .. "beautiful.tga",
        plating         = BASE .. "plating.tga",
        matte           = BASE .. "matte.tga",
        glass           = BASE .. "glass.tga",
        sheer           = BASE .. "sheer.tga",
        atrocity        = BASE .. "atrocity.tga",
        divide          = BASE .. "divide.tga",
        ["soft-line"]   = BASE .. "soft-line.tga",
        fade            = BASE .. "fade.tga",
        ["gradient-lr"] = BASE .. "gradient-lr.tga",
    }
    OUI.BAR_TEXTURE_ORDER = {
        "flat", "melli", "beautiful", "plating", "matte", "glass",
        "sheer", "atrocity", "divide", "soft-line", "fade", "gradient-lr",
    }
    OUI.BAR_TEXTURE_NAMES = {
        flat = "Flat", melli = "Melli", beautiful = "Beautiful", plating = "Plating",
        matte = "Matte", glass = "Glass", sheer = "Sheer", atrocity = "Atrocity",
        divide = "Divide", ["soft-line"] = "Soft Line", fade = "Fade",
        ["gradient-lr"] = "Gradient",
    }
end

-- Resolve a bar-texture key to a path. A nil/empty key falls back to the global
-- default; an unknown key falls back to "flat".
function OUI.GetBarTexturePath(key)
    if not key or key == "" then
        key = (OUI.db and OUI.db.global and OUI.db.global.barTexture) or "flat"
    end
    return OUI.BAR_TEXTURES[key] or OUI.BAR_TEXTURES.flat
end

function OUI.GetGlobalBarTextureKey()
    return (OUI.db and OUI.db.global and OUI.db.global.barTexture) or "flat"
end

local _barTexListeners = {}
function OUI.RegisterBarTextureListener(fn)
    if fn then _barTexListeners[#_barTexListeners + 1] = fn end
end
-- Canonical name: any global style change (texture, border, …) notifies these.
OUI.RegisterStyleListener = OUI.RegisterBarTextureListener
local function NotifyStyle()
    for _, fn in ipairs(_barTexListeners) do pcall(fn) end
end
OUI.NotifyStyle = NotifyStyle

-- Set the global default texture and notify every registered module to re-skin.
function OUI.SetGlobalBarTexture(key)
    if OUI.db and OUI.db.global then OUI.db.global.barTexture = key end
    NotifyStyle()
end

-------------------------------------------------------------------------------
--  Shared border style (colour + size), same 3-tier model as bar textures
-------------------------------------------------------------------------------
function OUI.GetGlobalBorderColor()
    local c = OUI.db and OUI.db.global and OUI.db.global.borderColor
    if c then return { c[1], c[2], c[3], c[4] or 1 } end
    return { 0, 0, 0, 0.9 }
end
function OUI.SetGlobalBorderColor(r, g, b, a)
    if OUI.db and OUI.db.global then OUI.db.global.borderColor = { r, g, b, a or 1 } end
    NotifyStyle()
end
function OUI.GetGlobalBorderSize()
    return (OUI.db and OUI.db.global and OUI.db.global.borderSize) or 1
end
function OUI.SetGlobalBorderSize(n)
    if OUI.db and OUI.db.global then OUI.db.global.borderSize = n end
    NotifyStyle()
end

-- Reusable 3-tier resolver for any per-module style system. Given a module's
-- profile, a key prefix, and a bar-type tag ("Health"/"Power"/…), returns which
-- scope's value should win: "type" (profile[prefix.."Override"..which] set),
-- else "all" (profile[prefix.."OverrideAll"] set), else "global". The module
-- then reads its own prefix..which / prefix.."All" keys, or the suite-global.
function OUI.ResolveStyleScope(profile, prefix, which)
    if profile[prefix .. "Override" .. which] then return "type" end
    if profile[prefix .. "OverrideAll"] then return "all" end
    return "global"
end

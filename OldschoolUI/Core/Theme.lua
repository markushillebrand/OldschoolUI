-- OldschoolUI / Core / Theme.lua
-- Theme + accent engine. One accent colour drives tabs, glows, highlights and
-- borders; registered elements recolour live on a theme switch. Account-wide
-- (db.global), so the whole client follows one theme by default.

local OUI = OldschoolUI

local DEFAULT = { r = 217/255, g = 164/255, b = 65/255 }   -- #D9A441 MoP gold

local PRESETS = {
    ["OldschoolUI"]    = { r = 217/255, g = 164/255, b = 65/255  },  -- #D9A441 gold
    ["Classic"]        = { r = 178/255, g = 145/255, b = 47/255  },  -- #B2912F brass
    ["Horde"]          = { r = 255/255, g = 90/255,  b = 31/255  },  -- #FF5A1F
    ["Alliance"]       = { r = 63/255,  g = 167/255, b = 255/255 },  -- #3FA7FF
    ["Faction (Auto)"] = nil,   -- resolved at runtime
    ["Dark"]           = { r = 1, g = 1, b = 1 },                    -- white accent
    ["Class Colored"]  = nil,   -- resolved from player class
    ["Custom Color"]   = nil,   -- user-picked
}

local ORDER = {
    "OldschoolUI", "Classic", "Horde", "Alliance",
    "Faction (Auto)", "Dark", "Class Colored", "Custom Color",
}

local MEDIA = "Interface\\AddOns\\OldschoolUI\\media\\"
local BG_FILES = {
    ["OldschoolUI"]   = MEDIA .. "backgrounds\\oui-bg-default",
    ["Classic"]       = MEDIA .. "backgrounds\\oui-bg-classic",
    ["Horde"]         = MEDIA .. "backgrounds\\oui-bg-horde",
    ["Alliance"]      = MEDIA .. "backgrounds\\oui-bg-alliance",
    ["Dark"]          = MEDIA .. "backgrounds\\oui-bg-dark",
    ["Class Colored"] = MEDIA .. "backgrounds\\oui-bg-default",
    ["Custom Color"]  = MEDIA .. "backgrounds\\oui-bg-default",
}

OUI.THEME_PRESETS  = PRESETS
OUI.THEME_ORDER    = ORDER
OUI.THEME_BG_FILES = BG_FILES

-- Live accent. Modules read OUI.ACCENT.r/g/b. Never replace the table; only its fields.
OUI.ACCENT = { r = DEFAULT.r, g = DEFAULT.g, b = DEFAULT.b }

local function ResolveFactionTheme(theme)
    if theme ~= "Faction (Auto)" then return theme end
    return (UnitFactionGroup("player") == "Horde") and "Horde" or "Alliance"
end
OUI.ResolveFactionTheme = ResolveFactionTheme

function OUI.GetPlayerClassColor()
    local _, class = UnitClass("player")
    return OUI.GetClassColor(class)
end

local CLASS_TOKENS = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
    "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "MONK", "DRUID" }
OUI.CLASS_TOKENS = CLASS_TOKENS

local function clamp01(v) if v < 0 then return 0 elseif v > 1 then return 1 end return v end

-- Class colour, 3-tier: module-profile override -> global override -> Blizzard,
-- then a brightness multiplier (module-local intensity -> global intensity).
-- `profile` is optional; pass a module's DB profile to honour its overrides.
function OUI.GetClassColor(token, profile)
    local glob = OUI.db and OUI.db.global
    local r, g, b
    local mo = profile and profile.classColors and profile.classColors[token]
    local go = glob and glob.classColors and glob.classColors[token]
    local base = mo or go
    if base then
        r, g, b = base.r or base[1], base.g or base[2], base.b or base[3]
    else
        local c = token and RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
        if c then r, g, b = c.r, c.g, c.b else r, g, b = 1, 1, 1 end
    end
    local intensity
    if profile and profile.colorIntensityOverride and profile.colorIntensity then
        intensity = profile.colorIntensity
    elseif glob and glob.colorIntensity then
        intensity = glob.colorIntensity
    else
        intensity = 1.0
    end
    if intensity and intensity ~= 1.0 then
        r, g, b = clamp01(r * intensity), clamp01(g * intensity), clamp01(b * intensity)
    end
    return r, g, b
end

function OUI.SetClassColor(token, r, g, b)
    if not (OUI.db and token) then return end
    OUI.db.global.classColors[token] = { r = r, g = g, b = b }
    if OUI.NotifyStyle then OUI.NotifyStyle() end
end

function OUI.ResetClassColor(token)
    if not (OUI.db and token) then return end
    OUI.db.global.classColors[token] = nil
    if OUI.NotifyStyle then OUI.NotifyStyle() end
end

function OUI.GetColorIntensity()
    return (OUI.db and OUI.db.global.colorIntensity) or 1.0
end

function OUI.SetColorIntensity(v)
    if OUI.db then OUI.db.global.colorIntensity = v end
    if OUI.NotifyStyle then OUI.NotifyStyle() end
end

-- Effective accent r,g,b from the saved theme.
function OUI.ResolveActiveAccent()
    local g = OUI.db and OUI.db.global or nil
    local theme = ResolveFactionTheme((g and g.activeTheme) or "OldschoolUI")

    if g and g.useClassAccentColor then
        return OUI.GetPlayerClassColor()
    elseif theme == "Custom Color" then
        local c = g and g.accentColor
        if c then return c.r, c.g, c.b end
        return DEFAULT.r, DEFAULT.g, DEFAULT.b
    elseif theme == "Class Colored" then
        return OUI.GetPlayerClassColor()
    else
        local p = PRESETS[theme]
        if p then return p.r, p.g, p.b end
        return DEFAULT.r, DEFAULT.g, DEFAULT.b
    end
end

-- ---- Accent registry: one-time-coloured elements recolour on theme switch ----
local registry = { _idx = {} }

-- entry = { type="solid"|"vertex"|"font"|"gradient"|"callback", obj=, fn=, a=, ... }
local function RegAccent(entry)
    local key = entry.obj or entry.fn
    if key and registry._idx[key] then
        registry[registry._idx[key]] = entry
    else
        registry[#registry + 1] = entry
        if key then registry._idx[key] = #registry end
    end
end
OUI.RegAccent = RegAccent

local function ApplyToElement(e, r, g, b)
    local t = e.type
    if t == "solid" then
        if e.obj.SetColorTexture then
            e.obj:SetColorTexture(r, g, b, e.a or 1)
        elseif e.obj.SetVertexColor then
            e.obj:SetVertexColor(r, g, b, e.a or 1)
        end
    elseif t == "vertex" then
        e.obj:SetVertexColor(r, g, b, e.a or 1)
    elseif t == "font" then
        e.obj:SetTextColor(r, g, b, e.a or 1)
    elseif t == "gradient" then
        local sA, eA = e.startA or 0.15, e.endA or 0
        local obj = e.obj
        if obj.SetColorTexture then obj:SetColorTexture(1, 1, 1, 1) end
        if obj.SetGradient and CreateColor then
            obj:SetGradient(e.dir or "HORIZONTAL", CreateColor(r, g, b, sA), CreateColor(r, g, b, eA))
        elseif obj.SetGradientAlpha then
            obj:SetGradientAlpha(e.dir or "HORIZONTAL", r, g, b, sA, r, g, b, eA)
        end
    elseif t == "callback" then
        if e.fn then e.fn(r, g, b) end
    end
end

local function UpdateAccentElements(r, g, b)
    for i = 1, #registry do
        local e = registry[i]
        if e then ApplyToElement(e, r, g, b) end
    end
end
OUI.UpdateAccentElements = UpdateAccentElements

-- Push r,g,b into the live accent and recolour everything registered.
local function ApplyAccentLive(r, g, b)
    OUI.ACCENT.r, OUI.ACCENT.g, OUI.ACCENT.b = r, g, b
    UpdateAccentElements(r, g, b)
end
OUI.ApplyAccentColorLive = ApplyAccentLive

function OUI.GetAccentColor()
    return OUI.ACCENT.r, OUI.ACCENT.g, OUI.ACCENT.b
end

function OUI.GetActiveTheme()
    local g = OUI.db and OUI.db.global
    return (g and g.activeTheme) or "OldschoolUI"
end

function OUI.RefreshAccent()
    ApplyAccentLive(OUI.ResolveActiveAccent())
end

function OUI.SetActiveTheme(theme)
    if OUI.db then OUI.db.global.activeTheme = theme end
    OUI.RefreshAccent()
end

function OUI.SetAccentColor(r, g, b)
    if OUI.db then
        OUI.db.global.activeTheme         = "Custom Color"
        OUI.db.global.accentColor         = { r = r, g = g, b = b }
        OUI.db.global.useClassAccentColor = false
    end
    ApplyAccentLive(r, g, b)
end

function OUI.ResetAccentColor()
    if OUI.db then OUI.db.global.accentColor = nil end
    OUI.RefreshAccent()
end

function OUI.ResetTheme()
    if OUI.db then
        OUI.db.global.activeTheme         = "OldschoolUI"
        OUI.db.global.accentColor         = nil
        OUI.db.global.useClassAccentColor = false
    end
    OUI.RefreshAccent()
end

function OUI.DarkenColor(r, g, b, frac)
    frac = frac or 0.5
    return r * frac, g * frac, b * frac
end

-- Resolve the accent once SavedVariables are up (called by Bootstrap.OnInitialize).
function OUI._InitTheme()
    ApplyAccentLive(OUI.ResolveActiveAccent())
end

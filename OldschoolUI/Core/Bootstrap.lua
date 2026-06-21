-- OldschoolUI / Core / Bootstrap.lua
-- Foundation: namespace, Ace3 addon object, SavedVariables via AceDB, and the
-- deferred init that brings up i18n + theme once SavedVariables are loaded.

local ADDON_NAME, NS = ...

local AceAddon = LibStub("AceAddon-3.0")
local AceDB    = LibStub("AceDB-3.0")

-- One global table + a short alias. Modules may reference either.
local OUI = AceAddon:NewAddon("OldschoolUI", "AceEvent-3.0")
_G.OldschoolUI = OUI
_G.OUI         = OUI
NS.OUI         = OUI

OUI.ADDON_NAME = ADDON_NAME
OUI.VERSION    = "@project-version@"   -- substituted by the packager on tag-push

-- Account-wide defaults. Theme/accent/locale live in `global`, so one
-- client-wide profile is the out-of-the-box behaviour; the per-character
-- scope toggle is layered on top of this in the later profile pass.
local DEFAULTS = {
    global = {
        activeTheme         = "OldschoolUI",
        accentColor         = nil,        -- {r,g,b}; only when activeTheme == "Custom Color"
        useClassAccentColor = false,
        displayLocale       = "auto",     -- "auto" | locale code
        scope               = "global",   -- "global" | "character"
        barTexture          = "flat",      -- shared default status-bar texture key
        borderColor         = { 0, 0, 0, 0.9 }, -- shared default border colour
        borderSize          = 1,           -- shared default border thickness (px)
        classColors         = {},          -- [CLASS]={r,g,b} global per-class overrides (empty = Blizzard)
        colorIntensity      = 1.0,         -- global class-colour brightness multiplier
    },
    char = {},
}

function OUI:Print(...)
    print("|cffD9A441OldschoolUI|r:", ...)
end

function OUI:OnInitialize()
    self.db = AceDB:New("OldschoolUIDB", DEFAULTS)

    -- Subsystems, in dependency order, now that SavedVariables exist.
    if self._InitLocale then self:_InitLocale() end   -- re-resolve with displayLocale override
    if self._InitTheme  then self:_InitTheme()  end   -- resolve OUI.ACCENT from db
end

function OUI:OnEnable()
    if self._InitOptions then self:_InitOptions() end
end

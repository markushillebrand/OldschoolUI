-- OldschoolUI / Core / Bootstrap.lua
-- Namespace + Ace3 addon object. Global: OldschoolUI, alias OUI.
-- (Pass 1 implementation goes here.)
local ADDON, ns = ...

local OldschoolUI = LibStub("AceAddon-3.0"):NewAddon("OldschoolUI", "AceEvent-3.0")
_G.OldschoolUI = OldschoolUI
_G.OUI        = OldschoolUI   -- alias
ns.OUI = OldschoolUI

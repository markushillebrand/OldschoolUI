# OldschoolUI (OUI)

A clean, MoP-Classic (interface 50504) UI suite. Independent rewrite — own code,
Ace3 (MIT) embedded.

## Structure
- `OldschoolUI/` — Core addon (namespace `OldschoolUI`, alias `OUI`)
  - `Libs/` — Ace3 stack (pulled at build via `.pkgmeta` externals)
  - `Core/` — Bootstrap, Locale, Theme, Widgets, Options, ...
  - `Locales/` — `deDE.lua` (+ user-contributed locales via `RegisterLocale`)
  - `media/`
- `OUI_<Module>/` — suite modules (added per build pass)

# OldschoolUI (OUI)

A clean, MoP-Classic (interface 50504) UI suite. Ace3 (MIT) embedded

## Structure
- `OldschoolUI/` — Core addon (namespace `OldschoolUI`, alias `OUI`)
  - `Libs/` — Ace3 stack (pulled at build via `.pkgmeta` externals)
  - `Core/` — Bootstrap, Locale, Theme, Widgets, Options, ...
  - `Locales/` — `deDE.lua` (+ user-contributed locales via `RegisterLocale`)
  - `media/`
- `OUI_<Module>/` — suite modules (added per build pass)

## Build / Release
CI = BigWigs packager on tag-push (substitutes `## Version: @project-version@`).
Locale files: UTF-8 **without** BOM. Every Lua file must pass `luac5.1 -p`.

## License
Own code: see LICENSE. Bundled Ace3 retains its own MIT license.

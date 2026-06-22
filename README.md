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

## Build / Release
CI = BigWigs packager on tag-push (substitutes `## Version: @project-version@`).
Locale files: UTF-8 **without** BOM. Every Lua file must pass `luac5.1 -p`.

### What ships vs. what doesn't
- **Release artifacts** (CI addon zip, source release): addon folders
  (`OldschoolUI/` + `OUI_*`), `README.md`, `LICENSE`, `CHANGELOG.md`,
  `DESCRIPTION.md`, `.github/`, `.pkgmeta`, `.gitignore`, `.gitattributes`.
- **Development-only — never shipped:** `OUI_Probe/` (diagnostic addon) and
  `dev/` (internal handovers/notes). Both are excluded via `.pkgmeta ignore`
  and from the release build below. `DESCRIPTION.md` is the CurseForge project
  page; `CHANGELOG.md` feeds the GitHub/CurseForge release notes.

### Manual builds
Release zip (addon + GitHub files, no dev data):
```
zip -rq OldschoolUI-<version>.zip . \
  -x "*.zip" -x "OUI_Probe/*" -x "dev/*" \
  -x ".release/*" -x "dist/*" -x "tmp/*" -x "*.bak"
```

## License
Own code: see LICENSE. Bundled Ace3 retains its own MIT license.

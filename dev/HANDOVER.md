# OUI — Internal Dev Handover

> **DEVELOPMENT-ONLY.** This folder is excluded from every release artifact
> (`.pkgmeta ignore` + the in-chat release build excludes `dev/`). Never ship it.

This file carries project state and conventions between work sessions. The
**only source of truth for code is the newest ZIP** — the build container is
wiped between sessions; memory/handover carry context, not code.

---

## Project

- **OldschoolUI (OUI)** — clean-room rebrand/rewrite of EllesmereUI for **WoW
  Classic Mists of Pandaria 5.5.x** (interface `50504`, modern engine).
- Author tag in every `.toc`: `Lyonthedragon`.
- Accent default gold `#D9A441`, but **all themed colour must route through
  `OUI.GetAccentColor()`** so the in-game "UI Accent Color" picker recolours the
  whole UI live.
- Namespace `OldschoolUI`, alias `OUI`. Ace3 (AceAddon/AceEvent/AceDB) is the
  only embedded external lib (in `Libs/`).

## Conventions (hard rules)

- Every Lua file must pass `luac5.1 -p` before delivery.
- English string literals via `OUI.L()` / `OUI.Lf()`; deDE in
  `OldschoolUI/Locales/deDE.lua` as `L["English"] = "Deutsch"`. German strings
  with inner quotes use typographic `„ "` (ASCII `"` breaks the Lua string).
- Locale files: UTF-8 **without** BOM.
- **Fingerprint sweep must be clean** (no upstream identifiers):
  ```
  grep -rniE "ellesmere|[^a-z]eui[^a-z]|_ebs|_elr|_erb" --include=*.lua . \
    | grep -vi Libs/ | grep -vi OUI_Probe/
  ```
- Clean-room rule: modules derived from upstream are rewritten fresh (own
  structure/naming/logic). Only code we authored ourselves is carried 1:1 (with
  a hygiene/naming sweep). WoW API calls are free to use.

## Module set (16 shipping + Core)

ActionBars, UnitFrames, RaidFrames, ResourceBars, Nameplates, Bags, Chat,
Friends, QoL, AuraBuffReminders, BlizzardSkin, DamageMeter, GroupTimer,
QuestTracker, LootRoll, Minimap. `OUI_Probe` is a dev-only diagnostic addon
(never shipped).

## Build commands (run in-chat)

**Dev handover ZIP — everything (incl. OUI_Probe + dev/):**
```
cd /home/claude/OldschoolUI && \
  zip -rq /mnt/user-data/outputs/OldschoolUI-DEV-handover.zip . -x "*.zip"
```

**Release ZIP — addon + GitHub files, NO development data:**
```
cd /home/claude/OldschoolUI && \
  zip -rq /mnt/user-data/outputs/OldschoolUI-<version>.zip . \
    -x "*.zip" -x "OUI_Probe/*" -x "dev/*" \
    -x ".release/*" -x "dist/*" -x "tmp/*" -x "*.bak"
```
Release contains: addon folders (Core + modules, **no OUI_Probe**), `README.md`,
`LICENSE`, `CHANGELOG.md`, `DESCRIPTION.md`, `.github/`, `.pkgmeta`,
`.gitignore`, `.gitattributes`. The CurseForge/GitHub CI (BigWigs packager,
`.github/workflows/release.yml`) builds the player-install addon zip on tag-push
and strips `*.md`/`.github`/`OUI_Probe`/`dev` via `.pkgmeta`.

**Validate before any delivery:**
```
for f in $(find . -name '*.lua' | grep -v /Libs/ | grep -v OUI_Probe); do luac5.1 -p "$f"; done
```

## Per-session protocol (consistency across chats)

1. New chat → upload the **newest ZIP** + this handover.
2. Unzip to `/home/claude/OldschoolUI/`, run full `luac` + fingerprint sweep →
   baseline confirmed.
3. Do the work package → `luac` + sweep + ZIP + `present_files`.
4. The delivered ZIP is the new baseline. **Never start from an old ZIP or from
   memory** — only the latest ZIP has the real code.

---

## CURRENT WORK PACKAGE — Config-menu redesign (cosmetic shell restyle)

Baseline ZIP: `OldschoolUI-NP6-classpower.zip` (cumulative: all bugfixes +
nameplate class-power).

Restyle the existing options shell (`OldschoolUI/Core/Options.lua` +
`Widgets.lua`) into the EllesmereUI look, fully accent-driven. No module-logic
changes except a 1-line guard (below).

Existing shell facts: `mainFrame` 720×620 centred; header `hb` 46px (emblem
`med` 24×24 + close); footer `fb` 44px; sidebar 192px, `RebuildSidebar()` with
category headers + module buttons (`e.bar` accent stripe, `e.bg`, `e.lbl`);
`SelectModule()` sets `content.title`/`content.desc`, `content.body:Reset()`,
`cfg.build(body)`; `content.scroll` exists. `RegisterModule(folder, {folder,
category, order, title, description, disabled, build})`. Widgets:
`OUI.Widgets.Toggle{label,tooltip,get,set}` / `Slider{...min,max,step...}` /
`Dropdown` / `ColorSwatch`. Helpers `Tex`/`Lbl`/`A()` (=accent). ESC button
(`_InitGameMenuButton`) + Move/Lock (`Core/Mover.lua` `ToggleUnlock` /
`EnsureLockButton`) already exist.

**Locked spec:**
1. Window bigger (~920 wide, more height); content scrollable (exists).
2. Header: accent **sweep** gradient + "O" emblem + title + close; sweep colour
   from `GetAccentColor()`.
3. Section labels: spaced small-caps (sentence case, letter-spacing, muted) —
   NOT all-caps.
4. Sidebar: per-module **"O" glyph** toggle: GREY = off, ACCENT = on. Active
   module = accent left-stripe + accent tint. Top: Edit Mode + Global Settings +
   search.
5. Widgets accent-driven: pill toggle (accent when on), slider (accent fill +
   value box), dropdown, colour swatch — **all colours via
   `GetAccentColor()`**.
6. **No tabs** this build (next build, after in-game verify of this one).
7. Footer: left `[Reset module] [Reload UI] [Move frames →
   OUI:Hide();OUI:ToggleUnlock(true)]`; right `[CurseForge link
   (ti-external-link equivalent — NO other socials)] [Done (accent button)]`.

**Module enable/disable (point 4 behaviour):**
- New: `OUI:IsModuleEnabled(folder)` + persistent flag table in the Core DB
  (default on).
- The "O" click **only sets the trigger (flag)** and immediately shows
  grey/accent; it takes effect **only after "Reload UI"**. Show a clear in-UI
  banner whenever a flag differs from the loaded state: *"Reload required to
  apply"*.
- Add a **1-line guard in every module `OnEnable`**:
  `if OUI.IsModuleEnabled and not OUI:IsModuleEnabled("OUI_Xxx") then return end`
  Modules: OUI_ActionBars, OUI_UnitFrames, OUI_RaidFrames, OUI_Bags,
  OUI_Nameplates, OUI_Chat, OUI_Friends, OUI_QoL, OUI_BlizzardSkin,
  OUI_AuraBuffReminders, OUI_DamageMeter, OUI_GroupTimer, OUI_QuestTracker,
  OUI_ResourceBars, OUI_LootRoll, OUI_Minimap. (Core is not toggleable.)
- No hot-unload/teardown this build (later).

**Mandatory translation pass before building:** every module `title` +
`description`, every section header, every widget label/tooltip, every new
button/banner string → ensure a deDE key exists; add the missing ones. Use the
Python scanner (extract `L()`/`Lf()` literals, diff vs. deDE keys).

**After:** checkpoint ZIP + `present_files` → in-game verify → tabs as the
follow-up build.

## Backlog (deferred)

- Tabs per module (next build): Nameplates → Allgemein/Klassenressource/Auren;
  Unitframes → Hauptrahmen/Mini-Rahmen/Spieler-Buffs.
- Custom-UI replacement (replace, not reskin): Collections/Mounts-Pets → Mail →
  Quest Log → Group Finder.
- Live per-module hot-disable (without reload).
- Eclipse direction verify on the new nameplate class-power (GetEclipseDirection
  vs. UnitPower sign).
- ActionBars round-button edge; minimap non-square mask distortion; BlizzardSkin
  mastery-stat tooltip — all deferred.
- Final project-wide fingerprint sweep before first tagged release.

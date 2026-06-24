# Changelog

All notable changes to OldschoolUI are documented here. Format based on
[Keep a Changelog](https://keepachangelog.com/); versions follow the tag pushed
to CI (the BigWigs packager substitutes `@project-version@` in every `.toc`).

## [1.1.0] - 2026-06-24

### Added
- **Blizzard frame reskin:** Merchant, Auction House, Spellbook, Talents, Group
  Finder, Guild, Dungeon Journal, Achievements, Inspect and more now match the
  OldschoolUI dark theme and are movable.
- **World Map:** opens in windowed (panel) mode by default instead of fullscreen.
- **Quest Log:** both the map quest panel and the classic quest-log window are
  reskinned (dark backgrounds, OldschoolUI border) and the classic window is
  movable.
- **Mail:** full dark reskin; the minimap mail indicator now clears once mail is
  collected.
- **Character sheet:** Currency and Reputation tabs reskinned to match; the
  Mastery stat tooltip now shows the specialization's mastery name and effect.
- **Nameplates – Class Power:** secondary resource shown above the target's
  nameplate (combo points, chi, holy power, shadow orbs, soul shards, burning
  embers, demonic fury, eclipse, death-knight runes). Options: show on/off, on
  target only, bar height.
- **Unit Frames:** hover tooltips on aura/buff icons.
- **Movers (`/ouimove`):** Resource Bars, Quest Tracker, Chat, Friends, Bags and
  Damage Meter windows are now repositionable; a floating "Lock frames" button
  and a "Move Frames" entry in the options footer.
- **Escape menu:** an OldschoolUI button in the game menu opens the options.
- **Theming:** a central skin background colour now drives the native frames
  reskinned by OldschoolUI, kept in sync with the chosen accent.

### Fixed
- **Bags:** main-bank item tooltips no longer flash and turn into a black box.
- **QoL:** the "screenshot captured" message is reliably suppressed, including
  the first screenshot of a session.
- **Aura/Buff Reminders:** corrected MoP raid-buff and flask spell IDs; added
  missing entries (Mark of the Wild, Dark Intent).
- **Quest Tracker / Group Timer:** mover and run-overlay fixes; reliable run
  completion, best-time and corpse-run continuity in Group Timer.
- **Minimap:** LFG/Group-Finder right-click context menu rebuilt for the modern
  client (MenuUtil).

### Notes
- Changelog started mid-development; entries predating this file are summarised
  by the initial scaffold below.

## [0.0.0] - scaffold
- Repo scaffold + Core foundation (Ace3, i18n, theme) and the full module suite
  built out across development passes.

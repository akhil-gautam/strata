# Shelfie

A widget bar for macOS that takes the Dock's place: app and folder launchers next to live tiles for time, calendar, weather, system stats, media, timers, AI coding agents and more.

Shelfie was called DockDock until 0.2.0.

Requires macOS 26 (Tahoe) or later.

## Install

```bash
brew trust akhil-gautam/tap
brew tap akhil-gautam/tap
brew install --cask shelfie
```

Shelfie is signed with a Developer ID but not notarized yet, so the cask removes the download quarantine flag. macOS may still ask you to confirm the first launch in System Settings › Privacy & Security.

## What it does

- **Bar:** bottom, left, right or hanging from the notch; auto-hide; 20 themes; drag tiles to reorder; pick a display or follow the pointer; hides over full-screen apps. Hides the macOS Dock while shown and restores it on quit.
- **Dock features:** pinned apps with running dots, notification badges, window lists, Hide / Quit / Force Quit; drop files on an app to open them; Running Apps and Trash tiles.
- **Tiles:** 110+ in the widget library: clocks and timers, calendar and reminders, weather, CPU / RAM / network / battery, now playing, clipboard history, screenshots, quick toggles, Keep Awake, a Settings gear, stocks, and service tiles (Stripe, Polar, DataFast, X, YouTube…).
- **Extensions** (Settings › Extensions):
  - **AI Usage:** Claude Code and Codex rate limits, token usage, and a live Agent Status tile for Claude Code, Codex and omp sessions.
  - **Script Tiles:** any executable in `~/Library/Application Support/Shelfie/Scripts` becomes a tile (xbar-style text or JSON). Scripts run only after you approve them.
- **Automation:** global shortcuts (⌃⌥D bar, ⌃⌥W widgets), `shelfie://` links (`show`, `hide`, `toggle`, `library`, `settings`, `focus/start`, `focus/pause`, `awake/on`, `awake/off`, `refresh`), launch at login.

Permissions are asked for only when a tile needs them (Calendar, Reminders, Photos, Contacts, Accessibility for badges and window lists, Automation for Mail and media players).

## Build from source

```bash
swift build -c release
scripts/build-app.sh release      # assembles and signs build/Shelfie.app
open build/Shelfie.app
```

Set `SHELFIE_NOTARY_PROFILE` to a `notarytool` keychain profile to notarize and staple the build.

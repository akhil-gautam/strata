<p align="center">
  <img src="Resources/AppIcon.svg" width="128" height="128" alt="Strata icon">
</p>

<h1 align="center">Strata</h1>

<p align="center">A widget bar for macOS that takes the Dock's place: app and folder launchers next to live tiles for time, calendar, weather, system stats, media, timers, AI coding agents and more.</p>

![Strata's bar at the bottom of the screen: clock, weather, focus timer, Codex limits, CPU chart, stock watchlist, Claude token count and Keep Awake](docs/screenshots/hero.jpg)

Strata was called Shelfie until 0.3.0, and DockDock before that.

Requires macOS 26 (Tahoe) or later.

## Install

```bash
brew trust akhil-gautam/tap
brew tap akhil-gautam/tap
brew install --cask strata
```

Strata is signed with a Developer ID but not notarized yet, so the cask removes the download quarantine flag. macOS may still ask you to confirm the first launch in System Settings › Privacy & Security.

## What it does

- **Bar:** bottom, left, right or hanging from the notch; auto-hide; 20 themes; drag tiles to reorder; pick a display or follow the pointer; hides over full-screen apps. Hides the macOS Dock while shown and restores it on quit.
- **Dock features:** pinned apps with running dots, notification badges, window lists, Hide / Quit / Force Quit; drop files on an app to open them; Running Apps and Trash tiles.
- **Tiles:** 110+ in the widget library: clocks and timers, calendar and reminders, weather, CPU / RAM / network / battery, now playing, clipboard history, screenshots, quick toggles, Keep Awake, a Settings gear, stocks, and service tiles (Stripe, Polar, DataFast, X, YouTube…).
- **Extensions** (Settings › Extensions):
  - **AI Usage:** Claude Code and Codex rate limits, token usage, and a live Agent Status tile for Claude Code, Codex and omp sessions.
  - **Script Tiles:** any executable in `~/Library/Application Support/Strata/Scripts` becomes a tile (xbar-style text or JSON). Scripts run only after you approve them.
- **Automation:** global shortcuts (⌃⌥D bar, ⌃⌥W widgets), `strata://` links (`show`, `hide`, `toggle`, `library`, `settings`, `focus/start`, `focus/pause`, `awake/on`, `awake/off`, `refresh`), launch at login.

Permissions are asked for only when a tile needs them (Calendar, Reminders, Photos, Contacts, Accessibility for badges and window lists, Automation for Mail and media players).

## A look around

**At the notch.** In Island style the bar folds into the camera housing. Hover and it opens with a soft glow; while it's closed, small "ears" beside the notch show what's going on: a coding agent that needs you, a focus timer, Keep Awake, music.

![The notch island open, showing the date, widgets and settings buttons above a row of tiles; below it, the closed island with a coffee cup and a Keep Awake countdown](docs/screenshots/island.jpg)

**Twenty themes.** Each one restyles the bar, its tiles, the widget library and every settings popover. Here are Midnight, Daylight, Paper, Nord and Sunset.

![The same bar in five themes: Midnight, Daylight, Paper, Nord and Sunset](docs/screenshots/themes.jpg)

**The widget library.** Search 110+ tiles and click one to add it. While the library is open, every bar tile shows a remove badge, and you can drag tiles to reorder them.

![The widget library filtered to "usage", showing Cursor and AI usage tiles, above the bar in edit mode](docs/screenshots/library.jpg)

**Any edge.** Put the bar at the bottom, the notch, or down the left or right side, where tiles pack into neat rows.

![A vertical bar on the left edge in the Dracula theme](docs/screenshots/vertical.jpg)

![The Themes page in Strata's Settings window](docs/screenshots/settings.jpg)

## Build from source

```bash
swift build -c release
scripts/build-app.sh release      # assembles and signs build/Strata.app
open build/Strata.app
```

Set `STRATA_NOTARY_PROFILE` to a `notarytool` keychain profile to notarize and staple the build.

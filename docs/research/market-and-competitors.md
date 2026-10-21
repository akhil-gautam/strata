# DockDock market research: Dock replacements, widget bars, and menu bar and notch utilities

Researched 2026-10-21. Every external claim links to a primary source (a vendor site or docs page, a GitHub repo or issue, a first-party Reddit or HN thread). Repo claims cite `file:line` in this repository. Anything inferred is marked **[INFERENCE]**.

How the data was collected:
- GitHub issue rankings come from `gh api search/issues … sort=reactions`, run on 2026-10-21.
- HN data comes from the Algolia HN API.
- Reddit blocked the scraper after a few page loads. Only the CoolDock threads were read in full; other Reddit sentiment is limited to the threads cited below.

---

## 1. CoolDock: the product DockDock clones

### 1.1 Identity, ownership and distribution
| Item | Fact | Source |
|---|---|---|
| Pitch | "A second Dock for your Mac, with 160+ live widgets." It sits beside the original Dock, and you can choose 7 layouts, from a floating panel to a full Dock replacement with auto-hide | https://www.tinylaunch.com/launch/23322-cooldock |
| Original developer | Solt Wagner. Appit Studio bought the app on 2026-09-02 | https://cooldock.app/updates |
| Sibling apps (Appit Studio) | DockFlow, ExtraDock, ExtraBar, Shiori. CoolDock is their "third Mac dock application" | https://cooldock.app/updates, https://www.reddit.com/r/macapps/comments/1wfbhxk/cooldock_your_smart_second_dock_of_widgets/ |
| Positioning vs. their own ExtraDock | CoolDock is "a widget app"; showing apps was "just a user request". ExtraDock is about many docks and multiple screens. The stated plan is to turn CoolDock's widgets into a library that both apps use | https://www.reddit.com/r/macapps/comments/1x53gs1/cooldock_mac_widgets_that_live_where_you_can_see/ |
| Distribution | Direct DMG hosted on GitHub releases (`AppitStudio/cooldock-updates`). No Mac App Store listing was found **[INFERENCE]** | https://github.com/AppitStudio/cooldock-updates/releases/latest/download/CoolDock.dmg |
| Requirements | macOS 14 Sonoma or later, Apple Silicon and Intel. The developer says it supports "up to and including Golden Gate" (macOS 27) | https://www.tinylaunch.com/launch/23322-cooldock, https://www.reddit.com/r/macapps/comments/1x53gs1/cooldock_mac_widgets_that_live_where_you_can_see/ |
| Recognition | Listed on Awwwards. TinyLaunch "1st Place" | https://www.awwwards.com/sites/cooldock, https://www.tinylaunch.com/launch/23322-cooldock |
| Product Hunt | Product page exists with 11 followers (search snippet) | https://www.producthunt.com/products/cooldock |

### 1.2 Pricing and licensing
Prices shown on cooldock.app on 2026-10-21:

| Tier | Price | Terms |
|---|---|---|
| One Year License | €14.99 | 1 Mac. Expires after 12 months and does not auto-renew |
| Lifetime Access | €29.99 per device (was €39.99), for 1, 2 or 3 devices | The app keeps working forever, but only 1 year of updates is included |
| Forever Edition | €99.99 | Up to 5 Macs, all future updates and versions |
| All tiers | 14-day money-back guarantee | — |

Source: https://cooldock.app/

Other licensing facts:
- **Price history.** Before the acquisition the site offered "1 device / 2 devices / 3 devices: $15 / $29" (search snippet dated Jun 17, https://www.dock.cool/). A month ago the r/macapps post said "$15 Lifetime license & lifetime updates". The terms have since moved to one year of updates (https://www.reddit.com/r/macapps/comments/1wfbhxk/cooldock_your_smart_second_dock_of_widgets/).
- **No free trial**, only refunds. Developer: "no free trial but there's a money back guarantee" (same thread).
- **Activation** is through Keyper or Polar keys and needs an internet connection. A Keyper key counts seats; a Polar key works on one Mac at a time (https://cooldock.app/docs/license).
- **Weekly releases**, per the developer: "We release weekly updates" (https://www.reddit.com/r/macapps/comments/1x53gs1/cooldock_mac_widgets_that_live_where_you_can_see/).

### 1.3 Full feature list
| Area | What CoolDock ships | Source |
|---|---|---|
| Layouts | Swap at the Bottom (recommended: CoolDock shows while the auto-hidden macOS Dock is away), Reveal at the Bottom, Fixed (6 screen positions), Reveal on Top, Replace the macOS Dock, Replace & Auto-Hide, Floating | https://cooldock.app/docs/layout |
| Placement controls | Distance from the edge; alignment; show and hide delay (up to 2 s); trigger-area size (3 px by default, 20–40 px suggested when stacked above the macOS Dock) | https://cooldock.app/docs/layout, https://cooldock.app/roadmap |
| Window space | Overlay Windows (the default, no permission), or Reserve Dock Space, which moves and resizes other windows through Accessibility. Also After Dragging | https://cooldock.app/docs/layout |
| Hide behaviours | Hide on Window Hover (fades out and lets clicks pass through). Hide During Fullscreen (needs Accessibility). Reset Layout recovery | https://cooldock.app/docs/layout, https://cooldock.app/updates |
| Screens | One Display, Attached Displays (priority list), or All Displays (one copy per display, same profile). Displays are remembered across sleep and clamshell mode; identical monitors can be named | https://cooldock.app/docs/screens |
| Profiles | Up to 8. Switch with a swipe or drag on the bar, a tab strip on hover, or the ⌃⌥⌘+number hotkey. Running apps can be shown in selected profiles only | https://cooldock.app/docs/profiles, https://cooldock.app/docs/shortcuts |
| Dock-replacement basics | Running apps with dots and badges (badges like "99+" render correctly; web apps show up), native-style right-click menus (New Window, browser profiles, Open Recent), window previews with auto-hide, drag to rearrange, folder colours, stacks with breadcrumbs, spacers and separators | https://cooldock.app/updates |
| Interaction model | Click for the main action or a mini window; hover for a label or preview; right-click for configure, refresh and remove | https://cooldock.app/docs/widgets |
| Appearance | Light Glass, Dark Glass, Liquid Glass on macOS 26, and 150–170+ wallpapers from Backgrounds.Supply | https://www.tinylaunch.com/launch/23322-cooldock, https://cooldock.app/ |
| AI Assistant (v2.1.0) | A local MCP server for Claude, Codex, Cursor, VS Code and Claude Desktop. Read-only by default; "Allow changes" asks for approval per action; a "YOLO mode" exists. Ships a `cooldock-assistant` skill and undo for AI changes. Tools are grouped as dock, widgets, apps, system, runtime, content, windows, providers, home, files_media, wallpapers, recovery | https://cooldock.app/docs/aiassistant, https://cooldock.app/updates |
| Credential storage | macOS Keychain, or an encrypted local file. Removing a widget does not delete its credentials | https://cooldock.app/docs/integrations, https://cooldock.app/docs/permissions |
| Permissions | Each permission is requested only when a feature needs it, and Settings → Privacy groups them by feature (Accessibility, Screen Recording, Calendar, Contacts, Mail and Notes Automation, Photos, Location, Mic, Bluetooth, Finder Automation, clipboard) | https://cooldock.app/docs/permissions |
| Support tooling | Export Diagnostics: a redacted local report with no tokens, URLs or paths | https://cooldock.app/updates |
| Privacy | "Local first", "Privacy first", no telemetry | https://cooldock.app/, https://cooldock.app/updates |

### 1.4 Widget catalogue (160+ widgets in 20 categories)
From https://cooldock.app/docs/widgets, https://cooldock.app/docs/integrations and https://cooldock.app/:

| Category | Widgets |
|---|---|
| Apps | featured apps, More Apps, Applications, Trash, App Switcher |
| Folders | common folders, More Folders, Files & Downloads, File Shelf, Search, Dropbox |
| Social | X, TikTok, YouTube, YouTube Studio, X Studio |
| Finance and commerce | Polar, Stripe, Dodo Payments; Shopify revenue, overview and trends; stocks and crypto quotes, charts and watchlists |
| AI | Plan and API usage for Claude, Codex, Claude Code, Cursor (incl. Personal), Antigravity, GLM/Z.ai, Grok, OpenCode, GitHub Copilot, Gemini, Perplexity |
| Analytics | DataFast, Simple Analytics, Plausible, Supabase, GitHub, Resend, Dub; Linear tasks |
| Clocks | time, date, timers, stopwatch, Pomodoro, posture, world clocks, analog, flip and pixel styles |
| Calendar | events, agendas, meetings, Zoom Meeting, day, month and year progress |
| Personal | Reminders, Todo, Habit Tracker, Quick Contacts, Notes, Mail and Gmail, Bookmarks |
| Media | Now Playing (any system player, YouTube tab control), YouTube Video, Background Sounds, App Volume, AirPods, Apple Watch |
| Photos | Recent Photo, Wallpaper |
| System | battery, CPU, RAM, temperature, network, storage, audio, clipboard, screenshots, Quick Toggles, Emoji, Voice Memo, Converter, Calculator, Color Picker, Separator, Space, Keyboard Lock, Drink Water |
| Home | Home controls (the AI tool group "home") |

Some widgets appear only when relevant: AirPods and Apple Watch while connected, Battery on laptops (https://cooldock.app/docs/widgets).

### 1.5 Release cadence (from https://cooldock.app/updates)
| Date (2026) | Version | Highlights |
|---|---|---|
| Jun 22 | Launch | Widgets, apps, folders, quick actions |
| Jun 24 | 1.2 | GitHub, Resend, Shopify, Linear, Dropbox, Dub, Supabase, Plausible, Dodo widgets; wallpapers |
| Jul 21 | 1.3 / 1.4 / 1.6 (posted together) | Profiles, Liquid Glass, running apps, custom folders, Claude, Crypto, Todo and Zoom widgets, Window Manager |
| Aug 7 | 1.8 | Native right-click menus, folder colours, folder search and breadcrumbs, Habit Tracker, temperature |
| Sep 2 | 2.0.0 | Appit Studio acquisition; new licensing and update system |
| Sep 3–27 | 2.0.2 → 2.0.9 (7 releases) | Keychain-prompt fixes; Screens pane; diagnostics; more AI usage widgets; Now Playing for any player; app menus; performance work |
| Oct 1 | 2.1.0 | MCP AI Assistant, Hide on Window Hover, drag to rearrange, per-display docks |
| Oct 5 | 2.1.1 | Lower idle CPU; M5 temperature readings |
| Oct 12 | 2.2.0 | Browser-profile windows, Space-correct new windows, badge accuracy |

About 11 releases in the 6 weeks after the acquisition, which fits "weekly updates".

### 1.6 What users praise
- Testimonials on the site: "replaced my default dock entirely… the kind of dock Apple should have built"; "functional, fast, or sexy… all three"; "easily a $50 product" once "the rough edges get smoothened out"; and "I wish to have widget for Structured" (https://cooldock.app/).
- Reddit replies: "This looks super well polished!"; "feels like a car dashboard on the Mac"; "could be the new improved touchbar" (https://www.reddit.com/r/macapps/comments/1wfbhxk/cooldock_your_smart_second_dock_of_widgets/).

### 1.7 Complaints and requests
**Pricing.** All in https://www.reddit.com/r/macapps/comments/1x53gs1/cooldock_mac_widgets_that_live_where_you_can_see/ unless noted:
- "$34 and only a year of updates? 😂"
- "lifetime access with only a year of updates?!! Hard pass"
- "Lifetime with hook 1 year of updates feels a bit wacky… it's an addon, eyecandy"
- The lack of a trial worries buyers: "Would love to try this but been burned in the past" (https://www.reddit.com/r/macapps/comments/1wfbhxk/cooldock_your_smart_second_dock_of_widgets/).

**Questions raised in that thread:**
- Do integrations update in real time? (No: "They poll on specific intervals".)
- Can each monitor have different widgets? ("right now you can't… going on the roadmap")
- Can it be vertical? ("Pour le moment il n'y a pas de mode vertical, uniquement en haut ou en bas", i.e. not yet, only top or bottom)
- Will it support other players such as Qobuz? ("depends on Qobuz")
- Sources: the same 1x53gs1 thread, and the 1wfbhxk thread for the vertical and Qobuz answers.

**Public roadmap**, votes in brackets (https://cooldock.app/roadmap):
- Community-created or importable widgets [13]: the top request.
- Layout and display: bar overlaps app windows [6]; fit width without scrolling [5]; hide in fullscreen [5]; adjustable hide and show speed [5]; show and hide in sync with the macOS Dock [5]; profiles that also store appearance and position [5]; vertical layout next to the native Dock [1]; different profiles on different docks at once [1]; copy layouts between Macs [0]. Many reports that Reserve Dock Space breaks on multiple monitors and in Mission Control.
- Apps and windows: folders and sorting in the app drawer [6]; a dedicated view for minimized windows [4]; active-app indicator inside folders [3].
- Widgets: Big Clock AM/PM [4]; Fahrenheit [4]; Habit tracker [4]; Home Assistant [3]; Teams controls [2]; show a widget only when relevant, e.g. music playing or meetings left today [1+1]; "Claude active session if agent is running / waiting for authorisation" [1]; Slack DM counts [1]; GPU widget; Google Tasks.
- Bugs: wrong album art [4]; Liquid Glass white border on macOS 27 [3+3]; widgets take about 10 s to reflect state [2]; Mail widget counts trash [2]; "Mail Unavailable"; laggy horizontal scrolling [1]; Shopify settings popover closes when focus leaves, so tokens can't be pasted [0].

**Keychain friction (relevant to DockDock's AI Usage tiles).** CoolDock fixed repeated Claude Keychain prompts in 2.0.3 and migration prompts in 2.0.2, then added encrypted-file storage because some login keychains "cannot be unlocked reliably" (https://cooldock.app/updates).

### 1.8 Where DockDock can beat CoolDock on real usefulness
Rows are grounded in DockDock code (cited) and CoolDock evidence (linked):

| # | Opportunity | CoolDock today | DockDock today | Why it matters |
|---|---|---|---|---|
| 1 | **Vertical left and right bars (DockDock already has them)** | Top or bottom only; vertical is a roadmap item ([reddit](https://www.reddit.com/r/macapps/comments/1wfbhxk/cooldock_your_smart_second_dock_of_widgets/), [roadmap](https://cooldock.app/roadmap)) | `bottom`, `left`, `right`, `notch` positions (`Sources/DockDock/Tiles/Theme.swift:7-15`) | Vertical docks use space that 16:10 and ultrawide screens otherwise waste ([ActiveDock review quote](https://noteifyapp.com/activedock/)). Make every tile lay out properly when vertical (see the DockDoor Pro SDK's `orientations`). |
| 2 | **Live agent status, not just plan usage** | Usage widgets only; "Claude active session / waiting for authorisation" is a 1-vote request ([roadmap](https://cooldock.app/roadmap)) | Claude and Codex limits, plus local token logs (`Sources/DockDock/Services/AIUsageSources.swift:62-66`) | A dock tile that turns orange when Claude Code or Codex needs permission, and shows running, idle or done per session, is something no competitor offers **[INFERENCE]**. |
| 3 | **Event-driven freshness** | Integrations poll "on specific intervals"; the bug list says widgets lag about 10 s ([reddit](https://www.reddit.com/r/macapps/comments/1x53gs1/cooldock_mac_widgets_that_live_where_you_can_see/), [roadmap](https://cooldock.app/roadmap)) | Polling loops (plan step 5) | Use push sources where they exist: `MRMediaRemote`/Now Playing notifications, EventKit change notifications, FSEvents on `~/.claude` and `~/.codex`, `NSWorkspace` notifications. Feeling instant is the main thing that separates a glance surface from a gimmick. |
| 4 | **A fair licence with a trial** | One-year licence, or "lifetime" with one year of updates; no trial; widely mocked ([reddit](https://www.reddit.com/r/macapps/comments/1x53gs1/cooldock_mac_widgets_that_live_where_you_can_see/)) | — | Ship a 7–14-day trial plus a perpetual licence with ≥2 years of updates, or a major-version licence (see §4d). The boringBar HN thread shows the backlash and the fix ([HN](https://news.ycombinator.com/item?id=47743992)). |
| 5 | **Contextual or conditional tiles** | Requested, not built ([roadmap](https://cooldock.app/roadmap)) | Fixed tile list | Show Now Playing only while audio plays, Calendar only while meetings remain, the AI tile only while an agent runs, Battery only below 20%. That keeps a fixed-height bar dense and relevant. Smart Stacks in Docky are a related idea ([Docky](https://github.com/josejuanqm/docky)). |
| 6 | **Third-party widget SDK** | #1 request [13 votes], not shipped ([roadmap](https://cooldock.app/roadmap)) | Compiled-in extensions (plan: `DockExtension`) | DockDoor Pro (open-source reviewed marketplace + `DockDoorWidgetSDK`) and Docky (`.dockywidget` bundles) already have this ([DockDoor Pro SDK](https://github.com/ejbills/dockdoorpro-widgets/blob/main/CONTRIBUTING.md), [Docky](https://github.com/josejuanqm/docky/blob/main/docs/external-widgets.md)). A no-code "script tile" (shell command plus refresh interval, like Übersicht or SketchyBar) is cheaper and covers most cases ([Übersicht](http://tracesof.net/uebersicht)). |
| 7 | **Multiple displays** | All Displays mirrors one profile; per-monitor widgets are on the roadmap ([docs](https://cooldock.app/docs/screens), [reddit](https://www.reddit.com/r/macapps/comments/1x53gs1/cooldock_mac_widgets_that_live_where_you_can_see/)) | Bar is placed on `NSScreen.screens.first` only (`Sources/DockDock/Panel/DockBarController.swift:336-337`) | This is a gap for DockDock. Doing a different bar per display *at once* would leapfrog CoolDock. |
| 8 | **Window previews and a switcher** | Has previews and an App Switcher ([updates](https://cooldock.app/updates)) | None: no `ScreenCaptureKit` or `AXUIElement` references in `Sources/` (grep) | Table stakes for replacing the Dock (§4b). If DockDock hides the Dock, it needs previews or it loses the window-finding job. |
| 9 | **Any Now Playing source** | Any system Now Playing app, plus YouTube tab control ([updates 2.0.7](https://cooldock.app/updates)) | Spotify and Apple Music only (`Sources/DockDock/Services/NowPlayingService.swift:47-49`) | Gap. Users ask about Qobuz, Cider and Dia ([reddit](https://www.reddit.com/r/macapps/comments/1wfbhxk/cooldock_your_smart_second_dock_of_widgets/), [roadmap](https://cooldock.app/roadmap)). |
| 10 | **Reliability of the replacement-Dock basics** | Many open Reserve Space, fullscreen and multi-monitor bugs ([roadmap](https://cooldock.app/roadmap)) | Auto-hides the macOS Dock via the `com.apple.dock autohide` default and `killall Dock` (`Sources/DockDock/Services/SystemDock.swift:9-18`); running-app tracking (`Sources/DockDock/Tiles/AppsTiles.swift:275-293`) | Win on boring correctness: fullscreen hide, Spaces, sleep and wake, badges ("number one issue" for dock switchers, [HN](https://news.ycombinator.com/item?id=47742920)). |
| 11 | **Local-first developer tiles** | AI and dev widgets need pasted API tokens ([integrations](https://cooldock.app/docs/integrations)) | Reads local Claude Code and Codex state with no token (plan) | Extend the same idea to local data: git status of the frontmost repo, CI status via `gh`, localhost port monitor, Docker containers, Xcode build state **[INFERENCE]**. |

---

## 2. Per-product table

Stars and issue data were captured from GitHub on 2026-10-21.

| Product | Core value | Killer features | Pricing / distribution | Extension model | Top praise / complaints |
|---|---|---|---|---|---|
| **uBar** | A Windows-style taskbar or dock for the Mac ([site](https://ubarapp.com/)) | Per-monitor bars, window previews, grouping, app flashes and progress, CPU/RAM per app on ⌃, up to 5 rows, "Hey uBar" Command ([site](https://ubarapp.com/)) | $39 Personal (2 Macs), $69 Commercial, 14-day trial, direct sale. uBar Cloud $2.99/mo ([site](https://ubarapp.com/)) | None | The "stuck the longest" with an HN user, who still went back to the Dock over notification-badge bugs ([HN](https://news.ycombinator.com/item?id=47742920)) |
| **ActiveDock 2** | Dock plus Launchpad replacement ([site](https://noteifyapp.com/activedock/)) | Window previews, Start Menu, groups and folders, themes, custom icons, multiple monitors ([site](https://noteifyapp.com/activedock/)) | One-time purchase (Pro Lifetime $59.99 on FastSpring), 14-day trial ([store](https://sites.fastspring.com/noteifyapp/product/activedock2)) | Themes only | Recent fixes for licences showing as an expired trial and for preview crashes ([site changelog](https://noteifyapp.com/activedock/)) |
| **DockDoor** (free) | Window previews and Alt-Tab for the stock Dock ([repo](https://github.com/ejbills/DockDoor)) | Hover previews (incl. other Spaces and minimized windows), ⌥Tab window switcher, ⌘Tab with windows, Folder Pop, music controls with lyrics, AppleScript and CLI ([repo](https://github.com/ejbills/DockDoor)) | Free, GPL-3.0, 6.4k★ ([repo](https://github.com/ejbills/DockDoor)) | — | Top issues: shortcut modifier [17], settings backup [14], preview stuck open on fast mouse moves [12], a paid clone on the App Store [6] ([issues](https://github.com/ejbills/DockDoor/issues/1254), [#688](https://github.com/ejbills/DockDoor/issues/688), [#1097](https://github.com/ejbills/DockDoor/issues/1097)) |
| **DockDoor Pro** | "The whole Dock, rebuilt" ([site](https://pro.dockdoor.net/)) | ~50 widgets, profiles with AppSense (switches when an app comes forward), one dock per display, Minimize Into Dock, file tray, 217 features, full network disclosure ([site](https://pro.dockdoor.net/)) | $20 once for 3 Macs, all future updates, 14-day refund, Gumroad and Homebrew ([site](https://pro.dockdoor.net/)) | **Widget marketplace**: open-source, reviewed Swift bundles, settings schema rendered by the host, horizontal and vertical orientations ([SDK](https://github.com/ejbills/dockdoorpro-widgets/blob/main/CONTRIBUTING.md)) | "Most of DockDoor Pro starts switched off", which needed an 11-minute settings tour ([site](https://pro.dockdoor.net/)) |
| **Dockish** | Cheap per-monitor dock ([Appish](https://appish.app/blog/mac-dock-replacement-apps-compared)) | Dock on every display, iOS-style folders, profiles that follow displays | $6.99 once (rising to $9.99), 7-day trial ([Appish](https://appish.app/blog/mac-dock-replacement-apps-compared)) | — | — |
| **DockFix** | A fully customizable Dock replacement ([site](https://www.dockfix.app/)) | Native-identical magnification and Liquid Glass, custom icons, community presets, widgets, previews, <1% CPU ([site](https://www.dockfix.app/)) | €14.99 once, 7-day trial, 30% student discount ([site](https://www.dockfix.app/)) | Community presets | The rewrite thread drew 262 upvotes and 192 comments (title in [related list](https://www.reddit.com/r/macapps/comments/1warxaj/i_spent_months_rebuilding_dockfix_from_the_ground/)) |
| **Docky** | Free and open-source Dock replacement ([repo](https://github.com/josejuanqm/docky)) | Smart Stacks, Launchpad, live window switcher, scripted actions, themes and profiles ([repo](https://github.com/josejuanqm/docky)) | Free, GPL-3.0, 1.4k★; sponsors. Uses private APIs, so no App Store ([repo](https://github.com/josejuanqm/docky)) | `.dockywidget` native bundles loaded from `~/Library/Application Support/Docky/Widgets` ([doc](https://github.com/josejuanqm/docky/blob/main/docs/external-widgets.md)) | The "Docky is now free and open source" post reached 2.1K upvotes ([thread](https://www.reddit.com/r/MacOSApps/comments/1ufbsl5/fck_it_docky_is_now_free_and_open_source/)) |
| **docktor** | Widgets in the empty space beside the stock Dock ([site](https://docktorapp.com/)) | Previews, ⌘Tab with thumbnails, music with lyrics and Apple Music browsing, calendar countdown that auto-opens the meeting link, Open-Meteo weather, stats, device batteries, per-widget keyboard shortcuts ([site](https://docktorapp.com/)) | Free beta, Buy Me a Coffee, macOS 26+ ([site](https://docktorapp.com/)) | — | "Setup asks for nothing"; permissions are requested only when needed; in-app community forum ([site](https://docktorapp.com/)) |
| **ExtraDock** (Appit) | Unlimited docks on any screen ([site](https://extradock.app/)) | Per-dock style, edge or float, display-aware, Live Dock mirror, collapse to a single button, widgets, a "TamaDocky" pet ([site](https://extradock.app/)) | Lifetime licences, frequent 40%-off sales ([site](https://extradock.app/)) | — | "Over 90% of ExtraDock's features came from user requests" ([site](https://extradock.app/)) |
| **Dockspace** | Widgets in a Dock ([site](https://getdockspace.app/)) | Music, app collections, timer, events, weather, themes; "<2% CPU" ([site](https://getdockspace.app/)) | $9.99 once, trial, Homebrew ([site](https://getdockspace.app/)) | Discord requests | — |
| **boringBar** | Taskbar per Space ([site](https://boringbar.app/)) | Current-Space windows only, scroll to switch desktops, badges, attention pulse, snap layouts ([site](https://boringbar.app/)) | Moved from a subscription to perpetual after backlash: now $29.99 for 2 devices with 1 year of updates, or $7.99/yr ([site](https://boringbar.app/), [HN](https://news.ycombinator.com/item?id=47743992)) | — | Show HN 520 pts: "A subscription for a menu bar… kills it for me" ([HN](https://news.ycombinator.com/item?id=47742559)) |
| **DockMate** | Previews for the stock Dock ([site](https://www.macenhance.com/dockmate.html)) | Previews, calendar quick-look with one-click meeting join, music controls ([site](https://www.macenhance.com/dockmate.html)) | From $14.99. Last version 0.8.7 (2021), so effectively abandoned ([site](https://www.macenhance.com/dockmate.html)) | — | Abandonment is a category risk |
| **Dockey / HiDock** | Tweaks for the stock Dock's hidden settings ([Dockey](https://dockey.publicspace.co/), [HiDock](https://www.idownloadblog.com/2023/01/27/hidock-app-customize-mac-dock-multiple-displays)) | Auto-hide speed and delay (Dockey); Dock settings per display (HiDock) | Free | — | CoolDock users ask for adjustable hide speed "like Dockey" [5 votes] ([roadmap](https://cooldock.app/roadmap)) |
| **Übersicht** | Shell command output rendered as desktop widgets ([site](http://tracesof.net/uebersicht)) | JSX widgets with `command` and `refreshFrequency` ([site](http://tracesof.net/uebersicht)) | Free, GPL-3.0, 5.0k★, sponsorships; last push 2025-06 ([repo](https://github.com/felixhageloh/uebersicht)) | Community widget gallery ([gallery](https://tracesof.net/uebersicht-widgets)) | Top issue "Always on Top?" [19] ([#97](https://github.com/felixhageloh/uebersicht/issues/97)): desktop widgets get hidden under windows |
| **SketchyBar** | Scriptable menu bar replacement ([README](https://github.com/FelixKratz/SketchyBar/blob/master/README.md)) | Event-driven scripting, graphs, popups, menu bar item aliases, animation ([README](https://github.com/FelixKratz/SketchyBar/blob/master/README.md)) | Free, GPL-3.0, 12.5k★ ([repo](https://github.com/felixkratz/SketchyBar)) | Shell or Lua (SbarLua) plugins; shared setups ([SbarLua](https://github.com/FelixKratz/SbarLua)) | Top issues: vertical bar [9], tooltips [8], crash on wake [5] ([#240](https://github.com/FelixKratz/SketchyBar/issues/240), [#691](https://github.com/FelixKratz/SketchyBar/issues/691)) |
| **Stats** | Free menu bar system monitor ([site](https://mac-stats.com/)) | 9 modules, 13 widget styles, top processes, sensors, Bluetooth batteries ([site](https://mac-stats.com/)) | Free, MIT, 42.7k★, "100M+ downloads" ([site](https://mac-stats.com/), [repo](https://github.com/exelban/stats)) | — | Top issues: missing sensors on new chips [20], combined single item [17], **Desktop Widget** [16] ([#2249](https://github.com/exelban/stats/issues/2249), [#1084](https://github.com/exelban/stats/issues/1084), [#1626](https://github.com/exelban/stats/issues/1626)). HN: "I basically never look at it and the icons were just taking up space" ([HN](https://news.ycombinator.com/item?id=42883175)) |
| **iStat Menus 7** | The most detailed system monitor ([site](https://bjango.com/mac/istatmenus/)) | Rules and alerts (e.g. CPU >60% for 10 s, IP changed, internet down), combined mode, fan control, weather, world clocks ([site](https://bjango.com/mac/istatmenus/)) | US$11.99 single, $14.99 family; paid major upgrades; Mac App Store and Setapp ([site](https://bjango.com/mac/istatmenus/), [why paid](https://bjango.com/help/istatmenus7/update)) | — | HN: a user lost access after a new laptop ("couldn't figure out how to download the old version") ([HN](https://news.ycombinator.com/item?id=42882763)) |
| **Bartender** | Menu bar manager ([site](https://www.macbartender.com/)) | Hide, group and trigger items, profiles, search; "Top Shelf" Dynamic Island in Pro ([purchase](https://www.macbartender.com/Bartender6/purchase.html)) | One-time Bartender 7, a yearly Pro, and a lifetime Mega Supporter; Setapp ([purchase](https://www.macbartender.com/Bartender6/purchase.html)) | — | 2024 silent sale and new telemetry broke trust ([MacRumors](https://www.macrumors.com/2024/06/04/bartender-mac-app-new-owner), [HN](https://news.ycombinator.com/item?id=40584606)): "requires screen recording… zero trust in the new owner" ([HN](https://news.ycombinator.com/item?id=40605735)) |
| **Ice** | Free Bartender alternative ([repo](https://github.com/jordanbaird/Ice)) | Hidden sections, Ice Bar for the notch, search, spacing, tint and shapes ([repo](https://github.com/jordanbaird/Ice)) | Free, GPL-3.0, 29.8k★ ([repo](https://github.com/jordanbaird/Ice)) | — | Top issues: no stable Tahoe build [87] and [69]; trigger conditions [78]; broken on macOS 27 [51]; Screen Recording should be optional [55] ([#760](https://github.com/jordanbaird/Ice/issues/760), [#62](https://github.com/jordanbaird/Ice/issues/62), [#954](https://github.com/jordanbaird/Ice/issues/954), [#75](https://github.com/jordanbaird/Ice/issues/75)) |
| **NotchNook** | Notch hub ([site](https://getnotchnook.com/)) | Music, calendar with Meet/Zoom/Teams/Webex join buttons, notes, to-dos, timers, mirror, Shortcuts, file Tray with AirDrop; works without a notch ([site](https://getnotchnook.com/)) | $15 lifetime (was $25) or $2/mo, 48-hour trial, 2 Macs, Setapp; "60,000+" buyers ([site](https://getnotchnook.com/)) | — | Press: "not sure I can do without it" (The Verge, quoted on the [site](https://getnotchnook.com/)). The "NotchNook is back" banner admits it went quiet ([site](https://getnotchnook.com/)) |
| **Boring Notch** | Free notch music hub ([repo](https://github.com/TheBoredTeam/boring.notch)) | Visualizer, calendar, reminders, shelf with AirDrop, HUD replacement ([repo](https://github.com/TheBoredTeam/boring.notch)) | Free, GPL-3.0, 11.1k★; unsigned, so users must run `xattr` ([repo](https://github.com/TheBoredTeam/boring.notch)) | "Extension system" on the roadmap ([repo](https://github.com/TheBoredTeam/boring.notch)) | Top issues: Now Playing broke on macOS 15.4 [54]; several requests to disable the wobbly animation [26+21+21+16]; hide in fullscreen and on external displays [14] ([#417](https://github.com/TheBoredTeam/boring.notch/issues/417), [#364](https://github.com/TheBoredTeam/boring.notch/issues/364), [#119](https://github.com/TheBoredTeam/boring.notch/issues/119)) |
| **MediaMate** | Better volume and brightness HUDs plus Now Playing in the notch ([site](https://wouter01.github.io/MediaMate)) | Compact HUDs, keyboard backlight HUD ([site](https://wouter01.github.io/MediaMate)) | €6.99 once on Gumroad; macOS 13+ ([site](https://wouter01.github.io/MediaMate), [Crest comparison](https://crestnotch.app/crest-vs-mediamate)) | — | Focused and cheap ([Lifehacker](https://lifehacker.com/tech/mediamate-macos)) |
| **Raycast** | An extendable launcher ([manual](https://manual.raycast.com/billing)) | Clipboard history, snippets, window management, AI, notes, Store ([manual](https://manual.raycast.com/billing)) | Free core; Pro $10/mo or $96/yr; Pro+ $20; Max $50; Teams per seat ([manual](https://manual.raycast.com/billing)) | React/TypeScript/Node extensions in the open `raycast/extensions` repo (7.8k★, 7.2k forks), published to the Store ([dev](https://www.raycast.com/developers), [repo](https://github.com/raycast/extensions)) | Top request: extension sandboxing and permissions [84] ([#200](https://github.com/raycast/extensions/issues/200)). Extensions break when upstream apps change ([#27537](https://github.com/raycast/extensions/issues/27537)) |
| **Alfred** | Launcher plus workflows ([site](https://www.alfredapp.com/powerpack/)) | Workflows, clipboard, snippets ([site](https://www.alfredapp.com/powerpack/)) | Free core; Powerpack £34 (v5, free upgrade to v6) or £59 Mega Supporter with lifetime upgrades ([shop](https://www.alfredapp.com/shop/)) | Alfred Gallery: an official, curated workflow store ([gallery](https://alfred.app/)) | Paying once per major version is accepted |
| **macOS desktop widgets** | WidgetKit widgets on the desktop and in Notification Centre, iPhone widgets via Continuity ([Apple](https://support.apple.com/guide/mac-help/add-and-customize-widgets-mchl52be5da5/mac)) | Interactive through App Intents ([Apple dev](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities)) | Built in | Any app's WidgetKit extension | Hidden behind windows: Apple's own tip is to "click the wallpaper to move the open windows away" ([Apple](https://support.apple.com/guide/mac-help/add-and-customize-widgets-mchl52be5da5/mac)). "Widgets on MacBook Air, what's the point!?" ([r/mac](https://www.reddit.com/r/mac/comments/194jfue/widgets_on_macbook_air_whats_the_point)); "widgets keep vanishing" ([Apple Community](https://discussions.apple.com/thread/255722398)) |
| **Rectangle / Rectangle Pro** | Keyboard and snap window management ([repo](https://github.com/rxhanson/Rectangle), [Pro](https://rectangleapp.com/pro)) | Snap areas; Pro adds window "throw", app layouts that trigger on display connect, stash windows at the edge, iCloud sync ([Pro](https://rectangleapp.com/pro)) | Free (30.1k★) plus paid Pro with a 10-day trial ([Pro](https://rectangleapp.com/pro)) | — | Top issues: slow with Chrome [40], Spaces support [23], move to the next desktop [22] ([#912](https://github.com/rxhanson/Rectangle/issues/912), [#215](https://github.com/rxhanson/Rectangle/issues/215)) |
| **Loop** | Radial-menu window management ([repo](https://github.com/MrKai77/Loop)) | Radial menu and gestures | Free, GPL-3.0, 11.8k★ ([repo](https://github.com/MrKai77/Loop)) | — | Top issues: move a window to another Space [16], resize adjacent windows [11], import/export settings [5] ([#223](https://github.com/MrKai77/Loop/issues/223), [#945](https://github.com/MrKai77/Loop/issues/945)) |
| **AltTab** | Windows-style window switching ([site](https://alt-tab.app/)) | Every window incl. minimized and other Spaces; preview before switching ([site](https://alt-tab.app/)) | Free GPL core plus a Pro tier (search, styles); 9.3M downloads ([site](https://alt-tab.app/)) | — | Top issues: maintainer search [212], Secure Input bug [98], fuzzy search [78], run without Screen Recording [70] ([#1179](https://github.com/lwouis/alt-tab-macos/issues/1179), [#590](https://github.com/lwouis/alt-tab-macos/issues/590), [#1082](https://github.com/lwouis/alt-tab-macos/issues/1082)) |
| **Hammerspoon** | Lua desktop automation ([repo](https://github.com/Hammerspoon/hammerspoon)) | Hotkeys, window, USB, Wi-Fi and app watchers | Free, MIT, 16.3k★ ([repo](https://github.com/Hammerspoon/hammerspoon)) | Lua "Spoons" | HN 355 pts: "the glue that holds my Mac together"; wishes include "a global toggle Teams mute button" ([HN](https://news.ycombinator.com/item?id=47368692), [HN](https://news.ycombinator.com/item?id=47368149)). A JS-based v2 is in progress ([HN](https://news.ycombinator.com/item?id=47371349)) |
| **"DockDock" name check** | No shipping product with that name was found. The search returned CoolDock, ExtraDock, Dockspace and a Raycast Glaze mini-app "The Dock" (880 installs) ([search target](https://www.glaze.app/app/the-dock-u2upth)) | — | — | — | Name looks free **[INFERENCE: web search only, no trademark search]** |

---

## 3. Patterns behind the evidence
- **Glanceable surfaces only stay useful when they are always visible.** Desktop widgets disappear under windows ([Apple tip](https://support.apple.com/guide/mac-help/add-and-customize-widgets-mchl52be5da5/mac), [Übersicht #97](https://github.com/felixhageloh/uebersicht/issues/97)), and that gap is the whole pitch for CoolDock and ExtraDock ([ExtraDock widgets page title](https://extradock.app/uses/widgets-for-mac): "Widgets… should stay visible, not buried under your windows").
- **Static readouts churn users.** "I basically never look at it" ([HN Stats](https://news.ycombinator.com/item?id=42883175)). iStat Menus retains users through *rules and alerts* ([iStat](https://bjango.com/mac/istatmenus/)), and Ice and Bartender users want *trigger conditions* ([Ice #62](https://github.com/jordanbaird/Ice/issues/62)).
- **Trust is the moat.** The Bartender sale ([HN](https://news.ycombinator.com/item?id=40605735)) sent users to Ice. DockDoor Pro publishes every network destination ([site](https://pro.dockdoor.net/)). docktor and CoolDock both request permissions only when needed ([docktor](https://docktorapp.com/), [CoolDock](https://cooldock.app/docs/permissions)).
- **OS updates break these apps every year.** Examples: Ice on Tahoe and on 27 ([#760](https://github.com/jordanbaird/Ice/issues/760), [#954](https://github.com/jordanbaird/Ice/issues/954)); Boring Notch Now Playing on 15.4 ([#417](https://github.com/TheBoredTeam/boring.notch/issues/417)); the AltTab Screen Recording prompt loop on 15.x ([#3973](https://github.com/lwouis/alt-tab-macos/issues/3973)); SketchyBar on 27 ([#849](https://github.com/FelixKratz/SketchyBar/issues/849)). Fixing fast is a feature in itself.

---

## 4. Syntheses

### (a) The 10 most-requested capabilities in this category
| # | Capability | Evidence |
|---|---|---|
| 1 | **User or community widgets (SDK or marketplace)** | CoolDock's #1 roadmap item [13] ([roadmap](https://cooldock.app/roadmap)); DockDoor Pro marketplace ([SDK](https://github.com/ejbills/dockdoorpro-widgets/blob/main/CONTRIBUTING.md)); Docky bundles ([doc](https://github.com/josejuanqm/docky/blob/main/docs/external-widgets.md)); Boring Notch "Extension system" ([repo](https://github.com/TheBoredTeam/boring.notch)); Raycast's model ([dev](https://www.raycast.com/developers)) |
| 2 | **Proper multi-monitor support (a bar per display, different content per display)** | CoolDock roadmap and Reddit ([roadmap](https://cooldock.app/roadmap), [reddit](https://www.reddit.com/r/macapps/comments/1x53gs1/cooldock_mac_widgets_that_live_where_you_can_see/)); uBar "Every monitor. Its own bar" ([uBar](https://ubarapp.com/)); Ice Bar on the built-in display only [68] ([#223](https://github.com/jordanbaird/Ice/issues/223)); Rectangle "move to a specific display" ([#199](https://github.com/rxhanson/Rectangle/issues/199)) |
| 3 | **Get out of the way: fullscreen hiding, no overlap, reserved space** | CoolDock [6], [5] and many bugs ([roadmap](https://cooldock.app/roadmap)); Boring Notch [14] ([#119](https://github.com/TheBoredTeam/boring.notch/issues/119)); Übersicht always-on-top [19] ([#97](https://github.com/felixhageloh/uebersicht/issues/97)) |
| 4 | **Conditional or triggered visibility** | Ice [78] ([#62](https://github.com/jordanbaird/Ice/issues/62)); CoolDock conditional widgets ([roadmap](https://cooldock.app/roadmap)); Bartender "Triggers" ([purchase](https://www.macbartender.com/Bartender6/purchase.html)) |
| 5 | **Window previews and a switcher covering every window, incl. minimized and other Spaces** | DockDoor's core ([repo](https://github.com/ejbills/DockDoor)); AltTab 9.3M downloads ([site](https://alt-tab.app/)); DockFix "Our most requested feature" ([site](https://www.dockfix.app/)); CoolDock minimized-window view [4] ([roadmap](https://cooldock.app/roadmap)) |
| 6 | **Settings sync, backup and export (and layout copy between Macs)** | DockDoor backup [14] ([#688](https://github.com/ejbills/DockDoor/issues/688)); Loop import/export [5] ([#945](https://github.com/MrKai77/Loop/issues/945)); CoolDock copy layouts ([roadmap](https://cooldock.app/roadmap)); Raycast Cloud Sync is a paid driver ([manual](https://manual.raycast.com/billing)) |
| 7 | **Profiles or contexts that switch automatically** | DockDoor Pro AppSense ([site](https://pro.dockdoor.net/)); CoolDock profiles that store appearance [5] ([roadmap](https://cooldock.app/roadmap)); Rectangle Pro layouts on display connect ([Pro](https://rectangleapp.com/pro)); Ice profiles (roadmap, [repo](https://github.com/jordanbaird/Ice)) |
| 8 | **Reliable Now Playing for any player** | Boring Notch [54] ([#417](https://github.com/TheBoredTeam/boring.notch/issues/417)); CoolDock album-art bugs [4] and Cider, Dia and Qobuz asks ([roadmap](https://cooldock.app/roadmap)) |
| 9 | **Fewer or optional invasive permissions** | Ice "Screen Recording optional" [55] ([#75](https://github.com/jordanbaird/Ice/issues/75)); AltTab degraded mode [70] ([#1082](https://github.com/lwouis/alt-tab-macos/issues/1082)); Raycast sandboxing [84] ([#200](https://github.com/raycast/extensions/issues/200)) |
| 10 | **Fine-grained control of behaviour (hide speed, delays, shortcut modifiers, animation off)** | CoolDock hide speed [5] ([roadmap](https://cooldock.app/roadmap)); DockDoor modifier key [17] ([#1254](https://github.com/ejbills/DockDoor/issues/1254)); Boring Notch "disable wobble", ~84 reactions across 4 issues ([#364](https://github.com/TheBoredTeam/boring.notch/issues/364)) |

Honourable mentions:
- Vertical layout: SketchyBar [9] ([#240](https://github.com/FelixKratz/SketchyBar/issues/240)) and CoolDock ([roadmap](https://cooldock.app/roadmap)).
- Spaces awareness: Rectangle [23] ([#215](https://github.com/rxhanson/Rectangle/issues/215)), Loop [16] ([#223](https://github.com/MrKai77/Loop/issues/223)), boringBar ([site](https://boringbar.app/)).
- A combined single item: Stats [17] ([#1084](https://github.com/exelban/stats/issues/1084)).

### (b) Table stakes for a Dock replacement people actually use every day
A replacement loses users the first time it fails at any of these:

1. **Pinned and running apps** with launch, quit and force-quit, a running indicator, an attention bounce or pulse, and **correct unread badges even for apps that aren't open**. Badges are "the number one issue" that sent an HN user back to the stock Dock ([HN](https://news.ycombinator.com/item?id=47742920)); boringBar and CoolDock both market badge accuracy ([boringBar](https://boringbar.app/), [CoolDock 2.2.0](https://cooldock.app/updates)).
2. **Window previews or a window list on hover**, covering minimized and hidden windows ([DockDoor](https://github.com/ejbills/DockDoor), [uBar](https://ubarapp.com/)).
3. **Drag and drop**: files onto app icons to open them, reordering, dropping on folders ([uBar](https://ubarapp.com/), [CoolDock request](https://cooldock.app/roadmap)).
4. **Folders and stacks** with list or grid views, and Downloads and Trash that stay in sync with Finder. CoolDock's Trash not syncing was reported as a bug ([roadmap](https://cooldock.app/roadmap)).
5. **Native right-click menu parity**: New Window, Open Recent, Show in Finder, Options → Keep in Dock / Open at Login, Quit / Force Quit ([CoolDock 1.8/2.0.6](https://cooldock.app/updates), [DockDoor Pro](https://pro.dockdoor.net/)).
6. **Auto-hide that feels as fast as the stock Dock**, with tunable delay and speed, plus a clean hand-off with the macOS Dock (hide it, restore it on quit) ([CoolDock layout](https://cooldock.app/docs/layout), [Dockish FAQ](https://appish.app/blog/mac-dock-replacement-apps-compared)).
7. **Fullscreen, Spaces, Mission Control, sleep and wake, display hot-plug and clamshell all handled.** These are CoolDock's largest bug cluster ([roadmap](https://cooldock.app/roadmap), [screens](https://cooldock.app/docs/screens)).
8. **Multiple displays**: at least "dock on the display under the pointer" or "dock on every display" ([Appish comparison](https://appish.app/blog/mac-dock-replacement-apps-compared)).
9. **Import the existing macOS Dock on first run** ([DockDoor Pro](https://pro.dockdoor.net/), [Dockish](https://appish.app/blog/mac-dock-replacement-apps-compared)).
10. **Performance budget**: under 1–2% CPU at idle is now marketed as a headline number ([DockFix](https://www.dockfix.app/), [Dockspace](https://getdockspace.app/), [CoolDock 2.1.1](https://cooldock.app/updates)).
11. **A safe exit**: quitting restores the Dock, and there is a Reset Layout or safe mode ([DockFix FAQ](https://www.dockfix.app/), [CoolDock Reset Layout](https://cooldock.app/docs/layout), [docktor safe mode](https://docktorapp.com/)).
12. **Signed and notarized builds with auto-update** (Sparkle). Unsigned apps make users run `xattr` ([Boring Notch](https://github.com/TheBoredTeam/boring.notch)).

DockDock status against these (code-grounded):
- Has: running-app tracking (`Sources/DockDock/Tiles/AppsTiles.swift:275-293`) and macOS Dock auto-hide control (`Sources/DockDock/Services/SystemDock.swift:9-18`).
- Missing: previews (no ScreenCaptureKit/AX in `Sources/`) and multi-display (`Sources/DockDock/Panel/DockBarController.swift:336-337`). The others were not audited; that is the AppInventory peer's scope.

### (c) Differentiation opportunities competitors don't serve well
| Opportunity | Gap evidence | Notes for DockDock |
|---|---|---|
| **Agent cockpit**: live Claude Code and Codex session state (running, waiting for approval, done), approve or jump to the terminal, limits and reset countdowns, token burn | CoolDock has usage only; the live-session request is unbuilt ([roadmap](https://cooldock.app/roadmap)). No other dock covers it (product sites above) | DockDock already reads local Claude and Codex state without tokens (plan §4). The next step is hooks or FSEvents for session status **[INFERENCE]** |
| **Alerts and rules on any tile** (threshold → tint, pulse, notification) | iStat's rules are its stickiest feature ([iStat](https://bjango.com/mac/istatmenus/)); the Stats complaint "never look at it" ([HN](https://news.ycombinator.com/item?id=42883175)) | Turns passive tiles into something you can't miss: CPU, disk, revenue drop, AI limit ≥ 90% |
| **Contextual tiles and auto-profiles** (by frontmost app, Focus mode, display, time of day) | Only DockDoor Pro AppSense exists ([site](https://pro.dockdoor.net/)); CoolDock and Ice requests ([roadmap](https://cooldock.app/roadmap), [Ice #62](https://github.com/jordanbaird/Ice/issues/62)) | Fits a fixed-height bar: fewer tiles, the right ones |
| **Script or command tiles with no SDK** (shell command + interval → value, sparkline or button), plus an MCP or URL-scheme push endpoint | Übersicht and SketchyBar prove demand among power users but are desktop- or menu-bar-only and code-heavy ([Übersicht](http://tracesof.net/uebersicht), [SketchyBar](https://github.com/FelixKratz/SketchyBar/blob/master/README.md)); CoolDock users want user widgets [13] ([roadmap](https://cooldock.app/roadmap)) | Cheaper than a Swift bundle SDK. Hammerspoon users want one-button toggles such as Teams mute ([HN](https://news.ycombinator.com/item?id=47368149)) |
| **Meeting-first calendar tile** (countdown, auto-join, mute toggle) | docktor auto-opens meeting links ([site](https://docktorapp.com/)); NotchNook join buttons ([site](https://getnotchnook.com/)); CoolDock Teams request ([roadmap](https://cooldock.app/roadmap)) | Small, high daily-use value |
| **Vertical, per-display bars with orientation-aware tiles** | CoolDock has no vertical mode ([reddit](https://www.reddit.com/r/macapps/comments/1wfbhxk/cooldock_your_smart_second_dock_of_widgets/)); SketchyBar request [9] ([#240](https://github.com/FelixKratz/SketchyBar/issues/240)) | DockDock already has left and right (`Theme.swift:7-15`) |
| **Transparent privacy and network ledger** | Pioneered by DockDoor Pro ([site](https://pro.dockdoor.net/)); Bartender trust collapse ([HN](https://news.ycombinator.com/item?id=40605735)) | DockDock pulls from many services: list every host and when it is contacted |
| **Setup that doesn't scare people** (ask only when needed, start useful, import your Dock, templates) | docktor's "setup that asks for nothing" ([site](https://docktorapp.com/)); CoolDock templates request ([roadmap](https://cooldock.app/roadmap)); DockDoor Pro needs an 11-minute tour ([site](https://pro.dockdoor.net/)) | Persona presets ("Founder", "Developer", "Student"): one click fills the bar |
| **Settings export and sync across Macs** | Requests from DockDoor, Loop and CoolDock (§4a #6) | iCloud key-value store or a JSON export of `layout.json` |

### (d) Monetization and distribution patterns that work
| Pattern | Who | Evidence of reception |
|---|---|---|
| **Free open-source core + separate paid "Pro" app** | DockDoor → DockDoor Pro ($20, 3 Macs, all updates); AltTab → AltTab Pro | DockDoor 6.4k★ feeding Pro ([repo](https://github.com/ejbills/DockDoor), [Pro](https://pro.dockdoor.net/)); AltTab 9.3M downloads ([site](https://alt-tab.app/)) |
| **One-time, per major version, paid upgrades** | iStat Menus ($11.99), Alfred (£34), uBar ($39), Bartender 7 | Bjango explains why upgrades are paid ([help](https://bjango.com/help/istatmenus7/update)); Alfred gives a free v6 upgrade to v5 buyers ([shop](https://www.alfredapp.com/shop/)) |
| **Low one-time price ($7–$20) plus a trial** | Dockish $6.99 with 7 days; DockFix €14.99 with 7 days; Dockspace $9.99; NotchNook $15 with 48 h; MediaMate €6.99 | Common across the 2026 dock wave ([Appish](https://appish.app/blog/mac-dock-replacement-apps-compared), [DockFix](https://www.dockfix.app/), [NotchNook](https://getnotchnook.com/)) |
| **Avoid**: subscriptions for a bar or dock, or "lifetime" with one year of updates | boringBar dropped its subscription after the HN backlash ([HN](https://news.ycombinator.com/item?id=47743992)); CoolDock pricing mocked ([reddit](https://www.reddit.com/r/macapps/comments/1x53gs1/cooldock_mac_widgets_that_live_where_you_can_see/)) | Clear negative signal |
| **Subscription only where cloud or AI costs are real** | Raycast Pro (AI credits, sync) at $10/mo; uBar Cloud $2.99/mo for Command | Free core keeps reach ([Raycast manual](https://manual.raycast.com/billing), [uBar](https://ubarapp.com/)) |
| **Setapp listing as a second channel** | iStat Menus, Bartender, NotchNook | Listed on vendor pages ([iStat](https://bjango.com/mac/istatmenus/), [Bartender](https://www.macbartender.com/Bartender6/purchase.html), [NotchNook](https://lo.cafe/notchnook)) |
| **Direct DMG + Homebrew cask + Sparkle; not the App Store** | Docky, DockDoor, docktor, CoolDock | Private SPI / Accessibility needs rule out the MAS ([Docky note](https://github.com/josejuanqm/docky)) |
| **Launch on r/macapps / Product Hunt / Show HN with launch discounts** | CoolDock, ExtraDock (40% off), boringBar (HN 520 pts), docktor (PH #17) | ([reddit](https://www.reddit.com/r/macapps/comments/1wfbhxk/cooldock_your_smart_second_dock_of_widgets/), [ExtraDock](https://extradock.app/), [HN](https://news.ycombinator.com/item?id=47742200), [docktor](https://docktorapp.com/)) |
| **Bundles across sibling apps** | Appit Studio bundle; Appish Suite $26.99 | ([CoolDock footer](https://cooldock.app/), [Appish](https://appish.app/blog/mac-dock-replacement-apps-compared)) |
| **Public roadmap and voting + changelog cadence as marketing** | CoolDock roadmap, docktor in-app forum, ExtraDock "90% of features from user requests" | ([roadmap](https://cooldock.app/roadmap), [docktor](https://docktorapp.com/), [ExtraDock](https://extradock.app/)) |

A recommended shape for DockDock **[INFERENCE]**, grounded in the rows above:
- a free trial of 7–14 days;
- a $15–25 one-time licence covering the current major version, or at least 2 years of updates, on 2–3 Macs;
- optional Setapp distribution;
- direct DMG plus a Homebrew cask plus Sparkle;
- a public roadmap;
- no subscription unless a hosted service, such as sync or a cloud relay, is added.

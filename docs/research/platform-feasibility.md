# DockDock — platform feasibility research (macOS 26 Tahoe, Developer ID, not sandboxed)

Scope: which APIs exist for each capability, which TCC prompt each one triggers, and what could break. As of 2026-10-21, macOS 27 "Golden Gate" has shipped, with 27.2 at RC ([macOS release notes index](https://developer.apple.com/documentation/macos-release-notes)). DockDock's minimum is macOS 26 (`Resources/Info.plist:23-24`), so 27 changes are listed as forward risks.

Legend: **Yes** = public API, no prompt · **Yes+TCC** = public API plus a user consent prompt · **Private API** = undocumented symbol, system-binary trampoline or private file format · **No** = no route a shipping app should use.

## 0. Verdict table

| # | Capability | Verdict | API / mechanism | TCC / entitlement | Key risk |
|---|---|---|---|---|---|
|1.1|Running apps + launch/running indicators|**Yes**|`NSWorkspace.runningApplications` (KVO), `didLaunch/didTerminate/didActivateApplicationNotification`|none|none (already used: `Sources/DockDock/Tiles/AppsTiles.swift:275-292`)|
|1.2|Per-app window list (titles, minimized, hidden)|**Yes+TCC**|`AXUIElementCreateApplication` → `kAXWindowsAttribute`, `AXObserver`|Accessibility|Windows on other Spaces and the CGWindowID mapping need private calls (`_AXUIElementGetWindow`, `_AXUIElementCreateWithRemoteToken`)|
|1.3|Window thumbnails / live previews|**Yes+TCC**|`SCScreenshotManager`, `SCStream(SCContentFilter(desktopIndependentWindow:))`|Screen Recording; Sequoia+ asks again periodically|Minimized windows need the **private** `CGSHWCaptureWindowList`|
|1.4|Minimized windows (list, restore)|**Yes+TCC**|`kAXMinimizedAttribute` read and set|Accessibility|Thumbnails of minimized windows are private-only|
|1.5|Other apps' badge counts|**Yes+TCC**|Read the Dock process's AX tree, `AXStatusLabel` per Dock item|Accessibility|Depends on the Dock's AX tree (unsupported contract); must poll|
|1.6|Drop files onto an app tile|**Yes**|`NSWorkspace.open(_:withApplicationAt:configuration:)` + SwiftUI `onDrop`|none|—|
|1.7|Trash tile (drop to trash / count / empty)|Drop: **Yes**; count: **Yes+TCC** (FDA); empty: **Yes+TCC** (Automation→Finder)|`FileManager.trashItem`; reading `~/.Trash`; Finder Apple event|Full Disk Access for listing; Automation|Full Disk Access is a heavy ask just for a count|
|1.8|Downloads stack|**Yes+TCC**|`FileManager` on `~/Downloads`|Files & Folders → Downloads|Already prompt-gated (`Sources/DockDock/Services/UtilityServices.swift:37-60`)|
|1.9|Recent apps|**Yes** (self-tracked)|Record `didActivateApplicationNotification` history|none|The Dock's own recents list lives in its private prefs|
|1.10|An app's own Dock menu|**No** (public); workaround **Yes+TCC**|Dock menus are app↔Dock IPC; AX `AXShowMenu` on the Dock item|Accessibility|Menu appears at the hidden Dock's position; build DockDock's own menu instead|
|1.11|Hide the system Dock|**Yes** (prefs) / **Private API** (CoreDock)|`autohide` default (DockDock today) or `CoreDockSetAutoHideEnabled`|none|Mission Control still draws the parked Dock|
|2|Host other apps' WidgetKit widgets|**No**|No host API; only the system places widgets (desktop, Notification Center)|—|Alternatives in §2|
|3.1|App Intents / Shortcuts / Spotlight actions|**Yes**|`AppIntent`, `AppEntity`, `AppShortcutsProvider`|none|**`swift build` doesn't produce `Metadata.appintents`** → needs an Xcode target or a metadata step|
|3.2|Custom URL scheme `dockdock://`|**Yes**|`CFBundleURLTypes` + `kAEGetURL` / `onOpenURL`|none|Any web page or process can fire it → validate input, never run destructive actions|
|3.3|AppleScript dictionary (sdef)|**Yes**|`OSAScriptingDefinition`, `NSAppleScriptEnabled`, `NSScriptCommand`|Callers get an Automation prompt|Cocoa Scripting boilerplate|
|3.4|Local CLI|**Yes**|Helper binary in the bundle → URL scheme, Distributed Notifications or XPC|none|Authenticate local IPC if it can mutate state|
|3.5|User script/JSON tiles (xbar/SwiftBar/SketchyBar style)|**Yes**|`Process` + stdout parsing|**Child processes inherit DockDock's TCC grants**|Security design is mandatory (§3.5)|
|3.6|JavaScriptCore / WebView tiles|**Yes**|`JSContext`, `WKWebView`|none|JS gets no I/O except what you bridge; WebViews cost RAM|
|4.1|Now playing (any app)|**Private API**|MediaRemote via the `/usr/bin/perl` trampoline (mediaremote-adapter)|none|Apple closed direct access in 15.4 and could close the trampoline|
|4.2|Calendar / Reminders|**Yes+TCC**|EventKit `requestFullAccessToEvents/Reminders`|Calendars / Reminders full access|Reading requires *full* access (no read-only)|
|4.3|WeatherKit|**Yes** (entitlement)|`WeatherService`|WeatherKit capability on the App ID (provisioning)|Bare `swift build` + `codesign` embeds no profile; DockDock uses Open-Meteo, which is **non-commercial only**|
|4.4|Mail (unread, recent)|**Yes+TCC**|Apple Events to Mail (AppleScript)|Automation → Mail|Slow, launches Mail; a Dock badge (1.5) is the cheaper unread count|
|4.5|Read other apps' notifications|**No**|`UNUserNotificationCenter` sees only your own; the DB moved behind TCC in 15|(FDA + private DB)|Don't|
|4.6|Focus status|**Yes+TCC** (bool only); name = **Private** file read with FDA|`INFocusStatusCenter.focusStatus.isFocused`|Focus authorization + Communication Notifications capability|No public API for the Focus *name*|
|4.7|Bluetooth battery levels|Apple HID: **Yes** (IORegistry); AirPods/others: **Private API**|`AppleDeviceManagementHIDEventService` → `BatteryPercent`|none for IORegistry [INFERENCE]|IORegistry keys are undocumented|
|4.8|Network speed|**Yes**|`getifaddrs` `if_data` byte counters (already used)|none|Per-app speeds need private NetworkStatistics [INFERENCE]|
|4.9|Other apps' keychain items|**Yes+TCC** (login keychain ACL prompt); data-protection items of other teams: **No**|`SecItemCopyMatching`|ACL dialog (Deny / Allow / Always Allow)|26.4 moved the login keychain to data protection; watch for ACL behavior changes|
|5.1|Global hotkeys|**Yes** (Carbon) / **Yes+TCC** (monitors, taps)|`RegisterEventHotKey`; `NSEvent.addGlobalMonitorForEvents`; `CGEventTap`|Carbon: none; key monitors: Accessibility; taps: Input Monitoring|Sequoia+ rejects ⌥-only and ⌥⇧-only hotkeys|
|5.2|Liquid Glass bar|**Yes**|SwiftUI `glassEffect`, `GlassEffectContainer`; AppKit `NSGlassEffectView` (26+)|none|Too many glass effects hurt performance; DockDock doesn't use any yet|
|5.3|Spaces / full screen / Stage Manager|**Yes**|`NSWindow.collectionBehavior`, `level`, `activeSpaceDidChangeNotification`|none|No public "is this a full-screen Space" API|
|5.4|Multi-display|**Yes**|`NSScreen.screens`, `didChangeScreenParametersNotification`, `screensHaveSeparateSpaces`|none|—|
|6.1|Sparkle 2 auto-update|**Yes**|`SPUStandardUpdaterController`, EdDSA appcast|none|SwiftPM build must embed the framework and set the rpath|
|6.2|Notarization|**Yes** (build script change needed)|`notarytool` + `stapler`|—|`scripts/build-app.sh:36` signs with `--timestamp=none`, which **notarization rejects**|
|6.3|Mac App Store|**No** (without dropping core features)|Sandbox mandatory|—|AX, private APIs, `~/.claude` reads, Sparkle and plugins all conflict (§6.3)|
|6.4|Crash reporting|**Yes**|MetricKit (macOS 12+; new `MetricManager` in 27), Sentry, PLCrashReporter|none|MetricKit delivers late; third-party SDKs mean data leaves the Mac|
|6.5|Launch at login|**Yes+approval**|`SMAppService.mainApp.register()`|Login Items approval|Not implemented in DockDock (no `SMAppService` in `Sources/`)|

---

## 1. Dock parity

### 1.1 Running apps and indicators — Yes
- Public: `NSWorkspace.didActivateApplicationNotification` carries the `NSRunningApplication` ([doc](https://developer.apple.com/documentation/appkit/nsworkspace/didactivateapplicationnotification)). `NSRunningApplication.isHidden` is KVO-observable ([doc](https://developer.apple.com/documentation/appkit/nsrunningapplication/ishidden)).
- DockDock already refreshes on launch and terminate (`Sources/DockDock/Tiles/AppsTiles.swift:275-292`). Missing pieces: an activation-order history (needed for recents, 1.9) and hidden-state dimming.
- AltTab follows the same pattern: running apps via KVO, then an `AXObserver` per app ([AltTab architecture write-up](https://github.com/kaikozlov/alt-tab/blob/main/ARCHITECTURE.md)).

### 1.2 Window lists — Yes+TCC (Accessibility), with private extras
- Public path: `AXUIElementCreateApplication(pid)` → `kAXWindowsAttribute`. Subscribe with `AXObserverAddNotification` to `kAXWindowCreated`, `kAXUIElementDestroyed`, `kAXTitleChanged`, `kAXWindowMiniaturized`/`Deminiaturized` and `kAXFocusedWindowChanged` ([AltTab architecture](https://github.com/kaikozlov/alt-tab/blob/main/ARCHITECTURE.md)). AX calls default to a 6 s timeout; AltTab lowers it to 1 s so a hung app can't block threads ([alt-tab-macos AXUIElement.swift](https://github.com/lwouis/alt-tab-macos/blob/master/src/api-wrappers/AXUIElement.swift)).
- Private extras every switcher uses:
  - `_AXUIElementGetWindow` maps an AX window to its `CGWindowID` ([DockDoor PrivateApis.swift#L17](https://github.com/ejbills/DockDoor/blob/main/DockDoor/Utilities/PrivateApis.swift#L17)).
  - `_AXUIElementCreateWithRemoteToken` brute-forces windows on other Spaces ([#L89-L91](https://github.com/ejbills/DockDoor/blob/main/DockDoor/Utilities/PrivateApis.swift#L89-L91)).
  - SkyLight `CGSCopySpacesForWindows`, `_SLPSSetFrontProcessWithOptions` and `SLPSPostEventRecordTo` focus one specific window ([alt-tab SkyLight.framework.swift](https://github.com/lwouis/alt-tab-macos/blob/master/src/macos/api-wrappers/SkyLight.framework.swift)).
- `CGWindowListCopyWindowInfo` returns `kCGWindowName` only with Screen Recording access ([Apple forums 126860](https://developer.apple.com/forums/thread/126860)).
- Sandbox note: listing via `CGWindowList` is sandbox-legal; cross-app AX is not ([Crosley, citing DTS in forums 805556](https://blakecrosley.com/blog/window-manager-mac-app-store-sandbox)).
- macOS 27 risk: a third-party report says 27 exposes more decoy micro-windows, so pick the largest on-screen window per app ([gist](https://gist.github.com/ebowwa/a4eddd43a7d39c3f2d4986df0635e6ee/646e4cebe05e17b047684b2f3ed56386ca81bad6)).

### 1.3 Thumbnails and live previews — Yes+TCC (Screen Recording)
- Stills: `SCScreenshotManager.captureImage(contentFilter:configuration:)` ([doc](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager)).
- Live previews: DockDoor runs `SCStream` with `SCContentFilter(desktopIndependentWindow:)` ([LiveWindowCapture.swift#L178](https://github.com/ejbills/DockDoor/blob/main/DockDoor/Utilities/Window%20Management/LiveWindowCapture.swift#L178), [#L233](https://github.com/ejbills/DockDoor/blob/main/DockDoor/Utilities/Window%20Management/LiveWindowCapture.swift#L233)).
- Stills via the private batch call: DockDoor uses `CGSHWCaptureWindowList` ([WindowUtil.swift#L520-L542](https://github.com/ejbills/DockDoor/blob/main/DockDoor/Utilities/Window%20Management/WindowUtil.swift#L520-L542)). AltTab does too ([SkyLight.framework.swift#L34](https://github.com/lwouis/alt-tab-macos/blob/master/src/macos/api-wrappers/SkyLight.framework.swift#L34)). It is "the only option that works" for minimized windows ([AltTab architecture](https://github.com/kaikozlov/alt-tab/blob/main/ARCHITECTURE.md)).
- `CGWindowListCreateImage` is deprecated in favor of ScreenCaptureKit ([forums 740493](https://developer.apple.com/forums/thread/740493)).
- TCC friction:
  - Sequoia added recurring re-consent prompts. Weekly in beta, relaxed to monthly ([9to5Mac](https://9to5mac.com/2024/08/06/macos-sequoia-screen-recording-privacy-prompt), [iDownloadBlog](https://www.idownloadblog.com/2024/08/14/macos-sequoia-beta-6-screen-recording-prompt-weekly)), then reduced further in 15.1 ([9to5Mac](https://9to5mac.com/2024/10/07/macos-sequoia-screen-recording-popups/)).
  - The only bypass, `com.apple.developer.persistent-content-capture`, is for VNC apps ([doc](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.persistent-content-capture)).
  - AltTab issue trackers show "granted but not detected" bugs ([#5739](https://github.com/lwouis/alt-tab-macos/issues/5739)).
  - DockDock already declares `NSScreenCaptureUsageDescription` (`Resources/Info.plist:41-42`).
- Recommendation [INFERENCE]: make previews opt-in. Show title-only window lists with Accessibility alone, and ask for Screen Recording only when the user turns thumbnails on.

### 1.4 Minimized windows — Yes+TCC
- Read and set `kAXMinimizedAttribute`. DockDoor minimizes with `setAttribute(kAXMinimizedAttribute, true)` ([WindowUtil.swift#L1879](https://github.com/ejbills/DockDoor/blob/main/DockDoor/Utilities/Window%20Management/WindowUtil.swift#L1879)). Thumbnails of minimized windows are private-only (1.3).

### 1.5 Badge counts — Yes+TCC (Accessibility)
- `NSDockTile` badges only *your own* app's tile ([doc](https://developer.apple.com/documentation/appkit/nsdocktile)).
- Other apps' badges are only in the Dock process. Each Dock item exposes `AXStatusLabel` ([Hammerspoon discussion #3251](https://github.com/Hammerspoon/hammerspoon/discussions/3251), [dock-badge-counter](https://github.com/strayer/dock-badge-counter): JSON like `{"Mail":"3","Slack":"12"}`; requires Accessibility).
- Works with the Dock hidden: a shipping Dock replacement reads badges from the parked Dock every 1.5 s, off the main thread, only when the option is on ([dock-profiler how-it-works](https://github.com/estruyf/dock-profiler-macos/blob/main/docs/how-it-works.md)).
- DockDoor watches the Dock's AX list with `kAXSelectedChildrenChangedNotification` for hover ([DockObserver.swift#L323-L331](https://github.com/ejbills/DockDoor/blob/main/DockDoor/Utilities/DockObserver.swift#L323-L331)).
- Constraint [INFERENCE]: only apps the Dock shows have a badge. Running apps always do; non-running pinned apps only if they're in the user's real Dock.

### 1.6 Drop files onto app tiles — Yes
- `NSWorkspace.open(_ urls:withApplicationAt:configuration:)` opens URLs in a chosen app ([doc](https://developer.apple.com/documentation/appkit/nsworkspace/open(_:withapplicationat:configuration:completionhandler:))). No TCC.
- Per-app acceptance check (does the app declare this UTI?) [INFERENCE]: `NSWorkspace.urlsForApplications(toOpen:)` or LaunchServices.

### 1.7 Trash — mixed
- Drop to trash: `FileManager.trashItem(at:resultingItemURL:)` ([doc](https://developer.apple.com/documentation/foundation/filemanager/trashitem(at:resultingitemurl:))). No TCC.
- Full/empty state and item count: listing `~/.Trash` returns "Operation not permitted" without Full Disk Access since Catalina ([Ask Different](https://apple.stackexchange.com/questions/376916/cannot-ls-trash-in-the-terminal-in-catalina-operation-not-permitted)).
- Empty Trash: ask Finder via Apple events, which raises the Automation prompt. DockDock already declares `NSAppleEventsUsageDescription` (`Resources/Info.plist:31-32`) and `com.apple.security.automation.apple-events` (`Resources/DockDock.entitlements:18-19`). [INFERENCE: Finder's scripting dictionary has an `empty trash` command]
- Prior art: DockDoor Pro ships "Trash at the Dock end … with size, custom icons, and an empty confirmation" ([features](https://pro.dockdoor.net/features/)).

### 1.8 Downloads stack — Yes+TCC
- Files & Folders → Downloads prompt. DockDock already defers the read to a click (`Sources/DockDock/Services/UtilityServices.swift:37-60`, `Sources/DockDock/Tiles/UtilityTiles.swift:540-541`). A fan or grid stack is pure UI work.

### 1.9 Recent apps — Yes
- Keep an MRU list from `didActivateApplicationNotification` ([doc](https://developer.apple.com/documentation/appkit/nsworkspace/didactivateapplicationnotification)).
- The Dock's own "show recents" toggle is the documented MDM key `show-recents` ([Dock payload](https://developer.apple.com/documentation/devicemanagement/dock)); the list itself isn't documented [INFERENCE].

### 1.10 Dock menus — No public API
- An app's Dock menu is handed to the Dock: "The target and action for each menu item are passed to the dock. On selection … the dock messages your application" ([applicationDockMenu(_:)](https://developer.apple.com/documentation/appkit/nsapplicationdelegate/applicationdockmenu(_:))). No API lets a third party read it.
- Workaround: AX `AXShowMenu` on the Dock item, as System Events does via `perform action "AXShowMenu"` ([JXA cookbook](https://github-wiki-see.page/m/JXA-Cookbook/JXA-Cookbook/wiki/System-Events), [AXUIElementPerformAction](https://developer.apple.com/documentation/applicationservices/1462091-axuielementperformaction)). It draws at the hidden Dock's position [INFERENCE].
- Recommendation: build DockDock's own context menu. Window list (AX), New Window via the app's AX menu bar [INFERENCE], Show in Finder, Hide / Quit / Force Quit (`NSRunningApplication`), Options (keep in bar, open at login).

### 1.11 Hiding the real Dock
- DockDock toggles the user's autohide and restores it, persisting the original against crashes (`Sources/DockDock/Shell/SystemDockSwap.swift:3-52`).
- DockDoor declares the private `CoreDockSetAutoHideEnabled`/`CoreDockGetAutoHideEnabled` ([PrivateApis.swift#L28-L33](https://github.com/ejbills/DockDoor/blob/main/DockDoor/Utilities/PrivateApis.swift#L28-L33)).
- dock-profiler "parks" the Dock: auto-hide with a very long delay plus the smallest tile size. It notes "Mission Control still draws the parked macOS Dock underneath; there is no API to stop it" ([how-it-works](https://github.com/estruyf/dock-profiler-macos/blob/main/docs/how-it-works.md)). Its bar sits just above the Dock's window level, the one Mission Control doesn't hide (same source).
- macOS 27 fixed "Dock might persist when entering and exiting Mission Control" in full screen ([27 release notes, Dock](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes)).

---

## 2. Hosting other apps' WidgetKit widgets — **No**
- Apple describes only system placement: "On Mac, people put native Mac app widgets on the desktop and in Notification Center." Controls appear "in Control Center or as menu bar items" ([WidgetKit overview](https://developer.apple.com/documentation/widgetkit)). The framework's topics list provider-side APIs only (timelines, `WidgetBundle`, controls, previews). There is no host or embedding API (same page) [INFERENCE from the API surface: absence of a symbol].
- Widgets are SwiftUI archived by the system's widget host and rendered out of process [INFERENCE]. Hosting someone else's would need private Chrono/WidgetKit-host internals, with no public project found.
- Alternatives, best first:

| Option | What it gives | Cost |
|---|---|---|
|Ship **DockDock's own widget extension**|DockDock tiles on the desktop and in Notification Center (WidgetKit), plus **Controls** in Control Center / menu bar|Needs an `.appex` target, which in practice means an Xcode project; `scripts/build-app.sh:10` is plain `swift build` [INFERENCE]|
|**App Intents** both ways (§3.1)|Other apps' intents run *from* a tile via Shortcuts (`shortcuts run`, [Apple](https://support.apple.com/guide/shortcuts-mac/run-shortcuts-from-the-command-line-apd455c82f02/mac)); DockDock's data exposed *to* Shortcuts / Spotlight|Moderate|
|**Script / JSON tiles** (§3.5)|Any CLI's output becomes a tile, xbar-style|Security design|
|**Web tiles** (`WKWebView`, Übersicht-style)|Arbitrary HTML dashboards|RAM per view|
|Marketplace bundles|DockDoor Pro advertises a community "widget marketplace" and sideloaded bundles ([features](https://pro.dockdoor.net/features/))|Code-loading policy (§3.5, §6.3)|

---

## 3. Automation and extensibility

### 3.1 App Intents / Shortcuts / Spotlight — Yes, but the build system blocks it today
- macOS 26 runs App Intents from **Spotlight on Mac**. The parameter summary must contain every required parameter without a default, or the intent won't show. It also adds **personal Automations on Mac** (time of day, folder, external drive, Bluetooth) that can call any macOS app intent ([WWDC25-260](https://developer.apple.com/videos/play/wwdc2025/260/)). Entities exposed to Shortcuts also feed the "Use Model" action as JSON (same session).
- **Build blocker:** intents are discovered via `Metadata.appintents`, produced by Xcode's ExtractAppIntentsMetadata phase (`appintentsmetadataprocessor`) ([rules_apple #1766](https://github.com/bazelbuild/rules_apple/issues/1766), [forums 766501](https://developer.apple.com/forums/thread/766501)). Reports show intents missing from Shortcuts when they live in an SPM package ([forums 759160](https://developer.apple.com/forums/thread/759160)). DockDock builds with `swift build` and hand-assembles the bundle (`scripts/build-app.sh:10-18`), so intents wouldn't register [INFERENCE]. Fix: an Xcode app target, or run `xcrun appintentsmetadataprocessor` in the script (unsupported path).
- Suggested surface [INFERENCE: design]:
  - `ShowTile(tile: TileEntity)` and `ToggleBar`.
  - `StartTimer(kind: pomodoro|interval|water, minutes: Int)`.
  - `GetTileValue(tile) -> String`, so Shortcuts can read e.g. Claude usage %.
  - `SwitchTheme(theme: ThemeEntity)`, `AddTileToBar(tile)`.
  - `TileEntity` with an `EnumerableEntityQuery` from `TileCatalog.available`, so Spotlight suggestions work (WWDC25-260 recommends suggested/all entities).
- macOS 27 App Intents fixes include an AppEntity 10 MB cumulative size limit ([27 notes](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes)).

### 3.2 URL scheme — Yes
- `CFBundleURLTypes` ([doc](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleurltypes)). Apple calls custom schemes acceptable but recommends universal links ([doc](https://developer.apple.com/documentation/xcode/defining-a-custom-url-scheme-for-your-app)).
- DockDock declares none (`Resources/Info.plist:1-52`). Shortcuts also uses URL schemes ([Apple](https://support.apple.com/guide/shortcuts-mac/run-a-shortcut-from-another-app-apd163eb9f95/mac)).
- Security [INFERENCE]: any web page can trigger the scheme (the browser prompts once). Allow only idempotent verbs (`show`, `refresh`, `timer/start`). Never accept tokens or file paths. Rate-limit.

### 3.3 AppleScript dictionary — Yes
- Precedent: DockDoor ships `DockDoor.sdef` plus `ScriptCommands.swift` ([tree](https://github.com/ejbills/DockDoor/tree/main/DockDoor), [docs](https://dockdoor.net/docs)). DockDoor Pro markets an "AppleScript dictionary" for Shortcuts / osascript ([features](https://pro.dockdoor.net/features/)).
- Key: `OSAScriptingDefinition` ([doc](https://developer.apple.com/documentation/bundleresources/information-property-list/osascriptingdefinition)).
- Scripts that call DockDock trigger the caller's Automation prompt. Apple's own example of why that matters: indirect access to Mail data ([NSAppleEventsUsageDescription](https://developer.apple.com/documentation/bundleresources/information-property-list/nsappleeventsusagedescription)).

### 3.4 Local CLI — Yes
- Precedent: DockDoor docs cover "AppleScript and CLI" control ([README](https://github.com/ejbills/DockDoor/blob/main/README.md), [docs](https://dockdoor.net/docs)). SketchyBar is fully CLI-driven: `sketchybar --set`, `--subscribe item event` ([events docs](https://felixkratz.github.io/SketchyBar/config/events)).
- Transport [INFERENCE: design]: ship `Contents/Helpers/dockdock`, which posts to the running app via the URL scheme for one-shot verbs, or via XPC / a Unix socket in Application Support for `dockdock set <tile> --value …` (push data into a "custom tile"). Gate the socket by file permissions (0600).

### 3.5 User-defined tiles (script / JSON / JS / Web) — Yes; security design required

| Model | Prior art (format) | Fit for DockDock |
|---|---|---|
|**Poll script → stdout**|xbar/SwiftBar: executable in a plugin folder, refresh interval in the filename (`date.1m.sh`), header before the first `---`, env vars like `SWIFTBAR_PLUGIN_CACHE_PATH`, cron tag ([SwiftBar README](https://github.com/swiftbar/SwiftBar/blob/main/README.md), [xbar](https://github.com/matryer/xbar))|Most compatible: can run the xbar plugin corpus [INFERENCE]|
|**JSON-output script**|Same, but stdout = `{"value","caption","sparkline":[…],"tint","url"}` [INFERENCE: design]|Best fit for fixed-height tiles|
|**Event-driven**|SketchyBar items `--subscribe` to `front_app_switched`, `volume_change`, custom events ([docs](https://felixkratz.github.io/SketchyBar/config/events))|Lower CPU than polling|
|**JSX/Web**|Übersicht: `.jsx` module exporting `command`, `refreshFrequency` (ms, default 1000), `render` with React ([README](https://github.com/felixhageloh/uebersicht/blob/master/README.md))|Heavy (WebView per tile)|
|**JavaScriptCore**|`JSContext` evaluates JS and bridges native objects ([doc](https://developer.apple.com/documentation/javascriptcore/jscontext))|JS has no I/O unless bridged, so it's a capability sandbox you control|

- **Security implications:**
  - **TCC inheritance:** a process DockDock spawns is attributed to DockDock as the "responsible process" and gets its grants: Calendar, Photos, Screen Recording, Accessibility, Automation ([Qt: The Curious Case of the Responsible Process](https://www.qt.io/blog/the-curious-case-of-the-responsible-process), [Michael Tsai](https://mjtsai.com/blog/2025/07/07/the-curious-case-of-the-responsible-process), [Ghostty #9263](https://github.com/ghostty-org/ghostty/issues/9263)). A malicious plugin is effectively a malicious DockDock.
  - Mitigation: spawn plugins with responsibility disclaimed, so each child is judged by its own signature ([disclaim](https://github.com/AprilNEA/disclaim/blob/master/README.md); private `responsibility_spawnattrs_setdisclaim` [INFERENCE]). Plus explicit per-plugin trust (show the path and a hash; re-confirm on change), no auto-download, timeouts and output size caps.
  - Keychain ACLs trust specific binaries, so a child `/bin/sh` is not DockDock for keychain prompts [INFERENCE]. Still, never pass DockDock's tokens to plugin env vars.
  - Distribution: a marketplace of downloadable code is fine for Developer ID but violates MAS 2.5.2 / 2.4.5(iv) (§6.3).

---

## 4. Data sources (2025–2026 status)

### 4.1 Now playing — Private API
- Since 15.4, `mediaremoted` checks entitlements, and "clients without the required entitlement are denied access to NowPlaying information" ([media-remote crate](https://crates.io/crates/media-remote)).
- Workaround: [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) runs `/usr/bin/perl` ("entitled to use the MediaRemote framework") to load a bundled helper framework and stream JSON. Commands: `get`, `stream` (diffs, `--no-artwork`), `send`, `seek`, `test` ([README v0.7.7](https://raw.githubusercontent.com/ungive/mediaremote-adapter/v0.7.7/README.md)). The framework is bundled, *not linked*, so it has no effect on the app's own signature (same).
- Status: actively maintained, last push 2026-10-17, with issues through Oct 2026 and none reporting a Tahoe/27 break ([issues](https://github.com/ungive/mediaremote-adapter/issues)). A DockDoor author maintains a Swift package fork ([ejbills/mediaremote-adapter](https://github.com/ejbills/mediaremote-adapter)). The `test` command lets apps fall back to AppleScript if Apple closes it (README).
- DockDock today: AppleScript to Spotify / Music only, avoiding MediaRemote because the direct call "segfaults" (`Sources/DockDock/Services/NowPlayingService.swift:7-10`, `:47-49`). Browsers, Podcasts, and others are invisible.
- Recommendation [INFERENCE]: adapter first, AppleScript fallback. Sandboxed apps can't use it (the child inherits the sandbox).

### 4.2 EventKit — Yes+TCC
- No read-only access: "To read events or reminders … your app needs full access." Write-only events exist ([Accessing the event store](https://developer.apple.com/documentation/eventkit/accessing-the-event-store)). DockDock already uses the full-access keys (`Resources/Info.plist:33-36`) and gates tiles (`Sources/DockDock/Tiles/CalendarTiles.swift:509-514`).

### 4.3 Weather — WeatherKit possible, check Open-Meteo licensing
- WeatherKit:
  - Included in the Developer Program: 500k calls/month, paid tiers above.
  - Requires the Apple Weather trademark plus a legal attribution link.
  - REST API for other platforms ([WeatherKit](https://developer.apple.com/weatherkit/)).
  - Enable it on the App ID in the portal, then add the capability in Xcode ([WWDC22 Meet WeatherKit](https://developer.apple.com/videos/play/wwdc2022/10003/), [entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.weatherkit)).
  - [INFERENCE]: restricted entitlements need an embedded Developer ID provisioning profile, which `scripts/build-app.sh` doesn't embed.
- DockDock uses Open-Meteo (`Sources/DockDock/Services/SystemServices.swift:316`). The free tier is **"only … non-commercial purposes"**, capped below 10,000 calls/day, CC-BY 4.0 ([terms](https://open-meteo.com/en/terms)). A paid DockDock needs an Open-Meteo commercial plan or WeatherKit.

### 4.4 Mail — Yes+TCC (Automation)
- Apple events to Mail need `NSAppleEventsUsageDescription`. Apple cites Mail as the example of sensitive indirect access ([doc](https://developer.apple.com/documentation/bundleresources/information-property-list/nsappleeventsusagedescription)). Hardened-runtime apps need `com.apple.security.automation.apple-events` ([doc](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.automation.apple-events)). Both are present (`Resources/Info.plist:31-32`, `Resources/DockDock.entitlements:18-19`).
- Cheaper unread count without Automation: the Dock badge (1.5).

### 4.5 Other apps' notifications — No
- `getDeliveredNotifications` "fetches all of **your app's** delivered notifications" ([doc](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/getdeliverednotifications(completionhandler:))).
- Sequoia moved the Notification Center DB "to a group container, which will be protected by TCC" ([Michael Tsai](https://mjtsai.com/blog/2024/07/15/sequoia-finally-addresses-notification-center-privacy/), [9to5Mac](https://9to5mac.com/2024/09/01/security-bite-apple-addresses-privacy-concerns-around-notification-center-database-in-macos-sequoia)).
- macOS 27 SIP: access to other teams' app-group containers is now "denied by default" ([27 notes, SIP](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes)).
- Substitute: Dock badges (1.5).

### 4.6 Focus — bool via API; name via private files
- `INFocusStatus.isFocused: Bool?` only ([doc](https://developer.apple.com/documentation/intents/infocusstatus)). It needs Focus authorization, the Focus usage string and the Communication Notifications capability. The value is from the app's perspective: "the user doesn't appear focused to an app if an enabled Focus allows notifications from that app" ([Apple sample](https://developer.apple.com/documentation/usernotifications/handling-communication-notifications-and-focus-status-updates)). The capability pulls in sandbox rules in practice ([infocus README](https://github.com/bartreardon/infocus)).
- Focus *name*: read `~/Library/DoNotDisturb/DB/Assertions.json` + `ModeConfigurations.json`, which needs Full Disk Access and changes across releases ([gist + comments](https://gist.github.com/drewkerr/0f2b61ce34e2b9e3ce0ec6a92ab05c18)). Or run a user Shortcut via `shortcuts run` ([Apple](https://support.apple.com/guide/shortcuts-mac/run-shortcuts-from-the-command-line-apd455c82f02/mac)).

### 4.7 Bluetooth battery
- Apple HID peripherals (Magic Mouse / Keyboard / Trackpad): IORegistry `AppleDeviceManagementHIDEventService` → `BatteryPercent`, keyed by `DeviceAddress` ([Stack Overflow](https://stackoverflow.com/questions/55785359)). The keys are undocumented.
- AirPods and third-party devices: private. Hammerspoon's `privateBluetoothBatteryInfo` "using Apple Private APIs" ([hs.battery](http://www.hammerspoon.org/docs/0.9.91/hs.battery.html)).
- BLE devices exposing the GATT Battery Service via CoreBluetooth hit the Bluetooth TCC prompt [INFERENCE]. DockDock already declares `NSBluetoothAlwaysUsageDescription` (`Resources/Info.plist:49-50`) and calls the undeclared `IOBluetoothPreference*` symbols via `dlsym` (`Sources/DockDock/Services/ToggleService.swift:95-117`).

### 4.8 Network speed — Yes
- Sample `getifaddrs` `if_data` byte counters ([man page](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/getifaddrs.3.html)). Already done (`Sources/DockDock/Services/SystemServices.swift:145-149`).

### 4.9 Other apps' keychain items
- Login (file-based) keychain: each item's ACL lists trusted apps. Otherwise "the system prompts the user … Deny, Allow, or Always Allow" ([Access Control Lists](https://developer.apple.com/documentation/security/access-control-lists)). ACLs don't exist for iCloud / data-protection keychain items, which use access groups ([same](https://developer.apple.com/documentation/security/access-control-lists); [TN3137](https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains)).
- DockDock reads `Claude Code-credentials` this way (`Sources/DockDock/Services/AIUsageSources.swift:41-44`).
- Risk: macOS 26.4 silently enabled data protection for the login keychain (non-portable, can't be unlocked outside its session) ([Lap Cat Software](https://lapcatsoftware.com/articles/2026/9/5.html)). Cross-app ACL prompts aren't reported changed [INFERENCE]. Re-test on each point release.
- macOS 27 adds "XProtect may now restrict access to app data commonly targeted by malicious software … files created by other developer teams' apps may be denied by default" ([27 notes, SIP](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes)). That class plausibly covers credential and log files such as `~/.claude` / `~/.codex` [INFERENCE]. Test on 27.

---

## 5. Input, design, windowing

### 5.1 Global hotkeys
- Carbon `RegisterEventHotKey` needs no TCC. The KeyboardShortcuts package is "fully sandboxed and Mac App Store compatible" ([README](https://github.com/sindresorhus/KeyboardShortcuts)). AltTab uses it for ⌘⇥ ([architecture](https://github.com/kaikozlov/alt-tab/blob/main/ARCHITECTURE.md)).
- Sequoia rule: a hotkey needs at least one modifier other than ⇧/⌥ ([KeyboardShortcuts #176](https://github.com/sindresorhus/KeyboardShortcuts/issues/176), [FB15168205](https://github.com/feedback-assistant/reports/issues/552), [forums 763878](https://developer.apple.com/forums/thread/763878)).
- `NSEvent.addGlobalMonitorForEvents`: "Key-related events may only be monitored if … trusted for accessibility" ([doc](https://developer.apple.com/documentation/appkit/nsevent/addglobalmonitorforevents(matching:handler:))). DockDock's global monitor is mouse-only (`Sources/DockDock/Panel/AutoHideController.swift:113-115`), so it prompts nothing.
- `CGEventTap` listen access = Input Monitoring (`CGPreflightListenEventAccess` / `CGRequestListenEventAccess`, [doc](https://developer.apple.com/documentation/coregraphics/cgrequestlisteneventaccess()); [Apple Support](https://support.apple.com/guide/mac-help/control-access-to-input-monitoring-on-mac-mchl4cedafb6/mac)).
- Recommendation: use KeyboardShortcuts (Carbon). No prompt for "toggle bar", "open library", "start pomodoro".

### 5.2 Liquid Glass (macOS 26)
- SwiftUI:
  - `glassEffect(_:in:)`, default `.regular` in a capsule; `.tint`, `.interactive()`.
  - `GlassEffectContainer(spacing:)` for shared rendering and morphing; `glassEffectUnion`, `glassEffectID`.
  - "Limit the use of Liquid Glass effects onscreen at the same time" ([Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)).
- AppKit: `NSGlassEffectView` (macOS 26+): `contentView`, `cornerRadius`, `style`, `tintColor`, `effectIsInteractive` ([doc](https://developer.apple.com/documentation/appkit/nsglasseffectview)). macOS 27 adds AppKit fixes for glass rendering and accessories ([27 notes, AppKit](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes)).
- DockDock today: `NSVisualEffectView(.hudWindow)` (`Sources/DockDock/Shell/ShellEnvironment.swift:87-92`) and a "Frosted Glass" theme built from a blur plus translucent fill (`Sources/DockDock/Tiles/Themes.swift:69-75`). No `glassEffect` anywhere in `Sources/`.
- Recommendation [INFERENCE]: a "Liquid Glass" theme = one `GlassEffectContainer` for the bar with per-tile `glassEffect(.regular, in: .rect(cornerRadius:))`. That matches DockDoor, which offers Liquid Glass / frosted / clear ([README](https://github.com/ejbills/DockDoor/blob/main/README.md)).

### 5.3 Spaces, full screen, Stage Manager
- Current bar: level `statusBar + 1` (`Sources/DockDock/Panel/DockBarController.swift:20`), behavior `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]` (`:75`).
- Docs:
  - `.fullScreenAuxiliary`: "displays on the same space as the full screen window".
  - `.stationary`: "Mission Control doesn't affect the window".
  - `.primary`, `.auxiliary` and `.canJoinAllApplications` apply to full screen *and Stage Manager* and are mutually exclusive ([CollectionBehavior](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct)).
- Gap [INFERENCE]: the real Dock hides in full-screen Spaces; DockDock's bar will sit over full-screen apps. There is no public "this Space is full screen" query. Heuristic: on `activeSpaceDidChangeNotification` ([doc](https://developer.apple.com/documentation/appkit/nsworkspace/activespacedidchangenotification)), check whether the frontmost app's focused AX window has `AXFullScreen` or fills the screen (CGWindowList bounds). Private alternatives: `CGSCopyManagedDisplaySpaces` / space type ([AltTab SkyLight](https://github.com/lwouis/alt-tab-macos/blob/master/src/macos/api-wrappers/SkyLight.framework.swift)).
- Stage Manager: the left/right bar positions collide with the Stage Manager strip [INFERENCE]. Offer an inset, or auto-switch to bottom.
- macOS 27 adds `.disableScreenCornerInteractions` to presentation options ([27 notes, NSApplication](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes)). Relevant if bar-edge hover fights Hot Corners.

### 5.4 Multi-display — Yes
- `NSScreen.screens` must not be cached; observe `didChangeScreenParametersNotification` ([doc](https://developer.apple.com/documentation/appkit/nsscreen/screens)). Check `screensHaveSeparateSpaces` ("Displays have separate Spaces", [doc](https://developer.apple.com/documentation/appkit/nsscreen/screenshaveseparatespaces)).
- Options: one bar per display (DockDoor Pro: "a different Dock on every display", [README](https://github.com/ejbills/DockDoor/blob/main/README.md)), or follow-the-pointer like the system Dock [INFERENCE].
- macOS 27 risk for the **notch** position: the menu bar is now a single window, which broke menu-bar managers ([gist](https://gist.github.com/ebowwa/a4eddd43a7d39c3f2d4986df0635e6ee/646e4cebe05e17b047684b2f3ed56386ca81bad6), third-party, empirical).

---

## 6. Distribution

### 6.1 Sparkle 2 — Yes
- Setup: `SPUStandardUpdaterController`, `SUFeedURL`, `SUPublicEDKey` (from `generate_keys`), EdDSA-signed archives, `generate_appcast`, an incrementing `CFBundleVersion` (DockDock: `"1"`, `Resources/Info.plist:21-22`).
- Security: serve over HTTPS; notarize the Developer ID build; optional signed feeds (`SURequireSignedFeed`, Sparkle 2.9).
- Non-sandboxed apps may remove Sparkle's XPC services. Non-Xcode builds need the `@loader_path/../Frameworks` rpath, symlinks preserved ([Sparkle docs](https://sparkle-project.org/documentation/)).
- DockDock work: copy `Sparkle.framework` into `Contents/Frameworks` in `scripts/build-app.sh` and sign it [INFERENCE].
- Dev-install pitfall: Sparkle treats dev builds as older and replaces them ([gist](https://gist.github.com/ebowwa/a4eddd43a7d39c3f2d4986df0635e6ee/646e4cebe05e17b047684b2f3ed56386ca81bad6)).

### 6.2 Notarization — script change required
- Requirements: Developer ID cert, hardened runtime (`--options=runtime`), a **secure timestamp** ("The signature does not include a secure timestamp" otherwise), no `get-task-allow`, well-formed XML entitlements ([Resolving common notarization issues](https://developer.apple.com/documentation/security/resolving-common-notarization-issues)).
- DockDock: hardened runtime is on, but it signs with `--timestamp=none` (`scripts/build-app.sh:36-38`), and the fallback drops `--options runtime` (`:38`). No `notarytool` / `stapler` step. Needed: `--timestamp`, `xcrun notarytool submit --wait`, `xcrun stapler staple`, a DMG.

### 6.3 Mac App Store — not viable without gutting the app
- Rules:
  - 2.4.5(i) "must be appropriately sandboxed"; (iii) no auto-launch without consent; (iv) no downloading code; (vii) "must use the Mac App Store to distribute updates".
  - 2.5.1 public APIs only; 2.5.2 no reading outside the container and no downloaded code that changes functionality ([App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)).
- DTS on sandboxed apps: "It's not possible to use the Accessibility APIs from a sandboxed app… your only path forward here is to directly distribute your app" (quoted from [forums 805556](https://developer.apple.com/forums/thread/805556) via [Crosley](https://blakecrosley.com/blog/window-manager-mac-app-store-sandbox)). PopClip left the MAS over the same issue ([Tsai](https://mjtsai.com/blog/2024/03/21/popclip-leaving-the-mac-app-store/)).

| DockDock feature | Breaks under sandbox/MAS because |
|---|---|
|Window lists, previews, badges, Dock menus (§1.2–1.5, 1.10)|Cross-app AX is blocked (DTS quote above)|
|MediaRemote adapter, CoreDock, `IOBluetoothPreference*` dlsym, `SACLockScreenImmediate` (`Sources/DockDock/Services/ToggleService.swift:95-131`)|2.5.1 private APIs; spawned `/usr/bin/perl` inherits the sandbox|
|AI Usage: `~/.claude`, `~/.codex` logs, Claude Code keychain item (`Sources/DockDock/Services/AIUsageSources.swift:41-44`, `:109`)|2.5.2, outside the container; another team's keychain item|
|AppleScript to Spotify / Music / Mail / Finder (`Sources/DockDock/Services/NowPlayingService.swift:246-248`)|Needs `temporary-exception.apple-events` per target (review-discretionary)|
|Sparkle|2.4.5(vii)|
|Script tiles / plugin marketplace|2.5.2, 2.4.5(iv)|
|Auto-hiding the system Dock (`Sources/DockDock/Shell/SystemDockSwap.swift`)|Changes another app's prefs; 2.5.9 "alter … native user interface elements" risk|

- Sandboxed escape hatch: drive Shortcuts via Apple events (`com.apple.shortcuts.events`), the method 941 Tiles and snApp use ([Crosley](https://blakecrosley.com/blog/window-manager-mac-app-store-sandbox), [snApp](https://github.com/OmChachad/snApp)). Not worth a MAS SKU for DockDock [INFERENCE].

### 6.4 Crash reporting
- MetricKit on macOS 12+ delivers diagnostics immediately ([MetricKit](https://developer.apple.com/documentation/metrickit)). `MXCrashDiagnostic` is marked macOS 12.0–27.2 (deprecated), replaced by the async `MetricManager` → `DiagnosticReport` / `CrashDiagnostic` in macOS 27 ([MXCrashDiagnostic](https://developer.apple.com/documentation/metrickit/mxcrashdiagnostic), [MetricKit](https://developer.apple.com/documentation/metrickit)). Data stays on device unless you upload it.
- Third-party: [sentry-cocoa](https://github.com/getsentry/sentry-cocoa) ("iOS / iPadOS / tvOS / macOS …") and [PLCrashReporter](https://github.com/microsoft/plcrashreporter) ("macOS 11.5", "only supported and public APIs").
- Xcode Organizer crash triage covers App Store / TestFlight distribution ([WWDC21-10203](https://developer.apple.com/videos/play/wwdc2021/10203)); Developer ID builds need one of the above [INFERENCE].
- Privacy positioning: DockDoor advertises "no crash reporters" ([README](https://github.com/ejbills/DockDoor/blob/main/README.md)). Pick opt-in plus local export.

### 6.5 Launch at login — Yes
- `SMAppService.mainApp.register()` ("configure the main app to launch at login", [doc](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp)). Check `status`; send the user to `openSystemSettingsLoginItems()` when approval is required ([SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)).
- DockDock has no `SMAppService` in `Sources/`. For a Dock replacement (`LSUIElement`, `Resources/Info.plist:25-26`) this is table stakes [INFERENCE].

---

## 7. Cross-cutting risks and recommendations
1. **TCC budget:** ask for each permission only when its feature is turned on. Window previews: Accessibility first, Screen Recording on its own opt-in. Badges: Accessibility. Trash count: skip Full Disk Access and show only the drop target. Grants are tied to the signing identity, so ad-hoc builds lose them (already noted in `scripts/build-app.sh:20-25`).
2. **Private-API isolation:** put every `@_silgen_name` / `dlsym` / trampoline behind one module with feature flags and a self-test. mediaremote-adapter's `test` command is the model ([README](https://raw.githubusercontent.com/ungive/mediaremote-adapter/v0.7.7/README.md)).
3. **Build system:** App Intents, a WidgetKit extension, WeatherKit (provisioning) and notarization all need more than `swift build` plus a bare `codesign`. Moving to an Xcode project (or `xcodebuild` + `appintentsmetadataprocessor` + profile embedding) unblocks four rows of the verdict table [INFERENCE].
4. **macOS 27 regression pass** (shipped): menu-bar single window (notch position); SIP/XProtect denial of other teams' data (`~/.claude`, `~/.codex`); MetricKit API change; App Intents changes ([27 notes](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes)).

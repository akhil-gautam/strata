import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The Apps and Folders sections: launchers for applications and folders.
///
/// Tile ids:
/// - `"applications"`: the 2×2 icon grid that opens /Applications.
/// - `"app:<bundle id>"` (or `"app:<absolute .app path>"` for a bundle without
///   an identifier): one application. In the bar it opens files dropped on
///   it, shows the Dock's badge, and while the app runs its menu lists the
///   app's windows and offers Hide, Quit and Force Quit.
/// - `"running-apps"`: the running apps that have no `app:` tile on the bar,
///   in launch order.
/// - `"folder:<path>"`: one folder; paths inside the home folder are stored
///   with a tilde (`"folder:~/Downloads"`, `"folder:~"`).
/// - `"trash"`: the Trash; files dropped on it move to the Trash.
/// - `"more-apps"`, `"add-folder"`: library entries that pick an app or a
///   folder and add the resulting `app:`/`folder:` tile to the bar.
///
/// Shell hooks:
/// - Set ``addToBar`` once at launch; the pickers hand it the new tile id.
/// - Before adding a library tile, call ``handleLibraryClick(id:)``; when it
///   returns `true` the click opened a picker and the id itself must not be
///   added.
@MainActor
enum AppsTiles {
    /// Appends a tile id to the bar. Set by the shell.
    static var addToBar: (@MainActor (String) -> Void)?

    /// Runs the picker behind "More Apps" and the add-folder entry. Returns
    /// `true` when `id` is one of those entries.
    static func handleLibraryClick(id: String) -> Bool {
        switch id {
        case moreAppsID:
            presentAppPicker()
            return true
        case addFolderID:
            presentFolderPanel()
            return true
        default:
            return false
        }
    }

    static let specs: [TileSpec] = appSpecs + folderSpecs

    /// Builds the tiles for user-added apps and folders.
    static func dynamicSpec(id: String) -> TileSpec? {
        if id.hasPrefix(appPrefix) {
            return appSpec(id: id, title: nil)
        }
        if id.hasPrefix(folderPrefix) {
            return folderSpec(id: id, title: nil)
        }
        return nil
    }

    // MARK: Ids

    private static let applicationsID = "applications"
    private static let runningAppsID = "running-apps"
    private static let trashID = "trash"
    private static let moreAppsID = "more-apps"
    private static let addFolderID = "add-folder"
    private static let appPrefix = "app:"
    private static let folderPrefix = "folder:"

    private static func appID(for url: URL) -> String {
        appPrefix + (Bundle(url: url)?.bundleIdentifier ?? url.path)
    }

    private static func folderID(for url: URL) -> String {
        folderPrefix + (url.path as NSString).abbreviatingWithTildeInPath
    }

    // MARK: Library

    /// The apps the library offers, in the video's order.
    private static let featuredApps: [(title: String, bundleID: String)] = [
        ("Safari", "com.apple.Safari"),
        ("Mail", "com.apple.mail"),
        ("Messages", "com.apple.MobileSMS"),
        ("Notes", "com.apple.Notes"),
        ("Calendar", "com.apple.iCal"),
        ("Music", "com.apple.Music"),
        ("Photos", "com.apple.Photos"),
        ("Finder", "com.apple.finder"),
    ]

    /// The folders the library offers, in the video's order.
    private static let featuredFolders: [(title: String, path: String)] = [
        ("Applications", "/Applications"),
        ("Downloads", "~/Downloads"),
        ("Documents", "~/Documents"),
        ("Desktop", "~/Desktop"),
        ("Pictures", "~/Pictures"),
        ("Movies", "~/Movies"),
        ("Music", "~/Music"),
        ("Home", "~"),
    ]

    private static var appSpecs: [TileSpec] {
        let applications = TileSpec(
            id: applicationsID,
            title: "Applications",
            category: .apps,
            menu: [
                .action("Open") { AppsLaunchTarget.applicationsFolder.open() },
            ],
            make: { AnyView(AppsApplicationsTile()) }
        )
        let running = TileSpec(
            id: runningAppsID,
            title: "Running Apps",
            category: .apps,
            menu: [
                .dynamic { runningAppsMenu() },
            ],
            make: { AnyView(AppsRunningTile()) }
        )
        let featured = featuredApps.compactMap { app in
            appSpec(id: appPrefix + app.bundleID, title: app.title)
        }
        let more = TileSpec(
            id: moreAppsID,
            title: "More Apps",
            category: .apps,
            make: { AnyView(AppsPickerTile(symbol: "plus.square", symbolSize: 19, action: presentAppPicker)) }
        )
        return [applications, running] + featured + [more]
    }

    private static var folderSpecs: [TileSpec] {
        let featured = featuredFolders.compactMap { folder in
            folderSpec(id: folderPrefix + folder.path, title: folder.title)
        }
        let trash = TileSpec(
            id: trashID,
            title: "Trash",
            category: .folders,
            menu: [
                .action("Open Trash") { AppsTrash.open() },
                .separator,
                .action("Empty Trash…") { AppsTrash.confirmEmpty() },
            ],
            make: { AnyView(AppsTrashTile()) }
        )
        let add = TileSpec(
            id: addFolderID,
            title: "Add Folder",
            category: .folders,
            make: { AnyView(AppsPickerTile(symbol: "folder.badge.plus", symbolSize: 20, action: presentFolderPanel)) }
        )
        return featured + [trash, add]
    }

    // MARK: Specs

    /// `nil` when the app is not installed.
    private static func appSpec(id: String, title: String?) -> TileSpec? {
        let value = String(id.dropFirst(appPrefix.count))
        let url: URL
        if value.hasPrefix("/") {
            guard FileManager.default.fileExists(atPath: value) else { return nil }
            url = URL(fileURLWithPath: value)
        } else {
            guard let resolved = NSWorkspace.shared.urlForApplication(withBundleIdentifier: value) else {
                return nil
            }
            url = resolved
        }
        let target = AppsLaunchTarget(url: url, kind: .application)
        return TileSpec(
            id: id,
            title: title ?? target.displayName,
            category: .apps,
            menu: [
                .dynamic { runningAppMenu(for: target) },
                .action("Open") { target.open() },
                .action("Show in Finder") { target.reveal() },
            ],
            make: { AnyView(AppsIconTile(target: target)) }
        )
    }

    /// `nil` when the folder does not exist.
    private static func folderSpec(id: String, title: String?) -> TileSpec? {
        let path = (String(id.dropFirst(folderPrefix.count)) as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        let target = AppsLaunchTarget(url: URL(fileURLWithPath: path, isDirectory: true), kind: .folder)
        return TileSpec(
            id: id,
            title: title ?? target.displayName,
            category: .folders,
            menu: [
                .action("Open") { target.open() },
                .action("Show in Finder") { target.reveal() },
            ],
            make: { AnyView(AppsIconTile(target: target)) }
        )
    }

    // MARK: Running apps

    /// The windows and app commands of an app tile's menu; nothing while the
    /// app is not running. The window list comes from ``AppWindows``' cache,
    /// which this also refreshes for the next time the menu opens.
    private static func runningAppMenu(for target: AppsLaunchTarget) -> [TileMenuItem] {
        guard let app = AppsRunningMonitor.shared.application(at: target.url) else { return [] }
        var items: [TileMenuItem] = [.header("Windows")]
        if !AccessibilityAccess.isTrusted {
            items.append(.action("Allow Accessibility to List Windows…") {
                _ = AccessibilityAccess.request()
            })
        } else {
            let windows = AppWindows.shared
            switch windows.listing(for: app) {
            case .loading:
                items.append(.header("Loading Windows…"))
            case .unresponsive:
                items.append(.header("Not Responding"))
            case let .windows(list) where list.isEmpty:
                items.append(.header("No Open Windows"))
            case let .windows(list):
                for window in list {
                    let title = window.isMinimized ? "\(window.title) (Minimized)" : window.title
                    items.append(.action(title) { AppWindows.shared.focus(window, of: app) })
                }
            }
            windows.refresh(app)
        }
        items.append(.separator)
        items += AppsRunningActions.commands(for: app, includingShow: false)
        items.append(.action("Force Quit…") { AppsRunningActions.confirmForceQuit(app) })
        items.append(.separator)
        return items
    }

    /// One submenu per app the Running Apps tile shows.
    private static func runningAppsMenu() -> [TileMenuItem] {
        let apps = unpinnedRunningApps()
        guard !apps.isEmpty else { return [.header("No Other Apps Running")] }
        return apps.map { app in
            TileMenuItem.submenu(app.localizedName ?? "App", AppsRunningActions.commands(for: app, includingShow: true))
        }
    }

    /// Running regular apps without an `app:` tile on the bar, in launch
    /// order.
    fileprivate static func unpinnedRunningApps() -> [NSRunningApplication] {
        var pinnedIDs: Set<String> = []
        var pinnedPaths: Set<String> = []
        for id in DockBarState.shared.tileIDs where id.hasPrefix(appPrefix) {
            let value = String(id.dropFirst(appPrefix.count))
            if value.hasPrefix("/") {
                pinnedPaths.insert(URL(fileURLWithPath: value).standardizedFileURL.path)
            } else {
                pinnedIDs.insert(value)
            }
        }
        return AppsRunningMonitor.shared.regularApps.filter { app in
            if let id = app.bundleIdentifier, pinnedIDs.contains(id) { return false }
            if let url = app.bundleURL, pinnedPaths.contains(url.standardizedFileURL.path) { return false }
            return true
        }
    }

    // MARK: Pickers

    private static let appPicker = AppPickerController()

    private static func presentAppPicker() {
        appPicker.present { descriptor in
            switch descriptor.kind {
            case .application:
                addToBar?(appID(for: descriptor.url))
            case .folder:
                addToBar?(folderID(for: descriptor.url))
            }
        }
    }

    private static func presentFolderPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        panel.prompt = "Add Folder"
        NSApp.activate()
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            addToBar?(folderID(for: url))
        }
    }
}

// MARK: - Model

/// An application bundle or folder a tile opens.
private struct AppsLaunchTarget {
    let url: URL
    let kind: AppDescriptor.Kind

    static let applicationsFolder = AppsLaunchTarget(
        url: URL(fileURLWithPath: "/Applications", isDirectory: true),
        kind: .folder
    )

    static func application(bundleID: String) -> AppsLaunchTarget? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { AppsLaunchTarget(url: $0, kind: .application) }
    }

    var displayName: String {
        if kind == .application, let bundle = Bundle(url: url),
           let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String) {
            return name
        }
        return FileManager.default.displayName(atPath: url.path)
    }

    @MainActor
    var icon: NSImage {
        IconProvider.shared.icon(
            for: AppDescriptor(id: url.path, name: url.lastPathComponent, url: url, kind: kind)
        )
    }

    @MainActor
    var isRunning: Bool {
        kind == .application && AppsRunningMonitor.shared.contains(url)
    }

    @MainActor
    func open() {
        switch kind {
        case .application:
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: nil)
        case .folder:
            NSWorkspace.shared.open(url)
        }
    }

    /// Opens files with this app, as dropping them on its Dock icon does.
    @MainActor
    func open(_ files: [URL]) {
        guard kind == .application else { return }
        AppsRunningActions.open(files, with: url)
    }

    @MainActor
    func reveal() {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

/// The running applications, kept current from NSWorkspace's launch,
/// terminate and activate notifications (an app may switch to a regular app
/// after it launched).
@MainActor
@Observable
private final class AppsRunningMonitor {
    static let shared = AppsRunningMonitor()

    private var bundlePaths: Set<String> = []
    /// Apps that appear in the Dock (regular activation policy), Shelfie
    /// aside, in launch order.
    private(set) var regularApps: [NSRunningApplication] = []

    private init() {
        refresh()
        let center = NSWorkspace.shared.notificationCenter
        let names = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
        ]
        for name in names {
            _ = center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { AppsRunningMonitor.shared.refresh() }
            }
        }
    }

    func contains(_ url: URL) -> Bool {
        bundlePaths.contains(url.standardizedFileURL.path)
    }

    /// The running instance of an app bundle, whatever its activation policy.
    func application(at url: URL) -> NSRunningApplication? {
        let path = url.standardizedFileURL.path
        return NSWorkspace.shared.runningApplications.first {
            !$0.isTerminated && $0.bundleURL?.standardizedFileURL.path == path
        }
    }

    private func refresh() {
        let running = NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }
        let paths = Set(running.compactMap { $0.bundleURL?.standardizedFileURL.path })
        if paths != bundlePaths {
            bundlePaths = paths
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        // NSWorkspace does not promise an order; launch dates do. Apps
        // without one (launched before login) come first, as listed.
        let regular = running.enumerated()
            .filter { $0.element.activationPolicy == .regular && $0.element.processIdentifier != ownPID }
            .sorted { a, b in
                switch (a.element.launchDate, b.element.launchDate) {
                case let (x?, y?) where x != y: x < y
                case (nil, _?): true
                case (_?, nil): false
                default: a.offset < b.offset
                }
            }
            .map(\.element)
        if regular.map(\.processIdentifier) != regularApps.map(\.processIdentifier) {
            regularApps = regular
        }
    }
}

/// Show, Hide, Quit and Force Quit for a running app, and opening files with
/// an app.
@MainActor
private enum AppsRunningActions {
    static func commands(for app: NSRunningApplication, includingShow: Bool) -> [TileMenuItem] {
        var items: [TileMenuItem] = []
        if includingShow {
            items.append(.action("Show") { show(app) })
        }
        if app.isHidden {
            items.append(.action("Unhide") { _ = app.unhide() })
        } else {
            items.append(.action("Hide") { _ = app.hide() })
        }
        items.append(.action("Quit") { _ = app.terminate() })
        return items
    }

    /// Brings the app forward the way clicking its Dock icon does: unhides
    /// it and asks it to reopen a window when it has none.
    static func show(_ app: NSRunningApplication) {
        guard let url = app.bundleURL else {
            _ = app.unhide()
            _ = app.activate(options: [])
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: nil)
    }

    static func open(_ files: [URL], with appURL: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(files, withApplicationAt: appURL, configuration: configuration, completionHandler: nil)
    }

    static func confirmForceQuit(_ app: NSRunningApplication) {
        let name = app.localizedName ?? "this app"
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Force quit “\(name)”?"
        alert.informativeText = "You will lose any unsaved changes."
        alert.icon = app.icon
        alert.addButton(withTitle: "Force Quit")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        _ = app.forceTerminate()
    }
}

// MARK: - Trash

private enum AppsTrashState: Sendable {
    /// The Trash could not be read (Shelfie lacks Full Disk Access).
    case unknown
    case empty
    case full
}

/// The user's Trash folder. Every call blocks; run them off the main actor.
private enum AppsTrashFolder {
    static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash", isDirectory: true)
    }

    /// Reading ~/.Trash needs Full Disk Access; without it the state is
    /// unknown rather than empty.
    static func state() -> AppsTrashState {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: url.path) else {
            return .unknown
        }
        return names.contains { $0 != ".DS_Store" && $0 != ".localized" } ? .full : .empty
    }

    /// Moves items to the Trash. Returns how many moved.
    static func trash(_ urls: [URL]) -> Int {
        var moved = 0
        for url in urls {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                moved += 1
            } catch {
                NSLog("Shelfie: couldn't move %@ to the Trash: %@", url.path, error.localizedDescription)
            }
        }
        return moved
    }

    /// Empties the Trash through Finder, which handles every volume's Trash
    /// and locked items. Needs Automation access to Finder (macOS asks once).
    static func empty() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "tell application \"Finder\" to empty trash"]
        process.standardOutput = FileHandle.nullDevice
        let errors = Pipe()
        process.standardError = errors
        do {
            try process.run()
        } catch {
            NSLog("Shelfie: couldn't empty the Trash: %@", error.localizedDescription)
            return false
        }
        let message = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            NSLog("Shelfie: couldn't empty the Trash: %@", String(decoding: message, as: UTF8.self))
            return false
        }
        return true
    }
}

/// Whether the Trash holds anything, for the full/empty icon. Checked every
/// few seconds while a Trash tile is shown, and after every drop or empty.
@MainActor
@Observable
private final class AppsTrashMonitor {
    static let shared = AppsTrashMonitor()

    private(set) var state: AppsTrashState = .unknown
    @ObservationIgnored private var inFlight = false

    func run() async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: .seconds(5))
        }
    }

    func refresh() async {
        guard !inFlight else { return }
        inFlight = true
        defer { inFlight = false }
        let read = await Task.detached(priority: .utility) { AppsTrashFolder.state() }.value
        if read != state {
            state = read
        }
    }
}

/// The Trash tile's actions.
@MainActor
private enum AppsTrash {
    private static let soundsFolder = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/"

    static func open() {
        NSWorkspace.shared.open(AppsTrashFolder.url)
    }

    static func moveToTrash(_ urls: [URL]) {
        Task {
            let moved = await Task.detached(priority: .userInitiated) { AppsTrashFolder.trash(urls) }.value
            if moved > 0 {
                playSound("dock/drag to trash.aif")
            }
            await AppsTrashMonitor.shared.refresh()
        }
    }

    static func confirmEmpty() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Are you sure you want to permanently erase the items in the Trash?"
        alert.informativeText = "You can’t undo this action."
        alert.icon = NSImage(named: NSImage.trashFullName)
        alert.addButton(withTitle: "Empty Trash")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task {
            let emptied = await Task.detached(priority: .userInitiated) { AppsTrashFolder.empty() }.value
            if emptied {
                playSound("finder/empty trash.aif")
            }
            await AppsTrashMonitor.shared.refresh()
        }
    }

    /// Plays one of the system's Finder/Dock sounds, unless "Play user
    /// interface sound effects" is off.
    private static func playSound(_ name: String) {
        if let enabled = UserDefaults.standard.object(forKey: "com.apple.sound.uiaudio.enabled") as? Bool, !enabled {
            return
        }
        NSSound(contentsOfFile: soundsFolder + name, byReference: true)?.play()
    }
}

// MARK: - Views

/// An app or folder icon. In the library the icon stands on its own; in the
/// bar it sits on a square tile, opens on click and shows a dot while the app
/// runs. An app's tile also opens files dropped on it and shows the Dock's
/// badge.
private struct AppsIconTile: View {
    let target: AppsLaunchTarget
    @Environment(\.tileContext) private var context

    var body: some View {
        switch context {
        case .library:
            AppsIcon(image: target.icon, size: TileMetrics.square)
        case .bar:
            let tile = DockTile(width: TileMetrics.square, inset: 0) {
                ZStack(alignment: .bottom) {
                    AppsIcon(image: target.icon, size: 42)
                        .overlay(alignment: .topTrailing) { badge }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .offset(y: -2)
                    if target.isRunning {
                        AppsRunningDot()
                    }
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: TileMetrics.corner, style: .continuous))
            .onTapGesture { target.open() }
            if target.kind == .application {
                tile
                    .appsFileDrop(cornerRadius: TileMetrics.corner) { target.open($0) }
                    // The pointer reaches the tile before a right-click
                    // does; read the windows now so the menu has them.
                    .onHover { inside in
                        guard inside, AccessibilityAccess.isTrusted,
                              let app = AppsRunningMonitor.shared.application(at: target.url)
                        else { return }
                        AppWindows.shared.refresh(app)
                    }
            } else {
                tile
            }
        }
    }

    @ViewBuilder
    private var badge: some View {
        if target.kind == .application, let label = DockBadges.shared.label(forApp: target.url) {
            DockBadgeView(label: label)
                .offset(x: 4, y: -4)
        }
    }
}

/// The "Applications" tile: four app icons in a 2×2 grid; opens /Applications.
private struct AppsApplicationsTile: View {
    @Environment(\.tileContext) private var context

    private static let bundleIDs = ["com.apple.Photos", "com.apple.finder", "com.apple.iCal", "com.apple.Notes"]

    var body: some View {
        let tile = DockTile(width: TileMetrics.square, inset: 0) {
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    cell(Self.bundleIDs[0])
                    cell(Self.bundleIDs[1])
                }
                GridRow {
                    cell(Self.bundleIDs[2])
                    cell(Self.bundleIDs[3])
                }
            }
        }
        if context == .bar {
            tile
                .contentShape(RoundedRectangle(cornerRadius: TileMetrics.corner, style: .continuous))
                .onTapGesture { AppsLaunchTarget.applicationsFolder.open() }
        } else {
            tile
        }
    }

    @ViewBuilder
    private func cell(_ bundleID: String) -> some View {
        if let target = AppsLaunchTarget.application(bundleID: bundleID) {
            AppsIcon(image: target.icon, size: 24)
        } else {
            Color.clear.frame(width: 24, height: 24)
        }
    }
}

/// "More Apps" and the add-folder entry: a plain tile with a symbol. In the
/// library the shell routes the click through `AppsTiles.handleLibraryClick`;
/// in the bar the tile runs its picker itself.
private struct AppsPickerTile: View {
    let symbol: String
    let symbolSize: CGFloat
    let action: @MainActor () -> Void
    @Environment(\.tileContext) private var context

    var body: some View {
        let tile = DockTile(width: TileMetrics.square) {
            Image(systemName: symbol)
                .font(.system(size: symbolSize, weight: .regular))
                .foregroundStyle(TilePalette.ink.opacity(0.82))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        if context == .bar {
            tile
                .contentShape(RoundedRectangle(cornerRadius: TileMetrics.corner, style: .continuous))
                .onTapGesture { action() }
        } else {
            tile
        }
    }
}

private struct AppsIcon: View {
    let image: NSImage
    let size: CGFloat

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }
}

/// The dot under the icon of a running app.
private struct AppsRunningDot: View {
    var body: some View {
        Circle()
            .fill(TilePalette.ink.opacity(0.8))
            .frame(width: 4, height: 4)
            .padding(.bottom, 3)
    }
}

/// The "Running Apps" tile: one icon per running app that has no tile of
/// its own on the bar, as the Dock's right-hand section. The tile grows with
/// the number of apps and scrolls past ``maxVisible``. In the library it
/// previews the first four as a 2×2 grid.
private struct AppsRunningTile: View {
    @Environment(\.tileContext) private var context

    private static let iconSize: CGFloat = 40
    private static let spacing: CGFloat = 2
    private static let padding: CGFloat = 8
    private static let maxVisible = 10

    var body: some View {
        let apps = AppsTiles.unpinnedRunningApps()
        switch context {
        case .library:
            DockTile(width: TileMetrics.square, inset: 0) {
                Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                    GridRow {
                        cell(apps, 0)
                        cell(apps, 1)
                    }
                    GridRow {
                        cell(apps, 2)
                        cell(apps, 3)
                    }
                }
            }
        case .bar:
            if apps.isEmpty {
                DockTile(width: TileMetrics.square) {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(TilePalette.caption)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                let visible = CGFloat(min(apps.count, Self.maxVisible))
                DockTile(
                    width: Self.padding * 2 + visible * Self.iconSize + (visible - 1) * Self.spacing,
                    inset: 0
                ) {
                    if apps.count > Self.maxVisible {
                        ScrollView(.horizontal, showsIndicators: false) {
                            row(apps)
                        }
                    } else {
                        row(apps)
                    }
                }
            }
        }
    }

    private func row(_ apps: [NSRunningApplication]) -> some View {
        HStack(spacing: Self.spacing) {
            ForEach(apps, id: \.processIdentifier) { app in
                AppsRunningIcon(app: app, size: Self.iconSize)
            }
        }
        .padding(.horizontal, Self.padding)
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private func cell(_ apps: [NSRunningApplication], _ index: Int) -> some View {
        if index < apps.count {
            AppsIcon(image: AppsRunningIcon.image(for: apps[index]), size: 24)
        } else {
            Color.clear.frame(width: 24, height: 24)
        }
    }
}

/// One app of the Running Apps tile: activates on click, opens dropped
/// files, shows the running dot and the Dock's badge.
private struct AppsRunningIcon: View {
    let app: NSRunningApplication
    let size: CGFloat

    static func image(for app: NSRunningApplication) -> NSImage {
        if let url = app.bundleURL {
            return AppsLaunchTarget(url: url, kind: .application).icon
        }
        return app.icon ?? NSWorkspace.shared.icon(for: .application)
    }

    var body: some View {
        let icon = ZStack(alignment: .bottom) {
            AppsIcon(image: Self.image(for: app), size: size)
                .overlay(alignment: .topTrailing) { badge }
                .frame(maxHeight: .infinity)
                .offset(y: -2)
            AppsRunningDot()
        }
        .frame(width: size)
        .contentShape(Rectangle())
        .onTapGesture { AppsRunningActions.show(app) }
        if let url = app.bundleURL {
            icon.appsFileDrop(cornerRadius: 9) { AppsRunningActions.open($0, with: url) }
        } else {
            icon
        }
    }

    @ViewBuilder
    private var badge: some View {
        if let url = app.bundleURL, let label = DockBadges.shared.label(forApp: url) {
            DockBadgeView(label: label)
                .offset(x: 4, y: -4)
        }
    }
}

/// The Trash: the system's empty or full Trash icon. In the bar a click
/// opens the Trash and files dropped on it move to the Trash. When the Trash
/// cannot be read the empty icon is shown.
private struct AppsTrashTile: View {
    @Environment(\.tileContext) private var context

    private var image: NSImage {
        let name = AppsTrashMonitor.shared.state == .full ? NSImage.trashFullName : NSImage.trashEmptyName
        return NSImage(named: name) ?? NSWorkspace.shared.icon(forFile: AppsTrashFolder.url.path)
    }

    var body: some View {
        switch context {
        case .library:
            AppsIcon(image: image, size: TileMetrics.square)
                .task { await AppsTrashMonitor.shared.run() }
        case .bar:
            DockTile(width: TileMetrics.square, inset: 0) {
                AppsIcon(image: image, size: 42)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .offset(y: -2)
            }
            .contentShape(RoundedRectangle(cornerRadius: TileMetrics.corner, style: .continuous))
            .onTapGesture { AppsTrash.open() }
            .appsFileDrop(cornerRadius: TileMetrics.corner) { AppsTrash.moveToTrash($0) }
            .task { await AppsTrashMonitor.shared.run() }
        }
    }
}

/// Accepts files dragged from Finder and highlights the view while they
/// hover over it.
private struct AppsFileDrop: ViewModifier {
    let cornerRadius: CGFloat
    let perform: @MainActor ([URL]) -> Void

    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if isTargeted {
                    ZStack {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(TilePalette.focus.opacity(0.18))
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(TilePalette.focus, lineWidth: 2)
                    }
                    .allowsHitTesting(false)
                }
            }
            .scaleEffect(isTargeted ? 1.06 : 1)
            .animation(.easeOut(duration: 0.12), value: isTargeted)
            .dropDestination(for: URL.self) { urls, _ in
                let files = urls.filter(\.isFileURL)
                guard !files.isEmpty else { return false }
                perform(files)
                return true
            } isTargeted: { targeted in
                isTargeted = targeted
            }
    }
}

private extension View {
    func appsFileDrop(cornerRadius: CGFloat, perform: @escaping @MainActor ([URL]) -> Void) -> some View {
        modifier(AppsFileDrop(cornerRadius: cornerRadius, perform: perform))
    }
}

import AppKit
import ApplicationServices
import AVFoundation
import ImageIO
import SwiftUI

/// The second half of the System section (screenshots, files, search,
/// toggles, emoji, voice memo, converter, colour picker) and the Weather
/// section.
@MainActor
enum UtilityTiles {
    static let specs: [TileSpec] = systemSpecs + weatherSpecs

    // MARK: System

    private static var systemSpecs: [TileSpec] {
        [
            TileSpec(
                id: "recent-screenshots",
                title: "Recent Screenshots",
                category: .system,
                menu: [.action("Open Screenshots Folder") { UtilityScreenshots.openFolder() }],
                make: { AnyView(UtilityRecentScreenshotsTile()) }
            ),
            TileSpec(
                id: "screenshot-capture",
                title: "Screenshot Capture",
                category: .system,
                menu: UtilityCaptureMode.allCases.map { mode in
                    TileMenuItem.action(mode.menuTitle) { UtilityScreenshots.capture(mode) }
                },
                make: { AnyView(UtilityScreenshotCaptureTile()) }
            ),
            TileSpec(
                id: "recent-files",
                title: "Recent Files",
                category: .system,
                menu: [.action("Open Recents in Finder") { UtilityRecentFiles.openRecents() }],
                make: { AnyView(UtilityRecentFilesTile()) }
            ),
            TileSpec(
                id: "downloads",
                title: "Downloads",
                category: .system,
                menu: [
                    .action("Open Latest Download") { UtilityDownloads.openLatest() },
                    .action("Open Downloads Folder") { UtilityDownloads.openFolder() },
                ],
                make: { AnyView(UtilityDownloadsTile()) }
            ),
            TileSpec(
                id: "airdrop",
                title: "AirDrop",
                category: .system,
                menu: [.action("Open AirDrop") { UtilityAirDrop.openWindow() }],
                make: { AnyView(UtilityAirDropTile()) }
            ),
            TileSpec(
                id: "file-shelf",
                title: "File Shelf",
                category: .system,
                menu: [
                    .action("Show Files in Finder") { UtilityShelfStore.shared.revealAll() },
                    .action("Clear Shelf") { UtilityShelfStore.shared.clear() },
                ],
                make: { AnyView(UtilityFileShelfTile()) }
            ),
            TileSpec(
                id: "search",
                title: "Search",
                category: .system,
                make: { AnyView(UtilitySearchTile(kind: .web)) }
            ),
            TileSpec(
                id: "finder-search",
                title: "Finder Search",
                category: .system,
                make: { AnyView(UtilitySearchTile(kind: .finder)) }
            ),
            TileSpec(
                id: "app-switcher",
                title: "App Switcher",
                category: .system,
                menu: [.action("Mission Control") { UtilityAppSwitcher.openMissionControl() }],
                make: { AnyView(UtilityAppSwitcherTile()) }
            ),
            TileSpec(
                id: "quick-toggles",
                title: "Quick Toggles",
                category: .system,
                menu: [.customize()],
                settings: TileSettings(
                    symbol: "switch.2",
                    badge: { "\(UtilityQuickToggles.shared.visibleKinds.count)" },
                    content: { AnyView(UtilityQuickTogglesSettings()) }
                ),
                make: { AnyView(UtilityQuickTogglesTile()) }
            ),
            TileSpec(
                id: "emoji",
                title: "Emoji",
                category: .system,
                menu: [.action("Emoji & Symbols") { UtilityEmojiStore.showCharacterViewer() }],
                make: { AnyView(UtilityEmojiTile()) }
            ),
            TileSpec(
                id: "voice-memo",
                title: "Voice Memo",
                category: .system,
                menu: [.action("Show Recordings") { UtilityVoiceMemo.revealRecordings() }],
                make: { AnyView(UtilityVoiceMemoTile()) }
            ),
            TileSpec(
                id: "converter",
                title: "Converter",
                category: .system,
                menu: [.action("Swap Units") { UtilityConverterStore.shared.swap() }],
                make: { AnyView(UtilityConverterTile()) }
            ),
            TileSpec(
                id: "color-picker",
                title: "Color Picker",
                category: .system,
                menu: [
                    .action("Pick Color") { UtilityColorStore.shared.pick() },
                    .action("Clear Colors") { UtilityColorStore.shared.clear() },
                ],
                make: { AnyView(UtilityColorPickerTile()) }
            ),
        ]
    }

    // MARK: Weather

    private static var weatherSpecs: [TileSpec] {
        let menu: [TileMenuItem] = [
            .action("Refresh") { Task { await WeatherInfo.shared.refreshIfNeeded(force: true) } },
            .action("Open Weather") { UtilityWeather.openApp() },
            .customize("Location & Units…"),
        ]
        let settings = TileSettings(symbol: "location.fill", title: "Location & Units") {
            AnyView(UtilityWeatherSettings())
        }
        func spec(_ id: String, _ title: String, _ make: @escaping @MainActor () -> AnyView) -> TileSpec {
            TileSpec(id: id, title: title, category: .weather, menu: menu, settings: settings, make: make)
        }
        return [
            spec("weather", "Weather") { AnyView(UtilityWeatherTile()) },
            spec("weather-details", "Weather Details") { AnyView(UtilityWeatherDetailsTile()) },
            spec("weather-forecast", "Weather Forecast") { AnyView(UtilityWeatherForecastTile()) },
            spec("today-forecast", "Today & Forecast") { AnyView(UtilityTodayForecastTile()) },
            spec("weather-status", "Weather Status") { AnyView(UtilityWeatherStatusTile()) },
            spec("hourly", "Hourly") { AnyView(UtilityHourlyTile()) },
            spec("wind", "Wind") { AnyView(UtilityWindTile()) },
            spec("sunrise-sunset", "Sunrise & Sunset") { AnyView(UtilitySunTile()) },
        ]
    }
}

// MARK: - Shared pieces

private enum UtilityStyle {
    /// Semantic colours of the toggles themselves (Wi-Fi blue, Dark Mode
    /// purple); they stay the same in every theme.
    static let blue = Color(red: 0.16, green: 0.52, blue: 1.0)
    static let green = Color(red: 0.25, green: 0.8, blue: 0.45)
    static let purple = Color(red: 0.6, green: 0.45, blue: 1.0)
    static let orange = Color(red: 1.0, green: 0.62, blue: 0.2)
    static let teal = Color(red: 0.2, green: 0.78, blue: 0.62)
    static let indigo = Color(red: 0.45, green: 0.45, blue: 0.95)
    static let red = Color(red: 0.98, green: 0.26, blue: 0.27)
    static let yellow = Color(red: 1.0, green: 0.84, blue: 0.3)
    /// The grey of glyph-only tiles.
    @MainActor static var glyph: Color { TilePalette.ink.opacity(0.62) }

    /// An inner corner radius that keeps its proportion to the tile's: the
    /// value is the radius under the default 12 pt tile corner.
    @MainActor static func corner(_ radius: CGFloat) -> CGFloat {
        TileMetrics.corner * radius / 12
    }
}

/// A tile that is one big button around a glyph.
private struct UtilityGlyphTile<Glyph: View>: View {
    var width: CGFloat = TileMetrics.square
    var help: String?
    var action: @MainActor () -> Void
    @ViewBuilder var glyph: Glyph

    var body: some View {
        DockTile(width: width) {
            Button(action: action) {
                glyph
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(help ?? "")
        }
    }
}

/// Pops a native menu at the pointer. Used by the tiles whose content is a
/// list (recent files, screenshots, running apps, shelf files).
@MainActor
private enum UtilityMenu {
    struct Item {
        var title: String
        var image: NSImage?
        var isChecked = false
        var action: (@MainActor () -> Void)?

        static let separator = Item(title: "")
    }

    static func pop(_ items: [Item]) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for item in items {
            guard let action = item.action else {
                if item.title.isEmpty {
                    menu.addItem(.separator())
                } else {
                    let header = NSMenuItem(title: item.title, action: nil, keyEquivalent: "")
                    header.isEnabled = false
                    menu.addItem(header)
                }
                continue
            }
            let target = UtilityMenuTarget(action)
            let menuItem = NSMenuItem(title: item.title, action: #selector(UtilityMenuTarget.run), keyEquivalent: "")
            menuItem.target = target
            // The target is weak; the represented object keeps it alive.
            menuItem.representedObject = target
            menuItem.image = item.image
            menuItem.state = item.isChecked ? .on : .off
            menu.addItem(menuItem)
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    /// A file's Finder icon at menu size.
    static func icon(for url: URL) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }
}

@MainActor
private final class UtilityMenuTarget: NSObject {
    private let action: @MainActor () -> Void

    init(_ action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    @objc func run() {
        action()
    }
}

/// A live Spotlight query: screenshots, recently used files.
@MainActor
@Observable
private final class UtilitySpotlightFeed {
    private(set) var urls: [URL] = []

    private let query = NSMetadataQuery()
    private let limit: Int
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init(predicate: NSPredicate, sortKey: String, limit: Int) {
        query.predicate = predicate
        query.sortDescriptors = [NSSortDescriptor(key: sortKey, ascending: false)]
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        self.limit = limit
    }

    /// Starts the query once; it then keeps itself up to date.
    func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        for name in [Notification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            observers.append(
                center.addObserver(forName: name, object: query, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.collect() }
                }
            )
        }
        query.start()
    }

    private func collect() {
        query.disableUpdates()
        defer { query.enableUpdates() }
        let count = min(query.resultCount, limit)
        let next = (0..<count).compactMap { index -> URL? in
            guard let item = query.result(at: index) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String
            else { return nil }
            return URL(fileURLWithPath: path)
        }
        if next != urls {
            urls = next
        }
    }
}

// MARK: - Recent screenshots & capture

private enum UtilityCaptureMode: CaseIterable, Identifiable {
    case window, area, screen

    var id: Self { self }

    var symbol: String {
        switch self {
        case .window: "macwindow.on.rectangle"
        case .area: "crop"
        case .screen: "rectangle.inset.filled"
        }
    }

    var tint: Color {
        switch self {
        case .window: UtilityStyle.blue
        case .area: UtilityStyle.green
        case .screen: UtilityStyle.purple
        }
    }

    var menuTitle: String {
        switch self {
        case .window: "Capture Window"
        case .area: "Capture Area"
        case .screen: "Capture Screen"
        }
    }

    /// `screencapture` flags: interactive window pick, interactive
    /// selection, or the whole screen.
    var arguments: [String] {
        switch self {
        case .window: ["-i", "-W"]
        case .area: ["-i", "-s"]
        case .screen: []
        }
    }
}

@MainActor
private enum UtilityScreenshots {
    /// Every screenshot macOS knows about, newest first.
    static let feed = UtilitySpotlightFeed(
        predicate: NSPredicate(format: "kMDItemIsScreenCapture == 1"),
        sortKey: "kMDItemFSCreationDate",
        limit: 8
    )

    private static var thumbnails: [URL: NSImage] = [:]

    /// Where the system saves screenshots (Screenshot app's "Save to").
    static var folder: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        if let path = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"),
           !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        }
        return home.appending(path: "Desktop", directoryHint: .isDirectory)
    }

    static func openFolder() {
        NSWorkspace.shared.open(folder)
    }

    static func capture(_ mode: UtilityCaptureMode) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let url = folder.appending(path: "Screenshot \(formatter.string(from: Date())).png")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = mode.arguments + [url.path]
        try? process.run()
    }

    static func showMenu() {
        let urls = feed.urls
        var items: [UtilityMenu.Item] = []
        if urls.isEmpty {
            items.append(UtilityMenu.Item(title: "No screenshots yet"))
        }
        for url in urls {
            items.append(
                UtilityMenu.Item(title: url.deletingPathExtension().lastPathComponent, image: thumbnail(for: url)) {
                    NSWorkspace.shared.open(url)
                }
            )
        }
        items.append(.separator)
        items.append(UtilityMenu.Item(title: "Open Screenshots Folder") { openFolder() })
        UtilityMenu.pop(items)
    }

    private static func thumbnail(for url: URL) -> NSImage {
        if let cached = thumbnails[url] { return cached }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 96,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return UtilityMenu.icon(for: url) }
        let aspect = CGFloat(image.width) / CGFloat(max(image.height, 1))
        let thumbnail = NSImage(cgImage: image, size: NSSize(width: 26 * aspect, height: 26))
        thumbnails[url] = thumbnail
        return thumbnail
    }
}

private struct UtilityRecentScreenshotsTile: View {
    @Environment(\.tileContext) private var context

    var body: some View {
        UtilityGlyphTile(width: 96, help: "Recent screenshots", action: UtilityScreenshots.showMenu) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(UtilityStyle.glyph)
        }
        .onAppear {
            if context == .bar { UtilityScreenshots.feed.start() }
        }
    }
}

private struct UtilityScreenshotCaptureTile: View {
    var body: some View {
        DockTile(width: 136) {
            HStack(spacing: 7) {
                ForEach(UtilityCaptureMode.allCases) { mode in
                    Button {
                        UtilityScreenshots.capture(mode)
                    } label: {
                        Image(systemName: mode.symbol)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(mode.tint)
                            .frame(width: 33, height: 33)
                            .background { Circle().fill(mode.tint.opacity(0.14)) }
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(mode.menuTitle)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Recent files & downloads

@MainActor
private enum UtilityRecentFiles {
    /// Documents opened in the last two weeks, newest first.
    static let feed = UtilitySpotlightFeed(
        predicate: NSPredicate(
            format: "kMDItemLastUsedDate >= %@ AND kMDItemContentTypeTree == 'public.content' AND kMDItemContentType != 'com.apple.application-bundle' AND kMDItemContentType != 'public.folder'",
            Date(timeIntervalSinceNow: -14 * 86_400) as NSDate
        ),
        sortKey: "kMDItemLastUsedDate",
        limit: 10
    )

    /// Finder's own Recents window.
    static func openRecents() {
        let recents = URL(
            fileURLWithPath: "/System/Library/CoreServices/Finder.app/Contents/Resources/MyLibraries/myDocuments.cannedSearch"
        )
        NSWorkspace.shared.open(recents)
    }

    static func showMenu() {
        var items: [UtilityMenu.Item] = []
        if feed.urls.isEmpty {
            items.append(UtilityMenu.Item(title: "No recent files"))
        }
        for url in feed.urls {
            items.append(UtilityMenu.Item(title: url.lastPathComponent, image: UtilityMenu.icon(for: url)) {
                NSWorkspace.shared.open(url)
            })
        }
        items.append(.separator)
        items.append(UtilityMenu.Item(title: "Open Recents in Finder") { openRecents() })
        UtilityMenu.pop(items)
    }
}

private struct UtilityRecentFilesTile: View {
    @Environment(\.tileContext) private var context

    var body: some View {
        UtilityGlyphTile(width: 58, help: "Recent files", action: UtilityRecentFiles.showMenu) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(TilePalette.ink.opacity(0.85))
        }
        .onAppear {
            if context == .bar { UtilityRecentFiles.feed.start() }
        }
    }
}

@MainActor
private enum UtilityDownloads {
    private static let partialExtensions: Set<String> = ["download", "crdownload", "part", "partial"]

    static var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Downloads", directoryHint: .isDirectory)
    }

    /// The newest finished download.
    static var latest: URL? {
        FilesService.shared.downloads
            .map(\.url)
            .first { !partialExtensions.contains($0.pathExtension.lowercased()) }
    }

    static func openLatest() {
        // Reading ~/Downloads is behind a privacy prompt: only on a click.
        if FilesService.shared.isLoaded {
            FilesService.shared.refresh(force: true)
        } else {
            FilesService.shared.loadProtectedFolders()
        }
        if let latest {
            NSWorkspace.shared.open(latest)
        } else {
            openFolder()
        }
    }

    static func openFolder() {
        NSWorkspace.shared.open(folder)
    }
}

private struct UtilityDownloadsTile: View {
    var body: some View {
        UtilityGlyphTile(
            help: UtilityDownloads.latest.map { "Open \($0.lastPathComponent)" } ?? "Open latest download",
            action: UtilityDownloads.openLatest
        ) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 21, weight: .medium))
                .symbolRenderingMode(.palette)
                .foregroundStyle(TilePalette.tileFill, TilePalette.ink.opacity(0.72))
        }
    }
}

// MARK: - AirDrop

@MainActor
private enum UtilityAirDrop {
    static func openWindow() {
        let app = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app/Contents/Applications/AirDrop.app")
        NSWorkspace.shared.open(app)
    }

    static func send(_ urls: [URL]) {
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return }
        service.perform(withItems: urls)
    }
}

private struct UtilityAirDropTile: View {
    @State private var isTargeted = false

    var body: some View {
        UtilityGlyphTile(help: "AirDrop — drop files here to send them", action: UtilityAirDrop.openWindow) {
            UtilityAirDropGlyph()
                .stroke(isTargeted ? UtilityStyle.blue : UtilityStyle.glyph, style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
                .overlay {
                    Circle()
                        .fill(isTargeted ? UtilityStyle.blue : UtilityStyle.glyph)
                        .frame(width: 4, height: 4)
                        .offset(y: 2)
                }
                .frame(width: 22, height: 22)
        }
        .dropDestination(for: URL.self) { urls, _ in
            UtilityAirDrop.send(urls.filter(\.isFileURL))
            return true
        } isTargeted: { isTargeted = $0 }
    }
}

/// Concentric arcs open at the bottom, as in the AirDrop symbol.
private struct UtilityAirDropGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY + rect.height * 0.09)
        let start = Angle.degrees(130)
        for fraction in [0.17, 0.32, 0.47] {
            let radius = rect.width * fraction
            path.move(to: CGPoint(
                x: center.x + radius * CGFloat(cos(start.radians)),
                y: center.y + radius * CGFloat(sin(start.radians))
            ))
            path.addArc(center: center, radius: radius, startAngle: start, endAngle: .degrees(50), clockwise: false)
        }
        return path
    }
}

// MARK: - File shelf

/// Files dropped on the shelf, kept until cleared.
@MainActor
@Observable
private final class UtilityShelfStore {
    static let shared = UtilityShelfStore()

    private static let key = "fileShelf.paths"

    private(set) var files: [URL]

    init() {
        let paths = UserDefaults.standard.stringArray(forKey: Self.key) ?? []
        files = paths
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func add(_ urls: [URL]) {
        let fresh = urls.filter { url in url.isFileURL && !files.contains(url) }
        guard !fresh.isEmpty else { return }
        files = fresh + files
        save()
    }

    func remove(_ url: URL) {
        files.removeAll { $0 == url }
        save()
    }

    func clear() {
        files = []
        save()
    }

    func revealAll() {
        guard !files.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(files)
    }

    func showMenu() {
        var items: [UtilityMenu.Item] = []
        if files.isEmpty {
            items.append(UtilityMenu.Item(title: "Drop files here to keep them handy"))
        }
        for url in files {
            items.append(UtilityMenu.Item(title: url.lastPathComponent, image: UtilityMenu.icon(for: url)) {
                NSWorkspace.shared.open(url)
            })
        }
        if !files.isEmpty {
            items.append(.separator)
            items.append(UtilityMenu.Item(title: "Show Files in Finder") { self.revealAll() })
            items.append(UtilityMenu.Item(title: "Clear Shelf") { self.clear() })
        }
        UtilityMenu.pop(items)
    }

    private func save() {
        UserDefaults.standard.set(files.map(\.path), forKey: Self.key)
    }
}

private struct UtilityFileShelfTile: View {
    @State private var isTargeted = false

    var body: some View {
        let store = UtilityShelfStore.shared
        UtilityGlyphTile(help: "File Shelf — drop files to keep them", action: store.showMenu) {
            if store.files.isEmpty {
                UtilityShelfGlyph(tint: isTargeted ? UtilityStyle.blue : TilePalette.ink)
            } else {
                filled(store.files)
            }
        }
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: TileMetrics.corner, style: .continuous)
                    .strokeBorder(UtilityStyle.blue, lineWidth: 1.5)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            store.add(urls)
            return true
        } isTargeted: { isTargeted = $0 }
    }

    private func filled(_ files: [URL]) -> some View {
        let shown = Array(files.prefix(3))
        return ZStack {
            ForEach(Array(shown.enumerated().reversed()), id: \.element) { index, url in
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 26, height: 26)
                    .rotationEffect(.degrees(Double(index) * -9))
                    .offset(x: CGFloat(index) * -4, y: CGFloat(index) * -1)
                    .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if files.count > 1 {
                Text("\(files.count)")
                    .font(.tileText(8, weight: .bold))
                    .foregroundStyle(TilePalette.onFocus)
                    .padding(.horizontal, 4)
                    .frame(minWidth: 13, minHeight: 13)
                    .background { Capsule().fill(TilePalette.focus) }
                    .offset(x: 8, y: 6)
            }
        }
    }
}

/// Three file cards side by side.
private struct UtilityShelfGlyph: View {
    var tint: Color

    var body: some View {
        ZStack {
            card.rotationEffect(.degrees(-7)).offset(x: -10)
            card.rotationEffect(.degrees(7)).offset(x: 10)
            card
        }
        .frame(width: 34, height: 24)
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: UtilityStyle.corner(3), style: .continuous)
            .fill(
                LinearGradient(
                    colors: [tint.opacity(0.32), tint.opacity(0.16)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: UtilityStyle.corner(3), style: .continuous)
                    .strokeBorder(Color.black.opacity(0.45), lineWidth: 1)
            }
            .frame(width: 13, height: 21)
    }
}

// MARK: - Search

private enum UtilitySearchKind {
    case web, finder

    var placeholder: String {
        switch self {
        case .web: "Search web..."
        case .finder: "Find files..."
        }
    }

    @MainActor
    func run(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        switch self {
        case .web:
            var components = URLComponents(string: "https://www.google.com/search")!
            components.queryItems = [URLQueryItem(name: "q", value: trimmed)]
            if let url = components.url {
                NSWorkspace.shared.open(url)
            }
        case .finder:
            NSWorkspace.shared.showSearchResults(forQueryString: trimmed)
        }
    }
}

private struct UtilitySearchTile: View {
    let kind: UtilitySearchKind
    @State private var query = ""

    var body: some View {
        DockTile(width: 185) {
            HStack(spacing: 9) {
                leadingIcon
                TextField(
                    "",
                    text: $query,
                    prompt: Text(kind.placeholder).foregroundStyle(TilePalette.ink.opacity(0.32))
                )
                .textFieldStyle(.plain)
                .font(.tileText(13, weight: .medium))
                .foregroundStyle(TilePalette.ink)
                .onSubmit(submit)
                Button(action: submit) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(TilePalette.ink.opacity(0.85))
                        .frame(width: 19, height: 19)
                        .background { Circle().fill(TilePalette.ink.opacity(0.17)) }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 2)
        }
    }

    @ViewBuilder
    private var leadingIcon: some View {
        switch kind {
        case .web:
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(TilePalette.ink.opacity(0.55))
        case .finder:
            Image(systemName: "folder.fill")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(TilePalette.ink.opacity(0.45))
        }
    }

    private func submit() {
        kind.run(query)
        query = ""
    }
}

// MARK: - App switcher

@MainActor
private enum UtilityAppSwitcher {
    static func openMissionControl() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Mission Control.app"))
    }

    static func showMenu() {
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { ($0.localizedName ?? "").localizedStandardCompare($1.localizedName ?? "") == .orderedAscending }
        var items: [UtilityMenu.Item] = apps.map { app in
            let icon = app.icon?.copy() as? NSImage
            icon?.size = NSSize(width: 16, height: 16)
            return UtilityMenu.Item(title: app.localizedName ?? "App", image: icon, isChecked: app.isActive) {
                if app.isHidden { app.unhide() }
                app.activate()
            }
        }
        items.append(.separator)
        items.append(UtilityMenu.Item(title: "Mission Control") { openMissionControl() })
        UtilityMenu.pop(items)
    }
}

private struct UtilityAppSwitcherTile: View {
    var body: some View {
        UtilityGlyphTile(help: "Switch apps", action: UtilityAppSwitcher.showMenu) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(UtilityStyle.glyph)
        }
    }
}

// MARK: - Quick toggles

private enum UtilityToggleKind: String, CaseIterable, Identifiable {
    case wifi
    case bluetooth
    case darkMode = "dark-mode"
    case focus
    case keyboardLock = "keyboard-lock"
    case lockScreen = "lock-screen"
    case sleep

    var id: String { rawValue }

    static let defaultShown: [UtilityToggleKind] = [.wifi, .bluetooth, .darkMode, .focus]

    var title: String {
        switch self {
        case .wifi: "Wi-Fi"
        case .bluetooth: "Bluetooth"
        case .darkMode: "Dark Mode"
        case .focus: "Focus"
        case .keyboardLock: "Keyboard Lock"
        case .lockScreen: "Lock Screen"
        case .sleep: "Sleep"
        }
    }

    @MainActor var tint: Color {
        switch self {
        case .wifi, .bluetooth: UtilityStyle.blue
        case .darkMode: UtilityStyle.purple
        case .focus: UtilityStyle.orange
        case .keyboardLock: UtilityStyle.teal
        case .lockScreen: TilePalette.ink.opacity(0.6)
        case .sleep: UtilityStyle.indigo
        }
    }

    /// One-shot actions have no "on" state.
    var isMomentary: Bool { self == .lockScreen || self == .sleep }

    /// The glyph, or `nil` for Bluetooth, which has no public SF Symbol and
    /// is drawn by ``UtilityBluetoothGlyph``.
    func symbol(isOn: Bool) -> String? {
        switch self {
        case .wifi: isOn ? "wifi" : "wifi.slash"
        case .bluetooth: nil
        case .darkMode: isOn ? "moon.fill" : "sun.max"
        case .focus: isOn ? "moon.zzz.fill" : "bell"
        case .keyboardLock: "keyboard"
        case .lockScreen: "lock.fill"
        case .sleep: "moon"
        }
    }

    /// The glyph in the settings list, which shows what the toggle is
    /// rather than its state.
    var settingsSymbol: String? {
        switch self {
        case .darkMode: "moon.fill"
        case .focus: "moon.zzz.fill"
        default: symbol(isOn: true)
        }
    }
}

@MainActor
@Observable
private final class UtilityQuickToggles {
    static let shared = UtilityQuickToggles()

    private static let shownKey = "quickToggles.shown"

    private(set) var shown: Set<UtilityToggleKind>
    private(set) var bluetoothOn = false

    init() {
        if let stored = UserDefaults.standard.stringArray(forKey: Self.shownKey) {
            shown = Set(stored.compactMap(UtilityToggleKind.init(rawValue:)))
        } else {
            shown = Set(UtilityToggleKind.defaultShown)
        }
    }

    var visibleKinds: [UtilityToggleKind] {
        UtilityToggleKind.allCases.filter { shown.contains($0) }
    }

    func isShown(_ kind: UtilityToggleKind) -> Bool {
        shown.contains(kind)
    }

    func setShown(_ kind: UtilityToggleKind, _ isShown: Bool) {
        if isShown {
            shown.insert(kind)
        } else {
            shown.remove(kind)
        }
        UserDefaults.standard.set(visibleKinds.map(\.rawValue), forKey: Self.shownKey)
    }

    func isOn(_ kind: UtilityToggleKind) -> Bool {
        let states = ToggleService.shared.states
        switch kind {
        case .wifi: return states["wifi"] ?? false
        case .bluetooth: return bluetoothOn
        case .darkMode: return states["darkmode"] ?? ToggleService.isDarkMode
        case .focus: return states["dnd"] ?? false
        case .keyboardLock: return UtilityKeyboardLock.shared.isLocked
        case .lockScreen, .sleep: return false
        }
    }

    /// Reading Bluetooth raises a privacy prompt, so only the bar tile asks;
    /// the library preview shows the last state the bar saw.
    func refresh(includingBluetooth: Bool) {
        ToggleService.shared.refresh()
        guard includingBluetooth, !isReadingBluetooth else { return }
        isReadingBluetooth = true
        Task {
            let bluetooth = await ToggleService.isBluetoothOn()
            isReadingBluetooth = false
            if bluetooth != bluetoothOn {
                bluetoothOn = bluetooth
            }
        }
    }

    /// One read at a time: the first one may sit behind the privacy prompt.
    @ObservationIgnored private var isReadingBluetooth = false

    func perform(_ kind: UtilityToggleKind) {
        switch kind {
        case .wifi: flip(serviceID: "wifi")
        case .darkMode: flip(serviceID: "darkmode")
        case .focus: flip(serviceID: "dnd")
        case .bluetooth:
            let next = !bluetoothOn
            bluetoothOn = next
            Task { await ToggleService.setBluetoothOn(next) }
        case .keyboardLock:
            UtilityKeyboardLock.shared.setLocked(!UtilityKeyboardLock.shared.isLocked)
        case .lockScreen:
            ToggleService.lockScreen()
        case .sleep:
            ToggleService.sleepNow()
        }
    }

    private func flip(serviceID: String) {
        let service = ToggleService.shared
        guard let toggle = service.toggles.first(where: { $0.id == serviceID }) else { return }
        service.toggle(toggle)
    }

    static let ringSize: CGFloat = 34
    static let ringGap: CGFloat = 7

    /// The tile grows with the number of rings shown.
    static func width(for count: Int) -> CGFloat {
        guard count > 0 else { return TileMetrics.square }
        let rings = CGFloat(count) * ringSize + CGFloat(count - 1) * ringGap
        return rings + 2 * 10
    }
}

/// Swallows every key press while on, so the keyboard can be wiped clean.
/// Clicking the ring again releases it.
@MainActor
@Observable
private final class UtilityKeyboardLock {
    static let shared = UtilityKeyboardLock()

    private(set) var isLocked = false
    @ObservationIgnored private var source: CFRunLoopSource?

    func setLocked(_ locked: Bool) {
        locked ? lock() : unlock()
    }

    private func lock() {
        guard !isLocked else { return }
        // An event tap that drops keys needs Accessibility access.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else { return }

        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged]
        var mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        // Media and brightness keys arrive as system-defined events.
        mask |= CGEventMask(1) << 14
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, _ in
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = utilityKeyboardTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }
                return nil
            },
            userInfo: nil
        ) else { return }

        utilityKeyboardTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.source = source
        isLocked = true
    }

    private func unlock() {
        guard isLocked else { return }
        if let tap = utilityKeyboardTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        utilityKeyboardTap = nil
        source = nil
        isLocked = false
    }
}

/// The tap the C callback re-enables when the system times it out. Only
/// touched on the main run loop.
nonisolated(unsafe) private var utilityKeyboardTap: CFMachPort?

private struct UtilityQuickTogglesTile: View {
    @Environment(\.tileContext) private var context

    var body: some View {
        let model = UtilityQuickToggles.shared
        let kinds = model.visibleKinds
        DockTile(width: UtilityQuickToggles.width(for: kinds.count), inset: 0) {
            if kinds.isEmpty {
                Image(systemName: "switch.2")
                    .font(.system(size: 18))
                    .foregroundStyle(UtilityStyle.glyph)
            } else {
                HStack(spacing: UtilityQuickToggles.ringGap) {
                    ForEach(kinds) { kind in
                        UtilityToggleRing(kind: kind, isOn: model.isOn(kind)) {
                            model.perform(kind)
                        }
                    }
                }
            }
        }
        .task(id: context) {
            model.refresh(includingBluetooth: context == .bar)
            guard context == .bar else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                model.refresh(includingBluetooth: true)
            }
        }
    }
}

private struct UtilityToggleRing: View {
    let kind: UtilityToggleKind
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        let lit = isOn && !kind.isMomentary
        Button(action: action) {
            UtilityToggleGlyph(kind: kind, isOn: isOn, size: 13)
                .foregroundStyle(lit ? kind.tint : TilePalette.ink.opacity(0.72))
                .frame(width: UtilityQuickToggles.ringSize, height: UtilityQuickToggles.ringSize)
                .background {
                    Circle().fill(lit ? kind.tint.opacity(0.13) : TilePalette.ink.opacity(0.07))
                }
                .overlay {
                    if lit {
                        Circle().strokeBorder(kind.tint, lineWidth: 1.8)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(kind.title)
    }
}

/// A toggle's glyph: an SF Symbol, or the drawn Bluetooth rune.
private struct UtilityToggleGlyph: View {
    let kind: UtilityToggleKind
    let isOn: Bool
    let size: CGFloat

    var body: some View {
        if let symbol = kind.symbol(isOn: isOn) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
        } else {
            UtilityBluetoothGlyph()
                .stroke(style: StrokeStyle(lineWidth: size * 0.12, lineCap: .round, lineJoin: .round))
                .frame(width: size * 0.62, height: size * 1.05)
        }
    }
}

/// The Bluetooth rune.
private struct UtilityBluetoothGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }
        var path = Path()
        path.move(to: point(0, 0.27))
        path.addLine(to: point(1, 0.73))
        path.addLine(to: point(0.5, 1))
        path.addLine(to: point(0.5, 0))
        path.addLine(to: point(1, 0.27))
        path.addLine(to: point(0, 0.73))
        return path
    }
}

private struct UtilityQuickTogglesSettings: View {
    var body: some View {
        let model = UtilityQuickToggles.shared
        VStack(spacing: 4) {
            ForEach(UtilityToggleKind.allCases) { kind in
                UtilityToggleSettingsRow(
                    kind: kind,
                    isOn: Binding(
                        get: { model.isShown(kind) },
                        set: { model.setShown(kind, $0) }
                    )
                )
            }
        }
    }
}

/// `TileSettingsToggleRow`'s layout with a view for the chip, because the
/// Bluetooth glyph is not an SF Symbol and cannot go through its `symbol`
/// string.
private struct UtilityToggleSettingsRow: View {
    let kind: UtilityToggleKind
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            chip
            VStack(alignment: .leading, spacing: 1) {
                Text(kind.title)
                    .font(.tileText(11.5, weight: .semibold))
                    .foregroundStyle(TilePalette.ink.opacity(isOn ? 0.92 : 0.6))
                Text(isOn ? "Shown on dock" : "Hidden from dock")
                    .font(.tileText(9, weight: .medium))
                    .foregroundStyle(TilePalette.ink.opacity(0.4))
            }
            Spacer(minLength: 0)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
        // Matches `TileSettingsToggleRow`'s ink-coloured switches.
        .tint(TilePalette.ink.opacity(0.82))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: min(10, TileMetrics.corner), style: .continuous)
                .fill(TilePalette.ink.opacity(isOn ? 0.045 : 0.03))
        }
    }

    @ViewBuilder
    private var chip: some View {
        Group {
            if let symbol = kind.settingsSymbol {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
            } else {
                UtilityToggleGlyph(kind: kind, isOn: true, size: 11)
            }
        }
        .foregroundStyle(kind.tint.opacity(isOn ? 1 : 0.55))
        .frame(width: 24, height: 24)
        .background { Circle().fill(kind.tint.opacity(isOn ? 0.16 : 0.08)) }
    }
}

// MARK: - Emoji

/// The emoji the tile offers, most recently used first.
@MainActor
@Observable
private final class UtilityEmojiStore {
    static let shared = UtilityEmojiStore()

    private static let key = "emoji.recents"
    static let slots = 9

    private(set) var recents: [String]

    init() {
        recents = UserDefaults.standard.stringArray(forKey: Self.key)
            ?? ["😂", "✨", "✅", "🔥", "🥹", "🙏", "💡", "🚀", "❤️"]
    }

    /// Copies the emoji and, with Accessibility access, pastes it into the
    /// app the user is typing in (the bar never takes focus).
    func use(_ emoji: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(emoji, forType: .string)

        recents.removeAll { $0 == emoji }
        recents.insert(emoji, at: 0)
        recents = Array(recents.prefix(Self.slots))
        UserDefaults.standard.set(recents, forKey: Self.key)

        guard AXIsProcessTrusted() else { return }
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: isDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }

    static func showCharacterViewer() {
        NSApp.orderFrontCharacterPalette(nil)
    }
}

private struct UtilityEmojiTile: View {
    var body: some View {
        let store = UtilityEmojiStore.shared
        let cells = store.recents.map(Optional.some) + [nil]
        DockTile(width: 129, inset: 8) {
            Grid(horizontalSpacing: 0, verticalSpacing: 1) {
                ForEach(0..<2, id: \.self) { row in
                    GridRow {
                        ForEach(0..<5, id: \.self) { column in
                            let index = row * 5 + column
                            cell(index < cells.count ? cells[index] : nil, isPlus: index == cells.count - 1)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cell(_ emoji: String?, isPlus: Bool) -> some View {
        if let emoji {
            Button {
                UtilityEmojiStore.shared.use(emoji)
            } label: {
                Text(emoji)
                    .font(.system(size: 15))
                    .frame(width: 22.6, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Copy \(emoji)")
        } else if isPlus {
            Button(action: UtilityEmojiStore.showCharacterViewer) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(TilePalette.ink.opacity(0.55))
                    .frame(width: 22.6, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Emoji & Symbols")
        } else {
            Color.clear.frame(width: 22.6, height: 22)
        }
    }
}

// MARK: - Voice memo

@MainActor
private enum UtilityVoiceMemo {
    static func revealRecordings() {
        let directory = ProductivityVoiceMemoStore.directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct UtilityVoiceMemoTile: View {
    private static let barCount = 17

    @State private var levels = Array(repeating: 0.0, count: barCount)
    @State private var elapsed: TimeInterval = 0

    var body: some View {
        let store = ProductivityVoiceMemoStore.shared
        let isLive = store.isRecording && !store.isPaused
        let shownTime = store.isRecording ? elapsed : (store.recordings.first?.duration ?? 0)

        DockTile(width: 154, inset: 8) {
            HStack(spacing: 4) {
                Text(UtilityVoiceMemo.format(shownTime))
                    .font(.tileValue(20, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(TilePalette.ink)
                    .lineLimit(1)
                    .fixedSize()
                UtilityWaveform(levels: levels, tint: isLive ? UtilityStyle.red : TilePalette.ink.opacity(0.22))
                    .frame(maxWidth: .infinity)
                    .frame(height: 24)
                secondaryButton(store: store)
                primaryButton(store: store)
            }
        }
        .task(id: store.isRecording) {
            guard store.isRecording else {
                levels = Array(repeating: 0, count: Self.barCount)
                return
            }
            while !Task.isCancelled, store.isRecording {
                if !store.isPaused {
                    elapsed = store.elapsed
                    levels.append(store.inputLevel())
                    levels.removeFirst(levels.count - Self.barCount)
                }
                try? await Task.sleep(for: .milliseconds(80))
            }
        }
        .task(id: store.isPlaying) {
            while !Task.isCancelled, store.isPlaying {
                try? await Task.sleep(for: .milliseconds(250))
                store.syncPlayback()
            }
        }
    }

    /// Pause/resume while recording; play/stop the latest memo otherwise.
    @ViewBuilder
    private func secondaryButton(store: ProductivityVoiceMemoStore) -> some View {
        if store.isRecording {
            smallButton(symbol: store.isPaused ? "play.fill" : "pause.fill", help: store.isPaused ? "Resume" : "Pause") {
                store.isPaused ? store.resumeRecording() : store.pauseRecording()
            }
        } else if let latest = store.recordings.first {
            smallButton(symbol: store.isPlaying ? "stop.fill" : "play.fill", help: "Play latest memo") {
                store.play(latest)
            }
        }
    }

    private func primaryButton(store: ProductivityVoiceMemoStore) -> some View {
        Button {
            if store.isRecording {
                store.stopRecording()
            } else {
                elapsed = 0
                Task { _ = await store.startRecording() }
            }
        } label: {
            Group {
                if store.isRecording {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(.white)
                        .frame(width: 10, height: 10)
                } else {
                    Circle()
                        .fill(.white)
                        .frame(width: 11, height: 11)
                }
            }
            .frame(width: 28, height: 28)
            .background { Circle().fill(UtilityStyle.red) }
        }
        .buttonStyle(.plain)
        .help(store.isRecording ? "Stop recording" : (store.permission == .denied ? "Microphone access is off in System Settings" : "Record"))
    }

    private func smallButton(symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 7.5, weight: .bold))
                .foregroundStyle(TilePalette.ink.opacity(0.75))
                .frame(width: 20, height: 20)
                .background { Circle().fill(TilePalette.ink.opacity(0.12)) }
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Mirrored level bars, newest on the right.
private struct UtilityWaveform: View {
    let levels: [Double]
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let count = max(levels.count, 1)
            let step = proxy.size.width / CGFloat(count)
            let barWidth = max(step * 0.55, 1)
            HStack(alignment: .center, spacing: step - barWidth) {
                ForEach(levels.indices, id: \.self) { index in
                    Capsule()
                        .fill(tint)
                        .frame(width: barWidth, height: max(2, proxy.size.height * levels[index]))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

// MARK: - Converter

private enum UtilityUnitGroup: String, CaseIterable {
    case length, weight, temperature, data

    var title: String {
        switch self {
        case .length: "Length"
        case .weight: "Weight"
        case .temperature: "Temperature"
        case .data: "Data"
        }
    }

    var units: [UtilityUnit] {
        switch self {
        case .length: [.kilometer, .mile, .meter, .foot, .centimeter, .inch]
        case .weight: [.kilogram, .pound, .gram, .ounce]
        case .temperature: [.celsius, .fahrenheit, .kelvin]
        case .data: [.megabyte, .gigabyte, .kilobyte, .terabyte]
        }
    }
}

private enum UtilityUnit: String, CaseIterable {
    case kilometer, mile, meter, foot, centimeter, inch
    case kilogram, pound, gram, ounce
    case celsius, fahrenheit, kelvin
    case kilobyte, megabyte, gigabyte, terabyte

    var group: UtilityUnitGroup {
        UtilityUnitGroup.allCases.first { $0.units.contains(self) } ?? .length
    }

    var symbol: String {
        switch self {
        case .kilometer: "km"
        case .mile: "mi"
        case .meter: "m"
        case .foot: "ft"
        case .centimeter: "cm"
        case .inch: "in"
        case .kilogram: "kg"
        case .pound: "lb"
        case .gram: "g"
        case .ounce: "oz"
        case .celsius: "°C"
        case .fahrenheit: "°F"
        case .kelvin: "K"
        case .kilobyte: "KB"
        case .megabyte: "MB"
        case .gigabyte: "GB"
        case .terabyte: "TB"
        }
    }

    /// Base units: metre, kilogram, byte. Temperatures convert via Celsius.
    private var factor: Double {
        switch self {
        case .kilometer: 1_000
        case .mile: 1_609.344
        case .meter: 1
        case .foot: 0.3048
        case .centimeter: 0.01
        case .inch: 0.0254
        case .kilogram: 1
        case .pound: 0.453_592_37
        case .gram: 0.001
        case .ounce: 0.028_349_523_125
        case .kilobyte: 1_000
        case .megabyte: 1_000_000
        case .gigabyte: 1_000_000_000
        case .terabyte: 1_000_000_000_000
        case .celsius, .fahrenheit, .kelvin: 1
        }
    }

    private func toBase(_ value: Double) -> Double {
        switch self {
        case .fahrenheit: (value - 32) * 5 / 9
        case .kelvin: value - 273.15
        default: value * factor
        }
    }

    private func fromBase(_ value: Double) -> Double {
        switch self {
        case .fahrenheit: value * 9 / 5 + 32
        case .kelvin: value + 273.15
        default: value / factor
        }
    }

    func convert(_ value: Double, to target: UtilityUnit) -> Double {
        target.fromBase(toBase(value))
    }
}

@MainActor
@Observable
private final class UtilityConverterStore {
    static let shared = UtilityConverterStore()

    private enum Key {
        static let amount = "converter.amount"
        static let from = "converter.from"
        static let to = "converter.to"
    }

    var amount: Double {
        didSet { UserDefaults.standard.set(amount, forKey: Key.amount) }
    }

    private(set) var from: UtilityUnit
    private(set) var to: UtilityUnit

    init() {
        let defaults = UserDefaults.standard
        amount = defaults.object(forKey: Key.amount) as? Double ?? 12_345
        from = defaults.string(forKey: Key.from).flatMap(UtilityUnit.init(rawValue:)) ?? .kilometer
        to = defaults.string(forKey: Key.to).flatMap(UtilityUnit.init(rawValue:)) ?? .mile
    }

    var result: Double {
        from.convert(amount, to: to)
    }

    func swap() {
        (from, to) = (to, from)
        save()
    }

    /// Picking a unit from another group moves the other side along.
    func set(_ unit: UtilityUnit, asSource: Bool) {
        if asSource {
            from = unit
            if to.group != unit.group || to == unit {
                to = unit.group.units.first { $0 != unit } ?? unit
            }
        } else {
            to = unit
            if from.group != unit.group || from == unit {
                from = unit.group.units.first { $0 != unit } ?? unit
            }
        }
        save()
    }

    func showUnitMenu(asSource: Bool) {
        var items: [UtilityMenu.Item] = []
        for group in UtilityUnitGroup.allCases {
            if !items.isEmpty { items.append(.separator) }
            items.append(UtilityMenu.Item(title: group.title))
            for unit in group.units {
                let current = asSource ? from : to
                items.append(UtilityMenu.Item(title: unit.symbol, isChecked: unit == current) {
                    self.set(unit, asSource: asSource)
                })
            }
        }
        UtilityMenu.pop(items)
    }

    private func save() {
        UserDefaults.standard.set(from.rawValue, forKey: Key.from)
        UserDefaults.standard.set(to.rawValue, forKey: Key.to)
    }
}

private struct UtilityConverterTile: View {
    @Bindable private var store = UtilityConverterStore.shared

    var body: some View {
        DockTile(width: 164) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    TextField("", value: $store.amount, format: .number)
                        .textFieldStyle(.plain)
                        .font(.tileText(12, weight: .medium))
                        .foregroundStyle(TilePalette.ink.opacity(0.5))
                        .monospacedDigit()
                    Text(store.result.formatted(.number.precision(.fractionLength(0...6))))
                        .font(.tileValue(21, weight: .bold))
                        .foregroundStyle(TilePalette.ink)
                        .monospacedDigit()
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 0) {
                    unitChip(store.from, isTarget: false) { store.showUnitMenu(asSource: true) }
                    Button(action: store.swap) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(TilePalette.ink.opacity(0.35))
                            .frame(width: 30, height: 11)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Swap units")
                    unitChip(store.to, isTarget: true) { store.showUnitMenu(asSource: false) }
                }
            }
        }
    }

    private func unitChip(_ unit: UtilityUnit, isTarget: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(unit.symbol)
                .font(.tileText(10, weight: .bold))
                .foregroundStyle(TilePalette.ink.opacity(0.9))
                .frame(width: 34, height: 16)
                .background {
                    RoundedRectangle(cornerRadius: UtilityStyle.corner(8), style: .continuous)
                        .fill(isTarget ? TilePalette.focus.opacity(0.22) : TilePalette.ink.opacity(0.08))
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Colour picker

@MainActor
@Observable
private final class UtilityColorStore {
    static let shared = UtilityColorStore()

    private static let key = "colorPicker.recents"
    static let slots = 3

    /// Hex strings, newest first.
    private(set) var recents: [String]
    @ObservationIgnored private var sampler: NSColorSampler?

    init() {
        recents = UserDefaults.standard.stringArray(forKey: Self.key) ?? []
    }

    /// Runs the system loupe; the picked colour is kept and copied as hex.
    func pick() {
        let sampler = NSColorSampler()
        self.sampler = sampler
        sampler.show { color in
            let hex = color.flatMap(Self.hex(of:))
            MainActor.assumeIsolated {
                let store = UtilityColorStore.shared
                store.sampler = nil
                guard let hex else { return }
                store.remember(hex)
                store.copy(hex)
            }
        }
    }

    func copy(_ hex: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(hex, forType: .string)
    }

    func clear() {
        recents = []
        UserDefaults.standard.set(recents, forKey: Self.key)
    }

    private func remember(_ hex: String) {
        recents.removeAll { $0 == hex }
        recents.insert(hex, at: 0)
        recents = Array(recents.prefix(Self.slots))
        UserDefaults.standard.set(recents, forKey: Self.key)
    }

    nonisolated static func hex(of color: NSColor) -> String? {
        guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
        func byte(_ value: CGFloat) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(rgb.redComponent), byte(rgb.greenComponent), byte(rgb.blueComponent))
    }

    static func color(fromHex hex: String) -> Color {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let value = Int(digits, radix: 16) ?? 0
        return Color(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

private struct UtilityColorPickerTile: View {
    private let swatch: CGFloat = 19

    var body: some View {
        let store = UtilityColorStore.shared
        DockTile(width: 58, inset: 0) {
            Grid(horizontalSpacing: 3, verticalSpacing: 3) {
                GridRow {
                    slot(store.recents, 0)
                    slot(store.recents, 1)
                }
                GridRow {
                    slot(store.recents, 2)
                    Button(action: store.pick) {
                        Image(systemName: "eyedropper")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(TilePalette.ink.opacity(0.6))
                            .frame(width: swatch, height: swatch)
                            .background {
                                RoundedRectangle(cornerRadius: UtilityStyle.corner(4), style: .continuous)
                                    .fill(TilePalette.ink.opacity(0.07))
                            }
                    }
                    .buttonStyle(.plain)
                    .help("Pick a color")
                }
            }
        }
    }

    @ViewBuilder
    private func slot(_ recents: [String], _ index: Int) -> some View {
        if index < recents.count {
            let hex = recents[index]
            Button {
                UtilityColorStore.shared.copy(hex)
            } label: {
                RoundedRectangle(cornerRadius: UtilityStyle.corner(4), style: .continuous)
                    .fill(UtilityColorStore.color(fromHex: hex))
                    .frame(width: swatch, height: swatch)
            }
            .buttonStyle(.plain)
            .help("Copy \(hex)")
        } else {
            RoundedRectangle(cornerRadius: UtilityStyle.corner(4), style: .continuous)
                .strokeBorder(TilePalette.ink.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                .frame(width: swatch, height: swatch)
        }
    }
}

// MARK: - Weather

@MainActor
private enum UtilityWeather {
    private static var filledSymbols: [String: String] = [:]

    static func openApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.weather") {
            NSWorkspace.shared.open(url)
        }
    }

    /// The filled variant of a weather symbol, as the video draws them.
    static func filled(_ symbol: String) -> String {
        if let cached = filledSymbols[symbol] { return cached }
        let candidate = symbol.hasSuffix(".fill") ? symbol : symbol + ".fill"
        let resolved = NSImage(systemSymbolName: candidate, accessibilityDescription: nil) != nil ? candidate : symbol
        filledSymbols[symbol] = resolved
        return resolved
    }

    static func temperature(_ value: Double?) -> String {
        guard let value else { return "--°" }
        return "\(Int(value.rounded()))°"
    }

    /// The current conditions' symbol, with the moon after dark.
    static func currentSymbol(_ weather: WeatherInfo) -> String {
        weather.isDay ? weather.symbol : night(weather.symbol)
    }

    /// An hour's symbol, with the moon outside today's daylight hours.
    static func symbol(for hour: WeatherInfo.Hour, in weather: WeatherInfo) -> String {
        guard let sunrise = weather.sunrise, let sunset = weather.sunset else { return hour.symbol }
        let calendar = placeCalendar
        let time = hour.date.timeIntervalSince(calendar.startOfDay(for: hour.date))
        let rise = sunrise.timeIntervalSince(calendar.startOfDay(for: sunrise))
        let set = sunset.timeIntervalSince(calendar.startOfDay(for: sunset))
        return (rise...set).contains(time) ? hour.symbol : night(hour.symbol)
    }

    /// The user's calendar in the forecast place's time zone, so a chosen
    /// city's days and daylight read as they do there.
    static var placeCalendar: Calendar {
        var calendar = Calendar.current
        calendar.timeZone = WeatherInfo.shared.timeZone
        return calendar
    }

    private static func night(_ symbol: String) -> String {
        switch symbol {
        case "sun.max": "moon.stars"
        case "cloud.sun": "cloud.moon"
        default: symbol
        }
    }

    static func weekday(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(timeZone: WeatherInfo.shared.timeZone).weekday(.abbreviated))
    }

    /// The hour in the user's clock style, at the forecast place: "13" or "1 PM".
    static func hour(_ date: Date) -> String {
        hourFormatter.timeZone = WeatherInfo.shared.timeZone
        return hourFormatter.string(from: date)
    }

    static func clock(_ date: Date?) -> String {
        guard let date else { return "--:--" }
        clockFormatter.timeZone = WeatherInfo.shared.timeZone
        return clockFormatter.string(from: date)
    }

    static func compassPoint(_ degrees: Double) -> String {
        let points = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int(((degrees.truncatingRemainder(dividingBy: 360) + 360 + 22.5) / 45).rounded(.down)) % 8
        return points[index]
    }

    /// Wind speed in the unit the forecast came in: "12 km/h" or "7 mph".
    static func speed(_ value: Double?) -> String {
        let unit = WeatherInfo.shared.isImperial ? "mph" : "km/h"
        guard let value else { return "-- \(unit)" }
        return "\(Int(value.rounded())) \(unit)"
    }

    /// A day's rain: "3 mm", or "0.12 in" with imperial units.
    static func precipitation(_ value: Double?) -> String {
        let imperial = WeatherInfo.shared.isImperial
        guard let value else { return imperial ? "-- in" : "-- mm" }
        return imperial
            ? "\(value.formatted(.number.precision(.fractionLength(0...2)))) in"
            : "\(Int(value.rounded())) mm"
    }

    private static let hourFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("j")
        return formatter
    }()

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("jmm")
        return formatter
    }()
}

/// Weather tiles ask for fresh data when they appear; the app's ticker keeps
/// it current afterwards.
private struct UtilityWeatherFeed: ViewModifier {
    func body(content: Content) -> some View {
        content.task { await WeatherInfo.shared.refreshIfNeeded() }
    }
}

private extension View {
    func utilityWeatherFeed() -> some View {
        modifier(UtilityWeatherFeed())
    }
}

/// The weather tiles' "Location & Units" popover: a city search backed by
/// Open-Meteo's geocoding (or the time-zone guess), and the units.
private struct UtilityWeatherSettings: View {
    @Bindable private var settings = WeatherSettings.shared
    @State private var query = ""
    @State private var results: [WeatherService.Place] = []
    @State private var isSearching = false
    @State private var searchFailed = false

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading("Location")
            searchField
            VStack(spacing: 2) {
                if trimmed.isEmpty {
                    row(
                        title: "Automatic (time zone)",
                        detail: automaticDetail,
                        symbol: "location",
                        isChosen: settings.location == nil
                    ) { settings.location = nil }
                    if let place = settings.location {
                        row(title: place.name, detail: place.detail, symbol: "mappin.circle.fill", isChosen: true) {}
                    }
                } else if trimmed.count < 2 {
                    status("Keep typing to search")
                } else if results.isEmpty {
                    status(isSearching ? "Searching…" : searchFailed ? "Couldn't search; check the connection" : "No places match “\(trimmed)”")
                } else {
                    ForEach(results) { place in
                        row(title: place.name, detail: place.detail, symbol: "mappin", isChosen: place == settings.location) {
                            settings.location = place
                            query = ""
                        }
                    }
                }
            }
            heading("Units")
            TileChoiceChips(
                options: WeatherSettings.Units.allCases.map { (label: $0.title, value: $0) },
                selection: $settings.units
            )
        }
        .frame(width: 270)
        // Restarts on every keystroke, so the sleep debounces the search.
        .task(id: trimmed) { await search(trimmed) }
    }

    private var automaticDetail: String {
        let place = WeatherInfo.shared.placeName
        return settings.location == nil && !place.isEmpty ? "Now: \(place)" : "Guessed from the Mac's time zone"
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(TilePalette.ink.opacity(0.45))
            TextField(
                "",
                text: $query,
                prompt: Text("Search for a city").foregroundStyle(TilePalette.ink.opacity(0.32))
            )
            .textFieldStyle(.plain)
            .font(.tileText(11.5))
            .foregroundStyle(TilePalette.ink)
            .onSubmit {
                if let first = results.first {
                    settings.location = first
                    query = ""
                }
            }
            if isSearching {
                ProgressView().controlSize(.mini)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: min(8, TileMetrics.corner), style: .continuous)
                .fill(TilePalette.ink.opacity(0.07))
        }
    }

    private func search(_ name: String) async {
        guard name.count >= 2 else {
            results = []
            isSearching = false
            searchFailed = false
            return
        }
        isSearching = true
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        do {
            let found = try await WeatherService.search(name)
            guard !Task.isCancelled else { return }
            results = found
            searchFailed = false
        } catch {
            // A newer keystroke cancelled this request; its own task reports.
            guard !Task.isCancelled else { return }
            results = []
            searchFailed = true
        }
        isSearching = false
    }

    private func heading(_ text: String) -> some View {
        Text(text)
            .font(.tileText(9.5, weight: .semibold))
            .foregroundStyle(TilePalette.ink.opacity(0.45))
    }

    private func status(_ text: String) -> some View {
        Text(text)
            .font(.tileText(10, weight: .medium))
            .foregroundStyle(TilePalette.ink.opacity(0.5))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
    }

    private func row(
        title: String,
        detail: String,
        symbol: String,
        isChosen: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(TilePalette.ink.opacity(0.6))
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.tileText(11.5, weight: .medium))
                        .foregroundStyle(TilePalette.ink.opacity(0.9))
                        .lineLimit(1)
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.tileText(9, weight: .medium))
                            .foregroundStyle(TilePalette.ink.opacity(0.4))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: isChosen ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(isChosen ? TilePalette.focus : TilePalette.ink.opacity(0.25))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background {
                RoundedRectangle(cornerRadius: min(8, TileMetrics.corner), style: .continuous)
                    .fill(TilePalette.ink.opacity(isChosen ? 0.07 : 0.0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A weather glyph in the theme's ink, toned down.
private struct UtilityWeatherIcon: View {
    let symbol: String
    var size: CGFloat = 13

    var body: some View {
        Image(systemName: UtilityWeather.filled(symbol))
            .font(.system(size: size))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(TilePalette.ink.opacity(0.72))
    }
}

/// A small "label / icon / temperature" column of the forecast tiles.
private struct UtilityForecastColumn: View {
    let label: String
    let symbol: String
    let temperature: Double?
    var isEmphasised = false

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.tileCaption(7.5, weight: isEmphasised ? .bold : .semibold))
                .foregroundStyle(TilePalette.ink.opacity(isEmphasised ? 0.9 : 0.42))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            UtilityWeatherIcon(symbol: symbol, size: 11)
                .frame(height: 13)
            Text(UtilityWeather.temperature(temperature))
                .font(.tileText(11, weight: .semibold))
                .foregroundStyle(TilePalette.ink.opacity(0.9))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }
}

private struct UtilityWeatherTile: View {
    var body: some View {
        let weather = WeatherInfo.shared
        DockTile(width: 82) {
            HStack(spacing: 5) {
                UtilityWeatherIcon(symbol: UtilityWeather.currentSymbol(weather), size: 15)
                Text(UtilityWeather.temperature(weather.temperature))
                    .font(.tileValue(22))
                    .foregroundStyle(TilePalette.ink)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .help([weather.condition, weather.placeName].filter { !$0.isEmpty }.joined(separator: " · "))
        }
        .utilityWeatherFeed()
    }
}

private struct UtilityWeatherDetailsTile: View {
    var body: some View {
        let weather = WeatherInfo.shared
        let city = weather.placeName.split(separator: ",").first.map(String.init) ?? ""
        let rain = weather.days.first?.precipitation
        DockTile(width: 198) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(city.isEmpty ? "Location" : city)
                        .font(.tileText(12, weight: .semibold))
                        .foregroundStyle(TilePalette.ink)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        detail("wind", UtilityWeather.speed(weather.windSpeed))
                        detail("drop.fill", UtilityWeather.precipitation(rain))
                    }
                }
                Spacer(minLength: 0)
                UtilityWeatherIcon(symbol: UtilityWeather.currentSymbol(weather), size: 15)
                Text(UtilityWeather.temperature(weather.temperature))
                    .font(.tileValue(22))
                    .foregroundStyle(TilePalette.ink)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .utilityWeatherFeed()
    }

    private func detail(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 7.5, weight: .semibold))
            Text(text)
                .font(.tileText(9, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(TilePalette.ink.opacity(0.5))
    }
}

private struct UtilityWeatherForecastTile: View {
    var body: some View {
        let days = Array(WeatherInfo.shared.days.prefix(4))
        DockTile(width: 171, inset: 6) {
            HStack(spacing: 0) {
                if days.isEmpty {
                    ForEach(0..<4, id: \.self) { index in
                        if index > 0 { divider }
                        UtilityForecastColumn(label: "--", symbol: "cloud", temperature: nil)
                    }
                } else {
                    ForEach(days.indices, id: \.self) { index in
                        if index > 0 { divider }
                        UtilityForecastColumn(
                            label: label(index, days[index].date),
                            symbol: days[index].symbol,
                            temperature: days[index].high
                        )
                    }
                }
            }
        }
        .utilityWeatherFeed()
    }

    private var divider: some View {
        Rectangle()
            .fill(TilePalette.ink.opacity(0.06))
            .frame(width: 1, height: 36)
    }

    private func label(_ index: Int, _ date: Date) -> String {
        switch index {
        case 0: "Today"
        case 1: "Tomorrow"
        default: UtilityWeather.weekday(date)
        }
    }
}

private struct UtilityTodayForecastTile: View {
    var body: some View {
        let weather = WeatherInfo.shared
        let upcoming = Array(weather.days.dropFirst().prefix(3))
        DockTile(width: 180) {
            HStack(spacing: 4) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(UtilityWeather.temperature(weather.temperature))
                        .font(.tileValue(27, weight: .bold))
                        .foregroundStyle(TilePalette.ink)
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                    Text("Today")
                        .font(.tileCaption(9, weight: .semibold))
                        .foregroundStyle(TilePalette.caption)
                }
                Spacer(minLength: 6)
                HStack(spacing: 2) {
                    ForEach(upcoming.indices, id: \.self) { index in
                        UtilityForecastColumn(
                            label: UtilityWeather.weekday(upcoming[index].date),
                            symbol: upcoming[index].symbol,
                            temperature: upcoming[index].high
                        )
                        .frame(width: 30)
                    }
                }
            }
        }
        .utilityWeatherFeed()
    }
}

private struct UtilityWeatherStatusTile: View {
    var body: some View {
        let weather = WeatherInfo.shared
        let status = weather.condition.isEmpty
            ? UtilityWeather.temperature(weather.temperature)
            : "\(weather.condition), \(UtilityWeather.temperature(weather.temperature))"
        DockTile(width: 86, inset: 6) {
            VStack(spacing: 3) {
                UtilityWeatherIcon(symbol: UtilityWeather.currentSymbol(weather), size: 21)
                    .frame(height: 24)
                Text(status)
                    .font(.tileText(9.5, weight: .semibold))
                    .foregroundStyle(TilePalette.ink.opacity(0.88))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .utilityWeatherFeed()
    }
}

private struct UtilityHourlyTile: View {
    var body: some View {
        let hours = Array(WeatherInfo.shared.hours.prefix(7))
        DockTile(width: 250, inset: 6) {
            HStack(spacing: 0) {
                if hours.isEmpty {
                    ForEach(0..<7, id: \.self) { index in
                        UtilityForecastColumn(label: index == 0 ? "Now" : "--", symbol: "cloud", temperature: nil, isEmphasised: index == 0)
                    }
                } else {
                    ForEach(hours.indices, id: \.self) { index in
                        UtilityForecastColumn(
                            label: index == 0 ? "Now" : UtilityWeather.hour(hours[index].date),
                            symbol: UtilityWeather.symbol(for: hours[index], in: WeatherInfo.shared),
                            temperature: hours[index].temperature,
                            isEmphasised: index == 0
                        )
                    }
                }
            }
        }
        .utilityWeatherFeed()
    }
}

private struct UtilityWindTile: View {
    var body: some View {
        let weather = WeatherInfo.shared
        DockTile(width: 176) {
            HStack(spacing: 11) {
                UtilityCompass(direction: weather.windDirection)
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(UtilityWeather.speed(weather.windSpeed))
                        .font(.tileValue(17))
                        .foregroundStyle(TilePalette.ink)
                        .monospacedDigit()
                        .lineLimit(1)
                    Text(weather.windDirection.map { "\(UtilityWeather.compassPoint($0)) wind" } ?? "Wind")
                        .font(.tileCaption(9))
                        .foregroundStyle(TilePalette.ink.opacity(0.6))
                    Text("Gusts \(UtilityWeather.speed(weather.windGusts))")
                        .font(.tileCaption(8))
                        .foregroundStyle(TilePalette.ink.opacity(0.3))
                }
                Spacer(minLength: 0)
            }
        }
        .utilityWeatherFeed()
    }
}

/// A compass rose with an arrow pointing where the wind blows to.
private struct UtilityCompass: View {
    let direction: Double?

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let radius = size / 2
            ZStack {
                Circle().fill(TilePalette.ink.opacity(0.03))
                Circle().strokeBorder(TilePalette.ink.opacity(0.16), lineWidth: 1)
                ForEach(Array(["N", "E", "S", "W"].enumerated()), id: \.offset) { index, letter in
                    label(letter, size: 6, opacity: 0.75, angle: Double(index) * 90, radius: radius - 6)
                }
                ForEach(Array(["NE", "SE", "SW", "NW"].enumerated()), id: \.offset) { index, letter in
                    label(letter, size: 3.6, opacity: 0.32, angle: 45 + Double(index) * 90, radius: radius - 7)
                }
                if let direction {
                    Image(systemName: "location.north.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(TilePalette.ink.opacity(0.85))
                        .rotationEffect(.degrees(direction + 180))
                }
            }
            .frame(width: size, height: size)
        }
    }

    private func label(_ text: String, size: CGFloat, opacity: Double, angle: Double, radius: CGFloat) -> some View {
        let radians = angle * .pi / 180
        return Text(text)
            .font(.tileText(size, weight: .bold))
            .foregroundStyle(TilePalette.ink.opacity(opacity))
            .offset(x: radius * CGFloat(sin(radians)), y: -radius * CGFloat(cos(radians)))
    }
}

private struct UtilitySunTile: View {
    var body: some View {
        let weather = WeatherInfo.shared
        DockTile(width: 208) {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                VStack(spacing: 5) {
                    UtilitySunArc(progress: progress(at: context.date, sunrise: weather.sunrise, sunset: weather.sunset))
                        .frame(height: 15)
                    HStack(spacing: 4) {
                        sunIcon("sunrise.fill")
                        Text(UtilityWeather.clock(weather.sunrise))
                        Spacer(minLength: 0)
                        Text(UtilityWeather.clock(weather.sunset))
                        sunIcon("sunset.fill")
                    }
                    .font(.tileText(11, weight: .semibold))
                    .foregroundStyle(TilePalette.ink.opacity(0.9))
                    .monospacedDigit()
                }
                .padding(.top, 3)
            }
        }
        .utilityWeatherFeed()
    }

    private func sunIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 9))
            .symbolRenderingMode(.palette)
            .foregroundStyle(UtilityStyle.orange, UtilityStyle.orange.opacity(0.7))
    }

    /// Where the sun is between sunrise (0) and sunset (1); `nil` at night.
    private func progress(at date: Date, sunrise: Date?, sunset: Date?) -> Double? {
        guard let sunrise, let sunset, sunset > sunrise else { return nil }
        let calendar = UtilityWeather.placeCalendar
        // The forecast's times are today's; compare on the time of day.
        let start = calendar.startOfDay(for: date)
        let rise = sunrise.timeIntervalSince(calendar.startOfDay(for: sunrise))
        let set = sunset.timeIntervalSince(calendar.startOfDay(for: sunset))
        let now = date.timeIntervalSince(start)
        guard now >= rise, now <= set, set > rise else { return nil }
        return (now - rise) / (set - rise)
    }
}

/// The sun's path: a shallow arch in the theme's ink, warming to orange
/// around the sun.
private struct UtilitySunArc: View {
    let progress: Double?

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let path = Self.path(in: size)
            let grey = TilePalette.ink.opacity(0.35)
            if let progress {
                path.stroke(
                    LinearGradient(
                        stops: [
                            .init(color: grey, location: 0),
                            .init(color: UtilityStyle.orange.opacity(0.85), location: max(0, progress - 0.3)),
                            .init(color: UtilityStyle.yellow, location: progress),
                            .init(color: UtilityStyle.orange.opacity(0.85), location: min(1, progress + 0.3)),
                            .init(color: grey, location: 1),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 1.6, lineCap: .round)
                )
                Circle()
                    .fill(UtilityStyle.yellow)
                    .frame(width: 8, height: 8)
                    .shadow(color: UtilityStyle.yellow.opacity(0.7), radius: 4)
                    .position(Self.point(progress, in: size))
            } else {
                path.stroke(grey, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            }
        }
    }

    private static func point(_ t: Double, in size: CGSize) -> CGPoint {
        let amplitude = size.height - 4
        return CGPoint(
            x: size.width * t,
            y: size.height - 2 - amplitude * sin(.pi * t)
        )
    }

    private static func path(in size: CGSize) -> Path {
        var path = Path()
        let steps = 48
        for step in 0...steps {
            let t = Double(step) / Double(steps)
            let point = point(t, in: size)
            if step == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }
}

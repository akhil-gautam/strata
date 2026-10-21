import AppKit
import SwiftUI

/// The Scripts section, added by the Script Tiles extension: one tile per
/// executable file in `~/Library/Application Support/DockDock/Scripts`.
///
/// Tile ids: `"script:<filename>"`. The filename follows xbar's convention,
/// `name.<interval>.<ext>` (`hello.5s.sh` runs every 5 s; unmarked scripts
/// run every minute).
///
/// A script never runs until the user approves it; approval is the SHA-256
/// of the file's contents, so any edit asks again. Scripts only run from the
/// bar; the library shows their last output or a placeholder.
@MainActor
enum ScriptTiles {
    static let prefix = "script:"

    static func id(for filename: String) -> String { prefix + filename }

    /// One library tile per discovered script.
    static var librarySpecs: [TileSpec] {
        ScriptStore.shared.scripts.map { spec(filename: $0.filename) }
    }

    /// Builds the tile for a `script:` id, whether or not the file exists
    /// (a missing script says so on the bar instead of vanishing from it).
    static func dynamicSpec(id: String) -> TileSpec? {
        guard id.hasPrefix(prefix) else { return nil }
        let filename = String(id.dropFirst(prefix.count))
        guard !filename.isEmpty, !filename.contains("/"), !filename.hasPrefix(".") else { return nil }
        return spec(filename: filename)
    }

    private static func spec(filename: String) -> TileSpec {
        TileSpec(
            id: id(for: filename),
            title: ScriptFiles.title(of: filename),
            category: .scripts,
            menu: [
                .dynamic { outputMenu(filename) },
                .action("Refresh") { ScriptStore.shared.refresh(filename) },
                .dynamic { trustMenu(filename) },
                .action("Reveal in Finder") { ScriptStore.shared.reveal(filename) },
            ],
            make: { AnyView(ScriptTile(filename: filename)) }
        )
    }

    /// The items the script's last output asked for.
    private static func outputMenu(_ filename: String) -> [TileMenuItem] {
        let store = ScriptStore.shared
        guard let item = store.item(filename), store.trust(of: item) == .trusted,
              let entries = store.states[filename]?.output?.menu, !entries.isEmpty else { return [] }
        let items = entries.map { entry -> TileMenuItem in
            if let link = entry.url {
                return .action(entry.title) { open(link) }
            }
            if entry.refreshes {
                return .action(entry.title) { ScriptStore.shared.refresh(filename) }
            }
            return .header(entry.title)
        }
        return items + [.separator]
    }

    private static func trustMenu(_ filename: String) -> [TileMenuItem] {
        let store = ScriptStore.shared
        guard let item = store.item(filename) else { return [] }
        if store.trust(of: item) == .trusted {
            return [.action("Revoke Approval") { ScriptStore.shared.revoke(filename) }]
        }
        return [.action("Review Script…") { ScriptStore.shared.review(filename) }]
    }

    static func open(_ link: String) {
        guard let url = URL(string: link) else {
            NSLog("DockDock: script link is not a URL: %@", link)
            return
        }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Store

/// The scripts in the Scripts folder, which of them the user approved, and
/// their latest output. The folder is watched while the extension is on and
/// rescanned whenever the library opens.
@MainActor
@Observable
final class ScriptStore {
    static let shared = ScriptStore()

    enum Trust {
        case trusted
        case notReviewed
        /// Approved once, edited since.
        case changed
    }

    struct TileState {
        var output: ScriptOutput?
        /// Why the latest run failed; `output` keeps the last good value.
        var error: String?
        var ranAt: Date?
    }

    /// Executable files in the folder, by name.
    private(set) var scripts: [ScriptFileInfo] = []
    /// False until the first scan finishes.
    private(set) var hasScanned = false
    /// Latest output per filename.
    private(set) var states: [String: TileState] = [:]
    /// Approved contents: filename → SHA-256, in UserDefaults `scripts.trusted`.
    private var trusted: [String: String]

    @ObservationIgnored private var isActive = false
    @ObservationIgnored private var watcher: DispatchSourceFileSystemObject?
    @ObservationIgnored private var scanGeneration = 0
    @ObservationIgnored private var inFlight: Set<String> = []
    /// Filenames with a running refresh loop (tiles on the bar).
    @ObservationIgnored private var looping: [String: Int] = [:]
    @ObservationIgnored private var isReviewing = false

    private static let trustKey = "scripts.trusted"

    private init() {
        trusted = UserDefaults.standard.dictionary(forKey: Self.trustKey) as? [String: String] ?? [:]
        observeLibrary()
        if ExtensionStore.shared.isEnabled(.scripts) {
            setActive(true)
        }
    }

    // MARK: Discovery

    /// Called when the extension is switched on or off: creates and watches
    /// the folder, or stops watching it.
    func setActive(_ on: Bool) {
        guard on != isActive else { return }
        isActive = on
        if on {
            scan(createFolder: true)
        } else {
            stopWatching()
        }
    }

    func rescan() {
        scan(createFolder: false)
    }

    func item(_ filename: String) -> ScriptFileInfo? {
        scripts.first { $0.filename == filename }
    }

    private func scan(createFolder: Bool) {
        scanGeneration += 1
        let generation = scanGeneration
        Task {
            let found = await Task.detached(priority: .utility) {
                ScriptFiles.scan(createFolder: createFolder)
            }.value
            guard generation == scanGeneration else { return }
            apply(found)
        }
    }

    private func apply(_ found: [ScriptFileInfo]) {
        hasScanned = true
        if found != scripts {
            scripts = found
        }
        let names = Set(found.map(\.filename))
        if states.keys.contains(where: { !names.contains($0) }) {
            states = states.filter { names.contains($0.key) }
        }
        if isActive {
            startWatching()
        }
        // Bar tiles waiting for their script (launch, a new or renamed file).
        for filename in looping.keys {
            Task { await load(filename, force: false) }
        }
    }

    private func startWatching() {
        guard watcher == nil else { return }
        let descriptor = open(ScriptFiles.folder.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .link],
            queue: .main
        )
        source.setEventHandler {
            MainActor.assumeIsolated { ScriptStore.shared.folderChanged() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watcher = source
    }

    private func stopWatching() {
        watcher?.cancel()
        watcher = nil
    }

    private func folderChanged() {
        // The folder itself moved or went away: watch its path afresh.
        if let events = watcher?.data, !events.isDisjoint(with: [.delete, .rename]) {
            stopWatching()
        }
        rescan()
    }

    /// Rescans each time the widget library opens.
    private func observeLibrary() {
        withObservationTracking {
            _ = DockBarState.shared.isEditing
        } onChange: {
            Task { @MainActor in
                let store = ScriptStore.shared
                if store.isActive, DockBarState.shared.isEditing {
                    store.rescan()
                }
                store.observeLibrary()
            }
        }
    }

    // MARK: Trust

    func trust(of item: ScriptFileInfo) -> Trust {
        guard let approved = trusted[item.filename] else { return .notReviewed }
        return approved == item.hash ? .trusted : .changed
    }

    /// Shows the script and asks the user to approve it.
    func review(_ filename: String) {
        guard !isReviewing, let item = self.item(filename) else { return }
        isReviewing = true
        let url = item.url
        Task {
            defer { isReviewing = false }
            let preview = await Task.detached(priority: .userInitiated) { ScriptFiles.preview(url) }.value
            guard let preview else {
                NSSound.beep()
                return
            }
            guard ScriptTrustPrompt.confirm(item, preview: preview) else { return }
            approve(filename, hash: preview.hash)
        }
    }

    /// Trusts exactly the contents the user was shown. Approval only records
    /// trust; the script first runs when (or if) its tile is on the bar.
    private func approve(_ filename: String, hash: String) {
        trusted[filename] = hash
        saveTrust()
        if let index = scripts.firstIndex(where: { $0.filename == filename }) {
            scripts[index].hash = hash
        }
        states[filename] = nil
        if isOnBar(filename) {
            refresh(filename)
        }
    }

    func revoke(_ filename: String) {
        trusted[filename] = nil
        saveTrust()
        states[filename] = nil
    }

    private func saveTrust() {
        UserDefaults.standard.set(trusted, forKey: Self.trustKey)
    }

    // MARK: Running

    /// Keeps the script's output fresh while its bar tile is on screen.
    func run(_ filename: String) async {
        looping[filename, default: 0] += 1
        defer {
            let count = (looping[filename] ?? 1) - 1
            looping[filename] = count > 0 ? count : nil
        }
        while !Task.isCancelled {
            await load(filename, force: false)
            do {
                try await Task.sleep(for: .seconds(ScriptFiles.interval(of: filename)))
            } catch {
                return
            }
        }
    }

    func refresh(_ filename: String) {
        Task { await load(filename, force: true) }
    }

    /// Scripts only ever run for a tile on the bar.
    private func isOnBar(_ filename: String) -> Bool {
        DockBarState.shared.tileIDs.contains(ScriptTiles.id(for: filename))
    }

    private func load(_ filename: String, force: Bool) async {
        guard isActive, isOnBar(filename), !inFlight.contains(filename), let item = self.item(filename),
              let hash = item.hash, trust(of: item) == .trusted else { return }
        if !force, let ranAt = states[filename]?.ranAt, Date().timeIntervalSince(ranAt) < item.interval - 0.5 {
            return
        }

        inFlight.insert(filename)
        defer { inFlight.remove(filename) }
        let result = await ScriptRunner.shared.run(item.url, approvedHash: hash)
        // Revoked or re-approved while it ran.
        guard trusted[filename] == hash else { return }
        switch result {
        case .output(let output):
            states[filename] = TileState(output: output, error: nil, ranAt: Date())
        case .failed(let message):
            var state = states[filename] ?? TileState()
            state.error = message
            state.ranAt = Date()
            states[filename] = state
            NSLog("DockDock: script %@ failed: %@", filename, message)
        case .changed(let current):
            // Edited since approval: the tile asks for a review again.
            if let index = scripts.firstIndex(where: { $0.filename == filename }) {
                scripts[index].hash = current
            }
        }
    }

    // MARK: Folder

    func openFolder() {
        let folder = ScriptFiles.folder
        Task {
            await Task.detached(priority: .userInitiated) {
                _ = try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            }.value
            NSWorkspace.shared.open(folder)
        }
    }

    func reveal(_ filename: String) {
        if let item = self.item(filename) {
            NSWorkspace.shared.activateFileViewerSelecting([item.url])
        } else {
            openFolder()
        }
    }

    /// Writes the example scripts that are missing; returns how many.
    func installExamples() async -> Int {
        let added = await Task.detached(priority: .userInitiated) { ScriptFiles.installExamples() }.value
        rescan()
        return added
    }
}

// MARK: - Approval

/// The alert that shows a script before it may run.
@MainActor
private enum ScriptTrustPrompt {
    static func confirm(_ item: ScriptFileInfo, preview: ScriptPreview) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Allow “\(item.filename)” to run?"
        let path = (item.url.path as NSString).abbreviatingWithTildeInPath
        alert.informativeText = """
        \(path)
        Runs every \(ScriptFiles.intervalLabel(item.interval)) while its tile is on the bar.

        Scripts run with DockDock's permissions: they can read your files, use the network and anything else you have allowed DockDock. Only approve scripts you trust. Editing the file asks again.
        """
        alert.accessoryView = codeView(preview)
        alert.addButton(withTitle: "Approve")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }

    private static func codeView(_ preview: ScriptPreview) -> NSView {
        let scroll = NSTextView.scrollableTextView()
        scroll.frame = NSRect(x: 0, y: 0, width: 440, height: 220)
        scroll.borderType = .bezelBorder
        if let text = scroll.documentView as? NSTextView {
            text.isEditable = false
            text.isSelectable = true
            text.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            text.textContainerInset = NSSize(width: 4, height: 4)
            text.string = preview.text + (preview.isTruncated ? "\n…" : "")
        }
        return scroll
    }
}

// MARK: - Tile

private extension ScriptTileWidth {
    var points: CGFloat {
        switch self {
        case .small: 110
        case .medium: 160
        case .large: 230
        }
    }
}

private extension Color {
    init(rgb: UInt32) {
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}

/// What a click on a script tile does.
private enum ScriptTileAction {
    case none
    case review
    case refresh
    case open(String)
    case revealFolder
}

/// What a script tile shows.
private enum ScriptTileContent {
    /// A state without output: symbol, value over caption.
    case message(value: String, caption: String, symbol: String, action: ScriptTileAction)
    /// The script's output; `staleBecause` is the latest failure, if any.
    case output(ScriptOutput, staleBecause: String?)
}

private struct ScriptTile: View {
    let filename: String
    @Environment(\.tileContext) private var context

    var body: some View {
        let store = ScriptStore.shared
        let shown = content(store)
        Button {
            perform(shown)
        } label: {
            tile(shown)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .task {
            // Untrusted code never runs from the library.
            guard context == .bar else { return }
            await store.run(filename)
        }
    }

    private func content(_ store: ScriptStore) -> ScriptTileContent {
        let state = store.states[filename]
        let title = ScriptFiles.title(of: filename)
        if context == .library {
            if let output = state?.output {
                return .output(output, staleBecause: nil)
            }
            return .message(value: title, caption: "Run to preview", symbol: "terminal", action: .none)
        }
        guard let item = store.item(filename) else {
            if store.hasScanned {
                return .message(value: "Missing", caption: filename, symbol: "questionmark.folder", action: .revealFolder)
            }
            return .message(value: "—", caption: title, symbol: "terminal", action: .none)
        }
        switch store.trust(of: item) {
        case .notReviewed:
            return .message(value: "Review script", caption: title, symbol: "checkmark.shield", action: .review)
        case .changed:
            return .message(value: "Changed — review", caption: title, symbol: "exclamationmark.shield", action: .review)
        case .trusted:
            break
        }
        if let output = state?.output {
            return .output(output, staleBecause: state?.error)
        }
        if let error = state?.error {
            return .message(value: "Error", caption: error, symbol: "exclamationmark.triangle", action: .refresh)
        }
        return .message(value: "—", caption: "running…", symbol: "terminal", action: .none)
    }

    private func perform(_ content: ScriptTileContent) {
        let action: ScriptTileAction = switch content {
        case .message(_, _, _, let tap): tap
        case .output(let output, _): output.url.map { ScriptTileAction.open($0) } ?? .refresh
        }
        switch action {
        case .none: break
        case .review: ScriptStore.shared.review(filename)
        case .refresh: ScriptStore.shared.refresh(filename)
        case .open(let link): ScriptTiles.open(link)
        case .revealFolder: ScriptStore.shared.openFolder()
        }
    }

    @ViewBuilder
    private func tile(_ content: ScriptTileContent) -> some View {
        switch content {
        case .message(let value, let caption, let symbol, _):
            DockTile(width: ScriptTileWidth.medium.points) {
                HStack(spacing: 8) {
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(TilePalette.caption)
                        .frame(width: 20)
                    TileReadout(value: value, caption: caption, valueSize: 15)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        case .output(let output, let stale):
            ScriptOutputTile(output: output, fallbackCaption: ScriptFiles.title(of: filename), stale: stale)
        }
    }
}

/// A script's output: optional icon, value over caption, and a sparkline or
/// progress ring.
private struct ScriptOutputTile: View {
    let output: ScriptOutput
    let fallbackCaption: String
    let stale: String?

    var body: some View {
        let width = output.width ?? .medium
        let tint = output.tint.map(Color.init(rgb:)) ?? TilePalette.focus
        // A small tile has room for one accessory: the ring, else the icon.
        let showsIcon = output.icon != nil && (width != .small || output.progress == nil)
        DockTile(width: width.points) {
            HStack(spacing: 8) {
                if showsIcon, let icon = output.icon {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 20)
                }
                TileReadout(value: output.value, caption: output.caption ?? fallbackCaption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let progress = output.progress {
                    ScriptProgressRing(value: progress, tint: tint)
                } else if width != .small, let series = output.sparkline {
                    Sparkline(values: series)
                        .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .frame(width: width == .large ? 72 : 54, height: 24)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if let stale {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(DockAccent.orange)
                    .padding(5)
                    .help("Last run failed: \(stale)")
            }
        }
    }
}

/// A thin ring for `progress`, like the System gauges.
private struct ScriptProgressRing: View {
    var value: Double
    var tint: Color
    var diameter: CGFloat = 30
    var lineWidth: CGFloat = 3.5

    var body: some View {
        ZStack {
            Circle()
                .stroke(TilePalette.ink.opacity(0.12), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(value, 0.001), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.4), value: value)
        }
        .frame(width: diameter, height: diameter)
    }
}

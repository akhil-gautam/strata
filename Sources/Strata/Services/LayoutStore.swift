import Foundation

/// Persists the bar's contents and behaviour.
@MainActor
final class LayoutStore {
    struct Layout: Codable {
        /// Tile ids on the bar, in order. Empty means "never set": the bar
        /// starts with `TileCatalog.defaultBar`.
        var barTiles: [String] = []
        /// Slide the bar out of the way when the pointer is elsewhere.
        var autoHide = false
        /// Seconds the pointer must be away before the bar hides.
        var hideDelay: Double = 1.2
        /// Auto-hide the macOS Dock while Strata's bar is on screen.
        var hideSystemDock = true
        /// The user's own Dock auto-hide setting, remembered while Strata
        /// overrides it so quitting (or the next launch after a crash) can put
        /// it back.
        var systemDockOriginalAutohide: Bool?

        init() {}

        /// Tolerant decoding: a layout file written by an older build must
        /// still load.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            barTiles = try container.decodeIfPresent([String].self, forKey: .barTiles) ?? []
            autoHide = try container.decodeIfPresent(Bool.self, forKey: .autoHide) ?? false
            hideDelay = try container.decodeIfPresent(Double.self, forKey: .hideDelay) ?? 1.2
            hideSystemDock = try container.decodeIfPresent(Bool.self, forKey: .hideSystemDock) ?? true
            systemDockOriginalAutohide = try container.decodeIfPresent(
                Bool.self,
                forKey: .systemDockOriginalAutohide
            )
        }
    }

    private(set) var layout: Layout
    private let fileURL: URL

    init() {
        let support = AppPaths.support
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        fileURL = support.appending(path: "layout.json")
        layout = Layout()
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let decoded = try? JSONDecoder().decode(Layout.self, from: data) {
            layout = decoded
        }
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(layout) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func setBarTiles(_ tiles: [String]) {
        layout.barTiles = tiles
        save()
    }

    func setAutoHide(_ enabled: Bool) {
        layout.autoHide = enabled
        save()
    }

    func setHideSystemDock(_ enabled: Bool) {
        layout.hideSystemDock = enabled
        save()
    }

    func setSystemDockOriginalAutohide(_ value: Bool?) {
        layout.systemDockOriginalAutohide = value
        save()
    }
}

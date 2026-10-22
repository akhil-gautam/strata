import Foundation
import Observation

/// An optional feature compiled into the app and switched on in
/// Settings → Extensions. While it is off its library categories are hidden
/// and its tiles leave the bar.
enum DockExtension: String, CaseIterable, Identifiable, Sendable {
    case aiUsage = "ai-usage"
    case scripts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .aiUsage: "AI Usage"
        case .scripts: "Script Tiles"
        }
    }

    var summary: String {
        switch self {
        case .aiUsage: "Claude Code and Codex limits, resets and token usage, read from this Mac."
        case .scripts: "Turn any script's output into a tile. Scripts live in ~/Library/Application Support/Strata/Scripts."
        }
    }

    var symbol: String {
        switch self {
        case .aiUsage: "sparkles"
        case .scripts: "terminal"
        }
    }

    /// The library sections the extension adds.
    var categories: [TileCategory] {
        switch self {
        case .aiUsage: [.aiUsage]
        case .scripts: [.scripts]
        }
    }

    fileprivate var defaultsKey: String { "extensions.\(rawValue).enabled" }
}

/// Which extensions are switched on, persisted in UserDefaults.
@MainActor
@Observable
final class ExtensionStore {
    static let shared = ExtensionStore()

    private(set) var enabled: Set<DockExtension>

    private init() {
        let defaults = UserDefaults.standard
        enabled = Set(DockExtension.allCases.filter { defaults.bool(forKey: $0.defaultsKey) })
    }

    func isEnabled(_ e: DockExtension) -> Bool {
        enabled.contains(e)
    }

    func setEnabled(_ e: DockExtension, _ on: Bool) {
        UserDefaults.standard.set(on, forKey: e.defaultsKey)
        guard on != enabled.contains(e) else { return }
        if on {
            enabled.insert(e)
        } else {
            enabled.remove(e)
            DockBarState.shared.pruneUnavailable()
        }
        if e == .scripts {
            ScriptStore.shared.setActive(on)
        }
    }

    /// First launch after this feature: turn an extension on if the stored
    /// bar already uses one of its tiles.
    func enableIfUsed(byBar ids: [String]) {
        let defaults = UserDefaults.standard
        for e in DockExtension.allCases where defaults.object(forKey: e.defaultsKey) == nil {
            let used = ids.contains { id in
                TileCatalog.category(ofID: id).map { e.categories.contains($0) } ?? false
            }
            if used {
                setEnabled(e, true)
            }
        }
    }
}

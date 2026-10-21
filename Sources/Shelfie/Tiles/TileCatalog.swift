import SwiftUI

/// Every tile the library offers, in library order.
@MainActor
enum TileCatalog {
    static let all: [TileSpec] = {
        let specs = AppsTiles.specs + BusinessTiles.specs + ClockTiles.specs
            + CalendarTiles.specs + SystemTiles.specs + ControlTiles.specs + UtilityTiles.specs + AIUsageTiles.specs
        // Library order follows the category order; within a category the
        // order the file declares is kept.
        return TileCategory.allCases.flatMap { category in
            specs.filter { $0.category == category }
        }
    }()

    private static let index: [String: TileSpec] = Dictionary(
        all.map { ($0.id, $0) },
        uniquingKeysWith: { first, _ in first }
    )

    /// Tiles whose extension (if any) is switched on, plus one tile per
    /// discovered script while Script Tiles is on.
    static var available: [TileSpec] {
        let scripts = ExtensionStore.shared.isEnabled(.scripts) ? ScriptTiles.librarySpecs : []
        return all.filter(isAvailable) + scripts
    }

    static func isAvailable(_ spec: TileSpec) -> Bool {
        spec.category.dockExtension.map { ExtensionStore.shared.isEnabled($0) } ?? true
    }

    /// Static tiles first; user-added apps and folders ("app:<bundle id>",
    /// "folder:<path>") and scripts ("script:<filename>") are built on
    /// demand. Tiles of a switched-off extension do not resolve.
    static func spec(id: String) -> TileSpec? {
        if let spec = index[id] ?? ScriptTiles.dynamicSpec(id: id) {
            return isAvailable(spec) ? spec : nil
        }
        return AppsTiles.dynamicSpec(id: id)
    }

    /// The section an id belongs to, whether or not its extension is on.
    static func category(ofID id: String) -> TileCategory? {
        (index[id] ?? ScriptTiles.dynamicSpec(id: id))?.category
    }

    /// The bar a fresh install starts with, as the video opens.
    static let defaultBar = ["time-date", "analog-minimal", "polar", "datafast"]
}

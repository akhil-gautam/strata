import SwiftUI

/// What the bar holds. Tiles and services read `tileIDs` to know whether a
/// tile is on the bar (e.g. Drink Water only reminds while it is).
@MainActor
@Observable
final class DockBarState {
    static let shared = DockBarState()

    /// The bar's tiles, in order. Every id resolves through
    /// `TileCatalog.spec(id:)`.
    private(set) var tileIDs: [String] = []

    /// True while the widget library is open: every bar tile shows its
    /// remove badge.
    var isEditing = false
    /// The tile whose settings popover is open; the bar rings it in the
    /// theme's accent (video f61–f76).
    var selectedID: String?

    @ObservationIgnored private var store: LayoutStore?

    private init() {}

    /// Loads the stored bar, dropping ids the catalogue no longer knows.
    func load(from store: LayoutStore) {
        self.store = store
        var seen = Set<String>()
        let valid = store.layout.barTiles.filter { id in
            TileCatalog.spec(id: id) != nil && seen.insert(id).inserted
        }
        tileIDs = valid.isEmpty ? TileCatalog.defaultBar : valid
        if tileIDs != store.layout.barTiles {
            store.setBarTiles(tileIDs)
        }
    }

    /// Drops tiles the catalogue no longer offers (an extension was switched
    /// off). Unlike `load`, never falls back to the default bar.
    func pruneUnavailable() {
        let kept = tileIDs.filter { TileCatalog.spec(id: $0) != nil }
        guard kept != tileIDs else { return }
        withAnimation(.spring(duration: 0.3, bounce: 0.1)) {
            tileIDs = kept
        }
        if selectedID.map({ !kept.contains($0) }) ?? false {
            selectedID = nil
        }
        store?.setBarTiles(tileIDs)
    }

    /// Appends a tile. Returns `false` when it is already on the bar or the
    /// catalogue cannot build it.
    @discardableResult
    func add(_ id: String) -> Bool {
        guard !tileIDs.contains(id), TileCatalog.spec(id: id) != nil else { return false }
        withAnimation(.spring(duration: 0.4, bounce: 0.25)) {
            tileIDs.append(id)
        }
        store?.setBarTiles(tileIDs)
        return true
    }

    func remove(_ id: String) {
        guard tileIDs.contains(id) else { return }
        withAnimation(.spring(duration: 0.3, bounce: 0.1)) {
            tileIDs.removeAll { $0 == id }
        }
        store?.setBarTiles(tileIDs)
    }

    /// Moves a tile to `index` in the new order (dragged along the bar).
    func move(_ id: String, to index: Int) {
        guard let from = tileIDs.firstIndex(of: id) else { return }
        let target = min(max(index, 0), tileIDs.count - 1)
        guard target != from else { return }
        withAnimation(.spring(duration: 0.35, bounce: 0.2)) {
            tileIDs.remove(at: from)
            tileIDs.insert(id, at: target)
        }
        store?.setBarTiles(tileIDs)
    }
}

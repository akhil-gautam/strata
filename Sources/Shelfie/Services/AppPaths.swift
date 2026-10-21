import Foundation

/// Where Shelfie keeps its files.
enum AppPaths {
    /// `~/Library/Application Support/Shelfie`: the bar layout, voice memos
    /// and script tiles. Shelfie was called DockDock; the first access moves
    /// the old `DockDock` folder here so nothing is left behind.
    static let support: URL = {
        let manager = FileManager.default
        let base = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? manager.temporaryDirectory
        let folder = base.appending(path: "Shelfie", directoryHint: .isDirectory)
        let legacy = base.appending(path: "DockDock", directoryHint: .isDirectory)
        if !manager.fileExists(atPath: folder.path), manager.fileExists(atPath: legacy.path) {
            do {
                try manager.moveItem(at: legacy, to: folder)
            } catch {
                NSLog("Shelfie: couldn't move the DockDock folder: %@", error.localizedDescription)
            }
        }
        return folder
    }()
}

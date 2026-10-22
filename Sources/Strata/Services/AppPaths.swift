import Foundation

/// Where Strata keeps its files.
enum AppPaths {
    /// `~/Library/Application Support/Strata`: the bar layout, voice memos
    /// and script tiles. Strata was called Shelfie, and DockDock before that;
    /// the first access moves the newest of those folders here so nothing is
    /// left behind.
    static let support: URL = {
        let manager = FileManager.default
        let base = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? manager.temporaryDirectory
        let folder = base.appending(path: "Strata", directoryHint: .isDirectory)
        guard !manager.fileExists(atPath: folder.path) else { return folder }
        for name in ["Shelfie", "DockDock"] {
            let legacy = base.appending(path: name, directoryHint: .isDirectory)
            guard manager.fileExists(atPath: legacy.path) else { continue }
            do {
                try manager.moveItem(at: legacy, to: folder)
            } catch {
                NSLog("Strata: couldn't move the %@ folder: %@", name, error.localizedDescription)
            }
            break
        }
        return folder
    }()
}

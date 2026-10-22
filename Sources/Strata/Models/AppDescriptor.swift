import Foundation
import Observation

/// Shared, observable copy of the installed applications so the picker does
/// not rescan the disk every time it opens.
@MainActor
@Observable
final class AppCatalogStore {
    static let shared = AppCatalogStore()

    private(set) var apps: [AppDescriptor] = []

    func update(_ apps: [AppDescriptor]) {
        self.apps = apps
    }
}

/// A launchable item in the strip: either an application bundle or a folder.
struct AppDescriptor: Sendable, Identifiable, Hashable {
    enum Kind: String, Sendable {
        case application
        case folder
    }

    let id: String
    let name: String
    let url: URL
    let kind: Kind

    init(id: String, name: String, url: URL, kind: Kind) {
        self.id = id
        self.name = name
        self.url = url
        self.kind = kind
    }
}

enum AppCatalog {
    static let applicationRoots = [
        "/Applications",
        "/System/Applications",
        "/System/Applications/Utilities",
        "/System/Library/CoreServices/Applications"
    ]

    /// Apps that live outside the scanned folders.
    static let extraApplicationPaths = [
        "/System/Library/CoreServices/Finder.app"
    ]

    static var homeRoots: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [home.appending(path: "Applications").path]
    }

    /// Scans the standard application locations. Runs off the main thread.
    static func scan() -> [AppDescriptor] {
        var found: [AppDescriptor] = []
        var seen = Set<String>()

        for path in extraApplicationPaths {
            let entry = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: entry.path) else { continue }
            let bundle = Bundle(url: entry)
            found.append(
                AppDescriptor(
                    id: bundle?.bundleIdentifier ?? entry.path,
                    name: bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
                        ?? entry.deletingPathExtension().lastPathComponent,
                    url: entry,
                    kind: .application
                )
            )
        }

        for root in applicationRoots + homeRoots {
            let directory = URL(fileURLWithPath: root, isDirectory: true)
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for entry in entries where entry.pathExtension == "app" {
                let identity = entry.standardizedFileURL.path
                guard !seen.contains(identity) else { continue }
                seen.insert(identity)

                let bundle = Bundle(url: entry)
                let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? entry.deletingPathExtension().lastPathComponent
                let identifier = bundle?.bundleIdentifier ?? identity

                found.append(
                    AppDescriptor(
                        id: identifier,
                        name: name,
                        url: entry,
                        kind: .application
                    )
                )
            }
        }

        return found.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Standard folders offered in the picker.
    static func standardFolders() -> [AppDescriptor] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let names = ["Desktop", "Documents", "Downloads", "Applications"]
        return names.compactMap { name in
            let url = home.appending(path: name)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return AppDescriptor(id: url.path, name: name, url: url, kind: .folder)
        }
    }
}

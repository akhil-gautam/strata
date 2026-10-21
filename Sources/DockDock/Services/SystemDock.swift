import Foundation

/// Control over the macOS Dock's own auto-hide setting.
///
/// The Dock reads `com.apple.dock` from the user's domain and picks the
/// change up when it restarts, which is why the Dock is relaunched after a
/// write.
enum SystemDock {
    static var isAutoHidden: Bool {
        UserDefaults(suiteName: "com.apple.dock")?.bool(forKey: "autohide") ?? false
    }

    static func setAutoHidden(_ hidden: Bool) {
        let defaults = UserDefaults(suiteName: "com.apple.dock")
        defaults?.set(hidden, forKey: "autohide")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["Dock"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}

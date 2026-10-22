import AppKit
import CoreWLAN
import Observation

/// A switch the user can flip from a tile.
@MainActor
struct SystemToggle: Identifiable {
    let id: String
    let isOn: () -> Bool
    let set: (Bool) -> Void
}

/// Quick system switches: Wi-Fi, appearance, focus and accessibility.
@MainActor
@Observable
final class ToggleService {
    static let shared = ToggleService()

    private(set) var states: [String: Bool] = [:]
    /// The default Wi-Fi interface. `CWInterface()` on its own is not bound to
    /// a device and always reads as off.
    private var interface: CWInterface? { CWWiFiClient.shared().interface() }

    var toggles: [SystemToggle] {
        [
            SystemToggle(
                id: "wifi",
                isOn: { self.interface?.powerOn() ?? false },
                set: { self.setWiFi($0) }
            ),
            SystemToggle(
                id: "darkmode",
                isOn: { Self.isDarkMode },
                set: { Self.setDarkMode($0) }
            ),
            SystemToggle(
                id: "dnd",
                isOn: { Self.isFocusOn },
                set: { Self.setFocusOn($0) }
            )
        ]
    }

    func refresh() {
        for toggle in toggles {
            states[toggle.id] = toggle.isOn()
        }
    }

    func toggle(_ toggle: SystemToggle) {
        let next = !(states[toggle.id] ?? toggle.isOn())
        toggle.set(next)
        states[toggle.id] = next
    }

    // MARK: - Wi-Fi

    private func setWiFi(_ enabled: Bool) {
        do {
            try interface?.setPower(enabled)
        } catch {
            NSLog("Strata: Wi-Fi toggle failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Appearance

    static var isDarkMode: Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }

    static func setDarkMode(_ enabled: Bool) {
        let script = """
        tell application "System Events"
            tell appearance preferences
                set dark mode to \(enabled)
            end tell
        end tell
        """
        runAppleScript(script)
    }

    // MARK: - Focus

    static var isFocusOn: Bool {
        boolHostPref("com.apple.notificationcenterui", "doNotDisturb")
    }

    static func setFocusOn(_ enabled: Bool) {
        setHostBoolPref("com.apple.notificationcenterui", "doNotDisturb", enabled)
    }

    // MARK: - Bluetooth

    /// IOBluetooth's controller power switch. The functions are exported by
    /// the framework but not declared in its headers, so they are looked up
    /// at runtime.
    nonisolated private static let bluetoothPower: (
        get: (@convention(c) () -> Int32)?,
        set: (@convention(c) (Int32) -> Void)?
    ) = {
        guard let handle = dlopen("/System/Library/Frameworks/IOBluetooth.framework/IOBluetooth", RTLD_LAZY) else {
            return (nil, nil)
        }
        let get = dlsym(handle, "IOBluetoothPreferenceGetControllerPowerState").map {
            unsafeBitCast($0, to: (@convention(c) () -> Int32).self)
        }
        let set = dlsym(handle, "IOBluetoothPreferenceSetControllerPowerState").map {
            unsafeBitCast($0, to: (@convention(c) (Int32) -> Void).self)
        }
        return (get, set)
    }()

    /// IOBluetooth blocks its caller until the Bluetooth privacy prompt is
    /// answered, so these never run on the main actor.
    nonisolated static func isBluetoothOn() async -> Bool {
        await Task.detached { bluetoothPower.get?() == 1 }.value
    }

    nonisolated static func setBluetoothOn(_ enabled: Bool) async {
        await Task.detached { bluetoothPower.set?(enabled ? 1 : 0) }.value
    }

    // MARK: - Session

    /// Locks the screen immediately, as Control Center's "Lock Screen" does.
    static func lockScreen() {
        if let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY),
           let symbol = dlsym(handle, "SACLockScreenImmediate") {
            let lock = unsafeBitCast(symbol, to: (@convention(c) () -> Int32).self)
            _ = lock()
            return
        }
        runTool("/usr/bin/pmset", ["displaysleepnow"])
    }

    /// Puts the Mac to sleep.
    static func sleepNow() {
        runTool("/usr/bin/pmset", ["sleepnow"])
    }

    private static func runTool(_ path: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    // MARK: - Preferences helpers

    private static func boolHostPref(_ domain: String, _ key: String) -> Bool {
        guard let value = CFPreferencesCopyAppValue(key as CFString, domain as CFString) else {
            return false
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        if let bool = value as? Bool {
            return bool
        }
        return false
    }

    private static func setHostBoolPref(_ domain: String, _ key: String, _ value: Bool) {
        CFPreferencesSetAppValue(
            key as CFString,
            value ? kCFBooleanTrue : kCFBooleanFalse,
            domain as CFString
        )
        CFPreferencesAppSynchronize(domain as CFString)
    }

    static func runAppleScript(_ script: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}

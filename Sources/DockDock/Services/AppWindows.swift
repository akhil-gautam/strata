import AppKit
import ApplicationServices

/// Accessibility access, which the window lists in app tile menus and the
/// Dock badges need.
enum AccessibilityAccess {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Asks macOS to show its "allow Accessibility" prompt when access is
    /// missing. Returns whether access is already granted.
    @discardableResult
    static func request() -> Bool {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// System Settings › Privacy & Security › Accessibility.
    @MainActor
    static func openSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}

/// A time limit shared by a run of Accessibility calls. Each call blocks
/// until the target process answers or the element's messaging timeout runs
/// out, so before every call the timeout is cut to what is left of the
/// budget.
struct AXDeadline {
    private let end: Date

    init(seconds: TimeInterval) {
        end = Date(timeIntervalSinceNow: seconds)
    }

    var isExpired: Bool { end.timeIntervalSinceNow <= 0 }

    /// Sets the element's timeout to the remaining time (at least 50 ms).
    /// Returns `false` once the budget is spent; the caller then stops.
    func arm(_ element: AXUIElement) -> Bool {
        let remaining = end.timeIntervalSinceNow
        guard remaining > 0 else { return false }
        AXUIElementSetMessagingTimeout(element, Float(max(remaining, 0.05)))
        return true
    }
}

/// Typed reads of Accessibility attributes, each within a deadline. Every
/// call blocks; never call these on the main actor.
enum AXRead {
    static func value(_ element: AXUIElement, _ attribute: String, _ deadline: AXDeadline) -> CFTypeRef? {
        guard deadline.arm(element) else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    static func string(_ element: AXUIElement, _ attribute: String, _ deadline: AXDeadline) -> String? {
        value(element, attribute, deadline) as? String
    }

    static func bool(_ element: AXUIElement, _ attribute: String, _ deadline: AXDeadline) -> Bool? {
        value(element, attribute, deadline) as? Bool
    }

    static func url(_ element: AXUIElement, _ attribute: String, _ deadline: AXDeadline) -> URL? {
        value(element, attribute, deadline) as? URL
    }

    static func elements(_ element: AXUIElement, _ attribute: String, _ deadline: AXDeadline) -> [AXUIElement]? {
        value(element, attribute, deadline) as? [AXUIElement]
    }
}

/// One window of a running app, as Accessibility reports it.
struct AppWindow: @unchecked Sendable {
    // `@unchecked`: AXUIElement is an immutable CF reference that the
    // Accessibility API accepts from any thread.
    let title: String
    let isMinimized: Bool
    fileprivate let element: AXUIElement
}

/// The windows of running apps, for the "Windows" section of an app tile's
/// menu.
///
/// The menu is built synchronously on the main actor, and an app that is
/// busy can take seconds to answer Accessibility, so the lists are read in
/// the background and cached per process. A list is refreshed when its app
/// launches, activates or deactivates (the moments its windows usually
/// change), when the pointer enters its tile, and each time its menu opens;
/// the menu shows the cached list and "Loading Windows…" until the first
/// read lands. Windows on other Spaces are not reported by Accessibility and
/// are not listed.
@MainActor
final class AppWindows {
    static let shared = AppWindows()

    enum Listing {
        /// No read has finished yet.
        case loading
        /// The last read timed out or failed.
        case unresponsive
        case windows([AppWindow])
    }

    /// Time one read or focus may take, in seconds.
    private nonisolated static let budget: TimeInterval = 1

    private var cache: [pid_t: Listing] = [:]
    private var inFlight: Set<pid_t> = []

    private init() {
        let center = NSWorkspace.shared.notificationCenter
        let refreshing = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didDeactivateApplicationNotification,
        ]
        for name in refreshing {
            _ = center.addObserver(forName: name, object: nil, queue: .main) { note in
                let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
                    .processIdentifier
                MainActor.assumeIsolated {
                    guard let pid else { return }
                    AppWindows.shared.refresh(pid: pid)
                }
            }
        }
        _ = center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
                .processIdentifier
            MainActor.assumeIsolated {
                guard let pid else { return }
                AppWindows.shared.cache[pid] = nil
            }
        }
    }

    /// The cached list for an app. Never blocks.
    func listing(for app: NSRunningApplication) -> Listing {
        cache[app.processIdentifier] ?? .loading
    }

    /// Re-reads an app's windows in the background, unless a read is
    /// already running.
    func refresh(_ app: NSRunningApplication) {
        refresh(pid: app.processIdentifier)
    }

    private func refresh(pid: pid_t) {
        guard AccessibilityAccess.isTrusted, !inFlight.contains(pid) else { return }
        inFlight.insert(pid)
        Task {
            let read = await Task.detached(priority: .userInitiated) {
                Self.read(pid: pid, deadline: AXDeadline(seconds: Self.budget))
            }.value
            inFlight.remove(pid)
            guard NSRunningApplication(processIdentifier: pid)?.isTerminated == false else {
                cache[pid] = nil
                return
            }
            cache[pid] = read.map(Listing.windows) ?? .unresponsive
        }
    }

    /// Brings one window to the front: restores it from the Dock if it is
    /// minimized, unhides the app, raises the window and activates the app.
    func focus(_ window: AppWindow, of app: NSRunningApplication) {
        if app.isHidden {
            app.unhide()
        }
        let pid = app.processIdentifier
        Task {
            await Task.detached(priority: .userInitiated) {
                Self.raise(window, pid: pid, deadline: AXDeadline(seconds: Self.budget))
            }.value
            app.activate(options: [])
            refresh(pid: pid)
        }
    }

    // MARK: Accessibility (off the main actor)

    /// The app's standard windows, front to back; `nil` when the app did not
    /// answer in time.
    private nonisolated static func read(pid: pid_t, deadline: AXDeadline) -> [AppWindow]? {
        let element = AXUIElementCreateApplication(pid)
        guard let windows = AXRead.elements(element, kAXWindowsAttribute, deadline) else { return nil }
        var result: [AppWindow] = []
        for window in windows {
            // Palettes, sheets and popovers are not windows the Dock lists.
            let subrole = AXRead.string(window, kAXSubroleAttribute, deadline)
            guard !deadline.isExpired else { return result.isEmpty ? nil : result }
            guard subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole else { continue }
            let title = AXRead.string(window, kAXTitleAttribute, deadline) ?? ""
            let isMinimized = AXRead.bool(window, kAXMinimizedAttribute, deadline) ?? false
            result.append(AppWindow(
                title: title.isEmpty ? "Untitled Window" : title,
                isMinimized: isMinimized,
                element: window
            ))
        }
        return result
    }

    private nonisolated static func raise(_ window: AppWindow, pid: pid_t, deadline: AXDeadline) {
        let element = window.element
        if window.isMinimized, deadline.arm(element) {
            AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        if deadline.arm(element) {
            AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        }
        if deadline.arm(element) {
            AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        }
        // Activation from a background app may be declined; asking the app
        // through Accessibility to become frontmost is not.
        let app = AXUIElementCreateApplication(pid)
        if deadline.arm(app) {
            AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        }
    }
}

import AppKit
import ApplicationServices
import SwiftUI

/// The notification badges the Dock shows on app icons ("3", "99+", "!"),
/// mirrored onto the bar's app tiles.
///
/// macOS does not publish other apps' badges; the Dock does, as the
/// `AXStatusLabel` of each item in its Accessibility tree. The store reads
/// that tree every two seconds, off the main actor, and only while all of
/// these hold: the feature is on (`dock.badges.enabled`, off by default),
/// Strata has Accessibility access, and the bar holds an app tile or the
/// Running Apps tile. Apps must stay in the Dock (pinned or running) for
/// their badge to appear there, and so here.
@MainActor
@Observable
final class DockBadges {
    static let shared = DockBadges()

    static let enabledKey = "dock.badges.enabled"

    private(set) var isEnabled: Bool
    /// Accessibility access, as of the last check.
    private(set) var isTrusted: Bool
    /// Badge text keyed by standardized app bundle path and by bundle id.
    private var labels: [String: String] = [:]

    @ObservationIgnored private var pollTask: Task<Void, Never>?

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        isTrusted = AccessibilityAccess.isTrusted
        // macOS posts this whenever the Accessibility list changes; the new
        // state is readable a moment later.
        _ = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                DockBadges.shared.refreshTrust()
            }
        }
        _ = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { DockBadges.shared.refreshTrust() }
        }
        // Deferred so that creating the store from inside a view's body does
        // not make that view depend on the bar's contents.
        Task { @MainActor in DockBadges.shared.barChanged() }
    }

    func setEnabled(_ on: Bool) {
        guard on != isEnabled else { return }
        isEnabled = on
        UserDefaults.standard.set(on, forKey: Self.enabledKey)
        update()
    }

    func refreshTrust() {
        let trusted = AccessibilityAccess.isTrusted
        guard trusted != isTrusted else { return }
        isTrusted = trusted
        update()
    }

    /// The badge for an app bundle, if the Dock shows one.
    func label(forApp url: URL) -> String? {
        guard !labels.isEmpty else { return nil }
        if let label = labels[url.standardizedFileURL.path] {
            return label
        }
        return Bundle(url: url)?.bundleIdentifier.flatMap { labels[$0] }
    }

    // MARK: Polling

    private var barNeedsBadges: Bool {
        DockBarState.shared.tileIDs.contains { $0.hasPrefix("app:") || $0 == "running-apps" }
    }

    private func barChanged() {
        withObservationTracking {
            _ = DockBarState.shared.tileIDs
        } onChange: {
            Task { @MainActor in DockBadges.shared.barChanged() }
        }
        update()
    }

    private func update() {
        let wanted = isEnabled && isTrusted && barNeedsBadges
        if wanted, pollTask == nil {
            pollTask = Task { [weak self] in await self?.poll() }
        } else if !wanted, let task = pollTask {
            task.cancel()
            pollTask = nil
            if !labels.isEmpty {
                labels = [:]
            }
        }
    }

    private func poll() async {
        while !Task.isCancelled {
            let read = await Task.detached(priority: .utility) { DockBadgeReader.read() }.value
            guard !Task.isCancelled else { return }
            if let read {
                if read != labels {
                    labels = read
                }
            } else {
                // The Dock did not answer, or access was revoked.
                refreshTrust()
            }
            try? await Task.sleep(for: .seconds(2))
        }
    }
}

/// Reads the badges out of the Dock's Accessibility tree: the Dock process →
/// its `AXList` → one `AXDockItem` per icon, whose `AXStatusLabel` is the
/// badge text.
private enum DockBadgeReader {
    static func read() -> [String: String]? {
        guard AXIsProcessTrusted(),
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        else { return nil }
        // The whole walk shares one budget, so a stalled Dock delays a poll
        // by at most this long.
        let deadline = AXDeadline(seconds: 1.5)
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        guard let children = AXRead.elements(app, kAXChildrenAttribute, deadline) else { return nil }
        var labels: [String: String] = [:]
        for list in children where AXRead.string(list, kAXRoleAttribute, deadline) == kAXListRole {
            for item in AXRead.elements(list, kAXChildrenAttribute, deadline) ?? [] {
                // App tiles are matched by the item's bundle URL; items
                // without one (the Trash, recent stacks) are skipped.
                guard let label = AXRead.string(item, "AXStatusLabel", deadline), !label.isEmpty,
                      let url = AXRead.url(item, kAXURLAttribute, deadline), url.isFileURL
                else { continue }
                labels[url.standardizedFileURL.path] = label
                if let id = Bundle(url: url)?.bundleIdentifier {
                    labels[id] = label
                }
            }
        }
        // A walk cut short would drop the badges it did not reach; keep the
        // previous ones instead.
        return deadline.isExpired ? nil : labels
    }
}

/// The red count drawn at an app icon's top-right corner. Counts above 99
/// read "99+"; other labels (the Dock's "!" or "•") are shown as they are.
struct DockBadgeView: View {
    let label: String

    private var text: String {
        if label.allSatisfy({ $0.isNumber || $0 == "," || $0 == "." }), let count = Int(label.filter(\.isNumber)) {
            return count > 99 ? "99+" : String(count)
        }
        return String(label.prefix(4))
    }

    var body: some View {
        Text(text)
            .font(.system(size: 9.5, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .monospacedDigit()
            .lineLimit(1)
            .padding(.horizontal, 4)
            .frame(minWidth: 15, minHeight: 15)
            .background { Capsule().fill(TilePalette.destructive) }
            .fixedSize()
    }
}

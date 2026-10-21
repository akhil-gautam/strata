import AppKit
import Combine
import SwiftUI

/// Dock badges and the Accessibility access they and the app tiles' window
/// lists need. Embedded in a grouped `Form`.
struct DockFeaturesSettingsSection: View {
    var body: some View {
        let badges = DockBadges.shared
        Section {
            Toggle(isOn: Binding(
                get: { badges.isEnabled },
                set: { badges.setEnabled($0) }
            )) {
                Text("Show notification badges on app tiles")
                Text("Copies the red counts the Dock shows (unread mail, messages) onto app tiles and Running Apps.")
            }
            LabeledContent {
                if !badges.isTrusted {
                    HStack(spacing: 8) {
                        Button("Grant Access…") {
                            _ = AccessibilityAccess.request()
                            badges.refreshTrust()
                        }
                        Button("Open System Settings") { AccessibilityAccess.openSettings() }
                    }
                }
            } label: {
                Text("Accessibility: \(badges.isTrusted ? "Granted" : "Not granted")")
                Text(badges.isTrusted
                    ? "App tiles list their windows and can show badges."
                    : "Needed for badges and for listing an app's windows in its tile menu.")
            }
            .task {
                // Access can be granted or revoked in System Settings while
                // this window is open.
                while !Task.isCancelled {
                    badges.refreshTrust()
                    do {
                        try await Task.sleep(for: .seconds(2))
                    } catch {
                        return
                    }
                }
            }
        } header: {
            Text("Dock")
        } footer: {
            Text("Badges are read from the Dock, so an app's badge appears only while it is in the Dock or running.")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            badges.refreshTrust()
        }
    }
}

import Foundation
import Observation
import ServiceManagement

/// Opens Strata at login through `SMAppService.mainApp`. The login item
/// belongs to macOS, which may hold it for approval in System Settings, so
/// the switch reads its state back rather than remembering it.
@MainActor
@Observable
final class LaunchAtLogin {
    static let shared = LaunchAtLogin()

    private(set) var status: SMAppService.Status = .notRegistered
    /// Why the last change failed, shown under the switch.
    private(set) var lastError: String?
    private var isChanging = false
    /// Bumped by every read and change; a read that started before the
    /// latest change, or before a newer read landed, is stale.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var mutationGeneration = 0
    @ObservationIgnored private var appliedGeneration = 0

    private init() {}

    var isEnabled: Bool { status == .enabled }
    /// Registered, but waiting for the user to allow it in System Settings.
    var requiresApproval: Bool { status == .requiresApproval }
    /// On, or asked for and waiting on approval.
    var isRequested: Bool { isEnabled || requiresApproval }

    /// Re-reads the login item; the user can change it in System Settings.
    func refresh() {
        guard !isChanging else { return }
        generation += 1
        let ticket = generation
        Task {
            let status = await Task.detached(priority: .utility) { SMAppService.mainApp.status }.value
            guard !self.isChanging, ticket > self.mutationGeneration, ticket > self.appliedGeneration else { return }
            self.appliedGeneration = ticket
            self.status = status
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard !isChanging, enabled != isRequested else { return }
        isChanging = true
        generation += 1
        let ticket = generation
        mutationGeneration = ticket
        lastError = nil
        Task {
            let outcome = await Task.detached(priority: .userInitiated) { () -> (SMAppService.Status, String?) in
                let service = SMAppService.mainApp
                do {
                    if enabled {
                        try service.register()
                    } else {
                        try service.unregister()
                    }
                    return (service.status, nil)
                } catch {
                    return (service.status, error.localizedDescription)
                }
            }.value
            self.appliedGeneration = ticket
            self.status = outcome.0
            self.lastError = outcome.1
            self.isChanging = false
            if let message = outcome.1 {
                NSLog("Strata: launch at login failed: %@", message)
            }
        }
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

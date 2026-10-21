import AppKit
import Observation
import UserNotifications

/// The Drink Water reminder: a repeating countdown whose water level drains
/// until the next reminder, then notifies and starts over.
///
/// It only runs while the "drink-water" tile is in the bar; the library
/// preview shows a full tile.
@MainActor
@Observable
final class IntervalTimer {
    static let shared = IntervalTimer()

    /// The bar tile that owns the reminder.
    static let tileID = "drink-water"
    static let minimumMinutes = 5
    static let maximumMinutes = 180
    /// The settings' preset chips.
    static let presets = [15, 20, 30, 45, 60]

    private(set) var intervalMinutes: Int
    private(set) var remaining: TimeInterval
    /// Whether the tile is in the bar and the countdown is running.
    private(set) var isActive = false
    private var nextReminder: Date

    private static let intervalKey = "drinkWater.intervalMinutes"
    private static let deadlineKey = "drinkWater.nextReminder"

    init() {
        let defaults = UserDefaults.standard
        let stored = defaults.integer(forKey: Self.intervalKey)
        let minutes = stored > 0 ? min(max(stored, Self.minimumMinutes), Self.maximumMinutes) : 30
        intervalMinutes = minutes
        remaining = TimeInterval(minutes * 60)
        let deadline = defaults.double(forKey: Self.deadlineKey)
        if deadline > 0 {
            nextReminder = Date(timeIntervalSinceReferenceDate: deadline)
        } else {
            // Saved straight away, so a relaunch keeps counting down instead
            // of starting a new interval.
            nextReminder = Date().addingTimeInterval(TimeInterval(minutes * 60))
            defaults.set(nextReminder.timeIntervalSinceReferenceDate, forKey: Self.deadlineKey)
        }
    }

    var total: TimeInterval { TimeInterval(intervalMinutes * 60) }

    /// Remaining fraction: the water level.
    var level: Double {
        total > 0 ? min(max(remaining / total, 0), 1) : 0
    }

    /// "18:42"; hours are folded into minutes ("90:00").
    var formatted: String {
        let seconds = Int(remaining.rounded(.up))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    /// "Every 30 min", "Every 1 hr".
    var intervalLabel: String { "Every \(Self.label(minutes: intervalMinutes))" }

    /// "30 min", "1 hr", "90 min".
    static func label(minutes: Int) -> String {
        minutes % 60 == 0 ? "\(minutes / 60) hr" : "\(minutes) min"
    }

    func setInterval(_ minutes: Int) {
        let clamped = min(max(minutes, Self.minimumMinutes), Self.maximumMinutes)
        intervalMinutes = clamped
        UserDefaults.standard.set(clamped, forKey: Self.intervalKey)
        restart()
    }

    /// Fills the water back up and counts a full interval from now.
    func restart() {
        nextReminder = Date().addingTimeInterval(total)
        UserDefaults.standard.set(nextReminder.timeIntervalSinceReferenceDate, forKey: Self.deadlineKey)
        remaining = total
    }

    /// Called once per second by the shared ticker.
    func tick() {
        guard DockBarState.shared.tileIDs.contains(Self.tileID) else {
            isActive = false
            remaining = total
            return
        }
        let now = Date()
        if !isActive {
            isActive = true
            requestNotificationAccess()
            // A deadline that passed while the app was closed (or the tile
            // was off the bar) starts a fresh interval instead of firing.
            if nextReminder <= now { restart() }
        }
        remaining = max(0, nextReminder.timeIntervalSince(now))
        if remaining == 0 {
            remind()
            restart()
        }
    }

    // MARK: - Reminder

    /// Notification Center needs a bundled app; a bare `swift run` binary
    /// has no bundle identity and would throw.
    private var canNotify: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    private func requestNotificationAccess() {
        guard canNotify else { return }
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        }
    }

    private func remind() {
        // Our own sound, so the reminder is heard even when the
        // notification's sound is turned off in System Settings.
        NSSound(named: "Glass")?.play()
        guard canNotify else { return }
        let next = Self.label(minutes: intervalMinutes)
        Task {
            let content = UNMutableNotificationContent()
            content.title = "Drink Water"
            content.body = "Time for a glass of water. Next reminder in \(next)."
            let request = UNNotificationRequest(
                identifier: "drink-water-\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            try? await UNUserNotificationCenter.current().add(request)
        }
    }
}

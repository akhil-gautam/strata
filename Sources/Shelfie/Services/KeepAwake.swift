import Foundation
import IOKit.pwr_mgt
import Observation

/// Keeps the Mac from going to sleep, like `caffeinate`, for a while or
/// until stopped. A power-management assertion does the work; macOS drops it
/// if Shelfie quits, so nothing outlives the app.
@MainActor
@Observable
final class KeepAwake {
    static let shared = KeepAwake()

    /// How long a start lasts.
    enum Span: Hashable, Sendable {
        case minutes(Int)
        case untilStopped

        /// The menu's and the chips' choices.
        static let presets: [Span] = [.minutes(15), .minutes(60), .minutes(120), .minutes(240), .untilStopped]

        var chipLabel: String {
            switch self {
            case let .minutes(minutes) where minutes < 60: "\(minutes)m"
            case let .minutes(minutes): "\(minutes / 60)h"
            case .untilStopped: "∞"
            }
        }

        var menuTitle: String {
            switch self {
            case let .minutes(minutes) where minutes < 60: "Keep Awake for \(minutes) Minutes"
            case .minutes(60): "Keep Awake for 1 Hour"
            case let .minutes(minutes): "Keep Awake for \(minutes / 60) Hours"
            case .untilStopped: "Keep Awake Until I Stop It"
            }
        }

        /// Stored as minutes; 0 means until stopped.
        fileprivate var storedMinutes: Int {
            if case let .minutes(minutes) = self { return minutes }
            return 0
        }

        fileprivate init(storedMinutes: Int) {
            self = storedMinutes > 0 ? .minutes(storedMinutes) : .untilStopped
        }
    }

    private(set) var isActive = false
    /// When it stops by itself; `nil` while it runs until stopped.
    private(set) var until: Date?

    /// What a tap on the tile starts. Setting `awake.defaultMinutes`.
    var defaultSpan: Span {
        didSet { UserDefaults.standard.set(defaultSpan.storedMinutes, forKey: Keys.defaultMinutes) }
    }

    /// Keep the screen lit as well, not only the Mac. Setting
    /// `awake.keepsDisplayOn`, on by default.
    var keepsDisplayOn: Bool {
        didSet {
            UserDefaults.standard.set(keepsDisplayOn, forKey: Keys.keepsDisplayOn)
            if isActive { assert() }
        }
    }

    @ObservationIgnored private var assertionID: IOPMAssertionID?
    @ObservationIgnored private var expiry: Task<Void, Never>?

    private enum Keys {
        static let defaultMinutes = "awake.defaultMinutes"
        static let keepsDisplayOn = "awake.keepsDisplayOn"
    }

    private init() {
        let defaults = UserDefaults.standard
        defaultSpan = Span(storedMinutes: defaults.object(forKey: Keys.defaultMinutes) as? Int ?? 60)
        keepsDisplayOn = defaults.object(forKey: Keys.keepsDisplayOn) as? Bool ?? true
    }

    func toggle() {
        isActive ? stop() : start(defaultSpan)
    }

    /// Starts, or restarts with a new span while already on.
    func start(_ span: Span) {
        guard assert() else { return }
        isActive = true
        expiry?.cancel()
        switch span {
        case let .minutes(minutes):
            let end = Date().addingTimeInterval(TimeInterval(minutes * 60))
            until = end
            expiry = Task { [weak self] in
                try? await Task.sleep(for: .seconds(max(end.timeIntervalSinceNow, 0)))
                guard !Task.isCancelled, let self, self.until == end else { return }
                self.stop()
                DockIsland.shared.show(IslandPeek(
                    symbol: "moon.zzz.fill",
                    tint: DockAccent.blue,
                    title: "Keep Awake ended",
                    subtitle: "Your Mac can sleep again."
                ))
            }
        case .untilStopped:
            until = nil
            expiry = nil
        }
    }

    func stop() {
        expiry?.cancel()
        expiry = nil
        release()
        isActive = false
        until = nil
    }

    /// Time left, or `nil` while it runs until stopped or is off.
    func remaining(at date: Date) -> TimeInterval? {
        guard isActive, let until else { return nil }
        return max(until.timeIntervalSince(date), 0)
    }

    /// "1:59:59", "4:05".
    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        let hours = total / 3600
        let minutes = total / 60 % 60
        let rest = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest)
            : String(format: "%d:%02d", minutes, rest)
    }

    /// Takes the assertion for the current display choice, replacing any
    /// earlier one. `false` if macOS refused it.
    @discardableResult
    private func assert() -> Bool {
        release()
        let type = keepsDisplayOn ? kIOPMAssertionTypePreventUserIdleDisplaySleep : kIOPMAssertionTypePreventUserIdleSystemSleep
        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            type as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Shelfie Keep Awake" as CFString,
            &id
        )
        guard result == kIOReturnSuccess else {
            NSLog("Shelfie: keep awake assertion failed: %d", result)
            return false
        }
        assertionID = id
        return true
    }

    private func release() {
        guard let assertionID else { return }
        IOPMAssertionRelease(assertionID)
        self.assertionID = nil
    }
}

import Foundation

/// The one clock behind every live tile.
///
/// A service refreshes only while a tile that reads it sits on the bar, or
/// while the widget library is open (its previews read every service). A bar
/// of clocks therefore costs nothing beyond the two timers below.
///
/// The heartbeat never awaits anything. Slow refreshes (AppleScript for Now
/// Playing and Mail, the weather request) run in their own task behind an
/// in-flight guard, so a hung `osascript` delays only its own service, never
/// the CPU or battery readings.
@MainActor
final class ServiceScheduler {
    static let shared = ServiceScheduler()

    /// Set by the app delegate from the library's visibility callback.
    var libraryVisible = false {
        didSet {
            // Fill the previews straight away instead of on the next beat.
            if libraryVisible, !oldValue { runDue() }
        }
    }

    enum Service: String, CaseIterable {
        case systemMetrics, battery, nowPlaying, audio, clipboard
        case weather, calendar, reminders, toggles, mail
    }

    /// The tiles whose views read each service. A tile added elsewhere that
    /// reads one of these services must be listed here, or it shows stale
    /// values until the library is opened.
    static let tiles: [Service: Set<String>] = [
        .systemMetrics: ["cpu", "ram", "cpu-chart", "ram-chart", "network", "download", "upload", "network-chart", "storage"],
        .battery: ["battery"],
        .nowPlaying: ["now-playing", "now-playing-mini", "now-playing-bar"],
        .audio: ["audio-output"],
        .clipboard: ["clipboard"],
        // Every weather tile, plus the calendar's 7-day strip and the clock's
        // Today tile, which show the current temperature too.
        .weather: Set(TileCatalog.all.filter { $0.category == .weather }.map(\.id)).union(["7-days", "today"]),
        .calendar: ["calendar-today", "next-event", "next-3-events", "today-agenda", "week", "7-days", "next-meeting", "meeting-center"],
        .reminders: ["next-reminder", "due-today", "reminders-agenda"],
        .toggles: ["quick-toggles"],
        .mail: ["mail-unread", "latest-mail"],
    ]

    private struct Job {
        enum Run {
            /// Quick synchronous reads, done on the beat itself.
            case inline(@MainActor () -> Void)
            /// Anything that awaits: started in its own task, never awaited.
            case task(@MainActor () async -> Void)
        }

        let service: Service
        let interval: Duration
        let run: Run
    }

    private let jobs: [Job] = [
        Job(service: .systemMetrics, interval: .seconds(1), run: .inline { SystemMetrics.shared.update() }),
        Job(service: .battery, interval: .seconds(1), run: .inline { BatteryInfo.shared.update() }),
        Job(service: .audio, interval: .seconds(1), run: .inline { AudioService.shared.refresh() }),
        Job(service: .clipboard, interval: .seconds(1), run: .inline { ClipboardHistory.shared.refresh() }),
        Job(service: .nowPlaying, interval: .seconds(1), run: .task { await NowPlayingService.shared.refresh() }),
        Job(service: .calendar, interval: .seconds(15), run: .inline { CalendarInfo.shared.refresh() }),
        Job(service: .reminders, interval: .seconds(15), run: .inline { RemindersInfo.shared.refresh() }),
        Job(service: .toggles, interval: .seconds(15), run: .inline { ToggleService.shared.refresh() }),
        Job(service: .weather, interval: .seconds(15), run: .task { await WeatherInfo.shared.refreshIfNeeded() }),
        Job(service: .mail, interval: .seconds(15), run: .task { await MailService.shared.refresh() }),
    ]

    private var lastStart: [Service: ContinuousClock.Instant] = [:]
    private var inFlight: Set<Service> = []
    private var heartbeat: Task<Void, Never>?

    /// Demand is recomputed only when the bar's tiles change.
    private var demandIDs: [String] = []
    private var barDemand: Set<Service> = []

    #if DEBUG
    /// Refreshes started per service since launch. With a bar of clocks only
    /// and the library closed this stays empty.
    private(set) var runCounts: [Service: Int] = [:]
    #endif

    private init() {}

    func start() {
        guard heartbeat == nil else { return }
        heartbeat = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.beat()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func beat() {
        // Always: they post notifications whether or not anyone is looking.
        FocusTimer.shared.tick()
        IntervalTimer.shared.tick()
        runDue()
    }

    /// Starts every needed service whose interval has passed and that is not
    /// still busy with its previous refresh.
    private func runDue() {
        let needed = demand()
        let now = ContinuousClock.now
        for job in jobs {
            guard needed.contains(job.service) else {
                // Refresh at once when a tile that needs it comes back.
                lastStart[job.service] = nil
                continue
            }
            if let last = lastStart[job.service], now - last < job.interval { continue }
            guard !inFlight.contains(job.service) else { continue }
            lastStart[job.service] = now
            #if DEBUG
            runCounts[job.service, default: 0] += 1
            #endif
            switch job.run {
            case .inline(let work):
                work()
            case .task(let work):
                let service = job.service
                inFlight.insert(service)
                Task { @MainActor [weak self] in
                    await work()
                    self?.inFlight.remove(service)
                }
            }
        }
    }

    private func demand() -> Set<Service> {
        if libraryVisible { return Set(Service.allCases) }
        let ids = DockBarState.shared.tileIDs
        if ids != demandIDs {
            demandIDs = ids
            let onBar = Set(ids)
            barDemand = Set(Service.allCases.filter { !(Self.tiles[$0] ?? []).isDisjoint(with: onBar) })
            #if DEBUG
            let names = barDemand.map(\.rawValue).sorted().joined(separator: ", ")
            NSLog("DockDock: live services: %@", names.isEmpty ? "none" : names)
            #endif
        }
        return barDemand
    }
}

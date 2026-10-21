import AppKit
import SwiftUI
import UserNotifications

/// The Clocks section of the library, in the order the video shows it.
@MainActor
enum ClockTiles {
    static let specs: [TileSpec] = [
        TileSpec(id: "time", title: "Time", category: .clocks) {
            AnyView(ClockTimeTile(showsSeconds: false))
        },
        TileSpec(id: "time-seconds", title: "Time + Seconds", category: .clocks) {
            AnyView(ClockTimeTile(showsSeconds: true))
        },
        TileSpec(
            id: "stopwatch",
            title: "Stopwatch",
            category: .clocks,
            menu: [.action("Reset Stopwatch") { ClockStopwatch.shared.reset() }]
        ) {
            AnyView(ClockStopwatchTile())
        },
        TileSpec(
            id: "timer",
            title: "Timer",
            category: .clocks,
            menu: [
                .action("Reset Timer") { ClockCountdown.shared.reset() },
                .customize("Set Duration…")
            ],
            settings: TileSettings(symbol: "timer") { AnyView(ClockTimerSettings()) }
        ) {
            AnyView(ClockTimerTile())
        },
        TileSpec(
            id: "pomodoro",
            title: "Pomodoro",
            category: .clocks,
            menu: [
                .action("Start Focus") { FocusTimer.shared.startFocus() },
                .customize()
            ],
            settings: TileSettings(symbol: "hourglass", title: "Focus") { AnyView(ClockPomodoroSettings()) }
        ) {
            AnyView(ClockPomodoroTile())
        },
        TileSpec(id: "time-date", title: "Time & Date", category: .clocks) {
            AnyView(ClockTimeDateTile())
        },
        TileSpec(id: "flip-clock", title: "Flip Clock", category: .clocks) {
            AnyView(ClockFlipTile())
        },
        TileSpec(
            id: "world-clock",
            title: "World Clock",
            category: .clocks,
            menu: [.customize("Choose Cities…")],
            settings: TileSettings(symbol: "globe") { AnyView(ClockCitiesSettings(target: .worldClock)) }
        ) {
            AnyView(ClockWorldClockTile())
        },
        TileSpec(
            id: "world-time",
            title: "World Time",
            category: .clocks,
            menu: [.customize("Choose City…")],
            settings: TileSettings(symbol: "globe") { AnyView(ClockCitiesSettings(target: .worldTime)) }
        ) {
            AnyView(ClockWorldTimeTile())
        },
        TileSpec(id: "today", title: "Today", category: .clocks) {
            AnyView(ClockTodayTile())
        },
        TileSpec(id: "date", title: "Date", category: .clocks) {
            AnyView(ClockDateTile())
        },
        TileSpec(id: "day-number", title: "Day Number", category: .clocks) {
            AnyView(ClockDayNumberTile())
        },
        TileSpec(id: "analog-minimal", title: "Analog Minimal", category: .clocks) {
            AnyView(ClockAnalogTile(style: .minimal))
        },
        TileSpec(id: "analog-classic", title: "Analog Classic", category: .clocks) {
            AnyView(ClockAnalogTile(style: .classic))
        },
        TileSpec(id: "analog-classic-dark", title: "Analog Classic Dark", category: .clocks) {
            AnyView(ClockAnalogTile(style: .classicDark))
        }
    ]
}

// MARK: - Alerts

/// The chime and banner for a timer reaching zero.
@MainActor
enum ClockAlert {
    static func post(title: String, body: String) {
        NSSound(named: "Glass")?.play()
        // Notification Center needs a bundled app; `swift run` has none.
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        Task {
            let center = UNUserNotificationCenter.current()
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            try? await center.add(request)
        }
    }
}

// MARK: - Models

/// The Stopwatch tile's state.
@MainActor
@Observable
private final class ClockStopwatch {
    static let shared = ClockStopwatch()

    private(set) var startedAt: Date?
    private(set) var accumulated: TimeInterval = 0

    var isRunning: Bool { startedAt != nil }
    var hasTime: Bool { isRunning || accumulated > 0 }

    func elapsed(at date: Date) -> TimeInterval {
        accumulated + (startedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }

    func toggle() {
        if let startedAt {
            accumulated += Date().timeIntervalSince(startedAt)
            self.startedAt = nil
        } else {
            startedAt = Date()
        }
    }

    func reset() {
        startedAt = nil
        accumulated = 0
    }
}

/// The Timer tile's countdown. Rings at zero even when the tile is hidden.
@MainActor
@Observable
private final class ClockCountdown {
    static let shared = ClockCountdown()

    private static let minutesKey = "clock.timer.minutes"

    var minutes: Int {
        didSet { UserDefaults.standard.set(minutes, forKey: Self.minutesKey) }
    }

    private(set) var endDate: Date?
    private(set) var pausedRemaining: TimeInterval?
    @ObservationIgnored private var alarm: Task<Void, Never>?

    init() {
        minutes = UserDefaults.standard.object(forKey: Self.minutesKey) as? Int ?? 5
    }

    var duration: TimeInterval { TimeInterval(minutes * 60) }
    var isRunning: Bool { endDate != nil }
    /// Running, or paused part-way.
    var isActive: Bool { endDate != nil || pausedRemaining != nil }

    func remaining(at date: Date) -> TimeInterval {
        if let endDate { return max(0, endDate.timeIntervalSince(date)) }
        return pausedRemaining ?? duration
    }

    func toggle() {
        if let endDate {
            alarm?.cancel()
            pausedRemaining = max(0, endDate.timeIntervalSinceNow)
            self.endDate = nil
        } else {
            let left = pausedRemaining ?? duration
            pausedRemaining = nil
            schedule(end: Date().addingTimeInterval(left))
        }
    }

    func reset() {
        alarm?.cancel()
        endDate = nil
        pausedRemaining = nil
    }

    private func schedule(end: Date) {
        endDate = end
        alarm?.cancel()
        alarm = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            self?.finish()
        }
    }

    private func finish() {
        endDate = nil
        pausedRemaining = nil
        ClockAlert.post(title: "Timer done", body: "Your \(ClockFormat.minutesPhrase(minutes)) timer has finished.")
    }
}

// MARK: - Formatting

@MainActor
private enum ClockFormat {
    private static var cache: [String: DateFormatter] = [:]

    static var uses24Hour: Bool {
        !(DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? "").contains("a")
    }

    /// "12:34" / "12:34:56", in the user's 12/24-hour preference without a
    /// day-period marker.
    static func clock(_ date: Date, seconds: Bool = false, zone: TimeZone = .current) -> String {
        let hour = uses24Hour ? "H" : "h"
        return string(date, format: seconds ? "\(hour):mm:ss" : "\(hour):mm", zone: zone)
    }

    static func string(_ date: Date, format: String, zone: TimeZone = .current) -> String {
        formatter(format, isTemplate: false, zone: zone).string(from: date)
    }

    static func string(_ date: Date, template: String, zone: TimeZone = .current) -> String {
        formatter(template, isTemplate: true, zone: zone).string(from: date)
    }

    /// "0:00.0", "12:05.3", "1:02:03.4".
    static func stopwatch(_ elapsed: TimeInterval) -> String {
        let tenths = Int((elapsed * 10).rounded(.down))
        let seconds = tenths / 10
        let (h, m, s) = (seconds / 3600, seconds / 60 % 60, seconds % 60)
        return h > 0
            ? String(format: "%d:%02d:%02d.%d", h, m, s, tenths % 10)
            : String(format: "%d:%02d.%d", m, s, tenths % 10)
    }

    /// "5:00", "25:00", "1:30:00". Rounds up so a fresh countdown reads its
    /// full length.
    static func countdown(_ remaining: TimeInterval) -> String {
        let seconds = Int(remaining.rounded(.up))
        let (h, m, s) = (seconds / 3600, seconds / 60 % 60, seconds % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// "-6h", "+7h", "+5:30h" relative to the local time zone.
    static func offset(of zone: TimeZone, at date: Date) -> String {
        let seconds = zone.secondsFromGMT(for: date) - TimeZone.current.secondsFromGMT(for: date)
        guard seconds != 0 else { return "0h" }
        let sign = seconds < 0 ? "-" : "+"
        let hours = abs(seconds) / 3600
        let minutes = abs(seconds) % 3600 / 60
        return minutes == 0 ? "\(sign)\(hours)h" : "\(sign)\(hours):\(String(format: "%02d", minutes))h"
    }

    static func minutesPhrase(_ minutes: Int) -> String {
        minutes == 1 ? "1-minute" : "\(minutes)-minute"
    }

    private static func formatter(_ pattern: String, isTemplate: Bool, zone: TimeZone) -> DateFormatter {
        let key = "\(isTemplate ? "t" : "f")|\(pattern)|\(zone.identifier)|\(Locale.current.identifier)"
        if let cached = cache[key] { return cached }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = zone
        if isTemplate {
            formatter.setLocalizedDateFormatFromTemplate(pattern)
        } else {
            formatter.dateFormat = pattern
        }
        cache[key] = formatter
        return formatter
    }
}

/// A time zone shown as its city: "America/Argentina/Buenos_Aires" reads
/// "Buenos Aires" in "America · Argentina".
private struct ClockCity: Identifiable {
    let identifier: String
    let zone: TimeZone
    let name: String
    let region: String
    /// "Pacific Time", for searching by zone name.
    let zoneName: String
    var id: String { identifier }

    init(_ identifier: String) {
        self.identifier = identifier
        zone = TimeZone(identifier: identifier) ?? .gmt
        let parts = identifier.split(separator: "/").map { $0.replacingOccurrences(of: "_", with: " ") }
        name = parts.last ?? identifier
        region = parts.dropLast().joined(separator: " · ")
        zoneName = zone.localizedName(for: .generic, locale: .current) ?? ""
    }

    /// The name in at most `limit` characters: whole when it fits, then
    /// "B. Aires", then initials ("LA", "HCM"), then cut short.
    func label(fitting limit: Int) -> String {
        guard name.count > limit else { return name }
        let words = name.split(separator: " ")
        if words.count == 2, let first = words.first?.first, let last = words.last {
            let short = "\(first). \(last)"
            if short.count <= limit { return short }
        }
        if words.count >= 2 {
            return String(words.compactMap(\.first)).uppercased()
        }
        return String(name.prefix(max(1, limit - 1))) + "…"
    }

    /// Every zone the system knows, by city name.
    static let all: [ClockCity] = TimeZone.knownTimeZoneIdentifiers
        .map(ClockCity.init)
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
}

/// The cities the World Clock (three) and World Time (one) tiles show.
@MainActor
@Observable
private final class ClockWorldCities {
    static let shared = ClockWorldCities()

    private static let citiesKey = "clock.worldCities"
    private static let timeKey = "clock.worldTime"
    private static let defaultCities = ["America/New_York", "Europe/London", "Asia/Tokyo"]

    /// World Clock's three zone identifiers, top to bottom.
    var cities: [String] {
        didSet { UserDefaults.standard.set(cities, forKey: Self.citiesKey) }
    }

    /// World Time's zone identifier.
    var single: String {
        didSet { UserDefaults.standard.set(single, forKey: Self.timeKey) }
    }

    init() {
        let defaults = UserDefaults.standard
        let stored = defaults.stringArray(forKey: Self.citiesKey) ?? []
        cities = stored.count == 3 && stored.allSatisfy { TimeZone(identifier: $0) != nil }
            ? stored
            : Self.defaultCities
        single = defaults.string(forKey: Self.timeKey).flatMap { TimeZone(identifier: $0)?.identifier }
            ?? Self.defaultCities[0]
    }
}

/// Ticks on whole seconds.
private let clockEverySecond = PeriodicTimelineSchedule(
    from: Calendar.current.startOfDay(for: Date()),
    by: 1
)

@MainActor
private enum ClockTint {
    static var focus: Color { TilePalette.destructive }
    static let shortBreak = DockAccent.green
    static let longBreak = DockAccent.blue
    static let sessions = DockAccent.orange

    static func phase(_ phase: FocusTimer.Phase) -> Color {
        switch phase {
        case .focus: focus
        case .shortBreak: shortBreak
        case .longBreak: longBreak
        }
    }
}

// MARK: - Shared pieces

/// A countdown's remaining time traced around the tile's edge, starting at
/// the top-left corner and running down the left side.
private struct ClockProgressBorder: View {
    var fraction: Double
    var tint: Color

    var body: some View {
        ClockBorderPath(radius: TileMetrics.corner - 3)
            .trim(from: 0, to: min(max(fraction, 0), 1))
            .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .padding(3)
            .animation(.linear(duration: 1), value: fraction)
            .allowsHitTesting(false)
    }
}

private struct ClockBorderPath: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.width / 2, rect.height / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        path.addArc(
            tangent1End: CGPoint(x: rect.minX, y: rect.minY),
            tangent2End: CGPoint(x: rect.minX, y: rect.minY + r),
            radius: r
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r))
        path.addArc(
            tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
            tangent2End: CGPoint(x: rect.minX + r, y: rect.maxY),
            radius: r
        )
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.maxY))
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
            tangent2End: CGPoint(x: rect.maxX, y: rect.maxY - r),
            radius: r
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + r))
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
            tangent2End: CGPoint(x: rect.maxX - r, y: rect.minY),
            radius: r
        )
        path.closeSubpath()
        return path
    }
}

/// The small grey round button beside a play button (skip, reset).
private struct ClockSecondaryButton: View {
    var systemName: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(TilePalette.ink.opacity(0.65))
                .frame(width: 22, height: 22)
                .background { Circle().fill(TilePalette.ink.opacity(0.12)) }
        }
        .buttonStyle(.plain)
    }
}

private struct ClockValueText: View {
    var text: String
    var size: CGFloat
    var weight: Font.Weight = .semibold

    var body: some View {
        Text(text)
            .font(.tileValue(size, weight: weight))
            .foregroundStyle(TilePalette.ink)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}

private struct ClockCaptionText: View {
    var text: String
    var size: CGFloat = 10.5

    var body: some View {
        Text(text)
            .font(.tileCaption(size))
            .foregroundStyle(TilePalette.caption)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

// MARK: - Digital

/// "12:34" and "12:34:56".
private struct ClockTimeTile: View {
    var showsSeconds: Bool

    var body: some View {
        DockTile(width: showsSeconds ? 124 : 96) {
            if showsSeconds {
                TimelineView(clockEverySecond) { context in
                    ClockValueText(text: ClockFormat.clock(context.date, seconds: true), size: 21)
                }
            } else {
                TimelineView(.everyMinute) { context in
                    ClockValueText(text: ClockFormat.clock(context.date), size: 25)
                }
            }
        }
    }
}

/// "12:25" over "Mon, Jun 22" — the bar's first tile.
private struct ClockTimeDateTile: View {
    @Environment(\.tileContext) private var tileContext

    var body: some View {
        // The library lays the two lines out flush left; the bar centres them.
        let alignment: HorizontalAlignment = tileContext == .library ? .leading : .center
        DockTile(width: 98) {
            TimelineView(.everyMinute) { context in
                VStack(alignment: alignment, spacing: 0) {
                    ClockValueText(text: ClockFormat.clock(context.date), size: 24)
                    ClockCaptionText(text: ClockFormat.string(context.date, template: "EEEMMMd"), size: 10.5)
                }
                .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
                .padding(.leading, tileContext == .library ? 2 : 0)
            }
        }
    }
}

/// "Sunday" over "June 14".
private struct ClockDateTile: View {
    var body: some View {
        DockTile(width: 92, inset: 8) {
            TimelineView(.everyMinute) { context in
                VStack(alignment: .leading, spacing: 1) {
                    Text(ClockFormat.string(context.date, format: "cccc"))
                        .font(.tileCaption(10, weight: .semibold))
                        .foregroundStyle(TilePalette.ink.opacity(0.5))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    ClockValueText(text: ClockFormat.string(context.date, template: "MMMMd"), size: 18)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// "14" over "Jun".
private struct ClockDayNumberTile: View {
    var body: some View {
        DockTile(width: 63) {
            TimelineView(.everyMinute) { context in
                VStack(spacing: -1) {
                    ClockValueText(text: ClockFormat.string(context.date, format: "d"), size: 28, weight: .bold)
                    ClockCaptionText(text: ClockFormat.string(context.date, format: "LLL"), size: 10.5)
                }
            }
        }
    }
}

/// "Jun 24, Saturday" over "14:32 ☁ 21°".
private struct ClockTodayTile: View {
    private let weather = WeatherInfo.shared

    var body: some View {
        DockTile(width: 133) {
            TimelineView(.everyMinute) { context in
                VStack(spacing: 3) {
                    Text(
                        ClockFormat.string(context.date, template: "MMMd")
                            + ", "
                            + ClockFormat.string(context.date, format: "cccc")
                    )
                    .font(.tileValue(12, weight: .semibold))
                    .foregroundStyle(TilePalette.ink.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    HStack(spacing: 5) {
                        Text(ClockFormat.clock(context.date))
                            .monospacedDigit()
                        if let temperature = weather.temperature {
                            Image(systemName: weather.symbol)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(TilePalette.ink.opacity(0.7))
                            Text("\(Int(temperature.rounded()))°")
                        }
                    }
                    .font(.tileValue(12, weight: .semibold))
                    .foregroundStyle(TilePalette.ink.opacity(0.92))
                    .lineLimit(1)
                }
            }
        }
    }
}

/// Three cities, their local time and their offset from here.
private struct ClockWorldClockTile: View {
    var body: some View {
        let cities = ClockWorldCities.shared.cities.map(ClockCity.init)
        DockTile(width: 185, inset: 12) {
            TimelineView(.everyMinute) { context in
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(cities.indices, id: \.self) { index in
                        let city = cities[index]
                        HStack(spacing: 0) {
                            Text(city.label(fitting: 12))
                            Text(ClockFormat.clock(context.date, zone: city.zone))
                                .monospacedDigit()
                                .padding(.leading, 6)
                            Spacer(minLength: 6)
                            Text(ClockFormat.offset(of: city.zone, at: context.date))
                                .font(.tileCaption(9, weight: .semibold))
                                .foregroundStyle(TilePalette.ink.opacity(0.45))
                        }
                        .font(.tileText(10.5, weight: .bold))
                        .foregroundStyle(TilePalette.ink.opacity(0.95))
                        .lineLimit(1)
                        .help(city.name)
                    }
                }
            }
        }
    }
}

/// "6:26" over "New York -6h".
private struct ClockWorldTimeTile: View {
    var body: some View {
        let city = ClockCity(ClockWorldCities.shared.single)
        DockTile(width: 110) {
            TimelineView(.everyMinute) { context in
                VStack(spacing: 0) {
                    ClockValueText(text: ClockFormat.clock(context.date, zone: city.zone), size: 25)
                    ClockCaptionText(
                        text: "\(city.label(fitting: 10)) \(ClockFormat.offset(of: city.zone, at: context.date))",
                        size: 10.5
                    )
                }
            }
        }
        .help(city.name)
    }
}

// MARK: - Flip clock

/// Four flip cards, "1 2 3 4".
private struct ClockFlipTile: View {
    var body: some View {
        DockTile(width: 145, fill: AnyShapeStyle(Color.clear), inset: 0) {
            TimelineView(.everyMinute) { context in
                let digits = Array(ClockFormat.string(context.date, format: ClockFormat.uses24Hour ? "HHmm" : "hhmm"))
                HStack(spacing: 4) {
                    ForEach(0..<4, id: \.self) { index in
                        ClockFlipCard(digit: index < digits.count ? digits[index] : "0")
                    }
                }
            }
        }
    }
}

private struct ClockFlipCard: View {
    var digit: Character

    /// 7 pt on the 12 pt Midnight tile; follows the theme's corners.
    private var cardCorner: CGFloat { TileMetrics.corner * 7 / 12 }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                TilePalette.ink.opacity(0.15)
                TilePalette.ink.opacity(0.1)
            }
            Text(String(digit))
                .font(.tileValue(34, weight: .bold))
                .foregroundStyle(TilePalette.ink.opacity(0.94))
                .id(digit)
                .transition(.asymmetric(
                    insertion: .modifier(active: ClockFlipModifier(angle: -90), identity: ClockFlipModifier(angle: 0)),
                    removal: .modifier(active: ClockFlipModifier(angle: 90), identity: ClockFlipModifier(angle: 0))
                ))
            // The hinge between the two halves.
            VStack(spacing: 0) {
                TilePalette.tileFill.frame(height: 1)
                TilePalette.ink.opacity(0.1).frame(height: 0.5)
            }
        }
        .frame(width: 33, height: TileMetrics.height)
        .background(TilePalette.tileSurface)
        .clipShape(RoundedRectangle(cornerRadius: cardCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cardCorner, style: .continuous)
                .strokeBorder(TilePalette.tileBorder, lineWidth: AppearanceStore.shared.theme.tileBorderWidth)
        }
        .animation(.easeInOut(duration: 0.45), value: digit)
    }
}

private struct ClockFlipModifier: ViewModifier {
    var angle: Double

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(angle), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
            .opacity(abs(angle) < 90 ? 1 : 0)
    }
}

// MARK: - Analog

private enum ClockAnalogStyle {
    case minimal, classic, classicDark
}

private struct ClockAnalogTile: View {
    var style: ClockAnalogStyle
    @Environment(\.tileContext) private var tileContext

    /// In the library the tile is as wide as its name underneath.
    private var width: CGFloat {
        guard tileContext == .library else { return 62 }
        switch style {
        case .minimal: return 75
        case .classic: return 71
        case .classicDark: return 96
        }
    }

    var body: some View {
        DockTile(width: width, inset: 0) {
            TimelineView(clockEverySecond) { context in
                ClockAnalogDial(date: context.date, style: style)
                    .frame(width: 44, height: 44)
            }
        }
    }
}

private struct ClockAnalogDial: View {
    var date: Date
    var style: ClockAnalogStyle

    private static let secondRed = Color(red: 0.92, green: 0.2, blue: 0.2)

    var body: some View {
        let ink = TilePalette.ink
        let accent = TilePalette.focus
        Canvas { context, size in
            let radius = min(size.width, size.height) / 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let faceRect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)

            let parts = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
            let second = Double(parts.second ?? 0)
            let minute = Double(parts.minute ?? 0) + second / 60
            let hour = Double((parts.hour ?? 0) % 12) + minute / 60
            let hourAngle = hour / 12 * 2 * .pi
            let minuteAngle = minute / 60 * 2 * .pi
            let secondAngle = second / 60 * 2 * .pi

            func hand(_ angle: Double, length: CGFloat, tail: CGFloat, width: CGFloat, color: Color) {
                var path = Path()
                path.move(to: Self.point(center, angle: angle, distance: -tail))
                path.addLine(to: Self.point(center, angle: angle, distance: length))
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
            }

            func dot(_ diameter: CGFloat, _ color: Color) {
                let rect = CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
                context.fill(Path(ellipseIn: rect), with: .color(color))
            }

            func ticks(_ color: Color) {
                for index in 0..<60 {
                    let angle = Double(index) / 60 * 2 * .pi
                    let isQuarter = index % 15 == 0
                    let isHour = index % 5 == 0
                    let length: CGFloat = isQuarter ? radius * 0.2 : isHour ? radius * 0.13 : radius * 0.06
                    let width: CGFloat = isQuarter ? 2.2 : isHour ? 1.4 : 0.6
                    let outer = radius * 0.9
                    var path = Path()
                    path.move(to: Self.point(center, angle: angle, distance: outer - length))
                    path.addLine(to: Self.point(center, angle: angle, distance: outer))
                    context.stroke(path, with: .color(isHour ? color : color.opacity(0.55)), style: StrokeStyle(lineWidth: width))
                }
            }

            switch style {
            case .minimal:
                context.stroke(Path(ellipseIn: faceRect.insetBy(dx: 0.5, dy: 0.5)), with: .color(ink.opacity(0.13)), lineWidth: 1)
                hand(hourAngle, length: radius * 0.48, tail: 0, width: 2, color: ink.opacity(0.95))
                hand(minuteAngle, length: radius * 0.78, tail: 0, width: 1.4, color: ink.opacity(0.95))
                hand(secondAngle, length: radius * 0.72, tail: radius * 0.12, width: 1.3, color: accent)
                dot(3, ink)

            case .classic:
                context.fill(Path(ellipseIn: faceRect), with: .color(Color(white: 0.97)))
                ticks(Color(white: 0.1))
                hand(hourAngle, length: radius * 0.5, tail: radius * 0.08, width: 2.6, color: Color(white: 0.08))
                hand(minuteAngle, length: radius * 0.76, tail: radius * 0.08, width: 1.9, color: Color(white: 0.08))
                hand(secondAngle, length: radius * 0.8, tail: radius * 0.18, width: 0.9, color: Self.secondRed)
                dot(3.4, Self.secondRed)

            case .classicDark:
                context.fill(Path(ellipseIn: faceRect), with: .color(Color(white: 0.04)))
                context.stroke(Path(ellipseIn: faceRect.insetBy(dx: 0.5, dy: 0.5)), with: .color(.white.opacity(0.18)), lineWidth: 1)
                ticks(.white.opacity(0.92))
                hand(hourAngle, length: radius * 0.5, tail: radius * 0.08, width: 2.4, color: .white)
                hand(minuteAngle, length: radius * 0.76, tail: radius * 0.08, width: 1.7, color: .white)
                hand(secondAngle, length: radius * 0.8, tail: radius * 0.18, width: 0.9, color: Self.secondRed)
                dot(3.4, Self.secondRed)
            }
        }
    }

    /// A point `distance` from `center` along `angle`, measured clockwise
    /// from twelve o'clock.
    nonisolated private static func point(_ center: CGPoint, angle: Double, distance: CGFloat) -> CGPoint {
        CGPoint(x: center.x + sin(angle) * distance, y: center.y - cos(angle) * distance)
    }
}

// MARK: - Stopwatch

/// "0:00.0" and a play button.
private struct ClockStopwatchTile: View {
    private let stopwatch = ClockStopwatch.shared

    var body: some View {
        DockTile(width: 158) {
            HStack(spacing: 6) {
                TimelineView(.animation(minimumInterval: 0.1, paused: !stopwatch.isRunning)) { context in
                    ClockValueText(text: ClockFormat.stopwatch(stopwatch.elapsed(at: context.date)), size: 21)
                }
                Spacer(minLength: 0)
                if !stopwatch.isRunning, stopwatch.hasTime {
                    ClockSecondaryButton(systemName: "arrow.counterclockwise") { stopwatch.reset() }
                }
                TilePlayButton(systemName: stopwatch.isRunning ? "pause.fill" : "play.fill", diameter: 29) {
                    stopwatch.toggle()
                }
            }
        }
    }
}

// MARK: - Timer

/// "5:00" and a play button; the remaining time runs round the edge.
private struct ClockTimerTile: View {
    private let countdown = ClockCountdown.shared

    var body: some View {
        DockTile(width: 140, inset: 0) {
            TimelineView(.animation(minimumInterval: 0.25, paused: !countdown.isRunning)) { context in
                let remaining = countdown.remaining(at: context.date)
                HStack(spacing: 6) {
                    ClockValueText(text: ClockFormat.countdown(remaining), size: 21)
                    Spacer(minLength: 0)
                    if !countdown.isRunning, countdown.isActive {
                        ClockSecondaryButton(systemName: "arrow.counterclockwise") { countdown.reset() }
                    }
                    TilePlayButton(systemName: countdown.isRunning ? "pause.fill" : "play.fill", diameter: 29) {
                        countdown.toggle()
                    }
                }
                .padding(.horizontal, TileMetrics.inset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    if countdown.isActive, countdown.duration > 0 {
                        ClockProgressBorder(fraction: remaining / countdown.duration, tint: TilePalette.focus)
                    }
                }
            }
        }
    }
}

private struct ClockTimerSettings: View {
    @Bindable private var countdown = ClockCountdown.shared

    var body: some View {
        VStack(spacing: 8) {
            ClockSettingsHero(
                value: ClockFormat.countdown(countdown.duration),
                detail: countdown.isActive
                    ? "New length applies to the next countdown"
                    : "Rings with a sound and a notification"
            )
            TileChoiceChips(
                options: [1, 5, 10, 15, 30].map { (label: "\($0) min", value: $0) },
                selection: $countdown.minutes
            )
            TileStepperCard(
                symbol: "timer",
                title: "Duration",
                tint: TilePalette.focus,
                value: $countdown.minutes,
                range: 1...180
            )
        }
        .frame(width: 288)
    }
}

// MARK: - Pomodoro

/// The bar's "Focus" tile: phase and session over the remaining time, with
/// skip and play/pause.
private struct ClockPomodoroTile: View {
    private let timer = FocusTimer.shared

    var body: some View {
        let tint = ClockTint.phase(timer.phase)
        let isActive = !(timer.phase == .focus && timer.isIdle)
        let showsCount = isActive || timer.completedSessions > 0
        DockTile(width: 152, inset: 0) {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 4) {
                        Text(timer.phase.title)
                            .foregroundStyle(TilePalette.ink.opacity(0.62))
                        if showsCount {
                            Text("\(timer.sessionNumber)/\(timer.sessionsUntilLongBreak)")
                                .foregroundStyle(TilePalette.ink.opacity(0.35))
                                .monospacedDigit()
                        }
                    }
                    .font(.tileCaption(9.5, weight: .semibold))
                    .lineLimit(1)
                    ClockValueText(text: ClockFormat.countdown(timer.remaining), size: 20)
                }
                Spacer(minLength: 0)
                if isActive {
                    ClockSecondaryButton(systemName: "forward.fill") { timer.skip() }
                }
                TilePlayButton(
                    systemName: timer.isRunning ? "pause.fill" : "play.fill",
                    tint: timer.isRunning ? tint : TilePalette.focus,
                    diameter: 29
                ) {
                    timer.toggle()
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if isActive, timer.sessionLength > 0 {
                    ClockProgressBorder(fraction: timer.remaining / timer.sessionLength, tint: tint)
                }
            }
        }
    }
}

private struct ClockPomodoroSettings: View {
    @Bindable private var timer = FocusTimer.shared

    var body: some View {
        VStack(spacing: 8) {
            ClockSettingsHero(
                value: ClockFormat.countdown(TimeInterval(timer.focusMinutes * 60)),
                detail: "\(timer.shortBreakMinutes) min break · \(timer.longBreakMinutes) min long · "
                    + "every \(timer.sessionsUntilLongBreak) sessions"
            )
            TileStepperCard(
                symbol: "brain.head.profile",
                title: "Focus",
                tint: ClockTint.focus,
                value: $timer.focusMinutes,
                range: 1...180
            )
            TileStepperCard(
                symbol: "cup.and.saucer.fill",
                title: "Short break",
                tint: ClockTint.shortBreak,
                value: $timer.shortBreakMinutes,
                range: 1...60
            )
            TileStepperCard(
                symbol: "leaf.fill",
                title: "Long break",
                tint: ClockTint.longBreak,
                value: $timer.longBreakMinutes,
                range: 1...120
            )
            TileStepperCard(
                symbol: "repeat",
                title: "Sessions until long break",
                tint: ClockTint.sessions,
                value: $timer.sessionsUntilLongBreak,
                range: 1...12,
                unit: "focus sessions"
            )
        }
        .frame(width: 288)
    }
}

/// The summary card at the top of a timer's settings.
private struct ClockSettingsHero: View {
    var value: String
    var detail: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.tileValue(28, weight: .semibold))
                .foregroundStyle(TilePalette.ink)
                .monospacedDigit()
            Text(detail)
                .font(.tileText(9.5, weight: .medium))
                .foregroundStyle(TilePalette.ink.opacity(0.45))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 10)
        .background {
            RoundedRectangle(cornerRadius: TileMetrics.corner, style: .continuous)
                .fill(TilePalette.ink.opacity(0.045))
        }
        .overlay {
            RoundedRectangle(cornerRadius: TileMetrics.corner, style: .continuous)
                .strokeBorder(TilePalette.ink.opacity(0.05), lineWidth: 1)
        }
    }
}

// MARK: - World clock settings

/// Picks the World Clock's three cities or World Time's one: choose a slot,
/// then a city from every time zone the system knows.
private struct ClockCitiesSettings: View {
    enum Target {
        case worldClock
        case worldTime
    }

    let target: Target
    @State private var slot = 0
    @State private var query = ""

    private var chosen: [String] {
        let store = ClockWorldCities.shared
        return target == .worldClock ? store.cities : [store.single]
    }

    var body: some View {
        let chosen = self.chosen
        let current = chosen.indices.contains(slot) ? chosen[slot] : chosen.first ?? ""
        VStack(alignment: .leading, spacing: 8) {
            if chosen.count > 1 {
                HStack(spacing: 4) {
                    ForEach(chosen.indices, id: \.self) { index in
                        slotButton(index, city: ClockCity(chosen[index]))
                    }
                }
            }
            searchField
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(matches) { city in
                        row(city, isChosen: city.identifier == current, isElsewhere: chosen.contains(city.identifier))
                    }
                }
            }
            .frame(height: 220)
        }
        .frame(width: 288)
    }

    private var matches: [ClockCity] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return ClockCity.all }
        return ClockCity.all.filter {
            $0.name.localizedStandardContains(text)
                || $0.region.localizedStandardContains(text)
                || $0.zoneName.localizedStandardContains(text)
        }
    }

    private func choose(_ city: ClockCity) {
        let store = ClockWorldCities.shared
        switch target {
        case .worldClock:
            guard store.cities.indices.contains(slot) else { return }
            store.cities[slot] = city.identifier
        case .worldTime:
            store.single = city.identifier
        }
    }

    private func slotButton(_ index: Int, city: ClockCity) -> some View {
        let isSelected = index == slot
        return Button {
            slot = index
        } label: {
            Text(city.label(fitting: 12))
                .font(.tileText(9.5, weight: .semibold))
                .foregroundStyle(isSelected ? TilePalette.ink : TilePalette.ink.opacity(0.6))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background {
                    Capsule().fill(isSelected ? TilePalette.focus.opacity(0.35) : TilePalette.ink.opacity(0.045))
                }
                .overlay {
                    Capsule().strokeBorder(isSelected ? TilePalette.focus.opacity(0.7) : .clear, lineWidth: 1)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Replace \(city.name)")
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(TilePalette.ink.opacity(0.45))
            TextField(
                "",
                text: $query,
                prompt: Text("Search cities or time zones").foregroundStyle(TilePalette.ink.opacity(0.32))
            )
            .textFieldStyle(.plain)
            .font(.tileText(11.5))
            .foregroundStyle(TilePalette.ink)
            .onSubmit {
                if let first = matches.first { choose(first) }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: min(8, TileMetrics.corner), style: .continuous)
                .fill(TilePalette.ink.opacity(0.07))
        }
    }

    private func row(_ city: ClockCity, isChosen: Bool, isElsewhere: Bool) -> some View {
        Button {
            choose(city)
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(city.name)
                        .font(.tileText(11.5, weight: .medium))
                        .foregroundStyle(TilePalette.ink.opacity(0.9))
                        .lineLimit(1)
                    Text([city.region, city.zoneName].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.tileText(9, weight: .medium))
                        .foregroundStyle(TilePalette.ink.opacity(0.4))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(ClockFormat.offset(of: city.zone, at: Date()))
                    .font(.tileCaption(9, weight: .semibold))
                    .foregroundStyle(TilePalette.ink.opacity(0.45))
                    .monospacedDigit()
                Image(systemName: isChosen ? "checkmark.circle.fill" : isElsewhere ? "circle.inset.filled" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(isChosen ? TilePalette.focus : TilePalette.ink.opacity(0.25))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                RoundedRectangle(cornerRadius: min(8, TileMetrics.corner), style: .continuous)
                    .fill(TilePalette.ink.opacity(isChosen ? 0.07 : 0.0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

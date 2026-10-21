import AppKit
import Darwin
import EventKit
import Foundation
import IOKit.ps
import Observation

// MARK: - System metrics

/// CPU, memory, disk and network sampled once per second.
@MainActor
@Observable
final class SystemMetrics {
    static let shared = SystemMetrics()

    var cpuPercent: Double = 0
    var cpuHistory: [Double] = []
    var memoryUsed: Double = 0
    var memoryTotal: Double = 0
    var memoryHistory: [Double] = []
    var diskFree: Double = 0
    var diskTotal: Double = 0
    var networkDown: Double = 0
    var networkUp: Double = 0
    var networkHistory: [Double] = []
    var networkUpHistory: [Double] = []

    private var lastNetworkBytes: (down: UInt64, up: UInt64, date: Date)?
    private var lastCPUTicks: (busy: Double, total: Double)?

    var memoryFraction: Double {
        memoryTotal > 0 ? memoryUsed / memoryTotal : 0
    }

    func update() {
        // Load over the last sample, not the average since boot.
        let ticks = MetricsSampler.cpuTicks()
        if let last = lastCPUTicks, ticks.total > last.total {
            cpuPercent = min(max((ticks.busy - last.busy) / (ticks.total - last.total), 0), 1)
        } else if ticks.total > 0 {
            cpuPercent = ticks.busy / ticks.total
        }
        lastCPUTicks = ticks
        cpuHistory.append(cpuPercent)
        if cpuHistory.count > 60 {
            cpuHistory.removeFirst(cpuHistory.count - 60)
        }

        let memory = MetricsSampler.memory()
        memoryUsed = memory.used
        memoryTotal = memory.total
        memoryHistory.append(memoryFraction)
        if memoryHistory.count > 60 {
            memoryHistory.removeFirst(memoryHistory.count - 60)
        }

        let disk = MetricsSampler.disk(at: URL(fileURLWithPath: NSHomeDirectory()))
        diskFree = disk.free
        diskTotal = disk.total

        let bytes = MetricsSampler.networkBytes()
        let now = Date()
        if let last = lastNetworkBytes {
            let elapsed = now.timeIntervalSince(last.date)
            if elapsed > 0 {
                networkDown = Double(bytes.down &- last.down) / elapsed
                networkUp = Double(bytes.up &- last.up) / elapsed
            }
            networkHistory.append(networkDown)
            if networkHistory.count > 60 {
                networkHistory.removeFirst(networkHistory.count - 60)
            }
            networkUpHistory.append(networkUp)
            if networkUpHistory.count > 60 {
                networkUpHistory.removeFirst(networkUpHistory.count - 60)
            }
        }
        lastNetworkBytes = (bytes.down, bytes.up, now)
    }
}

enum MetricsSampler {
    /// Cumulative busy and total CPU ticks since boot; callers diff two
    /// samples to get the current load.
    static func cpuTicks() -> (busy: Double, total: Double) {
        var loadInfo = host_cpu_load_info()
        // host_cpu_load_info_data_t is four integer_t wide.
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &loadInfo) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, 0) }

        // cpu_ticks is (user, system, idle, nice).
        let ticks = loadInfo.cpu_ticks
        let total = Double(ticks.0) + Double(ticks.1) + Double(ticks.2) + Double(ticks.3)
        return (total - Double(ticks.2), total)
    }

    static func memory() -> (used: Double, total: Double) {
        var stats = vm_statistics64()
        // The count must match vm_statistics64_data_t, not the larger
        // host-side vm_statistics64 struct.
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, 0) }

        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        // Activity Monitor's "Memory Used": app memory + wired + compressed.
        // Inactive pages are reclaimable cache and not counted.
        let appPages = Double(stats.internal_page_count) - Double(stats.purgeable_count)
        let pages = max(appPages, 0) + Double(stats.wire_count) + Double(stats.compressor_page_count)
        let used = pages * Double(pageSize)
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        return (used, total)
    }

    static func disk(at url: URL) -> (free: Double, total: Double) {
        var info = statfs()
        guard statfs(url.path, &info) == 0 else { return (0, 0) }
        let blockSize = Double(info.f_bsize)
        let total = Double(info.f_blocks) * blockSize
        // Finder's "available" counts purgeable space that statfs leaves out.
        if let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let available = values.volumeAvailableCapacityForImportantUsage, available > 0 {
            return (Double(available), total)
        }
        return (Double(info.f_bavail) * blockSize, total)
    }

    static func networkBytes() -> (down: UInt64, up: UInt64) {
        var down: UInt64 = 0
        var up: UInt64 = 0
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return (0, 0) }
        defer { freeifaddrs(pointer) }

        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = entry.pointee
            guard let data = interface.ifa_data?.assumingMemoryBound(to: if_data.self) else { continue }
            down += UInt64(data.pointee.ifi_ibytes)
            up += UInt64(data.pointee.ifi_obytes)
        }
        return (down, up)
    }
}

// MARK: - Battery

@MainActor
@Observable
final class BatteryInfo {
    static let shared = BatteryInfo()

    var percent: Double = 0
    var isCharging = false
    var timeRemainingMinutes: Int?
    var isPresent = true

    func update() {
        guard
            let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else {
            isPresent = false
            return
        }
        isPresent = !list.isEmpty
        for source in list {
            // The dictionary is owned by the blob: borrow, never release.
            guard let unmanaged = IOPSGetPowerSourceDescription(blob, source) else { continue }
            let description = unmanaged.takeUnretainedValue() as? [String: Any] ?? [:]
            percent = (description[kIOPSCurrentCapacityKey] as? Double) ?? percent
            isCharging = (description[kIOPSIsChargingKey] as? Bool) ?? isCharging
            if let remaining = description[kIOPSTimeToEmptyKey] as? Int, remaining > 0 {
                timeRemainingMinutes = remaining
            } else if let remaining = description[kIOPSTimeToFullChargeKey] as? Int, remaining > 0 {
                timeRemainingMinutes = remaining
            } else {
                timeRemainingMinutes = nil
            }
        }
    }
}

// MARK: - Weather

/// Where the weather tiles report from and in which units. Shared by every
/// weather tile; changing either fetches again straight away.
@MainActor
@Observable
final class WeatherSettings {
    static let shared = WeatherSettings()

    enum Units: String, CaseIterable, Identifiable {
        /// °F and mph where the system uses US measurements, otherwise °C and km/h.
        case automatic
        case celsius
        case fahrenheit

        var id: String { rawValue }

        var title: String {
            switch self {
            case .automatic: "Auto (\(Self.systemIsImperial ? "°F" : "°C"))"
            case .celsius: "Celsius"
            case .fahrenheit: "Fahrenheit"
            }
        }

        /// Fahrenheit, mph and inches rather than Celsius, km/h and millimetres.
        var isImperial: Bool {
            switch self {
            case .automatic: Self.systemIsImperial
            case .celsius: false
            case .fahrenheit: true
            }
        }

        private static var systemIsImperial: Bool { Locale.current.measurementSystem == .us }
    }

    private static let locationKey = "weather.location"
    private static let unitsKey = "weather.units"

    /// The chosen place; `nil` guesses it from the system time zone.
    var location: WeatherService.Place? {
        didSet {
            guard location != oldValue else { return }
            if let location, let data = try? JSONEncoder().encode(location) {
                UserDefaults.standard.set(data, forKey: Self.locationKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.locationKey)
            }
            refetch()
        }
    }

    var units: Units {
        didSet {
            guard units != oldValue else { return }
            UserDefaults.standard.set(units.rawValue, forKey: Self.unitsKey)
            refetch()
        }
    }

    init() {
        let defaults = UserDefaults.standard
        location = defaults.data(forKey: Self.locationKey)
            .flatMap { try? JSONDecoder().decode(WeatherService.Place.self, from: $0) }
        units = defaults.string(forKey: Self.unitsKey).flatMap(Units.init(rawValue:)) ?? .automatic
    }

    private func refetch() {
        Task { await WeatherInfo.shared.refreshIfNeeded(force: true) }
    }
}

@MainActor
@Observable
final class WeatherInfo {
    static let shared = WeatherInfo()

    struct Hour: Identifiable {
        let id = UUID()
        let date: Date
        let temperature: Double
        let symbol: String
    }

    struct Day: Identifiable {
        let id = UUID()
        let date: Date
        let high: Double
        let low: Double
        let symbol: String
        /// Total precipitation over the day, in millimetres or, when
        /// `isImperial`, inches.
        let precipitation: Double
    }

    var temperature: Double?
    var condition: String = ""
    var symbol: String = "cloud.sun"
    var isDay = true
    var hours: [Hour] = []
    var placeName: String = ""
    var failed = false
    /// Today first, then the following days.
    var days: [Day] = []
    /// Current wind, in km/h (mph when `isImperial`); direction in degrees
    /// the wind comes from.
    var windSpeed: Double?
    var windDirection: Double?
    var windGusts: Double?
    var sunrise: Date?
    var sunset: Date?
    /// Whether the readings above are in °F, mph and inches.
    var isImperial = false
    /// The forecast place's time zone; hours, days and sun times read in it.
    var timeZone: TimeZone = .current

    /// A good forecast is kept this long.
    private static let freshness: TimeInterval = 600
    /// A failed fetch is tried again after this long.
    private static let retryDelay: TimeInterval = 60

    private var lastFetch: Date?
    private var isFetching = false
    /// A forced refresh arrived mid-fetch (the place or units changed): the
    /// answer in flight is stale, so fetch again once it lands.
    private var needsRefetch = false

    func refreshIfNeeded(force: Bool = false) async {
        if !force, let lastFetch, Date().timeIntervalSince(lastFetch) < Self.freshness {
            return
        }
        // Several tiles ask at once when they appear; one request serves all.
        guard !isFetching else {
            if force { needsRefetch = true }
            return
        }
        isFetching = true
        defer { isFetching = false }

        repeat {
            needsRefetch = false
            await fetch()
        } while needsRefetch
    }

    private func fetch() async {
        let settings = WeatherSettings.shared
        let place = settings.location
        let imperial = settings.units.isImperial
        do {
            let location: WeatherService.Location
            if let place {
                location = WeatherService.Location(place)
            } else {
                location = try await WeatherService.resolveLocation()
            }
            let forecast = try await WeatherService.fetch(location: location, imperial: imperial)
            guard !needsRefetch else { return }
            placeName = location.name
            temperature = forecast.temperature
            condition = forecast.condition
            symbol = forecast.symbol
            isDay = forecast.isDay
            hours = forecast.hours
            days = forecast.days
            windSpeed = forecast.windSpeed
            windDirection = forecast.windDirection
            windGusts = forecast.windGusts
            sunrise = forecast.sunrise
            sunset = forecast.sunset
            isImperial = imperial
            timeZone = forecast.timeZone
            failed = false
            lastFetch = Date()
        } catch {
            guard !needsRefetch else { return }
            failed = true
            // Back-date the fetch so the next try comes after `retryDelay`
            // rather than the full freshness window.
            lastFetch = Date(timeIntervalSinceNow: Self.retryDelay - Self.freshness)
            NSLog("DockDock: weather fetch failed: \(error.localizedDescription)")
        }
    }
}

enum WeatherService {
    struct Location: Sendable {
        let name: String
        let latitude: Double
        let longitude: Double
        /// The place's IANA time zone, when known; otherwise the forecast
        /// works it out from the coordinates.
        var timeZone: String? = nil

        init(name: String, latitude: Double, longitude: Double, timeZone: String? = nil) {
            self.name = name
            self.latitude = latitude
            self.longitude = longitude
            self.timeZone = timeZone
        }

        init(_ place: Place) {
            self.init(
                name: [place.name, place.country].compactMap { $0 }.joined(separator: ", "),
                latitude: place.latitude,
                longitude: place.longitude,
                timeZone: place.timezone
            )
        }
    }

    /// A geocoding match the user can pick, persisted as `weather.location`.
    struct Place: Codable, Hashable, Identifiable, Sendable {
        let name: String
        let country: String?
        /// State or province, to tell apart places with the same name.
        var region: String? = nil
        let latitude: Double
        let longitude: Double
        let timezone: String?

        var id: String { "\(latitude),\(longitude)" }

        /// "Portland, Oregon, United States".
        var detail: String {
            [region, country].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        }
    }

    struct Forecast: Sendable {
        let temperature: Double?
        let condition: String
        let symbol: String
        let isDay: Bool
        let hours: [WeatherInfo.Hour]
        let days: [WeatherInfo.Day]
        let windSpeed: Double?
        let windDirection: Double?
        let windGusts: Double?
        let sunrise: Date?
        let sunset: Date?
        let timeZone: TimeZone
    }

    /// Resolve the user's place from the system time zone, falling back to a
    /// fixed coordinate. No permission prompt, no API key.
    static func resolveLocation() async throws -> Location {
        let identifier = TimeZone.current.identifier
        let city = identifier.split(separator: "/").last
            .map { $0.replacingOccurrences(of: "_", with: " ") } ?? "London"
        if let first = try? await search(city).first {
            return Location(first)
        }
        return Location(name: "London", latitude: 51.5072, longitude: -0.1276)
    }

    /// Up to five places matching `name`, best first.
    static func search(_ name: String) async throws -> [Place] {
        let data = try await fetchJSON(url: geocodingURL(for: name))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let results = object?["results"] as? [[String: Any]] ?? []
        return results.compactMap { result in
            guard let name = result["name"] as? String,
                  let latitude = result["latitude"] as? Double,
                  let longitude = result["longitude"] as? Double else { return nil }
            return Place(
                name: name,
                country: result["country"] as? String,
                region: result["admin1"] as? String,
                latitude: latitude,
                longitude: longitude,
                timezone: result["timezone"] as? String
            )
        }
    }

    static func fetch(location: Location, imperial: Bool) async throws -> Forecast {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(location.latitude)),
            URLQueryItem(name: "longitude", value: String(location.longitude)),
            URLQueryItem(
                name: "current",
                value: "temperature_2m,is_day,weather_code,wind_speed_10m,wind_direction_10m,wind_gusts_10m"
            ),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code"),
            URLQueryItem(
                name: "daily",
                value: "weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,precipitation_sum"
            ),
            URLQueryItem(name: "forecast_days", value: "5"),
            URLQueryItem(name: "timezone", value: location.timeZone ?? "auto"),
            URLQueryItem(name: "temperature_unit", value: imperial ? "fahrenheit" : "celsius"),
            URLQueryItem(name: "wind_speed_unit", value: imperial ? "mph" : "kmh"),
            URLQueryItem(name: "precipitation_unit", value: imperial ? "inch" : "mm")
        ]
        let data = try await fetchJSON(url: components.url!)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        // Times come as the place's wall clock; read them in its zone.
        let zone = (object?["timezone"] as? String).flatMap(TimeZone.init(identifier:))
            ?? (object?["utc_offset_seconds"] as? Int).flatMap(TimeZone.init(secondsFromGMT:))
            ?? .current
        let current = object?["current"] as? [String: Any]
        let hourly = object?["hourly"] as? [String: Any]
        let codes = hourly?["weather_code"] as? [Int] ?? []
        let temperatures = hourly?["temperature_2m"] as? [Double] ?? []
        let times = hourly?["time"] as? [String] ?? []
        let now = Date()

        let hourFormatter = DateFormatter()
        hourFormatter.locale = Locale(identifier: "en_US_POSIX")
        hourFormatter.timeZone = zone
        hourFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm"

        var hours: [WeatherInfo.Hour] = []
        for (index, timeString) in times.enumerated() {
            guard index < temperatures.count, index < codes.count else { break }
            guard let date = hourFormatter.date(from: timeString) else { continue }
            guard date >= now.addingTimeInterval(-1800) else { continue }
            hours.append(
                WeatherInfo.Hour(
                    date: date,
                    temperature: temperatures[index],
                    symbol: symbol(for: codes[index])
                )
            )
            if hours.count == 8 { break }
        }

        let daily = object?["daily"] as? [String: Any]
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.timeZone = zone
        dayFormatter.dateFormat = "yyyy-MM-dd"
        let dayTimes = daily?["time"] as? [String] ?? []
        let dayCodes = daily?["weather_code"] as? [Int] ?? []
        let highs = daily?["temperature_2m_max"] as? [Double] ?? []
        let lows = daily?["temperature_2m_min"] as? [Double] ?? []
        let precipitation = daily?["precipitation_sum"] as? [Double] ?? []
        var days: [WeatherInfo.Day] = []
        for (index, timeString) in dayTimes.enumerated() {
            guard index < dayCodes.count, index < highs.count, index < lows.count else { break }
            guard let date = dayFormatter.date(from: timeString) else { continue }
            days.append(
                WeatherInfo.Day(
                    date: date,
                    high: highs[index],
                    low: lows[index],
                    symbol: symbol(for: dayCodes[index]),
                    precipitation: index < precipitation.count ? precipitation[index] : 0
                )
            )
        }
        let sunrises = daily?["sunrise"] as? [String] ?? []
        let sunsets = daily?["sunset"] as? [String] ?? []

        let code = current?["weather_code"] as? Int ?? 2
        return Forecast(
            temperature: current?["temperature_2m"] as? Double,
            condition: condition(for: code),
            symbol: symbol(for: code),
            isDay: (current?["is_day"] as? Int ?? 1) == 1,
            hours: hours,
            days: days,
            windSpeed: current?["wind_speed_10m"] as? Double,
            windDirection: current?["wind_direction_10m"] as? Double,
            windGusts: current?["wind_gusts_10m"] as? Double,
            sunrise: sunrises.first.flatMap { hourFormatter.date(from: $0) },
            sunset: sunsets.first.flatMap { hourFormatter.date(from: $0) },
            timeZone: zone
        )
    }

    static func condition(for code: Int) -> String {
        switch code {
        case 0: "Clear sky"
        case 1: "Mainly clear"
        case 2: "Partly cloudy"
        case 3: "Overcast"
        case 45, 48: "Fog"
        case 51, 53, 55, 56, 57: "Drizzle"
        case 61, 63, 65, 66, 67: "Rain"
        case 71, 73, 75, 77: "Snow"
        case 80, 81, 82: "Rain showers"
        case 85, 86: "Snow showers"
        case 95, 96, 99: "Thunderstorm"
        default: "Unknown"
        }
    }

    static func symbol(for code: Int) -> String {
        switch code {
        case 0: "sun.max"
        case 1, 2: "cloud.sun"
        case 3: "cloud"
        case 45, 48: "cloud.fog"
        case 51, 53, 55, 56, 57: "cloud.drizzle"
        case 61, 63, 65, 66, 67: "cloud.rain"
        case 71, 73, 75, 77: "cloud.snow"
        case 80, 81, 82: "cloud.rain"
        case 85, 86: "cloud.snow"
        case 95, 96, 99: "cloud.bolt.rain"
        default: "cloud"
        }
    }

    private static func geocodingURL(for name: String) -> URL {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "count", value: "5")
        ]
        return components.url!
    }

    private static func fetchJSON(url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

// MARK: - Calendar

@MainActor
@Observable
final class CalendarInfo {
    static let shared = CalendarInfo()

    struct Event: Identifiable {
        let id: String
        let title: String
        let start: Date
        let end: Date
        let isAllDay: Bool
        /// The colour of the event's calendar.
        var color: CGColor? = nil
        var location: String? = nil
        /// A video-call link found in the event's URL, location or notes.
        var meetingURL: URL? = nil
    }

    var events: [Event] = []
    /// Every event from the start of this week through the next two weeks,
    /// sorted by start. Feeds the week strip, next-event and meeting tiles.
    var nearbyEvents: [Event] = []
    var hasAccess = EKEventStore.authorizationStatus(for: .event) == .fullAccess
    var requestedAccess = false

    private let store = EKEventStore()

    init() {
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { CalendarInfo.shared.refresh() }
        }
    }

    func requestAccess() async {
        guard !requestedAccess else { return }
        requestedAccess = true
        hasAccess = (try? await store.requestFullAccessToEvents()) ?? false
        if hasAccess { refresh() }
    }

    func refresh() {
        guard hasAccess else { return }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: start)?.start ?? start
        let windowEnd = calendar.date(byAdding: .day, value: 15, to: start)!
        let predicate = store.predicateForEvents(withStart: weekStart, end: windowEnd, calendars: nil)
        nearbyEvents = store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .map(Self.event(from:))
        events = Array(
            nearbyEvents
                .filter { $0.start < end && $0.end > start }
                .prefix(6)
        )
    }

    private static func event(from event: EKEvent) -> Event {
        Event(
            id: event.eventIdentifier ?? UUID().uuidString,
            title: event.title ?? "Untitled",
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            color: event.calendar?.cgColor,
            location: event.location,
            meetingURL: meetingLink(url: event.url, location: event.location, notes: event.notes)
        )
    }

    private static let meetingHosts = [
        "meet.google.com", "zoom.us", "zoom.com", "teams.microsoft.com", "teams.live.com",
        "webex.com", "facetime.apple.com", "whereby.com", "around.co", "meet.jit.si", "chime.aws"
    ]

    /// The first video-call link in an event, if any.
    private static func meetingLink(url: URL?, location: String?, notes: String?) -> URL? {
        func isMeeting(_ link: URL) -> Bool {
            guard let host = link.host?.lowercased() else { return false }
            return meetingHosts.contains { host == $0 || host.hasSuffix("." + $0) }
        }
        if let url, isMeeting(url) { return url }
        let text = [location, notes].compactMap { $0 }.joined(separator: "\n")
        if !text.isEmpty,
           let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let range = NSRange(text.startIndex..., in: text)
            for match in detector.matches(in: text, range: range) {
                if let link = match.url, isMeeting(link) { return link }
            }
        }
        return nil
    }
}

// MARK: - Reminders

@MainActor
@Observable
final class RemindersInfo {
    static let shared = RemindersInfo()

    struct Reminder: Identifiable {
        let id: String
        let title: String
        let isCompleted: Bool
        let dueDate: Date?
        /// Whether the due date carries a time of day, not just a day.
        var hasDueTime = false
        var listTitle: String = ""
        var listColor: CGColor? = nil
        /// EventKit priority: 0 none, 1–4 high, 5 medium, 6–9 low.
        var priority: Int = 0
    }

    /// Incomplete reminders: dated ones first, soonest due first.
    var reminders: [Reminder] = []
    var hasAccess = EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
    var requestedAccess = false

    private let store = EKEventStore()

    init() {
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { RemindersInfo.shared.refresh() }
        }
    }

    func requestAccess() async {
        guard !requestedAccess else { return }
        requestedAccess = true
        hasAccess = (try? await store.requestFullAccessToReminders()) ?? false
        if hasAccess { refresh() }
    }

    func refresh() {
        guard hasAccess else { return }
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: nil,
            calendars: nil
        )
        Task { [weak self, store] in
            // EventKit calls back on its own queue; the mapping must not
            // inherit the main actor, and EKReminder is not Sendable.
            let fetched: [Reminder] = await withCheckedContinuation { continuation in
                store.fetchReminders(matching: predicate) { @Sendable reminders in
                    continuation.resume(returning: Self.sorted(reminders ?? []))
                }
            }
            self?.reminders = fetched
        }
    }

    /// Soonest-due first, undated ones after, at most 40.
    nonisolated private static func sorted(_ reminders: [EKReminder]) -> [Reminder] {
        let mapped = reminders.map { reminder in
            let components = reminder.dueDateComponents
            return Reminder(
                id: reminder.calendarItemIdentifier,
                title: reminder.title ?? "Untitled",
                isCompleted: reminder.isCompleted,
                dueDate: components.flatMap { Calendar.current.date(from: $0) },
                hasDueTime: components?.hour != nil,
                listTitle: reminder.calendar?.title ?? "",
                listColor: reminder.calendar?.cgColor,
                priority: reminder.priority
            )
        }
        let sorted = mapped.enumerated().sorted { lhs, rhs in
            switch (lhs.element.dueDate, rhs.element.dueDate) {
            case let (left?, right?): left < right
            case (.some, nil): true
            case (nil, .some): false
            case (nil, nil): lhs.offset < rhs.offset
            }
        }
        return sorted.prefix(40).map(\.element)
    }

    /// Marks a reminder as done in the Reminders database.
    func complete(id: String) {
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        reminder.isCompleted = true
        do {
            try store.save(reminder, commit: true)
            reminders.removeAll { $0.id == id }
        } catch {
            NSLog("DockDock: completing reminder failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Notes

/// A single sticky note persisted in user defaults.
@MainActor
@Observable
final class NotesStore {
    static let shared = NotesStore()

    var text: String {
        didSet { UserDefaults.standard.set(text, forKey: "notes") }
    }

    init() {
        text = UserDefaults.standard.string(forKey: "notes") ?? ""
    }
}

// MARK: - Focus timer

/// Pomodoro timer: focus sessions separated by short breaks, with a long
/// break after every `sessionsUntilLongBreak` focus sessions. The lengths
/// persist in user defaults.
@MainActor
@Observable
final class FocusTimer {
    static let shared = FocusTimer()

    enum Phase {
        case focus, shortBreak, longBreak

        var title: String {
            switch self {
            case .focus: "Focus"
            case .shortBreak: "Short break"
            case .longBreak: "Long break"
            }
        }
    }

    private(set) var phase: Phase = .focus
    var remaining: TimeInterval
    var isRunning = false
    /// Length of the current phase, in seconds.
    private(set) var sessionLength: TimeInterval
    /// Focus sessions finished since the last long break.
    private(set) var completedSessions = 0

    var focusMinutes: Int {
        didSet { lengthChanged(focusMinutes, key: Keys.focus, phase: .focus) }
    }
    var shortBreakMinutes: Int {
        didSet { lengthChanged(shortBreakMinutes, key: Keys.shortBreak, phase: .shortBreak) }
    }
    var longBreakMinutes: Int {
        didSet { lengthChanged(longBreakMinutes, key: Keys.longBreak, phase: .longBreak) }
    }
    var sessionsUntilLongBreak: Int {
        didSet {
            UserDefaults.standard.set(sessionsUntilLongBreak, forKey: Keys.sessions)
            completedSessions = min(completedSessions, max(sessionsUntilLongBreak - 1, 0))
        }
    }

    private enum Keys {
        static let focus = "focus.minutes"
        static let shortBreak = "focus.shortBreakMinutes"
        static let longBreak = "focus.longBreakMinutes"
        static let sessions = "focus.sessionsUntilLongBreak"
    }

    private var lastTick: Date?

    init() {
        let defaults = UserDefaults.standard
        let focus = defaults.object(forKey: Keys.focus) as? Int ?? 25
        focusMinutes = focus
        shortBreakMinutes = defaults.object(forKey: Keys.shortBreak) as? Int ?? 5
        longBreakMinutes = defaults.object(forKey: Keys.longBreak) as? Int ?? 15
        sessionsUntilLongBreak = defaults.object(forKey: Keys.sessions) as? Int ?? 4
        sessionLength = TimeInterval(focus * 60)
        remaining = TimeInterval(focus * 60)
    }

    var progress: Double {
        sessionLength > 0 ? 1 - (remaining / sessionLength) : 0
    }

    var formatted: String {
        let total = Int(remaining.rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    /// Neither running nor part-way through the current phase.
    var isIdle: Bool { !isRunning && remaining == sessionLength }

    /// The focus session in progress (or just finished, during a break),
    /// counted from 1 within the current long-break cycle.
    var sessionNumber: Int {
        phase == .focus ? completedSessions + 1 : max(completedSessions, 1)
    }

    func minutes(for phase: Phase) -> Int {
        switch phase {
        case .focus: focusMinutes
        case .shortBreak: shortBreakMinutes
        case .longBreak: longBreakMinutes
        }
    }

    func toggle() {
        isRunning.toggle()
        lastTick = isRunning ? Date() : nil
    }

    /// Starts a focus session from the top, leaving any break.
    func startFocus() {
        load(.focus)
        isRunning = true
        lastTick = Date()
    }

    /// Ends the current phase early and moves to the next one.
    func skip() {
        finishPhase(alert: false)
    }

    func reset() {
        completedSessions = 0
        load(.focus)
    }

    /// Called once per second by the shared ticker.
    func tick() {
        guard isRunning, let lastTick else { return }
        let now = Date()
        let elapsed = now.timeIntervalSince(lastTick)
        self.lastTick = now
        remaining = max(0, remaining - elapsed)
        if remaining == 0 {
            finishPhase(alert: true)
        }
    }

    /// Focus hands over to a break, which starts on its own; a break hands
    /// back to a focus session that waits for the user.
    private func finishPhase(alert: Bool) {
        switch phase {
        case .focus:
            completedSessions += 1
            let next: Phase = completedSessions >= sessionsUntilLongBreak ? .longBreak : .shortBreak
            load(next)
            isRunning = true
            lastTick = Date()
            if alert {
                ClockAlert.post(
                    title: "Focus session complete",
                    body: "Time for a \(minutes(for: next))-minute \(next == .longBreak ? "long break" : "break")."
                )
            }
        case .shortBreak, .longBreak:
            if phase == .longBreak { completedSessions = 0 }
            load(.focus)
            if alert {
                ClockAlert.post(
                    title: "Break is over",
                    body: "Ready for focus session \(completedSessions + 1) of \(sessionsUntilLongBreak)."
                )
            }
        }
    }

    /// Loads a phase at full length, stopped.
    private func load(_ next: Phase) {
        phase = next
        sessionLength = TimeInterval(minutes(for: next) * 60)
        remaining = sessionLength
        isRunning = false
        lastTick = nil
    }

    private func lengthChanged(_ minutes: Int, key: String, phase changed: Phase) {
        UserDefaults.standard.set(minutes, forKey: key)
        // A phase that has not started picks up its new length immediately;
        // one in progress keeps going and uses it next time.
        if phase == changed, isIdle {
            load(changed)
        }
    }
}

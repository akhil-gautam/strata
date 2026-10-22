import Foundation
import Security

// MARK: - Models

/// One rate-limit window ("Session (5h)", "Weekly").
struct AIUsageWindow: Sendable {
    var label: String
    /// 0–100.
    var usedPercent: Double
    var resetsAt: Date?
}

struct ClaudeLimits: Sendable {
    var windows: [AIUsageWindow]
    var plan: String?
    var extraUsage: ClaudeExtraUsage?
}

struct ClaudeExtraUsage: Sendable {
    var usedCredits: Double
    var monthlyLimit: Double?
    var currency: String
}

/// The rate limits Codex recorded with its last turn.
struct CodexLimits: Sendable {
    var windows: [AIUsageWindow]
    var plan: String?
    /// When Codex wrote the snapshot.
    var asOf: Date
    var creditsBalance: String?
}

enum AIUsageSource: String, Sendable {
    case claude, codex
}

// MARK: - Claude credentials

/// Claude Code's OAuth sign-in, as it stores it in the login keychain.
struct ClaudeCredential: Sendable {
    var token: String
    var expiresAt: Date?
    /// `subscriptionType`: "max", "pro"…
    var plan: String?
}

enum ClaudeCredentialError: Error {
    case notSignedIn
    case accessDenied
    case failed
}

enum ClaudeCredentials {
    /// Reads Claude Code's keychain item. Blocks while macOS shows its
    /// access prompt, so never call it on the main actor.
    ///
    /// Only the access token is used. The refresh token is never touched:
    /// refreshing rotates it and would sign Claude Code out.
    static func read() -> Result<ClaudeCredential, ClaudeCredentialError> {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let oauth = root["claudeAiOauth"] as? [String: Any],
                  let token = oauth["accessToken"] as? String, !token.isEmpty
            else { return .failure(.notSignedIn) }
            let expiresAt = (oauth["expiresAt"] as? NSNumber).map {
                Date(timeIntervalSince1970: $0.doubleValue / 1000)
            }
            return .success(ClaudeCredential(
                token: token,
                expiresAt: expiresAt,
                plan: oauth["subscriptionType"] as? String
            ))
        case errSecItemNotFound:
            return .failure(.notSignedIn)
        case errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed:
            return .failure(.accessDenied)
        default:
            NSLog("Shelfie: Claude keychain read failed: %d", status)
            return .failure(.failed)
        }
    }
}

// MARK: - Claude limits

enum ClaudeLimitsAPI {
    private static let windows: [(key: String, label: String)] = [
        ("five_hour", "Session (5h)"),
        ("seven_day", "Weekly"),
        ("seven_day_opus", "Weekly · Opus"),
        ("seven_day_sonnet", "Weekly · Sonnet"),
        ("seven_day_oauth_apps", "Weekly · Apps"),
    ]

    /// The subscription's live usage, as Claude Code's `/usage` shows it.
    static func fetch(token: String) async throws -> ClaudeLimits {
        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else {
            throw HTTPClient.Error(message: "Bad URL")
        }
        let payload = try await ServiceAPI.object(
            url,
            token: token,
            headers: ["anthropic-beta": "oauth-2025-04-20", "User-Agent": "Shelfie"]
        )
        let parsed = windows.compactMap { key, label -> AIUsageWindow? in
            guard let window = payload.object(key), let used = window.number("utilization") else { return nil }
            return AIUsageWindow(label: label, usedPercent: used, resetsAt: window.string("resets_at").flatMap(date))
        }
        var extra: ClaudeExtraUsage?
        if let usage = payload.object("extra_usage"),
           usage.raw["is_enabled"] as? Bool == true,
           let used = usage.number("used_credits") {
            extra = ClaudeExtraUsage(
                usedCredits: used,
                monthlyLimit: usage.number("monthly_limit"),
                currency: usage.string("currency") ?? "USD"
            )
        }
        return ClaudeLimits(windows: parsed, plan: nil, extraUsage: extra)
    }

    private static func date(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

// MARK: - Codex limits

enum CodexLimitsReader {
    static var root: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex/sessions", directoryHint: .isDirectory)
    }

    /// The rate-limit snapshot of Codex's most recent turn, from the newest
    /// session logs.
    static func latest() -> CodexLimits? {
        let files = AIUsageFiles.jsonl(under: root)
            .sorted { $0.modified > $1.modified }
            .prefix(5)
        let marker = Data(#""rate_limits""#.utf8)
        for file in files {
            guard let handle = try? FileHandle(forReadingFrom: file.url) else { continue }
            defer { try? handle.close() }
            let tail: UInt64 = 1 << 20
            let start = file.size > tail ? file.size - tail : 0
            guard (try? handle.seek(toOffset: start)) != nil,
                  let data = try? handle.readToEnd()
            else { continue }
            let lines = data.split(separator: 0x0A, omittingEmptySubsequences: true)
            for line in lines.reversed() where line.range(of: marker) != nil {
                if let limits = parse(Data(line)) { return limits }
            }
        }
        return nil
    }

    private static func parse(_ line: Data) -> CodexLimits? {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let payload = object["payload"] as? [String: Any],
              payload["type"] as? String == "token_count",
              let limits = payload["rate_limits"] as? [String: Any],
              // Other buckets ("premium") carry no windows of their own.
              (limits["limit_id"] as? String).map({ $0 == "codex" }) ?? true,
              let primary = limits["primary"] as? [String: Any]
        else { return nil }

        let windows = [primary, limits["secondary"] as? [String: Any]].compactMap { window -> AIUsageWindow? in
            guard let window, let used = (window["used_percent"] as? NSNumber)?.doubleValue else { return nil }
            let minutes = (window["window_minutes"] as? NSNumber)?.intValue ?? 0
            let resets = (window["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
            return AIUsageWindow(label: label(minutes: minutes), usedPercent: used, resetsAt: resets)
        }
        let credits = limits["credits"] as? [String: Any]
        let balance = credits?["has_credits"] as? Bool == true ? credits?["balance"] as? String : nil
        let asOf = (object["timestamp"] as? String).flatMap(AIUsageDates.parse) ?? Date()
        return CodexLimits(
            windows: windows,
            plan: (limits["plan_type"] as? String).map(planName),
            asOf: asOf,
            creditsBalance: balance
        )
    }

    private static func label(minutes: Int) -> String {
        switch minutes {
        case 300: "Session (5h)"
        case 10080: "Weekly"
        case ..<1440: "\(minutes / 60)h"
        default: "\(minutes / 1440)d"
        }
    }

    private static func planName(_ raw: String) -> String {
        switch raw {
        case "prolite": "Pro Lite"
        case "pro": "Pro"
        case "plus": "Plus"
        case "team": "Team"
        case "business": "Business"
        case "enterprise": "Enterprise"
        case "edu": "Edu"
        case "free": "Free"
        default: raw.capitalized
        }
    }
}

// MARK: - Token logs

/// Daily token totals read from Claude Code's and Codex's session logs.
/// The first scan reads every log touched in the last week; later scans read
/// only what was appended since.
actor AIUsageLogScanner {
    static let shared = AIUsageLogScanner()

    private var states: [AIUsageSource: AIUsageScanState] = [:]
    /// The scan in progress per source; concurrent callers await the same one.
    private var scanning: [AIUsageSource: Task<AIUsageScanState, Never>] = [:]

    /// Seven token totals, oldest first, the last one today's.
    func daily(_ source: AIUsageSource) async -> [Int] {
        let task: Task<AIUsageScanState, Never>
        if let running = scanning[source] {
            task = running
        } else {
            let state = states[source] ?? AIUsageScanState()
            task = Task.detached(priority: .utility) {
                let started = Date()
                let result = AIUsageScan.refresh(state, source: source)
                let elapsed = Date().timeIntervalSince(started)
                if elapsed > 1 {
                    NSLog("Shelfie: %@ token scan took %.1fs", source.rawValue, elapsed)
                }
                return result
            }
            scanning[source] = task
        }
        let result = await task.value
        // The first waiter to resume stores the result; a later one would
        // otherwise overwrite a newer scan.
        if scanning[source] == task {
            states[source] = result
            scanning[source] = nil
        }
        return AIUsageScan.series(states[source] ?? result)
    }
}

struct AIUsageScanCursor: Sendable {
    /// Bytes consumed, always just past a newline.
    var offset: UInt64
    /// Codex: the session's cumulative total at `offset`.
    var codexLastTotal: Int?
}

struct AIUsageScanState: Sendable {
    var cursors: [String: AIUsageScanCursor] = [:]
    /// Tokens per local day, keyed by the day's start.
    var buckets: [Date: Int] = [:]
    /// Claude: counted `message.id|requestId` keys and the day each fell on,
    /// pruned with the buckets.
    var seen: [String: Date] = [:]
}

private enum AIUsageScan {
    static let chunk = 4 << 20

    static func windowStart(_ calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .day, value: -6, to: today) ?? today
    }

    static func series(_ state: AIUsageScanState) -> [Int] {
        let calendar = Calendar.current
        let start = windowStart(calendar)
        return (0..<7).map { offset in
            let day = calendar.date(byAdding: .day, value: offset, to: start) ?? start
            return state.buckets[day] ?? 0
        }
    }

    static func refresh(_ initial: AIUsageScanState, source: AIUsageSource) -> AIUsageScanState {
        let calendar = Calendar.current
        let start = windowStart(calendar)
        let root = switch source {
        case .claude: FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/projects", directoryHint: .isDirectory)
        case .codex: CodexLimitsReader.root
        }
        let files = AIUsageFiles.jsonl(under: root).filter { $0.modified >= start }

        var state = initial
        // A log shorter than what was read has been rewritten: start over.
        if files.contains(where: { $0.size < state.cursors[$0.url.path]?.offset ?? 0 }) {
            state = AIUsageScanState()
        }
        state.buckets = state.buckets.filter { $0.key >= start }
        state.seen = state.seen.filter { $0.value >= start }

        let marker = Data((source == .claude ? #""usage""# : #""token_count""#).utf8)
        let dates = AIUsageDates()
        for file in files {
            let path = file.url.path
            var cursor = state.cursors[path] ?? AIUsageScanCursor(offset: 0)
            guard file.size > cursor.offset else { continue }
            cursor.offset = AIUsageLines.read(file.url, from: cursor.offset, marker: marker) { line in
                guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return }
                switch source {
                case .claude:
                    claudeLine(object, start: start, calendar: calendar, dates: dates, state: &state)
                case .codex:
                    codexLine(object, start: start, calendar: calendar, dates: dates, cursor: &cursor, state: &state)
                }
            }
            state.cursors[path] = cursor
        }
        return state
    }

    private static func claudeLine(
        _ object: [String: Any],
        start: Date,
        calendar: Calendar,
        dates: AIUsageDates,
        state: inout AIUsageScanState
    ) {
        guard object["type"] as? String == "assistant",
              let message = object["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any],
              let date = (object["timestamp"] as? String).flatMap(dates.date)
        else { return }
        let day = calendar.startOfDay(for: date)
        guard day >= start else { return }
        let id = message["id"] as? String ?? object["uuid"] as? String ?? ""
        let key = "\(id)|\(object["requestId"] as? String ?? "")"
        guard state.seen.updateValue(day, forKey: key) == nil else { return }
        let tokens = ["input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens", "output_tokens"]
            .reduce(0) { $0 + ((usage[$1] as? NSNumber)?.intValue ?? 0) }
        state.buckets[day, default: 0] += tokens
    }

    private static func codexLine(
        _ object: [String: Any],
        start: Date,
        calendar: Calendar,
        dates: AIUsageDates,
        cursor: inout AIUsageScanCursor,
        state: inout AIUsageScanState
    ) {
        guard let payload = object["payload"] as? [String: Any],
              payload["type"] as? String == "token_count",
              let info = payload["info"] as? [String: Any],
              let usage = info["total_token_usage"] as? [String: Any],
              let total = (usage["total_tokens"] as? NSNumber)?.intValue
        else { return }
        // Totals are cumulative per session; a drop means a new count.
        let delta = cursor.codexLastTotal.map { total >= $0 ? total - $0 : total } ?? total
        cursor.codexLastTotal = total
        guard delta > 0, let date = (object["timestamp"] as? String).flatMap(dates.date) else { return }
        let day = calendar.startOfDay(for: date)
        guard day >= start else { return }
        state.buckets[day, default: 0] += delta
    }
}

// MARK: - Files

enum AIUsageFiles {
    struct Entry {
        var url: URL
        var modified: Date
        var size: UInt64
    }

    /// Every `*.jsonl` under `root`, at any depth.
    static func jsonl(under root: URL) -> [Entry] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var entries: [Entry] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true
            else { continue }
            entries.append(Entry(
                url: url,
                modified: values.contentModificationDate ?? .distantPast,
                size: UInt64(values.fileSize ?? 0)
            ))
        }
        return entries
    }
}

private enum AIUsageLines {
    /// Calls `body` with every complete line from `offset` on that contains
    /// `marker`. Returns the offset just past the last newline read; a
    /// partial last line is left for the next read.
    static func read(_ url: URL, from offset: UInt64, marker: Data, body: (Data) -> Void) -> UInt64 {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return offset }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: offset)) != nil else { return offset }

        var consumed = offset
        var carry = Data()
        // Each 4 MB chunk drains its own autorelease pool: the JSON objects
        // parsed from it would otherwise pile up until the whole scan ends,
        // which peaked at 1.2 GB on 2.5 GB of logs.
        while true {
            let done: Bool = autoreleasepool {
                guard let chunk = try? handle.read(upToCount: AIUsageScan.chunk), !chunk.isEmpty else { return true }
                var buffer = carry
                buffer.append(chunk)
                let used = buffer.withUnsafeBytes { raw -> Int in
                    guard let base = raw.baseAddress else { return 0 }
                    return marker.withUnsafeBytes { needle -> Int in
                        var start = 0
                        while start < raw.count,
                              let newline = memchr(base + start, 0x0A, raw.count - start) {
                            let end = base.distance(to: UnsafeRawPointer(newline))
                            let length = end - start
                            if length > 0,
                               memmem(base + start, length, needle.baseAddress, needle.count) != nil {
                                body(Data(bytes: base + start, count: length))
                            }
                            start = end + 1
                        }
                        return start
                    }
                }
                consumed += UInt64(used)
                carry = used < buffer.count ? buffer.subdata(in: used..<buffer.count) : Data()
                return false
            }
            if done { break }
        }
        return consumed
    }
}

/// ISO-8601 timestamps as the logs write them, with or without fractional
/// seconds. One instance per scan: the formatters are not thread-safe.
final class AIUsageDates {
    private let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private let whole: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    func date(_ string: String) -> Date? {
        fractional.date(from: string) ?? whole.date(from: string)
    }

    static func parse(_ string: String) -> Date? {
        AIUsageDates().date(string)
    }
}

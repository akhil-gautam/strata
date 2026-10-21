import Foundation
import Observation
import SwiftUI

/// Claude Code and Codex usage for the AI Usage tiles. Tiles keep the data
/// fresh by running the loops from `.task`; nothing polls while no tile is
/// shown.
@MainActor
@Observable
final class AIUsageStore {
    static let shared = AIUsageStore()

    enum ClaudeState {
        case idle, loading, live(ClaudeLimits), notSignedIn, accessDenied, expired, failed
    }

    enum CodexState {
        case idle, live(CodexLimits), noData
    }

    private(set) var claude: ClaudeState = .idle
    private(set) var codex: CodexState = .idle
    /// Seven daily totals, oldest first; `nil` until the first scan ends.
    private(set) var claudeDaily: [Int]?
    private(set) var codexDaily: [Int]?

    @ObservationIgnored private var credential: ClaudeCredential?
    /// A token the usage endpoint refused; reading it again means Claude
    /// Code has not refreshed its sign-in yet.
    @ObservationIgnored private var rejectedToken: String?
    @ObservationIgnored private var fetchedAt: [Feed: Date] = [:]
    @ObservationIgnored private var inFlight: Set<Feed> = []

    private enum Feed: Hashable {
        case claudeLimits, codexLimits, tokens(AIUsageSource)

        var interval: TimeInterval {
            switch self {
            case .claudeLimits: 300
            case .codexLimits, .tokens: 60
            }
        }
    }

    private init() {}

    // MARK: Loops

    func runClaude() async { await run(.claudeLimits) }
    func runCodex() async { await run(.codexLimits) }
    func runTokens(_ source: AIUsageSource) async { await run(.tokens(source)) }

    /// Forces the limits and the token totals of one source.
    func refresh(_ source: AIUsageSource) {
        Task { await load(source == .claude ? .claudeLimits : .codexLimits, force: true) }
        Task { await load(.tokens(source), force: true) }
    }

    /// The user asked to try the keychain again after denying it.
    func retryClaudeAccess() {
        if case .accessDenied = claude { claude = .idle }
        Task { await load(.claudeLimits, force: true) }
    }

    private func run(_ feed: Feed) async {
        while !Task.isCancelled {
            await load(feed, force: false)
            do {
                try await Task.sleep(for: .seconds(feed.interval))
            } catch {
                return
            }
        }
    }

    private func load(_ feed: Feed, force: Bool) async {
        guard !inFlight.contains(feed) else { return }
        if !force, let at = fetchedAt[feed], Date().timeIntervalSince(at) < feed.interval - 1 { return }
        inFlight.insert(feed)
        defer {
            inFlight.remove(feed)
            fetchedAt[feed] = Date()
        }
        switch feed {
        case .claudeLimits:
            await loadClaude(force: force)
        case .codexLimits:
            let limits = await Task.detached(priority: .utility) { CodexLimitsReader.latest() }.value
            codex = limits.map { .live($0) } ?? .noData
        case .tokens(let source):
            let daily = await AIUsageLogScanner.shared.daily(source)
            switch source {
            case .claude: claudeDaily = daily
            case .codex: codexDaily = daily
            }
        }
    }

    // MARK: Claude

    private func loadClaude(force: Bool) async {
        // A denied keychain prompt is only retried by the user.
        if case .accessDenied = claude, !force { return }
        if case .live = claude {} else { claude = .loading }

        // A refused token is re-read once: Claude Code may have refreshed it.
        for _ in 0..<2 {
            if credential == nil || isExpired(credential) {
                let result = await Task.detached(priority: .utility) { ClaudeCredentials.read() }.value
                switch result {
                case .failure(.notSignedIn):
                    credential = nil
                    claude = .notSignedIn
                    return
                case .failure(.accessDenied):
                    credential = nil
                    claude = .accessDenied
                    return
                case .failure(.failed):
                    credential = nil
                    claude = .failed
                    return
                case .success(let read):
                    if read.token == rejectedToken {
                        claude = .expired
                        return
                    }
                    credential = read
                }
            }
            guard let current = credential, !isExpired(current) else {
                // Claude Code refreshes its token the next time it runs.
                claude = .expired
                return
            }

            do {
                var limits = try await ClaudeLimitsAPI.fetch(token: current.token)
                limits.plan = current.plan.map(Self.planName)
                rejectedToken = nil
                claude = .live(limits)
                return
            } catch let error as HTTPClient.Error where error.statusCode == 401 || error.statusCode == 403 {
                NSLog("Shelfie: Claude limits failed: %@", error.message)
                rejectedToken = current.token
                credential = nil
            } catch {
                NSLog("Shelfie: Claude limits failed: %@", String(describing: error))
                claude = .failed
                return
            }
        }
        claude = .expired
    }

    private func isExpired(_ credential: ClaudeCredential?) -> Bool {
        guard let expiresAt = credential?.expiresAt else { return false }
        return expiresAt <= Date()
    }

    private static func planName(_ raw: String) -> String {
        switch raw {
        case "max": "Max"
        case "pro": "Pro"
        default: raw.capitalized
        }
    }
}

// MARK: - Formatting

@MainActor
enum AIUsageFormat {
    /// Claude's and Codex's own colours; the same in every theme.
    static let claude = Color(red: 0.85, green: 0.47, blue: 0.34)
    static let codex = Color(red: 0.06, green: 0.64, blue: 0.50)
    /// omp has no brand colour of its own; a violet apart from the other two.
    static let omp = Color(red: 0.55, green: 0.43, blue: 0.96)

    static func brand(_ source: AIUsageSource) -> Color {
        source == .claude ? claude : codex
    }

    static func brand(_ tool: AgentTool) -> Color {
        switch tool {
        case .claude: claude
        case .codex: codex
        case .omp: omp
        }
    }

    /// "842", "12.4K", "12.4M", "1.2B".
    static func tokens(_ count: Int) -> String {
        let value = Double(count)
        let (scaled, suffix): (Double, String) = switch abs(value) {
        case ..<1_000: (value, "")
        case ..<1_000_000: (value / 1_000, "K")
        case ..<1_000_000_000: (value / 1_000_000, "M")
        default: (value / 1_000_000_000, "B")
        }
        if suffix.isEmpty { return "\(count)" }
        var text = String(format: "%.1f", scaled)
        if text.hasSuffix(".0") { text.removeLast(2) }
        return text + suffix
    }

    /// "45m", "2h 14m", "3d 4h"; "reset" once the time has passed.
    static func countdown(to date: Date?, now: Date = Date()) -> String {
        guard let date else { return "" }
        let seconds = Int(date.timeIntervalSince(now))
        if seconds <= 0 { return "reset" }
        if seconds < 60 { return "<1m" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h \(minutes % 60)m" }
        return "\(hours / 24)d \(hours % 24)h"
    }

    static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    /// A window whose reset has passed is empty again, even if the snapshot
    /// (Codex's last turn) predates the reset.
    static func effectiveUsed(_ window: AIUsageWindow, now: Date = Date()) -> Double {
        if let resetsAt = window.resetsAt, resetsAt <= now { return 0 }
        return window.usedPercent
    }

    static func tint(_ percent: Double, brand: Color) -> Color {
        if percent >= 90 { return TilePalette.destructive }
        if percent >= 75 { return DockAccent.orange }
        return brand
    }
}

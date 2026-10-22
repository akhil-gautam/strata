import AppKit
import SwiftUI

/// The AI Usage section, added by the AI Usage extension.
///
/// Tile ids: `"claude-limits"`, `"codex-limits"`, `"claude-tokens"`,
/// `"codex-tokens"`, `"ai-usage"`, `"agent-status"`. The org-level
/// `"claude-usage"` tile lives in ``BusinessTiles`` but shows in this section
/// too.
///
/// Claude limits come from Claude Code's sign-in and are only loaded from
/// the bar, so browsing the library never triggers the keychain prompt.
/// Codex limits and token totals are read from local logs everywhere.
/// Agent Status watches running sessions from the bar only; the library
/// shows sample rows.
@MainActor
enum AIUsageTiles {
    static let specs: [TileSpec] = [
        TileSpec(
            id: "claude-limits",
            title: "Claude Limits",
            category: .aiUsage,
            menu: [
                .customize("Details…"),
                .action("Refresh") { AIUsageStore.shared.refresh(.claude) },
                .action("Open Claude Usage") { open("https://claude.ai/settings/usage") },
            ],
            settings: TileSettings(symbol: "sparkles", badge: nil) { AnyView(AIUsageClaudeDetails()) },
            make: { AnyView(AIUsageClaudeLimitsTile()) }
        ),
        TileSpec(
            id: "codex-limits",
            title: "Codex Limits",
            category: .aiUsage,
            menu: [
                .customize("Details…"),
                .action("Refresh") { AIUsageStore.shared.refresh(.codex) },
                .action("Open Codex") { open("https://chatgpt.com/codex") },
            ],
            settings: TileSettings(symbol: "terminal", badge: nil) { AnyView(AIUsageCodexDetails()) },
            make: { AnyView(AIUsageCodexLimitsTile()) }
        ),
        tokens(id: "claude-tokens", title: "Claude Tokens", source: .claude, logs: ".claude/projects"),
        tokens(id: "codex-tokens", title: "Codex Tokens", source: .codex, logs: ".codex/sessions"),
        TileSpec(
            id: "ai-usage",
            title: "AI Usage",
            category: .aiUsage,
            menu: [
                .action("Refresh") {
                    AIUsageStore.shared.refresh(.claude)
                    AIUsageStore.shared.refresh(.codex)
                },
            ],
            make: { AnyView(AIUsageOverviewTile()) }
        ),
        TileSpec(
            id: "agent-status",
            title: "Agent Status",
            category: .aiUsage,
            menu: [.dynamic { AgentSessions.shared.menuItems() }],
            make: { AnyView(AgentStatusTile()) }
        ),
    ]

    private static func tokens(id: String, title: String, source: AIUsageSource, logs: String) -> TileSpec {
        TileSpec(
            id: id,
            title: title,
            category: .aiUsage,
            menu: [
                .action("Refresh") { AIUsageStore.shared.refresh(source) },
                .action("Reveal Logs in Finder") {
                    let url = FileManager.default.homeDirectoryForCurrentUser.appending(path: logs, directoryHint: .isDirectory)
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                },
            ],
            make: { AnyView(AIUsageTokensTile(source: source)) }
        )
    }

    private static func open(_ link: String) {
        if let url = URL(string: link) {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Samples

/// What the library shows before there is real data.
@MainActor
private enum AIUsageSample {
    static func windows(_ pairs: [(Double, TimeInterval)], now: Date) -> [AIUsageWindow] {
        zip(["Session (5h)", "Weekly"], pairs).map { label, pair in
            // Half a minute of slack so the countdown reads the round value.
            AIUsageWindow(label: label, usedPercent: pair.0, resetsAt: now.addingTimeInterval(pair.1 + 30))
        }
    }

    static func claude(now: Date) -> [AIUsageWindow] {
        windows([(34, 2 * 3600 + 14 * 60), (61, 3 * 86400 + 4 * 3600)], now: now)
    }

    static func codex(now: Date) -> [AIUsageWindow] {
        windows([(12, 3 * 3600 + 2 * 60), (48, 4 * 86400 + 1 * 3600)], now: now)
    }

    static func daily(_ source: AIUsageSource) -> [Double] {
        switch source {
        case .claude: [3.1, 5.2, 4.4, 8.9, 6.1, 9.8, 12.4].map { $0 * 1_000_000 }
        case .codex: [1.2, 2.0, 0.8, 3.3, 2.7, 4.1, 4.8].map { $0 * 1_000_000 }
        }
    }
}

// MARK: - Shared pieces

/// A thin ring with the percentage inside; the same gauge as the System
/// tiles.
private struct AIUsageRing: View {
    var value: Double
    var tint: Color
    var text: String
    var diameter: CGFloat = 38
    var lineWidth: CGFloat = 3.5

    var body: some View {
        ZStack {
            Circle()
                .stroke(TilePalette.ink.opacity(0.12), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(value, 0.001), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.4), value: value)
            Text(text)
                .font(.tileValue(11, weight: .bold))
                .foregroundStyle(TilePalette.ink)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: diameter - lineWidth * 2 - 4)
        }
        .frame(width: diameter, height: diameter)
    }
}

/// One window of a limits tile: ring, label and the reset countdown.
private struct AIUsageSlot: View {
    var window: AIUsageWindow?
    /// Shown when `window` is nil (not loaded yet).
    var label: String
    var brand: Color
    var now: Date

    var body: some View {
        let used = window.map { AIUsageFormat.effectiveUsed($0, now: now) }
        HStack(spacing: 5) {
            AIUsageRing(
                value: (used ?? 0) / 100,
                tint: AIUsageFormat.tint(used ?? 0, brand: brand),
                text: used.map(AIUsageFormat.percent) ?? "—"
            )
            VStack(alignment: .leading, spacing: 1) {
                Text(window?.label ?? label)
                    .font(.tileCaption(9, weight: .semibold))
                    .foregroundStyle(TilePalette.ink)
                Text(caption)
                    .font(.tileCaption(8))
                    .foregroundStyle(TilePalette.caption)
                    .monospacedDigit()
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var caption: String {
        guard let window else { return "—" }
        let countdown = AIUsageFormat.countdown(to: window.resetsAt, now: now)
        switch countdown {
        case "": return "no reset time"
        case "reset": return "reset"
        default: return "resets \(countdown)"
        }
    }
}

/// The plan name in a limits tile's second slot, when there is one window.
private struct AIUsagePlanSlot: View {
    var plan: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(plan)
                .font(.tileValue(14))
                .foregroundStyle(TilePalette.ink)
            Text("plan")
                .font(.tileCaption(8))
                .foregroundStyle(TilePalette.caption)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Value over caption for a state with nothing to chart.
private struct AIUsageMessage: View {
    var value: String
    var caption: String

    var body: some View {
        TileReadout(value: value, caption: caption, valueSize: 15)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// What a Claude state reads as when there are no limits to show.
@MainActor
private extension AIUsageStore.ClaudeState {
    var message: (value: String, caption: String, short: String)? {
        switch self {
        case .notSignedIn: ("Sign in", "to Claude Code", "Sign in")
        case .accessDenied: ("Allow access", "keychain", "Allow access")
        case .expired: ("Open Claude Code", "to refresh sign-in", "Expired")
        case .failed: ("Unavailable", "Claude limits", "Unavailable")
        case .idle, .loading, .live: nil
        }
    }

    var limits: ClaudeLimits? {
        if case .live(let limits) = self { return limits }
        return nil
    }
}

@MainActor
private extension AIUsageStore.CodexState {
    var limits: CodexLimits? {
        if case .live(let limits) = self { return limits }
        return nil
    }
}

// MARK: - Limits tiles

private struct AIUsageClaudeLimitsTile: View {
    @Environment(\.tileContext) private var context

    var body: some View {
        let store = AIUsageStore.shared
        TimelineView(.everyMinute) { timeline in
            let now = timeline.date
            DockTile(width: 210, inset: 8) {
                content(store.claude, now: now)
            }
        }
        .task {
            // Only the bar reads the keychain.
            guard context == .bar else { return }
            await store.runClaude()
        }
    }

    @ViewBuilder
    private func content(_ state: AIUsageStore.ClaudeState, now: Date) -> some View {
        if let limits = state.limits {
            slots(limits.windows, now: now)
        } else if context == .library {
            slots(AIUsageSample.claude(now: now), now: now)
        } else if case .accessDenied = state, let message = state.message {
            Button {
                AIUsageStore.shared.retryClaudeAccess()
            } label: {
                AIUsageMessage(value: message.value, caption: message.caption)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else if let message = state.message {
            AIUsageMessage(value: message.value, caption: message.caption)
        } else {
            slots([], now: now)
        }
    }

    private func slots(_ windows: [AIUsageWindow], now: Date) -> some View {
        HStack(spacing: 6) {
            AIUsageSlot(
                window: windows.first { $0.label == "Session (5h)" },
                label: "Session (5h)",
                brand: AIUsageFormat.claude,
                now: now
            )
            AIUsageSlot(
                window: windows.first { $0.label == "Weekly" },
                label: "Weekly",
                brand: AIUsageFormat.claude,
                now: now
            )
        }
    }
}

private struct AIUsageCodexLimitsTile: View {
    @Environment(\.tileContext) private var context

    var body: some View {
        let store = AIUsageStore.shared
        TimelineView(.everyMinute) { timeline in
            let now = timeline.date
            DockTile(width: 210, inset: 8) {
                if let limits = store.codex.limits {
                    slots(limits.windows, plan: limits.plan, now: now)
                } else if context == .library {
                    slots(AIUsageSample.codex(now: now), plan: nil, now: now)
                } else if case .noData = store.codex {
                    AIUsageMessage(value: "No Codex data", caption: "run Codex once")
                } else {
                    slots([], plan: nil, now: now)
                }
            }
        }
        .task { await store.runCodex() }
    }

    private func slots(_ windows: [AIUsageWindow], plan: String?, now: Date) -> some View {
        HStack(spacing: 6) {
            AIUsageSlot(window: windows.first, label: "Session (5h)", brand: AIUsageFormat.codex, now: now)
            if windows.count == 1 {
                AIUsagePlanSlot(plan: plan ?? "—")
            } else {
                AIUsageSlot(window: windows.dropFirst().first, label: "Weekly", brand: AIUsageFormat.codex, now: now)
            }
        }
    }
}

// MARK: - Token tiles

private struct AIUsageTokensTile: View {
    let source: AIUsageSource
    @Environment(\.tileContext) private var context

    var body: some View {
        let store = AIUsageStore.shared
        let daily = source == .claude ? store.claudeDaily : store.codexDaily
        let series = daily.map { $0.map(Double.init) } ?? (context == .library ? AIUsageSample.daily(source) : nil)
        DockTile(width: 150) {
            HStack(spacing: 8) {
                if let series {
                    TileReadout(value: AIUsageFormat.tokens(Int(series.last ?? 0)), caption: "tokens today")
                } else {
                    TileReadout(value: "—", caption: "reading logs…")
                }
                Spacer(minLength: 0)
                Sparkline(values: series ?? [])
                    .stroke(
                        AIUsageFormat.brand(source),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: 54, height: 24)
            }
        }
        .task(id: source) { await store.runTokens(source) }
    }
}

// MARK: - Overview tile

private struct AIUsageOverviewTile: View {
    @Environment(\.tileContext) private var context

    var body: some View {
        let store = AIUsageStore.shared
        TimelineView(.everyMinute) { timeline in
            let now = timeline.date
            DockTile(width: 250) {
                VStack(spacing: 7) {
                    if context == .bar, case .accessDenied = store.claude {
                        Button {
                            store.retryClaudeAccess()
                        } label: {
                            row(.claude, name: "Claude", now: now)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    } else {
                        row(.claude, name: "Claude", now: now)
                    }
                    row(.codex, name: "Codex", now: now)
                }
            }
        }
        .task {
            await withDiscardingTaskGroup { group in
                if context == .bar {
                    group.addTask { await store.runClaude() }
                }
                group.addTask { await store.runCodex() }
            }
        }
    }

    private func row(_ source: AIUsageSource, name: String, now: Date) -> some View {
        let (window, message) = state(source, now: now)
        let used = window.map { AIUsageFormat.effectiveUsed($0, now: now) }
        let brand = AIUsageFormat.brand(source)
        return HStack(spacing: 7) {
            Circle()
                .fill(brand)
                .frame(width: 6, height: 6)
            Text(name)
                .font(.tileText(11, weight: .semibold))
                .frame(width: 42, alignment: .leading)
            if let message {
                Text(message)
                    .font(.tileCaption(9.5))
                    .foregroundStyle(TilePalette.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Capsule()
                    .fill(TilePalette.ink.opacity(0.12))
                    .frame(height: 4)
                    .overlay(alignment: .leading) {
                        GeometryReader { proxy in
                            Capsule()
                                .fill(AIUsageFormat.tint(used ?? 0, brand: brand))
                                .frame(width: proxy.size.width * min(max((used ?? 0) / 100, 0), 1))
                        }
                    }
                    .animation(.easeOut(duration: 0.4), value: used)
                Text(used.map(AIUsageFormat.percent) ?? "—")
                    .font(.tileText(11, weight: .semibold))
                    .monospacedDigit()
                    .frame(width: 32, alignment: .trailing)
                Text(AIUsageFormat.countdown(to: window?.resetsAt, now: now))
                    .font(.tileCaption(9))
                    .foregroundStyle(TilePalette.caption)
                    .monospacedDigit()
                    .frame(width: 42, alignment: .trailing)
            }
        }
        .lineLimit(1)
        .foregroundStyle(TilePalette.ink)
    }

    private var store: AIUsageStore { AIUsageStore.shared }

    /// The first window to chart, or the short text standing in for it.
    private func state(_ source: AIUsageSource, now: Date) -> (AIUsageWindow?, String?) {
        switch source {
        case .claude:
            if let limits = store.claude.limits { return (limits.windows.first, nil) }
            if context == .library { return (AIUsageSample.claude(now: now).first, nil) }
            return (nil, store.claude.message?.short)
        case .codex:
            if let limits = store.codex.limits { return (limits.windows.first, nil) }
            if context == .library { return (AIUsageSample.codex(now: now).first, nil) }
            if case .noData = store.codex { return (nil, "No data") }
            return (nil, nil)
        }
    }
}

// MARK: - Details

private struct AIUsageDetailRow: View {
    var title: String
    var value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(TilePalette.ink)
            Spacer(minLength: 8)
            Text(value)
                .foregroundStyle(TilePalette.caption)
                .multilineTextAlignment(.trailing)
        }
        .font(.tileText(11.5))
    }
}

private struct AIUsageWindowRows: View {
    var windows: [AIUsageWindow]

    var body: some View {
        ForEach(Array(windows.enumerated()), id: \.offset) { _, window in
            let used = AIUsageFormat.percent(AIUsageFormat.effectiveUsed(window))
            let reset = window.resetsAt.map { "resets \($0.formatted(date: .abbreviated, time: .shortened))" }
            AIUsageDetailRow(title: window.label, value: [used, reset].compactMap { $0 }.joined(separator: " · "))
        }
    }
}

private struct AIUsageClaudeDetails: View {
    var body: some View {
        VStack(spacing: 6) {
            switch AIUsageStore.shared.claude {
            case .live(let limits):
                AIUsageWindowRows(windows: limits.windows)
                AIUsageDetailRow(title: "Plan", value: limits.plan ?? "—")
                if let extra = limits.extraUsage {
                    let used = extra.usedCredits.formatted(.number.precision(.fractionLength(2)))
                    let limit = extra.monthlyLimit.map { "of \($0.formatted(.number.precision(.fractionLength(2))))" }
                    AIUsageDetailRow(title: "Extra usage", value: "\(extra.currency) \(used) \(limit ?? "of no limit")")
                }
            case let state:
                AIUsageDetailRow(
                    title: "Status",
                    value: state.message.map { "\($0.value) \($0.caption)" } ?? "Loading…"
                )
            }
        }
        .frame(width: 260)
    }
}

private struct AIUsageCodexDetails: View {
    var body: some View {
        VStack(spacing: 6) {
            switch AIUsageStore.shared.codex {
            case .live(let limits):
                AIUsageWindowRows(windows: limits.windows)
                AIUsageDetailRow(title: "Plan", value: limits.plan ?? "—")
                AIUsageDetailRow(
                    title: "As of",
                    value: RelativeDateTimeFormatter().localizedString(for: limits.asOf, relativeTo: Date())
                )
                if let balance = limits.creditsBalance {
                    AIUsageDetailRow(title: "Credits", value: balance)
                }
            case .noData:
                AIUsageDetailRow(title: "Status", value: "No Codex sessions found")
            case .idle:
                AIUsageDetailRow(title: "Status", value: "Loading…")
            }
        }
        .frame(width: 260)
    }
}

// MARK: - Agent status

/// Live Claude Code, Codex and omp sessions: working, waiting for the user, or
/// done. Up to two rows; a click brings the session's terminal forward.
private struct AgentStatusTile: View {
    @Environment(\.tileContext) private var context

    var body: some View {
        let store = AgentSessions.shared
        // Elapsed times are shown to the minute, so the tile redraws once a
        // minute; a scan that changes a session redraws it at once. The
        // samples are drawn relative to the timeline's date.
        TimelineView(.everyMinute) { timeline in
            let sessions = context == .library ? AgentStatusSample.sessions(now: timeline.date) : store.sessions
            DockTile(width: 230) {
                content(sessions, now: timeline.date)
            }
        }
        .task {
            guard context == .bar else { return }
            await store.run()
        }
    }

    @ViewBuilder
    private func content(_ sessions: [AgentSession], now: Date) -> some View {
        if sessions.isEmpty {
            AIUsageMessage(value: emptyValue, caption: emptyCaption)
        } else if sessions.count == 1 {
            VStack(alignment: .leading, spacing: 4) {
                row(sessions[0], now: now, more: 0)
                Text(sessions[0].activity)
                    .font(.tileCaption(9.5))
                    .foregroundStyle(TilePalette.caption)
                    .lineLimit(1)
                    .padding(.leading, 13)
            }
        } else {
            VStack(spacing: 7) {
                row(sessions[0], now: now, more: 0)
                row(sessions[1], now: now, more: sessions.count - 2)
            }
        }
    }

    private var emptyValue: String {
        let store = AgentSessions.shared
        if !store.hasScanned { return "Agents" }
        return store.idleCount > 0 ? "All quiet" : "No agents running"
    }

    private var emptyCaption: String {
        let store = AgentSessions.shared
        if !store.hasScanned { return "looking for sessions…" }
        switch store.idleCount {
        case 0: return "Claude Code · Codex"
        case 1: return "1 idle session"
        default: return "\(store.idleCount) idle sessions"
        }
    }

    private func row(_ session: AgentSession, now: Date, more: Int) -> some View {
        Button {
            guard context == .bar else { return }
            AgentSessions.shared.focus(session)
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(AIUsageFormat.brand(session.tool))
                    .frame(width: 6, height: 6)
                Text(session.project)
                    .font(.tileText(11, weight: .semibold))
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                AgentStatePill(
                    state: session.state,
                    brand: AIUsageFormat.brand(session.tool),
                    waited: now.timeIntervalSince(session.since)
                )
                Text(AgentSessions.elapsed(since: session.since, now: now))
                    .font(.tileCaption(9))
                    .foregroundStyle(TilePalette.caption)
                    .monospacedDigit()
                    .frame(width: 34, alignment: .trailing)
                if more > 0 {
                    Text("+\(more)")
                        .font(.tileCaption(9, weight: .semibold))
                        .foregroundStyle(TilePalette.caption)
                }
            }
            .lineLimit(1)
            .foregroundStyle(TilePalette.ink)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(session.name ?? session.project) — \(session.activity)")
    }
}

/// "● Working" in the brand colour, "! Needs you" in orange (red after a
/// minute), "✓ Done" in green. Nothing animates: a looping effect here kept
/// the whole tile redrawing and cost about 16 % of a core.
private struct AgentStatePill: View {
    var state: AgentSession.State
    var brand: Color
    var waited: TimeInterval

    var body: some View {
        HStack(spacing: 3) {
            switch state {
            case .working:
                Image(systemName: "circle.fill")
                    .font(.system(size: 5))
            case .needsYou:
                Image(systemName: "exclamationmark")
                    .font(.system(size: 7, weight: .heavy))
            case .done:
                Image(systemName: "checkmark")
                    .font(.system(size: 7, weight: .heavy))
            }
            Text(state.title)
                .font(.tileCaption(9, weight: .semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background { Capsule().fill(tint.opacity(0.16)) }
        .fixedSize()
    }

    private var tint: Color {
        switch state {
        case .working: brand
        case .needsYou: waited >= 60 ? TilePalette.destructive : DockAccent.orange
        case .done: DockAccent.green
        }
    }
}

/// The library preview's rows.
@MainActor
private enum AgentStatusSample {
    static func sessions(now: Date) -> [AgentSession] { [
        AgentSession(
            id: "sample-claude",
            tool: .claude,
            cwd: "/Users/me/dockdock",
            name: nil,
            state: .working,
            since: now.addingTimeInterval(-194),
            activity: "Edit · AgentSessions.swift",
            pid: 0,
            log: nil,
            hostBundleID: nil,
            hostAncestors: []
        ),
        AgentSession(
            id: "sample-codex",
            tool: .codex,
            cwd: "/Users/me/api",
            name: nil,
            state: .needsYou,
            since: now.addingTimeInterval(-42),
            activity: "Approval · $ npm test",
            pid: 0,
            log: nil,
            hostBundleID: nil,
            hostAncestors: []
        ),
    ] }
}

import AppKit
import CoreServices
import Darwin
import Foundation
import Observation
import UserNotifications

// MARK: - Model

/// The coding agents the tile follows.
enum AgentTool: String, Sendable {
    case claude, codex, omp

    var title: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .omp: "omp"
        }
    }
}

/// One Claude Code, Codex or omp session running on this Mac.
struct AgentSession: Identifiable, Sendable, Equatable {
    enum State: Int, Sendable, Comparable {
        /// Waiting on the user: a permission prompt, a question, an approval.
        case needsYou
        case working
        /// The last turn ended; the agent waits for the next prompt.
        case done

        static func < (lhs: State, rhs: State) -> Bool { lhs.rawValue < rhs.rawValue }

        var title: String {
            switch self {
            case .needsYou: "Needs you"
            case .working: "Working"
            case .done: "Done"
            }
        }
    }

    /// `"claude:<session id>"`, `"codex:<thread id>"` or `"omp:<session id>"`.
    var id: String
    var tool: AgentTool
    var cwd: String
    /// Claude Code's session name ("i-shares-2d") or omp's session title.
    var name: String?
    var state: State
    /// When the session entered `state`: the turn's start while working, the
    /// prompt's appearance while it needs you, the turn's end once done.
    var since: Date
    /// "Bash · Run the tests", "$ git status", the start of the last reply.
    var activity: String
    var pid: pid_t
    var log: URL?
    /// The app that launched the agent (Terminal, iTerm, ChatGPT), from the
    /// `__CFBundleIdentifier` macOS puts in every child's environment.
    var hostBundleID: String?
    /// Parent, grandparent, … of `pid`, for when the environment has no
    /// bundle identifier.
    var hostAncestors: [pid_t]

    var project: String {
        let name = (cwd as NSString).lastPathComponent
        return name.isEmpty ? cwd : name
    }
}

// MARK: - Store

/// Live state of the Claude Code, Codex and omp sessions on this Mac, for the
/// Agent Status tile. The tile runs `run()` from `.task`; nothing is read
/// while no tile is on the bar.
@MainActor
@Observable
final class AgentSessions {
    static let shared = AgentSessions()

    /// Sessions worth showing, most urgent first. Sessions idle for half an
    /// hour or more are left out and only counted in `idleCount`.
    private(set) var sessions: [AgentSession] = []
    private(set) var idleCount = 0
    private(set) var hasScanned = false
    /// Banner when a session that worked for 30 s or more stops to wait for
    /// the user or finishes. Setting `agents.notify`, on by default.
    private(set) var notifies: Bool

    @ObservationIgnored private var memory = AgentScanMemory()
    @ObservationIgnored private var scanning = false
    @ObservationIgnored private var rescan = false
    @ObservationIgnored private var scannedAt: Date?
    @ObservationIgnored private var loops = 0
    @ObservationIgnored private var watcher: FSEventStreamRef?
    /// When each working session's turn began, for the notification rule.
    @ObservationIgnored private var workStart: [String: Date] = [:]

    private static let notifyKey = "agents.notify"
    private static let interval: Duration = .seconds(2)

    private init() {
        notifies = UserDefaults.standard.object(forKey: Self.notifyKey) as? Bool ?? true
    }

    // MARK: Loop

    /// Rescans every 2 s until cancelled, and right away when Claude Code
    /// rewrites its session registry.
    func run() async {
        loops += 1
        if loops == 1 { startWatching() }
        defer {
            loops -= 1
            if loops == 0 { stopWatching() }
        }
        while !Task.isCancelled {
            await refresh(force: false)
            do {
                try await Task.sleep(for: Self.interval)
            } catch {
                return
            }
        }
    }

    func refresh(force: Bool) async {
        if scanning {
            rescan = rescan || force
            return
        }
        if !force, let scannedAt, Date().timeIntervalSince(scannedAt) < 1.5 { return }
        scanning = true
        let memory = self.memory
        let scan = await Task.detached(priority: .utility) {
            AgentScanner.scan(memory: memory, now: Date())
        }.value
        self.memory = scan.memory
        scannedAt = Date()
        apply(scan)
        scanning = false
        if rescan {
            rescan = false
            await refresh(force: true)
        }
    }

    private func apply(_ scan: AgentScan) {
        let previous = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let now = Date()
        for session in scan.sessions {
            if session.state == .working {
                if previous[session.id]?.state != .working || workStart[session.id] == nil {
                    workStart[session.id] = session.since
                }
            } else if previous[session.id]?.state == .working, let start = workStart.removeValue(forKey: session.id) {
                let end = session.since > start ? session.since : now
                let long = end.timeIntervalSince(start) >= 30
                if long { notify(session) }
                // A question is worth a peek however short the turn was.
                if long || session.state == .needsYou { peek(session) }
            }
        }
        let live = Set(scan.sessions.map(\.id))
        workStart = workStart.filter { live.contains($0.key) }
        if sessions != scan.sessions { sessions = scan.sessions }
        if idleCount != scan.idle { idleCount = scan.idle }
        hasScanned = true
    }

    // MARK: Registry watch

    private func startWatching() {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".claude/sessions", directoryHint: .isDirectory).path
        watcher = Self.makeStream(path: path)
    }

    private func stopWatching() {
        guard let watcher else { return }
        FSEventStreamStop(watcher)
        FSEventStreamInvalidate(watcher)
        FSEventStreamRelease(watcher)
        self.watcher = nil
    }

    /// File-level events for `~/.claude/sessions`, delivered on the main
    /// queue. Claude Code rewrites `<pid>.json` whenever a session turns
    /// busy, waiting or idle, so the tile follows within a quarter second.
    private nonisolated static func makeStream(path: String) -> FSEventStreamRef? {
        var context = FSEventStreamContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, _, _, _, _, _ in
            MainActor.assumeIsolated {
                AgentSessions.shared.registryChanged()
            }
        }
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.25,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        ) else { return nil }
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return nil
        }
        return stream
    }

    private func registryChanged() {
        guard loops > 0 else { return }
        Task { await refresh(force: true) }
    }

    // MARK: Notifications

    func setNotifies(_ on: Bool) {
        notifies = on
        UserDefaults.standard.set(on, forKey: Self.notifyKey)
    }

    private func notify(_ session: AgentSession) {
        // Notification Center needs a bundled app; `swift run` has none.
        guard notifies, Bundle.main.bundleURL.pathExtension == "app" else { return }
        let tool = session.tool.title
        let title = session.state == .needsYou ? "\(tool) needs you" : "\(tool) finished"
        let body = "\(session.project) · \(session.activity)"
        let identifier = "agent-\(session.id)"
        Task {
            let center = UNUserNotificationCenter.current()
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            content.threadIdentifier = "agents"
            try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
        }
    }

    /// Drops a card from the notch island, when the bar is one.
    private func peek(_ session: AgentSession) {
        let needsYou = session.state == .needsYou
        DockIsland.shared.show(IslandPeek(
            symbol: needsYou ? "hand.raised.fill" : "checkmark.circle.fill",
            tint: needsYou ? DockAccent.orange : DockAccent.green,
            title: needsYou ? "\(session.tool.title) needs you" : "\(session.tool.title) finished",
            subtitle: "\(session.project) · \(session.activity)",
            action: { AgentSessions.shared.focus(session) },
            duration: needsYou ? 8 : 5
        ))
    }

    // MARK: Actions

    /// Brings the app hosting the session to the front, or opens the project
    /// folder when that app can't be found.
    func focus(_ session: AgentSession) {
        guard let app = hostApp(for: session) else {
            NSWorkspace.shared.open(URL(fileURLWithPath: session.cwd, isDirectory: true))
            return
        }
        _ = app.unhide()
        _ = app.activate(options: [])
    }

    func hostApp(for session: AgentSession) -> NSRunningApplication? {
        if let id = session.hostBundleID,
           let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first {
            return app
        }
        for pid in session.hostAncestors {
            if let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular {
                return app
            }
        }
        return nil
    }

    /// The tile's context menu: a submenu per session, then the
    /// notification switch.
    func menuItems() -> [TileMenuItem] {
        var items: [TileMenuItem] = sessions.map { session in
            var actions: [TileMenuItem] = []
            if let app = hostApp(for: session) {
                actions.append(.action("Show in \(app.localizedName ?? "Terminal")") {
                    AgentSessions.shared.focus(session)
                })
            }
            actions.append(.action("Reveal Project in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: session.cwd, isDirectory: true)])
            })
            if let log = session.log {
                actions.append(.action("Open Log") { Self.open(log: log) })
            }
            return .submenu("\(session.project) · \(session.state.title)", actions)
        }
        if !items.isEmpty { items.append(.separator) }
        items.append(.action(notifies ? "Turn Off Notifications" : "Turn On Notifications") {
            AgentSessions.shared.setNotifies(!AgentSessions.shared.notifies)
        })
        return items
    }

    private static func open(log: URL) {
        if NSWorkspace.shared.urlForApplication(toOpen: log) != nil {
            NSWorkspace.shared.open(log)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([log])
        }
    }

    /// "12s", "4m", "1h 5m", "2d".
    static func elapsed(since date: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return minutes % 60 == 0 ? "\(hours)h" : "\(hours)h \(minutes % 60)m" }
        return "\(hours / 24)d"
    }
}

// MARK: - Scanning

struct AgentScan: Sendable {
    var sessions: [AgentSession]
    var idle: Int
    var memory: AgentScanMemory
}

/// What one scan hands to the next.
struct AgentScanMemory: Sendable {
    struct Growth: Sendable {
        var size: UInt64
        var changedAt: Date
    }

    struct CodexThread: Sendable {
        var id: String
        var cwd: String
        var isSubagent: Bool
    }

    /// Log path → its size when it last changed.
    var growth: [String: Growth] = [:]
    /// Rollout path → its `session_meta`, read once.
    var codexThreads: [String: CodexThread] = [:]
    /// Rollout path → the last `turn_context.approval_policy` seen, for
    /// windows that no longer reach back to the turn's start.
    var codexPolicy: [String: String] = [:]
    /// Rollout path → when its running turn started.
    var codexTurnStart: [String: Date] = [:]
    /// pid → the host app's bundle identifier ("" for none).
    var hostBundles: [pid_t: String] = [:]

    /// Seconds since the file last grew, as far as scans have seen.
    mutating func quiet(_ path: String, size: UInt64, modified: Date, now: Date) -> TimeInterval {
        if let known = growth[path], known.size == size {
            return now.timeIntervalSince(known.changedAt)
        }
        let changed = growth[path] == nil ? min(modified, now) : now
        growth[path] = Growth(size: size, changedAt: changed)
        return now.timeIntervalSince(changed)
    }

    mutating func keep(paths: Set<String>, pids: Set<pid_t>) {
        growth = growth.filter { paths.contains($0.key) }
        codexThreads = codexThreads.filter { paths.contains($0.key) }
        codexPolicy = codexPolicy.filter { paths.contains($0.key) }
        codexTurnStart = codexTurnStart.filter { paths.contains($0.key) }
        hostBundles = hostBundles.filter { pids.contains($0.key) }
    }
}

/// One pass over the running agents. Runs off the main actor. omp is
/// described on `scanOmp()`.
///
/// Claude Code (verified against 2.1.296–2.1.304 on this Mac):
/// every interactive process writes `~/.claude/sessions/<pid>.json` with
/// `pid`, `sessionId`, `cwd`, `name`, `kind`, `startedAt` (ms) and — the
/// part this relies on — `status` and `statusUpdatedAt` (ms). The binary
/// (`Sxe` in 2.1.304) sets `status` to `"waiting"` with a `waitingFor`
/// reason whenever a dialog needs the user ("permission prompt" is the
/// default for tool-permission dialogs; also "input needed", "dialog open",
/// "sandbox request"), to `"busy"` while a query runs, and to `"idle"`
/// (or `"shell"`) otherwise. That gives working / needs-you exactly, with no
/// timing guesswork. The transcript `~/.claude/projects/<cwd slug>/<sessionId>.jsonl`
/// only supplies the activity text, and the state for versions that write
/// no `status`.
///
/// Codex (rollouts `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`, 124 files
/// here): turns are bracketed by `event_msg` payloads `task_started` and
/// `task_complete` (with `last_agent_message`) or `turn_aborted`. Approval
/// prompts are not written to the rollout (no approval event in 2.4 GB of
/// logs), so they are inferred; see `CodexLog`.
struct AgentScanner {
    var memory: AgentScanMemory
    let now: Date
    let processes: AgentProcessTable
    let dates = AIUsageDates()
    var sessions: [AgentSession] = []
    var idle = 0
    var paths: Set<String> = []

    /// Done sessions older than this, and working ones whose log has not
    /// grown for this long, are idle and hidden.
    static let stale: TimeInterval = 30 * 60

    static func scan(memory: AgentScanMemory, now: Date) -> AgentScan {
        var scanner = AgentScanner(memory: memory, now: now, processes: .snapshot())
        scanner.scanClaude()
        scanner.scanCodex()
        scanner.scanOmp()
        scanner.memory.keep(paths: scanner.paths, pids: Set(scanner.sessions.map(\.pid)))
        let sorted = scanner.sessions.sorted { lhs, rhs in
            lhs.state != rhs.state ? lhs.state < rhs.state : lhs.since > rhs.since
        }
        return AgentScan(sessions: sorted, idle: scanner.idle, memory: scanner.memory)
    }

    private var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    // MARK: Claude

    private mutating func scanClaude() {
        let registry = home.appending(path: ".claude/sessions", directoryHint: .isDirectory)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: registry.path) else { return }
        var bySession: [String: ClaudeRegistration] = [:]
        // `<pid>.json` only; the `<pid>.<hash>.key` files beside them are
        // messaging keys.
        for name in names where name.hasSuffix(".json") {
            guard let pid = pid_t(name.dropLast(5)),
                  let data = FileManager.default.contents(atPath: registry.appending(path: name).path),
                  let registration = ClaudeRegistration(data: data, pid: pid),
                  isLive(registration)
            else { continue }
            if let existing = bySession[registration.sessionId],
               (existing.statusUpdatedAt ?? .distantPast) >= (registration.statusUpdatedAt ?? .distantPast) {
                continue
            }
            bySession[registration.sessionId] = registration
        }
        for registration in bySession.values {
            addClaude(registration)
        }
    }

    /// The registry outlives crashed processes, and pids get reused: the pid
    /// must still run `claude` (`~/.local/bin/claude` →
    /// `~/.local/share/claude/versions/<v>`) and have started before the
    /// session registered.
    private func isLive(_ registration: ClaudeRegistration) -> Bool {
        if let kind = registration.kind, kind.hasPrefix("daemon") { return false }
        guard let process = processes.entries[registration.pid],
              let path = AgentProcessTable.executable(of: registration.pid),
              path.localizedCaseInsensitiveContains("claude")
        else { return false }
        if let startedAt = registration.startedAt, process.start > startedAt.addingTimeInterval(5) { return false }
        return true
    }

    private mutating func addClaude(_ registration: ClaudeRegistration) {
        let url = claudeLog(for: registration)
        var log: ClaudeLog?
        var quiet = TimeInterval.infinity
        if let url, let file = AgentFile(url) {
            paths.insert(url.path)
            quiet = memory.quiet(url.path, size: file.size, modified: file.modified, now: now)
            log = ClaudeLog.read(url, size: file.size, dates: dates)
        }

        let state: AgentSession.State
        let since: Date
        var activity = log?.activity
        switch registration.status {
        case "waiting":
            state = .needsYou
            since = registration.statusUpdatedAt ?? now
            activity = ClaudeLog.waitingText(registration.waitingFor, pendingTool: log?.pendingTool?.name)
        case "busy":
            state = .working
            since = registration.statusUpdatedAt ?? log?.since ?? now
        case "idle", "shell":
            // A session that has not run a turn yet, or finished long ago.
            guard let log, let changed = registration.statusUpdatedAt,
                  now.timeIntervalSince(max(changed, log.at)) < Self.stale
            else {
                idle += 1
                return
            }
            state = .done
            since = changed
        default:
            guard let log, let derived = fallback(log, pid: registration.pid, quiet: quiet) else {
                idle += 1
                return
            }
            state = derived.state
            since = derived.since
            activity = derived.activity ?? activity
        }

        sessions.append(AgentSession(
            id: "claude:\(registration.sessionId)",
            tool: .claude,
            cwd: registration.cwd,
            name: registration.name,
            state: state,
            since: since,
            activity: activity ?? (state == .working ? "Thinking" : state.title),
            pid: registration.pid,
            log: url,
            hostBundleID: hostBundle(of: registration.pid),
            hostAncestors: processes.ancestors(of: registration.pid)
        ))
    }

    /// The transcript Claude Code names after the session: the registry's
    /// `logPath` when present, else `<cwd with every non-alphanumeric
    /// replaced by "-">/<sessionId>.jsonl` (the binary's
    /// `replace(/[^a-zA-Z0-9]/g,"-")`; matches every project folder here),
    /// else any project folder holding that session.
    private func claudeLog(for registration: ClaudeRegistration) -> URL? {
        let manager = FileManager.default
        if let path = registration.logPath, manager.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        let projects = home.appending(path: ".claude/projects", directoryHint: .isDirectory)
        let file = "\(registration.sessionId).jsonl"
        let slug = String(registration.cwd.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" })
        let direct = projects.appending(path: slug, directoryHint: .isDirectory).appending(path: file)
        if manager.fileExists(atPath: direct.path) { return direct }
        for folder in (try? manager.contentsOfDirectory(atPath: projects.path)) ?? [] {
            let candidate = projects.appending(path: folder, directoryHint: .isDirectory).appending(path: file)
            if manager.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    /// State from the transcript alone, for Claude Code versions that write
    /// no `status` to the registry.
    ///
    /// A `tool_use` without its `tool_result` is not enough to call a
    /// permission prompt: across 28,000 tool calls in this Mac's logs,
    /// auto-approved `Bash` calls ran past 4 s 28 % of the time. So a
    /// pending tool reads as needing the user only when it is a question by
    /// nature (`AskUserQuestion`: median 330–370 s to answer; `ExitPlanMode`
    /// is often auto-approved, median 0.7 s, so it takes the next rule),
    /// or when the log has been quiet for 4 s and the `claude` process has
    /// started no child since the call (commands run as children; a tool
    /// held at a prompt has none).
    private func fallback(_ log: ClaudeLog, pid: pid_t, quiet: TimeInterval) -> (state: AgentSession.State, since: Date, activity: String?)? {
        switch log.state {
        case .done, .needsYou:
            guard now.timeIntervalSince(log.at) < Self.stale else { return nil }
            return (.done, log.at, nil)
        case .working:
            guard quiet < Self.stale else { return nil }
            if let tool = log.pendingTool {
                if ClaudeLog.asksUser.contains(tool.name) {
                    return (.needsYou, tool.at, ClaudeLog.waitingText(nil, pendingTool: tool.name))
                }
                if quiet >= 4, ClaudeLog.mayPrompt(tool.name),
                   !processes.hasDescendant(of: pid, startedAfter: tool.at.addingTimeInterval(-1)) {
                    return (.needsYou, tool.at, ClaudeLog.waitingText("permission prompt", pendingTool: tool.name))
                }
            }
            return (.working, log.since, nil)
        }
    }

    // MARK: Codex

    private mutating func scanCodex() {
        let pids = processes.pids(named: "codex")
        guard let first = pids.first else { return }
        let root = CodexLimitsReader.root
        let prefix = root.path + "/"
        // The rollout recorder keeps each thread's file open, so the open
        // files of the `codex` processes name the live threads exactly.
        var owners: [String: pid_t] = [:]
        for pid in pids {
            for path in AgentProcessTable.openFiles(of: pid, under: prefix) {
                owners[path] = pid
            }
        }
        var candidates: [(url: URL, file: AgentFile, owner: pid_t)] = []
        if owners.isEmpty {
            // Fall back to rollouts touched in the last half hour.
            for entry in AIUsageFiles.jsonl(under: root) where now.timeIntervalSince(entry.modified) < Self.stale {
                candidates.append((entry.url, AgentFile(size: entry.size, modified: entry.modified), first))
            }
        } else {
            for (path, owner) in owners {
                let url = URL(fileURLWithPath: path)
                if let file = AgentFile(url) { candidates.append((url, file, owner)) }
            }
        }
        for candidate in candidates {
            addCodex(candidate.url, file: candidate.file, owner: candidate.owner, pids: owners.isEmpty ? pids : [candidate.owner])
        }
    }

    private mutating func addCodex(_ url: URL, file: AgentFile, owner: pid_t, pids: [pid_t]) {
        paths.insert(url.path)
        guard let thread = codexThread(url), !thread.isSubagent else { return }
        let quiet = memory.quiet(url.path, size: file.size, modified: file.modified, now: now)
        guard let log = CodexLog.read(url, size: file.size, dates: dates, knowsStart: memory.codexTurnStart[url.path] != nil) else {
            idle += 1
            return
        }
        if let policy = log.policy { memory.codexPolicy[url.path] = policy }
        let policy = log.policy ?? memory.codexPolicy[url.path]

        var state = log.state
        var since = log.since
        if log.state != .working {
            memory.codexTurnStart[url.path] = nil
        } else if log.reachedStart {
            memory.codexTurnStart[url.path] = log.since
        } else if let start = memory.codexTurnStart[url.path] {
            since = start
        }
        var activity = log.activity
        switch log.state {
        case .done, .needsYou:
            guard now.timeIntervalSince(log.since) < Self.stale else {
                idle += 1
                return
            }
        case .working:
            guard quiet < Self.stale else {
                idle += 1
                return
            }
            if let call = log.pendingCall {
                if CodexLog.asksUser.contains(call.name) {
                    state = .needsYou
                    since = call.at
                    activity = "Question"
                } else if let policy, policy != "never", CodexLog.mayAsk(call.name), quiet >= 5,
                          !pids.contains(where: { processes.hasDescendant(of: $0, startedAfter: call.at.addingTimeInterval(-1)) }) {
                    state = .needsYou
                    since = call.at
                    activity = "Approval · \(call.label)"
                }
            }
        }

        sessions.append(AgentSession(
            id: "codex:\(thread.id)",
            tool: .codex,
            cwd: log.cwd ?? thread.cwd,
            name: nil,
            state: state,
            since: since,
            activity: activity ?? (state == .working ? "Thinking" : state.title),
            pid: owner,
            log: url,
            hostBundleID: hostBundle(of: owner),
            hostAncestors: processes.ancestors(of: owner)
        ))
    }

    /// The rollout's first line, `session_meta`: thread `id`, `cwd`, and
    /// `source.subagent` for threads Codex spawned itself (shown through
    /// their parent instead). About 23 KB per file here.
    private mutating func codexThread(_ url: URL) -> AgentScanMemory.CodexThread? {
        if let known = memory.codexThreads[url.path] { return known }
        guard let line = AgentLogTail.firstLine(url, limit: 1 << 20),
              let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              object["type"] as? String == "session_meta",
              let payload = object["payload"] as? [String: Any],
              let id = payload["id"] as? String
        else { return nil }
        let source = payload["source"] as? [String: Any]
        let thread = AgentScanMemory.CodexThread(
            id: id,
            cwd: payload["cwd"] as? String ?? "",
            isSubagent: source?["subagent"] != nil
        )
        memory.codexThreads[url.path] = thread
        return thread
    }

    // MARK: omp

    /// omp (verified against 18.12.3 on this Mac). An interactive session is
    /// a process named `omp` whose parent is not one; its helpers (`omp
    /// __omp_worker_daemon_broker`, `__omp_worker_lsp_mux`, …) are children
    /// of it or of each other. omp records the session it runs in each
    /// terminal at `~/.omp/agent/terminal-sessions/<tty>` ("ttys001"): the
    /// cwd on the first line, the session log
    /// `~/.omp/agent/sessions/<cwd slug>/<time>_<id>.jsonl` on the second,
    /// rewritten when the session changes (a new session after a plan, a
    /// resume). The tty is the one on the process's stdin. Logs are not held
    /// open, so when the record is missing or older than the process the
    /// newest log in the cwd's folder is used instead.
    private mutating func scanOmp() {
        let root = home.appending(path: ".omp/agent", directoryHint: .isDirectory)
        for (pid, entry) in processes.entries where entry.name == "omp" {
            guard processes.entries[entry.ppid]?.name != "omp",
                  !AgentProcessTable.isOmpHelper(pid),
                  let session = ompSession(pid: pid, started: entry.start, root: root)
            else { continue }
            addOmp(session.log, cwd: session.cwd, pid: pid)
        }
    }

    private func ompSession(pid: pid_t, started: Date, root: URL) -> (log: URL, cwd: String)? {
        let manager = FileManager.default
        let sessions = root.appending(path: "sessions", directoryHint: .isDirectory).path + "/"
        // A log written to since the process started is the one it runs.
        func isCurrent(_ url: URL) -> Bool {
            guard url.path.hasPrefix(sessions), let file = AgentFile(url) else { return false }
            return file.modified >= started.addingTimeInterval(-5)
        }
        if let tty = AgentProcessTable.terminalName(of: pid),
           let text = try? String(contentsOf: root.appending(path: "terminal-sessions/\(tty)"), encoding: .utf8) {
            let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            if lines.count >= 2 {
                let log = URL(fileURLWithPath: lines[1])
                if isCurrent(log) { return (log, lines[0]) }
            }
        }
        // `/Users/me/projects/app` → `-projects-app`.
        let home = self.home.path
        guard let cwd = AgentProcessTable.workingDirectory(of: pid), cwd.hasPrefix(home + "/") else { return nil }
        let slug = String(cwd.dropFirst(home.count)).replacingOccurrences(of: "/", with: "-")
        let folder = root.appending(path: "sessions/\(slug)", directoryHint: .isDirectory)
        let newest = ((try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .filter { $0.pathExtension == "jsonl" }
            .max { lhs, rhs in
                let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left < right
            }
        guard let newest, isCurrent(newest) else { return nil }
        return (newest, cwd)
    }

    private mutating func addOmp(_ url: URL, cwd: String, pid: pid_t) {
        guard let file = AgentFile(url) else { return }
        paths.insert(url.path)
        var quiet = memory.quiet(url.path, size: file.size, modified: file.modified, now: now)
        guard let log = OmpLog.read(url, size: file.size, dates: dates) else {
            idle += 1
            return
        }
        switch log.state {
        case .needsYou:
            // An open question stays urgent however long it waits.
            break
        case .done:
            guard now.timeIntervalSince(log.since) < Self.stale else {
                idle += 1
                return
            }
        case .working:
            // Subagents write to `<log name>/<agent>.jsonl` while the main
            // log only waits on their tool call.
            if quiet >= Self.stale, let latest = Self.newestModification(in: url.deletingPathExtension()) {
                quiet = min(quiet, now.timeIntervalSince(latest))
            }
            guard quiet < Self.stale else {
                idle += 1
                return
            }
        }
        // `<time>_<session id>.jsonl`.
        let stem = url.deletingPathExtension().lastPathComponent
        let id = stem.split(separator: "_").last.map(String.init) ?? stem
        sessions.append(AgentSession(
            id: "omp:\(id)",
            tool: .omp,
            cwd: cwd,
            name: OmpLog.title(url),
            state: log.state,
            since: log.since,
            activity: log.activity ?? (log.state == .working ? "Thinking" : log.state.title),
            pid: pid,
            log: url,
            hostBundleID: hostBundle(of: pid),
            hostAncestors: processes.ancestors(of: pid)
        ))
    }

    private static func newestModification(in folder: URL) -> Date? {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        return files.compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }.max()
    }

    private mutating func hostBundle(of pid: pid_t) -> String? {
        if let known = memory.hostBundles[pid] { return known.isEmpty ? nil : known }
        let found = AgentProcessTable.bundleIdentifier(of: pid)
        memory.hostBundles[pid] = found ?? ""
        return found
    }
}

/// `~/.claude/sessions/<pid>.json`.
private struct ClaudeRegistration {
    var pid: pid_t
    var sessionId: String
    var cwd: String
    var name: String?
    /// "interactive", "bg", "daemon", "daemon-worker".
    var kind: String?
    /// "busy", "shell", "idle", "waiting".
    var status: String?
    var waitingFor: String?
    var statusUpdatedAt: Date?
    var startedAt: Date?
    var logPath: String?

    init?(data: Data, pid: pid_t) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (object["pid"] as? NSNumber)?.int32Value == pid,
              let sessionId = object["sessionId"] as? String,
              let cwd = object["cwd"] as? String
        else { return nil }
        func date(_ key: String) -> Date? {
            (object[key] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
        }
        self.pid = pid
        self.sessionId = sessionId
        self.cwd = cwd
        name = object["name"] as? String
        kind = object["kind"] as? String
        status = object["status"] as? String
        waitingFor = object["waitingFor"] as? String
        statusUpdatedAt = date("statusUpdatedAt")
        startedAt = date("startedAt")
        logPath = object["logPath"] as? String
    }
}

private struct AgentFile {
    var size: UInt64
    var modified: Date

    init(size: UInt64, modified: Date) {
        self.size = size
        self.modified = modified
    }

    init?(_ url: URL) {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let size = values.fileSize
        else { return nil }
        self.size = UInt64(size)
        modified = values.contentModificationDate ?? .distantPast
    }
}

// MARK: - Claude transcript

/// What the end of a Claude Code transcript says.
///
/// Entries that matter (all others — `attachment`, `last-prompt`,
/// `ai-title`, `mode`, `permission-mode`, `api-request*`, `queue-operation`,
/// `file-history-*` — are bookkeeping and skipped):
/// - `system` with `subtype` `turn_duration` (and `durationMs`), preceded by
///   `stop_hook_summary`: the turn ended. In this Mac's logs the entry
///   before `turn_duration` is an assistant `end_turn` 1,521 times of 1,539
///   (`stop_sequence` 9, a user entry 9).
/// - `assistant` with `message.stop_reason` `end_turn` / `stop_sequence` /
///   `max_tokens`: done. `tool_use`: a `content` block of type `tool_use`
///   (`id`, `name`, `input`) waits for its `tool_result`. Each block is its
///   own entry; 2.1.30x copies the final `stop_reason` onto every block,
///   older versions leave it `null` on all but the last.
/// - `user` whose `content` holds `tool_result` blocks (`tool_use_id`):
///   the model is working on the result. A text prompt: working.
///   `[Request interrupted by user]` / `… for tool use]`: stopped.
///   `isMeta` entries and `<command-name>` / `<local-command-…>` /
///   `<bash-…>` texts are local commands and caveats, not prompts.
struct ClaudeLog {
    /// `.working` or `.done`.
    var state: AgentSession.State
    /// The newest entry that decided `state`.
    var at: Date
    /// Working: the prompt that started the turn (or the oldest entry read).
    /// Done: the turn's end.
    var since: Date
    var activity: String?
    var pendingTool: (name: String, at: Date)?

    /// Tools that are a question to the user by nature.
    static let asksUser: Set<String> = ["AskUserQuestion"]

    /// Tools that run long inside the `claude` process (subagents, network,
    /// MCP servers), where "no new child process" says nothing.
    private static let inProcess: Set<String> = [
        "Agent", "Task", "WebFetch", "WebSearch", "Monitor", "SendMessage", "TaskOutput", "TaskStop", "Skill", "ToolSearch",
    ]

    static func mayPrompt(_ tool: String) -> Bool {
        !inProcess.contains(tool) && !tool.hasPrefix("mcp__")
    }

    /// "Bash · permission prompt", "Question", "Plan approval".
    static func waitingText(_ waitingFor: String?, pendingTool: String?) -> String {
        switch pendingTool {
        case "AskUserQuestion": return "Question"
        case "ExitPlanMode": return "Plan approval"
        default: break
        }
        let reason = waitingFor.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? "Waiting for you"
        guard let pendingTool, reason == "Permission prompt" else { return reason }
        return "\(pendingTool) · permission"
    }

    private static let markers = [#""type":"assistant""#, #""type":"user""#, #""type":"system""#].map { Data($0.utf8) }

    static func read(_ url: URL, size: UInt64, dates: AIUsageDates) -> ClaudeLog? {
        AgentLogTail.read(url, size: size) { lines, _ in parse(lines, dates: dates) }
    }

    /// Walks the lines newest first. `nil` when none of them decides a state.
    private static func parse(_ lines: [Data], dates: AIUsageDates) -> ClaudeLog? {
        var log: ClaudeLog?
        var resolved = Set<String>()
        var oldest: Date?
        for line in lines.reversed() {
            guard markers.contains(where: { line.range(of: $0) != nil }),
                  let entry = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let type = entry["type"] as? String,
                  entry["isSidechain"] as? Bool != true,
                  let at = (entry["timestamp"] as? String).flatMap(dates.date)
            else { continue }
            let message = entry["message"] as? [String: Any]
            let blocks = message?["content"] as? [[String: Any]] ?? []
            switch type {
            case "system":
                guard log == nil else { continue }
                switch entry["subtype"] as? String {
                case "turn_duration", "stop_hook_summary", "local_command":
                    log = ClaudeLog(state: .done, at: at, since: at)
                default:
                    continue
                }
            case "user":
                oldest = at
                let results = blocks.filter { $0["type"] as? String == "tool_result" }
                if !results.isEmpty {
                    resolved.formUnion(results.compactMap { $0["tool_use_id"] as? String })
                    if log == nil { log = ClaudeLog(state: .working, at: at, since: at) }
                    continue
                }
                guard entry["isMeta"] as? Bool != true else { continue }
                let text = (message?["content"] as? String)
                    ?? blocks.compactMap { $0["text"] as? String }.joined(separator: " ")
                if text.hasPrefix("[Request interrupted") {
                    if log == nil { log = ClaudeLog(state: .done, at: at, since: at, activity: "Interrupted") }
                    if log?.activity != nil { return log }
                    continue
                }
                if text.hasPrefix("<command-name>") || text.hasPrefix("<local-command") || text.hasPrefix("<bash-") {
                    if log == nil { log = ClaudeLog(state: .done, at: at, since: at) }
                    continue
                }
                // The prompt that started the newest turn.
                guard var found = log else { return ClaudeLog(state: .working, at: at, since: at) }
                if found.state == .working { found.since = at }
                return found
            case "assistant":
                oldest = at
                if log == nil {
                    switch message?["stop_reason"] as? String {
                    case "end_turn", "stop_sequence", "max_tokens", "refusal":
                        log = ClaudeLog(state: .done, at: at, since: at)
                    default:
                        var working = ClaudeLog(state: .working, at: at, since: at)
                        let pending = blocks.last { block in
                            block["type"] as? String == "tool_use"
                                && (block["id"] as? String).map { !resolved.contains($0) } == true
                        }
                        if let name = pending?["name"] as? String { working.pendingTool = (name, at) }
                        log = working
                    }
                }
                if log?.activity == nil { log?.activity = activity(of: blocks) }
                if log?.state == .done, log?.activity != nil { return log }
            default:
                continue
            }
        }
        if var found = log, found.state == .working, let oldest {
            found.since = oldest
            return found
        }
        return log
    }

    /// The newest block worth naming: a tool ("Bash · Run the tests") or
    /// the start of a reply.
    private static func activity(of blocks: [[String: Any]]) -> String? {
        for block in blocks.reversed() {
            switch block["type"] as? String {
            case "tool_use":
                guard let name = block["name"] as? String else { continue }
                let input = block["input"] as? [String: Any]
                if let detail = (input?["description"] as? String) ?? (input?["file_path"] as? String).map({ ($0 as NSString).lastPathComponent }) {
                    return AgentText.short("\(name) · \(detail)")
                }
                return name
            case "text":
                if let text = AgentText.short(block["text"] as? String) { return text }
            default:
                continue
            }
        }
        return nil
    }
}

// MARK: - Codex rollout

/// What the end of a Codex rollout says.
///
/// - `event_msg` `task_started`: a turn began (followed by `turn_context`
///   with `cwd` and `approval_policy`: `never` in 1,143 turns here,
///   `on-request` in 58). `task_complete` (`last_agent_message`): done.
///   `turn_aborted` (`reason: "interrupted"`): stopped.
/// - `response_item` `function_call` / `custom_tool_call` (`call_id`,
///   `name`) pair with `function_call_output` / `custom_tool_call_output`.
///   A pending `request_user_input` is a question to the user. A pending
///   command (`exec`, `shell`, …) under a policy other than `never` may sit
///   at an approval prompt: in `on-request` sessions 8 % of `exec` calls ran
///   past 5 s versus 0 % under `never`. It counts as needing the user only
///   when the log is quiet for 5 s and `codex` has started no child since
///   the call.
struct CodexLog {
    struct Call {
        var name: String
        /// The command for shell calls ("git status"), else the tool name.
        var label: String
        var at: Date
    }

    var state: AgentSession.State
    var since: Date
    var activity: String?
    var pendingCall: Call?
    var policy: String?
    var cwd: String?
    /// False when the turn's `task_started` lies before the bytes read; then
    /// `since` is only the oldest entry read.
    var reachedStart = true

    static let asksUser: Set<String> = ["request_user_input", "request_user_input_async"]
    private static let commands: Set<String> = ["exec", "js", "shell", "exec_command", "local_shell", "apply_patch"]

    static func mayAsk(_ tool: String) -> Bool { commands.contains(tool) }

    /// Reads back up to 4 MB to find the turn's start, unless the caller
    /// already knows it (`knowsStart`); long Codex turns pass that easily.
    static func read(_ url: URL, size: UInt64, dates: AIUsageDates, knowsStart: Bool) -> CodexLog? {
        AgentLogTail.read(url, size: size) { lines, last in parse(lines, dates: dates, settle: last || knowsStart) }
    }

    private static let markers = [#""type":"event_msg""#, #""type":"response_item""#, #""type":"turn_context""#].map { Data($0.utf8) }

    private static func parse(_ lines: [Data], dates: AIUsageDates, settle: Bool) -> CodexLog? {
        var outputs = Set<String>()
        var sawCall = false
        var pending: Call?
        var activity: String?
        var policy: String?
        var cwd: String?
        var oldest: Date?
        for line in lines.reversed() {
            guard markers.contains(where: { line.range(of: $0) != nil }),
                  let entry = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let type = entry["type"] as? String,
                  let payload = entry["payload"] as? [String: Any],
                  let at = (entry["timestamp"] as? String).flatMap(dates.date)
            else { continue }
            let kind = payload["type"] as? String
            switch type {
            case "event_msg":
                switch kind {
                case "task_complete":
                    let message = AgentText.short(payload["last_agent_message"] as? String)
                    return CodexLog(state: .done, since: at, activity: message ?? activity, policy: policy, cwd: cwd)
                case "turn_aborted":
                    return CodexLog(state: .done, since: at, activity: "Interrupted", policy: policy, cwd: cwd)
                case "task_started":
                    return CodexLog(state: .working, since: at, activity: activity, pendingCall: pending, policy: policy, cwd: cwd)
                default:
                    continue
                }
            case "turn_context":
                if policy == nil { policy = payload["approval_policy"] as? String }
                if cwd == nil { cwd = payload["cwd"] as? String }
            case "response_item":
                oldest = at
                switch kind {
                case "function_call_output", "custom_tool_call_output":
                    if let id = payload["call_id"] as? String { outputs.insert(id) }
                case "function_call", "custom_tool_call":
                    let name = payload["name"] as? String ?? "tool"
                    let label = command(payload).map { "$ \($0)" } ?? name
                    if activity == nil { activity = AgentText.short(label) }
                    if !sawCall {
                        sawCall = true
                        if let id = payload["call_id"] as? String, !outputs.contains(id) {
                            pending = Call(name: name, label: AgentText.short(label) ?? name, at: at)
                        }
                    }
                case "message":
                    if activity == nil, payload["role"] as? String == "assistant",
                       let content = payload["content"] as? [[String: Any]] {
                        activity = AgentText.short(content.compactMap { $0["text"] as? String }.joined(separator: " "))
                    }
                case "reasoning":
                    if activity == nil { activity = "Thinking" }
                default:
                    continue
                }
            default:
                continue
            }
        }
        // Deep inside a long turn: its start is further back than we read.
        guard let oldest, settle else { return nil }
        return CodexLog(
            state: .working, since: oldest, activity: activity, pendingCall: pending, policy: policy, cwd: cwd,
            reachedStart: false
        )
    }

    /// The shell command of a call: `arguments.cmd` / `arguments.command`
    /// for function calls; `cmd:"…"` inside the script of a code-mode
    /// `exec` call (`tools.exec_command({cmd:"git status"})`).
    private static func command(_ payload: [String: Any]) -> String? {
        if let arguments = (payload["arguments"] as? String)?.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: arguments) as? [String: Any] {
            if let cmd = object["cmd"] as? String { return cmd }
            if let command = object["command"] as? [String] { return command.joined(separator: " ") }
            if let command = object["command"] as? String { return command }
        }
        guard let input = payload["input"] as? String,
              let start = input.range(of: "cmd:\"")?.upperBound
        else { return nil }
        var result = ""
        var escaped = false
        for character in input[start...].prefix(120) {
            if escaped {
                result.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "\"" {
                break
            } else {
                result.append(character)
            }
        }
        return result.isEmpty ? nil : result
    }
}

// MARK: - omp session

/// What the end of an omp session log says.
///
/// Entries (18.12.3): `message` with `message.role` `user` / `developer`
/// (a prompt), `assistant` (`stopReason` `toolUse`, `stop`, `aborted`,
/// `error`; `content` blocks `thinking`, `text`, `toolCall` with `id`,
/// `name`, `intent`) and `toolResult` (`toolCallId`). omp writes an
/// assistant message only once it is complete, so a log ending in a prompt
/// or a tool result means the model is answering. A `toolCall` named
/// `ask` without its result is a question on screen; any other pending
/// call is a tool at work. `custom` entries are bookkeeping
/// (`tool_execution_start`, `todo_hud_state`), except `session_exit`.
struct OmpLog {
    var state: AgentSession.State
    /// Working: the prompt that started the turn. Needs you: when the
    /// question was asked. Done: the turn's end.
    var since: Date
    var activity: String?

    private static let markers = [#""type":"message""#, #""customType":"session_exit""#].map { Data($0.utf8) }

    static func read(_ url: URL, size: UInt64, dates: AIUsageDates) -> OmpLog? {
        AgentLogTail.read(url, size: size) { lines, last in parse(lines, dates: dates, settle: last) }
    }

    /// The session title from the log's first line (`{"type":"title"}`).
    static func title(_ url: URL) -> String? {
        guard let line = AgentLogTail.firstLine(url, limit: 64 << 10),
              let entry = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              entry["type"] as? String == "title"
        else { return nil }
        return (entry["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Walks the lines newest first. `nil` while a working turn's prompt
    /// lies before the bytes read and `settle` is false.
    private static func parse(_ lines: [Data], dates: AIUsageDates, settle: Bool) -> OmpLog? {
        var log: OmpLog?
        var resolved = Set<String>()
        var oldest: Date?
        for line in lines.reversed() {
            guard markers.contains(where: { line.range(of: $0) != nil }),
                  let entry = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let at = (entry["timestamp"] as? String).flatMap(dates.date)
            else { continue }
            if entry["type"] as? String == "custom" {
                // The session ended; its process is on its way out.
                if log == nil, entry["customType"] as? String == "session_exit" { return nil }
                continue
            }
            guard let message = entry["message"] as? [String: Any], let role = message["role"] as? String else { continue }
            let blocks = message["content"] as? [[String: Any]] ?? []
            switch role {
            case "toolResult":
                oldest = at
                if let id = message["toolCallId"] as? String { resolved.insert(id) }
                if log == nil { log = OmpLog(state: .working, since: at) }
            case "assistant":
                oldest = at
                if log == nil {
                    switch message["stopReason"] as? String {
                    case "toolUse":
                        let pending = blocks.last { block in
                            block["type"] as? String == "toolCall"
                                && (block["id"] as? String).map { !resolved.contains($0) } == true
                        }
                        if pending?["name"] as? String == "ask" {
                            let intent = AgentText.short(pending?["intent"] as? String)
                            return OmpLog(state: .needsYou, since: at, activity: intent.map { "Question · \($0)" } ?? "Question")
                        }
                        log = OmpLog(state: .working, since: at)
                    case "aborted":
                        log = OmpLog(state: .done, since: at, activity: "Interrupted")
                    case "error":
                        log = OmpLog(state: .done, since: at, activity: AgentText.short(message["errorMessage"] as? String) ?? "Error")
                    default:
                        log = OmpLog(state: .done, since: at)
                    }
                }
                if log?.activity == nil { log?.activity = activity(of: blocks) }
                if log?.state == .done, log?.activity != nil { return log }
            case "user", "developer":
                // The prompt that started the newest turn.
                guard var found = log else { return OmpLog(state: .working, since: at, activity: "Thinking") }
                if found.state == .working { found.since = at }
                return found
            default:
                continue
            }
        }
        guard var found = log else { return nil }
        if found.state == .working {
            guard settle else { return nil }
            found.since = oldest ?? found.since
        }
        return found
    }

    /// The newest block worth naming: a tool with its intent ("bash ·
    /// Building release app") or the start of a reply.
    private static func activity(of blocks: [[String: Any]]) -> String? {
        for block in blocks.reversed() {
            switch block["type"] as? String {
            case "toolCall":
                guard let name = block["name"] as? String else { continue }
                if let intent = block["intent"] as? String, !intent.isEmpty {
                    return AgentText.short("\(name) · \(intent)")
                }
                return name
            case "text":
                if let text = AgentText.short(block["text"] as? String) { return text }
            default:
                continue
            }
        }
        return nil
    }
}

// MARK: - Helpers

enum AgentText {
    /// One line of plain text, at most 40 characters. Replies are Markdown:
    /// links keep their text, emphasis and code marks and heading hashes go.
    static func short(_ text: String?) -> String? {
        guard let text else { return nil }
        let plain = String(text.prefix(1_000))
            .replacing(/\[([^\]\n]*)\]\([^)\n]*\)/) { match in match.1 }
            .replacing(/\*\*|__|`/, with: "")
            .replacing(/(?m)^#+\s*/, with: "")
        let line = plain.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !line.isEmpty else { return nil }
        return line.count > 40 ? String(line.prefix(39)) + "…" : line
    }
}

enum AgentLogTail {
    /// Complete lines from the last `bytes` of the file, oldest first.
    static func lines(_ url: URL, size: UInt64, bytes: UInt64) -> (lines: [Data], whole: Bool)? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let start = size > bytes ? size - bytes : 0
        guard (try? handle.seek(toOffset: start)) != nil,
              let data = try? handle.read(upToCount: Int(size - start))
        else { return nil }
        var lines = data.split(separator: 0x0A, omittingEmptySubsequences: true)
        // The first line of a window that starts mid-file is cut.
        if start > 0, !lines.isEmpty { lines.removeFirst() }
        return (lines, start == 0)
    }

    /// Reads the last 64 KB, then 512 KB, then 4 MB (single transcript lines
    /// reach 1 MB), until `parse` decides.
    static func read<T>(_ url: URL, size: UInt64, parse: ([Data], _ last: Bool) -> T?) -> T? {
        var window: UInt64 = 64 << 10
        while true {
            guard let tail = lines(url, size: size, bytes: window) else { return nil }
            let last = tail.whole || window >= 4 << 20
            if let result = parse(tail.lines, last) { return result }
            if last { return nil }
            window *= 8
        }
    }

    static func firstLine(_ url: URL, limit: Int) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var line = Data()
        while line.count < limit {
            guard let chunk = try? handle.read(upToCount: 64 << 10), !chunk.isEmpty else { return nil }
            if let end = chunk.firstIndex(of: 0x0A) {
                line.append(chunk[chunk.startIndex..<end])
                return line
            }
            line.append(chunk)
        }
        return nil
    }
}

/// A snapshot of every process on the Mac (`sysctl KERN_PROC_ALL`).
struct AgentProcessTable {
    struct Entry {
        var ppid: pid_t
        var start: Date
        /// `p_comm`: "codex"; Claude Code's is its version ("2.1.304").
        var name: String
    }

    var entries: [pid_t: Entry] = [:]

    static func snapshot() -> AgentProcessTable {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return AgentProcessTable() }
        let stride = MemoryLayout<kinfo_proc>.stride
        var buffer = [kinfo_proc](repeating: kinfo_proc(), count: size / stride + 64)
        size = buffer.count * stride
        guard sysctl(&mib, u_int(mib.count), &buffer, &size, nil, 0) == 0 else { return AgentProcessTable() }
        var table = AgentProcessTable()
        for info in buffer.prefix(size / stride) {
            let start = info.kp_proc.p_un.__p_starttime
            let name = withUnsafeBytes(of: info.kp_proc.p_comm) { raw in
                String(decoding: raw.prefix { byte in byte != 0 }, as: UTF8.self)
            }
            table.entries[info.kp_proc.p_pid] = Entry(
                ppid: info.kp_eproc.e_ppid,
                start: Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000),
                name: name
            )
        }
        return table
    }

    func pids(named name: String) -> [pid_t] {
        entries.filter { $0.value.name == name }.map(\.key).sorted()
    }

    func ancestors(of pid: pid_t) -> [pid_t] {
        var chain: [pid_t] = []
        var parent = entries[pid]?.ppid ?? 0
        while parent > 1, chain.count < 16 {
            chain.append(parent)
            parent = entries[parent]?.ppid ?? 0
        }
        return chain
    }

    /// Whether any process started at or after `date` descends from `root`.
    func hasDescendant(of root: pid_t, startedAfter date: Date) -> Bool {
        for (pid, entry) in entries where pid != root && entry.start >= date {
            var parent = entry.ppid
            var hops = 0
            while parent > 1, hops < 16 {
                if parent == root { return true }
                parent = entries[parent]?.ppid ?? 0
                hops += 1
            }
        }
        return false
    }

    /// The binary's path. Claude Code's updater deletes old versions under
    /// running sessions (2.1.296 here), and `proc_pidpath` fails for those;
    /// the exec path the process was started with still names `claude`.
    static func executable(of pid: pid_t) -> String? {
        var buffer = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        if length > 0 { return String(decoding: buffer.prefix(Int(length)), as: UTF8.self) }
        return arguments(of: pid)?.strings.first.map { String(decoding: $0, as: UTF8.self) }
    }

    /// `__CFBundleIdentifier` from the process's environment. Every
    /// `claude` here carries `com.apple.Terminal`; walking parents does not
    /// get there, as Terminal's `login` is not visible to the user.
    static func bundleIdentifier(of pid: pid_t) -> String? {
        guard let process = arguments(of: pid) else { return nil }
        let key = Array("__CFBundleIdentifier=".utf8)
        // The exec path, then argc arguments, then environ.
        for string in process.strings.dropFirst(1 + process.argc) where string.starts(with: key) {
            return String(decoding: string.dropFirst(key.count), as: UTF8.self)
        }
        return nil
    }

    /// `KERN_PROCARGS2`: argc, then the exec path, argv and environ as
    /// NUL-separated strings. Readable for the user's own processes.
    private static func arguments(of pid: pid_t) -> (argc: Int, strings: [ArraySlice<UInt8>])? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size > 4 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, u_int(mib.count), &buffer, &size, nil, 0) == 0, size > 4 else { return nil }
        let argc = buffer.withUnsafeBytes { Int($0.loadUnaligned(as: Int32.self)) }
        return (argc, buffer[4..<size].split(separator: 0, omittingEmptySubsequences: true))
    }

    /// omp's helper processes run the same binary with a `__omp_…` verb.
    static func isOmpHelper(_ pid: pid_t) -> Bool {
        guard let process = arguments(of: pid) else { return false }
        let marker = Array("__omp_".utf8)
        // The exec path, then argv.
        return process.strings.dropFirst().prefix(process.argc).contains { $0.starts(with: marker) }
    }

    /// The terminal on the process's stdin ("ttys001"), else its
    /// controlling terminal.
    static func terminalName(of pid: pid_t) -> String? {
        var info = vnode_fdinfowithpath()
        let size = Int32(MemoryLayout<vnode_fdinfowithpath>.stride)
        if proc_pidfdinfo(pid, 0, PROC_PIDFDVNODEPATHINFO, &info, size) == size {
            let path = withUnsafeBytes(of: info.pvip.vip_path) { raw in
                String(decoding: raw.prefix { byte in byte != 0 }, as: UTF8.self)
            }
            if path.hasPrefix("/dev/tty") { return String(path.dropFirst("/dev/".count)) }
        }
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var process = kinfo_proc()
        var length = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, u_int(mib.count), &process, &length, nil, 0) == 0,
              length > 0,
              process.kp_eproc.e_tdev != -1,
              let name = devname(process.kp_eproc.e_tdev, S_IFCHR)
        else { return nil }
        return String(cString: name)
    }

    /// The process's current directory.
    static func workingDirectory(of pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.stride)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafeBytes(of: info.pvi_cdir.vip_path) { raw in
            String(decoding: raw.prefix { byte in byte != 0 }, as: UTF8.self)
        }
        return path.isEmpty ? nil : path
    }

    /// Paths of the `.jsonl` files under `prefix` the process holds open.
    static func openFiles(of pid: pid_t, under prefix: String) -> [String] {
        let needed = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard needed > 0 else { return [] }
        let stride = MemoryLayout<proc_fdinfo>.stride
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(needed) / stride + 16)
        let filled = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, Int32(fds.count * stride))
        guard filled > 0 else { return [] }
        var paths: [String] = []
        for fd in fds.prefix(Int(filled) / stride) where fd.proc_fdtype == UInt32(PROX_FDTYPE_VNODE) {
            var info = vnode_fdinfowithpath()
            let read = proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDVNODEPATHINFO, &info, Int32(MemoryLayout<vnode_fdinfowithpath>.stride))
            guard read > 0 else { continue }
            let path = withUnsafeBytes(of: info.pvip.vip_path) { raw in
                String(decoding: raw.prefix { byte in byte != 0 }, as: UTF8.self)
            }
            if path.hasPrefix(prefix), path.hasSuffix(".jsonl") { paths.append(path) }
        }
        return paths
    }
}

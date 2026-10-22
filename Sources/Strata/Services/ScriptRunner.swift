import CryptoKit
import Foundation

// MARK: - Output

/// How wide a script tile is drawn.
enum ScriptTileWidth: String, Sendable {
    case small, medium, large
}

/// One context-menu entry a script asks for.
struct ScriptMenuEntry: Sendable, Equatable {
    var title: String
    var url: String?
    /// Re-runs the script instead of opening a link.
    var refreshes = false
}

/// What a script printed, in either of the two formats ``ScriptOutputParser``
/// understands.
struct ScriptOutput: Sendable, Equatable {
    var value: String
    var caption: String?
    /// An SF Symbol name.
    var icon: String?
    /// `0xRRGGBB`.
    var tint: UInt32?
    var sparkline: [Double]?
    /// 0...1, drawn as a ring.
    var progress: Double?
    /// Opened when the tile is clicked; without it a click re-runs the script.
    var url: String?
    var width: ScriptTileWidth?
    var menu: [ScriptMenuEntry] = []
}

struct ScriptOutputError: Error {
    let message: String
}

/// Reads a script's stdout. Two formats:
///
/// - A JSON object: `{"value", "caption"?, "icon"?, "tint"? ("#RRGGBB"),
///   "sparkline"? [Number], "progress"? 0...1, "url"?, "width"?
///   ("small"|"medium"|"large"), "menu"? [{"title", "url"?, "run"?: "refresh"}]}`.
/// - xbar/SwiftBar text: the first line is the value, the second (before
///   `---`) the caption, and lines after `---` become menu items. `| href=URL`
///   makes a line a link (on the first line, the tile's click); `refresh=true`
///   re-runs; other parameters and nested `--` items are ignored.
enum ScriptOutputParser {
    static func parse(_ text: String) throws(ScriptOutputError) -> ScriptOutput {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ScriptOutputError(message: "No output") }
        if trimmed.hasPrefix("{"),
           let data = trimmed.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return try json(object)
        }
        return try xbar(text)
    }

    // MARK: JSON

    private static func json(_ object: [String: Any]) throws(ScriptOutputError) -> ScriptOutput {
        guard let value = string(object["value"]) else {
            throw ScriptOutputError(message: "JSON needs a \"value\"")
        }
        var output = ScriptOutput(value: value)
        output.caption = string(object["caption"])
        output.icon = string(object["icon"]).flatMap { $0.isEmpty ? nil : $0 }
        output.tint = string(object["tint"]).flatMap(rgb)
        if let series = object["sparkline"] as? [Any] {
            let values = series.compactMap { ($0 as? NSNumber)?.doubleValue }
            output.sparkline = values.count > 1 ? values : nil
        }
        if let progress = (object["progress"] as? NSNumber)?.doubleValue, progress.isFinite {
            output.progress = min(max(progress, 0), 1)
        }
        output.url = string(object["url"]).flatMap { $0.isEmpty ? nil : $0 }
        output.width = string(object["width"]).flatMap { ScriptTileWidth(rawValue: $0.lowercased()) }
        if let menu = object["menu"] as? [[String: Any]] {
            output.menu = menu.compactMap { entry in
                guard let title = string(entry["title"]), !title.isEmpty else { return nil }
                return ScriptMenuEntry(
                    title: title,
                    url: string(entry["url"]).flatMap { $0.isEmpty ? nil : $0 },
                    refreshes: string(entry["run"]) == "refresh"
                )
            }
        }
        return output
    }

    private static func string(_ any: Any?) -> String? {
        switch any {
        case let text as String: text
        case let number as NSNumber: number.stringValue
        default: nil
        }
    }

    /// `#RRGGBB`, `RRGGBB` or `#RGB`.
    private static func rgb(_ text: String) -> UInt32? {
        var hex = text.trimmingCharacters(in: .whitespaces)
        if hex.hasPrefix("#") { hex.removeFirst() }
        if hex.count == 3 {
            hex = hex.map { "\($0)\($0)" }.joined()
        }
        guard hex.count == 6 else { return nil }
        return UInt32(hex, radix: 16)
    }

    // MARK: xbar text

    private static func xbar(_ text: String) throws(ScriptOutputError) -> ScriptOutput {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false)
        var header: [Substring] = []
        var body: [Substring] = []
        var inBody = false
        for line in lines {
            if !inBody, line.trimmingCharacters(in: .whitespaces) == "---" {
                inBody = true
            } else if inBody {
                body.append(line)
            } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                header.append(line)
            }
        }
        guard let first = header.first else { throw ScriptOutputError(message: "No output") }

        let (value, params) = split(first)
        var output = ScriptOutput(value: value)
        output.url = params["href"]
        if header.count > 1 {
            output.caption = split(header[1]).title
        }

        var menu: [ScriptMenuEntry] = []
        for line in body {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Separators and nested levels ("--Sub item") are not shown.
            if trimmed.isEmpty || line.hasPrefix("--") { continue }
            let (title, params) = split(line)
            guard !title.isEmpty else { continue }
            menu.append(ScriptMenuEntry(title: title, url: params["href"], refreshes: params["refresh"] == "true"))
        }
        output.menu = menu
        return output
    }

    /// `"Title | href=https://… color=red"` → title and parameters.
    private static func split(_ line: Substring) -> (title: String, params: [String: String]) {
        guard let bar = line.firstIndex(of: "|") else {
            return (line.trimmingCharacters(in: .whitespaces), [:])
        }
        let title = line[..<bar].trimmingCharacters(in: .whitespaces)
        return (title, parameters(line[line.index(after: bar)...]))
    }

    /// `key=value key2='quoted value'` pairs.
    private static func parameters(_ text: Substring) -> [String: String] {
        var params: [String: String] = [:]
        var index = text.startIndex
        func skipSpaces() {
            while index < text.endIndex, text[index].isWhitespace { index = text.index(after: index) }
        }
        while true {
            skipSpaces()
            guard index < text.endIndex else { break }
            let keyStart = index
            while index < text.endIndex, text[index] != "=", !text[index].isWhitespace {
                index = text.index(after: index)
            }
            let key = String(text[keyStart..<index]).lowercased()
            guard index < text.endIndex, text[index] == "=" else { continue }
            index = text.index(after: index)
            var value = ""
            if index < text.endIndex, text[index] == "\"" || text[index] == "'" {
                let quote = text[index]
                index = text.index(after: index)
                let valueStart = index
                while index < text.endIndex, text[index] != quote { index = text.index(after: index) }
                value = String(text[valueStart..<index])
                if index < text.endIndex { index = text.index(after: index) }
            } else {
                let valueStart = index
                while index < text.endIndex, !text[index].isWhitespace { index = text.index(after: index) }
                value = String(text[valueStart..<index])
            }
            if !key.isEmpty { params[key] = value }
        }
        return params
    }
}

// MARK: - Files

/// A script found in the Scripts folder.
struct ScriptFileInfo: Sendable, Equatable, Identifiable {
    let filename: String
    let url: URL
    /// SHA-256 of the contents when they were last read; `nil` if unreadable.
    var hash: String?

    var id: String { filename }
    var title: String { ScriptFiles.title(of: filename) }
    var interval: TimeInterval { ScriptFiles.interval(of: filename) }
}

/// The start of a script, shown before the user approves it.
struct ScriptPreview: Sendable {
    /// SHA-256 of the whole file as it was read for this preview.
    let hash: String
    let text: String
    let isTruncated: Bool
}

/// The Scripts folder and the xbar naming convention
/// (`name.<interval>.<ext>`, e.g. `hello.5s.sh`).
enum ScriptFiles {
    static let defaultInterval: TimeInterval = 60

    static var folder: URL {
        AppPaths.support.appending(path: "Scripts", directoryHint: .isDirectory)
    }

    /// `"hello.5s.sh"` → `"hello"`.
    static func title(of filename: String) -> String {
        let parts = filename.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count >= 3, seconds(parts[parts.count - 2]) != nil {
            return parts.dropLast(2).joined(separator: ".")
        }
        if parts.count >= 2, !parts[0].isEmpty {
            return parts.dropLast().joined(separator: ".")
        }
        return filename
    }

    /// The longest interval a filename may ask for.
    static let maxInterval: TimeInterval = 7 * 86400

    /// `"hello.5s.sh"` → 5. Unmarked scripts run every minute, and so do
    /// scripts whose marker is outside 1 s … 7 days (`x.0s.sh`, `x.30d.sh`).
    static func interval(of filename: String) -> TimeInterval {
        let parts = filename.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 3, let seconds = seconds(parts[parts.count - 2]),
              (1...Int(maxInterval)).contains(seconds) else { return defaultInterval }
        return TimeInterval(seconds)
    }

    /// `"10s"`, `"5m"`, `"1h"`, `"1d"`. A count too large to multiply out
    /// reads as `Int.max`, which `interval(of:)` rejects as out of range.
    private static func seconds(_ token: Substring) -> Int? {
        guard let unit = token.last, let count = Int(token.dropLast()), count >= 0 else { return nil }
        let factor: Int
        switch unit {
        case "s": factor = 1
        case "m": factor = 60
        case "h": factor = 3600
        case "d": factor = 86400
        default: return nil
        }
        let (product, overflow) = count.multipliedReportingOverflow(by: factor)
        return overflow ? .max : product
    }

    /// "5s", "1m", "2h", "1d".
    static func intervalLabel(_ interval: TimeInterval) -> String {
        let seconds = Int(min(max(interval.rounded(), 1), maxInterval))
        if seconds % 86400 == 0 { return "\(seconds / 86400)d" }
        if seconds % 3600 == 0 { return "\(seconds / 3600)h" }
        if seconds % 60 == 0 { return "\(seconds / 60)m" }
        return "\(seconds)s"
    }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Executable, non-hidden files in the folder, by name. Blocking: call
    /// off the main actor.
    static func scan(createFolder: Bool) -> [ScriptFileInfo] {
        let manager = FileManager.default
        let directory = Self.folder
        if createFolder {
            try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        guard let urls = try? manager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else { return [] }
        return urls.compactMap { url -> ScriptFileInfo? in
            var isDirectory: ObjCBool = false
            guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue,
                  manager.isExecutableFile(atPath: url.path) else { return nil }
            let digest = (try? Data(contentsOf: url)).map(Self.hash)
            return ScriptFileInfo(filename: url.lastPathComponent, url: url, hash: digest)
        }
        .sorted { $0.filename.localizedStandardCompare($1.filename) == .orderedAscending }
    }

    /// The first `lines` lines and the hash of the whole file, from one read.
    static func preview(_ url: URL, lines: Int = 20) -> ScriptPreview? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let text = String(decoding: data, as: UTF8.self)
        let all = text.split(separator: "\n", omittingEmptySubsequences: false)
        let shown = all.prefix(lines).joined(separator: "\n")
        let truncated = all.count > lines && !all.dropFirst(lines).allSatisfy { $0.isEmpty }
        return ScriptPreview(hash: hash(data), text: shown, isTruncated: truncated)
    }

    /// Writes the example scripts that are not in the folder yet, mode 755.
    /// Returns how many were added. Blocking: call off the main actor.
    static func installExamples() -> Int {
        let manager = FileManager.default
        let directory = Self.folder
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        var added = 0
        for (name, source) in ScriptExamples.all {
            let url = directory.appending(path: name)
            guard !manager.fileExists(atPath: url.path) else { continue }
            do {
                try Data(source.utf8).write(to: url, options: .withoutOverwriting)
                try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
                added += 1
            } catch {
                NSLog("Strata: couldn't write example script %@: %@", name, String(describing: error))
            }
        }
        return added
    }
}

/// Starter scripts for "Add Example Scripts". They are read-only and start
/// unapproved like any other script.
private enum ScriptExamples {
    static let all: [(String, String)] = [
        ("uptime.1m.sh", uptime),
        ("battery.30s.sh", battery),
        ("git-dirty.5m.sh", gitDirty),
    ]

    static let uptime = #"""
    #!/bin/sh
    # Strata example: plain text output (xbar style).
    # Line 1 is the value, line 2 the caption, lines after --- the menu.
    boot=$(sysctl -n kern.boottime | sed -E 's/^\{ sec = ([0-9]+),.*/\1/')
    now=$(date +%s)
    up=$((now - boot))
    days=$((up / 86400))
    hours=$((up % 86400 / 3600))
    mins=$((up % 3600 / 60))
    if [ "$days" -gt 0 ]; then
      echo "${days}d ${hours}h"
    else
      echo "${hours}h ${mins}m"
    fi
    echo "up · load $(sysctl -n vm.loadavg | awk '{print $2}')"
    echo "---"
    echo "Activity Monitor | href=file:///System/Applications/Utilities/Activity%20Monitor.app"

    """#

    static let battery = #"""
    #!/bin/sh
    # Strata example: JSON output with an icon, a tint, a progress ring
    # and a menu.
    info=$(pmset -g batt)
    pct=$(printf '%s\n' "$info" | grep -Eo '[0-9]+%' | head -n 1 | tr -d '%')
    if [ -z "$pct" ]; then
      echo '{"value": "AC", "caption": "no battery", "icon": "powerplug.fill"}'
      exit 0
    fi
    state=$(printf '%s\n' "$info" | sed -n 2p | awk -F '; ' '{print $2}')
    left=$(printf '%s\n' "$info" | grep -Eo '[0-9]+:[0-9]+ remaining' | cut -d ' ' -f 1)
    [ "$left" = "0:00" ] && left=""
    case "$state" in
      charging|charged|"finishing charge") icon="battery.100percent.bolt" ;;
      *)
        if [ "$pct" -ge 75 ]; then icon="battery.100percent"
        elif [ "$pct" -ge 50 ]; then icon="battery.75percent"
        elif [ "$pct" -ge 25 ]; then icon="battery.50percent"
        elif [ "$pct" -ge 10 ]; then icon="battery.25percent"
        else icon="battery.0percent"
        fi ;;
    esac
    if [ "$pct" -le 20 ]; then tint="#FF453A"; else tint="#30D158"; fi
    caption="$state"
    if [ -n "$left" ]; then caption="$state · $left left"; fi
    progress=$(awk "BEGIN { printf \"%.2f\", $pct / 100 }")
    cat <<EOF
    {"value": "$pct%", "caption": "$caption", "icon": "$icon", "tint": "$tint", "progress": $progress,
     "menu": [{"title": "Battery Settings…", "url": "x-apple.systempreferences:com.apple.Battery-Settings.extension"},
              {"title": "Refresh", "run": "refresh"}]}
    EOF

    """#

    static let gitDirty = #"""
    #!/bin/sh
    # Strata example: counts git repositories under ~/projects with
    # uncommitted changes. Read-only: it only runs `git status`.
    root="$HOME/projects"
    if [ ! -d "$root" ]; then
      echo "No repos"
      echo "~/projects not found"
      exit 0
    fi
    git_bin=$(command -v git)
    if [ -z "$git_bin" ] || { [ "$git_bin" = /usr/bin/git ] && ! xcode-select -p >/dev/null 2>&1; }; then
      echo "No git"
      echo "install Xcode tools"
      exit 0
    fi
    set -f
    IFS='
    '
    total=0
    dirty=0
    list=""
    for git_dir in $(find "$root" -maxdepth 3 -type d -name .git -prune 2>/dev/null); do
      repo=${git_dir%/.git}
      total=$((total + 1))
      if [ -n "$(git --no-optional-locks -C "$repo" status --porcelain 2>/dev/null | head -n 1)" ]; then
        dirty=$((dirty + 1))
        list="$list$repo
    "
      fi
    done
    echo "$dirty dirty"
    echo "of $total repos"
    echo "---"
    printf '%s' "$list" | while IFS= read -r repo; do
      short=${repo#$HOME/}
      echo "$short | href='file://$repo'"
    done

    """#
}

// MARK: - Runner

/// The result of one run.
enum ScriptRun: Sendable {
    case output(ScriptOutput)
    /// The message to show: the first stderr line, a timeout, a bad format.
    case failed(String)
    /// The file no longer matches the approved contents; it did not run.
    case changed(hash: String?)
}

/// Runs approved scripts, one process per run, off the main actor.
///
/// Scripts get a minimal environment (PATH, HOME, USER, TMPDIR, LANG plus
/// `STRATA=1` and `STRATA_TILE_CONTEXT=bar`) and never Strata's tokens.
/// They run in the Scripts folder, are stopped after 10 s (SIGTERM, then
/// SIGKILL), and at most 64 KB of stdout is read.
///
/// What runs is a private copy of the bytes whose hash was checked, never
/// the file in the Scripts folder, so swapping the file between the check
/// and the launch cannot run unapproved code.
actor ScriptRunner {
    static let shared = ScriptRunner()

    static let timeout: TimeInterval = 10
    static let stdoutLimit = 64 * 1024
    static let stderrLimit = 16 * 1024

    private var sweptSnapshots = false

    /// Runs `file` if its contents still hash to `hash`.
    func run(_ file: URL, approvedHash hash: String) async -> ScriptRun {
        guard let data = try? Data(contentsOf: file) else { return .failed("Couldn't read the script") }
        let current = ScriptFiles.hash(data)
        guard current == hash else { return .changed(hash: current) }

        if !sweptSnapshots {
            sweptSnapshots = true
            ScriptSnapshot.removeAll()
        }
        let snapshot: ScriptSnapshot
        do {
            snapshot = try ScriptSnapshot(data, filename: file.lastPathComponent)
        } catch {
            NSLog("Strata: couldn't stage script %@: %@", file.lastPathComponent, String(describing: error))
            return .failed("Couldn't prepare the script")
        }
        let outcome = await ScriptProcess.execute(snapshot.url, in: file.deletingLastPathComponent())
        snapshot.remove()
        if let launchError = outcome.launchError {
            return .failed(launchError)
        }
        if outcome.timedOut {
            return .failed("Timed out after \(Int(Self.timeout)) s")
        }
        if outcome.status != 0 {
            let stderr = String(decoding: outcome.stderr, as: UTF8.self)
            let line = stderr.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty }
            return .failed(line ?? "Exited with status \(outcome.status)")
        }
        do throws(ScriptOutputError) {
            return .output(try ScriptOutputParser.parse(String(decoding: outcome.stdout, as: UTF8.self)))
        } catch {
            return .failed(error.message)
        }
    }
}

private struct ScriptProcessOutcome: Sendable {
    var status: Int32 = 0
    var stdout = Data()
    var stderr = Data()
    var timedOut = false
    var launchError: String?
}

/// A private, owner-only copy of verified script bytes:
/// `$TMPDIR/Strata-scripts/<uuid>/<original filename>`, mode 0700 for the
/// directories and the file. The original filename (and so its extension and
/// `$0`'s basename) is kept; the kernel reads the shebang from the copy
/// exactly as it would from the original.
private struct ScriptSnapshot {
    struct Failure: Error {
        let call: String
        let code: Int32
    }

    let url: URL
    private let directory: URL

    private static var root: URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appending(path: "Strata-scripts", directoryHint: .isDirectory)
    }

    init(_ data: Data, filename: String) throws(Failure) {
        let root = Self.root
        try Self.ensurePrivateDirectory(root)
        directory = root.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        guard mkdir(directory.path, 0o700) == 0 else { throw Failure(call: "mkdir", code: errno) }
        url = directory.appending(path: filename)

        let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o700)
        guard fd >= 0 else {
            let code = errno
            rmdir(directory.path)
            throw Failure(call: "open", code: code)
        }
        var failure: Failure?
        data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let written = write(fd, buffer.baseAddress! + offset, buffer.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    failure = Failure(call: "write", code: errno)
                    return
                }
                offset += written
            }
        }
        if failure == nil, fchmod(fd, 0o700) != 0 {
            failure = Failure(call: "fchmod", code: errno)
        }
        close(fd)
        if let failure {
            remove()
            throw failure
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Copies left behind by a crash.
    static func removeAll() {
        try? FileManager.default.removeItem(at: root)
    }

    /// Creates `root` as 0700, or accepts an existing real directory owned by
    /// this user (never a symlink) and tightens it to 0700.
    private static func ensurePrivateDirectory(_ root: URL) throws(Failure) {
        if mkdir(root.path, 0o700) != 0, errno != EEXIST {
            throw Failure(call: "mkdir", code: errno)
        }
        var info = stat()
        guard lstat(root.path, &info) == 0 else { throw Failure(call: "lstat", code: errno) }
        guard info.st_mode & S_IFMT == S_IFDIR, info.st_uid == getuid() else {
            throw Failure(call: "lstat", code: EPERM)
        }
        if info.st_mode & 0o777 != 0o700, chmod(root.path, 0o700) != 0 {
            throw Failure(call: "chmod", code: errno)
        }
    }
}

private enum ScriptProcess {
    static var environment: [String: String] {
        let current = ProcessInfo.processInfo.environment
        var env = [
            "PATH": "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
            "USER": NSUserName(),
            "LOGNAME": NSUserName(),
            "LANG": current["LANG"] ?? "en_US.UTF-8",
            "STRATA": "1",
            "STRATA_TILE_CONTEXT": "bar",
        ]
        env["TMPDIR"] = current["TMPDIR"]
        return env
    }

    /// Runs `file` with `directory` (the Scripts folder) as its working
    /// directory.
    static func execute(_ file: URL, in directory: URL) async -> ScriptProcessOutcome {
        let process = Process()
        process.executableURL = file
        process.currentDirectoryURL = directory
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let collector = ScriptProcessCollector(process: process, stdout: stdout, stderr: stderr)
        return await withCheckedContinuation { continuation in
            collector.begin(continuation)
            stdout.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    collector.closed()
                } else {
                    collector.append(data, isError: false)
                }
            }
            stderr.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    collector.closed()
                } else {
                    collector.append(data, isError: true)
                }
            }
            process.terminationHandler = { process in
                collector.exited(process.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                collector.failedToLaunch("Couldn't run: \(error.localizedDescription)")
                return
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + ScriptRunner.timeout) {
                collector.timeoutElapsed()
            }
        }
    }
}

/// Gathers a process's output and exit from the pipe and termination
/// callbacks, and resumes the waiting task once both pipes closed and the
/// process exited (or the timeout gave up on it).
private final class ScriptProcessCollector: @unchecked Sendable {
    private let lock = NSLock()
    private let process: Process
    private let stdoutPipe: Pipe
    private let stderrPipe: Pipe
    private var outcome = ScriptProcessOutcome()
    private var openStreams = 2
    private var exited = false
    private var finished = false
    private var continuation: CheckedContinuation<ScriptProcessOutcome, Never>?

    init(process: Process, stdout: Pipe, stderr: Pipe) {
        self.process = process
        stdoutPipe = stdout
        stderrPipe = stderr
    }

    func begin(_ continuation: CheckedContinuation<ScriptProcessOutcome, Never>) {
        lock.withLock { self.continuation = continuation }
    }

    func append(_ data: Data, isError: Bool) {
        lock.withLock {
            if isError {
                let room = ScriptRunner.stderrLimit - outcome.stderr.count
                if room > 0 { outcome.stderr.append(data.prefix(room)) }
            } else {
                let room = ScriptRunner.stdoutLimit - outcome.stdout.count
                if room > 0 { outcome.stdout.append(data.prefix(room)) }
            }
        }
    }

    func closed() {
        lock.withLock {
            openStreams -= 1
            finishIfDone(force: false)
        }
    }

    func exited(_ status: Int32) {
        lock.withLock {
            outcome.status = status
            exited = true
            finishIfDone(force: false)
        }
    }

    func failedToLaunch(_ message: String) {
        lock.withLock {
            outcome.launchError = message
            finishIfDone(force: true)
        }
        stopReading()
    }

    /// Ten seconds passed: stop the script, then give up on its pipes (a
    /// child it left behind may hold them open).
    func timeoutElapsed() {
        let running: Bool = lock.withLock {
            guard !finished else { return false }
            if process.isRunning { outcome.timedOut = true }
            return true
        }
        guard running else { return }
        if process.isRunning { process.terminate() }
        let pid = process.processIdentifier
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
            if self.process.isRunning { kill(pid, SIGKILL) }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
                self.lock.withLock { self.finishIfDone(force: true) }
                self.stopReading()
            }
        }
    }

    private func stopReading() {
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
    }

    /// Call with `lock` held.
    private func finishIfDone(force: Bool) {
        guard !finished, force || (exited && openStreams <= 0), let continuation else { return }
        finished = true
        self.continuation = nil
        continuation.resume(returning: outcome)
    }
}

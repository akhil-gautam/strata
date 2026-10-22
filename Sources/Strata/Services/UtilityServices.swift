import AppKit
import Foundation
import Observation

/// Carries a value across a concurrency boundary that the compiler cannot
/// prove is safe.
struct UncheckedBox<T>: @unchecked Sendable {
    let value: T
}

// MARK: - Files

/// Recent downloads.
@MainActor
@Observable
final class FilesService {
    static let shared = FilesService()

    struct Entry: Identifiable, Equatable {
        /// The path is the identity: a fresh UUID would make every refresh
        /// look like a change and re-trigger the tiles that read it.
        var id: String { url.path }
        let url: URL
        let modified: Date
        let size: Int64

        static func == (lhs: Entry, rhs: Entry) -> Bool {
            lhs.url == rhs.url && lhs.modified == rhs.modified && lhs.size == rhs.size
        }
    }

    private(set) var downloads: [Entry] = []
    /// False until the user asks for the protected folders.
    private(set) var isLoaded = false
    private var lastRefresh: Date?

    /// Reading ~/Downloads raises a macOS privacy prompt, so the scan only
    /// happens when the user asks for it.
    func loadProtectedFolders() {
        refresh(force: true)
        isLoaded = true
    }

    func refresh(force: Bool = false) {
        guard force || isLoaded else { return }
        if let lastRefresh, Date().timeIntervalSince(lastRefresh) < 10 {
            return
        }
        lastRefresh = Date()

        let downloadDirectory = FileManager.default
            .homeDirectoryForCurrentUser
            .appending(path: "Downloads", directoryHint: .isDirectory)

        // Only publish a change: rewriting an equal array would re-render
        // every tile that reads it, in a loop.
        let newDownloads = entries(in: downloadDirectory, limit: 8)
        if newDownloads != downloads {
            downloads = newDownloads
        }
    }

    private func entries(in directory: URL, limit: Int) -> [Entry] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey]
        guard
            let urls = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            )
        else { return [] }

        return urls
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true }
            .compactMap { url -> Entry? in
                let values = try? url.resourceValues(forKeys: Set(keys))
                return Entry(
                    url: url,
                    modified: values?.contentModificationDate ?? .distantPast,
                    size: Int64(values?.fileSize ?? 0)
                )
            }
            .sorted { $0.modified > $1.modified }
            .prefix(limit)
            .map { $0 }
    }
}

// MARK: - Bookmarks

/// Saved links.
@MainActor
@Observable
final class BookmarkStore {
    static let shared = BookmarkStore()

    struct Bookmark: Identifiable, Codable, Hashable {
        let id: UUID
        var title: String
        var url: String

        init(id: UUID = UUID(), title: String, url: String) {
            self.id = id
            self.title = title
            self.url = url
        }
    }

    private(set) var bookmarks: [Bookmark] = []

    init() {
        load()
    }

    func add(title: String, url: String) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let normalized = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let bookmark = Bookmark(
            title: name.isEmpty ? (URL(string: normalized)?.host ?? normalized) : name,
            url: normalized
        )
        bookmarks.insert(bookmark, at: 0)
        if bookmarks.count > 20 {
            bookmarks.removeLast(bookmarks.count - 20)
        }
        save()
    }

    func remove(_ bookmark: Bookmark) {
        bookmarks.removeAll { $0.id == bookmark.id }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(bookmarks) {
            UserDefaults.standard.set(data, forKey: "bookmarks")
        }
    }

    private func load() {
        guard
            let data = UserDefaults.standard.data(forKey: "bookmarks"),
            let decoded = try? JSONDecoder().decode([Bookmark].self, from: data)
        else { return }
        bookmarks = decoded
    }
}

// MARK: - Mail

/// Unread mail count, read through Mail's own AppleScript dictionary.
@MainActor
@Observable
final class MailService {
    static let shared = MailService()

    private(set) var unread: Int?
    private(set) var latestSubject: String?
    /// Display name of whoever sent the newest unread message (or the newest
    /// message when nothing is unread).
    private(set) var latestSender: String?
    /// Unread messages received since midnight.
    private(set) var unreadToday: Int?
    /// Mail is only queried while it runs; asking a closed Mail would launch it.
    private(set) var isMailRunning = false

    static let bundleIdentifier = "com.apple.mail"

    /// The script runs off the main thread: blocking the run loop inside a
    /// view body would stall the whole bar.
    func refresh() async {
        isMailRunning = !NSRunningApplication
            .runningApplications(withBundleIdentifier: Self.bundleIdentifier).isEmpty
        guard isMailRunning else {
            unread = nil
            unreadToday = nil
            latestSubject = nil
            latestSender = nil
            return
        }
        let script = """
        set midnight to (current date) - (time of (current date))
        set sep to character id 31
        tell application "Mail"
            set inboxUnread to count of messages of inbox whose read status is false
            set todayUnread to count of (messages of inbox whose read status is false and date received > midnight)
            set latestSender to ""
            set inboxSubject to ""
            try
                if inboxUnread > 0 then
                    set latest to first message of inbox whose read status is false
                else
                    set latest to first message of inbox
                end if
                set latestSender to extract name from sender of latest
                set inboxSubject to subject of latest
            end try
            return (inboxUnread as string) & sep & (todayUnread as string) & sep & latestSender & sep & inboxSubject
        end tell
        """
        let output = await Task.detached(priority: .utility) {
            Self.runScript(script)
        }.value

        guard let output else {
            unread = nil
            unreadToday = nil
            return
        }
        let parts = output.split(separator: "\u{1F}", maxSplits: 3, omittingEmptySubsequences: false)
            .map(String.init)
        func part(_ index: Int) -> String? {
            guard parts.count > index, !parts[index].isEmpty else { return nil }
            return parts[index]
        }
        unread = part(0).flatMap { Int($0) }
        unreadToday = part(1).flatMap { Int($0) }
        latestSender = part(2)
        latestSubject = part(3)
    }

    nonisolated private static func runScript(_ script: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let text = String(data: data, encoding: .utf8)
        else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

import AppKit
import Foundation
import Observation

/// What the system is playing right now.
///
/// Uses the players' own AppleScript dictionaries (Spotify and Music) rather
/// than the private `MediaRemote` framework: the private entry point
/// (`MRMediaRemoteGetNowPlayingInfo`) segfaults on current macOS, and a
/// dashboard must never take the app down with it.
@MainActor
@Observable
final class NowPlayingService {
    static let shared = NowPlayingService()

    /// A scriptable player.
    enum Player: String, Sendable {
        case spotify = "Spotify"
        case music = "Music"

        var bundleIdentifier: String {
            switch self {
            case .spotify: "com.spotify.client"
            case .music: "com.apple.Music"
            }
        }
    }

    var title: String = ""
    var artist: String = ""
    var artwork: NSImage?
    var isPlaying = false
    var position: TimeInterval = 0
    var duration: TimeInterval = 0
    /// The player the readout comes from, and that the transport controls.
    private(set) var player: Player?

    /// Played fraction of the current track.
    var progress: Double {
        duration > 0 ? min(max(position / duration, 0), 1) : 0
    }

    private var lastRefresh = Date.distantPast
    /// Identifies the track whose artwork is loaded (or loading).
    private var artworkKey = ""

    private var runningPlayers: [Player] {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        return [Player.spotify, .music].filter { running.contains($0.bundleIdentifier) }
    }

    /// The script runs off the main thread: blocking the run loop inside a
    /// view body would stall the whole bar.
    func refresh() async {
        guard Date().timeIntervalSince(lastRefresh) > 1.5 else { return }
        lastRefresh = Date()

        let players = runningPlayers
        guard !players.isEmpty else {
            clear()
            return
        }

        // Prefer whichever player is actually playing; otherwise show the
        // first one with a track loaded.
        var paused: (Player, Track)?
        for candidate in players {
            let track = await Task.detached(priority: .utility) {
                Self.readTrack(from: candidate)
            }.value
            guard let track else { continue }
            if track.isPlaying {
                apply(track, from: candidate)
                return
            }
            if paused == nil { paused = (candidate, track) }
        }
        if let paused {
            apply(paused.1, from: paused.0)
        } else {
            clear()
            player = players.first
        }
    }

    func playPause() async {
        let target = player ?? .music
        let command = isPlaying ? "pause" : "play"
        await Task.detached(priority: .utility) {
            _ = Self.run("tell application \"\(target.rawValue)\" to \(command)")
        }.value
        lastRefresh = .distantPast
        await refresh()
    }

    func next() async {
        let target = player ?? .music
        await Task.detached(priority: .utility) {
            _ = Self.run("tell application \"\(target.rawValue)\" to next track")
        }.value
        lastRefresh = .distantPast
        await refresh()
    }

    func previous() async {
        let target = player ?? .music
        await Task.detached(priority: .utility) {
            _ = Self.run("tell application \"\(target.rawValue)\" to previous track")
        }.value
        lastRefresh = .distantPast
        await refresh()
    }

    /// Brings the active player (or Music) to the front.
    func openPlayer() {
        let target = player ?? .music
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.bundleIdentifier) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: - Reading

    private struct Track: Sendable {
        var isPlaying: Bool
        var title: String
        var artist: String
        var album: String
        var duration: TimeInterval
        var position: TimeInterval
        /// Spotify hands out an artwork URL; Music's artwork is read separately.
        var artworkURL: URL?
    }

    private func apply(_ track: Track, from source: Player) {
        player = source
        isPlaying = track.isPlaying
        title = track.title
        artist = track.artist
        duration = track.duration
        position = track.position
        loadArtwork(for: track, from: source)
    }

    private func loadArtwork(for track: Track, from source: Player) {
        let key = "\(source.rawValue)|\(track.title)|\(track.artist)|\(track.album)"
        guard key != artworkKey else { return }
        artworkKey = key
        artwork = nil
        Task {
            let image: NSImage?
            switch source {
            case .spotify:
                guard let url = track.artworkURL,
                      let (data, _) = try? await URLSession.shared.data(from: url)
                else { return }
                image = NSImage(data: data)
            case .music:
                image = await Task.detached(priority: .utility) {
                    Self.readMusicArtwork()
                }.value
            }
            // The track may have changed while the artwork was loading.
            guard artworkKey == key else { return }
            artwork = image
        }
    }

    nonisolated private static func readTrack(from player: Player) -> Track? {
        let script: String
        switch player {
        case .spotify:
            script = """
            tell application "Spotify"
                if player state is stopped then return "idle"
                set t to current track
                return (player state as string) & "|" & (name of t) & "|" & (artist of t) & "|" & (album of t) & "|" & ((duration of t) as string) & "|" & (player position as string) & "|" & (artwork url of t)
            end tell
            """
        case .music:
            script = """
            tell application "Music"
                if player state is stopped then return "idle"
                set t to current track
                return (player state as string) & "|" & (name of t) & "|" & (artist of t) & "|" & (album of t) & "|" & ((duration of t) as string) & "|" & (player position as string) & "|"
            end tell
            """
        }
        guard let output = run(script) else { return nil }
        let parts = output.split(separator: "|", maxSplits: 6, omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 6, !parts[1].isEmpty else { return nil }
        var duration = number(parts[4])
        // Spotify reports the duration in milliseconds.
        if player == .spotify { duration /= 1000 }
        let artworkURL = parts.count > 6 ? URL(string: parts[6]) : nil
        return Track(
            isPlaying: parts[0] == "playing",
            title: parts[1],
            artist: parts[2],
            album: parts[3],
            duration: duration,
            position: number(parts[5]),
            artworkURL: artworkURL
        )
    }

    /// AppleScript formats reals with the user's decimal separator.
    nonisolated private static func number(_ text: String) -> Double {
        Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    /// Music exposes artwork only as raw data: write it to a temporary file.
    nonisolated private static func readMusicArtwork() -> NSImage? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dockdock-artwork-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }
        let script = """
        tell application "Music"
            if (count of artworks of current track) is 0 then return "none"
            set artData to raw data of artwork 1 of current track
        end tell
        set f to open for access (POSIX file "\(url.path)") with write permission
        try
            set eof f to 0
            write artData to f
        end try
        close access f
        return "ok"
        """
        guard run(script) == "ok" else { return nil }
        return NSImage(contentsOf: url)
    }

    private func clear() {
        player = nil
        title = ""
        artist = ""
        artwork = nil
        artworkKey = ""
        isPlaying = false
        position = 0
        duration = 0
    }

    @discardableResult
    nonisolated private static func run(_ script: String) -> String? {
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

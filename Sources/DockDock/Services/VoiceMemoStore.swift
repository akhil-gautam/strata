import AVFoundation
import Foundation
import Observation

/// A recorded memo on disk.
struct ProductivityVoiceMemo: Identifiable {
    let url: URL
    let created: Date
    let duration: TimeInterval

    var id: URL { url }
}

/// Records short voice memos and keeps them in Application Support.
@MainActor
@Observable
final class ProductivityVoiceMemoStore {
    static let shared = ProductivityVoiceMemoStore()

    private(set) var recordings: [ProductivityVoiceMemo] = []
    private(set) var isRecording = false
    /// The current recording is on hold; `isRecording` stays true.
    private(set) var isPaused = false
    private(set) var isPlaying = false
    private(set) var playingID: URL?
    private(set) var permission: AVAudioApplication.recordPermission = .undetermined

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?

    init() {
        refreshPermission()
        reload()
    }

    /// Where the memos live.
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appending(path: "DockDock", directoryHint: .isDirectory)
            .appending(path: "VoiceMemos", directoryHint: .isDirectory)
    }

    /// Time on the current recording.
    var elapsed: TimeInterval {
        recorder?.currentTime ?? 0
    }

    func refreshPermission() {
        permission = AVAudioApplication.shared.recordPermission
    }

    /// Asks for the microphone, then reports what the system answered.
    @discardableResult
    func requestPermission() async -> Bool {
        let granted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { allowed in
                continuation.resume(returning: allowed)
            }
        }
        permission = AVAudioApplication.shared.recordPermission
        return granted
    }

    /// Starts a new recording, asking for the microphone first if needed.
    func startRecording() async -> Bool {
        if permission == .undetermined {
            _ = await requestPermission()
        }
        guard permission == .granted else { return false }

        let directory = Self.directory
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return false
        }

        let url = directory.appending(path: "Memo \(Self.fileStamp(Date())).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            let newRecorder = try AVAudioRecorder(url: url, settings: settings)
            newRecorder.isMeteringEnabled = true
            guard newRecorder.record() else { return false }
            recorder = newRecorder
            isRecording = true
            return true
        } catch {
            return false
        }
    }

    func stopRecording() {
        guard let recorder else { return }
        recorder.stop()
        self.recorder = nil
        isRecording = false
        isPaused = false
        reload()
    }

    func pauseRecording() {
        guard let recorder, isRecording, !isPaused else { return }
        recorder.pause()
        isPaused = true
    }

    func resumeRecording() {
        guard let recorder, isPaused else { return }
        if recorder.record() {
            isPaused = false
        }
    }

    /// The microphone level of the current recording, 0 (silence) to 1.
    func inputLevel() -> Double {
        guard let recorder, recorder.isRecording else { return 0 }
        recorder.updateMeters()
        let decibels = Double(recorder.averagePower(forChannel: 0))
        return min(max((decibels + 50) / 50, 0), 1)
    }

    /// Clears the playing state once the player has reached the end.
    func syncPlayback() {
        if isPlaying, player?.isPlaying != true {
            stopPlayback()
        }
    }

    /// Plays a memo, or stops it when it is already the one playing.
    func play(_ recording: ProductivityVoiceMemo) {
        if isPlaying, playingID == recording.url {
            stopPlayback()
            return
        }
        stopPlayback()
        guard let newPlayer = try? AVAudioPlayer(contentsOf: recording.url) else { return }
        newPlayer.prepareToPlay()
        newPlayer.play()
        player = newPlayer
        isPlaying = true
        playingID = recording.url
    }

    func stopPlayback() {
        player?.stop()
        player = nil
        isPlaying = false
        playingID = nil
    }

    /// Re-reads the memos from disk.
    func reload() {
        let directory = Self.directory
        guard
            let urls = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.creationDateKey],
                options: [.skipsHiddenFiles]
            )
        else {
            recordings = []
            return
        }

        recordings = urls
            .filter { $0.pathExtension.lowercased() == "m4a" }
            .map { url in
                let created = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
                let duration = (try? AVAudioPlayer(contentsOf: url))?.duration ?? 0
                return ProductivityVoiceMemo(url: url, created: created, duration: duration)
            }
            .sorted { $0.created > $1.created }
    }

    private static func fileStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: date)
    }
}

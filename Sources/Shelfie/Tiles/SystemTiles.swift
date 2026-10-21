import AppKit
import AudioToolbox
import CoreAudio
import IOKit.ps
import Photos
import SwiftUI
import Synchronization

/// Media, Photos and the first half of System: now playing, the latest
/// photo, Drink Water, battery, CPU, memory, network, storage, audio and the
/// clipboard.
@MainActor
enum SystemTiles {
    static let specs: [TileSpec] = [
        // Media
        TileSpec(
            id: "now-playing",
            title: "Now Playing",
            category: .media,
            menu: [.action("Open Player") { NowPlayingService.shared.openPlayer() }],
            make: { AnyView(SystemNowPlayingTile()) }
        ),
        TileSpec(
            id: "now-playing-mini",
            title: "Now Playing Mini",
            category: .media,
            menu: [.action("Open Player") { NowPlayingService.shared.openPlayer() }],
            make: { AnyView(SystemNowPlayingMiniTile()) }
        ),
        TileSpec(
            id: "now-playing-bar",
            title: "Now Playing Bar",
            category: .media,
            menu: [.action("Open Player") { NowPlayingService.shared.openPlayer() }],
            make: { AnyView(SystemNowPlayingBarTile()) }
        ),

        // Photos
        TileSpec(
            id: "recent-photo",
            title: "Recent Photo",
            category: .photos,
            menu: [.action("Open Photos") { SystemLinks.openApp("com.apple.Photos") }],
            make: { AnyView(SystemRecentPhotoTile()) }
        ),

        // System
        TileSpec(
            id: IntervalTimer.tileID,
            title: "Drink Water",
            category: .system,
            menu: [
                .customize("Set Interval…"),
                .action("Restart Reminder") { IntervalTimer.shared.restart() },
            ],
            settings: TileSettings(symbol: "drop.fill", badge: nil) { AnyView(SystemDrinkWaterSettings()) },
            make: { AnyView(SystemDrinkWaterTile()) }
        ),
        TileSpec(
            id: "battery",
            title: "Battery",
            category: .system,
            menu: [.action("Battery Settings…") { SystemLinks.openSettings("com.apple.Battery-Settings.extension") }],
            make: { AnyView(SystemBatteryTile()) }
        ),
        TileSpec(
            id: "cpu",
            title: "CPU",
            category: .system,
            menu: [.action("Open Activity Monitor") { SystemLinks.openApp("com.apple.ActivityMonitor") }],
            make: { AnyView(SystemCPUTile()) }
        ),
        TileSpec(
            id: "ram",
            title: "RAM",
            category: .system,
            menu: [.action("Open Activity Monitor") { SystemLinks.openApp("com.apple.ActivityMonitor") }],
            make: { AnyView(SystemRAMTile()) }
        ),
        TileSpec(
            id: "cpu-chart",
            title: "CPU Chart",
            category: .system,
            menu: [.action("Open Activity Monitor") { SystemLinks.openApp("com.apple.ActivityMonitor") }],
            make: { AnyView(SystemCPUChartTile()) }
        ),
        TileSpec(
            id: "ram-chart",
            title: "RAM Chart",
            category: .system,
            menu: [.action("Open Activity Monitor") { SystemLinks.openApp("com.apple.ActivityMonitor") }],
            make: { AnyView(SystemRAMChartTile()) }
        ),
        TileSpec(
            id: "network",
            title: "Network",
            category: .system,
            menu: [.action("Network Settings…") { SystemLinks.openSettings("com.apple.Network-Settings.extension") }],
            make: { AnyView(SystemNetworkTile()) }
        ),
        TileSpec(
            id: "download",
            title: "Download",
            category: .system,
            menu: [.action("Network Settings…") { SystemLinks.openSettings("com.apple.Network-Settings.extension") }],
            make: { AnyView(SystemRateTile(direction: .down)) }
        ),
        TileSpec(
            id: "upload",
            title: "Upload",
            category: .system,
            menu: [.action("Network Settings…") { SystemLinks.openSettings("com.apple.Network-Settings.extension") }],
            make: { AnyView(SystemRateTile(direction: .up)) }
        ),
        TileSpec(
            id: "network-chart",
            title: "Network Chart",
            category: .system,
            menu: [.action("Network Settings…") { SystemLinks.openSettings("com.apple.Network-Settings.extension") }],
            make: { AnyView(SystemNetworkChartTile()) }
        ),
        TileSpec(
            id: "storage",
            title: "Storage",
            category: .system,
            menu: [.action("Storage Settings…") { SystemLinks.openSettings("com.apple.settings.Storage") }],
            make: { AnyView(SystemStorageTile()) }
        ),
        TileSpec(
            id: "audio-output",
            title: "Audio Output",
            category: .system,
            menu: [.action("Sound Settings…") { SystemLinks.openSettings("com.apple.Sound-Settings.extension") }],
            make: { AnyView(SystemAudioOutputTile()) }
        ),
        TileSpec(
            id: "app-volume",
            title: "App Volume",
            category: .system,
            menu: [.customize("App Volumes…")],
            settings: TileSettings(
                symbol: "slider.vertical.3",
                badge: {
                    let count = SystemAppMixer.shared.apps.count
                    return count > 0 ? "\(count)" : nil
                }
            ) { AnyView(SystemAppVolumeSettings()) },
            make: { AnyView(SystemAppVolumeTile()) }
        ),
        TileSpec(
            id: "mic-mute",
            title: "Mic Mute",
            category: .system,
            menu: [
                .action("Toggle Mute") { SystemMicrophone.shared.toggleMute() },
                .action("Sound Settings…") { SystemLinks.openSettings("com.apple.Sound-Settings.extension") },
            ],
            make: { AnyView(SystemMicMuteTile()) }
        ),
        TileSpec(
            id: "clipboard",
            title: "Clipboard",
            category: .system,
            menu: [
                .customize("Clipboard History…"),
                .dynamic {
                    let history = ClipboardHistory.shared
                    return [
                        .action(history.isPaused ? "Resume Clipboard History" : "Pause Clipboard History") {
                            history.isPaused.toggle()
                        }
                    ]
                },
            ],
            settings: TileSettings(
                symbol: "doc.on.clipboard",
                badge: {
                    let count = ClipboardHistory.shared.items.count
                    return count > 0 ? "\(count)" : nil
                }
            ) { AnyView(SystemClipboardSettings()) },
            make: { AnyView(SystemClipboardTile()) }
        ),
    ]
}

// MARK: - Palette

private enum SystemPalette {
    static let cyan = Color(red: 0.30, green: 0.80, blue: 0.96)
    static let blue = Color(red: 0.16, green: 0.56, blue: 1.0)
    static let purple = Color(red: 0.62, green: 0.48, blue: 1.0)
    static let green = Color(red: 0.24, green: 0.84, blue: 0.40)
    static let orange = Color(red: 1.0, green: 0.60, blue: 0.16)
    @MainActor static var track: Color { TilePalette.ink.opacity(0.09) }
    @MainActor static var control: Color { TilePalette.ink.opacity(0.11) }
    static let waterTop = Color(red: 0.43, green: 0.75, blue: 0.89)
    static let waterBottom = Color(red: 0.29, green: 0.62, blue: 0.80)

    /// An inner corner radius that keeps its proportion to the tile's: the
    /// value is the radius under the default 12 pt tile corner.
    @MainActor static func corner(_ radius: CGFloat) -> CGFloat {
        TileMetrics.corner * radius / 12
    }
}

// MARK: - Links

@MainActor
private enum SystemLinks {
    static func openApp(_ bundleIdentifier: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    static func openSettings(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Formatting

private enum SystemFormat {
    /// "4.2 MB/s", "312 KB/s", "18 B/s".
    static func rate(_ bytesPerSecond: Double) -> String {
        let value = max(bytesPerSecond, 0)
        switch value {
        case ..<1_000:
            return "\(Int(value)) B/s"
        case ..<1_000_000:
            let kilobytes = value / 1_000
            return kilobytes < 10 ? String(format: "%.1f KB/s", kilobytes) : "\(Int(kilobytes)) KB/s"
        case ..<1_000_000_000:
            let megabytes = value / 1_000_000
            return megabytes < 100 ? String(format: "%.1f MB/s", megabytes) : "\(Int(megabytes)) MB/s"
        default:
            return String(format: "%.1f GB/s", value / 1_000_000_000)
        }
    }

    /// "1:24", "1:02:05".
    static func time(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds), 0)
        if total >= 3600 {
            return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Shared pieces

/// A refresh loop that lives as long as the view: services that are not on
/// the app's shared ticker poll only while a tile that needs them is shown.
private struct SystemPolling: ViewModifier {
    var interval: Duration
    var action: @MainActor () -> Void

    func body(content: Content) -> some View {
        content.task {
            while !Task.isCancelled {
                action()
                try? await Task.sleep(for: interval)
            }
        }
    }
}

extension View {
    fileprivate func systemPolling(every interval: Duration, _ action: @escaping @MainActor () -> Void) -> some View {
        modifier(SystemPolling(interval: interval, action: action))
    }
}

/// The gauge used by Battery, CPU, RAM, Storage and Mic Mute: a thin ring,
/// a small glyph and the number.
private struct SystemRingGauge<Glyph: View>: View {
    var value: Double
    var tint: Color
    var text: String
    var diameter: CGFloat = 40
    var lineWidth: CGFloat = 3.5
    @ViewBuilder var glyph: Glyph

    var body: some View {
        ZStack {
            Circle()
                .stroke(SystemPalette.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(value, 0.001), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.4), value: value)
            VStack(spacing: 1) {
                glyph
                if !text.isEmpty {
                    Text(text)
                        .font(.tileValue(12, weight: .bold))
                        .foregroundStyle(TilePalette.ink)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(width: diameter - lineWidth * 2 - 4)
        }
        .frame(width: diameter, height: diameter)
    }
}

/// Points of a smooth curve through `values`, scaled into `rect`.
private func systemCurvePoints(_ values: [Double], in rect: CGRect, lower: Double, upper: Double) -> [CGPoint] {
    guard values.count > 1 else { return [] }
    let range = max(upper - lower, 0.000_1)
    let step = rect.width / CGFloat(values.count - 1)
    return values.enumerated().map { index, value in
        let normalized = CGFloat(min(max((value - lower) / range, 0), 1))
        return CGPoint(x: rect.minX + CGFloat(index) * step, y: rect.maxY - normalized * rect.height)
    }
}

private func systemCurve(through points: [CGPoint], into path: inout Path) {
    guard let first = points.first else { return }
    path.move(to: first)
    for index in 1..<points.count {
        let previous = points[index - 1]
        let current = points[index]
        let midpoint = CGPoint(x: (previous.x + current.x) / 2, y: (previous.y + current.y) / 2)
        path.addQuadCurve(to: midpoint, control: previous)
        path.addQuadCurve(to: current, control: midpoint)
    }
}

private struct SystemLineShape: Shape {
    var values: [Double]
    var lower: Double
    var upper: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        systemCurve(through: systemCurvePoints(values, in: rect, lower: lower, upper: upper), into: &path)
        return path
    }
}

/// The area under the curve, for the gradient fill.
private struct SystemAreaShape: Shape {
    var values: [Double]
    var lower: Double
    var upper: Double

    func path(in rect: CGRect) -> Path {
        let points = systemCurvePoints(values, in: rect, lower: lower, upper: upper)
        guard let first = points.first, let last = points.last else { return Path() }
        var path = Path()
        systemCurve(through: points, into: &path)
        path.addLine(to: CGPoint(x: last.x, y: rect.maxY))
        path.addLine(to: CGPoint(x: first.x, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// A line with a soft gradient underneath.
private struct SystemChart: View {
    var values: [Double]
    var tint: Color
    var lower: Double
    var upper: Double
    var lineWidth: CGFloat = 1.6

    var body: some View {
        // Pad a short history so the chart spans the tile from the start.
        let series = values.count > 1 ? values : Array(repeating: values.first ?? 0, count: 2)
        ZStack {
            SystemAreaShape(values: series, lower: lower, upper: upper)
                .fill(LinearGradient(colors: [tint.opacity(0.30), tint.opacity(0)], startPoint: .top, endPoint: .bottom))
            SystemLineShape(values: series, lower: lower, upper: upper)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
    }
}

/// A thin capsule progress bar.
private struct SystemProgressBar: View {
    var value: Double
    var height: CGFloat = 2.5
    var fill: Color = TilePalette.ink.opacity(0.85)

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(TilePalette.ink.opacity(0.16))
                Capsule()
                    .fill(fill)
                    .frame(width: max(height, proxy.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: height)
    }
}

/// A horizontal slider drawn like the video's: an ink fill and a round knob.
private struct SystemSlider: View {
    var value: Double
    var onChange: (Double) -> Void

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let knob: CGFloat = 11
            let clamped = min(max(value, 0), 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(TilePalette.ink.opacity(0.16))
                    .frame(height: 5)
                Capsule()
                    .fill(TilePalette.ink.opacity(0.88))
                    .frame(width: knob / 2 + (width - knob) * clamped, height: 5)
                Circle()
                    .fill(TilePalette.ink)
                    .shadow(color: .black.opacity(0.35), radius: 1.5, y: 0.5)
                    .frame(width: knob, height: knob)
                    .offset(x: (width - knob) * clamped)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        onChange(min(max((drag.location.x - knob / 2) / max(width - knob, 1), 0), 1))
                    }
            )
        }
        .frame(height: 14)
    }
}

// MARK: - Media

private struct SystemArtwork: View {
    var image: NSImage?
    var size: CGFloat
    var corner: CGFloat

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                TilePalette.ink.opacity(0.08)
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.34, weight: .medium))
                    .foregroundStyle(TilePalette.ink.opacity(0.62))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: SystemPalette.corner(corner), style: .continuous))
    }
}

/// Title and artist, or what to do when nothing is loaded.
@MainActor
private struct SystemTrackText {
    let title: String
    let artist: String

    init(_ player: NowPlayingService) {
        if player.title.isEmpty {
            title = "Not Playing"
            artist = player.player?.rawValue ?? "Spotify or Music"
        } else {
            title = player.title
            artist = player.artist
        }
    }
}

private struct SystemTransportButton: View {
    var systemName: String
    var size: CGFloat = 9.5
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(TilePalette.ink.opacity(0.78))
                .frame(width: 18, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SystemRoundButton: View {
    var systemName: String
    var diameter: CGFloat
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: diameter * 0.4, weight: .bold))
                .foregroundStyle(TilePalette.ink)
                .frame(width: diameter, height: diameter)
                .background { Circle().fill(SystemPalette.control) }
        }
        .buttonStyle(.plain)
    }
}

/// Artwork, title/artist with a progress line, and ⏮ ▶ ⏭.
private struct SystemNowPlayingTile: View {
    var body: some View {
        let player = NowPlayingService.shared
        let text = SystemTrackText(player)
        DockTile(width: 222) {
            HStack(spacing: 9) {
                SystemArtwork(image: player.artwork, size: 42, corner: 8)
                    .onTapGesture { player.openPlayer() }
                VStack(alignment: .leading, spacing: 2) {
                    Text(text.title)
                        .font(.tileText(11.5, weight: .semibold))
                        .foregroundStyle(TilePalette.ink)
                        .lineLimit(1)
                    Text(text.artist)
                        .font(.tileCaption(9))
                        .foregroundStyle(TilePalette.caption)
                        .lineLimit(1)
                    SystemProgressBar(value: player.progress)
                        .padding(.top, 5)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 2) {
                    SystemTransportButton(systemName: "backward.fill") {
                        Task { await player.previous() }
                    }
                    SystemRoundButton(systemName: player.isPlaying ? "pause.fill" : "play.fill", diameter: 27) {
                        Task { await player.playPause() }
                    }
                    SystemTransportButton(systemName: "forward.fill") {
                        Task { await player.next() }
                    }
                }
            }
        }
    }
}

/// A round play/pause button with the track's progress around it.
private struct SystemNowPlayingMiniTile: View {
    var body: some View {
        let player = NowPlayingService.shared
        DockTile(width: TileMetrics.square, fill: AnyShapeStyle(TilePalette.tileFill.mix(with: TilePalette.ink, by: 0.14))) {
            Button {
                Task { await player.playPause() }
            } label: {
                ZStack {
                    Circle()
                        .fill(TilePalette.ink.opacity(0.06))
                    Circle()
                        .stroke(TilePalette.ink.opacity(0.14), lineWidth: 2.2)
                    Circle()
                        .trim(from: 0, to: max(player.progress, 0.001))
                        .stroke(TilePalette.ink, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(TilePalette.ink)
                }
                .frame(width: 32, height: 32)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(player.title.isEmpty ? "Not Playing" : "\(player.title) — \(player.artist)")
        }
    }
}

/// Title/artist with pause and next, then elapsed — progress — duration.
private struct SystemNowPlayingBarTile: View {
    var body: some View {
        let player = NowPlayingService.shared
        let text = SystemTrackText(player)
        DockTile(width: 252) {
            VStack(spacing: 4) {
                HStack(spacing: 8) {
                    SystemArtwork(image: player.artwork, size: 31, corner: 6)
                        .onTapGesture { player.openPlayer() }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(text.title)
                            .font(.tileText(11, weight: .semibold))
                            .foregroundStyle(TilePalette.ink)
                            .lineLimit(1)
                        Text(text.artist)
                            .font(.tileCaption(8.5))
                            .foregroundStyle(TilePalette.caption)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    SystemRoundButton(systemName: player.isPlaying ? "pause.fill" : "play.fill", diameter: 22) {
                        Task { await player.playPause() }
                    }
                    SystemTransportButton(systemName: "forward.fill", size: 9) {
                        Task { await player.next() }
                    }
                }
                HStack(spacing: 7) {
                    Text(SystemFormat.time(player.position))
                    SystemProgressBar(value: player.progress, height: 2.5)
                    Text(SystemFormat.time(player.duration))
                }
                .font(.tileCaption(7.5))
                .foregroundStyle(TilePalette.ink.opacity(0.62))
                .monospacedDigit()
            }
        }
    }
}

// MARK: - Photos

/// The newest photo in the library, edge to edge.
private struct SystemRecentPhotoTile: View {
    @Environment(\.tileContext) private var context
    @State private var library = PhotosLibrary()

    var body: some View {
        DockTile(width: 76, inset: 0) {
            ZStack {
                if let image = library.image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 76, height: TileMetrics.height)
                        .clipped()
                } else {
                    LinearGradient(
                        colors: [Color(red: 0.64, green: 0.32, blue: 0.21), Color(red: 0.47, green: 0.21, blue: 0.16)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "photo")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
        }
        .onTapGesture {
            if library.needsAccess, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos") {
                NSWorkspace.shared.open(url)
            } else {
                SystemLinks.openApp("com.apple.Photos")
            }
        }
        .help(library.needsAccess ? "Allow Shelfie to access Photos" : "Recent Photo")
        .task {
            while !Task.isCancelled {
                // The library preview never prompts for access; adding the
                // tile to the bar does.
                let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
                if context == .bar || status == .authorized || status == .limited {
                    await library.load()
                }
                try? await Task.sleep(for: .seconds(120))
            }
        }
    }
}

// MARK: - Drink Water

/// Water with a gentle wave on top; `level` is the remaining fraction.
private struct SystemWaterShape: Shape {
    var level: Double
    var phase: Double

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(level, phase) }
        set {
            level = newValue.first
            phase = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let amplitude: CGFloat = 2.2
        // Keep the crest visible even when full, and a sliver when empty.
        let surface = rect.minY + amplitude + (rect.height - amplitude * 2) * CGFloat(1 - min(max(level, 0), 1))
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        let steps = 40
        for step in 0...steps {
            let x = rect.minX + rect.width * CGFloat(step) / CGFloat(steps)
            let angle = Double(step) / Double(steps) * .pi * 2 * 1.3 + phase
            path.addLine(to: CGPoint(x: x, y: surface + amplitude * CGFloat(sin(angle))))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct SystemDrinkWaterTile: View {
    var body: some View {
        let timer = IntervalTimer.shared
        DockTile(width: 135, inset: 0) {
            // The wave rolls slowly; the level follows the countdown and
            // refills with a short animation when the reminder restarts. The
            // readout is ink above the water and white where the water covers
            // it, so it reads on light and dark themes alike.
            TimelineView(.animation(minimumInterval: 1.0 / 15)) { timeline in
                let water = SystemWaterShape(
                    level: timer.level,
                    phase: timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600) * 1.4
                )
                ZStack {
                    readout(timer, ink: TilePalette.ink)
                    water.fill(LinearGradient(
                        colors: [SystemPalette.waterTop, SystemPalette.waterBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                    readout(timer, ink: .white)
                        .shadow(color: .black.opacity(0.12), radius: 1, y: 0.5)
                        .mask { water }
                }
            }
            .animation(.easeInOut(duration: 0.8), value: timer.level > 0.995)
        }
    }

    private func readout(_ timer: IntervalTimer, ink: Color) -> some View {
        VStack(spacing: 0) {
            Text(timer.formatted)
                .font(.tileValue(22, weight: .bold))
                .foregroundStyle(ink)
                .monospacedDigit()
            Text(timer.intervalLabel)
                .font(.tileCaption(8.5, weight: .semibold))
                .foregroundStyle(ink.opacity(0.78))
        }
    }
}

/// "Every 30 min", the minutes stepper and the preset chips.
private struct SystemDrinkWaterSettings: View {
    var body: some View {
        let timer = IntervalTimer.shared
        VStack(spacing: 12) {
            VStack(spacing: 4) {
                Text(timer.intervalLabel)
                    .font(.tileValue(24, weight: .bold))
                    .foregroundStyle(TilePalette.ink)
                Text("Water level drains until the next reminder.")
                    .font(.tileText(10, weight: .medium))
                    .foregroundStyle(TilePalette.ink.opacity(0.55))
            }
            VStack(spacing: 4) {
                Text("Minutes")
                    .font(.tileText(9.5, weight: .medium))
                    .foregroundStyle(TilePalette.ink.opacity(0.5))
                HStack(spacing: 18) {
                    stepButton("minus", enabled: timer.intervalMinutes > IntervalTimer.minimumMinutes) {
                        timer.setInterval(timer.intervalMinutes - 5)
                    }
                    Text("\(timer.intervalMinutes)")
                        .font(.tileValue(20))
                        .foregroundStyle(TilePalette.ink)
                        .monospacedDigit()
                        .frame(minWidth: 36)
                    stepButton("plus", enabled: timer.intervalMinutes < IntervalTimer.maximumMinutes) {
                        timer.setInterval(timer.intervalMinutes + 5)
                    }
                }
            }
            TileChoiceChips(
                options: IntervalTimer.presets.map { (label: IntervalTimer.label(minutes: $0), value: $0) },
                selection: Binding(
                    get: { timer.intervalMinutes },
                    set: { timer.setInterval($0) }
                )
            )
        }
        .frame(maxWidth: .infinity)
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(TilePalette.ink.opacity(enabled ? 0.8 : 0.25))
                .frame(width: 24, height: 24)
                .background { Circle().fill(TilePalette.ink.opacity(0.09)) }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

// MARK: - Gauges

private struct SystemBatteryTile: View {
    var body: some View {
        let battery = BatteryInfo.shared
        DockTile(width: 65) {
            if battery.isPresent {
                SystemRingGauge(value: battery.percent / 100, tint: SystemPalette.green, text: "\(Int(battery.percent.rounded()))") {
                    Image(systemName: battery.isCharging ? "bolt.fill" : "battery.100percent")
                        .font(.system(size: battery.isCharging ? 9 : 8, weight: .bold))
                        .foregroundStyle(SystemPalette.green)
                }
            } else {
                // Desktops run on mains power.
                SystemRingGauge(value: 1, tint: SystemPalette.green, text: "AC") {
                    Image(systemName: "powerplug.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(SystemPalette.green)
                }
            }
        }
        .help(batteryHelp(battery))
    }

    private func batteryHelp(_ battery: BatteryInfo) -> String {
        guard battery.isPresent else { return "Power adapter" }
        var text = "Battery \(Int(battery.percent.rounded()))%"
        if let minutes = battery.timeRemainingMinutes {
            text += battery.isCharging ? " · full in " : " · "
            text += "\(minutes / 60):\(String(format: "%02d", minutes % 60))"
            if !battery.isCharging { text += " remaining" }
        }
        return text
    }
}

private struct SystemCPUTile: View {
    var body: some View {
        let metrics = SystemMetrics.shared
        DockTile(width: 64) {
            SystemRingGauge(value: metrics.cpuPercent, tint: SystemPalette.cyan, text: "\(Int((metrics.cpuPercent * 100).rounded()))") {
                Image(systemName: "cpu")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(SystemPalette.cyan)
            }
        }
    }
}

private struct SystemRAMTile: View {
    var body: some View {
        let metrics = SystemMetrics.shared
        DockTile(width: 64) {
            SystemRingGauge(value: metrics.memoryFraction, tint: SystemPalette.blue, text: "\(Int((metrics.memoryFraction * 100).rounded()))") {
                Image(systemName: "memorychip")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(SystemPalette.blue)
            }
        }
    }
}

private struct SystemStorageTile: View {
    var body: some View {
        let metrics = SystemMetrics.shared
        let used = metrics.diskTotal > 0 ? (metrics.diskTotal - metrics.diskFree) / metrics.diskTotal : 0
        DockTile(width: 63) {
            SystemRingGauge(value: used, tint: SystemPalette.orange, text: "\(Int(metrics.diskFree / 1_000_000_000))") {
                Image(systemName: "internaldrive.fill")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(SystemPalette.orange)
            }
        }
        .help("\(Int(metrics.diskFree / 1_000_000_000)) GB free of \(Int(metrics.diskTotal / 1_000_000_000)) GB")
    }
}

// MARK: - Charts

/// "CPU 34%" over a filled sparkline.
private struct SystemMetricChartTile: View {
    var symbol: String
    var label: String
    var value: Double
    var history: [Double]
    var tint: Color
    var lower: Double
    var upper: Double

    var body: some View {
        DockTile(width: 135, inset: 0) {
            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: symbol)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(tint)
                    Text(label)
                        .font(.tileCaption(8.5, weight: .semibold))
                        .foregroundStyle(TilePalette.ink.opacity(0.62))
                    Spacer(minLength: 4)
                    Text("\(Int((value * 100).rounded()))%")
                        .font(.tileValue(11.5, weight: .bold))
                        .foregroundStyle(TilePalette.ink)
                        .monospacedDigit()
                }
                .padding(.horizontal, 9)
                SystemChart(values: history, tint: tint, lower: lower, upper: upper)
                    .padding(.horizontal, 7)
                    .frame(height: 25)
            }
            .padding(.top, 6)
            .padding(.bottom, 5)
        }
    }
}

private struct SystemCPUChartTile: View {
    var body: some View {
        let metrics = SystemMetrics.shared
        SystemMetricChartTile(
            symbol: "cpu",
            label: "CPU",
            value: metrics.cpuPercent,
            history: metrics.cpuHistory,
            tint: SystemPalette.cyan,
            lower: 0,
            upper: max((metrics.cpuHistory.max() ?? 0) * 1.2, 0.1)
        )
    }
}

private struct SystemRAMChartTile: View {
    var body: some View {
        let metrics = SystemMetrics.shared
        let history = metrics.memoryHistory
        SystemMetricChartTile(
            symbol: "memorychip",
            label: "RAM",
            value: metrics.memoryFraction,
            history: history,
            tint: SystemPalette.blue,
            lower: max((history.min() ?? 0) - 0.04, 0),
            upper: min((history.max() ?? 1) + 0.04, 1)
        )
    }
}

// MARK: - Network

private enum SystemRateDirection {
    case down, up

    var symbol: String { self == .down ? "arrow.down" : "arrow.up" }
    var tint: Color { self == .down ? SystemPalette.cyan : SystemPalette.purple }

    @MainActor
    var value: Double {
        self == .down ? SystemMetrics.shared.networkDown : SystemMetrics.shared.networkUp
    }
}

private struct SystemRateLabel: View {
    var direction: SystemRateDirection
    var arrowTrailing = false

    var body: some View {
        HStack(spacing: 3) {
            if !arrowTrailing { arrow }
            Text(SystemFormat.rate(direction.value))
                .font(.tileText(10.5, weight: .semibold))
                .foregroundStyle(TilePalette.ink)
                .monospacedDigit()
                .lineLimit(1)
            if arrowTrailing { arrow }
        }
    }

    private var arrow: some View {
        Image(systemName: direction.symbol)
            .font(.system(size: 8.5, weight: .bold))
            .foregroundStyle(direction.tint)
    }
}

/// "↓ 4.2 MB/s" over "↑ 312 KB/s".
private struct SystemNetworkTile: View {
    var body: some View {
        DockTile(width: 78, inset: 8) {
            VStack(alignment: .leading, spacing: 7) {
                SystemRateLabel(direction: .down)
                SystemRateLabel(direction: .up)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// One direction: an arrow over the rate.
private struct SystemRateTile: View {
    var direction: SystemRateDirection

    var body: some View {
        DockTile(width: 71, inset: 7) {
            VStack(spacing: 4) {
                Image(systemName: direction.symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(direction.tint)
                Text(SystemFormat.rate(direction.value))
                    .font(.tileValue(14, weight: .bold))
                    .foregroundStyle(TilePalette.ink)
                    .monospacedDigit()
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .help(SystemFormat.rate(direction.value))
    }
}

/// Download (filled) and upload (line) on a shared scale.
private struct SystemNetworkChartTile: View {
    var body: some View {
        let metrics = SystemMetrics.shared
        let upper = max(metrics.networkHistory.max() ?? 0, metrics.networkUpHistory.max() ?? 0, 10_000) * 1.15
        DockTile(width: 149, inset: 0) {
            VStack(spacing: 2) {
                HStack {
                    SystemRateLabel(direction: .down)
                    Spacer(minLength: 4)
                    SystemRateLabel(direction: .up, arrowTrailing: true)
                }
                .padding(.horizontal, 9)
                ZStack {
                    SystemChart(values: metrics.networkHistory, tint: SystemPalette.cyan, lower: 0, upper: upper)
                    SystemChart(values: metrics.networkUpHistory, tint: SystemPalette.purple, lower: 0, upper: upper, lineWidth: 1.4)
                }
                .padding(.horizontal, 7)
                .frame(height: 25)
            }
            .padding(.top, 6)
            .padding(.bottom, 5)
        }
    }
}

// MARK: - Clipboard

private struct SystemClipboardTile: View {
    var body: some View {
        let history = ClipboardHistory.shared
        let latest = history.items.first
        DockTile(width: 113) {
            HStack(spacing: 4) {
                if history.isPaused {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(TilePalette.ink.opacity(0.5))
                } else if let thumbnail = latest?.image?.thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 18, height: 18)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                } else if let latest, latest.kind != .text {
                    Image(systemName: latest.kind == .image ? "photo" : "doc")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(TilePalette.ink.opacity(0.7))
                }
                Text(history.isPaused ? "Paused" : latest?.preview ?? "Nothing copied")
                    .font(.tileText(10.5, weight: .semibold))
                    .foregroundStyle(latest == nil || history.isPaused ? TilePalette.caption : TilePalette.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity)
        }
        .help(history.isPaused ? "Clipboard history is paused" : latest?.preview ?? "Nothing copied")
    }
}

/// Recent clips; clicking one puts it back on the clipboard.
private struct SystemClipboardSettings: View {
    @Bindable private var history = ClipboardHistory.shared

    var body: some View {
        VStack(spacing: 8) {
            TileSettingsToggleRow(
                symbol: "pause.fill",
                tint: TilePalette.ink.opacity(0.7),
                title: "Pause Clipboard History",
                subtitle: "Password manager copies are never kept",
                isOn: $history.isPaused
            )
            if history.items.isEmpty {
                Text("Copy some text or an image and it shows up here.")
                    .font(.tileText(10, weight: .medium))
                    .foregroundStyle(TilePalette.ink.opacity(0.5))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(history.items) { item in
                            Button {
                                history.copy(item)
                            } label: {
                                HStack(spacing: 8) {
                                    leading(for: item)
                                    Text(item.preview)
                                        .font(.tileText(11, weight: .medium))
                                        .foregroundStyle(TilePalette.ink.opacity(0.9))
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, item.image?.thumbnail == nil ? 7 : 4)
                                .background {
                                    RoundedRectangle(cornerRadius: min(9, TileMetrics.corner), style: .continuous)
                                        .fill(TilePalette.ink.opacity(0.045))
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 260)
            }
        }
    }

    @ViewBuilder
    private func leading(for item: ClipboardHistory.Item) -> some View {
        if let thumbnail = item.image?.thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(TilePalette.ink.opacity(0.1), lineWidth: 1)
                }
        } else {
            Image(systemName: icon(for: item.kind))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(TilePalette.ink.opacity(0.6))
                .frame(width: 16)
        }
    }

    private func icon(for kind: ClipboardHistory.Item.Kind) -> String {
        switch kind {
        case .text: "text.alignleft"
        case .image: "photo"
        case .files: "doc"
        }
    }
}

// MARK: - Audio Output

/// The current output device with a volume slider, then one-click buttons
/// for other outputs.
private struct SystemAudioOutputTile: View {
    var body: some View {
        let audio = AudioService.shared
        let devices = SystemAudioDevices.shared
        let current = devices.outputs.first { $0.id == devices.defaultOutputID }
        let others = Array(devices.outputs.filter { $0.id != devices.defaultOutputID }.prefix(2))
        DockTile(width: 202, inset: 5) {
            HStack(spacing: 4) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 5) {
                        Image(systemName: current?.symbol ?? "speaker.wave.2")
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(TilePalette.ink.opacity(0.65))
                        Text(current?.label ?? audio.outputDevice)
                            .font(.tileText(10, weight: .semibold))
                            .foregroundStyle(TilePalette.ink)
                            .lineLimit(1)
                    }
                    HStack(spacing: 5) {
                        Button {
                            audio.toggleMute()
                        } label: {
                            Image(systemName: audio.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(TilePalette.ink.opacity(0.75))
                                .frame(width: 12)
                        }
                        .buttonStyle(.plain)
                        SystemSlider(value: audio.isMuted ? 0 : audio.volume) { value in
                            if audio.isMuted { audio.toggleMute() }
                            audio.setVolume(value)
                        }
                        Text("\(Int(((audio.isMuted ? 0 : audio.volume) * 100).rounded()))%")
                            .font(.tileCaption(8))
                            .foregroundStyle(TilePalette.ink.opacity(0.6))
                            .monospacedDigit()
                            .frame(width: 24, alignment: .trailing)
                    }
                }
                .padding(.horizontal, 7)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: SystemPalette.corner(8), style: .continuous)
                        .fill(TilePalette.ink.opacity(0.06))
                }
                .help(current?.name ?? audio.outputDevice)

                ForEach(others) { device in
                    Button {
                        devices.setDefaultOutput(device.id)
                        audio.refresh()
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: device.symbol)
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(TilePalette.ink.opacity(0.75))
                                .frame(height: 14)
                            Text(device.label)
                                .font(.tileCaption(7.5))
                                .foregroundStyle(TilePalette.ink.opacity(0.55))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 3)
                        .frame(width: 43)
                        .frame(maxHeight: .infinity)
                        .background {
                            RoundedRectangle(cornerRadius: SystemPalette.corner(8), style: .continuous)
                                .fill(TilePalette.ink.opacity(0.06))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Play through \(device.name)")
                }
            }
            .padding(.vertical, 5)
        }
        .systemPolling(every: .seconds(3)) { devices.refresh() }
    }
}

/// Output devices and the default output, read from Core Audio.
@MainActor
@Observable
private final class SystemAudioDevices {
    static let shared = SystemAudioDevices()

    struct Device: Identifiable, Equatable {
        let id: AudioDeviceID
        let name: String
        let transport: UInt32

        /// The short label the video uses: "MacBook", "AirPods", "Display".
        var label: String {
            switch transport {
            case kAudioDeviceTransportTypeBuiltIn:
                return SystemAudioDevices.isLaptop ? "MacBook" : "Mac"
            case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort:
                return "Display"
            case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
                return name.localizedCaseInsensitiveContains("AirPods") ? "AirPods" : name
            case kAudioDeviceTransportTypeAirPlay:
                return "AirPlay"
            default:
                return name
            }
        }

        var symbol: String {
            switch transport {
            case kAudioDeviceTransportTypeBuiltIn:
                return SystemAudioDevices.isLaptop ? "laptopcomputer" : "desktopcomputer"
            case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort:
                return "display"
            case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
                if name.localizedCaseInsensitiveContains("AirPods Max") { return "airpodsmax" }
                if name.localizedCaseInsensitiveContains("AirPods") { return "airpods" }
                return "headphones"
            case kAudioDeviceTransportTypeAirPlay:
                return "airplayaudio"
            case kAudioDeviceTransportTypeUSB, kAudioDeviceTransportTypeThunderbolt:
                return "hifispeaker"
            default:
                return "speaker.wave.2"
            }
        }
    }

    private(set) var outputs: [Device] = []
    private(set) var defaultOutputID: AudioDeviceID = 0

    /// Laptops have an internal battery; their speakers read "MacBook".
    nonisolated static let isLaptop: Bool = {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return false }
        return !list.isEmpty
    }()

    func refresh() {
        let all = SystemCoreAudio.deviceIDs().compactMap { id -> Device? in
            guard SystemCoreAudio.hasStreams(id, scope: kAudioObjectPropertyScopeOutput) else { return nil }
            let transport = SystemCoreAudio.transportType(id)
            guard transport != kAudioDeviceTransportTypeAggregate,
                  transport != kAudioDeviceTransportTypeVirtual,
                  !SystemCoreAudio.isHidden(id)
            else { return nil }
            return Device(id: id, name: SystemCoreAudio.name(of: id) ?? "Output", transport: transport)
        }
        if all != outputs { outputs = all }
        let current = SystemCoreAudio.defaultDevice(input: false)
        if current != defaultOutputID { defaultOutputID = current }
    }

    func setDefaultOutput(_ id: AudioDeviceID) {
        SystemCoreAudio.setDefaultOutput(id)
        refresh()
    }
}

// MARK: - Mic Mute

private struct SystemMicMuteTile: View {
    var body: some View {
        let mic = SystemMicrophone.shared
        let tint = mic.isMuted ? TilePalette.destructive : SystemPalette.green
        DockTile(width: 64) {
            Button {
                mic.toggleMute()
            } label: {
                SystemRingGauge(value: mic.isMuted ? 1 : mic.level, tint: tint.opacity(mic.isMuted ? 0.55 : 1), text: "") {
                    Image(systemName: mic.isMuted ? "mic.slash.fill" : "mic.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!mic.hasInput)
        }
        .help(mic.hasInput ? (mic.isMuted ? "Microphone muted" : "Microphone on") : "No microphone")
        .systemPolling(every: .seconds(2)) { mic.refresh() }
    }
}

/// Mute state and input volume of the default input device.
///
/// Devices with a hardware mute control are muted directly; for the rest the
/// input volume is dropped to zero and restored on unmute.
@MainActor
@Observable
private final class SystemMicrophone {
    static let shared = SystemMicrophone()

    private(set) var isMuted = false
    /// Input volume, 0...1.
    private(set) var level: Double = 0
    private(set) var hasInput = false

    private static let restoreKey = "micMute.restoreVolume"

    func refresh() {
        let device = SystemCoreAudio.defaultDevice(input: true)
        hasInput = device != 0
        guard hasInput else { return }
        let volume = SystemCoreAudio.inputVolume(device) ?? 1
        let hardwareMute = SystemCoreAudio.inputMute(device)
        level = volume
        isMuted = hardwareMute ?? (volume <= 0.001)
    }

    func toggleMute() {
        let device = SystemCoreAudio.defaultDevice(input: true)
        guard device != 0 else { return }
        let mute = !isMuted
        if SystemCoreAudio.canSetInputMute(device) {
            SystemCoreAudio.setInputMute(device, mute)
            // Some devices keep their mute flag but also need volume back.
            if !mute, (SystemCoreAudio.inputVolume(device) ?? 1) <= 0.001 {
                SystemCoreAudio.setInputVolume(device, restoreVolume)
            }
        } else if mute {
            UserDefaults.standard.set(SystemCoreAudio.inputVolume(device) ?? 0.75, forKey: Self.restoreKey)
            SystemCoreAudio.setInputVolume(device, 0)
        } else {
            SystemCoreAudio.setInputVolume(device, restoreVolume)
        }
        refresh()
    }

    private var restoreVolume: Double {
        let stored = UserDefaults.standard.double(forKey: Self.restoreKey)
        return stored > 0.001 ? stored : 0.75
    }
}

// MARK: - App Volume

/// Level bars that move while any app is playing sound.
private struct SystemAppVolumeTile: View {
    var body: some View {
        let mixer = SystemAppMixer.shared
        DockTile(width: 58) {
            TimelineView(.animation(minimumInterval: 1.0 / 12, paused: !mixer.isAnyPlaying)) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                HStack(spacing: 2.6) {
                    ForEach(0..<5, id: \.self) { index in
                        Capsule()
                            .fill(TilePalette.ink.opacity(0.9))
                            .frame(width: 2.6, height: barHeight(index: index, time: time, active: mixer.isAnyPlaying))
                    }
                }
                .frame(height: 20)
            }
        }
        .help(mixer.isAnyPlaying ? "Apps playing: \(mixer.apps.map(\.name).joined(separator: ", "))" : "No apps playing")
        .systemPolling(every: .seconds(2)) { mixer.refresh() }
    }

    private func barHeight(index: Int, time: TimeInterval, active: Bool) -> CGFloat {
        let resting: [CGFloat] = [9, 15, 20, 15, 9]
        guard active else { return resting[index] }
        let wobble = (sin(time * 7 + Double(index) * 1.7) + 1) / 2
        return 6 + 14 * CGFloat(wobble) * (index == 2 ? 1 : 0.85)
    }
}

/// One slider per app playing sound.
private struct SystemAppVolumeSettings: View {
    var body: some View {
        let mixer = SystemAppMixer.shared
        VStack(spacing: 6) {
            if mixer.captureDenied {
                VStack(spacing: 6) {
                    Text("Per-app volume needs System Audio Recording access.")
                        .font(.tileText(10, weight: .medium))
                        .foregroundStyle(TilePalette.ink.opacity(0.6))
                        .multilineTextAlignment(.center)
                    Button("Open Privacy Settings") {
                        SystemLinks.openSettings("com.apple.preference.security?Privacy_AudioCapture")
                    }
                    .buttonStyle(.plain)
                    .font(.tileText(10, weight: .semibold))
                    .foregroundStyle(TilePalette.focus)
                }
                .padding(.vertical, 4)
            }
            if mixer.apps.isEmpty {
                Text("No apps are playing sound.")
                    .font(.tileText(10, weight: .medium))
                    .foregroundStyle(TilePalette.ink.opacity(0.5))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            } else {
                ForEach(mixer.apps) { app in
                    HStack(spacing: 8) {
                        Group {
                            if let icon = app.icon {
                                Image(nsImage: icon).resizable()
                            } else {
                                Image(systemName: "app.dashed").resizable().foregroundStyle(TilePalette.ink.opacity(0.5))
                            }
                        }
                        .frame(width: 20, height: 20)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(app.name)
                                .font(.tileText(10.5, weight: .semibold))
                                .foregroundStyle(TilePalette.ink.opacity(0.9))
                                .lineLimit(1)
                            SystemSlider(value: mixer.volume(for: app)) { value in
                                mixer.setVolume(value, for: app)
                            }
                        }
                        Text("\(Int((mixer.volume(for: app) * 100).rounded()))%")
                            .font(.tileText(9, weight: .medium))
                            .foregroundStyle(TilePalette.ink.opacity(0.55))
                            .monospacedDigit()
                            .frame(width: 30, alignment: .trailing)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background {
                        RoundedRectangle(cornerRadius: min(10, TileMetrics.corner), style: .continuous)
                            .fill(TilePalette.ink.opacity(0.045))
                    }
                }
            }
        }
        .systemPolling(every: .seconds(1)) { mixer.refresh() }
    }
}

/// Apps playing sound, and a per-app gain applied through Core Audio
/// process taps: an app turned down is tapped (and muted at its source), and
/// its audio is played to the current output at the chosen volume. Apps at
/// 100% are left untouched.
@MainActor
@Observable
private final class SystemAppMixer {
    static let shared = SystemAppMixer()

    struct App: Identifiable {
        /// The app's bundle identifier (or its process name).
        let id: String
        let name: String
        let icon: NSImage?
        /// Every Core Audio process object that plays for this app (the app
        /// and its helpers).
        let objects: [AudioObjectID]
    }

    private(set) var apps: [App] = []
    private(set) var isAnyPlaying = false
    private(set) var captureDenied = false

    private var volumes: [String: Double] = [:]
    private var taps: [String: SystemProcessTap] = [:]
    private var requestingAccess = false

    func volume(for app: App) -> Double { volumes[app.id] ?? 1 }

    func refresh() {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var groups: [String: (name: String, icon: NSImage?, objects: [AudioObjectID], playing: Bool)] = [:]
        var order: [String] = []
        for object in SystemCoreAudio.processObjects() {
            let pid = SystemCoreAudio.processPID(object)
            guard pid > 0, pid != ownPID else { continue }
            let playing = SystemCoreAudio.isRunningOutput(object)
            let owner = Self.owner(of: pid, bundleID: SystemCoreAudio.processBundleID(object))
            // Keep showing an app we turned down even between sounds.
            guard playing || volumes[owner.id] != nil else { continue }
            if groups[owner.id] == nil {
                groups[owner.id] = (owner.name, owner.icon, [], false)
                order.append(owner.id)
            }
            groups[owner.id]?.objects.append(object)
            if playing { groups[owner.id]?.playing = true }
        }

        let next = order.compactMap { id -> App? in
            guard let group = groups[id] else { return nil }
            return App(id: id, name: group.name, icon: group.icon, objects: group.objects.sorted())
        }
        let anyPlaying = groups.values.contains { $0.playing }
        if next.map(\.id) != apps.map(\.id) || next.map(\.objects) != apps.map(\.objects) {
            apps = next
        }
        if anyPlaying != isAnyPlaying { isAnyPlaying = anyPlaying }

        // Drop state for apps that quit; rebuild taps whose processes or
        // output device changed.
        let outputUID = SystemCoreAudio.defaultOutputUID()
        for (id, tap) in taps {
            guard let app = next.first(where: { $0.id == id }) else {
                tap.stop()
                taps[id] = nil
                volumes[id] = nil
                continue
            }
            if tap.objects != app.objects || tap.outputUID != outputUID {
                tap.stop()
                taps[id] = nil
                startTap(for: app)
            }
        }
    }

    func setVolume(_ value: Double, for app: App) {
        let clamped = min(max(value, 0), 1)
        if clamped >= 0.995 {
            volumes[app.id] = nil
            taps[app.id]?.stop()
            taps[app.id] = nil
            return
        }
        volumes[app.id] = clamped
        if let tap = taps[app.id] {
            tap.gain.set(clamped)
            return
        }
        switch SystemAudioCapturePermission.status {
        case .authorized:
            captureDenied = false
            startTap(for: app)
        case .denied:
            captureDenied = true
            volumes[app.id] = nil
        case .unknown:
            guard !requestingAccess else { return }
            requestingAccess = true
            Task {
                let granted = await SystemAudioCapturePermission.request()
                requestingAccess = false
                captureDenied = !granted
                guard granted, let current = apps.first(where: { $0.id == app.id }) else {
                    volumes[app.id] = nil
                    return
                }
                startTap(for: current)
            }
        }
    }

    private func startTap(for app: App) {
        guard let volume = volumes[app.id], taps[app.id] == nil,
              let outputUID = SystemCoreAudio.defaultOutputUID()
        else { return }
        if let tap = SystemProcessTap(objects: app.objects, outputUID: outputUID, gain: volume) {
            taps[app.id] = tap
        } else {
            volumes[app.id] = nil
        }
    }

    /// The app a process plays for: helpers ("com.google.Chrome.helper")
    /// are folded into their app ("com.google.Chrome").
    private static func owner(of pid: pid_t, bundleID: String?) -> (id: String, name: String, icon: NSImage?) {
        let process = NSRunningApplication(processIdentifier: pid)
        let identifier = bundleID ?? process?.bundleIdentifier
        if let identifier {
            var components = identifier.split(separator: ".").map(String.init)
            while components.count >= 2 {
                let candidate = components.joined(separator: ".")
                if let app = NSRunningApplication.runningApplications(withBundleIdentifier: candidate)
                    .first(where: { $0.activationPolicy == .regular }) {
                    return (candidate, app.localizedName ?? candidate, app.icon)
                }
                components.removeLast()
            }
        }
        let name = process?.localizedName ?? identifier ?? "PID \(pid)"
        return (identifier ?? "pid.\(pid)", name, process?.icon)
    }
}

/// A gain shared with the real-time audio thread.
private final class SystemGain: Sendable {
    private let bits: Atomic<UInt32>

    init(_ value: Double) {
        bits = Atomic(Float(value).bitPattern)
    }

    var value: Float { Float(bitPattern: bits.load(ordering: .relaxed)) }

    func set(_ value: Double) {
        bits.store(Float(value).bitPattern, ordering: .relaxed)
    }
}

/// One app's audio, tapped (muting the original) and replayed to the output
/// device at a gain.
@MainActor
private final class SystemProcessTap {
    let objects: [AudioObjectID]
    let outputUID: String
    let gain: SystemGain

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?

    init?(objects: [AudioObjectID], outputUID: String, gain: Double) {
        self.objects = objects
        self.outputUID = outputUID
        self.gain = SystemGain(gain)

        let description = CATapDescription(stereoMixdownOfProcesses: objects)
        description.uuid = UUID()
        description.name = "Shelfie App Volume"
        description.muteBehavior = .mutedWhenTapped
        description.isPrivate = true
        var tap = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateProcessTap(description, &tap) == noErr else { return nil }
        tapID = tap

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Shelfie App Volume",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: description.uuid.uuidString,
            ]],
        ]
        var device = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &device) == noErr else {
            AudioHardwareDestroyProcessTap(tap)
            return nil
        }
        aggregateID = device

        let tapChannels = Int(SystemCoreAudio.tapChannelCount(tap) ?? 2)
        let gainBox = self.gain
        var proc: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&proc, device, nil) { @Sendable _, input, _, output, _ in
            SystemProcessTap.render(input: input, output: output, tapChannels: tapChannels, gain: gainBox.value)
        }
        guard status == noErr, let proc, AudioDeviceStart(device, proc) == noErr else {
            if let proc { AudioDeviceDestroyIOProcID(device, proc) }
            AudioHardwareDestroyAggregateDevice(device)
            AudioHardwareDestroyProcessTap(tap)
            return nil
        }
        procID = proc
    }

    func stop() {
        if let procID {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
            self.procID = nil
        }
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    /// Copies the tap's channels (the last `tapChannels` input channels,
    /// after any input of the output device) to the output at `gain`.
    /// Runs on the real-time thread: no allocation, no locks.
    nonisolated private static func render(
        input: UnsafePointer<AudioBufferList>,
        output: UnsafeMutablePointer<AudioBufferList>,
        tapChannels: Int,
        gain: Float
    ) {
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outputs = UnsafeMutableAudioBufferListPointer(output)
        var outputChannels = 0
        for buffer in outputs {
            outputChannels += Int(buffer.mNumberChannels)
            if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
        }
        var inputChannels = 0
        for buffer in inputs { inputChannels += Int(buffer.mNumberChannels) }
        guard tapChannels > 0, inputChannels >= tapChannels else { return }

        let firstTapChannel = inputChannels - tapChannels
        for channel in 0..<min(outputChannels, tapChannels) {
            guard let destination = location(outputs, channel: channel),
                  let source = location(inputs, channel: firstTapChannel + channel)
            else { continue }
            let frames = min(destination.frames, source.frames)
            for frame in 0..<frames {
                destination.pointer[frame * destination.stride] = source.pointer[frame * source.stride] * gain
            }
        }
    }

    nonisolated private static func location(
        _ list: UnsafeMutableAudioBufferListPointer,
        channel: Int
    ) -> (pointer: UnsafeMutablePointer<Float32>, stride: Int, frames: Int)? {
        var remaining = channel
        for buffer in list {
            let count = Int(buffer.mNumberChannels)
            if remaining < count {
                guard let data = buffer.mData, count > 0 else { return nil }
                let frames = Int(buffer.mDataByteSize) / (MemoryLayout<Float32>.size * count)
                return (data.assumingMemoryBound(to: Float32.self) + remaining, count, frames)
            }
            remaining -= count
        }
        return nil
    }
}

/// "System Audio Recording" access, which process taps need. There is no
/// public API to read it, so this goes through TCC the same way Apple's own
/// sample (AudioCap) does.
private enum SystemAudioCapturePermission {
    enum Status { case authorized, denied, unknown }

    private static var service: CFString { "kTCCServiceAudioCapture" as CFString }
    nonisolated(unsafe) private static let handle = dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW)

    private typealias Preflight = @convention(c) (CFString, CFDictionary?) -> Int
    private typealias Request = @convention(c) (CFString, CFDictionary?, @escaping @convention(block) (Bool) -> Void) -> Void

    static var status: Status {
        guard let handle, let symbol = dlsym(handle, "TCCAccessPreflight") else { return .unknown }
        let preflight = unsafeBitCast(symbol, to: Preflight.self)
        switch preflight(service, nil) {
        case 0: return .authorized
        case 1: return .denied
        default: return .unknown
        }
    }

    static func request() async -> Bool {
        guard let handle, let symbol = dlsym(handle, "TCCAccessRequest") else { return false }
        let request = unsafeBitCast(symbol, to: Request.self)
        return await withCheckedContinuation { continuation in
            request(service, nil) { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}

// MARK: - Core Audio

/// Thin readers and writers over the Core Audio object properties used above.
private enum SystemCoreAudio {
    private static func makeAddress(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func read<T: BitwiseCopyable>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, initial: T) -> T? {
        var address = makeAddress(selector, scope: scope)
        guard AudioObjectHasProperty(object, &address) else { return nil }
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func readArray(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> [AudioObjectID] {
        var address = makeAddress(selector, scope: scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var values = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &values) == noErr else { return [] }
        return Array(values.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    private static func readString(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = makeAddress(selector)
        guard AudioObjectHasProperty(object, &address) else { return nil }
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr,
              let value
        else { return nil }
        return value.takeRetainedValue() as String
    }

    private static func write<T: BitwiseCopyable>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, _ value: T) {
        var address = makeAddress(selector, scope: scope)
        var value = value
        AudioObjectSetPropertyData(object, &address, 0, nil, UInt32(MemoryLayout<T>.size), &value)
    }

    private static func isSettable(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope) -> Bool {
        var address = makeAddress(selector, scope: scope)
        guard AudioObjectHasProperty(object, &address) else { return false }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(object, &address, &settable) == noErr && settable.boolValue
    }

    // Devices

    static func deviceIDs() -> [AudioDeviceID] {
        readArray(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices)
    }

    static func defaultDevice(input: Bool) -> AudioDeviceID {
        read(
            AudioObjectID(kAudioObjectSystemObject),
            input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice,
            initial: AudioDeviceID(0)
        ) ?? 0
    }

    static func setDefaultOutput(_ device: AudioDeviceID) {
        write(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, device)
    }

    static func defaultOutputUID() -> String? {
        let device = defaultDevice(input: false)
        return device == 0 ? nil : readString(device, kAudioDevicePropertyDeviceUID)
    }

    static func hasStreams(_ device: AudioDeviceID, scope: AudioObjectPropertyScope) -> Bool {
        !readArray(device, kAudioDevicePropertyStreams, scope: scope).isEmpty
    }

    static func name(of device: AudioDeviceID) -> String? {
        readString(device, kAudioObjectPropertyName)
    }

    static func transportType(_ device: AudioDeviceID) -> UInt32 {
        read(device, kAudioDevicePropertyTransportType, initial: UInt32(0)) ?? 0
    }

    static func isHidden(_ device: AudioDeviceID) -> Bool {
        (read(device, kAudioDevicePropertyIsHidden, initial: UInt32(0)) ?? 0) != 0
    }

    // Input

    static func inputVolume(_ device: AudioDeviceID) -> Double? {
        if let volume = read(device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: kAudioObjectPropertyScopeInput, initial: Float32(0)) {
            return Double(volume)
        }
        return read(device, kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeInput, initial: Float32(0)).map(Double.init)
    }

    static func setInputVolume(_ device: AudioDeviceID, _ volume: Double) {
        let value = Float32(min(max(volume, 0), 1))
        if isSettable(device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: kAudioObjectPropertyScopeInput) {
            write(device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: kAudioObjectPropertyScopeInput, value)
        } else if isSettable(device, kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeInput) {
            write(device, kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeInput, value)
        }
    }

    static func inputMute(_ device: AudioDeviceID) -> Bool? {
        guard canSetInputMute(device) else { return nil }
        return read(device, kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeInput, initial: UInt32(0)).map { $0 != 0 }
    }

    static func canSetInputMute(_ device: AudioDeviceID) -> Bool {
        isSettable(device, kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeInput)
    }

    static func setInputMute(_ device: AudioDeviceID, _ muted: Bool) {
        write(device, kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeInput, UInt32(muted ? 1 : 0))
    }

    // Processes and taps

    static func processObjects() -> [AudioObjectID] {
        readArray(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList)
    }

    static func processPID(_ process: AudioObjectID) -> pid_t {
        read(process, kAudioProcessPropertyPID, initial: pid_t(-1)) ?? -1
    }

    static func processBundleID(_ process: AudioObjectID) -> String? {
        readString(process, kAudioProcessPropertyBundleID).flatMap { $0.isEmpty ? nil : $0 }
    }

    static func isRunningOutput(_ process: AudioObjectID) -> Bool {
        (read(process, kAudioProcessPropertyIsRunningOutput, initial: UInt32(0)) ?? 0) != 0
    }

    static func tapChannelCount(_ tap: AudioObjectID) -> UInt32? {
        read(tap, kAudioTapPropertyFormat, initial: AudioStreamBasicDescription()).map(\.mChannelsPerFrame)
    }
}

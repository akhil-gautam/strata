import AppKit
import SwiftUI

// MARK: - State

/// A short notice the island drops down from the notch ("omp needs you",
/// "Timer done").
struct IslandPeek: Identifiable {
    let id = UUID()
    var symbol: String
    var tint: Color
    var title: String
    var subtitle: String?
    /// Runs on click; the peek closes either way.
    var action: (@MainActor () -> Void)?
    var duration: TimeInterval = 5
}

/// The notch island's state: collapsed around the camera housing, showing a
/// peek, or expanded into the full bar. The bar controller owns the window
/// and the pointer tracking; tiles and services only call `show(_:)`.
@MainActor
@Observable
final class DockIsland {
    static let shared = DockIsland()

    enum Phase: Equatable {
        case collapsed, peek, expanded
    }

    private(set) var isExpanded = false
    private(set) var peek: IslandPeek?

    var phase: Phase {
        if isExpanded { return .expanded }
        return peek == nil ? .collapsed : .peek
    }

    /// Set by the bar controller: the bar sits at the notch in island style.
    /// Peeks are dropped while it is off.
    @ObservationIgnored var isEnabled = false {
        didSet {
            guard !isEnabled, oldValue else { return }
            isExpanded = false
            dismissPeek()
        }
    }

    /// Called after every phase change, so the controller can let clicks
    /// through while the island is collapsed.
    @ObservationIgnored var onPhaseChange: (() -> Void)?

    @ObservationIgnored private var queue: [IslandPeek] = []
    @ObservationIgnored private var dismissal: Task<Void, Never>?
    @ObservationIgnored private var isHoveringPeek = false

    private init() {}

    func setExpanded(_ expanded: Bool) {
        guard expanded != isExpanded else { return }
        isExpanded = expanded
        // Expanding shows everything a peek would; queued peeks are stale.
        if expanded {
            queue.removeAll()
            dismissPeek()
        }
        onPhaseChange?()
    }

    /// Drops `peek` down from the notch, after any peek already showing.
    func show(_ peek: IslandPeek) {
        guard isEnabled, !isExpanded else { return }
        guard self.peek != nil else {
            present(peek)
            return
        }
        queue.append(peek)
    }

    func dismissPeek() {
        dismissal?.cancel()
        dismissal = nil
        isHoveringPeek = false
        guard peek != nil else { return }
        peek = nil
        if let next = queue.first, !isExpanded {
            queue.removeFirst()
            present(next)
        } else {
            onPhaseChange?()
        }
    }

    /// The pointer rests on the peek: it stays until the pointer leaves.
    func hoverPeek(_ hovering: Bool) {
        guard peek != nil, hovering != isHoveringPeek else { return }
        isHoveringPeek = hovering
        if hovering {
            dismissal?.cancel()
            dismissal = nil
        } else {
            scheduleDismissal(after: 1.5)
        }
    }

    func activatePeek() {
        let action = peek?.action
        dismissPeek()
        action?()
    }

    private func present(_ next: IslandPeek) {
        peek = next
        onPhaseChange?()
        scheduleDismissal(after: next.duration)
    }

    private func scheduleDismissal(after seconds: TimeInterval) {
        dismissal?.cancel()
        let id = peek?.id
        dismissal = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self, self.peek?.id == id else { return }
            self.dismissPeek()
        }
    }
}

// MARK: - Geometry

/// Sizes the island view needs, computed by the bar controller for the
/// bar's screen. The window changes size with the phase; the view keeps
/// its shapes centred at the top of it.
struct DockIslandLayout: Equatable {
    /// Room for the glow around the lifted shape.
    var glow: CGFloat
    /// The camera housing's width; zero on displays without a notch.
    var housingWidth: CGFloat
    /// The strip beside the housing, as tall as the menu bar.
    var bandHeight: CGFloat
    /// The expanded bar: tiles plus the band above them.
    var expandedSize: CGSize

    static let earWidth: CGFloat = 74
    static let peekSize = CGSize(width: 360, height: 60)

    var hasNotch: Bool { housingWidth > 0 }

    func collapsedSize(hasActivity: Bool) -> CGSize {
        guard hasActivity else {
            // Exactly the housing: the island disappears into the notch.
            return CGSize(width: housingWidth, height: hasNotch ? bandHeight : 0)
        }
        let gap = hasNotch ? housingWidth : 10
        return CGSize(width: gap + Self.earWidth * 2, height: hasNotch ? bandHeight : bandHeight - 4)
    }

    var peekShapeSize: CGSize {
        CGSize(
            width: max(Self.peekSize.width, housingWidth + Self.earWidth * 2),
            height: bandHeight + Self.peekSize.height
        )
    }
}

/// The bar window's content: the plain bar, or the bar inside the notch
/// island.
struct DockBarRoot: View {
    let bar: DockBarView
    let island: DockIslandLayout?
    let actions: DockBarActions

    var body: some View {
        if let island {
            DockIslandView(bar: bar, layout: island, actions: actions)
        } else {
            bar
        }
    }
}

// MARK: - Views

/// The bar at the notch in island style. The shape grows out of the
/// housing; the tiles are revealed inside it as it expands.
struct DockIslandView: View {
    let bar: DockBarView
    let layout: DockIslandLayout
    let actions: DockBarActions

    private var island: DockIsland { .shared }

    var body: some View {
        let activity = IslandActivity.current
        let phase = island.phase
        let size = shapeSize(phase, hasActivity: activity != nil)
        let radius = cornerRadius(phase)
        let shape = UnevenRoundedRectangle(
            cornerRadii: RectangleCornerRadii(bottomLeading: radius, bottomTrailing: radius),
            style: .continuous
        )
        let glow = phase == .peek ? (island.peek?.tint ?? TilePalette.focus) : TilePalette.focus
        let lifted = phase != .collapsed

        ZStack(alignment: .top) {
            shape
                .fill(.black)
                .overlay { shape.strokeBorder(.white.opacity(lifted ? 0.1 : 0), lineWidth: 1) }
                .frame(width: size.width, height: size.height)
                .shadow(color: glow.opacity(lifted ? 0.55 : 0), radius: 18, y: 4)
                .shadow(color: glow.opacity(lifted ? 0.3 : 0), radius: 5)

            ZStack(alignment: .top) {
                bar
                    .frame(width: layout.expandedSize.width, height: layout.expandedSize.height)
                    .opacity(phase == .expanded ? 1 : 0)
                    .scaleEffect(phase == .expanded ? 1 : 0.94, anchor: .top)
                    .allowsHitTesting(phase == .expanded)
                IslandHeader(width: layout.expandedSize.width, layout: layout, actions: actions)
                    .opacity(phase == .expanded ? 1 : 0)
                    .allowsHitTesting(phase == .expanded)
                if phase != .expanded, let activity {
                    IslandEars(activity: activity, layout: layout)
                        .transition(.opacity)
                }
                if phase == .peek, let peek = island.peek {
                    IslandPeekCard(peek: peek, width: size.width)
                        .padding(.top, layout.bandHeight)
                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
                }
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .clipShape(shape)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: phase)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: activity != nil)
        .environment(\.colorScheme, .dark)
    }

    private func shapeSize(_ phase: DockIsland.Phase, hasActivity: Bool) -> CGSize {
        switch phase {
        case .collapsed: layout.collapsedSize(hasActivity: hasActivity)
        case .peek: layout.peekShapeSize
        case .expanded: layout.expandedSize
        }
    }

    private func cornerRadius(_ phase: DockIsland.Phase) -> CGFloat {
        switch phase {
        case .collapsed: layout.hasNotch ? 11 : (layout.bandHeight - 4) / 2
        case .peek: 20
        case .expanded: max(TileMetrics.barCorner, 20)
        }
    }
}

/// What the collapsed island shows beside the housing, most urgent first.
enum IslandActivity: Equatable {
    case agentNeedsYou(AgentSession)
    case focus
    case agentWorking(AgentSession)
    case awake
    case music

    @MainActor
    static var current: IslandActivity? {
        let sessions = AgentSessions.shared.sessions
        if let session = sessions.first(where: { $0.state == .needsYou }) { return .agentNeedsYou(session) }
        if FocusTimer.shared.isRunning { return .focus }
        if let session = sessions.first(where: { $0.state == .working }) { return .agentWorking(session) }
        if KeepAwake.shared.isActive { return .awake }
        if NowPlayingService.shared.isPlaying { return .music }
        return nil
    }
}

/// A glyph on the left of the housing, a short readout on the right, like
/// the compact Dynamic Island.
private struct IslandEars: View {
    let activity: IslandActivity
    let layout: DockIslandLayout

    var body: some View {
        HStack(spacing: 0) {
            leading
                .frame(width: DockIslandLayout.earWidth - 14, alignment: .leading)
                .padding(.leading, 14)
            Spacer(minLength: layout.hasNotch ? layout.housingWidth : 10)
            trailing
                .frame(width: DockIslandLayout.earWidth - 14, alignment: .trailing)
                .padding(.trailing, 14)
        }
        // The stack around it is as wide as the expanded bar; the ears
        // hug the housing whatever the island's shape.
        .frame(
            width: layout.collapsedSize(hasActivity: true).width,
            height: layout.hasNotch ? layout.bandHeight : layout.bandHeight - 4
        )
        .lineLimit(1)
        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private var leading: some View {
        switch activity {
        case .agentNeedsYou:
            // Still glyphs throughout: a looping effect keeps the whole
            // window redrawing for as long as it shows.
            Image(systemName: "hand.raised.fill")
                .foregroundStyle(DockAccent.orange)
        case .focus:
            let phase = FocusTimer.shared.phase
            // The cup is Keep Awake's.
            Image(systemName: phase == .focus ? "brain.head.profile" : "leaf.fill")
                .foregroundStyle(phase == .focus ? DockAccent.orange : DockAccent.green)
        case let .agentWorking(session):
            Circle()
                .fill(AIUsageFormat.brand(session.tool))
                .frame(width: 7, height: 7)
        case .awake:
            Image(systemName: "cup.and.saucer.fill")
                .foregroundStyle(DockAccent.orange)
        case .music:
            if let artwork = NowPlayingService.shared.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 18, height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else {
                Image(systemName: "music.note")
            }
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch activity {
        case let .agentNeedsYou(session), let .agentWorking(session):
            Text(session.project)
                .foregroundStyle(.white.opacity(0.85))
                .truncationMode(.tail)
        case .focus:
            Text(FocusTimer.shared.formatted)
                .monospacedDigit()
        case .awake:
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                Text(KeepAwake.shared.remaining(at: timeline.date).map(KeepAwake.format) ?? "Awake")
                    .monospacedDigit()
            }
        case .music:
            Image(systemName: "waveform")
                .foregroundStyle(DockAccent.green)
        }
    }
}

/// The strip beside the housing in the expanded island: the date and time
/// on the left, the widget library and settings on the right.
private struct IslandHeader: View {
    let width: CGFloat
    let layout: DockIslandLayout
    let actions: DockBarActions

    var body: some View {
        let side = max((width - layout.housingWidth) / 2, 0)
        HStack(spacing: 0) {
            TimelineView(.everyMinute) { context in
                Text(context.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .padding(.leading, 18)
            .frame(width: side, alignment: .leading)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                IslandHeaderButton(symbol: "square.grid.2x2", help: "Widgets", action: actions.openLibrary)
                IslandHeaderButton(symbol: "gearshape.fill", help: "Settings", action: actions.openBarSettings)
            }
            .padding(.trailing, 14)
            .frame(width: side, alignment: .trailing)
        }
        .frame(width: width, height: layout.bandHeight)
    }
}

private struct IslandHeaderButton: View {
    let symbol: String
    let help: String
    let action: @MainActor () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white.opacity(isHovering ? 1 : 0.7))
                .frame(width: 24, height: 20)
                .background {
                    Capsule().fill(.white.opacity(isHovering ? 0.16 : 0.08))
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
        .help(help)
    }
}

/// The card a peek drops below the housing.
private struct IslandPeekCard: View {
    let peek: IslandPeek
    let width: CGFloat

    var body: some View {
        Button {
            DockIsland.shared.activatePeek()
        } label: {
            HStack(spacing: 11) {
                Image(systemName: peek.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(peek.tint)
                    .frame(width: 32, height: 32)
                    .background { Circle().fill(peek.tint.opacity(0.18)) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(peek.title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    if let subtitle = peek.subtitle {
                        Text(subtitle)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 0)
                if peek.action != nil {
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .padding(.horizontal, 16)
            .frame(width: width, height: DockIslandLayout.peekSize.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { DockIsland.shared.hoverPeek($0) }
    }
}

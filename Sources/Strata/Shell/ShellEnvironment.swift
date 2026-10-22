import AppKit
import SwiftUI

private struct OpenTileSettingsKey: EnvironmentKey {
    static let defaultValue: @MainActor @Sendable () -> Void = {}
}

extension EnvironmentValues {
    /// Opens the settings popover of the tile reading it, beside the tile on
    /// the bar's inner side. Set by the bar for every tile whose spec has
    /// `settings`; a service tile's "Connect" state calls it to show its
    /// token entry.
    var openTileSettings: @MainActor @Sendable () -> Void {
        get { self[OpenTileSettingsKey.self] }
        set { self[OpenTileSettingsKey.self] = newValue }
    }
}

/// An `NSMenuItem` that runs a closure.
@MainActor
final class ShellMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(_ title: String, handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func run() {
        handler()
    }
}

// MARK: - Theme

extension ColorScheme {
    /// The AppKit appearance matching a theme's scheme, for windows, menus
    /// and materials: light themes get light controls and menus.
    var nsAppearance: NSAppearance? {
        NSAppearance(named: self == .light ? .aqua : .darkAqua)
    }
}

extension View {
    /// Paints a shell surface (the bar, the library, a popover): an optional
    /// blur of what is behind the window, the fill on top, the border over
    /// the content, everything clipped to `shape`. `openTop` leaves the top
    /// edge unbordered (the notch bar, flush with the top of the screen).
    func shellSurface<S: InsettableShape>(
        _ shape: S,
        fill: ThemeFill,
        blur: Bool,
        border: Color,
        borderWidth: CGFloat,
        appearance: ColorScheme,
        openTop: Bool = false
    ) -> some View {
        background {
            ZStack {
                if blur {
                    ShellBlur(appearance: appearance)
                }
                shape.fill(fill.style)
            }
            .clipShape(shape)
        }
        .overlay {
            if borderWidth > 0 {
                // Stroked one line taller, so the clip drops the top edge.
                shape.strokeBorder(border, lineWidth: borderWidth)
                    .padding(.top, openTop ? -borderWidth : 0)
            }
        }
        .clipShape(shape)
    }
}

/// The blur behind a translucent shell surface.
private struct ShellBlur: NSViewRepresentable {
    let appearance: ColorScheme

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.appearance = appearance.nsAppearance
    }
}

// MARK: - Placement

extension DockPosition {
    /// Unit vector from the bar's screen edge toward the screen's centre:
    /// the side the library, popovers and tooltips open on.
    var inward: CGVector {
        switch self {
        case .bottom: CGVector(dx: 0, dy: 1)
        case .notch: CGVector(dx: 0, dy: -1)
        case .left: CGVector(dx: 1, dy: 0)
        case .right: CGVector(dx: -1, dy: 0)
        }
    }

    /// A frame of `size` on the inner side of `bar`, `gap` away from it,
    /// centred on `anchor` along the bar and kept `margin` inside `bounds`
    /// along the bar.
    func frame(
        ofSize size: CGSize,
        beside bar: NSRect,
        centredOn anchor: NSRect,
        gap: CGFloat,
        within bounds: NSRect,
        margin: CGFloat
    ) -> NSRect {
        let inner = bounds.insetBy(dx: margin, dy: margin)
        var origin: CGPoint
        switch self {
        case .bottom:
            origin = CGPoint(x: anchor.midX - size.width / 2, y: bar.maxY + gap)
        case .notch:
            origin = CGPoint(x: anchor.midX - size.width / 2, y: bar.minY - gap - size.height)
        case .left:
            origin = CGPoint(x: bar.maxX + gap, y: anchor.midY - size.height / 2)
        case .right:
            origin = CGPoint(x: bar.minX - gap - size.width, y: anchor.midY - size.height / 2)
        }
        if isVertical {
            origin.y = max(inner.minY, min(origin.y, inner.maxY - size.height))
        } else {
            origin.x = max(inner.minX, min(origin.x, inner.maxX - size.width))
        }
        return NSRect(origin: CGPoint(x: origin.x.rounded(), y: origin.y.rounded()), size: size)
    }
}

extension NSScreen {
    /// The screen showing `rect`, or the main display when it is off screen
    /// (an auto-hidden bar).
    static func showing(_ rect: NSRect) -> NSScreen? {
        screens.first { $0.frame.intersects(rect) } ?? screens.first
    }
}

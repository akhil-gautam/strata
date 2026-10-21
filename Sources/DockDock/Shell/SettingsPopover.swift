import AppKit
import SwiftUI

/// The small panel a tile's "Customize…" item opens beside it, on the bar's
/// inner side (video f57–f76): symbol, title, optional count badge, close
/// button, and the tile's own settings underneath.
@MainActor
final class SettingsPopoverController {
    /// The tallest the popover grows; longer settings scroll under the header.
    static let maxHeight: CGFloat = 360
    /// Gap between the bar's inner edge and the popover.
    static let gap: CGFloat = 6

    private var panel: SettingsPopoverPanel?
    private var monitors: [Any] = []
    /// The tile the popover belongs to, in screen coordinates.
    private var anchor: NSRect = .zero
    /// The bar the tile sits on, in screen coordinates.
    private var bar: NSRect = .zero

    /// The id of the tile whose settings are showing.
    private(set) var openID: String?

    var isOpen: Bool { panel != nil }

    init() {
        let center = NotificationCenter.default
        center.addObserver(forName: .dockThemeDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.panel?.appearance = AppearanceStore.shared.theme.appearance.nsAppearance
            }
        }
        // The bar is leaving for another edge; the popover would be left
        // hanging beside nothing.
        center.addObserver(forName: .dockPositionDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.close()
            }
        }
    }

    func open(
        id: String,
        title: String,
        settings: TileSettings,
        anchor: NSRect,
        bar: NSRect
    ) {
        close()
        self.anchor = anchor
        self.bar = bar
        openID = id
        DockBarState.shared.selectedID = id

        let panel = SettingsPopoverPanel(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: 25)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.appearance = AppearanceStore.shared.theme.appearance.nsAppearance

        let host = NSHostingView(
            rootView: SettingsPopoverView(
                title: settings.title ?? title,
                settings: settings,
                onClose: { [weak self] in self?.close() },
                onSize: { [weak self] size in self?.place(size) }
            )
        )
        host.sizingOptions = []
        panel.contentView = host
        self.panel = panel

        place(host.fittingSize)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
        installMonitors()
    }

    func close() {
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors.removeAll()
        openID = nil
        DockBarState.shared.selectedID = nil
        guard let panel else { return }
        self.panel = nil
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated {
                panel.orderOut(nil)
            }
        }
    }

    /// Centres the popover on its tile, just past the bar's inner edge,
    /// inside the screen.
    private func place(_ size: CGSize) {
        guard let panel, size.width > 0, size.height > 0 else { return }
        let frame = AppearanceStore.shared.position.frame(
            ofSize: size,
            beside: bar,
            centredOn: anchor,
            gap: Self.gap,
            within: NSScreen.showing(bar)?.visibleFrame ?? bar,
            margin: 8
        )
        panel.setFrame(frame, display: true)
        panel.invalidateShadow()
    }

    /// Escape closes; so does a click anywhere outside the popover.
    private func installMonitors() {
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let local = NSEvent.addLocalMonitorForEvents(matching: clicks, handler: { [weak self] event in
            MainActor.assumeIsolated {
                if let self, event.window !== self.panel {
                    self.close()
                }
            }
            return event
        }) {
            monitors.append(local)
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { [weak self] _ in
            MainActor.assumeIsolated {
                self?.close()
            }
        }) {
            monitors.append(global)
        }
        if let keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            let handled = MainActor.assumeIsolated {
                guard let self, event.keyCode == 53, event.window === self.panel else { return false }
                self.close()
                return true
            }
            return handled ? nil : event
        }) {
            monitors.append(keys)
        }
    }
}

/// Takes key focus without activating the app, so the settings' controls
/// and text fields work.
private final class SettingsPopoverPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct SettingsPopoverView: View {
    let title: String
    let settings: TileSettings
    let onClose: () -> Void
    let onSize: (CGSize) -> Void

    @State private var contentHeight: CGFloat = 0

    private static let padding: CGFloat = 12
    private static let headerHeight: CGFloat = 18
    private static let spacing: CGFloat = 10
    private static var maxBodyHeight: CGFloat {
        SettingsPopoverController.maxHeight - padding * 2 - headerHeight - spacing
    }

    /// Scales with the theme's bar corner (Midnight's 18 gives 16).
    private var corner: CGFloat { TileMetrics.barCorner * 16 / 18 }

    var body: some View {
        let theme = AppearanceStore.shared.theme
        VStack(alignment: .leading, spacing: Self.spacing) {
            SettingsPopoverHeader(
                symbol: settings.symbol,
                title: title,
                badge: settings.badge,
                onClose: onClose
            )
            .frame(height: Self.headerHeight)

            ScrollView(.vertical) {
                settings.content()
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        contentHeight = height
                    }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(contentHeight, Self.maxBodyHeight))
        }
        .padding(Self.padding)
        .frame(minWidth: 230, alignment: .leading)
        .shellSurface(
            RoundedRectangle(cornerRadius: corner, style: .continuous),
            fill: theme.panelFill,
            blur: theme.panelBlur,
            border: theme.panelBorder,
            borderWidth: theme.barBorderWidth,
            appearance: theme.appearance
        )
        .fixedSize()
        .environment(\.colorScheme, theme.appearance)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            onSize(size)
        }
    }
}

private struct SettingsPopoverHeader: View {
    let symbol: String
    let title: String
    let badge: (@MainActor () -> String?)?
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(TilePalette.ink.opacity(0.9))
            Text(title)
                .font(.tileText(12.5, weight: .semibold))
                .foregroundStyle(TilePalette.ink)
                .lineLimit(1)
            if let value = badge?() {
                Text(value)
                    .font(.tileText(9.5, weight: .semibold))
                    .foregroundStyle(TilePalette.caption)
                    .monospacedDigit()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background { Capsule().fill(TilePalette.ink.opacity(0.1)) }
            }
            Spacer(minLength: 16)
            ShellCloseButton(diameter: 16, action: onClose)
        }
    }
}

/// The circular close button of the library and the popovers: an
/// ink-tinted disc with the cross cut out of it.
struct ShellCloseButton: View {
    var diameter: CGFloat = 16
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(TilePalette.ink.opacity(0.62))
                .overlay {
                    // Cut out, so the cross shows the panel's own surface.
                    Image(systemName: "xmark")
                        .font(.system(size: diameter * 0.42, weight: .bold))
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
                .frame(width: diameter, height: diameter)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Close")
    }
}

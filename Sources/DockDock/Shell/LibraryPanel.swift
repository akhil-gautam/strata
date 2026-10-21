import AppKit
import SwiftUI

/// The "Widgets" library beside the bar (video f10–f53): a searchable,
/// scrolling catalogue of every tile, grouped by category. Clicking a tile
/// adds it to the bar.
@MainActor
final class LibraryPanelController {
    static let size = NSSize(width: 615, height: 370)
    /// Gap between the panel and the bar's inner edge.
    static let gap: CGFloat = 7
    /// How far the panel travels toward its place as it opens.
    private static let openTravel: CGFloat = 10

    private let panel: LibraryPanelWindow
    private let model = LibraryModel()
    private var keyMonitor: Any?

    /// A library tile was clicked.
    var onAdd: ((String) -> Void)?
    /// The panel opened or closed.
    var onVisibilityChange: ((Bool) -> Void)?

    private(set) var isVisible = false

    init() {
        panel = LibraryPanelWindow(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: 24)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = false

        let host = NSHostingView(
            rootView: LibraryPanelView(
                model: model,
                onAdd: { [weak self] id in self?.onAdd?(id) },
                onClose: { [weak self] in self?.hide() }
            )
        )
        host.sizingOptions = []
        panel.contentView = host
        panel.appearance = AppearanceStore.shared.theme.appearance.nsAppearance

        NotificationCenter.default.addObserver(forName: .dockThemeDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.panel.appearance = AppearanceStore.shared.theme.appearance.nsAppearance
            }
        }
    }

    /// Opens the panel on the inner side of `barFrame`, centred on the bar.
    func show(beside barFrame: NSRect) {
        let target = frame(beside: barFrame)
        if !isVisible {
            isVisible = true
            model.query = ""
            let inward = AppearanceStore.shared.position.inward
            panel.setFrame(
                target.offsetBy(dx: -inward.dx * Self.openTravel, dy: -inward.dy * Self.openTravel),
                display: true
            )
            panel.alphaValue = 0
            panel.makeKeyAndOrderFront(nil)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(target, display: true)
                panel.animator().alphaValue = 1
            }
            model.focusRequest += 1
            installKeyMonitor()
            onVisibilityChange?(true)
        } else {
            panel.setFrame(target, display: true)
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        let panel = panel
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            panel.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated {
                // Re-opened while fading out: keep it on screen.
                guard panel.alphaValue == 0 else { return }
                panel.orderOut(nil)
            }
        }
        onVisibilityChange?(false)
    }

    /// Follows the bar when it moves, changes size or changes edge.
    func place(beside barFrame: NSRect) {
        guard isVisible else { return }
        panel.setFrame(frame(beside: barFrame), display: true)
    }

    private func frame(beside barFrame: NSRect) -> NSRect {
        AppearanceStore.shared.position.frame(
            ofSize: Self.size,
            beside: barFrame,
            centredOn: barFrame,
            gap: Self.gap,
            within: NSScreen.showing(barFrame)?.visibleFrame ?? barFrame,
            margin: 8
        )
    }

    /// Escape clears the search, then closes the panel.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated {
                guard let self, event.keyCode == 53, event.window === self.panel else { return false }
                if self.model.query.isEmpty {
                    self.hide()
                } else {
                    self.model.query = ""
                }
                return true
            }
            return handled ? nil : event
        }
    }
}

/// Takes key focus without activating the app, so the search field works.
private final class LibraryPanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
@Observable
private final class LibraryModel {
    var query = ""
    /// Bumped on every open so the search field takes focus.
    var focusRequest = 0
}

// MARK: - Views

private struct LibraryPanelView: View {
    @Bindable var model: LibraryModel
    let onAdd: (String) -> Void
    let onClose: () -> Void

    @FocusState private var searchFocused: Bool

    private static let inset: CGFloat = 14

    /// Scales with the theme's bar corner (Midnight's 18 gives 19).
    private var corner: CGFloat { TileMetrics.barCorner * 19 / 18 }

    private struct Section: Identifiable {
        let category: TileCategory
        let specs: [TileSpec]
        var id: TileCategory { category }
    }

    private var sections: [Section] {
        let query = model.query.trimmingCharacters(in: .whitespaces)
        return TileCategory.allCases.compactMap { category in
            let specs = TileCatalog.available.filter { spec in
                guard spec.category == category else { return false }
                return query.isEmpty
                    || spec.title.localizedCaseInsensitiveContains(query)
                    || category.title.localizedCaseInsensitiveContains(query)
            }
            return specs.isEmpty ? nil : Section(category: category, specs: specs)
        }
    }

    var body: some View {
        let theme = AppearanceStore.shared.theme
        VStack(spacing: 0) {
            header
                .padding(.horizontal, Self.inset)
                .padding(.top, 10)
                .padding(.bottom, 8)

            let sections = sections
            if sections.isEmpty {
                Text("No widgets match “\(model.query)”")
                    .font(.tileText(12, weight: .medium))
                    .foregroundStyle(TilePalette.caption)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(sections) { section in
                            LibrarySection(category: section.category, specs: section.specs, onAdd: onAdd)
                        }
                    }
                    .padding(.horizontal, Self.inset)
                    .padding(.top, 4)
                    .padding(.bottom, Self.inset)
                }
                .scrollIndicators(.automatic)
                .environment(\.tileContext, .library)
            }
        }
        .frame(width: LibraryPanelController.size.width, height: LibraryPanelController.size.height)
        .shellSurface(
            RoundedRectangle(cornerRadius: corner, style: .continuous),
            fill: theme.panelFill,
            blur: theme.panelBlur,
            border: theme.panelBorder,
            borderWidth: theme.barBorderWidth,
            appearance: theme.appearance
        )
        .environment(\.colorScheme, theme.appearance)
        .onChange(of: model.focusRequest, initial: true) {
            searchFocused = true
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Widgets")
                .font(.tileText(15, weight: .bold))
                .foregroundStyle(TilePalette.ink)

            Text("\(TileCatalog.available.count)")
                .font(.tileText(10.5, weight: .semibold))
                .foregroundStyle(TilePalette.ink.opacity(0.62))
                .monospacedDigit()
                .padding(.horizontal, 7)
                .frame(height: 17)
                .background { Capsule().fill(TilePalette.ink.opacity(0.1)) }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(TilePalette.caption)
                TextField("Search widgets", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.tileText(12.5, weight: .medium))
                    .foregroundStyle(TilePalette.ink)
                    .tint(TilePalette.focus)
                    .focused($searchFocused)
            }
            .padding(.horizontal, 10)
            .frame(height: 25)
            .frame(maxWidth: .infinity)
            .background { Capsule().fill(TilePalette.ink.opacity(0.07)) }
            .overlay {
                Capsule().strokeBorder(
                    searchFocused ? TilePalette.focus : TilePalette.ink.opacity(0.1),
                    lineWidth: searchFocused ? 1.5 : 1
                )
            }
            .contentShape(Capsule())
            .onTapGesture { searchFocused = true }
            .padding(.leading, 6)

            ShellCloseButton(diameter: 17, action: onClose)
                .padding(.leading, 12)
        }
    }
}

private struct LibrarySection: View {
    let category: TileCategory
    let specs: [TileSpec]
    let onAdd: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: category.symbol)
                    .font(.system(size: 11.5, weight: .semibold))
                Text(category.title)
                    .font(.tileText(12.5, weight: .semibold))
            }
            .foregroundStyle(TilePalette.caption)

            if category.isIconGrid {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5),
                    spacing: 15
                ) {
                    ForEach(specs) { spec in
                        LibraryCell(spec: spec, onAdd: onAdd)
                    }
                }
            } else {
                LibraryFlowLayout(spacing: 10, lineSpacing: 15) {
                    ForEach(specs) { spec in
                        LibraryCell(spec: spec, onAdd: onAdd)
                    }
                }
            }
        }
    }
}

/// One library entry: the live tile preview with its name underneath.
private struct LibraryCell: View {
    let spec: TileSpec
    let onAdd: (String) -> Void

    @State private var isHovering = false

    var body: some View {
        Button {
            onAdd(spec.id)
        } label: {
            VStack(spacing: 7) {
                spec.make()
                    .allowsHitTesting(false)
                    .overlay {
                        if isHovering {
                            RoundedRectangle(cornerRadius: TileMetrics.corner, style: .continuous)
                                .fill(TilePalette.ink.opacity(0.05))
                            RoundedRectangle(cornerRadius: TileMetrics.corner, style: .continuous)
                                .strokeBorder(TilePalette.focus, lineWidth: 2)
                        }
                    }
                Text(spec.title)
                    .font(.tileText(10.5, weight: .medium))
                    .foregroundStyle(TilePalette.ink.opacity(0.7))
                    .lineLimit(1)
                    .fixedSize()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(LibraryCellButtonStyle())
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

/// No press dimming beyond a slight scale, like the video's library.
private struct LibraryCellButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Lays tiles out left to right and wraps, every row top-aligned.
private struct LibraryFlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.minX
            for (index, size) in zip(row.indices, row.sizes) {
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var sizes: [CGSize] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
            current.sizes.append(size)
        }
        if !current.indices.isEmpty {
            rows.append(current)
        }
        return rows
    }
}

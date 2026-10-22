import AppKit
import SwiftUI

/// The app's own switches, as the Settings window drives them. The app
/// delegate provides the closures so the window and the status menu run the
/// same code.
@MainActor
struct ShellControls {
    var isBarVisible: @MainActor () -> Bool
    var setBarVisible: @MainActor (Bool) -> Void
    var autoHidesBar: @MainActor () -> Bool
    var setAutoHidesBar: @MainActor (Bool) -> Void
    var hidesSystemDock: @MainActor () -> Bool
    var setHidesSystemDock: @MainActor (Bool) -> Void
}

/// The General section's state. The values live in the app delegate's
/// controllers; `refresh()` re-reads them after a change made elsewhere
/// (the status menu, the bar's own menu).
@MainActor
@Observable
final class ShellSettingsModel {
    @ObservationIgnored var controls: ShellControls?
    private var revision = 0

    func refresh() {
        revision += 1
    }

    var barVisible: Bool {
        get { _ = revision; return controls?.isBarVisible() ?? false }
        set { controls?.setBarVisible(newValue); refresh() }
    }

    var autoHidesBar: Bool {
        get { _ = revision; return controls?.autoHidesBar() ?? false }
        set { controls?.setAutoHidesBar(newValue); refresh() }
    }

    var hidesSystemDock: Bool {
        get { _ = revision; return controls?.hidesSystemDock() ?? false }
        set { controls?.setHidesSystemDock(newValue); refresh() }
    }

    /// The sidebar's selection; `show(section:)` sets it.
    var section: SettingsSection = .general
}

/// The Settings window: general behaviour, bar position and theme.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    let model = ShellSettingsModel()
    private var window: NSWindow?

    /// Set once by the app delegate.
    var controls: ShellControls? {
        get { model.controls }
        set { model.controls = newValue; model.refresh() }
    }

    /// Re-reads the General switches after they changed outside the window.
    func refresh() {
        model.refresh()
    }

    /// Brings the Settings window to the front, creating it on first use,
    /// at `section` when given.
    func show(section: SettingsSection? = nil) {
        let window = window ?? makeWindow()
        self.window = window
        model.refresh()
        if let section {
            model.section = section
        }
        if !window.isVisible {
            window.center()
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: SettingsView(model: model))
        hosting.sizingOptions = []
        let window = SettingsNSWindow(
            contentRect: NSRect(origin: .zero, size: SettingsView.size),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hosting
        window.setContentSize(SettingsView.size)
        window.title = "Strata Settings"
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        return window
    }
}

/// Strata is an agent app with no main menu, so the window handles the
/// standard close shortcut itself.
private final class SettingsNSWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.charactersIgnoringModifiers == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

// MARK: - Root

enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case position
    case themes
    case extensions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .position: "Position"
        case .themes: "Themes"
        case .extensions: "Extensions"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .position: "rectangle.bottomhalf.inset.filled"
        case .themes: "paintpalette"
        case .extensions: "puzzlepiece.extension"
        }
    }
}

struct SettingsView: View {
    static let size = CGSize(width: 1000, height: 660)

    @Bindable var model: ShellSettingsModel

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $model.section) { section in
                Label(section.title, systemImage: section.symbol)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(190)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            SettingsSectionView(section: model.section, model: model)
                .navigationTitle(model.section.title)
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }
}

/// One section's content, without the sidebar.
struct SettingsSectionView: View {
    var section: SettingsSection
    var model: ShellSettingsModel

    var body: some View {
        switch section {
        case .general: GeneralSettingsView(model: model)
        case .position: PositionSettingsView()
        case .themes: ThemeSettingsView()
        case .extensions: ExtensionsSettingsView()
        }
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @Bindable var model: ShellSettingsModel

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $model.barVisible) {
                    Text("Show Strata bar")
                    Text("Puts the bar of widgets on screen.")
                }
                Toggle(isOn: $model.autoHidesBar) {
                    Text("Auto-hide Strata bar")
                    Text("The bar slides away until the pointer returns to its edge.")
                }
                Toggle(isOn: $model.hidesSystemDock) {
                    Text("Hide macOS Dock while the bar is shown")
                    Text("The macOS Dock comes back when the bar is hidden or Strata quits.")
                }
            } header: {
                Text("Strata Bar")
            }
            BarDisplaySettingsSection()
            DockFeaturesSettingsSection()
            StartupSettingsSection()
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
    }
}

// MARK: - Extensions

struct ExtensionsSettingsView: View {
    var body: some View {
        let extensions = ExtensionStore.shared
        Form {
            ForEach(DockExtension.allCases) { e in
                Section {
                    Toggle(isOn: Binding(
                        get: { extensions.isEnabled(e) },
                        set: { extensions.setEnabled(e, $0) }
                    )) {
                        Text(e.title)
                        Text(e.summary)
                    }
                    if extensions.isEnabled(e) {
                        switch e {
                        case .aiUsage: AIUsageExtensionStatus()
                        case .scripts: ScriptTilesStatusRows()
                        }
                    }
                } footer: {
                    switch e {
                    case .aiUsage:
                        Text("Claude limits use Claude Code's sign-in from your keychain; macOS asks once. Codex limits update whenever Codex runs. Token counts are read from ~/.claude and ~/.codex logs on this Mac.")
                    case .scripts:
                        Text(ScriptTilesStatusRows.footer)
                    }
                }
            }
            if extensions.isEnabled(.scripts) {
                ScriptTilesSettingsSection()
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
    }
}

/// Where the AI Usage extension reads from, and whether that works.
private struct AIUsageExtensionStatus: View {
    var body: some View {
        let store = AIUsageStore.shared
        LabeledContent("Claude Code") {
            switch store.claude {
            case .live(let limits):
                Text(["Connected", limits.plan].compactMap { $0 }.joined(separator: " · "))
            case .notSignedIn:
                Text("Not signed in")
            case .accessDenied:
                HStack {
                    Text("Keychain access denied")
                    Button("Allow Access") { store.retryClaudeAccess() }
                }
            case .expired:
                Text("Sign-in expired — open Claude Code")
            case .idle, .loading:
                Text("Checks when a Claude tile is on the bar")
            case .failed:
                Text("Couldn't load limits — Claude Code may have changed its API")
            }
        }
        LabeledContent("Codex") {
            switch store.codex {
            case .live(let limits):
                let relative = RelativeDateTimeFormatter().localizedString(for: limits.asOf, relativeTo: Date())
                Text(["Last activity \(relative)", limits.plan].compactMap { $0 }.joined(separator: " · "))
            case .noData:
                Text("No Codex sessions found")
            case .idle:
                Text("Checks when a Codex tile is on the bar")
            }
        }
    }
}

// MARK: - Position

struct PositionSettingsView: View {
    var body: some View {
        ScrollView {
            PositionPicker()
        }
    }
}

/// The Position section's content: one card per screen edge.
struct PositionPicker: View {
    private var store: AppearanceStore { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsHeader(
                title: "Bar position",
                subtitle: "Choose the screen edge Strata lives on. Changes apply right away."
            )
            HStack(spacing: 14) {
                ForEach(DockPosition.allCases) { position in
                    PositionCard(
                        position: position,
                        theme: store.theme,
                        isSelected: store.position == position
                    ) {
                        store.position = position
                    }
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PositionCard: View {
    var position: DockPosition
    var theme: DockTheme
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                PositionDiagram(position: position, theme: theme)
                    .frame(height: 110)
                HStack(spacing: 6) {
                    Text(position.title)
                        .font(.system(size: 13, weight: .semibold))
                    Spacer(minLength: 0)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Text(position.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .topLeading)
            }
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(isSelected ? 0.07 : 0.035))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color.primary.opacity(0.1),
                        lineWidth: isSelected ? 2.5 : 1
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private extension DockPosition {
    var detail: String {
        switch self {
        case .bottom: "Centred along the bottom edge, where the Dock sits."
        case .left: "A vertical column down the left edge."
        case .right: "A vertical column down the right edge."
        case .notch: "Hangs from the top edge around the camera notch."
        }
    }
}

/// A small screen with a menu bar and the Strata bar drawn where it sits.
private struct PositionDiagram: View {
    var position: DockPosition
    var theme: DockTheme

    private let menuBar: CGFloat = 8
    private let thickness: CGFloat = 12
    private let tileCount = 4

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .topLeading) {
                SettingsWallpaper()
                Rectangle()
                    .fill(Color.white.opacity(0.55))
                    .frame(width: size.width, height: menuBar)
                if position == .notch {
                    UnevenRoundedRectangle(bottomLeadingRadius: 3, bottomTrailingRadius: 3, style: .continuous)
                        .fill(Color.black)
                        .frame(width: 22, height: menuBar)
                        .offset(x: (size.width - 22) / 2)
                }
                bar
                    .frame(width: barSize(in: size).width, height: barSize(in: size).height)
                    .offset(barOrigin(in: size))
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.25), lineWidth: 1)
            }
        }
    }

    private var bar: some View {
        let corner = min(theme.barCorner * 0.25, 5)
        let shape = position == .notch
            ? AnyShape(UnevenRoundedRectangle(bottomLeadingRadius: corner, bottomTrailingRadius: corner, style: .continuous))
            : AnyShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        let tileCorner = min(theme.tileCorner * 0.2, 2.5)
        let tiles = ForEach(0..<tileCount, id: \.self) { _ in
            RoundedRectangle(cornerRadius: tileCorner, style: .continuous)
                .fill(theme.tileFill.style)
                .overlay {
                    RoundedRectangle(cornerRadius: tileCorner, style: .continuous)
                        .strokeBorder(theme.tileBorder, lineWidth: 0.5)
                }
        }
        return Group {
            if position.isVertical {
                VStack(spacing: 2) { tiles }
            } else {
                HStack(spacing: 2) { tiles }
            }
        }
        .padding(2)
        .background { shape.fill(theme.barFill.style) }
        .overlay { shape.stroke(theme.barBorder, lineWidth: 0.75) }
        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
    }

    private func barSize(in size: CGSize) -> CGSize {
        position.isVertical
            ? CGSize(width: thickness, height: size.height * 0.5)
            : CGSize(width: size.width * 0.46, height: thickness)
    }

    private func barOrigin(in size: CGSize) -> CGSize {
        let bar = barSize(in: size)
        let inset: CGFloat = 4
        switch position {
        case .bottom:
            return CGSize(width: (size.width - bar.width) / 2, height: size.height - bar.height - inset)
        case .left:
            return CGSize(width: inset, height: menuBar + (size.height - menuBar - bar.height) / 2)
        case .right:
            return CGSize(width: size.width - bar.width - inset, height: menuBar + (size.height - menuBar - bar.height) / 2)
        case .notch:
            return CGSize(width: (size.width - bar.width) / 2, height: 0)
        }
    }
}

// MARK: - Themes

struct ThemeSettingsView: View {
    var body: some View {
        ScrollView {
            ThemePicker()
        }
    }
}

/// The Themes section's content: every theme as a live miniature.
struct ThemePicker: View {
    private var store: AppearanceStore { .shared }
    private let columnCount = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsHeader(
                title: "Theme",
                subtitle: "Restyles the bar, its tiles, the widget library and tile settings. Changes apply right away."
            )
            Grid(horizontalSpacing: 14, verticalSpacing: 14) {
                ForEach(Array(stride(from: 0, to: DockThemes.all.count, by: columnCount)), id: \.self) { start in
                    GridRow(alignment: .top) {
                        ForEach(DockThemes.all[start..<min(start + columnCount, DockThemes.all.count)]) { theme in
                            ThemeCard(theme: theme, isSelected: store.themeID == theme.id) {
                                store.themeID = theme.id
                            }
                        }
                    }
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ThemeCard: View {
    var theme: DockTheme
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ThemePreview(theme: theme)
                    .frame(height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.18), lineWidth: 1)
                    }
                HStack(spacing: 6) {
                    Text(theme.name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Text(theme.summary)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(8)
            .background {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color.primary.opacity(isSelected ? 0.07 : 0.035))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color.primary.opacity(0.1),
                        lineWidth: isSelected ? 2.5 : 1
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A miniature bar drawn from one theme's tokens, on a desktop backdrop:
/// a clock, a value with a caption, a gauge and an accent play button.
struct ThemePreview: View {
    var theme: DockTheme

    /// Mock tiles are half the real 56 pt tile.
    private let scale: CGFloat = 0.5
    private var tileHeight: CGFloat { TileMetrics.height * scale }

    var body: some View {
        ZStack {
            SettingsWallpaper()
            bar
        }
    }

    private var bar: some View {
        let barShape = RoundedRectangle(cornerRadius: theme.barCorner * scale, style: .continuous)
        return HStack(spacing: TileMetrics.barGap * scale) {
            tile(width: 48) {
                readout(value: "12:26", caption: "Mon, Jun 22")
            }
            tile(width: 38) {
                readout(value: "21°", caption: "Sunny")
            }
            tile(width: tileHeight) {
                ZStack {
                    Circle()
                        .stroke(theme.inkSecondary.opacity(0.35), lineWidth: 2.5)
                    Circle()
                        .trim(from: 0, to: 0.68)
                        .stroke(theme.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("68")
                        .font(.system(size: 7, weight: theme.valueWeight, design: theme.fontDesign))
                        .foregroundStyle(theme.ink)
                }
                .padding(5)
            }
            tile(width: tileHeight) {
                Image(systemName: "play.fill")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(theme.onAccent)
                    .frame(width: 17, height: 17)
                    .background { Circle().fill(theme.accent) }
            }
        }
        .padding(TileMetrics.barPadding * scale)
        .background {
            ZStack {
                if theme.barBlur {
                    SettingsWallpaper()
                        .blur(radius: 6)
                        .clipShape(barShape)
                }
                barShape.fill(theme.barFill.style)
            }
        }
        .overlay {
            barShape.strokeBorder(theme.barBorder, lineWidth: border(theme.barBorderWidth))
        }
        .shadow(color: .black.opacity(theme.barShadow ? 0.35 : 0), radius: 5, y: 2)
    }

    private func readout(value text: String, caption captionText: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(text)
                .font(value(12))
                .foregroundStyle(theme.ink)
            Text(captionText)
                .font(caption)
                .foregroundStyle(theme.inkSecondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    private func tile<Content: View>(width: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: theme.tileCorner * scale, style: .continuous)
        return content()
            .padding(.horizontal, width > tileHeight ? 4 : 0)
            .frame(width: width, height: tileHeight, alignment: width > tileHeight ? .leading : .center)
            .background { shape.fill(theme.tileFill.style) }
            .overlay { shape.strokeBorder(theme.tileBorder, lineWidth: border(theme.tileBorderWidth)) }
            .clipShape(shape)
    }

    private func value(_ size: CGFloat) -> Font {
        .system(size: size, weight: theme.valueWeight, design: theme.fontDesign)
    }

    private var caption: Font {
        .system(size: 5.5, weight: .medium, design: theme.fontDesign)
    }

    private func border(_ width: CGFloat) -> CGFloat {
        max(0.5, width * 0.75)
    }
}

// MARK: - Shared pieces

private struct SettingsHeader: View {
    var title: String
    var subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}

/// A stand-in desktop picture behind the previews, with enough shape for
/// glass themes' blur to show.
private struct SettingsWallpaper: View {
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.24, green: 0.33, blue: 0.68), Color(red: 0.72, green: 0.38, blue: 0.58)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Circle()
                    .fill(Color(red: 1.0, green: 0.62, blue: 0.3).opacity(0.85))
                    .frame(width: size.width * 0.42)
                    .position(x: size.width * 0.18, y: size.height * 0.78)
                Circle()
                    .fill(Color(red: 0.25, green: 0.85, blue: 0.78).opacity(0.75))
                    .frame(width: size.width * 0.36)
                    .position(x: size.width * 0.86, y: size.height * 0.2)
            }
        }
    }
}

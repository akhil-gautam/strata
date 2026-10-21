import SwiftUI

// MARK: - Metrics

/// Measurements taken from the reference video. Every tile in the library
/// and in the bar is the same height; only the width varies. Corner radii
/// come from the current theme.
@MainActor
enum TileMetrics {
    /// Height of every tile.
    static let height: CGFloat = 56
    /// Width of a square tile (gauges, analog clocks, single icons).
    static let square: CGFloat = 56
    static var corner: CGFloat { AppearanceStore.shared.theme.tileCorner }
    /// Horizontal inset of a tile's content.
    static let inset: CGFloat = 10
    /// Gap between tiles in the bar.
    static let barGap: CGFloat = 7
    /// Padding between the bar's edge and its tiles.
    static let barPadding: CGFloat = 9
    /// The bar's thickness: its height at the bottom/notch, its width is
    /// content-driven on the left/right.
    static let barHeight: CGFloat = height + barPadding * 2
    static var barCorner: CGFloat { AppearanceStore.shared.theme.barCorner }
}

/// The current theme's colours. Reading any of these inside a view's body
/// makes the view follow theme changes.
@MainActor
enum TilePalette {
    private static var theme: DockTheme { AppearanceStore.shared.theme }

    /// The bar's own surface.
    static var barFill: AnyShapeStyle { theme.barFill.style }
    /// A tile's surface.
    static var tileSurface: AnyShapeStyle { theme.tileFill.style }
    /// A flat stand-in for the tile surface, for places that need a `Color`.
    static var tileFill: Color { theme.tileFill.base }
    static var tileBorder: Color { theme.tileBorder }
    /// Primary text and glyphs.
    static var ink: Color { theme.ink }
    /// Secondary text under a value.
    static var caption: Color { theme.inkSecondary }
    /// Focus rings, play buttons, selected chips.
    static var focus: Color { theme.accent }
    /// Glyphs drawn on a `focus` fill.
    static var onFocus: Color { theme.onAccent }
    /// The red of the remove badge and recording states.
    static var destructive: Color { theme.destructive }
}

@MainActor
extension Font {
    /// The large readout of a tile ("12:26", "$4,803", "21°").
    static func tileValue(_ size: CGFloat = 19, weight: Font.Weight? = nil) -> Font {
        let theme = AppearanceStore.shared.theme
        return .system(size: size, weight: weight ?? theme.valueWeight, design: theme.fontDesign)
    }

    /// Captions and secondary lines ("Mon, Jun 22", "visitors now").
    static func tileCaption(_ size: CGFloat = 9, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: AppearanceStore.shared.theme.fontDesign)
    }

    /// Any other text inside a tile or panel, in the theme's type design.
    static func tileText(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: AppearanceStore.shared.theme.fontDesign)
    }
}

// MARK: - Context

/// Where a tile is being drawn. The library shows previews; the bar shows the
/// live tile.
enum TileContext {
    case library
    case bar
}

private struct TileContextKey: EnvironmentKey {
    static let defaultValue: TileContext = .bar
}

extension EnvironmentValues {
    /// Service tiles that are not connected show sample data in the library
    /// (as a preview of what they will look like) and a "Connect" state in the
    /// bar. Tiles backed by local data show the real data in both places.
    var tileContext: TileContext {
        get { self[TileContextKey.self] }
        set { self[TileContextKey.self] = newValue }
    }
}

private struct TileFillsWidthKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// When true a `DockTile` grows to the width it is offered (never below
    /// its own width). The vertical bar sets it so its rows line up.
    var tileFillsWidth: Bool {
        get { self[TileFillsWidthKey.self] }
        set { self[TileFillsWidthKey.self] = newValue }
    }
}

// MARK: - Shell

/// The surface every tile is drawn on: a dark rounded rectangle of fixed
/// height. Tiles choose their own width.
struct DockTile<Content: View>: View {
    var width: CGFloat
    /// A tinted fill for tiles that are "on" (Drink Water's water, a running
    /// timer). `nil` uses the standard dark fill.
    var fill: AnyShapeStyle?
    /// Drop the horizontal inset for edge-to-edge content (charts, artwork).
    var inset: CGFloat = TileMetrics.inset
    @ViewBuilder var content: Content

    @Environment(\.tileFillsWidth) private var fillsWidth

    var body: some View {
        content
            .padding(.horizontal, inset)
            // In the vertical bar every row is justified to the column's
            // width, so a tile may be offered more than its natural width.
            .frame(
                minWidth: fillsWidth ? width : nil,
                idealWidth: fillsWidth ? width : nil,
                maxWidth: fillsWidth ? .infinity : nil
            )
            .frame(width: fillsWidth ? nil : width, height: TileMetrics.height)
            .background {
                RoundedRectangle(cornerRadius: TileMetrics.corner, style: .continuous)
                    .fill(fill ?? TilePalette.tileSurface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: TileMetrics.corner, style: .continuous)
                    .strokeBorder(TilePalette.tileBorder, lineWidth: AppearanceStore.shared.theme.tileBorderWidth)
            }
            .clipShape(RoundedRectangle(cornerRadius: TileMetrics.corner, style: .continuous))
            .foregroundStyle(TilePalette.ink)
    }
}

/// The common "value over caption" layout.
struct TileReadout: View {
    var value: String
    var caption: String
    var valueSize: CGFloat = 19
    var captionTint: Color = TilePalette.caption

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.tileValue(valueSize))
                .foregroundStyle(TilePalette.ink)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(caption)
                .font(.tileCaption())
                .foregroundStyle(captionTint)
                .lineLimit(1)
        }
    }
}

/// The round blue button used for play/pause and similar primary actions.
struct TilePlayButton: View {
    var systemName: String
    var tint: Color = TilePalette.focus
    var diameter: CGFloat = 24
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: diameter * 0.4, weight: .bold))
                .foregroundStyle(tint == TilePalette.focus ? TilePalette.onFocus : .white)
                .frame(width: diameter, height: diameter)
                .background { Circle().fill(tint) }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Catalogue

/// The sections of the widget library, in the order the video shows them.
enum TileCategory: String, CaseIterable, Identifiable {
    case apps, folders, social, finance, stocks, analytics, aiUsage, scripts, clocks, calendar
    case reminders, contacts, media, photos, system, weather, mail, notes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apps: "Apps"
        case .folders: "Folders"
        case .social: "Social"
        case .finance: "Finance"
        case .stocks: "Stocks"
        case .analytics: "Analytics"
        case .aiUsage: "AI Usage"
        case .scripts: "Scripts"
        case .clocks: "Clocks"
        case .calendar: "Calendar"
        case .reminders: "Reminders"
        case .contacts: "Phone"
        case .media: "Media"
        case .photos: "Photos"
        case .system: "System"
        case .weather: "Weather"
        case .mail: "Mail"
        case .notes: "Notes"
        }
    }

    var symbol: String {
        switch self {
        case .apps: "square.grid.2x2"
        case .folders: "folder.fill"
        case .social: "person.crop.circle"
        case .finance: "dollarsign.circle"
        case .stocks: "chart.line.uptrend.xyaxis"
        case .analytics: "chart.bar.fill"
        case .aiUsage: "sparkles"
        case .scripts: "terminal"
        case .clocks: "clock"
        case .calendar: "calendar"
        case .reminders: "checklist"
        case .contacts: "phone.fill"
        case .media: "music.note"
        case .photos: "photo.on.rectangle"
        case .system: "memorychip"
        case .weather: "cloud.sun.fill"
        case .mail: "envelope"
        case .notes: "note.text"
        }
    }

    /// Apps and folders are laid out as an even icon grid; every other
    /// section flows its tiles left to right.
    var isIconGrid: Bool { self == .apps || self == .folders }

    /// The extension that adds this section; `nil` for built-in sections.
    var dockExtension: DockExtension? {
        switch self {
        case .aiUsage: .aiUsage
        case .scripts: .scripts
        default: nil
        }
    }
}

/// One entry of a tile's context menu. The shell appends "Remove" itself.
enum TileMenuItem {
    /// Runs an action ("Start Focus", "Restart Reminder").
    case action(String, @MainActor () -> Void)
    /// Opens the tile's settings popover ("Customize…", "Set Interval…").
    case customize(String = "Customize…")
    /// A line between groups of items.
    case separator
    /// A greyed-out label heading the items below it ("Windows").
    case header(String)
    /// A nested menu.
    case submenu(String, [TileMenuItem])
    /// Items built when the menu opens, for menus that list live state (an
    /// app's windows). An empty result adds nothing.
    case dynamic(@MainActor () -> [TileMenuItem])
}

/// The settings popover a tile opens from its context menu. The shell draws
/// the chrome (symbol, title, badge, close button); the tile provides the
/// content.
struct TileSettings {
    var symbol: String
    /// The popover's title when it differs from the tile's name (the
    /// Pomodoro tile's settings are titled "Focus").
    var title: String? = nil
    /// A count shown next to the title ("4" toggles shown on the dock).
    var badge: (@MainActor () -> String?)?
    var content: @MainActor () -> AnyView
}

/// A tile the library offers and the bar can hold.
struct TileSpec: Identifiable {
    /// Stable identifier, persisted in the bar layout. Never reuse or rename.
    let id: String
    /// The name under the tile in the library and in the bar's tooltip.
    let title: String
    let category: TileCategory
    var menu: [TileMenuItem] = []
    var settings: TileSettings?
    /// Builds the tile. The view reads `\.tileContext` to know where it is.
    let make: @MainActor () -> AnyView
}

// MARK: - Settings building blocks

/// A row of the settings list: tinted chip, title, subtitle, switch.
struct TileSettingsToggleRow: View {
    var symbol: String
    var tint: Color
    var title: String
    var subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background { Circle().fill(tint.opacity(0.16)) }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.tileText(11.5, weight: .semibold))
                    .foregroundStyle(TilePalette.ink.opacity(0.92))
                Text(subtitle)
                    .font(.tileText(9, weight: .medium))
                    .foregroundStyle(TilePalette.ink.opacity(0.4))
            }
            Spacer(minLength: 0)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
        // The video's switches are light grey when on, not the accent blue;
        // light themes keep the ink colour instead.
        .tint(TilePalette.ink.opacity(0.82))
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: min(10, TileMetrics.corner), style: .continuous)
                .fill(TilePalette.ink.opacity(0.045))
        }
    }
}

/// A tinted card holding a "−  value  +" stepper, as in the Focus and
/// Drink Water settings.
struct TileStepperCard: View {
    var symbol: String?
    var title: String?
    var tint: Color
    @Binding var value: Int
    var range: ClosedRange<Int>
    var step: Int = 1
    var unit: String = "minutes"

    var body: some View {
        VStack(spacing: 4) {
            if let title {
                HStack(spacing: 5) {
                    if let symbol {
                        Image(systemName: symbol)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(tint)
                    }
                    Text(title)
                        .font(.tileText(10, weight: .semibold))
                        .foregroundStyle(TilePalette.ink.opacity(0.85))
                }
            }
            HStack(spacing: 26) {
                stepButton("minus") { value = max(range.lowerBound, value - step) }
                VStack(spacing: 0) {
                    Text("\(value)")
                        .font(.tileValue(20))
                        .foregroundStyle(TilePalette.ink)
                        .monospacedDigit()
                    Text(unit)
                        .font(.tileCaption(8.5))
                        .foregroundStyle(TilePalette.ink.opacity(0.4))
                }
                .frame(minWidth: 34)
                stepButton("plus") { value = min(range.upperBound, value + step) }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: TileMetrics.corner, style: .continuous)
                .fill(tint.opacity(0.12))
        }
        .overlay {
            RoundedRectangle(cornerRadius: TileMetrics.corner, style: .continuous)
                .strokeBorder(TilePalette.ink.opacity(0.05), lineWidth: 1)
        }
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(TilePalette.ink.opacity(0.75))
                .frame(width: 20, height: 20)
                .background { Circle().fill(tint.opacity(0.22)) }
                .overlay { Circle().strokeBorder(tint.opacity(0.25), lineWidth: 1) }
        }
        .buttonStyle(.plain)
    }
}

/// A row of preset chips ("15 min", "20 min", "30 min"…), one selected.
struct TileChoiceChips<Value: Hashable>: View {
    var options: [(label: String, value: Value)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let isSelected = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(option.label)
                        .font(.tileText(9.5, weight: .semibold))
                        .foregroundStyle(isSelected ? TilePalette.ink : TilePalette.ink.opacity(0.6))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background {
                            Capsule().fill(isSelected ? TilePalette.focus.opacity(0.35) : Color.clear)
                        }
                        .overlay {
                            Capsule().strokeBorder(isSelected ? TilePalette.focus.opacity(0.7) : .clear, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

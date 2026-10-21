import SwiftUI

// MARK: - Position

/// Where the bar lives on screen.
enum DockPosition: String, CaseIterable, Identifiable, Sendable {
    /// Bottom centre, where the macOS Dock sits (the video's layout).
    case bottom
    /// A vertical bar on the left edge, centred vertically.
    case left
    /// A vertical bar on the right edge, centred vertically.
    case right
    /// Top centre, flush with the top edge and hanging down around the
    /// camera housing like a notch: square top corners, rounded bottom ones.
    case notch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bottom: "Bottom"
        case .left: "Left"
        case .right: "Right"
        case .notch: "Notch"
        }
    }

    /// Left and right bars stack their tiles vertically.
    var isVertical: Bool { self == .left || self == .right }
}

// MARK: - Theme

/// A fill that is either a flat colour or a gradient.
enum ThemeFill: Sendable {
    case color(Color)
    /// Colours from top-leading to bottom-trailing.
    case gradient([Color])

    var style: AnyShapeStyle {
        switch self {
        case .color(let color):
            AnyShapeStyle(color)
        case .gradient(let colors):
            AnyShapeStyle(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
        }
    }

    /// A single representative colour, for places that need a `Color`.
    var base: Color {
        switch self {
        case .color(let color): color
        case .gradient(let colors): colors.first ?? .clear
        }
    }
}

/// Everything a theme can change. Tile layout and sizes never change; the
/// surfaces, colours, corners, borders, materials and type do.
struct DockTheme: Identifiable, Sendable {
    let id: String
    let name: String
    /// One line for the theme picker ("Green phosphor on black, square corners").
    let summary: String
    /// Drives system controls drawn inside tiles and panels (switches,
    /// text fields, menus): `.light` themes get dark-on-light controls.
    var appearance: ColorScheme

    // Bar
    var barFill: ThemeFill
    /// Blur what is behind the bar before painting `barFill` (glass themes
    /// use a translucent `barFill`).
    var barBlur: Bool = false
    var barBorder: Color
    var barBorderWidth: CGFloat = 1
    var barCorner: CGFloat
    var barShadow: Bool = true

    // Tiles
    var tileFill: ThemeFill
    var tileBorder: Color
    var tileBorderWidth: CGFloat = 1
    var tileCorner: CGFloat

    // Content
    /// Primary text and glyphs on a tile.
    var ink: Color
    /// Captions and secondary lines.
    var inkSecondary: Color
    /// Focus rings, play buttons, selected chips, hover rings.
    var accent: Color
    /// Glyphs and text drawn on top of an `accent` fill.
    var onAccent: Color
    /// Remove badges, recording, losses.
    var destructive: Color

    // Library panel, settings popovers, tooltips
    var panelFill: ThemeFill
    var panelBlur: Bool = true
    var panelBorder: Color

    // Type
    var fontDesign: Font.Design = .default
    var valueWeight: Font.Weight = .semibold
}

// MARK: - Store

/// The user's chosen position and theme. Observable: any view that reads a
/// token (directly or through `TilePalette` / `TileMetrics` / the tile fonts)
/// redraws when either changes.
@MainActor
@Observable
final class AppearanceStore {
    static let shared = AppearanceStore()

    private static let positionKey = "appearance.position"
    private static let themeKey = "appearance.theme"

    var position: DockPosition {
        didSet {
            guard position != oldValue else { return }
            UserDefaults.standard.set(position.rawValue, forKey: Self.positionKey)
            NotificationCenter.default.post(name: .dockPositionDidChange, object: nil)
        }
    }

    var themeID: String {
        didSet {
            guard themeID != oldValue else { return }
            UserDefaults.standard.set(themeID, forKey: Self.themeKey)
            NotificationCenter.default.post(name: .dockThemeDidChange, object: nil)
        }
    }

    var theme: DockTheme {
        DockThemes.theme(id: themeID)
    }

    private init() {
        let defaults = UserDefaults.standard
        position = defaults.string(forKey: Self.positionKey).flatMap(DockPosition.init(rawValue:)) ?? .bottom
        themeID = defaults.string(forKey: Self.themeKey) ?? DockThemes.defaultID
    }
}

extension Notification.Name {
    /// Posted after `AppearanceStore.position` changes; AppKit code that
    /// places windows listens for it.
    static let dockPositionDidChange = Notification.Name("DockDock.positionDidChange")
    /// Posted after `AppearanceStore.themeID` changes; AppKit code that sets
    /// materials, shadows or appearances listens for it.
    static let dockThemeDidChange = Notification.Name("DockDock.themeDidChange")
}

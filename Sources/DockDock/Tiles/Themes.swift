import SwiftUI

/// The themes offered in Settings, in picker order.
enum DockThemes {
    static let defaultID = "midnight"

    static let all: [DockTheme] = [
        midnight, daylight, frostedGlass, terminal, amberCRT,
        paper, brutalist, synthwave, nord, solarizedLight,
        dracula, sunset, ocean, forest, pastel,
        outline, highContrast, aurora, blueprint, gilded,
    ]

    static func theme(id: String) -> DockTheme {
        all.first { $0.id == id } ?? midnight
    }

    /// An sRGB colour from a 0xRRGGBB literal.
    private static func hex(_ value: UInt32, _ opacity: Double = 1) -> Color {
        Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: opacity
        )
    }

    /// The video's look: near-black bar, dark grey tiles, white ink, blue accent.
    static let midnight = DockTheme(
        id: "midnight",
        name: "Midnight",
        summary: "The original: near-black glass, white type, blue accents",
        appearance: .dark,
        barFill: .color(Color(white: 0.055)),
        barBorder: Color.white.opacity(0.07),
        barCorner: 18,
        tileFill: .color(Color(white: 0.115)),
        tileBorder: Color.white.opacity(0.06),
        tileCorner: 12,
        ink: .white,
        inkSecondary: Color.white.opacity(0.48),
        accent: Color(red: 0.16, green: 0.52, blue: 1.0),
        onAccent: .white,
        destructive: Color(red: 0.95, green: 0.27, blue: 0.27),
        panelFill: .color(Color.black.opacity(0.78)),
        panelBorder: Color.white.opacity(0.08)
    )

    static let daylight = DockTheme(
        id: "daylight",
        name: "Daylight",
        summary: "Bright white bar, soft grey tiles, crisp black type",
        appearance: .light,
        barFill: .color(hex(0xFBFBFC)),
        barBorder: Color.black.opacity(0.09),
        barCorner: 18,
        tileFill: .color(hex(0xECEDF0)),
        tileBorder: Color.black.opacity(0.06),
        tileCorner: 12,
        ink: hex(0x141518),
        inkSecondary: hex(0x5E626B),
        accent: hex(0x0A6CF0),
        onAccent: .white,
        destructive: hex(0xD62F2F),
        panelFill: .color(hex(0xF7F7F9, 0.94)),
        panelBorder: Color.black.opacity(0.1)
    )

    static let frostedGlass = DockTheme(
        id: "frosted-glass",
        name: "Frosted Glass",
        summary: "See-through blurred glass with milky tiles",
        appearance: .dark,
        barFill: .color(Color.white.opacity(0.12)),
        barBlur: true,
        barBorder: Color.white.opacity(0.32),
        barCorner: 24,
        tileFill: .color(Color.white.opacity(0.16)),
        tileBorder: Color.white.opacity(0.26),
        tileCorner: 17,
        ink: .white,
        inkSecondary: Color.white.opacity(0.76),
        accent: hex(0x7FD4FF),
        onAccent: hex(0x06222E),
        destructive: hex(0xFF6B6B),
        panelFill: .color(Color.white.opacity(0.1)),
        panelBorder: Color.white.opacity(0.3),
        valueWeight: .medium
    )

    static let terminal = DockTheme(
        id: "terminal",
        name: "Terminal",
        summary: "Green phosphor on black, monospaced, square corners",
        appearance: .dark,
        barFill: .color(.black),
        barBorder: hex(0x33FF66, 0.4),
        barCorner: 3,
        barShadow: false,
        tileFill: .color(hex(0x07120A)),
        tileBorder: hex(0x33FF66, 0.32),
        tileCorner: 2,
        ink: hex(0x3CFF6E),
        inkSecondary: hex(0x2BB84F),
        accent: hex(0x3CFF6E),
        onAccent: .black,
        destructive: hex(0xFF4D3D),
        panelFill: .color(Color.black.opacity(0.96)),
        panelBlur: false,
        panelBorder: hex(0x33FF66, 0.45),
        fontDesign: .monospaced,
        valueWeight: .regular
    )

    static let amberCRT = DockTheme(
        id: "amber-crt",
        name: "Amber CRT",
        summary: "Warm amber glow on a scanline-black monitor",
        appearance: .dark,
        barFill: .color(hex(0x120A02)),
        barBorder: hex(0xFFA51F, 0.32),
        barCorner: 8,
        tileFill: .gradient([hex(0x24160A), hex(0x170D03)]),
        tileBorder: hex(0xFFA51F, 0.22),
        tileCorner: 6,
        ink: hex(0xFFB000),
        inkSecondary: hex(0xCC8A1E),
        accent: hex(0xFF9F0A),
        onAccent: hex(0x1A0C00),
        destructive: hex(0xFF5533),
        panelFill: .color(hex(0x0E0801, 0.95)),
        panelBlur: false,
        panelBorder: hex(0xFFA51F, 0.3),
        fontDesign: .monospaced,
        valueWeight: .medium
    )

    static let paper = DockTheme(
        id: "paper",
        name: "Paper",
        summary: "Cream stationery, sepia serif ink, hairline rules",
        appearance: .light,
        barFill: .color(hex(0xF3ECDC)),
        barBorder: hex(0x6B5440, 0.35),
        barBorderWidth: 0.5,
        barCorner: 10,
        tileFill: .color(hex(0xFCF8EE)),
        tileBorder: hex(0x5A4430, 0.32),
        tileBorderWidth: 0.5,
        tileCorner: 5,
        ink: hex(0x3B2A1C),
        inkSecondary: hex(0x76604A),
        accent: hex(0xA2421F),
        onAccent: hex(0xFCF8EE),
        destructive: hex(0xB0261C),
        panelFill: .color(hex(0xF3ECDC, 0.97)),
        panelBlur: false,
        panelBorder: hex(0x6B5440, 0.3),
        fontDesign: .serif,
        valueWeight: .medium
    )

    static let brutalist = DockTheme(
        id: "brutalist",
        name: "Brutalist",
        summary: "Raw white blocks, thick black borders, no curves",
        appearance: .light,
        barFill: .color(.white),
        barBorder: .black,
        barBorderWidth: 3,
        barCorner: 0,
        barShadow: false,
        tileFill: .color(.white),
        tileBorder: .black,
        tileBorderWidth: 2,
        tileCorner: 0,
        ink: .black,
        inkSecondary: hex(0x3A3A3A),
        accent: hex(0xFFDD00),
        onAccent: .black,
        destructive: hex(0xE01010),
        panelFill: .color(.white),
        panelBlur: false,
        panelBorder: .black,
        valueWeight: .black
    )

    static let synthwave = DockTheme(
        id: "synthwave",
        name: "Synthwave",
        summary: "Deep purple dusk with neon magenta and cyan edges",
        appearance: .dark,
        barFill: .gradient([hex(0x2B0A4D), hex(0x0D0326)]),
        barBorder: hex(0xFF2FD0, 0.85),
        barBorderWidth: 1.5,
        barCorner: 14,
        tileFill: .gradient([hex(0x3A1068), hex(0x1E0844)]),
        tileBorder: hex(0x2EF2FF, 0.7),
        tileCorner: 10,
        ink: hex(0xFDEBFF),
        inkSecondary: hex(0x5CE8FF),
        accent: hex(0xFF2FC0),
        onAccent: .white,
        destructive: hex(0xFF5A5A),
        panelFill: .gradient([hex(0x220840, 0.94), hex(0x0D0326, 0.94)]),
        panelBorder: hex(0xFF2FD0, 0.5),
        valueWeight: .heavy
    )

    static let nord = DockTheme(
        id: "nord",
        name: "Nord",
        summary: "Arctic slate greys with frosty blue accents",
        appearance: .dark,
        barFill: .color(hex(0x2E3440)),
        barBorder: hex(0x4C566A, 0.7),
        barCorner: 16,
        tileFill: .color(hex(0x3B4252)),
        tileBorder: hex(0x4C566A, 0.6),
        tileCorner: 10,
        ink: hex(0xECEFF4),
        inkSecondary: hex(0xAEB7C6),
        accent: hex(0x88C0D0),
        onAccent: hex(0x2E3440),
        destructive: hex(0xBF616A),
        panelFill: .color(hex(0x2E3440, 0.95)),
        panelBorder: hex(0x4C566A, 0.6),
        fontDesign: .rounded,
        valueWeight: .medium
    )

    static let solarizedLight = DockTheme(
        id: "solarized-light",
        name: "Solarized Light",
        summary: "The classic warm base3 palette with cool blue accents",
        appearance: .light,
        barFill: .color(hex(0xFDF6E3)),
        barBorder: hex(0x93A1A1, 0.5),
        barCorner: 12,
        tileFill: .color(hex(0xEEE8D5)),
        tileBorder: hex(0x93A1A1, 0.4),
        tileCorner: 8,
        ink: hex(0x073642),
        inkSecondary: hex(0x586E75),
        accent: hex(0x268BD2),
        onAccent: hex(0xFDF6E3),
        destructive: hex(0xDC322F),
        panelFill: .color(hex(0xFDF6E3, 0.96)),
        panelBorder: hex(0x93A1A1, 0.5)
    )

    static let dracula = DockTheme(
        id: "dracula",
        name: "Dracula",
        summary: "Moody grey-violet with pink and purple highlights",
        appearance: .dark,
        barFill: .color(hex(0x282A36)),
        barBorder: hex(0x6272A4, 0.55),
        barCorner: 14,
        tileFill: .color(hex(0x44475A)),
        tileBorder: hex(0x6272A4, 0.5),
        tileCorner: 9,
        ink: hex(0xF8F8F2),
        inkSecondary: hex(0xCBA6FF),
        accent: hex(0xFF79C6),
        onAccent: hex(0x282A36),
        destructive: hex(0xFF5555),
        panelFill: .color(hex(0x282A36, 0.95)),
        panelBorder: hex(0x6272A4, 0.5),
        valueWeight: .bold
    )

    static let sunset = DockTheme(
        id: "sunset",
        name: "Sunset",
        summary: "An orange-to-pink sky bar with deep wine tiles",
        appearance: .dark,
        barFill: .gradient([hex(0xFF8A34), hex(0xEC3F7E)]),
        barBorder: Color.white.opacity(0.3),
        barCorner: 20,
        tileFill: .gradient([hex(0x6E2316), hex(0x55153F)]),
        tileBorder: Color.white.opacity(0.16),
        tileCorner: 14,
        ink: hex(0xFFF3EA),
        inkSecondary: hex(0xFFC29E),
        accent: hex(0xFFD15C),
        onAccent: hex(0x4A1210),
        destructive: hex(0xFF5C5C),
        panelFill: .gradient([hex(0x5A1E1A, 0.95), hex(0x4A1238, 0.95)]),
        panelBorder: hex(0xFFB37A, 0.35),
        fontDesign: .rounded
    )

    static let ocean = DockTheme(
        id: "ocean",
        name: "Ocean",
        summary: "Navy depths fading to teal, with turquoise accents",
        appearance: .dark,
        barFill: .gradient([hex(0x061A47), hex(0x006273)]),
        barBorder: hex(0x7FE6FF, 0.22),
        barCorner: 18,
        tileFill: .gradient([hex(0x0B2D5C), hex(0x074A5E)]),
        tileBorder: hex(0x7FE6FF, 0.2),
        tileCorner: 12,
        ink: hex(0xE8FAFF),
        inkSecondary: hex(0x8FD9E8),
        accent: hex(0x2FE0CF),
        onAccent: hex(0x002A33),
        destructive: hex(0xFF6B66),
        panelFill: .gradient([hex(0x061A47, 0.94), hex(0x003F4D, 0.94)]),
        panelBorder: hex(0x7FE6FF, 0.25),
        valueWeight: .medium
    )

    static let forest = DockTheme(
        id: "forest",
        name: "Forest",
        summary: "Mossy greens with cream serif type and ochre accents",
        appearance: .dark,
        barFill: .color(hex(0x1F2B19)),
        barBorder: hex(0xF4EBD0, 0.14),
        barCorner: 16,
        tileFill: .color(hex(0x33452A)),
        tileBorder: hex(0xF4EBD0, 0.12),
        tileCorner: 10,
        ink: hex(0xF6EFD8),
        inkSecondary: hex(0xC9CCA2),
        accent: hex(0xE3A93B),
        onAccent: hex(0x241A06),
        destructive: hex(0xEB6A4C),
        panelFill: .color(hex(0x1F2B19, 0.95)),
        panelBorder: hex(0xF4EBD0, 0.16),
        fontDesign: .serif
    )

    static let pastel = DockTheme(
        id: "pastel",
        name: "Pastel",
        summary: "Candy pink and lavender, plump corners, plum type",
        appearance: .light,
        barFill: .gradient([hex(0xFFD6E8), hex(0xE6DBFF)]),
        barBorder: Color.white.opacity(0.8),
        barBorderWidth: 1.5,
        barCorner: 24,
        tileFill: .color(hex(0xFFF2F7)),
        tileBorder: hex(0xF2A7C9, 0.6),
        tileCorner: 18,
        ink: hex(0x5A2457),
        inkSecondary: hex(0x8A5A86),
        accent: hex(0xF0609E),
        onAccent: .white,
        destructive: hex(0xE0394F),
        panelFill: .gradient([hex(0xFFEAF3, 0.96), hex(0xF1EAFF, 0.96)]),
        panelBorder: hex(0xF2A7C9, 0.6),
        fontDesign: .rounded,
        valueWeight: .bold
    )

    static let outline = DockTheme(
        id: "outline",
        name: "Outline",
        summary: "Clear blurred bar, hollow tiles drawn in hairlines",
        appearance: .dark,
        barFill: .color(Color.black.opacity(0.14)),
        barBlur: true,
        barBorder: Color.white.opacity(0.4),
        barCorner: 16,
        barShadow: false,
        tileFill: .color(.clear),
        tileBorder: Color.white.opacity(0.55),
        tileCorner: 10,
        ink: .white,
        inkSecondary: Color.white.opacity(0.74),
        accent: .white,
        onAccent: .black,
        destructive: hex(0xFF6262),
        panelFill: .color(Color.black.opacity(0.3)),
        panelBorder: Color.white.opacity(0.4),
        valueWeight: .light
    )

    static let highContrast = DockTheme(
        id: "high-contrast",
        name: "High Contrast",
        summary: "Pure black, bold white outlines, yellow highlights",
        appearance: .dark,
        barFill: .color(.black),
        barBorder: .white,
        barBorderWidth: 2,
        barCorner: 10,
        tileFill: .color(.black),
        tileBorder: .white,
        tileBorderWidth: 2,
        tileCorner: 8,
        ink: .white,
        inkSecondary: Color(white: 0.9),
        accent: hex(0xFFE500),
        onAccent: .black,
        destructive: hex(0xFF4040),
        panelFill: .color(.black),
        panelBlur: false,
        panelBorder: .white,
        valueWeight: .bold
    )

    static let aurora = DockTheme(
        id: "aurora",
        name: "Aurora",
        summary: "Polar night lit by green-to-violet northern lights",
        appearance: .dark,
        barFill: .gradient([hex(0x05141C), hex(0x120A26)]),
        barBorder: hex(0x5CFFB0, 0.3),
        barCorner: 20,
        tileFill: .gradient([hex(0x0B4A3C), hex(0x3A1A66)]),
        tileBorder: hex(0xA98BFF, 0.3),
        tileCorner: 14,
        ink: .white,
        inkSecondary: hex(0xB4F5D8),
        accent: hex(0x5CFFA8),
        onAccent: hex(0x03201A),
        destructive: hex(0xFF6680),
        panelFill: .gradient([hex(0x05141C, 0.94), hex(0x150B2C, 0.94)]),
        panelBorder: hex(0x5CFFB0, 0.28),
        fontDesign: .rounded
    )

    static let blueprint = DockTheme(
        id: "blueprint",
        name: "Blueprint",
        summary: "Drafting-table blue with white hairline outlines",
        appearance: .dark,
        barFill: .color(hex(0x124A99)),
        barBorder: Color.white.opacity(0.7),
        barCorner: 4,
        barShadow: false,
        tileFill: .color(hex(0x1A58AD)),
        tileBorder: Color.white.opacity(0.8),
        tileCorner: 2,
        ink: .white,
        inkSecondary: hex(0xC7DDFF),
        accent: .white,
        onAccent: hex(0x124A99),
        destructive: hex(0xFF8A70),
        panelFill: .color(hex(0x124A99, 0.97)),
        panelBlur: false,
        panelBorder: Color.white.opacity(0.7),
        fontDesign: .monospaced,
        valueWeight: .medium
    )

    static let gilded = DockTheme(
        id: "gilded",
        name: "Gilded",
        summary: "Black lacquer with gold leaf edges and serif numerals",
        appearance: .dark,
        barFill: .color(hex(0x080706)),
        barBorder: hex(0xD4AE5C, 0.65),
        barCorner: 14,
        tileFill: .gradient([hex(0x1C170F), hex(0x0D0B08)]),
        tileBorder: hex(0xD4AE5C, 0.45),
        tileCorner: 8,
        ink: hex(0xEDCB7E),
        inkSecondary: hex(0xB89C68),
        accent: hex(0xD9AE4F),
        onAccent: hex(0x140E04),
        destructive: hex(0xE35A45),
        panelFill: .color(hex(0x080706, 0.95)),
        panelBorder: hex(0xD4AE5C, 0.45),
        fontDesign: .serif,
        valueWeight: .medium
    )
}

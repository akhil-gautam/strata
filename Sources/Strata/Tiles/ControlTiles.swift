import SwiftUI

/// Tiles that control the Mac and Strata itself, in the System section.
///
/// Tile ids: `"keep-awake"` (stops the Mac from sleeping, for a while or
/// until stopped) and `"settings"` (opens Strata's Settings).
@MainActor
enum ControlTiles {
    static let specs: [TileSpec] = [
        TileSpec(
            id: "keep-awake",
            title: "Keep Awake",
            category: .system,
            menu: KeepAwake.Span.presets.map { span in
                TileMenuItem.action(span.menuTitle) { KeepAwake.shared.start(span) }
            } + [
                .dynamic {
                    KeepAwake.shared.isActive ? [.separator, .action("Stop Keeping Awake") { KeepAwake.shared.stop() }] : []
                },
                .separator,
                .customize("Keep Awake Settings…"),
            ],
            settings: TileSettings(symbol: "cup.and.saucer.fill", title: "Keep Awake", badge: nil) {
                AnyView(KeepAwakeSettings())
            },
            make: { AnyView(KeepAwakeTile()) }
        ),
        TileSpec(
            id: "settings",
            title: "Settings",
            category: .system,
            menu: [
                .action("Open Settings") { SettingsWindowController.shared.show(section: .general) },
                .separator,
                .action("Position…") { SettingsWindowController.shared.show(section: .position) },
                .action("Themes…") { SettingsWindowController.shared.show(section: .themes) },
                .action("Extensions…") { SettingsWindowController.shared.show(section: .extensions) },
            ],
            make: { AnyView(SettingsTile()) }
        ),
    ]
}

// MARK: - Keep Awake

private struct KeepAwakeTile: View {
    @Environment(\.tileContext) private var context

    var body: some View {
        let awake = KeepAwake.shared
        let tile = DockTile(width: 150) {
            HStack(spacing: 9) {
                Image(systemName: awake.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(awake.isActive ? Color.white : TilePalette.ink.opacity(0.7))
                    .frame(width: 32, height: 32)
                    .background {
                        Circle().fill(awake.isActive ? AnyShapeStyle(DockAccent.orange) : AnyShapeStyle(TilePalette.ink.opacity(0.1)))
                    }
                    .symbolEffect(.bounce, value: awake.isActive)
                // Ticks every second only while counting down.
                TimelineView(.periodic(from: .now, by: awake.until == nil ? 3600 : 1)) { timeline in
                    TileReadout(
                        value: awake.isActive ? "Awake" : "Sleep OK",
                        caption: caption(at: timeline.date),
                        valueSize: 15,
                        captionTint: awake.isActive ? DockAccent.orange : TilePalette.caption
                    )
                }
                Spacer(minLength: 0)
            }
        }
        if context == .bar {
            tile
                .contentShape(RoundedRectangle(cornerRadius: TileMetrics.corner, style: .continuous))
                .onTapGesture { awake.toggle() }
                .help(awake.isActive ? "Let the Mac sleep" : "Keep the Mac awake (\(awake.defaultSpan.chipLabel))")
        } else {
            tile
        }
    }

    private func caption(at date: Date) -> String {
        let awake = KeepAwake.shared
        guard awake.isActive else { return "tap to stay awake" }
        guard let remaining = awake.remaining(at: date) else { return "until stopped" }
        return "\(KeepAwake.format(remaining)) left"
    }
}

private struct KeepAwakeSettings: View {
    var body: some View {
        @Bindable var awake = KeepAwake.shared
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text("A tap keeps it awake for")
                    .font(.tileText(10, weight: .semibold))
                    .foregroundStyle(TilePalette.ink.opacity(0.6))
                TileChoiceChips(
                    options: KeepAwake.Span.presets.map { (label: $0.chipLabel, value: $0) },
                    selection: $awake.defaultSpan
                )
            }
            TileSettingsToggleRow(
                symbol: "display",
                tint: DockAccent.blue,
                title: "Keep display on",
                subtitle: "Off: the screen may sleep; the Mac stays awake.",
                isOn: $awake.keepsDisplayOn
            )
            Text("Closing the lid still puts the Mac to sleep.")
                .font(.tileText(9, weight: .medium))
                .foregroundStyle(TilePalette.ink.opacity(0.4))
        }
        .frame(width: 250)
    }
}

// MARK: - Settings

/// A square gear that opens Strata's Settings; the gear turns while the
/// pointer is over it.
private struct SettingsTile: View {
    @Environment(\.tileContext) private var context
    @State private var isHovering = false

    var body: some View {
        let tile = DockTile(width: TileMetrics.square) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(TilePalette.ink.opacity(0.82))
                .rotationEffect(.degrees(isHovering ? 60 : 0))
                .animation(.spring(duration: 0.5, bounce: 0.3), value: isHovering)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        if context == .bar {
            tile
                .contentShape(RoundedRectangle(cornerRadius: TileMetrics.corner, style: .continuous))
                .onTapGesture { SettingsWindowController.shared.show() }
                .onHover { isHovering = $0 }
        } else {
            tile
        }
    }
}

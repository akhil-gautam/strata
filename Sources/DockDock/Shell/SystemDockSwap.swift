import Foundation

/// Auto-hides the macOS Dock while DockDock's bar stands in for it, and puts
/// the user's own setting back afterwards (video f07–f09, f79–f82).
///
/// The user's original setting is persisted before it is overridden, so a
/// crash or force-quit is repaired on the next launch or quit.
@MainActor
final class SystemDockSwap {
    private let layoutStore: LayoutStore

    init(layoutStore: LayoutStore) {
        self.layoutStore = layoutStore
    }

    /// Whether DockDock hides the macOS Dock while its bar is showing.
    var isEnabled: Bool { layoutStore.layout.hideSystemDock }

    func setEnabled(_ enabled: Bool, barVisible: Bool) {
        layoutStore.setHideSystemDock(enabled)
        update(barVisible: barVisible)
    }

    /// Hides the Dock when the bar is on screen and the swap is enabled;
    /// otherwise restores the user's setting.
    func update(barVisible: Bool) {
        if isEnabled && barVisible {
            hideSystemDock()
        } else {
            restore()
        }
    }

    /// Puts the user's own auto-hide setting back.
    func restore() {
        guard let original = layoutStore.layout.systemDockOriginalAutohide else { return }
        if SystemDock.isAutoHidden != original {
            SystemDock.setAutoHidden(original)
        }
        layoutStore.setSystemDockOriginalAutohide(nil)
    }

    private func hideSystemDock() {
        // Already overriding (or left over from a run that did not quit
        // cleanly): the stored value is still the user's own.
        if layoutStore.layout.systemDockOriginalAutohide == nil {
            layoutStore.setSystemDockOriginalAutohide(SystemDock.isAutoHidden)
        }
        if !SystemDock.isAutoHidden {
            SystemDock.setAutoHidden(true)
        }
    }
}

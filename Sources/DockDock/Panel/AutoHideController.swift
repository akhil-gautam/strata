import AppKit

/// Hides a window when the pointer is elsewhere and brings it back when the
/// pointer approaches where it was parked.
@MainActor
final class AutoHideController {
    private let window: NSWindow
    private let delay: () -> TimeInterval
    private let parkedOrigin: () -> NSPoint
    private let hiddenOrigin: () -> NSPoint
    private let revealZone: () -> CGRect
    /// While this returns true the window stays where it is parked (the
    /// library or a popover is open beside it).
    private let holdsOpen: () -> Bool

    /// Whether the window is parked off screen at its hidden origin.
    private(set) var isHidden = false
    private var awaySince: Date?
    private var isEnabled = false
    private var monitor: Any?
    private var localMonitor: Any?

    init(
        window: NSWindow,
        delay: @escaping () -> TimeInterval,
        parkedOrigin: @escaping () -> NSPoint,
        hiddenOrigin: @escaping () -> NSPoint,
        revealZone: @escaping () -> CGRect,
        holdsOpen: @escaping () -> Bool = { false }
    ) {
        self.window = window
        self.delay = delay
        self.parkedOrigin = parkedOrigin
        self.hiddenOrigin = hiddenOrigin
        self.revealZone = revealZone
        self.holdsOpen = holdsOpen
    }

    func setEnabled(_ enabled: Bool, animated: Bool = true) {
        let wasHidden = isHidden
        isEnabled = enabled
        if enabled {
            installMonitors()
            evaluate()
        } else {
            isHidden = false
            awaySince = nil
            if wasHidden, animated {
                move(to: parkedOrigin(), animated: true)
            }
        }
    }

    func evaluate() {
        guard isEnabled else { return }
        let cursor = NSEvent.mouseLocation

        if holdsOpen() {
            awaySince = nil
            if isHidden {
                reveal()
            }
            return
        }

        if isHidden {
            if revealZone().contains(cursor) {
                reveal()
            }
            return
        }

        if window.frame.insetBy(dx: -6, dy: -6).contains(cursor) {
            awaySince = nil
        } else {
            if awaySince == nil {
                awaySince = Date()
            } else if Date().timeIntervalSince(awaySince!) > delay() {
                hide()
            }
        }
    }

    private func reveal() {
        isHidden = false
        awaySince = nil
        move(to: parkedOrigin(), animated: true)
    }

    private func hide() {
        guard !isHidden else { return }
        isHidden = true
        awaySince = nil
        move(to: hiddenOrigin(), animated: true)
    }

    private func move(to origin: NSPoint, animated: Bool) {
        let frame = NSRect(origin: origin, size: window.frame.size)
        guard animated else {
            window.setFrame(frame, display: true)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(frame, display: true)
        }
    }

    private func installMonitors() {
        guard monitor == nil else { return }

        monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged]
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.evaluate()
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged]
        ) { [weak self] event in
            MainActor.assumeIsolated {
                self?.evaluate()
            }
            return event
        }

        // The pointer often stops moving, so visibility is also checked on a
        // slow tick: otherwise a still pointer would never trigger the hide.
        Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                self?.evaluate()
            }
        }
    }
}

import AppKit

/// Strata's one-colour mark for the menu bar: three bars, light to dark,
/// building up to the widest. The same drawing as
/// `design/logo-options-v2.html` (`m-strata`).
enum StrataMark {
    static func menuBarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: true) { _ in
            let bars: [(NSRect, CGFloat)] = [
                (NSRect(x: 5, y: 2.8, width: 6, height: 2), 0.4),
                (NSRect(x: 3.5, y: 6.2, width: 9, height: 2.4), 0.7),
                (NSRect(x: 1.5, y: 10, width: 13, height: 3), 1),
            ]
            for (rect, alpha) in bars {
                NSColor.black.withAlphaComponent(alpha).setFill()
                NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Strata"
        return image
    }
}

import AppKit

/// Shelfie's one-colour mark for the menu bar: a tile with an eye, standing
/// on a shelf. The same drawing as `design/brand-options.html` (`m-shelfie`).
enum ShelfieMark {
    static func menuBarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: true) { _ in
            NSColor.black.setFill()
            let tile = NSBezierPath(roundedRect: NSRect(x: 4.5, y: 2.5, width: 7, height: 9), xRadius: 2, yRadius: 2)
            // The eye is cut out of the tile.
            tile.append(NSBezierPath(ovalIn: NSRect(x: 5.7, y: 5.1, width: 1.8, height: 1.8)))
            tile.windingRule = .evenOdd
            tile.fill()
            NSBezierPath(roundedRect: NSRect(x: 1.5, y: 13, width: 13, height: 1.5), xRadius: 0.75, yRadius: 0.75).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Shelfie"
        return image
    }
}

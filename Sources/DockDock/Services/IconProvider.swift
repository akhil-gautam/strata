import AppKit

/// Caches downscaled icons so the strip never re-rasterises artwork while drawing.
@MainActor
final class IconProvider {
    static let shared = IconProvider()

    private let cache = NSCache<NSString, NSImage>()
    private let maxDimension: CGFloat = 128

    init() {
        cache.countLimit = 512
    }

    func icon(for descriptor: AppDescriptor) -> NSImage {
        let key = descriptor.id as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let source = NSWorkspace.shared.icon(forFile: descriptor.url.path)
        let scaled = rasterized(source, maxDimension: maxDimension)
        cache.setObject(scaled, forKey: key)
        return scaled
    }

    private func rasterized(_ image: NSImage, maxDimension: CGFloat) -> NSImage {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }

        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return image }

        let ratio = maxDimension / longest
        let target = NSSize(width: (size.width * ratio).rounded(), height: (size.height * ratio).rounded())
        let output = NSImage(size: target)
        output.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: target), from: .zero, operation: .copy, fraction: 1)
        output.unlockFocus()
        return output
    }
}

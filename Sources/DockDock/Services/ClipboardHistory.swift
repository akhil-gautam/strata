import AppKit
import ImageIO
import Observation

/// A short history of what was copied, so it can be pasted again.
@MainActor
@Observable
final class ClipboardHistory {
    static let shared = ClipboardHistory()

    struct Item: Identifiable {
        let id: Int
        let text: String
        let kind: Kind
        let fileURL: URL?
        /// The copied image, as it came off the pasteboard (PNG or TIFF).
        var image: ImageData? = nil

        enum Kind: String, Sendable {
            case text
            case image
            case files
        }

        struct ImageData {
            let data: Data
            let type: NSPasteboard.PasteboardType
            let thumbnail: NSImage?
            /// Pixel size, for the preview text.
            let size: CGSize
        }

        var preview: String {
            switch kind {
            case .text:
                return text.replacingOccurrences(of: "\n", with: " ")
            case .image:
                guard let size = image?.size, size.width > 0 else { return "Image" }
                return "Image \(Int(size.width))×\(Int(size.height))"
            case .files:
                return fileURL?.lastPathComponent ?? "File"
            }
        }
    }

    private(set) var items: [Item] = []
    /// While on, nothing new is recorded.
    var isPaused: Bool {
        didSet { UserDefaults.standard.set(isPaused, forKey: Self.pausedKey) }
    }

    private var lastChangeCount = -1
    private var nextID = 0
    private let limit = 12

    private static let pausedKey = "clipboard.paused"
    /// Larger images are left out of the history.
    private static let maxImageBytes = 8 * 1024 * 1024
    /// Images that would decode to more than this are never decoded in full
    /// (no PNG shrinking, no TIFF copy on restore).
    private nonisolated static let maxDecodedBytes = 128 * 1024 * 1024
    /// Markers password managers and other apps put on copies that should
    /// not be kept (nspasteboard.org conventions, plus 1Password's own).
    private static let privateTypes: Set<NSPasteboard.PasteboardType> = [
        NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"),
        NSPasteboard.PasteboardType("org.nspasteboard.TransientType"),
        NSPasteboard.PasteboardType("com.agilebits.onepassword"),
    ]
    /// A copy carrying these is text, even with a picture of it attached.
    private static let richTextTypes: Set<NSPasteboard.PasteboardType> = [.rtf, .rtfd, .html]

    init() {
        isPaused = UserDefaults.standard.bool(forKey: Self.pausedKey)
    }

    func refresh() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        guard !isPaused else { return }

        let types = pasteboard.types ?? []
        guard Self.privateTypes.isDisjoint(with: types) else { return }

        let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]
        // Office apps and browsers put a picture of copied text alongside the
        // rich text; that copy is text.
        let isRichText = !Self.richTextTypes.isDisjoint(with: types)
        let imageType = isRichText ? nil : [NSPasteboard.PasteboardType.png, .tiff].first { types.contains($0) }
        if let url = fileURLs?.first {
            add(Item(id: nextID, text: url.path, kind: .files, fileURL: url))
        } else if let imageType, let data = pasteboard.data(forType: imageType) {
            recordImage(data, type: imageType, changeCount: lastChangeCount)
        } else if let text = pasteboard.string(forType: .string), !text.isEmpty {
            add(Item(id: nextID, text: text, kind: .text, fileURL: nil))
        }
    }

    /// Decodes the thumbnail (and shrinks an oversized TIFF to PNG) off the
    /// main actor, then records the image unless something newer was copied
    /// meanwhile.
    private func recordImage(_ data: Data, type: NSPasteboard.PasteboardType, changeCount: Int) {
        let maxBytes = Self.maxImageBytes
        let typeName = type.rawValue
        Task {
            let prepared = await Task.detached(priority: .utility) {
                ClipboardHistory.prepareImage(data, typeName: typeName, maxBytes: maxBytes)
            }.value
            guard let prepared, lastChangeCount == changeCount, !isPaused else { return }
            add(Item(
                id: nextID,
                text: "",
                kind: .image,
                fileURL: nil,
                image: Item.ImageData(
                    data: prepared.data,
                    type: NSPasteboard.PasteboardType(prepared.typeName),
                    thumbnail: prepared.thumbnail.flatMap(NSImage.init(data:)),
                    size: prepared.size
                )
            ))
        }
    }

    private struct PreparedImage: Sendable {
        let data: Data
        /// The pasteboard type's raw name.
        let typeName: String
        /// A small PNG for the list.
        let thumbnail: Data?
        let size: CGSize
    }

    private nonisolated static func prepareImage(_ data: Data, typeName: String, maxBytes: Int) -> PreparedImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        var stored = data
        var storedType = typeName
        if stored.count > maxBytes {
            // TIFFs from screenshots and image editors are often uncompressed;
            // PNG usually brings them under the cap.
            guard let decoded = decodedBytes(source), decoded <= maxDecodedBytes,
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
                  let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]),
                  png.count <= maxBytes else { return nil }
            stored = png
            storedType = "public.png"
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 96,
        ]
        let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            .flatMap { NSBitmapImageRep(cgImage: $0).representation(using: .png, properties: [:]) }
        return PreparedImage(
            data: stored,
            typeName: storedType,
            thumbnail: thumbnail,
            size: CGSize(width: width, height: height)
        )
    }

    /// What decoding the first frame would take, from the header alone
    /// (4 bytes a pixel); `nil` when the size is unknown.
    private nonisolated static func decodedBytes(_ source: CGImageSource) -> Int? {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        guard let width = properties?[kCGImagePropertyPixelWidth] as? Int,
              let height = properties?[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { return nil }
        let (pixels, overflow) = width.multipliedReportingOverflow(by: height)
        guard !overflow, pixels <= Int.max / 4 else { return nil }
        return pixels * 4
    }

    /// A TIFF of `data` for apps that only paste TIFF; `nil` when the image
    /// would decode to more than `maxDecodedBytes`.
    private nonisolated static func tiffCompatibility(for data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let decoded = decodedBytes(source), decoded <= maxDecodedBytes,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return NSBitmapImageRep(cgImage: image).tiffRepresentation
    }

    private func add(_ item: Item) {
        nextID += 1
        if let existing = items.firstIndex(where: { isSame($0, item) }) {
            items.remove(at: existing)
        }
        items.insert(item, at: 0)
        if items.count > limit {
            items.removeLast(items.count - limit)
        }
    }

    private func isSame(_ a: Item, _ b: Item) -> Bool {
        guard a.kind == b.kind else { return false }
        if a.kind == .image { return a.image?.data == b.image?.data }
        return a.text == b.text
    }

    func copy(_ item: Item) {
        let pasteboard = NSPasteboard.general
        switch item.kind {
        case .text:
            pasteboard.clearContents()
            pasteboard.setString(item.text, forType: .string)
        case .files:
            if let url = item.fileURL {
                pasteboard.clearContents()
                pasteboard.writeObjects([url as NSURL])
            }
        case .image:
            guard let image = item.image else { return }
            pasteboard.clearContents()
            pasteboard.setData(image.data, forType: image.type)
            guard image.type != .tiff else { return }
            // Older apps only paste TIFF. Decoding can be large, so build it off
            // the main actor and add it only if nothing was copied meanwhile.
            let changeCount = pasteboard.changeCount
            let data = image.data
            Task {
                let tiff = await Task.detached(priority: .userInitiated) {
                    ClipboardHistory.tiffCompatibility(for: data)
                }.value
                let pasteboard = NSPasteboard.general
                guard let tiff, pasteboard.changeCount == changeCount else { return }
                pasteboard.addTypes([.tiff], owner: nil)
                pasteboard.setData(tiff, forType: .tiff)
            }
        }
    }
}

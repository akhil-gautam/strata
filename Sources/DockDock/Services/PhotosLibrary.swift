import AppKit
import Photos
import Observation

/// Reads the newest asset out of the photo library.
@MainActor
@Observable
final class PhotosLibrary {
    private(set) var image: NSImage?
    private(set) var date: Date?
    private(set) var needsAccess = false

    func load() async {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            let granted = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            needsAccess = !(granted == .authorized || granted == .limited)
        } else {
            needsAccess = status != .authorized && status != .limited
        }
        guard !needsAccess else { return }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 1

        let assets = PHAsset.fetchAssets(with: .image, options: options)
        guard let asset = assets.firstObject else { return }
        date = asset.creationDate

        let settings = PHImageRequestOptions()
        settings.deliveryMode = .highQualityFormat
        settings.resizeMode = .fast
        settings.isNetworkAccessAllowed = true

        let result = await withCheckedContinuation { continuation in
            var resumed = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 320, height: 320),
                contentMode: .aspectFill,
                options: settings
            ) { image, _ in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: image)
            }
        }
        image = result
    }
}

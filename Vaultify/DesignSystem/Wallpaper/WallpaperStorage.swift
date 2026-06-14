import UIKit

/// Stores user-picked wallpaper images in the App Group container (file-protected).
/// Used by the wallpaper gallery (Phase 05). Kept light — downscaled JPEG.
nonisolated enum WallpaperStorage {
    private static var directory: URL {
        let url = SharedConfig.containerURL.appending(path: "Wallpapers", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func url(named name: String) -> URL { directory.appending(path: name) }

    static func loadImage(named name: String) -> UIImage? {
        UIImage(contentsOfFile: url(named: name).path)
    }

    /// Persist a (already-downscaled) image; returns its file name for the `Wallpaper`.
    @discardableResult
    static func save(_ image: UIImage, name: String = UUID().uuidString + ".jpg") -> String? {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return nil }
        do {
            try data.write(to: url(named: name), options: [.completeFileProtection, .atomic])
            return name
        } catch {
            return nil
        }
    }

    static func delete(named name: String) {
        try? FileManager.default.removeItem(at: url(named: name))
    }

    /// Downscale so the longest side is at most `maxDimension` (keeps the wallpaper
    /// file small + memory-cheap, esp. for the AutoFill extension).
    static func downscale(_ image: UIImage, maxDimension: CGFloat = 1600) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension, longest > 0 else { return image }
        let scale = maxDimension / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

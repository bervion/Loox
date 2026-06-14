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
}

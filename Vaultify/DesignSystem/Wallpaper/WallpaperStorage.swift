import Foundation
import CoreGraphics
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Stores user-picked wallpaper images in the App Group container (file-protected).
/// Used by the wallpaper gallery (Phase 05). Kept light — downscaled JPEG.
nonisolated enum WallpaperStorage {
    private static var directory: URL {
        let url = SharedConfig.containerURL.appending(path: "Wallpapers", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func url(named name: String) -> URL { directory.appending(path: name) }

    static func loadImage(named name: String) -> PlatformImage? {
        PlatformImage(contentsOfFile: url(named: name).path)
    }

    /// Persist a (already-downscaled) image; returns its file name for the `Wallpaper`.
    @discardableResult
    static func save(_ image: PlatformImage, name: String = UUID().uuidString + ".jpg") -> String? {
        guard let data = jpegData(image, quality: 0.85) else { return nil }
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
    static func downscale(_ image: PlatformImage, maxDimension: CGFloat = 1600) -> PlatformImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension, longest > 0 else { return image }
        let scale = maxDimension / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        #if canImport(UIKit)
        return UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        #elseif canImport(AppKit)
        let resized = NSImage(size: size)
        resized.lockFocus()
        image.draw(in: CGRect(origin: .zero, size: size))
        resized.unlockFocus()
        return resized
        #endif
    }

    /// JPEG-encode `image` at `quality` (0...1), cross-platform.
    private static func jpegData(_ image: PlatformImage, quality: CGFloat) -> Data? {
        #if canImport(UIKit)
        return image.jpegData(compressionQuality: quality)
        #elseif canImport(AppKit)
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
        #endif
    }
}

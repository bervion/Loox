import Foundation
import CoreGraphics
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Avatar image processing: downscale a picked photo to a small JPEG so the sealed bytes
/// ride the item's CKRecord well under the 1MB field limit. Pure (no I/O), testable.
enum AvatarImage {
    static let maxDimension: CGFloat = 256

    /// Downscale `image` so its longest side ≤ `maxDimension`, then JPEG-encode.
    static func downscaledJPEG(_ image: PlatformImage,
                               maxDimension: CGFloat = maxDimension,
                               quality: CGFloat = 0.8) -> Data? {
        let longest = max(image.size.width, image.size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        #if canImport(UIKit)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1  // `target` is already in pixels — don't let @2x/@3x inflate the output
        let rendered = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return rendered.jpegData(compressionQuality: quality)
        #elseif canImport(AppKit)
        let resized = NSImage(size: target)
        resized.lockFocus()
        image.draw(in: CGRect(origin: .zero, size: target))
        resized.unlockFocus()
        guard let tiff = resized.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
        #endif
    }
}

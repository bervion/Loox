import SwiftUI

#if canImport(UIKit)
import UIKit
/// Cross-platform bitmap type: `UIImage` on iOS/iPadOS, `NSImage` on macOS.
/// Lives in VaultifyCore so shared code (e.g. `MeshGradientRenderer`) that is
/// compiled into BOTH the app and the AutoFill extension resolves one symbol.
public typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
public typealias PlatformImage = NSImage
#endif

public extension PlatformImage {
    /// Decode raw bytes into a platform image (nil on failure).
    static func fromData(_ data: Data) -> PlatformImage? {
        #if canImport(UIKit)
        return UIImage(data: data)
        #elseif canImport(AppKit)
        return NSImage(data: data)
        #endif
    }

    /// Wrap a `CGImage` at an explicit pixel size (macOS `NSImage` needs a size).
    static func fromCGImage(_ cgImage: CGImage, pixelSize: CGSize) -> PlatformImage {
        #if canImport(UIKit)
        return UIImage(cgImage: cgImage)
        #elseif canImport(AppKit)
        return NSImage(cgImage: cgImage, size: pixelSize)
        #endif
    }

    /// PNG encoding of the image (nil if it cannot be rendered).
    var platformPNGData: Data? {
        #if canImport(UIKit)
        return pngData()
        #elseif canImport(AppKit)
        guard let tiff = tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
        #endif
    }
}

public extension Image {
    /// Build a SwiftUI `Image` from a platform bitmap without per-call `#if`.
    init(platformImage: PlatformImage) {
        #if canImport(UIKit)
        self.init(uiImage: platformImage)
        #elseif canImport(AppKit)
        self.init(nsImage: platformImage)
        #endif
    }
}

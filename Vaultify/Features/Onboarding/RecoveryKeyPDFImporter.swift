import Foundation
#if os(iOS)
import PDFKit
import CoreImage
import UIKit

/// Reads a recovery key out of a saved Emergency Kit PDF by decoding its Setup Code
/// QR (the same payload the camera scanner reads — the recovery key verbatim). The
/// PDF page is rasterised via `ImageRenderer`, so the text is not extractable; the
/// QR is, and it is machine-readable regardless of how the page was drawn.
enum RecoveryKeyPDFImporter {
    /// Render each page and return the first QR payload found, or nil. Runs the heavy
    /// rasterise + detect off the main actor.
    static func extractRecoveryKey(from url: URL) async -> String? {
        await Task.detached(priority: .userInitiated) {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            guard let document = PDFDocument(url: url) else { return nil }
            let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: CIContext(),
                                      options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])

            for index in 0..<document.pageCount {
                guard let page = document.page(at: index) else { continue }
                let bounds = page.bounds(for: .mediaBox)
                // Upscale so the QR modules stay crisp for the detector.
                let scale: CGFloat = 3
                let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
                let image = page.thumbnail(of: size, for: .mediaBox)
                guard let cgImage = image.cgImage else { continue }

                let features = detector?.features(in: CIImage(cgImage: cgImage)) ?? []
                for case let qr as CIQRCodeFeature in features {
                    let payload = qr.messageString?.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let payload, !payload.isEmpty { return payload }
                }
            }
            return nil
        }.value
    }
}
#endif

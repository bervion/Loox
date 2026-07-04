import SwiftUI
import UniformTypeIdentifiers

/// Renders `EmergencyKitPDFPage` to a single-page PDF and wraps the bytes as a
/// `FileDocument` so SwiftUI's `.fileExporter` can save it. Kept separate from the
/// page layout so the drawing view stays purely declarative.
enum EmergencyKitPDF {
    /// Rasterise the kit page into PDF data. `@MainActor` because `ImageRenderer` and the
    /// SwiftUI view it draws are main-actor bound. Returns nil only if the PDF context
    /// can't be created (out of memory) — the caller treats that as an export failure.
    @MainActor
    static func makeData(_ info: EmergencyKitInfo) -> Data? {
        let renderer = ImageRenderer(content: EmergencyKitPDFPage(info: info))
        // Point-for-point mapping: the page view is already A4-sized in points.
        renderer.proposedSize = .init(EmergencyKitPDFPage.pageSize)

        let data = NSMutableData()
        var didDraw = false
        renderer.render { size, renderInContext in
            var mediaBox = CGRect(origin: .zero, size: size)
            guard let consumer = CGDataConsumer(data: data as CFMutableData),
                  let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return }
            ctx.beginPDFPage(nil)
            renderInContext(ctx)
            ctx.endPDFPage()
            ctx.closePDF()
            didDraw = true
        }
        return didDraw ? data as Data : nil
    }
}

/// A ready-made PDF wrapped for `.fileExporter`. Export-only (no reading back).
struct EmergencyKitPDFFile: FileDocument {
    static let readableContentTypes: [UTType] = [.pdf]

    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

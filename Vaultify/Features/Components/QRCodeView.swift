import SwiftUI
import CoreImage.CIFilterBuiltins

/// Renders a string as a QR code (used by device pairing). CoreImage is available
/// on both iOS and macOS; the tiny generated bitmap is scaled up with interpolation
/// off so the modules stay crisp. Always drawn on a white tile — QR readers need
/// dark-on-light regardless of the app theme (mirrors the favicon-tile exemption).
struct QRCodeView: View {
    let payload: String

    var body: some View {
        Group {
            if let image = Self.qrImage(for: payload) {
                Image(decorative: image, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                Color.clear
            }
        }
        .padding(Space.s4)
        .background(.white, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private static func qrImage(for payload: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }
}

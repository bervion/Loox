import SwiftUI
import UIKit
import PhotosUI
import CoreImage
import CoreImage.CIFilterBuiltins

/// Add a one-time-code secret like 1Password: scan a QR with the camera, pick a
/// QR screenshot from Photos, or paste a setup key / `otpauth://` URI.
struct TOTPScannerSheet: View {
    let onCapture: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var photoItem: PhotosPickerItem?
    @State private var manual = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ZStack {
                    QRScannerView { handle($0) }
                    VStack {
                        Spacer()
                        Text("Point the camera at the 2FA QR code")
                            .font(.subheadline).foregroundStyle(.white)
                            .padding(.bottom, 28).shadow(radius: 4)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)

                controls
            }
            .ignoresSafeArea(edges: .top)
            .navigationTitle("Add 2FA Code")
            // Camera scanner is always dark (black preview), so keep the nav title /
            // chrome light regardless of the app theme — themed light here would make
            // the title invisible over the black camera feed.
            .preferredColorScheme(.dark)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .onChange(of: photoItem) { _, item in Task { await loadPhoto(item) } }
        }
    }

    private var controls: some View {
        VStack(spacing: Space.s3) {
            if let error {
                Text(error).font(.footnote).foregroundStyle(VaultColors.strengthWeak)
            }
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label { Text("Choose a screenshot") } icon: { PolarisIcon(Icons.image) }
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            HStack {
                TextField("Or paste setup key", text: $manual)
                    .font(.body)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Add") { handle(manual) }.disabled(manual.isEmpty)
            }
        }
        .padding()
        .background(.regularMaterial)
    }

    private func handle(_ raw: String) {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        if value.lowercased().hasPrefix("otpauth://") || TOTPGenerator.base32Decode(value) != nil {
            onCapture(value)
            dismiss()
        } else {
            error = appString("That doesn’t look like a 2FA setup code.")
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        if let code = Self.decodeQR(from: image) {
            handle(code)
        } else {
            error = appString("No QR code found in that image.")
        }
    }

    static func decodeQR(from image: UIImage) -> String? {
        guard let ciImage = CIImage(image: image) else { return nil }
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                  options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        let features = (detector?.features(in: ciImage) as? [CIQRCodeFeature]) ?? []
        return features.compactMap(\.messageString).first
    }
}

import SwiftUI

/// Thin wrapper presenting `QRScannerView` for a Quick View session code —
/// reuses the same scanner the 2FA setup flow uses (`TOTPScannerSheet`),
/// never a re-implementation.
struct QuickViewScannerSheet: View {
    let onFound: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                QRScannerView { value in
                    onFound(value)
                    dismiss()
                }
                VStack {
                    Spacer()
                    Text("Point the camera at the code on your computer")
                        .font(.subheadline).foregroundStyle(.white)
                        .padding(.bottom, 28).shadow(radius: 4)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
            .ignoresSafeArea(edges: .top)
            .navigationTitle("Scan Code")
            // Camera preview is always dark — keep the nav chrome legible
            // over it regardless of the app theme.
            .preferredColorScheme(.dark)
            .platformNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}

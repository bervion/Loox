import SwiftUI

#if os(iOS)
import VisionKit
#endif

/// Result of a completed card scan: digits-only card number, `MM/YY` expiry (if found),
/// and cardholder name (if found) — feeds straight into the card template's fields.
struct CardScanResult {
    let numberDigits: String
    let expiry: String?
    let cardholderName: String?
}

/// Scan a physical card with the camera (VisionKit live text) to prefill the Card Number,
/// Expiry, and Cardholder fields. The entry point that presents this sheet
/// (`ItemEditorScreen`) checks `isAvailable` first and hides itself entirely when
/// unsupported (the Simulator, or a device without the on-device text model) — manual
/// entry always remains the fallback, never gated on this feature.
struct CardScannerSheet: View {
    let onCapture: (CardScanResult) -> Void
    @Environment(\.dismiss) private var dismiss

    /// Whether this device can run live camera text scanning at all.
    static var isAvailable: Bool {
        #if os(iOS)
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
        #else
        false
        #endif
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CardDataScannerView { result in
                    onCapture(result)
                    dismiss()
                }
                VStack {
                    Spacer()
                    Text("Point the camera at your card")
                        .vaultType(.subhead).foregroundStyle(.white)
                        .padding(.bottom, 28).shadow(radius: 4)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
            .ignoresSafeArea(edges: .top)
            .navigationTitle("Scan Card")
            // Camera scanner is always dark (black preview) — keep the nav chrome light
            // regardless of the app theme, matching `TOTPScannerSheet`'s own camera sheet.
            .preferredColorScheme(.dark)
            .platformNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}

#if os(iOS)

/// Bridges `DataScannerViewController` (VisionKit live text) into SwiftUI. This file (and
/// every card-scan file) lives under `Vaultify/**`, never `VaultifyCore/**` — the AutoFill
/// extension target doesn't compile it and never links VisionKit.
private struct CardDataScannerView: UIViewControllerRepresentable {
    var onCandidate: (CardScanResult) -> Void

    func makeCoordinator() -> CardScannerCoordinator {
        let coordinator = CardScannerCoordinator()
        coordinator.onCandidate = onCandidate
        return coordinator
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.text()],
            qualityLevel: .balanced,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: false,
            isGuidanceEnabled: true,
            isHighlightingEnabled: false)
        controller.delegate = context.coordinator
        try? controller.startScanning()
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}
}

/// Runs the text heuristics over every recognized-text update and fires `onCandidate` once
/// the same candidate PAN has been read stably across a few consecutive frames (avoids
/// capturing a single misread frame) — mirrors `QRScannerController`'s "fire once" contract.
final class CardScannerCoordinator: NSObject, DataScannerViewControllerDelegate {
    var onCandidate: (CardScanResult) -> Void = { _ in }

    private var stablePAN: String?
    private var stableFrameCount = 0
    private var didCapture = false
    private let requiredStableFrames = 3

    func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem],
                     allItems: [RecognizedItem]) {
        process(allItems)
    }

    func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem],
                     allItems: [RecognizedItem]) {
        process(allItems)
    }

    private func process(_ items: [RecognizedItem]) {
        guard !didCapture else { return }
        let lines: [String] = items.compactMap { item in
            if case let .text(text) = item { return text.transcript }
            return nil
        }
        guard let pan = CardScanHeuristics.longestLuhnValidPAN(in: lines) else {
            stablePAN = nil
            stableFrameCount = 0
            return
        }
        if pan == stablePAN {
            stableFrameCount += 1
        } else {
            stablePAN = pan
            stableFrameCount = 1
        }
        guard stableFrameCount >= requiredStableFrames else { return }

        didCapture = true
        let result = CardScanResult(numberDigits: pan,
                                    expiry: CardScanHeuristics.expiry(in: lines),
                                    cardholderName: CardScanHeuristics.cardholderName(in: lines))
        Haptics.tap()
        onCandidate(result)
    }
}

#else

/// macOS has no camera scanner in this app — `CardScannerSheet.isAvailable` is always
/// `false` there, so this branch never actually presents (kept only so the file compiles
/// on every platform target, mirroring `QRScannerView`'s cross-platform placeholder).
private struct CardDataScannerView: View {
    var onCandidate: (CardScanResult) -> Void

    var body: some View {
        Text("Scan on iPhone")
            .vaultType(.headline)
            .foregroundStyle(.white)
    }
}

#endif

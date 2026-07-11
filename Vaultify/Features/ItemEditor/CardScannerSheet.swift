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
                CardScanReticleOverlay()
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
                ToolbarItem(placement: .cancellationAction) {
                    // Explicit white — the app accent can be dark enough to sink into
                    // the camera preview (camera surface: literal white is exempt).
                    Button("Cancel") { dismiss() }.tint(.white)
                }
            }
        }
    }
}

/// Card-shaped reticle over the live preview: dims everything except an ISO-ratio
/// (1.586:1) rounded window, outlines it, and anchors the guidance line below it — the
/// user instantly knows where to hold the card. Literal white/black are fine here (camera
/// surface exemption); the overlay never intercepts touches and is purely decorative to
/// VoiceOver except the guidance text.
private struct CardScanReticleOverlay: View {
    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width * 0.78
            let height = width / 1.586
            let frame = CGRect(x: (geo.size.width - width) / 2,
                               y: geo.size.height * 0.42 - height / 2,
                               width: width, height: height)
            ZStack {
                // Dim outside the card window (even-odd punch-out).
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: geo.size))
                    path.addRoundedRect(in: frame,
                                        cornerSize: CGSize(width: Radius.lg, height: Radius.lg),
                                        style: .continuous)
                }
                .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))
                .accessibilityHidden(true)

                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(.white.opacity(0.7), lineWidth: 1.5)
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                    .accessibilityHidden(true)

                cornerBrackets(frame)
                    .accessibilityHidden(true)

                Text("Point the camera at your card")
                    .vaultType(.subhead)
                    .foregroundStyle(.white)
                    .shadow(radius: 4)
                    .position(x: frame.midX, y: frame.maxY + 40)
            }
        }
        .allowsHitTesting(false)
    }

    /// Four bold corner brackets on the window — the familiar scan-UI affordance.
    private func cornerBrackets(_ frame: CGRect) -> some View {
        let arm: CGFloat = 22
        let inset: CGFloat = Radius.lg
        return Path { path in
            // Each bracket: two arms meeting at the corner, following the rounded edge.
            for (corner, dx, dy) in [(CGPoint(x: frame.minX, y: frame.minY), 1.0, 1.0),
                                     (CGPoint(x: frame.maxX, y: frame.minY), -1.0, 1.0),
                                     (CGPoint(x: frame.minX, y: frame.maxY), 1.0, -1.0),
                                     (CGPoint(x: frame.maxX, y: frame.maxY), -1.0, -1.0)] {
                path.move(to: CGPoint(x: corner.x, y: corner.y + dy * (inset + arm)))
                path.addLine(to: CGPoint(x: corner.x, y: corner.y + dy * inset))
                path.addQuadCurve(to: CGPoint(x: corner.x + dx * inset, y: corner.y),
                                  control: corner)
                path.addLine(to: CGPoint(x: corner.x + dx * (inset + arm), y: corner.y))
            }
        }
        .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
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

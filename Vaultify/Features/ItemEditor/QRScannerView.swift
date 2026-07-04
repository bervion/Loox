import SwiftUI

#if os(iOS)
import UIKit
import AVFoundation

/// Live QR scanner (AVFoundation) bridged to SwiftUI, with a Telegram-style
/// animated focus frame that springs onto the detected code. Fires `onFound`
/// once. The camera is unavailable on the Simulator, so callers also offer
/// photo import and manual entry.
struct QRScannerView: UIViewControllerRepresentable {
    var onFound: (String) -> Void

    func makeUIViewController(context: Context) -> QRScannerController {
        let controller = QRScannerController()
        controller.onFound = onFound
        return controller
    }

    func updateUIViewController(_ controller: QRScannerController, context: Context) {}
}

final class QRScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onFound: ((String) -> Void)?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let overlay = QRScannerOverlayView()
    private var didFind = false
    private var didEnter = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        overlay.frame = view.bounds
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(overlay) // always present, even where no camera exists (Simulator)
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard granted else { return }
            DispatchQueue.main.async { self?.configureSession() }
        }
    }

    private func configureSession() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.layer.bounds
        if let connection = preview.connection, connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90 // portrait
        }
        view.layer.insertSublayer(preview, at: 0) // below the overlay subview
        previewLayer = preview

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in self?.session.startRunning() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !didEnter { didEnter = true; overlay.playEntryAnimation() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning { session.stopRunning() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.layer.bounds
        overlay.frame = view.bounds
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard !didFind,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue,
              let transformed = previewLayer?.transformedMetadataObject(for: object) else { return }

        // Gate: only lock when the code is roughly centered (avoids edge jitter).
        let center = CGPoint(x: transformed.bounds.midX, y: transformed.bounds.midY)
        guard overlay.idleRect.insetBy(dx: -32, dy: -32).contains(center) else { return }

        didFind = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        overlay.focus(on: transformed.bounds)
        // Let the snap animation play before handing the value back.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.onFound?(value)
        }
    }
}

#else

/// macOS has no camera scanner in this app (iPad/iPhone-only capture flow).
/// Callers (`TOTPScannerSheet`) still offer photo import + manual paste on macOS,
/// so this is a simple placeholder over the same black backdrop the iOS camera
/// preview uses — not a functional gap, since the manual paths remain live.
struct QRScannerView: View {
    var onFound: (String) -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("Scan on iPhone")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Use a photo or paste the setup key below instead.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

#endif

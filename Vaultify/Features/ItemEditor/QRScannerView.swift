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
    /// Tint for the warm-up glow. Camera surfaces are a documented exemption
    /// from the semantic-colour rule, but the cold start should still read as
    /// Loox rather than as a stalled black rectangle.
    ///
    /// `VaultColors.accent`, not `.accentColor`: the latter resolves to the
    /// asset catalog's fixed blue and would ignore whichever of the seven
    /// Design System accents the user actually picked.
    var tint: Color = VaultColors.accent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeUIViewController(context: Context) -> QRScannerController {
        let controller = QRScannerController()
        controller.onFound = onFound
        controller.glowColor = UIColor(tint)
        controller.reduceMotion = reduceMotion
        return controller
    }

    func updateUIViewController(_ controller: QRScannerController, context: Context) {
        controller.reduceMotion = reduceMotion
    }
}

/// Cold-start cover for the camera preview.
///
/// `AVCaptureSession` needs a few hundred milliseconds to deliver its first
/// frame, and the sheet animates up long before that. Without a cover the user
/// watches a black rectangle slide in, which reads as a broken camera rather
/// than a loading one. A literal blur has nothing to sample here — both callers
/// place `.background(.black)` directly behind the scanner, so a material would
/// resolve to flat grey — so this is an accent glow that breathes until the
/// first frame lands.
final class QRScannerWarmUpView: UIView {
    private let glow = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .black
        glow.type = .radial
        glow.startPoint = CGPoint(x: 0.5, y: 0.5)
        glow.endPoint = CGPoint(x: 1, y: 1)
        layer.addSublayer(glow)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Square, centred, and wider than the view so the falloff never shows
        // a hard edge on any aspect ratio.
        let side = max(bounds.width, bounds.height) * 1.4
        glow.frame = CGRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2,
                            width: side, height: side)
    }

    func apply(tint: UIColor) {
        glow.colors = [tint.withAlphaComponent(0.30).cgColor,
                       tint.withAlphaComponent(0.10).cgColor,
                       tint.withAlphaComponent(0).cgColor]
        glow.locations = [0, 0.45, 1]
    }

    /// Breathing opacity so the wait reads as "working", not "frozen".
    func startBreathing() {
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.5
        pulse.toValue = 1
        pulse.duration = 1.1
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        glow.add(pulse, forKey: "warmUpBreath")
    }

    /// The pulse lives on `glow`, a SUBLAYER. `layer.removeAllAnimations()` is
    /// not recursive, so removing from the view's own layer left an infinite
    /// animation running on a hidden view for as long as the scanner was open.
    func stopBreathing() {
        glow.removeAnimation(forKey: "warmUpBreath")
    }
}

final class QRScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onFound: ((String) -> Void)?

    var glowColor: UIColor = .systemBlue
    var reduceMotion = false

    private let session = AVCaptureSession()
    /// Every session mutation in the app runs here, and it is deliberately
    /// STATIC — one queue shared by every scanner instance that will ever
    /// exist, not one per controller.
    ///
    /// A per-instance queue let two sessions overlap: dismissing the sheet
    /// enqueues `stopRunning()` on the outgoing controller's queue, and
    /// re-presenting immediately builds a NEW controller that runs
    /// `startRunning()` on a different queue. Both then hold the same capture
    /// device, the newcomer loses and is interrupted with
    /// `videoDeviceInUseByAnotherClient`, and the preview stays black until the
    /// next open — exactly the "toggle it quickly a few times" failure. One
    /// shared serial queue orders the teardown strictly before the next
    /// startup, so the device is always free when the new session claims it.
    private static let sessionQueue = DispatchQueue(label: "com.bervion.vaultify.qr-session")
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let overlay = QRScannerOverlayView()
    private let warmUp = QRScannerWarmUpView()
    private var previewingObservation: NSKeyValueObservation?
    private var didFind = false
    private var didReveal = false

    /// Last-resort ceiling on the warm-up cover. `isPreviewing` is the real
    /// signal, but Apple does not document it as KVO-compliant, so a silent
    /// miss must not strand the user behind the cover forever.
    ///
    /// Deliberately long. An earlier 2s value was a bug, not a safety net:
    /// session start is serialised across every scanner instance, so
    /// re-opening right after a close waits for the previous teardown and
    /// legitimately exceeds two seconds. The timer then tore the cover away to
    /// reveal a preview with no frames yet — the "black for a moment" the user
    /// sees. Nothing that is merely slow should trip this; the cases where the
    /// camera will genuinely never start (denied, restricted, no device) call
    /// `reveal()` directly instead of waiting it out.
    private static let warmUpTimeout: TimeInterval = 10.0

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        // The preview layer exists before the session is configured so the
        // cover, the overlay and the layer are all in their final z-order by
        // the time the sheet starts animating.
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.layer.bounds
        view.layer.insertSublayer(preview, at: 0)
        previewLayer = preview

        overlay.frame = view.bounds
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.alpha = 0 // enters with the reveal, not with the sheet
        view.addSubview(overlay) // always present, even where no camera exists (Simulator)

        warmUp.frame = view.bounds
        warmUp.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        warmUp.apply(tint: glowColor)
        view.addSubview(warmUp)
        if !reduceMotion { warmUp.startBreathing() }

        observePreviewing(preview)
        observeSessionHealth()
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.warmUpTimeout) { [weak self] in
            self?.reveal()
        }

        // Asking for a status we already hold avoids a pointless async hop on
        // every subsequent open.
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startSession()
        case .notDetermined:
            // The weak reference is resolved INSIDE the main hop, never on
            // AVFoundation's own queue: resolving it there would make this
            // completion the last owner and deallocate the controller off main.
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted { self.startSession() } else { self.reveal() }
                }
            }
        default:
            // Denied or restricted: nothing will ever arrive, so drop the cover
            // now and let the caller's photo-import / manual-entry paths show.
            reveal()
        }
    }

    /// `isPreviewing` flips when the layer has a frame to present — the only
    /// signal that actually means "there is something to look at".
    private func observePreviewing(_ preview: AVCaptureVideoPreviewLayer) {
        previewingObservation = preview.observe(\.isPreviewing, options: [.initial, .new]) {
            [weak self] layer, _ in
            guard layer.isPreviewing else { return }
            DispatchQueue.main.async { self?.reveal() }
        }
    }

    private func startSession() {
        Self.sessionQueue.async { [weak self] in
            guard let self else { return }
            let configured = self.configureSession()
            DispatchQueue.main.async {
                self.applyPreviewRotation()
                // No usable device (Simulator, hardware fault): frames will
                // never arrive, so drop the cover now rather than making the
                // user stare at it until the backstop expires.
                if !configured { self.reveal() }
            }
            guard configured else { return }
            self.session.startRunning()
            // `guard let self` promotes the weak capture to a strong one held
            // for the whole block — several hundred ms on a cold camera. If the
            // user dismisses inside that window this block owns the LAST
            // reference, and returning would deallocate a UIViewController, its
            // view tree and an AVCaptureVideoPreviewLayer on this queue. UIKit
            // and CoreAnimation teardown is main-thread-only, so hand the final
            // release back to main.
            DispatchQueue.main.async { withExtendedLifetime(self) {} }
        }
    }

    /// The capture device can be taken away mid-session (a phone call, Control
    /// Centre, another app, Split View). Without these the preview simply goes
    /// black and never comes back, which is indistinguishable from a crash to
    /// the user. Recovery is: restart on runtime error, and resume when an
    /// interruption ends.
    private func observeSessionHealth() {
        let center = NotificationCenter.default
        center.addObserver(forName: .AVCaptureSessionRuntimeError, object: session,
                           queue: .main) { [weak self] _ in
            self?.restartSession()
        }
        center.addObserver(forName: .AVCaptureSessionInterruptionEnded, object: session,
                           queue: .main) { [weak self] _ in
            self?.restartSession()
        }
    }

    private func restartSession() {
        guard isViewLoaded, view.window != nil else { return }
        previewLayer?.connection?.isEnabled = true
        Self.sessionQueue.async { [session] in
            if !session.isRunning { session.startRunning() }
        }
    }

    /// Runs on `sessionQueue`. One begin/commit pair so the session reconfigures
    /// once rather than per-addition. Returns false when there is nothing to
    /// capture from, so the caller can stop waiting for frames.
    private func configureSession() -> Bool {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return false }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return false }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]
        return true
    }

    /// Layer geometry is main-thread state, so it is applied here rather than
    /// on the session queue. The connection only exists once an input is added.
    private func applyPreviewRotation() {
        guard let connection = previewLayer?.connection,
              connection.isVideoRotationAngleSupported(90) else { return }
        connection.videoRotationAngle = 90 // portrait
    }

    /// Idempotent: whichever of the KVO signal, the timeout, or the denied path
    /// arrives first wins, and the rest are no-ops.
    private func reveal() {
        guard !didReveal else { return }
        didReveal = true
        previewingObservation = nil

        let settle = { [weak self] in
            self?.warmUp.isHidden = true
            self?.warmUp.stopBreathing()
        }
        guard !reduceMotion else {
            warmUp.alpha = 0
            overlay.alpha = 1
            settle()
            return
        }
        UIView.animate(withDuration: 0.32, delay: 0, options: [.curveEaseOut]) {
            self.warmUp.alpha = 0
            self.overlay.alpha = 1
        } completion: { _ in settle() }
        overlay.playEntryAnimation()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // A controller can be presented again after `viewWillDisappear` froze
        // its connection. Without this the second presentation renders the one
        // stale frame it held and never updates.
        previewLayer?.connection?.isEnabled = true
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Hold the last frame rather than tearing to black behind the sheet's
        // dismissal: disabling the connection stops new frames while the layer
        // keeps presenting the one it already has.
        previewLayer?.connection?.isEnabled = false
        Self.sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.layer.bounds
        overlay.frame = view.bounds
        warmUp.frame = view.bounds
    }

    deinit {
        previewingObservation = nil
        NotificationCenter.default.removeObserver(self)
        // The session must be torn down even if the controller is released
        // without ever disappearing, or it keeps holding the capture device
        // and the next scanner opens black.
        Self.sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard !didFind,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue,
              let transformed = previewLayer?.transformedMetadataObject(for: object) else { return }

        // Accept a decoded QR anywhere in the visible camera frame. The earlier
        // gate required the code to be centered inside the focus square, which
        // silently dropped a QR shown on a computer screen (it appears small /
        // off-center when the phone frames the whole monitor) — reading to the
        // user as "the camera never detects". AVFoundation only reports codes it
        // actually decoded, so firing on any on-frame QR is safe; the focus
        // animation still snaps to wherever the code sits.
        let center = CGPoint(x: transformed.bounds.midX, y: transformed.bounds.midY)
        guard view.bounds.contains(center) else { return }

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
                .vaultType(.headline)
                .foregroundStyle(.white)
            Text("Use a photo or paste the setup key below instead.")
                .vaultType(.footnote)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding(Space.gutter)
    }
}

#endif

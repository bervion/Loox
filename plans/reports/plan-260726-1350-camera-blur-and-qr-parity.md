# Camera cold-start blur + QR rendering parity — hardened plan

Date: 2026-07-26
Status: ready to execute (Track A independent of Track B)
Repos:
- iOS: `/Users/bervion/Developer/Projects/mobile/ios/Vaultify`
- Web: `/Users/bervion/Developer/Projects/frontend/looxpassword`

Every file:line below was opened and read during review. Corrections to the incoming
drafts are called out inline as **CORRECTION**; they are load-bearing, not stylistic.

---

## Review verdict on the incoming drafts

| # | Incoming claim | Verdict | Action |
|---|---|---|---|
| A1 | Session config runs on main inside the present animation | **Confirmed** — `QRScannerView.swift:38-66`, `configureSession()` dispatched to `DispatchQueue.main.async` at :40 | Keep |
| A2 | `stopRunning()` blocks main on dismiss | **Confirmed** — `QRScannerView.swift:75` | Keep |
| A3 | Nothing drawn before first frame | **Confirmed** — `:34` `view.backgroundColor = .black`; preview layer only created at `:56` | Keep |
| A4 | No first-frame signal; entry animation on `viewDidAppear` | **Confirmed** — `:68-71` | Keep |
| A5 | `requestAccess` called unconditionally | **Confirmed** — `:38` | Keep |
| A6 | No freeze/blur on pause, dismiss, background | **Confirmed** | Keep |
| A7 | `.font(.subheadline)` in Quick View caption | **Confirmed** — `QuickViewScannerSheet.swift:20` (siblings use `.vaultType(.subhead)`, `TOTPScannerSheet.swift:24`) | Keep |
| A8 | "`.ultraThinMaterial` in a sheet samples the dimmed presenting screen" | **WRONG** | **CORRECTION 1** |
| A9 | "Freeze cover leaves the reticle snap visible" | **WRONG** (z-order) | **CORRECTION 2** |
| A10 | `sessionQueue.suspend()`/`resume()` around the permission prompt | Unnecessary | **CORRECTION 4** |
| A11 | Drop preset to `.hd1280x720` | **Rejected** — scannability regression | **CORRECTION 5** |
| A12 | Watchdog delay `Motion.slow * 6` | Token misuse | **CORRECTION 6** |
| B1 | `ctx.roundRect` unguarded, throw escapes to `renderTerminal('error')` | **Confirmed** — `open-page-script-render.ts:64,76,79`; `open-page-script-flow.ts:81-83` catch → `renderTerminal('error')` | Keep |
| B1b | "…and it is currently DEPLOYED in production" | **Unverified** | **CORRECTION 7** |
| B2 | Web insets all four sides; runs merge horizontally only | **Confirmed** — `gap = modulePx * 0.08` at `:51`, horizontal-only run loop `:52-67` | Keep |
| B3 | Web finders stroked at `lineWidth = modulePx * 0.95` | **Confirmed** — `:70-81` | Keep |
| B4 | App quiet zone is fixed 16pt, sub-spec | **Confirmed** — `QRCodeView.swift:24` `.padding(Space.s4)`, `Space.s4 = 16` | Keep |
| B5 | Landing mock is a third copy with 2.6-module quiet zone | **Confirmed** — `brand-canvas.ts:758` `pad = S * 0.1`, n=21 | Keep |
| B6 | Landing mock redrawn at 60fps | **Confirmed** — `use-brand-canvas.ts` rAF loop calls `drawRef.current` every frame unless reduced motion | Keep |
| B7 | `QRCodeView` regenerates matrix + `CIContext()` per body eval | **Confirmed** — `:13-16` eager `makeMatrix`, `:107` `CIContext()` per call | Keep |
| B8 | Encoder hard-codes mask 0, EC-M only | **Confirmed** — `qr-encoder.ts:6-9` header, `buildMatrix(version, 0, …)` in `encodeByteMode`, `formatInfoBits` comment "ECC level M = 00" | Keep |
| B9 | Decode test rasterizes squares only | **Confirmed** — `test-qr-decode.ts:21-31` `toImage` fills `SCALE×SCALE` blocks | Keep |
| B10 | Ink `#101114` vs app `.black` | **Confirmed** — `open-page-script-render.ts:41`, `brand-canvas.ts:771`; app `QRCodeView.swift:61,73,77` | Keep |
| B11 | `roundRect` only in the worker | **Incomplete** — `brand-canvas.ts` uses it at 4 sites too | **CORRECTION 8** |

### Cross-cutting checks requested

**(a) API availability at iOS 17.3.** All verified available:
- `AVCaptureVideoPreviewLayer.isPreviewing` — iOS 13.0+. **Caveat:** Apple does not
  document it as KVO-compliant. It is observed in practice, but the watchdog in Step A4 is a
  **hard requirement**, not defensive polish.
- `AVCaptureConnection.isEnabled` — iOS 4.0+, settable.
- `connection.isVideoRotationAngleSupported(_:)` / `videoRotationAngle` — iOS 17.0+. Already
  in use at `QRScannerView.swift:59-61`, so the ceiling is already established.
- `AVCaptureSession.beginConfiguration()/commitConfiguration()` — iOS 4.0+.
- `\.accessibilityReduceMotion`, `\.accessibilityReduceTransparency` — iOS 14+ / 13+, both
  already used in-repo (`VaultScreenHeader.swift:60`, `HomeHeaderBar.swift:21`).
- `Animation.vault(_:reduceMotion:)` — exists, `DesignSystem/Tokens/Motion.swift`.
- `Color(rgb:opacity:)` — exists, `VaultifyCore/Theme/ColorHex.swift:80`.
- `arcTo` (Canvas 2D) — universally supported, no floor.

**(b) Tokens vs hardcoded constants.** Corrected below. The drafts leaked three hardcoded
values (`0.16` glow opacity, `0.55` radius factor, `Motion.slow * 6`); all are re-expressed as
named constants with stated rationale, and every animation goes through
`.vault(_, reduceMotion:)`. Black/white in the QR and the camera backdrop are the
**documented camera/QR exemption** (`docs/design-dna-standard.md:114`) and are annotated as
such in code.

**(c) Scannability.** Two changes were rejected on scannability grounds: the 720p preset
(A11) and any non-zero module gap on web (locked by the spec table below). The quiet-zone fix
is a strict improvement; corner-clip math re-verified.

**(d) GPL.** No Telegram source is reproduced. What crosses over is API selection
(`isPreviewing` KVO; disabling the preview connection to hold the last frame; a private serial
session queue) and numeric timings — facts and ideas, not expression. `QRScannerOverlayView`
is already independently written. **Constraint for the implementer: do not open
`/Users/bervion/Downloads/Telegram-iOS-master` while writing these files.** Code sketches
below are written from the API docs.

---

# TRACK A — Camera cold-start blur

## Root difference

Telegram never shows a black frame because it **renders something plausible from frame zero**
and **cross-fades on a real first-frame signal**, while doing **zero** capture work on the main
thread. Vaultify does the opposite on all three axes: it paints black, has no readiness signal,
and runs everything except `startRunning()` on main.

## A. Current state

`Vaultify/Features/ItemEditor/QRScannerView.swift`

| Line | Behaviour | Problem |
|---|---|---|
| `:34` | `view.backgroundColor = .black` | The entire cold-start visual |
| `:38` | `AVCaptureDevice.requestAccess` unconditional | Extra async hop on every open, even when already authorized |
| `:40` | `DispatchQueue.main.async { configureSession() }` | All setup lands on main |
| `:45-48` | `AVCaptureDevice.default` + `AVCaptureDeviceInput(device:)` + `addInput` | 100-400 ms of main-thread time, cold |
| `:50-52` | `AVCaptureMetadataOutput` + `addOutput` | Un-batched: each implicitly begins/commits its own configuration |
| `:56-63` | Preview layer created and inserted **after** configuration | Layer literally does not exist during the present animation |
| `:65` | `startRunning()` off main | The only thing already correct |
| `:68-71` | `playEntryAnimation()` on `viewDidAppear` | Brackets spring in over black, long before the first frame |
| `:73-76` | `session.stopRunning()` synchronously on main | Blocks the dismiss animation |
| `:102-108` | Live preview keeps running for 0.5 s after detection | Live QR is what the app-switcher snapshots |

Callers stack their own black: `TOTPScannerSheet.swift:29` and `QuickViewScannerSheet.swift:25`
both apply `.background(.black)` with `.preferredColorScheme(.dark)`.

Five call sites, all reached through `QRScannerView`:

| Caller | Presentation |
|---|---|
| `Features/Sharing/QuickView/QuickViewScannerSheet.swift:13` | `.sheet` |
| `Features/Settings/PairDeviceSheet.swift:35` | `.sheet` |
| `Features/Onboarding/JoinVaultFlow.swift:613` | `.sheet` |
| `Features/ItemEditor/TOTPScannerSheet.swift:20` | `.platformFullScreenCover` |
| `Features/ItemEditor/CardScannerSheet.swift` | VisionKit, **not** touched by this track |

## B. Target behaviour

1. No AVFoundation work on the main thread except assigning the session to the preview layer.
2. The scanner opens onto a **designed dark surface with an accent glow**, not a black hole.
3. The reticle springs in **at the moment the feed goes live**, on a real signal, not on a timer.
4. The last frame is held and hidden when the app backgrounds or the sheet dismisses.
5. Everything collapses correctly under Reduce Motion / Reduce Transparency.

### CORRECTION 1 — the material does not sample the presenting screen

The draft's Tier A rests on "in a `.sheet` the material samples the dimmed presenting screen,
so this literally is a blurred version of the screen you came from". That is false here, for a
verifiable reason: in both sheet callers the scanner is a ZStack child sitting directly on
`.background(.black)` (`TOTPScannerSheet.swift:29`, `QuickViewScannerSheet.swift:25`). A SwiftUI
`Material` blurs its **immediate backdrop inside the same presentation**, not the presenting
view controller behind a sheet. The result would be a flat dark grey — a blur pass over solid
black, costing GPU time to produce a constant colour.

**Revised design:** the warm-up cover is an opaque, intentional dark surface — the camera-black
base (documented exemption), a soft accent radial glow marking where the reticle lands, and a
slow breathing opacity on the glow that stops dead under Reduce Motion. No material, no
sampling assumption, no per-caller device check, and it looks identical in `.sheet` and
`.platformFullScreenCover`. This also removes the draft's open question 2 entirely.

### CORRECTION 2 — z-order: a SwiftUI cover sits above the reticle

`QRScannerOverlayView` is a **subview of the controller's view**
(`QRScannerView.swift:37`), so any SwiftUI cover placed as a ZStack sibling of the
representable renders **above** the dim layer and the brackets. The draft claims the capture
beat still shows the reticle snapping "over a frozen, blurred frame" — it would not; the cover
would hide it.

**Revised split**, which is both simpler and correct:

- **Capture beat** (QR detected): freeze the preview connection only. The frame holds, the
  reticle snaps onto it, no cover. This is the whole "got it" moment and it must stay visible.
- **Privacy cover** (`willResignActive` / `viewWillDisappear`): full-screen cover **above
  everything**, including the reticle. Hiding the highlighted code is exactly what we want here.
- **Warm-up**: overlay starts at `alpha = 0`, so the cover never sits on top of a half-drawn
  dim layer. The overlay fades in with the reveal.

Three phases, unambiguous: `.warmingUp` → `.previewing` → `.covered`.

## C. Implementation

All of Track A lives in **one existing file** plus two one-line edits, so `tuist generate` adds
no new sources (regenerate anyway before compiling).

### Step A1 — move all session work off main

File: `Vaultify/Features/ItemEditor/QRScannerView.swift`

Ordering rule: **session object + preview layer on main first; configure and start on a private
serial queue; hop back to main only for the connection's rotation angle.**

```swift
/// Lifecycle of the live preview, surfaced to SwiftUI so the warm-up and privacy
/// covers are styled with design tokens and honour the accessibility settings.
enum ScannerPreviewPhase { case warmingUp, previewing, covered }

final class QRScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onFound: ((String) -> Void)?
    var onPhaseChange: ((ScannerPreviewPhase) -> Void)?

    private let session = AVCaptureSession()
    /// Every AVCaptureSession mutation happens here. `AVCaptureDeviceInput(device:)`,
    /// `addInput`, `startRunning` and `stopRunning` each block their caller for
    /// hundreds of milliseconds on a cold camera; on main that lands inside the
    /// sheet's present/dismiss animation and visibly drops frames.
    private let sessionQueue = DispatchQueue(label: "com.bervion.vaultify.scanner.session",
                                             qos: .userInitiated)
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var previewingObservation: NSKeyValueObservation?
    private let overlay = QRScannerOverlayView()
    private var didFind = false
    private var didEnter = false

    private var phase: ScannerPreviewPhase = .warmingUp {
        didSet {
            guard phase != oldValue else { return }
            onPhaseChange?(phase)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Camera surface: literal black is the documented exemption
        // (docs/design-dna-standard.md) and is what the live feed resolves to,
        // so the cover-to-feed swap has no colour step.
        view.backgroundColor = .black

        // Layer exists from frame zero, so there is no "layer appears late" pop.
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.layer.bounds
        view.layer.insertSublayer(preview, at: 0)
        previewLayer = preview
        observePreviewing(preview)

        overlay.frame = view.bounds
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.alpha = 0            // revealed with the first frame, never over black
        view.addSubview(overlay)

        observeAppLifecycle()

        // Already-authorized (every open after the first) skips the TCC round-trip
        // and a full runloop turn.
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            sessionQueue.async { [weak self] in self?.configureAndStart() }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard granted, let self else { return }
                self.sessionQueue.async { self.configureAndStart() }
            }
        default:
            break   // denied/restricted: cover stays; callers still offer photo + manual entry
        }
    }

    /// Runs on `sessionQueue`. One begin/commit pair, so the session is reconfigured once
    /// instead of once per add.
    private func configureAndStart() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return }

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        // Session preset deliberately left at the default. Lowering it shrinks the
        // pixel size of a QR shown on a distant monitor, which is the exact case the
        // detection gate below was widened for.
        guard session.canAddInput(input) else { return }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]
        session.commitConfiguration()   // commit before start; `defer` is the error path only

        session.startRunning()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let connection = self.previewLayer?.connection,
               connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90 // portrait
            }
            self.startRevealWatchdog()
        }
    }
```

> Note on the `defer` + explicit `commitConfiguration()` pairing above: pick one. Cleanest is a
> single `commitConfiguration()` at the end of the happy path with each `guard` doing its own
> commit before `return` — write it whichever way the reviewer prefers, but **it must commit
> exactly once on every exit path**, otherwise the session stays wedged mid-configuration.

Dismissal — replace `:73-76`:

```swift
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cover(animated: true)
        sessionQueue.async { [weak self] in           // never block the dismiss animation
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    deinit { previewingObservation?.invalidate() }
```

### CORRECTION 4 — no `suspend()`/`resume()` around the permission prompt

The draft suspends `sessionQueue` while `requestAccess` is pending and resumes in the callback.
Nothing is enqueued on that queue between those two points, so the pair is a no-op with two
ways to go wrong (an unbalanced `resume()` on an early return traps). Dropped above. YAGNI.

### CORRECTION 5 — do not change the session preset

The draft proposes `.hd1280x720` "starts measurably faster". `QRScannerView.swift:92-98`
documents a prior fix made specifically because users point the phone at a **QR on a computer
monitor**, where the code occupies a small part of the frame. Reducing capture resolution
directly reduces the module pixel count for that case. The stated win is start-up latency,
which Step A1 already solves by moving the work off main. Rejected on scannability grounds.

### Step A2 — first-frame readiness signal

```swift
    private func observePreviewing(_ layer: AVCaptureVideoPreviewLayer) {
        // `isPreviewing` flips when the layer actually has video on screen. The
        // AVCaptureSessionDidStartRunning notification fires earlier, before the
        // first frame renders, so it cannot drive the reveal.
        previewingObservation = layer.observe(\.isPreviewing, options: [.new]) { [weak self] layer, _ in
            guard layer.isPreviewing else { return }
            DispatchQueue.main.async { self?.reveal() }
        }
    }

    /// Delay before the reveal so auto-exposure and white balance settle; without it
    /// the cross-fade lands on a blown-out or near-black first frame.
    private func reveal() {
        guard phase == .warmingUp else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Motion.fast) { [weak self] in
            guard let self, self.phase == .warmingUp else { return }
            self.phase = .previewing
            UIView.animate(withDuration: self.reduceMotion ? 0 : Motion.base) {
                self.overlay.alpha = 1
            }
            if !self.didEnter, !self.reduceMotion {
                self.didEnter = true
                self.overlay.playEntryAnimation()
            }
        }
    }

    private var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }
```

Delete the `viewDidAppear` override at `:68-71` — the brackets now enter with the reveal.

**`isPreviewing` is not documented as KVO-compliant**, so the watchdog is mandatory:

```swift
    /// `isPreviewing` KVO is undocumented by Apple. If it never fires on a session
    /// that is demonstrably running, uncover anyway rather than sitting on the cover.
    private static let revealTimeout: TimeInterval = 2.0   // timeout, not a motion duration
    private func startRevealWatchdog() {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.revealTimeout) { [weak self] in
            guard let self, self.phase == .warmingUp, self.session.isRunning else { return }
            self.reveal()
        }
    }
```

### CORRECTION 6 — `Motion.slow * 6` is token misuse

`Motion.slow` is an **animation duration** (0.32 s). A 1.92 s failure timeout is not motion, and
multiplying a motion token by a magic 6 reads as a design-system value while behaving as a
timeout. Replaced with a named `revealTimeout` constant above. `Motion.fast` (0.14 s) as the
exposure-settle beat is legitimate — that one really is a motion delay.

### Step A3 — freeze and cover

```swift
    /// Hold the last frame without a snapshot: disabling the preview connection stops
    /// delivery and the layer keeps what it last drew.
    private func holdLastFrame() {
        previewLayer?.connection?.isEnabled = false
    }

    /// Cover the held frame. Used on dismissal and on resign-active, so the app-switcher
    /// card is never a readable QR carrying a TOTP seed or a pairing payload.
    private func cover(animated: Bool) {
        guard phase != .covered else { return }
        holdLastFrame()
        phase = .covered
    }

    private func observeAppLifecycle() {
        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.willResignActiveNotification,
                           object: nil, queue: .main) { [weak self] _ in
            // No animation: the system snapshot can be taken before a cross-fade lands.
            guard let self else { return }
            self.cover(animated: false)
        }
        center.addObserver(forName: UIApplication.didBecomeActiveNotification,
                           object: nil, queue: .main) { [weak self] _ in
            guard let self, !self.didFind else { return }
            self.previewLayer?.connection?.isEnabled = true
            self.phase = .warmingUp
            self.sessionQueue.async { [weak self] in
                guard let self, !self.session.isRunning else { return }
                self.session.startRunning()
            }
            DispatchQueue.main.async { self.startRevealWatchdog() }
        }
    }
```

In `metadataOutput(_:didOutput:from:)`, immediately after `didFind = true` (`:102`), call
`holdLastFrame()` **only** — not `cover()`. The reticle then snaps onto a frozen frame and the
existing 0.5 s handback at `:106` plays over it. That is the capture beat.

### CORRECTION 3 — the privacy cover must be un-animated

`willResignActive` is the last reliable hook before the system takes the app-switcher snapshot.
A 0.20 s cross-fade may not have landed by then, leaving a partially transparent cover over a
readable QR in the switcher. The SwiftUI side must therefore apply the `.covered` phase inside a
transaction with animations disabled — see `applyPhase` below.

### Step A4 — SwiftUI wrapper and covers

Rename the existing representable to `QRScannerRepresentable` and make `QRScannerView` a
`View`, so **all five call sites stay untouched**:

```swift
struct QRScannerView: View {
    var onFound: (String) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: ScannerPreviewPhase = .warmingUp

    var body: some View {
        ZStack {
            QRScannerRepresentable(onFound: onFound, onPhaseChange: applyPhase)
            switch phase {
            case .warmingUp: ScannerWarmUpCover()
            case .covered:   ScannerPrivacyCover()
            case .previewing: EmptyView()
            }
        }
        .animation(.vault(Motion.standard, reduceMotion: reduceMotion), value: phase)
    }

    /// `.covered` is applied without animation: it exists to beat the app-switcher
    /// snapshot, and a cross-fade may not have landed by the time it is taken.
    private func applyPhase(_ next: ScannerPreviewPhase) {
        if next == .covered {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { phase = next }
        } else {
            phase = next
        }
    }
}

struct QRScannerRepresentable: UIViewControllerRepresentable {
    var onFound: (String) -> Void
    var onPhaseChange: (ScannerPreviewPhase) -> Void

    func makeUIViewController(context: Context) -> QRScannerController {
        let controller = QRScannerController()
        controller.onFound = onFound
        // Always hop: `phase` changes must never be applied inside a SwiftUI update pass.
        controller.onPhaseChange = { next in DispatchQueue.main.async { onPhaseChange(next) } }
        return controller
    }

    func updateUIViewController(_ controller: QRScannerController, context: Context) {}
}
```

The `DispatchQueue.main.async` hop is not cosmetic: without it a phase change raised during
`makeUIViewController` (or during a layout pass) mutates `@State` inside a view update, which
SwiftUI reports as "Modifying state during view update" and can drop the change.

The covers:

```swift
/// Stand-in for the live feed while `AVCaptureSession` spins up. Camera black is the
/// documented QR/camera exemption (docs/design-dna-standard.md) and matches what the feed
/// resolves to, so the swap has no colour step; the accent glow marks where the reticle
/// will land, so the screen reads as "starting" rather than as a dead black rectangle.
private struct ScannerWarmUpCover: View {
    /// Peak glow opacity — strong enough to read on OLED black at min brightness,
    /// low enough that the first camera frame is not a brightness jump.
    private static let glowOpacity: Double = 0.16
    /// Glow reaches 55% of the short edge, matching the reticle's 66% idle square
    /// (QRScannerOverlayView.idleRect) without touching its brackets.
    private static let glowRadiusRatio: CGFloat = 0.55

    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                RadialGradient(
                    colors: [Color(rgb: env.theme.active.accent, opacity: Self.glowOpacity), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: min(geo.size.width, geo.size.height) * Self.glowRadiusRatio
                )
                .opacity(breathing ? 1 : 0.6)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: Motion.slow * 3).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Starting the camera"))
    }
}

/// Opaque cover over the held last frame. Keeps a live QR out of the app-switcher
/// snapshot and off screen during dismissal.
private struct ScannerPrivacyCover: View {
    var body: some View {
        Color.black
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}
```

Note the privacy cover is **opaque black, not a material**: the entire point is that nothing of
the frame survives into the snapshot, and a translucent material by definition leaks the frame
it is sampling. It is also the one path that must work identically under Reduce Transparency.

Verify `env.theme.active.accent` is the correct token name against
`VaultifyCore/Theme/AppTheme.swift` before writing; if the accent lives under a different key,
resolve it through `theme.color(.accent)` instead. Do not hardcode a hue.

### Step A5 — localization and drive-by

1. `Vaultify/Localizable.xcstrings` — add (verified absent today):
   - key `Starting the camera` · EN `Starting the camera` · VI `Đang khởi động camera`
   Consistent with existing entries that leave "camera" untranslated
   (e.g. `Hướng camera vào mã QR 2FA`). No "!", no em dash, no middle dot.
2. `Vaultify/Features/Sharing/QuickView/QuickViewScannerSheet.swift:20` —
   `.font(.subheadline)` → `.vaultType(.subhead)`.

## D. Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| `isPreviewing` KVO does not fire (undocumented compliance) | Low | `revealTimeout` watchdog, mandatory |
| Commit path leaves the session mid-configuration on an error return | Medium if written carelessly | Exactly one `commitConfiguration()` per exit path; review this specifically |
| `@State` mutation during view update | Medium | `DispatchQueue.main.async` hop in `makeUIViewController` |
| Glow reads as a bug ("why is it purple") on some accents | Low | 7-accent sweep in the verification matrix |
| Privacy cover misses the snapshot | Low | `willResignActive` + `disablesAnimations` transaction; verify in the switcher |
| `didBecomeActive` restart races a session still stopping | Low | `guard !session.isRunning` inside the `sessionQueue.async` block, so the check runs serialized with stop |
| Phase 4 (in-memory blurred-frame cache) | — | **Deferred.** Steps A1-A4 remove the reported problem. Do not build it speculatively. |

**Persistence decision (was draft §0):** do **not** persist camera stills. These scanners point
at QR codes carrying TOTP seeds, recovery keys and pairing payloads; writing even a heavily
blurred JPEG of that to the container is data-at-rest we do not need and an App Privacy answer
we do not want. The revised warm-up cover needs no cache at all, which also removes the draft's
Tier B.

## E. Verification

```bash
cd /Users/bervion/Developer/Projects/mobile/ios/Vaultify
tuist generate --no-open
make check
```

No new files, so the source globs do not change — regenerate anyway.

Manual matrix (physical device; the Simulator has no camera and will sit on the warm-up cover
by design, which is the correct degraded state since callers offer photo import and manual paste):

- Light and dark, all 7 accents: glow visible, never washed out, never garish.
- Reduce Motion ON: no breathing, no bracket spring, cover swap instant.
- Reduce Transparency ON: unchanged (both covers are already opaque) — confirm no regression.
- Increased contrast ON: reticle and caption legible over the cover.
- All five entry points: Quick View scan, Pair New Device, Join Vault setup code, 2FA scan,
  and Card scan (VisionKit — confirm no regression, it is untouched).
- Present/dismiss 10× consecutively: no black frame on open, no stutter on either animation.
- Instruments Time Profiler: zero `AVCaptureDeviceInput` / `startRunning` / `stopRunning`
  frames on the main thread; present and dismiss hold 120 Hz on ProMotion.
- Background mid-scan: switcher card is solid black, not a readable QR. Foreground again:
  preview resumes and reveals.
- VoiceOver: "Starting the camera" announced once; the cover leaves the tree after reveal.

## F. Rollback

Everything is inside `QRScannerView.swift` plus two one-line edits. Step A1 (threading) is
independently valuable and should ship regardless of how the covers land. If the glow reads
badly on device, `ScannerWarmUpCover` reduces to `Color.black` without touching A1-A3.

---

# TRACK B — QR rendering parity

## Root difference

The app fuses modules in **both** axes (gap 0, per-corner rounding) and draws finders as three
**filled** rects; the web insets every module by 8% and merges **horizontally only**, so every
row becomes a separate strip of pills — that is the "stripey / ugly" the user is reacting to.
The app is simultaneously the prettier and the more scannable of the two. The single thing the
app gets wrong is the quiet zone.

**So: the app is canonical for geometry, the web is canonical for the quiet zone.**

## A. Current state

**Surface 1 — iOS app.** `Vaultify/Features/Components/QRCodeView.swift`
- `:100-122` `makeMatrix` — CoreImage `qrCodeGenerator`, correctionLevel `"M"` (`:103`),
  fresh `CIContext()` **per call** (`:107`), quiet zone trimmed off by `trim` (`:125-137`).
- `:13-16` matrix built eagerly in `init`, so it re-runs on every parent body evaluation.
- `:49` `radius = cell * 0.5`; `:54-58` per-corner rounding, gap 0.
- `:71-78` finders as three filled rounded rects, radii `cell * 2.2 / 1.6 / 1.0`.
- `:61,73,77` `.black` on `:25` `.white` tile, `Radius.lg` (= 20).
- `:24` `.padding(Space.s4)` (= 16 pt) — **fixed points, not module-relative**.

Call sites (all verified):
- `Features/Onboarding/JoinVaultFlow.swift:286` — `.frame(maxWidth: 260)`, payload
  `loox-pair/1/<id>/<pubkey>` ≈ 78 bytes → v5, 37 modules → cell ≈ 6.16 pt →
  **quiet ≈ 2.6 modules. Under the ISO 4-module minimum.**
- `Features/Sharing/ShareAccessSheet.swift:744` — `.frame(width: 200, height: 200)`,
  invite URL → v4-v5, ~35 modules → cell ≈ 4.8 pt → **quiet ≈ 3.3 modules. Under spec.**
- `Features/EmergencyKit/EmergencyKitPDFPage.swift:93` — 128 pt, v3, 29 modules →
  cell ≈ 3.31 pt → quiet ≈ 4.8 modules. OK.

The app does **not** render the Quick View QR — `QuickViewQRCode.swift` is a *parser* for the
payload the app scans off the web page. There has never been an app-side reference rendering of
surface 2, which is how the two drifted.

**Surface 2 — Quick View /open.**
`workers/loox-quick-view/src/open-page-script-render.ts`, `drawQr` at `:32-81`.
- `:64,76,79` — `ctx.roundRect`, unguarded. Safari 16.4+ / Chrome 99+.
- `:51` `gap = modulePx * 0.08` subtracted on all four edges.
- `:52-67` run-merge loop walks **horizontally only**.
- `:70-81` finders **stroked** at `lineWidth = modulePx * 0.95` on a 6×6 path at +0.5 offset,
  radius `1.8 * modulePx`, plus a filled 3×3 centre.
- `:41` `ink = '#101114'`, `:39` paper `#ffffff`, `:36` quiet 4 modules.
- Encoder: `workers/loox-quick-view/src/qr-encoder.ts` — byte mode, **EC-M only** (single `ec`
  count per version in `VERSION_TABLE`; `formatInfoBits` comments "ECC level M = 00"),
  **mask fixed at 0** (`:6-9` header; `encodeByteMode` calls `buildMatrix(version, 0, …)`).

**The crash path, verified end to end:** `drawQr` has no `try`; its only caller `renderWaiting`
(`:96-102`) has no `try`; `renderWaiting` is called from `bootstrap()` at
`open-page-script-flow.ts:80`, whose `catch` at `:81-83` does `renderTerminal('error')`. So on
an engine without `roundRect`:

```
roundRect undefined → drawQr throws → renderWaiting throws → bootstrap catch → renderTerminal('error')
```

with `POST /v1/quick-view/sessions` **already succeeded server-side**. `subscribeEvents()`
(`:81`) never runs, so the session is orphaned; the human code and SAS words — a complete manual
fallback that needs no QR — are never shown; each retry burns another session against the rate
limiter.

**Surface 3 — marketing landing.** `src/lib/brand-canvas.ts` `drawQrMock` at `:747-800`,
via `src/components/canvas/qr-mock-canvas.tsx`, rendered at `src/app/[locale]/page.tsx:348`.
- Verbatim copy of the /open geometry: `:779` `g = c * 0.08`, `:788` `lineWidth = c * 0.95`,
  ink `#101114`.
- `:758` `pad = S * 0.1`, `:759` `c = (S - pad*2)/21` → **2.625-module quiet zone**, n fixed at 21.
- `:754` its own canvas-painted tile, `roundRect(0,0,S,S,S*0.11)`.
- Not a real QR: seeded LCG at 45% density, `aria-hidden="true"`. **Keep it that way** — a
  scannable marketing QR resolving to nothing is a worse outcome.
- `use-brand-canvas.ts` runs an unconditional `requestAnimationFrame` loop calling the draw
  callback every frame; `drawQrMock` is time-invariant (fixed seed `1234567`), so the homepage
  repaints an identical bitmap ~60×/s forever. Its `ResizeObserver` already redraws on size
  change, so the loop contributes nothing.

### CORRECTION 7 — "already deployed" is unverified

`git status` in the web repo shows `open-page-script-render.ts` as **modified-uncommitted** and
`src/lib/brand-canvas.ts` as **untracked**. That establishes the code is not committed; it does
**not** establish that it is live. Before treating this as a production incident, confirm:

```bash
cd /Users/bervion/Developer/Projects/frontend/looxpassword
npx wrangler deployments list --name loox-quick-view
```

The fix is worth doing either way (`arcTo` costs nothing). Only the urgency of the redeploy
depends on the answer.

### CORRECTION 8 — `roundRect` is also used on the landing

The draft treats `roundRect` as a worker-only problem. `brand-canvas.ts` calls it at `:754`
(tile), `:780` (modules), `:793` and `:797` (finders). It sits inside the rAF loop, so on an
affected engine it throws every frame. The `arcTo` helper must land in **both** files.

## B. Target behaviour — the shared spec

**Loox QR v1.** Reproduce this table verbatim in every implementation and in the spec doc.

### Encoding

| Parameter | Value | Notes |
|---|---|---|
| `MODE` | byte | |
| `EC_LEVEL` | `M` | All surfaces |
| `MASK` | 0 (web) / encoder-selected (CoreImage) | Web encoder has no penalty-based selection |
| `LOGO` | **none** | A centre logo needs EC-H; `qr-encoder.ts` cannot produce it |

### Canvas

| Parameter | Value |
|---|---|
| `QUIET` | **4 modules**, module-relative on all four sides |
| `cell` | `side / (n + 2 * QUIET)` |
| `PAPER` | `#FFFFFF` |
| `INK` | `#000000` |

### Data modules

| Parameter | Value |
|---|---|
| `GAP` | **0** — modules touch. Never inset. |
| `CORNER_R` | `0.50 * cell` |
| corner rule | round corner Q iff **both** orthogonal neighbours forming Q are light |
| `tl` | `!dark(r-1,c) && !dark(r,c-1)` |
| `tr` | `!dark(r-1,c) && !dark(r,c+1)` |
| `br` | `!dark(r+1,c) && !dark(r,c+1)` |
| `bl` | `!dark(r+1,c) && !dark(r,c-1)` |
| consequence | isolated module = circle Ø 1.0 cell; runs fuse in **both** axes |
| skip | any module inside a 7×7 finder box (drawn separately) |

### Finder patterns — three **filled** rounded rects, no stroke

Positions (row, col): `(0,0)`, `(0, n-7)`, `(n-7, 0)`.

| Layer | Colour | Size | Inset | Radius |
|---|---|---|---|---|
| 1 | `INK` | 7×7 cells | 0 | `2.20 * cell` |
| 2 | `PAPER` | 5×5 cells | 1 cell | `1.60 * cell` |
| 3 | `INK` | 3×3 cells | 2 cells | `1.00 * cell` |

Ring thickness is exactly `1.00 cell`; all edges land on exact module boundaries, giving a
textbook `1:1:3:1:1` scanline ratio.

### Tile — container concern, **outside** the spec, may differ per surface

| Surface | Tile |
|---|---|
| app | `RoundedRectangle(cornerRadius: Radius.lg)` filled `.white` |
| /open | `.qr-card` div, 20 px padding, 34 px radius |
| landing | canvas-painted `roundRect`, radius `0.11 * S` |

### Standing constraints — do not relax without redoing the maths

1. **`GAP` must stay 0.** `qr-encoder.ts:6-9` fixes the mask at 0 with no penalty-based
   selection. Adaptive binarizers (jsQR and ZXing both threshold over 8×8 blocks) estimate a
   local black point from block means; a mask-0 diagonal artefact plus thinned modules pushes
   light-ish regions toward all-white. The ink budget cannot be spent on insets.
2. **No centre logo at EC-M.** `VERSION_TABLE` carries one `ec` codeword count per version and
   `formatInfoBits` hardcodes level M. A logo requires EC-H, i.e. new EC/block tables first.
3. **Ink/paper stay literal black and white** on every surface. On iOS this is the documented
   camera/QR exemption (`docs/design-dna-standard.md:114`) and must be annotated in the code
   comment so design review does not re-flag it.

### Why the app is canonical on geometry

Zero gap keeps every module's centre pixel solidly ink — that is the pixel decoders sample after
grid alignment. Both-axis fusion gives the binarizer large connected components instead of
per-row dashes separated by a `2 × 0.08 = 0.16`-module white seam. Filled finder rects give an
exact 1.00-module ring with no `lineWidth`-vs-radius interaction. Ink coverage for an isolated
module rises from ~55% (web, Ø 0.84 cell) to ~78% (app, Ø 1.0 cell).

## C. Implementation

### Phase B1 — /open page (highest priority: functional, not cosmetic)

File: `workers/loox-quick-view/src/open-page-script-render.ts`

**B1a.** Add two path helpers above `drawQr`:

```js
// Rounded-rect path via arcTo. Deliberately NOT ctx.roundRect: that is
// Safari 16.4+ / Chrome 99+, and on older engines calling it THROWS. The throw
// propagated out of drawQr -> renderWaiting -> bootstrap's catch and terminated an
// already-created session, hiding the human code and SAS words that are a complete
// manual fallback. arcTo has no support floor.
function rrPath(ctx, x, y, w, h, r) {
  var rr = Math.min(r, w / 2, h / 2);
  ctx.beginPath();
  ctx.moveTo(x + rr, y);
  ctx.arcTo(x + w, y,     x + w, y + h, rr);
  ctx.arcTo(x + w, y + h, x,     y + h, rr);
  ctx.arcTo(x,     y + h, x,     y,     rr);
  ctx.arcTo(x,     y,     x + w, y,     rr);
  ctx.closePath();
}

// One data module, corners rounded individually. Mirrors the app's
// QRCodeView.addRoundedCell — keep the two in sync, see docs/qr-visual-spec.md.
function cellPath(ctx, x, y, s, r, tl, tr, br, bl) {
  var x1 = x + s, y1 = y + s;
  ctx.beginPath();
  ctx.moveTo(x + (tl ? r : 0), y);
  ctx.lineTo(x1 - (tr ? r : 0), y);
  if (tr) ctx.quadraticCurveTo(x1, y, x1, y + r);
  ctx.lineTo(x1, y1 - (br ? r : 0));
  if (br) ctx.quadraticCurveTo(x1, y1, x1 - r, y1);
  ctx.lineTo(x + (bl ? r : 0), y1);
  if (bl) ctx.quadraticCurveTo(x, y1, x, y1 - r);
  ctx.lineTo(x, y + (tl ? r : 0));
  if (tl) ctx.quadraticCurveTo(x, y, x + r, y);
  ctx.closePath();
}
```

**B1b.** Replace the body of `drawQr` (`:32-81`) with the spec:

```js
function drawQr(canvas, qr) {
  var QUIET = 4, INK = '#000000', PAPER = '#ffffff';
  var n = qr.size;
  var m = Math.max(4, Math.floor(480 / (n + QUIET * 2)));
  var side = (n + QUIET * 2) * m;
  canvas.width = side; canvas.height = side;
  var ctx = canvas.getContext('2d');
  ctx.fillStyle = PAPER; ctx.fillRect(0, 0, side, side);

  var finders = [[0, 0], [0, n - 7], [n - 7, 0]];   // [row, col]
  function inFinder(r, c) {
    for (var k = 0; k < 3; k++) {
      var f = finders[k];
      if (r >= f[0] && r < f[0] + 7 && c >= f[1] && c < f[1] + 7) return true;
    }
    return false;
  }
  function dark(r, c) { return r >= 0 && r < n && c >= 0 && c < n && qr.modules[r][c]; }

  var R = m * 0.5;
  ctx.fillStyle = INK;
  for (var r = 0; r < n; r++) {
    for (var c = 0; c < n; c++) {
      if (!qr.modules[r][c] || inFinder(r, c)) continue;
      cellPath(ctx, (c + QUIET) * m, (r + QUIET) * m, m, R,
        !dark(r-1,c) && !dark(r,c-1), !dark(r-1,c) && !dark(r,c+1),
        !dark(r+1,c) && !dark(r,c+1), !dark(r+1,c) && !dark(r,c-1));
      ctx.fill();
    }
  }
  for (var k2 = 0; k2 < 3; k2++) {
    var X = (finders[k2][1] + QUIET) * m, Y = (finders[k2][0] + QUIET) * m;
    ctx.fillStyle = INK;   rrPath(ctx, X,       Y,       7*m, 7*m, 2.2*m); ctx.fill();
    ctx.fillStyle = PAPER; rrPath(ctx, X + m,   Y + m,   5*m, 5*m, 1.6*m); ctx.fill();
    ctx.fillStyle = INK;   rrPath(ctx, X + 2*m, Y + 2*m, 3*m, 3*m, 1.0*m); ctx.fill();
  }
}
```

This also normalises the finder tuples to `[row, col]`. The current code stores `[col, row]` and
calls `inFinder(c, r)` — self-consistent, and verified correct today, but a standing trap.

**B1c.** Make the QR non-fatal in `renderWaiting` (`:96-102`). The human code and SAS words are
a complete manual path; a canvas problem must never terminate a live session:

```js
  try { drawQr($('qr-canvas'), qr); }
  catch (e) { var qc = $('qr-canvas'); if (qc) qc.classList.add('hidden'); }
```

**B1d.** Leave `open-page.ts` CSS alone. `.qr-card` padding 20 px is extra paper on top of the
4-module quiet zone — harmless and visually good.

### Phase B2 — iOS app

File: `Vaultify/Features/Components/QRCodeView.swift`

**B2a.** Hoist the spec constants so both repos diff against the same numbers:

```swift
    // Loox QR v1 — see docs/qr-visual-spec.md. Keep in sync with the web renderers
    // (loox-quick-view open-page-script-render.ts, src/lib/brand-canvas.ts).
    // Ink/paper are literal black/white by design: readers need dark-on-light
    // regardless of theme. Documented camera/QR exemption, docs/design-dna-standard.md.
    private static let quiet = 4
    private static let cornerRatio: CGFloat = 0.5
    private static let finderOuterR: CGFloat = 2.2
    private static let finderInnerR: CGFloat = 1.6
    private static let finderCoreR:  CGFloat = 1.0
```

**B2b.** Move the quiet zone inside the `Canvas`. Delete `:24` `.padding(Space.s4)`; keep the
`.white` `RoundedRectangle(cornerRadius: Radius.lg)` background. In `draw(_:in:size:)` replace
`:31-35`:

```swift
        let n = matrix.count
        let units = CGFloat(n + 2 * Self.quiet)
        let side = min(size.width, size.height)
        let cell = side / units
        let ox = (size.width  - side) / 2 + CGFloat(Self.quiet) * cell
        let oy = (size.height - side) / 2 + CGFloat(Self.quiet) * cell
```

Everything downstream (`ox + CGFloat(c) * cell`, the finder rects) is unchanged. Use
`cell * Self.cornerRatio` at `:49` and the finder constants at `:72-77`.

Resulting quiet zones, recomputed: JoinVaultFlow 260 pt / 37 modules → cell 5.78 pt, quiet
23.1 pt (4.0 modules); ShareAccessSheet 200 pt / 35 → cell 4.65, quiet 18.6 pt; Emergency Kit
128 pt / 29 → cell 3.46, quiet 13.8 pt. Outer footprint at each call site is unchanged, because
the 16 pt padding was already inside the declared frame.

**Corner-clip check passes.** Worst case is JoinVaultFlow: 23.1 pt of paper between the symbol
and the tile edge, while a `Radius.lg` = 20 corner cuts only `20 * (√2 − 1) = 8.3 pt` along the
diagonal. No module is clipped.

**B2c.** Share the `CIContext` and memoize. `CIContext()` is documented as expensive to create
and `:107` builds a fresh one on every `init`, which runs on every parent body evaluation —
`JoinVaultFlow.swift:286` sits in a view that re-renders on pairing-poll state changes:

```swift
        private static let ciContext = CIContext()
        private static var cache: (payload: String, matrix: [[Bool]]?)?

        init(payload: String) {
            self.payload = payload
            if let cached = Self.cache, cached.payload == payload {
                self.matrix = cached.matrix
            } else {
                let generated = Self.makeMatrix(payload)
                Self.cache = (payload, generated)
                self.matrix = generated
            }
        }
```

and `:107` → `Self.ciContext.createCGImage(output, from: output.extent)`.

Both statics are MainActor-isolated under the project default, which is correct: `QRCodeView` is
a SwiftUI `View` and can only be constructed on the main actor. If the memo adds friction in
review, ship the `ciContext` hoist alone — it is the larger and completely risk-free half.

**B2d.** Leave `.black` / `.white` as they are; they already match the spec. Do **not** introduce
a theme role — that is the documented exemption.

**B2e.** No `Localizable.xcstrings` work: this track adds no user-facing text.

### Phase B3 — marketing landing mock

File: `src/lib/brand-canvas.ts`, `drawQrMock` (`:747`)

**B3a.** Module-relative quiet zone, replacing `:758-759`:

```ts
  const QUIET = 4, n = 21;
  const c = S / (n + QUIET * 2);
  const pad = QUIET * c;
```

**B3b.** Swap the drawing loop for the same zero-gap per-corner-rounded cells and the same
three-filled-rects finder as B1b, with `INK = '#000000'`, `R = 0.5 * c`, radii 2.2 / 1.6 / 1.0.
Delete `:779` `const g = c * 0.08` and the `:787-798` stroked-finder block. Port `rrPath` /
`cellPath` here too (**CORRECTION 8** — `roundRect` is used at `:754`, `:780`, `:793`, `:797`).

**B3c.** Keep it a **mock**: retain the seeded LCG matrix and `aria-hidden="true"`. Do not make
it decodable. Keep the `inF` 9×9 exclusion so the separator ring reads clean.

**B3d.** Keep the canvas-painted white tile (`roundRect` → `rrPath`, radius `S * 0.11`) — that is
the container layer, out of spec scope.

**Open decision:** module count. 21 keeps the mock chunky and legible at 150 CSS px; 29 matches
the real v3 payload users actually see. One-constant change either way. Recommendation: **29**,
for honesty — the landing is the promise the /open page has to keep.

File: `src/components/canvas/qr-mock-canvas.tsx`

**B3e.** Stop the 60 fps repaint of a static image. `useBrandCanvas`'s `ResizeObserver` already
redraws on size change, so an early return is sufficient and needs no hook change:

```tsx
  const lastW = useRef(0);
  const {ref} = useBrandCanvas((cv) => {
    if (cv.width === lastW.current) return;   // drawQrMock is time-invariant
    lastW.current = cv.width;
    drawQrMock(cv);
  });
```

### Phase B4 — lock it down with tests

File: `workers/loox-quick-view/scripts/test-qr-decode.ts`

The harness already has jsQR, a reference `qrcode` encoder and a payload list (`:33-38`). Its
`toImage` (`:21-31`) rasterizes **solid squares**, so it validates the encoder and says nothing
about `drawQr`. Every "still scannable" claim in the render comments is currently unverified.

**B4a.** Add a styled rasterizer beside `toImage` that reproduces the B1 geometry analytically
(no canvas dependency): supersample each module 8×8, mark a subpixel as ink if it falls inside
the rounded-cell region or a finder ring, threshold to 1-bit, and run the **same** jsQR
assertion over the **same** payload list. This is the test that actually answers "is the pretty
version scannable".

**B4b.** Add a degradation case: rasterize styled, then downsample to ~4 device px per module
(real on-screen density at 72vw on a 320 pt phone is ~6.2 CSS px/module) and assert jsQR still
decodes. This is the regression guard against anyone re-introducing a gap.

**B4c.** Add a no-`roundRect` test: evaluate `RENDER_JS_SOURCE` against a stub 2D context that
records path ops and has **no** `roundRect` property, call `drawQr`, assert it does not throw and
that it emitted the expected op counts. This locks B1a permanently and is the cheapest test here.

**B4d.** Add a constants-parity assertion: `QUIET = 4`, `0.5`, `2.2`, `1.6`, `1.0`, `'#000000'`
must appear in **both** `open-page-script-render.ts` and `src/lib/brand-canvas.ts`. Crude, but
the pragmatic DRY substitute — the worker inlines its script as a raw JS string while the
landing is bundled TS, so a genuinely shared module needs either `new Function` in the browser
(blocked by CSP) or a build step. Not worth it for ~40 lines.

File: `VaultifySnapshotTests/`

**B4e.** Add `QRCodeSnapshotTests.swift`. `swift-snapshot-testing` is already wired
(`VaultifySnapshotTests/LockControlSnapshotTests.swift`, target at `Project.swift:303`), and
`QRCodeView` needs no `AppEnvironment`, so the test is a few lines:

```swift
assertSnapshot(of: QRCodeView(payload: fixture).frame(width: 260, height: 260),
               as: .image(layout: .fixed(width: 260, height: 260)), named: "join-260")
```

Cover all three shipping sizes (128 / 200 / 260) with fixed payloads so the geometry cannot
drift silently. **This is a new file → run `tuist generate` before compiling.**

### Phase B5 — document and deploy

**B5a.** New doc `docs/qr-visual-spec.md` containing the parameter tables above verbatim, the
three implementing files by absolute path across both repos, and the three standing constraints.
Cross-link it from `docs/design-guidelines.md` next to the existing camera/QR exemption.

**B5b.** Commit and deploy the worker. Confirm the live state first (**CORRECTION 7**) with
`npx wrangler deployments list --name loox-quick-view`. If the current `drawQr` is live, B1 is a
hotfix and ships before everything else.

**Order:** B1 → B4c → confirm/deploy, then B2, B3, B4a/B4b/B4d/B4e, B5.

## D. Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Styled geometry is less scannable than squares | Low | B4a/B4b decode tests gate the change; the spec strictly *increases* ink vs today's web |
| Quiet-zone change shrinks the symbol enough to hurt Emergency Kit print scans | Low | Symbol drops 128→100 pt at v3 but gains a compliant margin; scan the printed PDF |
| App memo cache returns a stale matrix | Very low | Cache key is the full payload string; single entry; MainActor-isolated |
| Landing mock at 29 modules looks noisy at 150 px | Medium | Visual check; the constant is trivially reversible |
| `arcTo` corner rendering differs subtly from `roundRect` | Very low | Both are circular arcs; B4a compares decode, not pixels |
| Someone re-introduces a gap "for looks" | Medium | B4b degradation test + constraint 1 written into the code comment and the spec doc |

## E. Verification

```bash
# iOS
cd /Users/bervion/Developer/Projects/mobile/ios/Vaultify
tuist generate --no-open
make check
```

Then visually check ShareAccessSheet, JoinVaultFlow and the Emergency Kit PDF in **light and
dark**, and scan each with the stock Camera app — dark mode is where the sub-spec quiet zone
actually bit, because the white tile abutted a dark themed background.

```bash
# Web
cd /Users/bervion/Developer/Projects/frontend/looxpassword
npx tsx workers/loox-quick-view/scripts/test-qr-decode.ts
```

Then load `/open` on a real iOS 16.3 device (or a WebKit build with `roundRect` deleted) and
confirm the waiting view renders with code, SAS words **and** QR. Confirm the landing mock
repaints once, not per frame (DevTools Performance: no sustained rAF work on an idle homepage).

---

## Unresolved questions

1. **Track A** — is the app-switcher privacy cover wanted on the *cancel* path too, or only on
   successful capture and backgrounding? The plan covers all three; cancel is the least visible.
2. **Track A** — accent glow opacity `0.16`: needs a device check across all 7 accents on OLED
   at minimum brightness. It is one constant.
3. **Track B** — is the current `drawQr` actually deployed? Blocks the severity call
   (**CORRECTION 7**). Confirm with `wrangler deployments list`.
4. **Track B** — what is the supported browser floor for `/open`? If iOS 16.0-16.3 is genuinely
   out of support, B1 is still worth doing (`arcTo` costs nothing) but the redeploy is routine
   rather than urgent.
5. **Track B** — landing mock: 21 modules (chunky at 150 px) or 29 (matches the real payload)?
   Recommendation is 29.
6. **Track B** — `src/lib/brand-canvas.ts` is untracked. Is it intended to be committed as part
   of this work, or is it a scratch file?

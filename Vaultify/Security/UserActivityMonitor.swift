import SwiftUI

/// Refreshes the foreground inactivity auto-lock baseline on ANY user touch (tap, scroll,
/// drag, key entry) anywhere in the unlocked app — not just tab switches.
///
/// Rationale: the idle timer locks when `now - lastActivity` crosses the auto-lock window.
/// Previously only a tab switch refreshed `lastActivity`, so reading, scrolling, or editing
/// a single screen never counted as activity and the vault locked mid-use ~5 min after
/// unlock. This installs one passthrough gesture recognizer on the host window that observes
/// touches without consuming them, so buttons, lists, and gestures are unaffected.
///
/// The recognizer's lifetime is tied to the SHELL, not to the probe's window membership:
/// the compact shell pushes details onto a UIKit `UINavigationController` (`AppNavigator`),
/// and UIKit removes the tab root's view — this probe included — from the window once a
/// push settles. Touches on pushed screens (Profile, Settings, a paywall sheet above them)
/// still reach the window's recognizers, so the observer keeps working there — but only if
/// it stays attached while the probe is off-window.
///
/// iOS only. On macOS (native slice, no UIKit) the modifier is a no-op — the sidebar and
/// `MacRootView` already register activity on their interactions.
extension View {
    /// Reset the auto-lock idle timer on every user touch inside this view's window.
    func userActivityMonitor(_ onActivity: @escaping () -> Void) -> some View {
        #if canImport(UIKit)
        background(UserActivityMonitor(onActivity: onActivity).allowsHitTesting(false))
        #else
        self
        #endif
    }
}

#if canImport(UIKit)
import UIKit

private struct UserActivityMonitor: UIViewRepresentable {
    let onActivity: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onActivity: onActivity) }

    func makeUIView(context: Context) -> UIView {
        let probe = ProbeView()
        probe.isUserInteractionEnabled = false
        probe.onWindowChange = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        return probe
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onActivity = onActivity
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onActivity: () -> Void
        private weak var recognizer: ActivityGestureRecognizer?

        init(onActivity: @escaping () -> Void) {
            self.onActivity = onActivity
            super.init()
            // Keyboard taps land in a separate system window, so the window gesture recognizer
            // never sees typing. Observe the text-change notifications instead — SwiftUI's
            // TextField/SecureField are UITextField-backed and TextEditor is UITextView-backed,
            // so every keystroke anywhere in the app refreshes the idle baseline.
            let center = NotificationCenter.default
            for name in [UITextField.textDidChangeNotification, UITextView.textDidChangeNotification] {
                center.addObserver(self, selector: #selector(textDidChange), name: name, object: nil)
            }
        }

        deinit { NotificationCenter.default.removeObserver(self) }

        @objc private func textDidChange() { onActivity() }

        /// Park the observer on `window`. A nil window (probe left the hierarchy) deliberately
        /// KEEPS the recognizer attached: a `UINavigationController` push or a full-screen
        /// cover removes the presenting shell's view — probe included — from the window, and
        /// detaching here would stop touch tracking exactly while the user is on the pushed
        /// screen, so the idle timer would lock the vault mid-use. The recognizer moves only
        /// when the probe surfaces in a genuinely different window, and is removed only by
        /// `detach()` when the shell is dismantled (lock/unlock recreates it — that removal
        /// is what avoids leaking one recognizer per unlock onto the same window).
        func attach(to window: UIWindow?) {
            guard let window, recognizer?.view !== window else { return }
            detach()
            let gr = ActivityGestureRecognizer()
            gr.onTouch = { [weak self] in self?.onActivity() }
            gr.delegate = self
            gr.cancelsTouchesInView = false
            gr.delaysTouchesBegan = false
            gr.delaysTouchesEnded = false
            window.addGestureRecognizer(gr)
            recognizer = gr
        }

        /// Remove the observer from whichever window holds it (shell teardown).
        func detach() {
            if let existing = recognizer {
                existing.view?.removeGestureRecognizer(existing)
                recognizer = nil
            }
        }

        // Pure observer — never block another recognizer from firing.
        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}

/// Fires `onTouch` at the start of every touch sequence, then fails immediately so the touch
/// flows untouched to the real views (never recognized, never cancelled).
private final class ActivityGestureRecognizer: UIGestureRecognizer {
    var onTouch: (() -> Void)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        onTouch?()
        state = .failed
    }
}

/// Reports its host window to the coordinator as the SwiftUI view attaches/detaches.
private final class ProbeView: UIView {
    var onWindowChange: ((UIWindow?) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onWindowChange?(window)
    }
}
#endif

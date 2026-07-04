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
        coordinator.attach(to: nil)
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

        /// Move the observer to `window` (or detach when nil). Lock/unlock recreates the shell,
        /// so detaching the previous recognizer avoids leaking one per unlock onto the same window.
        func attach(to window: UIWindow?) {
            if let existing = recognizer {
                existing.view?.removeGestureRecognizer(existing)
                recognizer = nil
            }
            guard let window else { return }
            let gr = ActivityGestureRecognizer()
            gr.onTouch = { [weak self] in self?.onActivity() }
            gr.delegate = self
            gr.cancelsTouchesInView = false
            gr.delaysTouchesBegan = false
            gr.delaysTouchesEnded = false
            window.addGestureRecognizer(gr)
            recognizer = gr
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

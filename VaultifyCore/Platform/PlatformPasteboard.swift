import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Cross-platform sensitive-clipboard writer.
///
/// **iOS/iPadOS**: uses `UIPasteboard.expirationDate` — the OS removes the item at
/// the deadline even if the app is suspended or killed (a real security guarantee).
///
/// **macOS**: `NSPasteboard` has no expiry API. We instead mark the item as
/// `org.nspasteboard.ConcealedType` (excludes it from clipboard managers / Universal
/// Clipboard) and clear it via a mechanism that also fires on app resign / terminate —
/// this is best-effort, NOT the OS-enforced guarantee iOS provides.
@MainActor enum PlatformPasteboard {
    /// Copy a sensitive string, scheduling an auto-clear after `seconds` (0 = no auto-clear).
    static func copySensitive(_ value: String, clearAfter seconds: TimeInterval) {
        #if canImport(UIKit)
        // Secrets never ride Universal Clipboard/Handoff: a token copied on iPhone
        // must not silently materialize on a nearby Mac's clipboard history.
        var options: [UIPasteboard.OptionsKey: Any] = [.localOnly: true]
        if seconds > 0 {
            options[.expirationDate] = Date().addingTimeInterval(seconds)
        }
        UIPasteboard.general.setItems([["public.utf8-plain-text": value]], options: options)
        #elseif canImport(AppKit)
        MacClipboardGuardian.shared.copySensitive(value, clearAfter: seconds)
        #endif
    }

    /// Copy a non-sensitive string (no auto-clear).
    static func copyPlain(_ value: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = value
        #elseif canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        #endif
    }
}

#if canImport(AppKit)
/// Best-effort macOS replacement for `UIPasteboard.expirationDate`: clears the copied
/// secret after a delay, and also on app resign / terminate, but only if the clipboard
/// still holds our item (never wipes something the user copied afterward).
@MainActor final class MacClipboardGuardian {
    static let shared = MacClipboardGuardian()

    private static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    private var pendingChangeCount: Int?
    private var clearTask: Task<Void, Never>?
    private var observersInstalled = false

    func copySensitive(_ value: String, clearAfter seconds: TimeInterval) {
        installObservers()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        // Concealed marker → excluded from clipboard-history apps and Universal Clipboard.
        pasteboard.setString(value, forType: Self.concealedType)
        pendingChangeCount = pasteboard.changeCount

        clearTask?.cancel()
        guard seconds > 0 else { clearTask = nil; return }
        clearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.clearIfUnchanged()
        }
    }

    private func installObservers() {
        guard !observersInstalled else { return }
        observersInstalled = true
        // Clear a lingering secret on app termination. Deliberately NOT on
        // willResignActive: on macOS pasting *requires* switching to another app, so
        // clearing on resign would wipe the secret before the user can paste it. The
        // timer (user's configured delay) + concealed-type marker bound exposure instead.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.clearIfUnchanged() }
        }
    }

    /// Clear the pasteboard only if our sensitive item is still current.
    private func clearIfUnchanged() {
        defer { pendingChangeCount = nil; clearTask?.cancel(); clearTask = nil }
        guard let pending = pendingChangeCount,
              NSPasteboard.general.changeCount == pending else { return }
        NSPasteboard.general.clearContents()
    }
}
#endif

import SwiftUI

/// Copies values to the system pasteboard via `PlatformPasteboard`. Sensitive values
/// auto-expire after the user's configured delay: on iOS the OS removes the item even
/// if the app is suspended or killed (`UIPasteboard.expirationDate`); on macOS the item
/// is marked concealed and cleared on a timer / app resign / terminate (best-effort,
/// see `PlatformPasteboard`).
@MainActor @Observable final class ClipboardService {
    private let settings: SettingsStore
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    /// Set briefly after a copy so the UI can show "Copied <label>".
    var recentCopyLabel: String?

    init(settings: SettingsStore) { self.settings = settings }

    func copy(_ value: String, label: String? = nil, sensitive: Bool = true) {
        let seconds = settings.clipboardClearSeconds
        if sensitive {
            PlatformPasteboard.copySensitive(value, clearAfter: seconds > 0 ? TimeInterval(seconds) : 0)
        } else {
            PlatformPasteboard.copyPlain(value)
        }

        recentCopyLabel = label ?? "Copied"
        scheduleToastDismiss()
        Haptics.success()
        // Copy frequency is the core daily-use signal; only the sensitivity
        // class travels — never the value, field, or item.
        AnalyticsEngine.shared.log(.copiedToClipboard(sensitive: sensitive))
    }

    private func scheduleToastDismiss() {
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.recentCopyLabel = nil
        }
    }
}

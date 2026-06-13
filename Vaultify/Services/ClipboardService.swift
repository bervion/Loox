import SwiftUI
import UIKit

/// Copies values to the system pasteboard. Sensitive values auto-expire after
/// the user's configured delay using the pasteboard's own `expirationDate` —
/// the OS removes the item even if the app is suspended or killed, and only the
/// item we set is affected. Universal Clipboard is allowed so paste works on the
/// user's other devices; the auto-expiry still bounds exposure.
@MainActor @Observable final class ClipboardService {
    private let settings: SettingsStore
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    /// Set briefly after a copy so the UI can show "Copied <label>".
    var recentCopyLabel: String?

    init(settings: SettingsStore) { self.settings = settings }

    func copy(_ value: String, label: String? = nil, sensitive: Bool = true) {
        let seconds = settings.clipboardClearSeconds
        var options: [UIPasteboard.OptionsKey: Any] = [:]
        if sensitive, seconds > 0 {
            options[.expirationDate] = Date().addingTimeInterval(TimeInterval(seconds))
        }
        UIPasteboard.general.setItems([["public.utf8-plain-text": value]], options: options)

        recentCopyLabel = label ?? "Copied"
        scheduleToastDismiss()
        Haptics.success()
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

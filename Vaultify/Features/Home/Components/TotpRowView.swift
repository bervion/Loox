import SwiftUI

/// Full-width authenticator row for the 2FA codes list screen — the row
/// counterpart of the Home scroller's `TotpCardView`. Favicon + title/username
/// leading, the ticking code + countdown ring trailing. Tap copies the code and
/// flashes "Copied" for ~1.1 s (same contract and timings as the card).
struct TotpRowView: View {
    let item: VaultItem

    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var copied = false

    var body: some View {
        // 1-second tick via TimelineView so every visible row stays in sync
        // without spinning up individual timers (mirrors TotpCardView).
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let date = context.date
            let value = item.totpField?.value ?? ""
            let code = TOTPGenerator.code(forStoredValue: value, date: date)
            // Ring + expiry warning honor the otpauth period (a 60s code with a
            // hardcoded 30 looked expired mid-validity).
            let period = TOTPGenerator.period(forStoredValue: value)
            let remaining = TOTPGenerator.secondsRemaining(period: period, date: date)
            rowContent(code: code, remaining: remaining, progress: Double(remaining) / Double(period))
        }
    }

    private func rowContent(code: String?, remaining: Int, progress: Double) -> some View {
        let theme = env.theme.active

        return Button(action: { copyCode(code) }) {
            HStack(spacing: Space.s3) {
                FaviconView(urlString: item.urlField?.value,
                            category: item.category,
                            size: 40, title: item.title, iconAsset: item.iconAsset)

                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: item.title.isEmpty ? appString("Untitled") : item.title)
                        .vaultType(.body)
                        .themedForeground()
                        .lineLimit(1)
                    // Username distinguishes multiple accounts on the same service —
                    // STRICTLY the username field, never the URL-falling-back subtitle
                    // (noise next to a code; same rule as TotpCardView).
                    if let username = item.readableUsernameField?.value, !username.isEmpty {
                        Text(username)
                            .vaultType(.caption)
                            .themedForeground(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: Space.s2)

                // The code text stays resident (opacity 0) under the "Copied" flash so
                // the trailing slot keeps its width — a Group swap here would jump the
                // label toward the ring and back, reading as layout jitter (the card
                // could swap in place because its content is leading-aligned in a
                // fixed-width frame).
                ZStack(alignment: .trailing) {
                    // Code mirrors the ring's ≤5 s warning so an about-to-expire
                    // code is obvious before the user copies it.
                    Text(formatCode(code))
                        .foregroundStyle(remaining <= 5
                            ? theme.color(.warning)
                            : Color(rgb: theme.primaryText))
                        .opacity(copied ? 0 : 1)
                    if copied {
                        Text("Copied")
                            .foregroundStyle(theme.color(.success))
                    }
                }
                // SF with tabular digits (user rule: mono is for passwords only) —
                // digits keep a stable width so the per-second tick never jitters.
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                // Guards the "123 456" grouping at accessibility Dynamic Type sizes
                // (parity with TotpCardView); priority makes the TITLE column give
                // way first so the code — the row's payload — never truncates.
                .minimumScaleFactor(0.7)
                .layoutPriority(1)
                .animation(reduceMotion ? nil : .easeInOut(duration: Motion.fast), value: copied)

                TotpRingView(progress: progress, remaining: remaining)
            }
            .frame(minHeight: Metric.hitMin)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // TOTP codes are sensitive — respect privacy screen.
        .privacySensitiveContents()
        // VoiceOver: identity as the label, the code digit-by-digit as the value
        // (a grouped "123 456" would be spoken as two cardinal numbers — useless
        // when typing the code into another device), and an explicit copy hint.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilityIdentity))
        .accessibilityValue(Text(verbatim: copied ? appString("Copied") : spokenDigits(code)))
        .accessibilityHint(Text("Double tap to copy"))
    }

    /// "Title, username" — the row's spoken identity.
    private var accessibilityIdentity: String {
        let title = item.title.isEmpty ? appString("Untitled") : item.title
        guard let username = item.readableUsernameField?.value, !username.isEmpty else { return title }
        return "\(title), \(username)"
    }

    /// Space-separated digits so VoiceOver reads the code digit-by-digit.
    private func spokenDigits(_ code: String?) -> String {
        guard let code else { return "" }
        return code.map(String.init).joined(separator: " ")
    }

    private func copyCode(_ code: String?) {
        guard let code, !copied else { return }
        // ClipboardService fires Haptics.success on copy — do not add a second
        // haptic here (would double-buzz on every 2FA code copy).
        env.clipboard.copy(code, label: appString("2FA code"))
        copied = true
        // The visual flash mutates the focused element's label silently —
        // announce the copy so VoiceOver users know the activation landed.
        AccessibilityNotification.Announcement(appString("Copied")).post()
        // Flash duration matches DS: 1100 ms.
        Task {
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            copied = false
        }
    }

    /// Insert a space between the two halves of a 6-digit code (e.g. "123 456").
    private func formatCode(_ code: String?) -> String {
        guard let code, code.count == 6 else { return code ?? "------" }
        return String(code.prefix(3)) + " " + String(code.suffix(3))
    }
}

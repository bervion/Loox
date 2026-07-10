import SwiftUI

/// Horizontal authenticator card for the Home TOTP quick-view scroller.
/// 158pt wide card (surface-base, Radius.md, hairline stroke).
/// Tap copies the code and flashes "Đã chép" for ~1.1 s with haptic feedback.
/// Under Reduce Motion: ring is replaced by a numeric countdown (see TotpRingView).
struct TotpCardView: View {
    let item: VaultItem

    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // 1-second tick shared via a TimelineView so every visible card stays in sync
    // without spinning up individual timers.
    @State private var copied = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let date = context.date
            let code = TOTPGenerator.code(forStoredValue: item.totpField?.value ?? "", date: date)
            let remaining = TOTPGenerator.secondsRemaining(date: date)
            let progress = Double(remaining) / 30.0

            cardContent(code: code, remaining: remaining, progress: progress)
        }
    }

    private func cardContent(code: String?, remaining: Int, progress: Double) -> some View {
        let theme = env.theme.active

        return Button(action: { copyCode(code) }) {
            VStack(alignment: .leading, spacing: Space.s3) {
                // Top row: icon tile + ring
                HStack {
                    FaviconView(urlString: item.urlField?.value,
                                category: item.category,
                                size: 26, title: item.title)
                    Spacer()
                    TotpRingView(progress: progress, remaining: remaining)
                }

                // Code + name
                VStack(alignment: .leading, spacing: 2) {
                    Group {
                        if copied {
                            Text("Copied")
                                .foregroundStyle(theme.color(.success))
                        } else {
                            // Code mirrors the ring's ≤5 s warning so an about-to-expire
                            // code is obvious before the user copies it.
                            Text(formatCode(code))
                                .foregroundStyle(remaining <= 5
                                    ? theme.color(.warning)
                                    : Color(rgb: theme.primaryText))
                        }
                    }
                    // OTP is a secret/code — the typographic object gets MonoLisa
                    // (matches ItemDetail's TOTPCodeView), not a system font.
                    .font(.vaultCode(.title3, weight: .bold))
                    .lineLimit(1)
                    // Guards the "123 456" grouping from clipping inside the
                    // fixed 158pt-wide card at accessibility XXL Dynamic Type.
                    .minimumScaleFactor(0.7)
                    .animation(reduceMotion ? nil : .easeInOut(duration: Motion.fast), value: copied)

                    Text(item.title.isEmpty ? "Untitled" : item.title)
                        .vaultType(.footnote)
                        .themedForeground(.secondary)
                        .lineLimit(1)

                    // Username distinguishes multiple accounts on the same service
                    // (two GitHub logins would otherwise render identical cards).
                    if let username = item.subtitle, !username.isEmpty {
                        Text(username)
                            .vaultType(.caption)
                            .themedForeground(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
            .frame(width: 158, alignment: .leading)
            // Surface-base card with hairline stroke (matches DS TotpCard spec).
            .background(Color(rgb: theme.elevatedBackground))
            .vaultCornerRadius(Radius.md)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(Color(rgb: theme.separator), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        // TOTP codes are sensitive — respect privacy screen.
        .privacySensitiveContents()
    }

    private func copyCode(_ code: String?) {
        guard let code, !copied else { return }
        // ClipboardService fires Haptics.success on copy — do not add a second
        // haptic here (would double-buzz on every 2FA code copy).
        env.clipboard.copy(code, label: "2FA code")
        copied = true
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

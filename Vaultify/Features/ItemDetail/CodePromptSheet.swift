import SwiftUI

/// Reveal prompt for a protected field: the Extra Protection swirl plays its
/// one-shot dot reveal over the shield, the framing line sits right above the
/// input, and the lock-screen password field (embedded unlock arrow, busy
/// spinner) submits. `onSubmit` returns an error string to show, or `nil` on
/// success (which dismisses the sheet).
struct CodePromptSheet: View {
    let title: LocalizedStringResource
    var message: LocalizedStringResource?
    /// Names the secret being asked for — "Extra Password" and "Custom code"
    /// prompts must not both say "Code".
    var placeholder: LocalizedStringKey = "Code"
    let onSubmit: (String) async -> String?

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    @State private var code = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        VaultSheetScaffold(title: title, trailing: { EmptyView() }) {
            VStack(spacing: Space.s4) {
                // One-shot reveal, then still — the same mark as the Extra
                // Protection screen, so the prompt reads as the same feature.
                LooxSwirlAnimationView(mode: .reveal,
                                       centerIcon: "dt_shield_keyhole",
                                       centerTint: env.theme.active.color(.accent))
                    .frame(width: 110, height: 110)
                    .padding(.top, Space.s2)

                if let message {
                    Text(message.inAppLocalized)
                        .vaultType(.footnote).themedForeground(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                LockPasswordField(text: $code, busy: busy, title: placeholder,
                                  focus: $focused) {
                    Task { await submit() }
                }

                if let error {
                    Text(verbatim: error)
                        .vaultType(.footnote).foregroundStyle(VaultColors.strengthWeak)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.s6)
            .padding(.top, Space.s4)
        }
        .platformPresentationDetents([.medium])
    }

    private func submit() async {
        guard !code.isEmpty, !busy else { return }
        busy = true; error = nil
        if let failure = await onSubmit(code) {
            error = failure
            Haptics.error()
        } else {
            dismiss()
        }
        busy = false
    }
}

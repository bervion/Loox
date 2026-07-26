import SwiftUI

/// Reusable secure code/password entry sheet. `onSubmit` returns an error string
/// to show, or `nil` on success (which dismisses the sheet).
struct CodePromptSheet: View {
    let title: LocalizedStringResource
    var message: LocalizedStringResource?
    var confirmLabel: LocalizedStringResource = "Unlock"
    /// Names the secret being asked for — "Extra Password" and "Custom code"
    /// prompts must not both say "Code".
    var placeholder: LocalizedStringKey = "Code"
    let onSubmit: (String) async -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        VaultSheetScaffold(title: title, trailing: {
            Button(String(localized: confirmLabel.inAppLocalized)) { Task { await submit() } }
                .disabled(code.isEmpty || busy)
        }) {
            Form {
                if let message {
                    // Framing copy, not content — a white pill here reads as a
                    // second text field sitting above the real one.
                    Section {
                        Text(message.inAppLocalized).vaultType(.footnote).themedForeground(.secondary)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }
                Section {
                    RevealableSecureField(title: placeholder, text: $code, autofocus: true)
                        .listRowInsets(.init())
                        .submitLabel(.go)
                        .onSubmit { Task { await submit() } }
                }
                .listRowBackground(VaultColors.surface)
                if let error { Text(error).foregroundStyle(VaultColors.strengthWeak) }
            }
            .overlay { if busy { ProgressView().controlSize(.large) } }
        }
        .platformPresentationDetents([.medium])
    }

    private func submit() async {
        guard !code.isEmpty else { return }
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

import SwiftUI

/// Reusable secure code/password entry sheet. `onSubmit` returns an error string
/// to show, or `nil` on success (which dismisses the sheet).
struct CodePromptSheet: View {
    let title: LocalizedStringResource
    var message: LocalizedStringResource?
    var confirmLabel: LocalizedStringResource = "Unlock"
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
                    Section { Text(message.inAppLocalized).font(.footnote).themedForeground(.secondary) }
                    .listRowBackground(VaultColors.surface)
                }
                Section {
                    RevealableSecureField(title: "Code", text: $code)
                        .listRowInsets(.init())
                        .submitLabel(.go)
                        .onSubmit { Task { await submit() } }
                }
                .listRowBackground(VaultColors.surface)
                if let error { Text(error).foregroundStyle(VaultColors.strengthWeak) }
            }
            .overlay { if busy { ProgressView().controlSize(.large) } }
        }
        .presentationDetents([.medium])
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

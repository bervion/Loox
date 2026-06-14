import SwiftUI

/// Master-password creation step. Enforces a minimum length and confirmation,
/// shows live strength, and warns that the password cannot be recovered.
struct CreateMasterPasswordView: View {
    /// Returns an error message, or `nil` on success (parent then advances).
    let onSubmit: (String) async -> String?

    @State private var password = ""
    @State private var confirm = ""
    @State private var busy = false
    @State private var error: String?

    private var meetsLength: Bool { password.count >= 8 }
    private var matches: Bool { !confirm.isEmpty && password == confirm }
    private var canSubmit: Bool { meetsLength && matches && !busy }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    PolarisIcon(Icons.lockFill, size: 44).foregroundStyle(Color.accentColor)
                    Text("Create your master password")
                        .font(.title.bold())
                    Text("This is the only password you’ll need to remember. It unlocks everything.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.top, 8)

                VStack(alignment: .leading, spacing: 12) {
                    RevealableSecureField(title: "Master password", text: $password)
                    PasswordStrengthMeter(password: password)
                    RevealableSecureField(title: "Confirm password", text: $confirm)
                    if !confirm.isEmpty && !matches {
                        Text("Passwords don’t match")
                            .font(.caption).foregroundStyle(VaultColors.strengthWeak)
                    }
                }

                Label {
                    Text("If you forget this password, only your Emergency Kit can recover the vault. There is no reset.")
                        .font(.footnote).foregroundStyle(.secondary)
                } icon: {
                    PolarisIcon(Icons.alert, size: 18).foregroundStyle(VaultColors.strengthMedium)
                }
                .padding(12)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                if let error {
                    Text(error).font(.footnote).foregroundStyle(VaultColors.strengthWeak)
                }
            }
            .padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            Button {
                Task { await submit() }
            } label: {
                if busy { ProgressView().frame(maxWidth: .infinity) }
                else { Text("Continue").frame(maxWidth: .infinity) }
            }
            .buttonStyle(.themedProminent)
            .controlSize(.large)
            .disabled(!canSubmit)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
    }

    private func submit() async {
        guard canSubmit else { return }
        busy = true
        error = nil
        error = await onSubmit(password)
        busy = false
        if error != nil { Haptics.error() }
    }
}

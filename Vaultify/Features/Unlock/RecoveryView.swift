import SwiftUI

/// Recover a vault with the Emergency Kit recovery key and set a new master
/// password. Presented as a sheet from the lock screen. Field styling mirrors the
/// create-master-password step (prominent icon-tile cards on the grouped background).
struct RecoveryView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var recoveryKey = ""
    @State private var newPassword = ""
    @State private var confirm = ""
    @State private var busy = false
    @State private var error: String?

    private var canSubmit: Bool {
        !recoveryKey.isEmpty && newPassword.count >= 8 && newPassword == confirm && !busy
    }

    var body: some View {
        VaultSheetScaffold(title: "Recover Vault", trailing: {
            Button("Recover") { Task { await recover() } }.disabled(!canSubmit)
        }) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s5) {
                    VStack(alignment: .leading, spacing: Space.s2) {
                        sectionLabel("Emergency Kit")
                        recoveryKeyField
                        Text("Enter the recovery key from your Emergency Kit.")
                            .vaultType(.footnote).themedForeground(.secondary)
                    }

                    VStack(alignment: .leading, spacing: Space.s3) {
                        sectionLabel("New master password")
                        RevealableSecureField(title: "New password", text: $newPassword,
                                              icon: Icons.lockFill, prominent: true)
                        PasswordStrengthMeter(password: newPassword, emptyLabel: "Choose a strong password")
                        RevealableSecureField(title: "Confirm password", text: $confirm,
                                              icon: Icons.lockFill, prominent: true)
                    }

                    if let error {
                        Text(error).vaultType(.footnote).foregroundStyle(VaultColors.strengthWeak)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.s6)
            }
            .scrollDismissesKeyboard(.immediately)
            .overlay { if busy { ProgressView().controlSize(.large) } }
        }
    }

    private func sectionLabel(_ text: LocalizedStringKey) -> some View {
        Text(text).vaultType(.subhead).fontWeight(.semibold).themedForeground(.secondary)
    }

    /// Recovery-key input in the same prominent card as the password fields, with a key tile.
    private var recoveryKeyField: some View {
        HStack(alignment: .center, spacing: Space.s3) {
            PolarisIcon(Icons.key, size: Metric.iconInline)
                .foregroundStyle(Color(rgb: theme.accent))
                .frame(width: Metric.controlSmall, height: Metric.controlSmall)
                .background(Color(rgb: theme.accentSoft),
                            in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            TextField("Recovery key", text: $recoveryKey, axis: .vertical)
                .font(recoveryKey.isEmpty ? .body : .vaultCode())
                .platformAutocapitalization(.characters)
                .autocorrectionDisabled()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, Space.s3)
        .background(VaultColors.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .elevation(.level2)
    }

    private func recover() async {
        busy = true; error = nil
        do {
            try await env.session.recover(recoveryKey: recoveryKey, newPassword: newPassword)
            dismiss()
        } catch {
            self.error = error.localizedDescription
            Haptics.error()
        }
        busy = false
    }
}

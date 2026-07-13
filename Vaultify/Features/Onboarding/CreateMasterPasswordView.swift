import SwiftUI

/// Master-password creation step. Enforces a minimum length and confirmation,
/// shows live strength, and warns that the password cannot be recovered.
struct CreateMasterPasswordView: View {
    /// Returns an error message, or `nil` on success (parent then advances).
    let onSubmit: (String) async -> String?
    /// Header copy. Defaults fit first-run vault creation; the join-existing-vault
    /// flow overrides them (same fields, different context — the vault already exists).
    var title: LocalizedStringKey = "Create your password"
    var subtitle: LocalizedStringKey = "This is the only password you’ll need to remember. It unlocks everything."
    @Environment(\.appTheme) private var theme

    @State private var password = ""
    @State private var confirm = ""
    @State private var busy = false
    @State private var error: String?

    private var meetsLength: Bool { password.count >= 8 }
    private var matches: Bool { !confirm.isEmpty && password == confirm }
    private var canSubmit: Bool { meetsLength && matches && !busy }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s5) {
                VStack(alignment: .leading, spacing: Space.s3) {
                    // Loox brand lockup: the six-circle symbol next to the LOOX
                    // wordmark, inline — the brand identity for this step.
                    BrandLockup(height: 38)
                    Text(title)
                        .vaultType(.screenTitle)
                    Text(subtitle)
                        .vaultType(.subhead).themedForeground(.secondary)
                }
                .padding(.top, Space.s2)

                VStack(alignment: .leading, spacing: Space.s6) {
                    // Password + its strength meter form one tight group; the confirm field
                    // sits a full step below so the strength label doesn't crowd it.
                    VStack(alignment: .leading, spacing: Space.s3) {
                        RevealableSecureField(title: "Loox Password", text: $password, icon: Icons.lockFill, prominent: true)
                        PasswordStrengthMeter(password: password, emptyLabel: "Choose a strong password")
                    }
                    VStack(alignment: .leading, spacing: Space.s2) {
                        RevealableSecureField(title: "Confirm Loox Password", text: $confirm, icon: Icons.lockFill, prominent: true)
                        if !confirm.isEmpty && !matches {
                            Text("Passwords don’t match")
                                .vaultType(.caption).foregroundStyle(VaultColors.strengthWeak)
                        }
                    }
                }

                // Amber caution card — the vault is unrecoverable without the Emergency Kit,
                // so this warning carries a warning tint (not a neutral surface).
                // Custom HStack (not Label) so the icon stays vertically centred against
                // the multi-line text instead of riding the first baseline.
                HStack(alignment: .center, spacing: Space.s3) {
                    PolarisIcon(Icons.alert, size: Metric.iconUtility)
                        .foregroundStyle(Color(rgb: theme.warning))
                    Text("If you forget this password, only your Emergency Kit can recover the vault. There is no reset.")
                        .vaultType(.footnote).themedForeground(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(Space.s4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(rgb: theme.warningSoft), in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))

                if let error {
                    Text(error).vaultType(.footnote).foregroundStyle(VaultColors.strengthWeak)
                }
            }
            .padding(Space.s6)
        }
        // Dismiss the keyboard on scroll or when an empty area is tapped
        // (field/button taps keep their own handling — children win over this gesture).
        .scrollDismissesKeyboard(.immediately)
        .onTapGesture { dismissKeyboard() }
        .safeAreaInset(edge: .bottom) {
            Button {
                Task { await submit() }
            } label: {
                Text("Continue").frame(maxWidth: .infinity).prominentButtonLoading(busy)
            }
            .buttonStyle(.themedProminent)
            .controlSize(.large)
            .disabled(!canSubmit)
            .padding(.horizontal, Space.s6)
            .padding(.bottom, Space.gutter)
        }
    }

    /// Resign the first responder so the keyboard hides (on scroll / tap-outside).
    private func dismissKeyboard() {
        PlatformAppearance.dismissKeyboard()
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

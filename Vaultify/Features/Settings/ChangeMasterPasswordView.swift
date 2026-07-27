import SwiftUI

/// Re-keys the master-password unlock path after verifying the current password.
/// The Vault Key is unchanged, so biometrics and the Emergency Kit stay valid.
///
/// Styled as a sibling of the Extra Password screen and the onboarding password
/// step: a plain page with capsule fields, the brand swirl playing its one-shot
/// reveal above the title, and one pinned capsule CTA.
struct ChangeMasterPasswordView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var current = ""
    @State private var newPassword = ""
    @State private var confirm = ""
    @State private var busy = false
    @State private var error: String?

    private var matches: Bool { !confirm.isEmpty && newPassword == confirm }

    private var canSubmit: Bool {
        !current.isEmpty && newPassword.count >= 8 && newPassword == confirm && !busy
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s5) {
                header
                currentPasswordCapsule
                // Same group as onboarding: one capsule holding the new password
                // (with its inline strength ring) and the confirm row.
                PasswordCreationGroup(password: $newPassword, confirm: $confirm,
                                      passwordTitle: "New master password",
                                      confirmTitle: "Confirm new password")
                if !confirm.isEmpty && !matches {
                    Text("Passwords don’t match")
                        .vaultType(.caption).foregroundStyle(VaultColors.strengthWeak)
                }
                VaultInfoBanner(.info, icon: Icons.key,
                                text: "Your Vault Key doesn't change. Face ID unlock and your Emergency Kit keep working.")
                if let error {
                    Text(verbatim: error)
                        .vaultType(.footnote).foregroundStyle(VaultColors.strengthWeak)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.s6)
            .vaultContentWidth(.form)
        }
        // Plain page with GRAY capsule fields — the Apple-Account idiom the
        // onboarding step and Extra Password screen already use, and what the
        // swirl's dot mask reads best on.
        .background(Color(rgb: theme.background).ignoresSafeArea())
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle("Change Master Password")
        .platformNavigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            // The CTA holds the physical bottom edge instead of riding up with
            // the keyboard. The scroll view itself stays keyboard-aware, so the
            // focused field is still scrolled into view on small phones.
            BrandCapsuleCTA(title: "Change Password", enabled: canSubmit, busy: busy) {
                Task { await change() }
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .overlay { if busy { ProgressView().controlSize(.large) } }
    }

    // MARK: Pieces

    /// One-shot swirl reveal around a padlock, then the title and subtitle —
    /// the shape the Extra Password screen established.
    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            LooxSwirlAnimationView(mode: .reveal,
                                   centerIcon: "dt_lock",
                                   centerTint: env.theme.active.color(.accent))
                .frame(width: 150, height: 150)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.s4)
            Text("Choose a new master password")
                .vaultType(.screenTitle)
            Text("Enter your current master password, then choose a new one.")
                .vaultType(.subhead).themedForeground(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Single capsule row for the password being replaced. No autofocus: the
    /// keyboard would come up over the header before the swirl finished its
    /// reveal, which is the first thing this screen shows.
    private var currentPasswordCapsule: some View {
        RevealableSecureField(title: "Current master password", text: $current,
                              inList: true)
            .padding(.horizontal, Space.s5)
            .frame(height: 54)
            .background(Color(rgb: theme.secondaryBackground),
                        in: RoundedRectangle(cornerRadius: 27, style: .continuous))
    }

    // MARK: Actions

    private func change() async {
        guard canSubmit else { return }
        busy = true; error = nil
        do {
            try await env.session.changeMasterPassword(current: current, new: newPassword)
            Haptics.success()
            dismiss()
        } catch {
            self.error = error.localizedDescription
            Haptics.error()
        }
        busy = false
    }
}

import SwiftUI

/// Master-password creation step, styled like the Apple Account sign-in: a white
/// page, one gray capsule field that grows a confirm row (grouped, with a divider)
/// once typing starts, a strength RING inside the first row, a duotone info note
/// instead of a warning card, and a blue capsule Continue pinned at the bottom.
struct CreateMasterPasswordView: View {
    /// Returns an error message, or `nil` on success (parent then advances).
    let onSubmit: (String) async -> String?
    /// Header copy. Defaults fit first-run vault creation; the join-existing-vault
    /// flow overrides them (same fields, different context — the vault already exists).
    var title: LocalizedStringKey = "Create your password"
    var subtitle: LocalizedStringKey = "This is the only password you’ll need to remember. It unlocks everything."
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    // Loox dots mark (the Home empty-avatar look), centred,
                    // revealing its rings on appear.
                    LooxDotsAvatar(size: 100, revealsOnAppear: true)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Space.s6)
                    Text(title)
                        .vaultType(.screenTitle)
                    Text(subtitle)
                        .vaultType(.subhead).themedForeground(.secondary)
                }
                .padding(.top, Space.s2)

                PasswordCreationGroup(password: $password, confirm: $confirm,
                                      passwordTitle: "Loox Password",
                                      confirmTitle: "Confirm Loox Password")

                if !confirm.isEmpty && !matches {
                    Text("Passwords don’t match")
                        .vaultType(.caption).foregroundStyle(VaultColors.strengthWeak)
                }

                infoNote

                if let error {
                    Text(error).vaultType(.footnote).foregroundStyle(VaultColors.strengthWeak)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.s6)
            // Regular width (iPad/Mac): centered form column, not a full-screen stretch.
            .vaultContentWidth(.form)
        }
        // Apple-Account look: a plain white page with GRAY capsule fields.
        .background(Color(rgb: theme.background).ignoresSafeArea())
        // Dismiss the keyboard on scroll or when an empty area is tapped
        // (field/button taps keep their own handling — children win over this gesture).
        .scrollDismissesKeyboard(.immediately)
        .onTapGesture { dismissKeyboard() }
        .safeAreaInset(edge: .bottom) {
            // ONLY the CTA ignores the keyboard: it holds the physical bottom
            // edge instead of sliding up under the thumb mid-entry. The scroll
            // view keeps its keyboard inset, so the focused field still gets
            // scrolled into view — on a 4.7-inch phone the confirm row sits
            // below the keyboard line, and this screen has too little content
            // to scroll it back up by hand.
            BrandCapsuleCTA(enabled: canSubmit, busy: busy) { Task { await submit() } }
                .ignoresSafeArea(.keyboard, edges: .bottom)
        }
    }

    /// Duotone info glyph + the no-reset note (replaces the amber warning card).
    private var infoNote: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Image("HandshakeDuotone")
                .resizable()
                .scaledToFit()
                .frame(width: 26, height: 26)
            Text("If you forget this password, only your Emergency Kit can recover the vault. There is no reset.")
                .vaultType(.footnote).themedForeground(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Space.s2)
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

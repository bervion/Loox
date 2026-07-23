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
    private var showConfirm: Bool { !password.isEmpty }

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

                passwordGroup

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
            BrandCapsuleCTA(enabled: canSubmit, busy: busy) { Task { await submit() } }
        }
        // The CTA stays PINNED at the bottom — it must not ride up on the
        // keyboard (the fields all sit in the top half of the screen).
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    // MARK: Password group (grows the confirm row once typing starts)

    private var passwordGroup: some View {
        VStack(spacing: 0) {
            HStack(spacing: Space.s3) {
                SecureField("Loox Password", text: $password)
                    .platformAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .platformTextContentType(.newPassword)
                if showConfirm {
                    strengthRing
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, Space.s5)
            .frame(height: 54)

            if showConfirm {
                Divider().padding(.leading, Space.s5)
                SecureField("Confirm Loox Password", text: $confirm)
                    .platformAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .platformTextContentType(.newPassword)
                    .padding(.horizontal, Space.s5)
                    .frame(height: 54)
                    .transition(.opacity)
            }
        }
        .background(Color(rgb: theme.secondaryBackground),
                    in: RoundedRectangle(cornerRadius: 27, style: .continuous))
        .animation(.vault(.spring(response: 0.4, dampingFraction: 0.85), reduceMotion: reduceMotion),
                   value: showConfirm)
    }

    /// Password strength as a small progress ring (replaces the bar meter):
    /// fills and recolors with the pattern-aware grade as the user types.
    private var strengthRing: some View {
        let result = PasswordStrengthEngine.evaluate(password)
        let (progress, strength): (Double, PasswordStrength) = {
            switch result.grade {
            case .veryWeak: return (0.2, .weak)
            case .weak:     return (0.4, .weak)
            case .fair:     return (0.6, .medium)
            case .strong:   return (0.8, .strong)
            case .excellent: return (1.0, .strong)
            }
        }()
        return ZStack {
            Circle().stroke(VaultColors.fill, lineWidth: 3)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(VaultColors.strength(strength),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 22, height: 22)
        .animation(.vault(.spring(response: 0.35, dampingFraction: 0.85), reduceMotion: reduceMotion),
                   value: progress)
        .accessibilityLabel(Text("Password strength"))
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

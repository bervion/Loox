import SwiftUI

/// Apple-Account-style password creation group, shared by the onboarding master
/// password step and the Extra Password screen: one gray capsule holding the
/// password row with an inline strength RING, and a confirm row (divider-split)
/// that appears once either field holds text. A single eye on the confirm row
/// reveals BOTH fields so what was typed can be compared visually.
struct PasswordCreationGroup: View {
    @Binding var password: String
    @Binding var confirm: String
    var passwordTitle: LocalizedStringKey = "Password"
    var confirmTitle: LocalizedStringKey = "Confirm password"

    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One reveal toggle for the WHOLE group — the eye shows both fields, so
    /// the user can visually compare what they typed against the confirm row.
    @State private var revealed = false

    /// The confirm row stays once EITHER field holds text — clearing the first
    /// field must never hide (and visually "swallow") a typed confirmation.
    private var showConfirm: Bool { !password.isEmpty || !confirm.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Space.s3) {
                passwordInput(passwordTitle, text: $password)
                if showConfirm {
                    strengthRing
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, Space.s5)
            .frame(height: 54)

            if showConfirm {
                Divider().padding(.leading, Space.s5)
                // The eye lives on the CONFIRM row (the first row already
                // carries the strength ring — two glyphs there read cluttered)
                // and still reveals BOTH fields.
                HStack(spacing: Space.s3) {
                    passwordInput(confirmTitle, text: $confirm)
                    revealButton
                }
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

    /// Secure by default, plain text while the eye is on. `.newPassword` stays
    /// on both variants so the system password tools keep working.
    @ViewBuilder private func passwordInput(_ title: LocalizedStringKey,
                                            text: Binding<String>) -> some View {
        Group {
            if revealed {
                TextField(title, text: text)
            } else {
                SecureField(title, text: text)
            }
        }
        .platformAutocapitalization(.never)
        .autocorrectionDisabled()
        .platformTextContentType(.newPassword)
    }

    /// The eye — reveals BOTH fields at once. Hit area padded to the 44pt
    /// minimum without growing the row (contentShape only affects hit-testing).
    private var revealButton: some View {
        Button {
            revealed.toggle()
            Haptics.tap()
        } label: {
            VaultIcon(revealed ? Icons.hide : Icons.reveal, size: Metric.iconInline)
                .themedForeground(.secondary)
                .contentShape(Rectangle().inset(by: -(Metric.hitMin - Metric.iconInline) / 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(revealed ? "Hide password" : "Show password"))
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
}

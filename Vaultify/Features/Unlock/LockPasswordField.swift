import SwiftUI

/// Master-password field for the lock screen: a rounded field with an inline accent
/// "login" arrow button on the trailing edge (with a little padding around it). Tapping the
/// button — or the keyboard's Go/return key — submits. Shows a spinner on the button while busy.
struct LockPasswordField: View {
    @Binding var text: String
    var busy: Bool
    /// Placeholder + accessibility name. The default fits the lock screen; the
    /// Extra Password prompt names its own secret.
    var title: LocalizedStringKey = "Enter password"
    /// Owned by the lock screen so the success choreography can dismiss the
    /// keyboard before the mark glides back to centre.
    var focus: FocusState<Bool>.Binding
    let onSubmit: () -> Void

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        HStack(spacing: Space.s2) {
            VaultIcon(Icons.lock, size: Metric.iconInline)
                .foregroundStyle(Color(rgb: env.theme.active.secondaryText))
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    // Placeholder → SF; the typed value keeps MonoLisa below.
                    Text(title)
                        .vaultType(.body)
                        .foregroundStyle(Color(rgb: env.theme.active.secondaryText))
                }
                SecureField("", text: $text)
                    .accessibilityLabel(Text(title))
                    .accessibilityIdentifier("lock.password")
                    .platformAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .platformTextContentType(.password)
                    .font(.vaultCode())
                    .focused(focus)
                    .submitLabel(.go)
                    .onSubmit(onSubmit)
                    .foregroundStyle(Color(rgb: env.theme.active.primaryText))
            }

            loginButton
        }
        // Asymmetric by design: the field hugs the embedded login button (36pt) on the
        // trailing edge, so the row's total height tracks the button, not a 4pt-grid pick.
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(Color(rgb: env.theme.active.controlBackground),
                    in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .onAppear { focus.wrappedValue = true }
    }

    private var loginButton: some View {
        // The accent fill, like every other primary action (the slide-to-unlock
        // knob on this same screen is the closest sibling). THEME tokens, not
        // `Color.primary`/system background — those follow the SYSTEM scheme,
        // and inside a sheet whose surface follows the APP theme they can land
        // near the surface color (a washed-out "disabled" button). `accentFill`
        // and `accentForeground` also carry the WCAG guarantee that the arrow
        // stays legible on every preset, which a raw accent pairing would not.
        let onTint = Color(rgb: env.theme.active.accentForeground)
        let side: CGFloat = 36
        return Button(action: onSubmit) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(Color(rgb: env.theme.active.accentFill))
                if busy {
                    ProgressView()
                        .controlSize(.small)
                        .tint(onTint)
                } else {
                    VaultIcon(Icons.arrowRight, size: 18)
                        .foregroundStyle(onTint)
                }
            }
            .frame(width: side, height: side)
            // Invisible padded hit area to the 44pt minimum — the visual button stays
            // snug inside the field row (same technique as `RevealableSecureField`).
            .contentShape(Rectangle().inset(by: -(Metric.hitMin - side) / 2))
        }
        .buttonStyle(.plain)
        .disabled(text.isEmpty || busy)
        .opacity(text.isEmpty ? 0.45 : 1)
        .accessibilityLabel(Text("Unlock"))
        .accessibilityIdentifier("lock.submit")
    }
}

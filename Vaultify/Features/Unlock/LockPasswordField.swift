import SwiftUI

/// Master-password field for the lock screen: a rounded field with an inline accent
/// "login" arrow button on the trailing edge (with a little padding around it). Tapping the
/// button — or the keyboard's Go/return key — submits. Shows a spinner on the button while busy.
struct LockPasswordField: View {
    @Binding var text: String
    var busy: Bool
    /// Owned by the lock screen so the success choreography can dismiss the
    /// keyboard before the mark glides back to centre.
    var focus: FocusState<Bool>.Binding
    let onSubmit: () -> Void

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        HStack(spacing: Space.s2) {
            PolarisIcon(Icons.lock, size: Metric.iconInline)
                .foregroundStyle(Color(rgb: env.theme.active.secondaryText))
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    // Placeholder → SF; the typed value keeps MonoLisa below.
                    Text("Enter password")
                        .vaultType(.body)
                        .foregroundStyle(Color(rgb: env.theme.active.secondaryText))
                }
                SecureField("", text: $text)
                    .accessibilityLabel(Text("Enter password"))
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
        // Neutral primary fill (Apple-style): black in light, white in dark —
        // matching the app's neutral CTAs; the glyph is the opposing background.
        let onTint = Color.platformBackground
        let side: CGFloat = 36
        return Button(action: onSubmit) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(Color.primary)
                if busy {
                    ProgressView()
                        .controlSize(.small)
                        .tint(onTint)
                } else {
                    PolarisIcon(Icons.arrowRight, size: 18)
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

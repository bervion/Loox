import SwiftUI

/// Master-password field for the lock screen: a rounded field with an inline accent
/// "login" arrow button on the trailing edge (with a little padding around it). Tapping the
/// button — or the keyboard's Go/return key — submits. Shows a spinner on the button while busy.
struct LockPasswordField: View {
    @Binding var text: String
    var busy: Bool
    let onSubmit: () -> Void

    @Environment(AppEnvironment.self) private var env
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: Space.s2) {
            PolarisIcon(Icons.lock, size: Metric.iconInline)
                .foregroundStyle(Color(rgb: env.theme.active.secondaryText))
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text("Enter password")
                        .font(.vaultCode())
                        .foregroundStyle(Color(rgb: env.theme.active.secondaryText))
                }
                SecureField("", text: $text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.password)
                    .font(.vaultCode())
                    .focused($focused)
                    .submitLabel(.go)
                    .onSubmit(onSubmit)
                    .foregroundStyle(Color(rgb: env.theme.active.primaryText))
            }

            loginButton
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(Color(rgb: env.theme.active.controlBackground),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onAppear { focused = true }
    }

    private var loginButton: some View {
        // Follow the app's control tint: accent fill in light, white in dark. The glyph is the
        // contrasting colour (white on the accent fill; the dark background colour on white).
        let theme = env.theme.active
        let onTint = Color(rgb: theme.isDark ? theme.background : theme.accentForeground)
        return Button(action: onSubmit) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(env.theme.uiTint)
                if busy {
                    ProgressView()
                        .controlSize(.small)
                        .tint(onTint)
                } else {
                    PolarisIcon(Icons.arrowRight, size: 18)
                        .foregroundStyle(onTint)
                }
            }
            .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .disabled(text.isEmpty || busy)
        .opacity(text.isEmpty ? 0.45 : 1)
        .accessibilityLabel(Text("Unlock"))
    }
}

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
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text("Master password")
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
        Button(action: onSubmit) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(rgb: env.theme.active.accent))
                if busy {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color(rgb: env.theme.active.accentForeground))
                } else {
                    PolarisIcon(Icons.arrowRight, size: 18)
                        .foregroundStyle(Color(rgb: env.theme.active.accentForeground))
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

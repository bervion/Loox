import SwiftUI

/// First-run step that collects a display name. The flow seeds the mandatory default
/// identity from it (blank → a localized fallback, so the invariant always holds).
struct NameStepView: View {
    let onContinue: (String) -> Void
    @State private var name = ""
    @FocusState private var focused: Bool
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            PolarisIcon(Icons.person, size: 72)
                .foregroundStyle(Color.accentColor)
            Text("What should we call you?")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
                .padding(.top, Space.gutter)
            Text("We’ll set up your identity profile. You can edit it and add details anytime.")
                .font(.body)
                .themedForeground(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Space.s8)
                .padding(.top, Space.s2)

            TextField("Your name", text: $name)
                .textContentType(.name)
                .submitLabel(.continue)
                .focused($focused)
                .padding(.horizontal, 14)
                .padding(.vertical, Space.s3)
                .background(Color(rgb: theme.controlBackground),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, Space.s6)
                .padding(.top, Space.s6)
                .onSubmit { onContinue(name) }

            Spacer()
            Button { onContinue(name) } label: {
                Text("Continue").frame(maxWidth: .infinity)
            }
            .buttonStyle(.themedProminent)
            .controlSize(.large)
            .padding(.horizontal, Space.s6)
            .padding(.bottom, Space.s6)
        }
        .onAppear { focused = true }
    }
}

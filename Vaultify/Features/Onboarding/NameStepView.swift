import SwiftUI

/// First-run step that collects a display name + optional email. The flow seeds the
/// mandatory default identity and a "Loox Account" login from them.
/// Layout mirrors `CreateMasterPasswordView`: top-aligned, left-aligned, Loox brand
/// mark, and prominent fields with a leading icon tile.
struct NameStepView: View {
    let onContinue: (_ name: String, _ email: String) -> Void
    @State private var name = ""
    @State private var email = ""
    @FocusState private var focus: FieldID?
    @Environment(\.appTheme) private var theme

    private enum FieldID { case name, email }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s5) {
                VStack(alignment: .leading, spacing: Space.s3) {
                    // Loox dots mark (the Home empty-avatar look), centred,
                    // revealing its rings on appear.
                    LooxDotsAvatar(size: 100, revealsOnAppear: true)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Space.s6)
                    Text("What should we call you?")
                        .vaultType(.screenTitle)
                    Text("We’ll set up your identity profile. You can edit it and add details anytime.")
                        .vaultType(.subhead).themedForeground(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, Space.s2)

                VStack(spacing: Space.s3) {
                    field(Icons.person, "Your name", text: $name, id: .name,
                          contentType: .name, keyboard: .default, submit: .next)
                    field(Icons.mail, "Email (optional)", text: $email, id: .email,
                          contentType: .emailAddress, keyboard: .emailAddress, submit: .continue)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.s6)
        }
        // Dismiss the keyboard on scroll or when an empty area is tapped
        // (field/button taps keep their own handling — children win over this gesture).
        .scrollDismissesKeyboard(.immediately)
        .onTapGesture { dismissKeyboard() }
        .safeAreaInset(edge: .bottom) {
            Button { onContinue(name, email) } label: {
                Text("Continue").frame(maxWidth: .infinity)
            }
            .buttonStyle(.themedProminent)
            .controlSize(.large)
            .padding(.horizontal, Space.s6)
            .padding(.bottom, Space.s6)
        }
        // Pinned CTA — never rides up on the keyboard (fields sit high).
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onAppear { focus = .name }
    }

    /// Prominent field — mirrors `RevealableSecureField`'s onboarding style
    /// (accent icon tile + white card + soft shadow), but plain (non-secure) text.
    private func field(_ icon: String, _ placeholder: LocalizedStringKey, text: Binding<String>,
                       id: FieldID, contentType: PlatformTextContentType, keyboard: PlatformKeyboardType,
                       submit: SubmitLabel) -> some View {
        HStack(spacing: Space.s2) {
            PolarisIcon(icon, size: Metric.iconInline)
                .foregroundStyle(Color(rgb: theme.accent))
                .frame(width: Metric.controlSmall, height: Metric.controlSmall)
                .background(Color(rgb: theme.accentSoft),
                            in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            TextField(placeholder, text: text)
                .platformTextContentType(contentType)
                .platformKeyboardType(keyboard)
                .platformAutocapitalization(id == .email ? .never : .words)
                .autocorrectionDisabled(id == .email)
                .submitLabel(submit)
                .focused($focus, equals: id)
                .vaultType(.body)
                .foregroundStyle(Color(rgb: theme.primaryText))
                .onSubmit { id == .name ? (focus = .email) : onContinue(name, email) }
        }
        // Matches `RevealableSecureField`'s prominent-field card exactly (same
        // radius + horizontal inset) so sibling onboarding fields read as one family.
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s3)
        .background(Color(rgb: theme.elevatedBackground),
                    in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        .elevation(.level2)
    }

    /// Resign the first responder so the keyboard hides (on scroll / tap-outside).
    private func dismissKeyboard() {
        PlatformAppearance.dismissKeyboard()
    }
}

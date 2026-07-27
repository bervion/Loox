import SwiftUI

/// First-run step that collects a display name + email (both required) — the flow
/// seeds the mandatory default identity from them.
/// Onboarding concept: white page, one gray grouped capsule holding both fields
/// (no leading icons), and the blue capsule Continue pinned below the keyboard.
struct NameStepView: View {
    let onContinue: (_ name: String, _ email: String) -> Void
    @State private var name = ""
    @State private var email = ""
    @FocusState private var focus: FieldID?
    @Environment(\.appTheme) private var theme

    private enum FieldID { case name, email }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// Light-weight shape check — deliverability is proven later (sync / kit).
    private var emailLooksValid: Bool {
        trimmedEmail.contains("@") && trimmedEmail.contains(".") && trimmedEmail.count >= 5
    }
    private var canSubmit: Bool { !trimmedName.isEmpty && emailLooksValid }

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

                fieldGroup
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.s6)
            // Regular width (iPad/Mac): centered form column, not a full-screen stretch.
            .vaultContentWidth(.form)
        }
        // Onboarding concept: plain white page, gray grouped fields.
        .background(Color(rgb: theme.background).ignoresSafeArea())
        // Dismiss the keyboard on scroll or when an empty area is tapped
        // (field/button taps keep their own handling — children win over this gesture).
        .scrollDismissesKeyboard(.immediately)
        .onTapGesture { dismissKeyboard() }
        .safeAreaInset(edge: .bottom) {
            // ONLY the CTA ignores the keyboard (same rationale as the password
            // step): it holds the bottom edge instead of shifting under the thumb
            // mid-typing, while the scroll view stays keyboard-aware so the
            // autofocused field is still scrolled clear. The email field's Return
            // key submits directly, so the pinned button is not the only way on.
            BrandCapsuleCTA(enabled: canSubmit) { onContinue(trimmedName, trimmedEmail) }
                .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .onAppear { focus = .name }
    }

    /// Both fields in ONE gray capsule group split by an inset divider —
    /// mirrors the password step's grouped field. No leading icons.
    private var fieldGroup: some View {
        VStack(spacing: 0) {
            TextField("Your name", text: $name)
                .platformTextContentType(.name)
                .platformAutocapitalization(.words)
                .submitLabel(.next)
                .focused($focus, equals: .name)
                .onSubmit { focus = .email }
                .padding(.horizontal, Space.s5)
                .frame(height: 54)

            Divider().padding(.leading, Space.s5)

            TextField("Email", text: $email)
                .platformTextContentType(.emailAddress)
                .platformKeyboardType(.emailAddress)
                .platformAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.continue)
                .focused($focus, equals: .email)
                .onSubmit { if canSubmit { onContinue(trimmedName, trimmedEmail) } }
                .padding(.horizontal, Space.s5)
                .frame(height: 54)
        }
        .background(Color(rgb: theme.secondaryBackground),
                    in: RoundedRectangle(cornerRadius: 27, style: .continuous))
    }

    /// Resign the first responder so the keyboard hides (on scroll / tap-outside).
    private func dismissKeyboard() {
        PlatformAppearance.dismissKeyboard()
    }
}

import SwiftUI
import UIKit

/// First-run step that collects a display name. The flow seeds the mandatory default
/// identity from it (blank → a localized fallback, so the invariant always holds).
/// Layout mirrors `CreateMasterPasswordView`: top-aligned, left-aligned, Loox brand
/// mark, and a prominent field with a leading icon tile.
struct NameStepView: View {
    let onContinue: (String) -> Void
    @State private var name = ""
    @FocusState private var focused: Bool
    @Environment(\.appTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s5) {
                VStack(alignment: .leading, spacing: Space.s3) {
                    // Loox brand mark instead of a generic person glyph (that icon now
                    // leads the field). Wide wordmark, so `size` is its height.
                    BrandLogoMark.compact
                    Text("What should we call you?")
                        .vaultType(.screenTitle)
                    Text("We’ll set up your identity profile. You can edit it and add details anytime.")
                        .vaultType(.subhead).themedForeground(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, Space.s2)

                nameField
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.s6)
        }
        // Dismiss the keyboard on scroll or when an empty area is tapped
        // (field/button taps keep their own handling — children win over this gesture).
        .scrollDismissesKeyboard(.immediately)
        .onTapGesture { dismissKeyboard() }
        .safeAreaInset(edge: .bottom) {
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

    /// Prominent name field — mirrors `RevealableSecureField`'s onboarding style
    /// (accent icon tile + white card + soft shadow), but plain (non-secure) text.
    private var nameField: some View {
        HStack(spacing: Space.s2) {
            PolarisIcon(Icons.person, size: Metric.iconInline)
                .foregroundStyle(Color(rgb: theme.accent))
                .frame(width: Metric.controlSmall, height: Metric.controlSmall)
                .background(Color(rgb: theme.accentSoft),
                            in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            TextField("Your name", text: $name)
                .textContentType(.name)
                .submitLabel(.continue)
                .focused($focused)
                .font(.body)
                .foregroundStyle(Color(rgb: theme.primaryText))
                .onSubmit { onContinue(name) }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, Space.s3)
        .background(Color(rgb: theme.elevatedBackground),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .elevation(.level2)
    }

    /// Resign the first responder so the keyboard hides (on scroll / tap-outside).
    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

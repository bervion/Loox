import SwiftUI

/// Shows the generated recovery key once. The user must confirm they saved it
/// before continuing — it is the only way to recover a forgotten master password.
/// Layout mirrors the other onboarding steps: centered hero header, then the
/// key as the focal card, equal-width actions, and a card-backed confirmation.
struct EmergencyKitView: View {
    let recoveryKey: String
    let onContinue: () -> Void

    @Environment(AppEnvironment.self) private var env
    @State private var confirmedSaved = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                PolarisIcon(Icons.shield, size: 72)
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, Space.s8)
                OnboardingStepHeader(
                    "Save your Emergency Kit",
                    subtitle: "This recovery key can restore your vault if you forget your master password.",
                    style: .compact)

                keyCard
                    .padding(.horizontal, Space.s6)
                    .padding(.top, Space.s6)

                HStack(spacing: Space.s3) {
                    Button {
                        env.clipboard.copy(recoveryKey, label: "Recovery key", sensitive: true)
                    } label: {
                        Label("Copy", image: Icons.copy).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    if !recoveryKey.isEmpty {
                        ShareLink(item: recoveryKey) {
                            Label("Share", image: Icons.share).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                }
                .padding(.horizontal, Space.s6)
                .padding(.top, Space.s3)

                HStack(alignment: .center, spacing: Space.s3) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("I’ve saved my recovery key")
                            .vaultType(.headline)
                        Text("Store it somewhere safe and offline — it is shown only once.")
                            .vaultType(.footnote)
                            .themedForeground(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: Space.s2)
                    Toggle("", isOn: $confirmedSaved)
                        .labelsHidden()
                        .accessibilityLabel(Text("I’ve saved my recovery key"))
                }
                .padding(Space.gutter)
                .background(VaultColors.surface,
                            in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .padding(.horizontal, Space.s6)
                .padding(.top, Space.s6)
            }
            .padding(.bottom, Space.s6)
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: onContinue) {
                Text("Continue").frame(maxWidth: .infinity)
            }
            .buttonStyle(.themedProminent)
            .controlSize(.large)
            .disabled(!confirmedSaved || recoveryKey.isEmpty)
            .padding(.horizontal, Space.s6)
            .padding(.bottom, Space.gutter)
        }
    }

    private var keyCard: some View {
        Group {
            if recoveryKey.isEmpty {
                ProgressView().frame(maxWidth: .infinity, minHeight: 88)
            } else {
                Text(displayKey)
                    .font(.vaultCode(.title3, weight: .semibold))
                    .tracking(0.5)
                    .lineSpacing(Space.s2)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.s6)
                    .padding(.horizontal, Space.s3)
            }
        }
        .background(VaultColors.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(.quaternary, lineWidth: 1))
    }

    /// Split the hyphenated key into two balanced lines so it reads as a block
    /// instead of wrapping wherever the screen width happens to break it. The
    /// Copy button always uses the original single-line value.
    private var displayKey: String {
        let groups = recoveryKey.split(separator: "-")
        guard groups.count >= 4 else { return recoveryKey }
        let mid = (groups.count + 1) / 2
        return groups[..<mid].joined(separator: "-") + "-\n" + groups[mid...].joined(separator: "-")
    }
}

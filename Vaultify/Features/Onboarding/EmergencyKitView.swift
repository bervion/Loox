import SwiftUI

/// Shows the generated recovery key once. The user must confirm they saved it
/// before continuing — it is the only way to recover a forgotten master password.
/// Layout mirrors the other onboarding steps: top-aligned, left-aligned, Loox brand
/// mark, the key as the focal card, soft tinted actions, and a tappable confirm card.
struct EmergencyKitView: View {
    let recoveryKey: String
    let onContinue: () -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(\.appTheme) private var theme
    @State private var confirmedSaved = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s5) {
                VStack(alignment: .leading, spacing: Space.s3) {
                    // Loox brand mark instead of a generic shield — same identity as the
                    // other onboarding steps. Wide wordmark, so `size` is its height.
                    BrandLogoMark(size: 24)
                    Text("Save your Emergency Kit")
                        .vaultType(.screenTitle)
                    Text("This recovery key can restore your vault if you forget your master password.")
                        .vaultType(.subhead).themedForeground(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, Space.s2)

                VStack(spacing: Space.s3) {
                    keyCard
                    HStack(spacing: Space.s3) {
                        Button {
                            env.clipboard.copy(recoveryKey, label: "Recovery key", sensitive: true)
                        } label: {
                            tintedActionLabel("Copy", icon: Icons.copy)
                        }
                        .buttonStyle(.themedTinted)

                        if !recoveryKey.isEmpty {
                            ShareLink(item: recoveryKey) {
                                tintedActionLabel("Share", icon: Icons.share)
                            }
                            .buttonStyle(.themedTinted)
                        }
                    }
                }

                confirmationCard
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.s6)
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

    private func tintedActionLabel(_ title: LocalizedStringKey, icon: String) -> some View {
        Label { Text(title) } icon: { PolarisIcon(icon, size: Metric.iconInline) }
            .frame(maxWidth: .infinity)
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
        .background(Color(rgb: theme.elevatedBackground),
                    in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .elevation(.level2)
    }

    /// Tappable confirmation card — the whole card toggles the checkbox (a checkbox,
    /// not a switch, keeps a fixed footprint so long labels never break the layout).
    private var confirmationCard: some View {
        Button {
            confirmedSaved.toggle()
            Haptics.tap()
        } label: {
            HStack(alignment: .center, spacing: Space.s3) {
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text("I’ve saved my recovery key")
                        .vaultType(.headline)
                    Text("Store it somewhere safe and offline — it is shown only once.")
                        .vaultType(.footnote).themedForeground(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: Space.s2)
                checkbox
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(rgb: theme.elevatedBackground),
                        in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .elevation(.level2)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(confirmedSaved ? [.isSelected] : [])
    }

    private var checkbox: some View {
        RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
            .fill(confirmedSaved ? Color(rgb: theme.accent) : .clear)
            .overlay {
                if confirmedSaved {
                    PolarisIcon(Icons.check, size: 15)
                        .foregroundStyle(Color(rgb: theme.accentForeground))
                } else {
                    RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                        .strokeBorder(Color(rgb: theme.separator), lineWidth: 1.5)
                }
            }
            .frame(width: 26, height: 26)
            .animation(.easeInOut(duration: 0.15), value: confirmedSaved)
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

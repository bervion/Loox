import SwiftUI

/// Shows the generated recovery key once. The user must confirm they saved it
/// before continuing — it is the only way to recover a forgotten master password.
struct EmergencyKitView: View {
    let recoveryKey: String
    let onContinue: () -> Void

    @Environment(AppEnvironment.self) private var env
    @State private var confirmedSaved = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    PolarisIcon(Icons.shield, size: Metric.controlMedium).foregroundStyle(Color.accentColor)
                    Text("Save your Emergency Kit")
                        .font(.title.bold())
                    Text("This recovery key can restore your vault if you forget your master password. Store it somewhere safe and offline — it is shown only once.")
                        .font(.subheadline).themedForeground(.secondary)
                }
                .padding(.top, Space.s2)

                keyCard

                HStack(spacing: Space.s3) {
                    Button {
                        env.clipboard.copy(recoveryKey, label: "Recovery key", sensitive: true)
                    } label: {
                        Label("Copy", image: Icons.copy)
                    }
                    .buttonStyle(.bordered)

                    if !recoveryKey.isEmpty {
                        ShareLink(item: recoveryKey) {
                            Label("Share", image: Icons.share)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Toggle(isOn: $confirmedSaved) {
                    Text("I’ve saved my recovery key in a safe place")
                        .font(.subheadline)
                }
                .padding(.top, Space.s1)
            }
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

    private var keyCard: some View {
        Group {
            if recoveryKey.isEmpty {
                ProgressView().frame(maxWidth: .infinity, minHeight: 80)
            } else {
                Text(recoveryKey)
                    .font(.vaultCode(.title3, weight: .medium))
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.s6)
                    .padding(.horizontal, Space.s3)
            }
        }
        .background(VaultColors.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
}

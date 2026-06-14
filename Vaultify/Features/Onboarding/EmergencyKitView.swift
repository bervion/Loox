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
                    PolarisIcon(Icons.shield, size: 44).foregroundStyle(Color.accentColor)
                    Text("Save your Emergency Kit")
                        .font(.title.bold())
                    Text("This recovery key can restore your vault if you forget your master password. Store it somewhere safe and offline — it is shown only once.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.top, 8)

                keyCard

                HStack(spacing: 12) {
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
                .padding(.top, 4)
            }
            .padding(24)
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: onContinue) {
                Text("Continue").frame(maxWidth: .infinity)
            }
            .buttonStyle(.themedProminent)
            .controlSize(.large)
            .disabled(!confirmedSaved || recoveryKey.isEmpty)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
    }

    private var keyCard: some View {
        Group {
            if recoveryKey.isEmpty {
                ProgressView().frame(maxWidth: .infinity, minHeight: 80)
            } else {
                Text(recoveryKey)
                    .font(.vaultMono(.title3, weight: .medium))
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .padding(.horizontal, 12)
            }
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

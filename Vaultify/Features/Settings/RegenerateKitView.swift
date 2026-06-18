import SwiftUI

/// View / regenerate the Emergency Kit recovery key. Generating a new key
/// invalidates the previous one.
struct RegenerateKitView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var newKey = ""
    @State private var busy = false
    @State private var confirmRegenerate = false

    var body: some View {
        Form {
            Section {
                Label {
                    Text(env.session.hasRecoveryKit
                         ? "An Emergency Kit is set up for this vault."
                         : "No Emergency Kit yet — generate one to enable recovery.")
                } icon: {
                    PolarisIcon(Icons.shield).foregroundStyle(Color.accentColor)
                }
            } footer: {
                Text("The recovery key can restore your vault if you forget your master password.")
            }
            .listRowBackground(VaultColors.surface)

            if !newKey.isEmpty {
                Section {
                    Text(newKey)
                        .font(.vaultCode(.body, weight: .medium))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Space.s2)
                    Button { env.clipboard.copy(newKey, label: "Recovery key") } label: {
                        Label { Text("Copy") } icon: { PolarisIcon(Icons.copy) }
                    }
                    ShareLink(item: newKey) { Label { Text("Share") } icon: { PolarisIcon(Icons.share) } }
                } header: {
                    Text("Your new recovery key")
                } footer: {
                    Text("Store it somewhere safe and offline. It is shown only once.")
                }
                .listRowBackground(VaultColors.surface)
            }

            Section {
                Button {
                    if env.session.hasRecoveryKit { confirmRegenerate = true } else { Task { await regenerate() } }
                } label: {
                    Label { Text(env.session.hasRecoveryKit ? "Regenerate Kit" : "Generate Kit") } icon: { PolarisIcon(Icons.refresh) }
                }
                .disabled(busy)
            }
            .listRowBackground(VaultColors.surface)
        }
        .themedFormBackground()
        .navigationTitle("Emergency Kit")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if busy { ProgressView().controlSize(.large) } }
        .confirmationDialog("Regenerate recovery key?", isPresented: $confirmRegenerate, titleVisibility: .visible) {
            Button("Regenerate", role: .destructive) { Task { await regenerate() } }
        } message: {
            Text("Your previous recovery key will stop working.")
        }
    }

    private func regenerate() async {
        busy = true
        newKey = (try? await env.session.generateRecoveryKit()) ?? ""
        busy = false
        if !newKey.isEmpty { Haptics.success() }
    }
}

import SwiftUI

struct AboutView: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    PolarisIcon(Icons.shield, size: 56).foregroundStyle(Color.accentColor)
                    Text("Loox Password").font(.title2.bold())
                    Text("Version \(version) (\(build))").font(.footnote).themedForeground(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.s2)
            }
            .listRowBackground(VaultColors.surface)

            Section("How your data is protected") {
                aboutRow(Icons.key, "Argon2id key derivation",
                         "Your master password is stretched with a memory-hard function (64 MiB, t=3).")
                aboutRow(Icons.lockFill, "AES-256-GCM encryption",
                         "Every item is sealed individually before it touches storage.")
                aboutRow(Icons.person, "Secure Enclave biometrics",
                         "The Vault Key is released only after Face ID / Touch ID.")
                aboutRow(Icons.globe, "Zero backend",
                         "Nothing is sent to a server. Your vault never leaves the device unencrypted.")
            }
            .listRowBackground(VaultColors.surface)

            Section {
                Text("Loox collects no analytics and has no accounts. The only network request is the optional, anonymised breach check.")
                    .font(.footnote).themedForeground(.secondary)
            } header: {
                Text("Privacy")
            } footer: {
                Text("Includes the Argon2 reference implementation (CC0 / Apache-2.0).")
            }
            .listRowBackground(VaultColors.surface)
        }
        .themedFormBackground()
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func aboutRow(_ icon: String, _ title: LocalizedStringResource, _ detail: LocalizedStringResource) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            PolarisIcon(icon, size: 22).foregroundStyle(Color.accentColor).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium))
                Text(detail).font(.caption).themedForeground(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

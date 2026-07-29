import SwiftUI

struct PasskeyDetailSheet: View {
    let passkey: PasskeyInfo
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
    @State private var deleteError: String?

    var body: some View {
        VaultSheetScaffold(title: "Passkey",
                           leading: { EmptyView() },
                           trailing: { SheetDismissButton("Done") }) {
            Form {
                Section {
                    HStack(spacing: Space.s3) {
                        FaviconView(urlString: "https://\(passkey.relyingParty)", category: .login, size: 44)
                        VStack(alignment: .leading, spacing: Space.s1) {
                            Text(passkey.relyingParty)
                                .vaultType(.headline)
                                .themedForeground()
                                .lineLimit(1)
                            statusBadge
                        }
                    }
                    .padding(.vertical, Space.s1)
                }
                .listRowBackground(VaultColors.surface)

                Section {
                    LabeledContent("Username", value: passkey.userName)
                    LabeledContent("Created", value: passkey.createdAt.formatted(date: .abbreviated, time: .shortened))
                    if let lastUsed = passkey.lastUsedAt {
                        LabeledContent("Last used", value: lastUsed.formatted(date: .abbreviated, time: .shortened))
                    }
                    LabeledContent("Credential ID", value: passkey.credentialID.base64URLEncodedString())
                }
                .listRowBackground(VaultColors.surface)

                Section {
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label {
                            Text("Delete Passkey")
                        } icon: {
                            VaultIcon(Icons.trash)
                        }
                        .foregroundStyle(env.theme.active.color(.destructive))
                    }
                } footer: {
                    Text("Websites will no longer offer this passkey. You may lose access if it is your only sign-in method.")
                }
                .listRowBackground(VaultColors.surface)

                if let deleteError {
                    Text(deleteError).foregroundStyle(VaultColors.strengthWeak)
                }
            }
            .confirmationDialog("Delete this passkey?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete Passkey", role: .destructive) {
                    Haptics.error()
                    do {
                        try env.repository.deletePasskey(credentialID: passkey.credentialID)
                        dismiss()
                    } catch {
                        deleteError = "Couldn’t delete this passkey. Try again."
                    }
                }
            } message: {
                Text("This permanently destroys the private key and cannot be undone.")
            }
        }
    }

    /// Backup/sync status pill, mirroring how 1Password surfaces passkey portability.
    /// The BE/BS flags speak for the relying party's view (registrations mint
    /// BE=BS=1), but the user-facing promise is only honest while iCloud Sync
    /// actually carries the credential — with sync off, the truthful storage
    /// story is "this device" (manual encrypted exports aside).
    @ViewBuilder private var statusBadge: some View {
        switch passkey.backupStatus {
        case .backedUp where env.settings.iCloudSyncEnabled:
            badge(Text("Backed up"), icon: Icons.checkCircle, role: .success)
        case .backedUp:
            badge(Text("This device only"), icon: Icons.lockFill, role: .secondary)
        case .backupEligible:
            // SF icloud: the eligibility is specifically iCloud Keychain backup —
            // the generic sync arrows read as "refreshing", not the feature.
            badge(Text("Backup eligible"), systemName: "icloud", role: .secondary)
        case .deviceBound:
            badge(Text("This device only"), icon: Icons.lockFill, role: .secondary)
        }
    }

    private func badge(_ text: Text, icon: String? = nil, systemName: String? = nil,
                       role: ThemeRole) -> some View {
        HStack(spacing: Space.s1) {
            if let systemName {
                Image(systemName: systemName).font(.system(size: 12, weight: .medium))
            } else if let icon {
                VaultIcon(icon, size: 13)
            }
            text.vaultType(.caption)
        }
        .foregroundStyle(env.theme.active.color(role))
    }
}

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
                    LabeledContent("Website", value: passkey.relyingParty)
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
                            PolarisIcon(Icons.trash)
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
}

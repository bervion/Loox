import SwiftUI

/// Unlock then pick a login to fill (or create a new one). Items whose website matches the
/// requesting app/site are shown first. Unlock is handled by the shared `UnlockGate`.
struct AutoFillView: View {
    let serviceIdentifiers: [String]
    let preferredRecordID: String?
    let onSelect: (_ user: String, _ password: String) -> Void
    let onCancel: () -> Void

    var body: some View {
        UnlockGate(title: "Loox", onCancel: onCancel) { vaultKey in
            CredentialListView(serviceIdentifiers: serviceIdentifiers,
                               preferredRecordID: preferredRecordID,
                               vaultKey: vaultKey,
                               onSelect: onSelect)
        }
    }
}

/// Post-unlock login picker. Loads logins + the default-identity prefill once, then auto-selects a
/// preferred record (the QuickType path) or shows the list with a "Create new login" entry.
private struct CredentialListView: View {
    let serviceIdentifiers: [String]
    let preferredRecordID: String?
    let vaultKey: [UInt8]
    let onSelect: (_ user: String, _ password: String) -> Void

    @State private var items: [VaultItem] = []
    @State private var defaultUsername = ""
    @State private var loaded = false

    var body: some View {
        Group {
            if loaded { list } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .task {
            guard !loaded else { return }
            items = VaultReader.logins(vaultKey: vaultKey)
            defaultUsername = VaultReader.defaultIdentityUsername(vaultKey: vaultKey) ?? ""
            loaded = true
            if let preferredRecordID, let hit = items.first(where: { $0.id == preferredRecordID }) {
                select(hit)
            }
        }
    }

    private var list: some View {
        List {
            Section {
                NavigationLink {
                    CreateLoginView(host: serviceIdentifiers.first ?? "",
                                    defaultUsername: defaultUsername,
                                    vaultKey: vaultKey,
                                    onSaved: onSelect)
                } label: {
                    Text("＋ Create new login")
                }
            }
            if matched.isEmpty && !others.isEmpty {
                Section("All logins") { ForEach(others, content: row) }
            } else {
                if !matched.isEmpty { Section("For this app") { ForEach(matched, content: row) } }
                if !others.isEmpty { Section("Other logins") { ForEach(others, content: row) } }
            }
            if items.isEmpty { Text("No logins found").foregroundStyle(.secondary) }
        }
    }

    private var matched: [VaultItem] { items.filter { $0.matchesAutoFill(serviceIdentifiers: serviceIdentifiers) } }
    private var others: [VaultItem] {
        serviceIdentifiers.isEmpty ? items : items.filter { !$0.matchesAutoFill(serviceIdentifiers: serviceIdentifiers) }
    }

    private func row(_ item: VaultItem) -> some View {
        Button { select(item) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title.isEmpty ? "Untitled" : item.title).foregroundStyle(.primary)
                if let user = item.usernameField?.value, !user.isEmpty {
                    Text(user).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func select(_ item: VaultItem) {
        onSelect(item.usernameField?.value ?? "", item.passwordField?.value ?? "")
    }
}

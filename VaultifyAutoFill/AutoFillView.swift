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
                               onSelect: onSelect,
                               onCancel: onCancel)
        }
    }
}

/// One row in the picker — an owned vault login or a recipient-side shared credential
/// (from `SharedCredentialsCache`, never from `VaultStore`). Kept as an enum rather than
/// merging into `VaultItem` so a shared entry can never be mistaken for something this
/// extension could save/edit/re-seal.
private enum CredentialRow: Identifiable {
    case owned(VaultItem)
    case shared(SharedCredentialEntry)

    var id: String {
        switch self {
        case .owned(let item): return item.id
        case .shared(let entry): return entry.itemID
        }
    }

    var title: String {
        switch self {
        case .owned(let item): return item.title
        case .shared(let entry): return entry.title
        }
    }

    var username: String? {
        switch self {
        case .owned(let item): return item.usernameField?.value
        case .shared(let entry): return entry.username
        }
    }

    var isShared: Bool { if case .shared = self { return true }; return false }

    /// The grant's `askEachTime` TOTP field id, if this shared entry has one — drives
    /// the "Request code" affordance. Always nil for owned rows.
    var sharedTOTPFieldId: String? {
        if case .shared(let entry) = self { return entry.askEachTimeTOTPFieldId }
        return nil
    }

    var sharedItemID: String? {
        if case .shared(let entry) = self { return entry.itemID }
        return nil
    }

    func matches(serviceIdentifiers: [String]) -> Bool {
        switch self {
        case .owned(let item): return item.matchesAutoFill(serviceIdentifiers: serviceIdentifiers)
        case .shared(let entry): return entry.matchesAutoFill(serviceIdentifiers: serviceIdentifiers)
        }
    }

    var credential: (user: String, password: String) {
        switch self {
        case .owned(let item): return (item.usernameField?.value ?? "", item.passwordField?.value ?? "")
        case .shared(let entry): return (entry.username ?? "", entry.password ?? "")
        }
    }
}

/// Post-unlock login picker. Loads logins + the default-identity prefill once, then auto-selects a
/// preferred record (the QuickType path) or shows the list with a "Create new login" entry. Shared
/// credentials (`SharedCredentialsCache`) are merged in read-only, marked "· Shared".
private struct CredentialListView: View {
    let serviceIdentifiers: [String]
    let preferredRecordID: String?
    let vaultKey: [UInt8]
    let onSelect: (_ user: String, _ password: String) -> Void
    let onCancel: () -> Void

    @Environment(\.openURL) private var openURL
    @State private var items: [VaultItem] = []
    @State private var sharedEntries: [SharedCredentialEntry] = []
    @State private var defaultUsername = ""
    @State private var loaded = false

    var body: some View {
        Group {
            if loaded { list } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .task {
            guard !loaded else { return }
            items = VaultReader.logins(vaultKey: vaultKey)
            sharedEntries = SharedCredentialsCache.load(vaultKey: vaultKey)
            defaultUsername = VaultReader.defaultIdentityUsername(vaultKey: vaultKey) ?? ""
            loaded = true
            if let preferredRecordID {
                if let hit = sharedEntries.first(where: { $0.itemID == preferredRecordID }) {
                    onSelect(hit.username ?? "", hit.password ?? "")
                } else if let hit = items.first(where: { $0.id == preferredRecordID }) {
                    select(.owned(hit))
                }
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
            if rows.isEmpty { Text("No logins found").foregroundStyle(.secondary) }
        }
    }

    private var rows: [CredentialRow] {
        items.map(CredentialRow.owned) + sharedEntries.map(CredentialRow.shared)
    }
    private var matched: [CredentialRow] { rows.filter { $0.matches(serviceIdentifiers: serviceIdentifiers) } }
    private var others: [CredentialRow] {
        serviceIdentifiers.isEmpty ? rows : rows.filter { !$0.matches(serviceIdentifiers: serviceIdentifiers) }
    }

    private func row(_ row: CredentialRow) -> some View {
        HStack {
            Button { select(row) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title.isEmpty ? "Untitled" : row.title).foregroundStyle(.primary)
                    if let user = row.username, !user.isEmpty {
                        HStack(spacing: 4) {
                            Text(user).font(.caption).foregroundStyle(.secondary)
                            if row.isShared {
                                Text("· Shared").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } else if row.isShared {
                        Text("· Shared").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer()
            // Extensions have no CloudKit entitlement, so the request/response ceremony
            // can't run here — hand off to the app, which already has the Request
            // control on this shared item's detail screen (ItemDetailScreen).
            if row.sharedTOTPFieldId != nil, let itemID = row.sharedItemID {
                Button {
                    requestCode(itemID: itemID)
                } label: {
                    Label("Request code", systemImage: "arrow.up.right.square")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Request code"))
            }
        }
    }

    private func select(_ row: CredentialRow) {
        let credential = row.credential
        onSelect(credential.user, credential.password)
    }

    private func requestCode(itemID: String) {
        guard let url = SharedItemDeepLink.url(itemID: itemID) else { return }
        openURL(url)
        onCancel()
    }
}

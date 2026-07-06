import SwiftUI

/// Unlock then pick a login to fill (or create a new one). Items whose website matches the
/// requesting app/site are shown first. Unlock is handled by the shared `UnlockGate`.
struct AutoFillView: View {
    let serviceIdentifiers: [String]
    let preferredRecordID: String?
    /// Set when another flow already unlocked (passkey → password fallback):
    /// skips the second Face ID prompt for the same key.
    var presetKey: [UInt8]? = nil
    let onSelect: (_ user: String, _ password: String) -> Void
    let onCancel: () -> Void

    var body: some View {
        UnlockGate(title: "Loox", presetKey: presetKey, onCancel: onCancel) { vaultKey in
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

    var sharedEntry: SharedCredentialEntry? {
        if case .shared(let entry) = self { return entry }
        return nil
    }

    var ownedItem: VaultItem? {
        if case .owned(let item) = self { return item }
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
    /// Layer A for the shared-credential gate (INV-02): offline hides shared
    /// rows entirely; a satisfied path still needs the live check below.
    @State private var reachability = NetworkReachabilityMonitor()
    /// Non-nil while the pre-fill live grant check runs (INV-11).
    @State private var verifyingRowID: String?
    @State private var fillBlockedMessage: String?

    var body: some View {
        Group {
            if loaded { list } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .overlay { if verifyingRowID != nil { ProgressView().controlSize(.large) } }
        .disabled(verifyingRowID != nil)
        .alert(Text(verbatim: fillBlockedMessage ?? ""),
               isPresented: Binding(get: { fillBlockedMessage != nil },
                                    set: { if !$0 { fillBlockedMessage = nil } })) {
            Button("OK", role: .cancel) {}
        }
        .task {
            guard !loaded else { return }
            items = VaultReader.logins(vaultKey: vaultKey)
            sharedEntries = SharedCredentialsCache.load(vaultKey: vaultKey)
            defaultUsername = VaultReader.autofillPrefillUsername(vaultKey: vaultKey)
            loaded = true
            if let preferredRecordID {
                if let hit = sharedEntries.first(where: { $0.itemID == preferredRecordID }) {
                    // Same gated path as a manual tap — QuickType must not
                    // bypass the live check (INV-11).
                    select(.shared(hit))
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
            if !reachability.hasSatisfiedNetworkPath && !sharedEntries.isEmpty {
                Text("Shared items need an internet connection.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    /// Offline ⇒ shared credentials are not offered at all (absolute online
    /// gate — same rule the app applies).
    private var visibleSharedEntries: [SharedCredentialEntry] {
        reachability.hasSatisfiedNetworkPath ? sharedEntries : []
    }

    private var rows: [CredentialRow] {
        items.map(CredentialRow.owned) + visibleSharedEntries.map(CredentialRow.shared)
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
            // Alias reuse (owned rows only): the written-back "Private email" field
            // fills instead of the primary username. Read-only vault access — the
            // extension makes NO relay network calls; provisioning stays in the app.
            .contextMenu {
                if let item = row.ownedItem, let alias = item.privateEmailValue {
                    Button {
                        onSelect(alias, item.passwordField?.value ?? "")
                    } label: {
                        Label("Use private email", systemImage: "envelope.badge.shield.half.filled")
                    }
                }
            }
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
        // Shared credentials pass the authoritative gate right before the
        // fill (INV-11): live grant check, fail-closed on every outcome that
        // isn't a verified match. Owned items fill directly as before.
        if let entry = row.sharedEntry {
            guard reachability.hasSatisfiedNetworkPath else {
                fillBlockedMessage = appString("Shared items need an internet connection.")
                return
            }
            verifyingRowID = row.id
            Task {
                let outcome = await SharedGrantLiveCheck.verify(
                    zoneName: entry.zoneName, ownerName: entry.ownerName,
                    expectedGrantId: entry.grantId)
                verifyingRowID = nil
                switch outcome {
                case .authorized:
                    onSelect(entry.username ?? "", entry.password ?? "")
                case .revoked:
                    fillBlockedMessage = appString("The owner has revoked access to this item.")
                case .unavailable:
                    fillBlockedMessage = appString("Couldn't verify access right now.")
                }
            }
            return
        }
        let credential = row.credential
        onSelect(credential.user, credential.password)
    }

    private func requestCode(itemID: String) {
        guard let url = SharedItemDeepLink.url(itemID: itemID) else { return }
        openURL(url)
        onCancel()
    }
}

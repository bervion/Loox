import SwiftUI

/// 2FA AutoFill: unlock (via `UnlockGate`), then supply the current TOTP code for a login matching
/// the site. A single matching code is filled automatically; multiple show a picker.
struct OneTimeCodeView: View {
    let serviceIdentifiers: [String]
    let preferredRecordID: String?
    let onSelect: (_ code: String) -> Void
    let onCancel: () -> Void

    var body: some View {
        UnlockGate(title: "One-time code", onCancel: onCancel) { vaultKey in
            OneTimeCodeListView(serviceIdentifiers: serviceIdentifiers,
                                preferredRecordID: preferredRecordID,
                                vaultKey: vaultKey,
                                onSelect: onSelect)
        }
    }
}

/// Post-unlock TOTP picker. Loads TOTP-bearing items once; auto-fills a preferred record or a sole
/// match, else shows the list. Codes are generated on tap (never rendered inline) — see `provide`.
private struct OneTimeCodeListView: View {
    let serviceIdentifiers: [String]
    let preferredRecordID: String?
    let vaultKey: [UInt8]
    let onSelect: (_ code: String) -> Void

    @State private var items: [VaultItem] = []
    @State private var loaded = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if loaded { list } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .task {
            guard !loaded else { return }
            items = VaultReader.totpItems(vaultKey: vaultKey)
            loaded = true
            if let preferredRecordID, let hit = items.first(where: { $0.id == preferredRecordID }) {
                provide(hit); return
            }
            let m = matched
            if m.count == 1 { provide(m[0]) }
        }
    }

    private var list: some View {
        List {
            if matched.isEmpty && others.isEmpty {
                Text("No 2FA codes found").foregroundStyle(.secondary)
            }
            if !matched.isEmpty { Section("For this app") { ForEach(matched, content: row) } }
            if !others.isEmpty { Section("Other codes") { ForEach(others, content: row) } }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
        }
    }

    private var matched: [VaultItem] { items.filter { $0.matchesAutoFill(serviceIdentifiers: serviceIdentifiers) } }
    private var others: [VaultItem] {
        serviceIdentifiers.isEmpty ? items : items.filter { !$0.matchesAutoFill(serviceIdentifiers: serviceIdentifiers) }
    }

    /// Title + username only — never render the live code inline (avoids putting every 2FA code on
    /// one screen). The code is generated on tap in `provide`.
    private func row(_ item: VaultItem) -> some View {
        Button { provide(item) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title.isEmpty ? "Untitled" : item.title).foregroundStyle(.primary)
                if let user = item.usernameField?.value, !user.isEmpty {
                    Text(user).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func provide(_ item: VaultItem) {
        if let value = item.totpField?.value, let code = TOTPGenerator.code(forStoredValue: value) {
            onSelect(code)
        } else {
            errorMessage = appString("Couldn’t generate the code.")
        }
    }
}

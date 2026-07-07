import SwiftUI

/// Retirement/shutdown review: which of the ACTIVE persona's logins depend on
/// a private-email address (bound per-site aliases). Local records only —
/// works fully offline; scoped to the active persona so the partition
/// isolation holds (a strictAnonymous persona never surfaces another
/// persona's accounts here).
struct AffectedAccountsScreen: View {
    @Environment(AppEnvironment.self) private var env

    /// (login item, alias address) pairs for the active persona.
    private var affected: [(item: VaultItem, address: String)] {
        guard let persona = env.repository.activePersona else { return [] }
        return env.repository.aliases(forPersona: persona.id).compactMap { alias in
            guard let itemId = alias.boundItemId,
                  let item = env.repository.item(id: itemId) else { return nil }
            return (item, AliasAddress.display(localPart: alias.localPart, status: alias.status,
                                               relayDomain: alias.emailDomain))
        }
    }

    var body: some View {
        List {
            if affected.isEmpty {
                Section {
                    Text("No accounts here use a private address.")
                        .themedForeground(.secondary)
                }
                .listRowBackground(VaultColors.surface)
            } else {
                Section {
                    ForEach(affected, id: \.item.id) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: entry.item.title).vaultType(.body).themedForeground(.primary)
                            Text(verbatim: entry.address).vaultType(.caption).themedForeground(.secondary)
                        }
                    }
                } footer: {
                    Text("Update these accounts to a different email so you keep receiving password resets and important mail.")
                }
                .listRowBackground(VaultColors.surface)
            }
        }
        .navigationTitle(Text("Affected accounts"))
    }
}

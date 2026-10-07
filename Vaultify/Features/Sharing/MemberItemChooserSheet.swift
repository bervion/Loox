import SwiftUI

/// The chooser never keeps a decrypted item snapshot after selection. The
/// receiving ceremony re-reads ownership and eligibility using the item ID.
struct MemberItemChooserSheet: View {
    let title: LocalizedStringResource
    var needsSnapshotFields = true
    let onSelect: (String, String) -> Void
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var items: [VaultItem] {
        MemberFeatureProjection.eligibleItems(env.repository.memberOwnedItems,
                                              needsSnapshotFields: needsSnapshotFields)
            .filter { search.isEmpty || $0.title.localizedStandardContains(search) }
    }

    var body: some View {
        VaultSheetScaffold(title: title) {
            List {
                Section {
                    ForEach(items) { item in
                        Button {
                            guard let personaID = env.repository.activePersona?.id,
                                  env.repository.memberCanUseItem(item.id, personaID: personaID,
                                                                   needsSnapshotFields: needsSnapshotFields) else { return }
                            onSelect(item.id, personaID)
                            dismiss()
                        } label: {
                            HStack(spacing: Space.s3) {
                                VaultIcon(item.category.avatarIcon, size: Metric.iconUtility)
                                    .themedForeground(.iconSecondary)
                                Text(verbatim: item.title).vaultType(.body).themedForeground()
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: Space.s2)
                                VaultIcon(Icons.chevronRight, size: Metric.iconInline)
                                    .themedForeground(.iconSecondary)
                            }
                            .frame(minHeight: Metric.hitMin)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                    if items.isEmpty {
                        Text((search.isEmpty
                              ? LocalizedStringResource("No eligible items in this profile")
                              : LocalizedStringResource("No matching items")).inAppLocalized)
                            .vaultType(.body).themedForeground(.secondaryBody)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } footer: {
                    Text((needsSnapshotFields
                         ? LocalizedStringResource("Only saved items with readable fields appear here. Extra-protected values are excluded.")
                         : LocalizedStringResource("Choose a saved item from this profile. You will choose its permissions next.")).inAppLocalized)
                        .vaultType(.footnote).themedForeground(.secondaryBody)
                }
                .listRowBackground(VaultColors.surface)
            }
            .searchable(text: $search, prompt: Text("Search items"))
        }
    }
}

struct MemberItemSelection: Identifiable {
    let id: String
    let personaID: String
}

/// Operator/connectivity states remain separate from commerce. These copy
/// paths never offer an upgrade for a service outage.
enum MemberFeatureAvailability {
    static func message(_ state: CapabilityAvailability) -> String? {
        switch state {
        case .available: nil
        case .offline: appString("Connect to the internet to start sharing. Saved records remain available.")
        case .disabledByUser: appString("This feature is turned off in Connected Services.")
        case .maintenance: appString("Sharing is paused for maintenance. Your saved records remain available.")
        case .retired: appString("This service is no longer offered. Your saved items remain unchanged.")
        default: appString("Sharing is temporarily unavailable. You can try again later.")
        }
    }
}

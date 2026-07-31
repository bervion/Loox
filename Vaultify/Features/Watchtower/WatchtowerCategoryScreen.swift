import SwiftUI

/// Drill-down list for a single Watchtower finding group (compromised / reused /
/// weak / missing details). Rows are the app's ONE vault item row
/// (`VaultItemRowLink`: favicon, title, subtitle, swipe actions, push to
/// detail) — a bespoke row here drifted immediately (its own chevron on top of
/// the List disclosure, no favicon, no Space chip).
struct WatchtowerCategoryScreen: View {
    let title: LocalizedStringResource
    let items: [VaultItem]
    /// Privacy/context note pinned above the list (e.g. the k-anonymity
    /// explanation on the breach category). nil for categories without one.
    var infoNote: LocalizedStringKey? = nil

    var body: some View {
        List {
            if let infoNote {
                Section {
                    VaultInfoBanner(.info, icon: Icons.shield, text: infoNote)
                        .inList()
                }
            }
            Section {
                ForEach(items) { item in
                    VaultItemRowLink(item: item)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .themedFormBackground()
        .navigationTitle(title)
        .platformNavigationBarTitleDisplayMode(.inline)
    }
}

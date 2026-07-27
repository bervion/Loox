import SwiftUI

/// Drill-down list for a single Watchtower issue category (compromised / reused /
/// weak / missing 2FA). Each row taps through to the item's detail screen.
struct WatchtowerCategoryScreen: View {
    let title: LocalizedStringResource
    let issues: [VaultIssue]
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
            ForEach(issues) { issue in
                NavigationLink(value: issue.itemID) {
                    WatchtowerIssueRow(issue: issue)
                }
                .listRowBackground(VaultColors.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .themedFormBackground()
        .navigationTitle(title)
        .platformNavigationBarTitleDisplayMode(.inline)
    }
}

import SwiftUI

/// Drill-down list for a single Watchtower issue category (compromised / reused /
/// weak / missing 2FA). Each row taps through to the item's detail screen.
struct WatchtowerCategoryScreen: View {
    let title: LocalizedStringResource
    let issues: [VaultIssue]

    var body: some View {
        List {
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

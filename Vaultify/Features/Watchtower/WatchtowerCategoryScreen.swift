import SwiftUI

/// Drill-down list for a single Watchtower finding group (compromised / reused /
/// weak / missing details). Rows are the app's ONE vault item row
/// (`VaultItemRowLink`: favicon, title, subtitle, swipe actions, push to
/// detail) — a bespoke row here drifted immediately (its own chevron on top of
/// the List disclosure, no favicon).
struct WatchtowerCategoryScreen: View {
    let title: LocalizedStringResource
    let items: [VaultItem]
    /// Rule explanation folded into a collapsed banner above the list (e.g. why
    /// a missing website matters). nil for categories without one.
    var explanation: LocalizedStringResource? = nil

    var body: some View {
        List {
            // The banner lives in the section HEADER, not as a row: iOS masks a
            // List row's content to the section card's own (much larger) corner
            // radius, which re-clipped the banner's Radius.md corners into a
            // pill. Headers keep their content's own shape. Same register as
            // the item detail's warning banner: collapsed to one line, the
            // explanation one tap away.
            Section {
                ForEach(items) { item in
                    VaultItemRowLink(item: item)
                }
            } header: {
                if let explanation {
                    VaultExpandableBanner(.info, icon: Icons.shield,
                                          title: LocalizedStringResource("Why this matters").inAppLocalized,
                                          detail: explanation)
                        .textCase(nil)
                        .listRowInsets(EdgeInsets())
                        .padding(.bottom, Space.s2)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .themedFormBackground()
        .navigationTitle(title)
        .platformNavigationBarTitleDisplayMode(.inline)
    }
}

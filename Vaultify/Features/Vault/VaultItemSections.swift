import SwiftUI

/// Rows of a browse list, flat or grouped into month-year sections when the
/// active sort key is date-based. Lives inside the host screen's `List` so each
/// screen keeps its own chrome (search field, toolbar, identity header).
struct VaultItemSections: View {
    let items: [VaultItem]
    let sort: VaultSort
    var highlight: String? = nil

    var body: some View {
        if let sections = sort.monthSections(items) {
            ForEach(sections) { section in
                Section {
                    ForEach(section.items) { VaultItemRowLink(item: $0, highlight: highlight) }
                } header: {
                    Text(verbatim: section.title)
                        .vaultType(.sectionLabel)
                        .themedForeground(.tertiary)
                        .textCase(nil)
                }
            }
        } else {
            ForEach(items) { VaultItemRowLink(item: $0, highlight: highlight) }
        }
    }
}

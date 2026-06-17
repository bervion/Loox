import SwiftUI

/// Fixed (non-collapsing) screen header — a Threads-style title pinned at the top of a
/// screen with optional trailing actions. Place it ABOVE a `ScrollView` in a `VStack`
/// (not inside the scroll content) so it stays put while the content scrolls.
///
/// Title is `.screenTitle` (moderate — not the oversized system large title) and
/// left-aligned, matching the Home folder-switcher header for a consistent look.
struct VaultScreenHeader<Trailing: View>: View {
    let title: LocalizedStringResource
    @ViewBuilder let trailing: Trailing

    init(_ title: LocalizedStringResource, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: Space.s2) {
            Text(title)
                .vaultType(.screenTitle)
                .themedForeground(.primary)
                .lineLimit(1)
            Spacer(minLength: Space.s2)
            trailing
        }
        .frame(minHeight: Metric.hitMin)
        .padding(.horizontal, Space.gutter)
        .padding(.top, Space.s2)
        .padding(.bottom, Space.s2)
    }
}

extension VaultScreenHeader where Trailing == EmptyView {
    init(_ title: LocalizedStringResource) {
        self.init(title) { EmptyView() }
    }
}

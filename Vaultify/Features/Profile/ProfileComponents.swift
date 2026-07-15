import SwiftUI

/// Shared building blocks for the Profile hub (Apple-Account-style grouped nav rows).
/// Kept in one place so `ProfileScreen` and its detail screens compose identical chrome.

/// Grouped, elevated card wrapping a run of Profile rows.
struct ProfileGroupCard<Content: View>: View {
    @Environment(AppEnvironment.self) private var env
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(Color(rgb: env.theme.active.elevatedBackground))
            .vaultCornerRadius(Radius.lg)
            .elevation(.level1)
    }
}

/// 30pt rounded tinted tile holding a Polaris glyph — the leading art on a Profile row.
struct ProfileRowTile: View {
    @Environment(AppEnvironment.self) private var env
    let icon: String

    var body: some View {
        PolarisIcon(icon, size: 18)
            .themedForeground(.iconSecondary)
            .frame(width: 30, height: 30)
            .background(VaultColors.fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// A Profile nav row: leading tile + title + optional trailing value + chevron, pushing
/// `destination` onto the enclosing (navigator-hosted) stack.
struct ProfileNavRow<Destination: View>: View {
    let title: LocalizedStringResource
    let icon: String
    var value: String? = nil
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink { destination() } label: {
            HStack(spacing: Space.s3) {
                ProfileRowTile(icon: icon)
                Text(title).vaultType(.body).themedForeground()
                Spacer(minLength: Space.s2)
                if let value {
                    Text(verbatim: value).vaultType(.subhead).themedForeground(.secondary)
                }
                PolarisIcon(Icons.chevronRight, size: 14).themedForeground(.tertiary)
            }
            .padding(.horizontal, Space.s4)
            .frame(minHeight: Metric.rowHeight)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// Leading-inset hairline between two Profile rows (aligns under the title, past the tile).
struct ProfileRowDivider: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        Rectangle()
            .fill(Color(rgb: env.theme.active.separator))
            .frame(height: 0.5)
            .padding(.leading, Space.s4 + 30 + Space.s3)
    }
}

import SwiftUI

// MARK: - PressableSurfaceStyle

/// Button style that swaps a pressed background WITHOUT a `DragGesture`, so rows and
/// cards stay scrollable inside a `ScrollView` (a `minimumDistance: 0` drag gesture
/// captures the touch and blocks scrolling).
struct PressableSurfaceStyle: ButtonStyle {
    let theme: AppTheme
    var base: Color = .clear
    var cornerRadius: CGFloat = 0
    var bordered: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color(rgb: theme.surfacePressed) : base)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                if bordered {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color(rgb: theme.separator), lineWidth: 0.5)
                }
            }
            .animation(.easeOut(duration: Motion.fast), value: configuration.isPressed)
    }
}

// MARK: - CategoryRow

/// A tappable row representing one issue category in the "Cần xử lý" list.
/// Shows an icon tile, title, subtitle ("N mục…"), a count badge, and a chevron.
struct CategoryRow: View {
    let icon: String
    let tintRole: ThemeRole
    let title: LocalizedStringResource
    /// Dynamic subtitle (includes interpolated counts) — passed as a plain String
    /// because string-interpolated counts cannot be expressed as LocalizedStringResource.
    let subtitle: String
    let count: Int
    let onTap: () -> Void

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let theme = env.theme.active
        Button(action: onTap) {
            HStack(spacing: Space.s3) {
                // Icon tile: tinted rounded square (soft background variant)
                IconTileBadge(icon: icon, tintRole: tintRole, size: Metric.iconTile)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .vaultType(.body)
                        .themedForeground(.primary)
                        .lineLimit(1)
                    Text(verbatim: subtitle)
                        .vaultType(.footnote)
                        .themedForeground(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Count badge
                CountBadge(count: count, tintRole: tintRole)

                PolarisIcon(Icons.chevronRight, size: 14)
                    .themedForeground(.tertiary)
            }
            .padding(.horizontal, Space.s4)
            .frame(minHeight: Metric.rowHeight)
            .contentShape(.rect)
        }
        .buttonStyle(PressableSurfaceStyle(theme: theme))
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(subtitle))
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - IconTileBadge

/// Soft-tinted rounded square tile for category icons (mirrors DS "IconTile soft").
struct IconTileBadge: View {
    let icon: String
    let tintRole: ThemeRole
    var size: CGFloat = Metric.iconTile

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let tint = env.theme.active.color(tintRole)
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(tint.opacity(0.14))
            .frame(width: size, height: size)
            .overlay(
                PolarisIcon(icon, size: size * 0.58)
                    .foregroundStyle(tint)
            )
    }
}

// MARK: - CountBadge

/// Compact pill badge showing an integer count, tinted by role.
struct CountBadge: View {
    let count: Int
    let tintRole: ThemeRole

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let tint = env.theme.active.color(tintRole)
        Text("\(count)")
            .vaultType(.footnote)
            .fontWeight(.semibold)
            .foregroundStyle(tint)
            .padding(.horizontal, Space.s2)
            .padding(.vertical, 3)
            .background(tint.opacity(0.14), in: Capsule())
    }
}

// MARK: - WatchtowerIssueRow

/// A row representing a flagged item in a Watchtower category drill-down list.
struct WatchtowerIssueRow: View {
    let issue: VaultIssue

    var body: some View {
        HStack(spacing: Space.s3) {
            CategoryBadge(category: issue.category, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(issue.itemTitle).vaultType(.body).lineLimit(1)
                if let detail = issue.detail {
                    Text(detail).vaultType(.footnote).themedForeground(.secondary)
                }
            }
            Spacer(minLength: 8)
            PolarisIcon(Icons.chevronRight, size: 14).themedForeground(.tertiary)
        }
        .contentShape(.rect)
    }
}

import SwiftUI

// MARK: - PressableSurfaceStyle

/// Button style that swaps a pressed background WITHOUT a `DragGesture`, so rows and
/// cards stay scrollable inside a `ScrollView` (a `minimumDistance: 0` drag gesture
/// captures the touch and blocks scrolling).
struct PressableSurfaceStyle: ButtonStyle {
    let theme: AppTheme
    var base: Color = .clear
    var cornerRadius: CGFloat = 0

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color(rgb: theme.surfacePressed) : base)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .animation(.easeOut(duration: Motion.fast), value: configuration.isPressed)
    }
}

// MARK: - CategoryRow

/// Row content for one issue category in the "Cần xử lý" list: icon tile, title,
/// subtitle ("N mục…"), a count badge, and a chevron. A plain LABEL by design —
/// the host wraps it in a `NavigationLink` (the previous inner `Button` with an
/// empty action swallowed the link's tap, so the rows navigated nowhere).
struct CategoryRow: View {
    let icon: String
    let tintRole: ThemeRole
    let title: LocalizedStringResource
    /// Dynamic subtitle (includes interpolated counts) — passed as a plain String
    /// because string-interpolated counts cannot be expressed as LocalizedStringResource.
    let subtitle: String
    let count: Int

    var body: some View {
        HStack(spacing: Space.s3) {
            // Icon tile: tinted rounded square (soft background variant)
            IconTileBadge(icon: icon, tintRole: tintRole, size: Metric.iconTile)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .vaultType(.body)
                    .themedForeground(.primary)
                    // 2 lines: the longest EN title ("Set up two-factor
                    // authentication") clips at SE width with lineLimit(1) once
                    // the icon tile + count badge + chevron eat into the row.
                    .lineLimit(2)
                // Empty = single-line row. The audit group rows pass no subtitle
                // by design: "3 mục" under a title next to a "3" badge is the
                // same fact twice, and the doubled line made rows read heavy.
                if !subtitle.isEmpty {
                    Text(verbatim: subtitle)
                        .vaultType(.footnote)
                        .themedForeground(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Count badge
            CountBadge(count: count, tintRole: tintRole)

            VaultIcon(Icons.chevronRight, size: 14)
                .themedForeground(.tertiary)
        }
        .padding(.horizontal, Space.s4)
        .frame(minHeight: Metric.rowHeight)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(subtitle))
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
                VaultIcon(icon, size: size * 0.58)
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

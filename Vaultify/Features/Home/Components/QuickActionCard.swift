import SwiftUI

/// Home "Quick Actions" group card: a titled, described surface that gathers the four
/// secondary actions (Add, Generate, 2FA, Security) as a 2×2 grid of quiet grey tiles.
///
/// Each tile is a horizontal [duotone glyph + one-line label] control. The glyph is a
/// single-hue **accent duotone** — a full-opacity primary path over a 40% secondary path,
/// tinted through the template pipeline — so all four read as one calm family that follows
/// the user's chosen accent (DNA #8 "calm intelligence"), with no per-tile icon well.
///
/// Tiles are SOLID (`controlBackground`) — never glass — per the "no glass on content
/// rows" rule; only the outer card carries the standard level-1 elevation, matching the
/// other grouped sections on Home.
struct QuickActionsGroupCard: View {
    /// One tile. `icon` is a `dt_*` duotone asset name (see `Assets.xcassets/PolarisIcons`);
    /// `count`, when > 0, renders as a small trailing badge (live 2FA / issue counts).
    struct Item: Identifiable {
        let icon: String
        let label: LocalizedStringResource
        /// Per-type duotone hue (see the fixed palette on `QuickActionsGroupCard`).
        let tint: Color
        var count: Int? = nil
        /// Long-label tiles ("Generate Password", "2FA Codes" + badge) get a
        /// full-width row at compact width instead of squeezing into a half
        /// tile; roomy layouts keep the 2×2.
        var fullWidthWhenNarrow: Bool = false
        let action: () -> Void
        var id: String { icon }
    }

    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource
    /// Expects four items; laid out two per row (2×2).
    let items: [Item]

    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// Chunk the items into rows of two for the even 2×2 grid.
    private var rows: [[Item]] {
        stride(from: 0, to: items.count, by: 2).map {
            Array(items[$0 ..< min($0 + 2, items.count)])
        }
    }

    /// Compact width uses the split layout only when some tile asked for a
    /// full row; regular widths always keep the even 2×2.
    private var usesNarrowLayout: Bool {
        horizontalSizeClass != .regular && items.contains(where: \.fullWidthWhenNarrow)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .vaultType(.headline)
                    .themedForeground(.primary)
                Text(subtitle)
                    .vaultType(.subhead)
                    .themedForeground(.secondary)
            }

            // NON-lazy rows: a fixed set of four tiles never needs cell recycling,
            // and explicit stacks keep tile identity stable across Home re-renders.
            if usesNarrowLayout {
                // Compact split (owner 260726): the short-label pair shares one
                // grid row; the long-label tiles ("Generate Password",
                // "2FA Codes" + count badge) each take a full-width row —
                // half tiles scaled and truncated them on small phones.
                VStack(spacing: Space.s3) {
                    HStack(spacing: Space.s3) {
                        ForEach(items.filter { !$0.fullWidthWhenNarrow }) { item in
                            QuickActionTile(item: item, reduceMotion: reduceMotion)
                        }
                    }
                    ForEach(items.filter(\.fullWidthWhenNarrow)) { item in
                        QuickActionTile(item: item, reduceMotion: reduceMotion)
                    }
                }
            } else {
                VStack(spacing: Space.s3) {
                    ForEach(rows.indices, id: \.self) { row in
                        HStack(spacing: Space.s3) {
                            ForEach(rows[row]) { item in
                                QuickActionTile(item: item, reduceMotion: reduceMotion)
                            }
                        }
                    }
                }
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(rgb: env.theme.active.elevatedBackground))
        .vaultCornerRadius(Radius.lg)
        .elevation(.level1)
    }
}

// MARK: - Per-type duotone palette

extension QuickActionsGroupCard {
    /// Fixed, always-distinct hues per action type. Generate/2FA/Security use light/dark
    /// pairs tuned to clear ~3:1 as a glyph on `controlBackground`; Add uses the brand
    /// `looxBlue` so it matches the item-type picker's glyphs (the sheet Add opens).
    /// Fixed rather than the theme accent so the four never collapse to one color.
    static let addTint      = Color.looxBlue                                       // create — brand blue
    static let generateTint = VaultColors.dynamic(light: 0x0E8A7D, dark: 0x1DB8A6) // key — teal
    static let totpTint     = VaultColors.dynamic(light: 0x7C3AED, dark: 0x9D65F5) // codes — purple
    static let securityTint = VaultColors.dynamic(light: 0x0A8F3C, dark: 0x1DB356) // protected — green
}

/// A single grey quick-action tile: duotone glyph + one-line label, optional trailing count.
private struct QuickActionTile: View {
    let item: QuickActionsGroupCard.Item
    let reduceMotion: Bool

    @Environment(AppEnvironment.self) private var env

    private static let radius = Radius.md

    var body: some View {
        Button(action: item.action) {
            HStack(spacing: Space.s2) {
                // Per-type duotone: the tile's hue fills the full-opacity primary path,
                // the 40% secondary path softens it. Each hue clears ~3:1 on
                // `controlBackground` in light + dark (palette on the parent).
                PolarisIcon(item.icon, size: Metric.iconUtility)
                    .foregroundStyle(item.tint)

                Text(item.label)
                    .vaultType(.subhead)
                    .fontWeight(.semibold)
                    .themedForeground(.primary)
                    .lineLimit(1)
                    // Backstop only — the longest label ("Tạo mật khẩu") fits a half-width
                    // tile; DNA allows scale-down as a last resort, never below 0.7.
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 0)

                if let count = item.count, count > 0 {
                    countBadge(count)
                }
            }
            .padding(.horizontal, Space.s3)
            .padding(.vertical, Space.s3)
            .frame(maxWidth: .infinity, minHeight: Metric.hitMin)
            .background(Color(rgb: env.theme.active.controlBackground))
            .vaultCornerRadius(Self.radius)
            .contentShape(.rect(cornerRadius: Self.radius))
        }
        .buttonStyle(QuickActionPressStyle(reduceMotion: reduceMotion))
        .accessibilityLabel(accessibilityText)
    }

    /// Label plus the live count, so VoiceOver reads "2FA Codes, 5" rather than dropping it.
    private var accessibilityText: Text {
        if let count = item.count, count > 0 {
            return Text(item.label) + Text(verbatim: ", \(count)")
        }
        return Text(item.label)
    }

    /// Small trailing badge — counts are secondary, so they stay a quiet capsule in the
    /// tile's own hue (a 14% well + full-tint numerals), not a headline.
    private func countBadge(_ count: Int) -> some View {
        Text(verbatim: "\(min(count, 99))")
            .vaultType(.caption)
            .fontWeight(.bold)
            .foregroundStyle(item.tint)
            .padding(.horizontal, Space.s1)
            .frame(minWidth: 18, minHeight: 18)
            .background(item.tint.opacity(0.14), in: Capsule())
    }
}

/// Press-scale feedback matching the DS press = 0.97, collapsing under Reduce Motion.
private struct QuickActionPressStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? Motion.pressScale : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: Motion.fast),
                       value: configuration.isPressed)
    }
}

import SwiftUI

/// How an item's avatar is drawn. Encoded in `VaultItem.iconAsset`:
/// - `nil` → `.auto`: the category's duotone type icon (or the website favicon
///   for logins, resolved one level up in `FaviconView`).
/// - the reserved `monogramToken` → `.monogram`: initials on a title-derived color.
/// - any other value → `.custom`: that (duotone) icon asset.
enum ItemAvatarStyle: Equatable {
    case auto
    case monogram
    case custom(String)

    /// Reserved `iconAsset` value that means "letter avatar".
    static let monogramToken = "__monogram"

    static func resolve(_ iconAsset: String?) -> ItemAvatarStyle {
        // NB: match against the token with an explicit comparison — a bare
        // `case .some(monogramToken)` would bind, not compare, and swallow every
        // custom icon into `.monogram`.
        guard let asset = iconAsset else { return .auto }
        return asset == monogramToken ? .monogram : .custom(asset)
    }
}

/// Square item avatar (continuous corner) — the non-favicon part of the item
/// icon, shown in rows, the detail header, and the editor preview.
///
/// Resolution by `ItemAvatarStyle`:
/// - `.auto` → the category's duotone type icon (the default),
/// - `.monogram` → initials from the title (empty title falls back to the type icon),
/// - `.custom` → the chosen icon asset.
struct ItemThumbnail: View {
    let title: String
    let category: ItemCategory
    let iconAsset: String?
    var size: CGFloat = Metric.rowHeight

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
        Group {
            switch ItemAvatarStyle.resolve(iconAsset) {
            case .auto:
                largeIcon(category.avatarIcon)
            case .custom(let asset):
                largeIcon(asset)
            case .monogram:
                if let initials = Self.initials(from: title) {
                    letterAvatar(initials, shape: shape)
                } else {
                    largeIcon(category.avatarIcon)
                }
            }
        }
        .frame(width: size, height: size)
    }

    /// Type / custom icons drop the tinted badge tile and fill the whole avatar —
    /// the duotone glyph IS the avatar, at the category tint. (Only the monogram
    /// keeps a colored backing tile.)
    private func largeIcon(_ asset: String) -> some View {
        VaultIcon(asset, size: size).foregroundStyle(VaultColors.category(category))
    }

    private func letterAvatar(_ initials: String, shape: some Shape) -> some View {
        // White monogram on the title-derived colour (a generated avatar, like a favicon —
        // exempt from the no-raw-white rule). System rounded font scales with the square, so
        // it can't use a fixed Dynamic Type style without breaking the layout.
        shape.fill(Self.color(for: title))
            .overlay(
                Text(initials)
                    .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            )
    }

    /// Up to two uppercase initials from the title's first two words.
    static func initials(from title: String) -> String? {
        let words = title.split(separator: " ")
        guard let first = words.first?.first else { return nil }
        if words.count >= 2, let second = words[1].first {
            return String([first, second]).uppercased()
        }
        return String(first).uppercased()
    }

    /// Deterministic colour from the title (stable across launches — Swift's `hashValue`
    /// is randomised per process, so use a small FNV-style hash instead).
    static func color(for title: String) -> Color {
        var hash = 5381
        for scalar in title.unicodeScalars { hash = ((hash << 5) &+ hash) &+ Int(scalar.value) }
        let hue = Double(abs(hash) % 360) / 360
        // Mid brightness keeps white initials legible across every hue.
        return Color(hue: hue, saturation: 0.58, brightness: 0.66)
    }
}

import SwiftUI

/// Square item thumbnail (continuous corner) used in the editor / detail header.
///
/// Resolution order:
/// 1. explicit `iconAsset` override → tinted square + that Polaris icon,
/// 2. else a letter-avatar from the title (initials + a colour derived from the title),
/// 3. else (title still empty) the category icon, so a brand-new item still reads.
struct ItemThumbnail: View {
    let title: String
    let category: ItemCategory
    let iconAsset: String?
    var size: CGFloat = Metric.rowHeight

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
        Group {
            if let iconAsset {
                tintedIcon(iconAsset, shape: shape)
            } else if let initials = Self.initials(from: title) {
                letterAvatar(initials, shape: shape)
            } else {
                tintedIcon(category.iconAsset, shape: shape)
            }
        }
        .frame(width: size, height: size)
    }

    private func tintedIcon(_ asset: String, shape: some Shape) -> some View {
        let tint = VaultColors.category(category)
        return shape.fill(tint.opacity(0.18))
            .overlay(PolarisIcon(asset, size: size * 0.5).foregroundStyle(tint))
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

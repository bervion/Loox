import SwiftUI

/// The letter-avatar language shared by every surface that shows a vault item
/// without a favicon: the app's `ItemThumbnail`, the AutoFill picker, and (by
/// value parity) the Safari extension's web layer. One algorithm, one look —
/// an item keeps the same initials and the same hue wherever it appears.
enum MonogramAvatar {
    /// Up to two uppercase initials from the title's first two words.
    nonisolated static func initials(from title: String) -> String? {
        let words = title.split(separator: " ")
        guard let first = words.first?.first else { return nil }
        if words.count >= 2, let second = words[1].first {
            return String([first, second]).uppercased()
        }
        return String(first).uppercased()
    }

    /// Deterministic color from the title (stable across launches — Swift's
    /// `hashValue` is randomised per process, so use a small FNV-style hash).
    /// The Safari web layer mirrors this exact arithmetic with BigInt so the
    /// same item lands on the same hue in the popup and the inline menu.
    nonisolated static func color(for title: String) -> Color {
        var hash = 5381
        for scalar in title.unicodeScalars { hash = ((hash << 5) &+ hash) &+ Int(scalar.value) }
        let hue = Double(abs(hash) % 360) / 360
        // Mid brightness keeps white initials legible across every hue.
        return Color(hue: hue, saturation: 0.58, brightness: 0.66)
    }
}

/// Compact item avatar for surfaces that cannot reach the app's icon system
/// (the AutoFill extension links VaultifyCore only): white initials on the
/// title's stable hue, in the same continuous-corner square as `ItemThumbnail`.
/// Titles without a letter fall back to a neutral key glyph so the tile never
/// renders empty.
struct CredentialAvatarView: View {
    let title: String
    var size: CGFloat = 36

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
        Group {
            if let initials = MonogramAvatar.initials(from: title) {
                shape.fill(MonogramAvatar.color(for: title))
                    .overlay(
                        // A generated avatar, like a favicon — white content on
                        // the derived hue is the letter-avatar contract.
                        Text(initials)
                            .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                    )
            } else {
                shape.fill(Color.platformSystemGray5)
                    .overlay(
                        Image(systemName: "key.fill")
                            .font(.system(size: size * 0.38, weight: .medium))
                            .foregroundStyle(.secondary)
                    )
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

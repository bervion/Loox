import SwiftUI
import UIKit

/// Shows a website's favicon (login item avatar) when available + enabled,
/// falling back to the tinted category badge.
struct FaviconView: View {
    let urlString: String?
    let category: ItemCategory
    var size: CGFloat = 44

    @Environment(AppEnvironment.self) private var env
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                let shape = RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.16)
                    .frame(width: size, height: size)
                    .background(Self.tileColor, in: shape)
                    .overlay(shape.strokeBorder(Color(.separator).opacity(0.6), lineWidth: 0.5))
                    // Soft shadow lifts the white tile off the near-white card in light mode;
                    // invisible (and harmless) on the dark card. compositingGroup so the shadow
                    // traces the tile silhouette, not each child view.
                    .compositingGroup()
                    .shadow(color: .black.opacity(0.10), radius: 1.5, y: 1)
            } else {
                CategoryBadge(category: category, size: size)
            }
        }
        .task(id: urlString) { await load() }
    }

    /// Favicons are authored for light backgrounds, so the tile stays light in both
    /// appearances (a dark tile would swallow light/transparent logos). Dark mode uses a soft
    /// off-white to tame the glare; light mode keeps pure white and leans on the border +
    /// shadow to separate from the near-white card. (Favicon surfaces are exempt from the
    /// no-raw-white rule by design.)
    private static let tileColor = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(white: 0.90, alpha: 1) : .white
    })

    private func load() async {
        guard env.settings.showWebsiteIcons,
              let urlString, let host = FaviconService.host(from: urlString) else { image = nil; return }
        if let cached = env.faviconService.cachedIcon(host: host) { image = cached; return }
        image = await env.faviconService.fetchIcon(host: host)
    }
}

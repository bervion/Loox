import SwiftUI
import UIKit

/// Shows a website's favicon (login item avatar) when available + enabled,
/// falling back to the tinted category badge.
struct FaviconView: View {
    let urlString: String?
    let category: ItemCategory
    var size: CGFloat = 44
    /// When the item title carries the Loox brand (e.g. "Loox Account"), the avatar
    /// becomes the app icon instead of a favicon/badge. Pass the item title to opt in.
    var title: String? = nil

    @Environment(AppEnvironment.self) private var env
    @State private var image: UIImage?

    private var isBrandLoox: Bool {
        title?.range(of: "loox", options: .caseInsensitive) != nil
    }

    var body: some View {
        Group {
            if isBrandLoox {
                LooxAppIcon(size: size)
            } else if let image {
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

/// The Loox app-icon look, reused as an item avatar for brand items ("Loox Account").
/// Reproduces the app icon (`vaultify.icon`): the blue→cyan gradient behind the white
/// Loox wordmark. Colours match `Path.svg`'s gradient stops.
struct LooxAppIcon: View {
    var size: CGFloat = 44

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
        BrandLogoMark(size: size * 0.20, shadowRadius: 0, shadowY: 0)
            // Force the light (white) wordmark variant so it reads on the gradient.
            .environment(\.colorScheme, .dark)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: [Color(rgb: 0x1544FD), Color(rgb: 0x20BDFD)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: shape)
            .overlay(shape.strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5))
    }
}

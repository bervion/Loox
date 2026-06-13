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
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.16)
                    .frame(width: size, height: size)
                    .background(.white, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                            .strokeBorder(Color(.separator).opacity(0.4), lineWidth: 0.5)
                    )
            } else {
                CategoryBadge(category: category, size: size)
            }
        }
        .task(id: urlString) { await load() }
    }

    private func load() async {
        guard env.settings.showWebsiteIcons,
              let urlString, let host = FaviconService.host(from: urlString) else { image = nil; return }
        if let cached = env.faviconService.cachedIcon(host: host) { image = cached; return }
        image = await env.faviconService.fetchIcon(host: host)
    }
}

import SwiftUI
import Foundation

/// Shows a website's favicon (login item avatar) when available + enabled,
/// falling back to the tinted category badge.
struct FaviconView: View {
    let urlString: String?
    let category: ItemCategory
    var size: CGFloat = Metric.controlMedium
    /// When the item title carries the Loox brand (e.g. "Loox Account"), the avatar
    /// becomes the app icon instead of a favicon/badge. Pass the item title to opt in.
    var title: String? = nil
    /// The item's stored avatar choice (`nil` = auto, monogram token = letters,
    /// else a custom icon). A favicon is only fetched in the auto style.
    var iconAsset: String? = nil

    @Environment(AppEnvironment.self) private var env
    @Environment(\.faviconNetworkLookups) private var networkLookupsAllowed
    @State private var image: PlatformImage?
    /// True once this row has resolved its avatar at least once. A later run of
    /// `.task(id:)` therefore means the website value CHANGED, which in practice
    /// only happens while the user types in the editor — so that run is the one
    /// that gets debounced.
    @State private var hasResolvedOnce = false

    private var isBrandLoox: Bool { LooxAppIcon.isBrandTitle(title) }
    private var isAuto: Bool { ItemAvatarStyle.resolve(iconAsset) == .auto }

    var body: some View {
        Group {
            if isBrandLoox {
                LooxAppIcon(size: size)
            } else if isAuto, let image {
                let shape = RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                Image(platformImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.16)
                    .frame(width: size, height: size)
                    .background(Self.tileColor, in: shape)
                    .overlay(shape.strokeBorder(Color.platformSeparator.opacity(0.6), lineWidth: 0.5))
                    // Soft shadow lifts the white tile off the near-white card in light mode;
                    // invisible (and harmless) on the dark card. compositingGroup so the shadow
                    // traces the tile silhouette, not each child view.
                    .compositingGroup()
                    .shadow(color: .black.opacity(0.10), radius: 1.5, y: 1)
            } else {
                // Monogram / custom icon, or the auto type icon when no favicon.
                ItemThumbnail(title: title ?? "", category: category,
                              iconAsset: iconAsset, size: size)
            }
        }
        .task(id: faviconLoadKey) { await load() }
    }

    /// Only fetch a favicon in the auto style; monogram/custom never trigger a load.
    private var faviconLoadKey: String? { isAuto ? urlString : nil }

    /// Favicons are authored for light backgrounds, so the tile stays light in both
    /// appearances (a dark tile would swallow light/transparent logos). Dark mode uses a soft
    /// off-white to tame the glare; light mode keeps pure white and leans on the border +
    /// shadow to separate from the near-white card. (Favicon surfaces are exempt from the
    /// no-raw-white rule by design.)
    private static let tileColor = Color.platformDynamic(light: 0xFFFFFF, dark: 0xE6E6E6)

    private func load() async {
        // Read and set before the first suspension: a keystroke during a fetch
        // restarts this task, and that restart must already count as an edit.
        let isFirstResolve = !hasResolvedOnce
        hasResolvedOnce = true
        // `showWebsiteIcons` off hides the icons outright, cached ones included:
        // the setting is about what the avatar shows, not only about traffic.
        guard isAuto, env.settings.showWebsiteIcons,
              let urlString, let host = FaviconService.host(from: urlString) else {
            image = nil
            return
        }
        if let cached = env.faviconService.cachedIcon(host: host) { image = cached; return }
        // Drop the previous site's icon straight away: while a URL is being
        // edited, keeping it would label the new value with the old site.
        image = nil
        // First resolve is a render, so it stays instant. Anything after is an
        // edit, and each keystroke cancels this task before the delay is up, so
        // no half-typed host is ever sent.
        let debounce: Duration = isFirstResolve ? .zero : FaviconService.typingDebounce
        image = await env.faviconService.fetchIcon(
            host: host,
            allowNetwork: networkLookupsAllowed,
            debounce: debounce)
    }
}

/// Whether `FaviconView`s in this subtree may put a host on the network. Cached
/// icons still render when it is off.
private struct FaviconNetworkLookupsKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var faviconNetworkLookups: Bool {
        get { self[FaviconNetworkLookupsKey.self] }
        set { self[FaviconNetworkLookupsKey.self] = newValue }
    }
}

extension View {
    /// Opt a subtree out of favicon network lookups.
    ///
    /// Vault screens leave this on. A bulk preview turns it off: choosing an
    /// import file must not enumerate that file's hosts to a third party before
    /// the user has decided to import anything.
    func faviconNetworkLookups(_ allowed: Bool) -> some View {
        environment(\.faviconNetworkLookups, allowed)
    }
}

/// The Loox app-icon look, reused as an item avatar for brand items ("Loox Account").
/// Light mode uses a near-black tile (the blue→cyan gradient sank into the white card);
/// dark mode keeps the gradient from the app icon (`vaultify.icon`, `Path.svg` stops) —
/// a black tile would melt into the dark card there.
struct LooxAppIcon: View {
    var size: CGFloat = Metric.controlMedium
    @Environment(\.colorScheme) private var colorScheme

    /// Whether an item title carries the Loox brand (e.g. "Loox Account") — such items
    /// show the app-icon avatar everywhere an item avatar renders (Home, detail, TOTP…).
    nonisolated static func isBrandTitle(_ title: String?) -> Bool {
        title?.range(of: "loox", options: .caseInsensitive) != nil
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
        BrandLogoMark(size: size * 0.20, shadowRadius: 0, shadowY: 0)
            // Force the light (white) wordmark variant so it reads on the dark tile/gradient.
            .environment(\.colorScheme, .dark)
            .frame(width: size, height: size)
            .background(tileBackground, in: shape)
            .overlay(shape.strokeBorder(Color.platformSeparator.opacity(0.5), lineWidth: 0.5))
    }

    private var tileBackground: AnyShapeStyle {
        if colorScheme == .dark {
            AnyShapeStyle(LinearGradient(colors: [Color(rgb: 0x1544FD), Color(rgb: 0x20BDFD)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
        } else {
            AnyShapeStyle(Color(rgb: 0x0B0C0E))
        }
    }
}

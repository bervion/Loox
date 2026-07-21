import Foundation

/// Fetches and caches website favicons (for login item avatars) via Google's
/// `s2/favicons` endpoint (higher-resolution icons). Results are cached on disk
/// so each domain is fetched at most once.
///
/// Privacy: enabling this reveals the domains you have logins for to Google.
/// Gated by `SettingsStore.showWebsiteIcons`; the service is only called when
/// that's on (see `FaviconView`).
@MainActor @Observable final class FaviconService {
    @ObservationIgnored private var memory: [String: PlatformImage] = [:]
    @ObservationIgnored private var inFlight: Set<String> = []
    @ObservationIgnored private let cacheDir: URL

    init(cacheDirectory: URL? = nil) {
        cacheDir = cacheDirectory ?? SharedConfig.containerURL.appending(path: "Favicons")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    /// Normalised host for a URL string, or nil if it has none.
    static func host(from urlString: String) -> String? {
        var string = urlString.trimmingCharacters(in: .whitespaces)
        guard !string.isEmpty else { return nil }
        if !string.contains("://") { string = "https://" + string }
        guard let host = URL(string: string)?.host?.lowercased() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Synchronous cache lookup (memory then disk). No network.
    func cachedIcon(host: String) -> PlatformImage? {
        if let image = memory[host] { return image }
        let file = cacheDir.appending(path: "\(host).img")
        guard let data = try? Data(contentsOf: file), let image = PlatformImage.fromData(data) else { return nil }
        memory[host] = image
        return image
    }

    /// Fetch (if not cached/in-flight) and cache the favicon for `host`.
    func fetchIcon(host: String) async -> PlatformImage? {
        if let cached = cachedIcon(host: host) { return cached }
        guard !inFlight.contains(host),
              let url = URL(string: "https://www.google.com/s2/favicons?sz=128&domain=\(host)") else { return nil }
        inFlight.insert(host)
        defer { inFlight.remove(host) }

        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let image = PlatformImage.fromData(data) else { return nil }
        memory[host] = image
        try? data.write(to: cacheDir.appending(path: "\(host).img"))
        return image
    }
}

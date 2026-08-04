import Foundation
import CryptoKit

/// Fetches and caches website favicons (for login item avatars) via Google's
/// `s2/favicons` endpoint (higher-resolution icons). Results are cached on disk
/// so each domain is fetched at most once.
///
/// Privacy: enabling this reveals the domains you have logins for to Google.
/// `SettingsStore.showWebsiteIcons` decides whether the avatar shows a favicon
/// at all (`FaviconView`); this service additionally requires an explicit
/// `allowNetwork` on every lookup, which has no default, so no call site can
/// reach the network without saying so. Three further limits keep the
/// disclosure to the minimum the feature needs:
///
/// - the transport is ephemeral and cookieless, so Google's `NID` cookie cannot
///   tie the hosts to one persistent pseudonym across a session;
/// - a host is only sent once it parses as a complete, public domain name, so a
///   URL field mid-typing never emits prefixes or internal hostnames;
/// - cached bytes are filed under a keyed HMAC of the host, so the cache
///   directory is not a readable inventory of the user's accounts.
@MainActor @Observable final class FaviconService {
    /// How long a host that failed lookup is left alone before being tried
    /// again. Without it every offline or error-path host is re-requested on
    /// each render pass.
    static let failureCooldown: TimeInterval = 60 * 60

    /// Delay applied to a lookup that came from an edit in progress. Each
    /// keystroke cancels the previous `.task`, so the request only leaves the
    /// device once typing settles.
    static let typingDebounce: Duration = .milliseconds(600)

    /// Keychain account holding the 32-byte cache-name HMAC key.
    private static let keychainAccount = "favicon-cache-name-key"

    @ObservationIgnored private var memory: [String: PlatformImage] = [:]
    /// Live downloads keyed by host, so N rows sharing a host make one request
    /// and all N get the image (previously only the first row was served).
    @ObservationIgnored private var inFlight: [String: Task<PlatformImage?, Never>] = [:]
    @ObservationIgnored private var failures: [String: Date] = [:]
    @ObservationIgnored private let cacheDir: URL
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private let injectedKey: SymmetricKey?
    @ObservationIgnored private var resolvedKey: SymmetricKey?

    init(cacheDirectory: URL? = nil, session: URLSession? = nil, cacheKey: Data? = nil) {
        cacheDir = cacheDirectory ?? SharedConfig.containerURL.appending(path: "Favicons")
        self.session = session ?? Self.makeSession()
        injectedKey = cacheKey.map { SymmetricKey(data: $0) }
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        purgeForeignCacheFiles()
    }

    /// Ephemeral, cookieless, bounded. `URLSession.shared` files these requests
    /// in the app-wide cookie jar: Google's `NID` cookie would then link every
    /// host the user has a login for into one persistent pseudonym, which is a
    /// strictly larger disclosure than the domain names themselves.
    private static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        // We keep our own disk cache; a second one would only duplicate the bytes.
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        // An avatar is decoration: never let it hold a task open on a bad network.
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 15
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }

    // MARK: - Host parsing

    /// Normalised host for a URL string, or nil if it has none.
    nonisolated static func host(from urlString: String) -> String? {
        var string = urlString.trimmingCharacters(in: .whitespaces)
        guard !string.isEmpty else { return nil }
        if !string.contains("://") { string = "https://" + string }
        guard let host = URL(string: string)?.host?.lowercased() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Whether a host is complete and public enough to send to a third party.
    ///
    /// A URL field being typed produces a host on every keystroke ("g", "goo",
    /// "google.c"), and a home lab produces names that exist only on the user's
    /// LAN ("nas.local", "192.168.1.4"). Neither is useful to look up and both
    /// disclose something, so both are rejected before any request is formed.
    nonisolated static func isLookupEligible(_ host: String) -> Bool {
        guard (4...253).contains(host.count), host == host.lowercased() else { return false }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return false }
        for label in labels {
            guard (1...63).contains(label.count),
                  !label.hasPrefix("-"), !label.hasSuffix("-"),
                  label.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") })
            else { return false }
        }
        guard let tld = labels.last else { return false }
        // A numeric or single-character last label is an IP literal or a
        // half-typed suffix, never a registrable domain.
        let isPunycode = tld.hasPrefix("xn--")
        guard isPunycode || (tld.count >= 2 && tld.allSatisfy(\.isLetter)) else { return false }
        return !reservedSuffixes.contains(where: { host == $0 || host.hasSuffix(".\($0)") })
    }

    /// Names that resolve only inside a private network (or not at all). Sending
    /// them to a favicon service leaks internal topology and returns nothing.
    private nonisolated static let reservedSuffixes = [
        "local", "localhost", "localdomain", "internal", "intranet", "lan",
        "home", "home.arpa", "corp", "test", "example", "invalid", "onion", "i2p",
    ]

    // MARK: - Lookup

    /// Synchronous cache lookup (memory then disk). No network.
    func cachedIcon(host: String) -> PlatformImage? {
        if let image = memory[host] { return image }
        guard let data = try? Data(contentsOf: fileURL(for: host)),
              let image = PlatformImage.fromData(data) else { return nil }
        memory[host] = image
        return image
    }

    /// Fetch (if permitted, and not cached, cooling down, or already in flight)
    /// and cache the favicon for `host`.
    ///
    /// - Parameters:
    ///   - allowNetwork: whether this subtree may reach the network at all.
    ///     Deliberately has no default: a call site must state it.
    ///   - debounce: delay before the request. Cancelling during the delay (the
    ///     next keystroke does exactly that) means no request is ever made.
    func fetchIcon(host: String, allowNetwork: Bool, debounce: Duration = .zero) async -> PlatformImage? {
        if let cached = cachedIcon(host: host) { return cached }
        guard allowNetwork, Self.isLookupEligible(host), !isCoolingDown(host) else { return nil }
        if let existing = inFlight[host] { return await existing.value }

        if debounce > .zero {
            do { try await Task.sleep(for: debounce) } catch { return nil }
        }
        guard !Task.isCancelled else { return nil }
        // The wait gave another row time to finish, or to start, the same host.
        if let cached = cachedIcon(host: host) { return cached }
        if let existing = inFlight[host] { return await existing.value }

        let task = Task<PlatformImage?, Never> { [self] in
            defer { inFlight[host] = nil }
            guard let data = await Self.download(host: host, session: self.session),
                  let image = PlatformImage.fromData(data) else {
                failures[host] = Date()
                return nil
            }
            // `clearCache()` cancels in-flight work; a response that landed just
            // before an erase must not re-create the file that was just removed.
            guard !Task.isCancelled else { return nil }
            failures[host] = nil
            memory[host] = image
            // Every other write in this app is atomic and protected; a favicon
            // is low value on its own but the file's existence still says the
            // user has an account on that site.
            try? data.write(to: fileURL(for: host), options: [.atomic, .completeFileProtection])
            return image
        }
        inFlight[host] = task
        return await task.value
    }

    /// Drop every cached icon, the in-memory state, and the name key.
    ///
    /// Called by the vault-erase path and by the settings toggle. The filenames
    /// are hashed, but the surviving set of files is still a count of the sites
    /// the erased vault held logins for, so the key is rotated with the bytes:
    /// a later cache cannot be correlated with this one.
    func clearCache() {
        for task in inFlight.values { task.cancel() }
        inFlight.removeAll()
        memory.removeAll()
        failures.removeAll()
        let manager = FileManager.default
        let files = (try? manager.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil)) ?? []
        for file in files { try? manager.removeItem(at: file) }
        guard injectedKey == nil else { return }
        resolvedKey = nil
        _ = KeychainStore.delete(account: Self.keychainAccount)
    }

    // MARK: - Internals

    private nonisolated static func download(host: String, session: URLSession) async -> Data? {
        // `isLookupEligible` restricts the host to [a-z0-9.-], so it needs no escaping.
        guard let url = URL(string: "https://www.google.com/s2/favicons?sz=128&domain=\(host)"),
              let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              !data.isEmpty else { return nil }
        return data
    }

    private func isCoolingDown(_ host: String, now: Date = .now) -> Bool {
        guard let failedAt = failures[host] else { return false }
        guard now.timeIntervalSince(failedAt) < Self.failureCooldown else {
            failures[host] = nil
            return false
        }
        return true
    }

    /// Cache file for a host: a keyed HMAC, not the host. The previous
    /// `<host>.img` naming made the directory listing a plaintext inventory of
    /// the user's accounts, readable by anything with App Group access.
    private func fileURL(for host: String) -> URL {
        let mac = HMAC<SHA256>.authenticationCode(for: Data(host.utf8), using: nameKey())
        let name = mac.prefix(16).map { String(format: "%02x", $0) }.joined()
        return cacheDir.appending(path: "\(name).img")
    }

    private func nameKey() -> SymmetricKey {
        if let injectedKey { return injectedKey }
        if let resolvedKey { return resolvedKey }
        let key = SymmetricKey(data: Self.loadOrCreateNameKey())
        resolvedKey = key
        return key
    }

    /// A Keychain read failure degrades to a session-scoped key: the cache
    /// misses and refetches, which is strictly better than falling back to
    /// plaintext names.
    private static func loadOrCreateNameKey() -> Data {
        if let data = try? KeychainStore.get(account: keychainAccount), data.count == 32 { return data }
        let fresh = CryptoRandom.data(32)
        try? KeychainStore.set(fresh, account: keychainAccount)
        return fresh
    }

    /// Shape of a current cache filename: 32 lowercase hex characters + `.img`.
    nonisolated static func isHashedCacheName(_ name: String) -> Bool {
        guard name.hasSuffix(".img") else { return false }
        let stem = name.dropLast(4)
        return stem.count == 32 && stem.allSatisfy { "0123456789abcdef".contains($0) }
    }

    /// Anything that is not a current hashed name is a pre-hash `<host>.img`
    /// file, i.e. exactly the plaintext listing this cache stopped keeping.
    /// Removed on construction so an upgrade does not carry the old inventory
    /// forward; the icons themselves refetch on demand.
    private func purgeForeignCacheFiles() {
        let manager = FileManager.default
        let names = (try? manager.contentsOfDirectory(atPath: cacheDir.path)) ?? []
        for name in names where !Self.isHashedCacheName(name) {
            try? manager.removeItem(at: cacheDir.appending(path: name))
        }
    }
}

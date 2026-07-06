import Foundation

/// Fetch → verify → cache → apply for the signed capability manifest.
/// NEVER called at startup on the critical path (INV-CAP-02): C3's screen-open
/// probe / foreground refresh drives it, and every failure degrades to the
/// cached manifest → bundled defaults (all-active). A fetch failure of any
/// kind (404 included) is NOT a policy signal (INV-CAP-07).
@MainActor final class CapabilityManifestClient {

    /// Primary source (Cloudflare). Secondary (independent failure domain,
    /// CloudKit public DB) lands when the BE publishes there — same signed
    /// bytes, one semantic manifest.
    static let primaryURL = URL(string: "https://api-relay.looxpassword.com/v1/capabilities/manifest")!

    private let defaults: UserDefaults
    private let trustedKeys: [String: Data]
    private weak var store: CapabilityStore?

    private let cacheKey = "capability_manifest_envelope"
    private let versionKey = "capability_manifest_highest_version"

    init(store: CapabilityStore,
         trustedKeys: [String: Data] = CapabilityManifestVerifier.bundledTrustedKeys,
         defaults: UserDefaults = .standard) {
        self.store = store
        self.trustedKeys = trustedKeys
        self.defaults = defaults
    }

    private(set) var highestAcceptedVersion: UInt64 {
        get { UInt64(defaults.string(forKey: versionKey) ?? "") ?? 0 }
        set { defaults.set(String(newValue), forKey: versionKey) }
    }

    /// Re-verify and apply the cached manifest (e.g. after relaunch). A cache
    /// that no longer verifies (expired, key removed) is dropped silently —
    /// the store keeps its last per-response verified modes.
    func applyCached(now: Date = .now) {
        guard let cached = defaults.data(forKey: cacheKey) else { return }
        guard let manifest = try? CapabilityManifestVerifier.verify(
            envelopeData: cached, trustedKeys: trustedKeys, now: now,
            highestAcceptedVersion: 0) else {   // rollback vs SELF is meaningless
            defaults.removeObject(forKey: cacheKey)
            return
        }
        apply(manifest)
    }

    /// Fetch the primary source and, if it verifies, persist + apply.
    /// All failures are silent by design — availability then derives from
    /// cache/bundled defaults + live per-response signals.
    func refresh(now: Date = .now) async {
        guard !trustedKeys.isEmpty else { return }   // B3 not frozen yet — dormant
        var request = URLRequest(url: Self.primaryURL)
        request.timeoutInterval = 15
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return }
        accept(envelopeData: data, now: now)
    }

    /// Verification + anti-rollback + persistence, separated for tests.
    @discardableResult
    func accept(envelopeData: Data, now: Date = .now) -> Bool {
        guard let manifest = try? CapabilityManifestVerifier.verify(
            envelopeData: envelopeData, trustedKeys: trustedKeys, now: now,
            highestAcceptedVersion: highestAcceptedVersion) else { return false }
        highestAcceptedVersion = manifest.manifestVersion
        defaults.set(envelopeData, forKey: cacheKey)
        apply(manifest)
        return true
    }

    private func apply(_ manifest: CapabilityManifest) {
        for id in CapabilityID.allCases {
            guard let entry = manifest.entry(for: id) else { continue }
            store?.applyOperatorPolicy(id, .init(mode: entry.mode, retryAfter: entry.retryAfter))
        }
    }
}

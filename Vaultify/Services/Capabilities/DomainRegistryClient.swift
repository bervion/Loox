import Foundation

/// Fetch → verify → cache → apply for the signed auxiliary-domain registry
/// (`LOOX-DOMAIN-REGISTRY-V1`). Same silent-failure posture as the capability
/// manifest client: never on the startup critical path, and every failure —
/// 404 (owner hasn't published yet), timeout, bad signature, wrong env,
/// rollback — quietly keeps the last verified set (or the bundled fallback).
@MainActor @Observable final class DomainRegistryClient {

    /// The env this build accepts — bound INSIDE the signed payload, so a
    /// staging registry can't steer a production install (or vice versa).
    /// The fetch URL follows: each env serves its own signed document, and a
    /// cross-served one fails `wrongEnvironment` regardless of its signature.
    #if DEBUG
    static let primaryURL = URL(string: "https://config-staging.looxpassword.com/v1/domain-registry")!
    nonisolated static let expectedEnv = "staging"
    #else
    static let primaryURL = URL(string: "https://config.looxpassword.com/v1/domain-registry")!
    nonisolated static let expectedEnv = "production"
    #endif

    /// Bumped on every applied registry. The trusted set itself lives in the
    /// nonisolated `AuxiliaryDomainRegistry` (model code reads it lock-free);
    /// views read THIS so a registry that arrives after first render still
    /// re-renders the domain picker instead of silently never appearing.
    private(set) var appliedRevision = 0

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let trustedKeys: [String: Data]

    @ObservationIgnored private let cacheKey = "domain_registry_v1"
    @ObservationIgnored private let versionKey = "domain_registry_highest_version"

    init(trustedKeys: [String: Data] = CapabilityManifestVerifier.bundledTrustedKeys,
         defaults: UserDefaults = .standard) {
        self.trustedKeys = trustedKeys
        self.defaults = defaults
    }

    @ObservationIgnored private(set) var highestAcceptedVersion: UInt64 {
        get { UInt64(defaults.string(forKey: versionKey) ?? "") ?? 0 }
        set { defaults.set(String(newValue), forKey: versionKey) }
    }

    /// Re-verify and apply the cached registry (relaunch path). A cache that
    /// no longer verifies (expired, key retired) is dropped; the app then
    /// runs on the bundled domain set.
    func applyCached(now: Date = .now) {
        guard let cached = defaults.data(forKey: cacheKey) else { return }
        guard let document = try? DomainRegistryVerifier.verify(
            documentData: cached, trustedKeys: trustedKeys, expectedEnv: Self.expectedEnv,
            now: now, highestAcceptedVersion: 0) else {   // rollback-vs-self is meaningless
            defaults.removeObject(forKey: cacheKey)
            return
        }
        AuxiliaryDomainRegistry.applyRemote(document.descriptors)
        appliedRevision += 1
    }

    func refresh(now: Date = .now) async {
        guard !trustedKeys.isEmpty else { return }
        var request = URLRequest(url: Self.primaryURL)
        request.timeoutInterval = 15
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return }
        accept(documentData: data, now: now)
    }

    /// Verification + strict anti-rollback + persistence; separated for tests.
    @discardableResult
    func accept(documentData: Data, now: Date = .now) -> Bool {
        guard let document = try? DomainRegistryVerifier.verify(
            documentData: documentData, trustedKeys: trustedKeys, expectedEnv: Self.expectedEnv,
            now: now, highestAcceptedVersion: highestAcceptedVersion) else { return false }
        highestAcceptedVersion = document.registryVersion
        defaults.set(documentData, forKey: cacheKey)
        AuxiliaryDomainRegistry.applyRemote(document.descriptors)
        appliedRevision += 1
        return true
    }
}

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
    nonisolated static let primaryURL = URL(string: "https://config.looxpassword.com/v1/domain-registry")!
    nonisolated static let expectedEnv = RelayConfig.environment

    /// Bumped on every applied registry. The trusted set itself lives in the
    /// nonisolated `AuxiliaryDomainRegistry` (model code reads it lock-free);
    /// views read THIS so a registry that arrives after first render still
    /// re-renders the domain picker instead of silently never appearing.
    private(set) var appliedRevision = 0

    @ObservationIgnored private let trustedKeys: [String: Data]
    @ObservationIgnored private let controlStore: SignedControlPlaneStore
    @ObservationIgnored private let registryURL: URL
    @ObservationIgnored private let environment: String
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored var onApplied: (() -> Void)?

    init(trustedKeys: [String: Data] = CapabilityManifestVerifier.bundledTrustedKeys,
         defaults: UserDefaults = .standard,
         registryURL: URL = DomainRegistryClient.primaryURL,
         environment: String = DomainRegistryClient.expectedEnv,
         session: URLSession = .shared) {
        self.trustedKeys = trustedKeys
        self.registryURL = registryURL
        self.environment = environment
        self.session = session
        self.controlStore = SignedControlPlaneStore(
            family: .domainRegistry, env: environment,
            legacyVersionKey: "domain_registry_highest_version",
            legacyCacheKey: "domain_registry_v1", defaults: defaults)
    }

    @ObservationIgnored var highestAcceptedVersion: UInt64 { controlStore.highestVersion }

    /// Re-verify and apply the cached registry (relaunch path). A cache that
    /// no longer verifies (expired, key retired) has its bytes dropped (high-water
    /// preserved); the app then runs on the bundled domain set.
    func applyCached(now: Date = .now) {
        guard let cached = controlStore.currentBytes else { return }
        guard let document = try? DomainRegistryVerifier.verify(
            documentData: cached, trustedKeys: trustedKeys, expectedEnv: environment,
            now: now, highestAcceptedVersion: 0) else {   // rollback-vs-self is meaningless
            controlStore.dropBytesKeepingHighWater()
            return
        }
        controlStore.backfillCanonicalHashIfMissing(canonicalBytes: document.transcript)
        AuxiliaryDomainRegistry.applyRemote(document.descriptors, signedEnvelope: cached)
        appliedRevision += 1
        onApplied?()
    }

    @discardableResult
    func refresh(now: Date = .now) async -> Bool {
        guard !trustedKeys.isEmpty else { return false }
        // The signed store is our offline fallback. An explicit refresh must
        // reach the control plane rather than reuse an HTTP-cached lifecycle.
        var request = URLRequest(url: registryURL, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.timeoutInterval = 15
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return false }
        guard accept(documentData: data, now: now) else { return false }
        controlStore.markRefreshSuccess(now: now)
        return true
    }

    /// Verification + anti-rollback + atomic persistence; separated for tests.
    @discardableResult
    func accept(documentData: Data, now: Date = .now) -> Bool {
        guard let document = try? DomainRegistryVerifier.verify(
            documentData: documentData, trustedKeys: trustedKeys, expectedEnv: environment,
            now: now, highestAcceptedVersion: controlStore.highestVersion) else { return false }
        guard controlStore.reconcile(incomingVersion: document.registryVersion,
                                     canonicalBytes: document.transcript,
                                     signedBytes: documentData, now: now) == .accepted else { return false }
        AuxiliaryDomainRegistry.applyRemote(document.descriptors, signedEnvelope: documentData)
        appliedRevision += 1
        onApplied?()
        return true
    }
}

extension DomainRegistryClient: RefreshableControlPlaneDocument {
    var controlPlaneFamily: SignedControlPlaneStore.Family { .domainRegistry }
    var lastRefreshMs: Int64? { controlStore.lastRefreshMs }
    var hasVerifiedCache: Bool { controlStore.hasVerifiedCache }
}

import Foundation

/// Fetch → verify → cache → apply for the signed Quick View runtime
/// session-signer endorsement (`LOOX-QUICK-VIEW-SIGNER-KEYSET-V1`). Same
/// silent-failure posture as the capability manifest / domain registry
/// clients: never on the startup critical path, and every failure — 404
/// (not published yet), timeout, bad signature, wrong env, rollback —
/// quietly keeps the last verified document (or `nil`, meaning Quick View
/// session verification cannot proceed until one is fetched).
@MainActor @Observable final class QuickViewSignerKeysetClient {

    /// The env this build accepts — bound INSIDE the signed payload, same
    /// convention as `DomainRegistryClient.expectedEnv`.
    #if DEBUG
    static let primaryURL = URL(string: "https://config-staging.looxpassword.com/v1/quick-view/signer-keyset")!
    nonisolated static let expectedEnv = "staging"
    #else
    static let primaryURL = URL(string: "https://config.looxpassword.com/v1/quick-view/signer-keyset")!
    nonisolated static let expectedEnv = "production"
    #endif

    /// The last verified, currently-applied keyset — `nil` until the first
    /// successful fetch/cache-restore. `QuickViewSessionEnvelopeVerifier`
    /// callers must treat `nil` as "cannot verify a session yet", never as
    /// an empty-but-trusted key set.
    private(set) var current: QuickViewSignerKeysetDocument?

    @ObservationIgnored private let trustedKeys: [String: Data]
    @ObservationIgnored private let controlStore: SignedControlPlaneStore

    init(trustedKeys: [String: Data] = CapabilityManifestVerifier.bundledTrustedKeys,
         defaults: UserDefaults = .standard) {
        self.trustedKeys = trustedKeys
        self.controlStore = SignedControlPlaneStore(
            family: .quickViewSignerKeyset, env: Self.expectedEnv,
            legacyVersionKey: "quick_view_signer_keyset_highest_version",
            legacyCacheKey: "quick_view_signer_keyset_v1", defaults: defaults)
    }

    @ObservationIgnored var highestAcceptedVersion: UInt64 { controlStore.highestVersion }

    /// Re-verify and apply the cached keyset (relaunch path). A cache that no
    /// longer verifies (expired, root key retired) has its bytes dropped (high-water
    /// preserved); Quick View session verification then fails closed until a fresh
    /// fetch succeeds.
    func applyCached(now: Date = .now) {
        guard let cached = controlStore.currentBytes else { return }
        guard let document = try? QuickViewSignerKeysetVerifier.verify(
            documentData: cached, trustedKeys: trustedKeys, expectedEnv: Self.expectedEnv,
            now: now, highestAcceptedVersion: 0) else {   // rollback-vs-self is meaningless
            controlStore.dropBytesKeepingHighWater()
            return
        }
        controlStore.backfillCanonicalHashIfMissing(canonicalBytes: document.transcript)
        current = document
    }

    @discardableResult
    func refresh(now: Date = .now) async -> Bool {
        guard !trustedKeys.isEmpty else { return false }
        var request = URLRequest(url: Self.primaryURL)
        request.timeoutInterval = 15
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return false }
        guard accept(documentData: data, now: now) else { return false }
        controlStore.markRefreshSuccess(now: now)
        return true
    }

    /// Verification + anti-rollback + atomic persistence; separated for tests.
    @discardableResult
    func accept(documentData: Data, now: Date = .now) -> Bool {
        guard let document = try? QuickViewSignerKeysetVerifier.verify(
            documentData: documentData, trustedKeys: trustedKeys, expectedEnv: Self.expectedEnv,
            now: now, highestAcceptedVersion: controlStore.highestVersion) else { return false }
        guard controlStore.reconcile(incomingVersion: document.keysetVersion,
                                     canonicalBytes: document.transcript,
                                     signedBytes: documentData, now: now) == .accepted else { return false }
        current = document
        return true
    }

    /// Resolve `keyID`'s endorsed public key against the currently-applied
    /// document — `nil` if no keyset has been applied yet, or the key isn't
    /// currently endorsed (unknown/expired/wrong-env/wrong-status).
    func resolveSignerKey(keyID: String, now: Date = .now) -> Data? {
        current?.endorsedPublicKey(keyID: keyID, expectedEnv: Self.expectedEnv, now: now)
    }
}

extension QuickViewSignerKeysetClient: RefreshableControlPlaneDocument {
    var controlPlaneFamily: SignedControlPlaneStore.Family { .quickViewSignerKeyset }
    var lastRefreshMs: Int64? { controlStore.lastRefreshMs }
    var hasVerifiedCache: Bool { controlStore.hasVerifiedCache }
}

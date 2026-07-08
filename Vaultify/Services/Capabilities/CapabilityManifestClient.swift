import CloudKit
import Foundation

/// Fetch → verify → cache → apply for the signed capability manifest
/// (`LOOX-CAP-MANIFEST-V1`). Source order per BE handoff: primary Cloudflare
/// config endpoint → secondary CloudKit public DB mirror (independent failure
/// domain, IDENTICAL bytes) → verified cache → bundled defaults (all-enabled).
/// NEVER on the startup critical path (INV-CAP-02); every failure — 404,
/// timeout, bad signature, rollback — is silent and is NOT a policy signal
/// (INV-CAP-07).
@MainActor final class CapabilityManifestClient {

    static let primaryURL = URL(string: "https://config.looxpassword.com/v1/capabilities")!
    /// Secondary mirror record (schema is iOS-owned per handoff): public DB,
    /// record type `LooxCapabilityManifest`, recordName `current`, field
    /// `bytes` = the exact primary response bytes.
    static let mirrorRecordType = "LooxCapabilityManifest"
    static let mirrorRecordName = "current"
    static let mirrorBytesField = "bytes"

    /// Build-environment tag for key scoping. The capability manifest URL is prod
    /// for BOTH configs and carries no in-payload env binding, so this only scopes
    /// UserDefaults keys (defensive isolation, INV-CP-AR-06) — it never changes
    /// which document is fetched.
    #if DEBUG
    static let envTag = "staging"
    #else
    static let envTag = "production"
    #endif

    private let trustedKeys: [String: Data]
    private weak var store: CapabilityStore?
    private let controlStore: SignedControlPlaneStore

    init(store: CapabilityStore,
         trustedKeys: [String: Data] = CapabilityManifestVerifier.bundledTrustedKeys,
         defaults: UserDefaults = .standard) {
        self.store = store
        self.trustedKeys = trustedKeys
        self.controlStore = SignedControlPlaneStore(
            family: .capabilityManifest, env: Self.envTag,
            legacyVersionKey: "capability_manifest_highest_version",
            legacyCacheKey: "capability_manifest_v1", defaults: defaults)
    }

    var highestAcceptedVersion: UInt64 { controlStore.highestVersion }

    /// Re-verify and apply the cached manifest (relaunch path). A cache that
    /// no longer verifies (expired, key retired) has its bytes dropped silently —
    /// the high-water survives so a later re-serve of that version still recovers;
    /// the store then runs on bundled defaults + live per-response signals.
    func applyCached(now: Date = .now) {
        guard let cached = controlStore.currentBytes else { return }
        guard let manifest = try? CapabilityManifestVerifier.verify(
            manifestData: cached, trustedKeys: trustedKeys, now: now,
            highestAcceptedVersion: 0) else {   // rollback-vs-self is meaningless
            controlStore.dropBytesKeepingHighWater()
            return
        }
        controlStore.backfillCanonicalHashIfMissing(canonicalBytes: manifest.transcript)
        apply(manifest)
    }

    /// Primary → secondary → give up silently (cache/bundled stay in force).
    @discardableResult
    func refresh(now: Date = .now) async -> Bool {
        guard !trustedKeys.isEmpty else { return false }
        if let data = await fetchPrimary(), accept(manifestData: data, now: now) {
            controlStore.markRefreshSuccess(now: now); return true
        }
        if let data = await fetchSecondary(), accept(manifestData: data, now: now) {
            controlStore.markRefreshSuccess(now: now); return true
        }
        return false
    }

    /// Verification + anti-rollback + atomic persistence; separated for tests.
    @discardableResult
    func accept(manifestData: Data, now: Date = .now) -> Bool {
        guard let manifest = try? CapabilityManifestVerifier.verify(
            manifestData: manifestData, trustedKeys: trustedKeys, now: now,
            highestAcceptedVersion: controlStore.highestVersion) else { return false }
        guard controlStore.reconcile(incomingVersion: manifest.manifestVersion,
                                     canonicalBytes: manifest.transcript,
                                     signedBytes: manifestData, now: now) == .accepted else { return false }
        apply(manifest)
        return true
    }

    // MARK: Sources

    private func fetchPrimary() async -> Data? {
        var request = URLRequest(url: Self.primaryURL)
        request.timeoutInterval = 15
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    private func fetchSecondary() async -> Data? {
        guard CloudSyncService.isConfigured else { return nil }
        let database = CKContainer(identifier: "iCloud.com.bervion.vaultify").publicCloudDatabase
        let recordID = CKRecord.ID(recordName: Self.mirrorRecordName)
        guard let record = try? await database.record(for: recordID),
              record.recordType == Self.mirrorRecordType else { return nil }
        return record[Self.mirrorBytesField] as? Data
    }

    /// Operator tooling (handoff TODO 3): mirror the verified primary bytes
    /// into the CloudKit public DB so the secondary serves IDENTICAL bytes.
    /// Verifies BEFORE publishing — the mirror never propagates junk.
    func publishSecondaryMirror(now: Date = .now) async throws {
        guard let data = await fetchPrimary() else { throw CocoaError(.fileNoSuchFile) }
        _ = try CapabilityManifestVerifier.verify(
            manifestData: data, trustedKeys: trustedKeys, now: now, highestAcceptedVersion: 0)
        let database = CKContainer(identifier: "iCloud.com.bervion.vaultify").publicCloudDatabase
        let recordID = CKRecord.ID(recordName: Self.mirrorRecordName)
        let record: CKRecord
        if let existing = try? await database.record(for: recordID) {
            record = existing
        } else {
            record = CKRecord(recordType: Self.mirrorRecordType, recordID: recordID)
        }
        record[Self.mirrorBytesField] = data as CKRecordValue
        _ = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .changedKeys)
    }

    private func apply(_ manifest: CapabilityManifest) {
        for id in CapabilityID.allCases {
            guard let entry = manifest.entry(for: id) else { continue }
            store?.applyOperatorPolicy(id, .init(mode: entry.policy.serviceMode, retryAfter: nil),
                                       disabledOps: entry.disabledOperations,
                                       messageKey: entry.messageKey)
        }
        // Schema-1 manifests and schema-2 manifests omitting the field both
        // decode `exposure` as nil — the store must reflect that as "no
        // signal", never coerce it into a signed value.
        store?.applyQuickViewExposure(manifest.exposure(for: .quickView).flatMap(QuickViewExposure.init(rawValue:)))
    }
}

extension CapabilityManifestClient: RefreshableControlPlaneDocument {
    var controlPlaneFamily: SignedControlPlaneStore.Family { .capabilityManifest }
    var lastRefreshMs: Int64? { controlStore.lastRefreshMs }
    var hasVerifiedCache: Bool { controlStore.hasVerifiedCache }
}

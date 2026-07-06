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

    private let defaults: UserDefaults
    private let trustedKeys: [String: Data]
    private weak var store: CapabilityStore?

    private let cacheKey = "capability_manifest_v1"
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

    /// Re-verify and apply the cached manifest (relaunch path). A cache that
    /// no longer verifies (expired, key retired) is dropped silently; the
    /// store then runs on bundled defaults + live per-response signals.
    func applyCached(now: Date = .now) {
        guard let cached = defaults.data(forKey: cacheKey) else { return }
        guard let manifest = try? CapabilityManifestVerifier.verify(
            manifestData: cached, trustedKeys: trustedKeys, now: now,
            highestAcceptedVersion: 0) else {   // rollback-vs-self is meaningless
            defaults.removeObject(forKey: cacheKey)
            return
        }
        apply(manifest)
    }

    /// Primary → secondary → give up silently (cache/bundled stay in force).
    func refresh(now: Date = .now) async {
        guard !trustedKeys.isEmpty else { return }
        if let data = await fetchPrimary(), accept(manifestData: data, now: now) { return }
        if let data = await fetchSecondary() { accept(manifestData: data, now: now) }
    }

    /// Verification + strict anti-rollback + persistence; separated for tests.
    @discardableResult
    func accept(manifestData: Data, now: Date = .now) -> Bool {
        guard let manifest = try? CapabilityManifestVerifier.verify(
            manifestData: manifestData, trustedKeys: trustedKeys, now: now,
            highestAcceptedVersion: highestAcceptedVersion) else { return false }
        highestAcceptedVersion = manifest.manifestVersion
        defaults.set(manifestData, forKey: cacheKey)
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
    }
}

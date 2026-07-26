import Foundation
import CloudKit
#if canImport(UIKit)
import UIKit
import Darwin
#endif

/// One device that syncs this vault (owner-side registry).
nonisolated struct VaultDevice: Identifiable, Sendable {
    let id: String           // stable device id (hex)
    let name: String
    let model: String
    let lastSeenAt: Date
    let appVersion: String
    let isCurrent: Bool
}

/// Publishes THIS device to a private-DB `OwnerDevice` record and lists every device that
/// has published one (read from `DeviceRegistryMirror`, fed by the delta sync — no
/// `CKQuery`, so no dashboard index is required). Best-effort and gated (compile flag +
/// `iCloudSyncEnabled` + not under tests), so a disabled sync, offline, or
/// not-yet-provisioned schema degrades to "just this device" — never a crash.
///
/// "Log Out Device" is a COOPERATIVE sign-out: a `DeviceRevocation` record the target
/// device honors on its next sync (foreground / reconnect / silent push) by erasing its
/// local state. It is NOT cryptographic access revocation — a device kept permanently
/// offline is out of reach, and truly cutting access still requires rotating the vault
/// key (plan `260715-1630-profile-refactor` phase 06 / ADR-D, unchanged).
///
/// CloudKit schema (owner does this once in the dashboard before prod/TestFlight):
/// deploy record types `OwnerDevice` and `DeviceRevocation` to Production. No queryable
/// indexes are needed (mirror + fetch-by-recordName only).
@MainActor final class DeviceRegistryService {
    static let recordType = "OwnerDevice"
    static let revocationRecordType = "DeviceRevocation"

    private let settings: SettingsStore
    private let deviceID = OwnerDeviceIdentity.resolve()
    // Lazy: created only when a network call actually runs (never under tests / when sync is
    // off), so `CKContainer.init` can't trap on an unprovisioned build.
    private lazy var container = CKContainer(identifier: "iCloud.com.bervion.vaultify")
    private let zone = CKRecordZone(zoneName: "Vault")
    private var database: CKDatabase { container.privateCloudDatabase }

    init(settings: SettingsStore) { self.settings = settings }

    /// Gated: never touch CloudKit under tests, off a non-iCloud build, or when the user
    /// hasn't opted into iCloud sync.
    private var canRun: Bool {
        !CloudSyncService.isHostingUnitTests && CloudSyncService.isConfigured && settings.iCloudSyncEnabled
    }

    /// This device — always available with no network (the list falls back to it).
    var thisDevice: VaultDevice {
        VaultDevice(id: deviceID, name: Self.deviceName(), model: Self.deviceModel(),
                    lastSeenAt: .now, appVersion: Self.appVersion(), isCurrent: true)
    }

    /// Upsert this device's record (best-effort). Silently retried next time on failure.
    func publish() async {
        guard canRun else { return }
        let recordID = CKRecord.ID(recordName: "owner-device-\(deviceID)", zoneID: zone.zoneID)
        let record = CKRecord(recordType: Self.recordType, recordID: recordID)
        record["deviceID"] = deviceID as CKRecordValue
        record["name"] = Self.deviceName() as CKRecordValue
        record["model"] = Self.deviceModel() as CKRecordValue
        record["lastSeenAt"] = Date.now as CKRecordValue
        record["appVersion"] = Self.appVersion() as CKRecordValue
        do {
            _ = try await database.modifyRecordZones(saving: [zone], deleting: [])
            _ = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
            // The delta pull won't re-deliver our own write — mirror it directly.
            DeviceRegistryMirror.upsert(.init(id: deviceID, name: Self.deviceName(),
                                              model: Self.deviceModel(), lastSeenAt: .now,
                                              appVersion: Self.appVersion()))
        } catch {
            // Best-effort: offline / missing schema / not-signed-in retry on the next visit.
        }
    }

    /// Every known device, from the delta-sync mirror: no network, no query index.
    /// Always includes this device; signed-out (revoked) devices are filtered.
    func fetchDevices() async -> [VaultDevice] {
        let current = thisDevice
        guard canRun else { return [current] }
        let revoked = DeviceRegistryMirror.revokedIDs()
        var devices: [VaultDevice] = DeviceRegistryMirror.devices()
            .filter { !revoked.contains($0.id) && $0.id != current.id }
            .map {
                VaultDevice(id: $0.id,
                            name: $0.name.isEmpty ? appString("Unknown device") : $0.name,
                            model: $0.model, lastSeenAt: $0.lastSeenAt,
                            appVersion: $0.appVersion, isCurrent: false)
            }
        devices.append(current)
        // Current device first, then most-recently-seen.
        return devices.sorted {
            if $0.isCurrent != $1.isCurrent { return $0.isCurrent }
            return $0.lastSeenAt > $1.lastSeenAt
        }
    }

    // MARK: Cooperative sign-out

    /// Ask `deviceID` to sign itself out: write the revocation marker it will honor on
    /// its next sync. Throws so the UI can surface a failed write (unlike the
    /// best-effort publish) — a sign-out the owner believes happened must not silently
    /// not exist.
    func logOut(deviceID target: String) async throws {
        let recordID = CKRecord.ID(recordName: "revoke-\(target)", zoneID: zone.zoneID)
        let record = CKRecord(recordType: Self.revocationRecordType, recordID: recordID)
        record["deviceID"] = target as CKRecordValue
        record["revokedAt"] = Date.now as CKRecordValue
        record["byDeviceID"] = deviceID as CKRecordValue
        _ = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
        // Hide it locally right away; peers learn through the delta pull.
        DeviceRegistryMirror.markRevoked(target)
    }

    /// Whether THIS device has been signed out remotely (marker seen by the delta
    /// pull). Mirror-only — no extra network round-trip per sync.
    var isSelfRevoked: Bool { DeviceRegistryMirror.isRevoked(deviceID) }

    /// Best-effort removal of this device's own registry record — called while
    /// executing a remote sign-out, before local state is erased.
    func deleteOwnRecord() async {
        let recordID = CKRecord.ID(recordName: "owner-device-\(deviceID)", zoneID: zone.zoneID)
        _ = try? await database.modifyRecords(saving: [], deleting: [recordID])
    }

    /// After honoring a remote sign-out: drop the keychain device id so a future
    /// re-pair mints a FRESH identity — otherwise the standing revocation marker
    /// would wipe the device again on its first sync.
    nonisolated static func resetIdentityAfterRemoteSignOut() {
        OwnerDeviceIdentity.reset()
        DeviceRegistryMirror.clear()
    }

    // MARK: Device info (non-sensitive; private DB only)

    private static func deviceName() -> String {
        #if canImport(UIKit)
        return UIDevice.current.name
        #else
        return Host.current().localizedName ?? "Mac"
        #endif
    }
    private static func deviceModel() -> String {
        #if canImport(UIKit)
        return DeviceModelNames.marketingName(forIdentifier: hardwareIdentifier())
        #else
        return "Mac"
        #endif
    }

    #if canImport(UIKit)
    /// Raw hardware identifier (`hw.machine`, e.g. "iPhone17,2") for `DeviceModelNames` to
    /// resolve into a marketing name. `UIDevice.current.model` only ever returns the generic
    /// "iPhone"/"iPad" — this reads the actual model off the kernel instead. On the Simulator,
    /// `uname`'s `machine` field reports the HOST Mac's architecture ("arm64"/"x86_64") rather
    /// than a simulated device identifier, so this reads `SIMULATOR_MODEL_IDENTIFIER` from the
    /// process environment first (set by Xcode/simctl for every simulated run, so Simulator
    /// testing still shows a real device name) and only falls back to `uname` on a real device.
    private static func hardwareIdentifier() -> String {
        #if targetEnvironment(simulator)
        if let simulatorIdentifier = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"],
           !simulatorIdentifier.isEmpty {
            return simulatorIdentifier
        }
        #endif
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafeBytes(of: &systemInfo.machine) { rawBuffer in
            let pointer = rawBuffer.baseAddress!.assumingMemoryBound(to: CChar.self)
            return String(cString: pointer)
        }
    }
    #endif
    private static func appVersion() -> String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? ""
    }
}

/// A stable per-device id (16 random bytes, hex) persisted in the shared Keychain group so it
/// survives relaunch and is consistent across the app + AutoFill extension. Independent of
/// the approval/HPKE device key so the registry doesn't create crypto material it never uses.
nonisolated enum OwnerDeviceIdentity {
    private static let account = "owner_device_id_v1"

    static func resolve() -> String {
        let group = SharedConfig.keychainAccessGroup
        if let existing = try? KeychainStore.get(account: account, accessGroup: group), existing.count == 16 {
            return existing.hexString
        }
        let fresh = CryptoRandom.data(16)
        try? KeychainStore.set(fresh, account: account, accessGroup: group)
        return fresh.hexString
    }

    /// Drop the stored id so the next `resolve()` mints a fresh one — used after a
    /// remote sign-out so a re-paired device isn't re-wiped by its own old marker.
    static func reset() {
        _ = KeychainStore.delete(account: account, accessGroup: SharedConfig.keychainAccessGroup)
    }
}

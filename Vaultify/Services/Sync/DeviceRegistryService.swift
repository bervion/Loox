import Foundation
import CloudKit
#if canImport(UIKit)
import UIKit
import Darwin
#endif

/// One device that syncs this vault (owner-side registry). **List-only** — there is no
/// revoke here: cutting a device's access requires rotating the vault key, which is a
/// separate security-reviewed step (plan `260715-1630-profile-refactor` phase 06 / ADR-D).
nonisolated struct VaultDevice: Identifiable, Sendable {
    let id: String           // stable device id (hex)
    let name: String
    let model: String
    let lastSeenAt: Date
    let isCurrent: Bool
}

/// Publishes THIS device to a private-DB `OwnerDevice` record and lists every device that
/// has published one. Best-effort and gated (compile flag + `iCloudSyncEnabled` + not under
/// tests), so a disabled sync, offline, or not-yet-provisioned schema degrades to "just this
/// device" — never a crash.
///
/// CloudKit schema (owner does this once in the CloudKit dashboard before a prod/TestFlight
/// build can list peers): record type `OwnerDevice` in the private `Vault` zone, with a
/// **Queryable index on `recordName`** so the list query works. The dev environment infers
/// the type on first save; the queryable index still has to be added.
@MainActor final class DeviceRegistryService {
    static let recordType = "OwnerDevice"

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
                    lastSeenAt: .now, isCurrent: true)
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
        } catch {
            // Best-effort: offline / missing schema / not-signed-in retry on the next visit.
        }
    }

    /// Every published device (best-effort). Always includes this device, even before its
    /// first publish round-trips or if the query fails (no schema index yet).
    func fetchDevices() async -> [VaultDevice] {
        let current = thisDevice
        guard canRun else { return [current] }
        let query = CKQuery(recordType: Self.recordType, predicate: NSPredicate(value: true))
        do {
            let (results, _) = try await database.records(
                matching: query, inZoneWith: zone.zoneID,
                desiredKeys: nil, resultsLimit: CKQueryOperation.maximumResults)
            var devices: [VaultDevice] = []
            for (_, result) in results {
                guard case .success(let record) = result else { continue }
                let id = (record["deviceID"] as? String) ?? record.recordID.recordName
                devices.append(VaultDevice(
                    id: id,
                    name: (record["name"] as? String) ?? appString("Unknown device"),
                    model: (record["model"] as? String) ?? "",
                    lastSeenAt: (record["lastSeenAt"] as? Date) ?? .now,
                    isCurrent: id == current.id))
            }
            if !devices.contains(where: \.isCurrent) { devices.append(current) }
            // Current device first, then most-recently-seen.
            return devices.sorted {
                if $0.isCurrent != $1.isCurrent { return $0.isCurrent }
                return $0.lastSeenAt > $1.lastSeenAt
            }
        } catch {
            return [current]
        }
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
}

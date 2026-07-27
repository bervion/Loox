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

    enum Failure: Error, LocalizedError {
        /// The target resolves to this very device. Writing the marker would
        /// sign the user out of the phone in their hand.
        case cannotSignOutSelf

        var errorDescription: String? {
            switch self {
            case .cannotSignOutSelf:
                return appString("This is the device you're using. Sign out from the device you want to remove.")
            }
        }
    }

    private let settings: SettingsStore
    /// Re-read per use, never frozen at init: this service is constructed at
    /// launch, including background wakes while the phone is locked, when the
    /// id is temporarily unreadable. nil means "not knowable right now".
    private var deviceID: String? { OwnerDeviceIdentity.current() }
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
    /// An empty id means the registry identity was not readable at this moment;
    /// the row still renders (the user is looking at an unlocked screen, so this
    /// is rare) but nothing that writes to the registry will act on it.
    var thisDevice: VaultDevice {
        VaultDevice(id: deviceID ?? "", name: Self.deviceName(), model: Self.deviceModel(),
                    lastSeenAt: .now, appVersion: Self.appVersion(), isCurrent: true)
    }

    /// Upsert this device's record (best-effort). Silently retried next time on failure.
    func publish() async {
        // No id, no publish. Publishing under an unresolved identity is exactly
        // how duplicate "devices" appeared in the list.
        guard canRun, let deviceID else { return }
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
        // Signing THIS device out from its own row is not what the control
        // means, and the id may be a stale one this install used to publish
        // under — either way the marker would wipe the device it was tapped on.
        guard !target.isEmpty, target != deviceID else { throw Failure.cannotSignOutSelf }
        let recordID = CKRecord.ID(recordName: "revoke-\(target)", zoneID: zone.zoneID)
        let record = CKRecord(recordType: Self.revocationRecordType, recordID: recordID)
        record["deviceID"] = target as CKRecordValue
        record["revokedAt"] = Date.now as CKRecordValue
        record["byDeviceID"] = (deviceID ?? "") as CKRecordValue
        _ = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
        // Hide it locally right away; peers learn through the delta pull.
        DeviceRegistryMirror.markRevoked(target)
    }

    /// Whether THIS device has been signed out remotely (marker seen by the delta
    /// pull). Mirror-only — no extra network round-trip per sync.
    ///
    /// Fails SAFE when the id is unreadable: honoring a sign-out erases local
    /// state, so an uncertain identity must never trigger it. The check runs
    /// again on the next unlocked pass, when the answer is trustworthy.
    var isSelfRevoked: Bool {
        guard let deviceID else { return false }
        return DeviceRegistryMirror.isRevoked(deviceID)
    }

    /// Best-effort removal of this device's own registry record — called while
    /// executing a remote sign-out, before local state is erased.
    func deleteOwnRecord() async {
        guard let deviceID else { return }
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

    /// This device's registry id, or nil when it cannot be established RIGHT NOW.
    ///
    /// The distinction that matters: `KeychainStore.get` returns nil only for
    /// "no such item", and THROWS for everything else. Keychain items here are
    /// `WhenUnlockedThisDeviceOnly`, so a background wake while the phone is
    /// locked (a silent sync or share-acceptance push) throws
    /// `errSecInteractionNotAllowed` — the id exists and is simply unreadable.
    ///
    /// Collapsing both cases with `try?` and minting on nil is what produced
    /// ghost devices: every locked background wake invented a new id, published
    /// it as a brand-new device, and could not even persist it (the write is
    /// blocked for the same reason), so the next wake invented another. It also
    /// made signing a device out dangerous — the row the user tapped could be
    /// carrying their REAL id while the running session held a ghost, so the
    /// revocation landed on themselves and the device signed itself out on the
    /// next unlock.
    ///
    /// Returning nil instead means callers do nothing rather than something
    /// wrong. A read failure is transient; the next unlocked pass resolves it.
    static func current() -> String? {
        let group = SharedConfig.keychainAccessGroup
        do {
            if let existing = try KeychainStore.get(account: account, accessGroup: group),
               existing.count == 16 {
                return existing.hexString
            }
        } catch {
            return nil
        }
        // Genuinely absent (first launch). Mint one, but only claim it if it
        // persisted — an id that cannot be stored is a ghost by another name.
        let fresh = CryptoRandom.data(16)
        do {
            try KeychainStore.set(fresh, account: account, accessGroup: group)
        } catch {
            return nil
        }
        return fresh.hexString
    }

    /// Drop the stored id so the next `resolve()` mints a fresh one — used after a
    /// remote sign-out so a re-paired device isn't re-wiped by its own old marker.
    static func reset() {
        _ = KeychainStore.delete(account: account, accessGroup: SharedConfig.keychainAccessGroup)
    }
}

import Foundation
import CloudKit

/// Local mirror of the owner device registry, fed by the DELTA SYNC — the zone-changes
/// pull already delivers every `OwnerDevice` / `DeviceRevocation` record in the Vault
/// zone, so listing devices needs no `CKQuery` (whose TRUEPREDICATE form silently fails
/// without a manually-added Queryable index per CloudKit environment; that was why the
/// Devices list only ever showed the current device).
///
/// Plain UserDefaults JSON: device model names and timestamps are non-secret metadata,
/// and the mirror must be readable before unlock (the self-sign-out check runs on any
/// sync trigger, including a locked background pull).
nonisolated enum DeviceRegistryMirror {
    struct Entry: Codable, Equatable {
        let id: String
        var name: String
        var model: String
        var lastSeenAt: Date
        var appVersion: String
    }

    private static let devicesKey = "owner_device_mirror_v1"
    private static let revokedKey = "owner_device_revoked_v1"

    // MARK: Delta-sync feed

    /// Route a pulled Vault-zone record into the mirror. Called from
    /// `CloudSyncService.pull()` for the registry record types.
    static func apply(_ record: CKRecord) {
        switch record.recordType {
        case DeviceRegistryService.recordType:
            upsert(Entry(
                id: (record["deviceID"] as? String) ?? record.recordID.recordName,
                name: (record["name"] as? String) ?? "",
                model: (record["model"] as? String) ?? "",
                lastSeenAt: (record["lastSeenAt"] as? Date) ?? .now,
                appVersion: (record["appVersion"] as? String) ?? ""))
        case DeviceRegistryService.revocationRecordType:
            if let id = record["deviceID"] as? String { markRevoked(id) }
        default:
            break
        }
    }

    // MARK: Devices

    static func devices() -> [Entry] {
        decode([Entry].self, forKey: devicesKey) ?? []
    }

    static func upsert(_ entry: Entry) {
        var all = devices().filter { $0.id != entry.id }
        all.append(entry)
        encode(all, forKey: devicesKey)
    }

    // MARK: Revocations (cooperative sign-out markers, see `DeviceRegistryService`)

    static func revokedIDs() -> Set<String> {
        decode(Set<String>.self, forKey: revokedKey) ?? []
    }

    static func markRevoked(_ id: String) {
        var ids = revokedIDs()
        ids.insert(id)
        encode(ids, forKey: revokedKey)
    }

    static func isRevoked(_ id: String) -> Bool { revokedIDs().contains(id) }

    /// Erase Vault / remote sign-out: the mirror describes a registry this install
    /// no longer belongs to.
    static func clear() {
        UserDefaults.standard.removeObject(forKey: devicesKey)
        UserDefaults.standard.removeObject(forKey: revokedKey)
    }

    // MARK: Storage

    private static func decode<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func encode<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

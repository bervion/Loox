import Foundation

/// Reduced capability snapshot the main app writes to the App Group for the
/// AutoFill extension. The extension NEVER fetches capability state itself,
/// and a missing/stale/corrupt snapshot only means "remote actions unknown" —
/// owned local AutoFill never depends on it (INV-CAP-01/06).
nonisolated struct CapabilitySnapshot: Codable, Sendable, Equatable {
    static let schemaVersion: UInt8 = 1
    private static let key = "capability_snapshot_v1"

    var schemaVersion: UInt8 = CapabilitySnapshot.schemaVersion
    let generatedAt: Date
    /// Raw `CapabilityServiceMode` values keyed by raw `CapabilityID`.
    let modes: [String: String]

    func mode(for id: CapabilityID) -> CapabilityServiceMode? {
        modes[id.rawValue].flatMap(CapabilityServiceMode.init(rawValue:))
    }

    static func write(modes: [CapabilityID: CapabilityServiceMode],
                      defaults: UserDefaults = SharedConfig.sharedDefaults,
                      now: Date = .now) {
        let snapshot = CapabilitySnapshot(
            generatedAt: now,
            modes: Dictionary(uniqueKeysWithValues: modes.map { ($0.key.rawValue, $0.value.rawValue) }))
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: key)
        }
    }

    /// nil on missing/corrupt/unsupported — callers treat that as "unknown",
    /// never as a gate on owned local behavior.
    static func read(defaults: UserDefaults = SharedConfig.sharedDefaults) -> CapabilitySnapshot? {
        guard let data = defaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(CapabilitySnapshot.self, from: data),
              snapshot.schemaVersion == schemaVersion else { return nil }
        return snapshot
    }
}

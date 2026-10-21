import Foundation

/// Persists the complimentary Loox+ start in the Keychain so a REINSTALL keeps
/// it (Keychain items outlive app deletion today; Apple does not guarantee
/// this, accepted). WhenUnlockedThisDeviceOnly, never synchronizable: a new
/// device or Erase All Content gets a fresh 750 days (owner decision 261021,
/// device-local start accepted).
///
/// Rules:
/// - A THROWING read (locked wake, errSecInteractionNotAllowed) never mints,
///   the same as `OwnerDeviceIdentity.current()`.
/// - Mint is ADD-ONLY (`KeychainStore.add`). On a duplicate the store reads
///   again, so a racing scene or a wrong "absent" never overwrites a start.
/// - The only rewrites are the clamp (a start more than a day after `now`,
///   from a clock moved forward at mint, becomes `now`, which can only shorten
///   the grant) and a malformed payload, which cannot be parsed anyway.
/// - `eraseLocalState` never erases this item.
nonisolated struct LooxComplimentaryGrantStore: Sendable {
    nonisolated struct Backend: Sendable {
        var read: @Sendable () throws -> Data?        // nil = absent; throws = unknown
        var add: @Sendable (Data) throws -> Bool       // false = duplicate
        var update: @Sendable (Data) throws -> Bool    // false = absent
        var delete: @Sendable () -> Void
    }

    static let account = "loox-complimentary-start-v1"

    static let keychain = Self(backend: Backend(
        read: { try KeychainStore.get(account: account) },
        add: { try KeychainStore.add($0, account: account) },
        update: { try KeychainStore.update($0, account: account) },
        delete: { KeychainStore.delete(account: account) }
    ))

    let backend: Backend

    /// Read → clamp a future start → grant. Absent: add `now`; a duplicate means
    /// read again. Malformed: overwrite with `now`. A read or write that throws
    /// (or loses a race) returns nil and writes nothing more.
    func resolve(now: Date) -> LooxComplimentaryGrant? {
        do {
            if let data = try backend.read() {
                return try grant(from: data, now: now)
            }
            if try backend.add(Self.encode(now)) { return Self.minted(now) }
            guard let data = try backend.read() else { return nil }
            return try grant(from: data, now: now)
        } catch {
            return nil
        }
    }

    /// A stored payload → grant, applying the two allowed rewrites.
    private func grant(from data: Data, now: Date) throws -> LooxComplimentaryGrant? {
        if let start = Self.decode(data),
           start.timeIntervalSince(now) <= LooxComplimentaryGrant.futureStartTolerance {
            return LooxComplimentaryGrant(start: start)
        }
        // Future start (clamp) or malformed payload: rewrite to `now`. `false`
        // means the item vanished in between; the next resolve mints it.
        guard try backend.update(Self.encode(now)) else { return nil }
        return Self.minted(now)
    }

    /// The grant exactly as it reads back from storage (whole seconds).
    private static func minted(_ now: Date) -> LooxComplimentaryGrant {
        LooxComplimentaryGrant(start: decode(encode(now)) ?? now)
    }

    /// UTF-8 decimal Int64 Unix seconds.
    static func encode(_ date: Date) -> Data {
        Data(String(Int64(date.timeIntervalSince1970.rounded(.down))).utf8)
    }

    static func decode(_ data: Data) -> Date? {
        guard let text = String(data: data, encoding: .utf8),
              let seconds = Int64(text) else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    #if DEBUG
    /// Process-local backend for UI-test isolation and unit tests: never
    /// touches the Keychain. `start` seeds the stored value (nil = absent).
    static func inMemory(start: Date?) -> Self {
        let box = MemoryBox(start.map(encode))
        return Self(backend: Backend(
            read: { box.value },
            add: { data in box.mutate { stored in
                guard stored == nil else { return false }
                stored = data
                return true
            } },
            update: { data in box.mutate { stored in
                guard stored != nil else { return false }
                stored = data
                return true
            } },
            delete: { box.mutate { $0 = nil } }
        ))
    }

    /// QA only (Settings → Debug): update, or add if absent; nil deletes.
    func debugOverwrite(start: Date?) {
        guard let start else { return backend.delete() }
        let data = Self.encode(start)
        if (try? backend.update(data)) != true { _ = try? backend.add(data) }
    }

    private final class MemoryBox: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: Data?
        init(_ stored: Data?) { self.stored = stored }
        var value: Data? { lock.withLock { stored } }
        func mutate<R>(_ body: (inout Data?) -> R) -> R { lock.withLock { body(&stored) } }
    }
    #endif
}

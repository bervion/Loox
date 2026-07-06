import Foundation

/// Deterministic, versioned byte encoding for signed control-plane artifacts.
/// Deliberately NOT `JSONEncoder` (key order/float formatting are unstable):
/// a signature must verify after a CKRecord round-trip, so the transported
/// bytes ARE the canonical bytes (`encoded()` travels as one `Data` field).
///
/// Layout primitives: fixed-width big-endian integers; blobs/strings are
/// u32-length-prefixed; optionals are a 0/1 flag byte + value; dictionaries
/// are encoded sorted by key. A leading version byte + artifact type tag
/// domain-separates signatures (a grant can never verify as a request).
nonisolated enum ApprovalWire {
    static let version: UInt8 = 1
    /// Grant layout v2 (P03b): v1 fields + deviceScope + device-key bindings,
    /// and the extended capability set (passkey, TOTP `.shared`). The leading
    /// version byte is part of the signed bytes, so a v2 payload can never
    /// verify against a v1 signature or vice versa. Grants that use no v2
    /// feature keep encoding as v1 — bit-identical to pre-P03b.
    static let versionV2: UInt8 = 2

    enum TypeTag: UInt8 {
        case grant = 1, request = 2, response = 3
    }

    enum DecodeError: Error, Equatable {
        case truncated, unknownVersion, wrongType, invalidValue
    }
}

// MARK: - Writer / Reader

nonisolated struct CanonicalWriter {
    private(set) var data = Data()

    mutating func byte(_ value: UInt8) { data.append(value) }

    mutating func u32(_ value: UInt32) {
        withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) }
    }

    mutating func u64(_ value: UInt64) {
        withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) }
    }

    mutating func i64(_ value: Int64) { u64(UInt64(bitPattern: value)) }

    mutating func blob(_ value: Data) {
        u32(UInt32(value.count))
        data.append(value)
    }

    /// Append raw bytes with NO length prefix (used to concatenate an
    /// already-canonical signing body with its trailing signature blob).
    mutating func raw(_ value: Data) { data.append(value) }

    mutating func string(_ value: String) { blob(Data(value.utf8)) }

    mutating func optionalI64(_ value: Int64?) {
        if let value { byte(1); i64(value) } else { byte(0) }
    }
}

nonisolated struct CanonicalReader {
    private let data: Data
    private var offset: Int

    init(_ data: Data) {
        self.data = data
        self.offset = data.startIndex
    }

    var isAtEnd: Bool { offset == data.endIndex }

    mutating func byte() throws -> UInt8 {
        guard offset < data.endIndex else { throw ApprovalWire.DecodeError.truncated }
        defer { offset += 1 }
        return data[offset]
    }

    mutating func u32() throws -> UInt32 {
        try fixed(4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian }
    }

    mutating func u64() throws -> UInt64 {
        try fixed(8).withUnsafeBytes { $0.loadUnaligned(as: UInt64.self).bigEndian }
    }

    mutating func i64() throws -> Int64 { Int64(bitPattern: try u64()) }

    mutating func blob() throws -> Data {
        let count = Int(try u32())
        return try fixed(count)
    }

    mutating func string() throws -> String {
        guard let value = String(data: try blob(), encoding: .utf8) else {
            throw ApprovalWire.DecodeError.invalidValue
        }
        return value
    }

    mutating func optionalI64() throws -> Int64? {
        switch try byte() {
        case 0: return nil
        case 1: return try i64()
        default: throw ApprovalWire.DecodeError.invalidValue
        }
    }

    private mutating func fixed(_ count: Int) throws -> Data {
        guard count >= 0, data.distance(from: offset, to: data.endIndex) >= count else {
            throw ApprovalWire.DecodeError.truncated
        }
        defer { offset += count }
        return data.subdata(in: offset..<(offset + count))
    }
}

// MARK: - FieldCapability wire form

extension FieldCapability {
    /// Tag byte (0 = totp, 1 = value, 2 = passkey) + raw capability byte.
    nonisolated func write(to writer: inout CanonicalWriter) {
        switch self {
        case .totp(let cap): writer.byte(0); writer.byte(cap.rawValue)
        case .value(let cap): writer.byte(1); writer.byte(cap.rawValue)
        case .passkey(let cap): writer.byte(2); writer.byte(cap.rawValue)
        }
    }

    nonisolated static func read(from reader: inout CanonicalReader) throws -> FieldCapability {
        switch try reader.byte() {
        case 0:
            guard let cap = TOTPFieldCapability(rawValue: try reader.byte()) else {
                throw ApprovalWire.DecodeError.invalidValue
            }
            return .totp(cap)
        case 1:
            guard let cap = ValueFieldCapability(rawValue: try reader.byte()) else {
                throw ApprovalWire.DecodeError.invalidValue
            }
            return .value(cap)
        case 2:
            guard let cap = PasskeyFieldCapability(rawValue: try reader.byte()) else {
                throw ApprovalWire.DecodeError.invalidValue
            }
            return .passkey(cap)
        default:
            throw ApprovalWire.DecodeError.invalidValue
        }
    }
}

// MARK: - AccessGrant

extension AccessGrant {
    /// The exact bytes the owner signs (everything except the signature).
    /// The leading version byte is 1 or 2 depending on `requiresWireV2` —
    /// grants without v2 features stay bit-identical to pre-P03b, keeping
    /// every existing signature valid.
    nonisolated func signingBody() -> Data {
        var w = CanonicalWriter()
        let v2 = requiresWireV2
        w.byte(v2 ? ApprovalWire.versionV2 : ApprovalWire.version)
        w.byte(ApprovalWire.TypeTag.grant.rawValue)
        w.string(id)
        w.string(itemId)
        w.string(recipientId)
        w.blob(participantPubKey)
        w.u32(UInt32(pinnedDeviceSigningKeys.count))
        // Sorted so the signed bytes never depend on insertion order.
        for key in pinnedDeviceSigningKeys.sorted(by: { $0.lexicographicallyPrecedes($1) }) {
            w.blob(key)
        }
        w.u32(UInt32(capabilities.count))
        for fieldId in capabilities.keys.sorted() {
            w.string(fieldId)
            capabilities[fieldId]!.write(to: &w)
        }
        if v2 {
            // v2 section sits between capabilities and epoch: device scope +
            // bindings sorted by deviceKeyID (INV-12 deterministic ordering).
            w.byte(deviceScope.rawValue)
            let bindings = allowedDeviceKeyBindings
                .sorted { $0.deviceKeyID.lexicographicallyPrecedes($1.deviceKeyID) }
            w.u32(UInt32(bindings.count))
            for binding in bindings {
                w.blob(binding.deviceKeyID)
                w.blob(binding.hpkePublicKeyHash)
            }
        }
        w.u32(epoch)
        w.i64(createdAtUnixMs)
        w.optionalI64(expiresAtUnixMs)
        w.blob(ownerSigningPubKey)
        return w.data
    }

    nonisolated func encoded() -> Data {
        var w = CanonicalWriter()
        w.raw(signingBody())
        w.blob(ownerSignature)
        return w.data
    }

    nonisolated static func decode(_ data: Data) throws -> AccessGrant {
        var r = CanonicalReader(data)
        let version = try r.byte()
        guard version == ApprovalWire.version || version == ApprovalWire.versionV2 else {
            throw ApprovalWire.DecodeError.unknownVersion
        }
        guard try r.byte() == ApprovalWire.TypeTag.grant.rawValue else { throw ApprovalWire.DecodeError.wrongType }
        let id = try r.string()
        let itemId = try r.string()
        let recipientId = try r.string()
        let participantPubKey = try r.blob()
        var pinned: [Data] = []
        for _ in 0..<(try r.u32()) { pinned.append(try r.blob()) }
        var capabilities: [String: FieldCapability] = [:]
        for _ in 0..<(try r.u32()) {
            let fieldId = try r.string()
            capabilities[fieldId] = try FieldCapability.read(from: &r)
        }
        var deviceScope = DeviceScope.multi
        var bindings: [DeviceKeyBinding] = []
        if version == ApprovalWire.versionV2 {
            guard let scope = DeviceScope(rawValue: try r.byte()) else {
                throw ApprovalWire.DecodeError.invalidValue
            }
            deviceScope = scope
            var previousID: Data?
            for _ in 0..<(try r.u32()) {
                let binding = DeviceKeyBinding(deviceKeyID: try r.blob(),
                                               hpkePublicKeyHash: try r.blob())
                // Strictly ascending: rejects duplicates AND reordering in
                // one check (INV-12 — canonical bytes have exactly one form).
                if let previousID,
                   !previousID.lexicographicallyPrecedes(binding.deviceKeyID) {
                    throw ApprovalWire.DecodeError.invalidValue
                }
                previousID = binding.deviceKeyID
                bindings.append(binding)
            }
        }
        let epoch = try r.u32()
        let createdAtUnixMs = try r.i64()
        let expiresAtUnixMs = try r.optionalI64()
        let ownerSigningPubKey = try r.blob()
        let ownerSignature = try r.blob()
        guard r.isAtEnd else { throw ApprovalWire.DecodeError.invalidValue }
        let grant = AccessGrant(
            id: id, itemId: itemId, recipientId: recipientId,
            participantPubKey: participantPubKey, pinnedDeviceSigningKeys: pinned,
            capabilities: capabilities, epoch: epoch,
            createdAtUnixMs: createdAtUnixMs, expiresAtUnixMs: expiresAtUnixMs,
            ownerSigningPubKey: ownerSigningPubKey, ownerSignature: ownerSignature,
            deviceScope: deviceScope, allowedDeviceKeyBindings: bindings)
        // Version-feature agreement both ways: a v1 payload smuggling v2-only
        // capabilities, or a v2 payload that uses no v2 feature (so its
        // re-encoding would flip back to v1 and the signature could never
        // verify), are both malformed.
        guard grant.requiresWireV2 == (version == ApprovalWire.versionV2) else {
            throw ApprovalWire.DecodeError.invalidValue
        }
        return grant
    }
}

// MARK: - ApprovalRequest

extension ApprovalRequest {
    /// Wire v2 iff `payloadBinding` is present (passkey askEachTime) — TOTP
    /// requests keep encoding bit-identical to pre-v2, so existing pinned
    /// devices and in-flight requests are untouched.
    nonisolated func signingBody() -> Data {
        var w = CanonicalWriter()
        let v2 = payloadBinding != nil
        w.byte(v2 ? ApprovalWire.versionV2 : ApprovalWire.version)
        w.byte(ApprovalWire.TypeTag.request.rawValue)
        w.string(requestId)
        w.string(grantId)
        w.string(requesterDeviceId)
        w.string(itemId)
        w.string(fieldId)
        w.blob(nonce)
        w.blob(ephemeralPubKey)
        if let payloadBinding { w.blob(payloadBinding) }
        w.i64(createdAtUnixMs)
        w.i64(expiresAtUnixMs)
        w.blob(requesterSigningPubKey)
        return w.data
    }

    nonisolated func encoded() -> Data {
        var w = CanonicalWriter()
        w.raw(signingBody())
        w.blob(requesterSignature)
        return w.data
    }

    nonisolated static func decode(_ data: Data) throws -> ApprovalRequest {
        var r = CanonicalReader(data)
        let version = try r.byte()
        guard version == ApprovalWire.version || version == ApprovalWire.versionV2 else {
            throw ApprovalWire.DecodeError.unknownVersion
        }
        guard try r.byte() == ApprovalWire.TypeTag.request.rawValue else { throw ApprovalWire.DecodeError.wrongType }
        let requestId = try r.string()
        let grantId = try r.string()
        let requesterDeviceId = try r.string()
        let itemId = try r.string()
        let fieldId = try r.string()
        let nonce = try r.blob()
        let ephemeralPubKey = try r.blob()
        var payloadBinding: Data?
        if version == ApprovalWire.versionV2 {
            let binding = try r.blob()
            // The binding IS the reason v2 exists — exactly one SHA-256.
            guard binding.count == 32 else { throw ApprovalWire.DecodeError.invalidValue }
            payloadBinding = binding
        }
        let createdAtUnixMs = try r.i64()
        let expiresAtUnixMs = try r.i64()
        let requesterSigningPubKey = try r.blob()
        let requesterSignature = try r.blob()
        guard r.isAtEnd else { throw ApprovalWire.DecodeError.invalidValue }
        return ApprovalRequest(
            requestId: requestId, grantId: grantId,
            requesterDeviceId: requesterDeviceId, itemId: itemId,
            fieldId: fieldId, nonce: nonce,
            ephemeralPubKey: ephemeralPubKey,
            createdAtUnixMs: createdAtUnixMs, expiresAtUnixMs: expiresAtUnixMs,
            requesterSigningPubKey: requesterSigningPubKey,
            requesterSignature: requesterSignature,
            payloadBinding: payloadBinding)
    }
}

// MARK: - ApprovalResponse

extension ApprovalResponse {
    nonisolated func signingBody() -> Data {
        var w = CanonicalWriter()
        w.byte(ApprovalWire.version)
        w.byte(ApprovalWire.TypeTag.response.rawValue)
        w.string(requestId)
        w.byte(decision.rawValue)
        if let sealedPayload { w.byte(1); w.blob(sealedPayload) } else { w.byte(0) }
        w.i64(respondedAtUnixMs)
        w.blob(ownerSigningPubKey)
        return w.data
    }

    nonisolated func encoded() -> Data {
        var w = CanonicalWriter()
        w.raw(signingBody())
        w.blob(ownerSignature)
        return w.data
    }

    nonisolated static func decode(_ data: Data) throws -> ApprovalResponse {
        var r = CanonicalReader(data)
        guard try r.byte() == ApprovalWire.version else { throw ApprovalWire.DecodeError.unknownVersion }
        guard try r.byte() == ApprovalWire.TypeTag.response.rawValue else { throw ApprovalWire.DecodeError.wrongType }
        let requestId = try r.string()
        guard let decision = ApprovalDecision(rawValue: try r.byte()) else {
            throw ApprovalWire.DecodeError.invalidValue
        }
        let sealedPayload: Data?
        switch try r.byte() {
        case 0: sealedPayload = nil
        case 1: sealedPayload = try r.blob()
        default: throw ApprovalWire.DecodeError.invalidValue
        }
        let respondedAtUnixMs = try r.i64()
        let ownerSigningPubKey = try r.blob()
        let ownerSignature = try r.blob()
        guard r.isAtEnd else { throw ApprovalWire.DecodeError.invalidValue }
        return ApprovalResponse(
            requestId: requestId, decision: decision, sealedPayload: sealedPayload,
            respondedAtUnixMs: respondedAtUnixMs,
            ownerSigningPubKey: ownerSigningPubKey, ownerSignature: ownerSignature)
    }
}

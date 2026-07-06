import CryptoKit
import Foundation

/// Signed capability manifest — BE contract `LOOX-CAP-MANIFEST-V1` (frozen,
/// parity vector in VaultifyTests/Fixtures/cap-manifest-vectors-v1.json).
/// Distribution layer only: the workers' `capability_*` gate stays the
/// enforcement, so a stale manifest can never widen what the server allows.
///
/// Wire = ONE flat JSON document; the 64-byte raw P256 ECDSA signature (base64,
/// `signature` field) covers the canonical transcript below — NOT the JSON
/// bytes — so any party (worker, operator tooling, this verifier) reproduces
/// the exact signed bytes with its own CanonicalWriter.
nonisolated struct CapabilityManifest: Codable, Sendable, Equatable {

    /// Operator policy vocabulary of the manifest ("enabled", not "active").
    enum Policy: String, Codable, Sendable {
        case enabled, degraded, maintenance, disabled, retired

        /// Bridge to the service-state vocabulary the rest of the app uses.
        var serviceMode: CapabilityServiceMode {
            switch self {
            case .enabled: return .active
            case .degraded: return .degraded
            case .maintenance: return .maintenance
            case .disabled: return .disabled
            case .retired: return .retired
            }
        }
    }

    struct Entry: Codable, Sendable, Equatable {
        let policy: Policy
        /// Per-operation narrow-only overrides: "enabled" | "disabled".
        let operations: [String: String]
        let messageKey: String?

        enum CodingKeys: String, CodingKey {
            case policy, operations
            case messageKey = "message_key"
        }

        /// Operations the manifest explicitly disables (narrower than the
        /// per-mode default table; never widens past the code gate).
        var disabledOperations: Set<CapabilityOperation> {
            Set(operations.compactMap { key, state in
                state == "disabled" ? CapabilityOperation(rawValue: key) : nil
            })
        }
    }

    let schemaVersion: Int
    let manifestVersion: UInt64
    let keyID: String
    let issuedAt: Int64    // unix ms
    let expiresAt: Int64   // unix ms
    let capabilities: [String: Entry]
    let signature: String?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case manifestVersion = "manifest_version"
        case keyID = "key_id"
        case issuedAt = "issued_at"
        case expiresAt = "expires_at"
        case capabilities, signature
    }

    func entry(for id: CapabilityID) -> Entry? { capabilities[id.rawValue] }

    /// Canonical signing transcript (must match `loox-config/src/manifest.ts`
    /// byte-for-byte — parity-tested against the frozen vector):
    ///   raw("LOOX-CAP-MANIFEST-V1") ‖ byte(schema) ‖ u64(version) ‖
    ///   string(key_id) ‖ i64(issued) ‖ i64(expires) ‖ u32(#caps) ‖
    ///   ∀cap sorted: string(name) ‖ string(policy) ‖ u32(#ops) ‖
    ///     ∀op sorted: string(op) ‖ string(state) — then optString(message_key)
    var transcript: Data {
        var w = CanonicalWriter()
        w.raw(Data("LOOX-CAP-MANIFEST-V1".utf8))
        w.byte(UInt8(truncatingIfNeeded: schemaVersion))
        w.u64(manifestVersion)
        w.string(keyID)
        w.i64(issuedAt)
        w.i64(expiresAt)
        let names = capabilities.keys.sorted()
        w.u32(UInt32(names.count))
        for name in names {
            let entry = capabilities[name]!
            w.string(name)
            w.string(entry.policy.rawValue)
            let ops = entry.operations.keys.sorted()
            w.u32(UInt32(ops.count))
            for op in ops {
                w.string(op)
                w.string(entry.operations[op]!)
            }
            // optString: flag byte then string when present.
            if let key = entry.messageKey {
                w.byte(1)
                w.string(key)
            } else {
                w.byte(0)
            }
        }
        return w.data
    }
}

/// Pure verification: signature over the canonical transcript (trusted key set
/// by `key_id` — rotation = the app trusts old+new simultaneously), schema,
/// freshness window, strict anti-rollback (reject ≤ highest accepted).
nonisolated enum CapabilityManifestVerifier {
    static let supportedSchemaVersion = 1

    enum VerifyError: Error, Equatable {
        case malformedManifest
        case missingSignature
        case unknownKey(String)
        case badSignature
        case unsupportedSchema(Int)
        case notYetValid
        case expired
        case rollback(received: UInt64, highestAccepted: UInt64)
    }

    /// Operator signing keys (x963 P256), pinned by key_id. From the BE
    /// handoff 260706; fingerprint eee533bf…9a7da1.
    static let bundledTrustedKeys: [String: Data] = [
        "cap-2026-01": Data(base64Encoded:
            "BLwFFtj1orHb/wjU7ryCtg3pJI3soQp0HCUVa+q29MjjcQ3L2I+24ZYwXWnOZV4KPf08Jsv/i8vCLvbEI1WrHxQ=")!,
    ]

    static func verify(manifestData: Data,
                       trustedKeys: [String: Data],
                       now: Date,
                       highestAcceptedVersion: UInt64) throws -> CapabilityManifest {
        guard let manifest = try? JSONDecoder().decode(CapabilityManifest.self, from: manifestData) else {
            throw VerifyError.malformedManifest
        }
        guard let signatureB64 = manifest.signature,
              let rawSignature = Data(base64Encoded: signatureB64) else {
            throw VerifyError.missingSignature
        }
        guard let keyBytes = trustedKeys[manifest.keyID] else {
            throw VerifyError.unknownKey(manifest.keyID)
        }
        guard let key = try? P256.Signing.PublicKey(x963Representation: keyBytes),
              let signature = try? P256.Signing.ECDSASignature(rawRepresentation: rawSignature),
              key.isValidSignature(signature, for: manifest.transcript) else {
            throw VerifyError.badSignature
        }
        guard manifest.schemaVersion == supportedSchemaVersion else {
            throw VerifyError.unsupportedSchema(manifest.schemaVersion)
        }
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        guard nowMs >= manifest.issuedAt else { throw VerifyError.notYetValid }
        guard nowMs < manifest.expiresAt else { throw VerifyError.expired }
        // Strict: a re-served OLD version must never re-enable a capability
        // that a newer manifest retired (BE handoff §5).
        guard manifest.manifestVersion > highestAcceptedVersion else {
            throw VerifyError.rollback(received: manifest.manifestVersion,
                                       highestAccepted: highestAcceptedVersion)
        }
        return manifest
    }
}

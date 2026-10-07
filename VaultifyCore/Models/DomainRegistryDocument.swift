import CryptoKit
import Foundation

/// Signed auxiliary-domain registry — BE contract `LOOX-DOMAIN-REGISTRY-V1`
/// (frozen, parity vectors in `VaultifyTests/Fixtures/domain-registry-vectors-v1.json`).
/// Same trust root and verify pipeline shape as the capability manifest, but a
/// deliberately distinct MAGIC (a manifest must never verify as a registry or
/// vice versa) and an independent monotonic `registry_version`.
///
/// Wire strings (capabilities, lifecycle) stay VERBATIM in this type: the
/// transcript must reproduce exactly what was signed, so lenient typed mapping
/// (unknown capability → ignored, unknown lifecycle → fail-closed) happens
/// only after verification, in `descriptors`.
nonisolated struct DomainRegistryDocument: Codable, Sendable, Equatable {

    struct Domain: Codable, Sendable, Equatable {
        let id: String
        let displayName: String
        let emailAddressDomain: String?
        let shortLinkHost: String?
        let capabilities: [String]
        let lifecycle: String
        let isPrimaryEmailChoice: Bool
        let isPrimaryShortLinkChoice: Bool

        enum CodingKeys: String, CodingKey {
            case id
            case displayName = "display_name"
            case emailAddressDomain = "email_address_domain"
            case shortLinkHost = "short_link_host"
            case capabilities, lifecycle
            case isPrimaryEmailChoice = "is_primary_email_choice"
            case isPrimaryShortLinkChoice = "is_primary_short_link_choice"
        }
    }

    let schemaVersion: Int
    let registryVersion: UInt64
    let keyID: String
    /// "staging" | "production" — INSIDE the signed payload, so a staging
    /// document can never be replayed against a production install.
    let env: String
    let issuedAt: Int64    // unix ms
    let expiresAt: Int64   // unix ms
    let domains: [Domain]
    let signature: String?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case registryVersion = "registry_version"
        case keyID = "key_id"
        case env
        case issuedAt = "issued_at"
        case expiresAt = "expires_at"
        case domains, signature
    }

    /// Canonical signing transcript (must match the production encoder in
    /// `loox-config` byte-for-byte — parity-tested against the frozen vectors):
    ///   raw("LOOX-DOMAIN-REGISTRY-V1") ‖ byte(schema) ‖ u64(registry_version) ‖
    ///   string(key_id) ‖ string(env) ‖ i64(issued) ‖ i64(expires) ‖
    ///   u32(#domains) ‖ ∀domain sorted by id: string(id) ‖ string(display_name) ‖
    ///   optString(email_domain) ‖ optString(short_host) ‖ u32(#caps) ‖
    ///   ∀cap sorted: string(cap) — then string(lifecycle) ‖ byte(primaryEmail) ‖
    ///   byte(primaryShortLink)
    var transcript: Data {
        var w = CanonicalWriter()
        w.raw(Data("LOOX-DOMAIN-REGISTRY-V1".utf8))
        w.byte(UInt8(truncatingIfNeeded: schemaVersion))
        w.u64(registryVersion)
        w.string(keyID)
        w.string(env)
        w.i64(issuedAt)
        w.i64(expiresAt)
        let sorted = domains.sorted { $0.id < $1.id }
        w.u32(UInt32(sorted.count))
        for domain in sorted {
            w.string(domain.id)
            w.string(domain.displayName)
            w.optionalTranscriptString(domain.emailAddressDomain)
            w.optionalTranscriptString(domain.shortLinkHost)
            let caps = domain.capabilities.sorted()
            w.u32(UInt32(caps.count))
            for cap in caps { w.string(cap) }
            w.string(domain.lifecycle)
            w.byte(domain.isPrimaryEmailChoice ? 1 : 0)
            w.byte(domain.isPrimaryShortLinkChoice ? 1 : 0)
        }
        return w.data
    }

    /// Typed, lenient view for the trust set — call only AFTER verification.
    /// Unknown capability strings are ignored (a future capability must not
    /// break older clients); an unknown lifecycle maps to `createDisabled` —
    /// existing resources keep working, nothing new gets minted on a state
    /// this build doesn't understand.
    var descriptors: [AuxiliaryDomainDescriptor] {
        domains.map { domain in
            AuxiliaryDomainDescriptor(
                id: domain.id,
                displayName: domain.displayName,
                emailAddressDomain: domain.emailAddressDomain,
                shortLinkHost: domain.shortLinkHost,
                capabilities: Set(domain.capabilities.compactMap(AuxiliaryDomainCapability.init(rawValue:))),
                lifecycle: AuxiliaryDomainLifecycle(rawValue: domain.lifecycle) ?? .createDisabled,
                isPrimaryEmailChoice: domain.isPrimaryEmailChoice,
                isPrimaryShortLinkChoice: domain.isPrimaryShortLinkChoice)
        }
    }
}

private extension CanonicalWriter {
    /// Flag byte then the string when present — the registry encoder's
    /// optional-field convention (same as the manifest's message_key).
    nonisolated mutating func optionalTranscriptString(_ value: String?) {
        if let value { byte(1); string(value) } else { byte(0) }
    }
}

/// Pure verification, mirroring `CapabilityManifestVerifier`: signature over
/// the canonical transcript (shared trusted key set), schema, env binding,
/// freshness window, strict anti-rollback on the registry's OWN version.
nonisolated enum DomainRegistryVerifier {
    static let supportedSchemaVersion = 1

    enum VerifyError: Error, Equatable {
        case malformedDocument
        case missingSignature
        case unknownKey(String)
        case badSignature
        case unsupportedSchema(Int)
        case wrongEnvironment(String)
        case notYetValid
        case expired
        case rollback(received: UInt64, highestAccepted: UInt64)
    }

    static func verify(documentData: Data,
                       trustedKeys: [String: Data],
                       expectedEnv: String,
                       now: Date,
                       highestAcceptedVersion: UInt64) throws -> DomainRegistryDocument {
        let document = try authenticate(documentData: documentData, trustedKeys: trustedKeys,
                                        expectedEnv: expectedEnv)
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        guard nowMs >= document.issuedAt else { throw VerifyError.notYetValid }
        guard nowMs < document.expiresAt else { throw VerifyError.expired }
        guard document.registryVersion >= highestAcceptedVersion else {
            throw VerifyError.rollback(received: document.registryVersion,
                                       highestAccepted: highestAcceptedVersion)
        }
        return document
    }

    /// Address-only provenance. An expired registry may prove an issued
    /// namespace; it cannot be applied as current config or allow mutations.
    static func historicalMappings(documentData: Data,
                                   trustedKeys: [String: Data],
                                   expectedEnv: String,
                                   now: Date = .now) throws -> [String: String] {
        let document = try authenticate(documentData: documentData, trustedKeys: trustedKeys,
                                        expectedEnv: expectedEnv)
        guard document.issuedAt <= Int64(now.timeIntervalSince1970 * 1000),
              document.expiresAt > document.issuedAt else { throw VerifyError.notYetValid }
        var mappings: [String: String] = [:]
        let uniqueIDs = Set(document.domains.map(\.id))
        guard uniqueIDs.count == document.domains.count else { throw VerifyError.malformedDocument }
        for domain in document.domains {
            guard domain.capabilities.contains("email"), let hostname = domain.emailAddressDomain,
                  isEmailHostname(hostname) else { continue }
            mappings[domain.id] = hostname
        }
        return mappings
    }

    static func isEmailHostname(_ hostname: String) -> Bool {
        guard hostname == hostname.lowercased(), hostname.utf8.count <= 253 else { return false }
        let labels = hostname.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return false }
        return labels.allSatisfy { label in
            !label.isEmpty && label.utf8.count <= 63 && label.first != "-" && label.last != "-"
                && label.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
        }
    }

    private static func authenticate(documentData: Data, trustedKeys: [String: Data],
                                     expectedEnv: String) throws -> DomainRegistryDocument {
        guard let document = try? JSONDecoder().decode(DomainRegistryDocument.self, from: documentData) else {
            throw VerifyError.malformedDocument
        }
        guard let signatureB64 = document.signature,
              let rawSignature = Data(base64Encoded: signatureB64) else {
            throw VerifyError.missingSignature
        }
        guard let keyBytes = trustedKeys[document.keyID] else {
            throw VerifyError.unknownKey(document.keyID)
        }
        guard let key = try? P256.Signing.PublicKey(x963Representation: keyBytes),
              let signature = try? P256.Signing.ECDSASignature(rawRepresentation: rawSignature),
              key.isValidSignature(signature, for: document.transcript) else {
            throw VerifyError.badSignature
        }
        guard document.schemaVersion == supportedSchemaVersion else {
            throw VerifyError.unsupportedSchema(document.schemaVersion)
        }
        guard document.env == expectedEnv else {
            throw VerifyError.wrongEnvironment(document.env)
        }
        return document
    }
}

/// Bounded in-memory verification cache. No trust flag or hostname from sync
/// is accepted without verifying the sealed envelope against the bundled key.
nonisolated enum DomainRegistryMappingProof {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var verified: [Data: [String: String]] = [:]

    static func hostname(envelope: Data, domainID: String, snapshot: String) -> String? {
        guard DomainRegistryVerifier.isEmailHostname(snapshot) else { return nil }
        let mappings: [String: String]
        if let cached = lock.withLock({ verified[envelope] }) {
            mappings = cached
        } else {
            guard let checked = try? DomainRegistryVerifier.historicalMappings(
                documentData: envelope,
                trustedKeys: CapabilityManifestVerifier.bundledTrustedKeys,
                expectedEnv: RelayConfig.environment) else { return nil }
            mappings = checked
            lock.withLock {
                if verified.count >= 32 { verified.removeAll(keepingCapacity: true) }
                verified[envelope] = checked
            }
        }
        return mappings[domainID] == snapshot ? snapshot : nil
    }
}

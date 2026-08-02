import Foundation
import CryptoKit

/// Offline inspection of imported SSH key text.
///
/// Import-first contract: the ORIGINAL imported bytes are canonical and stored
/// verbatim; inspection only derives display metadata (algorithm, fingerprint,
/// comment, authorized_keys line) to sit next to them. Anything the parser
/// cannot prove is left nil and the result stays `verified == false` — the UI
/// then says "saved, not verified" instead of guessing.
///
/// Parsing is strictly bounded: 1 MiB input ceiling, at most 64 length-prefixed
/// fields per wire section, every field length checked against the remaining
/// bytes, no recursion. Malformed input degrades to a `.unknown` result and
/// never throws. Key material never appears in errors or logs.
nonisolated enum SSHKeyInspector {

    // MARK: - Result model

    enum KeyFormat: Equatable, Sendable {
        /// authorized_keys single line: `<alg> <base64 blob> [comment]`.
        case opensshPublic
        /// `-----BEGIN OPENSSH PRIVATE KEY-----` (openssh-key-v1 container).
        case opensshPrivate
        /// Traditional PEM (`BEGIN RSA/EC/DSA PRIVATE KEY`) — classified only.
        case pem
        /// PKCS#8 (`BEGIN [ENCRYPTED] PRIVATE KEY`) — classified only.
        case pkcs8
        case unknown
    }

    enum Algorithm: Equatable, Sendable {
        case ed25519
        case rsa
        case ecdsaP256
        case ecdsaP384
        case ecdsaP521
        /// A well-framed algorithm identifier this build does not model.
        case unknown(String)
    }

    struct InspectionResult: Equatable, Sendable {
        var format: KeyFormat = .unknown
        var algorithm: Algorithm?
        /// Key strength where derivable (RSA modulus bits, curve size).
        var bitSize: Int?
        var comment: String?
        /// `SHA256:<base64 without padding>` over the public key blob — the
        /// exact string `ssh-keygen -lf` prints.
        var sha256Fingerprint: String?
        /// authorized_keys form of the public half, when derivable.
        var publicKeyLine: String?
        /// Private keys only: the container declares a cipher/KDF.
        var isEncrypted = false
        /// True only when the structure was fully validated and, for private
        /// keys, the public half provably matches the private half.
        var verified = false

        /// Human-readable algorithm for the `ssh.algorithm` metadata field.
        var algorithmDisplay: String? {
            guard let algorithm else { return nil }
            switch algorithm {
            case .ed25519: return "ED25519"
            case .rsa: return bitSize.map { "RSA \($0)" } ?? "RSA"
            case .ecdsaP256: return "ECDSA P-256"
            case .ecdsaP384: return "ECDSA P-384"
            case .ecdsaP521: return "ECDSA P-521"
            case .unknown(let raw): return raw
            }
        }
    }

    // MARK: - Bounds

    /// Hard input ceiling — anything larger is refused before parsing.
    static let maxInputBytes = 1 << 20
    /// Maximum length-prefixed fields one wire section may declare.
    static let maxFields = 64

    // MARK: - Entry points

    static func inspect(_ text: String) -> InspectionResult {
        guard text.utf8.count <= maxInputBytes else { return InspectionResult() }
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let trimmed = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return InspectionResult() }
        if trimmed.contains(opensshPrivateHeader) { return inspectOpenSSHPrivate(trimmed) }
        if let armored = classifyOtherArmor(trimmed) { return armored }
        return inspectPublicLine(trimmed)
    }

    /// Off-main wrapper for import flows; parsing is pure and bounded.
    static func inspectDetached(_ text: String) async -> InspectionResult {
        await Task.detached(priority: .userInitiated) { inspect(text) }.value
    }

    // MARK: - OpenSSH private container (openssh-key-v1)

    private static let opensshPrivateHeader = "-----BEGIN OPENSSH PRIVATE KEY-----"
    private static let opensshPrivateFooter = "-----END OPENSSH PRIVATE KEY-----"

    private static func inspectOpenSSHPrivate(_ text: String) -> InspectionResult {
        guard let body = armorBody(of: text, header: opensshPrivateHeader,
                                   footer: opensshPrivateFooter),
              let data = Data(base64Encoded: body),
              data.count <= maxInputBytes
        else { return InspectionResult() }

        var reader = FieldReader(data)
        guard reader.consumeMagic() else { return InspectionResult() }

        // Magic proven: the format claim is honest even if the rest is opaque.
        var result = InspectionResult()
        result.format = .opensshPrivate

        guard let cipherName = reader.readStringField(),
              let kdfName = reader.readStringField(),
              reader.readField() != nil,                       // kdf options, opaque
              let keyCount = reader.readUInt32(), keyCount == 1,
              let publicBlob = reader.readField(), !publicBlob.isEmpty
        else { return result }

        result.isEncrypted = !(cipherName == "none" && kdfName == "none")
        result.sha256Fingerprint = fingerprint(of: publicBlob)

        let parsed = parsePublicBlob(publicBlob)
        if let parsed {
            result.algorithm = parsed.algorithm
            result.bitSize = parsed.bitSize
            result.publicKeyLine = parsed.name + " " + Data(publicBlob).base64EncodedString()
        }

        guard !result.isEncrypted,
              let parsed,
              let privateSection = reader.readField(), reader.isAtEnd
        else { return result }

        if let inner = parsePrivateSection(privateSection, expecting: parsed) {
            if let comment = inner.comment, !comment.isEmpty {
                result.comment = comment
                result.publicKeyLine = result.publicKeyLine.map { $0 + " " + comment }
            }
            result.verified = inner.verified
        }
        return result
    }

    private struct PrivateSectionInfo {
        let comment: String?
        let verified: Bool
    }

    /// Parses the UNENCRYPTED inner section: checkint pair, algorithm name,
    /// per-algorithm key fields, comment, then 1,2,3… padding. Any structural
    /// violation discards the whole section — header-derived facts stand alone.
    private static func parsePrivateSection(_ section: [UInt8],
                                            expecting header: PublicBlobInfo) -> PrivateSectionInfo? {
        var reader = FieldReader(section)
        guard let check1 = reader.readUInt32(),
              let check2 = reader.readUInt32(),
              check1 == check2,
              let innerName = reader.readStringField(),
              innerName == header.name
        else { return nil }

        var verified = false
        switch header.algorithm {
        case .ed25519:
            guard let publicKey = reader.readField(), publicKey.count == 32,
                  let privatePair = reader.readField(), privatePair.count == 64
            else { return nil }
            // openssh stores seed(32) || public(32); the seed must regenerate
            // the SAME public key the cleartext header advertises.
            let seed = Array(privatePair[0..<32])
            let embedded = Array(privatePair[32..<64])
            if embedded == publicKey,
               publicKey == header.ed25519Key,
               let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: Data(seed)),
               [UInt8](key.publicKey.rawRepresentation) == publicKey {
                verified = true
            }
        case .rsa:
            for _ in 0..<6 {                                    // n e d iqmp p q
                guard reader.readField() != nil else { return nil }
            }
        case .ecdsaP256, .ecdsaP384, .ecdsaP521:
            for _ in 0..<3 {                                    // curve point scalar
                guard reader.readField() != nil else { return nil }
            }
        case .unknown:
            return nil
        }

        guard let commentField = reader.readField(),
              let comment = String(bytes: commentField, encoding: .utf8)
        else { return nil }

        var expectedPad: UInt8 = 1
        while let byte = reader.readByte() {
            guard byte == expectedPad else { return nil }
            expectedPad &+= 1
        }
        return PrivateSectionInfo(comment: comment, verified: verified)
    }

    // MARK: - Other armors (classification only, stored opaque)

    private static func classifyOtherArmor(_ text: String) -> InspectionResult? {
        func result(_ format: KeyFormat, algorithm: Algorithm? = nil,
                    encrypted: Bool) -> InspectionResult {
            var r = InspectionResult()
            r.format = format
            r.algorithm = algorithm
            r.isEncrypted = encrypted
            return r
        }
        let legacyEncrypted = text.contains("Proc-Type: 4,ENCRYPTED")
        if text.contains("-----BEGIN RSA PRIVATE KEY-----") {
            return result(.pem, algorithm: .rsa, encrypted: legacyEncrypted)
        }
        if text.contains("-----BEGIN EC PRIVATE KEY-----") {
            return result(.pem, encrypted: legacyEncrypted)
        }
        if text.contains("-----BEGIN DSA PRIVATE KEY-----") {
            return result(.pem, algorithm: .unknown("DSA"), encrypted: legacyEncrypted)
        }
        if text.contains("-----BEGIN ENCRYPTED PRIVATE KEY-----") {
            return result(.pkcs8, encrypted: true)
        }
        if text.contains("-----BEGIN PRIVATE KEY-----") {
            return result(.pkcs8, encrypted: false)
        }
        return nil
    }

    // MARK: - OpenSSH public line (authorized_keys form)

    private static func inspectPublicLine(_ text: String) -> InspectionResult {
        guard let line = text.split(separator: "\n")
            .map({ $0.trimmingCharacters(in: .whitespaces) })
            .first(where: { !$0.isEmpty })
        else { return InspectionResult() }

        let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard tokens.count >= 2 else { return InspectionResult() }

        let outerName = tokens[0]
        guard outerName.hasPrefix("ssh-") || outerName.hasPrefix("ecdsa-")
                || outerName.hasPrefix("sk-")
        else { return InspectionResult() }

        guard let blobData = Data(base64Encoded: tokens[1]),
              !blobData.isEmpty, blobData.count <= maxInputBytes
        else { return InspectionResult() }
        let blob = [UInt8](blobData)

        // The name inside the blob is authoritative and must match the outer
        // token — a mismatch is a spoofed line, not a salvageable key.
        guard let parsed = parsePublicBlob(blob), parsed.name == outerName
        else { return InspectionResult() }

        var result = InspectionResult()
        result.format = .opensshPublic
        result.algorithm = parsed.algorithm
        result.bitSize = parsed.bitSize
        result.sha256Fingerprint = fingerprint(of: blob)
        result.verified = parsed.fullyValidated

        let comment = tokens.dropFirst(2).joined(separator: " ")
        result.comment = comment.isEmpty ? nil : comment
        result.publicKeyLine = ([outerName, tokens[1]] + (comment.isEmpty ? [] : [comment]))
            .joined(separator: " ")
        return result
    }

    // MARK: - Public key blob

    private struct PublicBlobInfo {
        let name: String
        let algorithm: Algorithm
        let bitSize: Int?
        /// ed25519 only: the 32-byte public key, for pair verification.
        let ed25519Key: [UInt8]?
        /// Whether the per-algorithm inner structure was checked, not just framing.
        let fullyValidated: Bool
    }

    private static func parsePublicBlob(_ blob: [UInt8]) -> PublicBlobInfo? {
        var reader = FieldReader(blob)
        guard let nameField = reader.readField(),
              let name = String(bytes: nameField, encoding: .utf8),
              !name.isEmpty
        else { return nil }

        switch name {
        case "ssh-ed25519":
            guard let key = reader.readField(), key.count == 32, reader.isAtEnd
            else { return nil }
            return PublicBlobInfo(name: name, algorithm: .ed25519, bitSize: 256,
                                  ed25519Key: key, fullyValidated: true)

        case "ssh-rsa":
            guard let exponent = reader.readField(), !exponent.isEmpty,
                  let modulus = reader.readField(), !modulus.isEmpty,
                  reader.isAtEnd
            else { return nil }
            return PublicBlobInfo(name: name, algorithm: .rsa,
                                  bitSize: mpintBitCount(modulus),
                                  ed25519Key: nil, fullyValidated: true)

        case "ecdsa-sha2-nistp256", "ecdsa-sha2-nistp384", "ecdsa-sha2-nistp521":
            let (algorithm, bits, coordBytes): (Algorithm, Int, Int) = switch name {
            case "ecdsa-sha2-nistp256": (.ecdsaP256, 256, 32)
            case "ecdsa-sha2-nistp384": (.ecdsaP384, 384, 48)
            default: (.ecdsaP521, 521, 66)
            }
            let expectedCurve = String(name.dropFirst("ecdsa-sha2-".count))
            guard let curveField = reader.readField(),
                  String(bytes: curveField, encoding: .utf8) == expectedCurve,
                  let point = reader.readField(),
                  isValidECPoint(point, coordBytes: coordBytes),
                  reader.isAtEnd
            else { return nil }
            return PublicBlobInfo(name: name, algorithm: algorithm, bitSize: bits,
                                  ed25519Key: nil, fullyValidated: true)

        default:
            // Unknown algorithm: accept only if the whole blob is well-framed;
            // fingerprint stays derivable, structure stays unverified.
            while !reader.isAtEnd {
                guard reader.readField() != nil else { return nil }
            }
            return PublicBlobInfo(name: name, algorithm: .unknown(name), bitSize: nil,
                                  ed25519Key: nil, fullyValidated: false)
        }
    }

    private static func isValidECPoint(_ point: [UInt8], coordBytes: Int) -> Bool {
        guard let first = point.first else { return false }
        if first == 0x04 { return point.count == 1 + 2 * coordBytes }
        if first == 0x02 || first == 0x03 { return point.count == 1 + coordBytes }
        return false
    }

    /// Bit length of an ssh mpint (big-endian, possible 0x00 sign byte).
    private static func mpintBitCount(_ bytes: [UInt8]) -> Int? {
        var significant = bytes[...]
        while significant.first == 0 { significant = significant.dropFirst() }
        guard let first = significant.first else { return nil }
        return (significant.count - 1) * 8 + (8 - first.leadingZeroBitCount)
    }

    // MARK: - Shared helpers

    private static func fingerprint(of blob: [UInt8]) -> String {
        let digest = SHA256.hash(data: Data(blob))
        let base64 = Data(digest).base64EncodedString()
        return "SHA256:" + base64.replacingOccurrences(of: "=", with: "")
    }

    private static func armorBody(of text: String, header: String, footer: String) -> String? {
        guard let headerRange = text.range(of: header),
              let footerRange = text.range(of: footer),
              headerRange.upperBound <= footerRange.lowerBound
        else { return nil }
        let body = text[headerRange.upperBound..<footerRange.lowerBound]
            .filter { !$0.isWhitespace }
        return body.isEmpty ? nil : String(body)
    }

    /// Bounded big-endian reader over `uint32`-length-prefixed fields. Every
    /// read checks the remaining byte count; a section may declare at most
    /// `maxFields` fields; there is no recursion and no unchecked arithmetic.
    private struct FieldReader {
        private let bytes: [UInt8]
        private var offset = 0
        private var fieldsRead = 0

        init(_ data: Data) { bytes = [UInt8](data) }
        init(_ bytes: [UInt8]) { self.bytes = bytes }

        var isAtEnd: Bool { offset == bytes.count }
        var remaining: Int { bytes.count - offset }

        mutating func consumeMagic() -> Bool {
            let magic = Array("openssh-key-v1".utf8) + [0]
            guard remaining >= magic.count,
                  Array(bytes[offset..<offset + magic.count]) == magic
            else { return false }
            offset += magic.count
            return true
        }

        mutating func readByte() -> UInt8? {
            guard remaining >= 1 else { return nil }
            defer { offset += 1 }
            return bytes[offset]
        }

        mutating func readUInt32() -> UInt32? {
            guard remaining >= 4 else { return nil }
            let value = UInt32(bytes[offset]) << 24
                | UInt32(bytes[offset + 1]) << 16
                | UInt32(bytes[offset + 2]) << 8
                | UInt32(bytes[offset + 3])
            offset += 4
            return value
        }

        mutating func readField() -> [UInt8]? {
            guard fieldsRead < SSHKeyInspector.maxFields else { return nil }
            fieldsRead += 1
            guard let declared = readUInt32() else { return nil }
            let length = Int(declared)
            guard length <= remaining else { return nil }
            defer { offset += length }
            return Array(bytes[offset..<offset + length])
        }

        mutating func readStringField() -> String? {
            guard let field = readField() else { return nil }
            return String(bytes: field, encoding: .utf8)
        }
    }
}

// MARK: - Template field mapping

/// Pure mapping of an inspection result onto the `developer.ssh-key`
/// template's fields. The imported text is canonical: it lands in the key
/// field byte-for-byte VERBATIM; only derived metadata is written beside it.
/// Metadata fields the item does not yet carry are appended from the registry
/// template so their semantics (role, sensitivity, section) are stamped.
nonisolated enum SSHKeyImportMapper {

    static func fields(applying result: SSHKeyInspector.InspectionResult,
                       originalText: String,
                       to fields: [DynamicField]) -> [DynamicField] {
        var updated = fields

        func upsert(_ roleID: FieldRoleID, _ value: String) {
            if let index = updated.firstIndex(where: { $0.roleID == roleID }) {
                updated[index].value = value
            } else if var field = templateField(for: roleID) {
                field.value = value
                updated.append(field)
            }
        }

        switch result.format {
        case .opensshPublic:
            upsert(.sshPublicKey, originalText)
        case .opensshPrivate, .pem, .pkcs8, .unknown:
            // Unknown material is treated as a private key: it stays inside
            // the protected key-material slot, never a looser field.
            upsert(.sshPrivateKey, originalText)
            if let line = result.publicKeyLine { upsert(.sshPublicKey, line) }
        }
        if let algorithm = result.algorithmDisplay { upsert(.sshAlgorithm, algorithm) }
        if let fingerprint = result.sha256Fingerprint { upsert(.sshFingerprint, fingerprint) }
        if let comment = result.comment, !comment.isEmpty { upsert(.sshComment, comment) }
        return updated
    }

    private static func templateField(for roleID: FieldRoleID) -> DynamicField? {
        guard let template = ItemTemplateRegistry.definition(for: .sshKey) else { return nil }
        for section in template.sections {
            if let descriptor = section.fields.first(where: { $0.roleID == roleID }) {
                return descriptor.makeField(sectionID: section.id)
            }
        }
        return nil
    }
}

import XCTest
@testable import Vaultify

/// SSH inspection must derive exactly what ssh-keygen derives — fingerprints
/// are compared byte-for-byte against captured `ssh-keygen -lf` output — and
/// must degrade to an honest `.unknown` (never a crash, never a guess) for
/// malformed, oversized, or adversarially framed input. The imported text is
/// canonical: the mapper stores it verbatim and only writes metadata beside it.
final class SSHKeyInspectorTests: XCTestCase {

    // MARK: - Fixture access

    private static let vectorNames = [
        "ssh-test-vector-ed25519",
        "ssh-test-vector-rsa2048",
        "ssh-test-vector-ecdsa256",
        "ssh-test-vector-ed25519-pass",
    ]

    private func fixtureText(_ name: String, _ ext: String) throws -> String {
        let bundle = Bundle(for: SSHKeyInspectorTests.self)
        let url = bundle.url(forResource: name, withExtension: ext,
                             subdirectory: "ssh-vectors-v1")
            ?? bundle.url(forResource: name, withExtension: ext)
        return try String(contentsOf: XCTUnwrap(url, "missing fixture \(name).\(ext)"),
                          encoding: .utf8)
    }

    /// `expected-fingerprints.txt` lines: `<name> <bits> SHA256:<b64> <comment> (<ALG>)`.
    private func expectedVectors() throws -> [String: (bits: Int, fingerprint: String)] {
        let text = try fixtureText("expected-fingerprints", "txt")
        var out: [String: (Int, String)] = [:]
        for line in text.split(separator: "\n") {
            let tokens = line.split(separator: " ")
            guard tokens.count >= 3, let bits = Int(tokens[1]) else { continue }
            out[String(tokens[0])] = (bits, String(tokens[2]))
        }
        XCTAssertEqual(out.count, Self.vectorNames.count, "fingerprint fixture incomplete")
        return out
    }

    // MARK: - ssh-keygen parity

    func testPublicKeyFingerprintParityWithSSHKeygen() throws {
        let expected = try expectedVectors()
        for name in Self.vectorNames {
            let result = SSHKeyInspector.inspect(try fixtureText(name, "pub"))
            XCTAssertEqual(result.format, .opensshPublic, name)
            XCTAssertEqual(result.sha256Fingerprint, expected[name]?.fingerprint, name)
            XCTAssertEqual(result.bitSize, expected[name]?.bits, name)
            XCTAssertTrue(result.verified, name)
            XCTAssertFalse(result.isEncrypted, name)
        }
    }

    func testPrivateKeyFingerprintParityWithSSHKeygen() throws {
        let expected = try expectedVectors()
        for name in Self.vectorNames {
            let result = SSHKeyInspector.inspect(try fixtureText(name, "key"))
            XCTAssertEqual(result.format, .opensshPrivate, name)
            XCTAssertEqual(result.sha256Fingerprint, expected[name]?.fingerprint, name)
            XCTAssertEqual(result.bitSize, expected[name]?.bits, name)
        }
    }

    func testEd25519PrivatePairIsCryptographicallyVerified() throws {
        let result = SSHKeyInspector.inspect(try fixtureText("ssh-test-vector-ed25519", "key"))
        XCTAssertEqual(result.algorithm, .ed25519)
        XCTAssertFalse(result.isEncrypted)
        XCTAssertTrue(result.verified)
        XCTAssertEqual(result.comment, "vaultify-test-ed25519")
        // The derived authorized_keys line must reproduce the .pub file exactly.
        let pubLine = try fixtureText("ssh-test-vector-ed25519", "pub")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(result.publicKeyLine, pubLine)
    }

    func testUnencryptedNonEd25519ExtractsCommentButStaysUnverified() throws {
        let cases: [(String, SSHKeyInspector.Algorithm, String)] = [
            ("ssh-test-vector-rsa2048", .rsa, "vaultify-test-rsa2048"),
            ("ssh-test-vector-ecdsa256", .ecdsaP256, "vaultify-test-ecdsa256"),
        ]
        for (name, algorithm, comment) in cases {
            let result = SSHKeyInspector.inspect(try fixtureText(name, "key"))
            XCTAssertEqual(result.algorithm, algorithm, name)
            XCTAssertEqual(result.comment, comment, name)
            XCTAssertFalse(result.isEncrypted, name)
            // Only an ed25519 pair is cryptographically cross-checked.
            XCTAssertFalse(result.verified, name)
            let pubLine = try fixtureText(name, "pub")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertEqual(result.publicKeyLine, pubLine, name)
        }
    }

    func testEncryptedPrivateKeyDetectedWithFingerprintStillDerived() throws {
        let expected = try expectedVectors()
        let result = SSHKeyInspector.inspect(try fixtureText("ssh-test-vector-ed25519-pass", "key"))
        XCTAssertEqual(result.format, .opensshPrivate)
        XCTAssertTrue(result.isEncrypted)
        XCTAssertFalse(result.verified)
        XCTAssertEqual(result.algorithm, .ed25519)
        // The public blob sits in the clear in the container header.
        XCTAssertEqual(result.sha256Fingerprint,
                       expected["ssh-test-vector-ed25519-pass"]?.fingerprint)
        // The comment lives in the ENCRYPTED section and must not be guessed.
        XCTAssertNil(result.comment)
    }

    // MARK: - Normalization and comments

    func testCRLFInputMatchesLFInput() throws {
        for ext in ["pub", "key"] {
            let original = try fixtureText("ssh-test-vector-ed25519", ext)
            let crlf = original.replacingOccurrences(of: "\n", with: "\r\n")
            XCTAssertEqual(SSHKeyInspector.inspect(crlf),
                           SSHKeyInspector.inspect(original), ext)
        }
    }

    func testCommentWithSpacesIsExtractedWhole() throws {
        let pub = try fixtureText("ssh-test-vector-ed25519", "pub")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = pub.split(separator: " ").map(String.init)
        let line = "\(tokens[0]) \(tokens[1]) deploy key for server"
        let result = SSHKeyInspector.inspect(line)
        XCTAssertEqual(result.format, .opensshPublic)
        XCTAssertEqual(result.comment, "deploy key for server")
        XCTAssertEqual(result.publicKeyLine, line)
    }

    func testMissingCommentIsNilNotEmpty() throws {
        let pub = try fixtureText("ssh-test-vector-ed25519", "pub")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = pub.split(separator: " ").map(String.init)
        let result = SSHKeyInspector.inspect("\(tokens[0]) \(tokens[1])")
        XCTAssertEqual(result.format, .opensshPublic)
        XCTAssertNil(result.comment)
    }

    // MARK: - PEM / PKCS#8 classification

    func testPEMAndPKCS8AreClassifiedOnlyNeverVerified() {
        let rsaPEM = "-----BEGIN RSA PRIVATE KEY-----\nAAAA\n-----END RSA PRIVATE KEY-----"
        var result = SSHKeyInspector.inspect(rsaPEM)
        XCTAssertEqual(result.format, .pem)
        XCTAssertEqual(result.algorithm, .rsa)
        XCTAssertFalse(result.isEncrypted)
        XCTAssertFalse(result.verified)
        XCTAssertNil(result.sha256Fingerprint)

        let encryptedPEM = """
        -----BEGIN RSA PRIVATE KEY-----
        Proc-Type: 4,ENCRYPTED
        DEK-Info: AES-128-CBC,ABCD

        AAAA
        -----END RSA PRIVATE KEY-----
        """
        result = SSHKeyInspector.inspect(encryptedPEM)
        XCTAssertEqual(result.format, .pem)
        XCTAssertTrue(result.isEncrypted)

        result = SSHKeyInspector.inspect(
            "-----BEGIN EC PRIVATE KEY-----\nAAAA\n-----END EC PRIVATE KEY-----")
        XCTAssertEqual(result.format, .pem)
        XCTAssertNil(result.algorithm)

        result = SSHKeyInspector.inspect(
            "-----BEGIN PRIVATE KEY-----\nAAAA\n-----END PRIVATE KEY-----")
        XCTAssertEqual(result.format, .pkcs8)
        XCTAssertFalse(result.isEncrypted)

        result = SSHKeyInspector.inspect(
            "-----BEGIN ENCRYPTED PRIVATE KEY-----\nAAAA\n-----END ENCRYPTED PRIVATE KEY-----")
        XCTAssertEqual(result.format, .pkcs8)
        XCTAssertTrue(result.isEncrypted)
        XCTAssertFalse(result.verified)
    }

    // MARK: - Malformed input

    func testMalformedInputsLandInUnknownWithoutCrash() {
        let garbage: [String] = [
            "",
            "   \n\n  ",
            "not a key at all",
            "ssh-ed25519",                             // missing blob
            "ssh-ed25519 %%%not-base64%%%",
            "ssh-ed25519 " + Data([0xde, 0xad, 0xbe, 0xef]).base64EncodedString(),
            "rsa AAAA comment",                        // outer token not an ssh alg
            String(repeating: "a", count: SSHKeyInspector.maxInputBytes + 1),
        ]
        for input in garbage {
            let result = SSHKeyInspector.inspect(input)
            XCTAssertEqual(result.format, .unknown, String(input.prefix(24)))
            XCTAssertFalse(result.verified)
            XCTAssertNil(result.sha256Fingerprint)
        }
    }

    func testOpenSSHArmorWithBadMagicIsUnknown() {
        let body = Data("this is not openssh-key-v1 content".utf8).base64EncodedString()
        let text = "-----BEGIN OPENSSH PRIVATE KEY-----\n\(body)\n-----END OPENSSH PRIVATE KEY-----"
        XCTAssertEqual(SSHKeyInspector.inspect(text).format, .unknown)
    }

    func testOpenSSHArmorWithValidMagicButTruncatedBodyStaysOpaque() {
        var bytes = Array("openssh-key-v1".utf8) + [0]
        bytes += [0x00, 0x00]                          // truncated cipher length prefix
        let body = Data(bytes).base64EncodedString()
        let text = "-----BEGIN OPENSSH PRIVATE KEY-----\n\(body)\n-----END OPENSSH PRIVATE KEY-----"
        let result = SSHKeyInspector.inspect(text)
        // The container claim is proven by magic; everything else is honestly absent.
        XCTAssertEqual(result.format, .opensshPrivate)
        XCTAssertNil(result.algorithm)
        XCTAssertNil(result.sha256Fingerprint)
        XCTAssertFalse(result.verified)
    }

    // MARK: - Framing attacks

    private func lengthPrefixed(_ bytes: [UInt8]) -> [UInt8] {
        let n = UInt32(bytes.count)
        return [UInt8(truncatingIfNeeded: n >> 24), UInt8(truncatingIfNeeded: n >> 16),
                UInt8(truncatingIfNeeded: n >> 8), UInt8(truncatingIfNeeded: n)] + bytes
    }

    private func lengthPrefixed(_ string: String) -> [UInt8] {
        lengthPrefixed(Array(string.utf8))
    }

    private func publicLine(algorithm: String, blob: [UInt8]) -> String {
        "\(algorithm) \(Data(blob).base64EncodedString())"
    }

    func testFramingAttacksAreRejected() {
        // Length prefix claims 4 GiB with 11 bytes present.
        let hugeClaim: [UInt8] = [0xff, 0xff, 0xff, 0xff] + Array("ssh-ed25519".utf8)
        XCTAssertEqual(SSHKeyInspector.inspect(
            publicLine(algorithm: "ssh-ed25519", blob: hugeClaim)).format, .unknown)

        // Truncated length prefix after a valid name field.
        let truncated = lengthPrefixed("ssh-ed25519") + [0x00, 0x00]
        XCTAssertEqual(SSHKeyInspector.inspect(
            publicLine(algorithm: "ssh-ed25519", blob: truncated)).format, .unknown)

        // Inner field length larger than the remaining bytes.
        let oversized = lengthPrefixed("ssh-ed25519") + [0x00, 0x00, 0x00, 0x40]
            + [UInt8](repeating: 0xaa, count: 32)
        XCTAssertEqual(SSHKeyInspector.inspect(
            publicLine(algorithm: "ssh-ed25519", blob: oversized)).format, .unknown)

        // Wrong key length for the declared algorithm.
        let shortKey = lengthPrefixed("ssh-ed25519")
            + lengthPrefixed([UInt8](repeating: 0xaa, count: 31))
        XCTAssertEqual(SSHKeyInspector.inspect(
            publicLine(algorithm: "ssh-ed25519", blob: shortKey)).format, .unknown)

        // Trailing bytes after a structurally complete key.
        let trailing = lengthPrefixed("ssh-ed25519")
            + lengthPrefixed([UInt8](repeating: 0xaa, count: 32)) + [0x00]
        XCTAssertEqual(SSHKeyInspector.inspect(
            publicLine(algorithm: "ssh-ed25519", blob: trailing)).format, .unknown)

        // Algorithm name inside the blob must match the outer token.
        let rsaBlob = lengthPrefixed("ssh-rsa") + lengthPrefixed([0x01, 0x00, 0x01])
            + lengthPrefixed([UInt8](repeating: 0xbb, count: 256))
        XCTAssertEqual(SSHKeyInspector.inspect(
            publicLine(algorithm: "ssh-ed25519", blob: rsaBlob)).format, .unknown)

        // More inner fields than the hard cap.
        var flood = lengthPrefixed("ssh-flood@test")
        for _ in 0..<(SSHKeyInspector.maxFields + 8) { flood += [0x00, 0x00, 0x00, 0x00] }
        XCTAssertEqual(SSHKeyInspector.inspect(
            publicLine(algorithm: "ssh-flood@test", blob: flood)).format, .unknown)
    }

    func testUnknownAlgorithmWellFramedBlobIsHonestlyUnverified() {
        let name = "ssh-custom@example.com"
        let blob = lengthPrefixed(name)
            + lengthPrefixed([UInt8](repeating: 0x11, count: 16))
            + lengthPrefixed([UInt8](repeating: 0x22, count: 8))
        let result = SSHKeyInspector.inspect(publicLine(algorithm: name, blob: blob))
        XCTAssertEqual(result.format, .opensshPublic)
        XCTAssertEqual(result.algorithm, .unknown(name))
        XCTAssertNotNil(result.sha256Fingerprint)
        XCTAssertFalse(result.verified)
    }

    // MARK: - Template field mapping

    private func sshTemplateFields() throws -> [DynamicField] {
        try XCTUnwrap(ItemTemplateRegistry.definition(for: .sshKey)).defaultFields
    }

    func testMapperStoresPrivateKeyVerbatimAndFillsMetadata() throws {
        let original = try fixtureText("ssh-test-vector-ed25519", "key")
        let result = SSHKeyInspector.inspect(original)
        let fields = SSHKeyImportMapper.fields(applying: result, originalText: original,
                                               to: try sshTemplateFields())

        let privateField = try XCTUnwrap(fields.first { $0.roleID == .sshPrivateKey })
        XCTAssertEqual(privateField.value, original,
                       "imported bytes are canonical and must survive verbatim")

        let publicField = try XCTUnwrap(fields.first { $0.roleID == .sshPublicKey })
        let pubLine = try fixtureText("ssh-test-vector-ed25519", "pub")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(publicField.value, pubLine)

        XCTAssertEqual(fields.first { $0.roleID == .sshAlgorithm }?.value, "ED25519")
        XCTAssertEqual(fields.first { $0.roleID == .sshFingerprint }?.value,
                       result.sha256Fingerprint)
        XCTAssertEqual(fields.first { $0.roleID == .sshComment }?.value,
                       "vaultify-test-ed25519")
        // Appended metadata fields must carry registry semantics, not bare labels.
        let fingerprintField = try XCTUnwrap(fields.first { $0.roleID == .sshFingerprint })
        XCTAssertEqual(fingerprintField.semantics?.sectionID, "metadata")
    }

    func testMapperPublicImportFillsPublicSlotOnly() throws {
        let original = try fixtureText("ssh-test-vector-ed25519", "pub")
        let result = SSHKeyInspector.inspect(original)
        let fields = SSHKeyImportMapper.fields(applying: result, originalText: original,
                                               to: try sshTemplateFields())
        XCTAssertEqual(fields.first { $0.roleID == .sshPublicKey }?.value, original)
        XCTAssertEqual(fields.first { $0.roleID == .sshPrivateKey }?.value, "")
        XCTAssertEqual(fields.first { $0.roleID == .sshAlgorithm }?.value, "ED25519")
    }

    func testMapperUnknownInputStaysOpaqueInPrivateSlot() throws {
        let original = "definitely not any kind of key"
        let result = SSHKeyInspector.inspect(original)
        XCTAssertEqual(result.format, .unknown)
        let base = try sshTemplateFields()
        let fields = SSHKeyImportMapper.fields(applying: result, originalText: original,
                                               to: base)
        // Unknown material lands in the protected key slot; nothing is invented.
        XCTAssertEqual(fields.first { $0.roleID == .sshPrivateKey }?.value, original)
        XCTAssertEqual(fields.count, base.count)
        XCTAssertNil(fields.first { $0.roleID == .sshAlgorithm })
        XCTAssertNil(fields.first { $0.roleID == .sshFingerprint })
    }

    func testMapperEncryptedImportFillsDerivedMetadataWithoutComment() throws {
        let original = try fixtureText("ssh-test-vector-ed25519-pass", "key")
        let result = SSHKeyInspector.inspect(original)
        let fields = SSHKeyImportMapper.fields(applying: result, originalText: original,
                                               to: try sshTemplateFields())
        XCTAssertEqual(fields.first { $0.roleID == .sshPrivateKey }?.value, original)
        XCTAssertEqual(fields.first { $0.roleID == .sshAlgorithm }?.value, "ED25519")
        XCTAssertNotNil(fields.first { $0.roleID == .sshFingerprint })
        XCTAssertNil(fields.first { $0.roleID == .sshComment })
    }
}

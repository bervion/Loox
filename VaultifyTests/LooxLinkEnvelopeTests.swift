import XCTest
@testable import Vaultify

/// Envelope hardening (M2) + wire-crypto layout (A2): excluded fields are
/// absent (not hidden), the TOTP seed / guard2 / attachments can never be
/// offered, and the AES-GCM output matches the Web Crypto layout the viewer
/// decrypts (tag appended, base64 body, base64url fragment key).
final class LooxLinkEnvelopeTests: XCTestCase {

    private func makeItem() -> VaultItem {
        VaultItem(category: .login, title: "Example", fields: [
            DynamicField(id: "f-user", label: "Username", kind: .username, value: "ada@example.com"),
            DynamicField(id: "f-pass", label: "Password", kind: .password, value: "hunter2"),
            DynamicField(id: "f-url", label: "Website", kind: .url, value: "https://example.com"),
            DynamicField(id: "f-totp", label: "One-time Code", kind: .totp, value: "JBSWY3DPEHPK3PXP"),
            DynamicField(id: "f-note", label: "Note", kind: .multiline, value: "some note"),
            DynamicField(id: "f-guard", label: "Recovery", kind: .text, value: "opaque", guard2: true),
            DynamicField(id: "f-empty", label: "Empty", kind: .text, value: "  "),
        ])
    }

    func testShareableFieldsExcludeTOTPGuard2AttachmentsAndEmpty() {
        let ids = LooxLinkEnvelope.shareableFields(of: makeItem()).map(\.id)
        XCTAssertEqual(ids, ["f-user", "f-pass", "f-url", "f-note"])
    }

    func testDefaultSelectionIsCredentialTrio() {
        let defaults = LooxLinkEnvelope.defaultSelectedFieldIDs(of: makeItem())
        XCTAssertEqual(defaults, ["f-user", "f-pass", "f-url"])
    }

    func testBuildPreservesOrderOmitsUnselectedAndConcealsSecrets() throws {
        let item = makeItem()
        // Select everything shareable PLUS the forbidden ids — the builder
        // must silently drop the forbidden ones (selection can't smuggle).
        let envelope = LooxLinkEnvelope.build(
            item: item,
            selectedFieldIDs: ["f-user", "f-pass", "f-note", "f-totp", "f-guard"])

        XCTAssertEqual(envelope.version, 1)
        XCTAssertEqual(envelope.fields.map(\.value),
                       ["ada@example.com", "hunter2", "some note"])
        XCTAssertEqual(envelope.fields.map(\.kind), ["username", "password", "note"])
        // concealed: display hint on protected values only, omitted otherwise.
        XCTAssertNil(envelope.fields[0].concealed)
        XCTAssertEqual(envelope.fields[1].concealed, true)

        // Excluded values must not appear ANYWHERE in the plaintext JSON.
        let json = String(decoding: try envelope.encoded(), as: UTF8.self)
        XCTAssertFalse(json.contains("JBSWY3DPEHPK3PXP"))
        XCTAssertFalse(json.contains("opaque"))
        XCTAssertFalse(json.contains("example.com/")) // unselected url absent too
    }

    func testEncryptDecryptRoundTripMatchesViewerLayout() throws {
        let envelope = LooxLinkEnvelope(fields: [
            .init(label: "Password", value: "hunter2", concealed: true, kind: "password"),
        ])
        let plaintext = try envelope.encoded()
        let cipher = try LooxLinkCrypto.encrypt(plaintext)

        // Wire layout: body fields are standard base64; iv is 12 bytes;
        // ciphertext carries the 16-byte tag appended.
        XCTAssertEqual(Data(base64Encoded: cipher.ivB64)?.count, 12)
        XCTAssertEqual(Data(base64Encoded: cipher.ciphertextB64)?.count, plaintext.count + 16)
        // Fragment key: base64url, unpadded, 32 raw bytes.
        XCTAssertFalse(cipher.fragmentKey.contains("+"))
        XCTAssertFalse(cipher.fragmentKey.contains("/"))
        XCTAssertFalse(cipher.fragmentKey.contains("="))
        XCTAssertEqual(LooxLinkCrypto.base64urlDecode(cipher.fragmentKey)?.count, 32)

        let decrypted = try LooxLinkCrypto.decrypt(
            ciphertextB64: cipher.ciphertextB64, ivB64: cipher.ivB64,
            fragmentKey: cipher.fragmentKey)
        XCTAssertEqual(try JSONDecoder().decode(LooxLinkEnvelope.self, from: decrypted), envelope)
    }

    func testTamperedFragmentKeyFailsClosed() throws {
        let cipher = try LooxLinkCrypto.encrypt(Data("secret".utf8))
        var tampered = cipher.fragmentKey
        let first = tampered.removeFirst()
        tampered.insert(first == "A" ? "B" : "A", at: tampered.startIndex)
        XCTAssertThrowsError(try LooxLinkCrypto.decrypt(
            ciphertextB64: cipher.ciphertextB64, ivB64: cipher.ivB64, fragmentKey: tampered))
    }

    func testFreshKeyAndNoncePerShare() throws {
        let a = try LooxLinkCrypto.encrypt(Data("x".utf8))
        let b = try LooxLinkCrypto.encrypt(Data("x".utf8))
        XCTAssertNotEqual(a.fragmentKey, b.fragmentKey)
        XCTAssertNotEqual(a.ivB64, b.ivB64)
    }
}

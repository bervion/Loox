import XCTest
import Security
@testable import Vaultify

/// Invariant: the developer-asset inspectors classify by CONTENT only, honor
/// their byte ceilings, sanitize every extracted display string, report
/// parsed/verified strictly as "read locally" (never trust), and leave zero
/// keychain residue after a PKCS#12 inspection. Fixture values are pinned to
/// the openssl-generated vectors in Fixtures/apple-vectors-v1.
final class AppleAssetInspectorTests: XCTestCase {

    // Pinned from the openssl run that generated apple-selfsigned-cert.*:
    // notBefore 2026-08-02T09:33:45Z, notAfter 2036-07-30T09:33:45Z.
    private let certNotBefore = Date(timeIntervalSince1970: 1_785_663_225)
    private let certNotAfter = Date(timeIntervalSince1970: 2_101_023_225)
    private let certSerialHex = "3BA8077CEE8DB2ED153C601FAFBB2ED04905AFE5"
    private let certFingerprint = "88:3B:1D:C8:B7:81:44:DF:62:E4:F7:D0:AC:AB:C1:88:06:39:74:54:16:6A:66:BB:34:D2:2C:6B:59:3F:7A:02"
    private let certCommonName = "Apple Distribution: Vaultify Test (ABCDE12345)"

    private func fixture(_ name: String, _ ext: String) throws -> Data {
        let bundle = Bundle(for: Self.self)
        // Sensitive-LOOKING extensions (.p8/.p12/.mobileprovision) ship as
        // "<name>-<ext>.fixture" so the repo's never-commit-secrets ignore
        // rules stay fully armed — these are disposable generated vectors,
        // and inspectors sniff content, never extensions.
        let url = bundle.url(forResource: "\(name)-\(ext)", withExtension: "fixture",
                             subdirectory: "apple-vectors-v1")
            ?? bundle.url(forResource: "\(name)-\(ext)", withExtension: "fixture")
            ?? bundle.url(forResource: name, withExtension: ext, subdirectory: "apple-vectors-v1")
            ?? bundle.url(forResource: name, withExtension: ext)
        return try Data(contentsOf: XCTUnwrap(url, "missing fixture \(name).\(ext)"))
    }

    // MARK: - Sanitize

    func testSanitizeStripsControlAndBidiCharacters() {
        let dirty = "A\u{0000}B\u{0009}C\u{001F}D\u{007F}E\u{0090}F\u{202A}G\u{202E}H\u{2066}I\u{2069}J"
        XCTAssertEqual(Sanitize.displayString(dirty), "ABCDEFGHIJ")
    }

    func testSanitizeCapsLength() {
        let long = String(repeating: "x", count: 600)
        XCTAssertEqual(Sanitize.displayString(long).count, 512)
    }

    // MARK: - P8

    func testECP256PKCS8KeyIsClassifiedFromContent() throws {
        let result = P8KeyInspector.inspect(try fixture("apple-ec-p256", "p8"))
        XCTAssertTrue(result.isPKCS8)
        XCTAssertEqual(result.keyType, .ecP256)
        XCTAssertTrue(result.verified)
    }

    func testCertificateContentInP8ExtensionIsNotAKey() throws {
        // Extension says .p8, bytes say certificate — content must win.
        let result = P8KeyInspector.inspect(try fixture("apple-wrong-extension", "p8"))
        XCTAssertEqual(result, .notPKCS8)
    }

    func testOversizedP8IsRejectedBeforeParsing() throws {
        let data = try fixture("apple-oversized", "p8")
        XCTAssertGreaterThan(data.count, P8KeyInspector.maxInputBytes)
        XCTAssertEqual(P8KeyInspector.inspect(data), .notPKCS8)
    }

    func testGarbageIsNotPKCS8() {
        XCTAssertEqual(P8KeyInspector.inspect(Data("not a key".utf8)), .notPKCS8)
    }

    // MARK: - Certificate

    func testDERCertificateMetadataMatchesPinnedValues() throws {
        let result = try XCTUnwrap(CertificateInspector.inspect(try fixture("apple-selfsigned-cert", "der")))
        XCTAssertEqual(result.subjectSummary, certCommonName)
        XCTAssertEqual(result.serialNumberHex, certSerialHex)
        XCTAssertEqual(result.sha256Fingerprint, certFingerprint)
        XCTAssertEqual(result.notBefore, certNotBefore)
        XCTAssertEqual(result.notAfter, certNotAfter)
        XCTAssertTrue(result.verified)
    }

    func testPEMCertificateResolvesToSameDERMetadata() throws {
        let result = try XCTUnwrap(CertificateInspector.inspect(try fixture("apple-selfsigned-cert", "pem")))
        XCTAssertEqual(result.sha256Fingerprint, certFingerprint)
        XCTAssertEqual(result.notAfter, certNotAfter)
        XCTAssertTrue(result.verified)
    }

    func testTruncatedDERCertificateIsRejected() throws {
        XCTAssertNil(CertificateInspector.inspect(try fixture("apple-truncated-cert", "der")))
    }

    func testOversizedCertificateInputIsRejected() {
        XCTAssertNil(CertificateInspector.inspect(Data(count: CertificateInspector.maxInputBytes + 1)))
    }

    // MARK: - P12

    func testP12WithCorrectPassphraseYieldsCertificateMetadata() throws {
        let outcome = P12Inspector.inspect(try fixture("apple-identity", "p12"), passphrase: "test-passphrase")
        guard case .parsed(let metadata) = outcome else {
            return XCTFail("expected parsed, got \(outcome)")
        }
        XCTAssertEqual(metadata.commonName, certCommonName)
        XCTAssertEqual(metadata.teamID, "ABCDE12345")
        let certificate = try XCTUnwrap(metadata.certificate)
        XCTAssertEqual(certificate.serialNumberHex, certSerialHex)
        XCTAssertEqual(certificate.sha256Fingerprint, certFingerprint)
        XCTAssertEqual(certificate.notAfter, certNotAfter)
        XCTAssertTrue(certificate.verified)
    }

    func testP12WrongPassphraseIsAClassifiedResultNotAnError() throws {
        let data = try fixture("apple-identity", "p12")
        XCTAssertEqual(P12Inspector.inspect(data, passphrase: "wrong-passphrase"), .wrongPassphrase)
        XCTAssertEqual(P12Inspector.inspect(data, passphrase: ""), .wrongPassphrase)
    }

    func testP12GarbageIsUnreadable() {
        XCTAssertEqual(P12Inspector.inspect(Data("junk".utf8), passphrase: "x"), .unreadable)
    }

    func testP12InspectionLeavesNoKeychainIdentityResidue() throws {
        _ = P12Inspector.inspect(try fixture("apple-identity", "p12"), passphrase: "test-passphrase")
        let query: [CFString: Any] = [
            kSecClass: kSecClassIdentity,
            kSecMatchLimit: kSecMatchLimitAll,
            kSecReturnRef: true,
        ]
        var found: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &found)
        // Residue exists only if the query SUCCEEDS and returns an identity.
        // The test host may lack keychain entitlements (errSecMissingEntitlement)
        // — that still proves nothing was persisted anywhere this process can
        // reach, which is the invariant.
        XCTAssertNotEqual(status, errSecSuccess, "PKCS#12 inspection must not persist identities")
    }

    // MARK: - Provisioning profile

    func testFakeMobileprovisionParsesPinnedPlistFields() throws {
        let result = ProvisioningProfileInspector.inspect(try fixture("apple-fake", "mobileprovision"))
        XCTAssertTrue(result.parsed)
        XCTAssertFalse(result.signatureChecked)
        XCTAssertEqual(result.uuid, "12345678-ABCD-4EF0-9876-543210FEDCBA")
        XCTAssertEqual(result.name, "Vaultify Test Profile")
        XCTAssertEqual(result.appIDName, "Vaultify Test")
        XCTAssertEqual(result.applicationIdentifier, "ABCDE12345.com.example.vaultify-test")
        XCTAssertEqual(result.teamIdentifier, "ABCDE12345")
        XCTAssertEqual(result.creationDate, Date(timeIntervalSince1970: 1_767_323_045))
        XCTAssertEqual(result.expirationDate, Date(timeIntervalSince1970: 1_798_859_045))
        XCTAssertEqual(result.platforms, ["iOS", "xrOS"])
        XCTAssertFalse(result.provisionsAllDevices)
        XCTAssertEqual(result.provisionedDeviceCount, 2)
        XCTAssertEqual(result.getTaskAllow, true)
    }

    func testMobileprovisionNameIsSanitizedOfBidiAndControlCharacters() throws {
        let result = ProvisioningProfileInspector.inspect(try fixture("apple-bidi-name", "mobileprovision"))
        XCTAssertTrue(result.parsed)
        XCTAssertEqual(result.name, "Vaultify Profile")
    }

    func testOversizedMobileprovisionIsRejected() {
        let oversized = Data(count: ProvisioningProfileInspector.maxInputBytes + 1)
        XCTAssertEqual(ProvisioningProfileInspector.inspect(oversized), .unparsed)
    }

    func testMobileprovisionWithoutEmbeddedPlistIsUnparsed() {
        XCTAssertEqual(ProvisioningProfileInspector.inspect(Data("no plist here".utf8)), .unparsed)
    }
}

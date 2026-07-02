import XCTest
@testable import Vaultify

@MainActor
final class PasskeyEnvelopeTests: XCTestCase {
    private let key = [UInt8](repeating: 0x2A, count: 32)
    private var originalBundle: Data?

    override func setUpWithError() throws {
        originalBundle = try? Data(contentsOf: SharedConfig.keyBundleURL)
        try? FileManager.default.removeItem(at: SharedConfig.keyBundleURL)
        try FileManager.default.createDirectory(at: SharedConfig.containerURL,
                                                withIntermediateDirectories: true)
        try installBundle()
    }

    override func tearDownWithError() throws {
        if let originalBundle {
            try originalBundle.write(to: SharedConfig.keyBundleURL, options: [.atomic])
        } else {
            try? FileManager.default.removeItem(at: SharedConfig.keyBundleURL)
        }
    }

    func testEnvelopeRoundtripAndWrongKeyFailure() throws {
        XCTAssertEqual(try PasskeyEnvelope.provisionOrVerify(vaultKey: key), .generated)
        let publicKey = try XCTUnwrap(PasskeyEnvelope.publicKey())
        let secret = makeSecret(relyingParty: "example.com", userName: "me")

        let envelope = try PasskeyEnvelope.seal(secret, to: publicKey)
        let opened = try PasskeyEnvelope.open(envelope, vaultKey: key)

        XCTAssertEqual(opened.credentialID, secret.credentialID)
        XCTAssertEqual(opened.privateKeyRaw, secret.privateKeyRaw)
        XCTAssertThrowsError(try PasskeyEnvelope.open(envelope, vaultKey: [UInt8](repeating: 1, count: 32)))
    }

    func testUnknownVersionAndOversizedPayloadsAreRejected() throws {
        _ = try PasskeyEnvelope.provisionOrVerify(vaultKey: key)
        let publicKey = try XCTUnwrap(PasskeyEnvelope.publicKey())
        var envelope = try PasskeyEnvelope.seal(makeSecret(), to: publicKey)

        envelope[envelope.startIndex] = 0xFF
        XCTAssertThrowsError(try PasskeyEnvelope.open(envelope, vaultKey: key))
        XCTAssertThrowsError(try PasskeyEnvelope.open(Data(repeating: 0, count: 17_000), vaultKey: key))
    }

    func testProvisioningValidatesAndRegeneratesMismatchedPublicKey() throws {
        XCTAssertEqual(try PasskeyEnvelope.provisionOrVerify(vaultKey: key), .generated)
        let originalPublic = try XCTUnwrap(PasskeyEnvelope.publicKey())
        XCTAssertEqual(try PasskeyEnvelope.provisionOrVerify(vaultKey: key), .valid)

        var bundle = try XCTUnwrap(VaultKeyBundle.load())
        bundle.envelopePublicKey = Data([UInt8(1)] + [UInt8](repeating: 0, count: 32))
        try bundle.save()

        XCTAssertEqual(try PasskeyEnvelope.provisionOrVerify(vaultKey: key), .mismatch)
        XCTAssertNotEqual(PasskeyEnvelope.publicKey(), originalPublic)
    }

    func testUnlockMigrationResealsEnvelopeRecordsAndDedupesNewestAccount() throws {
        _ = try PasskeyEnvelope.provisionOrVerify(vaultKey: key)
        let publicKey = try XCTUnwrap(PasskeyEnvelope.publicKey())
        let store = VaultStore(inMemory: true)
        TestLifetimeRetainer.retain(store)
        let vault = PasskeyVault(store: store)
        let old = makeSecret(relyingParty: "example.com", userName: "old",
                             userHandle: Data([7]), createdAt: Date(timeIntervalSince1970: 1))
        let newer = makeSecret(relyingParty: "example.com", userName: "new",
                               userHandle: Data([7]), createdAt: Date(timeIntervalSince1970: 2))

        _ = try vault.save(old, key: key)
        try vault.saveEnvelope(newer, envelopeSealed: PasskeyEnvelope.seal(newer, to: publicKey))
        let result = vault.prepareEnvelopeOnUnlock(key: key)

        XCTAssertEqual(result.migrated, 1)
        XCTAssertEqual(result.replaced.map(\.credentialID), [old.credentialID])
        XCTAssertEqual(vault.all(key: key).map(\.credentialID), [newer.credentialID])
        XCTAssertNil(vault.record(id: newer.credentialID.base64URLEncodedString())?.envelopeSealed)
    }

    func testCorruptEnvelopeRecordIsQuarantinedWithSiteNotice() throws {
        _ = try PasskeyEnvelope.provisionOrVerify(vaultKey: key)
        let store = VaultStore(inMemory: true)
        TestLifetimeRetainer.retain(store)
        let vault = PasskeyVault(store: store)
        let secret = makeSecret(relyingParty: "bad.example", userName: "me")

        try vault.saveEnvelope(secret, envelopeSealed: Data([1, 2, 3]))
        let result = vault.prepareEnvelopeOnUnlock(key: key)

        XCTAssertEqual(result.quarantinedSites, ["bad.example"])
        XCTAssertEqual(result.quarantinedIdentities.map(\.credentialID), [secret.credentialID])
        XCTAssertTrue(vault.all(key: key).isEmpty)
    }

    func testEnvelopeRecordIDMismatchIsQuarantined() throws {
        _ = try PasskeyEnvelope.provisionOrVerify(vaultKey: key)
        let publicKey = try XCTUnwrap(PasskeyEnvelope.publicKey())
        let store = VaultStore(inMemory: true)
        TestLifetimeRetainer.retain(store)
        let vault = PasskeyVault(store: store)
        let secret = makeSecret(relyingParty: "mismatch.example", userName: "me")
        let wrongCredentialID = Data([0x09])

        store.context.insert(PasskeyRecord(
            id: wrongCredentialID.base64URLEncodedString(),
            sealed: Data(),
            envelopeSealed: try PasskeyEnvelope.seal(secret, to: publicKey),
            relyingPartyHint: secret.relyingParty,
            userNameHint: secret.userName,
            userHandleHint: secret.userHandle,
            createdAt: secret.createdAt))
        try store.context.save()

        let result = vault.prepareEnvelopeOnUnlock(key: key)

        XCTAssertEqual(result.quarantinedSites, ["mismatch.example"])
        XCTAssertEqual(result.quarantinedIdentities.map(\.credentialID), [secret.credentialID])
        XCTAssertTrue(vault.all(key: key).isEmpty)
        XCTAssertNil(vault.record(id: wrongCredentialID.base64URLEncodedString()))
    }

    private func installBundle() throws {
        let bundle = VaultKeyBundle(version: VaultKeyBundle.currentVersion,
                                    createdAt: .now,
                                    kdfSalt: Data(repeating: 1, count: 16),
                                    kdf: .standard,
                                    wrappedByPassword: Data(repeating: 2, count: 48),
                                    recoverySalt: nil,
                                    wrappedByRecovery: nil)
        try bundle.save()
    }

    private func makeSecret(relyingParty: String = "example.com",
                            userName: String = "me",
                            userHandle: Data = Data([1]),
                            createdAt: Date = Date(timeIntervalSince1970: 1)) -> PasskeySecret {
        let registration = WebAuthn.register(relyingParty: relyingParty)
        return PasskeySecret(relyingParty: relyingParty,
                             userName: userName,
                             userHandle: userHandle,
                             credentialID: registration.credentialID,
                             privateKeyRaw: registration.privateKeyRaw,
                             counter: 0,
                             createdAt: createdAt,
                             flags: registration.flags)
    }
}

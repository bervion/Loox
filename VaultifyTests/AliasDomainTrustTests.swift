import CryptoKit
import XCTest
@testable import Vaultify

@MainActor
final class AliasDomainTrustTests: XCTestCase {
    private func signed(_ key: P256.Signing.PrivateKey, env: String = "production",
                        host: String = "loox.pw", expiresAt: Int64 = 100,
                        lifecycle: String = "retired") throws -> Data {
        var json: [String: Any] = [
            "schema_version": 1, "registry_version": 1, "key_id": "test",
            "env": env, "issued_at": 0, "expires_at": expiresAt,
            "domains": [["id": "email-pw", "display_name": "Loox",
                         "email_address_domain": host, "capabilities": ["email"],
                         "lifecycle": lifecycle, "is_primary_email_choice": true,
                         "is_primary_short_link_choice": false]],
        ]
        let document = try JSONDecoder().decode(DomainRegistryDocument.self,
                                                from: JSONSerialization.data(withJSONObject: json))
        json["signature"] = try key.signature(for: document.transcript).rawRepresentation.base64EncodedString()
        return try JSONSerialization.data(withJSONObject: json)
    }

    func testDebugAndReleaseUseProductionRegistryMatchingRelay() {
        XCTAssertEqual(DomainRegistryClient.expectedEnv, RelayConfig.environment)
        XCTAssertEqual(DomainRegistryClient.primaryURL.host, "config.looxpassword.com")
    }

    func testHistoricalProofIsAddressOnlyAndDoesNotAcceptExpiredConfig() throws {
        let key = P256.Signing.PrivateKey()
        let data = try signed(key)
        let trusted = ["test": key.publicKey.x963Representation]
        XCTAssertEqual(try DomainRegistryVerifier.historicalMappings(
            documentData: data, trustedKeys: trusted, expectedEnv: "production")["email-pw"], "loox.pw")
        XCTAssertThrowsError(try DomainRegistryVerifier.verify(
            documentData: data, trustedKeys: trusted, expectedEnv: "production",
            now: .now, highestAcceptedVersion: 0)) {
            XCTAssertEqual($0 as? DomainRegistryVerifier.VerifyError, .expired)
        }
    }

    func testHistoricalProofRejectsWrongEnvironmentAndTampering() throws {
        let key = P256.Signing.PrivateKey()
        let trusted = ["test": key.publicKey.x963Representation]
        let staging = try signed(key, env: "staging")
        XCTAssertThrowsError(try DomainRegistryVerifier.historicalMappings(
            documentData: staging, trustedKeys: trusted, expectedEnv: "production"))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: signed(key)) as? [String: Any])
        var domains = try XCTUnwrap(json["domains"] as? [[String: Any]])
        domains[0]["email_address_domain"] = "other.example"
        json["domains"] = domains
        XCTAssertThrowsError(try DomainRegistryVerifier.historicalMappings(
            documentData: JSONSerialization.data(withJSONObject: json), trustedKeys: trusted,
            expectedEnv: "production"))
    }

    func testSyncedUnprovenSnapshotCannotCreateReachableAddress() {
        let alias = EmailAlias(personaId: "p", tier: .perSite, localPart: "abc",
                               relayDomainID: "unknown", relayHostnameSnapshot: "loox.pw")
        XCTAssertNil(alias.emailDomain)
        XCTAssertNil(alias.resolvedAddress)
    }

    func testForgedSnapshotDoesNotOverrideLegacyMapping() {
        let alias = EmailAlias(personaId: "p", tier: .perSite, localPart: "abc",
                               relayHostnameSnapshot: "other.example")
        XCTAssertEqual(alias.resolvedAddress, "abc@relay.looxpassword.com")
    }

    func testSealedNewFieldsRoundTripAndLegacyDefaults() throws {
        let alias = EmailAlias(personaId: "p", tier: .perSite, localPart: "abc",
                               relayHostnameSnapshot: RelayConfig.emailDomain,
                               relayDomainMappingProof: Data([1, 2]), relationRevision: 9)
        let secret = try JSONDecoder().decode(EmailAliasSecret.self, from: JSONEncoder().encode(alias.secret))
        XCTAssertEqual(secret.relayHostnameSnapshot, RelayConfig.emailDomain)
        XCTAssertEqual(secret.relayDomainMappingProof, Data([1, 2]))
        XCTAssertEqual(secret.relationRevision, 9)
        let old = try JSONDecoder().decode(EmailAliasSecret.self,
            from: Data(#"{"personaId":"p","localPart":"abc"}"#.utf8))
        XCTAssertNil(old.relayHostnameSnapshot)
        XCTAssertNil(old.relayDomainMappingProof)
        XCTAssertEqual(old.relationRevision, 0)
    }

    private func repo() -> VaultRepository {
        let session = VaultSession(settings: SettingsStore())
        session.adoptUnlocked(key: [UInt8](repeating: 0x2a, count: 32))
        let repo = VaultRepository(store: VaultStore(inMemory: true), session: session)
        repo.reload()
        TestLifetimeRetainer.retain(repo)
        return repo
    }

    func testMintCheckpointFreezesNamespaceBeforeActivation() throws {
        let repo = repo()
        let persona = try XCTUnwrap(repo.activePersona)
        let id = try XCTUnwrap(repo.createPersonaAlias(for: persona))
        try repo.markMinted(try XCTUnwrap(repo.aliases.first(where: { $0.id == id })))
        var minted = try XCTUnwrap(repo.aliases.first(where: { $0.id == id }))
        XCTAssertEqual(minted.status, .reserved)
        minted.localPart = "changed"
        XCTAssertThrowsError(try repo.updateAlias(minted))
        minted = try XCTUnwrap(repo.aliases.first(where: { $0.id == id }))
        minted.relayDomainID = "email-pw"
        XCTAssertThrowsError(try repo.updateAlias(minted))
    }

    func testInactiveDomainCannotReserveNewAlias() throws {
        defer { AuxiliaryDomainRegistry.applyRemote([]) }
        let domain = AuxiliaryDomainDescriptor(
            id: "email-pw", displayName: "Loox", emailAddressDomain: "loox.pw", shortLinkHost: nil,
            capabilities: [.privateEmail], lifecycle: .createDisabled,
            isPrimaryEmailChoice: false, isPrimaryShortLinkChoice: false)
        AuxiliaryDomainRegistry.applyRemote([domain])
        let repo = repo()
        XCTAssertThrowsError(try repo.createPersonaAlias(for: XCTUnwrap(repo.activePersona), domainID: "email-pw"))
        XCTAssertTrue(repo.aliases.isEmpty)
    }
}

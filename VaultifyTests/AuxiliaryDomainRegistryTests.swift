import XCTest
@testable import Vaultify

/// The trusted auxiliary-domain set: bundled registry invariants, lifecycle
/// filtering, unknown-ID rejection, and the sealed alias blob's domain field
/// (a pre-domain blob must decode as the legacy namespace, never fail).
final class AuxiliaryDomainRegistryTests: XCTestCase {

    // MARK: Registry

    func testBundledRegistryHasExactlyOnePrimaryEmailChoice() {
        let primaries = AuxiliaryDomainRegistry.current.filter {
            $0.lifecycle == .active && $0.isPrimaryEmailChoice
        }
        XCTAssertEqual(primaries.count, 1)
        XCTAssertEqual(AuxiliaryDomainRegistry.defaultEmailDomainID, primaries[0].id)
    }

    func testLegacyDomainResolvesToRelayHost() {
        XCTAssertEqual(
            AuxiliaryDomainRegistry.emailDomain(forDomainID: AuxiliaryDomainRegistry.legacyEmailDomainID),
            RelayConfig.emailDomain)
    }

    func testUnknownDomainIDDoesNotBecomeLegacyAddress() {
        let host = AuxiliaryDomainRegistry.emailDomain(forDomainID: "no-such-domain")
        XCTAssertNil(host)
    }

    func testOnlyActivePrivateEmailDomainsAreCreatable() {
        for domain in AuxiliaryDomainRegistry.creatableEmailDomains {
            XCTAssertTrue(domain.offersPrivateEmail)
            XCTAssertTrue(domain.lifecycle.allowsCreation)
        }
    }

    func testLifecycleCreationGate() {
        XCTAssertTrue(AuxiliaryDomainLifecycle.active.allowsCreation)
        XCTAssertFalse(AuxiliaryDomainLifecycle.createDisabled.allowsCreation)
        XCTAssertFalse(AuxiliaryDomainLifecycle.retiring.allowsCreation)
        XCTAssertFalse(AuxiliaryDomainLifecycle.retired.allowsCreation)
    }

    // MARK: Sealed alias blob compatibility

    func testPreDomainSealedBlobDecodesAsLegacyDomain() throws {
        // Exactly what an old client sealed: no relayDomainID key at all.
        let legacy = Data("""
        {"personaId":"p1","localPart":"abc123","tier":"perSite","status":"active",
         "backendMinted":true}
        """.utf8)
        let secret = try JSONDecoder().decode(EmailAliasSecret.self, from: legacy)
        XCTAssertEqual(secret.relayDomainID, AuxiliaryDomainRegistry.legacyEmailDomainID)
    }

    func testAliasDomainRoundTripsThroughSecret() throws {
        let alias = EmailAlias(personaId: "p1", tier: .perSite, localPart: "xyz",
                               relayDomainID: "some-future-domain")
        let data = try JSONEncoder().encode(alias.secret)
        let decoded = try JSONDecoder().decode(EmailAliasSecret.self, from: data)
        XCTAssertEqual(decoded.relayDomainID, "some-future-domain")
    }

    func testAliasEmailDomainUsesTrustedMappingOnly() {
        let known = EmailAlias(personaId: "p1", tier: .perSite, localPart: "a",
                               relayDomainID: AuxiliaryDomainRegistry.legacyEmailDomainID)
        XCTAssertEqual(known.emailDomain, RelayConfig.emailDomain)
        let future = EmailAlias(personaId: "p1", tier: .perSite, localPart: "a",
                                relayDomainID: "from-a-newer-build")
        XCTAssertNil(future.emailDomain)
        XCTAssertNil(future.resolvedAddress)
    }
}

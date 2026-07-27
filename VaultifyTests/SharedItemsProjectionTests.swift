import XCTest
@testable import Vaultify

/// V1.2 phase-1 invariants: grant → projected VaultItem mapping, the
/// `shared::` id scheme, and owned-item purity (`sharedOrigin` must be
/// invisible to persistence of owned items).
final class SharedItemsProjectionTests: XCTestCase {

    private let nowMs: Int64 = 1_783_256_400_000

    private func makeGrant(capabilities: [String: FieldCapability]) throws -> AccessGrant {
        let owner = DeviceSigningIdentity.ephemeral()
        var grant = AccessGrant(
            id: "grant-1", itemId: "item-1", recipientId: "rcpt-1",
            participantPubKey: Data(repeating: 1, count: 32),
            pinnedDeviceSigningKeys: [Data(repeating: 2, count: 64)],
            capabilities: capabilities, epoch: 1,
            createdAtUnixMs: nowMs, expiresAtUnixMs: nil,
            ownerSigningPubKey: owner.publicKeyRaw, ownerSignature: Data())
        grant.ownerSignature = try owner.signature(for: grant.signingBody())
        return grant
    }

    private let origin = SharedOrigin(zoneName: "apz-abc", ownerName: "_owner1",
                                      grantId: "grant-1")

    func testBuildItemMapsValuesAndEnvelope() throws {
        let grant = try makeGrant(capabilities: [
            "f-pass": .value(.shared),
            "f-totp": .totp(.askEachTime),
        ])
        let display = SharedDisplayEnvelope(title: "GitHub", websiteHost: "github.com",
                                            updatedAtUnixMs: nowMs, revision: 3)
        let item = SharedItemsProjection.buildItem(
            origin: origin, grant: grant, display: display,
            values: ["f-pass": Data("hunter2".utf8)])

        XCTAssertEqual(item.id, "shared::_owner1::apz-abc::grant-1")
        XCTAssertEqual(item.sharedOrigin, origin)
        XCTAssertEqual(item.title, "GitHub")
        // Shared value → protected password-kind field, same field id.
        let shared = item.fields.first { $0.id == "f-pass" }
        XCTAssertEqual(shared?.value, "hunter2")
        XCTAssertEqual(shared?.kind, .password)
        XCTAssertEqual(shared?.protected, true)
        // NO placeholder for askEachTime capabilities — the detail screen
        // derives Request rows from the grant, not from empty fields.
        XCTAssertNil(item.fields.first { $0.kind == .totp })
        // Envelope host lands as a url field with a STABLE id.
        let url = item.fields.first { $0.kind == .url }
        XCTAssertEqual(url?.value, "github.com")
        XCTAssertEqual(url?.id, "shared-website")
    }

    func testBuildItemFallbackTitleWithoutEnvelope() throws {
        let grant = try makeGrant(capabilities: ["f": .value(.shared)])
        let item = SharedItemsProjection.buildItem(origin: origin, grant: grant,
                                                   display: nil, values: [:])
        XCTAssertFalse(item.title.isEmpty) // localized "Shared item" fallback
        XCTAssertNil(item.fields.first { $0.kind == .url })
    }

    func testBuildItemCarriesTheSendersCategory() throws {
        // A shared Secure Note must not arrive as a login: the category drives
        // the avatar glyph and the type line on the recipient's screen.
        let grant = try makeGrant(capabilities: ["f": .value(.shared)])
        var display = SharedDisplayEnvelope(title: "Recovery notes",
                                            updatedAtUnixMs: nowMs, revision: 1)
        display.category = ItemCategory.note.rawValue
        let item = SharedItemsProjection.buildItem(origin: origin, grant: grant,
                                                   display: display,
                                                   values: ["f": Data("body".utf8)])
        XCTAssertEqual(item.category, .note)
    }

    func testBuildItemFallsBackToLoginForMissingOrUnknownCategory() throws {
        // Senders that predate the field, and a category only a newer build
        // knows, both degrade to the historical rendering rather than losing
        // the item.
        let grant = try makeGrant(capabilities: ["f": .value(.shared)])
        var display = SharedDisplayEnvelope(title: "X", updatedAtUnixMs: nowMs, revision: 1)
        XCTAssertEqual(SharedItemsProjection.buildItem(origin: origin, grant: grant,
                                                       display: display, values: [:]).category,
                       .login)
        display.category = "hologram"
        XCTAssertEqual(SharedItemsProjection.buildItem(origin: origin, grant: grant,
                                                       display: display, values: [:]).category,
                       .login)
    }

    func testDisplayEnvelopeWithoutCategoryStillDecodes() throws {
        // Wire compatibility: an envelope encoded before the field existed
        // must decode unchanged, with no category.
        let legacy = Data("""
        {"title":"GitHub","websiteHost":"github.com","updatedAtUnixMs":1,"revision":2}
        """.utf8)
        let decoded = try JSONDecoder().decode(SharedDisplayEnvelope.self, from: legacy)
        XCTAssertNil(decoded.category)
        XCTAssertEqual(decoded.title, "GitHub")
    }

    func testOwnedItemEncodingUnchangedBySharedOriginAddition() throws {
        // Owned items never carry an origin — the synthesized Codable must
        // omit the key entirely so sync/backup blobs stay byte-compatible.
        let owned = VaultItem(id: "A", category: .login, title: "T")
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(owned), encoding: .utf8))
        XCTAssertFalse(json.contains("sharedOrigin"))
        // And a legacy blob (no key) decodes with nil origin.
        let decoded = try JSONDecoder().decode(VaultItem.self,
                                               from: JSONEncoder().encode(owned))
        XCTAssertNil(decoded.sharedOrigin)
    }

    func testSecretPayloadNeverContainsOrigin() throws {
        var item = VaultItem(id: "B", category: .login, title: "T")
        item.sharedOrigin = origin
        // The sealed-at-rest payload is built from `secret` — origin excluded
        // by construction (projection items are never persisted anyway).
        let sealed = try XCTUnwrap(String(data: JSONEncoder().encode(item.secret),
                                          encoding: .utf8))
        XCTAssertFalse(sealed.contains("sharedOrigin"))
        XCTAssertFalse(sealed.contains("apz-abc"))
    }
}

import XCTest
@testable import Vaultify

/// Contextual upsell gates (proposal §5.3): table-driven over every gate, tier
/// and boundary count. The gates are pure functions of (tier, current count)
/// against the frozen §3.1 quota table.
final class LooxGateTests: XCTestCase {

    // MARK: Personas (free 1, plus 3, max uncapped)

    func testPersonaGateBoundaries() {
        XCTAssertEqual(LooxGate.canCreatePersona(tier: .free, current: 0), .allowed)
        XCTAssertEqual(LooxGate.canCreatePersona(tier: .free, current: 1), .needsUpgrade(to: .plus))
        XCTAssertEqual(LooxGate.canCreatePersona(tier: .plus, current: 2), .allowed)
        XCTAssertEqual(LooxGate.canCreatePersona(tier: .plus, current: 3), .needsUpgrade(to: .max))
        // Max has no product cap — any count stays allowed.
        XCTAssertEqual(LooxGate.canCreatePersona(tier: .max, current: 250), .allowed)
    }

    // MARK: Aliases (free 1, plus 10, max 200)

    func testAliasGateBoundaries() {
        XCTAssertEqual(LooxGate.canCreateAlias(tier: .free, retained: 0), .allowed)
        XCTAssertEqual(LooxGate.canCreateAlias(tier: .free, retained: 1), .needsUpgrade(to: .plus))
        XCTAssertEqual(LooxGate.canCreateAlias(tier: .plus, retained: 9), .allowed)
        XCTAssertEqual(LooxGate.canCreateAlias(tier: .plus, retained: 10), .needsUpgrade(to: .max))
        XCTAssertEqual(LooxGate.canCreateAlias(tier: .max, retained: 199), .allowed)
        // Beyond even Max the client defers to the backend counter — never a
        // dead-end offer that wouldn't help.
        XCTAssertEqual(LooxGate.canCreateAlias(tier: .max, retained: 200), .allowed)
    }

    // MARK: Links / Quick View (free 3, plus 30, max 300 per rolling 30 days)

    func testLinkGateBoundaries() {
        XCTAssertEqual(LooxGate.canCreateLink(tier: .free, createdIn30d: 2), .allowed)
        XCTAssertEqual(LooxGate.canCreateLink(tier: .free, createdIn30d: 3), .needsUpgrade(to: .plus))
        // A Free user far over the window (e.g. counts accrued while paid)
        // still gets the cheapest tier that covers one more.
        XCTAssertEqual(LooxGate.canCreateLink(tier: .free, createdIn30d: 31), .needsUpgrade(to: .max))
        XCTAssertEqual(LooxGate.canCreateLink(tier: .max, createdIn30d: 300), .allowed)
    }

    func testQuickViewGateBoundaries() {
        XCTAssertEqual(LooxGate.canApproveQuickView(tier: .free, approvedIn30d: 3), .needsUpgrade(to: .plus))
        XCTAssertEqual(LooxGate.canApproveQuickView(tier: .plus, approvedIn30d: 30), .needsUpgrade(to: .max))
        XCTAssertEqual(LooxGate.canApproveQuickView(tier: .plus, approvedIn30d: 29), .allowed)
    }

    // MARK: Outgoing recipients (free 0, plus 1, max 10)

    func testRecipientGateBoundaries() {
        // Free has zero seats: the very first NEW recipient needs Plus.
        XCTAssertEqual(LooxGate.canAddOutgoingRecipient(tier: .free, activeRecipients: 0), .needsUpgrade(to: .plus))
        XCTAssertEqual(LooxGate.canAddOutgoingRecipient(tier: .plus, activeRecipients: 0), .allowed)
        XCTAssertEqual(LooxGate.canAddOutgoingRecipient(tier: .plus, activeRecipients: 1), .needsUpgrade(to: .max))
        XCTAssertEqual(LooxGate.canAddOutgoingRecipient(tier: .max, activeRecipients: 9), .allowed)
        XCTAssertEqual(LooxGate.canAddOutgoingRecipient(tier: .max, activeRecipients: 10), .allowed)
    }

    // MARK: Boolean surfaces

    func testWatchtowerAndThemesFollowTheQuotaTable() {
        XCTAssertFalse(LooxGate.fullWatchtower(.free))
        XCTAssertTrue(LooxGate.fullWatchtower(.plus))
        XCTAssertTrue(LooxGate.fullWatchtower(.max))
        XCTAssertFalse(LooxGate.fullThemes(.free))
        XCTAssertTrue(LooxGate.fullThemes(.plus))
        XCTAssertTrue(LooxGate.fullThemes(.max))
    }
}

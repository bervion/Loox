import XCTest
@testable import Vaultify

/// The owner's capability editor (share-details sheet and create sheet).
///
/// Regression for the reported bug: hand over a TOTP seed, move it to "Ask
/// each time" and apply, then pick hand over again. The second hand-over did
/// nothing, because the details sheet built its TOTP rows without the
/// confirmation hook and the rows defaulted it to a no-op. Hand-over now goes
/// through the draft, and the grant it produces ships the seed again.
final class ShareCapabilityDraftTests: XCTestCase {

    private let totpID = "totp-field"
    private let passwordID = "password-field"
    private let seed = "JBSWY3DPEHPK3PXP"

    private var item: VaultItem {
        VaultItem(id: "item", category: .login, title: "Acme", folderId: nil, fields: [
            DynamicField(id: passwordID, label: "Password", kind: .password, value: "pw"),
            DynamicField(id: totpID, label: "One-time Code", kind: .totp, value: seed),
        ])
    }

    /// What the grant would seal for `capabilities` (the transport side).
    private func sealedFieldIDs(_ capabilities: [String: FieldCapability]) -> Set<String> {
        Set(SharedGrantComposer.sharedFieldValues(item: item, capabilities: capabilities).keys)
    }

    func testHandOverThenAskEachTimeThenHandOverAgain() {
        // 1. Shared with the seed handed over.
        var draft = ShareCapabilityDraft(published: [
            passwordID: .value(.shared), totpID: .totp(.shared),
        ])
        XCTAssertTrue(sealedFieldIDs(draft.selection).contains(totpID))

        // 2. Ask each time, applied: the seed no longer ships.
        draft.select(.totp(.askEachTime), for: totpID)
        XCTAssertNil(draft.pendingHandOver, "moving away from hand-over needs no confirmation")
        XCTAssertTrue(draft.hasChanges)
        draft.didPublish(draft.selection)
        XCTAssertEqual(draft.capability(for: totpID), .totp(.askEachTime))
        XCTAssertFalse(sealedFieldIDs(draft.selection).contains(totpID))

        // 3. Hand over again: it must reach the confirmation, not vanish.
        draft.select(.totp(.shared), for: totpID)
        XCTAssertEqual(draft.pendingHandOver,
                       ShareCapabilityDraft.HandOver(slot: totpID, capability: .totp(.shared)))
        XCTAssertEqual(draft.capability(for: totpID), .totp(.askEachTime),
                       "a hand-over never applies before it is confirmed")

        // Confirmed: the republished grant carries the seed again.
        let confirmed = draft.publishedConfirmingHandOver
        XCTAssertEqual(confirmed[totpID], .totp(.shared))
        let values = SharedGrantComposer.sharedFieldValues(item: item, capabilities: confirmed)
        XCTAssertEqual(values[totpID], Data(seed.utf8))
        draft.didPublish(confirmed)
        XCTAssertNil(draft.pendingHandOver)
        XCTAssertEqual(draft.capability(for: totpID), .totp(.shared))
        XCTAssertFalse(draft.hasChanges)
    }

    func testPasskeyHandOverRoundTrip() {
        let slot = PasskeySlot.slotId(credentialID: Data([9]))
        var draft = ShareCapabilityDraft(published: [slot: .passkey(.shared)])
        draft.select(.passkey(.askEachTime), for: slot)
        draft.didPublish(draft.selection)

        draft.select(.passkey(.shared), for: slot)
        XCTAssertEqual(draft.pendingHandOver?.slot, slot)
        draft.confirmHandOver()

        let secret = PasskeySecret(relyingParty: "acme.example", userName: "u", userHandle: Data([1]),
                                   credentialID: Data([9]), privateKeyRaw: Data([7]), counter: 0,
                                   createdAt: Date(timeIntervalSince1970: 0), flags: 0x1D)
        let artifacts = SharedGrantComposer.passkeyArtifacts(secretsBySlot: [(slot, secret)],
                                                              capabilities: draft.selection)
        XCTAssertEqual(Set(artifacts.shared.keys), [slot], "the key ships again after the second hand-over")
    }

    func testCancelledHandOverKeepsTheCurrentMode() {
        var draft = ShareCapabilityDraft(published: [totpID: .totp(.askEachTime)])
        draft.select(.totp(.shared), for: totpID)
        draft.cancelHandOver()
        XCTAssertNil(draft.pendingHandOver)
        XCTAssertEqual(draft.capability(for: totpID), .totp(.askEachTime))
        XCTAssertFalse(draft.hasChanges)
    }

    func testPickingTheLiveHandOverAgainDoesNotAskTwice() {
        var draft = ShareCapabilityDraft(published: [totpID: .totp(.shared)])
        draft.select(.totp(.shared), for: totpID)
        XCTAssertNil(draft.pendingHandOver)
        XCTAssertFalse(draft.hasChanges)
    }

    /// Moved off a live hand-over, then picked it again before Apply: the
    /// grant still carries it, so there is nothing new to confirm.
    func testRestoringThePublishedHandOverDoesNotAskAgain() {
        var draft = ShareCapabilityDraft(published: [totpID: .totp(.shared)])
        draft.select(.totp(.askEachTime), for: totpID)
        draft.select(.totp(.shared), for: totpID)
        XCTAssertNil(draft.pendingHandOver)
        XCTAssertFalse(draft.hasChanges)
    }

    /// On a live share a confirmed hand-over publishes at once, and only
    /// itself: an unapplied pick elsewhere is neither sent nor lost.
    func testConfirmedHandOverPublishesOnlyItselfAndKeepsOtherEdits() {
        var draft = ShareCapabilityDraft(published: [
            passwordID: .value(.none), totpID: .totp(.askEachTime),
        ])
        draft.select(.value(.shared), for: passwordID)
        draft.select(.totp(.shared), for: totpID)
        let confirmed = draft.publishedConfirmingHandOver
        XCTAssertEqual(confirmed, [passwordID: .value(.none), totpID: .totp(.shared)])

        draft.didPublish(confirmed)
        XCTAssertEqual(draft.capability(for: totpID), .totp(.shared))
        XCTAssertEqual(draft.capability(for: passwordID), .value(.shared), "the unapplied pick survives")
        XCTAssertTrue(draft.hasChanges, "and still waits for Apply")
    }

    /// The create flow sends nothing until the share exists: confirming only
    /// takes the hand-over into the selection.
    func testCreateFlowConfirmationOnlyRecordsTheChoice() {
        var draft = ShareCapabilityDraft(published: [totpID: .totp(.none)])
        draft.select(.totp(.shared), for: totpID)
        draft.confirmHandOver()
        XCTAssertEqual(draft.selection, [totpID: .totp(.shared)])
        XCTAssertEqual(draft.published, [totpID: .totp(.none)])
    }

    /// An edit after the last delivery is unsent whatever the update mode:
    /// manual shares wait for Apply, and an automatic push that failed is
    /// never retried by itself.
    func testItemEditsAfterTheLastDeliveryAreUnsent() {
        let lastSent: Int64 = 1_000_000
        XCTAssertTrue(ShareCapabilityDraft.hasUnsentItemEdits(
            itemUpdatedAt: Date(timeIntervalSince1970: 2_000), lastSentAtUnixMs: lastSent))
        XCTAssertFalse(ShareCapabilityDraft.hasUnsentItemEdits(
            itemUpdatedAt: Date(timeIntervalSince1970: 1_000), lastSentAtUnixMs: lastSent))
        XCTAssertFalse(ShareCapabilityDraft.hasUnsentItemEdits(
            itemUpdatedAt: Date(timeIntervalSince1970: 500), lastSentAtUnixMs: lastSent))
    }
}

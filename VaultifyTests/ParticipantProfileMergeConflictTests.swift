import XCTest
@testable import Vaultify

/// Convergence of the participant-profile merge under the two-device
/// conflict: whichever device loses the change-tag race re-merges its own
/// entry onto the winner's server record and re-saves — after both passes
/// BOTH devices' signing keys and directory entries must be present, in the
/// same deterministic order regardless of who won. Pure merge layer — the
/// CloudKit retry loop feeds it, but the guarantee lives here.
@MainActor
final class ParticipantProfileMergeConflictTests: XCTestCase {

    private func entry(_ byte: UInt8, label: String,
                       addedAt: Int64) -> DeviceHPKEDirectoryEntry {
        DeviceHPKEDirectoryEntry(deviceKeyID: Data(repeating: byte, count: 32),
                                 hpkePublicKey: Data([byte]), label: label,
                                 addedAtUnixMs: addedAt)
    }

    func testConflictSequenceConvergesOrderIndependently() {
        let deviceA = entry(0xA, label: "A", addedAt: 100)
        let deviceB = entry(0xB, label: "B", addedAt: 200)

        // Device A won the race: server holds [A]; B re-merges onto it.
        let bOntoA = ParticipantProfileMerge.directory(existing: [deviceA],
                                                       upserting: deviceB)
        // Device B won the race: server holds [B]; A re-merges onto it.
        let aOntoB = ParticipantProfileMerge.directory(existing: [deviceB],
                                                       upserting: deviceA)

        XCTAssertEqual(bOntoA.count, 2)
        XCTAssertEqual(aOntoB.count, 2)
        // Deterministic order (enrollment time, then key id) makes the two
        // outcomes literally equal, not merely set-equal.
        XCTAssertEqual(bOntoA, aOntoB)
        XCTAssertEqual(bOntoA.map(\.label), ["A", "B"])
    }

    func testRepeatedMergeIsIdempotent() {
        let deviceA = entry(0xA, label: "A", addedAt: 100)
        let deviceB = entry(0xB, label: "B", addedAt: 200)
        let once = ParticipantProfileMerge.directory(existing: [deviceA],
                                                     upserting: deviceB)
        // A retried save (outer resume backoff) re-runs the same merge.
        let twice = ParticipantProfileMerge.directory(existing: once,
                                                      upserting: deviceB)
        XCTAssertEqual(once, twice)
    }

    func testSigningKeyUnionConvergesOrderIndependently() {
        let keyA = Data([1]), keyB = Data([2])
        let bOntoA = ParticipantProfileMerge.signingKeys(existing: [keyA], adding: keyB)
        let aOntoB = ParticipantProfileMerge.signingKeys(existing: [keyB], adding: keyA)
        XCTAssertEqual(Set(bOntoA), Set(aOntoB))
        XCTAssertEqual(bOntoA.count, 2)
        // Idempotent on a retried save.
        XCTAssertEqual(ParticipantProfileMerge.signingKeys(existing: bOntoA, adding: keyB),
                       bOntoA)
    }

    func testMergeOntoEmptyServerRecordKeepsOwnEntryOnly() {
        // Concurrent CREATE resolved by the retry: the winner's record may
        // still be empty of directory data (legacy shape) — the loser's
        // re-merge must simply install itself.
        let deviceB = entry(0xB, label: "B", addedAt: 200)
        XCTAssertEqual(ParticipantProfileMerge.directory(existing: [], upserting: deviceB),
                       [deviceB])
        XCTAssertEqual(ParticipantProfileMerge.signingKeys(existing: [], adding: Data([2])),
                       [Data([2])])
    }
}

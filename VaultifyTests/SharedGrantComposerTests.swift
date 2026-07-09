import XCTest
@testable import Vaultify

/// Pins the pure grant-assembly rules the create + edit share paths now share,
/// so the edit path can never again drop passkeys or widen single-device scope.
final class SharedGrantComposerTests: XCTestCase {

    // MARK: allowedDevices (device-scope preservation)

    private func device(_ id: UInt8, at ms: Int64) -> DeviceHPKEDirectoryEntry {
        DeviceHPKEDirectoryEntry(deviceKeyID: Data([id]), hpkePublicKey: Data([id, id]),
                                 label: "d\(id)", addedAtUnixMs: ms)
    }

    func testMultiScopeSealsToNoDevices() throws {
        let result = try SharedGrantComposer.allowedDevices(
            scope: .multi, directory: [device(1, at: 1)])
        XCTAssertTrue(result.isEmpty)
    }

    func testSingleScopeEmptyDirectoryThrows() {
        // Never silently widen to multi (INV-04) — fail loud.
        XCTAssertThrowsError(try SharedGrantComposer.allowedDevices(scope: .single, directory: []))
    }

    func testSingleScopePicksFirstEnrolledDeterministically() throws {
        let later = device(1, at: 100)
        let earlier = device(2, at: 50)
        let result = try SharedGrantComposer.allowedDevices(
            scope: .single, directory: [later, earlier])
        XCTAssertEqual(result, [earlier])
    }

    // MARK: passkeyArtifacts (mode → display + hand-over blob)

    private func secret(_ rp: String) -> PasskeySecret {
        PasskeySecret(relyingParty: rp, userName: "u@\(rp)", userHandle: Data([1]),
                      credentialID: Data([9]), privateKeyRaw: Data([7]), counter: 0,
                      createdAt: Date(timeIntervalSince1970: 0), flags: 0x1D)
    }

    func testArtifactsIncludeGrantedModesAndShipSecretOnlyForHandOver() {
        let shared = "pk:aa", ask = "pk:bb", off = "pk:cc"
        let caps: [String: FieldCapability] = [
            shared: .passkey(.shared),
            ask: .passkey(.askEachTime),
            off: .passkey(.none),
        ]
        let art = SharedGrantComposer.passkeyArtifacts(
            secretsBySlot: [(shared, secret("s.com")), (ask, secret("a.com")), (off, secret("o.com"))],
            capabilities: caps)
        // Metadata travels for every GRANTED mode (recipient renders/registers it).
        XCTAssertEqual(Set(art.display.map(\.slotId)), [shared, ask])
        // The full secret ships ONLY for hand-over (mode .shared) — INV-07/08.
        XCTAssertEqual(Set(art.shared.keys), [shared])
    }

    func testArtifactsEmptyWhenNothingGranted() {
        let art = SharedGrantComposer.passkeyArtifacts(
            secretsBySlot: [("pk:x", secret("x.com"))],
            capabilities: ["pk:x": .passkey(.none)])
        XCTAssertTrue(art.display.isEmpty)
        XCTAssertTrue(art.shared.isEmpty)
    }
}

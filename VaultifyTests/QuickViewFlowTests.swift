import XCTest
@testable import Vaultify

/// Approval-UX tests (QV-A3, Increment B): exposure gating, the SAS
/// mismatch abort path, the payload composer's virtual-TOTP append + manifest
/// coverage, and the Enter Code charset/checksum pre-check.
@MainActor
final class QuickViewFlowTests: XCTestCase {

    private func makeRepo() -> VaultRepository {
        let session = VaultSession(settings: SettingsStore())
        session.adoptUnlocked(key: [UInt8](repeating: 0x2a, count: 32))
        let repo = VaultRepository(store: VaultStore(inMemory: true), session: session)
        repo.reload()
        TestLifetimeRetainer.retain(repo)
        return repo
    }

    // MARK: - Exposure gating (entry hidden unless the resolver allows it)

    func testEntryHiddenByDefaultRegardlessOfCohort() {
        UserDefaults.standard.removeObject(forKey: QuickViewExposureProvider.debugOverrideKey)
        XCTAssertFalse(QuickViewExposureProvider.entryVisible(isBetaCohort: true))
        XCTAssertFalse(QuickViewExposureProvider.entryVisible(isBetaCohort: false))
    }

    func testEntryVisibleForBetaCohortOnlyWhenOverrideIsBeta() {
        UserDefaults.standard.set("beta", forKey: QuickViewExposureProvider.debugOverrideKey)
        defer { UserDefaults.standard.removeObject(forKey: QuickViewExposureProvider.debugOverrideKey) }
        XCTAssertTrue(QuickViewExposureProvider.entryVisible(isBetaCohort: true))
        XCTAssertFalse(QuickViewExposureProvider.entryVisible(isBetaCohort: false))
    }

    /// Precedence: DEBUG override > verified-manifest exposure > `.hidden`
    /// fail-safe (no signed signal must never fall back to `.ga`).
    func testCurrentExposurePrecedence() {
        UserDefaults.standard.removeObject(forKey: QuickViewExposureProvider.debugOverrideKey)
        // No manifest, no override → hidden.
        XCTAssertEqual(QuickViewExposureProvider.currentExposure(manifestExposure: nil), .hidden)
        // Manifest signal, no override → the manifest's exposure wins.
        XCTAssertEqual(QuickViewExposureProvider.currentExposure(manifestExposure: .ga), .ga)
        XCTAssertTrue(QuickViewExposureProvider.entryVisible(manifestExposure: .ga, isBetaCohort: true))
        // DEBUG override wins over a verified-manifest signal.
        UserDefaults.standard.set("beta", forKey: QuickViewExposureProvider.debugOverrideKey)
        defer { UserDefaults.standard.removeObject(forKey: QuickViewExposureProvider.debugOverrideKey) }
        XCTAssertEqual(QuickViewExposureProvider.currentExposure(manifestExposure: .ga), .beta)
    }

    // MARK: - SAS mismatch — abort only, no bypass

    func testAbortSASMismatchResetsToIdleAndRecordsCancelled() throws {
        let repo = makeRepo()
        try repo.add(VaultItem(id: "item-1", category: .login, title: "Acme"))
        let history = QuickViewHistoryStore()
        let model = QuickViewApprovalFlowModel(itemID: "item-1", defaultSelectedFieldIDs: [],
                                               repository: repo, history: history)
        // Simulate a verified session (would normally come from a live resolve).
        model.state = .verified(.init(sessionID: "sess-1", sessionIDBytes: Data("sess-1".utf8),
                                      sas: "apple river 42",
                                      browserEncPublicKey: Data([0x04]), browserEncKeyHash: Data(),
                                      browserSigKeyHash: Data(), env: "staging",
                                      expiresAtUnixMs: Int64(Date().timeIntervalSince1970 * 1000) + 100_000))
        model.abortSASMismatch()
        XCTAssertEqual(model.state, .idle, "mismatch must abort to idle — no bypass state exists")
        XCTAssertEqual(history.rows(forItem: "item-1").first?.result, .cancelled)
    }

    // MARK: - Composer: virtual TOTP append + structural manifest coverage

    private func makeItem(includeTOTP: Bool) -> VaultItem {
        var fields = [
            DynamicField(label: "Username", kind: .username, value: "owner@example.com"),
            DynamicField(label: "Password", kind: .password, value: "s3cr3t!", protected: true),
        ]
        if includeTOTP {
            fields.append(DynamicField(label: "2FA", kind: .totp, value: "JBSWY3DPEHPK3PXP"))
        }
        return VaultItem(id: "item-totp", category: .login, title: "Acme", fields: fields)
    }

    func testComposerAppendsTOTPAfterPersistedFieldsAndCoversManifestHash() async throws {
        let item = makeItem(includeTOTP: true)
        let selected = Set(item.fields.filter { $0.kind != .totp }.map(\.id))
        let farExpiry = Int64(Date().timeIntervalSince1970 * 1000) + 10 * 60_000

        let without = try await QuickViewPayloadComposer.compose(
            item: item, selectedFieldIDs: selected, includeCurrentTOTP: false,
            sessionExpiresAtUnixMs: farExpiry)
        let with = try await QuickViewPayloadComposer.compose(
            item: item, selectedFieldIDs: selected, includeCurrentTOTP: true,
            sessionExpiresAtUnixMs: farExpiry)

        XCTAssertEqual(without.orderedFields.count, 2)
        XCTAssertFalse(without.orderedFields.contains { $0.kind == .currentTOTP })

        XCTAssertEqual(with.orderedFields.count, 3)
        XCTAssertEqual(with.orderedFields.last?.kind, .currentTOTP, "virtual field must be appended LAST")
        XCTAssertEqual(with.orderedFields.last?.stableID, QuickViewPayloadComposer.currentTOTPStableID)
        XCTAssertNotNil(with.orderedFields.last?.validUntilUnixMs)

        // The structural manifest hash must differ once the virtual field is
        // appended — proving the append happens BEFORE hashing, not after.
        XCTAssertNotEqual(without.fieldManifestHash, with.fieldManifestHash)
    }

    func testComposerWirePayloadMirrorsLooxLinkShapeWithValidUntilOnTOTPOnly() async throws {
        let item = makeItem(includeTOTP: true)
        let selected = Set(item.fields.filter { $0.kind != .totp }.map(\.id))
        let farExpiry = Int64(Date().timeIntervalSince1970 * 1000) + 10 * 60_000

        let result = try await QuickViewPayloadComposer.compose(
            item: item, selectedFieldIDs: selected, includeCurrentTOTP: true,
            sessionExpiresAtUnixMs: farExpiry)
        let payload = try JSONDecoder().decode(QuickViewPayload.self, from: result.payloadPlaintext)

        XCTAssertEqual(payload.fields.count, 3)
        // Persisted fields carry label/value/kind but no valid_until.
        for field in payload.fields.dropLast() {
            XCTAssertNil(field.validUntilUnixMs)
        }
        // Only the virtual TOTP field carries the authenticated expiry + the
        // "otp-code" wire kind the /open viewer expects.
        let totpField = try XCTUnwrap(payload.fields.last)
        XCTAssertEqual(totpField.kind, "otp-code")
        XCTAssertNotNil(totpField.validUntilUnixMs)
    }

    func testComposerTOTPWaitExceedsSessionBudgetThrows() async throws {
        let item = makeItem(includeTOTP: true)
        let selected: Set<String> = []
        // 25s into a 30s window → 5s remaining, below the 18s issuance floor,
        // so a wait is required; give a budget that expires before the next
        // window opens.
        let nowMs: Int64 = 25_000
        let tightExpiry = nowMs + 3_000

        do {
            _ = try await QuickViewPayloadComposer.compose(
                item: item, selectedFieldIDs: selected, includeCurrentTOTP: true,
                sessionExpiresAtUnixMs: tightExpiry,
                now: { Date(timeIntervalSince1970: Double(nowMs) / 1000) },
                sleep: { _ in })
            XCTFail("expected totpWaitExceedsSessionBudget")
        } catch QuickViewPayloadComposer.ComposeError.totpWaitExceedsSessionBudget {
            // expected
        }
    }

    func testComposerTOTPWithoutSeedThrows() async throws {
        let item = makeItem(includeTOTP: false)
        do {
            _ = try await QuickViewPayloadComposer.compose(
                item: item, selectedFieldIDs: [], includeCurrentTOTP: true,
                sessionExpiresAtUnixMs: Int64(Date().timeIntervalSince1970 * 1000) + 100_000)
            XCTFail("expected totpSeedUnreadable")
        } catch QuickViewPayloadComposer.ComposeError.totpSeedUnreadable {
            // expected
        }
    }

    /// A guard2 (Extra Protection) TOTP must never be handed off — its stored
    /// value is SecretGuard ciphertext, not a seed. The composer must fail
    /// closed EXPLICITLY, not by an incidental base32-decode failure.
    func testComposerExcludesGuard2TOTP() async throws {
        let item = VaultItem(id: "item-g2-totp", category: .login, title: "Acme", fields: [
            DynamicField(label: "Username", kind: .username, value: "owner@example.com"),
            DynamicField(label: "2FA", kind: .totp, value: "v2g:ZmFrZS1jaXBoZXJ0ZXh0", guard2: true),
        ])
        do {
            _ = try await QuickViewPayloadComposer.compose(
                item: item, selectedFieldIDs: [], includeCurrentTOTP: true,
                sessionExpiresAtUnixMs: Int64(Date().timeIntervalSince1970 * 1000) + 100_000)
            XCTFail("expected totpSeedUnreadable for guard2 TOTP")
        } catch QuickViewPayloadComposer.ComposeError.totpSeedUnreadable {
            // expected — guard2 TOTP excluded explicitly
        }
    }

    // MARK: - Enter Code: charset + checksum pre-check

    func testHumanCodeRoundTripsWithGeneratedChecksum() {
        let code = try! XCTUnwrap(QuickViewHumanCode.appendingChecksum(to: "2B3C4D7"))
        XCTAssertTrue(QuickViewHumanCode.isValid(code))
        XCTAssertEqual(QuickViewHumanCode.formatted(code), "\(code.prefix(4))-\(code.suffix(4))")
    }

    func testHumanCodeRejectsTamperedCharacter() {
        let code = try! XCTUnwrap(QuickViewHumanCode.appendingChecksum(to: "2B3C4D7"))
        var chars = Array(code)
        // Flip the first data character to another valid-alphabet symbol —
        // the checksum must no longer match.
        chars[0] = chars[0] == "2" ? "3" : "2"
        XCTAssertFalse(QuickViewHumanCode.isValid(String(chars)))
    }

    func testHumanCodeRejectsWrongLengthAndCharset() {
        XCTAssertFalse(QuickViewHumanCode.isValid("2B3C4D7"))     // 7 chars, too short
        XCTAssertFalse(QuickViewHumanCode.isValid("2B3C4D7OO"))   // 9 chars, too long
        XCTAssertFalse(QuickViewHumanCode.isValid("O0O0O0O0"))    // ambiguous chars excluded from the alphabet
    }

    func testHumanCodeNormalizeStripsDashesAndWhitespace() {
        XCTAssertEqual(QuickViewHumanCode.normalize(" 2b3c-4d7q "), "2B3C4D7Q")
    }

    /// Golden parity: a REAL backend-minted code (staging `mint()`, alphabet
    /// `23456789ABCDEFGHJKMNPQRSTVWXYZ` + Luhn-mod-N) must validate locally.
    /// Guards against the alphabet/checksum drift that once rejected every
    /// real code (the app wrongly kept `U` + a positional-sum checksum).
    func testHumanCodeAcceptsRealBackendCode() {
        XCTAssertTrue(QuickViewHumanCode.isValid("KHCK-TZZJ"))
        XCTAssertTrue(QuickViewHumanCode.isValid("khcktzzj"))
        XCTAssertFalse(QuickViewHumanCode.alphabet.contains("U"), "U must be excluded (matches BE)")
    }
}

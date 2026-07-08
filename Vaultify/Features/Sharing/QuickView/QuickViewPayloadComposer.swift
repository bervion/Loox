import Foundation

/// The wire shape actually sealed to the browser — mirrors `LooxLinkEnvelope`
/// so `/open` reuses the existing viewer renderer (backend proposal §B6:
/// "payload plaintext = `LooxLinkEnvelope` JSON schema: label/value/
/// concealed/kind"), plus one field-level extension: an authenticated
/// `valid_until`, present ONLY on the virtual current-TOTP field. Deliberately
/// NOT `QuickViewApprovedField` verbatim — `stableID` is app-internal
/// (structural manifest hashing only) and must never leave the device.
nonisolated struct QuickViewPayloadField: Codable, Sendable, Equatable {
    var label: String
    var value: String
    var concealed: Bool?
    var kind: String?
    var validUntilUnixMs: Int64?

    enum CodingKeys: String, CodingKey {
        case label, value, concealed, kind
        case validUntilUnixMs = "valid_until"
    }
}

nonisolated struct QuickViewPayload: Codable, Sendable, Equatable {
    var version: Int = 1
    var fields: [QuickViewPayloadField]
}

/// Assembles the FINAL ordered field array for one Quick View approval:
/// persisted fields (via `LooxLinkEnvelope`'s existing shareable-field
/// selection, UNCHANGED) followed by Quick-View-only virtual fields (current
/// TOTP, last). `LooxLinkEnvelope` never gains a Quick View concept — this
/// composer is the ONLY place persisted and virtual fields combine.
enum QuickViewPayloadComposer {

    nonisolated enum ComposeError: Error, Equatable {
        /// The TOTP boundary wait would outlive the remaining session budget
        /// — abort rather than seal-then-fail-at-upload.
        case totpWaitExceedsSessionBudget
        case totpSeedUnreadable
    }

    /// Fixed protocol identity for the virtual current-TOTP field — feeds the
    /// STRUCTURAL manifest hash only, never a per-item value, so its
    /// contribution to the hash is stable across items.
    static let currentTOTPStableID = "quick-view::current-totp"

    struct Result: Sendable {
        let orderedFields: [QuickViewApprovedField]
        let fieldManifestHash: Data
        /// JSON to hand to `QuickViewPayloadSealer.seal(plaintext:...)`.
        let payloadPlaintext: Data
    }

    /// - Parameters:
    ///   - item: a FRESHLY re-read item (post-Face-ID) — callers must not
    ///     reuse a copy read before the biometric prompt.
    ///   - selectedFieldIDs: the owner's persisted-field toggle selection.
    ///   - includeCurrentTOTP: the "Current 2FA code" toggle.
    ///   - sessionExpiresAtUnixMs: the resolved session's absolute expiry —
    ///     bounds the TOTP boundary wait: waiting past this must abort rather
    ///     than seal a payload the server will reject as expired anyway.
    static func compose(item: VaultItem, selectedFieldIDs: Set<String>,
                        includeCurrentTOTP: Bool, sessionExpiresAtUnixMs: Int64,
                        now: @escaping () -> Date = { .now },
                        sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) async throws -> Result {
        let ordered = LooxLinkEnvelope.shareableFields(of: item)
            .filter { selectedFieldIDs.contains($0.id) }
        let envelope = LooxLinkEnvelope.build(item: item, selectedFieldIDs: selectedFieldIDs)
        var fields: [QuickViewApprovedField] = zip(ordered, envelope.fields).map { source, built in
            QuickViewApprovedField(stableID: source.id, kind: kind(fromViewerKind: built.kind),
                                   label: built.label, value: built.value,
                                   concealed: built.concealed ?? false)
        }
        if includeCurrentTOTP {
            guard let totpField = item.totpField, !totpField.value.isEmpty else {
                throw ComposeError.totpSeedUnreadable
            }
            // Extra-protected (guard2) TOTP is never handed off: its stored value
            // is SecretGuard ciphertext, not a base32 seed. Fail closed explicitly
            // rather than relying on the decode returning nil downstream — mirrors
            // LooxLinkEnvelope.shareableFields excluding every guard2 field.
            guard !totpField.isExtraProtected else {
                throw ComposeError.totpSeedUnreadable
            }
            let totpSecret = totpField.value
            fields.append(try await mintCurrentTOTPField(
                secretOrURI: totpSecret, sessionExpiresAtUnixMs: sessionExpiresAtUnixMs,
                now: now, sleep: sleep))
        }
        // AAD binds this exact ordered array — freeze here; callers must not
        // reorder the result afterward.
        let hash = QuickViewFieldManifest.hash(orderedFields: fields)
        let payload = QuickViewPayload(fields: fields.map(wireField))
        let plaintext = try JSONEncoder().encode(payload)
        return Result(orderedFields: fields, fieldManifestHash: hash, payloadPlaintext: plaintext)
    }

    // MARK: - TOTP minting (boundary-aware, Quick-View-owned wait loop)

    /// Current code only (never the seed, never a future-window code) — the
    /// wait, when needed, is owned entirely by this composer (never
    /// `ApprovalCeremonyService`, which is CKShare/ChaCha-bound and unrelated).
    private static func mintCurrentTOTPField(secretOrURI: String, sessionExpiresAtUnixMs: Int64,
                                             now: () -> Date,
                                             sleep: (Duration) async throws -> Void) async throws
        -> QuickViewApprovedField {
        let period: UInt32 = secretOrURI.lowercased().hasPrefix("otpauth://")
            ? UInt32(max(TOTPGenerator.parse(uri: secretOrURI)?.period ?? 30, 1))
            : 30
        var targetDate = now()
        var nowMs = Int64(targetDate.timeIntervalSince1970 * 1000)
        if !TOTPIssuancePolicy.v1.canIssueNow(atUnixMs: nowMs, period: period) {
            let waitMs = TOTPWindow.remainingMs(atUnixMs: nowMs, period: period)
            guard nowMs + waitMs < sessionExpiresAtUnixMs else {
                throw ComposeError.totpWaitExceedsSessionBudget
            }
            if waitMs > 0 { try await sleep(.milliseconds(waitMs)) }
            targetDate = now()
            nowMs = Int64(targetDate.timeIntervalSince1970 * 1000)
        }
        guard let code = TOTPGenerator.code(forStoredValue: secretOrURI, date: targetDate) else {
            throw ComposeError.totpSeedUnreadable
        }
        let validUntilMs = TOTPWindow.periodEndUnixMs(atUnixMs: nowMs, period: period)
        return QuickViewApprovedField(stableID: currentTOTPStableID, kind: .currentTOTP,
                                      label: appString("Current 2FA code"), value: code,
                                      concealed: false, validUntilUnixMs: validUntilMs)
    }

    // MARK: - Kind mapping

    private static func kind(fromViewerKind raw: String?) -> QuickViewFieldKind {
        switch raw {
        case "username": .username
        case "password": .password
        case "url": .website
        case "note": .note
        default: .custom
        }
    }

    private static func wireKind(_ kind: QuickViewFieldKind) -> String {
        switch kind {
        case .username, .email: "username"
        case .password: "password"
        case .website: "url"
        case .note: "note"
        case .custom: "custom"
        case .currentTOTP: "otp-code"
        }
    }

    private static func wireField(_ field: QuickViewApprovedField) -> QuickViewPayloadField {
        QuickViewPayloadField(label: field.label, value: field.value,
                              concealed: field.concealed ? true : nil,
                              kind: wireKind(field.kind),
                              validUntilUnixMs: field.kind == .currentTOTP ? field.validUntilUnixMs : nil)
    }
}

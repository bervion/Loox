import XCTest
import CloudKit
@testable import Vaultify

/// Relay failure handling: the bounded silent-retry decision table and the
/// user-facing copy mapping (backend vocabulary must never surface).
@MainActor
final class RelayRetryPolicyTests: XCTestCase {

    func testEscrowGenesisRequiresConfirmedAbsence() {
        for code in [CKError.Code.unknownItem, .zoneNotFound] {
            XCTAssertTrue(RelayPrincipalEscrowService.isMissingEscrow(CKError(code)))
        }
        for code in [CKError.Code.notAuthenticated, .networkFailure, .serviceUnavailable,
                     .permissionFailure, .serverRejectedRequest, .partialFailure] {
            XCTAssertFalse(RelayPrincipalEscrowService.isMissingEscrow(CKError(code)))
        }
        XCTAssertFalse(RelayPrincipalEscrowService.isMissingEscrow(URLError(.timedOut)))
    }

    func testUnauthenticatedEscrowHasAccountSpecificFailure() {
        let error = NSError(domain: CKErrorDomain, code: CKError.Code.notAuthenticated.rawValue)
        XCTAssertEqual(RelayService.Failure.principalFailure(for: error), .iCloudAuthenticationRequired)
        XCTAssertEqual(RelayService.Failure.iCloudAuthenticationRequired.userTitle,
                       appString("Sign in to iCloud"))
        XCTAssertNotEqual(RelayService.Failure.iCloudAuthenticationRequired.userMessage,
                          RelayService.Failure.principalUnavailable.userMessage)
    }

    func testOtherEscrowErrorsDoNotSuggestSigningIn() {
        for code in [CKError.Code.networkFailure, .permissionFailure, .serverRejectedRequest] {
            XCTAssertEqual(RelayService.Failure.principalFailure(for: CKError(code)), .principalUnavailable)
        }
        // A numeric 9 from another error domain is not CloudKit authentication.
        XCTAssertEqual(RelayService.Failure.principalFailure(for: NSError(domain: "Other", code: 9)),
                       .principalUnavailable)
    }

    func testEscrowFromAnotherVaultOffersAReset() {
        let failure = RelayService.Failure.principalFailure(
            for: RelayPrincipalIdentity.EscrowFailure.cannotOpenWithVaultKey)
        XCTAssertEqual(failure, .principalFromAnotherVault)
        XCTAssertTrue(failure.offersPrivateEmailReset)
        // Not the iCloud copy, which sent users to Settings for a problem that
        // was not there.
        XCTAssertNotEqual(failure.userTitle, RelayService.Failure.principalUnavailable.userTitle)
        XCTAssertNotEqual(failure.userMessage, RelayService.Failure.principalUnavailable.userMessage)
    }

    func testOnlyAnUnopenableEscrowMayBeReplaced() {
        XCTAssertTrue(RelayPrincipalEscrowService.isUnopenableWithThisVault(
            RelayPrincipalIdentity.EscrowFailure.cannotOpenWithVaultKey))
        // A newer format, damaged key material and CloudKit trouble keep the
        // escrow: replacing it would orphan aliases that may still be reachable.
        let kept: [any Error] = [
            RelayPrincipalIdentity.EscrowFailure.unknownVersion,
            RelayPrincipalIdentity.EscrowFailure.invalidKeyMaterial,
            RelayPrincipalIdentity.EscrowFailure.identityMismatch,
            CKError(.networkFailure), CKError(.notAuthenticated), CKError(.unknownItem),
        ]
        for error in kept {
            XCTAssertFalse(RelayPrincipalEscrowService.isUnopenableWithThisVault(error), "\(error)")
            XCTAssertFalse(RelayService.Failure.principalFailure(for: error).offersPrivateEmailReset, "\(error)")
        }
    }

    func testEscrowFailureDoesNotClaimRelayOutage() {
        XCTAssertNotEqual(RelayService.Failure.principalUnavailable.userTitle,
                          RelayService.Failure.rejected("server_503").userTitle)
        XCTAssertNotEqual(RelayService.Failure.principalUnavailable.userMessage,
                          RelayService.Failure.rejected("server_503").userMessage)
    }

    func testNonceReplayRetriesExactlyOnce() {
        XCTAssertEqual(RelayRetryPolicy.action(for: .nonceReplay, attempt: 1), .retry)
        XCTAssertEqual(RelayRetryPolicy.action(for: .nonceReplay, attempt: 2), .fail("nonce_replay"))
    }

    func testEpochStaleRefreshesThenRetriesExactlyOnce() {
        XCTAssertEqual(RelayRetryPolicy.action(for: .epochStale, attempt: 1), .refreshEpochThenRetry)
        XCTAssertEqual(RelayRetryPolicy.action(for: .epochStale, attempt: 2), .fail("epoch_stale"))
    }

    func testHardFailuresNeverRetry() {
        for attempt in [1, 2] {
            XCTAssertEqual(RelayRetryPolicy.action(for: .unauthorized, attempt: attempt), .fail("unauthorized"))
            XCTAssertEqual(RelayRetryPolicy.action(for: .rateLimited, attempt: attempt), .fail("rate_limited"))
            XCTAssertEqual(RelayRetryPolicy.action(for: .aliasCapReached, attempt: attempt), .fail("alias_cap_reached"))
            XCTAssertEqual(RelayRetryPolicy.action(for: .transport, attempt: attempt), .fail("network"))
            XCTAssertEqual(RelayRetryPolicy.action(for: .server(500), attempt: attempt), .fail("server_500"))
        }
    }

    func testUnknownAttestationKeyReenrollsExactlyOnce() {
        XCTAssertEqual(RelayRetryPolicy.action(for: .attestationKeyUnknown, attempt: 1), .reenrollThenRetry)
        for attempt in [2, 3] {
            XCTAssertEqual(RelayRetryPolicy.action(for: .attestationKeyUnknown, attempt: attempt), .fail("unauthorized"))
        }
    }

    func testEnrollmentNetworkAndServerFailuresDoNotBlameDeviceIdentity() {
        XCTAssertEqual(RelayService.Failure.attestationFailure(for: RelayAPIClient.Failure.transport), .network)
        XCTAssertEqual(RelayService.Failure.attestationFailure(for: RelayAPIClient.Failure.server(429)), .rejected("rate_limited"))
        XCTAssertEqual(RelayService.Failure.attestationFailure(for: RelayAPIClient.Failure.server(503)), .rejected("server_503"))
        XCTAssertEqual(RelayService.Failure.attestationFailure(for: NSError(domain: "DeviceCheck", code: 2)), .rejected("unauthorized"))
    }

    func testUserMessageNeverLeaksBackendVocabulary() {
        let failures: [RelayService.Failure] = [
            .vaultLocked, .principalUnavailable, .iCloudAuthenticationRequired, .principalFromAnotherVault,
            .missingDestination, .network,
            .rejected("unauthorized"), .rejected("rate_limited"),
            .rejected("nonce_replay"), .rejected("epoch_stale"), .rejected("server_503"),
            .rejected("alias_cap_reached"),
        ]
        for failure in failures {
            let message = failure.userMessage
            XCTAssertFalse(message.isEmpty)
            for banned in ["nonce", "epoch", "principal", "transcript", "alias_"] {
                XCTAssertFalse(message.lowercased().contains(banned),
                               "\(failure) leaked '\(banned)' in: \(message)")
            }
        }
    }

    func testDistinctCopyForActionableFailures() {
        // Offline, device-verify, and rate-limit each need their own guidance.
        let messages = [RelayService.Failure.network,
                        .rejected("unauthorized"),
                        .rejected("rate_limited")].map(\.userMessage)
        XCTAssertEqual(Set(messages).count, messages.count)
    }
}

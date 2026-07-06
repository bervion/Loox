import XCTest
@testable import Vaultify

/// Relay failure handling: the bounded silent-retry decision table and the
/// user-facing copy mapping (backend vocabulary must never surface).
@MainActor
final class RelayRetryPolicyTests: XCTestCase {

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

    func testUserMessageNeverLeaksBackendVocabulary() {
        let failures: [RelayService.Failure] = [
            .vaultLocked, .principalUnavailable, .missingDestination, .network,
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

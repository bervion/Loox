import XCTest
@testable import Vaultify

@MainActor
final class AppAttestEnrollmentCoordinatorTests: XCTestCase {
    private let productionScope = "api.example.test#production"
    private let developmentScope = "api.example.test#development"

    func testSameScopeSharesTheInFlightEnrollment() async throws {
        let coordinator = AppAttestEnrollmentCoordinator()
        let started = expectation(description: "First enrollment started")
        let secondEntered = expectation(description: "Second caller entered coordinator")
        let gate = EnrollmentGate(started: started)
        let duplicate = EnrollmentProbe()
        let scope = productionScope

        let first = Task { try await coordinator.key(scope: scope) { try await gate.enroll() } }
        await fulfillment(of: [started], timeout: 2)
        let second = Task {
            try await coordinator.enterKey(scope: scope, entered: secondEntered) {
                await duplicate.key("unexpected-second-key")
            }
        }
        await fulfillment(of: [secondEntered], timeout: 2)
        await gate.finish(with: .success("shared-key"))

        let firstKey = try await first.value
        let secondKey = try await second.value
        let firstEnrollments = await gate.calls
        let duplicateEnrollments = await duplicate.calls
        XCTAssertEqual(firstKey, "shared-key")
        XCTAssertEqual(secondKey, firstKey)
        XCTAssertEqual(firstEnrollments, 1)
        XCTAssertEqual(duplicateEnrollments, 0)
    }

    func testDifferentScopesEnrollIndependently() async throws {
        let coordinator = AppAttestEnrollmentCoordinator()
        let productionStarted = expectation(description: "Production enrollment started")
        let developmentStarted = expectation(description: "Development enrollment started")
        let developmentFinished = expectation(description: "Development completed while production waits")
        let productionGate = EnrollmentGate(started: productionStarted)
        let developmentGate = EnrollmentGate(started: developmentStarted)
        let production = productionScope
        let development = developmentScope

        let first = Task {
            try await coordinator.key(scope: production) { try await productionGate.enroll() }
        }
        await fulfillment(of: [productionStarted], timeout: 2)
        let second = Task {
            let key = try await coordinator.key(scope: development) { try await developmentGate.enroll() }
            developmentFinished.fulfill()
            return key
        }
        await fulfillment(of: [developmentStarted], timeout: 2)
        await developmentGate.finish(with: .success("development-key"))
        await fulfillment(of: [developmentFinished], timeout: 2)
        let productionStillWaiting = await productionGate.isWaiting
        XCTAssertTrue(productionStillWaiting)
        // Release both tasks even if an expectation above failed.
        await productionGate.finish(with: .success("production-key"))

        let firstKey = try await first.value
        let secondKey = try await second.value
        let productionEnrollments = await productionGate.calls
        let developmentEnrollments = await developmentGate.calls
        XCTAssertEqual(firstKey, "production-key")
        XCTAssertEqual(secondKey, "development-key")
        XCTAssertEqual(productionEnrollments, 1)
        XCTAssertEqual(developmentEnrollments, 1)
    }

    func testSharedFailureAllowsALaterEnrollmentRetry() async throws {
        let coordinator = AppAttestEnrollmentCoordinator()
        let started = expectation(description: "Failing enrollment started")
        let secondEntered = expectation(description: "Second caller joined failing enrollment")
        let gate = EnrollmentGate(started: started)
        let retry = EnrollmentProbe()
        let scope = productionScope

        let first = Task { try await coordinator.key(scope: scope) { try await gate.enroll() } }
        await fulfillment(of: [started], timeout: 2)
        let second = Task {
            try await coordinator.enterKey(scope: scope, entered: secondEntered) {
                await retry.key("unexpected-second-key")
            }
        }
        await fulfillment(of: [secondEntered], timeout: 2)
        await gate.finish(with: .failure(EnrollmentError.rejected))
        await assertRejected(first)
        await assertRejected(second)
        let enrollmentsBeforeRetry = await retry.calls
        XCTAssertEqual(enrollmentsBeforeRetry, 0)

        let recoveredKey = try await coordinator.key(scope: scope) { await retry.key("recovered-key") }
        let retryEnrollments = await retry.calls
        XCTAssertEqual(recoveredKey, "recovered-key")
        XCTAssertEqual(retryEnrollments, 1)
    }

    func testCompletedEnrollmentIsNotRetainedAsAStaleCache() async throws {
        let coordinator = AppAttestEnrollmentCoordinator()
        let probe = EnrollmentProbe()
        let first = try await coordinator.key(scope: productionScope) { await probe.key("old-key") }
        let replacement = try await coordinator.key(scope: productionScope) { await probe.key("replacement-key") }
        let enrollments = await probe.calls
        XCTAssertEqual(first, "old-key")
        XCTAssertEqual(replacement, "replacement-key")
        XCTAssertEqual(enrollments, 2)
    }

    private func assertRejected(_ task: Task<String, Error>,
                                file: StaticString = #filePath, line: UInt = #line) async {
        switch await task.result {
        case .success:
            XCTFail("Enrollment must preserve the shared failure", file: file, line: line)
        case .failure(let error):
            XCTAssertEqual(error as? EnrollmentError, .rejected, file: file, line: line)
        }
    }
}

private extension AppAttestEnrollmentCoordinator {
    /// This marker and the entry to key run on the same actor without a
    /// suspension between them. The first caller cannot clear its pending
    /// task before this second caller has joined, even if the test releases
    /// the enrollment gate immediately after receiving the marker.
    func enterKey(scope: String, entered: XCTestExpectation,
                  enroll: @escaping @Sendable () async throws -> String) async throws -> String {
        entered.fulfill()
        return try await key(scope: scope, enroll: enroll)
    }
}

private actor EnrollmentGate {
    let started: XCTestExpectation
    private(set) var calls = 0
    private var continuation: CheckedContinuation<String, Error>?

    init(started: XCTestExpectation) { self.started = started }

    var isWaiting: Bool { continuation != nil }

    func enroll() async throws -> String {
        calls += 1
        started.fulfill()
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func finish(with result: Result<String, Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }
}

private actor EnrollmentProbe {
    private(set) var calls = 0

    func key(_ value: String) -> String {
        calls += 1
        return value
    }
}

nonisolated private enum EnrollmentError: Error, Equatable {
    case rejected
}

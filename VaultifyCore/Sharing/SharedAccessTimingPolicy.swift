import Foundation

/// Central timing configuration for the shared-vault access gate and the
/// approval ceremonies — no magic numbers in call sites (P00). The three
/// budgets are deliberately independent: a request's server-side TTL is not
/// the UI wait, and neither is the extension's polling budget — a response
/// that lands after its ceremony was abandoned is harmless because responses
/// are bound to their requestID (INV-09).
nonisolated struct SharedAccessTimingPolicy: Sendable {
    /// Authoritative grant verification longer than this fails CLOSED into
    /// the `unavailable` state (INV-03) — never treated as "offline".
    var grantVerificationDeadline: Duration = .seconds(4)
    /// Server-side lifetime of an askEachTime approval request.
    var approvalRequestTTL: Duration = .seconds(120)
    /// How long the AutoFill extension keeps polling for an approval response.
    var extensionPollingBudget: Duration = .seconds(45)
    /// Poll spacing (last value repeats until the budget runs out).
    var pollingBackoff: [Duration] = [.seconds(1), .seconds(2), .seconds(3), .seconds(5)]

    static let standard = SharedAccessTimingPolicy()
}

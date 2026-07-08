import Foundation

/// Canonical endpoints, TTLs, and size limits for Quick View — mirrors
/// `LooxLinkConfig`'s DEBUG-override convention. Quick View talks to its OWN
/// dedicated worker (F6 — never the shared loox-link service-state route),
/// and the QR/code payload is never itself a callable URL (INV-QV-14).
nonisolated enum QuickViewConfig {
    // DEBUG builds target staging so dev/QA round-trips work on any device
    // without a local Worker; Release targets production.
    #if DEBUG
    static let defaultAPIBase = URL(string: "https://api-staging.looxpassword.com")!
    #else
    static let defaultAPIBase = URL(string: "https://api.looxpassword.com")!
    #endif

    /// `#if DEBUG` UserDefaults override (mirrors `loox_link_api_base_url`)
    /// so a local `wrangler dev` Worker can be targeted without a rebuild.
    static var apiBase: URL {
        #if DEBUG
        if let raw = UserDefaults.standard.string(forKey: "quick_view_api_base_url"),
           let url = URL(string: raw) { return url }
        #endif
        return defaultAPIBase
    }

    static let servicePathPrefix = "/v1/quick-view"

    /// Dedicated quick-view service-state route (Phase 3 wiring; F6 — never
    /// the shared `/v1/link/service-state` loox-link uses).
    static var serviceStateURL: URL {
        apiBase.appending(path: "\(servicePathPrefix)/service-state")
    }

    // MARK: TTLs (plan.md, owner-locked)

    /// Browser tab session window before the QR/code goes stale.
    static let sessionResolveTTLSeconds: TimeInterval = 180
    /// Owner-approval → upload window once approval starts.
    static let approvalUploadTTLSeconds: TimeInterval = 90
    /// Browser payload render window (DEC-QV-TOTP-01 fallback:
    /// `min(5m, otp_valid_until)` when field-level TOTP expiry isn't used).
    static let payloadRenderTTLSeconds: TimeInterval = 300
    /// Advisory "phone connected" bind window — failure here never blocks
    /// approve (bind is telemetry-only, plan.md).
    static let bindAdvisoryTTLSeconds: TimeInterval = 120

    /// Max serialized upload body size (ciphertext + framing).
    static let maxBodyBytes = 16 * 1024

    static let cryptoVersion = QuickViewPayloadSealer.cryptoVersion

    /// Inside-the-signed-payload environment tag (same convention as
    /// `DomainRegistryDocument.env`) — a staging session can never verify
    /// against a production install or vice versa.
    static var environment: String {
        #if DEBUG
        "staging"
        #else
        "production"
        #endif
    }

    /// Tracks the server's `ASSERTION_MODE`. Prod is `required` (verified live
    /// 2026-07-08 — required-before-active, enforced by the worker), so this is
    /// `true`. Enforcement of the assertion itself is SERVER-side: the client
    /// always sends the App Attest headers when it can and the prod worker
    /// rejects an upload that lacks a valid assertion. Client-side this flag
    /// only feeds `QuickViewExposureResolver`'s `assertionRequired` signal —
    /// which is what makes the "Open on Computer" entry visible to GENERAL
    /// (non-beta) users once `exposure = ga` (a general user under `ga` is gated
    /// on assertion being required, INV-QV-24). Keep it in lockstep with the
    /// server: while the server is still `shadow`, set this `false`.
    static let assertionRequired = true
}

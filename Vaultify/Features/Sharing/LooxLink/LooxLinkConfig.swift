import Foundation

/// Environment + limits for the Loox Link server (`workers/loox-link`).
/// Production endpoints are the defaults; DEBUG builds can point at a local
/// `wrangler dev` Worker via UserDefaults overrides (config only — no secrets:
/// the design is self-provisioning, there is no API key to embed).
nonisolated enum LooxLinkConfig {
    // DEBUG builds target staging so dev/QA round-trips work on any device
    // without a local Worker; Release targets production.
    #if DEBUG
    static let defaultAPIBase = URL(string: "https://api-staging.looxpassword.com")!
    static let defaultViewerBase = URL(string: "https://s-staging.looxpassword.com")!
    #else
    static let defaultAPIBase = URL(string: "https://api.looxpassword.com")!
    static let defaultViewerBase = URL(string: "https://s.looxpassword.com")!
    #endif

    /// App Attest register/assert flow. The Worker's register route is live
    /// on staging + production (verified 260706: bogus challenge → 401
    /// challenge_invalid, no longer the 404 catch-all) and create-share
    /// verifies assertions in SHADOW mode (`ASSERTION_MODE=off` server-side:
    /// verify + observe, interim token remains the auth).
    static let attestationEnabled = true

    /// Fail-closed switch, flipped together with the server moving
    /// `ASSERTION_MODE` to `required`: attestation failures then BLOCK the
    /// create (C6 — no unauthenticated fallback). While the server is in
    /// off/shadow mode, an attest failure only logs and the token path
    /// proceeds — a register bug must not brick a flow the assertion isn't
    /// even authenticating yet.
    static let attestationRequired = false

    /// Interim anti-abuse token (`X-Loox-App-Token`) — both staging and
    /// production Workers gate create on it until App Attest ships (C7).
    /// Resolution order, never hard-coded in source:
    /// 1. UserDefaults `loox_link_app_token` (dev: Xcode launch argument
    ///    `-loox_link_app_token <t>` or `simctl … defaults write`).
    /// 2. Info.plist `LooxLinkAppToken`, injected at `tuist generate` time
    ///    from the `TUIST_LOOX_LINK_PROD_TOKEN` environment variable (set on
    ///    the CI runner for Release/TestFlight; absent → empty → nil here).
    static var appToken: String? {
        if let t = UserDefaults.standard.string(forKey: "loox_link_app_token"), !t.isEmpty {
            #if DEBUG
            // A token supplied as an Xcode launch argument lives only in the
            // volatile argument domain — persist it so the device keeps
            // working after the arg is removed (Tuist regenerates schemes,
            // wiping launch args). One run with the arg provisions the device.
            UserDefaults.standard.set(t, forKey: "loox_link_app_token")
            #endif
            return t
        }
        if let t = Bundle.main.object(forInfoDictionaryKey: "LooxLinkAppToken") as? String,
           !t.isEmpty {
            return t
        }
        return nil
    }

    static var apiBase: URL {
        #if DEBUG
        if let raw = UserDefaults.standard.string(forKey: "loox_link_api_base_url"),
           let url = URL(string: raw) { return url }
        #endif
        return defaultAPIBase
    }

    static var viewerBase: URL {
        #if DEBUG
        if let raw = UserDefaults.standard.string(forKey: "loox_link_viewer_base_url"),
           let url = URL(string: raw) { return url }
        #endif
        return defaultViewerBase
    }

    /// Server caps (mirrored client-side to fail early with a clear message).
    static let maxExpirySeconds: UInt64 = 2_592_000 // 30 days
    static let maxBodyBytes = 64 * 1024

    static let cryptoVersion: UInt32 = 1

    /// One-time links don't expose the expiry picker (two competing time
    /// concepts read as confusing) — they die on first open, with this fixed
    /// safety net so an unopened link can't float around for weeks.
    static let oneTimeFallbackExpirySeconds: UInt64 = 86_400

    /// Expiry presets surfaced in the UI. Default: 24 hours.
    enum ExpiryPreset: UInt64, CaseIterable, Identifiable {
        case fiveMinutes = 300
        case tenMinutes = 600
        case fifteenMinutes = 900
        case thirtyMinutes = 1_800
        case oneHour = 3_600
        case oneDay = 86_400
        case sevenDays = 604_800
        case thirtyDays = 2_592_000

        var id: UInt64 { rawValue }
        var seconds: UInt64 { rawValue }
    }

    /// Share URL: the id is path material; the content key ONLY ever appears
    /// in the fragment (never sent to any server, never logged). One-time
    /// links carry a fragment-only `o=1` hint so the viewer gates the
    /// burn-after-read fetch behind an explicit click (link-preview bots
    /// must not consume the single view).
    static func shareURL(shareId: String, fragmentKey: String, oneTime: Bool = false) -> URL? {
        URL(string: "\(viewerBase.absoluteString)/s/\(shareId)#k=\(fragmentKey)\(oneTime ? "&o=1" : "")")
    }
}

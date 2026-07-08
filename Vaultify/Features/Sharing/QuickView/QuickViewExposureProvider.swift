import Foundation

/// App build/cohort gate for Quick View — one layer of the multi-layer
/// exposure gate (`QuickViewExposureResolver`'s `isBetaCohort`). A DEBUG or
/// TestFlight build reads as the "beta" cohort; an App Store Release build
/// (no sandbox receipt) never does. The backend's own cohort allowlist is the
/// other, load-bearing layer — this alone can never widen access past what
/// the server accepts.
nonisolated enum QuickViewBuildCohort {
    static var isBeta: Bool {
        #if DEBUG
        true
        #else
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }
}

/// Bridges an operator-declared exposure signal into the pure
/// `QuickViewExposureResolver` matrix.
///
/// Precedence for `currentExposure`:
///   1. DEBUG-only `quick_view_exposure_override` UserDefaults (QA escape
///      hatch — mirrors the `loox_link_api_base_url` override convention);
///      never compiled into Release/TestFlight builds.
///   2. The verified schema-2+ manifest exposure, when one was supplied.
///   3. `.hidden` — FAIL-SAFE. No signed signal must never fall back to
///      `.ga`: "ga" is only the byte-encoding default INSIDE a signed
///      schema-2 manifest transcript, never the app's no-manifest fallback.
nonisolated enum QuickViewExposureProvider {
    static let debugOverrideKey = "quick_view_exposure_override"

    static func currentExposure(manifestExposure: QuickViewExposure? = nil) -> QuickViewExposure {
        #if DEBUG
        if let raw = UserDefaults.standard.string(forKey: debugOverrideKey),
           let exposure = QuickViewExposure(rawValue: raw) {
            return exposure
        }
        #endif
        return manifestExposure ?? .hidden
    }

    static func entryVisible(manifestExposure: QuickViewExposure? = nil,
                             isBetaCohort: Bool = QuickViewBuildCohort.isBeta) -> Bool {
        QuickViewExposureResolver.entryVisible(exposure: currentExposure(manifestExposure: manifestExposure),
                                               assertionRequired: QuickViewConfig.assertionRequired,
                                               isBetaCohort: isBetaCohort)
    }
}

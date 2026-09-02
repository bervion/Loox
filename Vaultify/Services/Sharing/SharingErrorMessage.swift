import CloudKit
import DeviceCheck
import Foundation

/// User-facing text for a sharing failure.
///
/// CloudKit's own `localizedDescription` is written for developers and follows
/// the DEVICE language, so a Vietnamese or Japanese user hits English strings
/// like "Couldn't communicate with a helper application" mid-flow. Errors the
/// app defines already carry good copy (`LocalizedError`) and pass through
/// untouched; CloudKit's are mapped to a cause the user can act on.
nonisolated enum SharingErrorMessage {
    static func text(for error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        if let dcError = error as? DCError {
            return attestationText(for: dcError)
        }
        guard let ckError = error as? CKError else {
            return appString("Something went wrong. Please try again.")
        }
        switch ckError.code {
        case .networkUnavailable, .networkFailure:
            return appString("No connection. Check your network and try again.")
        case .notAuthenticated:
            return appString("Sign in to iCloud to continue.")
        case .quotaExceeded:
            return appString("Your iCloud storage is full.")
        case .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return appString("iCloud is busy right now. Try again in a moment.")
        case .permissionFailure:
            return appString("iCloud denied this request. Check that iCloud Drive is on for Loox.")
        case .participantMayNeedVerification:
            return appString("They need to verify their iCloud account before they can accept.")
        case .unknownItem, .referenceViolation:
            return appString("This share is no longer available.")
        default:
            return appString("Something went wrong with iCloud. Please try again.")
        }
    }

    /// App Attest failures used to collapse into the generic fallback above, so
    /// a device that could never attest looked identical to a server hiccup —
    /// and the one field that says which is which never reached anyone. Each
    /// cause now gets its own sentence plus a stable short code, because these
    /// arrive from a build we cannot attach a debugger to.
    private static func attestationText(for error: DCError) -> String {
        let sentence: String
        switch error.code {
        case .serverUnavailable:
            sentence = appString("Apple couldn't verify this app right now. Try again in a moment.")
        case .invalidKey:
            sentence = appString("This install needs to verify itself again. Try once more, and reinstall Loox if it keeps failing.")
        case .featureUnsupported:
            sentence = appString("This device can't verify the app, so share links are unavailable on it.")
        case .invalidInput:
            sentence = appString("The app sent something Apple's verification rejected. Please report this.")
        default:
            // `unknownSystemFailure` and anything Apple adds later.
            sentence = appString("Apple's app verification failed on this device. Please report this.")
        }
        // The code is appended outside localization so it reads the same in
        // every language and stays quotable in a bug report.
        return "\(sentence) (AA-\(error.code.rawValue))"
    }
}

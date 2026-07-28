import CloudKit
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
}

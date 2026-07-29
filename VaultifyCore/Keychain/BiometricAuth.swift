import Foundation
import LocalAuthentication

/// Device biometric capability lookups (no key access — see `BiometricKeyStore`).
nonisolated enum BiometricAuth {
    static func biometryType() -> LABiometryType {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        else { return .none }
        return context.biometryType
    }

    static var isAvailable: Bool { biometryType() != .none }

    /// Human label for the available biometry ("Face ID" / "Touch ID").
    static var displayName: String { displayName(for: biometryType()) }

    /// Polaris icon best matching the available biometry.
    static var iconAsset: String { iconAsset(for: biometryType()) }

    /// SF Symbol for the available biometry — used for the lock-screen badge, where the
    /// system glyph is the recognised affordance and Polaris ships no biometric equivalent.
    static var systemImage: String { systemImage(for: biometryType()) }

    // The naming is split from the probe on purpose: `biometryType()` is a
    // synchronous round-trip to the biometry daemon, so a caller that needs
    // several of these must probe ONCE and map the result (see
    // `BiometricCapability`) rather than pay for a fresh `LAContext` per label.

    static func displayName(for type: LABiometryType) -> String {
        switch type {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return appString("Biometrics")
        }
    }

    static func iconAsset(for type: LABiometryType) -> String {
        switch type {
        case .faceID, .opticID: return "ic_person"
        case .touchID: return "ic_passkey"
        default: return "ic_lock"
        }
    }

    static func systemImage(for type: LABiometryType) -> String {
        switch type {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .opticID: return "opticid"
        default: return "lock.fill"
        }
    }

    // MARK: - Failure classification

    /// How the app reads a biometric failure. This is the input to the app-wide
    /// policy in `VaultSession.noteBiometricOutcome`: a rejected face locks the
    /// vault, a dismissed prompt never does.
    enum Outcome: Equatable {
        /// The user dismissed the prompt, or chose the password fallback.
        /// Never a security signal.
        case cancelled
        /// Biometry ran and rejected the presented face or finger, or the cause
        /// could not be attributed.
        case failed
        /// Biometry is locked out until the device passcode is entered, so
        /// retrying is guaranteed to fail.
        case lockout
        /// Biometry could not run at all: no sensor, nothing enrolled, or the
        /// stored item was invalidated. Nothing was attempted, so no penalty.
        case unavailable
    }

    /// Classify anything thrown by a biometric prompt or a biometric-gated
    /// Keychain read.
    ///
    /// Unrecognised errors map to `.failed`. This feeds a security policy, and
    /// the conservative reading of "something went wrong during an identity
    /// check" is that identity was not established. The same choice also keeps
    /// the master-password fallback reachable on the lock screen instead of
    /// leaving a badge that can never succeed.
    static func classify(_ error: Error) -> Outcome {
        // Keychain failures already know their own meaning (and one of them
        // lives in a target this file cannot see — see the protocol below).
        if let reporting = error as? BiometricOutcomeReporting { return reporting.biometricOutcome }
        guard let laError = error as? LAError else { return .failed }
        switch laError.code {
        case .userCancel, .systemCancel, .appCancel, .userFallback:
            // `localizedFallbackTitle` is never set, so the system prompt shows
            // its default "Enter Password" button. Tapping it is a deliberate
            // choice of another route, not a rejected face.
            return .cancelled
        case .authenticationFailed:
            return .failed
        case .biometryLockout:
            return .lockout
        case .biometryNotAvailable, .biometryNotEnrolled, .invalidContext, .notInteractive,
             .passcodeNotSet:
            // The sensor never ran. `passcodeNotSet` belongs here for the same
            // reason: biometry cannot be evaluated at all without a passcode,
            // so treating it as a rejection would lock the vault over a device
            // configuration the prompt never got to test.
            return .unavailable
        default:
            return .failed
        }
    }

    /// Run an interactive biometric evaluation. This is what surfaces the system
    /// Face ID / Touch ID prompt AND the first-run NSFaceIDUsageDescription
    /// permission — adding a biometric Keychain item alone does neither.
    static func authenticate(reason: String) async throws {
        let context = LAContext()
        var availability: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &availability)
        else { throw availability ?? LAError(.biometryNotAvailable) }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { ok, error in
                if ok { cont.resume() }
                else { cont.resume(throwing: error ?? LAError(.authenticationFailed)) }
            }
        }
    }
}

/// Everything a screen needs to know about biometric unlock, captured once.
///
/// Both halves of the answer are synchronous IPC: `canEvaluatePolicy` talks to
/// the biometry daemon and `isEnrolled` runs a `SecItemCopyMatching` against the
/// keychain daemon. Both are cheap while warm and can take seconds right after a
/// device wake, so a SwiftUI `body` must never call them — it reads a snapshot,
/// and the owner re-probes whenever enrolment could have changed (any return to
/// the foreground: biometrics can be re-enrolled while the app is backgrounded).
nonisolated struct BiometricCapability: Equatable, Sendable {
    /// The device has usable biometry hardware and something enrolled in it.
    var isAvailable: Bool
    /// A biometric-gated Vault Key is provisioned for this app.
    var isEnrolled: Bool
    var displayName: String
    var systemImage: String

    /// The safe pre-probe value: no badge, no auto-prompt, password only.
    static let unavailable = BiometricCapability(
        isAvailable: false,
        isEnrolled: false,
        displayName: BiometricAuth.displayName(for: .none),
        systemImage: BiometricAuth.systemImage(for: .none))

    /// Probe both daemons. Blocking — call it off the main actor.
    static func probe() -> BiometricCapability {
        let type = BiometricAuth.biometryType()
        return BiometricCapability(isAvailable: type != .none,
                                   isEnrolled: BiometricKeyStore.isEnrolled,
                                   displayName: BiometricAuth.displayName(for: type),
                                   systemImage: BiometricAuth.systemImage(for: type))
    }
}

/// An error that already knows how the biometric policy should read it.
///
/// This exists so a store that only ships in the app target — `Level2BiometricKeyStore`
/// — can be classified by `BiometricAuth.classify`, which also compiles into the
/// AutoFill and Safari extensions and therefore cannot name that type.
nonisolated protocol BiometricOutcomeReporting {
    var biometricOutcome: BiometricAuth.Outcome { get }
}

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
    static var displayName: String {
        switch biometryType() {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return appString("Biometrics")
        }
    }

    /// Polaris icon best matching the available biometry.
    static var iconAsset: String {
        switch biometryType() {
        case .faceID, .opticID: return "ic_person"
        case .touchID: return "ic_passkey"
        default: return "ic_lock"
        }
    }

    /// SF Symbol for the available biometry — used for the lock-screen badge, where the
    /// system glyph is the recognised affordance and Polaris ships no biometric equivalent.
    static var systemImage: String {
        switch biometryType() {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .opticID: return "opticid"
        default: return "lock.fill"
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

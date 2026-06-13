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
        default: return String(localized: "Biometrics")
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
}

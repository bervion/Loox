import AuthenticationServices
import Foundation

/// Version-agnostic WebAuthn `largeBlob` intent. Extracted at the iOS 18 entry
/// points so the shared passkey ceremony (which must compile for 17.6) never
/// references iOS 18-only AuthenticationServices extension types directly.
enum PasskeyLargeBlobDirective: Equatable {
    case none
    /// Registration: the relying party asked whether we support largeBlob.
    case registerSupport
    /// Assertion: return the stored blob for this credential.
    case read
    /// Assertion: persist this blob for this credential.
    case write(Data)
}

@available(iOS 18, *)
enum PasskeyLargeBlob {
    /// Extract the directive from a request's unified extension input
    /// (`ASPasskeyCredentialRequest.extensionInput`).
    static func directive(_ input: ASPasskeyCredentialExtensionInput) -> PasskeyLargeBlobDirective {
        switch input {
        case .registration(let registration):
            return registration.largeBlob != nil ? .registerSupport : .none
        case .assertion(let assertion):
            return directive(assertion: assertion)
        case .none:
            return .none
        @unknown default:
            return .none
        }
    }

    /// Extract the directive from an assertion extension input
    /// (`ASPasskeyCredentialRequestParameters.extensionInput`).
    static func directive(assertion input: ASPasskeyAssertionCredentialExtensionInput?) -> PasskeyLargeBlobDirective {
        guard let operation = input?.largeBlob?.operation else { return .none }
        switch operation {
        case .read: return .read
        case .write(let data): return .write(data)
        @unknown default: return .none
        }
    }

    static func registrationOutput(supported: Bool) -> ASPasskeyRegistrationCredentialExtensionOutput {
        ASPasskeyRegistrationCredentialExtensionOutput(largeBlob: supported ? .supported : .unsupported)
    }

    static func assertionReadOutput(_ data: Data?) -> ASPasskeyAssertionCredentialExtensionOutput {
        ASPasskeyAssertionCredentialExtensionOutput(largeBlob: .read(data: data))
    }

    static func assertionWriteOutput(success: Bool) -> ASPasskeyAssertionCredentialExtensionOutput {
        ASPasskeyAssertionCredentialExtensionOutput(largeBlob: .write(success: success))
    }
}

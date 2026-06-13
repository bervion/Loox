import Foundation

/// Identifiers and container locations shared between the app and the AutoFill
/// extension. The App Group holds the encrypted SwiftData store and the wrapped
/// key bundle (both ciphertext) so the extension can decrypt after the user
/// authenticates — no shared-Keychain access group required.
nonisolated enum SharedConfig {
    static let appGroup = "group.com.bervion.vaultify"

    /// App Group container, or the app's Application Support dir as a fallback
    /// (keeps the app fully functional even if the group entitlement is absent).
    static var containerURL: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            ?? URL.applicationSupportDirectory
    }

    /// SwiftData store location (shared).
    static var storeURL: URL { containerURL.appending(path: "Vault.store") }

    /// Wrapped key bundle location (shared, complete file protection).
    static var keyBundleURL: URL { containerURL.appending(path: "vault-keybundle.json") }
}

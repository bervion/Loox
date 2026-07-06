import Foundation

/// Identifiers and container locations shared between the app and the AutoFill
/// extension. The App Group holds the encrypted SwiftData store and the wrapped
/// key bundle (both ciphertext) so the extension can decrypt after the user
/// authenticates — no shared-Keychain access group required.
nonisolated enum SharedConfig {
    static let appGroup = "group.com.bervion.vaultify"

    /// Apple team / app-identifier prefix (see CLAUDE.md). Used to compose the
    /// runtime keychain access-group strings — `kSecAttrAccessGroup` requires the
    /// team-prefixed value, unlike the App Group id which carries no prefix.
    static let teamPrefix = "WDNL2F75V7"

    /// Shared Keychain Access Group: lets the app AND the AutoFill extension read the
    /// same biometric-gated Vault Key item. Must be team-prefixed at runtime; the
    /// entitlement declares it as `$(AppIdentifierPrefix)com.bervion.vaultify.shared`.
    static let keychainAccessGroup = "\(teamPrefix).com.bervion.vaultify.shared"

    /// Legacy per-app keychain group (the app-identifier group) where the biometric
    /// key lived before the shared group existed. Used once during migration to remove
    /// the orphaned copy after the key moves to `keychainAccessGroup`.
    static let legacyKeychainGroup = "\(teamPrefix).com.bervion.vaultify"

    /// App-Group `UserDefaults`, or `.standard` as a fallback. Lets the extension read
    /// non-secret prefs the app mirrors here (e.g. the in-app language for localization).
    static var sharedDefaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }

    /// Key under which the app mirrors its in-app language code ("system"|"en"|"vi")
    /// into the shared defaults, so the extension can localize against the same choice.
    static let languageKey = "preferred_language"
    /// Active persona's isolation policy (raw value), mirrored so the AutoFill
    /// extension can honor isolation. Opaque enum only — no identity-bearing data.
    static let activePersonaPolicyKey = "active_persona_policy"
    /// Active persona's profile item id (opaque UUID), so the extension resolves
    /// that persona's own email under the Vault Key instead of the global default.
    static let activePersonaProfileItemKey = "active_persona_profile_item"

    /// Routing-only breadcrumb (standard defaults): a CKShare was accepted while
    /// the vault might have been locked/onboarding; the unlocked shell resumes
    /// the acceptance (participant escrow + profile publish) then clears it.
    static let pendingShareAcceptanceKey = "pending_share_acceptance"

    static let automaticPasskeyUpgradesKey = "automatic_passkey_upgrades_enabled"
    private static let passkeyQuarantineNoticeKey = "passkey_quarantine_notice_sites"

    /// Default ON: the public-key envelope preserves locked read privacy while
    /// allowing iOS 18's automatic passkey upgrade write path.
    static var automaticPasskeyUpgradesEnabled: Bool {
        get {
            let defaults = sharedDefaults
            guard defaults.object(forKey: automaticPasskeyUpgradesKey) != nil else { return true }
            return defaults.bool(forKey: automaticPasskeyUpgradesKey)
        }
        set { sharedDefaults.set(newValue, forKey: automaticPasskeyUpgradesKey) }
    }

    static var quarantinedPasskeySites: [String] {
        get { sharedDefaults.stringArray(forKey: passkeyQuarantineNoticeKey) ?? [] }
        set { sharedDefaults.set(newValue, forKey: passkeyQuarantineNoticeKey) }
    }

    static func queuePasskeyQuarantineNotice(sites: [String]) {
        let merged = Set(quarantinedPasskeySites + sites.filter { !$0.isEmpty })
        quarantinedPasskeySites = merged.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// App Group container. On iOS, falls back to the app's Application Support dir
    /// (keeps the app functional even if the group entitlement is momentarily absent).
    /// On macOS the container MUST resolve — a silent fallback would partition the vault
    /// from the AutoFill extension and mask a sandbox/entitlement misconfig, so we fail loud.
    static var containerURL: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) {
            return url
        }
        #if os(macOS)
        preconditionFailure(
            "App Group container \(appGroup) unavailable — verify the macOS App Sandbox "
            + "+ application-groups entitlement are provisioned.")
        #else
        return URL.applicationSupportDirectory
        #endif
    }

    /// SwiftData store location (shared).
    static var storeURL: URL { containerURL.appending(path: "Vault.store") }

    /// Wrapped key bundle location (shared, complete file protection).
    static var keyBundleURL: URL { containerURL.appending(path: "vault-keybundle.json") }

    /// Recipient shared-credentials cache location (shared, complete file protection).
    /// AES-GCM-sealed under the Vault Key by `SharedCredentialsCache` — see that file
    /// for why it deliberately survives an app lock (AutoFill needs it while closed).
    static var sharedCredentialsCacheURL: URL {
        containerURL.appending(path: "shared-credentials-cache.bin")
    }
}

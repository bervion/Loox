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
    /// The app's auto-lock window in seconds, mirrored here so the Safari web
    /// extension can size its unlocked session to the same policy (the app's own
    /// copy lives in `UserDefaults.standard`, unreadable from the extension).
    /// 0 = immediate = the extension never keeps a session. Non-sensitive int.
    static let autoLockSecondsKey = "auto_lock_seconds_mirror"
    /// Active persona's isolation policy (raw value), mirrored so the AutoFill
    /// extension can honor isolation. Opaque enum only — no identity-bearing data.
    static let activePersonaPolicyKey = "active_persona_policy"
    /// Active persona's profile item id (opaque UUID), so the extension resolves
    /// that persona's own email under the Vault Key instead of the global default.
    static let activePersonaProfileItemKey = "active_persona_profile_item"

    /// Active persona's own id (opaque UUID) — lets the extension scope its Space
    /// picker to Spaces owned by this persona (INV-R03), mirroring the app's
    /// `activePersonaSpaces` partition filter. Distinct key from the app's local
    /// `SettingsStore` selection (different `UserDefaults` suite) — named
    /// separately here to avoid ambiguity when auditing shared-defaults keys.
    static let activePersonaIdKey = "active_persona_id_mirror"
    /// Whether the mirrored active persona is the converged default persona.
    /// Needed to replicate `VaultRepository.spaces(for:)`: a Space with no
    /// `personaId` link belongs to the DEFAULT persona, not to any other.
    static let activePersonaIsDefaultKey = "active_persona_is_default_mirror"
    /// The active persona's `primarySpaceID` (opaque folder id), mirrored so a new
    /// item saved in the extension can fall back to it when there's no remembered
    /// Home Space selection (or it's stale). Mirrors `VaultRepository.primarySpaceId`.
    static let activePersonaPrimarySpaceKey = "active_persona_primary_space"
    /// The Home Space (folder id) last selected in-app for the active persona —
    /// mirrors `SettingsStore.lastSelectedSpace(persona:)` for that one persona only
    /// (the app's per-persona dictionary lives in `UserDefaults.standard`, which the
    /// extension cannot read). Absence means "All Spaces" was selected.
    static let activePersonaLastSpaceKey = "active_persona_last_selected_space"

    /// Hosts the user opted out of the Safari web extension's save-login
    /// overlay for ("Never for this site"). Hosts only — no secrets. Lives in
    /// the App Group so the choice survives extension reinstalls and stays
    /// readable for a future in-app management screen.
    static let webExtensionNeverSaveHostsKey = "web_extension_never_save_hosts"
    /// Sliding-window timestamps for the Safari extension's password-generation
    /// rate limit (non-secret; generated passwords themselves are never stored).
    static let webExtensionGenerateStampsKey = "web_extension_generate_stamps"

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

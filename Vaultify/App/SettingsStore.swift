import SwiftUI

/// App appearance preference.
nonisolated enum AppearanceMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
    var title: LocalizedStringResource {
        let base: LocalizedStringResource = switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
        return base.inAppLocalized
    }
}

/// Inactivity timeout before the vault auto-locks.
nonisolated enum AutoLockTimeout: Int, CaseIterable, Codable, Sendable, Identifiable {
    case immediate = 0
    case oneMinute = 60
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case oneHour = 3600
    var id: Int { rawValue }
    var seconds: TimeInterval { TimeInterval(rawValue) }
    var title: LocalizedStringResource {
        let base: LocalizedStringResource = switch self {
        case .immediate: "Immediately"
        case .oneMinute: "After 1 minute"
        case .fiveMinutes: "After 5 minutes"
        case .fifteenMinutes: "After 15 minutes"
        case .oneHour: "After 1 hour"
        }
        return base.inAppLocalized
    }
}

/// Non-sensitive preference flags persisted in `UserDefaults`. No secrets here.
@MainActor @Observable final class SettingsStore {

    // Deallocation must not hop to the main actor.
    //
    // This is a `@MainActor @Observable final class`, so without an explicit
    // `nonisolated deinit` the compiler synthesises an ISOLATED deallocating
    // deinit, and the iOS 17.3 deployment floor routes that through the
    // `swift_task_deinitOnExecutorMainActorBackDeploy` shim. On Xcode 27 that
    // shim aborts inside libmalloc ("pointer being freed was not allocated")
    // whenever one isolated deinit releases another — SettingsStore owns other
    // main-actor objects, so it nests by construction.
    //
    // Nothing here needs isolation: releasing stored references is thread-safe,
    // and the body is empty. The shipping app never deallocates these objects,
    // which is why only the test host ever hit it.
    nonisolated deinit {}
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let mirrorToSharedConfig: Bool

    var onboardingCompleted: Bool { didSet { defaults.set(onboardingCompleted, forKey: Key.onboarding) } }
    /// One-time story intro (the post-onboarding cinematic). Set on BOTH finish
    /// and skip so it never shows twice; restore paths set it too (returning
    /// users skip the story), and a full vault reset clears it so re-onboarding
    /// replays it.
    var storyIntroCompleted: Bool { didSet { defaults.set(storyIntroCompleted, forKey: Key.storyIntro) } }
    /// One-shot arrival bridge: the story's seal was COMPLETED (not skipped),
    /// so after the firstRun tutorial ends Home pulses the Add button once,
    /// then clears this.
    var storyIntroWantsFirstItem: Bool { didSet { defaults.set(storyIntroWantsFirstItem, forKey: Key.storyIntroFirstItem) } }
    /// Whether the user has made an explicit appearance choice (onboarding's
    /// ChooseTheme step), or onboarding completed without one (e.g. restoring a
    /// vault, which skips that step) — see `ThemeStore.forceLight`. Gates the
    /// fresh-install forced-light window: until this is true, the app is pinned to
    /// LIGHT regardless of the device scheme, so first-run screens never flash/flip
    /// dark before the user opts in.
    var hasChosenAppearance: Bool { didSet { defaults.set(hasChosenAppearance, forKey: Key.hasChosenAppearance) } }
    /// Single lock timer: `.immediate` locks the moment the app is hidden; any other
    /// window applies to BOTH backgrounding and foreground idle (the old separate
    /// "lock on background" toggle instant-locked regardless of this, which made a
    /// quick copy-into-another-app round trip re-prompt every time).
    var autoLock: AutoLockTimeout {
        didSet {
            defaults.set(autoLock.rawValue, forKey: Key.autoLock)
            mirrorAutoLock()
        }
    }
    /// Lock the vault on a deliberate device shake (privacy panic gesture). Opt-in.
    var shakeToLock: Bool { didSet { defaults.set(shakeToLock, forKey: Key.shakeToLock) } }
    var biometricUnlockEnabled: Bool { didSet { defaults.set(biometricUnlockEnabled, forKey: Key.biometric) } }
    /// Set once the biometric Vault Key has moved from the legacy per-app keychain group into the
    /// shared group (so the AutoFill extension can use Face ID). Guards the one-time migration.
    var biometricKeyMigratedToSharedGroup: Bool { didSet { defaults.set(biometricKeyMigratedToSharedGroup, forKey: Key.biometricKeyMigrated) } }
    var hibpEnabled: Bool { didSet { defaults.set(hibpEnabled, forKey: Key.hibp) } }
    /// Master switch for rotation-reminder local notifications. Default ON so existing
    /// behavior is preserved for users who never touch this new setting. Gated at the
    /// `RotationNotificationService.schedule` call sites via `isRotationRemindersEnabled()`
    /// below rather than inside the service itself (kept untouched, no restructure).
    var rotationRemindersEnabled: Bool { didSet { defaults.set(rotationRemindersEnabled, forKey: Key.rotationReminders) } }
    /// Master switch for the periodic security-checkup reminder notification.
    /// Default ON; the WatchtowerScreen reschedules on each completed audit.
    var auditRemindersEnabled: Bool { didSet { defaults.set(auditRemindersEnabled, forKey: Key.auditReminders) } }
    var iCloudSyncEnabled: Bool {
        didSet {
            defaults.set(iCloudSyncEnabled, forKey: Key.icloud)
            // Every UI path funnels through this setter, so the crash key that
            // splits sync-on from sync-off reports is refreshed here; sampling
            // it once at launch would mislabel any session that flipped it.
            CrashReporter.shared.set(.iCloudSync(enabled: iCloudSyncEnabled))
        }
    }
    /// Approval Mode transport (CKShare grants/requests/responses). Deliberately
    /// SEPARATE from `iCloudSyncEnabled`: enabling approval sharing must never
    /// imply vault-item uploads, and the approval push pipeline must never be
    /// gated by the vault-sync toggle (control plane ≠ secret plane).
    var approvalModeEnabled: Bool { didSet { defaults.set(approvalModeEnabled, forKey: Key.approvalMode) } }
    /// CloudKit artifact plane (encrypted attachment binaries as CKAssets).
    /// Default OFF and not surfaced in Settings yet: the mapping + merge policy
    /// exist (`ArtifactCloudMapping`), but the plane stays out of the live
    /// push/pull until its convergence story — asset upload retries,
    /// partial-download honesty, and the two-phase delete — is proven. Nothing
    /// may read this as "artifacts sync" until `CloudSyncService` actually
    /// wires the plane behind it.
    var artifactSyncEnabled: Bool { didSet { defaults.set(artifactSyncEnabled, forKey: Key.artifactSync) } }
    var showWebsiteIcons: Bool { didSet { defaults.set(showWebsiteIcons, forKey: Key.favicons) } }
    /// Anonymous GA4 usage statistics (see `AnalyticsEngine`'s privacy contract).
    /// Opt-IN: an install that has never answered collects nothing, so the first
    /// launch of a password manager sends no usage telemetry on the strength of
    /// a default nobody chose. The didSet keeps the live engine in lockstep so
    /// flipping the switch applies immediately, no relaunch.
    var analyticsEnabled: Bool {
        didSet {
            defaults.set(analyticsEnabled, forKey: Key.analytics)
            AnalyticsEngine.shared.setEnabled(analyticsEnabled)
        }
    }
    /// Crash diagnostics (see `CrashReporter`'s privacy and scope contract).
    /// Opt-out, and deliberately SEPARATE from `analyticsEnabled`: declining
    /// usage statistics should not silence the report that explains why the app
    /// died. The didSet drives the SDK's own collection switch, so turning this
    /// off stops Crashlytics recording rather than only stopping our calls.
    var crashReportingEnabled: Bool {
        didSet {
            defaults.set(crashReportingEnabled, forKey: Key.crashReporting)
            CrashReporter.shared.setEnabled(crashReportingEnabled)
        }
    }
    var clipboardClearSeconds: Int { didSet { defaults.set(clipboardClearSeconds, forKey: Key.clipboard) } }
    var hideInAppSwitcher: Bool { didSet { defaults.set(hideInAppSwitcher, forKey: Key.privacyScreen) } }
    /// Which payment card the Profile screen shows as "your" card. Device-local (not synced) —
    /// a display preference, unlike the synced default identity. nil = fall back to the first card.
    var selectedPaymentCardId: String? { didSet { defaults.set(selectedPaymentCardId, forKey: Key.selectedCard) } }
    /// Last Home Space filter, remembered per identity so it survives relaunch.
    /// Device-local display preference — deliberately NOT synced (a selected-Space
    /// choice reveals nothing sensitive and needn't cross devices). Keyed by
    /// identity id; today everything uses `PersonaID.placeholder`. Value is a
    /// folderId, or "" for an explicit "All Spaces" choice; absence of a key
    /// means the user never chose (Home's single-Space auto-select may fill it).
    private(set) var lastSelectedSpaceByPersona: [String: String] {
        didSet { defaults.set(lastSelectedSpaceByPersona, forKey: Key.lastSelectedSpaces) }
    }

    /// Which persona the UI currently acts as. Device-local selection (not synced,
    /// unlike the persona's converged `isDefault` flag): the active view is a
    /// per-device UI concern, and a persona id reveals nothing without the sealed
    /// name. nil / stale falls back to the default persona.
    var activePersonaID: String? { didSet { defaults.set(activePersonaID, forKey: Key.activePersona) } }

    /// Home section display order (identifiers from `HomeSection.rawValue`). Device-local
    /// layout preference — not synced. Empty = first-run default (canonical order); unknown
    /// or removed ids are ignored and newly shipped sections append at the end.
    var homeSectionOrder: [String] { didSet { defaults.set(homeSectionOrder, forKey: Key.homeSectionOrder) } }
    /// Home sections the user has hidden (identifiers from `HomeSection.rawValue`).
    /// Device-local; a hidden section is simply skipped when composing the Home feed.
    var homeHiddenSections: [String] { didSet { defaults.set(homeHiddenSections, forKey: Key.homeHiddenSections) } }

    /// Live item warnings silenced from the item detail banner's Ignore button
    /// (`ItemAttentionBanner`), as `"<itemID>|<kind>|<password baseline>"` keys.
    ///
    /// Device-local on purpose: this records a preference about being told, not vault
    /// data. Findings that came from an audit are NOT stored here — those get the real
    /// `FindingStatus.ignored` in the audit store, so Watchtower honors them too.
    ///
    /// The baseline is the password timestamp the warning was about, so a later
    /// password brings the warning back: silencing one weak password must never
    /// silence the next one.
    var dismissedItemWarnings: [String] {
        didSet { defaults.set(dismissedItemWarnings, forKey: Key.dismissedItemWarnings) }
    }

    func isItemWarningDismissed(_ key: String) -> Bool {
        dismissedItemWarnings.contains(key)
    }

    func dismissItemWarning(_ key: String) {
        guard !dismissedItemWarnings.contains(key) else { return }
        dismissedItemWarnings.append(key)
    }

    /// The remembered Home Space for an identity: a folderId, "" for an explicit
    /// "All Spaces" choice, or nil when the user never chose one.
    func lastSelectedSpace(persona: String) -> String? {
        lastSelectedSpaceByPersona[persona]
    }

    /// Remember the Home Space for an identity. nil records the EXPLICIT
    /// "All Spaces" choice (stored as "") — it must survive tab switches and
    /// relaunches rather than being erased and re-auto-selected away.
    func setLastSelectedSpace(_ folderId: String?, persona: String) {
        lastSelectedSpaceByPersona[persona] = folderId ?? ""
    }

    /// Forget an identity's remembered Space entirely (back to "never chose") —
    /// for cleanup when a persona is removed, and for tests.
    func clearLastSelectedSpace(persona: String) {
        lastSelectedSpaceByPersona.removeValue(forKey: persona)
    }
    var preferredLanguage: String {
        didSet {
            defaults.set(preferredLanguage, forKey: Key.language)
            // Mirror into the App Group so the AutoFill extension localizes against the same choice.
            if mirrorToSharedConfig {
                SharedConfig.sharedDefaults.set(preferredLanguage, forKey: SharedConfig.languageKey)
            }
            appResourceLocale = appLocale(forCode: preferredLanguage)
            // Every UI path (iOS selection screen, Mac segmented picker) funnels
            // through this setter, so the language signal lives here, not per-view.
            AnalyticsEngine.shared.log(.languageChanged(preferredLanguage))
            AnalyticsEngine.shared.setUserProperty(.appLanguage, preferredLanguage)
            CrashReporter.shared.set(.appLanguage(preferredLanguage))
        }
    }

    init(defaults: UserDefaults = .standard, mirrorToSharedConfig: Bool = true) {
        self.defaults = defaults
        self.mirrorToSharedConfig = mirrorToSharedConfig
        let d = defaults
        // Captured locally (not read back via `self.onboardingCompleted`): `@Observable`
        // accessors touch `self` as a whole, which Swift disallows before every stored
        // property has its first value.
        let onboarded = d.bool(forKey: Key.onboarding)
        onboardingCompleted = onboarded
        // Back-compat like `hasChosenAppearance` below: the story key didn't
        // exist before the story intro shipped, so an already-onboarded install
        // must not get a surprise cinematic on its next unlock — fall back to
        // `onboarded`. A genuinely fresh install correctly defaults to false.
        storyIntroCompleted = d.object(forKey: Key.storyIntro) as? Bool ?? onboarded
        storyIntroWantsFirstItem = d.bool(forKey: Key.storyIntroFirstItem)
        // PERSIST the resolved default immediately. Without this the fallback
        // re-evaluates every launch against `onboarded`, which onboarding has
        // just set to true — so a story the user was interrupted in (app
        // terminated mid-scroll) would read as "already seen" forever. Writing
        // it while `onboarded` is still false pins a fresh install to false.
        if d.object(forKey: Key.storyIntro) == nil {
            d.set(onboarded, forKey: Key.storyIntro)
        }
        // Back-compat: this key didn't exist before `hasChosenAppearance` shipped, so
        // an already-onboarded install has no persisted value — fall back to
        // `onboarded` so an existing user is never force-lit. A genuinely fresh
        // install has `onboarded == false` too, so this correctly defaults to false
        // there (forced-light applies).
        hasChosenAppearance = d.object(forKey: Key.hasChosenAppearance) as? Bool ?? onboarded
        autoLock = AutoLockTimeout(rawValue: d.object(forKey: Key.autoLock) as? Int ?? 300) ?? .fiveMinutes
        shakeToLock = d.object(forKey: Key.shakeToLock) as? Bool ?? false
        biometricUnlockEnabled = d.bool(forKey: Key.biometric)
        biometricKeyMigratedToSharedGroup = d.bool(forKey: Key.biometricKeyMigrated)
        hibpEnabled = d.object(forKey: Key.hibp) as? Bool ?? true
        rotationRemindersEnabled = d.object(forKey: Key.rotationReminders) as? Bool ?? true
        auditRemindersEnabled = d.object(forKey: Key.auditReminders) as? Bool ?? true
        iCloudSyncEnabled = d.bool(forKey: Key.icloud)
        approvalModeEnabled = d.bool(forKey: Key.approvalMode)
        artifactSyncEnabled = d.bool(forKey: Key.artifactSync)
        showWebsiteIcons = d.object(forKey: Key.favicons) as? Bool ?? true
        analyticsEnabled = d.object(forKey: Key.analytics) as? Bool ?? false
        crashReportingEnabled = d.object(forKey: Key.crashReporting) as? Bool ?? true
        clipboardClearSeconds = d.object(forKey: Key.clipboard) as? Int ?? 30
        hideInAppSwitcher = d.object(forKey: Key.privacyScreen) as? Bool ?? true
        selectedPaymentCardId = d.string(forKey: Key.selectedCard)
        lastSelectedSpaceByPersona = d.dictionary(forKey: Key.lastSelectedSpaces) as? [String: String] ?? [:]
        activePersonaID = d.string(forKey: Key.activePersona)
        homeSectionOrder = d.stringArray(forKey: Key.homeSectionOrder) ?? []
        homeHiddenSections = d.stringArray(forKey: Key.homeHiddenSections) ?? []
        dismissedItemWarnings = d.stringArray(forKey: Key.dismissedItemWarnings) ?? []
        preferredLanguage = d.string(forKey: Key.language) ?? "system"
        if mirrorToSharedConfig {
            SharedConfig.sharedDefaults.set(preferredLanguage, forKey: SharedConfig.languageKey)
        }
        // Deterministic under XCTest: the host app's persisted language choice must
        // not leak into string assertions (appString now genuinely follows
        // `appResourceLocale`, so a VI host would fail every EN expectation).
        appResourceLocale = CloudSyncService.isHostingUnitTests
            ? Locale(identifier: "en")
            : appLocale(forCode: preferredLanguage)
        mirrorAutoLock()
    }

    /// Mirror the auto-lock window into the App Group so the Safari web extension
    /// can size its unlocked session to the same policy (`UserDefaults.standard`
    /// stays the app's source of truth). Tightening to "immediate" also revokes
    /// any live extension session — the stricter policy applies at once.
    private func mirrorAutoLock() {
        guard mirrorToSharedConfig else { return }
        SharedConfig.sharedDefaults.set(autoLock.rawValue, forKey: SharedConfig.autoLockSecondsKey)
        if autoLock == .immediate {
            ExtensionSessionStore.clear()
        }
    }

    /// Cheap, dependency-free read of the rotation-reminders preference for call sites
    /// that don't otherwise hold a `SettingsStore` instance (e.g. `VaultRepository`,
    /// which schedules rotation notifications on item save/update).
    nonisolated static func isRotationRemindersEnabled() -> Bool {
        UserDefaults.standard.object(forKey: Key.rotationReminders) as? Bool ?? true
    }

    /// Consent read for `AnalyticsEngine` bootstrap, which runs before any
    /// `SettingsStore` instance exists. The fallback MUST match
    /// `analyticsEnabled`'s: nothing sets the property on a launch where the
    /// user never touched the switch, so a `true` here would bootstrap the
    /// engine (and GA4 collection) enabled while the settings screen showed the
    /// toggle off.
    nonisolated static func isAnalyticsEnabled() -> Bool {
        UserDefaults.standard.object(forKey: Key.analytics) as? Bool ?? false
    }

    /// Consent read for `CrashReporter` bootstrap, which runs before any
    /// `SettingsStore` instance exists.
    nonisolated static func isCrashReportingEnabled() -> Bool {
        UserDefaults.standard.object(forKey: Key.crashReporting) as? Bool ?? true
    }

    private nonisolated enum Key {
        static let onboarding = "onboarding_completed"
        static let storyIntro = "story_intro_completed"
        static let storyIntroFirstItem = "story_intro_wants_first_item"
        static let hasChosenAppearance = "has_chosen_appearance"
        static let autoLock = "auto_lock_timeout"
        static let shakeToLock = "shake_to_lock"
        static let biometric = "biometric_unlock_enabled"
        static let biometricKeyMigrated = "biometric_key_migrated_shared_group"
        static let hibp = "hibp_enabled"
        static let rotationReminders = "rotation_reminders_enabled"
        static let auditReminders = "audit_reminders_enabled"
        static let icloud = "icloud_sync_enabled"
        static let approvalMode = "approval_mode_enabled"
        static let artifactSync = "artifact_sync_enabled"
        static let favicons = "show_website_icons"
        static let analytics = "analytics_enabled"
        static let crashReporting = "crash_reporting_enabled"
        static let clipboard = "clipboard_clear_seconds"
        static let privacyScreen = "hide_in_app_switcher"
        static let selectedCard = "profile_selected_payment_card_id"
        static let lastSelectedSpaces = "last_selected_space_by_persona"
        static let activePersona = "active_persona_id"
        static let homeSectionOrder = "home_section_order"
        static let homeHiddenSections = "home_hidden_sections"
        static let dismissedItemWarnings = "dismissed_item_warnings"
        static let language = "preferred_language"
    }
}

import Foundation

/// Native-side policy for the Safari web extension's signup-assist flow:
/// the OS-version gate that defers saving to the system's own save sheet,
/// the per-host "never save" opt-out list, and light rate limits on
/// password generation and vault saves.
///
/// SECURITY: everything here is non-secret metadata (an OS version check,
/// bare hostnames, timestamps). Nothing in this file touches the Vault Key
/// or vault contents.
nonisolated enum WebExtensionSaveGate {

    // MARK: - Native save-sheet gate

    /// iOS version from which the OS shows its own native "Save password"
    /// sheet for our credential provider (`SupportsSavePasswordCredentials`).
    /// From here the web extension suppresses its in-page save overlay so the
    /// user never faces two save prompts for one signup.
    static let nativeSaveFloor = OperatingSystemVersion(majorVersion: 26,
                                                        minorVersion: 2,
                                                        patchVersion: 0)

    /// True when the system save-password path owns the save UX on this device.
    static func nativeSavePathActive(processInfo: ProcessInfo = .processInfo) -> Bool {
        processInfo.isOperatingSystemAtLeast(nativeSaveFloor)
    }

    // MARK: - Never-save hosts

    static func isNeverSaved(host: String, defaults: UserDefaults) -> Bool {
        neverSaveHosts(defaults: defaults).contains(normalizeHost(host))
    }

    static func addNeverSave(host: String, defaults: UserDefaults) {
        let normalized = normalizeHost(host)
        guard !normalized.isEmpty else { return }
        var hosts = neverSaveHosts(defaults: defaults)
        guard !hosts.contains(normalized) else { return }
        hosts.append(normalized)
        defaults.set(hosts.sorted(), forKey: SharedConfig.webExtensionNeverSaveHostsKey)
    }

    static func neverSaveHosts(defaults: UserDefaults) -> [String] {
        defaults.stringArray(forKey: SharedConfig.webExtensionNeverSaveHostsKey) ?? []
    }

    private static func normalizeHost(_ host: String) -> String {
        host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // MARK: - generatePassword rate limit

    /// At most `generateLimit` generated passwords per `generateWindow`.
    /// Defense in depth: the command is popup-gated in the background page,
    /// but a compromised renderer scripting the messaging surface should not
    /// be able to spin the generator freely. The handler process is
    /// short-lived, so the window persists as timestamps in shared defaults —
    /// timestamps only, never a generated value.
    ///
    /// The read-modify-write is not atomic across concurrent handler
    /// processes; a race can admit one extra request past the cap. Acceptable
    /// for a defense-in-depth limiter (same applies to `allowSave`).
    static let generateLimit = 5
    static let generateWindow: TimeInterval = 60

    static func allowGenerate(now: Date = .now, defaults: UserDefaults) -> Bool {
        let key = SharedConfig.webExtensionGenerateStampsKey
        let cutoff = now.timeIntervalSince1970 - generateWindow
        let stored = defaults.array(forKey: key) as? [Double] ?? []
        var stamps = stored.filter { $0 > cutoff }
        guard stamps.count < generateLimit else {
            defaults.set(stamps, forKey: key)
            return false
        }
        stamps.append(now.timeIntervalSince1970)
        defaults.set(stamps, forKey: key)
        return true
    }

    // MARK: - saveLogin rate limit

    /// At most `saveLimit` vault saves per `saveWindow`, tracked PER HOST.
    /// A save reaches native only on the user's Save tap in the overlay, but
    /// a compromised renderer scripting the extension messaging surface must
    /// not be able to spam vault writes (junk logins, CloudKit sync churn)
    /// or use the duplicate error as a high-rate username-existence probe
    /// for its own origin. Checked BEFORE any unlock, so spamming saveLogin
    /// also cannot prompt-bomb Face ID. Hosts + timestamps only, never
    /// credential data.
    static let saveLimit = 5
    static let saveWindow: TimeInterval = 60

    static func allowSave(host: String, now: Date = .now, defaults: UserDefaults) -> Bool {
        let key = SharedConfig.webExtensionSaveStampsKey
        let cutoff = now.timeIntervalSince1970 - saveWindow
        let stored = defaults.dictionary(forKey: key) as? [String: [Double]] ?? [:]
        // Prune expired stamps for every host so the map stays bounded by
        // activity inside the current window.
        var live: [String: [Double]] = [:]
        for (storedHost, stamps) in stored {
            let fresh = stamps.filter { $0 > cutoff }
            if !fresh.isEmpty { live[storedHost] = fresh }
        }
        let hostKey = normalizeHost(host)
        var stamps = live[hostKey] ?? []
        guard stamps.count < saveLimit else {
            defaults.set(live, forKey: key)
            return false
        }
        stamps.append(now.timeIntervalSince1970)
        live[hostKey] = stamps
        defaults.set(live, forKey: key)
        return true
    }
}
